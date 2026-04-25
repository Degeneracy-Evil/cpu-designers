`timescale 1ns / 1ps

module cpu_mem(
    input              clk,
    input              reset,
    input              mem_valid,
    input      [206:0] exe_mem_bus_r,
    output             mem_en,
    output     [3:0]   dataWen_4,
    output     [31:0]  dataAddr_32,
    output     [31:0]  writeData_32,
    input      [31:0]  readData_32,
    output             mem_done,
    output     [167:0] mem_wb_bus,

    output     [31:0]  mem_pc,
    output     [31:0]  mem_inst,

    output             mem_misalign_load,
    output             mem_misalign_store,
    output     [31:0]  mem_misalign_addr
);

    localparam MEM_IDLE = 2'd0;
    localparam MEM_READ = 2'd1;
    localparam MEM_WRITE = 2'd2;

    wire valid_inst;
    wire is_jal_like;
    wire is_load;
    wire is_store;
    wire is_csr;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] alu_result;
    wire [2:0] mem_size;
    wire mem_unsigned;
    wire [31:0] store_data;
    wire [31:0] csr_rdata;
    wire [31:0] pc_plus4;
    wire [31:0] pc;
    wire [31:0] inst;

    assign {
        pc_plus4,
        valid_inst,
        is_jal_like,
        is_load,
        is_store,
        is_csr,
        wb_we,
        wb_rd,
        alu_result,
        mem_size,
        mem_unsigned,
        store_data,
        csr_rdata,
        pc,
        inst
    } = exe_mem_bus_r;

    reg [1:0] mem_state;
    reg [31:0] addr_reg;
    reg [2:0] mem_size_reg;
    reg mem_unsigned_reg;
    reg [31:0] wb_data_reg;
    reg wb_we_reg;
    reg [4:0] wb_rd_reg;
    reg done_reg;
    reg mem_seen_valid;

    reg [3:0]  dataWen_4_reg;
    reg [31:0] dataAddr_32_reg;
    reg [31:0] writeData_32_reg;
    reg        mem_en_reg;

    wire [1:0] byte_offset;
    assign byte_offset = addr_reg[1:0];

    wire [7:0] selected_byte;
    assign selected_byte = (byte_offset == 2'b00) ? readData_32[7:0] :
                           (byte_offset == 2'b01) ? readData_32[15:8] :
                           (byte_offset == 2'b10) ? readData_32[23:16] :
                                                    readData_32[31:24];

    wire [15:0] selected_half;
    assign selected_half = byte_offset[1] ? readData_32[31:16] : readData_32[15:0];

    wire [31:0] load_value;
    assign load_value = (mem_size_reg == 3'b000) ?
                        (mem_unsigned_reg ? {24'b0, selected_byte} : {{24{selected_byte[7]}}, selected_byte}) :
                        (mem_size_reg == 3'b001) ?
                        (mem_unsigned_reg ? {16'b0, selected_half} : {{16{selected_half[15]}}, selected_half}) :
                        readData_32;

    wire misalign_load;
    wire misalign_store;
    assign misalign_load = is_load && ((mem_size == 3'b001 && alu_result[0] != 1'b0) ||
                                       (mem_size == 3'b010 && alu_result[1:0] != 2'b00));
    assign misalign_store = is_store && ((mem_size == 3'b001 && alu_result[0] != 1'b0) ||
                                         (mem_size == 3'b010 && alu_result[1:0] != 2'b00));

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_state <= MEM_IDLE;
            addr_reg <= 32'b0;
            mem_size_reg <= 3'b0;
            mem_unsigned_reg <= 1'b0;
            wb_data_reg <= 32'b0;
            wb_we_reg <= 1'b0;
            wb_rd_reg <= 5'b0;
            done_reg <= 1'b0;
            mem_seen_valid <= 1'b0;
            dataWen_4_reg <= 4'b1111;
            dataAddr_32_reg <= 32'b0;
            writeData_32_reg <= 32'b0;
            mem_en_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;
            mem_en_reg <= 1'b0;

            if (!mem_valid) begin
                mem_seen_valid <= 1'b0;
            end

            case (mem_state)
                MEM_IDLE: begin
                    if (mem_valid && !mem_seen_valid) begin
                        mem_seen_valid <= 1'b1;
                        addr_reg <= alu_result;
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
                            dataAddr_32_reg <= alu_result;
                            dataWen_4_reg <= 4'b1111;
                            writeData_32_reg <= 32'b0;
                            mem_en_reg <= 1'b1;
                            mem_state <= MEM_READ;
                        end else begin  // is_store
                            dataAddr_32_reg <= alu_result;
                            mem_en_reg <= 1'b1;
                            case (mem_size)
                                3'b000: begin  // sb
                                    writeData_32_reg <= {4{store_data[7:0]}};
                                    case (alu_result[1:0])
                                        2'b00: dataWen_4_reg <= 4'b1110;
                                        2'b01: dataWen_4_reg <= 4'b1101;
                                        2'b10: dataWen_4_reg <= 4'b1011;
                                        2'b11: dataWen_4_reg <= 4'b0111;
                                    endcase
                                end
                                3'b001: begin  // sh
                                    case (alu_result[1:0])
                                        2'b00: begin
                                            writeData_32_reg <= {16'b0, store_data[15:0]};
                                            dataWen_4_reg <= 4'b1100;
                                        end
                                        default: begin
                                            writeData_32_reg <= {store_data[15:0], 16'b0};
                                            dataWen_4_reg <= 4'b0011;
                                        end
                                    endcase
                                end
                                default: begin  // sw
                                    writeData_32_reg <= store_data;
                                    dataWen_4_reg <= 4'b0000;
                                end
                            endcase
                            mem_state <= MEM_WRITE;
                        end
                    end
                end
                MEM_READ: begin
                    wb_data_reg <= load_value;
                    done_reg <= 1'b1;
                    mem_state <= MEM_IDLE;
                end
                MEM_WRITE: begin
                    done_reg <= 1'b1;
                    wb_we_reg <= 1'b0;
                    wb_data_reg <= 32'b0;
                    mem_state <= MEM_IDLE;
                end
                default: begin
                    mem_state <= MEM_IDLE;
                end
            endcase
        end
    end

    assign mem_en = mem_en_reg;
    assign dataWen_4 = dataWen_4_reg;
    assign dataAddr_32 = dataAddr_32_reg;
    assign writeData_32 = writeData_32_reg;

    assign mem_done = done_reg;
    assign mem_wb_bus = {pc_plus4, is_jal_like, is_csr, wb_we_reg, wb_rd_reg, wb_data_reg, csr_rdata, pc, inst};
    assign mem_pc = pc;
    assign mem_inst = inst;

    assign mem_misalign_load  = misalign_load;
    assign mem_misalign_store = misalign_store;
    assign mem_misalign_addr  = alu_result;

endmodule
