`timescale 1ns / 1ps

module fpu_minmax(
    input  [31:0] src1,
    input  [31:0] src2,
    input         is_max,      // 0=FMIN.S, 1=FMAX.S
    output [31:0] result,
    output [4:0]  fflags       // NV if any input is NaN (including qNaN)
);

    wire        sign1 = src1[31];
    wire        sign2 = src2[31];
    wire [7:0]  exp1  = src1[30:23];
    wire [7:0]  exp2  = src2[30:23];
    wire [22:0] frac1 = src1[22:0];
    wire [22:0] frac2 = src2[22:0];

    wire is_nan1  = (exp1 == 8'hFF) && (frac1 != 23'b0);
    wire is_nan2  = (exp2 == 8'hFF) && (frac2 != 23'b0);
    wire is_zero1 = (exp1 == 8'b0) && (frac1 == 23'b0);
    wire is_zero2 = (exp2 == 8'b0) && (frac2 == 23'b0);

    wire any_nan  = is_nan1 || is_nan2;
    wire both_nan = is_nan1 && is_nan2;

    localparam [31:0] QNAN = 32'h7FC00000;

    // ---------- ordered comparison (same logic as fpu_compare) ----------
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
    wire [31:0] non_nan_val = is_nan1 ? src2 : src1;
    wire [31:0] nan_result  = both_nan ? QNAN : non_nan_val;

    // ---------- non-NaN result ----------
    wire [31:0] min_val = src1_strict_lt ? src1 : src2;
    wire [31:0] max_val = src1_strict_lt ? src2 : src1;
    wire [31:0] normal_result = is_max ? max_val : min_val;

    assign result = any_nan ? nan_result : normal_result;
    assign fflags = any_nan ? 5'b10000 : 5'b00000;  // NV if any NaN

endmodule
