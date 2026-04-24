`timescale 1ns / 1ps
`include "./riscv.h"
module m_decode(                      // 译码模块

	input  wire [63:0]  i_PcAndinstr_64,
	input  wire [63:0]  i_grfToId_64,
    input  wire [31:0]  i_csrValue_32,	    
    output wire [ 4:0]  o_rs1Addr_5,
    output wire [ 4:0]  o_rs2Addr_5,
    output wire [11:0]  o_csrAddr_12,
    output wire [31:0]  w_inst_32,
    output wire [190:0] o_DecoderExeBus_191,
    output wire         o_IllegalInsSecond_1,
    output wire [18:0]  o_secondtohazard_19
);
//-----{信号打包}begin
	wire [31:0]  w_PC_32;
	//wire [31:0]  w_inst_32;
	wire [31:0]  w_rs1Value_32;
	wire [31:0]  w_rs2Value_32;
	assign {
			w_PC_32,
			w_inst_32 } = i_PcAndinstr_64;
	assign {
			w_rs1Value_32,
			w_rs2Value_32 } = i_grfToId_64;		
    
//-----{信号打包}end
//-----{指令列表}begin

    // RV32指令分区
    wire [ 6:0] w_opcode_7;     // opcode区域
    wire [ 4:0] w_rd_5;         // rd区域
    wire [ 4:0] w_rs1_5;        // rs1区域
    wire [ 4:0] w_rs2_5;        // rs2区域
    wire [ 2:0] w_funct_3;      // funct3区域
    wire [ 6:0] w_funct_7;      // funct3区域
    wire [11:0] w_imm_12;       // imm12区域
    wire [ 6:0] w_imm_7;        // imm7区域
    wire [ 4:0] w_imm_5;        // imm5区域
    wire [19:0] w_imm_20;       // imm20区域
    wire [11:0] w_csrAddr_12;   // csr地址区域
    wire [ 4:0] w_csrImm_5;     // csr立即数区域

    assign w_opcode_7   = w_inst_32[ 6: 0];
    assign w_rd_5       = w_inst_32[11: 7];
    assign w_rs1_5      = w_inst_32[19:15];
    assign w_rs2_5      = w_inst_32[24:20];
    assign w_funct_3    = w_inst_32[14:12];
    assign w_funct_7    = w_inst_32[31:25];
    assign w_imm_12     = w_inst_32[31:20];
    assign w_imm_7      = w_inst_32[31:25];
    assign w_imm_5      = w_inst_32[11:7 ];
    assign w_imm_20     = w_inst_32[31:12];
    assign w_csrImm_5   = w_inst_32[19:15];
    assign w_csrAddr_12 = w_inst_32[31:20];


    assign o_rs1Addr_5 =  w_rs1_5;
    assign o_rs2Addr_5 = w_rs2_5 ;


    // RV32I指令列表
    wire w_instLUI_1    , w_instAUIPC_1;
    wire w_instLB_1     , w_instLH_1    , w_instLW_1    , w_instLBU_1 ;
    wire w_instLHU_1    , w_instSB_1    , w_instSH_1    , w_instSW_1  ;
    wire w_instADDI_1   , w_instSLTI_1  , w_instSLTIU_1 , w_instXORI_1;
    wire w_instORI_1    , w_instANDI_1  , w_instSLLI_1  , w_instSRLI_1;
    wire w_instSRAI_1   , w_instADD_1   , w_instSUB_1   , w_instSLL_1 ;
    wire w_instSLT_1    , w_instSLTU_1  , w_instXOR_1   , w_instSRL_1 ;
    wire w_instSRA_1    , w_instOR_1    , w_instAND_1   ;
    wire w_instJAL_1    , w_instJALR_1  ;

    // RV32M指令列表
    wire w_instMUL_1 , w_instMULH_1 , w_instMULHSU_1, w_instMULHU_1;
    wire w_instDIV_1 , w_instDIVU_1 , w_instREM_1   , w_instREMU_1;

    // RV32Zicsr指令列表
    wire w_instCSRRW_1  , w_instCSRRS_1 , w_instCSRRC_1 , w_intsCSRRWI_1
        ,w_instCSRRSI_1 , w_instCSRRCI_1;
        
    // wire w_instBEQ_1 , w_instBNE_1 , w_instBLT_1 , w_instBGE_1 , w_instBLTU_1 , 
    //     w_instBGEU_1 ;

//-----{指令列表}end

//-----{指令译码}begin
    // RV32I指令译码(ALU操作)
    assign w_instADD_1      = (w_funct_3 == `FUNCT3_ADD  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instSUB_1      = (w_funct_3 == `FUNCT3_SUB  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0100000);
    assign w_instSLL_1      = (w_funct_3 == `FUNCT3_SLL  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instSLT_1      = (w_funct_3 == `FUNCT3_SLT  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instSLTU_1     = (w_funct_3 == `FUNCT3_SLTU ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instXOR_1      = (w_funct_3 == `FUNCT3_XOR  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instSRL_1      = (w_funct_3 == `FUNCT3_SRL  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instSRA_1      = (w_funct_3 == `FUNCT3_SRA  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0100000);
    assign w_instOR_1       = (w_funct_3 == `FUNCT3_OR   ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
    assign w_instAND_1      = (w_funct_3 == `FUNCT3_AND  ) & (w_opcode_7 == `OP_OP    ) & (w_funct_7 == 7'b0000000);
  

    assign w_instADDI_1     = (w_funct_3 == `FUNCT3_ADDI)  & (w_opcode_7 == `OP_OP_IMM);
    assign w_instSLTI_1     = (w_funct_3 == `FUNCT3_SLTI)  & (w_opcode_7 == `OP_OP_IMM);
    assign w_instSLTIU_1    = (w_funct_3 == `FUNCT3_SLTIU) & (w_opcode_7 == `OP_OP_IMM);
    assign w_instXORI_1     = (w_funct_3 == `FUNCT3_XORI ) & (w_opcode_7 == `OP_OP_IMM);
    assign w_instORI_1      = (w_funct_3 == `FUNCT3_ORI  ) & (w_opcode_7 == `OP_OP_IMM);
    assign w_instANDI_1     = (w_funct_3 == `FUNCT3_ANDI ) & (w_opcode_7 == `OP_OP_IMM);

    assign w_instSLLI_1     = (w_funct_3 == `FUNCT3_SLLI ) & (w_opcode_7 == `OP_OP_IMM) & (w_funct_7 == 7'b0000000);
    assign w_instSRLI_1     = (w_funct_3 == `FUNCT3_SRLI ) & (w_opcode_7 == `OP_OP_IMM) & (w_funct_7 == 7'b0000000);
    assign w_instSRAI_1     = (w_funct_3 == `FUNCT3_SRAI ) & (w_opcode_7 == `OP_OP_IMM) & (w_funct_7 == 7'b0100000);

   
    // RV32I指令译码(Load Store指令)
    assign w_instLB_1       = (w_funct_3 == `FUNCT3_LB )   & (w_opcode_7 == `OP_LOAD);
    assign w_instLH_1       = (w_funct_3 == `FUNCT3_LH )   & (w_opcode_7 == `OP_LOAD);
    assign w_instLW_1       = (w_funct_3 == `FUNCT3_LW )   & (w_opcode_7 == `OP_LOAD);
    assign w_instLBU_1      = (w_funct_3 == `FUNCT3_LBU)   & (w_opcode_7 == `OP_LOAD);
    assign w_instLHU_1      = (w_funct_3 == `FUNCT3_LHU)   & (w_opcode_7 == `OP_LOAD);
    // RV32I指令译码(LUI和AUIPC)
    assign w_instLUI_1      = (w_opcode_7 == 7'b0110111);
    assign w_instAUIPC_1    = (w_opcode_7 == 7'b0010111);
    assign w_instSB_1       = (w_funct_3 == `FUNCT3_SB )   & (w_opcode_7 == `OP_STORE);
    assign w_instSH_1       = (w_funct_3 == `FUNCT3_SH )   & (w_opcode_7 == `OP_STORE);
    assign w_instSW_1       = (w_funct_3 == `FUNCT3_SW )   & (w_opcode_7 == `OP_STORE);

   
        // RV32I指令译码(跳转指令)
    assign w_instJAL_1      = (w_opcode_7 == `OP_JAL);
    assign w_instJALR_1     = (w_opcode_7 == `OP_JALR);

    // RV32M指令译码
    assign w_instMUL_1      = (w_funct_3 == `FUNCT3_MUL   ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instMULH_1     = (w_funct_3 == `FUNCT3_MULH  ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instMULHSU_1   = (w_funct_3 == `FUNCT3_MULHSU) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instMULHU_1    = (w_funct_3 == `FUNCT3_MULHU ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instDIV_1      = (w_funct_3 == `FUNCT3_DIV   ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instDIVU_1     = (w_funct_3 == `FUNCT3_DIVU  ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instREM_1      = (w_funct_3 == `FUNCT3_REM   ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);
    assign w_instREMU_1     = (w_funct_3 == `FUNCT3_REMU  ) & (w_opcode_7 == `OP_OP) & (w_funct_7 == `FUNCT7_RV32M);

    // RV32Zicsr指令译码
    assign w_instCSRRW_1    = (w_funct_3 == `FUNCT3_CSRRW ) & (w_opcode_7 == `OP_SYSTEM);
    assign w_instCSRRS_1    = (w_funct_3 == `FUNCT3_CSRRS ) & (w_opcode_7 == `OP_SYSTEM);
    assign w_instCSRRC_1    = (w_funct_3 == `FUNCT3_CSRRC ) & (w_opcode_7 == `OP_SYSTEM);
    assign w_intsCSRRWI_1   = (w_funct_3 == `FUNCT3_CSRRWI) & (w_opcode_7 == `OP_SYSTEM);
    assign w_instCSRRSI_1   = (w_funct_3 == `FUNCT3_CSRRSI) & (w_opcode_7 == `OP_SYSTEM);
    assign w_instCSRRCI_1   = (w_funct_3 == `FUNCT3_CSRRCI) & (w_opcode_7 == `OP_SYSTEM);

//-----{指令译码}end


    assign o_IllegalInsSecond_1 = ~( w_instADD_1 | w_instSUB_1 | w_instSLL_1 | w_instSLT_1 | w_instSLTU_1 | w_instXOR_1 
                                 | w_instSRL_1 | w_instSRA_1 | w_instOR_1  | w_instAND_1 
                                 | w_instADDI_1 | w_instSLTI_1 | w_instSLTIU_1 | w_instXORI_1 | w_instORI_1 | w_instANDI_1 
                                 | w_instSLLI_1 | w_instSRLI_1 | w_instSRAI_1 
                                 | w_instLB_1 |  w_instLH_1 | w_instLW_1 | w_instLBU_1 | w_instLHU_1 
                                 | w_instLUI_1 | w_instAUIPC_1 | w_instSB_1 | w_instSH_1 | w_instSW_1 
                                 | w_instJAL_1 | w_instJALR_1 
                                 | w_instMUL_1 | w_instMULH_1 | w_instMULHSU_1 | w_instMULHU_1 | w_instDIV_1 
                                 | w_instDIVU_1 | w_instREM_1 | w_instREMU_1 
                                 | w_instCSRRW_1 | w_instCSRRS_1 | w_instCSRRC_1 | w_intsCSRRWI_1 | w_instCSRRSI_1 | w_instCSRRCI_1 
                                 | (w_inst_32 == `nop)); //非法指令使能
                                 

//-----{指令分类}begin

    // ALU 操作分类
    wire w_add_1, w_sub_1, w_slt_1, w_sltu_1;
    wire w_and_1, w_or_1 , w_xor_1, w_sll_1 ;
    wire w_srl_1, w_sra_1, w_lui_1          ;

    assign w_add_1 =  w_instADDI_1  | w_instADD_1   | w_instLB_1            // 加法
                    | w_instLH_1    | w_instLW_1    | w_instLBU_1
                    | w_instLHU_1   | w_instSB_1    | w_instSH_1
                    | w_instSW_1    | w_instAUIPC_1 | w_instJAL_1
                    | w_instJALR_1   ;
    assign w_sub_1  = w_instSUB_1                 ;                         // 减法
    assign w_slt_1  = w_instSLT_1   | w_instSLTI_1 ;                        // 有符号小于置位
    assign w_sltu_1 = w_instSLTU_1  | w_instSLTIU_1;                        // 无符号小于置位
    assign w_and_1  = w_instAND_1   | w_instANDI_1
                    | w_instCSRRC_1 | w_instCSRRCI_1;                       // 逻辑与
    assign w_or_1   = w_instOR_1    | w_instORI_1
                    | w_instCSRRS_1 | w_instCSRRSI_1    ;                   // 逻辑或
    assign w_xor_1  = w_instXOR_1   | w_instXORI_1 ;                        // 逻辑异或
    assign w_sll_1  = w_instSLL_1   | w_instSLLI_1 ;                        // 逻辑左移
    assign w_srl_1  = w_instSRL_1   | w_instSRLI_1 ;                        // 逻辑右移
    assign w_sra_1  = w_instSRA_1   | w_instSRAI_1 ;                        // 算术右移
    assign w_lui_1  = w_instLUI_1   | w_instCSRRW_1 | w_intsCSRRWI_1;       // 高位加载

    // 根据指令类型进行分类

    wire w_RType_1;     // R-type
    wire w_IType_1;     // I-type
    wire w_SType_1;     // S-type
    wire w_UType_1;     // U-type
    wire w_CSRType_1;   // CSR指令
    wire w_JType_1;     // J-type
    wire w_RV32M_1;
    
    assign w_RV32M_1        =  w_instMUL_1  | w_instMULH_1  
                            | w_instMULHSU_1| w_instMULHU_1 | w_instDIV_1   
                            | w_instDIVU_1  | w_instREM_1   | w_instREMU_1 ; //fix bug
    assign w_RType_1        = w_instADD_1   | w_instSUB_1
                            | w_instSLL_1   | w_instSLT_1   | w_instSLTU_1
                            | w_instXOR_1   | w_instSRL_1   | w_instSRA_1
                            | w_instOR_1    | w_instAND_1   | w_RV32M_1;

    assign w_IType_1        = w_instLB_1    | w_instLH_1    | w_instLW_1
                            | w_instLBU_1   | w_instLHU_1   | w_instADDI_1
                            | w_instSLTI_1  | w_instSLTIU_1 | w_instXORI_1
                            | w_instORI_1   | w_instANDI_1  | w_instSLLI_1
                            | w_instSRLI_1  | w_instSRAI_1;

    assign w_SType_1        = w_instSB_1    | w_instSH_1    | w_instSW_1;

    assign w_UType_1        = w_lui_1       | w_instAUIPC_1 ;

    assign w_JType_1        = w_instJAL_1   | w_instJALR_1  ;

    assign w_CSRType_1      = w_instCSRRC_1 |w_instCSRRCI_1 | w_instCSRRW_1
                            | w_intsCSRRWI_1|w_instCSRRS_1  | w_instCSRRSI_1;
                            
    //                        
    

    // 根据指令组成进行分类

    wire w_rs1Exist_1;      // rs1存在
    wire w_rs2Exist_1;      // rs2存在
    wire w_rdExist_1;       // rd存在
    wire w_immExist_1;      // imm存在

    assign w_rs1Exist_1    = w_RType_1  | w_IType_1  | w_SType_1;

    assign w_rs2Exist_1    = w_RType_1;
	
    assign w_rdExist_1     = w_RType_1  | w_IType_1  | w_UType_1 | w_JType_1 |w_CSRType_1;

    assign w_immExist_1    = w_IType_1  | w_SType_1  | w_UType_1 | w_JType_1;

    wire w_rs1use_1,w_rs2use_1,w_rduse_1;
    assign w_rs1use_1 = ~(o_IllegalInsSecond_1 | w_instLUI_1 | w_instAUIPC_1 | w_JType_1 );
    assign w_rs2use_1 =  w_RType_1 | w_SType_1;
    assign w_rduse_1  =  w_RType_1 | w_IType_1 | w_UType_1 | w_CSRType_1 | w_JType_1 ;
    // 乘除法相关分类
    wire        w_mulquorem;
    wire        w_mulLow_1;             // 低位乘积
    wire        w_mulHigh_1;            // 高位乘积
    wire        w_quo_1;                // 求商
    wire        w_remainder_1;          // 取余

    assign w_mulLow_1       = w_instMUL_1;
    assign w_mulHigh_1      = w_instMULH_1  | w_instMULHU_1 | w_instMULHSU_1;

    assign w_quo_1          = w_instDIV_1   | w_instDIVU_1;
    assign w_remainder_1    = w_instREM_1   | w_instREMU_1;

    assign w_mulquorem = w_mulLow_1 | w_mulHigh_1 | w_quo_1 | w_remainder_1; //lzc


    // LoadStore相关分类
    wire [ 1:0] w_loadStoreWidth_2;     // 读写宽度标志
    wire        w_load_1 ;              // 读指令
    wire        w_store_1;              // 写指令
    wire        w_loadSign_1;           // Load拓展方式
    wire        w_widthB_1;             // 字节读写
    wire        w_widthH_1;             // 半字读写
    wire        w_widthW_1;             // 字长读写

    assign w_load_1         = w_instLB_1 | w_instLH_1 | w_instLW_1 | w_instLBU_1 | w_instLHU_1;
    assign w_store_1        = w_instSB_1 | w_instSH_1 | w_instSW_1 ;

    assign w_loadSign_1     = ~(w_instLBU_1 | w_instLHU_1);

    assign w_widthB_1       = w_instLB_1 | w_instLBU_1 | w_instSB_1;

    assign w_widthH_1       = w_instLH_1 | w_instLHU_1 | w_instSH_1;

    assign w_widthW_1       = w_instLW_1 | w_instSW_1;

    assign w_loadStoreWidth_2   = {{2{w_widthB_1}} & 2'b01}
                                | {{2{w_widthH_1}} & 2'b10}
                                | {{2{w_widthW_1}} & 2'b11};

    // 其他分类
    wire w_operand1PC_1;    // 第一操作数为PC的指�????

    assign w_operand1PC_1   = w_JType_1 | w_instAUIPC_1;

//-----{指令分类}end

//-----{输出信号生成}begin

    // ALU两个源操作数和控制信号
    wire [ 1:0] w_mulDivSign_2;         // 乘除法符号标志
    wire [ 4:0] w_rdValue_5;            // 目的寄存器地址
    wire [31:0] w_imm_32;               // 立即数
    wire [31:0] w_csrOper2_32;          // csr指令操作数
    wire [10:0] w_aluControl_11;        // alu控制
    wire [31:0] w_aluOperand1_32;       // alu操作数1
    wire [31:0] w_aluOperand2_32;       // alu操作数2
	wire 		w_grfWen_1;

    assign w_mulDivSign_2       = {{2{w_instMULH_1   }} & 2'b10}
                                | {{2{w_instMULHU_1  }} & 2'b00}
                                | {{2{w_instMULHSU_1 }} & 2'b00}
                                | {{2{w_instMUL_1    }} & 2'b10}
                                | {{2{w_instDIV_1    }} & 2'b01}
                                | {{2{w_instDIVU_1   }} & 2'b00}
                                | {{2{w_instREM_1    }} & 2'b01}
                                | {{2{w_instREMU_1   }} & 2'b00};

    assign w_rdValue_5          = {{5{w_rdExist_1}} & w_rd_5};

    assign w_csrOper2_32        = {{32{w_instCSRRW_1 | w_instCSRRS_1}} & w_rs1Value_32  }
                                | {{32{w_instCSRRC_1                }} & ~w_rs1Value_32 }
                                | {{32{w_intsCSRRWI_1|w_instCSRRSI_1}} & {27'b0,w_rs1_5}}
                                | {{32{w_instCSRRCI_1               }} &~{27'b0,w_rs1_5}};

    assign w_aluControl_11       = {w_add_1 ,        // ALU操作码，独热编码
                                    w_sub_1 ,
                                    w_slt_1 ,
                                    w_sltu_1,
                                    w_and_1 ,
                                    w_or_1  ,
                                    w_xor_1 ,
                                    w_sll_1 ,
                                    w_srl_1 ,
                                    w_sra_1 ,
                                    w_lui_1  };

    assign w_aluOperand1_32     = {{32{ w_operand1PC_1  }} &  w_PC_32   }
                                | {{32{ w_CSRType_1     }} &  i_csrValue_32 }
                                | {{32{~(w_operand1PC_1 | w_CSRType_1)     }} &  w_rs1Value_32 };

    assign w_aluOperand2_32     = {{32{ w_rs2Exist_1    }} &  w_rs2Value_32 }
                                | {{32{ w_immExist_1    }} &  w_imm_32      }
				| {{32{ w_CSRType_1     }} &  w_csrOper2_32 };

    assign w_imm_32             = {{32{w_IType_1    }} & {{20{w_inst_32[31]}},  w_imm_12            }}
                                | {{32{w_SType_1    }} & {{20{w_inst_32[31]}}, {w_imm_7, w_imm_5   }}}
                                | {{32{w_instLUI_1  }} & {    w_imm_20, 12'd0                       }}
                                | {{32{w_instAUIPC_1}} & {    w_imm_20, 12'd0                       }}
								| {{32{w_JType_1    }} & {    32'd4									}};
                                /*| {{32{w_JType_1    }} & {{{32{ i_RV32C_1}} & 32'd2 }
                                                        | {{32{~i_RV32C_1}} & 32'd4 }               }};*/

    assign w_grfWen_1           = w_RType_1  | w_UType_1 | w_JType_1 | w_instADDI_1
								| w_instSLTI_1  | w_instSLTIU_1 | w_instXORI_1
								| w_instORI_1   | w_instANDI_1  | w_instSLLI_1
								| w_instSRLI_1  | w_instSRAI_1 | w_CSRType_1 | w_load_1;     //////////////////////////////
    wire [31:0] w_storeData_32;
    assign w_storeData_32           = w_CSRType_1 ?  i_csrValue_32 : w_rs2Value_32 ;  
    assign o_DecoderExeBus_191  = {
									w_storeData_32,//jump
									w_grfWen_1,//wb
                                    w_aluControl_11,//alu
                                    w_aluOperand1_32,
                                    w_aluOperand2_32,//alu
                                    w_mulLow_1,//*/
                                    w_mulHigh_1,
                                    w_quo_1,
                                    w_remainder_1,//*/
                                    w_mulDivSign_2,//*/符号
                                    w_rdValue_5,//wb
                                    w_load_1,////load store
                                    w_store_1,
                                    w_loadSign_1,
                                    w_loadStoreWidth_2,////load store
                                    w_CSRType_1,//csr
                                    w_mulquorem,//*/
                                    w_PC_32,
                                    w_inst_32,
				    w_instMULHSU_1
                                                    };
	
	assign   o_secondtohazard_19 = { w_rs1_5 ,
	                                 w_rs2_5 ,
	                                 w_rs1use_1,
	                                 w_rs2use_1,
	                                 w_rd_5  ,
	                                 w_rduse_1 ,
	                                 w_load_1
	                                 };
	                                 
	                                 
    assign o_csrAddr_12   = {12{w_CSRType_1}} & w_csrAddr_12;
//-----{输出信号生成}end

endmodule
