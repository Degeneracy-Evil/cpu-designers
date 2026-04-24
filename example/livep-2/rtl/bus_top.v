`timescale 1ns / 1ps

/*总线顶层模块*/
module bus_top(
       input wire clk,
       input wire rst,
/*     input wire m0_req_,
       input wire[31:0] m0_addr,
       input wire m0_as_,
       input wire m0_rw,
       input wire[31:0] m0_wr_data,
       input wire m1_req_,*/
       input wire[31:0] i_addr_32,
       input wire i_as_1,
       input wire i_rw_1,
       input wire[31:0] i_wrData_32,
//       input wire m2_req_,
//       input wire[29:0] m2_addr,
//       input wire m2_as_,
//       input wire m2_rw,
//       input wire[31:0] m2_wr_data,
      // input wire m3_req_,
      // input wire[29:0] m3_addr,
      // input wire m3_as_,
      // input wire m3_rw,
      // input wire[31:0] m3_wr_data,
      //input wire[31:0] s0_rd_data,
      //input wire s0_rdy_,
      //input wire[31:0] s1_rd_data,
      //input wire s1_rdy_,
      //input wire[31:0] s2_rd_data,
      // input wire s2_rdy_,
      // input wire[31:0] s3_rd_data,
      // input wire s3_rdy_,
      // input wire[31:0] s4_rd_data,
      // input wire s4_rdy_,
      // input wire[31:0] s5_rd_data,
      // input wire s5_rdy_,
      // input wire[31:0] s6_rd_data,
      // input wire s6_rdy_,
      // input wire[31:0] s7_rd_data,
      // input wire s7_rdy_,
       input wire i_rx_1,
       input wire i_spiMiso_1,
       input wire [`GPIO_NUM-1:0] i_ioPin_16,
//       output wire m0_grnt_,
//       output wire m1_grnt_,
//       output wire m2_grnt_,
      // output wire m3_grnt_,
      // output wire s2_cs_,
      // output wire s3_cs_,
      // output wire s4_cs_,
      // output wire s5_cs_,
      // output wire s6_cs_,
      // output wire s7_cs_,
       output wire[31:0] o_rdData_32,
       output wire o_rdy_1,
       //output wire[29:0] i_addr_32,
       //output wire s_as_,
       //output wire s_rw,
       //output wire[31:0] s_wr_data,
//       output wire o_irq_1_o_tx_1,
//       output wire o_irq_1_rx,
       output wire o_tx_1,
       output wire o_spiSs_1,
       output wire o_spiMosi_1,
       output wire o_spiClk_1,
       output wire [31:0] o_gpioCtrl_32,
       output wire [31:0] o_gpioData_32,
       
       output wire o_irq_1
    );
 /*        wire[31:0] i_addr_32;
         wire s_as_;
         wire s_rw;
         wire[31:0] s_wr_data;*/
         wire[31:0] s1_rd_data;
         wire s1_rdy_;
         wire[31:0] s2_rd_data;
         wire s2_rdy_;
         wire[31:0] s3_rd_data;
         wire s3_rdy_;
         wire[31:0] s4_rd_data;
         wire s4_rdy_;
         wire s1_cs_;
         wire s2_cs_;
         wire s3_cs_;
         wire s4_cs_;
//       wire m0_grnt_;
//       wire m1_grnt_;
//       wire m2_grnt_;
//       wire m3_grnt_;
/*总线仲裁器*/
/*bus_arbiter arbiter(
.clk(clk),
.rst(rst),
.m0_req_(m0_req_),
.m1_req_(m1_req_),
//.m2_req_(m2_req_),
//.m3_req_(m3_req_),
.m0_grnt_(m0_grnt_),
.m1_grnt_(m1_grnt_)
//.m2_grnt_(m2_grnt_)
//.m3_grnt_(m3_grnt_)
    );
*/
/*总线主控多路复用器*/
/*
bus_master_mux master_mux(
.m0_grnt_(m0_grnt_),
.m1_grnt_(m1_grnt_),
//.m2_grnt_(m2_grnt_),
//.m3_grnt_(m3_grnt_),
.m0_addr(m0_addr),
.m1_addr(m1_addr),
//.m2_addr(m2_addr),
//.m3_addr(m3_addr),
.m0_as_(m0_as_),
.m1_as_(m1_as_),
//.m2_as_(m2_as_),
//.m3_as_(m3_as_),
.m0_rw(m0_rw),
.m1_rw(m1_rw),
//.m2_rw(m2_rw),
//.m3_rw(m3_rw),
.m0_wr_data(m0_wr_data),
.m1_wr_data(m1_wr_data),
//.m2_wr_data(m2_wr_data),
//.m3_wr_data(m3_wr_data),
.i_addr_32(i_addr_32),
.s_as_(s_as_),
.s_rw(s_rw),
.s_wr_data(s_wr_data)
);
*/
/*地址解码器*/
bus_addr_decoder addr_dec(
   .i_addr_32(i_addr_32),
//   .s0_cs_(s0_cs_),
   .o_cs1_1(s1_cs_),
   .o_cs2_1(s2_cs_),
   .o_cs3_1(s3_cs_),
   .o_cs4_1(s4_cs_)
   //.s5_cs_(s5_cs_),
   //.s6_cs_(s6_cs_),
   //.s7_cs_(s7_cs_)
    );
/*总线从属多路复用器*/
bus_slave_mux slave_mux(
//    .s0_cs_(s0_cs_),
   .i_cs1_1(s1_cs_),
   .i_cs2_1(s2_cs_),
   .i_cs3_1(s3_cs_),
   .i_cs4_1(s4_cs_),
   //.s5_cs_(s5_cs_),
   //.s6_cs_(s6_cs_),
   //.s7_cs_(s7_cs_),
//   .s0_rd_data(s0_rd_data),
   .i_rdData1_32(s1_rd_data),
   .i_rdData2_32(s2_rd_data),
   .i_rdData3_32(s3_rd_data),
   .i_rdData4_32(s4_rd_data),
   //.s5_rd_data(s5_rd_data),
   //.s6_rd_data(s6_rd_data),
   //.s7_rd_data(s7_rd_data),
//   .s0_rdy_(s0_rdy_),
   .i_rdy1_1(s1_rdy_),
   .i_rdy2_1(s2_rdy_),
   .i_rdy3_1(s3_rdy_),
   .i_rdy4_1(s4_rdy_),
   //.s5_rdy_(s5_rdy_),
   //.s6_rdy_(s6_rdy_),
   //.s7_rdy_(s7_rdy_),
   .o_rdData_32(o_rdData_32),
   .o_rdy_1(o_rdy_1)
    );
uart_top uart(
   .i_cs_1(s1_cs_),         
   .i_as_1(i_as_1),         
   .i_rw_1(i_rw_1),          
   .i_addr_32(i_addr_32),
   .i_wrData_32(i_wrData_32),
   .clk(clk),
   .rst(rst),
   .i_rx_1(i_rx_1),
  .o_rdData_32(s1_rd_data),
  .o_rdy_1(s1_rdy_),
  .o_tx_1(o_tx_1)
);
timer timer(
    .clk(clk),
    .rst(rst),
    .i_cs_1(s3_cs_),
    .i_as_1(i_as_1),
    .i_rw_1(i_rw_1),
    .i_addr_32(i_addr_32),
    .i_wrData_32(i_wrData_32),
    .o_rdData_32(s3_rd_data),
    .o_rdy_1(s3_rdy_),
    .o_irq_1(o_irq_1)
);
spi spi(
     .clk(clk),
     .rst(rst),
  
    
    .i_cs_1(s4_cs_),
    .i_as_1(i_as_1),
    .i_rw_1(i_rw_1),
  
    
    .o_rdy_1(s4_rdy_),
  
//     we_i,
     .i_data_32(i_wrData_32),
     .i_addr_32(i_addr_32),
     .o_data_32(s4_rd_data),

     .o_spiMosi_1(o_spiMosi_1),             // spi控制器输出、spi设备输入信号
     .i_spiMiso_1(i_spiMiso_1),             // spi控制器输入、spi设备输出信号
     .o_spiSs_1(o_spiSs_1),              // spi设备片选
     .o_spiClk_1(o_spiClk_1)

);
gpio gpio(
    .clk(clk),
    .rst(rst),
   
    
     .i_cs_1(s2_cs_),
     .i_as_1(i_as_1),
     .i_rw_1(i_rw_1),
   
    
      .o_rdy_1(s2_rdy_),   
    
      .i_addr_32(i_addr_32),
      .i_data_32(i_wrData_32),
      .o_data_32(s2_rd_data),

      .o_gpioCtrl_32(o_gpioCtrl_32),
      .o_gpioData_32(o_gpioData_32),
    
      .i_ioPin_16(i_ioPin_16)



);
endmodule
