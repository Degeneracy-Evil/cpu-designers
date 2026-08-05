// Dual-port RAM (read port registered)
// Adapted from chiplab IP/APB_DEV/URT/raminfr.v

`timescale 1ns / 1ps

module raminfr #(
    parameter ADDR_W = 4,
    parameter DATA_W = 8,
    parameter DEPTH   = 16
)(
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_W-1:0]    a,       // Write address
    input  wire [ADDR_W-1:0]    dpra,    // Read address
    input  wire [DATA_W-1:0]    di,      // Write data
    output reg  [DATA_W-1:0]    dpo      // Read data (registered)
);

    reg [DATA_W-1:0] ram [DEPTH-1:0];

    always @(posedge clk) begin
        if (we)
            ram[a] <= di;
    end

    always @(posedge clk) begin
        dpo <= ram[dpra];
    end

endmodule
