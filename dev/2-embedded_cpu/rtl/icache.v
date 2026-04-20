`timescale 1ns / 1ps

// Behavioral placeholder model for iCache BRAM IP.
// Replace with generated FPGA IP in hardware project.
module icache(
    input         clka,
    input         ena,
    input  [0:0]  wea,
    input  [10:0] addra,
    input  [31:0] dina,
    output [31:0] douta,
    input         clkb,
    input         enb,
    input  [0:0]  web,
    input  [10:0] addrb,
    input  [31:0] dinb,
    output [31:0] doutb
);

    reg [31:0] mem[0:2047];
    integer i;

    initial begin
        for (i = 0; i < 2048; i = i + 1)
            mem[i] = 32'b0;
    end

    assign douta = ena ? mem[addra] : 32'b0;
    assign doutb = enb ? mem[addrb] : 32'b0;

    always @(posedge clka) begin
        if (ena && wea[0])
            mem[addra] <= dina;
    end

    always @(posedge clkb) begin
        if (enb && web[0])
            mem[addrb] <= dinb;
    end

endmodule
