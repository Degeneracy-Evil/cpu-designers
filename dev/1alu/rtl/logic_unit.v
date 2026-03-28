`timescale 1ns / 1ps

module logic_unit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] and_result,
    output [31:0] or_result,
    output [31:0] not_result,
    output [31:0] xor_result,
    output [31:0] nor_result,
    output [31:0] slt_result,
    output [31:0] sltu_result
);
    wire [31:0] sub_result;
    wire sub_borrow;
    wire [31:0] a_xor_b;
    wire sign_diff;
    
    gate_and_32bit and_gate(.a(a), .b(b), .y(and_result));
    gate_or_32bit  or_gate(.a(a), .b(b), .y(or_result));
    gate_not_32bit not_gate(.a(a), .y(not_result));
    gate_xor_32bit xor_gate(.a(a), .b(b), .y(xor_result));
    gate_nor_32bit nor_gate(.a(a), .b(b), .y(nor_result));
    
    subtractor sub(
        .a(a),
        .b(b),
        .result(sub_result),
        .borrow(sub_borrow)
    );
    
    assign a_xor_b = a ^ b;
    assign sign_diff = sub_result[31];
    
    assign slt_result[31:1] = 31'b0;
    assign slt_result[0] = (a[31] & ~b[31]) | (~a_xor_b[31] & sign_diff);
    
    wire [31:0] b_complement;
    wire [31:0] add_result;
    wire add_cout;
    
    assign b_complement = ~b;
    
    cla_adder_32bit adder(
        .a(a),
        .b(b_complement),
        .cin(1'b1),
        .sum(add_result),
        .cout(add_cout)
    );
    
    assign sltu_result[31:1] = 31'b0;
    assign sltu_result[0] = ~add_cout;
endmodule