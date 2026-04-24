`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/23 07:15:46
// Design Name: 
// Module Name: gpio
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


module gpio(

    input         clk,
    input         reset,
    
     //来自总线的信号
    input wire      cs_,
    input wire      as_,
    input wire      rw,
    
    //输出到总线
    output reg      rdy_,   
    input  [31:0] addr_i,
    input  [31:0] data_i,
    output [31:0] data_o,

    output [31:0] gpio_ctrl_o,
    output [31:0] gpio_data_o,
               
    input  [`GPIO_NUM-1:0] io_pin_i
    );


    // GPIO控制寄存器
    localparam GPIO_CTRL = 4'h0;
    // GPIO数据寄存器
    localparam GPIO_DATA = 4'h4;

    // 1：输出,0：输入
    reg[31:0] gpio_ctrl;
    // 输入输出数据
    reg[31:0] gpio_data;
    //gpio_data处理
    
    reg write_reg_ctrl_en;
    reg write_reg_data_en;

    assign gpio_ctrl_o = gpio_ctrl;
    assign gpio_data_o = gpio_data;

    genvar i; 
// 产生使能信号
    // 传输期间一直有效
    always @ (posedge clk or negedge reset) begin
        if (!reset) begin
            write_reg_ctrl_en<=1'b0;
            write_reg_data_en<=1'b0;
            rdy_<=1'b1;
        end else begin
            /*就绪信号生成*/
            if((cs_ == 1'b0)&&(as_==1'b0))begin//改动
                rdy_<= 1'b0;
            end else begin
                rdy_<=1'b1;
            end
            if ((cs_==1'b0)&&(as_==1'b0)) begin
                write_reg_ctrl_en<=rw & (addr_i[3:0] == GPIO_CTRL);
                write_reg_data_en<=rw & (addr_i[3:0] == GPIO_DATA);
            end else begin
                write_reg_ctrl_en<=1'b0;
                write_reg_data_en<=1'b0;
            end
        end
    end
    //gpio_data处理
    generate
       for(i=0;i<`GPIO_NUM;i=i+1)
       begin: io_ctrl
            always@(posedge clk or negedge reset) begin
                if(!reset) begin
                    gpio_data[i] <= 1'b0;
                end else begin
                    if(write_reg_data_en & gpio_ctrl[i]) begin
                        gpio_data[i] <= data_i[i];
                    end
                    if(~gpio_ctrl[i]) begin 
                        gpio_data[i] <= io_pin_i[i];
                    end 
 
                end    
             end
       end
    endgenerate

    // gpio_ctrl 处理
    always @ (posedge clk or negedge reset) begin
        if (!reset) begin
            gpio_ctrl <= 32'h0;
        end else begin
            if (write_reg_ctrl_en) begin
                  gpio_ctrl <= data_i;
            end 
            else begin 
                  gpio_ctrl <= gpio_ctrl;
            end
        end
    end

    assign data_o = (addr_i[3:0] == GPIO_CTRL) ? gpio_ctrl:
                    (addr_i[3:0] == GPIO_DATA) ? gpio_data : 32'b0 ;

endmodule
