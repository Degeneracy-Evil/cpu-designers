`timescale 1ns / 1ps

module cla_adder_4bit(
    input  [3:0] a,
    input  [3:0] b,
    input         cin,
    output [3:0] sum,
    output        cout,
    output [3:0] g,
    output [3:0] p
);
    wire [3:0] c;
    
    assign p[0] = a[0] ^ b[0];
    assign g[0] = a[0] & b[0];
    assign sum[0] = p[0] ^ cin;
    assign c[0] = g[0] | (p[0] & cin);
    
    assign p[1] = a[1] ^ b[1];
    assign g[1] = a[1] & b[1];
    assign sum[1] = p[1] ^ c[0];
    assign c[1] = g[1] | (p[1] & c[0]);
    
    assign p[2] = a[2] ^ b[2];
    assign g[2] = a[2] & b[2];
    assign sum[2] = p[2] ^ c[1];
    assign c[2] = g[2] | (p[2] & c[1]);
    
    assign p[3] = a[3] ^ b[3];
    assign g[3] = a[3] & b[3];
    assign sum[3] = p[3] ^ c[2];
    assign c[3] = g[3] | (p[3] & c[2]);
    
    assign cout = c[3];
endmodule