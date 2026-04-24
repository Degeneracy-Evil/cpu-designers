module carry4to2(
 input clk,rst,en,
 input [63:0]i_num1_64,
 input [63:0]i_num2_64,
 input [63:0]i_num3_64,
 input [63:0]i_num4_64,
 output reg[63:0]o_sum_64,
 output reg[63:0]o_cout_64   
);
        
    //通过两次3压2得到4压2
    wire [63:0] sum1,temp_s,temp_q;
    wire [63:0] carry1;
    //第一次3压2得到一条进位链和一条和链
    carry3to2 csr1(
    .i_num1_64(i_num1_64),
    .i_num2_64(i_num2_64),
    .i_cin_64(i_num3_64),
    .o_sum_64(sum1),
    .o_cout_64(carry1)
    );
    //将第4个输入的部分积作为输入数1，将得到的和链作为输入2，将进位输出链作为进位输入再次压缩得到结果
    carry3to2 csr2(
    .i_num1_64(sum1),
    .i_num2_64(carry1),
    .i_cin_64(i_num4_64),
    .o_sum_64(temp_s),
    .o_cout_64(temp_q)
    );
    //通过使能信号判断是否得到压缩后的结果，为能达成乘法器的时序划分
    always@(*)begin
        if(~rst)begin
        o_sum_64=0;
        o_cout_64=0;
        end else begin
            if(en)begin
            o_sum_64=temp_s;
            o_cout_64=temp_q;
            end else begin
            o_sum_64=0;
            o_cout_64=0;
            end
        end
    
    end
endmodule

module carry3to2(
    input [63:0]i_num1_64,
    input [63:0]i_num2_64,
    input [63:0]i_cin_64,
    output [63:0] o_sum_64,
    output [63:0]o_cout_64
    );

    wire [63:0]temp;
    //对输入的三个数据的每一位进行压缩，得到和链以及进位链
    add2 add1(.i_num1_64(i_num1_64[0]), .i_num2_64(i_num2_64[0]), .i_cin_64(i_cin_64[0]), .o_sum_64(o_sum_64[0]), .o_cout_64(temp[0]));
    add2 add2(.i_num1_64(i_num1_64[1]), .i_num2_64(i_num2_64[1]), .i_cin_64(i_cin_64[1]), .o_sum_64(o_sum_64[1]), .o_cout_64(temp[1]));
    add2 add3(.i_num1_64(i_num1_64[2]), .i_num2_64(i_num2_64[2]), .i_cin_64(i_cin_64[2]), .o_sum_64(o_sum_64[2]), .o_cout_64(temp[2]));
    add2 add4(.i_num1_64(i_num1_64[3]), .i_num2_64(i_num2_64[3]), .i_cin_64(i_cin_64[3]), .o_sum_64(o_sum_64[3]), .o_cout_64(temp[3]));
    add2 add5(.i_num1_64(i_num1_64[4]), .i_num2_64(i_num2_64[4]), .i_cin_64(i_cin_64[4]), .o_sum_64(o_sum_64[4]), .o_cout_64(temp[4]));
    add2 add6(.i_num1_64(i_num1_64[5]), .i_num2_64(i_num2_64[5]), .i_cin_64(i_cin_64[5]), .o_sum_64(o_sum_64[5]), .o_cout_64(temp[5]));
    add2 add7(.i_num1_64(i_num1_64[6]), .i_num2_64(i_num2_64[6]), .i_cin_64(i_cin_64[6]), .o_sum_64(o_sum_64[6]), .o_cout_64(temp[6]));
    add2 add8(.i_num1_64(i_num1_64[7]), .i_num2_64(i_num2_64[7]), .i_cin_64(i_cin_64[7]), .o_sum_64(o_sum_64[7]), .o_cout_64(temp[7]));
    add2 add9(.i_num1_64(i_num1_64[8]), .i_num2_64(i_num2_64[8]), .i_cin_64(i_cin_64[8]), .o_sum_64(o_sum_64[8]), .o_cout_64(temp[8]));
    add2 add10(.i_num1_64(i_num1_64[9]), .i_num2_64(i_num2_64[9]), .i_cin_64(i_cin_64[9]), .o_sum_64(o_sum_64[9]), .o_cout_64(temp[9]));
    add2 add11(.i_num1_64(i_num1_64[10]), .i_num2_64(i_num2_64[10]), .i_cin_64(i_cin_64[10]), .o_sum_64(o_sum_64[10]), .o_cout_64(temp[10]));
    add2 add12(.i_num1_64(i_num1_64[11]), .i_num2_64(i_num2_64[11]), .i_cin_64(i_cin_64[11]), .o_sum_64(o_sum_64[11]), .o_cout_64(temp[11]));
    add2 add13(.i_num1_64(i_num1_64[12]), .i_num2_64(i_num2_64[12]), .i_cin_64(i_cin_64[12]), .o_sum_64(o_sum_64[12]), .o_cout_64(temp[12]));
    add2 add14(.i_num1_64(i_num1_64[13]), .i_num2_64(i_num2_64[13]), .i_cin_64(i_cin_64[13]), .o_sum_64(o_sum_64[13]), .o_cout_64(temp[13]));
    add2 add15(.i_num1_64(i_num1_64[14]), .i_num2_64(i_num2_64[14]), .i_cin_64(i_cin_64[14]), .o_sum_64(o_sum_64[14]), .o_cout_64(temp[14]));
    add2 add16(.i_num1_64(i_num1_64[15]), .i_num2_64(i_num2_64[15]), .i_cin_64(i_cin_64[15]), .o_sum_64(o_sum_64[15]), .o_cout_64(temp[15]));
    add2 add17(.i_num1_64(i_num1_64[16]), .i_num2_64(i_num2_64[16]), .i_cin_64(i_cin_64[16]), .o_sum_64(o_sum_64[16]), .o_cout_64(temp[16]));
    add2 add18(.i_num1_64(i_num1_64[17]), .i_num2_64(i_num2_64[17]), .i_cin_64(i_cin_64[17]), .o_sum_64(o_sum_64[17]), .o_cout_64(temp[17]));
    add2 add19(.i_num1_64(i_num1_64[18]), .i_num2_64(i_num2_64[18]), .i_cin_64(i_cin_64[18]), .o_sum_64(o_sum_64[18]), .o_cout_64(temp[18]));
    add2 add20(.i_num1_64(i_num1_64[19]), .i_num2_64(i_num2_64[19]), .i_cin_64(i_cin_64[19]), .o_sum_64(o_sum_64[19]), .o_cout_64(temp[19]));
    add2 add21(.i_num1_64(i_num1_64[20]), .i_num2_64(i_num2_64[20]), .i_cin_64(i_cin_64[20]), .o_sum_64(o_sum_64[20]), .o_cout_64(temp[20]));
    add2 add22(.i_num1_64(i_num1_64[21]), .i_num2_64(i_num2_64[21]), .i_cin_64(i_cin_64[21]), .o_sum_64(o_sum_64[21]), .o_cout_64(temp[21]));
    add2 add23(.i_num1_64(i_num1_64[22]), .i_num2_64(i_num2_64[22]), .i_cin_64(i_cin_64[22]), .o_sum_64(o_sum_64[22]), .o_cout_64(temp[22]));
    add2 add24(.i_num1_64(i_num1_64[23]), .i_num2_64(i_num2_64[23]), .i_cin_64(i_cin_64[23]), .o_sum_64(o_sum_64[23]), .o_cout_64(temp[23]));
    add2 add25(.i_num1_64(i_num1_64[24]), .i_num2_64(i_num2_64[24]), .i_cin_64(i_cin_64[24]), .o_sum_64(o_sum_64[24]), .o_cout_64(temp[24]));
    add2 add26(.i_num1_64(i_num1_64[25]), .i_num2_64(i_num2_64[25]), .i_cin_64(i_cin_64[25]), .o_sum_64(o_sum_64[25]), .o_cout_64(temp[25]));
    add2 add27(.i_num1_64(i_num1_64[26]), .i_num2_64(i_num2_64[26]), .i_cin_64(i_cin_64[26]), .o_sum_64(o_sum_64[26]), .o_cout_64(temp[26]));
    add2 add28(.i_num1_64(i_num1_64[27]), .i_num2_64(i_num2_64[27]), .i_cin_64(i_cin_64[27]), .o_sum_64(o_sum_64[27]), .o_cout_64(temp[27]));
    add2 add29(.i_num1_64(i_num1_64[28]), .i_num2_64(i_num2_64[28]), .i_cin_64(i_cin_64[28]), .o_sum_64(o_sum_64[28]), .o_cout_64(temp[28]));
    add2 add30(.i_num1_64(i_num1_64[29]), .i_num2_64(i_num2_64[29]), .i_cin_64(i_cin_64[29]), .o_sum_64(o_sum_64[29]), .o_cout_64(temp[29]));
    add2 add31(.i_num1_64(i_num1_64[30]), .i_num2_64(i_num2_64[30]), .i_cin_64(i_cin_64[30]), .o_sum_64(o_sum_64[30]), .o_cout_64(temp[30]));
    add2 add32(.i_num1_64(i_num1_64[31]), .i_num2_64(i_num2_64[31]), .i_cin_64(i_cin_64[31]), .o_sum_64(o_sum_64[31]), .o_cout_64(temp[31]));
    add2 add33(.i_num1_64(i_num1_64[32]), .i_num2_64(i_num2_64[32]), .i_cin_64(i_cin_64[32]), .o_sum_64(o_sum_64[32]), .o_cout_64(temp[32]));
    add2 add34(.i_num1_64(i_num1_64[33]), .i_num2_64(i_num2_64[33]), .i_cin_64(i_cin_64[33]), .o_sum_64(o_sum_64[33]), .o_cout_64(temp[33]));
    add2 add35(.i_num1_64(i_num1_64[34]), .i_num2_64(i_num2_64[34]), .i_cin_64(i_cin_64[34]), .o_sum_64(o_sum_64[34]), .o_cout_64(temp[34]));
    add2 add36(.i_num1_64(i_num1_64[35]), .i_num2_64(i_num2_64[35]), .i_cin_64(i_cin_64[35]), .o_sum_64(o_sum_64[35]), .o_cout_64(temp[35]));
    add2 add37(.i_num1_64(i_num1_64[36]), .i_num2_64(i_num2_64[36]), .i_cin_64(i_cin_64[36]), .o_sum_64(o_sum_64[36]), .o_cout_64(temp[36]));
    add2 add38(.i_num1_64(i_num1_64[37]), .i_num2_64(i_num2_64[37]), .i_cin_64(i_cin_64[37]), .o_sum_64(o_sum_64[37]), .o_cout_64(temp[37]));
    add2 add39(.i_num1_64(i_num1_64[38]), .i_num2_64(i_num2_64[38]), .i_cin_64(i_cin_64[38]), .o_sum_64(o_sum_64[38]), .o_cout_64(temp[38]));
    add2 add40(.i_num1_64(i_num1_64[39]), .i_num2_64(i_num2_64[39]), .i_cin_64(i_cin_64[39]), .o_sum_64(o_sum_64[39]), .o_cout_64(temp[39]));
    add2 add41(.i_num1_64(i_num1_64[40]), .i_num2_64(i_num2_64[40]), .i_cin_64(i_cin_64[40]), .o_sum_64(o_sum_64[40]), .o_cout_64(temp[40]));
    add2 add42(.i_num1_64(i_num1_64[41]), .i_num2_64(i_num2_64[41]), .i_cin_64(i_cin_64[41]), .o_sum_64(o_sum_64[41]), .o_cout_64(temp[41]));
    add2 add43(.i_num1_64(i_num1_64[42]), .i_num2_64(i_num2_64[42]), .i_cin_64(i_cin_64[42]), .o_sum_64(o_sum_64[42]), .o_cout_64(temp[42]));
    add2 add44(.i_num1_64(i_num1_64[43]), .i_num2_64(i_num2_64[43]), .i_cin_64(i_cin_64[43]), .o_sum_64(o_sum_64[43]), .o_cout_64(temp[43]));
    add2 add45(.i_num1_64(i_num1_64[44]), .i_num2_64(i_num2_64[44]), .i_cin_64(i_cin_64[44]), .o_sum_64(o_sum_64[44]), .o_cout_64(temp[44]));
    add2 add46(.i_num1_64(i_num1_64[45]), .i_num2_64(i_num2_64[45]), .i_cin_64(i_cin_64[45]), .o_sum_64(o_sum_64[45]), .o_cout_64(temp[45]));
    add2 add47(.i_num1_64(i_num1_64[46]), .i_num2_64(i_num2_64[46]), .i_cin_64(i_cin_64[46]), .o_sum_64(o_sum_64[46]), .o_cout_64(temp[46]));
    add2 add48(.i_num1_64(i_num1_64[47]), .i_num2_64(i_num2_64[47]), .i_cin_64(i_cin_64[47]), .o_sum_64(o_sum_64[47]), .o_cout_64(temp[47]));
    add2 add49(.i_num1_64(i_num1_64[48]), .i_num2_64(i_num2_64[48]), .i_cin_64(i_cin_64[48]), .o_sum_64(o_sum_64[48]), .o_cout_64(temp[48]));
    add2 add50(.i_num1_64(i_num1_64[49]), .i_num2_64(i_num2_64[49]), .i_cin_64(i_cin_64[49]), .o_sum_64(o_sum_64[49]), .o_cout_64(temp[49]));
    add2 add51(.i_num1_64(i_num1_64[50]), .i_num2_64(i_num2_64[50]), .i_cin_64(i_cin_64[50]), .o_sum_64(o_sum_64[50]), .o_cout_64(temp[50]));
    add2 add52(.i_num1_64(i_num1_64[51]), .i_num2_64(i_num2_64[51]), .i_cin_64(i_cin_64[51]), .o_sum_64(o_sum_64[51]), .o_cout_64(temp[51]));
    add2 add53(.i_num1_64(i_num1_64[52]), .i_num2_64(i_num2_64[52]), .i_cin_64(i_cin_64[52]), .o_sum_64(o_sum_64[52]), .o_cout_64(temp[52]));
    add2 add54(.i_num1_64(i_num1_64[53]), .i_num2_64(i_num2_64[53]), .i_cin_64(i_cin_64[53]), .o_sum_64(o_sum_64[53]), .o_cout_64(temp[53]));
    add2 add55(.i_num1_64(i_num1_64[54]), .i_num2_64(i_num2_64[54]), .i_cin_64(i_cin_64[54]), .o_sum_64(o_sum_64[54]), .o_cout_64(temp[54]));
    add2 add56(.i_num1_64(i_num1_64[55]), .i_num2_64(i_num2_64[55]), .i_cin_64(i_cin_64[55]), .o_sum_64(o_sum_64[55]), .o_cout_64(temp[55]));
    add2 add57(.i_num1_64(i_num1_64[56]), .i_num2_64(i_num2_64[56]), .i_cin_64(i_cin_64[56]), .o_sum_64(o_sum_64[56]), .o_cout_64(temp[56]));
    add2 add58(.i_num1_64(i_num1_64[57]), .i_num2_64(i_num2_64[57]), .i_cin_64(i_cin_64[57]), .o_sum_64(o_sum_64[57]), .o_cout_64(temp[57]));
    add2 add59(.i_num1_64(i_num1_64[58]), .i_num2_64(i_num2_64[58]), .i_cin_64(i_cin_64[58]), .o_sum_64(o_sum_64[58]), .o_cout_64(temp[58]));
    add2 add60(.i_num1_64(i_num1_64[59]), .i_num2_64(i_num2_64[59]), .i_cin_64(i_cin_64[59]), .o_sum_64(o_sum_64[59]), .o_cout_64(temp[59]));
    add2 add61(.i_num1_64(i_num1_64[60]), .i_num2_64(i_num2_64[60]), .i_cin_64(i_cin_64[60]), .o_sum_64(o_sum_64[60]), .o_cout_64(temp[60]));
    add2 add62(.i_num1_64(i_num1_64[61]), .i_num2_64(i_num2_64[61]), .i_cin_64(i_cin_64[61]), .o_sum_64(o_sum_64[61]), .o_cout_64(temp[61]));
    add2 add63(.i_num1_64(i_num1_64[62]), .i_num2_64(i_num2_64[62]), .i_cin_64(i_cin_64[62]), .o_sum_64(o_sum_64[62]), .o_cout_64(temp[62]));
    add2 add64(.i_num1_64(i_num1_64[63]), .i_num2_64(i_num2_64[63]), .i_cin_64(i_cin_64[63]), .o_sum_64(o_sum_64[63]), .o_cout_64(temp[63]));
    //最后的进位输出链需要左移一位
    assign o_cout_64=temp<<1;
endmodule
module add2
(
	input i_num1_64,     	
	input i_num2_64,		
	input i_cin_64,		
	output o_sum_64,		
	output o_cout_64		
);
    //1位全加器，作为3压2的基础部件
	assign o_sum_64 = i_num1_64^i_num2_64^i_cin_64;
	assign o_cout_64 = (i_num1_64&i_num2_64)|((i_num1_64^i_num2_64)&i_cin_64);
endmodule
