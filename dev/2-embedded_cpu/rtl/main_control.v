`timescale 1ns / 1ps

// Main multi-cycle controller (phase-1).
// Implements core FSM path:
// FETCH -> DECODE -> EXECUTE_REQ -> EXECUTE_WAIT -> WRITE_BACK -> INTERRUPT_CHECK -> FETCH
// Also keeps MEM REQ/WAIT state codes reserved for later phases.
module main_control(
    // Global clock.
    input         clk,
    // Asynchronous active-high reset.
    input         reset,
    // Current instruction opcode.
    input  [6:0]  opcode,
    // ALU decode illegal flag.
    input         alu_decode_illegal,
    // Execute unit ready handshake.
    input         exec_ready,
    // Execute unit done handshake.
    input         exec_done,
    // Instruction register write enable.
    output reg        ir_write,
    // Program counter write enable.
    output reg        pc_write,
    // Program counter source select.
    output reg [1:0]  pc_source,
    // Register file write enable.
    output reg        reg_write,
    // Execute request valid.
    output reg        exec_req,
    // ALU source A select.
    output reg [1:0]  alu_src_a,
    // ALU source B select.
    output reg [1:0]  alu_src_b,
    // Immediate type select.
    output reg [2:0]  imm_type,
    // Illegal instruction marker for debug/trap path.
    output reg        illegal_instr,
    // Current FSM state for debug visibility.
    output reg [4:0]  state_dbg,
    // Interrupt sample enable at instruction boundary.
    output reg        irq_sample_en
);

    // FSM state encoding.
    localparam FETCH            = 5'd0;
    localparam DECODE           = 5'd1;
    localparam EXECUTE_REQ      = 5'd2;
    localparam EXECUTE_WAIT     = 5'd3;
    localparam WRITE_BACK       = 5'd4;
    localparam INTERRUPT_CHECK  = 5'd5;
    localparam MEM_READ_REQ     = 5'd6;
    localparam MEM_READ_WAIT    = 5'd7;
    localparam MEM_WRITE_REQ    = 5'd8;
    localparam MEM_WRITE_WAIT   = 5'd9;
    localparam ERROR            = 5'd31;

    // PC source encoding.
    localparam PC_PLUS4 = 2'b00;

    // ALU source mux encoding.
    localparam ALU_SRC_A_RS1  = 2'b00;
    localparam ALU_SRC_A_PC   = 2'b01;
    localparam ALU_SRC_A_ZERO = 2'b10;

    localparam ALU_SRC_B_RS2 = 2'b00;
    localparam ALU_SRC_B_IMM = 2'b01;

    // Immediate type encoding.
    localparam IMM_I = 3'b000;
    localparam IMM_U = 3'b011;

    // Supported opcode set in phase-1.
    localparam OPCODE_OP      = 7'b0110011;
    localparam OPCODE_OP_IMM  = 7'b0010011;
    localparam OPCODE_LUI     = 7'b0110111;
    localparam OPCODE_AUIPC   = 7'b0010111;

    reg [4:0] state;
    reg [4:0] next_state;

    // Decode helpers.
    wire op_is_rtype;
    wire op_is_itype;
    wire op_is_lui;
    wire op_is_auipc;
    wire op_supported;
    wire decode_ok;

    assign op_is_rtype = (opcode == OPCODE_OP);
    assign op_is_itype = (opcode == OPCODE_OP_IMM);
    assign op_is_lui = (opcode == OPCODE_LUI);
    assign op_is_auipc = (opcode == OPCODE_AUIPC);
    assign op_supported = op_is_rtype | op_is_itype | op_is_lui | op_is_auipc;
    assign decode_ok = op_supported & (~alu_decode_illegal);

    // FSM state register.
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= FETCH;
        else
            state <= next_state;
    end

    // FSM next-state logic.
    always @(*) begin
        next_state = state;
        case (state)
            FETCH: begin
                // One-cycle fetch, then decode latched instruction.
                next_state = DECODE;
            end

            DECODE: begin
                // Continue only when opcode/funct decode is legal.
                if (decode_ok)
                    next_state = EXECUTE_REQ;
                else
                    next_state = ERROR;
            end

            EXECUTE_REQ: begin
                // Hold request until execute unit accepts it.
                if (exec_ready)
                    next_state = EXECUTE_WAIT;
                else
                    next_state = EXECUTE_REQ;
            end

            EXECUTE_WAIT: begin
                // Wait for execute result valid.
                if (exec_done)
                    next_state = WRITE_BACK;
                else
                    next_state = EXECUTE_WAIT;
            end

            WRITE_BACK: begin
                // Commit ALU result to register file.
                next_state = INTERRUPT_CHECK;
            end

            INTERRUPT_CHECK: begin
                // Instruction-boundary sampling point.
                next_state = FETCH;
            end

            ERROR: begin
                // Phase-1 fallback path for illegal instructions.
                next_state = INTERRUPT_CHECK;
            end

            default: begin
                next_state = FETCH;
            end
        endcase
    end

    // FSM output/control logic.
    always @(*) begin
        // Safe defaults.
        ir_write = 1'b0;
        pc_write = 1'b0;
        pc_source = PC_PLUS4;
        reg_write = 1'b0;
        exec_req = 1'b0;
        alu_src_a = ALU_SRC_A_RS1;
        alu_src_b = ALU_SRC_B_RS2;
        imm_type = IMM_I;
        illegal_instr = 1'b0;
        irq_sample_en = 1'b0;

        case (state)
            FETCH: begin
                // Latch instruction and advance PC by +4.
                ir_write = 1'b1;
                pc_write = 1'b1;
            end

            EXECUTE_REQ: begin
                // Fire execute request and select ALU sources by instruction class.
                exec_req = 1'b1;

                if (op_is_rtype) begin
                    // R-type: rs1 op rs2.
                    alu_src_a = ALU_SRC_A_RS1;
                    alu_src_b = ALU_SRC_B_RS2;
                    imm_type = IMM_I;
                end else if (op_is_itype) begin
                    // I-type: rs1 op imm(I).
                    alu_src_a = ALU_SRC_A_RS1;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_I;
                end else if (op_is_lui) begin
                    // LUI implemented as 0 + imm(U).
                    alu_src_a = ALU_SRC_A_ZERO;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_U;
                end else if (op_is_auipc) begin
                    // AUIPC implemented as PC + imm(U).
                    alu_src_a = ALU_SRC_A_PC;
                    alu_src_b = ALU_SRC_B_IMM;
                    imm_type = IMM_U;
                end
            end

            WRITE_BACK: begin
                // Enable architectural state writeback for valid decode.
                reg_write = decode_ok;
            end

            INTERRUPT_CHECK: begin
                // Explicit pulse for future interrupt sampling logic.
                irq_sample_en = 1'b1;
            end

            ERROR: begin
                // Export illegal instruction indication.
                illegal_instr = 1'b1;
            end
        endcase
    end

    // Debug state mirror.
    always @(*) begin
        state_dbg = state;
    end

endmodule
