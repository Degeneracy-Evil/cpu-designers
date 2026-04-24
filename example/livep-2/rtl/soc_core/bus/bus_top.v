`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 09:40:24
// Design Name: 
// Module Name: bus_top
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

/*总线顶层模块*/
module bus_top(
       input wire clk,
       input wire reset,
       input wire m0_req_,
       input wire[31:0] m0_addr,
       input wire m0_as_,
       input wire m0_rw,
       input wire[31:0] m0_wr_data,
       input wire m1_req_,
       input wire[31:0] m1_addr,
       input wire m1_as_,
       input wire m1_rw,
       input wire[31:0] m1_wr_data,
       input wire rx,
       input wire spi_miso,
       input wire [`GPIO_NUM-1:0] io_pin_i,
       output wire m0_grnt_,
       output wire m1_grnt_,
       output wire[31:0] m_rd_data,
       output wire m_rdy_,
       output wire tx,
       output wire spi_ss,
       output wire spi_mosi,
       output wire spi_clk,
       output wire [31:0] gpio_ctrl_o,
       output wire [31:0] gpio_data_o,
       
       output wire irq
    );
         wire[31:0] s_addr;
         wire s_as_;
         wire s_rw;
         wire[31:0] s_wr_data;
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
/*总线仲裁器*/
bus_arbiter arbiter(
.clk(clk),
.reset(reset),
.m0_req_(m0_req_),
.m1_req_(m1_req_),
.m0_grnt_(m0_grnt_),
.m1_grnt_(m1_grnt_)
    );
/*总线主控多路复用器*/
bus_master_mux master_mux(
.m0_grnt_(m0_grnt_),
.m1_grnt_(m1_grnt_),
.m0_addr(m0_addr),
.m1_addr(m1_addr),
.m0_as_(m0_as_),
.m1_as_(m1_as_),
.m0_rw(m0_rw),
.m1_rw(m1_rw),
.m0_wr_data(m0_wr_data),
.m1_wr_data(m1_wr_data),
.s_addr(s_addr),
.s_as_(s_as_),
.s_rw(s_rw),
.s_wr_data(s_wr_data)
);
/*地址解码器*/
bus_addr_decoder addr_dec(
   .s_addr(s_addr),
   .s1_cs_(s1_cs_),
   .s2_cs_(s2_cs_),
   .s3_cs_(s3_cs_),
   .s4_cs_(s4_cs_)
    );
/*总线从属多路复用器*/
bus_slave_mux slave_mux(
   .s1_cs_(s1_cs_),
   .s2_cs_(s2_cs_),
   .s3_cs_(s3_cs_),
   .s4_cs_(s4_cs_),
   .s1_rd_data(s1_rd_data),
   .s2_rd_data(s2_rd_data),
   .s3_rd_data(s3_rd_data),
   .s4_rd_data(s4_rd_data),
   .s1_rdy_(s1_rdy_),
   .s2_rdy_(s2_rdy_),
   .s3_rdy_(s3_rdy_),
   .s4_rdy_(s4_rdy_),
   .m_rd_data(m_rd_data),
   .m_rdy_(m_rdy_)
    );
uart_top uart(
   .cs_(s2_cs_),         
   .as_(s_as_),         
   .rw(s_rw),          
   .addr(s_addr),
   .wr_data(s_wr_data),
   .clk(clk),
   .reset(reset),
   .rx(rx),
  .rd_data(s2_rd_data),
  .rdy_(s2_rdy_),
  .tx(tx)
);
timer timer(
    .clk(clk),
    .reset(reset),
    .cs_(s1_cs_),
    .as_(s_as_),
    .rw(s_rw),
    .addr(s_addr),
	.wr_data(s_wr_data),
    .rd_data(s1_rd_data),
	.rdy_(s1_rdy_),
	.irq(irq)
);
spi spi(
     .clk(clk),
     .reset(reset),  
    .cs_(s3_cs_),
    .as_(s_as_),
    .rw(s_rw), 
    .rdy_(s3_rdy_),
     .data_i(s_wr_data),
     .addr_i(s_addr),
     .data_o(s3_rd_data),
     .spi_mosi(spi_mosi),             // spi控制器输出、spi设备输入信号
     .spi_miso(spi_miso),             // spi控制器输入、spi设备输出信号
     .spi_ss(spi_ss),              // spi设备片选
     .spi_clk(spi_clk)

);
gpio gpio(
    .clk(clk),
    .reset(reset),
     .cs_(s4_cs_),
     .as_(s_as_),
     .rw(s_rw),
      .rdy_(s4_rdy_),   
      .addr_i(s_addr),
      .data_i(s_wr_data),
      .data_o(s4_rd_data),
      .gpio_ctrl_o(gpio_ctrl_o),
      .gpio_data_o(gpio_data_o),
      .io_pin_i(io_pin_i)
);
endmodule
