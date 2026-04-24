
`timescale 1ns / 1ps
`include "riscv.h"
module m_alu (
    input  wire [10:0] i_aluControl_11,
    input  wire [31:0] i_aluOperand1_32,
    input  wire [31:0] i_aluOperand2_32,
    output wire [31:0] o_aluResult_32
);

//-----{aluControl解码}begin

    wire w_add_1;                               // 加法操作
    wire w_sub_1;                               // 减法操作
    wire w_slt_1;                               // 小于置位操作
    wire w_sltu_1;                              // 无符号小于置位操作
    wire w_and_1;                               // 与操作
    wire w_or_1;                                // 或操作
    wire w_xor_1;                               // 异或操作
    wire w_sll_1;                               // 逻辑左移操作
    wire w_srl_1;                               // 逻辑右移操作
    wire w_sra_1;                               // 算术右移操作
    wire w_lui_1;                               // 高位加载操作

    assign w_add_1  = i_aluControl_11[10];
    assign w_sub_1  = i_aluControl_11[ 9];
    assign w_slt_1  = i_aluControl_11[ 8];
    assign w_sltu_1 = i_aluControl_11[ 7];
    assign w_and_1  = i_aluControl_11[ 6];
    assign w_or_1   = i_aluControl_11[ 5];
    assign w_xor_1  = i_aluControl_11[ 4];
    assign w_sll_1  = i_aluControl_11[ 3];
    assign w_srl_1  = i_aluControl_11[ 2];
    assign w_sra_1  = i_aluControl_11[ 1];
    assign w_lui_1  = i_aluControl_11[ 0];

//-----{aluControl解码}end

    wire [31:0] w_addSubResult_32; //这部分放到前面，先声明后使用~
    wire [31:0] w_sltResult_32;
    wire [31:0] w_sltuResult_32;
    wire [31:0] w_andResult_32;
    wire [31:0] w_orResult_32;
    wire [31:0] w_xorResult_32;
    wire [31:0] w_sllResult_32;
    wire [31:0] w_srlResult_32;
    wire [31:0] w_sraResult_32;
    wire [31:0] w_luiResult_32;

    assign w_andResult_32   = i_aluOperand1_32 & i_aluOperand2_32;          // 与运算
    assign w_orResult_32    = i_aluOperand1_32 | i_aluOperand2_32;          // 或运算
    assign w_xorResult_32   = i_aluOperand1_32 ^ i_aluOperand2_32;          // 异或运算
    assign w_luiResult_32   = i_aluOperand2_32;                             // lui执行


//-----{加法器}begin
//add,sub,slt,sltu均使用该模块
    wire [31:0] w_adderOperand1_32;                                         // 加法操作数1
    wire [31:0] w_adderOperand2_32;                                         // 加法操作数2
    wire        w_adderCin_1;                                               // 加法进位输入
    wire [32:0] w_adderResult_33;                                           // 加法结果
    wire        w_adderCout_1;                                              // 加法进位输出
    assign w_adderOperand1_32   = i_aluOperand1_32;
    assign w_adderOperand2_32   = w_add_1   ?  i_aluOperand2_32
                                            : ~i_aluOperand2_32;
    assign w_adderCin_1         = ~w_add_1;
    assign w_adderResult_33     = w_adderOperand1_32 + w_adderOperand2_32 + w_adderCin_1;
    assign w_adderCout_1        = w_adderResult_33[32];

    //加减结果
    assign w_addSubResult_32    = w_adderResult_33[31:0];

   
    assign w_sltResult_32[31:1] = 31'd0;
    assign w_sltResult_32[0]    = (  i_aluOperand1_32[31] & ~i_aluOperand2_32[31])
                                | (~(i_aluOperand1_32[31] ^  i_aluOperand2_32[31])
                                &   w_addSubResult_32[31]                        );

    assign w_sltuResult_32  = {31'd0,~w_adderCout_1};

//-----{加法器}end

//-----{移位器}begin

    // 逻辑左移
    assign w_sllResult_32   =($unsigned(i_aluOperand1_32)) << i_aluOperand2_32[4:0]; //fix bug,两个操作数位置反了，srai等指令特殊要求未完成

    // 逻辑右移
    assign w_srlResult_32   =($unsigned(i_aluOperand1_32)) >> i_aluOperand2_32[4:0];

    // 算数右移
    assign w_sraResult_32   =(($signed(i_aluOperand1_32)) >>> i_aluOperand2_32[4:0]);


//-----{移位器}end

//-----{alu输出结果生成}begin

    assign o_aluResult_32   = {{32{w_add_1 | w_sub_1}}  & w_addSubResult_32 }   // 输出加减法结果
                            | {{32{w_slt_1          }}  & w_sltResult_32    }   // 输出小于置位结果
                            | {{32{w_sltu_1         }}  & w_sltuResult_32   }   // 输出无符号小于置位结果
                            | {{32{w_and_1          }}  & w_andResult_32    }   // 输出与结果
                            | {{32{w_or_1           }}  & w_orResult_32     }   // 输出或结果
                            | {{32{w_xor_1          }}  & w_xorResult_32    }   // 输出异或结果
                            | {{32{w_sll_1          }}  & w_sllResult_32    }   // 输出逻辑左移结果
                            | {{32{w_srl_1          }}  & w_srlResult_32    }   // 输出逻辑右移结果
                            | {{32{w_sra_1          }}  & w_sraResult_32    }   // 输出算数右移结果
                            | {{32{w_lui_1          }}  & w_luiResult_32    };  //添加输出 lui结果 

//-----{alu输出结果生成}begin
endmodule
