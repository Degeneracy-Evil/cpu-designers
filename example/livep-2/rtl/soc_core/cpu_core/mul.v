module mul(
    input clk,rst,mul_start,mul_sign,
    input [31:0] i_mulNum1,
    input [31:0] i_mulNum2, 
    output [63:0] o_mulNum ,
    output reg mul_end
    );
    wire [31:0] c[31:0];   
    wire [63:0] temp[31:0];
    wire [63:0] sum[14:0];
    wire [63:0] cout[14:0];
    reg [63:0] sonl[14:0];
    reg [63:0]sonr[14:0];
    wire sign;
    reg zero;
    wire [31:0]mulNum1,mulNum2;
    wire [63:0]result;
    transform trans(.i_num1(i_mulNum1),.i_num2(i_mulNum2),.i_sign(mul_sign),.sign(sign),.num1(mulNum1),.num2(mulNum2));
    assign c[0] = mulNum2[0] ? mulNum1 : 'd0;
    assign temp[0] = c[0] << 0;
    assign c[1] = mulNum2[1] ? mulNum1 : 'd0;
    assign temp[1] = c[1] << 1;    
    assign c[2] = mulNum2[2] ? mulNum1 : 'd0;
    assign temp[2] = c[2] << 2;   
    assign c[3] = mulNum2[3] ? mulNum1 : 'd0;
    assign temp[3] = c[3] << 3;    
    assign c[4] = mulNum2[4] ? mulNum1 : 'd0;
    assign temp[4] = c[4] << 4;   
    assign c[5] = mulNum2[5] ? mulNum1 : 'd0;
    assign temp[5] = c[5] << 5;  
    assign c[6] = mulNum2[6] ? mulNum1 : 'd0;
    assign temp[6] = c[6] << 6;  
    assign c[7] = mulNum2[7] ? mulNum1 : 'd0;
    assign temp[7] = c[7] << 7;   
    assign c[8] = mulNum2[8] ? mulNum1 : 'd0;
    assign temp[8] = c[8] << 8;  
    assign c[9] = mulNum2[9] ? mulNum1 : 'd0;
    assign temp[9] = c[9] << 9;  
    assign c[10] = mulNum2[10] ? mulNum1 : 'd0;
    assign temp[10] = c[10] << 10;  
    assign c[11] = mulNum2[11] ? mulNum1 : 'd0;
    assign temp[11] = c[11] << 11;
    assign c[12] = mulNum2[12] ? mulNum1 : 'd0;
    assign temp[12] = c[12] << 12;    
    assign c[13] = mulNum2[13] ? mulNum1 : 'd0;
    assign temp[13] = c[13] << 13;    
    assign c[14] = mulNum2[14] ? mulNum1 : 'd0;
    assign temp[14] = c[14] << 14;   
    assign c[15] = mulNum2[15] ? mulNum1 : 'd0;
    assign temp[15] = c[15] << 15;  
    assign c[16] = mulNum2[16] ? mulNum1 : 'd0;
    assign temp[16] = c[16] << 16; 
    assign c[17] = mulNum2[17] ? mulNum1 : 'd0;
    assign temp[17] = c[17] << 17; 
    assign c[18] = mulNum2[18] ? mulNum1 : 'd0;
    assign temp[18] = c[18] << 18;  
    assign c[19] = mulNum2[19] ? mulNum1 : 'd0;
    assign temp[19] = c[19] << 19; 
    assign c[20] = mulNum2[20] ? mulNum1 : 'd0;
    assign temp[20] = c[20] << 20; 
    assign c[21] = mulNum2[21] ? mulNum1 : 'd0;
    assign temp[21] = c[21] << 21;  
    assign c[22] = mulNum2[22] ? mulNum1 : 'd0;
    assign temp[22] = c[22] << 22;  
    assign c[23] = mulNum2[23] ? mulNum1 : 'd0;
    assign temp[23] = c[23] << 23;  
    assign c[24] = mulNum2[24] ? mulNum1 : 'd0;
    assign temp[24] = c[24] << 24;   
    assign c[25] = mulNum2[25] ? mulNum1 : 'd0;
    assign temp[25] = c[25] << 25;  
    assign c[26] = mulNum2[26] ? mulNum1 : 'd0;
    assign temp[26] = c[26] << 26;  
    assign c[27] = mulNum2[27] ? mulNum1 : 'd0;
    assign temp[27] = c[27] << 27;  
    assign c[28] = mulNum2[28] ? mulNum1 : 'd0;
    assign temp[28] = c[28] << 28;  
    assign c[29] = mulNum2[29] ? mulNum1 : 'd0;
    assign temp[29] = c[29] << 29; 
    assign c[30] = mulNum2[30] ? mulNum1 : 'd0;
    assign temp[30] = c[30] << 30; 
    assign c[31] = mulNum2[31] ? mulNum1 : 'd0;
    assign temp[31] = c[31] << 31;

	 //����������
	  reg[3:0]en,cnt;
      carry4to2  csr1(.clk(clk),.rst(rst),.en(en[0]),.a(temp[0]),.b(temp[1]),.c(temp[2]),.d(temp[3]),.s(sum[0]),.q(cout[0]));
      carry4to2  csr2(.clk(clk),.rst(rst),.en(en[0]),.a(temp[4]),.b(temp[5]),.c(temp[6]),.d(temp[7]),.s(sum[1]),.q(cout[1]));
      carry4to2  csr3(.clk(clk),.rst(rst),.en(en[0]),.a(temp[8]),.b(temp[9]),.c(temp[10]),.d(temp[11]),.s(sum[2]),.q(cout[2]));
      carry4to2  csr4(.clk(clk),.rst(rst),.en(en[0]),.a(temp[12]),.b(temp[13]),.c(temp[14]),.d(temp[15]),.s(sum[3]),.q(cout[3]));
      carry4to2  csr5(.clk(clk),.rst(rst),.en(en[0]),.a(temp[16]),.b(temp[17]),.c(temp[18]),.d(temp[19]),.s(sum[4]),.q(cout[4]));
      carry4to2  csr6(.clk(clk),.rst(rst),.en(en[0]),.a(temp[20]),.b(temp[21]),.c(temp[22]),.d(temp[23]),.s(sum[5]),.q(cout[5]));
      carry4to2  csr7(.clk(clk),.rst(rst),.en(en[0]),.a(temp[24]),.b(temp[25]),.c(temp[26]),.d(temp[27]),.s(sum[6]),.q(cout[6]));
      carry4to2  csr8(.clk(clk),.rst(rst),.en(en[0]),.a(temp[28]),.b(temp[29]),.c(temp[30]),.d(temp[31]),.s(sum[7]),.q(cout[7]));
       //����������
      carry4to2  csr9(.clk(clk),.rst(rst),.en(en[1]),.a(sonl[0]),.b(sonr[0]),.c(sonl[1]),.d(sonr[1]),.s(sum[8]),.q(cout[8]));
      carry4to2  csr10(.clk(clk),.rst(rst),.en(en[1]),.a(sonl[2]),.b(sonr[2]),.c(sonl[3]),.d(sonr[3]),.s(sum[9]),.q(cout[9]));
      carry4to2  csr11(.clk(clk),.rst(rst),.en(en[1]),.a(sonl[4]),.b(sonr[4]),.c(sonl[5]),.d(sonr[5]),.s(sum[10]),.q(cout[10]));
      carry4to2  csr12(.clk(clk),.rst(rst),.en(en[1]),.a(sonl[6]),.b(sonr[6]),.c(sonl[7]),.d(sonr[7]),.s(sum[11]),.q(cout[11]));		
      //����������
      carry4to2  csr13(.clk(clk),.rst(rst),.en(en[2]),.a(sonl[8]),.b(sonr[8]),.c(sonl[9]),.d(sonr[9]),.s(sum[12]),.q(cout[12]));
      carry4to2  csr14(.clk(clk),.rst(rst),.en(en[2]),.a(sonl[10]),.b(sonr[10]),.c(sonl[11]),.d(sonr[11]),.s(sum[13]),.q(cout[13]));
     //����������
      carry4to2  csr15(.clk(clk),.rst(rst),.en(en[3]),.a(sonl[12]),.b(sonr[12]),.c(sonl[13]),.d(sonr[13]),.s(sum[14]),.q(cout[14])); 	
    always@(posedge clk or negedge rst)begin
    if(~rst)begin
      en=0;
      cnt=0;
      zero=0;
      mul_end=0;
     sonl[0]=0;sonr[0]=0;
     sonl[1]=0;sonr[1]=0;
     sonl[2]=0;sonr[2]=0;
     sonl[3]=0;sonr[3]=0;
     sonl[4]=0;sonr[4]=0;
     sonl[5]=0;sonr[5]=0;
     sonl[6]=0;sonr[6]=0;
     sonl[7]=0;sonr[7]=0;
     sonl[8]=0;sonr[8]=0;
     sonl[9]=0;sonr[9]=0;
     sonl[10]=0;sonr[10]=0;
     sonl[11]=0;sonr[11]=0;
     sonl[12]=0;sonr[12]=0;
     sonl[13]=0;sonr[13]=0;
     sonl[14]=0;sonr[14]=0;
    
    end else begin
            if(mul_start)begin                           
               if(cnt==0)begin
                en=1;         
               end else if(cnt==1)begin
                en=2;  
                if(mulNum1==0||mulNum2==0)begin
                zero=1;
                end          
                sonl[8]=sum[8];sonr[8]=cout[8];
                sonl[9]=sum[9];sonr[9]=cout[9];
                sonl[10]=sum[10];sonr[10]=cout[10];
                sonl[11]=sum[11];sonr[11]=cout[11];
               end else if(cnt==2)begin
                en=4;          
               end else if(cnt==3)begin
               mul_end=1;
                en=8;             
               end else if(cnt==4)begin
               en=0;
               cnt=0;
               end      
                cnt=cnt+1;
               if(en==2)begin
                sonl[0]=sum[0];sonr[0]=cout[0];
                sonl[1]=sum[1];sonr[1]=cout[1];
                sonl[2]=sum[2];sonr[2]=cout[2];
                sonl[3]=sum[3];sonr[3]=cout[3];
                sonl[4]=sum[4];sonr[4]=cout[4];
                sonl[5]=sum[5];sonr[5]=cout[5];
                sonl[6]=sum[6];sonr[6]=cout[6];
                sonl[7]=sum[7];sonr[7]=cout[7];
               end else if(en==4) begin
                sonl[8]=sum[8];sonr[8]=cout[8];
                sonl[9]=sum[9];sonr[9]=cout[9];
                sonl[10]=sum[10];sonr[10]=cout[10];
                sonl[11]=sum[11];sonr[11]=cout[11];
               end else if(en==8)begin
               sonl[12]=sum[12];sonr[12]=cout[12];
                sonl[13]=sum[13];sonr[13]=cout[13];
               end else if(en==0)begin
               sonl[14]=sum[14];sonr[14]=cout[14];
               end
               
               
            
              
            end else begin
            mul_end=0;
            en=0;
            zero=0;
            cnt=0;
         sonl[0]=0;sonr[0]=0;
         sonl[1]=0;sonr[1]=0;
         sonl[2]=0;sonr[2]=0;
         sonl[3]=0;sonr[3]=0;
         sonl[4]=0;sonr[4]=0;
         sonl[5]=0;sonr[5]=0;
         sonl[6]=0;sonr[6]=0;
         sonl[7]=0;sonr[7]=0;
         sonl[8]=0;sonr[8]=0;
         sonl[9]=0;sonr[9]=0;
         sonl[10]=0;sonr[10]=0;
         sonl[11]=0;sonr[11]=0;
         sonl[12]=0;sonr[12]=0;
         sonl[13]=0;sonr[13]=0;
         sonl[14]=0;sonr[14]=0;
         
            end
        end
    end
    assign result=sum[14]+cout[14];
    assign o_mulNum[62:0]=(mul_sign&&sign)?(~(result[62:0])+1):result[62:0];
    assign o_mulNum[63]=(mul_sign&&(!zero))?sign:result[63];
endmodule


