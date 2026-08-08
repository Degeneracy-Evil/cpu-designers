`timescale 1ns / 1ps
`include "cache_def.svh"

// Blocking two-way ICache with register tags and BRAM line data.
// Accepted MMIO/refill transactions are always drained. A redirect may discard
// their architectural result, but it never cancels or retargets the bus access.
module icache_ctrl(
    input  wire        clk,
    input  wire        resetn,
    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    input  wire [31:0] cpu_req_vaddr,
    input  wire        mmu_ready,
    input  wire        flush_req,
    output wire [31:0] cpu_req_data,
    output wire        cpu_req_ready,

    output wire        mmio_req,
    input  wire        mmio_accept,
    output wire [31:0] mmio_addr,
    input  wire [31:0] mmio_data,
    input  wire        mmio_valid,

    output wire        refill_req,
    output wire [31:0] refill_addr,
    input  wire [`ICACHE_LINE_WIDTH-1:0] refill_data,
    input  wire        refill_valid,
    input  wire        refill_done,
    input  wire        refill_error,

    input  wire        invalidate_req,
    output wire        invalidate_done,
    output wire [2:0]  dbg_state
);
    localparam NUM_SETS   = `ICACHE_NUM_SETS;
    localparam TAG_WIDTH  = `ICACHE_TAG_WIDTH;
    localparam LINE_WIDTH = `ICACHE_LINE_WIDTH;
    localparam SET_W      = `ICACHE_SET_IDX_WIDTH;
    localparam WAY_W      = `ICACHE_WAY_WIDTH;
    localparam ADDR_W     = `ICACHE_ADDR_WIDTH;
    localparam WEA_W      = `ICACHE_WEA_WIDTH;

    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_LOOKUP     = 3'd1;
    localparam [2:0] S_READ_HIT   = 3'd2;
    localparam [2:0] S_REFILL     = 3'd3;
    localparam [2:0] S_MMIO_WAIT  = 3'd4;
    localparam [2:0] S_INVALIDATE = 3'd5;

    reg [2:0] state;
    reg valid_array [0:NUM_SETS-1][0:1];
    reg [TAG_WIDTH-1:0] tag_array [0:NUM_SETS-1][0:1];
    reg victim_array [0:NUM_SETS-1];

    reg [31:0] op_addr_r;
    reg [31:0] op_vaddr_r;
    reg [SET_W-1:0] op_set_r;
    reg [2:0] op_word_r;
    reg [TAG_WIDTH-1:0] op_tag_r;
    reg [WAY_W-1:0] fill_way_r;
    reg discard_r;

    wire hit0 = valid_array[op_set_r][0] &&
                (tag_array[op_set_r][0] == op_tag_r);
    wire hit1 = valid_array[op_set_r][1] &&
                (tag_array[op_set_r][1] == op_tag_r);
    wire cache_hit = hit0 || hit1;
    wire [WAY_W-1:0] hit_way = hit0 ? {WAY_W{1'b0}} : {{(WAY_W-1){1'b0}}, 1'b1};
    wire [WAY_W-1:0] victim_way = !valid_array[op_set_r][0] ? {WAY_W{1'b0}} :
                                   !valid_array[op_set_r][1] ? {{(WAY_W-1){1'b0}}, 1'b1} :
                                   victim_array[op_set_r];

    wire live_request_matches = cpu_req_valid &&
                                (cpu_req_vaddr == op_vaddr_r) &&
                                (!mmu_ready || (cpu_req_addr == op_addr_r));
    wire cpu_is_mmio = ~cpu_req_addr[31] || cpu_req_addr[30];

    reg mmio_pending_r;
    reg mmio_inflight_r;
    reg refill_req_r;
    reg [31:0] response_data_r;
    reg cpu_ready_r;
    reg invalidate_done_r;
    reg [SET_W-1:0] invalidate_set_r;

    assign mmio_req = mmio_pending_r;
    assign mmio_addr = op_addr_r;
    assign refill_req = refill_req_r;
    assign refill_addr = {op_addr_r[31:5], 5'b0};
    assign cpu_req_data = response_data_r;
    assign cpu_req_ready = cpu_ready_r;
    assign invalidate_done = invalidate_done_r;
    assign dbg_state = state;

    wire data_a_read = (state == S_LOOKUP) && cache_hit;
    wire [ADDR_W-1:0] data_a_addr = {op_set_r, hit_way};
    wire [LINE_WIDTH-1:0] data_a_out;
    wire refill_write = (state == S_REFILL) && refill_valid;
    wire [ADDR_W-1:0] data_b_addr = {op_set_r, fill_way_r};
    wire [LINE_WIDTH-1:0] data_b_out;

    icached u_icached(
        .clka(clk),
        .ena(data_a_read),
        .wea({WEA_W{1'b0}}),
        .addra(data_a_addr),
        .dina({LINE_WIDTH{1'b0}}),
        .douta(data_a_out),
        .clkb(clk),
        .enb(refill_write),
        .web({WEA_W{1'b1}}),
        .addrb(data_b_addr),
        .dinb(refill_data),
        .doutb(data_b_out)
    );

    integer s;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            op_addr_r <= 32'b0;
            op_vaddr_r <= 32'b0;
            op_set_r <= {SET_W{1'b0}};
            op_word_r <= 3'b0;
            op_tag_r <= {TAG_WIDTH{1'b0}};
            fill_way_r <= {WAY_W{1'b0}};
            discard_r <= 1'b0;
            mmio_pending_r <= 1'b0;
            mmio_inflight_r <= 1'b0;
            refill_req_r <= 1'b0;
            response_data_r <= 32'b0;
            cpu_ready_r <= 1'b0;
            invalidate_done_r <= 1'b0;
            invalidate_set_r <= {SET_W{1'b0}};
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                valid_array[s][0] <= 1'b0;
                valid_array[s][1] <= 1'b0;
                tag_array[s][0] <= {TAG_WIDTH{1'b0}};
                tag_array[s][1] <= {TAG_WIDTH{1'b0}};
                victim_array[s] <= 1'b0;
            end
        end else begin
            cpu_ready_r <= 1'b0;
            invalidate_done_r <= 1'b0;

            if (mmio_accept) begin
                mmio_pending_r <= 1'b0;
                mmio_inflight_r <= 1'b1;
            end

            // A pipeline redirect cancels only local lookups. Accepted external
            // transactions stay in their wait state until their response drains.
            if (flush_req && ((state == S_LOOKUP) || (state == S_READ_HIT))) begin
                state <= S_IDLE;
                discard_r <= 1'b0;
            end else begin
                if (flush_req && ((state == S_REFILL) || (state == S_MMIO_WAIT)))
                    discard_r <= 1'b1;

                case (state)
                    S_IDLE: begin
                        refill_req_r <= 1'b0;
                        if (invalidate_req) begin
                            invalidate_set_r <= {SET_W{1'b0}};
                            state <= S_INVALIDATE;
                        end else if (cpu_req_valid && mmu_ready && !cpu_ready_r) begin
                            op_addr_r <= cpu_req_addr;
                            op_vaddr_r <= cpu_req_vaddr;
                            op_set_r <= cpu_req_vaddr[`ICACHE_SET_IDX_HI:`ICACHE_SET_IDX_LO];
                            op_word_r <= cpu_req_vaddr[`ICACHE_WORD_OFF_HI:`ICACHE_WORD_OFF_LO];
                            op_tag_r <= cpu_req_addr[`ICACHE_TAG_HI:`ICACHE_TAG_LO];
                            discard_r <= 1'b0;
                            if (cpu_is_mmio) begin
                                mmio_pending_r <= 1'b1;
                                state <= S_MMIO_WAIT;
                            end else begin
                                state <= S_LOOKUP;
                            end
                        end
                    end

                    S_LOOKUP: begin
                        if (cache_hit) begin
                            state <= S_READ_HIT;
                        end else begin
                            fill_way_r <= victim_way;
                            refill_req_r <= 1'b1;
                            state <= S_REFILL;
                        end
                    end

                    S_READ_HIT: begin
                        if (!discard_r && live_request_matches) begin
                            response_data_r <= data_a_out[op_word_r*32 +: 32];
                            cpu_ready_r <= 1'b1;
                            victim_array[op_set_r] <= ~hit_way;
                        end
                        state <= S_IDLE;
                    end

                    S_REFILL: begin
                        refill_req_r <= 1'b1;
                        if (refill_done) begin
                            refill_req_r <= 1'b0;
                            if (!refill_error) begin
                                valid_array[op_set_r][fill_way_r] <= 1'b1;
                                tag_array[op_set_r][fill_way_r] <= op_tag_r;
                                victim_array[op_set_r] <= ~fill_way_r;
                                if (!discard_r && live_request_matches) begin
                                    response_data_r <= refill_data[op_word_r*32 +: 32];
                                    cpu_ready_r <= 1'b1;
                                end
                            end
                            discard_r <= 1'b0;
                            state <= S_IDLE;
                        end
                    end

                    S_MMIO_WAIT: begin
                        if (mmio_valid) begin
                            mmio_inflight_r <= 1'b0;
                            if (!discard_r && live_request_matches) begin
                                response_data_r <= mmio_data;
                                cpu_ready_r <= 1'b1;
                            end
                            discard_r <= 1'b0;
                            state <= S_IDLE;
                        end
                    end

                    S_INVALIDATE: begin
                        valid_array[invalidate_set_r][0] <= 1'b0;
                        valid_array[invalidate_set_r][1] <= 1'b0;
                        victim_array[invalidate_set_r] <= 1'b0;
                        if (invalidate_set_r == NUM_SETS - 1) begin
                            invalidate_done_r <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            invalidate_set_r <= invalidate_set_r + 1'b1;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
