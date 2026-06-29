`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "cache_def.svh"

module dcache_ctrl(
    input  wire        clk,
    input  wire        resetn,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    input  wire [31:0] cpu_req_vaddr,
    input  wire        mmu_ready,
    input  wire [31:0] cpu_req_wdata,
    input  wire        cpu_req_hwrite,
    input  wire [2:0]  cpu_req_hsize,
    output wire [31:0] cpu_req_rdata,
    output wire        cpu_req_ready,

    // PTW request port (priority over CPU requests)
    input  wire        ptw_req_valid,
    input  wire [31:0] ptw_req_addr,
    input  wire [31:0] ptw_req_vaddr,
    output wire        ptw_req_ready,
    output wire [31:0] ptw_req_rdata,
    output wire        ptw_req_fault,

    output wire        mmio_req,
    input  wire        mmio_accept,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire        mmio_hwrite,
    output wire [2:0]  mmio_hsize,
    input  wire [31:0] mmio_rdata,
    input  wire        mmio_valid,

    output wire        refill_req,
    output wire [31:0] refill_addr,
    input  wire [`DCACHE_LINE_WIDTH-1:0] refill_data,
    input  wire        refill_valid,
    input  wire        refill_done,
    input  wire        refill_error,

    output wire        wb_req,
    output wire [31:0] wb_addr,
    output wire [`DCACHE_LINE_WIDTH-1:0] wb_data,
    input  wire        wb_valid,
    input  wire        wb_done,
    input  wire        wb_error,

    input  wire        flush_req,
    output wire        flush_done,

    // Single-line invalidation (for PTW A/D bit writeback coherency)
    input  wire        inv_line_req,
    input  wire [31:0] inv_line_addr,
    output wire        inv_line_done,
    output wire        dbg_watch_lh_valid,
    output wire [31:0] dbg_watch_lh_data,
    output wire [31:0] dbg_watch_lh_count,
    output wire        dbg_watch_rf_valid,
    output wire [31:0] dbg_watch_rf_data,
    output wire [31:0] dbg_watch_rf_count,
    output wire        dbg_watch_wb_valid,
    output wire [31:0] dbg_watch_wb_data,
    output wire [31:0] dbg_watch_wb_count,

    input  wire        amo_abort          // cancel in-progress AMO write on trap
);

    // --- Cache geometry from config ---
    localparam NUM_SETS      = `DCACHE_NUM_SETS;
    localparam NUM_WAYS      = `DCACHE_NUM_WAYS;
    localparam TAG_WIDTH     = `DCACHE_TAG_WIDTH;
    localparam LINE_WIDTH    = `DCACHE_LINE_WIDTH;
    localparam BRAM_ADDR_W   = `DCACHE_ADDR_WIDTH;
    localparam WEA_WIDTH     = `DCACHE_WEA_WIDTH;
    localparam TAG_ENTRY_W   = `DCACHE_TAG_ENTRY_WIDTH;
    localparam SET_IDX_W     = `DCACHE_SET_IDX_WIDTH;
    localparam WAY_W         = `DCACHE_WAY_WIDTH;
    localparam TAG_BRAM_W    = `DCACHE_TAG_BRAM_WIDTH;
    localparam TAG_BRAM_WEA  = `DCACHE_TAG_BRAM_WEA_WIDTH;
    localparam TAG_BRAM_BS   = `DCACHE_TAG_BRAM_BYTE_SIZE;
    localparam TAG_BRAM_BPW  = `DCACHE_TAG_BRAM_WEA_BITS_PER_WAY;
    // Derived: address layout
    localparam ADDR_UPPER_ZEROS = 30 - `DCACHE_TAG_HI;
    localparam ADDR_LOWER_ZEROS = `DCACHE_SET_IDX_LO;
`ifdef SIMULATION
    localparam [31:0] DBG_WATCH_LINE_ADDR = 32'h8000_21E0;
`else
    localparam [31:0] DBG_WATCH_LINE_ADDR = 32'h807B_21E0;
`endif
    localparam integer DBG_WATCH_WORD_OFF = 7;

    // 状态机状态
    // =========================================================================
    // dcache FSM states (entry / exit / duration)
    // =========================================================================
    // S_IDLE             : Entry: reset (via S_RST_CLEAR), or any completing
    //                      state (S_TAG_READ/S_READ_HIT/S_REFILL/S_WB_SEND/
    //                      S_INV_LINE_WRITE/S_FLUSH_INVALIDATE).
    //                      Exit : flush_req → S_FLUSH_SCAN;
    //                             inv_line_req → S_INV_LINE;
    //                             ptw_req_valid → S_TAG_READ (priority);
    //                             cpu_req_valid + mmu_ready + !is_mmio → S_TAG_READ;
    //                             cpu_req_valid + is_mmio → MMIO bypass (stay).
    //                      Duration: 1 cycle (waits for request).
    //
    // S_TAG_READ         : Entry: S_IDLE on cacheable CPU or PTW request.
    //                      Exit : store hit → S_IDLE (write data+tag, ready);
    //                             load hit → S_READ_HIT;
    //                             miss + victim dirty → S_WB_READ;
    //                             miss + victim clean → S_REFILL.
    //                      Duration: 1 cycle. Tag BRAM Port A output valid.
    //
    // S_READ_HIT         : Entry: S_TAG_READ on load hit (CPU or PTW).
    //                      Exit : → S_IDLE (returns hit data, updates PLRU).
    //                      Duration: 1 cycle. Data BRAM Port A output valid.
    //
    // S_WB_READ          : Entry: S_TAG_READ on miss with dirty victim.
    //                      Exit : → S_WB_SEND (latches writeback address).
    //                      Duration: 1 cycle. Data BRAM Port B read for WB.
    //
    // S_WB_SEND          : Entry: S_WB_READ (asserts wb_req).
    //                      Exit : wb_done + wb_error → S_IDLE;
    //                             wb_done + !wb_error → S_REFILL (clears
    //                             dirty bit, issues refill for new line).
    //                      Duration: variable (AXI write burst latency).
    //
    // S_REFILL           : Entry: S_TAG_READ on clean miss, or S_WB_SEND
    //                      after successful writeback.
    //                      Exit : refill_done + refill_error → S_IDLE
    //                             (PTW: fault; CPU: silent drop);
    //                             refill_done + !refill_error → S_IDLE
    //                             (writes tag+data, returns refill word).
    //                      Duration: variable (AXI read burst latency).
    //
    // S_FLUSH_SCAN       : Entry: S_IDLE on flush_req.
    //                      Exit : → S_FLUSH_CHECK (tag BRAM Port A read).
    //                      Duration: 1 cycle per set/way scan step.
    //
    // S_FLUSH_CHECK      : Entry: S_FLUSH_SCAN (tag BRAM output valid).
    //                      Exit : valid+dirty → S_FLUSH_WB_RD;
    //                             not dirty, more ways → stay (next way);
    //                             not dirty, last way, more sets → S_FLUSH_SCAN;
    //                             not dirty, last way, last set → S_FLUSH_INVALIDATE.
    //                      Duration: 1 cycle per way (BRAM output held).
    //
    // S_FLUSH_WB_RD      : Entry: S_FLUSH_CHECK on valid+dirty line.
    //                      Exit : → S_FLUSH_WB_SD (latches WB address).
    //                      Duration: 1 cycle. Data BRAM Port B read.
    //
    // S_FLUSH_WB_SD      : Entry: S_FLUSH_WB_RD (asserts wb_req).
    //                      Exit : wb_done + wb_error → S_INV_LINE
    //                             (drop faulting line, set flush_error_seen_r);
    //                             wb_done + !wb_error → S_FLUSH_WB_WAIT
    //                             (clears dirty, advances flush_set/flush_way).
    //                      Duration: variable (AXI write burst latency).
    //
    // S_FLUSH_INVALIDATE : Entry: S_FLUSH_CHECK (all scanned) or
    //                      S_FLUSH_WB_WAIT (flush_resume_invalidate_r).
    //                      Exit : invalidate_set == NUM_SETS-1 → S_IDLE
    //                             (flush_done_r pulse, clears PLRU).
    //                      Duration: NUM_SETS cycles. Zero-writes all tag
    //                      BRAM sets (clears all valid bits).
    //
    // S_INV_LINE         : Entry: S_IDLE on inv_line_req (PTW A/D coherency),
    //                      or S_FLUSH_WB_SD on wb_error (flush error recovery).
    //                      Exit : → S_INV_LINE_WRITE (tag BRAM Port A read).
    //                      Duration: 1 cycle.
    //
    // S_INV_LINE_WRITE   : Entry: S_INV_LINE (tag BRAM output valid).
    //                      Exit : flush_error_seen_r → S_FLUSH_WB_WAIT
    //                             (ISSUE-1: resume scanning past faulting line);
    //                             normal → S_IDLE (inv_line_done_r pulse).
    //                      Duration: 1 cycle. Clears V bit on matching way(s).
    //
    // S_FLUSH_WB_WAIT    : Entry: S_FLUSH_WB_SD (success path) or
    //                      S_INV_LINE_WRITE (error recovery path).
    //                      Exit : flush_resume_invalidate_r → S_FLUSH_INVALIDATE;
    //                             else → S_FLUSH_SCAN.
    //                      Duration: 1 cycle. Defers next Port A read so the
    //                      Port B tag write commits without BRAM collision.
    //
    // S_RST_CLEAR        : Entry: reset (ISSUE-4: tag BRAM undefined at reset).
    //                      Exit : invalidate_set == NUM_SETS-1 → S_IDLE.
    //                      Duration: NUM_SETS cycles. Zero-writes all tag BRAM
    //                      sets before accepting any CPU/PTW request.
    //
    localparam S_IDLE             = 4'd0;
    localparam S_TAG_READ         = 4'd1;
    localparam S_READ_HIT         = 4'd2;
    localparam S_WB_READ          = 4'd3;
    localparam S_WB_SEND          = 4'd4;
    localparam S_REFILL           = 4'd5;
    localparam S_FLUSH_SCAN       = 4'd6;
    localparam S_FLUSH_CHECK      = 4'd7;
    localparam S_FLUSH_WB_RD      = 4'd8;
    localparam S_FLUSH_WB_SD      = 4'd9;
    localparam S_FLUSH_INVALIDATE = 4'd10;
    localparam S_INV_LINE         = 4'd11;
    localparam S_INV_LINE_WRITE   = 4'd12;
    localparam S_FLUSH_WB_WAIT    = 4'd13;
    localparam S_RST_CLEAR        = 4'd14;  // ISSUE-4: reset-time tag BRAM clear (X-propagation fix)
    localparam S_DONE             = 4'd15;  // ready/done 脉冲缓冲态：消除 S_IDLE 残留

    // Address map (same as icache):
    //   0x00000000-0x7FFFFFFF: MMIO (peripherals)     — bit[31]=0
    //   0x80000000-0x87FFFFFF: Cacheable (DDR3, 128MB) — bit[31]=1, bit[30]=0, bits[29:27]=0
    //   0x88000000-0xBFFFFFFF: Unmapped (no physical memory; tag aliasing risk if accessed)
    //   0xC0000000-0xFFFFFFFF: MMIO (boot ROM, etc.)  — bit[31]=1, bit[30]=1
    // Tag width (19 bits) covers exactly 128MB; bits[29:27] are forced zero
    // in refill/writeback addresses (ADDR_UPPER_ZEROS=4).
    //
    // BUG-FIX: MMIO judgment must be based on PHYSICAL address, not virtual address.
    // When Sv32 translation is active, a virtual address in the cacheable range
    // could map to an MMIO physical address (or vice versa). The is_mmio signal
    // is only consumed after mmu_ready is asserted (paddr valid).
    wire is_mmio = ~cpu_req_addr[31] | cpu_req_addr[30];

    // PIPT: use paddr for both set index and tag
    wire [TAG_WIDTH-1:0]   req_tag  = cpu_req_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
    wire [SET_IDX_W-1:0]   set_idx  = cpu_req_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
    wire [SET_IDX_W-1:0]   word_off = cpu_req_addr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];

    // PTW address decomposition (PIPT: paddr for both set index and tag)
    wire                  ptw_req_is_mmio = ~ptw_req_addr[31] | ptw_req_addr[30];
    wire [TAG_WIDTH-1:0]  ptw_req_tag     = ptw_req_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
    wire [SET_IDX_W-1:0]  ptw_set_idx     = ptw_req_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
    wire [SET_IDX_W-1:0]  ptw_word_off    = ptw_req_addr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];

    reg [3:0] state; // 状态机

    // --- PLRU state (kept as registers — too small for BRAM) ---
    reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

    // =========================================================================
    // Tag BRAM (dcachet) — 144-bit × 8 deep, Byte_Size=36, 4-bit WEA
    // Each address = 1 set, data = 4 ways packed: {Way3, Way2, Way1, Way0}
    //   Way N bits: [N*36 +: 36] = {15'b0, V(1), D(1), tag(19)}
    // =========================================================================
    wire [TAG_BRAM_W-1:0] tag_bram_douta;
    wire [TAG_BRAM_W-1:0] tag_bram_doutb;

    // Port A: CPU read / PTW read / Flush scan read
    // BUG-FIX: Gate S_IDLE term with mmu_ready because is_mmio now depends on
    // physical address, which is only valid when mmu_ready=1.
    // PTW has priority over CPU; PTW addresses are always physical (no mmu_ready needed).
    wire tag_bram_ena = ((state == S_IDLE) && ptw_req_valid && !ptw_req_ready_r && !ptw_req_is_mmio) ||
                        ((state == S_IDLE) && !ptw_req_valid && cpu_req_valid && !cpu_req_ready_r && mmu_ready && !is_mmio) ||
                        (state == S_FLUSH_SCAN) ||
                        (state == S_INV_LINE) ||
                        (state == S_INV_LINE_WRITE);
    wire [SET_IDX_W-1:0] tag_bram_addra = (state == S_FLUSH_SCAN) ? flush_set :
                                           (state == S_INV_LINE || state == S_INV_LINE_WRITE) ? inv_latched_set :
                                           ((state == S_IDLE) && ptw_req_valid && !ptw_req_is_mmio) ? ptw_set_idx : set_idx;

    // Port B: Refill write / Dirty update / Invalidate write (registered)
    reg                          tag_bram_enb_r;
    reg [TAG_BRAM_WEA-1:0]      tag_bram_web_r;
    reg [SET_IDX_W-1:0]         tag_bram_addrb_r;
    reg [TAG_BRAM_W-1:0]        tag_bram_dinb_r;

    dcachet u_dcachet(
        .clka   (clk),
        .ena    (tag_bram_ena),
        .wea    ({TAG_BRAM_WEA{1'b0}}),      // Port A: read only
        .addra  (tag_bram_addra),              // set_idx or flush_set
        .dina   ({TAG_BRAM_W{1'b0}}),
        .douta  (tag_bram_douta),

        .clkb   (clk),
        .enb    (tag_bram_enb_r),
        .web    (tag_bram_web_r),
        .addrb  (tag_bram_addrb_r),
        .dinb   (tag_bram_dinb_r),
        .doutb  (tag_bram_doutb)
    );

    // --- Tag comparison from BRAM Port A output (valid in S_TAG_READ / S_FLUSH_CHECK) ---
    // Two-step extraction: BRAM is organized in TAG_BRAM_BS-byte slots (36 bits),
    // but each way's tag entry is only TAG_ENTRY_W bits (21 bits: V+D+tag).
    // First extract the full BRAM byte slot, then slice the tag entry from it.
    wire [TAG_BRAM_BS-1:0] way0_raw = tag_bram_douta[TAG_BRAM_BS*1-1:TAG_BRAM_BS*0];
    wire [TAG_BRAM_BS-1:0] way1_raw = tag_bram_douta[TAG_BRAM_BS*2-1:TAG_BRAM_BS*1];
    wire [TAG_BRAM_BS-1:0] way2_raw = tag_bram_douta[TAG_BRAM_BS*3-1:TAG_BRAM_BS*2];
    wire [TAG_BRAM_BS-1:0] way3_raw = tag_bram_douta[TAG_BRAM_BS*4-1:TAG_BRAM_BS*3];
    wire [TAG_ENTRY_W-1:0] tag_r0 = way0_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r1 = way1_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r2 = way2_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r3 = way3_raw[TAG_ENTRY_W-1:0];

    // Tag entry layout: [TAG_ENTRY_W-1]=V, [TAG_ENTRY_W-2]=D, [TAG_WIDTH-1:0]=tag
    wire hit0 = tag_r0[TAG_ENTRY_W-1] && (tag_r0[TAG_WIDTH-1:0] == active_req_tag);
    wire hit1 = tag_r1[TAG_ENTRY_W-1] && (tag_r1[TAG_WIDTH-1:0] == active_req_tag);
    wire hit2 = tag_r2[TAG_ENTRY_W-1] && (tag_r2[TAG_WIDTH-1:0] == active_req_tag);
    wire hit3 = tag_r3[TAG_ENTRY_W-1] && (tag_r3[TAG_WIDTH-1:0] == active_req_tag);

    wire cache_hit = hit0 | hit1 | hit2 | hit3;

    wire [WAY_W-1:0] hit_way;
    assign hit_way = hit0 ? {WAY_W{1'b0}} :
                     hit1 ? {{(WAY_W-1){1'b0}}, 1'b1} :
                     hit2 ? {{(WAY_W-2){1'b0}}, 2'b10} :
                            {{(WAY_W-2){1'b0}}, 2'b11};

    wire inv0 = ~tag_r0[TAG_ENTRY_W-1];
    wire inv1 = ~tag_r1[TAG_ENTRY_W-1];
    wire inv2 = ~tag_r2[TAG_ENTRY_W-1];
    wire inv3 = ~tag_r3[TAG_ENTRY_W-1];

    // Invalidate-line hit detection (for PTW A/D bit coherency)
    // Matches any valid way whose tag equals inv_latched_tag
    wire inv_hit0 = tag_r0[TAG_ENTRY_W-1] && (tag_r0[TAG_WIDTH-1:0] == inv_latched_tag);
    wire inv_hit1 = tag_r1[TAG_ENTRY_W-1] && (tag_r1[TAG_WIDTH-1:0] == inv_latched_tag);
    wire inv_hit2 = tag_r2[TAG_ENTRY_W-1] && (tag_r2[TAG_WIDTH-1:0] == inv_latched_tag);
    wire inv_hit3 = tag_r3[TAG_ENTRY_W-1] && (tag_r3[TAG_WIDTH-1:0] == inv_latched_tag);

    reg [SET_IDX_W-1:0]  latched_set;
    reg [WAY_W-1:0]      latched_victim_way;
    reg [31:0] latched_addr;
    reg [31:0] latched_wdata;
    reg        latched_hwrite;
    reg [2:0]  latched_hsize;
    reg [SET_IDX_W-1:0]  latched_word_off;
    reg [TAG_WIDTH-1:0]  latched_tag;
    reg [TAG_WIDTH-1:0]  latched_victim_tag;  // victim's tag for writeback addr
    reg        is_ptw_req_r;             // 1 = current request is from PTW
    reg [31:0] latched_ptw_addr;         // Latched PTW physical address
    reg [31:0] latched_ptw_vaddr;        // Latched PTW virtual address (port preserved for compatibility)

    // Active request signals (muxed between CPU and PTW based on is_ptw_req_r)
    // Must be declared before tree_plru instantiation which uses active_set_idx
    wire [TAG_WIDTH-1:0]   active_req_tag  = is_ptw_req_r ? latched_ptw_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO] : req_tag;
    wire [SET_IDX_W-1:0]   active_set_idx  = is_ptw_req_r ? latched_ptw_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO] : set_idx;
    wire [SET_IDX_W-1:0]   active_word_off = is_ptw_req_r ? latched_ptw_addr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO] : word_off;

    wire [WAY_W-1:0] plru_victim;
    wire [NUM_WAYS-2:0] plru_next;
    tree_plru u_plru(
        .plru_state (plru_state[active_set_idx]),
        .victim_way (plru_victim),
        .access_way (hit_way),
        .next_state (plru_next)
    );

    wire [WAY_W-1:0] victim_way = inv0 ? {WAY_W{1'b0}} :
                            inv1 ? {{(WAY_W-1){1'b0}}, 1'b1} :
                            inv2 ? {{(WAY_W-2){1'b0}}, 2'b10} :
                            inv3 ? {{(WAY_W-2){1'b0}}, 2'b11} :
                            plru_victim;

    // Extract victim way's tag entry from BRAM output (for dirty check and tag value)
    wire [TAG_ENTRY_W-1:0] tag_r_victim = victim_way == 2'd0 ? tag_r0 :
                                         victim_way == 2'd1 ? tag_r1 :
                                         victim_way == 2'd2 ? tag_r2 : tag_r3;
    wire victim_dirty = tag_r_victim[TAG_ENTRY_W-2]; // 脏位

    // Extract hit way's tag entry (for store-hit dirty update)
    wire [TAG_ENTRY_W-1:0] tag_r_hit = hit_way == 2'd0 ? tag_r0 :
                                       hit_way == 2'd1 ? tag_r1 :
                                       hit_way == 2'd2 ? tag_r2 : tag_r3;

    // Extract flush way's tag entry from BRAM output (for flush scan)
    wire [TAG_ENTRY_W-1:0] tag_r_flush;
    assign tag_r_flush = flush_way == 2'd0 ? tag_r0 :
                         flush_way == 2'd1 ? tag_r1 :
                         flush_way == 2'd2 ? tag_r2 : tag_r3;

    reg [SET_IDX_W-1:0]  flush_set;
    reg [WAY_W-1:0]      flush_way;
    reg        flush_done_r;
    reg        flush_error_seen_r;
    reg        flush_resume_invalidate_r;
    reg [SET_IDX_W-1:0]  invalidate_set;     // multi-cycle invalidate counter

    // Single-line invalidation
    reg        inv_line_done_r;
    reg [TAG_WIDTH-1:0]  inv_latched_tag;
    reg [SET_IDX_W-1:0]  inv_latched_set;
    reg [SET_IDX_W-1:0]  hit_set_r;
    reg [WAY_W-1:0]      hit_way_r;
    reg [SET_IDX_W-1:0]  hit_word_off_r;
    reg                  hit_watch_r;
    reg                  dbg_watch_lh_valid_r;
    reg [31:0]           dbg_watch_lh_data_r;
    reg [31:0]           dbg_watch_lh_count_r;
    reg                  dbg_watch_rf_valid_r;
    reg [31:0]           dbg_watch_rf_data_r;
    reg [31:0]           dbg_watch_rf_count_r;
    reg                  dbg_watch_wb_valid_r;
    reg [31:0]           dbg_watch_wb_data_r;
    reg [31:0]           dbg_watch_wb_count_r;

    // =========================================================================
    // Data BRAM (dcached) — 256-bit × 32 deep
    // =========================================================================
    wire [BRAM_ADDR_W-1:0] bram_addra = {active_set_idx, hit_way};
    wire [BRAM_ADDR_W-1:0] bram_addrb = (state == S_FLUSH_WB_RD || state == S_FLUSH_WB_SD) ?
                            {flush_set, flush_way} :
                            {latched_set, latched_victim_way};

    wire [LINE_WIDTH-1:0] bram_douta;
    wire [LINE_WIDTH-1:0] bram_doutb;

    wire [3:0] word_byte_we;
    assign word_byte_we = (cpu_req_hsize == `AXI_SIZE_BYTE) ? (4'b0001 << cpu_req_addr[1:0]) :
                          (cpu_req_hsize == `AXI_SIZE_HWORD) ? (cpu_req_addr[1] ? 4'b1100 : 4'b0011) :
                          4'b1111;

    // word_store_data: position store data into the correct byte lane of a 32-bit word.
    // BYTE: CPU puts byte in wdata[7:0] (unshifted) — we shift to correct lane.
    // HWORD: CPU already pre-shifts wdata to the correct halfword lane — pass through.
    // WORD:  CPU provides full 32-bit word — pass through.
    wire [31:0] word_store_data;
    assign word_store_data = (cpu_req_hsize == `AXI_SIZE_BYTE) ?
                             (cpu_req_addr[1:0] == 2'b00 ? {24'b0, cpu_req_wdata[7:0]} :
                              cpu_req_addr[1:0] == 2'b01 ? {16'b0, cpu_req_wdata[7:0], 8'b0} :
                              cpu_req_addr[1:0] == 2'b10 ? {8'b0, cpu_req_wdata[7:0], 16'b0} :
                                                           {cpu_req_wdata[7:0], 24'b0}) :
                             cpu_req_wdata;  // HWORD and WORD: CPU pre-shifts, pass through

    wire [WEA_WIDTH-1:0]  store_full_wea  = ({28'b0, word_byte_we}) << (word_off * 4);
    wire [LINE_WIDTH-1:0] store_full_dina = ({224'b0, word_store_data}) << (word_off * 32);

    reg cpu_req_ready_r;
    reg ptw_req_ready_r;
    reg ptw_req_fault_r;

    // CONTRACT: LSU address stability. cpu_req_addr, cpu_req_vaddr, cpu_req_wdata,
    // cpu_req_hwrite, and cpu_req_hsize MUST remain stable from cpu_req_valid
    // assertion until cpu_req_ready is asserted. The dcache combinational
    // decode (is_mmio, set_idx, req_tag, word_off, word_byte_we, word_store_data)
    // all use cpu_req_* directly. If the LSU changes these mid-request, the
    // tag comparison, store data positioning, or BRAM address would be wrong.
    // The LSU (cpu_mem.sv) guarantees this by latching addr_reg/dataAddr_32_reg
    // in MEM_IDLE and holding them until data_valid (which maps to cpu_req_ready).
    //
    // Store hit / Load hit detected in S_TAG_READ (after tag comparison)
    // MUST be gated by mmu_ready: the data BRAM Port A write is combinational,
    // so without this gate, a store_hit with stale paddr (mmu_ready=0) would
    // corrupt the data BRAM by writing to the wrong cache line.
    // PTW is read-only: is_ptw_req_r gates off store_hit and provides load_hit
    // without mmu_ready (PTW addresses are already physical).
    wire is_store_hit = (state == S_TAG_READ) && cache_hit && !is_ptw_req_r && cpu_req_hwrite && mmu_ready;
    wire is_load_hit  = (state == S_TAG_READ) && cache_hit && (is_ptw_req_r || (!cpu_req_hwrite && mmu_ready));



    wire bram_ena = is_load_hit || is_store_hit;
    wire [WEA_WIDTH-1:0]  bram_wea  = is_store_hit ? store_full_wea : {WEA_WIDTH{1'b0}};
    wire [LINE_WIDTH-1:0] bram_dina = is_store_hit ? store_full_dina : {LINE_WIDTH{1'b0}};

    // CONTRACT: BRAM en=0 output hold. When bram_ena/bram_enb=0, Xilinx BRAM IP
    // holds the last read data on bram_douta/bram_doutb. The FSM relies on this:
    // S_READ_HIT reads bram_douta which was latched by the ena pulse in
    // S_TAG_READ (is_load_hit). S_WB_SEND reads bram_doutb which was latched by
    // the enb pulse in S_WB_READ. If en=0 caused dout to go X or 0, the hit
    // data or writeback data would be corrupted. Do NOT add logic that assumes
    // en=0 clears dout.

    wire [3:0] latched_word_byte_we;
    assign latched_word_byte_we = (latched_hsize == `AXI_SIZE_BYTE) ? (4'b0001 << latched_addr[1:0]) :
                                  (latched_hsize == `AXI_SIZE_HWORD) ? (latched_addr[1] ? 4'b1100 : 4'b0011) :
                                  4'b1111;

    // latched_word_store_data: same logic as word_store_data but using latched signals.
    // BYTE: latched_wdata[7:0] is unshifted — shift to correct lane.
    // HWORD/WORD: CPU pre-shifts — pass through.
    wire [31:0] latched_word_store_data;
    assign latched_word_store_data = (latched_hsize == `AXI_SIZE_BYTE) ?
                                     (latched_addr[1:0] == 2'b00 ? {24'b0, latched_wdata[7:0]} :
                                      latched_addr[1:0] == 2'b01 ? {16'b0, latched_wdata[7:0], 8'b0} :
                                      latched_addr[1:0] == 2'b10 ? {8'b0, latched_wdata[7:0], 16'b0} :
                                                                   {latched_wdata[7:0], 24'b0}) :
                                     latched_wdata;  // HWORD and WORD: CPU pre-shifts, pass through

    wire [WEA_WIDTH-1:0]  merge_full_wea  = ({28'b0, latched_word_byte_we}) << (latched_word_off * 4);
    wire [LINE_WIDTH-1:0] merge_full_dina = ({224'b0, latched_word_store_data}) << (latched_word_off * 32);

    wire [LINE_WIDTH-1:0] merged_line;
    genvar gi;
    generate
        for (gi = 0; gi < WEA_WIDTH; gi = gi + 1) begin
            assign merged_line[gi*8 +: 8] = merge_full_wea[gi] ? merge_full_dina[gi*8 +: 8] : refill_data[gi*8 +: 8];
        end
    endgenerate

    wire [LINE_WIDTH-1:0] refill_bram_din = latched_hwrite ? merged_line : refill_data;

    wire bram_enb = (state == S_WB_READ) ||
                    (state == S_FLUSH_WB_RD) ||
                    (refill_valid && (state == S_REFILL));
    wire [WEA_WIDTH-1:0]  bram_web = (state == S_REFILL && refill_valid) ? {WEA_WIDTH{1'b1}} : {WEA_WIDTH{1'b0}};

    dcached u_dcached(
        .clka   (clk),
        .ena    (bram_ena),
        .wea    (bram_wea),
        .addra  (bram_addra),
        .dina   (bram_dina),
        .douta  (bram_douta),

        .clkb   (clk),
        .enb    (bram_enb),
        .web    (bram_web),
        .addrb  (bram_addrb),
        .dinb   (refill_bram_din),
        .doutb  (bram_doutb)
    );

    reg [31:0] bypass_data;
    reg        mmio_pending_r;
    reg        mmio_inflight_r;
    reg [31:0] mmio_addr_r;
    reg [31:0] mmio_wdata_r;
    reg        mmio_hwrite_r;
    reg [2:0]  mmio_hsize_r;

    wire [31:0] rdata_word = bram_douta[hit_word_off_r*32 +: 32];
    wire [31:0] refill_word = refill_data[latched_word_off*32 +: 32];
    wire [31:0] live_cpu_rdata =
        ((state == S_READ_HIT)) ? rdata_word :
        ((state == S_REFILL) && refill_valid) ? refill_word :
        bypass_data;

    // Response data must not depend on the live request address. Once a request
    // is in flight, the return path should be driven only by the completing
    // source (hit/refill/MMIO) via live_cpu_rdata/bypass_data.
    assign cpu_req_rdata = live_cpu_rdata;

    assign cpu_req_ready = cpu_req_ready_r;

    // PTW response data (combinational — valid when ptw_req_ready is high)
    // ptw_req_ready_r is asserted in S_READ_HIT/S_REFILL but takes effect next
    // cycle when state has already moved to S_IDLE.  bypass_data latches the
    // correct word in those states, so use it as fallback when ready is high.
    wire [31:0] ptw_live_rdata = (state == S_READ_HIT) ? rdata_word :
                                 (state == S_REFILL && refill_valid) ? refill_word :
                                 ptw_req_ready_r ? bypass_data : 32'b0;
    assign ptw_req_ready  = ptw_req_ready_r;
    assign ptw_req_rdata  = ptw_live_rdata;
    assign ptw_req_fault  = ptw_req_fault_r;

    reg refill_req_r;
    reg [31:0] refill_addr_r;
    reg wb_req_r;
    reg [31:0] wb_addr_r;

    assign refill_req  = refill_req_r;
    assign refill_addr = refill_addr_r;
    assign wb_req      = wb_req_r;
    assign wb_addr     = wb_addr_r;
    assign wb_data     = bram_doutb;

    assign flush_done  = flush_done_r;
    assign inv_line_done = inv_line_done_r;
    assign dbg_watch_lh_valid = dbg_watch_lh_valid_r;
    assign dbg_watch_lh_data  = dbg_watch_lh_data_r;
    assign dbg_watch_lh_count = dbg_watch_lh_count_r;
    assign dbg_watch_rf_valid = dbg_watch_rf_valid_r;
    assign dbg_watch_rf_data  = dbg_watch_rf_data_r;
    assign dbg_watch_rf_count = dbg_watch_rf_count_r;
    assign dbg_watch_wb_valid = dbg_watch_wb_valid_r;
    assign dbg_watch_wb_data  = dbg_watch_wb_data_r;
    assign dbg_watch_wb_count = dbg_watch_wb_count_r;

    assign mmio_req    = mmio_pending_r;
    assign mmio_addr   = mmio_addr_r;
    assign mmio_wdata  = mmio_wdata_r;
    assign mmio_hwrite = mmio_hwrite_r;
    assign mmio_hsize  = mmio_hsize_r;

    wire [NUM_WAYS-2:0] plru_next_miss;
    tree_plru u_plru_miss(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (latched_victim_way),
        .next_state (plru_next_miss)
    );

    wire [NUM_WAYS-2:0] plru_next_hit;
    tree_plru u_plru_hit(
        .plru_state (plru_state[hit_set_r]),
        .victim_way (),
        .access_way (hit_way_r),
        .next_state (plru_next_hit)
    );

    // =========================================================================
    // Tag BRAM write helpers — pack a single way's entry into BRAM line position
    // =========================================================================
    // Store hit: set V=1, D=1, keep tag
    wire [TAG_ENTRY_W-1:0] store_hit_new_entry = {1'b1, 1'b1, tag_r_hit[TAG_WIDTH-1:0]};
    wire [TAG_BRAM_W-1:0]  store_hit_tag_din   = ({TAG_BRAM_W{1'b0}} | {{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, store_hit_new_entry}) << (hit_way * TAG_BRAM_BS);

    // Refill: set V=1, D=latched_hwrite, tag=latched_tag
    wire [TAG_ENTRY_W-1:0] refill_new_entry = {1'b1, latched_hwrite, latched_tag};
    wire [TAG_BRAM_W-1:0]  refill_tag_din   = ({TAG_BRAM_W{1'b0}} | {{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, refill_new_entry}) << (latched_victim_way * TAG_BRAM_BS);

    // Writeback clear dirty: set V=1, D=0, keep tag
    wire [TAG_ENTRY_W-1:0] wb_clear_entry = {1'b1, 1'b0, latched_victim_tag};
    wire [TAG_BRAM_W-1:0]  wb_clear_tag_din = ({TAG_BRAM_W{1'b0}} | {{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, wb_clear_entry}) << (latched_victim_way * TAG_BRAM_BS);

    // Flush clear dirty: set V=1, D=0, keep tag (uses flush_way position)
    wire [TAG_ENTRY_W-1:0] flush_clear_entry = {1'b1, 1'b0, tag_r_flush[TAG_WIDTH-1:0]};
    wire [TAG_BRAM_W-1:0]  flush_clear_tag_din = ({TAG_BRAM_W{1'b0}} | {{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, flush_clear_entry}) << (flush_way * TAG_BRAM_BS);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state            <= S_RST_CLEAR;  // ISSUE-4: clear tag BRAM before accepting requests
            refill_req_r     <= 1'b0;
            refill_addr_r    <= 32'b0;
            wb_req_r         <= 1'b0;
            wb_addr_r        <= 32'b0;
            // flush_set, flush_way, latched_set, latched_victim_way: intentionally NOT reset.
            // These registers drive BRAM addresses/write-enables but are only meaningful when
            // the state machine is in active states (not S_IDLE). BRAM EN is gated by state.
            // This eliminates REQP-1839 DRC warnings (async reset on BRAM address drivers).
            // Coding standard exception: address/control registers qualified by state machine.
            latched_addr     <= 32'b0;
            latched_wdata    <= 32'b0;
            latched_hwrite   <= 1'b0;
            latched_hsize    <= 3'b0;
            latched_word_off <= {SET_IDX_W{1'b0}};
            latched_tag      <= {TAG_WIDTH{1'b0}};
            latched_victim_tag <= {TAG_WIDTH{1'b0}};
            bypass_data      <= 32'b0;
            cpu_req_ready_r  <= 1'b0;
            ptw_req_ready_r  <= 1'b0;
            ptw_req_fault_r  <= 1'b0;
            // is_ptw_req_r: intentionally NOT reset. Value is qualified by state machine
            // (only meaningful in S_TAG_READ/S_READ/S_REFILL). BRAM address driven by
            // is_ptw_req_r is only used when state != S_IDLE, and BRAM EN is gated
            // by state. This eliminates REQP-1839 DRC warning.
            // Coding standard exception: control register qualified by state machine.
            // latched_ptw_addr: intentionally NOT reset. Same reasoning — only used
            // when is_ptw_req_r=1, which is only set during active PTW requests.
            latched_ptw_vaddr<= 32'b0;
            mmio_pending_r   <= 1'b0;
            mmio_inflight_r  <= 1'b0;
            mmio_addr_r      <= 32'b0;
            mmio_wdata_r     <= 32'b0;
            mmio_hwrite_r    <= 1'b0;
            mmio_hsize_r     <= 3'b0;
            flush_done_r     <= 1'b0;
            flush_error_seen_r <= 1'b0;
            flush_resume_invalidate_r <= 1'b0;
            invalidate_set   <= {SET_IDX_W{1'b0}};
            inv_line_done_r  <= 1'b0;
            inv_latched_tag  <= {TAG_WIDTH{1'b0}};
            inv_latched_set  <= {SET_IDX_W{1'b0}};
            hit_set_r        <= {SET_IDX_W{1'b0}};
            hit_way_r        <= {WAY_W{1'b0}};
            hit_word_off_r   <= {SET_IDX_W{1'b0}};
            hit_watch_r      <= 1'b0;
            dbg_watch_lh_valid_r <= 1'b0;
            dbg_watch_lh_data_r  <= 32'b0;
            dbg_watch_lh_count_r <= 32'b0;
            dbg_watch_rf_valid_r <= 1'b0;
            dbg_watch_rf_data_r  <= 32'b0;
            dbg_watch_rf_count_r <= 32'b0;
            dbg_watch_wb_valid_r <= 1'b0;
            dbg_watch_wb_data_r  <= 32'b0;
            dbg_watch_wb_count_r <= 32'b0;
            tag_bram_enb_r   <= 1'b0;
            tag_bram_web_r   <= {TAG_BRAM_WEA{1'b0}};
            tag_bram_addrb_r <= {SET_IDX_W{1'b0}};
            tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= {NUM_WAYS-1{1'b0}};
            end
        end else begin
            cpu_req_ready_r <= 1'b0;
            ptw_req_ready_r <= 1'b0;
            ptw_req_fault_r <= 1'b0;
            flush_done_r    <= 1'b0;
            inv_line_done_r <= 1'b0;
            tag_bram_enb_r  <= 1'b0;  // default: no tag BRAM write
            if (mmio_accept) begin
                mmio_pending_r <= 1'b0;
                mmio_inflight_r <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    wb_req_r     <= 1'b0;
                    if (!flush_req) begin
                        flush_error_seen_r <= 1'b0;
                    end
                    if (flush_req && !flush_error_seen_r) begin
                        flush_resume_invalidate_r <= 1'b0;
                        state     <= S_FLUSH_SCAN;
                        flush_set <= {SET_IDX_W{1'b0}};
                        flush_way <= {WAY_W{1'b0}};

                    end else if (inv_line_req) begin
                        // Single-line invalidation for PTW A/D bit coherency
                        // Extract set index and tag from inv_line_addr
                        // Use physical address for both set index and tag (PIPT for inv)
                        inv_latched_set <= inv_line_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
                        inv_latched_tag <= inv_line_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
                        state           <= S_INV_LINE;

                    end else if (ptw_req_valid && !ptw_req_ready_r) begin
                        // PTW request — priority over CPU
                        // PTW reads PTEs through dcache instead of directly through bus.
                        if (ptw_req_is_mmio) begin
                            // PTW addresses should never be MMIO (page tables in DDR3).
                            // Safety check: respond immediately with fault.
                            ptw_req_ready_r  <= 1'b1;
                            ptw_req_fault_r  <= 1'b1;
                        end else begin
                            // Cacheable PTW read — latch address, proceed to tag lookup
                            is_ptw_req_r      <= 1'b1;
                            latched_ptw_addr  <= ptw_req_addr;
                            latched_ptw_vaddr <= ptw_req_vaddr;
                            state <= S_TAG_READ;
                        end

                    end else if (cpu_req_valid && !cpu_req_ready_r) begin
                        // CPU request — PTW has priority, so we only reach here
                        // when ptw_req_valid is deasserted.
                        is_ptw_req_r <= 1'b0;
                        // BUG-FIX: Wait for mmu_ready before deciding MMIO vs cache,
                        // because is_mmio now depends on physical address (cpu_req_addr)
                        // which is only valid when mmu_ready=1.
                        if (mmu_ready) begin
                            if (is_mmio) begin
                                if (mmio_valid) begin
                                    bypass_data     <= mmio_rdata;
                                    cpu_req_ready_r <= 1'b1;
                                    mmio_inflight_r <= 1'b0;
                                end else if (!mmio_pending_r && !mmio_inflight_r) begin
                                    mmio_pending_r <= 1'b1;
                                    mmio_addr_r    <= cpu_req_addr;
                                    mmio_wdata_r   <= cpu_req_wdata;
                                    mmio_hwrite_r  <= cpu_req_hwrite;
                                    mmio_hsize_r   <= cpu_req_hsize;
                                end
                            end else begin
                                // Enable tag BRAM Port A → output valid next cycle
                                state <= S_TAG_READ;
                            end
                        end else begin
                            // mmu_ready not yet — wait for physical address.
                            // Handle any already-pending MMIO response defensively.
                            if (mmio_valid) begin
                                bypass_data     <= mmio_rdata;
                                cpu_req_ready_r <= 1'b1;
                                mmio_inflight_r <= 1'b0;
                            end
                        end
                    end
                end

                S_TAG_READ: begin
                    // Tag BRAM Port A output is now valid
                    // T_COMPLETE in MMU.sv holds translate_done high until !translate_req,
                    // so mmu_ready stays stable after translation — no ping-pong wait needed.
                    // PTW addresses are already physical (no mmu_ready needed).
                    if (cache_hit) begin
                        if (!is_ptw_req_r && cpu_req_hwrite) begin
                            // Store hit: write data BRAM + set dirty in tag BRAM
                            tag_bram_enb_r   <= 1'b1;
                            tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (hit_way * TAG_BRAM_BPW);
                            tag_bram_addrb_r <= active_set_idx;
                            tag_bram_dinb_r  <= store_hit_tag_din;
                            plru_state[active_set_idx] <= plru_next;
                            cpu_req_ready_r <= 1'b1;
                            state <= S_DONE;  // must return to S_IDLE (via S_DONE); tag BRAM output is stale for new request
                        end else begin
                            // Load hit (CPU or PTW): enable data BRAM, go to S_READ_HIT
                            hit_set_r      <= active_set_idx;
                            hit_way_r      <= hit_way;
                            hit_word_off_r <= active_word_off;
                            hit_watch_r    <= is_ptw_req_r ? ({latched_ptw_addr[31:5], 5'b0} == DBG_WATCH_LINE_ADDR) :
                                                              ({cpu_req_addr[31:5], 5'b0} == DBG_WATCH_LINE_ADDR);
                            state <= S_READ_HIT;
                        end
                    end else begin
                        // Miss: latch victim info
                        latched_set        <= active_set_idx;
                        latched_victim_way <= victim_way;
                        latched_addr       <= is_ptw_req_r ? latched_ptw_addr : cpu_req_addr;
                        latched_wdata      <= cpu_req_wdata;
                        latched_hwrite     <= is_ptw_req_r ? 1'b0 : cpu_req_hwrite;
                        latched_hsize      <= cpu_req_hsize;
                        latched_word_off   <= active_word_off;
                        latched_tag        <= active_req_tag;
                        latched_victim_tag <= tag_r_victim[TAG_WIDTH-1:0];
                        if (victim_dirty) begin
                            state <= S_WB_READ;
                        end else begin
                            refill_req_r  <= 1'b1;
                            refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, active_req_tag, active_set_idx, {ADDR_LOWER_ZEROS{1'b0}}};
                            state <= S_REFILL;
                        end
                    end
                end

                S_READ_HIT: begin
                    bypass_data     <= rdata_word;
                    if (is_ptw_req_r) begin
                        ptw_req_ready_r <= 1'b1;
                        is_ptw_req_r    <= 1'b0;
                    end else begin
                        cpu_req_ready_r <= 1'b1;
                    end
                    plru_state[hit_set_r] <= plru_next_hit;
                    if (hit_watch_r) begin
                        dbg_watch_lh_valid_r <= 1'b1;
                        dbg_watch_lh_data_r  <= rdata_word;
                        dbg_watch_lh_count_r <= dbg_watch_lh_count_r + 32'd1;
                    end
                    state <= S_DONE;
                end

                S_WB_READ: begin
                    wb_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, latched_victim_tag, latched_set, {ADDR_LOWER_ZEROS{1'b0}}};
                    state <= S_WB_SEND;
                end

                S_WB_SEND: begin
                    if (amo_abort) begin
                        wb_req_r      <= 1'b0;
                        refill_req_r  <= 1'b0;
                        state         <= S_IDLE;
                    end else begin
                        wb_req_r <= 1'b1;
                        if (wb_done) begin
                            if ({wb_addr_r[31:5], 5'b0} == DBG_WATCH_LINE_ADDR) begin
                                dbg_watch_wb_valid_r <= 1'b1;
                                dbg_watch_wb_data_r  <= bram_doutb[DBG_WATCH_WORD_OFF*32 +: 32];
                                dbg_watch_wb_count_r <= dbg_watch_wb_count_r + 32'd1;
                            end
                            wb_req_r      <= 1'b0;
                            if (wb_error) begin
                                state <= S_IDLE;
                            end else begin
                                // Clear dirty bit in tag BRAM
                                tag_bram_enb_r   <= 1'b1;
                                tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (latched_victim_way * TAG_BRAM_BPW);
                                tag_bram_addrb_r <= latched_set;
                                tag_bram_dinb_r  <= wb_clear_tag_din;
                                refill_req_r  <= 1'b1;
                                refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, latched_tag, latched_set, {ADDR_LOWER_ZEROS{1'b0}}};
                                state <= S_REFILL;
                            end
                        end
                    end
                end

                S_REFILL: begin
                    // Flush can abort in-progress refill — fence.i must not be
                    // blocked by unbounded AXI latency.  The bus bridge tolerates
                    // request cancellation; stale responses are discarded via
                    // refill_addr_match check.
                    if (flush_req) begin
                        refill_req_r      <= 1'b0;
                        flush_error_seen_r <= 1'b0;
                        flush_resume_invalidate_r <= 1'b0;
                        flush_set <= {SET_IDX_W{1'b0}};
                        flush_way <= {WAY_W{1'b0}};
                        state     <= S_FLUSH_SCAN;
                    end else if (amo_abort) begin
                        refill_req_r  <= 1'b0;
                        wb_req_r      <= 1'b0;
                        state         <= S_IDLE;
                    end else begin
                        refill_req_r <= 1'b1;
                        if (refill_done) begin
                            refill_req_r <= 1'b0;
                            if (refill_error) begin
                                if (is_ptw_req_r) begin
                                    ptw_req_ready_r <= 1'b1;
                                    ptw_req_fault_r <= 1'b1;
                                    is_ptw_req_r    <= 1'b0;
                                end
                                state <= S_DONE;
                            end else begin
                                if ({refill_addr_r[31:5], 5'b0} == DBG_WATCH_LINE_ADDR) begin
                                    dbg_watch_lh_valid_r <= 1'b1;
                                    dbg_watch_lh_data_r  <= refill_word;
                                    dbg_watch_lh_count_r <= {
                                        21'b0,
                                        refill_addr_r[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO],
                                        latched_word_off,
                                        state,
                                        refill_valid
                                    };
                                    dbg_watch_rf_valid_r <= 1'b1;
                                    dbg_watch_rf_data_r  <= refill_data[DBG_WATCH_WORD_OFF*32 +: 32];
                                    dbg_watch_rf_count_r <= dbg_watch_rf_count_r + 32'd1;
                                end
                                bypass_data     <= refill_word;
                                if (is_ptw_req_r) begin
                                    ptw_req_ready_r <= 1'b1;
                                    is_ptw_req_r    <= 1'b0;
                                end else begin
                                    cpu_req_ready_r <= 1'b1;
                                end
                                // Write tag BRAM: set valid, dirty=latched_hwrite, tag
                                tag_bram_enb_r   <= 1'b1;
                                tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (latched_victim_way * TAG_BRAM_BPW);
                                tag_bram_addrb_r <= latched_set;
                                tag_bram_dinb_r  <= refill_tag_din;
                                plru_state[latched_set] <= plru_next_miss;
                                state <= S_DONE;
                            end
                        end
                    end
                end

                S_FLUSH_SCAN: begin
                    // Enable tag BRAM Port A for flush_set → output valid next cycle
                    state <= S_FLUSH_CHECK;
                end

                S_FLUSH_CHECK: begin
                    // Tag BRAM output valid for flush_set
                    if (tag_r_flush[TAG_ENTRY_W-1] && tag_r_flush[TAG_ENTRY_W-2]) begin
                        // Valid && Dirty → need writeback

                        latched_set        <= flush_set;
                        latched_victim_way <= flush_way;
                        latched_victim_tag <= tag_r_flush[TAG_WIDTH-1:0];
                        state <= S_FLUSH_WB_RD;
                    end else begin
                        // Not dirty, advance to next way/set
                        if (flush_way == NUM_WAYS - 1) begin
                            if (flush_set == NUM_SETS - 1) begin
                                // All sets/ways scanned → invalidate all
                                state <= S_FLUSH_INVALIDATE;
                                invalidate_set <= {SET_IDX_W{1'b0}};
                            end else begin
                                flush_set <= flush_set + 1'b1;
                                flush_way <= {WAY_W{1'b0}};
                                state <= S_FLUSH_SCAN;
                            end
                        end else begin
                            flush_way <= flush_way + 1'b1;
                            // Same set, next way — BRAM output still valid, stay in S_FLUSH_CHECK
                        end
                    end
                end

                S_FLUSH_WB_RD: begin
                    wb_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, latched_victim_tag, latched_set, {ADDR_LOWER_ZEROS{1'b0}}};
state <= S_FLUSH_WB_SD;
                end

                S_FLUSH_WB_SD: begin
                    wb_req_r <= 1'b1;

                    if (wb_done) begin
                        wb_req_r <= 1'b0;
                        if (wb_error) begin
                            flush_error_seen_r <= 1'b1;
                            // A maintenance write-back fault must not leave the stale
                            // cache line resident. Reuse the dedicated single-line
                            // invalidation flow so the faulting way is dropped with the
                            // same tag-preserving semantics used by PTW coherency.
                            inv_latched_set <= latched_set;
                            inv_latched_tag <= latched_victim_tag;
                            state <= S_INV_LINE;
                        end else begin
                            // Clear dirty bit in tag BRAM
                            tag_bram_enb_r   <= 1'b1;
                            tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (latched_victim_way * TAG_BRAM_BPW);
                            tag_bram_addrb_r <= latched_set;
                            tag_bram_dinb_r  <= wb_clear_tag_din;
                            // Defer the next scan step by one cycle so the Port B tag
                            // write commits without colliding with a same-set Port A read.
                            if (latched_victim_way == NUM_WAYS - 1) begin
                                if (latched_set == NUM_SETS - 1) begin
                                    // All done → invalidate all
                                    flush_resume_invalidate_r <= 1'b1;
                                    invalidate_set <= {SET_IDX_W{1'b0}};
                                end else begin
                                    flush_set <= latched_set + 1'b1;
                                    flush_way <= {WAY_W{1'b0}};
                                    flush_resume_invalidate_r <= 1'b0;
                                end
                            end else begin
                                flush_set <= latched_set;
                                flush_way <= latched_victim_way + 1'b1;
                                flush_resume_invalidate_r <= 1'b0;
                            end
                            state <= S_FLUSH_WB_WAIT;
                        end
                    end
                end

                S_FLUSH_WB_WAIT: begin
                    if (flush_resume_invalidate_r) begin
                        state <= S_FLUSH_INVALIDATE;
                    end else begin
                        state <= S_FLUSH_SCAN;
                    end
                end

                S_FLUSH_INVALIDATE: begin
                    // Write one set per cycle with all zeros (clear all valid bits)
                    tag_bram_enb_r   <= 1'b1;
                    tag_bram_web_r   <= {TAG_BRAM_WEA{1'b1}};   // write all 4 ways
                    tag_bram_addrb_r <= invalidate_set;
                    tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};     // all zeros

                    if (invalidate_set == NUM_SETS - 1) begin
                        for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                            plru_state[s] <= {NUM_WAYS-1{1'b0}};
                        end
                        flush_done_r <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        invalidate_set <= invalidate_set + 1'b1;
                    end
                end

                S_INV_LINE: begin
                    // Tag BRAM Port A read enabled (via tag_bram_ena).
                    // Output will be valid next cycle → advance to S_INV_LINE_WRITE.
                    state <= S_INV_LINE_WRITE;
                end

                S_INV_LINE_WRITE: begin
                    // BUG-FIX (ISSUE-1): When wb_error occurs during a dcache flush
                    // writeback, this state previously set flush_done_r immediately
                    // and returned to S_IDLE, terminating the flush prematurely.
                    // This caused remaining dirty lines in later sets/ways to be
                    // silently lost (never written back to memory).
                    //
                    // Fix: When flush_error_seen_r==1, clear it, do NOT set
                    // flush_done_r. Advance flush_set/flush_way past the faulting
                    // line (mirroring the success path in S_FLUSH_WB_SD), then
                    // jump to S_FLUSH_WB_WAIT (not S_IDLE) to defer one cycle for
                    // Port B tag write commit before next Port A read. The
                    // faulting line is still invalidated (existing logic above).
                    // flush_done_r is now ONLY set in S_FLUSH_INVALIDATE when all
                    // sets have been scanned and invalidated.
                    //
                    // The store access fault (mcause=7) is routed independently via
                    // wb_error → cpu_bus_bridge → core_top → cpu_trap_manager.
                    // flush_error_seen_r is purely internal to dcache_ctrl for FSM
                    // control and does NOT feed the trap path.
                    //
                    // Tag BRAM Port A output is now valid.
                    // Invalidate any matching way by clearing its V bit.
                    // If the line is dirty, we must write it back first to avoid data loss.
                    // However, for PTW A/D bit coherency, the PTW has already written
                    // the updated PTE directly to memory. If dcache has a dirty copy,
                    // that dirty copy contains the OLD PTE (without A/D bits set).
                    // Invalidating it (dropping V) means:
                    //   - If D=1: the dirty data (old PTE) would be lost on invalidate.
                    //     But this is CORRECT — the PTW already wrote the new PTE to
                    //     memory, so the old dirty PTE in dcache is stale. We must NOT
                    //     write it back (that would overwrite the PTW's A/D update).
                    //   - Simply clear V (and D) to force a refill from memory on next
                    //     access, which will get the PTW-updated PTE.
                    //
                    // For each matching way: write {V=0, D=0, tag} to clear the entry.
                    // We handle at most one way per cycle (rare to have multiple ways
                    // match the same tag, but handle it safely).

                    if (inv_hit0) begin
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1);  // way 0
                        tag_bram_addrb_r <= inv_latched_set;
                        tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}} | ({{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, {1'b0, 1'b0, tag_r0[TAG_WIDTH-1:0]}} << (2'd0 * TAG_BRAM_BS));
                    end else if (inv_hit1) begin
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << TAG_BRAM_BPW;  // way 1
                        tag_bram_addrb_r <= inv_latched_set;
                        tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}} | ({{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, {1'b0, 1'b0, tag_r1[TAG_WIDTH-1:0]}} << (2'd1 * TAG_BRAM_BS));
                    end else if (inv_hit2) begin
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (2'd2 * TAG_BRAM_BPW);  // way 2
                        tag_bram_addrb_r <= inv_latched_set;
                        tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}} | ({{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, {1'b0, 1'b0, tag_r2[TAG_WIDTH-1:0]}} << (2'd2 * TAG_BRAM_BS));
                    end else if (inv_hit3) begin
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (2'd3 * TAG_BRAM_BPW);  // way 3
                        tag_bram_addrb_r <= inv_latched_set;
                        tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}} | ({{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, {1'b0, 1'b0, tag_r3[TAG_WIDTH-1:0]}} << (2'd3 * TAG_BRAM_BS));
                    end

                    if (flush_error_seen_r) begin
                        // Flush error recovery: the faulting line has been
                        // invalidated above. Do NOT signal flush_done —
                        // remaining dirty lines must still be scanned and
                        // written back. Advance flush_set/flush_way past the
                        // faulting line (mirroring the success path in
                        // S_FLUSH_WB_SD) and resume scanning via S_FLUSH_WB_WAIT
                        // (defers one cycle so the Port B tag write commits
                        // before the next Port A read).
                        flush_error_seen_r <= 1'b0;
                        if (latched_victim_way == NUM_WAYS - 1) begin
                            if (latched_set == NUM_SETS - 1) begin
                                // All sets scanned → invalidate all
                                flush_resume_invalidate_r <= 1'b1;
                                invalidate_set <= {SET_IDX_W{1'b0}};
                            end else begin
                                flush_set <= latched_set + 1'b1;
                                flush_way <= {WAY_W{1'b0}};
                                flush_resume_invalidate_r <= 1'b0;
                            end
                        end else begin
                            flush_set <= latched_set;
                            flush_way <= latched_victim_way + 1'b1;
                            flush_resume_invalidate_r <= 1'b0;
                        end
                        state <= S_FLUSH_WB_WAIT;
                    end else begin
                        inv_line_done_r <= 1'b1;
                        state <= S_DONE;
                    end
                end

                S_RST_CLEAR: begin
                    // ISSUE-4: At reset, tag BRAM contents are undefined (X in
                    // simulation). Since valid bits live in BRAM (TAG_ENTRY_W:
                    // V+D+tag), undefined BRAM means valid bits could be X,
                    // causing X-propagation on first access. Scan all sets and
                    // write zeros to clear valid bits before accepting any
                    // CPU/PTW request. Reuses the S_FLUSH_INVALIDATE zero-write
                    // pattern. No CPU/PTW requests accepted here — stay until
                    // scan complete.
                    tag_bram_enb_r   <= 1'b1;
                    tag_bram_web_r   <= {TAG_BRAM_WEA{1'b1}};   // write all 4 ways
                    tag_bram_addrb_r <= invalidate_set;
                    tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};     // all zeros
                    if (invalidate_set == NUM_SETS - 1) begin
                        state <= S_IDLE;
                    end else begin
                        invalidate_set <= invalidate_set + 1'b1;
                    end
                end

                S_DONE: begin
                    // ready/done 信号在上一状态已置 1（非阻塞赋值），
                    // 本周期可见并输出给消费者。下一周期转 S_IDLE，
                    // 默认清零生效，无残留。
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
