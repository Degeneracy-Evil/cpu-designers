`timescale 1ns / 1ps

module fpu_sign_inject(
    input  [31:0] src1,
    input  [31:0] src2,
    input  [2:0]  sgnj_funct,  // 000=FSGNJ, 001=FSGNJN, 010=FSGNJX
    output [31:0] result,
    output [4:0]  fflags       // always 0 for sign inject
);

    wire sign1 = src1[31];
    wire sign2 = src2[31];

    // FSGNJ.S:  result = {src2[31], src1[30:0]}  (copy sign from src2)
    // FSGNJN.S: result = {~src2[31], src1[30:0]} (copy inverted sign from src2)
    // FSGNJX.S: result = {src1[31]^src2[31], src1[30:0]} (XOR signs)
    wire new_sign = (sgnj_funct == 3'b000) ? sign2 :
                    (sgnj_funct == 3'b001) ? ~sign2 :
                    /* 3'b010 */             (sign1 ^ sign2);

    assign result = {new_sign, src1[30:0]};
    assign fflags = 5'b00000;

endmodule
