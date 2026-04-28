`timescale 1ns / 1ps
`include "bus_define.vh"

module bus_addr_decoder(
    input wire [31:0] i_addr_32,
    output reg o_cs1_1,
    output reg o_cs2_1,
    output reg o_cs3_1,
    output reg o_cs4_1
    );
    wire [2:0] s_index;
    assign s_index=((i_addr_32[31:0]>=32'h00080000&&i_addr_32[31:0]<=32'h0008ffff) ? `BUS_SLAVE_4 : ((i_addr_32[31:16]==16'h1001) ? `BUS_SLAVE_3 : ((i_addr_32[31:0]>=32'h00040000&&i_addr_32[31:0]<=32'h0004ffff) ? `BUS_SLAVE_3 : ((i_addr_32[31:0]>=32'h00020000&&i_addr_32[31:0]<=32'h0002ffff)? `BUS_SLAVE_2 :((i_addr_32[31:0]>=32'h00010000&&i_addr_32[31:0]<=32'h0001ffff) ? `BUS_SLAVE_1 : 1'b0)))));
     always@(*)begin
        o_cs1_1 = `DISABLE_;
        o_cs2_1 = `DISABLE_;
        o_cs3_1 = `DISABLE_;
        o_cs4_1 = `DISABLE_;
        case(s_index)
            `BUS_SLAVE_1:
            begin
                o_cs1_1 =`ENABLE_;
            end
            `BUS_SLAVE_2:
            begin
                o_cs2_1 =`ENABLE_;
            end
            `BUS_SLAVE_3:
            begin
                o_cs3_1 =`ENABLE_;
            end
            `BUS_SLAVE_4:
            begin
                o_cs4_1 =`ENABLE_;
            end
           endcase
        end
endmodule
