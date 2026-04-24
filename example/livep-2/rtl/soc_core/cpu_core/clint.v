`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/16 18:26:31
// Design Name: 
// Module Name: Clint
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


module Clint(	
	input wire i_InstrAcceFaultFirst_1,	
	input wire i_EcallFirst_1,						
	input wire i_EbreakFirst_1,						
	input wire i_MretFirst_1,				
	input wire i_IllegalInsSecond_1,												
	input wire i_LoadAcceFaultThird_1,						
	input wire i_StoreAcceFaultThird_1,				
	input wire i_TimerInt_1,
	input wire [95:0]	i_CsrToClint_96,
	//mtvec:95-64  mepc:63-32 mstatus: 31-0
	output reg [128:0]	o_ClintToCsr_129,
	// 31:0:mstatus;63:32:mtval; 95:64:mcause;127:96mepc
	input wire [31:0] i_PC_inter_32,		
	input wire [31:0] i_Inst_First_32,
	input wire [31:0] i_PC_First_32,
	input wire [31:0] i_Inst_Second_32,
	input wire [31:0] i_PC_Second_32,
	input wire [31:0] i_Inst_Third_32,
	input wire [31:0] i_PC_Third_32,
	output reg [31:0] o_PC_Clint_32,
	output reg o_PC_Clint_32En,
	output wire o_FlushSecond_Clint, o_FlushThird_Clint
);

	assign o_FlushSecond_Clint = ((i_CsrToClint_96[3]==1'b1)&&(i_IllegalInsSecond_1||i_LoadAcceFaultThird_1||i_StoreAcceFaultThird_1))?1'b1:1'b0;
	assign o_FlushThird_Clint = ((i_CsrToClint_96[3]==1'b1)&&(i_LoadAcceFaultThird_1||i_StoreAcceFaultThird_1))?1'b1:1'b0;
	// 31:0:mstatus;63:32:mtval; 95:64:mcause;127:96mepc
	//mtvec:95-64  mepc:63-32 mstatus: 31-0
	
	always@(*)
	begin
	        if(i_MretFirst_1)
				begin 
					o_PC_Clint_32En = 1'b1;
					//mepc
					o_PC_Clint_32 = i_CsrToClint_96[63:32];
					//mstatus
					o_ClintToCsr_129[31:0] = {i_CsrToClint_96[31:4],i_CsrToClint_96[7],i_CsrToClint_96[2:0]};
					o_ClintToCsr_129[127:96] = 32'b0;
					o_ClintToCsr_129[63:32] = 32'b0;
					o_ClintToCsr_129[95:64] = 32'b0;
					o_ClintToCsr_129[128] = 32'b1;
				end
			else if((i_CsrToClint_96[3]==1'b1)&&(i_InstrAcceFaultFirst_1||i_IllegalInsSecond_1||i_EcallFirst_1||i_EbreakFirst_1
			||i_LoadAcceFaultThird_1||i_StoreAcceFaultThird_1||i_TimerInt_1))
				begin
					o_PC_Clint_32En = 1'b1;
					//mtvec
				     o_PC_Clint_32 = {i_CsrToClint_96[95:66],2'b0};
					//mepc
					o_ClintToCsr_129[127:96] = (i_LoadAcceFaultThird_1||i_StoreAcceFaultThird_1)?i_PC_Third_32:((i_IllegalInsSecond_1)?i_PC_Second_32:((i_InstrAcceFaultFirst_1||i_EcallFirst_1||i_EbreakFirst_1)?i_PC_First_32:(
					(i_TimerInt_1)?i_PC_inter_32:32'b0)));
					//mtval
					o_ClintToCsr_129[63:32] = (i_LoadAcceFaultThird_1||i_StoreAcceFaultThird_1)?i_Inst_Third_32:((i_IllegalInsSecond_1)?i_Inst_Second_32:(
					(i_TimerInt_1||i_InstrAcceFaultFirst_1||i_EcallFirst_1||i_EbreakFirst_1)?i_Inst_First_32:32'b0));
					//mstatus
					o_ClintToCsr_129[31:0] = {i_CsrToClint_96[31:8],i_CsrToClint_96[3],i_CsrToClint_96[6:4],1'b0,i_CsrToClint_96[2:0]};
					//mcause
					if(i_StoreAcceFaultThird_1)
					begin
						o_ClintToCsr_129[95:64] = {24'b0,1'b1,7'b0};
					end
					else if(i_LoadAcceFaultThird_1)
					begin
						o_ClintToCsr_129[95:64] = {16'b0,1'b1,5'b0};
					end
					else if(i_IllegalInsSecond_1)
					begin
						o_ClintToCsr_129[95:64] = {29'b0,1'b1,2'b0};
					end
					else if(i_InstrAcceFaultFirst_1)
					begin
						o_ClintToCsr_129[95:64] = {30'b0,2'b10};
					end
					else if(i_EcallFirst_1)
					begin
						o_ClintToCsr_129[95:64] = {20'b0,1'b1,11'b0};   
					end
					else if(i_EbreakFirst_1)
					begin
						o_ClintToCsr_129[95:64] = {28'b0,1'b1,3'b0};
					end
					else if(i_TimerInt_1)
					begin
						o_ClintToCsr_129[95:64] = {1'b1,23'b0,1'b1,7'b0};
						if(i_CsrToClint_96[64])begin
						o_PC_Clint_32 ={i_CsrToClint_96[95:66],2'b0}+5'h1C;
						end
					end	
					o_ClintToCsr_129[128] = 32'b1;
				end
			else
				begin 
					o_PC_Clint_32En = 1'b0;
					o_PC_Clint_32 = 32'b0;
					o_ClintToCsr_129[128:0] =129'b0;
				end
	end
	
endmodule 

