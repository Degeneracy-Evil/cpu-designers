`timescale 1ns / 1ps

module logic_unit(
    input  [31:0] a,
    input  [31:0] b,
    input  [31:0] sub_result,
    input         sub_borrow,
    output [31:0] and_result,
    output [31:0] or_result,
    output [31:0] not_result,
    output [31:0] xor_result,
    output [31:0] nor_result,
    output [31:0] slt_result,
    output [31:0] sltu_result
  );
  assign and_result = a & b;
  assign or_result  = a | b;
  assign not_result = ~a;
  assign xor_result = a ^ b;
  assign nor_result = ~(a | b);

  assign slt_result[31:1] = 31'b0;
  assign slt_result[0] = (a[31] & ~b[31]) | (~(a[31] ^ b[31]) & sub_result[31]);

  assign sltu_result[31:1] = 31'b0;
  assign sltu_result[0] = sub_borrow;
endmodule
