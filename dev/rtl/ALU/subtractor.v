`timescale 1ns / 1ps

module subtractor(
    input  [31:0] b,
    output [31:0] b_neg,
    input  [31:0] adder_sum,
    input         adder_cout,
    output [31:0] result,
    output        borrow
  );
    assign b_neg = ~b;
    assign result = adder_sum;
    assign borrow = ~adder_cout;
endmodule
