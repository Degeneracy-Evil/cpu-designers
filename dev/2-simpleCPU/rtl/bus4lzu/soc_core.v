 `timescale 1ns / 1ps

module soc_top
#(
    parameter CLK_FREQ = 25,//时钟频率
    parameter GPIO_NUM = 16//gpio数量
)
(
    
    input  wire        clk         ,
    input  wire        rstn       ,
       
    input  wire        rx          ,    
    output wire        tx          ,
    
    output wire        timer_iqr       ,
    output wire        init_sig        ,
    
    input  wire        spi_miso    ,
    output wire        spi_mosi    ,
    output wire        spi_ss      ,
    output wire        spi_clk     ,
    
    inout  wire [GPIO_NUM-1:0] gpio_io     ,
    
    input  wire [31:0] instAddr_32 ,
    output wire [31:0] instData_32 ,
    
    input  wire [3:0]  dataWen_4   ,
    input  wire [31:0] dataAddr_32 ,
    input  wire [31:0] writeData_32,
    output wire [31:0] readData_32
    
    
    );

	wire [31:0] gpio_ctrl_o;
	wire [31:0] gpio_data_o;


     wire[31:0] s_addr;
     wire s_as_;
     wire s_rw;
     wire [31:0] s_wr_data;
     
     wire [31:0] m_rd_data;
     wire m_rdy_;

     wire  [3:0] w_dbus_we    ;
     wire [31:0] w_dbus_addr  ;
     wire [31:0] w_dbus_data_o;
     wire [31:0] w_dbus_data_i;
     
     
     wire init_tx;
     wire uart_tx;
     wire init_rx;
     wire uart_rx;

     assign tx=(init_sig ? init_tx :uart_tx);
     assign init_rx=(init_sig ? rx : 1'b1);
     assign uart_rx=(init_sig ? 1'b1 : rx);
     
     

slot_data slot_data(
    .i_memAddr_32(dataAddr_32),
    .i_lsuData_32(writeData_32),
    .i_memWen_4(dataWen_4),
    .i_busData_32(m_rd_data),
    .i_memData_32(w_dbus_data_i),
    .i_busRdy_1(m_rdy_),
    .o_memAddr_32(w_dbus_addr),
    .o_memData_32(w_dbus_data_o),
    .o_memWen_4(w_dbus_we),
    .o_busData_32(s_wr_data),
    .o_busAddr_32(s_addr),
    .o_busAs_1(s_as_),
    .o_busRw_1(s_rw),
    .o_loadData_32(readData_32)
);


memory_slot 
#(
    .FREQ(CLK_FREQ)
)
memory(
	    .clk                (clk               ),
        .rst               (rstn              ),
        
        .o_initSig_1           (init_sig          ),
        .i_initRx_1            (init_rx           ),
        .o_initTx_1            (init_tx           ),
        
        .i_ibusWe_4            (4'b1111           ),
        .i_ibusAddr_32        (instAddr_32     ),
        .i_ibusData_32        (32'b0             ),
        .o_ibusData_32        (instData_32     ),

        .i_dbusWe_4            (w_dbus_we         ),
        .i_dbusAddr_32        (w_dbus_addr       ),
        .i_dbusData_32        (w_dbus_data_o     ),
        .o_dbusData_32        (w_dbus_data_i     )
);
 bus_top
 #(
    .GPIO_NUM(GPIO_NUM),
    .FREQ(CLK_FREQ)
)bus(
        .clk(clk),
        .rst(rstn),
       .i_addr_32(s_addr),
       .i_as_1(s_as_),
       .i_rw_1(s_rw),
       .i_wrData_32(s_wr_data),
       .i_rx_1(uart_rx),
       .i_spiMiso_1(spi_miso),
       .io_ioPin_16(gpio_io),
       .o_rdData_32(m_rd_data),
       .o_rdy_1(m_rdy_),
       .o_tx_1(uart_tx),
       .o_spiMosi_1(spi_mosi),
       .o_spiSs_1(spi_ss),
       .o_spiClk_1(spi_clk),
       .o_gpioCtrl_32(gpio_ctrl_o),
       .o_gpioData_32(gpio_data_o),
       .o_irq_1(timer_iqr)
 );
endmodule

