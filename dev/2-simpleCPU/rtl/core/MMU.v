`timescale 1ns / 1ps

module MMU(
    input         clk,
    input         reset,
    input  [31:0] vaddr,
    output [31:0] paddr
);

    assign paddr = vaddr;

endmodule
