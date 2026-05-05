`timescale 1ns / 1ps

module alu_result_selector(
    input  [31:0] mul_result,
    input  [31:0] div_result,
    input  [31:0] not_result,
    input  [31:0] add_result,
    input  [31:0] sub_result,
    input  [31:0] slt_result,
    input  [31:0] sltu_result,
    input  [31:0] and_result,
    input  [31:0] nor_result,
    input  [31:0] or_result,
    input  [31:0] xor_result,
    input  [31:0] sll_result,
    input  [31:0] srl_result,
    input  [31:0] sra_result,
    input  [31:0] lui_result,
    input  [15:0] sel,
    output [31:0] y
  );
  wire [31:0] y_lui;
  wire [31:0] y_sra;
  wire [31:0] y_srl;
  wire [31:0] y_sll;
  wire [31:0] y_xor;
  wire [31:0] y_or;
  wire [31:0] y_nor;
  wire [31:0] y_and;
  wire [31:0] y_sltu;
  wire [31:0] y_slt;
  wire [31:0] y_sub;
  wire [31:0] y_add;
  wire [31:0] y_not;
  wire [31:0] y_div;
  wire [31:0] y_mul;

  assign y_lui  = {32{sel[1]}}  & lui_result;
  assign y_sra  = {32{sel[2]}}  & sra_result;
  assign y_srl  = {32{sel[3]}}  & srl_result;
  assign y_sll  = {32{sel[4]}}  & sll_result;
  assign y_xor  = {32{sel[5]}}  & xor_result;
  assign y_or   = {32{sel[6]}}  & or_result;
  assign y_nor  = {32{sel[7]}}  & nor_result;
  assign y_and  = {32{sel[8]}}  & and_result;
  assign y_sltu = {32{sel[9]}}  & sltu_result;
  assign y_slt  = {32{sel[10]}} & slt_result;
  assign y_sub  = {32{sel[11]}} & sub_result;
  assign y_add  = {32{sel[12]}} & add_result;
  assign y_not  = {32{sel[13]}} & not_result;
  assign y_div  = {32{sel[14]}} & div_result;
  assign y_mul  = {32{sel[15]}} & mul_result;

  assign y = y_lui | y_sra | y_srl | y_sll | y_xor |
         y_or | y_nor | y_and | y_sltu | y_slt |
         y_sub | y_add | y_not | y_div | y_mul;
endmodule
