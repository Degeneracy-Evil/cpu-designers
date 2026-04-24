`timescale 1ns / 1ps
`include "timer_define.vh"

module timer(
    input  wire        clk,
    input  wire        rst,
    input  wire        i_cs_1,
    input  wire 	   i_as_1,
    input  wire        i_rw_1,
    input  wire [31:0]  i_addr_32,
	input  wire [31:0] i_wrData_32,
    output reg  [31:0] o_rdData_32,
	output reg 	 	   o_rdy_1,
	output reg 		   o_irq_1
    ); 

	reg mode;
	reg start;
	reg [31:0] expr_val;
	reg [31:0] counter;



    // 计数完成标志位
	wire expr_flag = ((start == `ENABLE) && (counter == expr_val)) ?
					 `ENABLE : `DISABLE;
	
	//定时器控制
	always@(posedge clk or negedge rst) begin
		if (rst == `RESET_ENABLE) begin
			/* 异步复位 */
			o_rdData_32  <= `WORD_DATA_W'h0;
			o_rdy_1	 <=  `DISABLE_;
			start	 <=  `DISABLE;
			mode	 <=  `TIMER_MODE_ONE_SHOT;
			o_irq_1		 <=  `DISABLE;
			expr_val <=  `WORD_DATA_W'h0;
			counter	 <=  `WORD_DATA_W'h0;
		end else begin
			/* 就绪信号生成 */
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_)) begin
				o_rdy_1	<=  `ENABLE_;
			end else begin
				o_rdy_1	<=  `DISABLE_;
			end
			/* 就绪访问 */
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `READ)) begin
				case (i_addr_32[1:0])
					`TIMER_ADDR_CTRL	: begin		//控制寄存器0
						o_rdData_32	<=  {{`WORD_DATA_W-2{1'b0}}, mode, start};
					end
					`TIMER_ADDR_INTR	: begin		//控制寄存器1
						o_rdData_32	<=  {{`WORD_DATA_W-1{1'b0}}, o_irq_1};
					end
					`TIMER_ADDR_EXPR	: begin 	//控制寄存器2
						o_rdData_32	<=  expr_val;
					end
					`TIMER_ADDR_COUNTER	: begin		//控制寄存器3
						o_rdData_32	<= counter;
					end
				endcase
			end else begin
				o_rdData_32	<= `WORD_DATA_W'h0;
			end
			/* 写入访问 */
			//控制寄存器0
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[1:0] == `TIMER_ADDR_CTRL)) begin
				start	<=  i_wrData_32[`TimerStartLoc];
				mode	<=  i_wrData_32[`TimerModeLoc];
			end else if ((expr_flag == `ENABLE) && (mode == `TIMER_MODE_ONE_SHOT)) begin
				start	<=  `DISABLE;
			end
			//控制寄存器1
			if (expr_flag == `ENABLE) begin
				o_irq_1			<=  `ENABLE;
			end else if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[1:0] == `TIMER_ADDR_INTR)) begin
				o_irq_1			<=  i_wrData_32[`TimerIrqLoc];
			end
			//控制寄存器2
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[1:0] == `TIMER_ADDR_EXPR)) begin
				expr_val	<=  i_wrData_32;
			end
			//控制寄存器3
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[1:0] == `TIMER_ADDR_COUNTER)) begin
				counter		<=  i_wrData_32;
			end else if (expr_flag == `ENABLE) begin
				counter 	<=  `WORD_DATA_W'h0;
			end else if (start == `ENABLE) begin
				counter		<=  counter + 1'd1;
			end
		end
	end
endmodule
