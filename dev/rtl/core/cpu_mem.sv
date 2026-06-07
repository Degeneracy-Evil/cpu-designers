`timescale 1ns / 1ps
`include "ahb_def.svh"
`include "core_bus_types.svh"

module cpu_mem(
        input              clk,
        input              reset,
        input              mem_valid,
        input      exe_mem_bus_t exe_mem_bus_r,
        input      [31:0]  frs2_value,    // float register rs2 for FSW
        output             mem_en,
        output             mem_hwrite,
        output      [2:0]  mem_hsize,
        output     [31:0]  dataAddr_32,
        output     [31:0]  writeData_32,
        input      [31:0]  readData_32,
        input              data_valid,
        output             mem_done,
        output     wb_bus_t mem_wb_bus,

        output     [31:0]  mem_pc,
        output     [31:0]  mem_inst,

        output             mem_misalign_load,
        output             mem_misalign_store,
        output     [31:0]  mem_misalign_addr,
        output             mem_data_access
    );

    localparam MEM_IDLE  = 2'd0;
    localparam MEM_READ  = 2'd1;
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
    wire        is_fpu;
    wire        is_flw;
    wire        is_fsw;
    wire        fpu_rd_is_int;
    wire [4:0]  fpu_fflags;

    assign pc_plus4      = exe_mem_bus_r.pc_plus4;
    assign valid_inst    = exe_mem_bus_r.result_ok;
    assign is_jal_like   = exe_mem_bus_r.is_jal_like;
    assign is_load       = exe_mem_bus_r.is_load;
    assign is_store      = exe_mem_bus_r.is_store;
    assign is_csr        = exe_mem_bus_r.is_csr;
    assign wb_we         = exe_mem_bus_r.wb_we;
    assign wb_rd         = exe_mem_bus_r.wb_rd;
    assign alu_result    = exe_mem_bus_r.result_reg;
    assign mem_size      = exe_mem_bus_r.mem_size;
    assign mem_unsigned  = exe_mem_bus_r.mem_unsigned;
    assign store_data    = exe_mem_bus_r.rs2_value;
    assign csr_rdata     = exe_mem_bus_r.csr_rdata;
    assign pc            = exe_mem_bus_r.pc;
    assign inst          = exe_mem_bus_r.inst;
    assign is_fpu        = exe_mem_bus_r.is_fpu;
    assign is_flw        = exe_mem_bus_r.is_flw;
    assign is_fsw        = exe_mem_bus_r.is_fsw;
    assign fpu_rd_is_int = exe_mem_bus_r.fpu_rd_is_int;
    assign fpu_fflags    = exe_mem_bus_r.fpu_fflags;

    reg [1:0] mem_state;
    reg [31:0] addr_reg;
    reg [2:0] mem_size_reg;
    reg mem_unsigned_reg;
    reg [31:0] wb_data_reg;
    reg wb_we_reg;
    reg [4:0] wb_rd_reg;
    reg done_reg;
    reg mem_seen_valid;

    reg        hwrite_reg;
    reg [2:0]  hsize_reg;
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

    wire misalign_addr;
    assign misalign_addr = (mem_size == 3'b001 && alu_result[0]) ||
           (mem_size == 3'b010 && alu_result[1:0] != 2'b00);
    wire misalign_load;
    wire misalign_store;
    assign misalign_load  = (is_load | is_flw)  && misalign_addr;
    assign misalign_store = (is_store | is_fsw) && misalign_addr;

    always_ff @(posedge clk or posedge reset) begin
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
            hwrite_reg <= 1'b0;
            hsize_reg <= `AHB_SIZE_WORD;
            dataAddr_32_reg <= 32'b0;
            writeData_32_reg <= 32'b0;
            mem_en_reg <= 1'b0;
        end
        else begin
            done_reg <= 1'b0;
            if (mem_state == MEM_IDLE)
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
                        if (!valid_inst || (!is_load && !is_store && !is_flw && !is_fsw)) begin
                            wb_data_reg <= alu_result;
                            hwrite_reg <= 1'b0;
                            hsize_reg <= `AHB_SIZE_WORD;
                            done_reg <= 1'b1;
                        end
                        else if (misalign_load || misalign_store) begin
                            wb_data_reg <= 32'b0;
                            wb_we_reg <= 1'b0;
                            hwrite_reg <= 1'b0;
                            hsize_reg <= `AHB_SIZE_WORD;
                            done_reg <= 1'b1;
                        end
                        else if (is_load || is_flw) begin
                            dataAddr_32_reg <= alu_result;
                            hwrite_reg <= 1'b0;
                            hsize_reg <= `AHB_SIZE_WORD;
                            writeData_32_reg <= 32'b0;
                            mem_en_reg <= 1'b1;
                            mem_state <= MEM_READ;
                        end
                        else begin
                            dataAddr_32_reg <= alu_result;
                            hwrite_reg <= 1'b1;
                            mem_en_reg <= 1'b1;
                            // For FSW: use frs2_value as store data, always word size
                            if (is_fsw) begin
                                hsize_reg <= `AHB_SIZE_WORD;
                                writeData_32_reg <= frs2_value;
                            end
                            else begin
                                case (mem_size)
                                    3'b000: begin
                                        hsize_reg <= `AHB_SIZE_BYTE;
                                        writeData_32_reg <= {4{store_data[7:0]}};
                                    end
                                    3'b001: begin
                                        hsize_reg <= `AHB_SIZE_HWORD;
                                        case (alu_result[1:0])
                                            2'b00: begin
                                                writeData_32_reg <= {16'b0, store_data[15:0]};
                                            end
                                            default: begin
                                                writeData_32_reg <= {store_data[15:0], 16'b0};
                                            end
                                        endcase
                                    end
                                    default: begin
                                        hsize_reg <= `AHB_SIZE_WORD;
                                        writeData_32_reg <= store_data;
                                    end
                                endcase
                            end
                            mem_state <= MEM_WRITE;
                        end
                    end
                end
                MEM_READ: begin
                    if (data_valid) begin
                        wb_data_reg <= load_value;
                        done_reg <= 1'b1;
                        mem_en_reg <= 1'b0;
                        mem_state <= MEM_IDLE;
                    end
                end
                MEM_WRITE: begin
                    if (data_valid) begin
                        done_reg <= 1'b1;
                        wb_we_reg <= 1'b0;
                        wb_data_reg <= 32'b0;
                        hwrite_reg <= 1'b0;
                        hsize_reg <= `AHB_SIZE_WORD;
                        mem_en_reg <= 1'b0;
                        mem_state <= MEM_IDLE;
                    end
                end
                default: begin
                    mem_state <= MEM_IDLE;
                end
            endcase
        end
    end

    assign mem_en = mem_en_reg;
    assign mem_hwrite = hwrite_reg;
    assign mem_hsize = hsize_reg;
    assign dataAddr_32 = dataAddr_32_reg;
    assign writeData_32 = writeData_32_reg;

    assign mem_done = done_reg;
    assign mem_wb_bus = '{
        pc_plus4:      pc_plus4,
        is_jal_like:   is_jal_like,
        is_csr:        is_csr,
        wb_we:         wb_we_reg,
        wb_rd:         wb_rd_reg,
        wb_data:       wb_data_reg,
        csr_rdata:     csr_rdata,
        pc:            pc,
        inst:          inst,
        is_fpu:        is_fpu,
        is_flw:        is_flw,
        is_fsw:        is_fsw,
        fpu_rd_is_int: fpu_rd_is_int,
        fpu_fflags:    fpu_fflags
    };
    assign mem_pc = pc;
    assign mem_inst = inst;

    assign mem_misalign_load  = (is_load | is_flw)  && misalign_addr;
    assign mem_misalign_store = (is_store | is_fsw) && misalign_addr;
    assign mem_misalign_addr  = alu_result;
    assign mem_data_access    = is_load || is_store || is_flw || is_fsw;

endmodule
