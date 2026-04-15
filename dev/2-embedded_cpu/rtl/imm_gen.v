`timescale 1ns / 1ps

// Immediate generator for RV32I instruction formats.
// Supports I/S/B/U/J immediate extraction and sign extension rules.
module imm_gen(
    // Raw 32-bit instruction word.
    input  [31:0] instr,
    // Immediate type selector from main controller.
    input  [2:0]  imm_type,
    // Generated 32-bit immediate value.
    output reg [31:0] imm
);

    // Immediate type encodings.
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    // Combinational immediate decode.
    always @(*) begin
        case (imm_type)
            // I-type: sign-extend inst[31:20].
            IMM_I:   imm = {{20{instr[31]}}, instr[31:20]};
            // S-type: sign-extend {inst[31:25], inst[11:7]}.
            IMM_S:   imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            // B-type: sign-extend and append low zero bit.
            IMM_B:   imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            // U-type: upper 20 bits shifted left by 12.
            IMM_U:   imm = {instr[31:12], 12'b0};
            // J-type: sign-extend and append low zero bit.
            IMM_J:   imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            // Safe default for unsupported type.
            default: imm = 32'b0;
        endcase
    end

endmodule
