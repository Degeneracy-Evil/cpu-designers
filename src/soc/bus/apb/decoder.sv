`include "soc/bus/apb/defs.svh"
`timescale 1ns / 1ps

module apb_decoder #(
    parameter ADDR_WIDTH  = `APB_ADDR_WIDTH,
    parameter SLAVE_NUM   = 4
)(
    input  wire  [ADDR_WIDTH-1:0] PADDR,
    output wire  [SLAVE_NUM-1:0]  PSELx
);

    generate
        if (SLAVE_NUM == 1) begin : gen_single_slave
            assign PSELx[0] = 1'b1;
        end else if (SLAVE_NUM == 2) begin : gen_two_slave
            assign PSELx[0] = ~PADDR[ADDR_WIDTH-1];
            assign PSELx[1] =  PADDR[ADDR_WIDTH-1];
        end else if (SLAVE_NUM == 4) begin : gen_four_slave
            assign PSELx[0] = (PADDR[15:14] == 2'b00);
            assign PSELx[1] = (PADDR[15:14] == 2'b01);
            assign PSELx[2] = (PADDR[15:14] == 2'b10);
            assign PSELx[3] = (PADDR[15:14] == 2'b11);
        end else if (SLAVE_NUM == 8) begin : gen_eight_slave
            assign PSELx[0] = (PADDR[15:13] == 3'b000);
            assign PSELx[1] = (PADDR[15:13] == 3'b001);
            assign PSELx[2] = (PADDR[15:13] == 3'b010);
            assign PSELx[3] = (PADDR[15:13] == 3'b011);
            assign PSELx[4] = (PADDR[15:13] == 3'b100);
            assign PSELx[5] = (PADDR[15:13] == 3'b101);
            assign PSELx[6] = (PADDR[15:13] == 3'b110);
            assign PSELx[7] = (PADDR[15:13] == 3'b111);
        end
    endgenerate

endmodule
