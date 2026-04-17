`timescale 1ns / 1ps

// Instruction cache (L1 iCache) backed by BRAM.
module instr_mem #(
    parameter MEM_DEPTH = 256,
    parameter ADDR_WIDTH = 8,
    parameter INIT_FILE = ""
)(
    input         clk,
    input  [31:0] addr,
    output [31:0] instr
);

    wire [31:0] bram_dout;
    wire [ADDR_WIDTH-1:0] word_addr;

    assign word_addr = addr[ADDR_WIDTH+1:2];

    bram #(
        .DEPTH(MEM_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE(INIT_FILE)
    ) icache_bram (
        .clka(clk),
        .wea(4'b0000),
        .addra(word_addr),
        .dina(32'b0),
        .douta(bram_dout),
        .clkb(clk),
        .web(4'b0000),
        .addrb({ADDR_WIDTH{1'b0}}),
        .dinb(32'b0),
        .doutb()
    );

    assign instr = bram_dout;

endmodule
