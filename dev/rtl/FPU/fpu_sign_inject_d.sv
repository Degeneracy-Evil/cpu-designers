`timescale 1ns / 1ps

// Double-precision floating-point sign inject (FSGNJ.D / FSGNJN.D / FSGNJX.D)
// Pure combinational. IEEE 754 double: 1+11+52, bias 1023.
// sgnj_funct: 3'b000=FSGNJ (copy sign from src2),
//             3'b001=FSGNJN (invert sign from src2),
//             3'b010=FSGNJX (XOR signs)
// result:  64-bit with modified sign bit, rest of src1 preserved.
// fflags:  always 0 (sign inject never raises exceptions).

module fpu_sign_inject_d(
    input  [63:0] src1,
    input  [63:0] src2,
    input  [2:0]  sgnj_funct,  // 000=FSGNJ, 001=FSGNJN, 010=FSGNJX
    output [63:0] result,
    output [4:0]  fflags       // always 0 for sign inject
);

    wire sign1 = src1[63];
    wire sign2 = src2[63];

    // FSGNJ.D:  result = {src2[63], src1[62:0]}  (copy sign from src2)
    // FSGNJN.D: result = {~src2[63], src1[62:0]} (copy inverted sign from src2)
    // FSGNJX.D: result = {src1[63]^src2[63], src1[62:0]} (XOR signs)
    wire new_sign = (sgnj_funct == 3'b000) ? sign2 :
                    (sgnj_funct == 3'b001) ? ~sign2 :
                    /* 3'b010 */             (sign1 ^ sign2);

    assign result = {new_sign, src1[62:0]};
    assign fflags = 5'b00000;

endmodule
