`timescale 1ns / 1ps

module alu_32bit(
    input  [15:0] alu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    output [31:0] result
  );

  wire alu_srl;
  wire alu_sra;

  assign alu_srl  = alu_control[3];
  assign alu_sra  = alu_control[2];

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
  wire [31:0] shift_result;
  wire [31:0] lui_result;

  wire is_sub;
  assign is_sub = alu_control[11] | alu_control[10] | alu_control[9];

  wire [31:0] b_neg;
  wire [31:0] adder_b;
  wire        adder_cin;
  wire        adder_cout;

  assign b_neg    = ~src2;
  assign adder_b  = is_sub ? b_neg : src2;
  assign adder_cin = is_sub;

  cla_adder_32bit adder(
                    .a(src1),
                    .b(adder_b),
                    .cin(adder_cin),
                    .sum(add_result),
                    .cout(adder_cout)
                  );

  assign sub_result = add_result;
  assign sub_borrow = ~adder_cout;

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

  wire [1:0] shift_type;
  assign shift_type = ({2{alu_srl}} & 2'b01) | ({2{alu_sra}} & 2'b10);

  shifter shift_inst(
            .data(src1),
            .shamt(src2[4:0]),
            .shift_type(shift_type),
            .result(shift_result)
          );

  lui lui_inst(
        .imm(src2),
        .result(lui_result)
      );

  alu_result_selector result_mux(
                        .not_result(not_result),
                        .add_result(add_result),
                        .sub_result(sub_result),
                        .slt_result(slt_result),
                        .sltu_result(sltu_result),
                        .and_result(and_result),
                        .nor_result(nor_result),
                        .or_result(or_result),
                        .xor_result(xor_result),
                        .sll_result(shift_result),
                        .srl_result(shift_result),
                        .sra_result(shift_result),
                        .lui_result(lui_result),
                        .sel(alu_control),
                        .y(result)
                      );

endmodule
