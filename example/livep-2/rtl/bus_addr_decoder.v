`timescale 1ns / 1ps
`include "./bus_define.vh"

module bus_addr_decoder(
    input wire [31:0] i_addr_32,
//    output reg s0_cs_,
    output reg o_cs1_1,
    output reg o_cs2_1,
    output reg o_cs3_1,
    output reg o_cs4_1
    //output reg s5_cs_,
    //output reg s6_cs_,
    //output reg s7_cs_
    );
    wire [2:0] s_index;
     assign s_index=((i_addr_32[31:0]>32'h00080000&&i_addr_32[31:0]<32'h0008ffff) ? `BUS_SLAVE_4 : ((i_addr_32[31:0]>32'h00040000&&i_addr_32[31:0]<32'h0004ffff) ? `BUS_SLAVE_3 : ((i_addr_32[31:0]>32'h00020000&&i_addr_32[31:0]<32'h0002ffff)? `BUS_SLAVE_2 :((i_addr_32[31:0]>32'h00010000&&i_addr_32[31:0]<32'h0001ffff) ? `BUS_SLAVE_1 : 1'b0))));//生成总线丛属索引
     always@(*)begin
     /*初始化片选信号*/
//        s0_cs_ = `DISABLE_;
        o_cs1_1 = `DISABLE_;	//uart
        o_cs2_1 = `DISABLE_;	//gpio
        o_cs3_1 = `DISABLE_;	//timer
        o_cs4_1 = `DISABLE_;	//spi
        //s5_cs_ = `DISABLE_;
        //s6_cs_ = `DISABLE_;
        //s7_cs_ = `DISABLE_;
        case(s_index)
        /*选择地址对应的从属*/  
//            `BUS_SLAVE_0://0号总线从属
//            begin
//                s0_cs_ =`ENABLE_;//0号总线从属选通信号
//            end
            `BUS_SLAVE_1://1号总线丛属
            begin 
                o_cs1_1 =`ENABLE_;//1号总从属选通信号
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
            //`BUS_SLAVE_5:
            //begin
            //    s5_cs_ =`ENABLE_;
            //end
            //`BUS_SLAVE_6:
            //begin
            //    s6_cs_ =`ENABLE_;
            //end
            //`BUS_SLAVE_7:
            //begin
            //    s7_cs_ =`ENABLE_;
            //end
           endcase
        end
endmodule
