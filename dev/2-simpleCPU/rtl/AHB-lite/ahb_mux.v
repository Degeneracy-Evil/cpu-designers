`include "ahb_def.vh"
`timescale 1ns / 1ps

module ahb_mux #(
    parameter DATA_WIDTH = `AHB_DATA_WIDTH,
    parameter SLAVE_NUM  = 4
)(
    input  wire  [SLAVE_NUM-1:0]          HSELx,
    input  wire  [DATA_WIDTH-1:0]         slave_HRDATA   [0:SLAVE_NUM-1],
    input  wire  [SLAVE_NUM-1:0]          slave_HREADYOUT,
    input  wire  [SLAVE_NUM-1:0]          slave_HRESP,

    output reg   [DATA_WIDTH-1:0]         HRDATA,
    output reg                          HREADY,
    output reg                          HRESP
);

    integer i;
    always @(*) begin
        HRDATA  = {DATA_WIDTH{1'b0}};
        HREADY  = 1'b1;
        HRESP   = 1'b0;
        for (i = 0; i < SLAVE_NUM; i = i + 1) begin
            if (HSELx[i]) begin
                HRDATA  = slave_HRDATA[i];
                HREADY  = slave_HREADYOUT[i];
                HRESP   = slave_HRESP[i];
            end
        end
    end

endmodule
