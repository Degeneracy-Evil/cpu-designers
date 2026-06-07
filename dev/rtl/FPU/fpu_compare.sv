`timescale 1ns / 1ps

module fpu_compare(
    input  [31:0] src1,
    input  [31:0] src2,
    input  [2:0]  cmp_funct,   // 010=FEQ, 000=FLT, 001=FLE
    output [31:0] result,      // 1 or 0 (written to integer register)
    output [4:0]  fflags       // NV if any input is NaN (for FLT/FLE), NV if sNaN for FEQ
);

    wire        sign1 = src1[31];
    wire        sign2 = src2[31];
    wire [7:0]  exp1  = src1[30:23];
    wire [7:0]  exp2  = src2[30:23];
    wire [22:0] frac1 = src1[22:0];
    wire [22:0] frac2 = src2[22:0];

    // NaN detection
    wire is_nan1  = (exp1 == 8'hFF) && (frac1 != 23'b0);
    wire is_nan2  = (exp2 == 8'hFF) && (frac2 != 23'b0);
    wire is_snan1 = is_nan1 && !frac1[22];
    wire is_snan2 = is_nan2 && !frac2[22];
    wire is_zero1 = (exp1 == 8'b0) && (frac1 == 23'b0);
    wire is_zero2 = (exp2 == 8'b0) && (frac2 == 23'b0);

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

    // ---------- mux by cmp_funct ----------
    reg [31:0] result_r;
    reg [4:0]  fflags_r;

    always_comb begin
        result_r = 32'b0;
        fflags_r = 5'b0;
        case (cmp_funct)
            3'b010: begin // FEQ
                result_r   = feq_res ? 32'd1 : 32'd0;
                fflags_r[4] = any_snan;          // NV only for sNaN
            end
            3'b000: begin // FLT
                result_r   = flt_res ? 32'd1 : 32'd0;
                fflags_r[4] = any_nan;           // NV for any NaN
            end
            3'b001: begin // FLE
                result_r   = fle_res ? 32'd1 : 32'd0;
                fflags_r[4] = any_nan;           // NV for any NaN
            end
            default: begin
                result_r  = 32'd0;
                fflags_r  = 5'b0;
            end
        endcase
    end

    assign result = result_r;
    assign fflags = fflags_r;

endmodule
