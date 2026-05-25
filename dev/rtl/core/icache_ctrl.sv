`timescale 1ns / 1ps
`include "cache_def.svh"

module icache_ctrl(
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
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
    // Derived: address layout
    localparam ADDR_UPPER_ZEROS = 30 - `ICACHE_TAG_HI;
    localparam ADDR_LOWER_ZEROS = `ICACHE_SET_IDX_LO;

    localparam S_IDLE       = 2'd0;
    localparam S_READ       = 2'd1;
    localparam S_REFILL    = 2'd2;
    localparam S_INVALIDATE = 2'd3;

    wire is_mmio = ~cpu_req_addr[31];

    wire [TAG_WIDTH-1:0]   req_tag  = cpu_req_addr[`ICACHE_TAG_HI:`ICACHE_TAG_LO];
    wire [SET_IDX_W-1:0]   set_idx  = cpu_req_addr[`ICACHE_SET_IDX_HI:`ICACHE_SET_IDX_LO];
    wire [SET_IDX_W-1:0]   word_off = cpu_req_addr[`ICACHE_WORD_OFF_HI:`ICACHE_WORD_OFF_LO];

    reg [1:0] state;

    reg [TAG_ENTRY_W-1:0] tag_ram [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [NUM_WAYS-2:0] plru_state [0:NUM_SETS-1];

    wire [TAG_ENTRY_W-1:0] tag_r0 = tag_ram[set_idx][0];
    wire [TAG_ENTRY_W-1:0] tag_r1 = tag_ram[set_idx][1];
    wire [TAG_ENTRY_W-1:0] tag_r2 = tag_ram[set_idx][2];
    wire [TAG_ENTRY_W-1:0] tag_r3 = tag_ram[set_idx][3];

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

    wire [BRAM_ADDR_W-1:0] bram_addra = {set_idx, hit_way};
    wire [BRAM_ADDR_W-1:0] bram_addrb = {latched_set, refill_way};

    wire [LINE_WIDTH-1:0] bram_douta;
    wire [LINE_WIDTH-1:0] bram_doutb;

    reg cpu_req_ready_r;
    reg  invalidate_done_r;

    wire bram_ena = (state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && !is_mmio;
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

    assign mmio_req  = is_mmio ? cpu_req_valid : 1'b0;
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

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= S_IDLE;
            refill_req_r  <= 1'b0;
            refill_addr_r <= 32'b0;
            latched_set   <= {SET_IDX_W{1'b0}};
            refill_way    <= {WAY_W{1'b0}};
            latched_addr  <= 32'b0;
            bypass_data   <= 32'b0;
            cpu_req_ready_r <= 1'b0;
            invalidate_done_r <= 1'b0;
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= {NUM_WAYS-1{1'b0}};
                for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                    tag_ram[s][w] <= {TAG_ENTRY_W{1'b0}};
                end
            end
        end else begin
            cpu_req_ready_r <= 1'b0;
            invalidate_done_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    if (invalidate_req) begin
                        state <= S_INVALIDATE;
                    end else if (cpu_req_valid && !cpu_req_ready_r) begin
                        if (is_mmio) begin
                            if (mmio_valid) begin
                                bypass_data     <= mmio_data;
                                cpu_req_ready_r <= 1'b1;
                            end
                        end else begin
                            state <= S_READ;
                        end
                    end
                end

                S_READ: begin
                    if (cache_hit) begin
                        bypass_data     <= sel_word;
                        cpu_req_ready_r <= 1'b1;
                        plru_state[set_idx] <= plru_next;
                        state <= S_IDLE;
                    end else begin
                        latched_set  <= set_idx;
                        latched_addr <= cpu_req_addr;
                        refill_way   <= victim_way;
                        refill_req_r <= 1'b1;
                        refill_addr_r <= {1'b1, {ADDR_UPPER_ZEROS{1'b0}}, req_tag, set_idx, {ADDR_LOWER_ZEROS{1'b0}}};
                        state <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_valid) begin
                        refill_req_r    <= 1'b0;
                        bypass_data     <= sel_word;
                        cpu_req_ready_r <= 1'b1;
                        tag_ram[latched_set][refill_way] <= {1'b1, latched_addr[`ICACHE_TAG_HI:`ICACHE_TAG_LO]};
                        plru_state[latched_set] <= plru_next_refill;
                        state <= S_IDLE;
                    end
                end

                S_INVALIDATE: begin
                    for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                        plru_state[s] <= {NUM_WAYS-1{1'b0}};
                        for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                            tag_ram[s][w] <= {TAG_ENTRY_W{1'b0}};
                        end
                    end
                    invalidate_done_r <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
