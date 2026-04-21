`timescale 1ns / 1ps

// Instruction cache wrapper using FPGA BRAM IP.
// NOTE: iCache IP has the same style of interface as dCache IP.
module instr_mem(
    input         clk,
    input  [31:0] addr,
    output [31:0] instr
);

    wire [10:0] addra;

    assign addra = addr[12:2];

    // IP instance for iCache (32-bit x 2048 words).
    // Replace module name with generated IP name in FPGA project if needed.
    icache icache_bram (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(addra),
        .dina(32'b0),
        .douta(instr),
        .clkb(clk),
        .enb(1'b0),
        .web(1'b0),
        .addrb(11'b0),
        .dinb(32'b0),
        .doutb()
    );

endmodule
