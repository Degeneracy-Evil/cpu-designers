`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/18 16:31:49
// Design Name: 
// Module Name: soc_core
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
`include "riscv.h"

module soc_core(
    input  wire clk,
    input  wire rstn,
    input  wire rx,
    input  wire spi_miso,
    input  wire [`GPIO_NUM-1:0] io_pin_i,
    input  wire init_enable,
    output wire tx,
    output wire spi_mosi,
    output wire spi_ss,
    output wire spi_clk   
    );

	 wire [31:0] gpio_ctrl_o;
	 wire [31:0] gpio_data_o;
	 wire [`GPIO_NUM-1:0] io_pin;
     wire m0_req_;
     wire [31:0] m0_addr;
     wire m0_as_;
     wire m0_rw;
     wire [31:0] m0_wr_data;
     wire m1_req_;
     wire [31:0] m1_addr;
     wire m1_as_;
     wire m1_rw;
     wire [31:0] m1_wr_data;
     wire [31:0] m_rd_data;
     wire m0_grnt_;
     wire m1_grnt_;
     wire m_rdy_;    
     wire  i_intFlag_1;
     wire dbus_we;
     wire [31:0] d_address;
     wire [31:0] d_data;
     wire ibus_we;
     wire [31:0] fromDataInit_address;
     wire [31:0] fromCpuCore_address;
     wire [31:0] i_data; 
     wire [31:0] iToIf_data;
     wire [3:0] cpuToDcache_wen;
     wire [31:0] cpuToDcache_addr;
     wire [31:0] cpuToDcache_data;
     wire [31:0] dcacheTocpu_data;
     wire [3:0] wen_dcache;
     wire [3:0] wen_icache;
     wire [31:0] address;
     wire[31:0] i_address;
     wire[31:0] fromDataInit_data;
     wire tx_1;
     wire tx_2;
     wire rx_1;
     wire rx_2;
     
     assign i_address = (ibus_we == 1'b1 ? fromDataInit_address : fromCpuCore_address);
     assign address = (dbus_we==1'b1 ? d_address : cpuToDcache_addr);
     assign wen_dcache = (dbus_we==1'b1 ? 4'b0000 : cpuToDcache_wen);
     assign d_data = (dbus_we == 1'b1 ? fromDataInit_data : cpuToDcache_data);
     assign tx = (init_enable==1'b1 ? tx_1 :tx_2);
     assign rx_1 = (init_enable==1'b1 ? rx : 1'b0);
     assign rx_2 = (init_enable==1'b0 ? rx : 1'b0);
     
     reg [31:0] r_pc;
     wire [31:0] w_pc;
     
     always @(posedge clk)begin
        r_pc = w_pc;
     end
     
     assign iToIf_data = r_pc;    
        
 cpuCore cpu_top(
     .clk(clk),
     .rstn(rstn),
     .init_enable(init_enable),
     .i_intFlag_1(i_intFlag_1),
     
    //bus to ifStage
     .bus_rd_data(m_rd_data),
     .bus_rdy_(m_rdy_),
     .m0_grnt_(m0_grnt_),
     .m1_grnt_(m1_grnt_),
     
    //icache         
    .o_instAddr_32(fromCpuCore_address),
    .i_instData_32(iToIf_data),
    
    //dcache
    .o_dataWen_4(cpuToDcache_wen),
    .o_dataAddr_32(cpuToDcache_addr),
    .o_writeData_32(cpuToDcache_data),
    .i_readData_32(dcacheTocpu_data),
    
    //ifStage to bus
    .m0_req_(m0_req_),
    .m0_addr(m0_addr),
    .m0_as_(m0_as_),
    .m0_rw(m0_rw),
    .m0_wr_data(m0_wr_data),
    .m1_req_(m1_req_),
    .m1_addr(m1_addr),
    .m1_as_(m1_as_),
    .m1_rw(m1_rw),
    .m1_wr_data(m1_wr_data)
 );
 dist_mem_gen_0 Icache(
    .clk(clk),
    .a(i_address[14:2]),
    .we(ibus_we),
    .d(i_data),
    .spo(w_pc)
 );
 dCache Dcache(
    .clk(clk),
    .address(address[14:2]),
    .wen(wen_dcache),
    .w_data(d_data),
    .r_data(dcacheTocpu_data)
);
 data_init init_cache(
    .clk(clk),
    .rst_n(rstn),                      //��������������������
    .uart_rx(rx_1),                    //��������������������������������������1bit
    .enable(init_enable),                     //������������������������������
    .uart_tx(tx_1),                    //����CRC����������ACK/NAK��������uart_rx��������������1bit����
    
    .ibus_we(ibus_we),                    //Icache������������������������Icache������
    .ibus_addr_o(fromDataInit_address),                //Icache����������
    .ibus_data_o(i_data),                //������Icache����������data����������������������32bit
    .dbus_we(dbus_we),                    //Dcache������������������������Dcache������
    .dbus_addr_o(d_address),                //Dcache����������
    .dbus_data_o(fromDataInit_data)                 //������Dcache����������data����������������������32bit 
 );
 bus_top bus(
    .clk(clk),
    .reset(rstn),
    .m0_req_(m0_req_),
    .m0_addr(m0_addr),
    .m0_as_(m0_as_),
    .m0_rw(m0_rw),
    .m0_wr_data(m0_wr_data),
    .m1_req_(m1_req_),
    .m1_addr(m1_addr),
    .m1_as_(m1_as_),
    .m1_rw(m1_rw),
    .m1_wr_data(m1_wr_data),
    .rx(rx_2),
    .spi_miso(spi_miso),
    .io_pin_i(io_pin),
    .m0_grnt_(m0_grnt_),
    .m1_grnt_(m1_grnt_),
    .m_rd_data(m_rd_data),
    .m_rdy_(m_rdy_),
    .tx(tx_2),
    .spi_mosi(spi_mosi),
    .spi_ss(spi_ss),
    .spi_clk(spi_clk),
    .gpio_ctrl_o(gpio_ctrl_o),
    .gpio_data_o(gpio_data_o),
    .irq(i_intFlag_1)
 );
endmodule

