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
    output [31:0] result,       // 运算结果
    output        done          // 完成标志
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
               .and_result(and_result),
               .or_result(or_result),
               .not_result(not_result),
               .xor_result(xor_result),
               .nor_result(nor_result),
               .slt_result(slt_result),
               .sltu_result(sltu_result)
             );

  // 移位器实例 - src1[4:0]为移位量，src2为被移位数
  shifter shift_sll_inst(
            .data(src2),
            .shamt(src1[4:0]),
            .shift_type(2'b00),  // SLL
            .result(sll_result)
          );

  shifter shift_srl_inst(
            .data(src2),
            .shamt(src1[4:0]),
            .shift_type(2'b01),  // SRL
            .result(srl_result)
          );

  shifter shift_sra_inst(
            .data(src2),
            .shamt(src1[4:0]),
            .shift_type(2'b10),  // SRA
            .result(sra_result)
          );

  lui lui_inst(
        .imm(src2),
        .result(lui_result)
      );

  // 乘除法需要寄存输入，因为它们需要多个周期
  reg mul_start;
  reg div_start;
  reg [31:0] mul_src1_reg;
  reg [31:0] mul_src2_reg;
  reg [31:0] div_src1_reg;
  reg [31:0] div_src2_reg;

  // 乘除法启动控制
  always @(posedge clk or posedge reset)
  begin
    if (reset)
    begin
      mul_start <= 1'b0;
      div_start <= 1'b0;
      mul_src1_reg <= 32'b0;
      mul_src2_reg <= 32'b0;
      div_src1_reg <= 32'b0;
      div_src2_reg <= 32'b0;
    end
    else
    begin
      // 乘法启动
      if (alu_mul && !mul_start)
      begin
        mul_start <= 1'b1;
        mul_src1_reg <= src1;
        mul_src2_reg <= src2;
      end
      else if (mul_done)
      begin
        mul_start <= 1'b0;
      end

      // 除法启动
      if (alu_div && !div_start)
      begin
        div_start <= 1'b1;
        div_src1_reg <= src1;
        div_src2_reg <= src2;
      end
      else if (div_done)
      begin
        div_start <= 1'b0;
      end
    end
  end

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

  wire [31:0] mul_result_low;
  assign mul_result_low = mul_result[31:0];  // 取低32位

  // ALU结果选择器 - 根据控制信号选择对应运算结果
  // 使用MUX模块替代?:运算符，避免被推断为IP核
  alu_result_selector result_mux(
                        .mul_result(mul_result_low),
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
                        .y(result)
                      );

  // done信号选择 - 使用MUX避免?:运算符
  wire done_comb;
  wire done_mul_sel;
  wire done_div_sel;
  wire done_default;

  assign done_default = 1'b1;  // 组合逻辑运算立即完成

  mux_2to1 #(1) mux_done_0(
             .a(done_default),
             .b(div_done),
             .sel(alu_div),
             .y(done_div_sel)
           );

  mux_2to1 #(1) mux_done_1(
             .a(done_div_sel),
             .b(mul_done),
             .sel(alu_mul),
             .y(done)
           );

endmodule
