`timescale 1ns / 1ps

module fpu_special(
    input  [31:0] src1,
    input  [31:0] src2,
    output        src1_is_nan,
    output        src2_is_nan,
    output        src1_is_snan,
    output        src2_is_snan,
    output        src1_is_qnan,
    output        src2_is_qnan,
    output        src1_is_inf,
    output        src2_is_inf,
    output        src1_is_zero,
    output        src2_is_zero,
    output        src1_is_subnormal,
    output        src2_is_subnormal,
    output        src1_sign,
    output        src2_sign,
    output [7:0]  src1_exp,
    output [7:0]  src2_exp,
    output [22:0] src1_frac,
    output [22:0] src2_frac,
    output [31:0] canonical_qnan
);

    // ---------------------------------------------------------------------------
    // Field extraction
    // ---------------------------------------------------------------------------
    assign src1_sign = src1[31];
    assign src1_exp  = src1[30:23];
    assign src1_frac = src1[22:0];

    assign src2_sign = src2[31];
    assign src2_exp  = src2[30:23];
    assign src2_frac = src2[22:0];

    // ---------------------------------------------------------------------------
    // NaN: exponent = all-ones AND fraction != 0
    // ---------------------------------------------------------------------------
    assign src1_is_nan = (src1_exp == 8'hFF) & (src1_frac != 23'b0);
    assign src2_is_nan = (src2_exp == 8'hFF) & (src2_frac != 23'b0);

    // ---------------------------------------------------------------------------
    // sNaN: NaN AND quiet bit (frac[22]) == 0
    // qNaN: NaN AND quiet bit (frac[22]) == 1
    // ---------------------------------------------------------------------------
    assign src1_is_snan = src1_is_nan & ~src1_frac[22];
    assign src2_is_snan = src2_is_nan & ~src2_frac[22];
    assign src1_is_qnan = src1_is_nan &  src1_frac[22];
    assign src2_is_qnan = src2_is_nan &  src2_frac[22];

    // ---------------------------------------------------------------------------
    // Inf: exponent = all-ones AND fraction == 0
    // ---------------------------------------------------------------------------
    assign src1_is_inf = (src1_exp == 8'hFF) & (src1_frac == 23'b0);
    assign src2_is_inf = (src2_exp == 8'hFF) & (src2_frac == 23'b0);

    // ---------------------------------------------------------------------------
    // Zero: exponent == 0 AND fraction == 0
    // ---------------------------------------------------------------------------
    assign src1_is_zero = (src1_exp == 8'b0) & (src1_frac == 23'b0);
    assign src2_is_zero = (src2_exp == 8'b0) & (src2_frac == 23'b0);

    // ---------------------------------------------------------------------------
    // Subnormal: exponent == 0 AND fraction != 0
    // ---------------------------------------------------------------------------
    assign src1_is_subnormal = (src1_exp == 8'b0) & (src1_frac != 23'b0);
    assign src2_is_subnormal = (src2_exp == 8'b0) & (src2_frac != 23'b0);

    // ---------------------------------------------------------------------------
    // Canonical qNaN: sign=0, exp=0xFF, frac[22]=1, rest=0 => 0x7FC00000
    // ---------------------------------------------------------------------------
    assign canonical_qnan = 32'h7FC00000;

endmodule
