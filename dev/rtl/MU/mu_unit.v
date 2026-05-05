`timescale 1ns / 1ps

module mu_unit(
    input         clk,
    input         reset,
    input  [1:0]  mu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    input         req_valid,
    input         flush,
    input         result_ready,
    output [31:0] result,
    output        mu_busy,
    output        mu_ready,
    output        result_valid,
    output        div_by_zero
  );

  wire mu_mul = mu_control[0];
  wire mu_div = mu_control[1];

  wire [63:0] mul_result;
  wire        mul_done;
  wire [31:0] div_quotient;
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

  wire req_fire;
  wire req_mul;
  wire req_div;

  assign mu_busy = mul_busy | div_busy;
  assign mu_ready = (~mu_busy) & (~req_hold) & (~result_valid_reg);

  assign req_fire = req_valid & mu_ready & (mu_mul | mu_div);
  assign req_mul = req_fire & mu_mul;
  assign req_div = req_fire & mu_div;

  always @(posedge clk or posedge reset)
  begin
    if (reset)
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

        if (result_valid_reg && result_ready)
        begin
          result_valid_reg <= 1'b0;
        end

        if (mul_done && mul_busy)
        begin
          mul_busy <= 1'b0;
          result_hold_reg <= mul_result[31:0];
          result_valid_reg <= 1'b1;
        end

        if (div_done && div_busy)
        begin
          div_busy <= 1'b0;
          result_hold_reg <= div_quotient;
          result_valid_reg <= 1'b1;
        end

        if (req_mul)
        begin
          mul_start <= 1'b1;
          mul_busy <= 1'b1;
          mul_src1_reg <= src1;
          mul_src2_reg <= src2;
          div_by_zero_reg <= 1'b0;
        end
        else if (req_div)
        begin
          div_start <= 1'b1;
          div_busy <= 1'b1;
          div_src1_reg <= src1;
          div_src2_reg <= src2;
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

endmodule
