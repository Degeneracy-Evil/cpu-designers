`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 09:44:48
// Design Name: 
// Module Name: bus_master_mux
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

module bus_master_mux(
    input wire[31:0] m0_addr,
    input wire m0_as_,
    input wire m0_rw,
    input wire[31:0] m0_wr_data,
    input wire m0_grnt_,
    input wire[31:0] m1_addr,
    input wire m1_as_,
    input wire m1_rw,
    input wire[31:0] m1_wr_data,
    input wire m1_grnt_,
    output reg [31:0] s_addr,
    output reg s_as_,
    output reg s_rw,
    output reg[31:0] s_wr_data
    );
    always@(*)begin
    /*选择持有总线使用权的主控*/
        if(m0_grnt_==`ENABLE_)begin//0号总线主控
        /*从0号总线主控传过来的信号*/
            s_addr = m0_addr;
            s_as_ = m0_as_;
            s_rw = m0_rw;
            s_wr_data = m0_wr_data;
        end else if(m1_grnt_ == `ENABLE_)begin//1号总线主控
        /*从1号总线主控传过来的信号*/
            s_addr = m1_addr;
            s_as_ = m1_as_;
            s_rw = m1_rw;
            s_wr_data = m1_wr_data;
        end else begin//默认值
           s_addr = `WORD_ADDR_W'h0;
            s_as_ = `DISABLE_;
            s_rw = `READ;
            s_wr_data = `WORD_DATA_W'h0; 
        end
    end
endmodule
