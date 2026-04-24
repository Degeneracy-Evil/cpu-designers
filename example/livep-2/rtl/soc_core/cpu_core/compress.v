module carry4to2(
 input clk,rst,en,
 input [63:0]a,
 input [63:0]b,
 input [63:0]c,
 input [63:0]d,
 output reg[63:0]s,
 output reg[63:0]q   
);
        //������
    
    wire [63:0] sum1,temp_s,temp_q;
    wire [63:0] carry1;
    carry3to2 csr1(
    .a(a),
    .b(b),
    .cin(c),
    .sum(sum1),
    .carry_out(carry1)
    );
    
    carry3to2 csr2(
    .a(sum1),
    .b(carry1),
    .cin(d),
    .sum(temp_s),
    .carry_out(temp_q)
    );
    always@(*)begin
        if(~rst)begin
        s=0;
        q=0;
        end else begin
            if(en)begin
            s=temp_s;
            q=temp_q;
            end else begin
            s=0;
            q=0;
            end
        end
    
    end
endmodule

module carry3to2(
    input [63:0]a,
    input [63:0]b,
    input [63:0]cin,
    output [63:0] sum,
    output [63:0]carry_out
    );
        wire [63:0]temp;
add2 add1(.a(a[0]), .b(b[0]), .cin(cin[0]), .sum(sum[0]), .cout(temp[0]));
add2 add2(.a(a[1]), .b(b[1]), .cin(cin[1]), .sum(sum[1]), .cout(temp[1]));
add2 add3(.a(a[2]), .b(b[2]), .cin(cin[2]), .sum(sum[2]), .cout(temp[2]));
add2 add4(.a(a[3]), .b(b[3]), .cin(cin[3]), .sum(sum[3]), .cout(temp[3]));
add2 add5(.a(a[4]), .b(b[4]), .cin(cin[4]), .sum(sum[4]), .cout(temp[4]));
add2 add6(.a(a[5]), .b(b[5]), .cin(cin[5]), .sum(sum[5]), .cout(temp[5]));
add2 add7(.a(a[6]), .b(b[6]), .cin(cin[6]), .sum(sum[6]), .cout(temp[6]));
add2 add8(.a(a[7]), .b(b[7]), .cin(cin[7]), .sum(sum[7]), .cout(temp[7]));
add2 add9(.a(a[8]), .b(b[8]), .cin(cin[8]), .sum(sum[8]), .cout(temp[8]));
add2 add10(.a(a[9]), .b(b[9]), .cin(cin[9]), .sum(sum[9]), .cout(temp[9]));
add2 add11(.a(a[10]), .b(b[10]), .cin(cin[10]), .sum(sum[10]), .cout(temp[10]));
add2 add12(.a(a[11]), .b(b[11]), .cin(cin[11]), .sum(sum[11]), .cout(temp[11]));
add2 add13(.a(a[12]), .b(b[12]), .cin(cin[12]), .sum(sum[12]), .cout(temp[12]));
add2 add14(.a(a[13]), .b(b[13]), .cin(cin[13]), .sum(sum[13]), .cout(temp[13]));
add2 add15(.a(a[14]), .b(b[14]), .cin(cin[14]), .sum(sum[14]), .cout(temp[14]));
add2 add16(.a(a[15]), .b(b[15]), .cin(cin[15]), .sum(sum[15]), .cout(temp[15]));
add2 add17(.a(a[16]), .b(b[16]), .cin(cin[16]), .sum(sum[16]), .cout(temp[16]));
add2 add18(.a(a[17]), .b(b[17]), .cin(cin[17]), .sum(sum[17]), .cout(temp[17]));
add2 add19(.a(a[18]), .b(b[18]), .cin(cin[18]), .sum(sum[18]), .cout(temp[18]));
add2 add20(.a(a[19]), .b(b[19]), .cin(cin[19]), .sum(sum[19]), .cout(temp[19]));
add2 add21(.a(a[20]), .b(b[20]), .cin(cin[20]), .sum(sum[20]), .cout(temp[20]));
add2 add22(.a(a[21]), .b(b[21]), .cin(cin[21]), .sum(sum[21]), .cout(temp[21]));
add2 add23(.a(a[22]), .b(b[22]), .cin(cin[22]), .sum(sum[22]), .cout(temp[22]));
add2 add24(.a(a[23]), .b(b[23]), .cin(cin[23]), .sum(sum[23]), .cout(temp[23]));
add2 add25(.a(a[24]), .b(b[24]), .cin(cin[24]), .sum(sum[24]), .cout(temp[24]));
add2 add26(.a(a[25]), .b(b[25]), .cin(cin[25]), .sum(sum[25]), .cout(temp[25]));
add2 add27(.a(a[26]), .b(b[26]), .cin(cin[26]), .sum(sum[26]), .cout(temp[26]));
add2 add28(.a(a[27]), .b(b[27]), .cin(cin[27]), .sum(sum[27]), .cout(temp[27]));
add2 add29(.a(a[28]), .b(b[28]), .cin(cin[28]), .sum(sum[28]), .cout(temp[28]));
add2 add30(.a(a[29]), .b(b[29]), .cin(cin[29]), .sum(sum[29]), .cout(temp[29]));
add2 add31(.a(a[30]), .b(b[30]), .cin(cin[30]), .sum(sum[30]), .cout(temp[30]));
add2 add32(.a(a[31]), .b(b[31]), .cin(cin[31]), .sum(sum[31]), .cout(temp[31]));
add2 add33(.a(a[32]), .b(b[32]), .cin(cin[32]), .sum(sum[32]), .cout(temp[32]));
add2 add34(.a(a[33]), .b(b[33]), .cin(cin[33]), .sum(sum[33]), .cout(temp[33]));
add2 add35(.a(a[34]), .b(b[34]), .cin(cin[34]), .sum(sum[34]), .cout(temp[34]));
add2 add36(.a(a[35]), .b(b[35]), .cin(cin[35]), .sum(sum[35]), .cout(temp[35]));
add2 add37(.a(a[36]), .b(b[36]), .cin(cin[36]), .sum(sum[36]), .cout(temp[36]));
add2 add38(.a(a[37]), .b(b[37]), .cin(cin[37]), .sum(sum[37]), .cout(temp[37]));
add2 add39(.a(a[38]), .b(b[38]), .cin(cin[38]), .sum(sum[38]), .cout(temp[38]));
add2 add40(.a(a[39]), .b(b[39]), .cin(cin[39]), .sum(sum[39]), .cout(temp[39]));
add2 add41(.a(a[40]), .b(b[40]), .cin(cin[40]), .sum(sum[40]), .cout(temp[40]));
add2 add42(.a(a[41]), .b(b[41]), .cin(cin[41]), .sum(sum[41]), .cout(temp[41]));
add2 add43(.a(a[42]), .b(b[42]), .cin(cin[42]), .sum(sum[42]), .cout(temp[42]));
add2 add44(.a(a[43]), .b(b[43]), .cin(cin[43]), .sum(sum[43]), .cout(temp[43]));
add2 add45(.a(a[44]), .b(b[44]), .cin(cin[44]), .sum(sum[44]), .cout(temp[44]));
add2 add46(.a(a[45]), .b(b[45]), .cin(cin[45]), .sum(sum[45]), .cout(temp[45]));
add2 add47(.a(a[46]), .b(b[46]), .cin(cin[46]), .sum(sum[46]), .cout(temp[46]));
add2 add48(.a(a[47]), .b(b[47]), .cin(cin[47]), .sum(sum[47]), .cout(temp[47]));
add2 add49(.a(a[48]), .b(b[48]), .cin(cin[48]), .sum(sum[48]), .cout(temp[48]));
add2 add50(.a(a[49]), .b(b[49]), .cin(cin[49]), .sum(sum[49]), .cout(temp[49]));
add2 add51(.a(a[50]), .b(b[50]), .cin(cin[50]), .sum(sum[50]), .cout(temp[50]));
add2 add52(.a(a[51]), .b(b[51]), .cin(cin[51]), .sum(sum[51]), .cout(temp[51]));
add2 add53(.a(a[52]), .b(b[52]), .cin(cin[52]), .sum(sum[52]), .cout(temp[52]));
add2 add54(.a(a[53]), .b(b[53]), .cin(cin[53]), .sum(sum[53]), .cout(temp[53]));
add2 add55(.a(a[54]), .b(b[54]), .cin(cin[54]), .sum(sum[54]), .cout(temp[54]));
add2 add56(.a(a[55]), .b(b[55]), .cin(cin[55]), .sum(sum[55]), .cout(temp[55]));
add2 add57(.a(a[56]), .b(b[56]), .cin(cin[56]), .sum(sum[56]), .cout(temp[56]));
add2 add58(.a(a[57]), .b(b[57]), .cin(cin[57]), .sum(sum[57]), .cout(temp[57]));
add2 add59(.a(a[58]), .b(b[58]), .cin(cin[58]), .sum(sum[58]), .cout(temp[58]));
add2 add60(.a(a[59]), .b(b[59]), .cin(cin[59]), .sum(sum[59]), .cout(temp[59]));
add2 add61(.a(a[60]), .b(b[60]), .cin(cin[60]), .sum(sum[60]), .cout(temp[60]));
add2 add62(.a(a[61]), .b(b[61]), .cin(cin[61]), .sum(sum[61]), .cout(temp[61]));
add2 add63(.a(a[62]), .b(b[62]), .cin(cin[62]), .sum(sum[62]), .cout(temp[62]));
add2 add64(.a(a[63]), .b(b[63]), .cin(cin[63]), .sum(sum[63]), .cout(temp[63]));


    assign carry_out=temp<<1;
endmodule
module add2
(
	input a,     	//����
	input b,		//������
	input cin,		//��������
	output sum,		//��������
	output cout		//��������
);
	assign sum = a^b^cin;
	assign cout = (a&b)|((a^b)&cin);
endmodule