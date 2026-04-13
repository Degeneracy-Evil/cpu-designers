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
  input         req_valid,    // 请求有效
  input         flush,        // 取消当前请求
  input         result_ready, // 结果消费握手
    output [31:0] result,       // 运算结果
  output        alu_busy,     // 乘除法执行中
  output        alu_ready,    // 可接收新请求
  output        result_valid, // 结果有效
  output        illegal_op,   // 非法控制编码
  output        div_by_zero   // 最近一次除法是否为除零
  );

  // 从控制信号提取各操作使能位
  wire alu_mul;
  wire alu_div;
  wire alu_srl;
  wire alu_sra;

  assign alu_mul  = alu_control[15];  // 乘法
  assign alu_div  = alu_control[14];  // 除法
  assign alu_srl  = alu_control[3];   // 逻辑右移
  assign alu_sra  = alu_control[2];   // 算术右移

  // 各运算模块的结果
  wire [31:0] add_result;
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
  wire        div_done;

  // 实例化各运算模块
  cla_adder_32bit adder(
                    .a(src1),
                    .b(src2),
                    .cin(1'b0),
                    .sum(add_result),
                    .cout()
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
  reg result_valid_reg;
  reg div_by_zero_reg;
  reg [31:0] result_hold_reg;
  reg [31:0] mul_src1_reg;
  reg [31:0] mul_src2_reg;
  reg [31:0] div_src1_reg;
  reg [31:0] div_src2_reg;

  // 协议相关解码
  wire [15:0] op_vector;
  wire [15:0] op_vector_minus_1;
  wire has_op;
  wire op_is_onehot;
  wire flush_int;
  wire result_ready_int;
  wire req_fire;
  wire req_mul;
  wire req_div;
  wire req_comb;
  wire [31:0] comb_result;

  assign op_vector = alu_control & 16'hFFFE;
  assign op_vector_minus_1 = op_vector - 16'b1;
  assign has_op = |op_vector;
  assign op_is_onehot = has_op & ((op_vector & op_vector_minus_1) == 16'b0);

  assign flush_int = flush;
  assign result_ready_int = result_ready;

  assign illegal_op = req_valid & (~op_is_onehot);
  assign alu_busy = mul_busy | div_busy;
  assign alu_ready = (~alu_busy) & (~req_hold) & (~result_valid_reg);

  assign req_fire = req_valid & alu_ready & (~illegal_op);
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
      result_valid_reg <= 1'b0;
      div_by_zero_reg <= 1'b0;
      result_hold_reg <= 32'b0;
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
        result_valid_reg <= 1'b0;
        div_by_zero_reg <= 1'b0;
      end
      else
      begin
        if (!req_valid)
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
          result_hold_reg <= mul_result[31:0];
          result_valid_reg <= 1'b1;
        end

        // 除法完成后锁存结果
        if (div_done && (div_busy || div_active))
        begin
          div_busy <= 1'b0;
          div_active <= 1'b0;
          result_hold_reg <= div_quotient;
          result_valid_reg <= 1'b1;
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
          // 组合指令在请求拍采样并发布结果
          result_hold_reg <= comb_result;
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
                          .remainder(),
                          .done(div_done)
                        );

  alu_result_selector result_mux(
                        .mul_result(mul_result[31:0]),
                        .div_result(div_quotient),
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
                        .sel(alu_control),
                        .y(comb_result)
                      );

  assign result = result_hold_reg;

endmodule
