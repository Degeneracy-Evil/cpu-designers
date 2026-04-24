`timescale 1ns / 1ps

module ifstage(
    input  wire        clk,  
    input  wire        rstn,  
    input  wire        i_holdFlagFirst_1,
    input  wire        i_holdFlagIf_1,
    input  wire [31:0] i_inst_32,          

    input  wire        i_isIntPC_1,         
    input  wire [31:0] i_intPC_32,
    input  wire [63:0] i_grfToIf_64,
      
    //icache
    output wire [31:0] o_nextPC_32,
    //int
    output wire [31:0] o_pcIf_32, 
    output wire [31:0] o_intInsIf_32,
    
    output  wire [63:0]  o_pcAndInstr_64,
    
    output wire [ 9:0] o_ifToGrf_10,
    output wire [ 1:0] o_ifEnToGrf_2,
    output wire        o_InstrAcceFaultFirstIf_1,
    output wire        o_ecall_1,
    output wire        o_ebreak_1,
    output wire        o_mret_1
);

    wire [31:0] w_branchPC2_32;
    wire        w_isBranch_1;
    wire [31:0] w_branchPC_32;
    wire [31:0] w_instAddrIf_32;
    wire [31:0] w_instIf_32;

m_prefetch prefetch(
        .clk                (clk            ),     
        .rstn               (rstn           ),  
        .i_holdFlag_1       (i_holdFlagIf_1   ),  
       
        .i_inst_32          (i_inst_32      ),
   
        .i_isBranch_1       (w_isBranch_1   ), 
        .i_branchPc_32      (w_branchPC2_32  ),  
   
        .i_isIntPc_1        (i_isIntPC_1    ),    
        .i_intPc_32         (i_intPC_32     ),     
        
      
        .o_outputPc_32      (w_instAddrIf_32),
        .o_outputInst_32    (w_instIf_32),
     
     
	    .o_fetchAddr_32     (o_nextPC_32),
        .o_instrAcceFaultFirst_1      (o_InstrAcceFaultFirstIf_1)
    );

    wire [31:0] w_insIf_32;
    m_prebranch m_prebranch(
        .i_inst_32          (w_instIf_32       ),
        .i_addr_32          (w_instAddrIf_32   ),
        
        .o_ifToGrf_10       (o_ifToGrf_10    ),
        .o_ifEnToGrf_2      (o_ifEnToGrf_2),
        .i_grfToIf_64       (i_grfToIf_64    ),
        
        .o_inst_32          (w_insIf_32    ),
        .o_ecall            (o_ecall_1),         
        .o_ebreak           (o_ebreak_1),
        .o_mret             (o_mret_1),

        .o_branchPC_32      (w_branchPC_32   ),
        .o_isBranch_1       (w_isBranch_1    )
    );
    assign w_branchPC2_32=(i_holdFlagFirst_1==1'b0)?w_branchPC_32:32'b0;
	assign o_pcIf_32=w_instAddrIf_32;
	assign o_intInsIf_32=w_instIf_32;
    assign o_pcAndInstr_64 = {w_instAddrIf_32,w_insIf_32};

endmodule
