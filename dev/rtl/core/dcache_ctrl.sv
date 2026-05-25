`timescale 1ns / 1ps
`include "ahb_def.svh"

module dcache_ctrl(
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
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
    input  wire [255:0] refill_data,
    input  wire        refill_valid,

    output wire        wb_req,
    output wire [31:0] wb_addr,
    output wire [255:0] wb_data,
    input  wire        wb_valid,

    input  wire        flush_req,
    output wire        flush_done
);

    localparam NUM_SETS  = 8;   // 组数
    localparam NUM_WAYS  = 4;   // 路数
    localparam TAG_WIDTH = 7;   // tag宽
    // 状态机状态
    localparam S_IDLE        = 3'd0;
    localparam S_READ_HIT    = 3'd1;
    localparam S_WB_READ     = 3'd2;
    localparam S_WB_SEND     = 3'd3;
    localparam S_REFILL      = 3'd4;
    localparam S_FLUSH_SCAN  = 3'd5;
    localparam S_FLUSH_WB_RD = 3'd6;
    localparam S_FLUSH_WB_SD = 3'd7;

    wire is_mmio = ~cpu_req_addr[31];

    wire [TAG_WIDTH-1:0] req_tag  = cpu_req_addr[14:8]; // Cache tag
    wire [2:0]            set_idx  = cpu_req_addr[7:5]; // Cache Index（组号）
    wire [2:0]            word_off = cpu_req_addr[4:2]; // 块内偏移

    reg [2:0] state; // 状态机

    reg [8:0] tag_ram [0:NUM_SETS-1][0:NUM_WAYS-1]; // 标志段寄存器（0~6:tag,7:D,8:V）
    reg [2:0] plru_state [0:NUM_SETS-1];            // PLRU算法寄存器

    wire [8:0] tag_r0 = tag_ram[set_idx][0];        // 取tag
    wire [8:0] tag_r1 = tag_ram[set_idx][1];
    wire [8:0] tag_r2 = tag_ram[set_idx][2];
    wire [8:0] tag_r3 = tag_ram[set_idx][3];

    wire hit0 = tag_r0[8] && (tag_r0[6:0] == req_tag); // 比较tag，测试有效位
    wire hit1 = tag_r1[8] && (tag_r1[6:0] == req_tag);
    wire hit2 = tag_r2[8] && (tag_r2[6:0] == req_tag);
    wire hit3 = tag_r3[8] && (tag_r3[6:0] == req_tag);

    wire cache_hit = hit0 | hit1 | hit2 | hit3;     // 命中判断

    wire [1:0] hit_way;             // 具体命中路
    assign hit_way = hit0 ? 2'd0 :
                     hit1 ? 2'd1 :
                     hit2 ? 2'd2 :
                            2'd3;

    wire inv0 = ~tag_r0[8];         // 统计无效行
    wire inv1 = ~tag_r1[8];
    wire inv2 = ~tag_r2[8];
    wire inv3 = ~tag_r3[8];

    wire [1:0] plru_victim;
    wire [2:0] plru_next;
    tree_plru u_plru(
        .plru_state (plru_state[set_idx]),
        .victim_way (plru_victim),
        .access_way (hit_way),
        .next_state (plru_next)
    );

    wire [1:0] victim_way = inv0 ? 2'd0 :               // 选择受害者行-优先填无效行，否则用PLRU
                            inv1 ? 2'd1 :
                            inv2 ? 2'd2 :
                            inv3 ? 2'd3 :
                            plru_victim;

    wire victim_dirty = tag_ram[set_idx][victim_way][7]; // 脏位

    reg [2:0]  latched_set;
    reg [1:0]  latched_victim_way;
    reg [31:0] latched_addr;
    reg [31:0] latched_wdata;
    reg        latched_hwrite;
    reg [2:0]  latched_hsize;
    reg [2:0]  latched_word_off;
    reg [6:0]  latched_tag;

    reg [2:0]  flush_set;
    reg [1:0]  flush_way;
    reg        flush_done_r;

    wire [4:0] bram_addra = {set_idx, hit_way};
    wire [4:0] bram_addrb = (state == S_FLUSH_WB_RD || state == S_FLUSH_WB_SD) ?
                            {flush_set, flush_way} :
                            {latched_set, latched_victim_way};

    wire [255:0] bram_douta;
    wire [255:0] bram_doutb;

    wire [3:0] word_byte_we;
    assign word_byte_we = (cpu_req_hsize == `AHB_SIZE_BYTE) ? (4'b0001 << cpu_req_addr[1:0]) :
                          (cpu_req_hsize == `AHB_SIZE_HWORD) ? (cpu_req_addr[1] ? 4'b1100 : 4'b0011) :
                          4'b1111;

    wire [31:0] word_store_data;
    assign word_store_data = (cpu_req_hsize == `AHB_SIZE_BYTE) ?
                             (cpu_req_wdata[7:0] << (cpu_req_addr[1:0] * 8)) :
                             cpu_req_wdata;

    wire [31:0]  store_full_wea  = ({28'b0, word_byte_we}) << (word_off * 4);
    wire [255:0] store_full_dina = ({224'b0, word_store_data}) << (word_off * 32);

    reg cpu_req_ready_r;

    wire is_store_hit = cpu_req_valid && !cpu_req_ready_r && !is_mmio && cache_hit && cpu_req_hwrite;
    wire is_load_hit  = cpu_req_valid && !cpu_req_ready_r && !is_mmio && cache_hit && !cpu_req_hwrite;

    wire bram_ena = (is_load_hit || is_store_hit) && (state == S_IDLE);
    wire [31:0]  bram_wea  = is_store_hit ? store_full_wea : 32'b0;
    wire [255:0] bram_dina = is_store_hit ? store_full_dina : 256'b0;

    wire [3:0] latched_word_byte_we;
    assign latched_word_byte_we = (latched_hsize == `AHB_SIZE_BYTE) ? (4'b0001 << latched_addr[1:0]) :
                                  (latched_hsize == `AHB_SIZE_HWORD) ? (latched_addr[1] ? 4'b1100 : 4'b0011) :
                                  4'b1111;

    wire [31:0] latched_word_store_data;
    assign latched_word_store_data = (latched_hsize == `AHB_SIZE_BYTE) ?
                                     (latched_wdata[7:0] << (latched_addr[1:0] * 8)) :
                                     latched_wdata;

    wire [31:0]  merge_full_wea  = ({28'b0, latched_word_byte_we}) << (latched_word_off * 4);
    wire [255:0] merge_full_dina = ({224'b0, latched_word_store_data}) << (latched_word_off * 32);

    wire [255:0] merged_line;
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin
            assign merged_line[gi*8 +: 8] = merge_full_wea[gi] ? merge_full_dina[gi*8 +: 8] : refill_data[gi*8 +: 8];
        end
    endgenerate

    wire [255:0] refill_bram_din = latched_hwrite ? merged_line : refill_data;

    wire bram_enb = (state == S_WB_READ) ||
                    (state == S_FLUSH_WB_RD) ||
                    (refill_valid && (state == S_REFILL));
    wire [31:0]  bram_web = (state == S_REFILL && refill_valid) ? 32'hFFFFFFFF : 32'b0;

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

    assign mmio_req    = (state == S_IDLE) && cpu_req_valid && is_mmio ? 1'b1 : 1'b0;
    assign mmio_addr   = cpu_req_addr;
    assign mmio_wdata  = cpu_req_wdata;
    assign mmio_hwrite = cpu_req_hwrite;
    assign mmio_hsize  = cpu_req_hsize;

    wire [2:0] plru_next_miss;
    tree_plru u_plru_miss(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (latched_victim_way),
        .next_state (plru_next_miss)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= S_IDLE;
            refill_req_r     <= 1'b0;
            refill_addr_r    <= 32'b0;
            wb_req_r         <= 1'b0;
            wb_addr_r        <= 32'b0;
            latched_set      <= 3'b0;
            latched_victim_way <= 2'b0;
            latched_addr     <= 32'b0;
            latched_wdata    <= 32'b0;
            latched_hwrite   <= 1'b0;
            latched_hsize    <= 3'b0;
            latched_word_off <= 3'b0;
            latched_tag      <= 7'b0;
            bypass_data      <= 32'b0;
            cpu_req_ready_r  <= 1'b0;
            flush_set        <= 3'b0;
            flush_way        <= 2'b0;
            flush_done_r     <= 1'b0;
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= 3'b0;
                for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                    tag_ram[s][w] <= 9'b0;
                end
            end
        end else begin
            cpu_req_ready_r <= 1'b0;
            flush_done_r    <= 1'b0;

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    wb_req_r     <= 1'b0;
                    if (flush_req) begin
                        state     <= S_FLUSH_SCAN;
                        flush_set <= 3'b0;
                        flush_way <= 2'b0;
                    end else if (cpu_req_valid && !cpu_req_ready_r) begin
                        if (is_mmio) begin
                            if (mmio_valid) begin
                                bypass_data     <= mmio_rdata;
                                cpu_req_ready_r <= 1'b1;
                            end
                        end else if (cache_hit) begin
                            if (cpu_req_hwrite) begin
                                tag_ram[set_idx][hit_way] <= {1'b1, 1'b1, tag_ram[set_idx][hit_way][6:0]};
                                plru_state[set_idx] <= plru_next;
                                cpu_req_ready_r <= 1'b1;
                            end else begin
                                state <= S_READ_HIT;
                            end
                        end else begin
                            latched_set        <= set_idx;
                            latched_victim_way <= victim_way;
                            latched_addr       <= cpu_req_addr;
                            latched_wdata      <= cpu_req_wdata;
                            latched_hwrite     <= cpu_req_hwrite;
                            latched_hsize      <= cpu_req_hsize;
                            latched_word_off   <= word_off;
                            latched_tag        <= req_tag;
                            if (victim_dirty) begin
                                state <= S_WB_READ;
                            end else begin
                                refill_req_r  <= 1'b1;
                                refill_addr_r <= {1'b1, 16'b0, req_tag, set_idx, 5'b0};
                                state <= S_REFILL;
                            end
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
                    wb_addr_r <= {1'b1, 16'b0, tag_ram[latched_set][latched_victim_way][6:0], latched_set, 5'b0};
                    state <= S_WB_SEND;
                end

                S_WB_SEND: begin
                    wb_req_r <= 1'b1;
                    if (wb_valid) begin
                        wb_req_r      <= 1'b0;
                        tag_ram[latched_set][latched_victim_way][7] <= 1'b0;
                        refill_req_r  <= 1'b1;
                        refill_addr_r <= {1'b1, 16'b0, latched_tag, latched_set, 5'b0};
                        state <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_valid) begin
                        refill_req_r    <= 1'b0;
                        bypass_data     <= refill_word;
                        cpu_req_ready_r <= 1'b1;
                        tag_ram[latched_set][latched_victim_way] <= {1'b1, latched_hwrite, latched_tag};
                        plru_state[latched_set] <= plru_next_miss;
                        state <= S_IDLE;
                    end
                end

                S_FLUSH_SCAN: begin
                    if (tag_ram[flush_set][flush_way][8] && tag_ram[flush_set][flush_way][7]) begin
                        latched_set        <= flush_set;
                        latched_victim_way <= flush_way;
                        state <= S_FLUSH_WB_RD;
                    end else begin
                        if (flush_way == 2'd3) begin
                            if (flush_set == 3'd7) begin
                                for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                                    for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                                        tag_ram[s][w][8] <= 1'b0;
                                    end
                                end
                                flush_done_r <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                flush_set <= flush_set + 3'd1;
                                flush_way <= 2'd0;
                            end
                        end else begin
                            flush_way <= flush_way + 2'd1;
                        end
                    end
                end

                S_FLUSH_WB_RD: begin
                    wb_addr_r <= {1'b1, 16'b0, tag_ram[flush_set][flush_way][6:0], flush_set, 5'b0};
                    state <= S_FLUSH_WB_SD;
                end

                S_FLUSH_WB_SD: begin
                    wb_req_r <= 1'b1;
                    if (wb_valid) begin
                        wb_req_r <= 1'b0;
                        tag_ram[flush_set][flush_way][7] <= 1'b0;
                        if (flush_way == 2'd3) begin
                            if (flush_set == 3'd7) begin
                                for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                                    for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                                        tag_ram[s][w][8] <= 1'b0;
                                    end
                                end
                                flush_done_r <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                flush_set <= flush_set + 3'd1;
                                flush_way <= 2'd0;
                                state <= S_FLUSH_SCAN;
                            end
                        end else begin
                            flush_way <= flush_way + 2'd1;
                            state <= S_FLUSH_SCAN;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
