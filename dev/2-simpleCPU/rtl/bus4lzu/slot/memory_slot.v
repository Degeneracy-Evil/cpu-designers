`timescale 1ns / 1ps
module memory_slot
#(
    parameter FREQ = 25
)
(
    //�������ߵ��ź�
    input  wire         clk,
    input  wire         rst,
    output wire         o_initSig_1,
    input  wire         i_initRx_1,
    //�����tx����
    output wire         o_initTx_1,

    //Icache��������
    input  wire [ 3:0]   i_ibusWe_4        ,
    input  wire [31:0]  i_ibusAddr_32,
    input  wire [31:0]  i_ibusData_32,
    output wire [31:0]  o_ibusData_32,

    //Dcache��������
    input  wire [ 3:0]     i_dbusWe_4        ,
    input  wire [31:0]     i_dbusAddr_32,
    input  wire [31:0]     i_dbusData_32,
    output wire [31:0]     o_dbusData_32
    
    );
   //Icache �洢�ź���
    wire [3:0]          memory_ibus_we;
    wire [31:0]         memory_ibus_addr_i;      
    wire [31:0]         memory_ibus_data_i;        
    wire [31:0]         memory_ibus_data_o;   

   //Dcache �洢�ź���
    wire [3:0]          memory_dbus_we;        
    wire [31:0]         memory_dbus_addr_i; 
    wire [31:0]         memory_dbus_data_i; 
    wire [31:0]         memory_dbus_data_o; 
    
    //Icache�洢�� ��ʼ���ź���
    wire                init_ibus_we    ;
    wire [31:0]         init_ibus_addr    ;      
    wire [31:0]         init_ibus_data    ;        
    
    //Dcache�洢�� ��ʼ���ź���
    wire                init_dbus_we    ;        
    wire [31:0]         init_dbus_addr    ; 
    wire [31:0]         init_dbus_data    ; 

    //����init_enableѡ����������
    assign memory_ibus_we      = o_initSig_1 ?  {4{~init_ibus_we}} :  i_ibusWe_4      ;
    assign memory_ibus_addr_i  = o_initSig_1 ?  init_ibus_addr    :  i_ibusAddr_32  ;
    assign memory_ibus_data_i  = o_initSig_1 ?  init_ibus_data    :  i_ibusData_32  ;
    assign memory_dbus_we      = o_initSig_1 ?  {4{~init_dbus_we}} :  i_dbusWe_4      ;
    assign memory_dbus_addr_i  = o_initSig_1 ?  init_dbus_addr    :  i_dbusAddr_32  ;
    assign memory_dbus_data_i  = o_initSig_1 ?  init_dbus_data    :  i_dbusData_32  ;
    
    assign o_ibusData_32 = memory_ibus_data_o  ; //��bug�����������
    assign o_dbusData_32 = memory_dbus_data_o;
 Sram SramDualPort(
    .clka(clk),
    .ena(1'b1),
    .addra(memory_ibus_addr_i[14:2]),
    .wea(~memory_ibus_we),
    .dina(memory_ibus_data_i),
    .douta(memory_ibus_data_o),

    .clkb(clk),
    .enb(1'b1),
    .addrb(memory_dbus_addr_i[14:2]),
    .web(~memory_dbus_we),
    .dinb(memory_dbus_data_i),
    .doutb(memory_dbus_data_o)
 );

 data_init 
 #(
    .FREQ(FREQ)
 )
 data_init(
    .clk(clk),
    .rst(rst),
                      
    .i_uartRx_1(i_initRx_1),                    
    .o_uartTx_1(o_initTx_1),                   
    
    .o_initSig_1(o_initSig_1),
    .o_ibusWe_1(init_ibus_we),                  
    .o_ibusAddr_32(init_ibus_addr),                
    .o_ibusData_32(init_ibus_data),                
    .o_dbusWe_1(init_dbus_we),                   
    .o_dbusAddr_32(init_dbus_addr),                
    .o_dbusData_32(init_dbus_data)                
 );

endmodule    

