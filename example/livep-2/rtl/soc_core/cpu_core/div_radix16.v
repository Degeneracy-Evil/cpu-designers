module div_radix16 (
  input clk,
  input rst,
  input en,
  input signed_div,
  input [31:0] i_dividend,
  input [31:0] i_divisor,
  output  [31:0] quotient,
  output  [31:0] remainder,
  output reg done,busy
);
    parameter IDLE  =2'b00;
    parameter READY =2'b01;
    parameter WORK  =2'b10;
    parameter OUT   =2'b11;
    reg [1:0]   state;
    wire [31:0] dividend,divisor;
    reg [31:0] quotient_temp,remainder_temp;
    reg [35:0]  RegF[16:1];
    wire [36:0]  Re[15:1];
    reg [3:0]   cnt;
    reg[63:0]   result;
    reg [3:0]   Quot;
    wire [15:1]   level;
    wire sign;

    
transform trans(.i_num1(i_dividend),.i_num2(i_divisor),.i_sign(signed_div),.sign(sign),.num1(dividend),.num2(divisor));
    

always@(posedge clk or negedge rst)begin
    if(~rst)begin
    done=0;
    busy=0;
    cnt=0;
    result=0;
    Quot=0;
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
    end else begin
        if(en)begin
          if(cnt==0)begin
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
            case(state)
            IDLE:begin
               busy=1;  
               done=0; 
               quotient_temp=0;
               remainder_temp=0;
               if(i_divisor==0)begin
                   result=0;
                   state=OUT;
               end begin
                   state=READY;
               end
            end
            READY:begin
                 result={32'b0,dividend};
                 cnt=0;
                  if(divisor>dividend)begin
                      if(sign) begin
                         result={i_dividend,32'b1};
                      end else begin
                         result={i_dividend,32'b0};  
                      end           
                      state=OUT;  
                  end else begin
                     result=result<<4;
                     state=WORK;                   
                 end
            end
            WORK:begin
                if(level>=16'h4000) begin
                Quot = 4'hf; result[63:32]=Re[15];
                end else if(level>=16'h2000&&level<16'h4000) begin
                Quot = 4'he; result[63:32]=Re[14];
                end else if(level>=16'h1000&&level<16'h2000) begin
                Quot = 4'hd; result[63:32]=Re[13];
                end else if(level>=16'h0800&&level<16'h1000) begin
                Quot = 4'hc; result[63:32]=Re[12];
                end else if(level>=16'h0400&&level<16'h0800) begin
                Quot = 4'hb; result[63:32]=Re[11];
                end else if(level>=16'h0200&&level<16'h0400) begin
                Quot = 4'ha; result[63:32]=Re[10];
                end else if(level>=16'h0100&&level<16'h0200) begin
                Quot = 4'h9; result[63:32]=Re[9];
                end else if(level>=16'h0080&&level<16'h0100) begin
                Quot = 4'h8; result[63:32]=Re[8];
                end else if(level>=16'h0040&&level<16'h0080) begin
                Quot = 4'h7; result[63:32]=Re[7];
                end else if(level>=16'h0020&&level<16'h0040) begin
                Quot = 4'h6; result[63:32]=Re[6];
                end else if(level>=16'h0010&&level<16'h0020) begin
                Quot = 4'h5; result[63:32]=Re[5];
                end else if(level>=16'h0008&&level<16'h0010) begin
                Quot = 4'h4; result[63:32]=Re[4];
                end else if(level>=16'h0004&&level<16'h0008) begin
                Quot = 4'h3; result[63:32]=Re[3];
                end else if(level>=16'h0002&&level<16'h0004) begin
                Quot = 4'h2; result[63:32]=Re[2];
                end else if(level>=16'h0001&&level<16'h0002) begin
                Quot = 4'h1; result[63:32]=Re[1];
                end else begin
                 Quot = 4'h0; 
                end
                result=result<<4;    
                result[3:0]=Quot;
                cnt=cnt+1;       
                if(cnt==8)begin
                    state=OUT;
                end
            end
            OUT:begin
                quotient_temp=result[31:0];
                remainder_temp=result[63:32];
                done=1;
                busy=0;
                cnt=0; 
                state=IDLE;
            end
            endcase
        end else begin
        cnt=0;
        busy=0;
        done=0;
        end
    end
end

assign    Re[1]={5'b0,result[63:32]}-{1'b0,RegF[1]};
assign    Re[2]={5'b0,result[63:32]}-{1'b0,RegF[2]};
assign    Re[3]={5'b0,result[63:32]}-{1'b0,RegF[3]};
assign    Re[4]={5'b0,result[63:32]}-{1'b0,RegF[4]};
assign    Re[5]={5'b0,result[63:32]}-{1'b0,RegF[5]};
assign    Re[6]={5'b0,result[63:32]}-{1'b0,RegF[6]};
assign    Re[7]={5'b0,result[63:32]}-{1'b0,RegF[7]};
assign    Re[8]={5'b0,result[63:32]}-{1'b0,RegF[8]};
assign    Re[9]={5'b0,result[63:32]}-{1'b0,RegF[9]};
assign    Re[10]={5'b0,result[63:32]}-{1'b0,RegF[10]};
assign    Re[11]={5'b0,result[63:32]}-{1'b0,RegF[11]};
assign    Re[12]={5'b0,result[63:32]}-{1'b0,RegF[12]};
assign    Re[13]={5'b0,result[63:32]}-{1'b0,RegF[13]};
assign    Re[14]={5'b0,result[63:32]}-{1'b0,RegF[14]};
assign    Re[15]={5'b0,result[63:32]}-{1'b0,RegF[15]};


  
assign    level[1]=(Re[1][36])?0:1;
assign    level[2]=(Re[2][36])?0:1;
assign    level[3]=(Re[3][36])?0:1;
assign    level[4]=(Re[4][36])?0:1;
assign    level[5]=(Re[5][36])?0:1;
assign    level[6]=(Re[6][36])?0:1;
assign    level[7]=(Re[7][36])?0:1;
assign    level[8]=(Re[8][36])?0:1;
assign    level[9]=(Re[9][36])?0:1;
assign    level[10]=(Re[10][36])?0:1;
assign    level[11]=(Re[11][36])?0:1;
assign    level[12]=(Re[12][36])?0:1;
assign    level[13]=(Re[13][36])?0:1;
assign    level[14]=(Re[14][36])?0:1;
assign    level[15]=(Re[15][36])?0:1;  
             
assign    remainder[30:0]=remainder_temp[30:0];
assign    remainder[31]=(signed_div&&remainder_temp!=0)?i_dividend[31]:remainder_temp[31];
assign    quotient[30:0]=quotient_temp[30:0];
assign    quotient[31]=(signed_div)?sign:quotient_temp[31];
endmodule