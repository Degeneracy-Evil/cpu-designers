`timescale 1ns / 1ps

module non_restoring_divider(
    input         clk,
    input         reset,
    input  [31:0] dividend,
    input  [31:0] divisor,
    input         start,
    input         is_unsigned,
    output [31:0] quotient,
    output [31:0] remainder,
    output        done
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
  reg sign_dividend;
  reg sign_divisor;
  reg div_zero_case;
  reg div_overflow_case;
  reg [31:0] dividend_reg;
  reg [31:0] divisor_reg;
  wire [31:0] abs_dividend_comb;
  wire [31:0] abs_divisor_comb;
  wire [31:0] neg_dividend;
  wire [31:0] neg_divisor;

  wire abs_dividend_sel;
  wire abs_divisor_sel;
  assign abs_dividend_sel = is_unsigned ? 1'b0 : dividend[31];
  assign abs_divisor_sel  = is_unsigned ? 1'b0 : divisor[31];

  wire unsigned_large_div;
  assign unsigned_large_div = is_unsigned & divisor[31];

  wire unsigned_ge;
  assign unsigned_ge = dividend[31] & (divisor[31] ? (dividend[30:0] >= divisor[30:0]) : 1'b1);

  wire [31:0] dividend_sub_divisor;
  wire [31:0] div_sub_op;
  assign div_sub_op = ~divisor;

  cla_adder_32bit unsigned_sub_adder(
                    .a(dividend),
                    .b(div_sub_op),
                    .cin(1'b1),
                    .sum(dividend_sub_divisor),
                    .cout()
                  );

  cla_adder_32bit neg_dividend_adder(
                    .a(~dividend),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_dividend),
                    .cout()
                  );

  cla_adder_32bit neg_divisor_adder(
                    .a(~divisor),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_divisor),
                    .cout()
                  );

  mux_2to1 #(32) mux_abs_dividend(
             .a(dividend),
             .b(neg_dividend),
             .sel(abs_dividend_sel),
             .y(abs_dividend_comb)
           );

  mux_2to1 #(32) mux_abs_divisor(
             .a(divisor),
             .b(neg_divisor),
             .sel(abs_divisor_sel),
             .y(abs_divisor_comb)
           );

  // 非恢复余数核心：先整体左移，再按当前R符号选择R-D或R+D
  wire [31:0] shifted_R;
  assign shifted_R = {R[30:0], Q[31]};

  wire [31:0] r_sub_d;
  wire [31:0] r_add_d;
  wire [31:0] r_next;
  wire q_next_bit;

  wire [5:0] count_next;
  assign count_next = count + 6'd1;

  wire [31:0] sub_op;
  assign sub_op = ~D;

  cla_adder_32bit subtracter(
                    .a(shifted_R),
                    .b(sub_op),
                    .cin(1'b1),
                    .sum(r_sub_d),
                    .cout()
                  );

  cla_adder_32bit adder(
                    .a(shifted_R),
                    .b(D),
                    .cin(1'b0),
                    .sum(r_add_d),
                    .cout()
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

  cla_adder_32bit fix_adder(
                    .a(R),
                    .b(D),
                    .cin(1'b0),
                    .sum(r_fix_add),
                    .cout()
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
            sign_dividend <= is_unsigned ? 1'b0 : dividend[31];
            sign_divisor <= is_unsigned ? 1'b0 : divisor[31];

            if (divisor == 32'b0)
            begin
              state <= FINISH;
              count <= 6'b0;
              R <= dividend;
              Q <= 32'hFFFF_FFFF;
              D <= 32'b0;
              div_zero_case <= 1'b1;
              div_overflow_case <= 1'b0;
            end
            else if (!is_unsigned && (dividend == 32'h8000_0000) && (divisor == 32'hFFFF_FFFF))
            begin
              state <= FINISH;
              count <= 6'b0;
              R <= 32'b0;
              Q <= 32'h8000_0000;
              D <= 32'b0;
              div_zero_case <= 1'b0;
              div_overflow_case <= 1'b1;
            end
            else if (unsigned_large_div)
            begin
              state <= FINISH;
              count <= 6'b0;
              D <= 32'b0;
              div_zero_case <= 1'b0;
              div_overflow_case <= 1'b0;
              if (unsigned_ge)
              begin
                Q <= 32'd1;
                R <= dividend_sub_divisor;
              end
              else
              begin
                Q <= 32'd0;
                R <= dividend;
              end
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
            count <= count_next;
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

  cla_adder_32bit neg_q_adder(
                    .a(~Q),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_Q),
                    .cout()
                  );

  cla_adder_32bit neg_r_adder(
                    .a(~R),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(neg_R),
                    .cout()
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
  assign operand_same_sign = ~result_sign;

  // 同号整除修正: remainder == divisor -> quotient += 1, remainder -= divisor
  wire same_sign_special_hit;
  assign same_sign_special_hit = (~div_zero_case) & (~div_overflow_case) & operand_same_sign &
         (final_remainder == divisor_reg);

  wire [31:0] rem_minus_divisor;
  wire [31:0] rem_sub_op;
  assign rem_sub_op = ~divisor_reg;

  cla_adder_32bit rem_minus_divisor_adder(
                    .a(final_remainder),
                    .b(rem_sub_op),
                    .cin(1'b1),
                    .sum(rem_minus_divisor),
                    .cout()
                  );

  wire [31:0] quot_plus_one;
  cla_adder_32bit quot_plus_one_adder(
                    .a(final_quotient),
                    .b(32'b0),
                    .cin(1'b1),
                    .sum(quot_plus_one),
                    .cout()
                  );

  // 异号整除修正: remainder + divisor == 0 -> quotient -= 1, remainder = 0
  wire [31:0] rem_plus_divisor;
  cla_adder_32bit rem_plus_divisor_adder(
                    .a(final_remainder),
                    .b(divisor_reg),
                    .cin(1'b0),
                    .sum(rem_plus_divisor),
                    .cout()
                  );

  wire diff_sign_special_hit;
  assign diff_sign_special_hit = (~div_zero_case) & (~div_overflow_case) & (~operand_same_sign) &
         (rem_plus_divisor == 32'b0);

  wire [31:0] quot_minus_one;
  cla_adder_32bit quot_minus_one_adder(
                    .a(final_quotient),
                    .b(32'hFFFF_FFFF),
                    .cin(1'b0),
                    .sum(quot_minus_one),
                    .cout()
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
      corrected_quotient = 32'hFFFF_FFFF;
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
