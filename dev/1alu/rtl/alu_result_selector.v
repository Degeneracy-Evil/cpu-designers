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
    wire [31:0] mux_step0;
    wire [31:0] mux_step1;
    wire [31:0] mux_step2;
    wire [31:0] mux_step3;
    wire [31:0] mux_step4;
    wire [31:0] mux_step5;
    wire [31:0] mux_step6;
    wire [31:0] mux_step7;
    wire [31:0] mux_step8;
    wire [31:0] mux_step9;
    wire [31:0] mux_step10;
    wire [31:0] mux_step11;
    wire [31:0] mux_step12;
    wire [31:0] mux_step13;
    wire [31:0] mux_step14;
    
    mux_2to1 #(32) mux0(
        .a(32'b0),
        .b(lui_result),
        .sel(sel[1]),
        .y(mux_step0)
    );
    
    mux_2to1 #(32) mux1(
        .a(mux_step0),
        .b(sra_result),
        .sel(sel[2]),
        .y(mux_step1)
    );
    
    mux_2to1 #(32) mux2(
        .a(mux_step1),
        .b(srl_result),
        .sel(sel[3]),
        .y(mux_step2)
    );
    
    mux_2to1 #(32) mux3(
        .a(mux_step2),
        .b(sll_result),
        .sel(sel[4]),
        .y(mux_step3)
    );
    
    mux_2to1 #(32) mux4(
        .a(mux_step3),
        .b(xor_result),
        .sel(sel[5]),
        .y(mux_step4)
    );
    
    mux_2to1 #(32) mux5(
        .a(mux_step4),
        .b(or_result),
        .sel(sel[6]),
        .y(mux_step5)
    );
    
    mux_2to1 #(32) mux6(
        .a(mux_step5),
        .b(nor_result),
        .sel(sel[7]),
        .y(mux_step6)
    );
    
    mux_2to1 #(32) mux7(
        .a(mux_step6),
        .b(and_result),
        .sel(sel[8]),
        .y(mux_step7)
    );
    
    mux_2to1 #(32) mux8(
        .a(mux_step7),
        .b(sltu_result),
        .sel(sel[9]),
        .y(mux_step8)
    );
    
    mux_2to1 #(32) mux9(
        .a(mux_step8),
        .b(slt_result),
        .sel(sel[10]),
        .y(mux_step9)
    );
    
    mux_2to1 #(32) mux10(
        .a(mux_step9),
        .b(sub_result),
        .sel(sel[11]),
        .y(mux_step10)
    );
    
    mux_2to1 #(32) mux11(
        .a(mux_step10),
        .b(add_result),
        .sel(sel[12]),
        .y(mux_step11)
    );
    
    mux_2to1 #(32) mux12(
        .a(mux_step11),
        .b(not_result),
        .sel(sel[13]),
        .y(mux_step12)
    );
    
    mux_2to1 #(32) mux13(
        .a(mux_step12),
        .b(div_result),
        .sel(sel[14]),
        .y(mux_step13)
    );
    
    mux_2to1 #(32) mux14(
        .a(mux_step13),
        .b(mul_result),
        .sel(sel[15]),
        .y(y)
    );
endmodule