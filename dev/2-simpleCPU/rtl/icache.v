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
    reg [31:0] douta_reg;
    reg [31:0] doutb_reg;

    initial begin
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", mem);
    end

    always @(posedge clka) begin
        if (ena) begin
            douta_reg <= mem[addra];
            if (wea[0])
                mem[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            doutb_reg <= mem[addrb];
            if (web[0])
                mem[addrb] <= dinb;
        end
    end

    assign douta = douta_reg;
    assign doutb = doutb_reg;

endmodule
