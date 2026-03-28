`timescale 1ns / 1ps

module subtractor(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result,
    output        borrow
);
    wire [31:0] b_complement;
    wire [31:0] sum;
    wire cout;
    
    assign b_complement = ~b;
    
    cla_adder_32bit adder(
        .a(a),
        .b(b_complement),
        .cin(1'b1),
        .sum(sum),
        .cout(cout)
    );
    
    assign result = sum;
    assign borrow = ~cout;
endmodule