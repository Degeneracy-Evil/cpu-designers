`timescale 1ns / 1ps

// ALU control decoder.
// Maps RV32I opcode/funct fields to dev/1-alu one-hot ALU control codes.
// Flags illegal instructions when opcode/funct combination is unsupported.
module alu_control(
    // Instruction opcode field.
    input  [6:0] opcode,
    // Instruction funct3 field.
    input  [2:0] funct3,
    // Instruction funct7 field.
    input  [6:0] funct7,
    // One-hot ALU operation select.
    output reg [15:0] alu_control,
    // Illegal decode indicator.
    output reg        illegal_instr
);

    // dev/1-alu one-hot operation encodings.
    localparam ALU_SRA  = 16'b0000_0000_0000_0100;
    localparam ALU_SRL  = 16'b0000_0000_0000_1000;
    localparam ALU_SLL  = 16'b0000_0000_0001_0000;
    localparam ALU_XOR  = 16'b0000_0000_0010_0000;
    localparam ALU_OR   = 16'b0000_0000_0100_0000;
    localparam ALU_AND  = 16'b0000_0001_0000_0000;
    localparam ALU_SLTU = 16'b0000_0010_0000_0000;
    localparam ALU_SLT  = 16'b0000_0100_0000_0000;
    localparam ALU_SUB  = 16'b0000_1000_0000_0000;
    localparam ALU_ADD  = 16'b0001_0000_0000_0000;

    // Combinational decode logic.
    always @(*) begin
        // Default to ADD and legal.
        alu_control = ALU_ADD;
        illegal_instr = 1'b0;

        case (opcode)
            // R-type register-register operations.
            7'b0110011: begin
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_ADD;
                        else if (funct7 == 7'b0100000)
                            alu_control = ALU_SUB;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SLL;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b010: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SLT;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b011: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SLTU;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b100: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_XOR;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SRL;
                        else if (funct7 == 7'b0100000)
                            alu_control = ALU_SRA;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b110: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_OR;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b111: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_AND;
                        else
                            illegal_instr = 1'b1;
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end

            // I-type ALU immediate operations.
            7'b0010011: begin
                case (funct3)
                    3'b000: alu_control = ALU_ADD;
                    3'b001: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SLL;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b010: alu_control = ALU_SLT;
                    3'b011: alu_control = ALU_SLTU;
                    3'b100: alu_control = ALU_XOR;
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_control = ALU_SRL;
                        else if (funct7 == 7'b0100000)
                            alu_control = ALU_SRA;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b110: alu_control = ALU_OR;
                    3'b111: alu_control = ALU_AND;
                    default: illegal_instr = 1'b1;
                endcase
            end

            // LUI uses ALU add path with srcA=0 and srcB=imm(U).
            7'b0110111: alu_control = ALU_ADD;
            // AUIPC uses ALU add path with srcA=PC and srcB=imm(U).
            7'b0010111: alu_control = ALU_ADD;

            // Other opcodes are unsupported in phase-1.
            default: illegal_instr = 1'b1;
        endcase
    end

endmodule
