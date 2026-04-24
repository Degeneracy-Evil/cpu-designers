`timescale 1ns / 1ps
`include "./riscv.h"
module m_exe(                                // 鎵ц妯″潡

    input  wire         clk,                 // 鏃堕挓
    input  wire         rstn,                // 閲嶇疆
    
    input  wire [190:0] i_DecoderExeBus_191, // ID->EXE鎬荤嚎
    output wire [138:0] o_ExeLsuBus_139,     // EXE->MEM鎬荤嚎
    output wire         o_csrWen_1,
	output wire  [ 4:0] o_rdAddr_5,
	output wire [ 31:0] o_csrWdata_32,
    output wire         o_muldivHold_1,       // 涔橀櫎娉曟祦姘寸嚎鏆傚仠
    output wire [31:0]  o_exeResult_32   
);

//-----{IDEXE鎬荤嚎}begin

    //EXE瑕佺敤鍒扮殑淇℃伅
    wire        w_mulLow_1;                        // 涔樻硶浣庝綅
    wire        w_mulHigh_1;                       // 涔樻硶楂樹綅
    wire        w_quo_1;                           // 闄ゆ硶
    wire        w_remainder_1;                     // 鍙栦綑
    wire [ 4:0] w_rdValue_5;                       // 浠巇ecoder杈撳叆鐨勭洰鐨勫瘎瀛樺櫒鍦板潃
    wire        w_load_1;                          // 璇绘寚浠�
    wire        w_store_1;                         // 鍐欐寚浠�
    wire        w_loadSign_1;                      // 璇绘寚浠ょ鍙�
    wire [ 1:0] w_loadStoreWidth_2;                // 璇诲啓瀛楅暱
    wire        w_CSRTYpe_1;                       // CSR鎸囦护
    wire [11:0] w_csrAddr_12;                      // CSR鍦板潃
    wire [ 1:0] w_mulDivSign_2;                    // 涔橀櫎娉曠鍙锋儏鍐�
    wire [10:0] w_aluControl_11;                   // ALU鎺у埗鎬荤嚎
    wire [31:0] w_aluOperand1_32;                  // ALU鎿嶄綔鏁�1
    wire [31:0] w_aluOperand2_32;                  // ALU鎿嶄綔鏁�2
    wire        w_MulDiv_1;
	wire        w_grfWen_1;
	wire [31:0] w_storeData_32;  
	wire [31:0]  w_PC_32;
	wire [31:0]  w_inst_32;
	
    wire        w_instMULHSU_1 ;
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
            w_inst_32,
	    w_instMULHSU_1
                            }   = i_DecoderExeBus_191;

//-----{ID->EXE鎬荤嚎}end

//-----{ALU}begin

    wire [31:0] w_aluResult_32;                     // alu杈撳嚭

    m_alu alu(
        .i_aluControl_11    (w_aluControl_11    ),  // ALU鎺у埗淇″彿
        .i_aluOperand1_32   (w_aluOperand1_32   ),  // ALU鎿嶄綔鏁�1
        .i_aluOperand2_32   (w_aluOperand2_32   ),  // ALU鎿嶄綔鏁�2
        .o_aluResult_32     (w_aluResult_32     )   // ALU缁撴灉
    );

//-----{ALU}end

//-----{涔樻硶鍣▆begin

    wire        w_mulBegin_1;                           // 涔樻硶寮�濮嬩俊鍙�
    wire [63:0] w_product_64;                           // 涔樼Н
    wire        w_mulWorking_1;                         // 涔樻硶宸ヤ綔淇″彿
    wire        w_mulEnd_1;                             // 涔樻硶缁撴潫淇″彿
    wire        mul_sign,div_sign;
    assign   mul_sign = w_mulDivSign_2[1];
    assign   div_sign = w_mulDivSign_2[0];

    assign w_mulBegin_1 =  w_mulLow_1  | w_mulHigh_1;   // 涔樻硶寮�濮嬩俊鍙风敓鎴�
    
    mul multiply(
        .clk               (clk                ),      // 鏃堕挓
        .rst               (rstn               ),
        .i_mulStart_1          (w_mulBegin_1       ),      // 涔樻硶寮�濮嬩俊鍙�
        .i_mulSign_1           (mul_sign           ),      // 涔樻硶鎿嶄綔鏁�1
        .i_mulNum1_32         (w_aluOperand1_32   ),      // 涔樻硶鎿嶄綔鏁�2    w_mulDivSign_2
        .i_mulNum2_32         (w_aluOperand2_32   ),      // 涔樻硶绗﹀彿
        .o_mulNum_64         (w_product_64       ),  
        .i_mulMix_1            (w_instMULHSU_1     ),    // 涔樼Н
        .o_mulEnd_1            (w_mulEnd_1         )       // 涔樻硶缁撴潫淇″彿
    );
    assign w_mulWorking_1 = w_mulEnd_1;
//-----{涔樻硶鍣▆end

//-----{闄ゆ硶鍣▆begin

    wire        w_divBegin_1;                           // 闄ゆ硶寮�濮嬩俊鍙�
    wire [31:0] w_quotient_32;                          // 鍟�
    wire [31:0] w_remainder_32;                         // 浣欐暟
    wire        w_divWorking_1;                         // 闄ゆ硶宸ヤ綔淇″彿
    wire        w_divEnd_1;                             // 闄ゆ硶缁撴潫淇″彿

    assign w_divBegin_1 =   w_quo_1 | w_remainder_1;    // 闄ゆ硶寮�濮嬩俊鍙风敓鎴�
    div_radix16 division (
        .clk                (clk                ),      // 鏃堕挓
        .rst                (rstn               ),
        .i_divStart_1           (w_divBegin_1       ),      // 闄ゆ硶寮�濮嬩俊鍙�
        .i_divSign_1            (div_sign           ),      // 闄ゆ硶绗﹀彿
        .i_dividend_32         (w_aluOperand1_32   ),      // 琚櫎鏁�
        .i_divisor_32          (w_aluOperand2_32   ),      // 闄ゆ暟
        .o_quotient_32           (w_quotient_32      ),      // 鍟�
        .o_remainder_32          (w_remainder_32     ),      // 浣欐暟
        .o_done_1               (w_divEnd_1         ),      // 闄ゆ硶缁撴潫淇″彿
        .o_busy_1               (w_divWorking_1     )     // 闄ゆ硶宸ヤ綔淇″彿
    );





		assign o_muldivHold_1 = w_MulDiv_1 & (~(w_divEnd_1 | w_mulEnd_1));

//-----{EXE妯″潡鐨刣est鍊紏begin
   //鍙湁鍦‥XE妯″潡鏈夋晥鏃讹紝鍏跺啓鍥炵洰鐨勫瘎瀛樺櫒鍙锋墠鏈夋剰涔�
    wire [4:0] w_rdAddr_5;

    assign w_rdAddr_5      = w_rdValue_5   & {5{ w_divEnd_1}};

//-----{EXE妯″潡鐨刣est鍊紏end

//-----{EXE->MEM鎬荤嚎}begin

    wire [31:0] w_exeResult_32;     // exe妯″潡鏈�鍚庤緭鍑�

    assign w_exeResult_32   = {{32{w_mulHigh_1                      }}  & w_product_64[63:32]   }
                            | {{32{w_mulLow_1                       }}  & w_product_64[31: 0]   }
                            | {{32{w_quo_1                          }}  & w_quotient_32         }
                            | {{32{w_remainder_1                    }}  & w_remainder_32        }
                            | {{32{|w_aluControl_11                 }}  & w_aluResult_32        };
                            
     assign o_exeResult_32   =  w_CSRTYpe_1 ? w_storeData_32 : w_exeResult_32;                          
  

    assign o_ExeLsuBus_139   = {
                                w_load_1,
                                w_store_1,
                                w_loadSign_1,
								w_grfWen_1,
                                w_loadStoreWidth_2,
                                o_exeResult_32,
								w_storeData_32,//rs2
                                w_rdValue_5,
                                w_PC_32,
                                w_inst_32
							  };

//-----{EXE->MEM鎬荤嚎}end
	assign o_csrWen_1     = w_CSRTYpe_1;
	assign o_rdAddr_5     = w_rdAddr_5;
	assign o_csrWdata_32  = {32{w_CSRTYpe_1}} & w_exeResult_32;
	
endmodule

