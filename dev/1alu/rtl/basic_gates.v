`timescale 1ns / 1ps

module gate_and(
    input  a,
    input  b,
    output y
);
    assign y = a & b;
endmodule

module gate_or(
    input  a,
    input  b,
    output y
);
    assign y = a | b;
endmodule

module gate_not(
    input  a,
    output y
);
    assign y = ~a;
endmodule

module gate_xor(
    input  a,
    input  b,
    output y
);
    assign y = a ^ b;
endmodule

module gate_nor(
    input  a,
    input  b,
    output y
);
    assign y = ~(a | b);
endmodule

module gate_nand(
    input  a,
    input  b,
    output y
);
    assign y = ~(a & b);
endmodule

module gate_xnor(
    input  a,
    input  b,
    output y
);
    assign y = ~(a ^ b);
endmodule

module gate_and_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    assign y = a & b;
endmodule

module gate_or_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    assign y = a | b;
endmodule

module gate_not_32bit(
    input  [31:0] a,
    output [31:0] y
);
    assign y = ~a;
endmodule

module gate_xor_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    assign y = a ^ b;
endmodule

module gate_nor_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    assign y = ~(a | b);
endmodule

module full_adder(
    input  a,
    input  b,
    input  cin,
    output sum,
    output cout
);
    wire w1, w2, w3;
    
    gate_xor xor1(.a(a), .b(b), .y(w1));
    gate_xor xor2(.a(w1), .b(cin), .y(sum));
    
    gate_and and1(.a(a), .b(b), .y(w2));
    gate_and and2(.a(w1), .b(cin), .y(w3));
    gate_or  or1(.a(w2), .b(w3), .y(cout));
endmodule