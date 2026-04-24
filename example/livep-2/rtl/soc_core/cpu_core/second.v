//-----------------------------------------------
//    module name: m_idStage
//    author: Liang
//  
//    version: 1st version (2021-10-01)
//    description: ������������������������������������������������������������������lsu��������?
//                 ���������������������������alu��������������������������������������������������?
//
//
//-----------------------------------------------
`timescale 1ns / 1ps

module Second (
    input wire         clk,
    input wire         rstn,					  
	input  wire [63:0] i_PcAndinstr_64, /////////
    //��������������?      
    output wire        o_idPipeHold_1,
    //    GRF ������
	output wire [9:0]  o_secondtogrf_10,         //grf
	input  wire [63:0] i_grfToId_64,/////
    //	CSR ������
	input  wire [31:0] i_csrData_32,     /////         //csr
    output wire [11:0] o_csrreadaddr_12,             //CSR������������������������GRF
	output wire [44:0] o_idToCsr_45,
    //	LSU
	output wire [138:0] o_ExeLsuBus_139,
	//error
	output wire        o_IllegalInsSecond_1,      //clint
	//hazard
	output wire [18:0] o_secondtohazard_19,
	output wire [31:0] o_exeResult_32  
);
   
    //-----{������������}begin
	wire [11:0] w_csrAddr_12;                    //CSR��������������������?
	wire [31:0] w_csrWdata_32;                   //CSR��������������������?
	wire        w_csrWen_1;    
	//CSR��������������������?
	assign o_idToCsr_45 = {	w_csrWen_1,
	                        w_csrAddr_12, 
							w_csrWdata_32} ; 
							    
    wire [ 4:0] w_rs1Addr_5;
    wire [ 4:0] w_rs2Addr_5;
    
	assign o_secondtogrf_10 = {	     
                            w_rs1Addr_5,
                            w_rs2Addr_5 } ;
    assign o_csrreadaddr_12 = w_csrAddr_12;

//-----{������������}end

//-----{������������}begin
    wire [189:0] w_DecoderExeBus_190;
    wire [31:0]  w_inst_32;
    
    m_decode decode(
		.i_PcAndinstr_64		(i_PcAndinstr_64),
		.i_grfToId_64			(i_grfToId_64),
        .i_csrValue_32          (i_csrData_32),
        .o_rs1Addr_5            (w_rs1Addr_5),
        .o_rs2Addr_5            (w_rs2Addr_5),
        .o_csrAddr_12           (w_csrAddr_12),
	    .w_inst_32              (w_inst_32),       
        .o_DecoderExeBus_190    (w_DecoderExeBus_190),
        .o_IllegalInsSecond_1   (o_IllegalInsSecond_1),
        .o_secondtohazard_19    (o_secondtohazard_19)
    );
//-----{������������}end

//-----{������������������}begin
    wire [138:0] w_ExeLsuBus_139;
    wire 		 w_muldivHold_1;
    wire [4:0]  w_rdAddr_5;
    
    m_exe exe(
        .clk                    (clk),
        .rstn                   (rstn ),
        .i_DecoderExeBus_190    (w_DecoderExeBus_190),
        .o_ExeLsuBus_139        (w_ExeLsuBus_139),
        .o_csrWen_1				(w_csrWen_1),
		.o_rdAddr_5				(w_rdAddr_5),          
        .o_csrWdata_32			(w_csrWdata_32),
        .o_muldivHold_1         (w_muldivHold_1),
        .o_exeResult_32         (o_exeResult_32)
    );
    
    assign o_ExeLsuBus_139 = w_ExeLsuBus_139;
    assign o_idPipeHold_1   =  w_muldivHold_1;

endmodule

