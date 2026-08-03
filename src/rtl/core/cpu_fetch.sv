`timescale 1ns / 1ps

module cpu_fetch(
    input         clk,
    input         resetn,
    input         if_valid,
    input         init_sig,
    input  [31:0] pc,
    input  [31:0] instData_32,
    input         inst_valid,
    output [31:0] instAddr_32,
    output        if_done,
    output [95:0] if_id_bus,

    output [31:0] if_pc,
    output [31:0] if_inst
);

    wire [31:0] pc_plus4;
    assign pc_plus4 = pc + 32'd4;
    assign instAddr_32 = pc;

    assign if_done = if_valid && inst_valid;

    assign if_id_bus = {pc_plus4, pc, instData_32};

    assign if_pc = pc;
    assign if_inst = instData_32;

endmodule
