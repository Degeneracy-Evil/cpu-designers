`timescale 1ns / 1ps

// Double-precision floating-point compare (FEQ.D / FLT.D / FLE.D)
// Pure combinational. IEEE 754 double: 1+11+52, bias 1023.
// cmp_funct: 3'b000=FLT, 3'b001=FLE, 3'b010=FEQ
// result:    1-bit comparison result in bit[0], zero-extended to 64-bit
// fflags:    NV set on unordered comparison (any NaN for FLT/FLE, sNaN for FEQ)

module fpu_compare_d(
    input  [63:0] src1,
    input  [63:0] src2,
    input  [2:0]  cmp_funct,   // 010=FEQ, 000=FLT, 001=FLE
    output [63:0] result,      // 1 or 0 (written to integer register)
    output [4:0]  fflags       // NV if any input is NaN (for FLT/FLE), NV if sNaN for FEQ
);

    wire         sign1 = src1[63];
    wire         sign2 = src2[63];
    wire [10:0]  exp1  = src1[62:52];
    wire [10:0]  exp2  = src2[62:52];
    wire [51:0]  frac1 = src1[51:0];
    wire [51:0]  frac2 = src2[51:0];

    // NaN detection (double: exp==11'h7FF && frac!=0)
    wire is_nan1  = (exp1 == 11'h7FF) && (frac1 != 52'b0);
    wire is_nan2  = (exp2 == 11'h7FF) && (frac2 != 52'b0);
    wire is_snan1 = is_nan1 && !frac1[51];
    wire is_snan2 = is_nan2 && !frac2[51];
    wire is_zero1 = (exp1 == 11'b0) && (frac1 == 52'b0);
    wire is_zero2 = (exp2 == 11'b0) && (frac2 == 52'b0);

    wire any_nan  = is_nan1 || is_nan2;
    wire any_snan = is_snan1 || is_snan2;

    // ---------- equality: +0 == -0 ----------
    wire eq_value = (src1 == src2) || (is_zero1 && is_zero2);

    // ---------- less-than for ordered (non-NaN) values ----------
    // Magnitude comparison: |src1| < |src2|
    //   For non-zero, non-NaN values the raw exponent+fraction bits
    //   give the correct magnitude ordering (subnormals included).
    wire same_sign = (sign1 == sign2);
    wire mag_lt    = (exp1 < exp2) || ((exp1 == exp2) && (frac1 < frac2));

    // Correct for zero: zero has the smallest magnitude
    wire mag_lt_corr = (!is_zero1 && !is_zero2 && mag_lt) ||
                       (is_zero1 && !is_zero2);

    // Full less-than:
    //   sign1=1, sign2=0  => negative < positive  (unless both zero, handled by eq_value)
    //   same sign, both negative  => larger magnitude = smaller value
    //   same sign, both positive  => smaller magnitude = smaller value
    wire src1_lt_src2 = (!eq_value) && (
        (sign1 && !sign2) ||
        (same_sign && sign1 && !mag_lt_corr) ||
        (same_sign && !sign1 && mag_lt_corr)
    );

    // ---------- per-function results ----------
    // FEQ: 1 if equal and neither is NaN; NV only if sNaN
    wire feq_res = !any_nan && eq_value;
    // FLT: 1 if src1 < src2; NV if any NaN
    wire flt_res = !any_nan && src1_lt_src2;
    // FLE: 1 if src1 <= src2; NV if any NaN
    wire fle_res = !any_nan && (src1_lt_src2 || eq_value);

    // ---------- mux by cmp_funct (pure assign, no reg/always_comb) ----------
    // 3'b010=FEQ, 3'b000=FLT, 3'b001=FLE
    wire cmp_res = (cmp_funct == 3'b010) ? feq_res :
                   (cmp_funct == 3'b000) ? flt_res :
                   (cmp_funct == 3'b001) ? fle_res : 1'b0;

    wire nv_flag = (cmp_funct == 3'b010) ? any_snan :  // FEQ: NV only for sNaN
                   (cmp_funct == 3'b000) ? any_nan  :  // FLT: NV for any NaN
                   (cmp_funct == 3'b001) ? any_nan  :  // FLE: NV for any NaN
                   1'b0;

    assign result = {63'b0, cmp_res};
    assign fflags = {nv_flag, 4'b0};

endmodule
