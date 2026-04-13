`timescale 1ns / 1ps

// 32位riscv-CPU
module rsicv32bit();

    // 寄存器组
    reg [31:0] PC;
    reg [31:0] x0;
    reg [31:0] x1;
    reg [31:0] x2;
    reg [31:0] x3;
    reg [31:0] x4;
    reg [31:0] x5;
    reg [31:0] x6;
    reg [31:0] x7;
    reg [31:0] x8;
    reg [31:0] x9;
    reg [31:0] x10;
    reg [31:0] x11;
    reg [31:0] x12;
    reg [31:0] x13;
    reg [31:0] x14;
    reg [31:0] x15;
    reg [31:0] x16;
    reg [31:0] x17;
    reg [31:0] x18;
    reg [31:0] x19;
    reg [31:0] x20;
    reg [31:0] x21;
    reg [31:0] x22;
    reg [31:0] x23;
    reg [31:0] x24;
    reg [31:0] x25;
    reg [31:0] x26;
    reg [31:0] x27;
    reg [31:0] x28;
    reg [31:0] x29;
    reg [31:0] x30;
    reg [31:0] x31;

    wire [31:0] op32bit; // op输入占位符
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [31:0] immI;
    wire [31:0] immS;
    wire [31:0] immB;
    wire [31:0] immU;
    wire [31:0] immJ;

    op_regroup regrouper(
        .op32bit(op32bit),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .immI(immI),
        .immS(immS),
        .immB(immB),
        .immU(immU),
        .immJ(immJ)
    );

endmodule