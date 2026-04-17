`timescale 1ns / 1ps

// Main multi-cycle controller (phase-2).
// Supports ALU ops, load/store, branch, jump and fence class instructions.
module main_control(
    input         clk,
    input         reset,
    input  [6:0]  opcode,
    input  [2:0]  funct3,
    input         alu_decode_illegal,
    input         exec_ready,
    input         exec_done,
    input         mem_ready,
    input         mem_rvalid,
    input         mem_wdone,
    input         branch_taken,
    output reg        ir_write,
    output reg        pc_write,
    output reg [1:0]  pc_source,
    output reg        reg_write,
    output reg        exec_req,
    output reg        mem_req,
    output reg        mem_write_en,
    output reg [1:0]  wb_sel,
    output reg [1:0]  alu_src_a,
    output reg [1:0]  alu_src_b,
    output reg [2:0]  imm_type,
    output reg        illegal_instr,
    output reg [4:0]  state_dbg,
    output reg        irq_sample_en
);

    localparam FETCH            = 5'd0;
    localparam DECODE           = 5'd1;
    localparam EXECUTE_REQ      = 5'd2;
    localparam EXECUTE_WAIT     = 5'd3;
    localparam EXECUTE_B        = 5'd4;
    localparam EXECUTE_J        = 5'd5;
    localparam MEM_ADDR         = 5'd6;
    localparam MEM_READ_REQ     = 5'd7;
    localparam MEM_READ_WAIT    = 5'd8;
    localparam MEM_WRITE_REQ    = 5'd9;
    localparam MEM_WRITE_WAIT   = 5'd10;
    localparam WRITE_BACK       = 5'd11;
    localparam INTERRUPT_CHECK  = 5'd12;
    localparam ERROR            = 5'd31;

    localparam PC_PLUS4  = 2'b00;
    localparam PC_BRANCH = 2'b01;
    localparam PC_JUMP   = 2'b10;

    localparam WB_ALU = 2'b00;
    localparam WB_MEM = 2'b01;
    localparam WB_PC4 = 2'b10;

    localparam ALU_SRC_A_RS1  = 2'b00;
    localparam ALU_SRC_A_PC   = 2'b01;
    localparam ALU_SRC_A_ZERO = 2'b10;

    localparam ALU_SRC_B_RS2 = 2'b00;
    localparam ALU_SRC_B_IMM = 2'b01;

    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    localparam OPCODE_OP      = 7'b0110011;
    localparam OPCODE_OP_IMM  = 7'b0010011;
    localparam OPCODE_LOAD    = 7'b0000011;
    localparam OPCODE_STORE   = 7'b0100011;
    localparam OPCODE_BRANCH  = 7'b1100011;
    localparam OPCODE_JAL     = 7'b1101111;
    localparam OPCODE_JALR    = 7'b1100111;
    localparam OPCODE_LUI     = 7'b0110111;
    localparam OPCODE_AUIPC   = 7'b0010111;
    localparam OPCODE_FENCE   = 7'b0001111;

    reg [4:0] state;
    reg [4:0] next_state;

    wire op_is_rtype;
    wire op_is_itype;
    wire op_is_load;
    wire op_is_store;
    wire op_is_branch;
    wire op_is_jal;
    wire op_is_jalr;
    wire op_is_lui;
    wire op_is_auipc;
    wire op_is_fence;

    wire alu_class_op;
    wire load_funct3_ok;
    wire store_funct3_ok;
    wire branch_funct3_ok;
    wire jalr_funct3_ok;
    wire fence_funct3_ok;
    wire decode_ok;

    assign op_is_rtype = (opcode == OPCODE_OP);
    assign op_is_itype = (opcode == OPCODE_OP_IMM);
    assign op_is_load = (opcode == OPCODE_LOAD);
    assign op_is_store = (opcode == OPCODE_STORE);
    assign op_is_branch = (opcode == OPCODE_BRANCH);
    assign op_is_jal = (opcode == OPCODE_JAL);
    assign op_is_jalr = (opcode == OPCODE_JALR);
    assign op_is_lui = (opcode == OPCODE_LUI);
    assign op_is_auipc = (opcode == OPCODE_AUIPC);
    assign op_is_fence = (opcode == OPCODE_FENCE);

    assign alu_class_op = op_is_rtype | op_is_itype | op_is_lui | op_is_auipc;

    assign load_funct3_ok = (funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b010) |
                            (funct3 == 3'b100) | (funct3 == 3'b101);
    assign store_funct3_ok = (funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b010);
    assign branch_funct3_ok = (funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b100) |
                              (funct3 == 3'b101) | (funct3 == 3'b110) | (funct3 == 3'b111);
    assign jalr_funct3_ok = (funct3 == 3'b000);
    assign fence_funct3_ok = (funct3 == 3'b000) | (funct3 == 3'b001);

    assign decode_ok = (alu_class_op & (~alu_decode_illegal)) |
                       (op_is_load & load_funct3_ok) |
                       (op_is_store & store_funct3_ok) |
                       (op_is_branch & branch_funct3_ok) |
                       op_is_jal |
                       (op_is_jalr & jalr_funct3_ok) |
                       (op_is_fence & fence_funct3_ok);

    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= FETCH;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            FETCH: begin
                next_state = DECODE;
            end

            DECODE: begin
                if (!decode_ok)
                    next_state = ERROR;
                else if (alu_class_op)
                    next_state = EXECUTE_REQ;
                else if (op_is_load | op_is_store)
                    next_state = MEM_ADDR;
                else if (op_is_branch)
                    next_state = EXECUTE_B;
                else if (op_is_jal | op_is_jalr)
                    next_state = EXECUTE_J;
                else if (op_is_fence)
                    next_state = INTERRUPT_CHECK;
                else
                    next_state = ERROR;
            end

            EXECUTE_REQ: begin
                if (exec_ready)
                    next_state = EXECUTE_WAIT;
                else
                    next_state = EXECUTE_REQ;
            end

            EXECUTE_WAIT: begin
                if (exec_done)
                    next_state = WRITE_BACK;
                else
                    next_state = EXECUTE_WAIT;
            end

            EXECUTE_B: begin
                next_state = INTERRUPT_CHECK;
            end

            EXECUTE_J: begin
                next_state = INTERRUPT_CHECK;
            end

            MEM_ADDR: begin
                if (op_is_load)
                    next_state = MEM_READ_REQ;
                else
                    next_state = MEM_WRITE_REQ;
            end

            MEM_READ_REQ: begin
                if (mem_ready)
                    next_state = MEM_READ_WAIT;
                else
                    next_state = MEM_READ_REQ;
            end

            MEM_READ_WAIT: begin
                if (mem_rvalid)
                    next_state = WRITE_BACK;
                else
                    next_state = MEM_READ_WAIT;
            end

            MEM_WRITE_REQ: begin
                if (mem_ready)
                    next_state = MEM_WRITE_WAIT;
                else
                    next_state = MEM_WRITE_REQ;
            end

            MEM_WRITE_WAIT: begin
                if (mem_wdone)
                    next_state = INTERRUPT_CHECK;
                else
                    next_state = MEM_WRITE_WAIT;
            end

            WRITE_BACK: begin
                next_state = INTERRUPT_CHECK;
            end

            INTERRUPT_CHECK: begin
                next_state = FETCH;
            end

            ERROR: begin
                next_state = INTERRUPT_CHECK;
            end

            default: begin
                next_state = FETCH;
            end
        endcase
    end

    always @(*) begin
        ir_write = 1'b0;
        pc_write = 1'b0;
        pc_source = PC_PLUS4;
        reg_write = 1'b0;
        exec_req = 1'b0;
        mem_req = 1'b0;
        mem_write_en = 1'b0;
        wb_sel = WB_ALU;
        alu_src_a = ALU_SRC_A_RS1;
        alu_src_b = ALU_SRC_B_RS2;
        imm_type = IMM_I;
        illegal_instr = 1'b0;
        irq_sample_en = 1'b0;

        case (state)
            FETCH: begin
                ir_write = 1'b1;
                pc_write = 1'b1;
                pc_source = PC_PLUS4;
            end

            EXECUTE_REQ: begin
                exec_req = 1'b1;

                if (op_is_rtype) begin
                    alu_src_a = ALU_SRC_A_RS1;
                    alu_src_b = ALU_SRC_B_RS2;
                    imm_type = IMM_I;
                end else if (op_is_itype) begin
                    alu_src_a = ALU_SRC_A_RS1;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_I;
                end else if (op_is_lui) begin
                    alu_src_a = ALU_SRC_A_ZERO;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_U;
                end else if (op_is_auipc) begin
                    alu_src_a = ALU_SRC_A_PC;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_U;
                end
            end

            EXECUTE_B: begin
                imm_type = IMM_B;
                pc_source = PC_BRANCH;
                pc_write = branch_taken;
            end

            EXECUTE_J: begin
                imm_type = op_is_jal ? IMM_J : IMM_I;
                pc_source = PC_JUMP;
                pc_write = 1'b1;
                reg_write = 1'b1;
                wb_sel = WB_PC4;
            end

            MEM_ADDR: begin
                imm_type = op_is_load ? IMM_I : IMM_S;
            end

            MEM_READ_REQ: begin
                imm_type = IMM_I;
                mem_req = 1'b1;
                mem_write_en = 1'b0;
            end

            MEM_READ_WAIT: begin
                imm_type = IMM_I;
            end

            MEM_WRITE_REQ: begin
                imm_type = IMM_S;
                mem_req = 1'b1;
                mem_write_en = 1'b1;
            end

            MEM_WRITE_WAIT: begin
                imm_type = IMM_S;
            end

            WRITE_BACK: begin
                if (op_is_load) begin
                    reg_write = 1'b1;
                    wb_sel = WB_MEM;
                end else begin
                    reg_write = decode_ok;
                    wb_sel = WB_ALU;
                end
            end

            INTERRUPT_CHECK: begin
                irq_sample_en = 1'b1;
            end

            ERROR: begin
                illegal_instr = 1'b1;
            end
        endcase
    end

    always @(*) begin
        state_dbg = state;
    end

endmodule
