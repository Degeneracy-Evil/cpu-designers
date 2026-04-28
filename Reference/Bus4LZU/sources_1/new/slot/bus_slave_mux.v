`timescale 1ns / 1ps
`include "./bus_define.vh"

module bus_slave_mux(
//    input wire s0_cs_,
//    input wire[31:0] s0_rd_data,
//    input wire s0_rdy_,
    input wire i_cs1_1,
    input wire[31:0] i_rdData1_32,
    input wire i_rdy1_1,
    input wire i_cs2_1,
    input wire[31:0] i_rdData2_32,
    input wire i_rdy2_1,
    input wire i_cs3_1,
    input wire[31:0] i_rdData3_32,
    input wire i_rdy3_1,
    input wire i_cs4_1,
    input wire[31:0] i_rdData4_32,
    input wire i_rdy4_1,
    //input wire s5_cs_,
    //input wire[31:0] s5_rd_data,
    //input wire s5_rdy_,
    //input wire s6_cs_,
    //input wire[31:0] s6_rd_data,
    //input wire s6_rdy_,
    //input wire s7_cs_,
    //input wire[31:0] s7_rd_data,
    //input wire s7_rdy_,
    output reg[31:0] o_rdData_32,
    output reg o_rdy_1
    );
    always@(*)begin
    /*选择片选信号对应的从属*/
        if(i_cs1_1 ==`ENABLE_)begin//1号总线从属(uart)
            o_rdData_32 = i_rdData1_32;
            o_rdy_1 = i_rdy1_1;
        end else if(i_cs2_1 ==`ENABLE_)begin//2号总线从属(gpio)
            o_rdData_32 = i_rdData2_32;
            o_rdy_1 = i_rdy2_1;
        end else if(i_cs3_1 ==`ENABLE_)begin//3号总线从属(timer)
            o_rdData_32 = i_rdData3_32;
            o_rdy_1 = i_rdy3_1;
        end else if(i_cs4_1 ==`ENABLE_)begin//4号总线从属(spi)
            o_rdData_32 = i_rdData4_32;
            o_rdy_1 = i_rdy4_1;
        //end else if(s4_cs_ ==`ENABLE_)begin
        //    m_rd_data = s4_rd_data;
        //    m_rdy_ = s4_rdy_;
        //end else if(s5_cs_ ==`ENABLE_)begin
        //    m_rd_data = s5_rd_data;
        //    m_rdy_ = s5_rdy_;
        //end else if(s6_cs_ ==`ENABLE_)begin
        //    m_rd_data = s6_rd_data;
        //    m_rdy_ = s6_rdy_;
        //end else if(s7_cs_ ==`ENABLE_)begin
        //    m_rd_data = s7_rd_data;
        //    m_rdy_ = s7_rdy_;
        end else begin//默认值
            o_rdData_32 = `WORD_DATA_W'h0;
            o_rdy_1 = `DISABLE_;
        end
    end
endmodule
