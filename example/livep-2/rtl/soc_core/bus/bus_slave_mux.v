`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 09:46:12
// Design Name: 
// Module Name: bus_slave_mux
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

module bus_slave_mux(
    input wire s1_cs_,
    input wire[31:0] s1_rd_data,
    input wire s1_rdy_,
    input wire s2_cs_,
    input wire[31:0] s2_rd_data,
    input wire s2_rdy_,
    input wire s3_cs_,
    input wire[31:0] s3_rd_data,
    input wire s3_rdy_,
    input wire s4_cs_,
    input wire[31:0] s4_rd_data,
    input wire s4_rdy_,
    output reg[31:0] m_rd_data,
    output reg m_rdy_
    );
    always@(*)begin
    /*选择片选信号对应的从属*/
        if(s1_cs_ ==`ENABLE_)begin//1号总线从属(uart)
            m_rd_data = s1_rd_data;
            m_rdy_ = s1_rdy_;
        end else if(s2_cs_ ==`ENABLE_)begin//2号总线从属(timer)
            m_rd_data = s2_rd_data;
            m_rdy_ = s2_rdy_;
        end else if(s3_cs_ ==`ENABLE_)begin//3号总线从属(spi)
            m_rd_data = s3_rd_data;
            m_rdy_ = s3_rdy_;
        end else if(s4_cs_ ==`ENABLE_)begin//4号总线从属(gpio)
            m_rd_data = s4_rd_data;
            m_rdy_ = s4_rdy_;
        end else begin//默认值
            m_rd_data = `WORD_DATA_W'h0;
            m_rdy_ = `DISABLE_;
        end
    end
endmodule
