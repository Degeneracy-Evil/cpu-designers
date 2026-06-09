`timescale 1ns / 1ps
`include "ahb_def.svh"
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

    output wire        mmio_req,
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

    output wire        wb_req,
    output wire [31:0] wb_addr,
    output wire [`DCACHE_LINE_WIDTH-1:0] wb_data,
    input  wire        wb_valid,

    input  wire        flush_req,
    output wire        flush_done
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
    // Derived: address layout
    localparam ADDR_UPPER_ZEROS = 30 - `DCACHE_TAG_HI;
    localparam ADDR_LOWER_ZEROS = `DCACHE_SET_IDX_LO;

    // 状态机状态
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

    // Use vaddr for MMIO check: paddr may be stale when mmu_ready=0
    // (BRAM MMU latches inputs, so paddr uses latched_vaddr which is 0 after reset)
    // Safe because VA[31]=PA[31] for all translated addresses in this system
    wire is_mmio = ~cpu_req_vaddr[31];

    // VIPT: use vaddr for set index (bits within page offset), paddr for tag
    wire [TAG_WIDTH-1:0]   req_tag  = cpu_req_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
    wire [SET_IDX_W-1:0]   set_idx  = cpu_req_vaddr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
    wire [SET_IDX_W-1:0]   word_off = cpu_req_vaddr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];

    reg [3:0] state; // 状态机

    // --- PLRU state (kept as registers — too small for BRAM) ---
    reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

    // =========================================================================
    // Tag BRAM (dcachet) — 36-bit × 8 deep, Byte_Size=9, 4-bit WEA
    // Each address = 1 set, data = 4 ways packed: {Way3, Way2, Way1, Way0}
    //   Way N bits: [N*9 +: 9] = {V(1), D(1), tag(7)}
    // =========================================================================
    wire [TAG_BRAM_W-1:0] tag_bram_douta;
    wire [TAG_BRAM_W-1:0] tag_bram_doutb;

    // Port A: CPU read / Flush scan read
    wire tag_bram_ena = ((state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && !is_mmio) ||
                        (state == S_FLUSH_SCAN);
    wire [SET_IDX_W-1:0] tag_bram_addra = (state == S_FLUSH_SCAN) ? flush_set : set_idx;

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
    wire [TAG_ENTRY_W-1:0] tag_r0 = tag_bram_douta[TAG_ENTRY_W*1-1:TAG_ENTRY_W*0];
    wire [TAG_ENTRY_W-1:0] tag_r1 = tag_bram_douta[TAG_ENTRY_W*2-1:TAG_ENTRY_W*1];
    wire [TAG_ENTRY_W-1:0] tag_r2 = tag_bram_douta[TAG_ENTRY_W*3-1:TAG_ENTRY_W*2];
    wire [TAG_ENTRY_W-1:0] tag_r3 = tag_bram_douta[TAG_ENTRY_W*4-1:TAG_ENTRY_W*3];

    // Tag entry layout: [TAG_ENTRY_W-1]=V, [TAG_ENTRY_W-2]=D, [TAG_WIDTH-1:0]=tag
    wire hit0 = tag_r0[TAG_ENTRY_W-1] && (tag_r0[TAG_WIDTH-1:0] == req_tag);
    wire hit1 = tag_r1[TAG_ENTRY_W-1] && (tag_r1[TAG_WIDTH-1:0] == req_tag);
    wire hit2 = tag_r2[TAG_ENTRY_W-1] && (tag_r2[TAG_WIDTH-1:0] == req_tag);
    wire hit3 = tag_r3[TAG_ENTRY_W-1] && (tag_r3[TAG_WIDTH-1:0] == req_tag);

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

    wire [WAY_W-1:0] plru_victim;
    wire [NUM_WAYS-2:0] plru_next;
    tree_plru u_plru(
        .plru_state (plru_state[set_idx]),
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

    reg [SET_IDX_W-1:0]  latched_set;
    reg [WAY_W-1:0]      latched_victim_way;
    reg [31:0] latched_addr;
    reg [31:0] latched_wdata;
    reg        latched_hwrite;
    reg [2:0]  latched_hsize;
    reg [SET_IDX_W-1:0]  latched_word_off;
    reg [TAG_WIDTH-1:0]  latched_tag;
    reg [TAG_WIDTH-1:0]  latched_victim_tag;  // victim's tag for writeback addr

    reg [SET_IDX_W-1:0]  flush_set;
    reg [WAY_W-1:0]      flush_way;
    reg        flush_done_r;
    reg [SET_IDX_W-1:0]  invalidate_set;     // multi-cycle invalidate counter

    // =========================================================================
    // Data BRAM (dcached) — 256-bit × 32 deep
    // =========================================================================
    wire [BRAM_ADDR_W-1:0] bram_addra = {set_idx, hit_way};
    wire [BRAM_ADDR_W-1:0] bram_addrb = (state == S_FLUSH_WB_RD || state == S_FLUSH_WB_SD) ?
                            {flush_set, flush_way} :
                            {latched_set, latched_victim_way};

    wire [LINE_WIDTH-1:0] bram_douta;
    wire [LINE_WIDTH-1:0] bram_doutb;

    wire [3:0] word_byte_we;
    assign word_byte_we = (cpu_req_hsize == `AHB_SIZE_BYTE) ? (4'b0001 << cpu_req_addr[1:0]) :
                          (cpu_req_hsize == `AHB_SIZE_HWORD) ? (cpu_req_addr[1] ? 4'b1100 : 4'b0011) :
                          4'b1111;

    wire [31:0] word_store_data;
    assign word_store_data = (cpu_req_hsize == `AHB_SIZE_BYTE) ?
                             (cpu_req_wdata[7:0] << (cpu_req_addr[1:0] * 8)) :
                             cpu_req_wdata;

    wire [WEA_WIDTH-1:0]  store_full_wea  = ({28'b0, word_byte_we}) << (word_off * 4);
    wire [LINE_WIDTH-1:0] store_full_dina = ({224'b0, word_store_data}) << (word_off * 32);

    reg cpu_req_ready_r;

    // Store hit / Load hit detected in S_TAG_READ (after tag comparison)
    // MUST be gated by mmu_ready: the data BRAM Port A write is combinational,
    // so without this gate, a store_hit with stale paddr (mmu_ready=0) would
    // corrupt the data BRAM by writing to the wrong cache line.
    wire is_store_hit = (state == S_TAG_READ) && cache_hit && cpu_req_hwrite && mmu_ready;
    wire is_load_hit  = (state == S_TAG_READ) && cache_hit && !cpu_req_hwrite && mmu_ready;

    wire bram_ena = is_load_hit || is_store_hit;
    wire [WEA_WIDTH-1:0]  bram_wea  = is_store_hit ? store_full_wea : {WEA_WIDTH{1'b0}};
    wire [LINE_WIDTH-1:0] bram_dina = is_store_hit ? store_full_dina : {LINE_WIDTH{1'b0}};

    wire [3:0] latched_word_byte_we;
    assign latched_word_byte_we = (latched_hsize == `AHB_SIZE_BYTE) ? (4'b0001 << latched_addr[1:0]) :
                                  (latched_hsize == `AHB_SIZE_HWORD) ? (latched_addr[1] ? 4'b1100 : 4'b0011) :
                                  4'b1111;

    wire [31:0] latched_word_store_data;
    assign latched_word_store_data = (latched_hsize == `AHB_SIZE_BYTE) ?
                                     (latched_wdata[7:0] << (latched_addr[1:0] * 8)) :
                                     latched_wdata;

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

    wire [31:0] rdata_word = bram_douta[word_off*32 +: 32];
    wire [31:0] refill_word = refill_data[latched_word_off*32 +: 32];

    assign cpu_req_rdata = is_mmio ? mmio_rdata : bypass_data;

    assign cpu_req_ready = cpu_req_ready_r;

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

    assign mmio_req    = (state == S_IDLE) && cpu_req_valid && is_mmio && mmu_ready ? 1'b1 : 1'b0;
    assign mmio_addr   = cpu_req_addr;
    assign mmio_wdata  = cpu_req_wdata;
    assign mmio_hwrite = cpu_req_hwrite;
    assign mmio_hsize  = cpu_req_hsize;

    wire [NUM_WAYS-2:0] plru_next_miss;
    tree_plru u_plru_miss(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (latched_victim_way),
        .next_state (plru_next_miss)
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
            state            <= S_IDLE;
            refill_req_r     <= 1'b0;
            refill_addr_r    <= 32'b0;
            wb_req_r         <= 1'b0;
            wb_addr_r        <= 32'b0;
            latched_set      <= {SET_IDX_W{1'b0}};
            latched_victim_way <= {WAY_W{1'b0}};
            latched_addr     <= 32'b0;
            latched_wdata    <= 32'b0;
            latched_hwrite   <= 1'b0;
            latched_hsize    <= 3'b0;
            latched_word_off <= {SET_IDX_W{1'b0}};
            latched_tag      <= {TAG_WIDTH{1'b0}};
            latched_victim_tag <= {TAG_WIDTH{1'b0}};
            bypass_data      <= 32'b0;
            cpu_req_ready_r  <= 1'b0;
            flush_set        <= {SET_IDX_W{1'b0}};
            flush_way        <= {WAY_W{1'b0}};
            flush_done_r     <= 1'b0;
            invalidate_set   <= {SET_IDX_W{1'b0}};
            tag_bram_enb_r   <= 1'b0;
            tag_bram_web_r   <= {TAG_BRAM_WEA{1'b0}};
            tag_bram_addrb_r <= {SET_IDX_W{1'b0}};
            tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= {NUM_WAYS-1{1'b0}};
            end
        end else begin
            cpu_req_ready_r <= 1'b0;
            flush_done_r    <= 1'b0;
            tag_bram_enb_r  <= 1'b0;  // default: no tag BRAM write

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    wb_req_r     <= 1'b0;
                    if (flush_req) begin
                        state     <= S_FLUSH_SCAN;
                        flush_set <= {SET_IDX_W{1'b0}};
                        flush_way <= {WAY_W{1'b0}};
                    end else if (cpu_req_valid && !cpu_req_ready_r) begin
                        if (is_mmio) begin
                            if (mmio_valid) begin
                                bypass_data     <= mmio_rdata;
                                cpu_req_ready_r <= 1'b1;
                            end
                        end else begin
                            // Enable tag BRAM Port A → output valid next cycle
                            state <= S_TAG_READ;
                        end
                    end
                end

                S_TAG_READ: begin
                    // Tag BRAM Port A output is now valid
                    // Wait for MMU ready (paddr valid) before tag comparison
                    if (!mmu_ready) begin
                        // Stay in S_TAG_READ until paddr is valid
                    end else if (cache_hit) begin
                        if (cpu_req_hwrite) begin
                            // Store hit: write data BRAM + set dirty in tag BRAM
                            tag_bram_enb_r   <= 1'b1;
                            tag_bram_web_r   <= (1 << hit_way);
                            tag_bram_addrb_r <= set_idx;
                            tag_bram_dinb_r  <= store_hit_tag_din;
                            plru_state[set_idx] <= plru_next;
                            cpu_req_ready_r <= 1'b1;
                            state <= S_IDLE;  // must return to S_IDLE; tag BRAM output is stale for new request
                        end else begin
                            // Load hit: enable data BRAM, go to S_READ_HIT
                            state <= S_READ_HIT;
                        end
                    end else begin
                        // Miss: latch victim info
                        latched_set        <= set_idx;
                        latched_victim_way <= victim_way;
                        latched_addr       <= cpu_req_addr;
                        latched_wdata      <= cpu_req_wdata;
                        latched_hwrite     <= cpu_req_hwrite;
                        latched_hsize      <= cpu_req_hsize;
                        latched_word_off   <= word_off;
                        latched_tag        <= req_tag;
                        latched_victim_tag <= tag_r_victim[TAG_WIDTH-1:0];
                        if (victim_dirty) begin
                            state <= S_WB_READ;
                        end else begin
                            refill_req_r  <= 1'b1;
                            refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, req_tag, set_idx, {ADDR_LOWER_ZEROS{1'b0}}};
                            state <= S_REFILL;
                        end
                    end
                end

                S_READ_HIT: begin
                    bypass_data     <= rdata_word;
                    cpu_req_ready_r <= 1'b1;
                    plru_state[set_idx] <= plru_next;
                    state <= S_IDLE;
                end

                S_WB_READ: begin
                    wb_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, latched_victim_tag, latched_set, {ADDR_LOWER_ZEROS{1'b0}}};
                    state <= S_WB_SEND;
                end

                S_WB_SEND: begin
                    wb_req_r <= 1'b1;
                    if (wb_valid) begin
                        wb_req_r      <= 1'b0;
                        // Clear dirty bit in tag BRAM
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= (1 << latched_victim_way);
                        tag_bram_addrb_r <= latched_set;
                        tag_bram_dinb_r  <= wb_clear_tag_din;
                        refill_req_r  <= 1'b1;
                        refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, latched_tag, latched_set, {ADDR_LOWER_ZEROS{1'b0}}};
                        state <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_valid) begin
                        refill_req_r    <= 1'b0;
                        bypass_data     <= refill_word;
                        cpu_req_ready_r <= 1'b1;
                        // Write tag BRAM: set valid, dirty=latched_hwrite, tag
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= (1 << latched_victim_way);
                        tag_bram_addrb_r <= latched_set;
                        tag_bram_dinb_r  <= refill_tag_din;
                        plru_state[latched_set] <= plru_next_miss;
                        state <= S_IDLE;
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
                    if (wb_valid) begin
                        wb_req_r <= 1'b0;
                        // Clear dirty bit in tag BRAM
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= (1 << latched_victim_way);
                        tag_bram_addrb_r <= latched_set;
                        tag_bram_dinb_r  <= wb_clear_tag_din;
                        // Advance to next way/set
                        if (latched_victim_way == NUM_WAYS - 1) begin
                            if (latched_set == NUM_SETS - 1) begin
                                // All done → invalidate all
                                state <= S_FLUSH_INVALIDATE;
                                invalidate_set <= {SET_IDX_W{1'b0}};
                            end else begin
                                flush_set <= latched_set + 1'b1;
                                flush_way <= {WAY_W{1'b0}};
                                state <= S_FLUSH_SCAN;
                            end
                        end else begin
                            flush_set <= latched_set;
                            flush_way <= latched_victim_way + 1'b1;
                            state <= S_FLUSH_SCAN;
                        end
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
                        state <= S_IDLE;
                    end else begin
                        invalidate_set <= invalidate_set + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
