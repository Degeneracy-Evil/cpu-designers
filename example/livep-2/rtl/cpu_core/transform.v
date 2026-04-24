module transform(
    input [31:0]i_num1_32,
    input [31:0]i_num2_32,
    input i_sign_1,
    output [31:0] o_num1_32,
    output [31:0] o_num2_32,
    output o_sign_1
    );
    assign o_sign_1=i_num1_32[31]^i_num2_32[31];   //通过两个输入数据的高位确定符号位
    assign o_num1_32[30:0]=(i_sign_1&&i_num1_32[31]==1)?(~(i_num1_32[30:0])+1):i_num1_32[30:0];     //通过最高位以及是否进行符号运算来决定是否进行取反加一
    assign o_num2_32[30:0]=(i_sign_1&&i_num2_32[31]==1)?(~(i_num2_32[30:0])+1):i_num2_32[30:0];
    assign o_num1_32[31]=(i_sign_1)?0:i_num1_32[31];      //当进行符号位运算时，默认运算数的最高位为0，当成无符号数运算，最后确认符号位
    assign o_num2_32[31]=(i_sign_1)?0:i_num2_32[31];
endmodule
