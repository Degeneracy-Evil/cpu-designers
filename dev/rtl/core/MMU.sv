`timescale 1ns / 1ps
`include "cache_def.svh"

module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input              clk,
    input              resetn,

    // ── i-side interface ──
    input       [31:0] i_vaddr,
    input              i_translate_en,       // tied to 1'b1 in core_top
    output      [31:0] i_paddr,
    output             i_miss,
    output             i_page_fault,
    output      [3:0]  i_pf_cause,
    output      [31:0] i_pf_vaddr,
    output             i_ready,

    // ── d-side interface ──
    input       [31:0] d_vaddr,
    input       [1:0]  d_access_type,       // LOAD/STORE
    input              d_translate_en,       // mem_en
    output      [31:0] d_paddr,
    output             d_miss,
    output             d_page_fault,
    output      [3:0]  d_pf_cause,
    output      [31:0] d_pf_vaddr,
    output             d_ready,

    // ── shared CSR inputs ──
    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_sum,
    input              mstatus_mxr,

    // ── single PTW bus ──
    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error,

    // ── flush ──
    input              sfence_vma,

    // ── sfence completion ──
    output wire        sfence_done,
    output wire        dbg_i_walk_active,
    output wire        dbg_pending_i_walk,
    output wire [2:0]  dbg_nb_i_state,
    output wire        dbg_nb_i_input_changed,
    output wire [31:0] dbg_nb_i_latched_vaddr,
    output wire        dbg_nb_i_latched_sv32,
    output wire        dbg_i_tlb_hit,
    output wire        dbg_i_tlb_valid,
    output wire        dbg_i_tlb_perm_fault,
    output wire [1:0]  dbg_walk_state,
    // ── d-side debug outputs ──
    output wire [2:0]  dbg_nb_d_state,
    output wire        dbg_d_tlb_hit,
    output wire        dbg_d_tlb_valid,
    output wire        dbg_d_tlb_perm_fault,
    output wire        dbg_d_input_changed,
    output wire [31:0] dbg_d_latched_vaddr,
    output wire        dbg_d_latched_sv32,
    output wire        dbg_pending_d_walk,
    output wire        dbg_d_pf_from_ptw,
    output wire        dbg_d_tlb_miss
);

    localparam PRIV_M = 2'b11;

    localparam ACCESS_FETCH = 2'b00;
    localparam ACCESS_LOAD  = 2'b01;
    localparam ACCESS_STORE = 2'b10;
    localparam PTW_FAULT_NONE   = 2'd0;
    localparam PTW_FAULT_PAGE   = 2'd1;
    localparam PTW_FAULT_ACCESS = 2'd2;

    // =========================================================================
    // VPN / ASID / sv32 for each side
    // =========================================================================
    wire [19:0] i_vpn  = i_vaddr[31:12];
    wire [8:0]  i_asid = satp[30:22];
    wire        i_sv32 = satp[31] && (priv_mode != PRIV_M) && i_translate_en;

    wire [19:0] d_vpn  = d_vaddr[31:12];
    wire [8:0]  d_asid = satp[30:22];
    wire        d_sv32 = satp[31] && (priv_mode != PRIV_M) && d_translate_en;

    // =========================================================================
    // TLB flush on satp write (RISC-V spec requirement)
    // =========================================================================
    // Per spec: writing satp must invalidate TLB entries for current ASID.
    // Detect satp change and combine with sfence_vma for TLB flush.
    reg [31:0] satp_prev;
    wire satp_changed = (satp != satp_prev) && (priv_mode != PRIV_M);
    wire mmu_flush_req = sfence_vma || satp_changed;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            satp_prev <= 32'b0;
        else
            satp_prev <= satp;
    end

`ifdef USE_TLB_BRAM

    // =========================================================================
    // Unified MMU state machine
    // =========================================================================
    // i-side FSM
    localparam I_IDLE         = 3'd0;
    localparam I_LOOKUP       = 3'd1;
    localparam I_WALK_PENDING = 3'd2;
    localparam I_FILL_WAIT    = 3'd3;
    localparam I_FLUSH        = 3'd4;

    // d-side FSM
    localparam D_IDLE         = 3'd0;
    localparam D_LOOKUP       = 3'd1;
    localparam D_WALK_PENDING = 3'd2;
    localparam D_FILL_WAIT    = 3'd3;
    localparam D_FLUSH        = 3'd4;

    // Walk arbiter FSM
    localparam W_IDLE   = 2'd0;
    localparam W_D_WALK = 2'd1;
    localparam W_I_WALK = 2'd2;

    reg [2:0] i_state;
    reg [2:0] d_state;
    reg [1:0] walk_state;
    reg       pending_i_walk;     // i-miss queued while d-walk in progress
    reg       pending_d_walk;     // d-miss queued while i-walk in progress

    // ── i-side latched values ──
    reg [31:0] i_latched_vaddr;
    reg [1:0]  i_latched_access_type;  // always FETCH, but kept for uniformity
    reg [1:0]  i_latched_priv_mode;
    reg [31:0] i_latched_satp;
    reg        i_latched_translate_en;
    reg        i_latched_mstatus_sum;
    reg        i_latched_mstatus_mxr;
    wire       i_latched_sv32 = i_latched_satp[31] && (i_latched_priv_mode != PRIV_M) && i_latched_translate_en;

    // ── d-side latched values ──
    reg [31:0] d_latched_vaddr;
    reg [1:0]  d_latched_access_type;
    reg [1:0]  d_latched_priv_mode;
    reg [31:0] d_latched_satp;
    reg        d_latched_translate_en;
    reg        d_latched_mstatus_sum;
    reg        d_latched_mstatus_mxr;
    wire       d_latched_sv32 = d_latched_satp[31] && (d_latched_priv_mode != PRIV_M) && d_latched_translate_en;

    // ── Input change detection ──
    wire i_input_changed = (i_vaddr != i_latched_vaddr) ||
                           (priv_mode != i_latched_priv_mode) ||
                           (satp != i_latched_satp) ||
                           (i_translate_en != i_latched_translate_en) ||
                           (mstatus_sum != i_latched_mstatus_sum) ||
                           (mstatus_mxr != i_latched_mstatus_mxr);
    // Note: i_access_type is always FETCH, no change detection needed

    wire d_input_changed = (d_vaddr != d_latched_vaddr) ||
                           (d_access_type != d_latched_access_type) ||
                           (priv_mode != d_latched_priv_mode) ||
                           (satp != d_latched_satp) ||
                           (d_translate_en != d_latched_translate_en) ||
                           (mstatus_sum != d_latched_mstatus_sum) ||
                           (mstatus_mxr != d_latched_mstatus_mxr);

    // =========================================================================
    // TLB instance (dual-port)
    // =========================================================================
    wire        i_tlb_hit, i_tlb_r, i_tlb_w, i_tlb_x, i_tlb_u;
    wire        i_tlb_a, i_tlb_d, i_tlb_g, i_tlb_is_megapage;
    wire [21:0] i_tlb_ppn;
    wire        i_tlb_valid;

    wire        d_tlb_hit, d_tlb_r, d_tlb_w, d_tlb_x, d_tlb_u;
    wire        d_tlb_a, d_tlb_d, d_tlb_g, d_tlb_is_megapage;
    wire [21:0] d_tlb_ppn;
    wire        d_tlb_valid;

    wire        tlb_flush_done;

    // PTW done/fault (declared early for tlb_fill_req)
    wire        ptw_walk_done;
    wire        ptw_walk_fault;
    wire [1:0]  ptw_fault_kind_out;

    // TLB lookup requests
    // BUG-16 fix: keep lookup req active during I_LOOKUP/D_LOOKUP so BRAM-based
    // TLB i_lookup_valid_r/d_lookup_valid_r stay high. Otherwise the 1-cycle
    // valid pulse expires and the MMU deadlocks (valid=0, hit=1, ready=0, miss=0).
    wire i_req_active = (i_state == I_LOOKUP) && !i_input_changed;
    wire d_req_active = (d_state == D_LOOKUP) && !d_input_changed;
    wire i_tlb_lookup_req = i_req_active && !mmu_flush_req;
    wire d_tlb_lookup_req = d_req_active && !mmu_flush_req && !d_lookup_stalled;

    // PTW fill signals (declared early — used by TLB instance below)
    wire [21:0] ptw_fill_ppn;
    wire        ptw_fill_r, ptw_fill_w, ptw_fill_x, ptw_fill_u;
    wire        ptw_fill_a, ptw_fill_d, ptw_fill_g;
    wire        ptw_fill_is_megapage;
    wire [3:0]  ptw_fault_cause_out;
    wire [31:0] ptw_fault_vaddr_out;

    // TLB fill request: only on PTW done (NOT fault — no valid PTE to fill on fault)
    wire tlb_fill_req = ptw_walk_done &&
                        (walk_state == W_D_WALK || walk_state == W_I_WALK);

    // Fill VPN/ASID from the side being serviced by the walk arbiter
    wire [19:0] fill_vpn  = (walk_state == W_D_WALK) ? d_latched_vaddr[31:12] : i_latched_vaddr[31:12];
    wire [8:0]  fill_asid = (walk_state == W_D_WALK) ? d_latched_satp[30:22] : i_latched_satp[30:22];

    // d-side lookup stalled when Port B is used for fill
    wire d_lookup_stalled = tlb_fill_req;

    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb(
        .clk(clk),
        .resetn(resetn),
        // i-side lookup (Port A)
        .i_lookup_vpn(i_vpn),
        .i_lookup_asid(i_asid),
        .i_lookup_req(i_tlb_lookup_req),
        .i_lookup_hit(i_tlb_hit),
        .i_lookup_ppn(i_tlb_ppn),
        .i_lookup_r(i_tlb_r),
        .i_lookup_w(i_tlb_w),
        .i_lookup_x(i_tlb_x),
        .i_lookup_u(i_tlb_u),
        .i_lookup_a(i_tlb_a),
        .i_lookup_d(i_tlb_d),
        .i_lookup_g(i_tlb_g),
        .i_lookup_is_megapage(i_tlb_is_megapage),
        .i_lookup_valid(i_tlb_valid),
        // d-side lookup (Port B)
        .d_lookup_vpn(d_vpn),
        .d_lookup_asid(d_asid),
        .d_lookup_req(d_tlb_lookup_req),
        .d_lookup_hit(d_tlb_hit),
        .d_lookup_ppn(d_tlb_ppn),
        .d_lookup_r(d_tlb_r),
        .d_lookup_w(d_tlb_w),
        .d_lookup_x(d_tlb_x),
        .d_lookup_u(d_tlb_u),
        .d_lookup_a(d_tlb_a),
        .d_lookup_d(d_tlb_d),
        .d_lookup_g(d_tlb_g),
        .d_lookup_is_megapage(d_tlb_is_megapage),
        .d_lookup_valid(d_tlb_valid),
        // Fill (Port B write, preempts d-lookup)
        .fill_req(tlb_fill_req),
        .fill_vpn(fill_vpn),
        .fill_asid(fill_asid),
        .fill_ppn(ptw_fill_ppn),
        .fill_r(ptw_fill_r),
        .fill_w(ptw_fill_w),
        .fill_x(ptw_fill_x),
        .fill_u(ptw_fill_u),
        .fill_a(ptw_fill_a),
        .fill_d(ptw_fill_d),
        .fill_g(ptw_fill_g),
        .fill_is_megapage(ptw_fill_is_megapage),
        // Flush
        .flush_all(mmu_flush_req),
        .flush_done(tlb_flush_done)
    );

    // =========================================================================
    // Permission checks (using latched values + TLB outputs)
    // =========================================================================
    wire i_tlb_perm_fault;
    assign i_tlb_perm_fault = (i_latched_priv_mode == 2'b00 && !i_tlb_u) ? 1'b1 :
                              (i_latched_priv_mode == 2'b01 && i_tlb_u &&
                               (i_latched_access_type == ACCESS_FETCH || !i_latched_mstatus_sum)) ? 1'b1 :
                              (i_latched_access_type == ACCESS_FETCH && !i_tlb_x) ? 1'b1 :
                              (i_latched_access_type == ACCESS_LOAD && !i_tlb_r && !(i_tlb_x && i_latched_mstatus_mxr)) ? 1'b1 :
                              (i_latched_access_type == ACCESS_STORE && !i_tlb_w) ? 1'b1 : 1'b0;

    wire d_tlb_need_ad_update;
    assign d_tlb_need_ad_update = d_latched_sv32 && d_tlb_valid && d_tlb_hit &&
                                  (d_latched_access_type == ACCESS_STORE) && !d_tlb_d;

    wire d_tlb_perm_fault;
    assign d_tlb_perm_fault = (d_latched_priv_mode == 2'b00 && !d_tlb_u) ? 1'b1 :
                              (d_latched_priv_mode == 2'b01 && d_tlb_u &&
                               (d_latched_access_type == ACCESS_FETCH || !d_latched_mstatus_sum)) ? 1'b1 :
                              (d_latched_access_type == ACCESS_FETCH && !d_tlb_x) ? 1'b1 :
                              (d_latched_access_type == ACCESS_LOAD && !d_tlb_r && !(d_tlb_x && d_latched_mstatus_mxr)) ? 1'b1 :
                              (d_latched_access_type == ACCESS_STORE && !d_tlb_w) ? 1'b1 : 1'b0;

    // =========================================================================
    // Translation outputs
    // =========================================================================
    wire [33:0] i_translated_paddr;
    assign i_translated_paddr = i_tlb_is_megapage ?
        {i_tlb_ppn[21:10], i_latched_vaddr[21:0]} :
        {i_tlb_ppn, i_latched_vaddr[11:0]};

    wire i_translation_ok = i_latched_sv32 && i_tlb_valid && i_tlb_hit && !i_tlb_perm_fault;
    wire i_tlb_miss       = i_latched_sv32 && i_tlb_valid && !i_tlb_hit;
    wire i_tlb_pf         = i_latched_sv32 && i_tlb_valid && i_tlb_hit && i_tlb_perm_fault;

    assign i_paddr = !i_latched_sv32 ? i_latched_vaddr :
                     i_translation_ok ? i_translated_paddr[31:0] : i_latched_vaddr;

    wire [33:0] d_translated_paddr;
    assign d_translated_paddr = d_tlb_is_megapage ?
        {d_tlb_ppn[21:10], d_latched_vaddr[21:0]} :
        {d_tlb_ppn, d_latched_vaddr[11:0]};

    wire d_translation_ok = d_latched_sv32 && d_tlb_valid && d_tlb_hit &&
                            !d_tlb_perm_fault && !d_tlb_need_ad_update;
    wire d_tlb_miss       = d_latched_sv32 && d_tlb_valid && (!d_tlb_hit || d_tlb_need_ad_update);
    wire d_tlb_pf         = d_latched_sv32 && d_tlb_valid && d_tlb_hit &&
                            d_tlb_perm_fault && !d_tlb_need_ad_update;

    assign d_paddr = !d_latched_sv32 ? d_latched_vaddr :
                     d_translation_ok ? d_translated_paddr[31:0] : d_latched_vaddr;

    // =========================================================================
    // Ready / Miss outputs
    // =========================================================================
    // BUG-11 fix (symmetric): i_ready 仅在翻译真正完成且无 fault 时有效。
    assign i_ready = (i_state == I_LOOKUP) && !i_input_changed
                     && (!i_latched_sv32 || (i_tlb_valid && i_tlb_hit && !i_tlb_perm_fault));
    assign i_miss  = (i_state == I_LOOKUP) && i_latched_sv32 && i_tlb_miss && !i_input_changed;

    // BUG-11 fix: d_ready 仅在翻译真正完成且无 fault 时有效。
    // bare 模式 (!d_latched_sv32) 无需翻译；Sv32 模式必须 hit 且无 perm fault。
    assign d_ready = (d_state == D_LOOKUP) && !d_input_changed && !d_lookup_stalled
                     && (!d_latched_sv32 || (d_tlb_valid && d_tlb_hit && !d_tlb_perm_fault));
    assign d_miss  = (d_state == D_LOOKUP) && d_latched_sv32 && d_tlb_miss && !d_input_changed && !d_lookup_stalled;

    // =========================================================================
    // Page fault (registered, per side)
    // =========================================================================
    // PTW done/fault routed to the correct side
    wire ptw_done_for_d = ptw_walk_done && (walk_state == W_D_WALK);
    wire ptw_done_for_i = ptw_walk_done && (walk_state == W_I_WALK);
    wire ptw_fault_for_d = ptw_walk_fault && (walk_state == W_D_WALK);
    wire ptw_fault_for_i = ptw_walk_fault && (walk_state == W_I_WALK);

    // i-side page fault
    reg i_pf_r;
    reg [3:0] i_pf_cause_r;
    reg [31:0] i_pf_vaddr_r;
    reg i_pf_from_ptw_r;   // BUG-5: distinguish TLB perm fault from PTW walk fault

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            i_pf_r <= 1'b0;
            i_pf_cause_r <= 4'b0;
            i_pf_vaddr_r <= 32'b0;
            i_pf_from_ptw_r <= 1'b0;
        end else begin
            i_pf_r <= 1'b0;
            i_pf_from_ptw_r <= 1'b0;
            if (i_state == I_LOOKUP && i_tlb_pf && !i_input_changed) begin
                i_pf_r <= 1'b1;
                i_pf_from_ptw_r <= 1'b0;   // TLB permission fault
                i_pf_vaddr_r <= i_latched_vaddr;
                case (i_latched_access_type)
                    ACCESS_FETCH: i_pf_cause_r <= 4'd12;
                    ACCESS_LOAD:  i_pf_cause_r <= 4'd13;
                    default:      i_pf_cause_r <= 4'd15;
                endcase
            end else if (ptw_fault_for_i) begin
                i_pf_r <= 1'b1;
                i_pf_from_ptw_r <= 1'b1;   // PTW walk fault
                i_pf_cause_r <= ptw_fault_cause_out;
                i_pf_vaddr_r <= ptw_fault_vaddr_out;
            end
        end
    end

    assign i_page_fault = i_pf_r;
    assign i_pf_cause   = i_pf_r ? i_pf_cause_r : 4'b0;    // BUG-9 fix: always use latched value
    assign i_pf_vaddr   = i_pf_r ? i_pf_vaddr_r : 32'b0;    // BUG-9 fix: always use latched value

    // d-side page fault
    reg d_pf_r;
    reg [3:0] d_pf_cause_r;
    reg [31:0] d_pf_vaddr_r;
    reg d_pf_from_ptw_r;   // BUG-5: distinguish TLB perm fault from PTW walk fault

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d_pf_r <= 1'b0;
            d_pf_cause_r <= 4'b0;
            d_pf_vaddr_r <= 32'b0;
            d_pf_from_ptw_r <= 1'b0;
        end else begin
            d_pf_r <= 1'b0;
            d_pf_from_ptw_r <= 1'b0;
            if (d_state == D_LOOKUP && d_tlb_pf && !d_input_changed) begin
                d_pf_r <= 1'b1;
                d_pf_from_ptw_r <= 1'b0;   // TLB permission fault
                d_pf_vaddr_r <= d_latched_vaddr;
                case (d_latched_access_type)
                    ACCESS_FETCH: d_pf_cause_r <= 4'd12;
                    ACCESS_LOAD:  d_pf_cause_r <= 4'd13;
                    default:      d_pf_cause_r <= 4'd15;
                endcase
            end else if (ptw_fault_for_d) begin
                d_pf_r <= 1'b1;
                d_pf_from_ptw_r <= 1'b1;   // PTW walk fault
                d_pf_cause_r <= ptw_fault_cause_out;
                d_pf_vaddr_r <= ptw_fault_vaddr_out;
            end
        end
    end

    assign d_page_fault = d_pf_r;
    assign d_pf_cause   = d_pf_r ? d_pf_cause_r : 4'b0;    // BUG-9 fix: always use latched value
    assign d_pf_vaddr   = d_pf_r ? d_pf_vaddr_r : 32'b0;    // BUG-9 fix: always use latched value

    // =========================================================================
    // i-side FSM
    // =========================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            i_state              <= I_IDLE;
            i_latched_vaddr      <= 32'b0;
            i_latched_access_type <= ACCESS_FETCH;
            i_latched_priv_mode  <= 2'b0;
            i_latched_satp       <= 32'b0;
            i_latched_translate_en <= 1'b0;
            i_latched_mstatus_sum  <= 1'b0;
            i_latched_mstatus_mxr  <= 1'b0;
        end else begin
            case (i_state)
                I_IDLE: begin
                    if (mmu_flush_req) begin
                        i_state <= I_FLUSH;
                    end else begin
                        i_latched_vaddr       <= i_vaddr;
                        i_latched_access_type <= ACCESS_FETCH;
                        i_latched_priv_mode   <= priv_mode;
                        i_latched_satp        <= satp;
                        i_latched_translate_en <= i_translate_en;
                        i_latched_mstatus_sum  <= mstatus_sum;
                        i_latched_mstatus_mxr  <= mstatus_mxr;
                        i_state <= I_LOOKUP;
                    end
                end

                I_LOOKUP: begin
                    if (mmu_flush_req) begin
                        i_state <= I_FLUSH;
                    end else if (i_input_changed) begin
                        i_state <= I_IDLE;
                    end else if (i_tlb_miss) begin
                        // Miss: signal walk arbiter (handled below)
                        i_state <= I_WALK_PENDING;
                    end
                end

                I_WALK_PENDING: begin
                    if (mmu_flush_req) begin
                        i_state <= I_FLUSH;
                    end else if (ptw_done_for_i) begin
                        // PTW completed for i-side, fill TLB, wait 1 cycle
                        i_state <= I_FILL_WAIT;
                    end else if (ptw_fault_for_i) begin
                        // Page fault from PTW
                        i_state <= I_IDLE;
                    end
                end

                I_FILL_WAIT: begin
                    // TLB fill via Port B has completed. Re-initiate lookup.
                    i_state <= I_IDLE;
                end

                I_FLUSH: begin
                    if (tlb_flush_done) begin
                        i_state <= I_IDLE;
                    end
                end

                default: i_state <= I_IDLE;
            endcase
        end
    end

    // =========================================================================
    // d-side FSM
    // =========================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d_state              <= D_IDLE;
            d_latched_vaddr      <= 32'b0;
            d_latched_access_type <= 2'b0;
            d_latched_priv_mode  <= 2'b0;
            d_latched_satp       <= 32'b0;
            d_latched_translate_en <= 1'b0;
            d_latched_mstatus_sum  <= 1'b0;
            d_latched_mstatus_mxr  <= 1'b0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    if (mmu_flush_req) begin
                        d_state <= D_FLUSH;
                    end else if (d_translate_en) begin    // BUG-13 fix: gate with d_translate_en
                        // Only latch and transition when mem_en=1.
                        // When mem_en=0, stay in D_IDLE — don't latch stale inputs,
                        // don't trigger d_input_changed oscillation.
                        d_latched_vaddr       <= d_vaddr;
                        d_latched_access_type <= d_access_type;
                        d_latched_priv_mode   <= priv_mode;
                        d_latched_satp        <= satp;
                        d_latched_translate_en <= d_translate_en;
                        d_latched_mstatus_sum  <= mstatus_sum;
                        d_latched_mstatus_mxr  <= mstatus_mxr;
                        d_state <= D_LOOKUP;
                    end
                    // else: stay in D_IDLE, don't latch
                end

                D_LOOKUP: begin
                    if (mmu_flush_req) begin
                        d_state <= D_FLUSH;
                    end else if (d_lookup_stalled) begin
                        // Port B is filling (PTW done for other side).
                        // d-side BRAM output is stale — must re-lookup.
                        d_state <= D_IDLE;
                    end else if (d_input_changed) begin
                        d_state <= D_IDLE;
                    end else if (d_tlb_miss) begin
                        // Miss: signal walk arbiter
                        d_state <= D_WALK_PENDING;
                    end
                end

                D_WALK_PENDING: begin
                    if (mmu_flush_req) begin
                        d_state <= D_FLUSH;
                    end else if (ptw_done_for_d) begin
                        d_state <= D_FILL_WAIT;
                    end else if (ptw_fault_for_d) begin
                        d_state <= D_IDLE;
                    end
                end

                D_FILL_WAIT: begin
                    d_state <= D_IDLE;
                end

                D_FLUSH: begin
                    if (tlb_flush_done) begin
                        d_state <= D_IDLE;
                    end
                end

                default: d_state <= D_IDLE;
            endcase
        end
    end

    // =========================================================================
    // sfence.vma completion tracking
    // =========================================================================
    // sfence_done is asserted when both i-side and d-side have returned to
    // IDLE after a sfence_vma-triggered TLB flush.  This allows core_top to
    // sequence: dcache flush → icache inv → TLB flush → resume.
    reg sfence_pending_r;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            sfence_pending_r <= 1'b0;
        else if (sfence_vma && !sfence_pending_r)
            sfence_pending_r <= 1'b1;
        else if (sfence_pending_r && (i_state == I_IDLE) && (d_state == D_IDLE) && !sfence_vma)
            sfence_pending_r <= 1'b0;
    end

    assign sfence_done = sfence_pending_r && (i_state == I_IDLE) && (d_state == D_IDLE);

    // =========================================================================
    // Walk arbiter FSM (manages single PTW instance)
    // =========================================================================
    // Walk request pulses from each side (detected in I_LOOKUP / D_LOOKUP on miss)
    wire i_walk_req = (i_state == I_LOOKUP) && i_tlb_miss && !i_input_changed;
    wire d_walk_req = (d_state == D_LOOKUP) && d_tlb_miss && !d_input_changed && !d_lookup_stalled;
    wire selected_d_walk = pending_d_walk || (!pending_i_walk && d_walk_req);
    wire selected_i_walk = pending_i_walk || (!selected_d_walk && i_walk_req);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            walk_state     <= W_IDLE;
            pending_i_walk <= 1'b0;
            pending_d_walk <= 1'b0;
        end else begin
            case (walk_state)
                W_IDLE: begin
                    if (mmu_flush_req) begin
                        pending_i_walk <= 1'b0;
                        pending_d_walk <= 1'b0;
                    end else if (pending_i_walk) begin
                        // Service pending i-walk (from previous walk completion)
                        walk_state     <= W_I_WALK;
                        pending_i_walk <= 1'b0;
                    end else if (pending_d_walk) begin
                        // Service pending d-walk (from previous walk completion)
                        walk_state     <= W_D_WALK;
                        pending_d_walk <= 1'b0;
                    end else if (d_walk_req) begin
                        walk_state     <= W_D_WALK;
                        pending_i_walk <= i_walk_req;  // capture simultaneous i-miss
                    end else if (i_walk_req) begin
                        walk_state     <= W_I_WALK;
                        pending_d_walk <= d_walk_req;  // capture simultaneous d-miss
                    end
                end

                W_D_WALK: begin
                    if (mmu_flush_req) begin
                        walk_state     <= W_IDLE;
                        pending_i_walk <= 1'b0;
                        pending_d_walk <= 1'b0;
                    end else if (ptw_walk_done || ptw_walk_fault) begin
                        // Go to W_IDLE. If pending_i_walk/pending_d_walk,
                        // W_IDLE will restart PTW on the next cycle.
                        walk_state <= W_IDLE;
                        // BUG-FIX: Capture i_walk_req that arrives in the same
                        // cycle as ptw_walk_done. Without this, the i-walk
                        // request is lost because ptw_walk_done has higher
                        // priority in the if-else chain, and i_state transitions
                        // to I_WALK_PENDING on the next cycle (making
                        // i_walk_req=0). This causes a permanent deadlock.
                        if (i_walk_req && !pending_i_walk)
                            pending_i_walk <= 1'b1;
                    end else if (i_walk_req && !pending_i_walk) begin
                        // i-side miss arrived while d-walk in progress — queue it
                        pending_i_walk <= 1'b1;
                    end
                end

                W_I_WALK: begin
                    if (mmu_flush_req) begin
                        walk_state     <= W_IDLE;
                        pending_i_walk <= 1'b0;
                        pending_d_walk <= 1'b0;
                    end else if (ptw_walk_done || ptw_walk_fault) begin
                        walk_state <= W_IDLE;
                        // BUG-FIX: Same race as W_D_WALK — capture d_walk_req
                        // that arrives simultaneously with ptw_walk_done.
                        if (d_walk_req && !pending_d_walk)
                            pending_d_walk <= 1'b1;
                    end else if (d_walk_req && !pending_d_walk) begin
                        // d-side miss arrived while i-walk in progress — queue it
                        pending_d_walk <= 1'b1;
                    end
                end

                default: walk_state <= W_IDLE;
            endcase
        end
    end

    // =========================================================================
    // PTW instance — single shared walker
    // =========================================================================
    // (ptw_fill_* signals declared above, before TLB instance)

    // PTW inputs: mux based on which side is being serviced
    // BUG-2 fix: use "start" conditions for the startup instant when walk_state
    // is still W_IDLE but the arbiter is about to transition to W_D_WALK/W_I_WALK.
    // During active walk, walk_state is already correct.
    wire start_d_walk = (walk_state == W_IDLE) && selected_d_walk;
    wire start_i_walk = (walk_state == W_IDLE) && !selected_d_walk && selected_i_walk;

    wire active_d_walk = (walk_state == W_D_WALK) || start_d_walk;
    // active_i_walk = !active_d_walk (only two sides)

    wire [31:0] walk_vaddr  = active_d_walk ? d_latched_vaddr  : i_latched_vaddr;
    wire [1:0]  walk_access = active_d_walk ? d_latched_access_type : ACCESS_FETCH;
    wire [1:0]  walk_priv   = active_d_walk ? d_latched_priv_mode  : i_latched_priv_mode;
    wire [31:0] walk_satp   = active_d_walk ? d_latched_satp       : i_latched_satp;
    wire        walk_sum    = active_d_walk ? d_latched_mstatus_sum  : i_latched_mstatus_sum;
    wire        walk_mxr    = active_d_walk ? d_latched_mstatus_mxr  : i_latched_mstatus_mxr;

    // PTW walk_req: pulse when walk arbiter starts a new walk
    // Includes pending_i_walk/pending_d_walk: when W_IDLE services a queued miss, PTW needs restart
    wire ptw_walk_req_pulse = (walk_state == W_IDLE) &&
        (selected_d_walk || selected_i_walk);

    ptw u_ptw(
        .clk(clk),
        .resetn(resetn),
        .satp(walk_satp),
        .priv_mode(walk_priv),
        .mstatus_sum(walk_sum),
        .mstatus_mxr(walk_mxr),
        .access_type(walk_access),
        .walk_vaddr(walk_vaddr),
        .walk_req(ptw_walk_req_pulse),
        .walk_abort(mmu_flush_req),           // BUG-7: abort PTW on sfence_vma or satp change
        .walk_done(ptw_walk_done),
        .walk_fault(ptw_walk_fault),
        .walk_fault_cause(ptw_fault_cause_out),
        .walk_fault_vaddr(ptw_fault_vaddr_out),
        .walk_fault_kind(ptw_fault_kind_out),
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

    assign dbg_i_walk_active  = (walk_state != W_IDLE);
    assign dbg_pending_i_walk = pending_i_walk;
    assign dbg_nb_i_state = {2'b0, i_state};
    assign dbg_nb_i_input_changed = i_input_changed;
    assign dbg_nb_i_latched_vaddr = i_latched_vaddr;
    assign dbg_nb_i_latched_sv32 = i_latched_sv32;
    assign dbg_i_tlb_hit = i_tlb_hit;
    assign dbg_i_tlb_valid = i_tlb_valid;
    assign dbg_i_tlb_perm_fault = i_tlb_perm_fault;
    assign dbg_walk_state = walk_state;

    // ── d-side debug assignments ──
    assign dbg_nb_d_state        = {2'b0, d_state};
    assign dbg_d_tlb_hit         = d_tlb_hit;
    assign dbg_d_tlb_valid       = d_tlb_valid;
    assign dbg_d_tlb_perm_fault  = d_tlb_perm_fault;
    assign dbg_d_input_changed   = d_input_changed;
    assign dbg_d_latched_vaddr   = d_latched_vaddr;
    assign dbg_d_latched_sv32    = d_latched_sv32;
    assign dbg_pending_d_walk    = pending_d_walk;
    assign dbg_d_pf_from_ptw     = d_pf_from_ptw_r;
    assign dbg_d_tlb_miss        = d_tlb_miss;

`endif // USE_TLB_BRAM

endmodule
