module clint(	
	input wire i_instrAcceFaultFirst_1,	//各个产生异常中断的模块发送的异常中断使能信号；为1为有异常，为0为无异常；
	input wire i_ecallFirst_1,						
	input wire i_ebreakFirst_1,						
	input wire i_mretFirst_1,				
	input wire i_illegalInsSecond_1,												
	input wire i_loadAcceFaultThird_1,						
	input wire i_storeAcceFaultThird_1,				
	input wire i_timerInt_1,

	input wire [95:0]  i_csrToClint_96,     //mtvec:95-64  mepc:63-32 mstatus: 31-0
						       CSR向异常处理模块发送的CSR的值
	output reg [128:0] o_clintToCsr_129,    // 31:0:mstatus;63:32:mtval; 95:64:mcause;127:96mepc;128:CSR更改使能
							异常处理模块向CSR发送的需要更改的CSR的值

	input wire [31:0]  i_pc_inter_32,	//各个产生异常中断的模块发送的异常中断的指令和PC
	input wire [31:0]  i_inst_first_32,
	input wire [31:0]  i_pc_first_32,
	input wire [31:0]  i_inst_second_32,
	input wire [31:0]  i_pc_second_32,
	input wire [31:0]  i_inst_third_32,
	input wire [31:0]  i_pc_third_32,
	
	output reg [31:0]  o_pc_clint_32,	//取指模块PC更改使能
	output reg o_pc_clintEn_1,

	output wire o_flushsecond_clint_1, o_flushthird_clint_1   //级间寄存器冲刷使能
);

	assign o_flushsecond_clint_1 = ((i_csrToClint_96[3]==1'b1)&&(i_illegalInsSecond_1||i_loadAcceFaultThird_1||i_storeAcceFaultThird_1))?1'b1:1'b0;
	assign o_flushthird_clint_1 = ((i_csrToClint_96[3]==1'b1)&&(i_loadAcceFaultThird_1||i_storeAcceFaultThird_1))?1'b1:1'b0;

	always@(*)
	begin
	        if(i_mretFirst_1)
				begin
					//取指使能
					o_pc_clintEn_1 = 1'b1;
					//o_pc_clint_32=mepc
					o_pc_clint_32 = i_csrToClint_96[63:32];
					//mstatus
					o_clintToCsr_129[31:0] = {i_csrToClint_96[31:4],i_csrToClint_96[7],i_csrToClint_96[2:0]};
					//mtval
					o_clintToCsr_129[127:96] = 32'b0;
					//mcause
					o_clintToCsr_129[63:32] = 32'b0;
					//mepc
					o_clintToCsr_129[95:64] = 32'b0;
					//CSR更改使能
					o_clintToCsr_129[128] = 32'b1;
				end
			else
			if((i_csrToClint_96[3]==1'b1)&&(i_instrAcceFaultFirst_1||i_illegalInsSecond_1||i_ecallFirst_1||i_ebreakFirst_1
			||i_loadAcceFaultThird_1||i_storeAcceFaultThird_1||i_timerInt_1))
				begin
					o_pc_clintEn_1 = 1'b1;
					//mtvec
				        o_pc_clint_32 = {i_csrToClint_96[95:66],2'b0};
					//mepc
					o_clintToCsr_129[127:96] = (i_loadAcceFaultThird_1||i_storeAcceFaultThird_1)?i_pc_third_32:((i_illegalInsSecond_1)?i_pc_second_32:((i_instrAcceFaultFirst_1||i_ecallFirst_1||i_ebreakFirst_1)?i_pc_first_32:(
					(i_timerInt_1)?i_pc_inter_32:32'b0)));
					//mtval
					o_clintToCsr_129[63:32] = (i_loadAcceFaultThird_1||i_storeAcceFaultThird_1)?i_inst_third_32:((i_illegalInsSecond_1)?i_inst_second_32:(
					(i_timerInt_1||i_instrAcceFaultFirst_1||i_ecallFirst_1||i_ebreakFirst_1)?i_inst_first_32:32'b0));
					//mstatus
					o_clintToCsr_129[31:0] = {i_csrToClint_96[31:8],i_csrToClint_96[3],i_csrToClint_96[6:4],1'b0,i_csrToClint_96[2:0]};
					//mcause
					if(i_storeAcceFaultThird_1)
					begin
						o_clintToCsr_129[95:64] = {24'b0,1'b1,7'b0};
					end
					else if(i_loadAcceFaultThird_1)
					begin
						o_clintToCsr_129[95:64] = {16'b0,1'b1,5'b0};
					end
					else if(i_illegalInsSecond_1)
					begin
						o_clintToCsr_129[95:64] = {29'b0,1'b1,2'b0};
					end
					
					else if(i_instrAcceFaultFirst_1)
					begin
						o_clintToCsr_129[95:64] = {30'b0,2'b10};
					end
					else if(i_ecallFirst_1)
					begin
						o_clintToCsr_129[95:64] = {20'b0,1'b1,11'b0};   
					end
					else if(i_ebreakFirst_1)
					begin
						o_clintToCsr_129[95:64] = {28'b0,1'b1,3'b0};
					end
					else if(i_timerInt_1)
					begin
						o_clintToCsr_129[95:64] = {1'b1,23'b0,1'b1,7'b0};
						if(i_csrToClint_96[64])begin
						o_pc_clint_32 ={i_csrToClint_96[95:66],2'b0}+5'h1C;
						end
					end	
					o_clintToCsr_129[128] = 32'b1;
				end
			else
				begin 
					o_pc_clintEn_1 = 1'b0;
					o_pc_clint_32 = 32'b0;
					o_clintToCsr_129[128:0] =129'b0;
				end
	end
	
endmodule 

