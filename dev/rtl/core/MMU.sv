`timescale 1ns / 1ps
`include "cache_def.svh"

module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input              clk,
    input              resetn,

    // ── Unified translation request (CPU-driven handshake) ──
    input              translate_req,       // CPU requests translation (held high until done)
    input       [31:0] translate_vaddr,    // Virtual address to translate
    input       [1:0]  translate_access,   // ACCESS_FETCH/LOAD/STORE
    input       [1:0]  translate_priv,     // Current privilege mode
    input       [31:0] translate_satp,     // Current satp
    input              translate_sum,      // mstatus.SUM
    input              translate_mxr,      // mstatus.MXR

    // ── Translation result ──
    output reg        translate_done,      // Translation complete (1-cycle pulse)
    output reg [31:0] translate_paddr,    // Physical address (valid when done)
    output reg        translate_fault,     // Page fault or access fault
    output reg [3:0]  translate_cause,    // Exception cause code
    output reg [31:0] translate_vaddr_out,// Fault virtual address

    // ── Backward-compatible outputs for icache/dcache ──
    // These are driven from unified translate results; core_top muxes as needed
    output wire [31:0] i_paddr,
    output wire        i_ready,
    output wire        i_miss,
    output wire        i_page_fault,
    output wire [3:0]  i_pf_cause,
    output wire [31:0] i_pf_vaddr,

    output wire [31:0] d_paddr,
    output wire        d_ready,
    output wire        d_miss,
    output wire        d_page_fault,
    output wire [3:0]  d_pf_cause,
    output wire [31:0] d_pf_vaddr,

    // ── CSR inputs (continuous) ──
    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_sum,
    input              mstatus_mxr,

    // ── PTW cache interface (unchanged) ──
    output             ptw_cache_req,
    output      [31:0] ptw_cache_addr,
    input              ptw_cache_ready,
    input       [31:0] ptw_cache_rdata,
    input              ptw_cache_fault,

    // ── PMP (unchanged) ──
    input              pmp_grant,
    input       [1:0]  pmp_fault_type,

    // ── Flush ──
    input              sfence_vma,
    output wire        sfence_done,

    // ── Debug outputs (must exist for core_top compilation) ──
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

    // =========================================================================
    // Constants
    // =========================================================================
    localparam PRIV_M = 2'b11;

    localparam ACCESS_FETCH = 2'b00;
    localparam ACCESS_LOAD  = 2'b01;
    localparam ACCESS_STORE = 2'b10;
    localparam PTW_FAULT_NONE   = 2'd0;
    localparam PTW_FAULT_PAGE   = 2'd1;
    localparam PTW_FAULT_ACCESS = 2'd2;

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
    // Unified translation FSM states
    // =========================================================================
    // Single FSM replaces dual i-side/d-side FSMs + walk arbiter.
    // CPU drives translate_req handshake; MMU blocks until translate_done.
    // i-side and d-side NEVER access TLB simultaneously → no BRAM collision.
    localparam T_IDLE     = 4'd0;
    localparam T_LOOKUP   = 4'd1;
    localparam T_CHECK    = 4'd2;
    localparam T_WALK     = 4'd3;
    localparam T_FILL     = 4'd4;
    localparam T_RELOOKUP = 4'd5;
    localparam T_RECHECK  = 4'd6;
    localparam T_DONE     = 4'd7;
    localparam T_FAULT    = 4'd8;
    localparam T_FLUSH    = 4'd9;

    reg [3:0] t_state;

    // =========================================================================
    // Latched values (single set — no separate i_/d_)
    // =========================================================================
    reg [31:0] latched_vaddr;
    reg [1:0]  latched_access_type;
    reg [1:0]  latched_priv_mode;
    reg [31:0] latched_satp;
    reg        latched_sum;
    reg        latched_mxr;
    wire       latched_sv32 = latched_satp[31] && (latched_priv_mode != PRIV_M);

    // VPN/ASID derived from latched values (stable during translation)
    wire [19:0] latched_vpn  = latched_vaddr[31:12];
    wire [8:0]  latched_asid = latched_satp[30:22];

    // =========================================================================
    // Fault origin tracking (for debug output dbg_d_pf_from_ptw)
    // =========================================================================
    reg fault_from_ptw_r;

    // =========================================================================
    // TLB Port A signals (used for ALL lookups)
    // =========================================================================
    wire        i_tlb_hit, i_tlb_r, i_tlb_w, i_tlb_x, i_tlb_u;
    wire        i_tlb_a, i_tlb_d, i_tlb_g, i_tlb_is_megapage;
    wire [21:0] i_tlb_ppn;
    wire        i_tlb_valid;

    wire        tlb_flush_done;

    // =========================================================================
    // PTW signals
    // =========================================================================
    wire        ptw_walk_done;
    wire        ptw_walk_fault;
    wire [1:0]  ptw_fault_kind_out;
    wire [21:0] ptw_fill_ppn;
    wire        ptw_fill_r, ptw_fill_w, ptw_fill_x, ptw_fill_u;
    wire        ptw_fill_a, ptw_fill_d, ptw_fill_g;
    wire        ptw_fill_is_megapage;
    wire [3:0]  ptw_fault_cause_out;
    wire [31:0] ptw_fault_vaddr_out;

    // =========================================================================
    // TLB Port A lookup request
    // =========================================================================
    // Issued in T_LOOKUP and T_RELOOKUP; BRAM has 1-cycle read latency,
    // so output is valid in T_CHECK / T_RECHECK respectively.
    wire tlb_lookup_req = (t_state == T_LOOKUP || t_state == T_RELOOKUP) && !mmu_flush_req;

    // =========================================================================
    // TLB fill request (1 cycle in T_FILL, uses Port B write)
    // =========================================================================
    wire tlb_fill_req = (t_state == T_FILL);

    // Fill VPN/ASID from latched values (no walk_state mux needed)
    wire [19:0] fill_vpn  = latched_vaddr[31:12];
    wire [8:0]  fill_asid = latched_satp[30:22];

    // =========================================================================
    // TLB instance (dual-port BRAM)
    // Port A: ALL lookups (unified, never simultaneous i/d)
    // Port B: fill only (d_lookup_req = 0 always)
    // =========================================================================
    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb(
        .clk(clk),
        .resetn(resetn),
        // Port A: unified lookup
        .i_lookup_vpn(latched_vpn),
        .i_lookup_asid(latched_asid),
        .i_lookup_req(tlb_lookup_req),
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
        // Port B: NEVER used for lookup — only fill uses Port B write
        .d_lookup_vpn(20'b0),
        .d_lookup_asid(9'b0),
        .d_lookup_req(1'b0),
        .d_lookup_hit(),
        .d_lookup_ppn(),
        .d_lookup_r(),
        .d_lookup_w(),
        .d_lookup_x(),
        .d_lookup_u(),
        .d_lookup_a(),
        .d_lookup_d(),
        .d_lookup_g(),
        .d_lookup_is_megapage(),
        .d_lookup_valid(),
        // Fill (Port B write, preempts d-lookup — but d_lookup_req=0 so no conflict)
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
    // Permission check (using latched values + TLB Port A outputs)
    // =========================================================================
    wire tlb_perm_fault =
        (latched_priv_mode == 2'b00 && !i_tlb_u) ? 1'b1 :              // U-mode access to non-U page
        (latched_priv_mode == 2'b01 && i_tlb_u &&
         (latched_access_type == ACCESS_FETCH || !latched_sum)) ? 1'b1 : // S-mode access to U page
        (latched_access_type == ACCESS_FETCH && !i_tlb_x) ? 1'b1 :      // fetch from non-X page
        (latched_access_type == ACCESS_LOAD && !i_tlb_r && !(i_tlb_x && latched_mxr)) ? 1'b1 : // load, MXR
        (latched_access_type == ACCESS_STORE && !i_tlb_w) ? 1'b1 :      // store to non-W page
        1'b0;

    // =========================================================================
    // A/D bit check — trap to software as page fault
    // =========================================================================
    // RISC-V spec: if A=0 or (store && D=0), implementation may trap to software.
    wire tlb_need_ad_update = latched_sv32 && i_tlb_valid && i_tlb_hit &&
                             (!i_tlb_a || (latched_access_type == ACCESS_STORE && !i_tlb_d));

    // =========================================================================
    // Physical address computation (megapage handling)
    // =========================================================================
    wire [33:0] translated_paddr = i_tlb_is_megapage ?
        {i_tlb_ppn[21:10], latched_vaddr[21:0]} :
        {i_tlb_ppn, latched_vaddr[11:0]};

    // =========================================================================
    // Permission fault cause code (based on access type)
    // =========================================================================
    wire [3:0] perm_fault_cause =
        (latched_access_type == ACCESS_FETCH) ? 4'd12 :
        (latched_access_type == ACCESS_LOAD)  ? 4'd13 : 4'd15;

    // =========================================================================
    // PTW walk_req pulse — asserted when T_CHECK detects TLB miss
    // =========================================================================
    // High for exactly 1 cycle (when t_state == T_CHECK && miss).
    // PTW sees walk_req on the next rising edge and starts the walk.
    // By then, t_state has transitioned to T_WALK.
    wire ptw_walk_req_pulse = (t_state == T_CHECK) && latched_sv32 && i_tlb_valid && !i_tlb_hit;

    // =========================================================================
    // PTW instance — single shared walker (unchanged interface)
    // =========================================================================
    // Inputs from latched values directly (no arbiter mux needed).
    // walk_abort on mmu_flush_req (sfence_vma or satp_changed).
    ptw u_ptw(
        .clk(clk),
        .resetn(resetn),
        .satp(latched_satp),
        .priv_mode(latched_priv_mode),
        .mstatus_sum(latched_sum),
        .mstatus_mxr(latched_mxr),
        .access_type(latched_access_type),
        .walk_vaddr(latched_vaddr),
        .walk_req(ptw_walk_req_pulse),
        .walk_abort(mmu_flush_req),
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
        .ptw_cache_req(ptw_cache_req),
        .ptw_cache_addr(ptw_cache_addr),
        .ptw_cache_ready(ptw_cache_ready),
        .ptw_cache_rdata(ptw_cache_rdata),
        .ptw_cache_fault(ptw_cache_fault),
        .pmp_grant(pmp_grant),
        .pmp_fault_type(pmp_fault_type)
    );

    // =========================================================================
    // Unified translation FSM
    // =========================================================================
    // T_IDLE   : Wait for translate_req or mmu_flush_req
    // T_LOOKUP : Issue TLB Port A read (BRAM 1-cycle latency)
    // T_CHECK  : TLB output valid — decide hit/miss/fault
    // T_WALK   : PTW walking page tables
    // T_FILL   : Write filled PTE into TLB via Port B (1 cycle)
    // T_RELOOKUP: Re-issue TLB Port A read after fill
    // T_RECHECK : Check re-lookup result (should hit after fill)
    // T_DONE   : Translation successful — translate_done pulse (1 cycle)
    // T_FAULT  : Translation fault — translate_done + translate_fault pulse (1 cycle)
    // T_FLUSH  : TLB flush in progress — wait for tlb_flush_done
    //
    // Timing: translate_done is set on the edge that enters T_DONE/T_FAULT,
    // so it is high for exactly 1 cycle while the FSM is in T_DONE/T_FAULT.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            t_state              <= T_IDLE;
            latched_vaddr        <= 32'b0;
            latched_access_type  <= 2'b0;
            latched_priv_mode    <= 2'b0;
            latched_satp         <= 32'b0;
            latched_sum          <= 1'b0;
            latched_mxr          <= 1'b0;
            fault_from_ptw_r     <= 1'b0;
            translate_done       <= 1'b0;
            translate_fault      <= 1'b0;
            translate_paddr      <= 32'b0;
            translate_cause      <= 4'b0;
            translate_vaddr_out  <= 32'b0;
        end else begin
            // Default: translate_done/fault are 1-cycle pulses
            translate_done  <= 1'b0;
            translate_fault <= 1'b0;

            case (t_state)
                // ── T_IDLE: Accept new request or flush ──
                T_IDLE: begin
                    if (mmu_flush_req) begin
                        t_state <= T_FLUSH;
                    end else if (translate_req) begin
                        latched_vaddr       <= translate_vaddr;
                        latched_access_type <= translate_access;
                        latched_priv_mode   <= translate_priv;
                        latched_satp        <= translate_satp;
                        latched_sum         <= translate_sum;
                        latched_mxr         <= translate_mxr;
                        t_state             <= T_LOOKUP;
                    end
                end

                // ── T_LOOKUP: TLB BRAM read request issued combinationally ──
                T_LOOKUP: begin
                    if (mmu_flush_req) begin
                        t_state <= T_FLUSH;
                    end else begin
                        // tlb_lookup_req=1 this cycle → BRAM output valid next cycle
                        t_state <= T_CHECK;
                    end
                end

                // ── T_CHECK: TLB output valid, make decision ──
                T_CHECK: begin
                    if (mmu_flush_req) begin
                        t_state <= T_FLUSH;
                    end else if (!latched_sv32) begin
                        // Bare mode — no translation needed
                        translate_done   <= 1'b1;
                        translate_paddr  <= latched_vaddr;
                        fault_from_ptw_r <= 1'b0;
                        t_state <= T_DONE;
                    end else if (i_tlb_valid) begin
                        if (i_tlb_hit && !tlb_perm_fault && !tlb_need_ad_update) begin
                            // TLB hit, no permission fault, no A/D update needed
                            translate_done   <= 1'b1;
                            translate_paddr  <= translated_paddr[31:0];
                            fault_from_ptw_r <= 1'b0;
                            t_state <= T_DONE;
                        end else if (i_tlb_hit && tlb_perm_fault) begin
                            // TLB hit but permission fault
                            translate_done     <= 1'b1;
                            translate_fault    <= 1'b1;
                            translate_cause    <= perm_fault_cause;
                            translate_vaddr_out <= latched_vaddr;
                            fault_from_ptw_r  <= 1'b0;
                            t_state <= T_FAULT;
                        end else if (i_tlb_hit && tlb_need_ad_update) begin
                            // A/D bit needs update — trap to software as page fault
                            translate_done     <= 1'b1;
                            translate_fault    <= 1'b1;
                            translate_cause    <= perm_fault_cause;
                            translate_vaddr_out <= latched_vaddr;
                            fault_from_ptw_r  <= 1'b0;
                            t_state <= T_FAULT;
                        end else begin
                            // TLB miss — start PTW walk
                            t_state <= T_WALK;
                        end
                    end
                    // else: i_tlb_valid not yet asserted, wait in T_CHECK
                end

                // ── T_WALK: PTW walking page tables ──
                T_WALK: begin
                    if (mmu_flush_req) begin
                        // PTW will be aborted via walk_abort=mmu_flush_req
                        t_state <= T_FLUSH;
                    end else if (ptw_walk_done) begin
                        // Walk completed successfully — fill TLB
                        t_state <= T_FILL;
                    end else if (ptw_walk_fault) begin
                        // Walk fault (page fault or access fault from PTW)
                        translate_done     <= 1'b1;
                        translate_fault    <= 1'b1;
                        translate_cause    <= ptw_fault_cause_out;
                        translate_vaddr_out <= ptw_fault_vaddr_out;
                        fault_from_ptw_r  <= 1'b1;
                        t_state <= T_FAULT;
                    end
                end

                // ── T_FILL: Write filled PTE into TLB via Port B (1 cycle) ──
                T_FILL: begin
                    // tlb_fill_req=1 this cycle (combinational from t_state)
                    if (mmu_flush_req) begin
                        // Skip fill — TLB is being flushed anyway
                        t_state <= T_FLUSH;
                    end else begin
                        t_state <= T_RELOOKUP;
                    end
                end

                // ── T_RELOOKUP: Re-issue TLB Port A read after fill ──
                T_RELOOKUP: begin
                    if (mmu_flush_req) begin
                        t_state <= T_FLUSH;
                    end else begin
                        // tlb_lookup_req=1 this cycle → BRAM output valid next cycle
                        t_state <= T_RECHECK;
                    end
                end

                // ── T_RECHECK: Check re-lookup result (should hit after fill) ──
                T_RECHECK: begin
                    if (mmu_flush_req) begin
                        t_state <= T_FLUSH;
                    end else if (i_tlb_valid) begin
                        if (i_tlb_hit && !tlb_perm_fault && !tlb_need_ad_update) begin
                            // Hit after fill — translation complete
                            translate_done   <= 1'b1;
                            translate_paddr  <= translated_paddr[31:0];
                            fault_from_ptw_r <= 1'b0;
                            t_state <= T_DONE;
                        end else if (i_tlb_hit && tlb_perm_fault) begin
                            // Permission fault after fill
                            translate_done     <= 1'b1;
                            translate_fault    <= 1'b1;
                            translate_cause    <= perm_fault_cause;
                            translate_vaddr_out <= latched_vaddr;
                            fault_from_ptw_r  <= 1'b0;
                            t_state <= T_FAULT;
                        end else if (i_tlb_hit && tlb_need_ad_update) begin
                            // A/D bit fault after fill — trap to software
                            translate_done     <= 1'b1;
                            translate_fault    <= 1'b1;
                            translate_cause    <= perm_fault_cause;
                            translate_vaddr_out <= latched_vaddr;
                            fault_from_ptw_r  <= 1'b0;
                            t_state <= T_FAULT;
                        end else begin
                            // Miss after fill — should not happen (filled entry
                            // must be found). Treat as fault for robustness.
                            translate_done     <= 1'b1;
                            translate_fault    <= 1'b1;
                            translate_cause    <= perm_fault_cause;
                            translate_vaddr_out <= latched_vaddr;
                            fault_from_ptw_r  <= 1'b0;
                            t_state <= T_FAULT;
                        end
                    end
                    // else: i_tlb_valid not yet asserted, wait in T_RECHECK
                end

                // ── T_DONE: Translation successful (1-cycle pulse) ──
                T_DONE: begin
                    // translate_done was set on the edge entering T_DONE,
                    // so it is high for this 1 cycle. Return to IDLE.
                    t_state <= T_IDLE;
                end

                // ── T_FAULT: Translation fault (1-cycle pulse) ──
                T_FAULT: begin
                    // translate_done + translate_fault were set on the edge
                    // entering T_FAULT, so they are high for this 1 cycle.
                    t_state <= T_IDLE;
                end

                // ── T_FLUSH: TLB flush in progress ──
                T_FLUSH: begin
                    if (tlb_flush_done) begin
                        t_state <= T_IDLE;
                    end
                end

                default: t_state <= T_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Backward-compatible outputs for icache/dcache
    // =========================================================================
    // In the unified MMU, i-side and d-side are not distinguished.
    // Core_top muxes these based on which side is active.
    // Default wiring: all outputs reflect the unified translate result.
    assign i_paddr       = translate_paddr;
    assign i_ready       = translate_done && !translate_fault;
    assign i_miss        = 1'b0;   // No autonomous miss signaling in unified MMU
    assign i_page_fault  = translate_fault;
    assign i_pf_cause    = translate_cause;
    assign i_pf_vaddr    = translate_vaddr_out;

    assign d_paddr       = translate_paddr;
    assign d_ready       = translate_done && !translate_fault;
    assign d_miss        = 1'b0;   // No autonomous miss signaling in unified MMU
    assign d_page_fault  = translate_fault;
    assign d_pf_cause    = translate_cause;
    assign d_pf_vaddr    = translate_vaddr_out;

    // =========================================================================
    // sfence.vma completion tracking
    // =========================================================================
    // sfence_done is asserted when T_FLUSH completes due to an sfence_vma.
    // Only tracks sfence_vma (not satp_changed) — matches original behavior.
    reg sfence_pending_r;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            sfence_pending_r <= 1'b0;
        else if (sfence_vma && !sfence_pending_r)
            sfence_pending_r <= 1'b1;
        else if (sfence_pending_r && (t_state == T_FLUSH) && tlb_flush_done)
            sfence_pending_r <= 1'b0;
    end

    assign sfence_done = sfence_pending_r && (t_state == T_FLUSH) && tlb_flush_done;

    // =========================================================================
    // Debug outputs (simplified but valid for core_top compilation)
    // =========================================================================
    assign dbg_i_walk_active     = (t_state == T_WALK);
    assign dbg_pending_i_walk    = 1'b0;    // No pending walks in unified FSM
    assign dbg_nb_i_state        = t_state[2:0];
    assign dbg_nb_i_input_changed = 1'b0;   // No input change detection in unified FSM
    assign dbg_nb_i_latched_vaddr = latched_vaddr;
    assign dbg_nb_i_latched_sv32  = latched_sv32;
    assign dbg_i_tlb_hit         = i_tlb_hit;
    assign dbg_i_tlb_valid       = i_tlb_valid;
    assign dbg_i_tlb_perm_fault  = tlb_perm_fault;
    assign dbg_walk_state        = (t_state == T_WALK) ? 2'd1 : 2'd0;

    assign dbg_nb_d_state        = t_state[2:0];
    assign dbg_d_tlb_hit         = i_tlb_hit;
    assign dbg_d_tlb_valid       = i_tlb_valid;
    assign dbg_d_tlb_perm_fault  = tlb_perm_fault;
    assign dbg_d_input_changed   = 1'b0;    // No input change detection
    assign dbg_d_latched_vaddr   = latched_vaddr;
    assign dbg_d_latched_sv32    = latched_sv32;
    assign dbg_pending_d_walk    = 1'b0;    // No pending walks
    assign dbg_d_pf_from_ptw     = fault_from_ptw_r;
    assign dbg_d_tlb_miss        = latched_sv32 && i_tlb_valid && !i_tlb_hit;

`endif // USE_TLB_BRAM

endmodule
