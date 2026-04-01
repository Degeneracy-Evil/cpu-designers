`timescale 1ns / 1ps

// 非恢复余数除法器 - 支持32位有符号数除法
// 算法: Restoring Division算法
// 周期: 32个时钟周期完成
module non_restoring_divider(
    input         clk,
    input         reset,
    input  [31:0] dividend,   // 被除数
    input  [31:0] divisor,    // 除数
    input         start,      // 开始信号
    output [31:0] quotient,   // 商
    output [31:0] remainder,  // 余数
    output        done        // 完成标志
  );

  // 状态机状态定义
  localparam IDLE    = 2'b00;  // 空闲状态
  localparam COMPUTE = 2'b01;  // 计算状态
  localparam FINISH  = 2'b10;  // 完成状态

  reg [1:0] state;
  reg [5:0] count;         // 迭代计数器
  reg [31:0] R;            // 余数寄存器
  reg [31:0] Q;            // 商寄存器
  reg [31:0] D;            // 除数寄存器
  reg sign_dividend;       // 被除数符号
  reg sign_divisor;        // 除数符号

  // 移位后的R和Q
  wire [31:0] shifted_R;
  wire shifted_Q_msb;

  assign shifted_R = {R[30:0], Q[31]};  // R左移1位，低位补Q[31]
  assign shifted_Q_msb = Q[30];

  // 减法和加法结果
  wire [31:0] sub_result;
  wire [31:0] add_result;
  wire sub_cout;
  wire add_cout;

  wire [31:0] sub_op;
  assign sub_op = ~D;  // 用于减法

  // 减法器: shifted_R - D
  cla_adder_32bit subtracter(
                    .a(shifted_R),
                    .b(sub_op),
                    .cin(1'b1),
                    .sum(sub_result),
                    .cout(sub_cout)
                  );

  // 加法器: sub_result + D (用于恢复)
  cla_adder_32bit adder(
                    .a(sub_result),
                    .b(D),
                    .cin(1'b0),
                    .sum(add_result),
                    .cout(add_cout)
                  );

  // 计算绝对值 - 使用MUX选择，避免?:运算符
  wire [31:0] abs_dividend_comb;
  wire [31:0] abs_divisor_comb;

  wire [31:0] neg_dividend;
  wire [31:0] neg_divisor;

  assign neg_dividend = ~dividend + 1'b1;
  assign neg_divisor = ~divisor + 1'b1;

  mux_2to1 #(32) mux_abs_dividend(
             .a(dividend),
             .b(neg_dividend),
             .sel(dividend[31]),  // 如果为负，选择负值(即绝对值)
             .y(abs_dividend_comb)
           );

  mux_2to1 #(32) mux_abs_divisor(
             .a(divisor),
             .b(neg_divisor),
             .sel(divisor[31]),
             .y(abs_divisor_comb)
           );

  // 状态机
  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      state <= IDLE;
      count <= 6'b0;
      R <= 32'b0;
      Q <= 32'b0;
      D <= 32'b0;
      sign_dividend <= 1'b0;
      sign_divisor <= 1'b0;
    end
    else
    begin
      case (state)
        IDLE:
        begin
          if (start)
          begin
            state <= COMPUTE;
            count <= 6'b0;
            R <= 32'b0;
            Q <= abs_dividend_comb;  // 使用绝对值计算
            D <= abs_divisor_comb;
            sign_dividend <= dividend[31];
            sign_divisor <= divisor[31];
          end
        end

        COMPUTE:
        begin
          if (count < 32)
          begin
            // Restoring Division核心算法
            if (sub_result[31])
            begin
              // R < 0: 恢复R，Q[0]=0
              R <= shifted_R;
              Q <= {Q[30:0], 1'b0};
            end
            else
            begin
              // R >= 0: 不恢复，Q[0]=1
              R <= sub_result;
              Q <= {Q[30:0], 1'b1};
            end
            count <= count + 1'b1;
          end
          else
          begin
            state <= FINISH;
          end
        end

        FINISH:
        begin
          state <= IDLE;
        end

        default:
          state <= IDLE;
      endcase
    end
  end

  // 处理结果符号
  wire result_sign;
  assign result_sign = sign_dividend ^ sign_divisor;  // 商的符号

  wire [31:0] final_quotient;
  wire [31:0] final_remainder;

  wire [31:0] neg_Q;
  wire [31:0] neg_R;

  assign neg_Q = ~Q + 1'b1;
  assign neg_R = ~R + 1'b1;

  // 根据符号选择最终结果 - 使用MUX避免?:运算符
  mux_2to1 #(32) mux_final_quotient(
             .a(Q),
             .b(neg_Q),
             .sel(result_sign),  // 如果符号不同，取负
             .y(final_quotient)
           );

  mux_2to1 #(32) mux_final_remainder(
             .a(R),
             .b(neg_R),
             .sel(sign_dividend),  // 余数符号与被除数相同
             .y(final_remainder)
           );

  assign quotient = final_quotient;
  assign remainder = final_remainder;
  assign done = (state == FINISH);

endmodule
