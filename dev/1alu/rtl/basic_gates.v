`timescale 1ns / 1ps

module gate_and(
    input  a,
    input  b,
    output y
);
    and u_and(y, a, b);
endmodule

module gate_or(
    input  a,
    input  b,
    output y
);
    or u_or(y, a, b);
endmodule

module gate_not(
    input  a,
    output y
);
    not u_not(y, a);
endmodule

module gate_xor(
    input  a,
    input  b,
    output y
);
    xor u_xor(y, a, b);
endmodule

module gate_nor(
    input  a,
    input  b,
    output y
);
    nor u_nor(y, a, b);
endmodule

module gate_nand(
    input  a,
    input  b,
    output y
);
    nand u_nand(y, a, b);
endmodule

module gate_xnor(
    input  a,
    input  b,
    output y
);
    xnor u_xnor(y, a, b);
endmodule

module gate_and_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : and_gate
            and u_and(y[i], a[i], b[i]);
        end
    endgenerate
endmodule

module gate_or_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : or_gate
            or u_or(y[i], a[i], b[i]);
        end
    endgenerate
endmodule

module gate_not_32bit(
    input  [31:0] a,
    output [31:0] y
);
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : not_gate
            not u_not(y[i], a[i]);
        end
    endgenerate
endmodule

module gate_xor_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : xor_gate
            xor u_xor(y[i], a[i], b[i]);
        end
    endgenerate
endmodule

module gate_nor_32bit(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : nor_gate
            nor u_nor(y[i], a[i], b[i]);
        end
    endgenerate
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