// DEPRECATED: Not used in current 2-slave AHB bus (ahb_periph_bus with SLAVE_NUM=2).
// The 2-slave decoder covers the full 32-bit address space; no default slave needed.
`include "ahb_def.vh"
`timescale 1ns / 1ps

module ahb_default_slave #(
    parameter DATA_WIDTH = `AHB_DATA_WIDTH
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    HSEL,
    input  wire  [1:0]             HTRANS,
    input  wire                    HREADY,

    output reg                     HREADYOUT,
    output reg                     HRESP,
    output reg  [DATA_WIDTH-1:0]   HRDATA
);

    reg error_state;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADYOUT   <= 1'b1;
            HRESP       <= 1'b0;
            HRDATA      <= {DATA_WIDTH{1'b0}};
            error_state <= 1'b0;
        end else begin
            if (error_state) begin
                HREADYOUT   <= 1'b1;
                HRESP       <= 1'b1;
                error_state <= 1'b0;
            end else if (HSEL && HREADY && (HTRANS[1])) begin
                HREADYOUT   <= 1'b0;
                HRESP       <= 1'b1;
                HRDATA      <= {DATA_WIDTH{1'b0}};
                error_state <= 1'b1;
            end else begin
                HREADYOUT <= 1'b1;
                HRESP     <= 1'b0;
            end
        end
    end

endmodule
