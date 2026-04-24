`timescale 1ns / 1ps
module memory_slot(
    //来自总线的信号
    input  wire         clk,
    input  wire         rst,
    output wire         o_initSig_1,
    input  wire         i_initRx_1,
    //输出到tx引脚
    output wire         o_initTx_1,

    //Icache总线数据
    input  wire [ 3:0]   i_ibusWe_4        ,
    input  wire [31:0]  i_ibusAddr_32,
    input  wire [31:0]  i_ibusData_32,
    output wire [31:0]  o_ibusData_32,

    //Dcache总线数据
    input  wire [ 3:0]     i_dbusWe_4        ,
    input  wire [31:0]     i_dbusAddr_32,
    input  wire [31:0]     i_dbusData_32,
    output wire [31:0]     o_dbusData_32

    //Dcache总线信号          

    );
   //Icache 存储信号线
    wire [3:0]          memory_ibus_we;
    wire [31:0]         memory_ibus_addr_i;      
    wire [31:0]         memory_ibus_data_i;        
    wire [31:0]         memory_ibus_data_o;   

   //Dcache 存储信号线
    wire [3:0]          memory_dbus_we;        
    wire [31:0]         memory_dbus_addr_i; 
    wire [31:0]         memory_dbus_data_i; 
    wire [31:0]         memory_dbus_data_o; 
    
    //Icache存储器 初始化信号线
    wire                init_ibus_we    ;
    wire [31:0]         init_ibus_addr    ;      
    wire [31:0]         init_ibus_data    ;        
    
    //Dcache存储器 初始化信号线
    wire                init_dbus_we    ;        
    wire [31:0]         init_dbus_addr    ; 
    wire [31:0]         init_dbus_data    ; 

    //根据init_enable选择总线数据
    assign memory_ibus_we      = o_initSig_1 ?  {4{~init_ibus_we}} :  i_ibusWe_4      ;
    assign memory_ibus_addr_i  = o_initSig_1 ?  init_ibus_addr    :  i_ibusAddr_32  ;
    assign memory_ibus_data_i  = o_initSig_1 ?  init_ibus_data    :  i_ibusData_32  ;
    assign memory_dbus_we      = o_initSig_1 ?  {4{~init_dbus_we}} :  i_dbusWe_4      ;
    assign memory_dbus_addr_i  = o_initSig_1 ?  init_dbus_addr    :  i_dbusAddr_32  ;
    assign memory_dbus_data_i  = o_initSig_1 ?  init_dbus_data    :  i_dbusData_32  ;
    
    assign o_ibusData_32 = memory_ibus_data_o  ; //防bug补丁可真好用
    assign o_dbusData_32 = memory_dbus_data_o;

 SramTop Icache(
    .i_sramTrig(clk),
    .i_addr_13(memory_ibus_addr_i[14:2]),
    .i_WEB_4(memory_ibus_we),
    .i_data_32(memory_ibus_data_i),

    .o_data_32(memory_ibus_data_o)
 );
 SramTop Dcache(
    .i_sramTrig(clk),
    .i_addr_13(memory_dbus_addr_i[14:2]),
    .i_WEB_4(memory_dbus_we),
    .i_data_32(memory_dbus_data_i),
    .o_data_32(memory_dbus_data_o)
);

 data_init data_init(
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
