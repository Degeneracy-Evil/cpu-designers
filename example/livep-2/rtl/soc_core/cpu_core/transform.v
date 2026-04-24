module transform(
    input [31:0]i_num1,
    input [31:0]i_num2,
    input i_sign,
    output [31:0] num1,
    output [31:0] num2,
    output sign
    );
    assign sign=i_num1[31]^i_num2[31];
    assign num1[30:0]=(i_sign&&i_num1[31]==1)?(~(i_num1[30:0])+1):i_num1[30:0];
    assign num2[30:0]=(i_sign&&i_num2[31]==1)?(~(i_num2[30:0])+1):i_num2[30:0];
    assign num1[31]=(i_sign)?0:i_num1[31];
    assign num2[31]=(i_sign)?0:i_num2[31];
endmodule
