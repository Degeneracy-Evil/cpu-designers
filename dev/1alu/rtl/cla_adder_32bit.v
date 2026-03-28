`timescale 1ns / 1ps

module cla_adder_32bit(
    input  [31:0] a,
    input  [31:0] b,
    input         cin,
    output [31:0] sum,
    output        cout
);
    wire c15;
    
    cla_adder_16bit cla0(
        .a(a[15:0]),
        .b(b[15:0]),
        .cin(cin),
        .sum(sum[15:0]),
        .cout(c15)
    );
    
    cla_adder_16bit cla1(
        .a(a[31:16]),
        .b(b[31:16]),
        .cin(c15),
        .sum(sum[31:16]),
        .cout(cout)
    );
endmodule