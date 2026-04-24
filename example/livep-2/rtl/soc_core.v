 `timescale 1ns / 1ps

module soc_core(
    
    input  wire        clk_pad  ,
    input  wire        rstn_pad        ,   
    input  wire        rx_pin_pad      ,    
    output wire        tx_pin_pad      ,
    
    input  wire        spi_miso_pad,    // SPI MISO����
    output wire        spi_mosi_pad,    // SPI MOSI����
    output wire        spi_ss_pad,      // SPI SS����
    output wire        spi_clk_pad,     // SPI CLK����
    
    inout  wire [`GPIO_NUM-1:0]  io_pin_pad             //GPIO    
    );

	wire [31:0] gpio_ctrl_o;
	wire [31:0] gpio_data_o;
	wire [`GPIO_NUM-1:0] io_pin;
	wire        clk;
	wire        rstn;
	wire        init_sig;
	wire        rx;
	wire        tx;
    wire        spi_miso;    
    wire        spi_mosi;    
    wire        spi_ss;      
    wire        spi_clk;
     
    localparam input_DO   = 1'b0; localparam output_DI   = 1'bz;   
    localparam input_OE   = 1'b0; localparam output_OE   = 1'b1; 
    localparam input_IDDQ = 1'b0; localparam output_IDDQ = 1'b0; localparam inout_IDDQ = 1'b0;
    localparam input_PD   = 1'b1; localparam output_PD   = 1'b0; localparam inout_PD   = 1'b1;
    localparam input_PU   = 1'b1; localparam output_PU   = 1'b0; localparam inout_PU   = 1'b1;
    localparam input_SMT  = 1'b1; localparam output_SMT  = 1'b0; localparam inout_SMT  = 1'b1;
    localparam input_SR   = 1'b0; localparam output_SR   = 1'b0; localparam inout_SR   = 1'b0;
    localparam input_PIN2 = 1'b0; localparam output_PIN2 = 1'b1; localparam inout_PIN2 = 1'b1;
    localparam input_PIN1 = 1'b0; localparam output_PIN1 = 1'b1; localparam inout_PIN1 = 1'b1;

     

     wire[31:0] s_addr;
     wire s_as_;
     wire s_rw;
     wire [31:0] s_wr_data;
     
     wire [31:0] m_rd_data;
     wire m_rdy_;
     
     wire  i_intFlag_1;
     
     wire [31:0] w_instAddr_32 ;

     wire [31:0] w_instData_32 ;
     wire [3:0]  w_dataWen_1;
     wire [31:0] w_dataAddr_32;
     wire [31:0] w_writeData_32;
     wire [31:0] w_readData_32;
    
     wire  [3:0]  w_dbus_we     ;
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


////-----INPUT IO PAD
	IUMA input_clk(
				.PAD   (clk_pad),.DI (clk),
				.OE    (input_OE  ),.IDDQ  (input_IDDQ),.PD    (input_PD  ),
				.PU    (input_PU  ),.SMT   (input_SMT ),.DO    (input_DO  ),
				.SR    (input_SR  ),.PIN2  (input_PIN2),.PIN1  (input_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);
	IUMA input_rstn(
				.PAD   (rstn_pad),.DI    (rstn),
				.OE    (input_OE  ),.IDDQ  (input_IDDQ),.PD    (input_PD  ),
				.PU    (input_PU  ),.SMT   (input_SMT ),.DO    (input_DO  ),
				.SR    (input_SR  ),.PIN2  (input_PIN2),.PIN1  (input_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);

	IUMA input_rx_pin(
				.PAD   (rx_pin_pad),.DI    (rx),
				.OE    (input_OE  ),.IDDQ  (input_IDDQ),.PD    (input_PD  ),
				.PU    (input_PU  ),.SMT   (input_SMT ),.DO    (input_DO  ),
				.SR    (input_SR  ),.PIN2  (input_PIN2),.PIN1  (input_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);	
	IUMA input_spi_miso(
				.PAD   (spi_miso_pad),.DI  (spi_miso),
				.OE    (input_OE  ),.IDDQ  (input_IDDQ),.PD    (input_PD  ),
				.PU    (input_PU  ),.SMT   (input_SMT ),.DO    (input_DO  ),
				.SR    (input_SR  ),.PIN2  (input_PIN2),.PIN1  (input_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);		
//-----OUTPUT IO PAD
	IUMA output_tx_pin(
				.PAD   (tx_pin_pad), .DO    (tx),
				.OE    (output_OE  ),.IDDQ  (output_IDDQ),.PD    (output_PD  ),
				.PU    (output_PU  ),.SMT   (output_SMT ),.DI    (output_DI  ),
				.SR    (output_SR  ),.PIN2  (output_PIN2),.PIN1  (output_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);
	IUMA output_spi_mosi(
				.PAD   (spi_mosi_pad), .DO    (spi_mosi),
				.OE    (output_OE  ),.IDDQ  (output_IDDQ),.PD    (output_PD  ),
				.PU    (output_PU  ),.SMT   (output_SMT ),.DI    (output_DI  ),
				.SR    (output_SR  ),.PIN2  (output_PIN2),.PIN1  (output_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);		
	IUMA output_spi_ss(
				.PAD   (spi_ss_pad), .DO    (spi_ss),
				.OE    (output_OE  ),.IDDQ  (output_IDDQ),.PD    (output_PD  ),
				.PU    (output_PU  ),.SMT   (output_SMT ),.DI    (output_DI  ),
				.SR    (output_SR  ),.PIN2  (output_PIN2),.PIN1  (output_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);		
	IUMA output_spi_clk(
				.PAD   (spi_clk_pad), .DO    (spi_clk),
				.OE    (output_OE  ),.IDDQ  (output_IDDQ),.PD    (output_PD  ),
				.PU    (output_PU  ),.SMT   (output_SMT ),.DI    (output_DI  ),
				.SR    (output_SR  ),.PIN2  (output_PIN2),.PIN1  (output_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		);
	genvar i; 
   generate
      for(i=0;i<`GPIO_NUM;i=i+1)
      begin: gpio
	       IUMA inout_gpio_i(
				.PAD   (io_pin_pad[i]),  .OE    (gpio_ctrl_o[i]),
				.DO    (gpio_data_o[i]), .DI    (io_pin[i]), 

				.IDDQ  (inout_IDDQ),
				.PD    (inout_PD  ),.PU    (inout_PU  ),.SMT   (inout_SMT ),
				.SR    (inout_SR  ),.PIN2  (inout_PIN2),.PIN1  (inout_PIN1)//,.VSS(1'b0),.VDD(1'b1),.VSSIO(1'b0),.VDDIO(1'b1)
		  );
      end
   endgenerate
    
        
 cpuCore cpu_top(
     .clk(clk),
     .rstn(rstn),
     .i_intFlag_1(i_intFlag_1),
     .init_sig(init_sig),
     
    //icache         
    .o_instAddr_32(w_instAddr_32),
    .i_instData_32(w_instData_32),
    
    //dcache
    .o_dataWen_4(w_dataWen_1),
    .o_dataAddr_32(w_dataAddr_32),
    .o_writeData_32(w_writeData_32),
    .i_readData_32(w_readData_32)
    
 );
slot_data slot_data(
    .i_memAddr_32(w_dataAddr_32),
    .i_lsuData_32(w_writeData_32),
    .i_memWen_4(w_dataWen_1),
    .i_busData_32(m_rd_data),
    .i_memData_32(w_dbus_data_i),
    .i_busRdy_1(m_rdy_),
    //������dCache������
    .o_memAddr_32(w_dbus_addr),
    .o_memData_32(w_dbus_data_o),
    .o_memWen_4(w_dbus_we),
    //������uart������
    .o_busData_32(s_wr_data),
    .o_busAddr_32(s_addr),
    .o_busAs_1(s_as_),
    .o_busRw_1(s_rw),
    //����LSU����
    .o_loadData_32(w_readData_32)
);
memory_slot memory(
	.clk                (clk               ),
        .rstn               (rstn              ),
        
        .init_sig           (init_sig          ),
        .init_rx            (init_rx           ),
        .init_tx            (init_tx           ),
        
        .ibus_we            (4'b1111           ),
        .ibus_addr_i        (w_instAddr_32     ),
        .ibus_data_i        (32'b0             ),
        .ibus_data_o        (w_instData_32     ),

        .dbus_we            (w_dbus_we         ),
        .dbus_addr_i        (w_dbus_addr       ),
        .dbus_data_i        (w_dbus_data_o     ),
        .dbus_data_o        (w_dbus_data_i     )
);
 bus_top bus(
        .clk(clk),
        .reset(rstn),
       .s_addr(s_addr),
       .s_as_(s_as_),
       .s_rw(s_rw),
       .s_wr_data(s_wr_data),
       .rx(uart_rx),
       .spi_miso(spi_miso),
       .io_pin_i(io_pin),
       .m_rd_data(m_rd_data),
       .m_rdy_(m_rdy_),
       .tx(uart_tx),
       .spi_mosi(spi_mosi),
       .spi_ss(spi_ss),
       .spi_clk(spi_clk),
       .gpio_ctrl_o(gpio_ctrl_o),
       .gpio_data_o(gpio_data_o),
       .irq(i_intFlag_1)
 );
endmodule

