`timescale 1ns / 1ps
`include "ahb_def.svh"

module dcache_ctrl #(
    parameter DEPTH = 4096
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    input  wire [31:0] cpu_req_wdata,
    input  wire        cpu_req_hwrite,
    input  wire [2:0]  cpu_req_hsize,
    output wire [31:0] cpu_req_rdata,
    output wire        cpu_req_ready,

    output wire        mmio_req,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire        mmio_hwrite,
    output wire [2:0]  mmio_hsize,
    input  wire [31:0] mmio_rdata,
    input  wire        mmio_valid
);

    wire is_mmio = ~cpu_req_addr[31];

    wire [31:0] dcache_dout;
    reg dcache_valid_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dcache_valid_r <= 1'b0;
        end else begin
            dcache_valid_r <= cpu_req_valid && !is_mmio;
        end
    end

    wire [3:0] bram_wea;
    assign bram_wea = (!cpu_req_hwrite) ? 4'b0000 :
                      (cpu_req_hsize == `AHB_SIZE_BYTE) ?
                          (cpu_req_addr[1:0] == 2'b00) ? 4'b0001 :
                          (cpu_req_addr[1:0] == 2'b01) ? 4'b0010 :
                          (cpu_req_addr[1:0] == 2'b10) ? 4'b0100 :
                                                          4'b1000 :
                      (cpu_req_hsize == `AHB_SIZE_HWORD) ?
                          (cpu_req_addr[1]) ? 4'b1100 : 4'b0011 :
                      4'b1111;

    dcache u_dcache (
        .clka(clk),
        .ena(cpu_req_valid && !is_mmio),
        .wea(bram_wea),
        .addra(cpu_req_addr[13:2]),
        .dina(cpu_req_wdata),
        .douta(dcache_dout),

        .clkb(1'b0),
        .enb(1'b0),
        .web(4'b0),
        .addrb(12'b0),
        .dinb(32'b0),
        .doutb()
    );

    assign cpu_req_rdata = is_mmio ? mmio_rdata : dcache_dout;
    assign cpu_req_ready = is_mmio ? mmio_valid : dcache_valid_r;

    assign mmio_req   = is_mmio ? cpu_req_valid : 1'b0;
    assign mmio_addr  = cpu_req_addr;
    assign mmio_wdata = cpu_req_wdata;
    assign mmio_hwrite = is_mmio ? cpu_req_hwrite : 1'b0;
    assign mmio_hsize  = is_mmio ? cpu_req_hsize : `AHB_SIZE_WORD;

endmodule
