`timescale 1ns / 1ps

// Dual-port BRAM simulation model.
// Port A and Port B are symmetric 32-bit byte-write ports.
module bram #(
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = 8,
    parameter INIT_FILE = ""
)(
    input                     clka,
    input      [3:0]          wea,
    input      [ADDR_WIDTH-1:0] addra,
    input      [31:0]         dina,
    output     [31:0]         douta,

    input                     clkb,
    input      [3:0]          web,
    input      [ADDR_WIDTH-1:0] addrb,
    input      [31:0]         dinb,
    output     [31:0]         doutb
);

    reg [31:0] mem[0:DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign douta = (addra < DEPTH) ? mem[addra] : 32'b0;
    assign doutb = (addrb < DEPTH) ? mem[addrb] : 32'b0;

    always @(posedge clka) begin
        if (addra < DEPTH) begin
            if (wea[0])
                mem[addra][7:0] <= dina[7:0];
            if (wea[1])
                mem[addra][15:8] <= dina[15:8];
            if (wea[2])
                mem[addra][23:16] <= dina[23:16];
            if (wea[3])
                mem[addra][31:24] <= dina[31:24];
        end
    end

    always @(posedge clkb) begin
        if (addrb < DEPTH) begin
            if (web[0])
                mem[addrb][7:0] <= dinb[7:0];
            if (web[1])
                mem[addrb][15:8] <= dinb[15:8];
            if (web[2])
                mem[addrb][23:16] <= dinb[23:16];
            if (web[3])
                mem[addrb][31:24] <= dinb[31:24];
        end
    end

endmodule
