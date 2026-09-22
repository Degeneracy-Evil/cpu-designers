`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "core_bus_types.svh"

module cpu_mem(
    input              clk,
    input              resetn,
    input              mem_valid,
    input exe_mem_bus_t exe_mem_bus_r,
    input              trap_enter,

    // Architectural access: held stable through translation/permission check.
    output             mem_access_valid,
    output     [31:0]  mem_vaddr,
    output mem_kind_t  mem_kind,
    output access_class_t mem_access_type,
    input              mem_access_ready,
    input      [31:0]  mem_access_paddr,

    // Physical request: issued only after the architectural access is allowed.
    output             phys_req_valid,
    output     [31:0]  phys_req_paddr,
    output             phys_req_write,
    output     [2:0]   phys_req_size,
    output     [31:0]  phys_req_wdata,
    input      [31:0]  phys_resp_rdata,
    input              phys_resp_valid,

    output             mem_done,
    output wb_bus_t     mem_wb_bus,
    output     [31:0]  mem_pc,
    output     [31:0]  mem_inst,
    output exception_t mem_exception
);
    localparam [2:0] MEM_IDLE      = 3'd0;
    localparam [2:0] MEM_ACCESS    = 3'd1;
    localparam [2:0] MEM_READ      = 3'd2;
    localparam [2:0] MEM_WRITE     = 3'd3;
    localparam [2:0] MEM_AMO_READ  = 3'd4;
    localparam [2:0] MEM_AMO_WRITE = 3'd5;

    wire [31:0] result       = exe_mem_bus_r.result;
    wire        wb_we        = exe_mem_bus_r.wb_we;
    wire [4:0]  wb_rd        = exe_mem_bus_r.wb_rd;
    wire [2:0]  op_size      = exe_mem_bus_r.mem_size;
    wire        op_unsigned  = exe_mem_bus_r.mem_unsigned;
    wire [31:0] store_data   = exe_mem_bus_r.store_data;
    wire [31:0] pc           = exe_mem_bus_r.pc;
    wire [31:0] inst         = exe_mem_bus_r.inst;
    wire [4:0]  amo_funct5   = exe_mem_bus_r.amo_funct5;

    wire is_load = exe_mem_bus_r.mem_kind == MEM_LOAD;
    wire is_store = exe_mem_bus_r.mem_kind == MEM_STORE;
    wire is_lr = exe_mem_bus_r.mem_kind == MEM_LR;
    wire is_sc = exe_mem_bus_r.mem_kind == MEM_SC;
    wire is_amo = exe_mem_bus_r.mem_kind == MEM_AMO;
    wire has_mem_access = exe_mem_bus_r.mem_kind != MEM_NONE;

    wire misalign_addr = (op_size == `AXI_SIZE_HWORD && result[0]) ||
                         (op_size == `AXI_SIZE_WORD && result[1:0] != 2'b00);

    reg [2:0]  state_r;
    reg [31:0] addr_r;
    reg [31:0] checked_paddr_r;
    mem_kind_t kind_r;
    reg [2:0]  size_r;
    reg        unsigned_r;
    reg [31:0] store_data_r;
    reg [4:0]  amo_funct5_r;

    reg        access_valid_r;
    reg        phys_valid_r;
    reg        phys_write_r;
    reg [2:0]  phys_size_r;
    reg [31:0] phys_wdata_r;

    reg [31:0] wb_data_r;
    reg        wb_we_r;
    reg [4:0]  wb_rd_r;
    reg        done_r;
    reg        seen_valid_r;

    reg [29:0] reservation_word_r;
    reg        reservation_valid_r;
    reg [31:0] amo_loaded_r;

    wire [1:0] byte_offset = addr_r[1:0];
    wire [7:0] selected_byte =
        (byte_offset == 2'b00) ? phys_resp_rdata[7:0] :
        (byte_offset == 2'b01) ? phys_resp_rdata[15:8] :
        (byte_offset == 2'b10) ? phys_resp_rdata[23:16] :
                                phys_resp_rdata[31:24];
    wire [15:0] selected_half = byte_offset[1] ?
                                phys_resp_rdata[31:16] : phys_resp_rdata[15:0];
    wire [31:0] load_value =
        (size_r == `AXI_SIZE_BYTE) ?
            (unsigned_r ? {24'b0, selected_byte} : {{24{selected_byte[7]}}, selected_byte}) :
        (size_r == `AXI_SIZE_HWORD) ?
            (unsigned_r ? {16'b0, selected_half} : {{16{selected_half[15]}}, selected_half}) :
        phys_resp_rdata;

    wire reservation_match = reservation_valid_r &&
                             (reservation_word_r == mem_access_paddr[31:2]);

    function automatic [31:0] amo_compute(
        input [4:0] funct5,
        input [31:0] loaded,
        input [31:0] rhs
    );
        case (funct5)
            5'b00001: amo_compute = rhs;
            5'b00000: amo_compute = loaded + rhs;
            5'b01100: amo_compute = loaded & rhs;
            5'b01000: amo_compute = loaded | rhs;
            5'b00100: amo_compute = loaded ^ rhs;
            5'b10000: amo_compute = ($signed(loaded) < $signed(rhs)) ? loaded : rhs;
            5'b10100: amo_compute = ($signed(loaded) > $signed(rhs)) ? loaded : rhs;
            5'b11000: amo_compute = (loaded < rhs) ? loaded : rhs;
            5'b11100: amo_compute = (loaded > rhs) ? loaded : rhs;
            default:  amo_compute = loaded;
        endcase
    endfunction

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state_r <= MEM_IDLE;
            addr_r <= 32'b0;
            checked_paddr_r <= 32'b0;
            kind_r <= MEM_NONE;
            size_r <= `AXI_SIZE_WORD;
            unsigned_r <= 1'b0;
            store_data_r <= 32'b0;
            amo_funct5_r <= 5'b0;
            access_valid_r <= 1'b0;
            phys_valid_r <= 1'b0;
            phys_write_r <= 1'b0;
            phys_size_r <= `AXI_SIZE_WORD;
            phys_wdata_r <= 32'b0;
            wb_data_r <= 32'b0;
            wb_we_r <= 1'b0;
            wb_rd_r <= 5'b0;
            done_r <= 1'b0;
            seen_valid_r <= 1'b0;
            reservation_word_r <= 30'b0;
            reservation_valid_r <= 1'b0;
            amo_loaded_r <= 32'b0;
        end else begin
            done_r <= 1'b0;

            if (!mem_valid)
                seen_valid_r <= 1'b0;

            if (trap_enter) begin
                state_r <= MEM_IDLE;
                access_valid_r <= 1'b0;
                phys_valid_r <= 1'b0;
                reservation_valid_r <= 1'b0;
            end else begin
                case (state_r)
                    MEM_IDLE: begin
                        access_valid_r <= 1'b0;
                        phys_valid_r <= 1'b0;
                        if (mem_valid && !seen_valid_r) begin
                            seen_valid_r <= 1'b1;
                            addr_r <= result;
                            kind_r <= exe_mem_bus_r.mem_kind;
                            size_r <= op_size;
                            unsigned_r <= op_unsigned;
                            store_data_r <= store_data;
                            amo_funct5_r <= amo_funct5;
                            wb_rd_r <= wb_rd;
                            wb_we_r <= wb_we;

                            if (!has_mem_access) begin
                                wb_data_r <= result;
                                done_r <= 1'b1;
                            end else if (misalign_addr) begin
                                wb_data_r <= 32'b0;
                                wb_we_r <= 1'b0;
                            end else begin
                                access_valid_r <= 1'b1;
                                state_r <= MEM_ACCESS;
                            end
                        end
                    end

                    MEM_ACCESS: begin
                        if (mem_access_ready) begin
                            checked_paddr_r <= mem_access_paddr;
                            case (kind_r)
                                MEM_LOAD: begin
                                    phys_write_r <= 1'b0;
                                    phys_size_r <= size_r;
                                    phys_wdata_r <= 32'b0;
                                    phys_valid_r <= 1'b1;
                                    state_r <= MEM_READ;
                                end
                                MEM_STORE: begin
                                    phys_write_r <= 1'b1;
                                    phys_size_r <= size_r;
                                    // Store data is always an unshifted architectural value.
                                    phys_wdata_r <= store_data_r;
                                    phys_valid_r <= 1'b1;
                                    state_r <= MEM_WRITE;
                                end
                                MEM_LR: begin
                                    phys_write_r <= 1'b0;
                                    phys_size_r <= `AXI_SIZE_WORD;
                                    phys_wdata_r <= 32'b0;
                                    phys_valid_r <= 1'b1;
                                    state_r <= MEM_AMO_READ;
                                end
                                MEM_SC: begin
                                    // Permission is checked before reservation status.
                                    reservation_valid_r <= 1'b0;
                                    if (reservation_match) begin
                                        phys_write_r <= 1'b1;
                                        phys_size_r <= `AXI_SIZE_WORD;
                                        phys_wdata_r <= store_data_r;
                                        phys_valid_r <= 1'b1;
                                        state_r <= MEM_AMO_WRITE;
                                    end else begin
                                        access_valid_r <= 1'b0;
                                        wb_data_r <= 32'd1;
                                        wb_we_r <= 1'b1;
                                        done_r <= 1'b1;
                                        state_r <= MEM_IDLE;
                                    end
                                end
                                default: begin // MEM_AMO
                                    phys_write_r <= 1'b0;
                                    phys_size_r <= `AXI_SIZE_WORD;
                                    phys_wdata_r <= 32'b0;
                                    phys_valid_r <= 1'b1;
                                    state_r <= MEM_AMO_READ;
                                end
                            endcase
                        end
                    end

                    MEM_READ: begin
                        if (phys_resp_valid) begin
                            wb_data_r <= load_value;
                            phys_valid_r <= 1'b0;
                            access_valid_r <= 1'b0;
                            done_r <= 1'b1;
                            state_r <= MEM_IDLE;
                        end
                    end

                    MEM_WRITE: begin
                        if (phys_resp_valid) begin
                            phys_valid_r <= 1'b0;
                            access_valid_r <= 1'b0;
                            wb_data_r <= 32'b0;
                            wb_we_r <= 1'b0;
                            reservation_valid_r <= 1'b0;
                            done_r <= 1'b1;
                            state_r <= MEM_IDLE;
                        end
                    end

                    MEM_AMO_READ: begin
                        if (phys_resp_valid) begin
                            phys_valid_r <= 1'b0;
                            amo_loaded_r <= phys_resp_rdata;
                            if (kind_r == MEM_LR) begin
                                reservation_word_r <= checked_paddr_r[31:2];
                                reservation_valid_r <= 1'b1;
                                wb_data_r <= phys_resp_rdata;
                                wb_we_r <= 1'b1;
                                access_valid_r <= 1'b0;
                                done_r <= 1'b1;
                                state_r <= MEM_IDLE;
                            end else begin
                                // AMO keeps the checked PA/access contract while changing
                                // only its physical phase from READ to WRITE.
                                phys_write_r <= 1'b1;
                                phys_size_r <= `AXI_SIZE_WORD;
                                phys_wdata_r <= amo_compute(amo_funct5_r,
                                                            phys_resp_rdata,
                                                            store_data_r);
                                phys_valid_r <= 1'b1;
                                state_r <= MEM_AMO_WRITE;
                            end
                        end
                    end

                    MEM_AMO_WRITE: begin
                        if (phys_resp_valid) begin
                            phys_valid_r <= 1'b0;
                            access_valid_r <= 1'b0;
                            reservation_valid_r <= 1'b0;
                            wb_data_r <= (kind_r == MEM_SC) ? 32'd0 : amo_loaded_r;
                            wb_we_r <= 1'b1;
                            done_r <= 1'b1;
                            state_r <= MEM_IDLE;
                        end
                    end

                    default: state_r <= MEM_IDLE;
                endcase
            end
        end
    end

    assign mem_access_valid = access_valid_r;
    assign mem_vaddr = addr_r;
    assign mem_kind = kind_r;
    assign mem_access_type = mem_access_class(kind_r);
    assign phys_req_valid = phys_valid_r;
    assign phys_req_paddr = checked_paddr_r;
    assign phys_req_write = phys_write_r;
    assign phys_req_size = phys_size_r;
    assign phys_req_wdata = phys_wdata_r;
    assign mem_done = done_r;

    assign mem_wb_bus = '{
        wb_we:   wb_we_r,
        wb_rd:   wb_rd_r,
        wb_data: wb_data_r,
        pc:      pc,
        inst:    inst
    };

    assign mem_pc = pc;
    assign mem_inst = inst;
    assign mem_exception = '{
        valid: mem_valid && has_mem_access && misalign_addr,
        cause: (is_load || is_lr) ? 32'd4 : 32'd6,
        epc:   pc,
        tval:  result
    };
endmodule
