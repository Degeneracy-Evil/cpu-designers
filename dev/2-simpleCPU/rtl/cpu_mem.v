`timescale 1ns / 1ps

// 访存单元 跳过方式：is_load/is_store
module cpu_mem(
    input              clk,
    input              reset,
    input              mem_valid,
    input      [141:0] exe_mem_bus_r,
    output             dcache_en,
    output     [0:0]   dcache_we,
    output     [10:0]  dcache_addr,
    output     [31:0]  dcache_wdata,
    input      [31:0]  dcache_rdata,
    output             mem_done,
    output     [102:0] mem_wb_bus,

    // display使用
    output     [31:0]  mem_pc,
    output     [31:0]  mem_inst
);

    localparam MEM_IDLE = 2'd0;
    localparam MEM_READ = 2'd1;
    localparam MEM_WRITE_MODIFY = 2'd2;
    localparam MEM_WRITE_COMMIT = 2'd3;

    wire valid_inst;
    wire is_jal_like;
    wire is_load;
    wire is_store;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] alu_result;
    wire [2:0] mem_size;
    wire mem_unsigned;
    wire [31:0] store_data;
    wire [31:0] pc;
    wire [31:0] inst;

    assign {
        valid_inst,
        is_jal_like,
        is_load,
        is_store,
        wb_we,
        wb_rd,
        alu_result,
        mem_size,
        mem_unsigned,
        store_data,
        pc,
        inst
    } = exe_mem_bus_r;

    reg [1:0] mem_state;
    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;
    reg [2:0] mem_size_reg;
    reg mem_unsigned_reg;
    reg [31:0] read_word_reg;
    reg [31:0] wb_data_reg;
    reg wb_we_reg;
    reg [4:0] wb_rd_reg;
    reg done_reg;
    reg en_reg;
    reg we_reg;
    reg [10:0] daddr_reg;
    reg mem_seen_valid;

    wire [1:0] byte_offset;
    assign byte_offset = addr_reg[1:0];

    wire [31:0] mem_word_for_extract;
    assign mem_word_for_extract = (mem_state == MEM_READ || mem_state == MEM_WRITE_MODIFY) ? dcache_rdata : read_word_reg;

    wire [7:0] selected_byte;
    assign selected_byte = (byte_offset == 2'b00) ? mem_word_for_extract[7:0] :
                           (byte_offset == 2'b01) ? mem_word_for_extract[15:8] :
                           (byte_offset == 2'b10) ? mem_word_for_extract[23:16] :
                                                    mem_word_for_extract[31:24];

    wire [15:0] selected_half;
    assign selected_half = byte_offset[1] ? mem_word_for_extract[31:16] : mem_word_for_extract[15:0];

    wire [31:0] load_value;
    assign load_value = (mem_size_reg == 3'b000) ?
                        (mem_unsigned_reg ? {24'b0, selected_byte} : {{24{selected_byte[7]}}, selected_byte}) :
                        (mem_size_reg == 3'b001) ?
                        (mem_unsigned_reg ? {16'b0, selected_half} : {{16{selected_half[15]}}, selected_half}) :
                        mem_word_for_extract;

    wire misalign_load;
    wire misalign_store;
    assign misalign_load = is_load && ((mem_size == 3'b001 && alu_result[0] != 1'b0) ||
                                       (mem_size == 3'b010 && alu_result[1:0] != 2'b00));
    assign misalign_store = is_store && ((mem_size == 3'b001 && alu_result[0] != 1'b0) ||
                                         (mem_size == 3'b010 && alu_result[1:0] != 2'b00));

    wire [31:0] store_merged_word;
    assign store_merged_word = (mem_size_reg == 3'b010) ? wdata_reg :
                               (mem_size_reg == 3'b001) ?
                               (byte_offset[1] ? {wdata_reg[15:0], mem_word_for_extract[15:0]} : {mem_word_for_extract[31:16], wdata_reg[15:0]}) :
                               (byte_offset == 2'b00) ? {mem_word_for_extract[31:8], wdata_reg[7:0]} :
                               (byte_offset == 2'b01) ? {mem_word_for_extract[31:16], wdata_reg[7:0], mem_word_for_extract[7:0]} :
                               (byte_offset == 2'b10) ? {mem_word_for_extract[31:24], wdata_reg[7:0], mem_word_for_extract[15:0]} :
                                                       {wdata_reg[7:0], mem_word_for_extract[23:0]};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_state <= MEM_IDLE;
            addr_reg <= 32'b0;
            wdata_reg <= 32'b0;
            mem_size_reg <= 3'b0;
            mem_unsigned_reg <= 1'b0;
            read_word_reg <= 32'b0;
            wb_data_reg <= 32'b0;
            wb_we_reg <= 1'b0;
            wb_rd_reg <= 5'b0;
            done_reg <= 1'b0;
            en_reg <= 1'b0;
            we_reg <= 1'b0;
            mem_seen_valid <= 1'b0;
            daddr_reg <= 11'b0;
        end else begin
            done_reg <= 1'b0;
            en_reg <= 1'b0;
            we_reg <= 1'b0;

            if (!mem_valid) begin
                mem_seen_valid <= 1'b0;
            end

            case (mem_state)
                MEM_IDLE: begin
                    if (mem_valid && !mem_seen_valid) begin
                        mem_seen_valid <= 1'b1;
                        addr_reg <= alu_result;
                        wdata_reg <= store_data;
                        mem_size_reg <= mem_size;
                        mem_unsigned_reg <= mem_unsigned;
                        wb_rd_reg <= wb_rd;
                        wb_we_reg <= wb_we && valid_inst;
                        if (!valid_inst || (!is_load && !is_store)) begin
                            wb_data_reg <= alu_result;
                            done_reg <= 1'b1;
                        end else if (misalign_load || misalign_store) begin
                            wb_data_reg <= 32'b0;
                            wb_we_reg <= 1'b0;
                            done_reg <= 1'b1;
                        end else if (is_load) begin
                            en_reg <= 1'b1;
                            we_reg <= 1'b0;
                            daddr_reg <= alu_result[12:2];
                            mem_state <= MEM_READ;
                        end else begin
                            en_reg <= 1'b1;
                            we_reg <= 1'b0;
                            daddr_reg <= alu_result[12:2];
                            mem_state <= MEM_WRITE_MODIFY;
                        end
                    end
                end
                MEM_READ: begin
                    read_word_reg <= dcache_rdata;
                    wb_data_reg <= load_value;
                    done_reg <= 1'b1;
                    mem_state <= MEM_IDLE;
                end
                MEM_WRITE_MODIFY: begin
                    read_word_reg <= dcache_rdata;
                    en_reg <= 1'b1;
                    we_reg <= 1'b1;
                    daddr_reg <= addr_reg[12:2];
                    mem_state <= MEM_WRITE_COMMIT;
                end
                MEM_WRITE_COMMIT: begin
                    done_reg <= 1'b1;
                    wb_we_reg <= 1'b0;
                    wb_data_reg <= 32'b0;
                    mem_state <= MEM_IDLE;
                end
                default: begin
                    mem_state <= MEM_IDLE;
                end
            endcase

            if (mem_state == MEM_WRITE_MODIFY) begin
                wdata_reg <= store_merged_word;
            end
        end
    end

    assign dcache_en = en_reg;
    assign dcache_we = {we_reg};
    assign dcache_addr = daddr_reg;
    assign dcache_wdata = wdata_reg;

    assign mem_done = done_reg;
    assign mem_wb_bus = {is_jal_like, wb_we_reg, wb_rd_reg, wb_data_reg, pc, inst};
    assign mem_pc = pc;
    assign mem_inst = inst;

endmodule
