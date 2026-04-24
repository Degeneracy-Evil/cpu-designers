`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 09:45:24
// Design Name: 
// Module Name: bus_addr_decoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "./bus_define.vh"

module bus_addr_decoder(
    input wire [31:0] s_addr,
    output reg s1_cs_,
    output reg s2_cs_,
    output reg s3_cs_,
    output reg s4_cs_
    );
    wire [2:0] s_index;
     assign s_index=(s_addr[31:0]>32'h1eff ? `BUS_SLAVE_4 : (s_addr[31:0]>32'h1dff ? `BUS_SLAVE_3 : (s_addr[31:0]>32'h1cff ? `BUS_SLAVE_2 :(s_addr[31:0]>32'h1bff ? `BUS_SLAVE_1 : 1'b0))));//生成总线丛属索引
     always@(*)begin
     /*初始化片选信号*/
        s1_cs_ = `DISABLE_;
        s2_cs_ = `DISABLE_;
        s3_cs_ = `DISABLE_;
        s4_cs_ = `DISABLE_;
        case(s_index)
        /*选择地址对应的从属*/  
            `BUS_SLAVE_1://1号总线丛属
            begin 
                s1_cs_ =`ENABLE_;//1号总从属选通信号
            end
            `BUS_SLAVE_2:
            begin
                s2_cs_ =`ENABLE_;
            end
            `BUS_SLAVE_3:
            begin
                s3_cs_ =`ENABLE_;
            end
            `BUS_SLAVE_4:
            begin
                s4_cs_ =`ENABLE_;
            end
           endcase
        end
endmodule
