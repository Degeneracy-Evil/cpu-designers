`timescale 1ns / 1ps

// 基础门电路模块 - 使用Verilog内置门级原语
// 避免使用assign进行算术运算，防止被推断为IP核

// 2输入与门
module gate_and(
    input  a,
    input  b,
    output y
);
    and u_and(y, a, b);
endmodule

// 2输入或门
module gate_or(
    input  a,
    input  b,
    output y
);
    or u_or(y, a, b);
endmodule

// 非门
module gate_not(
    input  a,
    output y
);
    not u_not(y, a);
endmodule

// 2输入异或门
module gate_xor(
    input  a,
    input  b,
    output y
);
    xor u_xor(y, a, b);
endmodule

// 2输入或非门
module gate_nor(
    input  a,
    input  b,
    output y
);
    nor u_nor(y, a, b);
endmodule

// 2输入与非门
module gate_nand(
    input  a,
    input  b,
    output y
);
    nand u_nand(y, a, b);
endmodule

// 2输入同或门
module gate_xnor(
    input  a,
    input  b,
    output y
);
    xnor u_xnor(y, a, b);
endmodule

// 32位与门 - 使用generate对每一位实例化
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

// 32位或门
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

// 32位非门
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

// 32位异或门
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

// 32位或非门
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

// 全加器 - 使用基础门构建
// sum = a ^ b ^ cin
// cout = (a & b) | ((a ^ b) & cin)
module full_adder(
    input  a,
    input  b,
    input  cin,
    output sum,
    output cout
);
    wire w1, w2, w3;
    
    gate_xor xor1(.a(a), .b(b), .y(w1));      // w1 = a ^ b
    gate_xor xor2(.a(w1), .b(cin), .y(sum));  // sum = w1 ^ cin
    
    gate_and and1(.a(a), .b(b), .y(w2));      // w2 = a & b
    gate_and and2(.a(w1), .b(cin), .y(w3));   // w3 = (a ^ b) & cin
    gate_or  or1(.a(w2), .b(w3), .y(cout));   // cout = w2 | w3
endmodule