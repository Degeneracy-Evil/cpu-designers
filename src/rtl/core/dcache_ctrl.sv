`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "cache_def.svh"

// Blocking, two-way, write-through DCache.
//
// Loads allocate a complete line on miss. Stores always complete at the
// backing AXI memory first; a hit updates the cached bytes after the write
// response, while a miss is deliberately not allocated. There are no dirty
// lines, victim writebacks, MSHRs or cancelled transactions.
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
    input  wire        mmio_accept,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire        mmio_hwrite,
    output wire [2:0]  mmio_hsize,
    input  wire [31:0] mmio_rdata,
    input  wire        mmio_valid,
    input  wire        mmio_error,

    output wire        refill_req,
    output wire [31:0] refill_addr,
    input  wire [`DCACHE_LINE_WIDTH-1:0] refill_data,
    input  wire        refill_valid,
    input  wire        refill_done,
    input  wire        refill_error,

    // PTW writes A/D bits directly to memory. Because all tags are registers
    // and PTW runs while the CPU data access is stalled, a one-cycle snoop can
    // update an already-cached PTE without an invalidate/flush state machine.
    input  wire        snoop_write_valid,
    input  wire [31:0] snoop_write_addr,
    input  wire [31:0] snoop_write_data
);
    localparam NUM_SETS   = `DCACHE_NUM_SETS;
    localparam TAG_WIDTH  = `DCACHE_TAG_WIDTH;
    localparam LINE_WIDTH = `DCACHE_LINE_WIDTH;
    localparam SET_W      = `DCACHE_SET_IDX_WIDTH;
    localparam WAY_W      = `DCACHE_WAY_WIDTH;
    localparam ADDR_W     = `DCACHE_ADDR_WIDTH;
    localparam WEA_W      = `DCACHE_WEA_WIDTH;

    localparam [2:0] S_IDLE        = 3'd0;
    localparam [2:0] S_LOOKUP      = 3'd1;
    localparam [2:0] S_READ_HIT    = 3'd2;
    localparam [2:0] S_REFILL      = 3'd3;
    localparam [2:0] S_STORE_WAIT  = 3'd4;
    localparam [2:0] S_BYPASS_WAIT = 3'd5;

    reg [2:0] state;

    reg                    valid_array [0:NUM_SETS-1][0:1];
    reg [TAG_WIDTH-1:0]    tag_array   [0:NUM_SETS-1][0:1];
    reg                    victim_array[0:NUM_SETS-1];

    reg [31:0] op_addr_r;
    reg [31:0] op_vaddr_r;
    reg [31:0] op_wdata_r;
    reg        op_write_r;
    reg [2:0]  op_size_r;
    reg [SET_W-1:0] op_set_r;
    reg [2:0]  op_word_r;
    reg [TAG_WIDTH-1:0] op_tag_r;
    reg [WAY_W-1:0] store_way_r;
    reg store_hit_r;

    wire hit0 = valid_array[op_set_r][0] &&
                (tag_array[op_set_r][0] == op_tag_r);
    wire hit1 = valid_array[op_set_r][1] &&
                (tag_array[op_set_r][1] == op_tag_r);
    wire cache_hit = hit0 || hit1;
    wire [WAY_W-1:0] hit_way = hit0 ? {WAY_W{1'b0}} : {{(WAY_W-1){1'b0}}, 1'b1};
    wire [WAY_W-1:0] fill_way = !valid_array[op_set_r][0] ? {WAY_W{1'b0}} :
                                 !valid_array[op_set_r][1] ? {{(WAY_W-1){1'b0}}, 1'b1} :
                                 victim_array[op_set_r];

    wire cpu_is_mmio = ~cpu_req_addr[31] || cpu_req_addr[30];

    reg mmio_pending_r;
    reg mmio_inflight_r;
    reg refill_req_r;
    reg [31:0] refill_addr_r;
    reg [31:0] response_data_r;
    reg cpu_ready_r;

    assign mmio_req = mmio_pending_r;
    assign mmio_addr = op_addr_r;
    assign mmio_wdata = op_wdata_r;
    assign mmio_hwrite = op_write_r;
    assign mmio_hsize = op_size_r;
    assign refill_req = refill_req_r;
    assign refill_addr = refill_addr_r;
    assign cpu_req_rdata = response_data_r;
    assign cpu_req_ready = cpu_ready_r;

    wire [3:0] store_byte_we =
        (op_size_r == `AXI_SIZE_BYTE)  ? (4'b0001 << op_addr_r[1:0]) :
        (op_size_r == `AXI_SIZE_HWORD) ? (op_addr_r[1] ? 4'b1100 : 4'b0011) :
                                         4'b1111;
    wire [31:0] store_word_data =
        (op_size_r == `AXI_SIZE_BYTE) ? (op_wdata_r[7:0] << (op_addr_r[1:0] * 8)) :
                                        op_wdata_r;
    wire [WEA_W-1:0] store_line_we =
        ({{(WEA_W-4){1'b0}}, store_byte_we} << (op_word_r * 4));
    wire [LINE_WIDTH-1:0] store_line_data =
        ({{(LINE_WIDTH-32){1'b0}}, store_word_data} << (op_word_r * 32));

    wire data_a_read = (state == S_LOOKUP) && !op_write_r && cache_hit;
    wire data_a_store = (state == S_STORE_WAIT) && mmio_valid &&
                        !mmio_error && store_hit_r;
    wire [ADDR_W-1:0] data_a_addr = data_a_store ?
                                      {op_set_r, store_way_r} :
                                      {op_set_r, hit_way};
    wire [LINE_WIDTH-1:0] data_a_out;

    wire [SET_W-1:0] snoop_set = snoop_write_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
    wire [TAG_WIDTH-1:0] snoop_tag = snoop_write_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
    wire snoop_hit0 = valid_array[snoop_set][0] && (tag_array[snoop_set][0] == snoop_tag);
    wire snoop_hit1 = valid_array[snoop_set][1] && (tag_array[snoop_set][1] == snoop_tag);
    wire snoop_hit = snoop_hit0 || snoop_hit1;
    wire [WAY_W-1:0] snoop_way = snoop_hit0 ? {WAY_W{1'b0}} : {{(WAY_W-1){1'b0}}, 1'b1};
    wire [2:0] snoop_word = snoop_write_addr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];
    wire [WEA_W-1:0] snoop_line_we =
        ({{(WEA_W-4){1'b0}}, 4'b1111} << (snoop_word * 4));
    wire [LINE_WIDTH-1:0] snoop_line_data =
        ({{(LINE_WIDTH-32){1'b0}}, snoop_write_data} << (snoop_word * 32));

    wire refill_write = (state == S_REFILL) && refill_valid;
    wire snoop_write = snoop_write_valid && snoop_hit;
    wire [ADDR_W-1:0] data_b_addr = refill_write ?
                                      {op_set_r, fill_way} :
                                      {snoop_set, snoop_way};
    wire [WEA_W-1:0] data_b_we = refill_write ? {WEA_W{1'b1}} : snoop_line_we;
    wire [LINE_WIDTH-1:0] data_b_in = refill_write ? refill_data : snoop_line_data;
    wire [LINE_WIDTH-1:0] data_b_out;

    dcached u_dcached(
        .clka(clk),
        .ena(data_a_read || data_a_store),
        .wea(data_a_store ? store_line_we : {WEA_W{1'b0}}),
        .addra(data_a_addr),
        .dina(data_a_store ? store_line_data : {LINE_WIDTH{1'b0}}),
        .douta(data_a_out),
        .clkb(clk),
        .enb(refill_write || snoop_write),
        .web(data_b_we),
        .addrb(data_b_addr),
        .dinb(data_b_in),
        .doutb(data_b_out)
    );

    integer s;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            op_addr_r <= 32'b0;
            op_vaddr_r <= 32'b0;
            op_wdata_r <= 32'b0;
            op_write_r <= 1'b0;
            op_size_r <= `AXI_SIZE_WORD;
            op_set_r <= {SET_W{1'b0}};
            op_word_r <= 3'b0;
            op_tag_r <= {TAG_WIDTH{1'b0}};
            store_way_r <= {WAY_W{1'b0}};
            store_hit_r <= 1'b0;
            mmio_pending_r <= 1'b0;
            mmio_inflight_r <= 1'b0;
            refill_req_r <= 1'b0;
            refill_addr_r <= 32'b0;
            response_data_r <= 32'b0;
            cpu_ready_r <= 1'b0;
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                valid_array[s][0] <= 1'b0;
                valid_array[s][1] <= 1'b0;
                tag_array[s][0] <= {TAG_WIDTH{1'b0}};
                tag_array[s][1] <= {TAG_WIDTH{1'b0}};
                victim_array[s] <= 1'b0;
            end
        end else begin
            cpu_ready_r <= 1'b0;

            if (mmio_accept) begin
                mmio_pending_r <= 1'b0;
                mmio_inflight_r <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    if (cpu_req_valid && mmu_ready && !cpu_ready_r) begin
                        op_addr_r <= cpu_req_addr;
                        op_vaddr_r <= cpu_req_vaddr;
                        op_wdata_r <= cpu_req_wdata;
                        op_write_r <= cpu_req_hwrite;
                        op_size_r <= cpu_req_hsize;
                        op_set_r <= cpu_req_vaddr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
                        op_word_r <= cpu_req_vaddr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];
                        op_tag_r <= cpu_req_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
                        if (cpu_is_mmio)
                            state <= S_BYPASS_WAIT;
                        else
                            state <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (op_write_r) begin
                        store_hit_r <= cache_hit;
                        store_way_r <= hit_way;
                        mmio_pending_r <= 1'b1;
                        state <= S_STORE_WAIT;
                    end else if (cache_hit) begin
                        state <= S_READ_HIT;
                    end else begin
                        refill_addr_r <= {op_addr_r[31:5], 5'b0};
                        refill_req_r <= 1'b1;
                        state <= S_REFILL;
                    end
                end

                S_READ_HIT: begin
                    response_data_r <= data_a_out[op_word_r*32 +: 32];
                    cpu_ready_r <= 1'b1;
                    victim_array[op_set_r] <= ~hit_way;
                    state <= S_IDLE;
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_done) begin
                        refill_req_r <= 1'b0;
                        if (refill_error) begin
                            state <= S_IDLE;
                        end else begin
                            valid_array[op_set_r][fill_way] <= 1'b1;
                            tag_array[op_set_r][fill_way] <= op_tag_r;
                            victim_array[op_set_r] <= ~fill_way;
                            response_data_r <= refill_data[op_word_r*32 +: 32];
                            cpu_ready_r <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end

                S_STORE_WAIT: begin
                    if (mmio_valid) begin
                        mmio_inflight_r <= 1'b0;
                        if (store_hit_r && !mmio_error)
                            victim_array[op_set_r] <= ~store_way_r;
                        cpu_ready_r <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_BYPASS_WAIT: begin
                    if (!mmio_pending_r && !mmio_inflight_r)
                        mmio_pending_r <= 1'b1;
                    if (mmio_valid) begin
                        mmio_inflight_r <= 1'b0;
                        response_data_r <= mmio_rdata;
                        cpu_ready_r <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
