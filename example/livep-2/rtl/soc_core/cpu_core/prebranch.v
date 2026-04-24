//-----------------------------------------------
//    module name: m_prebranch
//    author: Jia Jintao
//  
//    version: 1st version
//    description: m_prebranch 模块实现了对跳转指令的译码和提前分支，
//                 并识别  MRET，ECALL，EBREAK 三种异常。
//        
//
//
//-----------------------------------------------
`timescale 1ns / 1ps
`include "riscv.h"
module m_prebranch(
    input  wire [31:0] i_inst_32,    
    input  wire [31:0] i_addr_32,    
	output wire [ 9:0]  o_ifToGrf_10,    //两个寄存器地址打包，发往GRF
	output wire [1:0]   o_ifEnToGrf_2,   //两位读使能
	input  wire [63:0] i_grfToIf_64,     //接收来自GRF的两个数据
    output wire [31:0] o_inst_32,    
    output wire        o_ecall,         
    output wire        o_ebreak,
    output wire        o_mret,
    output wire [31:0] o_branchPC_32,    //若跳转，下一条指令PC
    output wire        o_isBranch_1      //是否为J型指令或B型指令

);
//-----{寄存器信号打包}begin
    wire [31:0] w_rdata1_32; 
    wire [31:0] w_rdata2_32; 
    wire [ 4:0] w_addrGRF1_5;
    wire [ 4:0] w_addrGRF2_5;
    assign o_ifToGrf_10 = {
    						w_addrGRF1_5,
    						w_addrGRF2_5
    						};
    assign {	w_rdata1_32,
    			w_rdata2_32 } = i_grfToIf_64;
//-----{信号打包}end
    wire [2:0] w_funct_3;
    wire [6:0] w_opcode_7;
    wire       w_BJ_1;
    wire       w_MRET_1;
    wire       w_ECALL_1;
    wire       w_EBREAK_1;
    //define B-type and J-type address
    wire [31:0] w_branchPC_32;
    wire [31:0] w_branchPC_B1_32;
    wire [31:0] w_branchPC_B2_32;
    wire [31:0] w_branchPC_JALR_32;
    wire [31:0] w_branchPC_JAL_32;
    wire [ 4:0] w_rs1_5;
    wire [ 4:0] w_rs2_5;

    //三种异常指令
    localparam MRET   = 32'h30200073; 
    localparam ECALL  = 32'h00000073;
    localparam EBREAK = 32'h00100073;

    //判断是否为三种异常指令之一
    assign w_MRET_1         = (i_inst_32 == MRET);
    assign w_ECALL_1        = (i_inst_32 == ECALL);
    assign w_EBREAK_1       = (i_inst_32 == EBREAK);
   
    //跳转PC
    assign w_branchPC_B1_32 = i_addr_32 + {{20{i_inst_32[31]}}, i_inst_32[7], i_inst_32[30:25], i_inst_32[11:8],1'b0};//偏移量符号位拓展
    assign w_funct_3        = i_inst_32[14:12];
    assign w_opcode_7       = i_inst_32[6:0];
    
   //两个寄存器地址
    assign w_rs1_5          = i_inst_32[19:15];
    assign w_rs2_5          = i_inst_32[24:20];

    wire w_branchPCflag_BEQ_1   =   (w_funct_3 == `FUNCT3_BEQ)  & (w_rdata1_32 == w_rdata2_32);
    wire w_branchPCflag_BNE_1   =   (w_funct_3 == `FUNCT3_BNE)  & (w_rdata1_32 != w_rdata2_32);
    wire w_branchPCflag_BLT_1   =   (w_funct_3 == `FUNCT3_BLT)  & ($signed(w_rdata1_32) < $signed(w_rdata2_32)) ;
    wire w_branchPCflag_BGE_1   =   (w_funct_3 == `FUNCT3_BGE)  & ($signed(w_rdata1_32) >= $signed(w_rdata2_32));
    wire w_branchPCflag_BLTU_1  =   (w_funct_3 == `FUNCT3_BLTU) & (w_rdata1_32 < w_rdata2_32) ;
    wire w_branchPCflag_BGEU_1  =   (w_funct_3 == `FUNCT3_BGEU) & (w_rdata1_32 >= w_rdata2_32);
    wire w_branchflag = w_branchPCflag_BEQ_1 | w_branchPCflag_BNE_1 | w_branchPCflag_BLT_1 | 
                         w_branchPCflag_BGE_1 | w_branchPCflag_BLTU_1 | w_branchPCflag_BGEU_1;
    
    //判断是否为B型指令或J型指令, 是否成功跳转
    assign w_BJ_1           = ((w_opcode_7 == `OP_BRANCH & w_branchflag ) | (w_opcode_7 == `OP_JALR) | (w_opcode_7 == `OP_JAL)) ;
    assign o_ifEnToGrf_2    = (w_opcode_7 == `OP_BRANCH) ? 2'b11:
                              (w_opcode_7 == `OP_JALR)?2'b10:
                              2'b00;
    //下一条指令的PC
    wire [31:0] w_prenextpc_32;
    assign w_prenextpc_32   = i_addr_32 + 32'h4;
    //准备J型指令的跳转PC
    assign w_branchPC_JALR_32   = (w_rdata1_32 + {{20{i_inst_32[31]}}, i_inst_32[31:20]}) & ~1;
    assign w_branchPC_JAL_32    = i_addr_32 + {{12{i_inst_32[31]}}, i_inst_32[19:12], i_inst_32[20], i_inst_32[30:21],1'b0};
    //选择最终的B型指令地址
    assign w_branchPC_B2_32     = w_branchflag ? (w_branchPC_B1_32) : (w_prenextpc_32);
    //根据指令的opcode部分从B型指令、JALR和JAL指令的跳转地址中选择最终的跳转地址
    assign w_branchPC_32        = (w_opcode_7 == `OP_BRANCH) ? w_branchPC_B2_32   :
                                  (w_opcode_7 == `OP_JALR  ) ? w_branchPC_JALR_32 :
                                  (w_opcode_7 == `OP_JAL   ) ? w_branchPC_JAL_32  :
                                                               i_addr_32;
    //如果需要冲刷流水线则发送nop指令
    assign o_inst_32            = (w_opcode_7 == `OP_BRANCH | w_MRET_1 | w_ECALL_1 | w_EBREAK_1) ? `nop : i_inst_32; 
    
    assign o_mret=w_MRET_1;
    assign o_ecall=w_ECALL_1;
    assign o_ebreak=w_EBREAK_1;
 
    assign w_addrGRF1_5         = w_rs1_5;
    assign w_addrGRF2_5         = w_rs2_5;

    assign o_branchPC_32        = w_branchPC_32;
    assign o_isBranch_1         = (w_opcode_7 == `OP_BRANCH)|(w_opcode_7 == `OP_JALR  )|(w_opcode_7 == `OP_JAL   );

endmodule
