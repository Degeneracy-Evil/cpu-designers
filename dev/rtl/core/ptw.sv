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

    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error,
    input              ptw_bus_hold
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
    localparam S_AD_UPDATE  = 4'd6;
    localparam S_AD_WAIT    = 4'd7;
    localparam S_DONE       = 4'd8;
    localparam S_FAULT      = 4'd9;

    reg [3:0] state;

    reg [31:0] vaddr_r;
    reg [31:0] pte_r;
    reg [31:0] pte_addr_r;
    reg        is_megapage_r;
    reg        need_ad_update_r;
    reg        need_d_update_r;

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

    wire bus_pte_v     = ptw_bus_rdata[0];
    wire bus_pte_r_bit = ptw_bus_rdata[1];
    wire bus_pte_w     = ptw_bus_rdata[2];
    wire bus_pte_x     = ptw_bus_rdata[3];
    wire bus_pte_is_leaf   = bus_pte_r_bit || bus_pte_x;
    wire bus_pte_reserved = !bus_pte_r_bit && bus_pte_w;

    // HIGH-2 fix: L0 PTE address computed from bus data (pte_r not yet updated
    // when S_L1_CHECK transitions). Used to pre-issue L0 read without a gap.
    wire [21:0] bus_pte_ppn = {ptw_bus_rdata[31:20], ptw_bus_rdata[19:10]};
    wire [31:0] next_l0_addr = {bus_pte_ppn[19:0], 12'b0} + {20'b0, vpn0, 2'b0};

    reg [3:0] fault_cause_r;
    reg [1:0] fault_kind_r;

    wire bus_resp_any = ptw_bus_done || ptw_bus_error;
    wire bus_resp_err = ptw_bus_error;
    wire bus_resp_ok  = ptw_bus_done && !ptw_bus_error;

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

    reg bus_req_r;
    reg [31:0] bus_addr_r;
    reg bus_we_r;
    reg [31:0] bus_wdata_r;
    reg bus_req_pending_r;  // stays high until bus bridge accepts (ptw_bus_done/error)

    // BUG-15: bus response timeout counter — prevents permanent hang if bus never responds
    localparam PTW_TIMEOUT = 16'd256;   // 256 cycles per bus beat
    reg [15:0] timeout_cnt;

    assign ptw_bus_req   = bus_req_pending_r;
    assign ptw_bus_addr  = bus_addr_r;
    assign ptw_bus_we    = bus_we_r;
    assign ptw_bus_wdata = bus_wdata_r;

    // Explicit 32-bit arithmetic: use only PPN[19:0] for address (top 2 bits
    // would exceed 32-bit bus width). Each term is exactly 32 bits wide.
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
            pte_addr_r       <= 32'b0;
            is_megapage_r    <= 1'b0;
            need_ad_update_r <= 1'b0;
            need_d_update_r  <= 1'b0;
            bus_req_r        <= 1'b0;
            bus_addr_r       <= 32'b0;
            bus_we_r         <= 1'b0;
            bus_wdata_r      <= 32'b0;
            bus_req_pending_r <= 1'b0;
            timeout_cnt      <= 16'd0;
            fault_kind_r     <= FAULT_NONE;
        end else begin
            bus_req_r <= 1'b0;
            // Clear pending on bus response
            if (bus_resp_any)
                bus_req_pending_r <= 1'b0;

            // BUG-15: timeout counter — increments while waiting for bus response
            // in S_L1_CHECK/S_L0_CHECK/S_AD_WAIT. On expiry, force S_FAULT.
            if (state == S_L1_CHECK || state == S_L0_CHECK || state == S_AD_WAIT) begin
                if (bus_resp_any) begin
                    timeout_cnt <= 16'd0;   // normal response — reset
                end else if (!ptw_bus_hold) begin
                    timeout_cnt <= timeout_cnt + 16'd1;
                end
            end else begin
                timeout_cnt <= 16'd0;
            end

            // BUG-7: walk_abort (sfence_vma) forces PTW back to S_IDLE
            if (walk_abort && state != S_IDLE) begin
                state             <= S_IDLE;
                bus_req_pending_r <= 1'b0;
            end else
            case (state)
                S_IDLE: begin
                    fault_kind_r <= FAULT_NONE;
                    if (walk_req) begin
                        vaddr_r       <= walk_vaddr;
                        is_megapage_r <= 1'b0;
                        need_ad_update_r <= 1'b0;
                        need_d_update_r  <= 1'b0;
                        state         <= S_L1_READ;
                    end
                end

                S_L1_READ: begin
                    bus_addr_r <= l1_pte_addr;
                    bus_we_r   <= 1'b0;
                    bus_wdata_r<= 32'b0;
                    bus_req_r  <= 1'b1;
                    bus_req_pending_r <= 1'b1;
                    pte_addr_r <= l1_pte_addr;
                    state      <= S_L1_CHECK;
                end

                S_L1_CHECK: begin
                    if (bus_resp_err) begin
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                    end else if (bus_resp_ok) begin
                        if (ptw_bus_error) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            pte_r <= ptw_bus_rdata;
                            if (!bus_pte_v || bus_pte_reserved) begin
                                fault_kind_r <= FAULT_PAGE;
                                state <= S_FAULT;
                            end else if (bus_pte_is_leaf) begin
                                is_megapage_r <= 1'b1;
                                state <= S_PERM_CHECK;
                            end else begin
                                // HIGH-2 fix: pre-issue L0 read in the same
                                // cycle that L1 completes.  Without this,
                                // bus_req_pending_r drops for 1 cycle between
                                // S_L1_CHECK and S_L0_READ.  The bus bridge
                                // (PTW at lowest priority) may re-arbitrate
                                // and hand the bus to another master, delaying
                                // the L0 read or causing a spurious timeout.
                                // Skip S_L0_READ entirely → go to S_L0_CHECK.
                                bus_addr_r        <= next_l0_addr;
                                bus_we_r          <= 1'b0;
                                bus_wdata_r       <= 32'b0;
                                bus_req_r         <= 1'b1;
                                bus_req_pending_r <= 1'b1;  // override clear
                                pte_addr_r        <= next_l0_addr;
                                state             <= S_L0_CHECK;
                            end
                        end
                    end else if (!ptw_bus_hold && timeout_cnt >= PTW_TIMEOUT) begin  // BUG-15: timeout
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                        bus_req_pending_r <= 1'b0;
                    end
                end

                S_L0_READ: begin
                    bus_addr_r <= l0_pte_addr;
                    bus_we_r   <= 1'b0;
                    bus_wdata_r<= 32'b0;
                    bus_req_r  <= 1'b1;
                    bus_req_pending_r <= 1'b1;
                    pte_addr_r <= l0_pte_addr;
                    state      <= S_L0_CHECK;
                end

                S_L0_CHECK: begin
                    if (bus_resp_err) begin
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                    end else if (bus_resp_ok) begin
                        if (ptw_bus_error) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            pte_r <= ptw_bus_rdata;
                            if (!bus_pte_v || bus_pte_reserved) begin
                                fault_kind_r <= FAULT_PAGE;
                                state <= S_FAULT;
                            end else if (bus_pte_is_leaf) begin
                                is_megapage_r <= 1'b0;
                                state <= S_PERM_CHECK;
                            end else begin
                                fault_kind_r <= FAULT_PAGE;
                                state <= S_FAULT;
                            end
                        end
                    end else if (!ptw_bus_hold && timeout_cnt >= PTW_TIMEOUT) begin  // BUG-15: timeout
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                        bus_req_pending_r <= 1'b0;
                    end
                end

                S_PERM_CHECK: begin
                    if (perm_fault) begin
                        fault_kind_r <= FAULT_PAGE;
                        state <= S_FAULT;
                    end else begin
                        if (!pte_a || (access_type == ACCESS_STORE && !pte_d)) begin
                            need_ad_update_r <= 1'b1;
                            need_d_update_r  <= access_type[1] && !pte_d;
                            state <= S_AD_UPDATE;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end

                S_AD_UPDATE: begin
                    bus_addr_r <= pte_addr_r;
                    bus_we_r   <= 1'b1;
                    if (need_d_update_r)
                        bus_wdata_r <= pte_r | 32'hC0;
                    else
                        bus_wdata_r <= pte_r | 32'h40;
                    bus_req_r  <= 1'b1;
                    bus_req_pending_r <= 1'b1;
                    state      <= S_AD_WAIT;
                end

                S_AD_WAIT: begin
                    if (bus_resp_err) begin
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                    end else if (bus_resp_ok) begin
                        if (ptw_bus_error) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            pte_r[6] <= 1'b1;
                            if (need_d_update_r)
                                pte_r[7] <= 1'b1;
                            state <= S_DONE;
                        end
                    end else if (!ptw_bus_hold && timeout_cnt >= PTW_TIMEOUT) begin  // BUG-15: timeout
                        fault_kind_r <= FAULT_ACCESS;
                        state <= S_FAULT;
                        bus_req_pending_r <= 1'b0;
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
