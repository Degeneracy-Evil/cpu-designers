`include "ahb_def.vh"

module ahb_decoder #(
    parameter ADDR_WIDTH = `AHB_ADDR_WIDTH,
    parameter SLAVE_NUM  = 4
)(
    input  wire  [ADDR_WIDTH-1:0] HADDR,
    input  wire                   HREADY,
    output wire  [SLAVE_NUM-1:0]  HSELx
);

    generate
        if (SLAVE_NUM == 1) begin : gen_single_slave
            assign HSELx[0] = 1'b1;
        end else if (SLAVE_NUM == 2) begin : gen_two_slave
            assign HSELx[0] = (HADDR[ADDR_WIDTH-1:20] == {ADDR_WIDTH-20{1'b0}});
            assign HSELx[1] = (HADDR[ADDR_WIDTH-1:20] != {ADDR_WIDTH-20{1'b0}});
        end else if (SLAVE_NUM == 4) begin : gen_four_slave
            assign HSELx[0] = (HADDR[31:20] == 12'h000);
            assign HSELx[1] = (HADDR[31:20] == 12'h001);
            assign HSELx[2] = (HADDR[31:20] == 12'h100);
            assign HSELx[3] = ~((HADDR[31:20] == 12'h000) ||
                                (HADDR[31:20] == 12'h001) ||
                                (HADDR[31:20] == 12'h100));
        end else if (SLAVE_NUM == 8) begin : gen_eight_slave
            assign HSELx[0] = (HADDR[31:20] == 12'h000);
            assign HSELx[1] = (HADDR[31:20] == 12'h001);
            assign HSELx[2] = (HADDR[31:20] == 12'h002);
            assign HSELx[3] = (HADDR[31:20] == 12'h003);
            assign HSELx[4] = (HADDR[31:20] == 12'h100);
            assign HSELx[5] = (HADDR[31:20] == 12'h101);
            assign HSELx[6] = (HADDR[31:20] == 12'h102);
            assign HSELx[7] = ~((HADDR[31:20] == 12'h000) ||
                                (HADDR[31:20] == 12'h001) ||
                                (HADDR[31:20] == 12'h002) ||
                                (HADDR[31:20] == 12'h003) ||
                                (HADDR[31:20] == 12'h100) ||
                                (HADDR[31:20] == 12'h101) ||
                                (HADDR[31:20] == 12'h102));
        end
    endgenerate

endmodule
