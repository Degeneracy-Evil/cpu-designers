module div_radix16 (
  input clk,                                    //时钟信号
  input rst,                                    //置位信号
  input i_divStart_1,                               //除法开始信号
  input i_divSign_1,                                //除法符号运算控制信号
  input [31:0] i_dividend_32,                      //被除数
  input [31:0] i_divisor_32,                       //除数
  output  [31:0] o_quotient_32,                      //商 
  output  [31:0] o_remainder_32,                     //余数
  output reg o_done_1,o_busy_1                         //除法结束信号与除法器忙碌信号
);
    //除法运算状态机
    parameter IDLE  =3'b000;                    //空闲状态
    parameter READY =3'b001;                    //准备状态
    parameter WORK  =3'b010;                    //计算状态
    parameter CMP   =3'b011;                    //比较状态
    parameter OUT   =3'b100;                    //输出状态
    reg [2:0]   state;                          //状态寄存器
    wire [31:0] dividend,divisor;               //补码转换后的除数与被除数
    reg [31:0]  quotient_temp,remainder_temp;    //中间状态的除数与被除数
    reg [35:0]  RegF[16:1];                     //除数的1-F倍
    reg [36:0]  Re[15:0];                       //被除数与除数倍数之差
    reg [3:0]   cnt;                            //计数器
    reg[63:0]   result;                         //运算结果
    reg [3:0]   Quot;                           //迭代中的商的值
    reg [15:1]  level;                         //迭代中的优先等级
    wire sign;                                  //结果的符号位
    reg zero;                                   //零标志位
//补码转换模块   
transform trans(.i_num1_32(i_dividend_32),.i_num2_32(i_divisor_32),.i_sign_1(i_divSign_1),.o_sign_1(sign),.o_num1_32(dividend),.o_num2_32(divisor));
always@(posedge clk or negedge rst)begin
    if(~rst)begin//对寄存器值进行置位，赋初值
    o_done_1=0;
    o_busy_1=0;
    cnt=0;
    result=0;
    zero=0;
    Quot=0;
    level=0;
    quotient_temp=0;
    remainder_temp=0;
    state=IDLE;
    RegF[1]=0;
    RegF[2]=0;
    RegF[3]=0;
    RegF[4]=0;
    RegF[5]=0;
    RegF[6]=0;
    RegF[7]=0;
    RegF[8]=0;
    RegF[9]=0;
    RegF[10]=0;
    RegF[11]=0;
    RegF[12]=0;
    RegF[13]=0;
    RegF[14]=0;
    RegF[15]=0;
    RegF[16]=0;
    Re[0]=0;
    Re[1]=0;
    Re[2]=0;
    Re[3]=0;
    Re[4]=0;
    Re[5]=0;
    Re[6]=0;
    Re[7]=0;
    Re[8]=0;
    Re[9]=0;
    Re[10]=0;
    Re[11]=0;
    Re[12]=0;
    Re[13]=0;
    Re[14]=0;
    Re[15]=0;
    end else begin
        if(i_divStart_1)begin
          if(cnt==0)begin  //第一个周期确定除数的各个倍数，用于后面的计算
               RegF[1]=divisor;
               RegF[2]=divisor<<1;
               RegF[4]=divisor<<2;
               RegF[8]=divisor<<3;
               RegF[16]=divisor<<4;
                      
               RegF[3]=RegF[2]+RegF[1];
               RegF[5]=RegF[4]+RegF[1];
               RegF[7]=RegF[8]-RegF[1];
               RegF[9]=RegF[8]+RegF[1];
               RegF[15]=RegF[16]-RegF[1]; 
                         
               RegF[6]=RegF[3]<<1;
               RegF[10]=RegF[5]<<1;
               RegF[11]=RegF[8]+RegF[3];
               RegF[12]=RegF[3]<<2;
               RegF[13]=RegF[4]+RegF[9];
               RegF[14]=RegF[7]<<1;
               
        end
            case(state)                                 //空闲状态，等待除法开始信号到来
            IDLE:begin
               o_busy_1=1;  
               o_done_1=0; 
               zero=0;
               quotient_temp=0;
               remainder_temp=0;  
               state=READY;               
            end
            READY:begin                                 //进行特殊情况的判断，计算除数的1~F倍，发出除法器开始工作信号
                 result={32'b0,dividend};               //将被除数置于结果的低32位，进行迭代
                 cnt=0;
                  if(divisor==0)begin                   //当除数为0时，有符号数运算返回-1，无符号数返回0，然后进入输出状态
                    if(i_divSign_1)begin                          
                            result=-1;
                        end else begin
                            result=0;
                        end
                        zero=0;
                        state=OUT;
                  end else if(dividend==0)begin         //当被除数为0时，零标志位置1，进入输出状态
                        result=0;
                        zero=1;
                        state=OUT;
                  end else begin
//                 level=0;
                      if(divisor>dividend)begin         //当除数大于被除数时，根据符号位返回对应的商，余数等于被除数，进入输出状态
                          if(sign&&i_divSign_1) begin
                             result={i_dividend_32,32'b1};
                          end else begin
                             result={i_dividend_32,32'b0};  
                          end           
                          state=OUT;  
                      end else begin                    //当无特殊情况时，进入计算状态
                          state=WORK;                   
                     end
                 end
            end
            WORK:begin                                 //每一次计算将结果左移4位，然后比较计算得到部分余数与除数的各个倍数的差，从高到低，将小与0的level置0，大于0的置1
                result=result<<4;
                Re[0]={5'b0,result[63:32]};
                Re[1]={5'b0,result[63:32]}-{1'b0,RegF[1]};
                Re[2]={5'b0,result[63:32]}-{1'b0,RegF[2]};
                Re[3]={5'b0,result[63:32]}-{1'b0,RegF[3]};
                Re[4]={5'b0,result[63:32]}-{1'b0,RegF[4]};
                Re[5]={5'b0,result[63:32]}-{1'b0,RegF[5]};
                Re[6]={5'b0,result[63:32]}-{1'b0,RegF[6]};
                Re[7]={5'b0,result[63:32]}-{1'b0,RegF[7]};
                Re[8]={5'b0,result[63:32]}-{1'b0,RegF[8]};
                Re[9]={5'b0,result[63:32]}-{1'b0,RegF[9]};
                Re[10]={5'b0,result[63:32]}-{1'b0,RegF[10]};
                Re[11]={5'b0,result[63:32]}-{1'b0,RegF[11]};
                Re[12]={5'b0,result[63:32]}-{1'b0,RegF[12]};
                Re[13]={5'b0,result[63:32]}-{1'b0,RegF[13]};
                Re[14]={5'b0,result[63:32]}-{1'b0,RegF[14]};
                Re[15]={5'b0,result[63:32]}-{1'b0,RegF[15]};        
                if(Re[1][36])begin
                 level[1]=0;
                end else begin
                 level[1]=1;
                end
                if(Re[2][36])begin
                 level[2]=0;
                end else begin
                 level[2]=1;
                end
                if(Re[3][36])begin
                 level[3]=0;
                end else begin
                 level[3]=1;
                end
                if(Re[4][36])begin
                 level[4]=0;
                end else begin
                 level[4]=1;
                end
                if(Re[5][36])begin
                 level[5]=0;
                end else begin
                 level[5]=1;
                end
                if(Re[6][36])begin
                 level[6]=0;
                end else begin
                 level[6]=1;
                end
                if(Re[7][36])begin
                 level[7]=0;
                end else begin
                 level[7]=1;
                end
                if(Re[8][36])begin
                 level[8]=0;
                end else begin
                 level[8]=1;
                end
                if(Re[9][36])begin
                 level[9]=0;
                end else begin
                 level[9]=1;
                end
                if(Re[10][36])begin
                 level[10]=0;
                end else begin
                 level[10]=1;
                end
                if(Re[11][36])begin
                 level[11]=0;
                end else begin
                 level[11]=1;
                end
                if(Re[12][36])begin
                 level[12]=0;
                end else begin
                 level[12]=1;
                end
                if(Re[13][36])begin
                 level[13]=0;
                end else begin
                 level[13]=1;
                end
                if(Re[14][36])begin
                 level[14]=0;
                end else begin
                 level[14]=1;
                end
                if(Re[15][36])begin
                 level[15]=0;
                end else begin
                 level[15]=1;
                end  
                if(Re[1][36])begin
                 level[1]=0;
                end else begin
                 level[1]=1;
                end
                                 
                state=CMP;                               //进入比较状态              
                end
            CMP: begin
                 if(level>=16'h4000) begin              //通过对level的优先编码，得到第一个level大于0的位数，然后对应位数的值即为应上的商值
                    Quot = 4'hf;
                    end else if(level>=16'h2000&&level<16'h4000) begin
                    Quot = 4'he;
                    end else if(level>=16'h1000&&level<16'h2000) begin
                    Quot = 4'hd;
                    end else if(level>=16'h0800&&level<16'h1000) begin
                    Quot = 4'hc; 
                    end else if(level>=16'h0400&&level<16'h0800) begin
                    Quot = 4'hb;
                    end else if(level>=16'h0200&&level<16'h0400) begin
                    Quot = 4'ha;
                    end else if(level>=16'h0100&&level<16'h0200) begin
                    Quot = 4'h9;
                    end else if(level>=16'h0080&&level<16'h0100) begin
                    Quot = 4'h8;
                    end else if(level>=16'h0040&&level<16'h0080) begin
                    Quot = 4'h7;
                    end else if(level>=16'h0020&&level<16'h0040) begin
                    Quot = 4'h6; 
                    end else if(level>=16'h0010&&level<16'h0020) begin
                    Quot = 4'h5; 
                    end else if(level>=16'h0008&&level<16'h0010) begin
                    Quot = 4'h4;
                    end else if(level>=16'h0004&&level<16'h0008) begin
                    Quot = 4'h3; 
                    end else if(level>=16'h0002&&level<16'h0004) begin
                    Quot = 4'h2;
                    end else if(level>=16'h0001&&level<16'h0002) begin
                    Quot = 4'h1; 
                    end else begin
                    Quot = 4'h0; 
                    end
                result[63:32]=Re[Quot];                                        //找到对应的商值后，更新部分余数
                result[3:0]=Quot;
                cnt=cnt+1;       
                if(cnt==8)begin                                               //迭代次数到8次后进行输出状态，否则继续迭代计算
                    state=OUT;
                end else begin
                    state=WORK;
                end
            end
            OUT:begin
                quotient_temp=result[31:0];                                  //将结果的低32位作为商，高32位作为余数，并发出除法器结束工作信息
                remainder_temp=result[63:32];
                o_done_1=1;
                o_busy_1=0;
                cnt=0; 
                state=IDLE;
            end
            endcase
        end else begin
            cnt=0;
            o_busy_1=0;
            o_done_1=0;
        end
    end
end             
//根据进行有符号数还是无符号数运算以及是否为特殊情况得到最后的符号位与数值位
assign    o_remainder_32[30:0]=(zero)?0:(divisor==0)?i_dividend_32:(i_dividend_32[31]&&i_divSign_1)?(~remainder_temp[30:0]+1):remainder_temp[30:0];
assign    o_remainder_32[31]=(zero)?0:(i_divSign_1&&remainder_temp!=0)?i_dividend_32[31]:remainder_temp[31];
assign    o_quotient_32[30:0]=(zero)?0:(divisor==0)?(31'h7fffffff):((i_divSign_1&&sign))?(~quotient_temp[30:0]+1):quotient_temp[30:0];
assign    o_quotient_32[31]=(zero)?0:(divisor==0)?1:(i_divSign_1)?sign:quotient_temp[31];
endmodule
