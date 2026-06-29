`timescale 1ns / 1ps

// Double-precision floating-point minimum / maximum (FMIN.D / FMAX.D)
// Pure combinational. IEEE 754 double: 1+11+52, bias 1023.
// is_max: 0=FMIN.D, 1=FMAX.D
// NaN handling: if one operand is NaN, return the other; if both NaN, return qNaN.
// -0 vs +0: FMIN returns -0, FMAX returns +0 (strict total ordering).
// fflags: NV if any input is NaN (including qNaN).

module fpu_minmax_d(
    input  [63:0] src1,
    input  [63:0] src2,
    input         is_max,      // 0=FMIN.D, 1=FMAX.D
    output [63:0] result,
    output [4:0]  fflags       // NV if any input is NaN (including qNaN)
);

    wire         sign1 = src1[63];
    wire         sign2 = src2[63];
    wire [10:0]  exp1  = src1[62:52];
    wire [10:0]  exp2  = src2[62:52];
    wire [51:0]  frac1 = src1[51:0];
    wire [51:0]  frac2 = src2[51:0];

    wire is_nan1  = (exp1 == 11'h7FF) && (frac1 != 52'b0);
    wire is_nan2  = (exp2 == 11'h7FF) && (frac2 != 52'b0);
    wire is_zero1 = (exp1 == 11'b0) && (frac1 == 52'b0);
    wire is_zero2 = (exp2 == 11'b0) && (frac2 == 52'b0);

    wire any_nan  = is_nan1 || is_nan2;
    wire both_nan = is_nan1 && is_nan2;

    // Canonical quiet NaN for double precision
    localparam [63:0] QNAN = 64'h7FF8000000000000;

    // ---------- ordered comparison (same logic as fpu_compare_d) ----------
    wire same_sign = (sign1 == sign2);
    wire eq_value  = (src1 == src2) || (is_zero1 && is_zero2);
    wire mag_lt    = (exp1 < exp2) || ((exp1 == exp2) && (frac1 < frac2));
    wire mag_lt_corr = (!is_zero1 && !is_zero2 && mag_lt) ||
                       (is_zero1 && !is_zero2);

    wire src1_lt_src2 = (!eq_value) && (
        (sign1 && !sign2) ||
        (same_sign && sign1 && !mag_lt_corr) ||
        (same_sign && !sign1 && mag_lt_corr)
    );

    // For FMIN/FMAX the spec requires -0 < +0 (strict total ordering)
    wire neg_zero_lt  = sign1 && !sign2 && is_zero1 && is_zero2;
    wire src1_strict_lt = src1_lt_src2 || neg_zero_lt;

    // ---------- NaN handling ----------
    // If one input is NaN, return the non-NaN value.
    // If both are NaN, return qNaN.
    wire [63:0] non_nan_val = is_nan1 ? src2 : src1;
    wire [63:0] nan_result  = both_nan ? QNAN : non_nan_val;

    // ---------- non-NaN result ----------
    wire [63:0] min_val = src1_strict_lt ? src1 : src2;
    wire [63:0] max_val = src1_strict_lt ? src2 : src1;
    wire [63:0] normal_result = is_max ? max_val : min_val;

    assign result = any_nan ? nan_result : normal_result;
    assign fflags = any_nan ? 5'b10000 : 5'b00000;  // NV if any NaN

endmodule
