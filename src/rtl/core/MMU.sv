`timescale 1ns / 1ps

// Blocking Sv32 translation engine.
//
// The external I/D ports are a compatibility shell for core_top. Internally
// there is one owner, one latched request, one TLB lookup and one page walk.
// A request is never retargeted after acceptance.
module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input              clk,
    input              resetn,

    input       [31:0] i_vaddr,
    input              i_translate_en,
    output      [31:0] i_paddr,
    output             i_miss,
    output             i_page_fault,
    output      [3:0]  i_pf_cause,
    output      [31:0] i_pf_vaddr,
    output             i_ready,

    input       [31:0] d_vaddr,
    input       [1:0]  d_access_type,
    input              d_translate_en,
    output      [31:0] d_paddr,
    output             d_miss,
    output             d_page_fault,
    output      [3:0]  d_pf_cause,
    output      [31:0] d_pf_vaddr,
    output             d_ready,

    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_mprv,
    input       [1:0]  mstatus_mpp,
    input              mstatus_sum,
    input              mstatus_mxr,

    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error,

    input              sfence_req,
    output             sfence_done,

    output wire [3:0]  dbg_mmu_state,
    output wire        dbg_mmu_owner,
    output wire [31:0] dbg_mmu_req_vaddr,
    output wire        dbg_mmu_sv32,
    output wire        dbg_mmu_tlb_hit,
    output wire        dbg_mmu_tlb_perm_fault,
    output wire        dbg_mmu_ptw_active,
    output wire        dbg_mmu_fault_from_ptw
);
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    localparam [1:0] ACCESS_FETCH = 2'b00;
    localparam [1:0] ACCESS_LOAD  = 2'b01;
    localparam [1:0] ACCESS_STORE = 2'b10;

    localparam OWNER_I = 1'b0;
    localparam OWNER_D = 1'b1;

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_LOOKUP     = 4'd1;
    localparam [3:0] S_WALK_START = 4'd2;
    localparam [3:0] S_WALK_WAIT  = 4'd3;
    localparam [3:0] S_RESP       = 4'd4;
    localparam [3:0] S_FAULT      = 4'd5;
    localparam [3:0] S_ABORT      = 4'd6;
    localparam [3:0] S_FLUSH      = 4'd7;

    reg [3:0]  state;
    reg        owner_r;
    reg [31:0] req_vaddr_r;
    reg [1:0]  req_access_r;
    reg [1:0]  req_priv_r;
    reg [31:0] req_satp_r;
    reg        req_translate_en_r;
    reg        req_sum_r;
    reg        req_mxr_r;

    reg [31:0] response_paddr_r;
    reg [3:0]  fault_cause_r;
    reg [31:0] fault_vaddr_r;
    reg        fault_from_ptw_r;

    reg [31:0] satp_prev_r;
    reg        sfence_pending_r;
    reg        sfence_block_r;
    reg        sfence_done_r;

    wire [1:0] d_effective_priv =
        ((priv_mode == PRIV_M) && mstatus_mprv) ? mstatus_mpp : priv_mode;
    wire req_sv32 = req_translate_en_r && req_satp_r[31] &&
                    (req_priv_r != PRIV_M);

    wire i_request_matches = i_translate_en &&
                             (i_vaddr == req_vaddr_r) &&
                             (priv_mode == req_priv_r) &&
                             (satp == req_satp_r) &&
                             (mstatus_sum == req_sum_r) &&
                             (mstatus_mxr == req_mxr_r);
    wire d_request_matches = d_translate_en &&
                             (d_vaddr == req_vaddr_r) &&
                             (d_access_type == req_access_r) &&
                             (d_effective_priv == req_priv_r) &&
                             (satp == req_satp_r) &&
                             (mstatus_sum == req_sum_r) &&
                             (mstatus_mxr == req_mxr_r);
    wire request_matches = (owner_r == OWNER_D) ?
                           d_request_matches : i_request_matches;

    // A satp change is conservatively treated as a full TLB flush. Software
    // still uses SFENCE.VMA for architecturally ordered page-table updates.
    wire satp_changed = (satp != satp_prev_r);
    wire sfence_accept = sfence_req && !sfence_block_r &&
                          (state != S_FLUSH);
    wire flush_request = sfence_accept || satp_changed;

    wire        tlb_hit;
    wire [21:0] tlb_ppn;
    wire        tlb_r;
    wire        tlb_w;
    wire        tlb_x;
    wire        tlb_u;
    wire        tlb_a;
    wire        tlb_d;
    wire        tlb_g;
    wire        tlb_is_megapage;
    wire        tlb_flush_done;

    wire        ptw_walk_idle;
    wire        ptw_walk_done;
    wire        ptw_walk_fault;
    wire [3:0]  ptw_fault_cause;
    wire [31:0] ptw_fault_vaddr;
    wire [21:0] ptw_ppn;
    wire        ptw_r;
    wire        ptw_w;
    wire        ptw_x;
    wire        ptw_u;
    wire        ptw_a;
    wire        ptw_d;
    wire        ptw_g;
    wire        ptw_is_megapage;

    wire tlb_fill_req = (state == S_WALK_WAIT) && ptw_walk_done;
    wire tlb_flush_req = (state == S_FLUSH);

    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb (
        .clk(clk),
        .resetn(resetn),
        .lookup_vpn(req_vaddr_r[31:12]),
        .lookup_asid(req_satp_r[30:22]),
        .lookup_hit(tlb_hit),
        .lookup_ppn(tlb_ppn),
        .lookup_r(tlb_r),
        .lookup_w(tlb_w),
        .lookup_x(tlb_x),
        .lookup_u(tlb_u),
        .lookup_a(tlb_a),
        .lookup_d(tlb_d),
        .lookup_g(tlb_g),
        .lookup_is_megapage(tlb_is_megapage),
        .fill_req(tlb_fill_req),
        .fill_vpn(req_vaddr_r[31:12]),
        .fill_asid(req_satp_r[30:22]),
        .fill_ppn(ptw_ppn),
        .fill_r(ptw_r),
        .fill_w(ptw_w),
        .fill_x(ptw_x),
        .fill_u(ptw_u),
        .fill_a(ptw_a),
        .fill_d(ptw_d),
        .fill_g(ptw_g),
        .fill_is_megapage(ptw_is_megapage),
        .flush_all(tlb_flush_req),
        .flush_done(tlb_flush_done)
    );

    wire tlb_perm_fault =
        ((req_priv_r == PRIV_U) && !tlb_u) ||
        ((req_priv_r == PRIV_S) && tlb_u &&
            ((req_access_r == ACCESS_FETCH) || !req_sum_r)) ||
        ((req_access_r == ACCESS_FETCH) && !tlb_x) ||
        ((req_access_r == ACCESS_LOAD) && !tlb_r &&
            !(tlb_x && req_mxr_r)) ||
        ((req_access_r == ACCESS_STORE) && !tlb_w);
    wire tlb_need_ad_update = !tlb_a ||
                              ((req_access_r == ACCESS_STORE) && !tlb_d);

    wire [33:0] tlb_paddr = tlb_is_megapage ?
                            {tlb_ppn[21:10], req_vaddr_r[21:0]} :
                            {tlb_ppn, req_vaddr_r[11:0]};
    wire [33:0] ptw_paddr = ptw_is_megapage ?
                            {ptw_ppn[21:10], req_vaddr_r[21:0]} :
                            {ptw_ppn, req_vaddr_r[11:0]};

    function automatic [3:0] fault_cause;
        input [1:0] access_type;
        input       access_fault;
        begin
            if (access_fault) begin
                case (access_type)
                    ACCESS_FETCH: fault_cause = 4'd1;
                    ACCESS_LOAD:  fault_cause = 4'd5;
                    default:      fault_cause = 4'd7;
                endcase
            end else begin
                case (access_type)
                    ACCESS_FETCH: fault_cause = 4'd12;
                    ACCESS_LOAD:  fault_cause = 4'd13;
                    default:      fault_cause = 4'd15;
                endcase
            end
        end
    endfunction

    wire ptw_walk_req = (state == S_WALK_START) && request_matches;
    wire ptw_walk_abort = (state == S_ABORT);

    ptw u_ptw (
        .clk(clk),
        .resetn(resetn),
        .satp(req_satp_r),
        .priv_mode(req_priv_r),
        .mstatus_sum(req_sum_r),
        .mstatus_mxr(req_mxr_r),
        .access_type(req_access_r),
        .walk_vaddr(req_vaddr_r),
        .walk_req(ptw_walk_req),
        .walk_abort(ptw_walk_abort),
        .walk_idle(ptw_walk_idle),
        .walk_done(ptw_walk_done),
        .walk_fault(ptw_walk_fault),
        .walk_fault_cause(ptw_fault_cause),
        .walk_fault_vaddr(ptw_fault_vaddr),
        .walk_ppn(ptw_ppn),
        .walk_r(ptw_r),
        .walk_w(ptw_w),
        .walk_x(ptw_x),
        .walk_u(ptw_u),
        .walk_a(ptw_a),
        .walk_d(ptw_d),
        .walk_g(ptw_g),
        .walk_is_megapage(ptw_is_megapage),
        .ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),
        .ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),
        .ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),
        .ptw_bus_error(ptw_bus_error)
    );

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            owner_r <= OWNER_I;
            req_vaddr_r <= 32'b0;
            req_access_r <= ACCESS_FETCH;
            req_priv_r <= PRIV_M;
            req_satp_r <= 32'b0;
            req_translate_en_r <= 1'b0;
            req_sum_r <= 1'b0;
            req_mxr_r <= 1'b0;
            response_paddr_r <= 32'b0;
            fault_cause_r <= 4'b0;
            fault_vaddr_r <= 32'b0;
            fault_from_ptw_r <= 1'b0;
            satp_prev_r <= 32'b0;
            sfence_pending_r <= 1'b0;
            sfence_block_r <= 1'b0;
            sfence_done_r <= 1'b0;
        end else begin
            satp_prev_r <= satp;
            sfence_done_r <= 1'b0;

            if (!sfence_req)
                sfence_block_r <= 1'b0;

            if (sfence_accept) begin
                sfence_pending_r <= 1'b1;
                sfence_block_r <= 1'b1;
            end

            if (flush_request && state != S_ABORT && state != S_FLUSH) begin
                state <= S_ABORT;
            end else begin
                case (state)
                    S_IDLE: begin
                        fault_from_ptw_r <= 1'b0;
                        // MEM wins only when it has a real request. Fetch is
                        // otherwise accepted when its stage is active.
                        if (d_translate_en) begin
                            owner_r <= OWNER_D;
                            req_vaddr_r <= d_vaddr;
                            req_access_r <= d_access_type;
                            req_priv_r <= d_effective_priv;
                            req_satp_r <= satp;
                            req_translate_en_r <= 1'b1;
                            req_sum_r <= mstatus_sum;
                            req_mxr_r <= mstatus_mxr;
                            state <= S_LOOKUP;
                        end else if (i_translate_en) begin
                            owner_r <= OWNER_I;
                            req_vaddr_r <= i_vaddr;
                            req_access_r <= ACCESS_FETCH;
                            req_priv_r <= priv_mode;
                            req_satp_r <= satp;
                            req_translate_en_r <= 1'b1;
                            req_sum_r <= mstatus_sum;
                            req_mxr_r <= mstatus_mxr;
                            state <= S_LOOKUP;
                        end
                    end

                    S_LOOKUP: begin
                        if (!request_matches) begin
                            state <= S_IDLE;
                        end else if (!req_sv32) begin
                            response_paddr_r <= req_vaddr_r;
                            state <= S_RESP;
                        end else if (!tlb_hit) begin
                            state <= S_WALK_START;
                        end else if (tlb_perm_fault) begin
                            fault_cause_r <= fault_cause(req_access_r, 1'b0);
                            fault_vaddr_r <= req_vaddr_r;
                            fault_from_ptw_r <= 1'b0;
                            state <= S_FAULT;
                        end else if (tlb_need_ad_update) begin
                            state <= S_WALK_START;
                        end else if (tlb_paddr[33:32] != 2'b0) begin
                            fault_cause_r <= fault_cause(req_access_r, 1'b1);
                            fault_vaddr_r <= req_vaddr_r;
                            fault_from_ptw_r <= 1'b0;
                            state <= S_FAULT;
                        end else begin
                            response_paddr_r <= tlb_paddr[31:0];
                            state <= S_RESP;
                        end
                    end

                    S_WALK_START: begin
                        if (!request_matches)
                            state <= S_IDLE;
                        else
                            state <= S_WALK_WAIT;
                    end

                    S_WALK_WAIT: begin
                        if (ptw_walk_fault) begin
                            fault_cause_r <= ptw_fault_cause;
                            fault_vaddr_r <= ptw_fault_vaddr;
                            fault_from_ptw_r <= 1'b1;
                            state <= S_FAULT;
                        end else if (ptw_walk_done) begin
                            if (ptw_paddr[33:32] != 2'b0) begin
                                fault_cause_r <= fault_cause(req_access_r, 1'b1);
                                fault_vaddr_r <= req_vaddr_r;
                                fault_from_ptw_r <= 1'b1;
                                state <= S_FAULT;
                            end else begin
                                response_paddr_r <= ptw_paddr[31:0];
                                state <= S_RESP;
                            end
                        end
                    end

                    S_RESP: begin
                        if (!request_matches)
                            state <= S_IDLE;
                    end

                    S_FAULT: begin
                        if (!request_matches)
                            state <= S_IDLE;
                    end

                    S_ABORT: begin
                        // PTW drains an already-issued memory transaction before
                        // reporting idle. No external request is cancelled.
                        if (ptw_walk_idle)
                            state <= S_FLUSH;
                    end

                    S_FLUSH: begin
                        if (tlb_flush_done) begin
                            sfence_done_r <= sfence_pending_r;
                            sfence_pending_r <= 1'b0;
                            state <= S_IDLE;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    assign i_paddr = (owner_r == OWNER_I) ? response_paddr_r : i_vaddr;
    assign d_paddr = (owner_r == OWNER_D) ? response_paddr_r : d_vaddr;
    assign i_ready = (state == S_RESP) && (owner_r == OWNER_I) &&
                     i_request_matches;
    assign d_ready = (state == S_RESP) && (owner_r == OWNER_D) &&
                     d_request_matches;
    assign i_miss = ((state == S_WALK_START) || (state == S_WALK_WAIT)) &&
                    (owner_r == OWNER_I);
    assign d_miss = ((state == S_WALK_START) || (state == S_WALK_WAIT)) &&
                    (owner_r == OWNER_D);

    assign i_page_fault = (state == S_FAULT) && (owner_r == OWNER_I) &&
                          i_request_matches;
    assign d_page_fault = (state == S_FAULT) && (owner_r == OWNER_D) &&
                          d_request_matches;
    assign i_pf_cause = i_page_fault ? fault_cause_r : 4'b0;
    assign d_pf_cause = d_page_fault ? fault_cause_r : 4'b0;
    assign i_pf_vaddr = i_page_fault ? fault_vaddr_r : 32'b0;
    assign d_pf_vaddr = d_page_fault ? fault_vaddr_r : 32'b0;
    assign sfence_done = sfence_done_r;

    wire lookup_active = (state == S_LOOKUP) && req_sv32;
    assign dbg_mmu_state = state;
    assign dbg_mmu_owner = owner_r;
    assign dbg_mmu_req_vaddr = req_vaddr_r;
    assign dbg_mmu_sv32 = req_sv32;
    assign dbg_mmu_tlb_hit = lookup_active && tlb_hit;
    assign dbg_mmu_tlb_perm_fault = lookup_active && tlb_hit &&
                                    tlb_perm_fault;
    assign dbg_mmu_ptw_active = (state == S_WALK_START) ||
                                (state == S_WALK_WAIT);
    assign dbg_mmu_fault_from_ptw = (state == S_FAULT) &&
                                    fault_from_ptw_r;
endmodule
