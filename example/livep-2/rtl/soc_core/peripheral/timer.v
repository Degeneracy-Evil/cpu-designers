`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/18 01:41:11
// Design Name: 
// Module Name: timer
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
`include "timer_define.vh"

module timer(
    input  wire        clk,
    input  wire        reset,
    input  wire        cs_,
    input  wire 	   as_,
    input  wire        rw,
    input  wire [31:0]  addr,
	input  wire [31:0] wr_data,
    output reg  [31:0] rd_data,
	output reg 	 	   rdy_,
	output reg 		   irq
    ); 

	reg mode;
	reg start;
	reg [31:0] expr_val;
	reg [31:0] counter;



    // 计数完成标志位
	wire expr_flag = ((start == `ENABLE) && (counter == expr_val)) ?
					 `ENABLE : `DISABLE;
	
	//定时器控制
	always@(posedge clk or negedge reset) begin
		if (reset == `RESET_ENABLE) begin
			/* 异步复位 */
			rd_data  <= `WORD_DATA_W'h0;
			rdy_	 <=  `DISABLE_;
			start	 <=  `DISABLE;
			mode	 <=  `TIMER_MODE_ONE_SHOT;
			irq		 <=  `DISABLE;
			expr_val <=  `WORD_DATA_W'h0;
			counter	 <=  `WORD_DATA_W'h0;
		end else begin
			/* 就绪信号生成 */
			if ((cs_ == `ENABLE_) && (as_ == `ENABLE_)) begin
				rdy_	<=  `ENABLE_;
			end else begin
				rdy_	<=  `DISABLE_;
			end
			/* 就绪访问 */
			if ((cs_ == `ENABLE_) && (as_ == `ENABLE_) && (rw == `READ)) begin
				case (addr)
					`TIMER_ADDR_CTRL	: begin		//控制寄存器0
						rd_data	<=  {{`WORD_DATA_W-2{1'b0}}, mode, start};
					end
					`TIMER_ADDR_INTR	: begin		//控制寄存器1
						rd_data	<=  {{`WORD_DATA_W-1{1'b0}}, irq};
					end
					`TIMER_ADDR_EXPR	: begin 	//控制寄存器2
						rd_data	<=  expr_val;
					end
					`TIMER_ADDR_COUNTER	: begin		//控制寄存器3
						rd_data	<= counter;
					end
				endcase
			end else begin
				rd_data	<= `WORD_DATA_W'h0;
			end
			/* 写入访问 */
			//控制寄存器0
			if ((cs_ == `ENABLE_) && (as_ == `ENABLE_) && (rw == `WRITE) && (addr == `TIMER_ADDR_CTRL)) begin
				start	<=  wr_data[`TimerStartLoc];
				mode	<=  wr_data[`TimerModeLoc];
			end else if ((expr_flag == `ENABLE) && (mode == `TIMER_MODE_ONE_SHOT)) begin
				start	<=  `DISABLE;
			end
			//控制寄存器1
			if (expr_flag == `ENABLE) begin
				irq			<=  `ENABLE;
			end else if ((cs_ == `ENABLE_) && (as_ == `ENABLE_) && (rw == `WRITE) && (addr == `TIMER_ADDR_INTR)) begin
				irq			<=  wr_data[`TimerIrqLoc];
			end
			//控制寄存器2
			if ((cs_ == `ENABLE_) && (as_ == `ENABLE_) && (rw == `WRITE) && (addr == `TIMER_ADDR_EXPR)) begin
				expr_val	<=  wr_data;
			end
			//控制寄存器3
			if ((cs_ == `ENABLE_) && (as_ == `ENABLE_) && (rw == `WRITE) && (addr == `TIMER_ADDR_COUNTER)) begin
				counter		<=  wr_data;
			end else if (expr_flag == `ENABLE) begin
				counter 	<=  `WORD_DATA_W'h0;
			end else if (start == `ENABLE) begin
				counter		<=  counter + 1'd1;
			end
		end
	end
endmodule
