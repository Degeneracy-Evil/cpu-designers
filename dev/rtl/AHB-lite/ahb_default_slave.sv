`include "ahb_def.svh"
`timescale 1ns / 1ps

module ahb_default_slave(
    input  wire        HCLK,
    input  wire        HRESETn,

    input  wire        HSEL,
    input  wire [1:0]  HTRANS,
    input  wire        HREADY,

    output reg         HREADYOUT,
    output reg         HRESP
);

    wire ahb_transfer = HSEL & HREADY & HTRANS[1];

    reg error_phase;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADYOUT  <= 1'b1;
            HRESP      <= 1'b0;
            error_phase <= 1'b0;
        end else begin
            if (error_phase) begin
                HREADYOUT  <= 1'b1;
                HRESP      <= 1'b1;
                error_phase <= 1'b0;
            end else if (ahb_transfer) begin
                HRESP      <= 1'b1;
                HREADYOUT  <= 1'b0;
                error_phase <= 1'b1;
            end else begin
                HREADYOUT  <= 1'b1;
                HRESP      <= 1'b0;
            end
        end
    end

endmodule
