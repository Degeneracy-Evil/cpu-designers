`timescale 1ns / 1ps

// 2选1多路选择器 - 门级实现
// 功能: y = sel ? b : a
// 实现: 使用门级原语，避免被综合为IP核
module mux_2to1 #(
    parameter WIDTH = 32
  )(
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input              sel,
    output [WIDTH-1:0] y
  );
  wire [WIDTH-1:0] a_masked;
  wire [WIDTH-1:0] b_masked;
  wire [WIDTH-1:0] not_sel_vec;

  // 对每一位独立实现: y[i] = (a[i] & ~sel) | (b[i] & sel)
  genvar i;
  generate
    for (i = 0; i < WIDTH; i = i + 1)
    begin : mux_bit
      not u_not_sel(not_sel_vec[i], sel);
      and u_and_a(a_masked[i], a[i], not_sel_vec[i]);
      and u_and_b(b_masked[i], b[i], sel);
      or  u_or_y(y[i], a_masked[i], b_masked[i]);
    end
  endgenerate
endmodule

// 4选1多路选择器 - 层次化实现
// 使用3个2选1MUX构建
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
  wire [WIDTH-1:0] mux0_out;
  wire [WIDTH-1:0] mux1_out;

  // 第一级: 根据sel[0]选择in0/in1和in2/in3
  mux_2to1 #(WIDTH) mux0(
             .a(in0),
             .b(in1),
             .sel(sel[0]),
             .y(mux0_out)
           );

  mux_2to1 #(WIDTH) mux1(
             .a(in2),
             .b(in3),
             .sel(sel[0]),
             .y(mux1_out)
           );

  // 第二级: 根据sel[1]选择mux0_out或mux1_out
  mux_2to1 #(WIDTH) mux_final(
             .a(mux0_out),
             .b(mux1_out),
             .sel(sel[1]),
             .y(y)
           );
endmodule

// 8选1多路选择器 - 层次化实现
// 使用2个4选1MUX和1个2选1MUX构建
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
  wire [WIDTH-1:0] mux0_out;
  wire [WIDTH-1:0] mux1_out;

  // 低4输入和高4输入分别选择
  mux_4to1 #(WIDTH) mux0(
             .in0(in0),
             .in1(in1),
             .in2(in2),
             .in3(in3),
             .sel(sel[1:0]),
             .y(mux0_out)
           );

  mux_4to1 #(WIDTH) mux1(
             .in0(in4),
             .in1(in5),
             .in2(in6),
             .in3(in7),
             .sel(sel[1:0]),
             .y(mux1_out)
           );

  // 最终选择
  mux_2to1 #(WIDTH) mux_final(
             .a(mux0_out),
             .b(mux1_out),
             .sel(sel[2]),
             .y(y)
           );
endmodule

// 16选1多路选择器 - 层次化实现
// 使用2个8选1MUX和1个2选1MUX构建
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
  wire [WIDTH-1:0] mux0_out;
  wire [WIDTH-1:0] mux1_out;

  // 低8输入和高8输入分别选择
  mux_8to1 #(WIDTH) mux0(
             .in0(in0),
             .in1(in1),
             .in2(in2),
             .in3(in3),
             .in4(in4),
             .in5(in5),
             .in6(in6),
             .in7(in7),
             .sel(sel[2:0]),
             .y(mux0_out)
           );

  mux_8to1 #(WIDTH) mux1(
             .in0(in8),
             .in1(in9),
             .in2(in10),
             .in3(in11),
             .in4(in12),
             .in5(in13),
             .in6(in14),
             .in7(in15),
             .sel(sel[2:0]),
             .y(mux1_out)
           );

  // 最终选择
  mux_2to1 #(WIDTH) mux_final(
             .a(mux0_out),
             .b(mux1_out),
             .sel(sel[3]),
             .y(y)
           );
endmodule
