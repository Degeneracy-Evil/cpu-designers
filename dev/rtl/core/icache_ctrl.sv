`timescale 1ns / 1ps
`include "cache_def.svh"

module icache_ctrl(
    input  wire        clk,
    input  wire        resetn,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    input  wire [31:0] cpu_req_vaddr,
    input  wire        mmu_ready,
    output wire [31:0] cpu_req_data,
    output wire        cpu_req_ready,

    output wire        mmio_req,
    output wire [31:0] mmio_addr,
    input  wire [31:0] mmio_data,
    input  wire        mmio_valid,

    output wire        refill_req,
    output wire [31:0] refill_addr,
    input  wire [`ICACHE_LINE_WIDTH-1:0] refill_data,
    input  wire        refill_valid,

    input  wire        invalidate_req,
    output wire        invalidate_done
);

    // --- Cache geometry from config ---
    localparam NUM_SETS      = `ICACHE_NUM_SETS;
    localparam NUM_WAYS      = `ICACHE_NUM_WAYS;
    localparam TAG_WIDTH     = `ICACHE_TAG_WIDTH;
    localparam LINE_WIDTH    = `ICACHE_LINE_WIDTH;
    localparam BRAM_ADDR_W   = `ICACHE_ADDR_WIDTH;
    localparam WEA_WIDTH     = `ICACHE_WEA_WIDTH;
    localparam TAG_ENTRY_W   = `ICACHE_TAG_ENTRY_WIDTH;
    localparam SET_IDX_W     = `ICACHE_SET_IDX_WIDTH;
    localparam WAY_W         = `ICACHE_WAY_WIDTH;
    localparam TAG_BRAM_W    = `ICACHE_TAG_BRAM_WIDTH;
    localparam TAG_BRAM_WEA  = `ICACHE_TAG_BRAM_WEA_WIDTH;
    localparam TAG_BRAM_BS   = `ICACHE_TAG_BRAM_BYTE_SIZE;
    localparam TAG_BRAM_BPW  = `ICACHE_TAG_BRAM_WEA_BITS_PER_WAY;
    // Derived: address layout
    localparam ADDR_UPPER_ZEROS = 30 - `ICACHE_TAG_HI;
    localparam ADDR_LOWER_ZEROS = `ICACHE_SET_IDX_LO;

    localparam S_IDLE       = 3'd0;
    localparam S_TAG_READ   = 3'd1;
    localparam S_READ       = 3'd2;
    localparam S_REFILL     = 3'd3;
    localparam S_INVALIDATE = 3'd4;

    // Address map:
    //   0x00000000-0x7FFFFFFF: MMIO (peripherals)     — bit[31]=0
    //   0x80000000-0x87FFFFFF: Cacheable (DDR3, 128MB) — bit[31]=1, bit[30]=0, bits[29:27]=0
    //   0x88000000-0xBFFFFFFF: Unmapped (no physical memory; tag aliasing risk if accessed)
    //   0xC0000000-0xFFFFFFFF: MMIO (boot ROM, etc.)  — bit[31]=1, bit[30]=1
    // Boot ROM at 0xFC000000 MUST be uncached: addresses with bit[30]=1
    // are classified as MMIO, so they bypass the cache entirely.
    // Tag width (19 bits) covers exactly 128MB; bits[29:27] are forced zero
    // in refill addresses (ADDR_UPPER_ZEROS=4), so only 0x8000_0000–0x87FF_FFFF
    // is safely cacheable without aliasing.
    wire is_mmio = ~cpu_req_vaddr[31] | cpu_req_vaddr[30];

    // VIPT: use vaddr for set index (bits within page offset), paddr for tag
    wire [TAG_WIDTH-1:0]   req_tag  = cpu_req_addr[`ICACHE_TAG_HI:`ICACHE_TAG_LO];
    wire [SET_IDX_W-1:0]   set_idx  = cpu_req_vaddr[`ICACHE_SET_IDX_HI:`ICACHE_SET_IDX_LO];
    wire [SET_IDX_W-1:0]   word_off = cpu_req_vaddr[`ICACHE_WORD_OFF_HI:`ICACHE_WORD_OFF_LO];

    reg [2:0] state;

    // --- PLRU state (kept as registers — too small for BRAM) ---
    reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

    // =========================================================================
    // Tag BRAM (icachet) — 144-bit × 8 deep, Byte_Size=36, 4-bit WEA
    // Each address = 1 set, data = 4 ways packed: {Way3, Way2, Way1, Way0}
    //   Way N bits: [N*36 +: 36], lower 20 bits = {V(1), tag(19)}, upper 16 = padding
    // =========================================================================
    wire [TAG_BRAM_W-1:0] tag_bram_douta;
    wire [TAG_BRAM_W-1:0] tag_bram_doutb;

    // Port A: CPU read (enable in S_IDLE → output valid in S_TAG_READ)
    wire tag_bram_ena = (state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && !is_mmio;

    // Port B: Refill write / Invalidate write (registered, applied next cycle)
    reg                          tag_bram_enb_r;
    reg [TAG_BRAM_WEA-1:0]      tag_bram_web_r;
    reg [SET_IDX_W-1:0]         tag_bram_addrb_r;
    reg [TAG_BRAM_W-1:0]        tag_bram_dinb_r;

    icachet u_icachet(
        .clka   (clk),
        .ena    (tag_bram_ena),
        .wea    ({TAG_BRAM_WEA{1'b0}}),      // Port A: read only
        .addra  (set_idx),                    // 3-bit set index
        .dina   ({TAG_BRAM_W{1'b0}}),
        .douta  (tag_bram_douta),

        .clkb   (clk),
        .enb    (tag_bram_enb_r),
        .web    (tag_bram_web_r),
        .addrb  (tag_bram_addrb_r),
        .dinb   (tag_bram_dinb_r),
        .doutb  (tag_bram_doutb)
    );

    // --- Tag comparison from BRAM Port A output (valid in S_TAG_READ) ---
    // Each way occupies TAG_BRAM_BS bits in the BRAM word, but only the lower
    // TAG_ENTRY_W bits are meaningful (valid bit + tag). Upper padding is zero.
    wire [TAG_BRAM_BS-1:0] way0_raw = tag_bram_douta[TAG_BRAM_BS*1-1:TAG_BRAM_BS*0];
    wire [TAG_BRAM_BS-1:0] way1_raw = tag_bram_douta[TAG_BRAM_BS*2-1:TAG_BRAM_BS*1];
    wire [TAG_BRAM_BS-1:0] way2_raw = tag_bram_douta[TAG_BRAM_BS*3-1:TAG_BRAM_BS*2];
    wire [TAG_BRAM_BS-1:0] way3_raw = tag_bram_douta[TAG_BRAM_BS*4-1:TAG_BRAM_BS*3];
    wire [TAG_ENTRY_W-1:0] tag_r0 = way0_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r1 = way1_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r2 = way2_raw[TAG_ENTRY_W-1:0];
    wire [TAG_ENTRY_W-1:0] tag_r3 = way3_raw[TAG_ENTRY_W-1:0];

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

    reg [SET_IDX_W-1:0]  latched_set;
    reg [WAY_W-1:0]      refill_way;
    reg [31:0] latched_addr;

    // =========================================================================
    // Data BRAM (icached) — 256-bit × 32 deep
    // =========================================================================
    wire [BRAM_ADDR_W-1:0] bram_addra = {set_idx, hit_way};
    wire [BRAM_ADDR_W-1:0] bram_addrb = {latched_set, refill_way};

    wire [LINE_WIDTH-1:0] bram_douta;
    wire [LINE_WIDTH-1:0] bram_doutb;

    reg cpu_req_ready_r;
    reg  invalidate_done_r;

    // Data BRAM Port A: enable in S_TAG_READ on hit (hit_way now known)
    // Gated by mmu_ready to avoid reading with stale paddr
    wire bram_ena = (state == S_TAG_READ) && cache_hit && mmu_ready;
    wire bram_enb = refill_valid && (state == S_REFILL);

    icached u_icached(
        .clka   (clk),
        .ena    (bram_ena),
        .wea    ({WEA_WIDTH{1'b0}}),
        .addra  (bram_addra),
        .dina   ({LINE_WIDTH{1'b0}}),
        .douta  (bram_douta),

        .clkb   (clk),
        .enb    (bram_enb),
        .web    ({WEA_WIDTH{1'b1}}),
        .addrb  (bram_addrb),
        .dinb   (refill_data),
        .doutb  (bram_doutb)
    );

    reg [31:0] bypass_data;

    wire [SET_IDX_W-1:0] sel_word_off = (state == S_REFILL) ? latched_addr[`ICACHE_WORD_OFF_HI:`ICACHE_WORD_OFF_LO] : word_off;
    wire [LINE_WIDTH-1:0] sel_line     = (state == S_REFILL) ? refill_data : bram_douta;
    wire [31:0]  sel_word;
    assign sel_word = sel_line[sel_word_off*32 +: 32];

    assign cpu_req_data = is_mmio ? mmio_data : bypass_data;

    reg refill_req_r;
    reg [31:0] refill_addr_r;

    assign refill_req  = refill_req_r;
    assign refill_addr = refill_addr_r;

    assign mmio_req  = is_mmio ? (cpu_req_valid && mmu_ready) : 1'b0;
    assign mmio_addr = cpu_req_addr;

    assign cpu_req_ready = cpu_req_ready_r;
    assign invalidate_done = invalidate_done_r;

    wire [NUM_WAYS-2:0] plru_next_refill;
    tree_plru u_plru_refill(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (refill_way),
        .next_state (plru_next_refill)
    );

    // --- Invalidate counter (multi-cycle: 1 BRAM write per set) ---
    reg [SET_IDX_W-1:0] invalidate_set;

    // --- Helper: pack a single way's tag entry into the BRAM line position ---
    // new_entry is TAG_ENTRY_W bits wide; placed at refill_way * TAG_BRAM_BS offset
    wire [TAG_ENTRY_W-1:0] refill_new_entry = {1'b1, latched_addr[`ICACHE_TAG_HI:`ICACHE_TAG_LO]};
    wire [TAG_BRAM_W-1:0]  refill_tag_din   = ({TAG_BRAM_W{1'b0}} | {{(TAG_BRAM_W-TAG_ENTRY_W){1'b0}}, refill_new_entry}) << (refill_way * TAG_BRAM_BS);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state            <= S_IDLE;
            refill_req_r     <= 1'b0;
            refill_addr_r    <= 32'b0;
            latched_set      <= {SET_IDX_W{1'b0}};
            refill_way       <= {WAY_W{1'b0}};
            latched_addr     <= 32'b0;
            bypass_data      <= 32'b0;
            cpu_req_ready_r  <= 1'b0;
            invalidate_done_r <= 1'b0;
            invalidate_set   <= {SET_IDX_W{1'b0}};
            tag_bram_enb_r   <= 1'b0;
            tag_bram_web_r   <= {TAG_BRAM_WEA{1'b0}};
            tag_bram_addrb_r <= {SET_IDX_W{1'b0}};
            tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= {NUM_WAYS-1{1'b0}};
            end
        end else begin
            cpu_req_ready_r  <= 1'b0;
            invalidate_done_r <= 1'b0;
            tag_bram_enb_r   <= 1'b0;  // default: no tag BRAM write

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    if (invalidate_req) begin
                        state <= S_INVALIDATE;
                        invalidate_set <= {SET_IDX_W{1'b0}};
                    end else if (cpu_req_valid && !cpu_req_ready_r) begin
                        if (is_mmio) begin
                            if (mmio_valid) begin
                                bypass_data     <= mmio_data;
                                cpu_req_ready_r <= 1'b1;
                            end
                        end else begin
                            // Enable tag BRAM Port A (addra=set_idx already wired)
                            // Output will be valid next cycle in S_TAG_READ
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
                        // Data BRAM Port A enabled this cycle (bram_ena above)
                        // Data available next cycle in S_READ
                        state <= S_READ;
                    end else begin
                        latched_set  <= set_idx;
                        latched_addr <= cpu_req_addr;
                        refill_way   <= victim_way;
                        refill_req_r <= 1'b1;
                        refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, req_tag, set_idx, {ADDR_LOWER_ZEROS{1'b0}}};
                        state <= S_REFILL;
                    end
                end

                S_READ: begin
                    // Data BRAM Port A output is now valid
                    bypass_data     <= sel_word;
                    cpu_req_ready_r <= 1'b1;
                    plru_state[set_idx] <= plru_next;
                    state <= S_IDLE;
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_valid) begin
                        refill_req_r    <= 1'b0;
                        bypass_data     <= sel_word;
                        cpu_req_ready_r <= 1'b1;
                        // Write tag BRAM Port B: update only the refilled way
                        tag_bram_enb_r   <= 1'b1;
                        tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1) << (refill_way * TAG_BRAM_BPW);
                        tag_bram_addrb_r <= latched_set;
                        tag_bram_dinb_r  <= refill_tag_din;
                        plru_state[latched_set] <= plru_next_refill;
                        state <= S_IDLE;
                    end
                end

                S_INVALIDATE: begin
                    // Write one set per cycle with all zeros (clear all valid bits)
                    tag_bram_enb_r   <= 1'b1;
                    tag_bram_web_r   <= {TAG_BRAM_WEA{1'b1}};   // write all 4 ways
                    tag_bram_addrb_r <= invalidate_set;
                    tag_bram_dinb_r  <= {TAG_BRAM_W{1'b0}};     // all zeros
                    if (invalidate_set == NUM_SETS - 1) begin
                        // Last set written — done
                        for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                            plru_state[s] <= {NUM_WAYS-1{1'b0}};
                        end
                        invalidate_done_r <= 1'b1;
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
