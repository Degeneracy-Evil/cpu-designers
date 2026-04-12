`timescale 1ns / 1ps

// 32位ALU顶层模块
// 支持15种运算: MUL, DIV, NOT, ADD, SUB, SLT, SLTU, AND, NOR, OR, XOR, SLL, SRL, SRA, LUI
// 控制信号: 16位one-hot编码
module alu_32bit(
    input         clk,
    input         reset,
    input  [15:0] alu_control,  // ALU控制信号(one-hot)
    input  [31:0] src1,         // 源操作数1
    input  [31:0] src2,         // 源操作数2
  input         req_valid,    // 可选请求有效(未连接时保持兼容模式)
  input         flush,        // 可选取消当前请求
  input         result_ready, // 可选结果消费握手
    output [31:0] result,       // 运算结果
  output        done,         // 兼容完成标志
  output        alu_busy,     // 乘除法执行中
  output        alu_ready,    // 可接收新请求
  output        result_valid, // 结果有效(含多周期/握手模式)
  output        illegal_op,   // 非法控制编码
  output        div_by_zero   // 最近一次除法是否为除零
  );

  // 从控制信号提取各操作使能位
  wire alu_mul;
  wire alu_div;
  wire alu_not;
  wire alu_add;
  wire alu_sub;
  wire alu_slt;
  wire alu_sltu;
  wire alu_and;
  wire alu_nor;
  wire alu_or;
  wire alu_xor;
  wire alu_sll;
  wire alu_srl;
  wire alu_sra;
  wire alu_lui;

  assign alu_mul  = alu_control[15];  // 乘法
  assign alu_div  = alu_control[14];  // 除法
  assign alu_not  = alu_control[13];  // 按位取反
  assign alu_add  = alu_control[12];  // 加法
  assign alu_sub  = alu_control[11];  // 减法
  assign alu_slt  = alu_control[10];  // 有符号比较
  assign alu_sltu = alu_control[9];   // 无符号比较
  assign alu_and  = alu_control[8];   // 按位与
  assign alu_nor  = alu_control[7];   // 按位或非
  assign alu_or   = alu_control[6];   // 按位或
  assign alu_xor  = alu_control[5];   // 按位异或
  assign alu_sll  = alu_control[4];   // 逻辑左移
  assign alu_srl  = alu_control[3];   // 逻辑右移
  assign alu_sra  = alu_control[2];   // 算术右移
  assign alu_lui  = alu_control[1];   // 高位加载

  // 各运算模块的结果
  wire [31:0] add_result;
  wire        add_cout;
  wire [31:0] sub_result;
  wire        sub_borrow;
  wire [31:0] and_result;
  wire [31:0] or_result;
  wire [31:0] not_result;
  wire [31:0] xor_result;
  wire [31:0] nor_result;
  wire [31:0] slt_result;
  wire [31:0] sltu_result;
  wire [31:0] sll_result;
  wire [31:0] srl_result;
  wire [31:0] sra_result;
  wire [31:0] shift_result;
  wire [31:0] lui_result;
  wire [63:0] mul_result;
  wire        mul_done;
  wire [31:0] div_quotient;
  wire [31:0] div_remainder;
  wire        div_done;

  // 实例化各运算模块
  cla_adder_32bit adder(
                    .a(src1),
                    .b(src2),
                    .cin(1'b0),
                    .sum(add_result),
                    .cout(add_cout)
                  );

  subtractor sub(
               .a(src1),
               .b(src2),
               .result(sub_result),
               .borrow(sub_borrow)
             );

  logic_unit logic_inst(
               .a(src1),
               .b(src2),
               .sub_result(sub_result),
               .sub_borrow(sub_borrow),
               .and_result(and_result),
               .or_result(or_result),
               .not_result(not_result),
               .xor_result(xor_result),
               .nor_result(nor_result),
               .slt_result(slt_result),
               .sltu_result(sltu_result)
             );

  // 单实例移位器复用，减少面积与输入扇出
  wire [1:0] shift_type;
  assign shift_type = ({2{alu_srl}} & 2'b01) | ({2{alu_sra}} & 2'b10);

  shifter shift_inst(
            .data(src2),
            .shamt(src1[4:0]),
            .shift_type(shift_type),
            .result(shift_result)
          );

  assign sll_result = shift_result;
  assign srl_result = shift_result;
  assign sra_result = shift_result;

  lui lui_inst(
        .imm(src2),
        .result(lui_result)
      );

  // 乘除法需要寄存输入，因为它们需要多个周期
  reg mul_start;
  reg div_start;
  reg mul_busy;
  reg div_busy;
  reg mul_active;
  reg div_active;
  reg req_hold;
  reg mul_done_hold;
  reg div_done_hold;
  reg result_valid_reg;
  reg div_by_zero_reg;
  reg [31:0] result_hold_reg;
  reg [31:0] mul_result_reg;
  reg [31:0] div_result_reg;
  reg [31:0] mul_src1_reg;
  reg [31:0] mul_src2_reg;
  reg [31:0] div_src1_reg;
  reg [31:0] div_src2_reg;

  // 协议相关解码
  wire [15:0] op_vector;
  wire [15:0] op_vector_minus_1;
  wire has_op;
  wire op_is_onehot;
  wire req_valid_driven;
  wire req_valid_int;
  wire flush_int;
  wire result_ready_int;
  wire req_fire;
  wire req_mul;
  wire req_div;
  wire req_comb;

  assign op_vector = alu_control & 16'hFFFE;
  assign op_vector_minus_1 = op_vector - 16'b1;
  assign has_op = |op_vector;
  assign op_is_onehot = has_op & ((op_vector & op_vector_minus_1) == 16'b0);

  // 输入未连接时退回 legacy 行为：只看 alu_control 是否非零
  assign req_valid_driven = (req_valid === 1'b0) | (req_valid === 1'b1);
  assign req_valid_int = req_valid_driven ? (req_valid === 1'b1) : has_op;
  assign flush_int = (flush === 1'b1);
  assign result_ready_int = (result_ready === 1'b0) ? 1'b0 : 1'b1;

  assign illegal_op = req_valid_int & (~op_is_onehot);
  assign alu_busy = mul_busy | div_busy;
  assign alu_ready = (~alu_busy) & (~req_hold) & (~result_valid_reg);

  assign req_fire = req_valid_int & alu_ready & (~illegal_op);
  assign req_mul = req_fire & alu_mul;
  assign req_div = req_fire & alu_div;
  assign req_comb = req_fire & (~alu_mul) & (~alu_div);

  // 乘除法启动控制
  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      mul_start <= 1'b0;
      div_start <= 1'b0;
      mul_busy <= 1'b0;
      div_busy <= 1'b0;
      mul_active <= 1'b0;
      div_active <= 1'b0;
      req_hold <= 1'b0;
      mul_done_hold <= 1'b0;
      div_done_hold <= 1'b0;
      result_valid_reg <= 1'b0;
      div_by_zero_reg <= 1'b0;
      result_hold_reg <= 32'b0;
      mul_result_reg <= 32'b0;
      div_result_reg <= 32'b0;
      mul_src1_reg <= 32'b0;
      mul_src2_reg <= 32'b0;
      div_src1_reg <= 32'b0;
      div_src2_reg <= 32'b0;
    end
    else
    begin
      // 默认将start拉低，形成单周期脉冲
      mul_start <= 1'b0;
      div_start <= 1'b0;
      if (flush_int)
      begin
        mul_busy <= 1'b0;
        div_busy <= 1'b0;
        mul_active <= 1'b0;
        div_active <= 1'b0;
        req_hold <= 1'b0;
        mul_done_hold <= 1'b0;
        div_done_hold <= 1'b0;
        result_valid_reg <= 1'b0;
        div_by_zero_reg <= 1'b0;
      end
      else
      begin
        if (!req_valid_int)
        begin
          req_hold <= 1'b0;
        end
        else if (req_fire || illegal_op)
        begin
          req_hold <= 1'b1;
        end

        if (result_valid_reg && result_ready_int)
        begin
          result_valid_reg <= 1'b0;
        end

        // 乘法完成后锁存结果
        if (mul_done && (mul_busy || mul_active))
        begin
          mul_busy <= 1'b0;
          mul_active <= 1'b0;
          mul_done_hold <= 1'b1;
          mul_result_reg <= mul_result[31:0];
          result_hold_reg <= mul_result[31:0];
          result_valid_reg <= 1'b1;
        end
        else if (!alu_mul)
        begin
          mul_done_hold <= 1'b0;
        end

        // 除法完成后锁存结果
        if (div_done && (div_busy || div_active))
        begin
          div_busy <= 1'b0;
          div_active <= 1'b0;
          div_done_hold <= 1'b1;
          div_result_reg <= div_quotient;
          result_hold_reg <= div_quotient;
          result_valid_reg <= 1'b1;
        end
        else if (!alu_div)
        begin
          div_done_hold <= 1'b0;
        end

        if (req_mul)
        begin
          mul_start <= 1'b1;
          mul_busy <= 1'b1;
          mul_active <= 1'b1;
          mul_src1_reg <= src1;
          mul_src2_reg <= src2;
          div_by_zero_reg <= 1'b0;
        end
        else if (req_div)
        begin
          div_start <= 1'b1;
          div_busy <= 1'b1;
          div_active <= 1'b1;
          div_src1_reg <= src1;
          div_src2_reg <= src2;
          div_by_zero_reg <= (src2 == 32'b0);
        end
        else if (req_comb)
        begin
          // 组合指令在握手模式下提供一次性result_valid脉冲
          result_hold_reg <= legacy_result;
          result_valid_reg <= 1'b1;
          div_by_zero_reg <= 1'b0;
        end
      end
    end
  end

  assign div_by_zero = div_by_zero_reg;
  assign result_valid = result_valid_reg;

  booth_multiplier multiplier(
                     .clk(clk),
                     .reset(reset),
                     .multiplicand(mul_src1_reg),
                     .multiplier(mul_src2_reg),
                     .start(mul_start),
                     .product(mul_result),
                     .done(mul_done)
                   );

  non_restoring_divider divider(
                          .clk(clk),
                          .reset(reset),
                          .dividend(div_src1_reg),
                          .divisor(div_src2_reg),
                          .start(div_start),
                          .quotient(div_quotient),
                          .remainder(div_remainder),
                          .done(div_done)
                        );

  // 根据当前活动状态固定多周期选择，避免控制位提前撤销导致结果丢失
  wire mul_select_active;
  wire div_select_active;
  wire [15:0] result_sel_div;
  wire [15:0] result_sel;
  wire [31:0] legacy_result;

  assign mul_select_active = alu_mul | mul_active | mul_busy | mul_done_hold;
  assign div_select_active = (~mul_select_active) & (alu_div | div_active | div_busy | div_done_hold);

  mux_2to1 #(16) mux_result_sel_0(
             .a(alu_control),
             .b(16'b0100_0000_0000_0000),
             .sel(div_select_active),
             .y(result_sel_div)
           );

  mux_2to1 #(16) mux_result_sel_1(
             .a(result_sel_div),
             .b(16'b1000_0000_0000_0000),
             .sel(mul_select_active),
             .y(result_sel)
           );

  // ALU结果选择器
  alu_result_selector result_mux(
                        .mul_result(mul_result_reg),
                        .div_result(div_result_reg),
                        .not_result(not_result),
                        .add_result(add_result),
                        .sub_result(sub_result),
                        .slt_result(slt_result),
                        .sltu_result(sltu_result),
                        .and_result(and_result),
                        .nor_result(nor_result),
                        .or_result(or_result),
                        .xor_result(xor_result),
                        .sll_result(sll_result),
                        .srl_result(srl_result),
                        .sra_result(sra_result),
                        .lui_result(lui_result),
                        .sel(result_sel),
                        .y(legacy_result)
                      );

  mux_2to1 #(32) mux_result_out(
             .a(legacy_result),
             .b(result_hold_reg),
             .sel(result_valid_reg),
             .y(result)
           );

  // done信号选择
  wire mul_done_stable;
  wire div_done_stable;
  wire done_div_sel;
  wire done_default;

  assign mul_done_stable = mul_done | mul_done_hold;
  assign div_done_stable = div_done | div_done_hold;
  assign done_default = 1'b1;

  mux_2to1 #(1) mux_done_0(
             .a(done_default),
             .b(div_done_stable),
             .sel(div_select_active),
             .y(done_div_sel)
           );

  mux_2to1 #(1) mux_done_1(
             .a(done_div_sel),
             .b(mul_done_stable),
             .sel(mul_select_active),
             .y(done)
           );

endmodule
