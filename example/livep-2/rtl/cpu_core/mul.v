module mul(
    input clk,rst,i_mulStart_1,i_mulSign_1,i_mulMix_1,  //乘法的一系列控制信号，包括时钟、复位信号，开始信号，符号控制信号
    input [31:0] i_mulNum1_32,                 //操作数1
    input [31:0] i_mulNum2_32,                 //操作数2
    output [63:0] o_mulNum_64,               //运算结果
    output reg o_mulEnd_1                      //运算结束标志
    );
    wire [31:0] c[31:0];                   //原始部分积，共32个32位数
    wire [63:0] temp[31:0];                //进行拓展后的部分积，共32个64位数
    wire [63:0] sum[14:0];                 //中间变量，用于划分时序
    wire [63:0] cout[14:0];                //中间变量，用于划分时序
    reg [63:0] sonl[14:0];                 //中间变量，用于划分时序
    reg [63:0]sonr[14:0];                  //中间变量，用于划分时序
    reg [63:0] out;                        //中间变量，用于暂存最后输出的结果
//    reg [63:0] out;
    wire sign,sign1;                       //不同运算下的符号标志位
    reg zero;                              //零标志位
    wire [31:0]mulNum1,mulNum2,mult1,mult2;//进行补码转换后的操作数
    reg [63:0]result;                      //无符号数运算结果
    wire [63:0]mulTemp1,outMulNum1,temp1;  //不同符号数下的运算结果

    //例化补码准换模块
    transform trans(.i_num1_32(i_mulNum1_32),.i_num2_32(i_mulNum2_32),.i_sign_1(i_mulSign_1),.o_sign_1(sign1),.o_num1_32(mult1),.o_num2_32(mult2));
    //确定操作数以及符号位
    assign mulNum2=(i_mulMix_1)?i_mulNum2_32:mult2;
    assign mulNum1=(i_mulMix_1)?(i_mulNum1_32[31]==1'b1)?(~i_mulNum1_32+1):i_mulNum1_32:mult1;
    assign sign=(i_mulMix_1)?0:sign1;
    //获取部分积并进行高位补零
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

	 
	    reg[3:0]en,cnt;//计数器以及使能信号
      //第一次压缩，将32个部分积压缩至16个
      carry4to2  csr1(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[0]),.i_num2_64(temp[1]),.i_num3_64(temp[2]),.i_num4_64(temp[3]),.o_sum_64(sum[0]),.o_cout_64(cout[0]));
      carry4to2  csr2(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[4]),.i_num2_64(temp[5]),.i_num3_64(temp[6]),.i_num4_64(temp[7]),.o_sum_64(sum[1]),.o_cout_64(cout[1]));
      carry4to2  csr3(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[8]),.i_num2_64(temp[9]),.i_num3_64(temp[10]),.i_num4_64(temp[11]),.o_sum_64(sum[2]),.o_cout_64(cout[2]));
      carry4to2  csr4(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[12]),.i_num2_64(temp[13]),.i_num3_64(temp[14]),.i_num4_64(temp[15]),.o_sum_64(sum[3]),.o_cout_64(cout[3]));
      carry4to2  csr5(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[16]),.i_num2_64(temp[17]),.i_num3_64(temp[18]),.i_num4_64(temp[19]),.o_sum_64(sum[4]),.o_cout_64(cout[4]));
      carry4to2  csr6(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[20]),.i_num2_64(temp[21]),.i_num3_64(temp[22]),.i_num4_64(temp[23]),.o_sum_64(sum[5]),.o_cout_64(cout[5]));
      carry4to2  csr7(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[24]),.i_num2_64(temp[25]),.i_num3_64(temp[26]),.i_num4_64(temp[27]),.o_sum_64(sum[6]),.o_cout_64(cout[6]));
      carry4to2  csr8(.clk(clk),.rst(rst),.en(en[0]),.i_num1_64(temp[28]),.i_num2_64(temp[29]),.i_num3_64(temp[30]),.i_num4_64(temp[31]),.o_sum_64(sum[7]),.o_cout_64(cout[7]));
      //第二次压缩，将16个部分积压缩至8个
      carry4to2  csr9(.clk(clk),.rst(rst),.en(en[1]),.i_num1_64(sonl[0]),.i_num2_64(sonr[0]),.i_num3_64(sonl[1]),.i_num4_64(sonr[1]),.o_sum_64(sum[8]),.o_cout_64(cout[8]));
      carry4to2  csr10(.clk(clk),.rst(rst),.en(en[1]),.i_num1_64(sonl[2]),.i_num2_64(sonr[2]),.i_num3_64(sonl[3]),.i_num4_64(sonr[3]),.o_sum_64(sum[9]),.o_cout_64(cout[9]));
      carry4to2  csr11(.clk(clk),.rst(rst),.en(en[1]),.i_num1_64(sonl[4]),.i_num2_64(sonr[4]),.i_num3_64(sonl[5]),.i_num4_64(sonr[5]),.o_sum_64(sum[10]),.o_cout_64(cout[10]));
      carry4to2  csr12(.clk(clk),.rst(rst),.en(en[1]),.i_num1_64(sonl[6]),.i_num2_64(sonr[6]),.i_num3_64(sonl[7]),.i_num4_64(sonr[7]),.o_sum_64(sum[11]),.o_cout_64(cout[11]));		
      //第三次压缩，将8个部分积压缩至4个
      carry4to2  csr13(.clk(clk),.rst(rst),.en(en[2]),.i_num1_64(sonl[8]),.i_num2_64(sonr[8]),.i_num3_64(sonl[9]),.i_num4_64(sonr[9]),.o_sum_64(sum[12]),.o_cout_64(cout[12]));
      carry4to2  csr14(.clk(clk),.rst(rst),.en(en[2]),.i_num1_64(sonl[10]),.i_num2_64(sonr[10]),.i_num3_64(sonl[11]),.i_num4_64(sonr[11]),.o_sum_64(sum[13]),.o_cout_64(cout[13]));
      //第四次压缩，将4个部分积压缩至2个
      carry4to2  csr15(.clk(clk),.rst(rst),.en(en[3]),.i_num1_64(sonl[12]),.i_num2_64(sonr[12]),.i_num3_64(sonl[13]),.i_num4_64(sonr[13]),.o_sum_64(sum[14]),.o_cout_64(cout[14])); 	
   // assign product = sum[14]+cout[14];
    always@(posedge clk or negedge rst)begin
      if(~rst)begin//对信号置位
        en=0;
        cnt=0;
        out=0;
        result=0;
        zero=0;
        o_mulEnd_1=0;
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
              if(i_mulStart_1)begin                     //通过计数器进行使能信号的控制，控制每个周期进行对应周期的压缩操作                    
                if(cnt==0)begin
                  en=1;         
                end else if(cnt==1)begin
                  en=2;  
                if(mulNum1==0||mulNum2==0)begin
                  zero=1;                           //当操作数存在零时，零标志位置1
                  end          
                  sonl[8]=sum[8];sonr[8]=cout[8];
                  sonl[9]=sum[9];sonr[9]=cout[9];
                  sonl[10]=sum[10];sonr[10]=cout[10];
                  sonl[11]=sum[11];sonr[11]=cout[11];
                end else if(cnt==2)begin
                  en=4;          
                end else if(cnt==3)begin
                  en=8;             
                end else if(cnt==4)begin
                  o_mulEnd_1=1;                        //当计数器为4时，乘法结束标志信号置1
                  en=0;          
                end else if(cnt==5)begin 
                  en=0;
                end 
                  cnt=cnt+1;
                if(en==2)begin                    //当en为2时，将第一次压缩的结果存入sonl与sonr，使sonl和sonr作为第二次压缩的输出
                  sonl[0]=sum[0];sonr[0]=cout[0];
                  sonl[1]=sum[1];sonr[1]=cout[1];
                  sonl[2]=sum[2];sonr[2]=cout[2];
                  sonl[3]=sum[3];sonr[3]=cout[3];
                  sonl[4]=sum[4];sonr[4]=cout[4];
                  sonl[5]=sum[5];sonr[5]=cout[5];
                  sonl[6]=sum[6];sonr[6]=cout[6];
                  sonl[7]=sum[7];sonr[7]=cout[7];
                end else if(en==4) begin           //当en为4时，将第二次压缩的结果存入sonl与sonr，使sonl和sonr作为第三次压缩的输出
                  sonl[8]=sum[8];sonr[8]=cout[8];
                  sonl[9]=sum[9];sonr[9]=cout[9];
                  sonl[10]=sum[10];sonr[10]=cout[10];
                  sonl[11]=sum[11];sonr[11]=cout[11];
                end else if(en==8)begin            //当en为8时，将第三次压缩的结果存入sonl与sonr，使sonl和sonr作为第四次压缩的输出
                  sonl[12]=sum[12];sonr[12]=cout[12];
                  sonl[13]=sum[13];sonr[13]=cout[13];
                end else if(en==0)begin
                  sonl[14]=sum[14];sonr[14]=cout[14];//将最后的两次结果进行相加，得到最后的结果
                  out=sonl[14]+sonr[14];
                if(~i_mulMix_1)begin
                    if(i_mulSign_1&&sign)begin
                      result[62:0]=~(out[62:0])+1; //当不为无符号数乘有符号数时，最后的结果如果为负数，就取结果的补码
                    end else begin
                      result[62:0]=out[62:0];
                    end 
                    if(i_mulSign_1&&(!zero))begin       //当进行符号数运算且不为0时，最后的结果符号位为上面确定的符号位
                      result[63]=sign;
                    end else begin
                      result[63]=out[63];
                    end 
                end else begin                      //当运算为有符号数乘无符号数时，最后的结果的符号位为操作数中有符号数的符号位
                    if(i_mulNum1_32[31]==1'b1)begin
                      result=~out+1;
                    end else begin
                      result=out;
                    end
                  end 
                    if(i_mulSign_1&&sign)begin          //与上面不为无符号数乘有符号数时相同
                      result[62:0]=~(out[62:0])+1;
                    end else begin
                      result[62:0]=out[62:0];
                    end 
                    if(i_mulSign_1&&(!zero))begin
                      result[63]=sign;
                    end else begin
                      result[63]=out[63];
                    end  
                end                     
              end else begin                       //运算结束后将相关寄存器置0
                o_mulEnd_1=0;
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
    //判断结果是否为0
    assign outMulNum1[62:0]=(zero)?0:result[62:0]; 
    assign outMulNum1[63]=(zero)?0:result[63];
    //判断结果输出为有符号数还是无符号数还是有符号数乘无符号数
    assign o_mulNum_64=(i_mulMix_1)?((i_mulNum1_32[31]==1'b1)?(~out+1):out):outMulNum1;

endmodule


