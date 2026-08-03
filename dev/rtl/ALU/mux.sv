`timescale 1ns / 1ps

module mux_2to1 #(
    parameter WIDTH = 32
  )(
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input              sel,
    output [WIDTH-1:0] y
  );
  assign y = sel ? b : a;
endmodule

module mux_4to1 #(
    parameter WIDTH = 32
  )(
    input  [WIDTH-1:0] in0,
    input  [WIDTH-1:0] in1,
    input  [WIDTH-1:0] in2,
    input  [WIDTH-1:0] in3,
    input  [1:0]       sel,
    output [WIDTH-1:0] y
  );
  assign y = (sel == 2'b00) ? in0 :
             (sel == 2'b01) ? in1 :
             (sel == 2'b10) ? in2 :
                              in3;
endmodule
