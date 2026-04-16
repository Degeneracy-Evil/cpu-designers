`timescale 1ns / 1ps

// Data cache (L1 dCache) backed by BRAM.
// Exposes CPU-side req/ready/rvalid/wdone handshake and display read port.
module data_mem #(
    parameter MEM_DEPTH = 256,
    parameter ADDR_WIDTH = 8
)(
    input                     clk,
    input                     reset,
    input                     req,
    input                     write_en,
    input      [31:0]         addr,
    input      [31:0]         wdata,
    input      [3:0]          wstrb,
    output reg [31:0]         rdata,
    output                    ready,
    output reg                rvalid,
    output reg                wdone,

    // Display/debug BRAM port.
    input      [31:0]         mem_addr,
    output     [31:0]         mem_data
);

    wire [ADDR_WIDTH-1:0] addra;
    wire [ADDR_WIDTH-1:0] addrb;
    wire [3:0]            wea;
    wire [31:0]           bram_douta;

    assign addra = addr[ADDR_WIDTH+1:2];
    assign addrb = mem_addr[ADDR_WIDTH+1:2];
    assign wea = (req && write_en) ? wstrb : 4'b0000;
    assign ready = 1'b1;

    bram #(
        .DEPTH(MEM_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE("")
    ) dcache_bram (
        .clka(clk),
        .wea(wea),
        .addra(addra),
        .dina(wdata),
        .douta(bram_douta),
        .clkb(clk),
        .web(4'b0000),
        .addrb(addrb),
        .dinb(32'b0),
        .doutb(mem_data)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rdata <= 32'b0;
            rvalid <= 1'b0;
            wdone <= 1'b0;
        end else begin
            rvalid <= 1'b0;
            wdone <= 1'b0;

            if (req) begin
                if (write_en) begin
                    wdone <= 1'b1;
                end else begin
                    rdata <= bram_douta;
                    rvalid <= 1'b1;
                end
            end
        end
    end

endmodule
