//-----------------------------------------------
//    module name: m_exe
//    author: Wei Ren
//  
//    version: 1st version (2021-10-01)
//    description: 实例化alu模块、乘法模块�?�除法模块，输出目的寄存器地�??、CSR数据、乘除法流水线暂停信号以及�?�往存储器的总线数据�??
//                 总线数据包中包括寄存器数据�?�alu操作数�?�GRF写使能�?�store标志、读写宽度标志�?�读指令符号、执行模块结果�?�load标志、CSR指令标志
//
//
//-----------------------------------------------
`timescale 1ns / 1ps
`include "./riscv.h"
module m_exe(                                // 执行模块
    input  wire         clk,                 // 时钟
    input  wire         rstn,                // 重置    
    input  wire [189:0] i_DecoderExeBus_190, // ID->EXE总线
    output wire [138:0] o_ExeLsuBus_139,     // EXE->MEM总线
    output wire         o_csrWen_1,
	output wire  [ 4:0] o_rdAddr_5,
	output wire [ 31:0] o_csrWdata_32,
    output wire         o_muldivHold_1,      // 乘除法流水线暂� 
    output wire [31:0]  o_exeResult_32   
);
//-----{IDEXE总线}begin

    //EXE�??要用到的信息
    wire        w_mulLow_1;                        // 乘法低位
    wire        w_mulHigh_1;                       // 乘法高位
    wire        w_quo_1;                           // 除法
    wire        w_remainder_1;                     // 取余
    wire [ 4:0] w_rdValue_5;                       // 从decoder输入的目的寄存器地址
    wire        w_load_1;                          // 读指�??
    wire        w_store_1;                         // 写指�??
    wire        w_loadSign_1;                      // 读指令符�??
    wire [ 1:0] w_loadStoreWidth_2;                // 读写字长
    wire        w_CSRTYpe_1;                       // CSR指令
    wire [11:0] w_csrAddr_12;                      // CSR地址
    wire [ 1:0] w_mulDivSign_2;                    // 乘除法符号情�??
    wire [10:0] w_aluControl_11;                   // ALU控制总线
    wire [31:0] w_aluOperand1_32;                  // ALU操作�??1
    wire [31:0] w_aluOperand2_32;                  // ALU操作�??2
    wire        w_MulDiv_1;
	wire        w_grfWen_1;
	wire [31:0] w_storeData_32;  
	wire [31:0]  w_PC_32;
	wire [31:0]  w_inst_32;
    assign  {
			w_storeData_32,//rs2
			w_grfWen_1,
            w_aluControl_11,
            w_aluOperand1_32,
            w_aluOperand2_32,
            w_mulLow_1,
            w_mulHigh_1,
            w_quo_1,
            w_remainder_1,
            w_mulDivSign_2,
            w_rdValue_5,
            w_load_1,
            w_store_1,
            w_loadSign_1,
            w_loadStoreWidth_2,
            w_CSRTYpe_1,
            w_MulDiv_1,
            w_PC_32,
            w_inst_32 }   = i_DecoderExeBus_190;

//-----{ID->EXE总线}end

//-----{ALU}begin

    wire [31:0] w_aluResult_32;                  // alu输出

    m_alu alu(
        .i_aluControl_11    (w_aluControl_11),   // ALU控制信号
        .i_aluOperand1_32   (w_aluOperand1_32),  // ALU操作�??1
        .i_aluOperand2_32   (w_aluOperand2_32),  // ALU操作�??2
        .o_aluResult_32     (w_aluResult_32)     // ALU结果
    );

//-----{ALU}end

//-----{乘法器}begin

    wire        w_mulBegin_1;                           // 乘法�??始信�??
    wire [63:0] w_product_64;                           // 乘积
    wire        w_mulWorking_1;                         // 乘法工作信号
    wire        w_mulEnd_1;                             // 乘法结束信号
    wire        mul_sign,div_sign;
    
    assign   mul_sign = w_mulDivSign_2[1];
    assign   div_sign = w_mulDivSign_2[0];
    assign w_mulBegin_1 =  w_mulLow_1  | w_mulHigh_1;   // 乘法�??始信号生�??
    
    mul multiply(
        .clk       (clk),               // 时钟
        .rst       (rstn),
       .mul_start  (w_mulBegin_1),      // 乘法�??始信�??
        .mul_sign  (mul_sign),          // 乘法操作�??1
        .i_mulNum1 (w_aluOperand1_32),  // 乘法操作�??2    w_mulDivSign_2
        .i_mulNum2 (w_aluOperand2_32),  // 乘法符号
        .o_mulNum  (w_product_64),      // 乘积
        .mul_end   (w_mulEnd_1)         // 乘法结束信号
    );
    
    assign w_mulWorking_1 = w_mulEnd_1;
//-----{乘法器}end

//-----{除法器}begin

    wire        w_divBegin_1;                           // 除法�??始信�??
    wire [31:0] w_quotient_32;                          // �??
    wire [31:0] w_remainder_32;                         // 余数
    wire        w_divWorking_1;                         // 除法工作信号
    wire        w_divEnd_1;                             // 除法结束信号

    assign w_divBegin_1 =   w_quo_1 | w_remainder_1;    // 除法�??始信号生�??
    
    div_radix16 division (
        .clk                (clk                ),      // 时钟
        .rst                (rstn               ),
        .en                 (w_divBegin_1       ),      // 除法�??始信�??
        .signed_div         (div_sign           ),      // 除法符号
        .i_dividend         (w_aluOperand1_32   ),      // 被除�??
        .i_divisor          (w_aluOperand2_32   ),      // 除数
        .quotient           (w_quotient_32      ),      // �??
        .remainder          (w_remainder_32     ),      // 余数
        .done               (w_divEnd_1         ),      // 除法结束信号
        .busy               (w_divWorking_1     )     // 除法工作信号
    );
    
		assign o_muldivHold_1 = w_MulDiv_1 & (~(w_divEnd_1 & w_mulEnd_1));

//-----{EXE模块的dest值}begin
   //只有在EXE模块有效时，其写回目的寄存器号才有意�??
    wire [4:0] w_rdAddr_5;

    assign w_rdAddr_5      = w_rdValue_5   & {5{ w_divEnd_1}};

//-----{EXE模块的dest值}end

//-----{EXE->MEM总线}begin

    wire [31:0] w_exeResult_32;     // exe模块�??终输�??

    assign w_exeResult_32   = {{32{w_mulHigh_1                      }}  & w_product_64[63:32]   }
                            | {{32{w_mulLow_1                       }}  & w_product_64[31: 0]   }
                            | {{32{w_quo_1                          }}  & w_quotient_32         }
                            | {{32{w_remainder_1                    }}  & w_remainder_32        }
                            | {{32{|w_aluControl_11                 }}  & w_aluResult_32        };                            
     assign o_exeResult_32   =  w_CSRTYpe_1 ? w_storeData_32 : w_exeResult_32;                          ////////////////////////////�Ĺ�
    assign o_ExeLsuBus_139   = {
                                w_load_1,
                                w_store_1,
                                w_loadSign_1,
								w_grfWen_1,
                                w_loadStoreWidth_2,
                                w_exeResult_32,
								w_storeData_32,//rs2
                                w_rdValue_5,
                                w_PC_32,
                                w_inst_32
							  };

//-----{EXE->MEM总线}end

	assign o_csrWen_1     = w_CSRTYpe_1;
	assign o_rdAddr_5     = w_rdAddr_5;
	assign o_csrWdata_32  = {32{w_CSRTYpe_1}} & w_exeResult_32;
	
endmodule

//得做个寄存器，在做乘除法的时候把非当前要求的结果存起来，如果下一条指令是那个的要求的话，直接送出结果并启动�??
