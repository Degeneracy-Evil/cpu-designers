//-----------------------------------------------
//    module name: m_alu
//    author: Wei Ren
//  
//    version: 1st version (2021-10-01)
//    description: 绠楁湳閫昏緫鍗曞厓锛屽疄鐜扮殑鍔熻兘鏈夊姞娉曟搷浣溿?佸噺娉曟搷浣溿?佸皬浜庣疆浣嶆搷浣溿?佹棤绗﹀彿灏忎簬缃綅鎿嶄綔銆?
//                 涓庢搷浣溿?佹垨鎿嶄綔銆佸紓鎴栨搷浣溿?侀?昏緫宸︾Щ鎿嶄綔銆侀?昏緫鍙崇Щ鎿嶄綔銆佺畻鏈彸绉绘搷浣溿?侀珮浣嶅姞杞芥搷浣?
//
//
//-----------------------------------------------
`timescale 1ns / 1ps
`include "riscv.h"
module m_alu (
    input  wire [10:0] i_aluControl_11,
    input  wire [31:0] i_aluOperand1_32,
    input  wire [31:0] i_aluOperand2_32,
    output wire [31:0] o_aluResult_32
);

//-----{aluControl瑙ｇ爜}begin

    wire w_add_1;                               // 鍔犳硶鎿嶄綔
    wire w_sub_1;                               // 鍑忔硶鎿嶄綔
    wire w_slt_1;                               // 灏忎簬缃綅鎿嶄綔
    wire w_sltu_1;                              // 鏃犵鍙峰皬浜庣疆浣嶆搷浣?
    wire w_and_1;                               // 涓庢搷浣?
    wire w_or_1;                                // 鎴栨搷浣?
    wire w_xor_1;                               // 寮傛垨鎿嶄綔
    wire w_sll_1;                               // 閫昏緫宸︾Щ鎿嶄綔
    wire w_srl_1;                               // 閫昏緫鍙崇Щ鎿嶄綔
    wire w_sra_1;                               // 绠楁湳鍙崇Щ鎿嶄綔
    wire w_lui_1;                               // 楂樹綅鍔犺浇鎿嶄綔

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

//-----{aluControl瑙ｇ爜}end

    wire [31:0] w_addSubResult_32; //杩欓儴鍒嗘斁鍒板墠闈紝鍏堝０鏄庡悗浣跨敤~
    wire [31:0] w_sltResult_32;
    wire [31:0] w_sltuResult_32;
    wire [31:0] w_andResult_32;
    wire [31:0] w_orResult_32;
    wire [31:0] w_xorResult_32;
    wire [31:0] w_sllResult_32;
    wire [31:0] w_srlResult_32;
    wire [31:0] w_sraResult_32;
    wire [31:0] w_luiResult_32;

    assign w_andResult_32   = i_aluOperand1_32 & i_aluOperand2_32;          // 涓庤繍绠?
    assign w_orResult_32    = i_aluOperand1_32 | i_aluOperand2_32;          // 鎴栬繍绠?
    assign w_xorResult_32   = i_aluOperand1_32 ^ i_aluOperand2_32;          // 寮傛垨杩愮畻
    assign w_luiResult_32   = i_aluOperand2_32;                             // lui鎵ц


//-----{鍔犳硶鍣▆begin
//add,sub,slt,sltu鍧囦娇鐢ㄨ妯″潡
    wire [31:0] w_adderOperand1_32;                                         // 鍔犳硶鎿嶄綔鏁?1
    wire [31:0] w_adderOperand2_32;                                         // 鍔犳硶鎿嶄綔鏁?2
    wire        w_adderCin_1;                                               // 鍔犳硶杩涗綅杈撳叆
    wire [32:0] w_adderResult_33;                                           // 鍔犳硶缁撴灉
    wire        w_adderCout_1;                                              // 鍔犳硶杩涗綅杈撳嚭
    assign w_adderOperand1_32   = i_aluOperand1_32;
    assign w_adderOperand2_32   = w_add_1   ?  i_aluOperand2_32
                                            : ~i_aluOperand2_32;
    assign w_adderCin_1         = ~w_add_1;
    assign w_adderResult_33     = w_adderOperand1_32 + w_adderOperand2_32 + w_adderCin_1;
    assign w_adderCout_1        = w_adderResult_33[32];

    //鍔犲噺缁撴灉
    assign w_addSubResult_32    = w_adderResult_33[31:0];

    //slt缁撴灉
    //adderOperand1[31] adderOperand2[31] adderResult[31]
    //       0             1                  X(0鎴?1)       "姝?-璐?"锛屾樉鐒跺皬浜庝笉鎴愮珛
    //       0             0                    1           鐩稿噺涓鸿礋锛岃鏄庡皬浜?
    //       0             0                    0           鐩稿噺涓烘锛岃鏄庝笉灏忎簬
    //       1             1                    1           鐩稿噺涓鸿礋锛岃鏄庡皬浜?
    //       1             1                    0           鐩稿噺涓烘锛岃鏄庝笉灏忎簬
    //       1             0                  X(0鎴?1)       "璐?-姝?"锛屾樉鐒跺皬浜庢垚绔?
    assign w_sltResult_32[31:1] = 31'd0;
    assign w_sltResult_32[0]    = (  i_aluOperand1_32[31] & ~i_aluOperand2_32[31])
                                | (~(i_aluOperand1_32[31] ^  i_aluOperand2_32[31])
                                &   w_addSubResult_32[31]                        );

    //sltu缁撴灉
    //瀵逛簬32浣嶆棤绗﹀彿鏁版瘮杈冿紝鐩稿綋浜?33浣嶆湁绗﹀彿鏁帮紙{1'b0,operand1}鍜寋1'b0,operand2}锛夌殑姣旇緝锛屾渶楂樹綅0涓虹鍙蜂綅
    //鏁咃紝鍙互鐢?33浣嶅姞娉曞櫒鏉ユ瘮杈冨ぇ灏忥紝闇?瑕佸{1'b0,operand2}鍙栧弽,鍗抽渶瑕亄1'b0,operand1}+{1'b1,~operand2}+cin
    // 浣嗘澶勭敤鐨勪负32浣嶅姞娉曞櫒锛屽彧鍋氫簡杩愮畻:   operand1   +    ~operand2   +cin
    //32浣嶅姞娉曠殑缁撴灉涓簕adderCout,adderSubResult},鍒?33浣嶅姞娉曠粨鏋滃簲璇ヤ负{adderCout+1'b1,adder_result}
    //瀵规瘮slt缁撴灉娉ㄩ噴锛岀煡閬擄紝姝ゆ椂鍒ゆ柇澶у皬灞炰簬绗簩涓夌鎯呭喌锛屽嵆婧愭搷浣滄暟1绗﹀彿浣嶄负0锛屾簮鎿嶄綔鏁?2绗﹀彿浣嶄负0
    //缁撴灉鐨勭鍙蜂綅涓?1锛岃鏄庡皬浜庯紝鍗砤dderCout+1'b1涓?2'b01锛屽嵆adderCout涓?0
    assign w_sltuResult_32  = {31'd0,~w_adderCout_1};

//-----{鍔犳硶鍣▆end

//-----{绉讳綅鍣▆begin

    // 閫昏緫宸︾Щ
    assign w_sllResult_32   =($unsigned(i_aluOperand1_32)) << i_aluOperand2_32[4:0]; //fix bug,涓や釜鎿嶄綔鏁颁綅缃弽浜嗭紝srai绛夋寚浠ょ壒娈婅姹傛湭瀹屾垚

    // 閫昏緫鍙崇Щ
    assign w_srlResult_32   =($unsigned(i_aluOperand1_32)) >> i_aluOperand2_32[4:0];

    // 绠楁暟鍙崇Щ
    assign w_sraResult_32   =(($signed(i_aluOperand1_32)) >>> i_aluOperand2_32[4:0]);


//-----{绉讳綅鍣▆end

//-----{alu杈撳嚭缁撴灉鐢熸垚}begin

    assign o_aluResult_32   = {{32{w_add_1 | w_sub_1}}  & w_addSubResult_32 }   // 杈撳嚭鍔犲噺娉曠粨鏋?
                            | {{32{w_slt_1          }}  & w_sltResult_32    }   // 杈撳嚭灏忎簬缃綅缁撴灉
                            | {{32{w_sltu_1         }}  & w_sltuResult_32   }   // 杈撳嚭鏃犵鍙峰皬浜庣疆浣嶇粨鏋?
                            | {{32{w_and_1          }}  & w_andResult_32    }   // 杈撳嚭涓庣粨鏋?
                            | {{32{w_or_1           }}  & w_orResult_32     }   // 杈撳嚭鎴栫粨鏋?
                            | {{32{w_xor_1          }}  & w_xorResult_32    }   // 杈撳嚭寮傛垨缁撴灉
                            | {{32{w_sll_1          }}  & w_sllResult_32    }   // 杈撳嚭閫昏緫宸︾Щ缁撴灉
                            | {{32{w_srl_1          }}  & w_srlResult_32    }   // 杈撳嚭閫昏緫鍙崇Щ缁撴灉
                            | {{32{w_sra_1          }}  & w_sraResult_32    }   // 杈撳嚭绠楁暟鍙崇Щ缁撴灉
                            | {{32{w_lui_1          }}  & w_luiResult_32    };  //娣诲姞杈撳嚭 lui缁撴灉 锛?12鏀逛负32锛宐y.lzc

//-----{alu杈撳嚭缁撴灉鐢熸垚}begin
endmodule
