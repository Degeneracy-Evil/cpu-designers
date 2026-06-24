`timescale 1ns / 1ps

module ptw(
    input              clk,
    input              resetn,

    input       [31:0] satp,
    input       [1:0]  priv_mode,
    input              mstatus_sum,
    input              mstatus_mxr,
    input       [1:0]  access_type,

    input       [31:0] walk_vaddr,
    input              walk_req,
    input              walk_abort,       // BUG-7: sfence_vma abort in-progress walk
    output             walk_done,
    output             walk_fault,
    output      [3:0]  walk_fault_cause,
    output      [31:0] walk_fault_vaddr,
    output      [1:0]  walk_fault_kind,

    output      [21:0] walk_ppn,
    output             walk_r,
    output             walk_w,
    output             walk_x,
    output             walk_u,
    output             walk_a,
    output             walk_d,
    output             walk_g,
    output             walk_is_megapage,

    // Dcache read interface (PTE fetch)
    output             ptw_cache_req,    // read request (held high until response)
    output      [31:0] ptw_cache_addr,   // physical address of PTE to read
    input              ptw_cache_ready,  // response valid (1-cycle pulse)
    input       [31:0] ptw_cache_rdata,  // PTE data from dcache
    input              ptw_cache_fault,  // access fault from PMP/PMA during cache access

    // PMP check interface
    input              pmp_grant,        // PMP allows access to ptw_cache_addr
    input       [1:0]  pmp_fault_type    // 0=fetch, 1=load, 2=store (from PMP)
);

    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;

    localparam ACCESS_FETCH = 2'b00;
    localparam ACCESS_LOAD  = 2'b01;
    localparam ACCESS_STORE = 2'b10;

    localparam FAULT_NONE   = 2'd0;
    localparam FAULT_PAGE   = 2'd1;
    localparam FAULT_ACCESS = 2'd2;

    localparam S_IDLE       = 4'd0;
    localparam S_L1_READ    = 4'd1;
    localparam S_L1_CHECK   = 4'd2;
    localparam S_L0_READ    = 4'd3;
    localparam S_L0_CHECK   = 4'd4;
    localparam S_PERM_CHECK = 4'd5;
    localparam S_DONE       = 4'd6;
    localparam S_FAULT      = 4'd7;

    reg [3:0] state;

    reg [31:0] vaddr_r;
    reg [31:0] pte_r;
    reg        is_megapage_r;

    wire [9:0] vpn1 = vaddr_r[31:22];
    wire [9:0] vpn0 = vaddr_r[21:12];

    wire [21:0] satp_ppn = satp[21:0];

    wire pte_v = pte_r[0];
    wire pte_r_bit = pte_r[1];
    wire pte_w = pte_r[2];
    wire pte_x = pte_r[3];
    wire pte_u = pte_r[4];
    wire pte_g = pte_r[5];
    wire pte_a = pte_r[6];
    wire pte_d = pte_r[7];
    wire [21:0] pte_ppn = {pte_r[31:20], pte_r[19:10]};

    wire pte_is_leaf = pte_r_bit || pte_x;
    wire pte_reserved = !pte_r_bit && pte_w;

    // Cache response PTE field decodes
    wire cache_pte_v     = ptw_cache_rdata[0];
    wire cache_pte_r_bit = ptw_cache_rdata[1];
    wire cache_pte_w     = ptw_cache_rdata[2];
    wire cache_pte_x     = ptw_cache_rdata[3];
    wire cache_pte_is_leaf   = cache_pte_r_bit || cache_pte_x;
    wire cache_pte_reserved = !cache_pte_r_bit && cache_pte_w;

    // NOTE: HIGH-2 fix REMOVED — see S_L1_CHECK non-leaf path for rationale.

    reg [3:0] fault_cause_r;
    reg [1:0] fault_kind_r;

    always_comb begin
        case (fault_kind_r)
            FAULT_ACCESS: begin
                case (access_type)
                    ACCESS_FETCH: fault_cause_r = 4'd1;
                    ACCESS_LOAD:  fault_cause_r = 4'd5;
                    default:      fault_cause_r = 4'd7;
                endcase
            end
            default: begin
                case (access_type)
                    ACCESS_FETCH: fault_cause_r = 4'd12;
                    ACCESS_LOAD:  fault_cause_r = 4'd13;
                    default:      fault_cause_r = 4'd15;
                endcase
            end
        endcase
    end

    assign walk_fault_cause = fault_cause_r;
    assign walk_fault_vaddr = vaddr_r;
    assign walk_fault_kind  = fault_kind_r;

    assign walk_ppn         = pte_ppn;
    assign walk_r           = pte_r_bit;
    assign walk_w           = pte_w;
    assign walk_x           = pte_x;
    assign walk_u           = pte_u;
    assign walk_a           = pte_a;
    assign walk_d           = pte_d;
    assign walk_g           = pte_g;
    assign walk_is_megapage = is_megapage_r;

    assign walk_done   = (state == S_DONE);
    assign walk_fault  = (state == S_FAULT);

    reg [31:0] cache_addr_r;
    reg        cache_req_pending_r;  // stays high until cache responds (ptw_cache_ready)

    // BUG-15: cache response timeout counter — prevents permanent hang if cache never responds
    localparam PTW_TIMEOUT = 16'd256;   // 256 cycles per cache beat
    reg [15:0] timeout_cnt;

    assign ptw_cache_req  = cache_req_pending_r;
    assign ptw_cache_addr = cache_addr_r;

    // Explicit 32-bit arithmetic: use only PPN[19:0] for address (top 2 bits
    // would exceed 32-bit physical address space). Each term is exactly 32 bits wide.
    wire [31:0] l1_pte_addr = {satp_ppn[19:0], 12'b0} + {20'b0, vpn1, 2'b0};
    wire [31:0] l0_pte_addr = {pte_ppn[19:0], 12'b0} + {20'b0, vpn0, 2'b0};

    wire perm_fault;
    reg perm_fault_r;

    always_comb begin
        perm_fault_r = 1'b0;
        if (priv_mode == PRIV_U && !pte_u)
            perm_fault_r = 1'b1;
        if (priv_mode == PRIV_S && pte_u) begin
            if (access_type == ACCESS_FETCH)
                perm_fault_r = 1'b1;
            else if (!mstatus_sum)
                perm_fault_r = 1'b1;
        end
        if (access_type == ACCESS_FETCH && !pte_x)
            perm_fault_r = 1'b1;
        if (access_type == ACCESS_LOAD) begin
            if (!pte_r_bit && !(pte_x && mstatus_mxr))
                perm_fault_r = 1'b1;
        end
        if (access_type == ACCESS_STORE && !pte_w)
            perm_fault_r = 1'b1;
        if (is_megapage_r && pte_ppn[9:0] != 10'b0)
            perm_fault_r = 1'b1;
    end

    assign perm_fault = perm_fault_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state            <= S_IDLE;
            vaddr_r          <= 32'b0;
            pte_r            <= 32'b0;
            is_megapage_r    <= 1'b0;
            cache_addr_r     <= 32'b0;
            cache_req_pending_r <= 1'b0;
            timeout_cnt      <= 16'd0;
            fault_kind_r     <= FAULT_NONE;
        end else begin
            // BUG-15: timeout counter — increments while waiting for cache response
            // in S_L1_CHECK/S_L0_CHECK (after request issued). On expiry, force S_FAULT.
            if ((state == S_L1_CHECK || state == S_L0_CHECK) && cache_req_pending_r) begin
                if (ptw_cache_ready) begin
                    timeout_cnt <= 16'd0;   // normal response — reset
                end else begin
                    timeout_cnt <= timeout_cnt + 16'd1;
                end
            end else begin
                timeout_cnt <= 16'd0;
            end

            // BUG-7: walk_abort (sfence_vma) forces PTW back to S_IDLE
            if (walk_abort && state != S_IDLE) begin
                state             <= S_IDLE;
                cache_req_pending_r <= 1'b0;
            end else
            case (state)
                S_IDLE: begin
                    fault_kind_r <= FAULT_NONE;
                    if (walk_req) begin
                        vaddr_r       <= walk_vaddr;
                        is_megapage_r <= 1'b0;
                        state         <= S_L1_READ;
                    end
                end

                S_L1_READ: begin
                    cache_addr_r     <= l1_pte_addr;
                    state            <= S_L1_CHECK;
                end

                S_L1_CHECK: begin
                    if (!cache_req_pending_r) begin
                        // PMP check phase: address is stable in cache_addr_r
                        if (!pmp_grant) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            cache_req_pending_r <= 1'b1;  // issue cache request
                        end
                    end else begin
                        // Response wait phase
                        if (ptw_cache_ready) begin
                            cache_req_pending_r <= 1'b0;
                            if (ptw_cache_fault) begin
                                fault_kind_r <= FAULT_ACCESS;
                                state <= S_FAULT;
                            end else begin
                                pte_r <= ptw_cache_rdata;
                                if (!cache_pte_v || cache_pte_reserved) begin
                                    fault_kind_r <= FAULT_PAGE;
                                    state <= S_FAULT;
                                end else if (cache_pte_is_leaf) begin
                                    is_megapage_r <= 1'b1;
                                    state <= S_PERM_CHECK;
                                end else begin
                                    // HIGH-2 fix REMOVED: the original fix skipped
                                    // S_L0_READ by computing next_l0_addr from cache
                                    // response data and going directly to S_L0_CHECK.
                                    // This was needed for the old bus bridge interface
                                    // where bus_req_pending_r dropping caused a
                                    // re-arbitration gap. With the dcache arbiter:
                                    //   - cache_req_pending_r stays high until response
                                    //   - dcache holds the PTW request until completion
                                    //   - no re-arbitration gap exists
                                    // The normal S_L0_READ → S_L0_CHECK path is
                                    // cleaner and uses the already-registered pte_r.
                                    state <= S_L0_READ;
                                end
                            end
                        end else if (timeout_cnt >= PTW_TIMEOUT) begin  // BUG-15: timeout
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                            cache_req_pending_r <= 1'b0;
                        end
                    end
                end

                S_L0_READ: begin
                    cache_addr_r     <= l0_pte_addr;
                    state            <= S_L0_CHECK;
                end

                S_L0_CHECK: begin
                    if (!cache_req_pending_r) begin
                        // PMP check phase: address is stable in cache_addr_r
                        if (!pmp_grant) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            cache_req_pending_r <= 1'b1;  // issue cache request
                        end
                    end else begin
                        // Response wait phase
                        if (ptw_cache_ready) begin
                            cache_req_pending_r <= 1'b0;
                            if (ptw_cache_fault) begin
                                fault_kind_r <= FAULT_ACCESS;
                                state <= S_FAULT;
                            end else begin
                                pte_r <= ptw_cache_rdata;
                                if (!cache_pte_v || cache_pte_reserved) begin
                                    fault_kind_r <= FAULT_PAGE;
                                    state <= S_FAULT;
                                end else if (cache_pte_is_leaf) begin
                                    is_megapage_r <= 1'b0;
                                    state <= S_PERM_CHECK;
                                end else begin
                                    fault_kind_r <= FAULT_PAGE;
                                    state <= S_FAULT;
                                end
                            end
                        end else if (timeout_cnt >= PTW_TIMEOUT) begin  // BUG-15: timeout
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                            cache_req_pending_r <= 1'b0;
                        end
                    end
                end

                S_PERM_CHECK: begin
                    if (perm_fault) begin
                        fault_kind_r <= FAULT_PAGE;
                        state <= S_FAULT;
                    end else if (!pte_a || (access_type == ACCESS_STORE && !pte_d)) begin
                        // A=0 or (store && D=0): trap to software as page fault
                        fault_kind_r <= FAULT_PAGE;
                        state <= S_FAULT;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                S_FAULT: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
