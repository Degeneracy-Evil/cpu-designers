`timescale 1ns / 1ps

module mu_unit(
    input         clk,
    input         resetn,
    input  [2:0]  mu_funct3,
    input  [31:0] src1,
    input  [31:0] src2,
    input         req_valid,
    input         flush,
    input         result_got,
    output [31:0] result,
    output        mu_busy,
    output        mu_ready,
    output        result_valid,
    output        div_by_zero
  );

  wire is_mul     = ~mu_funct3[2];
  wire is_div_rem = mu_funct3[2];
  wire is_rem_op  = mu_funct3[2] & mu_funct3[1];
  wire is_unsigned_op = mu_funct3[2] & mu_funct3[0];

  wire [63:0] mul_result;
  wire        mul_done;
  wire [31:0] div_quotient;
  wire [31:0] div_remainder;
  wire        div_done;

  reg mul_start;
  reg div_start;
  reg mul_busy;
  reg div_busy;
  reg req_hold;
  reg result_valid_reg;
  reg div_by_zero_reg;
  reg [31:0] result_hold_reg;
  reg [31:0] mul_src1_reg;
  reg [31:0] mul_src2_reg;
  reg [31:0] div_src1_reg;
  reg [31:0] div_src2_reg;
  reg [2:0]  mu_funct3_reg;

  wire req_fire;
  wire req_mul;
  wire req_div_rem;

  assign mu_busy = mul_busy | div_busy;
  assign mu_ready = (~mu_busy) & (~req_hold) & (~result_valid_reg);

  assign req_fire = req_valid & mu_ready & (is_mul | is_div_rem);
  assign req_mul = req_fire & is_mul;
  assign req_div_rem = req_fire & is_div_rem;

  wire [31:0] mul_upper = mul_result[63:32];
  wire [31:0] mul_lower = mul_result[31:0];

  wire [31:0] mulhsu_correction = mul_src2_reg[31] ? mul_src1_reg : 32'b0;
  wire [31:0] mulhu_extra       = mul_src1_reg[31] ? mul_src2_reg : 32'b0;

  wire [31:0] mulhsu_upper;
  wire [31:0] mulhu_upper;

  cla_adder_32bit mulhsu_adder(
    .a(mul_upper),
    .b(mulhsu_correction),
    .cin(1'b0),
    .sum(mulhsu_upper),
    .cout()
  );

  cla_adder_32bit mulhu_adder(
    .a(mulhsu_upper),
    .b(mulhu_extra),
    .cin(1'b0),
    .sum(mulhu_upper),
    .cout()
  );

  wire [31:0] mul_selected_result;
  assign mul_selected_result = (mu_funct3_reg == 3'b000) ? mul_lower :
                               (mu_funct3_reg == 3'b001) ? mul_upper :
                               (mu_funct3_reg == 3'b010) ? mulhsu_upper :
                               mulhu_upper;

  wire [31:0] div_selected_result;
  assign div_selected_result = mu_funct3_reg[1] ? div_remainder : div_quotient;

  always_ff @(posedge clk or negedge resetn)
  begin
    if (!resetn)
    begin
      mul_start <= 1'b0;
      div_start <= 1'b0;
      mul_busy <= 1'b0;
      div_busy <= 1'b0;
      req_hold <= 1'b0;
      result_valid_reg <= 1'b0;
      div_by_zero_reg <= 1'b0;
      result_hold_reg <= 32'b0;
      mul_src1_reg <= 32'b0;
      mul_src2_reg <= 32'b0;
      div_src1_reg <= 32'b0;
      div_src2_reg <= 32'b0;
      mu_funct3_reg <= 3'b0;
    end
    else
    begin
      mul_start <= 1'b0;
      div_start <= 1'b0;
      if (flush)
      begin
        mul_busy <= 1'b0;
        div_busy <= 1'b0;
        req_hold <= 1'b0;
        result_valid_reg <= 1'b0;
        div_by_zero_reg <= 1'b0;
        // BUG-6 fix: clear hold register on flush to prevent stale data
        result_hold_reg <= 32'b0;
      end
      else
      begin
        if (!req_valid)
        begin
          req_hold <= 1'b0;
        end
        else if (req_fire)
        begin
          req_hold <= 1'b1;
        end

        if (result_valid_reg && result_got)
        begin
          result_valid_reg <= 1'b0;
        end

        if (mul_done && mul_busy)
        begin
          mul_busy <= 1'b0;
          result_hold_reg <= mul_selected_result;
          result_valid_reg <= 1'b1;
        end

        if (div_done && div_busy)
        begin
          div_busy <= 1'b0;
          result_hold_reg <= div_selected_result;
          result_valid_reg <= 1'b1;
        end

        if (req_mul)
        begin
          mul_start <= 1'b1;
          mul_busy <= 1'b1;
          mul_src1_reg <= src1;
          mul_src2_reg <= src2;
          mu_funct3_reg <= mu_funct3;
          div_by_zero_reg <= 1'b0;
        end
        else if (req_div_rem)
        begin
          div_start <= 1'b1;
          div_busy <= 1'b1;
          div_src1_reg <= src1;
          div_src2_reg <= src2;
          mu_funct3_reg <= mu_funct3;
          div_by_zero_reg <= (src2 == 32'b0);
        end
      end
    end
  end

  assign div_by_zero = div_by_zero_reg;
  assign result_valid = result_valid_reg;
  assign result = result_hold_reg;

  booth_multiplier multiplier(
                     .clk(clk),
                     .resetn(resetn),
                     .multiplicand(mul_src1_reg),
                     .multiplier(mul_src2_reg),
                     .start(mul_start),
                     .flush(flush),
                     .product(mul_result),
                     .done(mul_done)
                   );

  non_restoring_divider divider(
                          .clk(clk),
                          .resetn(resetn),
                          .dividend(div_src1_reg),
                          .divisor(div_src2_reg),
                          .start(div_start),
                          .flush(flush),
                          .is_unsigned(mu_funct3_reg[2] & mu_funct3_reg[0]),
                          .quotient(div_quotient),
                          .remainder(div_remainder),
                          .done(div_done)
                        );

endmodule
