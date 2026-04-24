`timescale 1ns / 1ps

module cpuCore(
    input  wire        clk,
    input  wire        rstn,

    //Peripheral interrupt
    input  wire  i_intFlag_1,
    input  wire  init_sig,
    
    //icache         
    output wire [31:0] o_instAddr_32,
    
    //dcache
    output wire [ 3:0] o_dataWen_4,
    output wire [31:0] o_dataAddr_32,
    output wire [31:0] o_writeData_32,
    input  wire [31:0] i_readData_32    
    );
	
	//clint
	wire [ 95:0]	w_CsrToClint_96;
    wire [128:0]	w_ClintToCsr_129;
	wire [31:0] 	w_PC_Clint_32;
    wire 			w_PC_Clint_32En;
    wire [31:0]     w_nextPC_32;
    wire [31:0]     w_pc_if_32; 
    wire [31:0]     w_intIns_if_32; 
	wire [31:0] 	w_PC_inter_32;
	wire [31:0] 	w_Inst_First_32;
	wire [31:0] 	w_PC_First_32;
	wire [31:0] 	w_Inst_Second_32;
	wire [31:0] 	w_PC_Second_32;
	wire [31:0] 	w_Inst_Third_32;
	wire [31:0] 	w_PC_Third_32;
	wire 		  w_InstrAcceFaultFirst_1;
    wire 		  w_EcallFirst_1;			
    wire 		  w_EbreakFirst_1;						
    wire 		  w_MretFirst_1;			
    wire 		  w_IllegalInsSecond_1;											
    wire 		  w_LoadAcceFaultThird_1;					
    wire 		  w_StoreAcceFaultThird_1;				
    wire 		  w_TimerInt_1;			
	
	//clint
	assign w_PC_inter_32 = w_nextPC_32;
	assign o_instAddr_32=w_nextPC_32;
	assign w_Inst_First_32 = w_intIns_if_32;
	assign w_PC_First_32 = w_pc_if_32;
	assign w_Inst_Second_32 = w_pcAndIns_de_64[31:0];	
	assign w_PC_Second_32 = w_pcAndIns_de_64[63:32];
    
	//interstage reg
	wire [63:0]     w_pcAndIns_if_64;	
    wire [63:0]     w_pcAndIns_de_64;	
    wire [63:0]   	w_pcAndIns_ls_64;	
	wire [138:0]  	w_deToLs_de_139;	
    wire [138:0]  	w_deToLs_ls_139;	
    
	//grf
	wire [9:0]      w_ifToGrf_10;
    wire [63:0]     w_grfToIf_64; 
    wire [  9:0]  	w_secondtogrf_10;  
    wire [ 63:0]  	w_grfToId_64;
    wire [ 37:0]    w_lsuToGrf_38;
	wire [ 31:0]  w_exeResult_32;		
	wire [ 31:0]  w_lsuResult_32;
	wire [63:0 ] w_ToIf_64;
	wire [63:0 ] w_ToId_64;
	
	//csr
	wire [44:0]   w_exeToCsr_45;
    wire [31:0]   w_CsrReadData_32;
	
	//hold flush
    wire          w_holdflag_if_1;
    wire          w_holdflag_ifde_1;
    wire 		  w_holdflag_dels_1;
    wire 		  w_flushflag_ifde_1;
    wire 		  w_flushflag_dels_1;
    wire          w_idPipeHold_1;
    wire 		  w_LsuPipeHold_1;
    wire 		  w_FlushSecond_Clint;
    wire 		  w_FlushThird_Clint;
	
	//hazard
	wire [11:0] w_ifToHazard_12;
    wire [18:0] w_exToHazard_19;
    wire [ 5:0] w_lsToHazard_6;
    wire [ 3:0] w_forward_first_4;
    wire [ 1:0] w_forward_second_2;
    wire o_holdflag_first_1;
	
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
	
    assign w_holdflag_if_1=(init_sig)?1'b1:(w_LsuPipeHold_1)?1'b1:
                           (w_idPipeHold_1)?1'b1:
                           1'b0;
    assign w_holdflag_ifde_1=(w_LsuPipeHold_1)?1'b1:
                           (w_idPipeHold_1)?1'b1:
                           1'b0;
    assign w_holdflag_dels_1=(w_LsuPipeHold_1)?1'b1:(w_idPipeHold_1)?1'b1:
							1'b0;
    assign w_flushflag_ifde_1=(w_FlushSecond_Clint)?1'b1:
                           1'b0;
    assign w_flushflag_dels_1=(w_FlushThird_Clint)?1'b1:
							1'b0;
	
	
    // ---------------------------------------------
    // PC-IF
    // ---------------------------------------------
	
    ifstage ifstage(
		.clk(clk),  
		.rstn(rstn),  
        .i_holdFlagFirst_1(o_holdflag_first_1),
		.i_holdFlagIf_1(w_holdflag_if_1),
		.i_inst_32(i_instData_32),          
		.i_isIntPC_1(w_PC_Clint_32En),         
		.i_intPC_32(w_PC_Clint_32),
		.i_grfToIf_64(w_ToIf_64),  
		.o_nextPC_32(w_nextPC_32),
		.o_pcIf_32(w_pc_if_32), 
		.o_intInsIf_32(w_intIns_if_32), 
		.o_pcAndInstr_64(w_pcAndIns_if_64),
		.o_ifToGrf_10(w_ifToHazard_12[11:2]),
		.o_ifEnToGrf_2(w_ifToHazard_12[1:0]),
		.o_InstrAcceFaultFirstIf_1(w_InstrAcceFaultFirst_1),
		.o_ecall_1(w_EcallFirst_1),
		.o_ebreak_1(w_EbreakFirst_1),
		.o_mret_1(w_MretFirst_1)
    );
	
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
    second second (
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
        .i_memData_32(i_readData_32),           
        .o_rdData_32(rdData_32),                
        .o_rdNum_5(rdNum_5),                   
        .o_rdWen_1(rdWen_1),
        .o_memAddr_32(o_dataAddr_32),              
        .o_memData_32(o_writeData_32),           
        .o_memWen(o_dataWen_4),                      
        .o_LsuPipeHold_1(w_LsuPipeHold_1),
        .o_epc_32(w_PC_Third_32),
        .o_einst_32(w_Inst_Third_32),
        .o_loadAcceFalutThird_1(w_LoadAcceFaultThird_1),
        .o_storeAcceFalutThird_1(w_StoreAcceFaultThird_1)
    );
    
    // ---------------------------------------------
    // hazard
    // ---------------------------------------------
    hazard hazard(
		.rst(!rstn),
		.i_ifToHazard_12(w_ifToHazard_12),	    
		.i_exToHazard_19(w_exToHazard_19),	 	
		.i_lsToHazard_6(w_lsToHazard_6),	
		.o_forward_first_4(w_forward_first_4),	
		.o_forward_second_2(w_forward_second_2),
        .o_holdflag_first_1 (o_holdflag_first_1)
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
    clint clint(	
		.i_instrAcceFaultFirst_1(w_InstrAcceFaultFirst_1),	
		.i_ecallFirst_1(w_EcallFirst_1),						
		.i_ebreakFirst_1(w_EbreakFirst_1),						
		.i_mretFirst_1(w_MretFirst_1),				
		.i_illegalInsSecond_1(w_IllegalInsSecond_1),												
		.i_loadAcceFaultThird_1(w_LoadAcceFaultThird_1),						
		.i_storeAcceFaultThird_1(w_StoreAcceFaultThird_1),				
		.i_timerInt_1(w_TimerInt_1),
		.i_csrToClint_96(w_CsrToClint_96),
		.o_clintToCsr_129(w_ClintToCsr_129),
		.i_pc_inter_32(w_PC_inter_32),		
		.i_inst_first_32(w_Inst_First_32),
		.i_pc_first_32(w_PC_First_32),
		.i_inst_second_32(w_Inst_Second_32),
		.i_pc_second_32(w_PC_Second_32),
		.i_inst_third_32(w_Inst_Third_32),
		.i_pc_third_32(w_PC_Third_32),
		.o_pc_clint_32(w_PC_Clint_32),
		.o_pc_clintEn_1(w_PC_Clint_32En),
		.o_flushsecond_clint_1(w_FlushSecond_Clint), 
		.o_flushthird_clint_1(w_FlushThird_Clint)
    );
	
    csr csr(
		.clk(clk),
		.rstn(rstn),
		.i_exe_45(w_exeToCsr_45),
		.o_readData_32(w_CsrReadData_32),
		.o_csrToClint_96(w_CsrToClint_96),
		.i_clintToCsr_129(w_ClintToCsr_129)
    );
	
	assign w_lsuResult_32=rdData_32;
endmodule
