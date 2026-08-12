`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "core_bus_types.svh"

module cpu_mem(
        input              clk,
        input              resetn,
        input              mem_valid,
        input      exe_mem_bus_t exe_mem_bus_r,
        input              trap_enter,    // trap entry: invalidate LR reservation
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

    localparam MEM_IDLE      = 3'd0;
    localparam MEM_READ      = 3'd1;
    localparam MEM_WRITE     = 3'd2;
    localparam MEM_AMO_READ  = 3'd3;   // A extension: AMO/LR/SC read phase
    localparam MEM_AMO_WRITE = 3'd4;   // A extension: AMO/SC write phase
    localparam MEM_AMO_FENCE = 3'd5;   // Ordered AMO/LR/SC completion bubble

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
    // A extension signals
    wire        is_amo;
    wire        is_lr;
    wire        is_sc;
    wire [4:0]  amo_funct5;
    wire        amo_aq;
    wire        amo_rl;

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
    assign is_amo       = exe_mem_bus_r.is_amo;
    assign is_lr         = exe_mem_bus_r.is_lr;
    assign is_sc         = exe_mem_bus_r.is_sc;
    assign amo_funct5    = exe_mem_bus_r.amo_funct5;
    assign amo_aq        = exe_mem_bus_r.amo_aq;
    assign amo_rl        = exe_mem_bus_r.amo_rl;

    reg [2:0] mem_state;
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

    // ── A extension: Reservation Set ──
    reg [31:0] lr_reservation_addr;
    reg        lr_reservation_valid;

    // ── A extension: AMO latched registers ──
    reg [31:0] amo_loaded_value;     // value read from memory
    reg [31:0] amo_computed_result;  // AMO operation result (value to write back)
    reg [4:0]  amo_funct5_reg;       // latched AMO operation code
    reg [31:0] amo_rs2_reg;          // latched rs2 value (for SC/AMO)
    reg        is_lr_reg;            // latched LR flag
    reg        is_sc_reg;            // latched SC flag
    reg        is_amo_op_reg;        // latched AMO operation flag (non-LR/SC AMO)
    reg        amo_ordered_reg;      // aq/rl form uses an explicit serialized completion step

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
    assign misalign_load  = is_load && misalign_addr;
    assign misalign_store = is_store && misalign_addr;

    // ── A extension: AMO misalign detection ──
    // LR.W/SC.W/AMO require word-aligned address (addr[1:0]==00)
    wire amo_misalign = is_amo && (alu_result[1:0] != 2'b00);

    // ── A extension: AMO computation function ──
    // Takes loaded value as parameter so caller can pass readData_32 directly
    // (avoids stale registered amo_loaded_value in same cycle as non-blocking assign)
    function automatic [31:0] amo_compute(
        input [4:0]  funct5,
        input [31:0] loaded,
        input [31:0] rs2
    );
        case (funct5)
            5'b00001: amo_compute = rs2;                                                       // AMOSWAP
            5'b00000: amo_compute = loaded + rs2;                                              // AMOADD
            5'b01100: amo_compute = loaded & rs2;                                              // AMOAND
            5'b01000: amo_compute = loaded | rs2;                                              // AMOOR
            5'b00100: amo_compute = loaded ^ rs2;                                              // AMOXOR
            5'b10000: amo_compute = ($signed(loaded) < $signed(rs2)) ? loaded : rs2;           // AMOMIN
            5'b10100: amo_compute = ($signed(loaded) > $signed(rs2)) ? loaded : rs2;           // AMOMAX
            5'b11000: amo_compute = (loaded < rs2) ? loaded : rs2;                             // AMOMINU
            5'b11100: amo_compute = (loaded > rs2) ? loaded : rs2;                             // AMOMAXU
            default:  amo_compute = loaded;                                                    // fallback
        endcase
    endfunction

    // ── A extension: SC reservation match check ──
    // Use the address captured when this memory operation was accepted.  The
    // SC response may arrive many cycles later and must not depend on live
    // execute-stage inputs remaining unchanged.
    wire sc_reservation_match = lr_reservation_valid && (lr_reservation_addr == addr_reg);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
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
            hsize_reg <= `AXI_SIZE_WORD;
            dataAddr_32_reg <= 32'b0;
            writeData_32_reg <= 32'b0;
            mem_en_reg <= 1'b0;
            // A extension reset
            lr_reservation_addr <= 32'b0;
            lr_reservation_valid <= 1'b0;
            amo_loaded_value <= 32'b0;
            amo_computed_result <= 32'b0;
            amo_funct5_reg <= 5'b0;
            amo_rs2_reg <= 32'b0;
            is_lr_reg <= 1'b0;
            is_sc_reg <= 1'b0;
            is_amo_op_reg <= 1'b0;
            amo_ordered_reg <= 1'b0;
        end
        else begin
            done_reg <= 1'b0;
            if (mem_state == MEM_IDLE)
                mem_en_reg <= 1'b0;

            if (!mem_valid) begin
                mem_seen_valid <= 1'b0;
            end

            // ── Reservation invalidation: trap entry ──
            // Also clear mem_en_reg and reset mem_state to prevent stale
            // dcache requests from retrying after a trap (e.g. after a
            // refill/write-back AXI error that never set cpu_req_ready).
            if (trap_enter) begin
                lr_reservation_valid <= 1'b0;
                mem_en_reg           <= 1'b0;
                mem_state            <= MEM_IDLE;
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

                        // ── A extension: AMO/LR/SC path ──
                        if (is_amo) begin
                            if (amo_misalign) begin
                                // Misaligned AMO: report as store/AMO misalign (exception code 6)
                                // The trap manager handles this via mem_misalign_store
                                wb_data_reg <= 32'b0;
                                wb_we_reg <= 1'b0;
                                hwrite_reg <= 1'b0;
                                hsize_reg <= `AXI_SIZE_WORD;
                                done_reg <= 1'b1;
                            end else begin
                                // Latch AMO-specific signals
                                amo_funct5_reg <= amo_funct5;
                                amo_rs2_reg <= store_data;  // rs2 value for SC/AMO
                                is_lr_reg <= is_lr;
                                is_sc_reg <= is_sc;
                                is_amo_op_reg <= is_amo & ~is_lr & ~is_sc;
                                amo_ordered_reg <= amo_aq || amo_rl;
                                // Issue read request
                                dataAddr_32_reg <= alu_result;
                                hwrite_reg <= 1'b0;
                                hsize_reg <= `AXI_SIZE_WORD;
                                writeData_32_reg <= 32'b0;
                                mem_en_reg <= 1'b1;
                                mem_state <= MEM_AMO_READ;
                            end
                        end
                        // ── Original non-AMO path ──
                        else if (!valid_inst || (!is_load && !is_store)) begin
                            wb_data_reg <= alu_result;
                            hwrite_reg <= 1'b0;
                            hsize_reg <= `AXI_SIZE_WORD;
                            done_reg <= 1'b1;
                        end
                        else if (misalign_load || misalign_store) begin
                            wb_data_reg <= 32'b0;
                            wb_we_reg <= 1'b0;
                            hwrite_reg <= 1'b0;
                            hsize_reg <= `AXI_SIZE_WORD;
                            done_reg <= 1'b1;
                        end
                        else if (is_load) begin
                            dataAddr_32_reg <= alu_result;
                            hwrite_reg <= 1'b0;
                            case (mem_size)
                                3'b000: hsize_reg <= `AXI_SIZE_BYTE;
                                3'b001: hsize_reg <= `AXI_SIZE_HWORD;
                                default: hsize_reg <= `AXI_SIZE_WORD;
                            endcase
                            writeData_32_reg <= 32'b0;
                            mem_en_reg <= 1'b1;
                            mem_state <= MEM_READ;
                        end
                        else begin
                            dataAddr_32_reg <= alu_result;
                            hwrite_reg <= 1'b1;
                            mem_en_reg <= 1'b1;
                            case (mem_size)
                                3'b000: begin
                                    hsize_reg <= `AXI_SIZE_BYTE;
                                    writeData_32_reg <= {4{store_data[7:0]}};
                                end
                                3'b001: begin
                                    hsize_reg <= `AXI_SIZE_HWORD;
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
                                    hsize_reg <= `AXI_SIZE_WORD;
                                    writeData_32_reg <= store_data;
                                end
                            endcase
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
                        hsize_reg <= `AXI_SIZE_WORD;
                        mem_en_reg <= 1'b0;
                        mem_state <= MEM_IDLE;
                        // ── Reservation invalidation: any normal Store ──
                        lr_reservation_valid <= 1'b0;
                    end
                end

                // ── A extension: AMO/LR/SC read phase ──
                MEM_AMO_READ: begin
                    if (data_valid) begin
                        amo_loaded_value <= readData_32;
                        if (is_lr_reg) begin
                            // LR.W: set reservation, return loaded value
                            lr_reservation_addr <= addr_reg;
                            lr_reservation_valid <= 1'b1;
                            wb_data_reg <= readData_32;
                            wb_we_reg <= 1'b1;
                            mem_en_reg <= 1'b0;
                            if (amo_ordered_reg) begin
                                mem_state <= MEM_AMO_FENCE;
                            end else begin
                                done_reg <= 1'b1;
                                mem_state <= MEM_IDLE;
                            end
                        end
                        else if (is_sc_reg) begin
                            // SC.W: check reservation
                            // Always clear reservation after SC attempt
                            lr_reservation_valid <= 1'b0;
                            if (sc_reservation_match) begin
                                // Reservation matches: issue write with rs2 value
                                dataAddr_32_reg <= addr_reg;
                                hwrite_reg <= 1'b1;
                                hsize_reg <= `AXI_SIZE_WORD;
                                writeData_32_reg <= amo_rs2_reg;
                                mem_en_reg <= 1'b1;
                                mem_state <= MEM_AMO_WRITE;
                            end else begin
                                // Reservation mismatch: SC fails, rd=1, no write
                                wb_data_reg <= 32'd1;
                                wb_we_reg <= 1'b1;
                                mem_en_reg <= 1'b0;
                                if (amo_ordered_reg) begin
                                    mem_state <= MEM_AMO_FENCE;
                                end else begin
                                    done_reg <= 1'b1;
                                    mem_state <= MEM_IDLE;
                                end
                            end
                        end
                        else begin
                            // AMO operation: compute result using readData_32 directly
                            // (amo_loaded_value not yet updated due to non-blocking assign)
                            amo_computed_result <= amo_compute(amo_funct5_reg, readData_32, amo_rs2_reg);
                            dataAddr_32_reg <= addr_reg;
                            hwrite_reg <= 1'b1;
                            hsize_reg <= `AXI_SIZE_WORD;
                            writeData_32_reg <= amo_compute(amo_funct5_reg, readData_32, amo_rs2_reg);
                            mem_en_reg <= 1'b1;
                            mem_state <= MEM_AMO_WRITE;
                        end
                    end
                end

                // ── A extension: AMO/SC write phase ──
                MEM_AMO_WRITE: begin
                    if (data_valid) begin
                        if (is_sc_reg) begin
                            // SC.W success: rd=0
                            wb_data_reg <= 32'd0;
                        end else begin
                            // AMO: return original loaded value (pre-operation value)
                            wb_data_reg <= amo_loaded_value;
                        end
                        wb_we_reg <= 1'b1;
                        hwrite_reg <= 1'b0;
                        hsize_reg <= `AXI_SIZE_WORD;
                        mem_en_reg <= 1'b0;
                        lr_reservation_valid <= 1'b0;
                        if (amo_ordered_reg) begin
                            mem_state <= MEM_AMO_FENCE;
                        end else begin
                            done_reg <= 1'b1;
                            mem_state <= MEM_IDLE;
                        end
                    end
                end

                MEM_AMO_FENCE: begin
                    done_reg <= 1'b1;
                    mem_state <= MEM_IDLE;
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
        is_amo:        is_amo,
        is_lr:         is_lr,
        is_sc:         is_sc
    };
    assign mem_pc = pc;
    assign mem_inst = inst;

    // LR.W misalign is a Load-type misalign (exception code 4)
    // SC.W/AMO misalign is a Store/AMO-type misalign (exception code 6)
    assign mem_misalign_load  = (is_load | is_lr)  && misalign_addr;
    assign mem_misalign_store = (is_store | is_sc | (is_amo & ~is_lr)) && misalign_addr;
    assign mem_misalign_addr  = alu_result;
    assign mem_data_access    = is_load || is_store || is_amo;
endmodule
