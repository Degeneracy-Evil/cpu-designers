`timescale 1ns / 1ps
`include "timer_define.vh"

module timer(
    input  wire        clk,
    input  wire        rst,
    input  wire        i_cs_1,
    input  wire 	   i_as_1,
    input  wire        i_rw_1,
    input  wire [31:0] i_addr_32,
	input  wire [31:0] i_wrData_32,
    output reg  [31:0] o_rdData_32,
	output reg 	 	   o_rdy_1,
	output reg 		   o_irq_1
    ); 

	reg mode;
	reg start;
	reg [31:0] expr_val;
	reg [31:0] counter;

    wire expr_flag = ((start == `ENABLE) && (counter >= expr_val) && (expr_val != 32'b0)) ?
					 `ENABLE : `DISABLE;
	
	always@(posedge clk or negedge rst) begin
		if (rst == `RESET_ENABLE) begin
			o_rdData_32  <= `WORD_DATA_W'h0;
			o_rdy_1	 <=  `DISABLE_;
			start	 <=  `DISABLE;
			mode	 <=  `TIMER_MODE_PERIODIC;
			o_irq_1		 <=  `DISABLE;
			expr_val <=  `WORD_DATA_W'h0;
			counter	 <=  `WORD_DATA_W'h0;
		end else begin
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_)) begin
				o_rdy_1	<=  `ENABLE_;
			end else begin
				o_rdy_1	<=  `DISABLE_;
			end
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `READ)) begin
				case (i_addr_32[3:2])
					2'd0: begin
						o_rdData_32	<=  expr_val;
					end
					2'd1: begin
						o_rdData_32	<=  {{`WORD_DATA_W-2{1'b0}}, mode, start};
					end
					2'd2: begin
						o_rdData_32	<=  {{`WORD_DATA_W-1{1'b0}}, o_irq_1};
					end
					2'd3: begin
						o_rdData_32	<=  counter;
					end
				endcase
			end else begin
				o_rdData_32	<= `WORD_DATA_W'h0;
			end
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[3:2] == 2'd0)) begin
				expr_val	<=  i_wrData_32;
			end
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[3:2] == 2'd1)) begin
				start	<=  i_wrData_32[`TimerStartLoc];
				mode	<=  i_wrData_32[`TimerModeLoc];
			end else if ((expr_flag == `ENABLE) && (mode == `TIMER_MODE_ONE_SHOT)) begin
				start	<=  `DISABLE;
			end
			if (expr_flag == `ENABLE) begin
				o_irq_1			<=  `ENABLE;
			end else if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[3:2] == 2'd2)) begin
				o_irq_1			<=  i_wrData_32[`TimerIrqLoc];
			end
			if ((i_cs_1 == `ENABLE_) && (i_as_1 == `ENABLE_) && (i_rw_1 == `WRITE) && (i_addr_32[3:2] == 2'd3)) begin
				counter		<=  i_wrData_32;
			end else if (expr_flag == `ENABLE) begin
				counter 	<=  `WORD_DATA_W'h0;
			end else if (start == `ENABLE) begin
				counter		<=  counter + 1'd1;
			end
		end
	end
endmodule
