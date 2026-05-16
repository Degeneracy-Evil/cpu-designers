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

module mux_8to1 #(
    parameter WIDTH = 32
  )(
    input  [WIDTH-1:0] in0,
    input  [WIDTH-1:0] in1,
    input  [WIDTH-1:0] in2,
    input  [WIDTH-1:0] in3,
    input  [WIDTH-1:0] in4,
    input  [WIDTH-1:0] in5,
    input  [WIDTH-1:0] in6,
    input  [WIDTH-1:0] in7,
    input  [2:0]       sel,
    output [WIDTH-1:0] y
  );
  assign y = (sel == 3'b000) ? in0 :
             (sel == 3'b001) ? in1 :
             (sel == 3'b010) ? in2 :
             (sel == 3'b011) ? in3 :
             (sel == 3'b100) ? in4 :
             (sel == 3'b101) ? in5 :
             (sel == 3'b110) ? in6 :
                               in7;
endmodule

module mux_16to1 #(
    parameter WIDTH = 32
  )(
    input  [WIDTH-1:0] in0,
    input  [WIDTH-1:0] in1,
    input  [WIDTH-1:0] in2,
    input  [WIDTH-1:0] in3,
    input  [WIDTH-1:0] in4,
    input  [WIDTH-1:0] in5,
    input  [WIDTH-1:0] in6,
    input  [WIDTH-1:0] in7,
    input  [WIDTH-1:0] in8,
    input  [WIDTH-1:0] in9,
    input  [WIDTH-1:0] in10,
    input  [WIDTH-1:0] in11,
    input  [WIDTH-1:0] in12,
    input  [WIDTH-1:0] in13,
    input  [WIDTH-1:0] in14,
    input  [WIDTH-1:0] in15,
    input  [3:0]       sel,
    output [WIDTH-1:0] y
  );
  assign y = (sel == 4'd0)  ? in0  :
             (sel == 4'd1)  ? in1  :
             (sel == 4'd2)  ? in2  :
             (sel == 4'd3)  ? in3  :
             (sel == 4'd4)  ? in4  :
             (sel == 4'd5)  ? in5  :
             (sel == 4'd6)  ? in6  :
             (sel == 4'd7)  ? in7  :
             (sel == 4'd8)  ? in8  :
             (sel == 4'd9)  ? in9  :
             (sel == 4'd10) ? in10 :
             (sel == 4'd11) ? in11 :
             (sel == 4'd12) ? in12 :
             (sel == 4'd13) ? in13 :
             (sel == 4'd14) ? in14 :
                               in15;
endmodule
