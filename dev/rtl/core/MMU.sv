`timescale 1ns / 1ps
`include "cache_def.svh"

module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input              clk,
    input              reset,

    input       [31:0] vaddr,
    input       [1:0]  access_type,
    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_sum,
    input              mstatus_mxr,
    input              translate_en,    // 0 = bare mode (no translation/faults)

    output      [31:0] paddr,
    output             miss,
    output             page_fault,
    output      [3:0]  page_fault_cause,
    output      [31:0] page_fault_vaddr,

    input              ptw_done,
    input              ptw_fault,

    input              sfence_vma,

    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error,

    output             ready
);

    localparam PRIV_M = 2'b11;

    localparam ACCESS_FETCH = 2'b00;
    localparam ACCESS_LOAD  = 2'b01;
    localparam ACCESS_STORE = 2'b10;

    wire sv32_enabled = satp[31] && (priv_mode != PRIV_M) && translate_en;
    wire [19:0] vpn   = vaddr[31:12];
    wire [8:0]  asid  = satp[30:22];

    wire        tlb_hit;
    wire [21:0] tlb_ppn;
    wire        tlb_r, tlb_w, tlb_x, tlb_u;
    wire        tlb_a, tlb_d, tlb_g;
    wire        tlb_is_megapage;
    wire        tlb_lookup_valid;
    wire        tlb_flush_done;

    wire [21:0] ptw_fill_ppn;
    wire        ptw_fill_r, ptw_fill_w, ptw_fill_x, ptw_fill_u;
    wire        ptw_fill_a, ptw_fill_d, ptw_fill_g;
    wire        ptw_fill_is_megapage;
    wire [19:0] ptw_fill_vpn;
    wire [8:0]  ptw_fill_asid;

    wire [3:0]  ptw_fault_cause_out;
    wire [31:0] ptw_fault_vaddr_out;

`ifdef USE_TLB_BRAM

    // =========================================================================
    // State machine for 1-cycle TLB BRAM latency
    // =========================================================================

    localparam S_IDLE      = 3'd0;
    localparam S_LOOKUP    = 3'd1;
    localparam S_WALK_WAIT = 3'd2;
    localparam S_FLUSH     = 3'd3;
    localparam S_FILL_WAIT = 3'd4;  // Wait for TLB BRAM Port B write to complete

    reg [2:0] mmu_state;

    // Latched values for use in S_LOOKUP
    reg [31:0] latched_vaddr;
    reg [1:0]  latched_access_type;
    reg [1:0]  latched_priv_mode;
    reg [31:0] latched_satp;
    reg        latched_translate_en;
    reg        latched_mstatus_sum;
    reg        latched_mstatus_mxr;

    wire latched_sv32 = latched_satp[31] && (latched_priv_mode != PRIV_M) && latched_translate_en;

    // Fill VPN/ASID from latched values (stable during walk)
    assign ptw_fill_vpn  = latched_vaddr[31:12];
    assign ptw_fill_asid = latched_satp[30:22];

    // TLB lookup request: assert in S_IDLE to start BRAM read
    wire tlb_lookup_req = (mmu_state == S_IDLE) && !sfence_vma;

    // TLB fill request: only when ptw_done in S_WALK_WAIT
    wire tlb_fill_req = ptw_done && (mmu_state == S_WALK_WAIT);

    // Input change detection: when any MMU input changes, we must re-latch
    // and re-do the TLB BRAM read (new set_idx → new BRAM output needed)
    wire input_changed = (vaddr != latched_vaddr) ||
                         (access_type != latched_access_type) ||
                         (priv_mode != latched_priv_mode) ||
                         (satp != latched_satp) ||
                         (translate_en != latched_translate_en) ||
                         (mstatus_sum != latched_mstatus_sum) ||
                         (mstatus_mxr != latched_mstatus_mxr);

    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb(
        .clk(clk),
        .reset(reset),
        .lookup_vpn(vpn),
        .lookup_asid(asid),
        .lookup_req(tlb_lookup_req),
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
        .lookup_valid(tlb_lookup_valid),
        .fill_req(tlb_fill_req),
        .fill_vpn(ptw_fill_vpn),
        .fill_asid(ptw_fill_asid),
        .fill_ppn(ptw_fill_ppn),
        .fill_r(ptw_fill_r),
        .fill_w(ptw_fill_w),
        .fill_x(ptw_fill_x),
        .fill_u(ptw_fill_u),
        .fill_a(ptw_fill_a),
        .fill_d(ptw_fill_d),
        .fill_g(ptw_fill_g),
        .fill_is_megapage(ptw_fill_is_megapage),
        .flush_all(sfence_vma),
        .flush_done(tlb_flush_done)
    );

    // Permission check using latched values and TLB outputs
    wire tlb_perm_fault;
    assign tlb_perm_fault = (latched_priv_mode == 2'b00 && !tlb_u) ? 1'b1 :
                            (latched_priv_mode == 2'b01 && tlb_u &&
                             (latched_access_type == ACCESS_FETCH || !latched_mstatus_sum)) ? 1'b1 :
                            (latched_access_type == ACCESS_FETCH && !tlb_x) ? 1'b1 :
                            (latched_access_type == ACCESS_LOAD && !tlb_r && !(tlb_x && latched_mstatus_mxr)) ? 1'b1 :
                            (latched_access_type == ACCESS_STORE && !tlb_w) ? 1'b1 : 1'b0;

    // Translation using latched vaddr
    wire [33:0] translated_paddr;
    assign translated_paddr = tlb_is_megapage ?
        {tlb_ppn[21:10], latched_vaddr[21:0]} :
        {tlb_ppn, latched_vaddr[11:0]};

    wire translation_ok = latched_sv32 && tlb_hit && !tlb_perm_fault;
    wire tlb_miss       = latched_sv32 && !tlb_hit;
    wire tlb_pf         = latched_sv32 && tlb_hit && tlb_perm_fault;

    // Combinational paddr output (valid when ready=1)
    assign paddr = !latched_sv32 ? latched_vaddr :
                   translation_ok ? translated_paddr[31:0] : latched_vaddr;

    // ready: combinational, high when MMU is in S_LOOKUP and TLB result is valid
    //        for the CURRENT inputs (not a stale latched set).
    //        Must deassert when input_changed: the latched values are stale,
    //        and the dcache would use the wrong paddr for tag comparison.
    assign ready = (mmu_state == S_LOOKUP) && !input_changed;

    // miss: combinational, gated by state, sv32_enabled, and input_changed
    //       Must gate on latched_sv32: in bare mode (sv32=0), TLB miss is irrelevant —
    //       the MMU bypasses translation, so miss must be 0 to avoid stalling the pipeline.
    //       When input_changed, the miss is for the OLD latched inputs — ignore it.
    assign miss = (mmu_state == S_LOOKUP) && latched_sv32 && tlb_miss && !input_changed;

    // Page fault: registered (same pattern as original)
    reg pf_r;
    reg [3:0] pf_cause_r;
    reg [31:0] pf_vaddr_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pf_r <= 1'b0;
            pf_cause_r <= 4'b0;
            pf_vaddr_r <= 32'b0;
        end else begin
            pf_r <= 1'b0;
            if (mmu_state == S_LOOKUP && tlb_pf && !input_changed) begin
                pf_r <= 1'b1;
                pf_vaddr_r <= latched_vaddr;
                case (latched_access_type)
                    ACCESS_FETCH: pf_cause_r <= 4'd12;
                    ACCESS_LOAD:  pf_cause_r <= 4'd13;
                    default:      pf_cause_r <= 4'd15;
                endcase
            end else if (mmu_state == S_WALK_WAIT && ptw_fault) begin
                pf_r <= 1'b1;
                pf_cause_r <= ptw_fault_cause_out;
                pf_vaddr_r <= ptw_fault_vaddr_out;
            end
        end
    end

    assign page_fault       = pf_r;
    assign page_fault_cause = pf_r ? (ptw_fault ? ptw_fault_cause_out : pf_cause_r) : 4'b0;
    assign page_fault_vaddr = pf_r ? (ptw_fault ? ptw_fault_vaddr_out : pf_vaddr_r) : 32'b0;

    // State machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mmu_state          <= S_IDLE;
            latched_vaddr      <= 32'b0;
            latched_access_type <= 2'b0;
            latched_priv_mode  <= 2'b0;
            latched_satp       <= 32'b0;
            latched_translate_en <= 1'b0;
            latched_mstatus_sum  <= 1'b0;
            latched_mstatus_mxr <= 1'b0;
        end else begin
            case (mmu_state)
                S_IDLE: begin
                    if (sfence_vma) begin
                        mmu_state <= S_FLUSH;
                    end else begin
                        // Latch inputs for use in S_LOOKUP
                        latched_vaddr       <= vaddr;
                        latched_access_type <= access_type;
                        latched_priv_mode   <= priv_mode;
                        latched_satp        <= satp;
                        latched_translate_en <= translate_en;
                        latched_mstatus_sum  <= mstatus_sum;
                        latched_mstatus_mxr  <= mstatus_mxr;
                        mmu_state <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    // TLB lookup_valid=1 in this state, ready=1
                    // Miss has priority over input_changed: once we detect a miss,
                    // we must enter S_WALK_WAIT to trigger PTW. If input_changed
                    // also fires (cache hasn't stalled yet), the walk will use
                    // the latched vaddr which is correct.
                    if (sfence_vma) begin
                        mmu_state <= S_FLUSH;
                    end else if (latched_sv32 && !tlb_hit) begin
                        // Miss: trigger PTW (priority over input_changed)
                        mmu_state <= S_WALK_WAIT;
                    end else if (input_changed) begin
                        // Inputs changed: go to S_IDLE to re-latch and re-do TLB BRAM read
                        mmu_state <= S_IDLE;
                    end
                    // Else: hit/bare-mode/pf — stay in S_LOOKUP (ready remains high)
                end

                S_WALK_WAIT: begin
                    if (sfence_vma) begin
                        // Abort walk, start flush
                        mmu_state <= S_FLUSH;
                    end else if (ptw_done) begin
                        // Fill TLB (Port B write takes effect next cycle),
                        // then wait 1 cycle to avoid BRAM collision with
                        // the re-lookup Port A read.
                        mmu_state <= S_FILL_WAIT;
                    end else if (ptw_fault) begin
                        // Page fault from PTW
                        mmu_state <= S_IDLE;
                    end
                end

                S_FILL_WAIT: begin
                    // Port B write from the fill has completed.
                    // Safe to start a new lookup (Port A read) from S_IDLE.
                    mmu_state <= S_IDLE;
                end

                S_FLUSH: begin
                    if (tlb_flush_done) begin
                        mmu_state <= S_IDLE;
                    end
                end

                default: mmu_state <= S_IDLE;
            endcase
        end
    end

    // PTW instance — walk_req is a one-cycle pulse in S_LOOKUP on miss
    wire walk_req_pulse = (mmu_state == S_LOOKUP) && tlb_miss;

    ptw u_ptw(
        .clk(clk),
        .reset(reset),
        .satp(latched_satp),
        .priv_mode(latched_priv_mode),
        .mstatus_sum(latched_mstatus_sum),
        .mstatus_mxr(latched_mstatus_mxr),
        .access_type(latched_access_type),
        .walk_vaddr(latched_vaddr),
        .walk_req(walk_req_pulse),
        .walk_done(ptw_done),
        .walk_fault(ptw_fault),
        .walk_fault_cause(ptw_fault_cause_out),
        .walk_fault_vaddr(ptw_fault_vaddr_out),
        .walk_ppn(ptw_fill_ppn),
        .walk_r(ptw_fill_r),
        .walk_w(ptw_fill_w),
        .walk_x(ptw_fill_x),
        .walk_u(ptw_fill_u),
        .walk_a(ptw_fill_a),
        .walk_d(ptw_fill_d),
        .walk_g(ptw_fill_g),
        .walk_is_megapage(ptw_fill_is_megapage),
        .ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),
        .ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),
        .ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),
        .ptw_bus_error(ptw_bus_error)
    );

`else // !USE_TLB_BRAM

    // =========================================================================
    // Original combinational MMU (no state machine)
    // =========================================================================

    // Fill VPN/ASID from raw inputs (combinational — no latching needed)
    assign ptw_fill_vpn  = vaddr[31:12];
    assign ptw_fill_asid = satp[30:22];

    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb(
        .clk(clk),
        .reset(reset),
        .lookup_vpn(vpn),
        .lookup_asid(asid),
        .lookup_req(1'b1),
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
        .lookup_valid(),
        .fill_req(ptw_done),
        .fill_vpn(ptw_fill_vpn),
        .fill_asid(ptw_fill_asid),
        .fill_ppn(ptw_fill_ppn),
        .fill_r(ptw_fill_r),
        .fill_w(ptw_fill_w),
        .fill_x(ptw_fill_x),
        .fill_u(ptw_fill_u),
        .fill_a(ptw_fill_a),
        .fill_d(ptw_fill_d),
        .fill_g(ptw_fill_g),
        .fill_is_megapage(ptw_fill_is_megapage),
        .flush_all(sfence_vma),
        .flush_done()
    );

    reg tlb_perm_fault;
    always @(*) begin
        tlb_perm_fault = 1'b0;
        if (priv_mode == 2'b00 && !tlb_u)
            tlb_perm_fault = 1'b1;
        if (priv_mode == 2'b01 && tlb_u) begin
            if (access_type == ACCESS_FETCH)
                tlb_perm_fault = 1'b1;
            else if (!mstatus_sum)
                tlb_perm_fault = 1'b1;
        end
        if (access_type == ACCESS_FETCH && !tlb_x)
            tlb_perm_fault = 1'b1;
        if (access_type == ACCESS_LOAD) begin
            if (!tlb_r && !(tlb_x && mstatus_mxr))
                tlb_perm_fault = 1'b1;
        end
        if (access_type == ACCESS_STORE && !tlb_w)
            tlb_perm_fault = 1'b1;
    end

    wire [33:0] translated_paddr;
    assign translated_paddr = tlb_is_megapage ?
        {tlb_ppn[21:10], vaddr[21:0]} :
        {tlb_ppn, vaddr[11:0]};

    wire translation_ok = sv32_enabled && tlb_hit && !tlb_perm_fault;
    wire tlb_miss       = sv32_enabled && !tlb_hit;
    wire tlb_pf         = sv32_enabled && tlb_hit && tlb_perm_fault;

    assign paddr = !sv32_enabled ? vaddr :
                   translation_ok ? translated_paddr[31:0] : vaddr;

    reg walk_active_r;
    always @(posedge clk or posedge reset) begin
        if (reset)
            walk_active_r <= 1'b0;
        else if (sfence_vma)
            walk_active_r <= 1'b0;
        else if (tlb_miss && !walk_active_r)
            walk_active_r <= 1'b1;
        else if (ptw_done || ptw_fault)
            walk_active_r <= 1'b0;
    end

    assign miss = tlb_miss && !walk_active_r;

    reg pf_r;
    reg [3:0] pf_cause_r;
    reg [31:0] pf_vaddr_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pf_r <= 1'b0;
            pf_cause_r <= 4'b0;
            pf_vaddr_r <= 32'b0;
        end else begin
            pf_r <= 1'b0;
            if (tlb_pf && !walk_active_r) begin
                pf_r <= 1'b1;
                pf_vaddr_r <= vaddr;
                case (access_type)
                    ACCESS_FETCH: pf_cause_r <= 4'd12;
                    ACCESS_LOAD:  pf_cause_r <= 4'd13;
                    default:      pf_cause_r <= 4'd15;
                endcase
            end else if (ptw_fault && walk_active_r) begin
                pf_r <= 1'b1;
            end
        end
    end

    assign page_fault       = pf_r;
    assign page_fault_cause = pf_r ? (ptw_fault ? ptw_fault_cause_out : pf_cause_r) : 4'b0;
    assign page_fault_vaddr = pf_r ? (ptw_fault ? ptw_fault_vaddr_out : pf_vaddr_r) : 32'b0;

    // Non-BRAM: always ready (combinational)
    assign ready = 1'b1;

    ptw u_ptw(
        .clk(clk),
        .reset(reset),
        .satp(satp),
        .priv_mode(priv_mode),
        .mstatus_sum(mstatus_sum),
        .mstatus_mxr(mstatus_mxr),
        .access_type(access_type),
        .walk_vaddr(vaddr),
        .walk_req(tlb_miss && !walk_active_r),
        .walk_done(ptw_done),
        .walk_fault(ptw_fault),
        .walk_fault_cause(ptw_fault_cause_out),
        .walk_fault_vaddr(ptw_fault_vaddr_out),
        .walk_ppn(ptw_fill_ppn),
        .walk_r(ptw_fill_r),
        .walk_w(ptw_fill_w),
        .walk_x(ptw_fill_x),
        .walk_u(ptw_fill_u),
        .walk_a(ptw_fill_a),
        .walk_d(ptw_fill_d),
        .walk_g(ptw_fill_g),
        .walk_is_megapage(ptw_fill_is_megapage),
        .ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),
        .ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),
        .ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),
        .ptw_bus_error(ptw_bus_error)
    );

`endif // USE_TLB_BRAM

endmodule
