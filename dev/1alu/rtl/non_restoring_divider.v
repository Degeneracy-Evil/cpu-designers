`timescale 1ns / 1ps

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
  localparam COMPUTE = 2'b01;  // 非恢复余数迭代
  localparam FIX     = 2'b10;  // 终态余数修正
  localparam FINISH  = 2'b11;  // 完成状态

  reg [1:0] state;
  reg [5:0] count;            // 迭代计数器
  reg [31:0] R;               // 余数寄存器
  reg [31:0] Q;               // 商寄存器(绝对值)
  reg [31:0] D;               // 除数绝对值
  reg sign_dividend;          // 被除数符号
  reg sign_divisor;           // 除数符号
  reg div_zero_case;          // 除零标志
  reg div_overflow_case;      // INT_MIN / -1 溢出标志
  reg [31:0] dividend_reg;    // 缓存原始被除数
  reg [31:0] divisor_reg;     // 缓存原始除数

  // 计算绝对值 - 使用MUX选择，避免?:运算符
  wire [31:0] abs_dividend_comb;
  wire [31:0] abs_divisor_comb;
  wire [31:0] neg_dividend;
  wire [31:0] neg_divisor;
  wire neg_dividend_cout;
  wire neg_divisor_cout;

  cla_adder_32bit neg_dividend_adder(
                    .a(~dividend),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_dividend),
                    .cout(neg_dividend_cout)
                  );

  cla_adder_32bit neg_divisor_adder(
                    .a(~divisor),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_divisor),
                    .cout(neg_divisor_cout)
                  );

  mux_2to1 #(32) mux_abs_dividend(
             .a(dividend),
             .b(neg_dividend),
             .sel(dividend[31]),
             .y(abs_dividend_comb)
           );

  mux_2to1 #(32) mux_abs_divisor(
             .a(divisor),
             .b(neg_divisor),
             .sel(divisor[31]),
             .y(abs_divisor_comb)
           );

  // 非恢复余数核心：先整体左移，再按当前R符号选择R-D或R+D
  wire [31:0] shifted_R;
  assign shifted_R = {R[30:0], Q[31]};

  wire [31:0] r_sub_d;
  wire [31:0] r_add_d;
  wire [31:0] r_next;
  wire q_next_bit;

  wire [31:0] sub_op;
  wire sub_cout;
  wire add_cout;
  wire [31:0] count_ext;
  wire [31:0] count_inc_ext;
  wire count_inc_cout;

  assign sub_op = ~D;
  assign count_ext = {26'b0, count};

  cla_adder_32bit subtracter(
                    .a(shifted_R),
                    .b(sub_op),
                    .cin(1'b1),
                    .sum(r_sub_d),
                    .cout(sub_cout)
                  );

  cla_adder_32bit adder(
                    .a(shifted_R),
                    .b(D),
                    .cin(1'b0),
                    .sum(r_add_d),
                    .cout(add_cout)
                  );

  cla_adder_32bit count_incrementer(
                    .a(count_ext),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(count_inc_ext),
                    .cout(count_inc_cout)
                  );

  mux_2to1 #(32) mux_r_next(
             .a(r_sub_d),
             .b(r_add_d),
             .sel(R[31]),
             .y(r_next)
           );

  // 新余数非负，上商1；新余数为负，上商0
  assign q_next_bit = ~r_next[31];

  // FIX阶段：终态余数为负时执行 R = R + D
  wire [31:0] r_fix_add;
  wire fix_add_cout;

  cla_adder_32bit fix_adder(
                    .a(R),
                    .b(D),
                    .cin(1'b0),
                    .sum(r_fix_add),
                    .cout(fix_add_cout)
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
      div_zero_case <= 1'b0;
      div_overflow_case <= 1'b0;
      dividend_reg <= 32'b0;
      divisor_reg <= 32'b0;
    end
    else
    begin
      case (state)
        IDLE:
        begin
          if (start)
          begin
            dividend_reg <= dividend;
            divisor_reg <= divisor;
            sign_dividend <= dividend[31];
            sign_divisor <= divisor[31];

            if (divisor == 32'b0)
            begin
              // 除零约定：商=0，余数=被除数
              state <= FINISH;
              count <= 6'b0;
              R <= dividend;
              Q <= 32'b0;
              D <= 32'b0;
              div_zero_case <= 1'b1;
              div_overflow_case <= 1'b0;
            end
            else if ((dividend == 32'h8000_0000) && (divisor == 32'hFFFF_FFFF))
            begin
              // 显式处理 INT_MIN / -1 溢出，采用二补码截断语义
              state <= FINISH;
              count <= 6'b0;
              R <= 32'b0;
              Q <= 32'h8000_0000;
              D <= 32'b0;
              div_zero_case <= 1'b0;
              div_overflow_case <= 1'b1;
            end
            else
            begin
              state <= COMPUTE;
              count <= 6'b0;
              R <= 32'b0;
              Q <= abs_dividend_comb;
              D <= abs_divisor_comb;
              div_zero_case <= 1'b0;
              div_overflow_case <= 1'b0;
            end
          end
        end

        COMPUTE:
        begin
          if (count < 6'd32)
          begin
            R <= r_next;
            Q <= {Q[30:0], q_next_bit};
            count <= count_inc_ext[5:0];
          end
          else
          begin
            state <= FIX;
          end
        end

        FIX:
        begin
          if (R[31])
          begin
            R <= r_fix_add;
          end
          state <= FINISH;
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

  // 结果符号处理
  wire result_sign;
  assign result_sign = sign_dividend ^ sign_divisor;

  wire [31:0] neg_Q;
  wire [31:0] neg_R;
  wire [31:0] final_quotient;
  wire [31:0] final_remainder;
  wire neg_q_cout;
  wire neg_r_cout;

  cla_adder_32bit neg_q_adder(
                    .a(~Q),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_Q),
                    .cout(neg_q_cout)
                  );

  cla_adder_32bit neg_r_adder(
                    .a(~R),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_R),
                    .cout(neg_r_cout)
                  );

  mux_2to1 #(32) mux_final_quotient(
             .a(Q),
             .b(neg_Q),
             .sel(result_sign),
             .y(final_quotient)
           );

  mux_2to1 #(32) mux_final_remainder(
             .a(R),
             .b(neg_R),
             .sel(sign_dividend),
             .y(final_remainder)
           );

  // 参考C实现的两类整除特殊修正
  wire operand_same_sign;
  assign operand_same_sign = ~(sign_dividend ^ sign_divisor);

  // 同号整除修正: remainder == divisor -> quotient += 1, remainder -= divisor
  wire same_sign_special_hit;
  assign same_sign_special_hit = (~div_zero_case) & (~div_overflow_case) & operand_same_sign &
         (final_remainder == divisor_reg);

  wire [31:0] rem_minus_divisor;
  wire [31:0] rem_sub_op;
  wire rem_minus_divisor_cout;
  assign rem_sub_op = ~divisor_reg;

  cla_adder_32bit rem_minus_divisor_adder(
                    .a(final_remainder),
                    .b(rem_sub_op),
                    .cin(1'b1),
                    .sum(rem_minus_divisor),
                    .cout(rem_minus_divisor_cout)
                  );

  wire [31:0] quot_plus_one;
  wire quot_plus_one_cout;
  cla_adder_32bit quot_plus_one_adder(
                    .a(final_quotient),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(quot_plus_one),
                    .cout(quot_plus_one_cout)
                  );

  // 异号整除修正: remainder + divisor == 0 -> quotient -= 1, remainder = 0
  wire [31:0] rem_plus_divisor;
  wire rem_plus_divisor_cout;
  cla_adder_32bit rem_plus_divisor_adder(
                    .a(final_remainder),
                    .b(divisor_reg),
                    .cin(1'b0),
                    .sum(rem_plus_divisor),
                    .cout(rem_plus_divisor_cout)
                  );

  wire diff_sign_special_hit;
  assign diff_sign_special_hit = (~div_zero_case) & (~div_overflow_case) & (~operand_same_sign) &
         (rem_plus_divisor == 32'b0);

  wire [31:0] quot_minus_one;
  wire quot_minus_one_cout;
  cla_adder_32bit quot_minus_one_adder(
                    .a(final_quotient),
                    .b(32'hFFFF_FFFF),
                    .cin(1'b0),
                    .sum(quot_minus_one),
                    .cout(quot_minus_one_cout)
                  );

  reg [31:0] corrected_quotient;
  reg [31:0] corrected_remainder;

  always @(*)
  begin
    corrected_quotient = final_quotient;
    corrected_remainder = final_remainder;

    if (same_sign_special_hit)
    begin
      corrected_quotient = quot_plus_one;
      corrected_remainder = rem_minus_divisor;
    end
    else if (diff_sign_special_hit)
    begin
      corrected_quotient = quot_minus_one;
      corrected_remainder = 32'b0;
    end

    if (div_zero_case)
    begin
      corrected_quotient = 32'b0;
      corrected_remainder = dividend_reg;
    end

    if (div_overflow_case)
    begin
      corrected_quotient = 32'h8000_0000;
      corrected_remainder = 32'b0;
    end
  end

  assign quotient = corrected_quotient;
  assign remainder = corrected_remainder;
  assign done = (state == FINISH);

endmodule
