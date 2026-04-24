//-----------------------------------------------
//    module name: cpuCore
//    author: 
//  
//    version: 1st version (2023-7-18)
//    description: CPU核模块，三级流水，包含中断异常处理
//        
//
//
//-----------------------------------------------
`timescale 1ns / 1ps

module cpuCore(
    input  wire        clk,
    input  wire        rstn,

    //Peripheral interrupt
    input  wire  i_intFlag_1,
    input wire init_enable,
    
    //bus to ifStage
    input wire [31:0] bus_rd_data,
    input wire bus_rdy_,
    input wire m0_grnt_,
    input wire m1_grnt_, 
    
    //icache         
    output wire [31:0] o_instAddr_32,
    output wire [3:0]  o_enToCache_4,
    input  wire [31:0] i_instData_32,
    
    //dcache
    output wire [ 3:0] o_dataWen_4,
    output wire [31:0] o_dataAddr_32,
    output wire [31:0] o_writeData_32,
    input  wire [31:0] i_readData_32,
  
    //ifStage to bus
    output wire m0_req_,
    output wire [29:0] m0_addr,
    output wire m0_as_,
    output wire m0_rw,
    output wire [31:0] m0_wr_data,
    output wire m1_req_,
    output wire [29:0] m1_addr,
    output wire m1_as_,
    output wire m1_rw,
    output wire [31:0] m1_wr_data
    
    );
    assign o_enToCache_4=4'b1111;
    
    wire [31:0]     w_nextPC_32;
    wire [31:0]     w_pc_if_32; 
    wire [31:0]     w_intIns_if_32; 
    wire [ 95:0]	w_CsrToClint_96;
    wire [128:0]	w_ClintToCsr_129;
	wire [31:0] 	w_PC_Clint_32;
    wire 			w_PC_Clint_32En;
	wire [63:0]     w_pcAndIns_if_64;	
    wire [63:0]     w_pcAndIns_de_64;	
    wire [63:0]   	w_pcAndIns_ls_64;	
	wire [138:0]  	w_deToLs_de_139;	
    wire [138:0]  	w_deToLs_ls_139;	 	
	wire [9:0]     w_ifToGrf_10;
    wire [63:0]     w_grfToIf_64; 
    wire [  9:0]  	w_secondtogrf_10;  
    wire [ 63:0]  	w_grfToId_64;
    wire [ 37:0]    w_lsuToGrf_38;	
	wire [44:0]   w_exeToCsr_45;
    wire [31:0]   w_CsrReadData_32;
    wire          w_holdflag_if_1;
    wire          w_holdflag_ifde_1;
    wire 		  w_holdflag_dels_1;
    wire 		  w_flushflag_ifde_1;
    wire 		  w_flushflag_dels_1;
    wire          w_idPipeHold_1;
    wire 		  w_LsuPipeHold_1;
    wire 		  w_FlushSecond_Clint;
    wire 		  w_FlushThird_Clint;
	wire 		  w_InstrAcceFaultFirst_1;
    wire 		  w_EcallFirst_1;			
    wire 		  w_EbreakFirst_1;						
    wire 		  w_MretFirst_1;			
    wire 		  w_IllegalInsSecond_1;											
    wire 		  w_LoadAcceFaultThird_1;					
    wire 		  w_StoreAcceFaultThird_1;				
    wire 		  w_TimerInt_1;				//source
    wire [31:0] 	w_PC_inter_32;
    
	assign w_PC_inter_32 = w_nextPC_32;
	
    wire [31:0] 	w_Inst_First_32;
    
	assign w_Inst_First_32 = w_intIns_if_32;
	
    wire [31:0] 	w_PC_First_32;
    
	assign w_PC_First_32 = w_pc_if_32;
	
	wire [31:0] 	w_Inst_Second_32;	
	
	assign w_Inst_Second_32 = w_pcAndIns_de_64[31:0];	
	
    wire [31:0] 	w_PC_Second_32;	
    
	assign w_PC_Second_32 = w_pcAndIns_de_64[63:32];
	
	wire [31:0] 	w_Inst_Third_32;
	wire [31:0] 	w_PC_Third_32;
	wire [11:0] w_ifToHazard_12;
    wire [18:0] w_exToHazard_19;
    wire [ 5:0] w_lsToHazard_6;
    wire [ 3:0] w_forward_first_4;
    wire [ 1:0] w_forward_second_2;
	wire [ 31:0]  w_exeResult_32;			//tag
	wire [ 31:0]  w_lsuResult_32;
	wire [63:0 ] w_ToIf_64;
	wire [63:0 ] w_ToId_64;
    //冲刷前递信号
	assign w_ToIf_64[63:32] =  (w_forward_first_4[3:2]==2'b01)?w_exeResult_32:
							   (w_forward_first_4[3:2]==2'b10)?w_lsuResult_32:
							   w_grfToIf_64[63:32];								 								  
	assign w_ToIf_64[31: 0] =  (w_forward_first_4[1:0]==2'b01)?w_exeResult_32:
							   (w_forward_first_4[1:0]==2'b10)?w_lsuResult_32:
							   w_grfToIf_64[31: 0];				   
	assign w_ToId_64[63:32] =  (w_forward_second_2[1] == 1'b1)?w_lsuResult_32:w_grfToId_64[63:32];
	assign w_ToId_64[31:0] =  (w_forward_second_2[0] == 1'b1)?w_lsuResult_32:w_grfToId_64[31: 0];
    assign w_TimerInt_1 = i_intFlag_1;
    
    // ---------------------------------------------
    // PC-IF
    // ---------------------------------------------
    
    assign w_holdflag_if_1=(init_enable)?1'b1:(w_LsuPipeHold_1)?1'b1:
                           (w_idPipeHold_1)?1'b1:
                           1'b0;
    assign w_holdflag_ifde_1=(w_LsuPipeHold_1)?1'b1:
                           (w_idPipeHold_1)?1'b1:
                           1'b0;
    assign w_holdflag_dels_1=(w_LsuPipeHold_1)?1'b1:
							1'b0;
    assign w_flushflag_ifde_1=(w_FlushSecond_Clint)?1'b1:
                           1'b0;
    assign w_flushflag_dels_1=(w_FlushThird_Clint)?1'b1:
							1'b0;
    
    ifStage ifStage(
		.clk(clk),  
		.rstn(rstn),  
		.i_holdflag_if_1(w_holdflag_if_1),
		.i_inst_32(i_instData_32),          
		.i_isIntPC_1(w_PC_Clint_32En),         
		.i_intPC_32(w_PC_Clint_32),
		.i_grfToIf_64(w_ToIf_64),  
		.o_nextPC_32(w_nextPC_32),
		.o_pc_if_32(w_pc_if_32), 
		.o_intIns_if_32(w_intIns_if_32), 
		.o_PcAndinstr_64(w_pcAndIns_if_64),
		.o_ifToGrf_10(w_ifToHazard_12[11:2]),
		.o_ifEnToGrf_2(w_ifToHazard_12[1:0]),
		.o_InstrAcceFaultFirst_if_1(w_InstrAcceFaultFirst_1),
		.o_ecall_1(w_EcallFirst_1),
		.o_ebreak_1(w_EbreakFirst_1),
		.o_mret_1(w_MretFirst_1)
    );
    
    assign o_instAddr_32=w_nextPC_32;
    
    if_de if_de(
		.clk(clk),  
		.rstn(rstn),                
		.i_holdflag_1(w_holdflag_ifde_1),
		.i_flushflag_1(w_flushflag_ifde_1),
		.i_instAndPc_64(w_pcAndIns_if_64),      	
		.o_instAndPc_64(w_pcAndIns_de_64)
    );
    
    // ---------------------------------------------
    // ID-EX
    // ---------------------------------------------
    
    Second Second (
		.clk(clk),
		.rstn(rstn),		
		.i_PcAndinstr_64(w_pcAndIns_de_64),
		.o_idPipeHold_1(w_idPipeHold_1),
		.o_secondtogrf_10(w_secondtogrf_10),        
		.i_grfToId_64(w_ToId_64),
		.i_csrData_32(w_CsrReadData_32),                         
		.o_idToCsr_45(w_exeToCsr_45),
		.o_ExeLsuBus_139(w_deToLs_de_139),
		.o_IllegalInsSecond_1(w_IllegalInsSecond_1),  
		.o_secondtohazard_19(w_exToHazard_19),
		.o_exeResult_32(w_exeResult_32)
    );
    de_ls de_ls(
		.rstn(rstn),            
		.clk(clk),      
		.i_holdflag_1(w_holdflag_dels_1),
		.i_flushflag_1(w_flushflag_dels_1),			
		.i_instAndPc_64(w_pcAndIns_de_64),	
		.o_instAndPc_64(w_pcAndIns_ls_64),
		.i_deToLs_139(w_deToLs_de_139),
		.o_deToLs_139(w_deToLs_ls_139)
    );
    // ---------------------------------------------
    // LSU
    // ---------------------------------------------
    wire [31:0] rdData_32;
    wire [4:0] rdNum_5;
    wire rdWen_1;
    
    assign w_lsuToGrf_38 = {
        rdWen_1,
        rdNum_5,
	    rdData_32
    };
    assign w_lsToHazard_6 = {
        rdNum_5,
        rdWen_1
    };
    
 load_store_unit lsu(
        .clk(clk),
        .rstn(rstn),
        .i_ExeLsuBus_139(w_deToLs_ls_139),
        .i_memData_32(i_readData_32),            //dcache
        .bus_rd_data(bus_rd_data),
        .bus_rdy_(bus_rdy_),
        .bus_grnt_(m1_grnt_),
        .o_rdData_32(rdData_32),                //grf
        .o_rdNum_5(rdNum_5),                    //grf
        .o_rdWen_1(rdWen_1),
        .o_memAddr_32(o_dataAddr_32),              //dcache
        .o_memData_32(o_writeData_32),            //dcache
        .o_memWen(o_dataWen_4),                      //dcache
        .o_LsuPipeHold_1(w_LsuPipeHold_1),
        .o_epc_32(w_PC_Third_32),
        .o_einst_32(w_Inst_Third_32),
        .o_loadAcceFalutThird_1(w_LoadAcceFaultThird_1),
        .o_storeAcceFalutThird_1(w_StoreAcceFaultThird_1),
        .bus_req_(m1_req_),
        .bus_addr(m1_addr),
        .bus_as_(m1_as_),
        .bus_rw(m1_rw),
        .bus_wr_data(m1_wr_data)
    );  
    
    // ---------------------------------------------
    // haz
    // ---------------------------------------------
    hazard hazard(
		.i_ifToHazard_12(w_ifToHazard_12),	    
		.i_exToHazard_19(w_exToHazard_19),	 	
		.i_lsToHazard_6(w_lsToHazard_6),	
		.rst(!rstn),
		.o_forward_first_4(w_forward_first_4),	
		.o_forward_second_2(w_forward_second_2)
    );
    
    // ---------------------------------------------
    // grf
    // ---------------------------------------------
    assign w_ifToGrf_10=w_ifToHazard_12[11:2];
	grf grf(
		.clk(clk),
		.rstn(rstn),
	
		.i_ifToGrf_10(w_ifToGrf_10),
		.o_grfToIf_64(w_grfToIf_64),
                      
		.i_deToGrf_10(w_secondtogrf_10),
		.o_grfTode_64(w_grfToId_64),
	
		.i_lsuToGrf_38(w_lsuToGrf_38)
    );
    
    // ---------------------------------------------
    // clint+csr
    // ---------------------------------------------
    Clint Clint(	
		.i_InstrAcceFaultFirst_1(w_InstrAcceFaultFirst_1),	
		.i_EcallFirst_1(w_EcallFirst_1),						
		.i_EbreakFirst_1(w_EbreakFirst_1),						
		.i_MretFirst_1(w_MretFirst_1),				
		.i_IllegalInsSecond_1(w_IllegalInsSecond_1),												
		.i_LoadAcceFaultThird_1(w_LoadAcceFaultThird_1),						
		.i_StoreAcceFaultThird_1(w_StoreAcceFaultThird_1),				
		.i_TimerInt_1(w_TimerInt_1),
		.i_CsrToClint_96(w_CsrToClint_96),
		.o_ClintToCsr_129(w_ClintToCsr_129),
		.i_PC_inter_32(w_PC_inter_32),		
		.i_Inst_First_32(w_Inst_First_32),
		.i_PC_First_32(w_PC_First_32),
		.i_Inst_Second_32(w_Inst_Second_32),
		.i_PC_Second_32(w_PC_Second_32),
		.i_Inst_Third_32(w_Inst_Third_32),
		.i_PC_Third_32(w_PC_Third_32),	
		.o_PC_Clint_32(w_PC_Clint_32),
		.o_PC_Clint_32En(w_PC_Clint_32En),
		.o_FlushSecond_Clint(w_FlushSecond_Clint), 
		.o_FlushThird_Clint(w_FlushThird_Clint)
    );
    CSR CSR(
		.clk(clk),
		.rstn(rstn),
		.i_exe_45(w_exeToCsr_45),
		.o_ReadData_32(w_CsrReadData_32),
		.o_CsrToClint_96(w_CsrToClint_96),
		.i_ClintToCsr_129(w_ClintToCsr_129)
    );
	assign w_lsuResult_32=rdData_32;
endmodule
