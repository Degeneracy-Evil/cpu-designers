`timescale 1ns / 1ps

module fpu_fma(
    input         clk,
    input         resetn,
    input  [31:0] src1,        // rs1 (float register)
    input  [31:0] src2,        // rs2 (float register)
    input  [31:0] src3,        // rs3 (float register, R4 format)
    input  [6:0]  fma_funct,   // 20=FMADD, 21=FMSUB, 22=FNMSUB, 23=FNMADD
    input  [2:0]  rm,          // rounding mode
    input         start,
    input         flush,
    output [31:0] result,
    output [4:0]  fflags,      // {NV, DZ, OF, UF, NX}
    output        done
);

    // ===================================================================
    // FSM states
    // ===================================================================
    localparam S_IDLE  = 3'd0;
    localparam S_MUL   = 3'd1;
    localparam S_ALIGN = 3'd2;
    localparam S_ADD   = 3'd3;
    localparam S_NORM  = 3'd4;
    localparam S_ROUND = 3'd5;
    localparam S_DONE  = 3'd6;

    reg [2:0] state;

    // ===================================================================
    // Latched inputs
    // ===================================================================
    reg [31:0] src1_r, src2_r, src3_r;
    reg [6:0]  fma_funct_r;
    reg [2:0]  rm_r;

    // ===================================================================
    // Instantiate fpu_special for multiply operands (src1, src2)
    // ===================================================================
    wire        s1_nan, s2_nan, s1_snan, s2_snan, s1_qnan, s2_qnan;
    wire        s1_inf, s2_inf, s1_zero, s2_zero;
    wire        s1_subn, s2_subn;
    wire        s1_sign, s2_sign;
    wire [7:0]  s1_exp, s2_exp;
    wire [22:0] s1_frac, s2_frac;
    wire [31:0] qnan_mul;

    fpu_special sp_mul(
        .src1(src1_r), .src2(src2_r),
        .src1_is_nan(s1_nan),   .src2_is_nan(s2_nan),
        .src1_is_snan(s1_snan), .src2_is_snan(s2_snan),
        .src1_is_qnan(s1_qnan), .src2_is_qnan(s2_qnan),
        .src1_is_inf(s1_inf),   .src2_is_inf(s2_inf),
        .src1_is_zero(s1_zero), .src2_is_zero(s2_zero),
        .src1_is_subnormal(s1_subn), .src2_is_subnormal(s2_subn),
        .src1_sign(s1_sign), .src2_sign(s2_sign),
        .src1_exp(s1_exp),   .src2_exp(s2_exp),
        .src1_frac(s1_frac), .src2_frac(s2_frac),
        .canonical_qnan(qnan_mul)
    );

    // ===================================================================
    // Instantiate fpu_special for addend (src3)
    // Only use src1 outputs from this instance
    // ===================================================================
    wire        s3_nan, s3_nan_d, s3_snan, s3_snan_d;
    wire        s3_qnan, s3_qnan_d, s3_inf, s3_inf_d;
    wire        s3_zero, s3_zero_d, s3_subn, s3_subn_d;
    wire        s3_sign, s3_sign_d;
    wire [7:0]  s3_exp, s3_exp_d;
    wire [22:0] s3_frac, s3_frac_d;
    wire [31:0] qnan_add;

    fpu_special sp_add(
        .src1(src3_r), .src2(src3_r),
        .src1_is_nan(s3_nan),   .src2_is_nan(s3_nan_d),
        .src1_is_snan(s3_snan), .src2_is_snan(s3_snan_d),
        .src1_is_qnan(s3_qnan), .src2_is_qnan(s3_qnan_d),
        .src1_is_inf(s3_inf),   .src2_is_inf(s3_inf_d),
        .src1_is_zero(s3_zero), .src2_is_zero(s3_zero_d),
        .src1_is_subnormal(s3_subn), .src2_is_subnormal(s3_subn_d),
        .src1_sign(s3_sign), .src2_sign(s3_sign_d),
        .src1_exp(s3_exp),   .src2_exp(s3_exp_d),
        .src1_frac(s3_frac), .src2_frac(s3_frac_d),
        .canonical_qnan(qnan_add)
    );

    // ===================================================================
    // S_MUL stage: Compute product and detect special cases
    // ===================================================================

    // --- Product computation ---
    wire prod_sign_raw = s1_sign ^ s2_sign;

    // Biased exponent: subnormals use 1, normals use exp
    wire [7:0] bexp1 = (s1_exp == 8'b0) ? 8'd1 : s1_exp;
    wire [7:0] bexp2 = (s2_exp == 8'b0) ? 8'd1 : s2_exp;

    // Hidden bits
    wire h1 = (s1_exp != 8'b0);
    wire h2 = (s2_exp != 8'b0);

    // 24-bit mantissas: {hidden, frac}
    wire [23:0] mant1 = {h1, s1_frac};
    wire [23:0] mant2 = {h2, s2_frac};

    // 48-bit product (Vivado DSP48)
    wire [47:0] product = mant1 * mant2;

    // Product exponent: bexp1 + bexp2 - 127
    wire [9:0] exp_sum_10  = {2'b0, bexp1} + {2'b0, bexp2};
    wire [9:0] exp_product = exp_sum_10 - 10'd127;

    // --- Effective signs based on FMA variant ---
    // FMADD.S:  (rs1*rs2) + rs3
    // FMSUB.S:  (rs1*rs2) - rs3
    // FNMSUB.S: -(rs1*rs2) + rs3
    // FNMADD.S: -(rs1*rs2) - rs3
    wire negate_prod = (fma_funct_r == 7'd22) | (fma_funct_r == 7'd23);
    wire negate_add = (fma_funct_r == 7'd21) | (fma_funct_r == 7'd23);

    wire prod_sign_eff  = prod_sign_raw ^ negate_prod;
    wire addend_sign_eff = s3_sign ^ negate_add;

    // --- Special case detection ---
    wire any_nan    = s1_nan | s2_nan | s3_nan;
    wire any_snan   = s1_snan | s2_snan | s3_snan;

    // Product is infinity (Inf * finite, finite * Inf, Inf * Inf)
    wire prod_inf       = (s1_inf & ~s2_zero) | (s2_inf & ~s1_zero);
    wire inf_times_zero = (s1_inf & s2_zero) | (s1_zero & s2_inf);

    // Inf - Inf: product is Inf and addend is Inf with different effective signs
    wire inf_minus_inf = prod_inf & s3_inf & (prod_sign_eff != addend_sign_eff);

    // Combined special case flag
    wire is_special = any_nan | inf_times_zero | inf_minus_inf | prod_inf | s3_inf;

    // Special case result
    wire [31:0] special_res = any_nan       ? qnan_mul :
                              inf_times_zero ? qnan_mul :
                              inf_minus_inf  ? qnan_mul :
                              prod_inf       ? {prod_sign_eff, 8'hFF, 23'b0} :
                                               {addend_sign_eff, 8'hFF, 23'b0};

    // Special case flags: NV for NaN, Inf*0, or Inf-Inf
    wire special_nv = any_snan | inf_times_zero | inf_minus_inf;
    wire [4:0] special_flags = {special_nv, 4'b0};

    // ===================================================================
    // Pipeline registers (S_MUL -> S_ALIGN)
    // ===================================================================
    reg [47:0] mul_product;
    reg [9:0]  mul_exp_product;
    reg        mul_prod_sign_eff;
    reg        mul_addend_sign_eff;
    reg        mul_eff_sub;
    reg        mul_is_special;
    reg [31:0] mul_spec_res;
    reg [4:0]  mul_spec_flags;

    // ===================================================================
    // S_ALIGN stage: Align addend with product
    // ===================================================================

    // Addend mantissa
    wire [7:0]  bexp3 = (s3_exp == 8'b0) ? 8'd1 : s3_exp;
    wire        h3    = (s3_exp != 8'b0);
    wire [23:0] mant3 = {h3, s3_frac};

    // ===================================================================
    // Internal mantissa width: 75 bits
    // Product at bits [74:27] (48 bits), addend aligned within field
    // Field binary point: bit 73 = 2^0 relative to result exponent
    // ===================================================================

    // Exponent difference: exp_product - bexp3 (can be negative)
    // Sign-extend mul_exp_product (10-bit two's complement) to 11 bits
    wire [10:0] exp_diff_s = {mul_exp_product[9], mul_exp_product} - {3'b0, bexp3};

    // Determine which operand is larger
    // Product MSB exponent: exp_product - 126
    // Addend MSB exponent: bexp3 - 127
    // Product larger when exp_product >= bexp3 - 1
    // When exp_product is negative (10-bit two's complement), product is always smaller
    wire prod_larger = (~mul_exp_product[9]) & (mul_exp_product >= {2'b0, bexp3} - 10'd1);

    // ===================================================================
    // Case 1: Product at top (prod_larger)
    // Product at [74:27], addend aligned within 75-bit field
    // For exp_diff = 0: addend[23] at field bit 73, addend[0] at bit 50
    // addend_field = mant3 << (50 - exp_diff) when exp_diff <= 50
    // addend_field = mant3 >> (exp_diff - 50) when exp_diff > 50
    // ===================================================================

    // Must check exp_diff_s is non-negative: negative values (sign bit set)
    // would incorrectly pass unsigned > 50 comparison
    wire addend_rshift_case = (~exp_diff_s[10]) & (exp_diff_s > 11'd50);

    // --- Left shift: place mant3 at bits [23:0] then shift left ---
    // For exp_diff = 50: no shift, mant3 at [23:0]
    // For exp_diff = 0:  shift left 50, mant3[23] at bit 73
    // For exp_diff = -1: shift left 51, mant3[23] at bit 74
    wire [6:0]  addend_lsh = 7'd50 - exp_diff_s[6:0];
    wire [74:0] addend_field_left = ({51'b0, mant3}) << addend_lsh[5:0];

    // --- Right shift: use wide field with offset for sticky capture ---
    // Place mant3 at physical bits [121:98] (logical [73:50] + offset 48)
    // Shift right by exp_diff, extract field at [122:48], sticky at [47:0]
    wire [122:0] addend_rsh_base = {1'b0, mant3, 98'b0};
    // Cap right shift at 122 (max useful for 123-bit field) to prevent
    // [6:0] wraparound when exp_diff_s > 127
    wire [6:0]  addend_rsh_amt = (~exp_diff_s[10] & (exp_diff_s > 11'd122)) ? 7'd122 : exp_diff_s[6:0];
    wire [122:0] addend_shifted_r = addend_rsh_base >> addend_rsh_amt;
    wire [74:0]  addend_field_right = addend_shifted_r[122:48];
    wire         addend_sticky_right = |addend_shifted_r[47:0];

    // Select between left and right shift
    wire [74:0] addend_field_c1 = addend_rshift_case ?
                                  addend_field_right : addend_field_left;
    wire        addend_sticky_c1 = addend_rshift_case ?
                                   addend_sticky_right : 1'b0;

    // Product field for case 1
    wire [74:0] prod_field_c1 = {mul_product, 27'b0};

    // Result exponent for case 1
    wire [9:0]  result_exp_c1 = mul_exp_product;

    // ===================================================================
    // Case 2: Addend at top (!prod_larger)
    // Addend at [74:51], product shifted right
    // shift = bexp3 - exp_product - 1
    // ===================================================================
    // Sign-extend mul_exp_product for correct two's complement subtraction
    wire [10:0] prod_rshift_val = {3'b0, bexp3} - {mul_exp_product[9], mul_exp_product} - 11'd1;

    // Product right shift using wide field with offset for sticky
    // Place product at physical bits [122:75] (logical [74:27] + offset 48)
    wire [122:0] prod_rsh_base = {mul_product, 75'b0};
    // Cap right shift at 122 (max useful for 123-bit field)
    wire [6:0]  prod_rsh_amt = (~prod_rshift_val[10] & (prod_rshift_val > 11'd122)) ? 7'd122 : prod_rshift_val[6:0];
    wire [122:0] prod_shifted_right = prod_rsh_base >> prod_rsh_amt;
    wire [74:0]  prod_field_c2 = prod_shifted_right[122:48];
    wire         prod_sticky_c2 = |prod_shifted_right[47:0];

    // Addend field for case 2
    wire [74:0] addend_field_c2 = {mant3, 51'b0};

    // Result exponent for case 2: bexp3 - 1
    wire [9:0]  result_exp_c2 = {2'b0, bexp3} - 10'd1;

    // ===================================================================
    // Mux between cases
    // ===================================================================
    wire [74:0] prod_field   = prod_larger ? prod_field_c1   : prod_field_c2;
    wire [74:0] addend_field = prod_larger ? addend_field_c1 : addend_field_c2;
    wire [9:0]  align_exp    = prod_larger ? result_exp_c1   : result_exp_c2;
    wire        align_sticky = prod_larger ? addend_sticky_c1 : prod_sticky_c2;

    // Effective subtract: must use combinational signs, NOT pipelined versions
    wire eff_sub = (prod_sign_eff != addend_sign_eff);

    // ===================================================================
    // Pipeline registers (S_ALIGN -> S_ADD)
    // ===================================================================
    reg [74:0] al_prod_field;
    reg [74:0] al_addend_field;
    reg [9:0]  al_exp;
    reg        al_eff_sub;
    reg        al_sign;
    reg        al_sticky;
    reg        al_is_special;
    reg [31:0] al_spec_res;
    reg [4:0]  al_spec_flags;

    // ===================================================================
    // S_ADD stage: Add/subtract aligned mantissas
    // ===================================================================
    wire [75:0] add_result = {1'b0, al_prod_field} + {1'b0, al_addend_field};
    // When addend > product and subtracting, swap order to avoid negative result
    wire [75:0] sub_result_prod_min = {1'b0, al_prod_field} - {1'b0, al_addend_field};
    wire [75:0] sub_result_add_min = {1'b0, al_addend_field} - {1'b0, al_prod_field};
    wire [75:0] sub_result = sub_sign_flip ? sub_result_add_min : sub_result_prod_min;
    wire [75:0] sum_comb   = al_eff_sub ? sub_result : add_result;

    // For effective subtract, determine result sign
    // If addend > product: result sign flips
    wire addend_gt_prod = ({1'b0, al_addend_field} > {1'b0, al_prod_field});
    wire sub_sign_flip  = al_eff_sub & addend_gt_prod;

    // ===================================================================
    // Pipeline registers (S_ADD -> S_NORM)
    // ===================================================================
    reg [75:0] ad_sum;
    reg [9:0]  ad_exp;
    reg        ad_sign;
    reg        ad_eff_sub;
    reg        ad_sub_sign_flip;
    reg        ad_sticky;
    reg        ad_is_special;
    reg [31:0] ad_spec_res;
    reg [4:0]  ad_spec_flags;

    // ===================================================================
    // S_NORM stage: Normalize result
    // ===================================================================
    // The 75-bit field has binary point at bit 73 (bit 73 = 2^0).
    // After addition, the sum can be in [0, ~6.0) in field value.
    // Three normalization cases:
    //   carry2: sum >= 4.0 (bit 75 set) → shift right by 2, exp+2
    //   carry1: sum in [2.0,4.0) (bit 74 set, bit 75 clear) → shift right by 1, exp+1
    //   no carry: sum < 2.0 → left-shift to normalize, with exponent
    //             adjusted for binary point at bit 73 (not bit 75)

    // --- Carry detection (checked on ad_sum directly) ---
    wire norm_carry2 = ad_sum[75];                    // sum >= 4.0
    wire norm_carry1 = ~ad_sum[75] & ad_sum[74];     // sum in [2.0, 4.0)
    wire norm_carry  = norm_carry2 | norm_carry1;     // sum >= 2.0

    // --- Carry2 normalization: shift right by 2, exponent +2 ---
    // After shift: hidden bit at bit 73, mant24 = ad_sum[75:52]
    // G=ad_sum[51], R=ad_sum[50], S=|ad_sum[49:0]|ad_sticky
    wire [26:0] norm_mant_carry2 = {ad_sum[75:52],
                                     ad_sum[51],
                                     ad_sum[50],
                                     (|ad_sum[49:0]) | ad_sticky};
    wire [9:0]  norm_exp_carry2  = ad_exp + 10'd2;

    // --- Carry1 normalization: shift right by 1, exponent +1 ---
    // After shift: hidden bit at bit 73, mant24 = ad_sum[74:51]
    // G=ad_sum[50], R=ad_sum[49], S=|ad_sum[48:0]|ad_sticky
    wire [26:0] norm_mant_carry1 = {ad_sum[74:51],
                                     ad_sum[50],
                                     ad_sum[49],
                                     (|ad_sum[48:0]) | ad_sticky};
    wire [9:0]  norm_exp_carry1  = ad_exp + 10'd1;

    // --- Select between carry2 and carry1 ---
    wire [26:0] norm_mant_carry = norm_carry2 ? norm_mant_carry2 : norm_mant_carry1;
    wire [9:0]  norm_exp_carry  = norm_carry2 ? norm_exp_carry2 : norm_exp_carry1;

    // --- No-carry case: left-shift normalization ---
    // Count leading zeros in the 76-bit sum
    // Use cascaded approach: top 48 bits then bottom 28 bits
    wire [47:0] sum_hi = ad_sum[75:28];
    wire [27:0] sum_lo = ad_sum[27:0];

    wire [5:0] lz_hi;
    assign lz_hi = (sum_hi[47]) ? 6'd0 :
                   (sum_hi[46]) ? 6'd1 :
                   (sum_hi[45]) ? 6'd2 :
                   (sum_hi[44]) ? 6'd3 :
                   (sum_hi[43]) ? 6'd4 :
                   (sum_hi[42]) ? 6'd5 :
                   (sum_hi[41]) ? 6'd6 :
                   (sum_hi[40]) ? 6'd7 :
                   (sum_hi[39]) ? 6'd8 :
                   (sum_hi[38]) ? 6'd9 :
                   (sum_hi[37]) ? 6'd10 :
                   (sum_hi[36]) ? 6'd11 :
                   (sum_hi[35]) ? 6'd12 :
                   (sum_hi[34]) ? 6'd13 :
                   (sum_hi[33]) ? 6'd14 :
                   (sum_hi[32]) ? 6'd15 :
                   (sum_hi[31]) ? 6'd16 :
                   (sum_hi[30]) ? 6'd17 :
                   (sum_hi[29]) ? 6'd18 :
                   (sum_hi[28]) ? 6'd19 :
                   (sum_hi[27]) ? 6'd20 :
                   (sum_hi[26]) ? 6'd21 :
                   (sum_hi[25]) ? 6'd22 :
                   (sum_hi[24]) ? 6'd23 :
                   (sum_hi[23]) ? 6'd24 :
                   (sum_hi[22]) ? 6'd25 :
                   (sum_hi[21]) ? 6'd26 :
                   (sum_hi[20]) ? 6'd27 :
                   (sum_hi[19]) ? 6'd28 :
                   (sum_hi[18]) ? 6'd29 :
                   (sum_hi[17]) ? 6'd30 :
                   (sum_hi[16]) ? 6'd31 :
                   (sum_hi[15]) ? 6'd32 :
                   (sum_hi[14]) ? 6'd33 :
                   (sum_hi[13]) ? 6'd34 :
                   (sum_hi[12]) ? 6'd35 :
                   (sum_hi[11]) ? 6'd36 :
                   (sum_hi[10]) ? 6'd37 :
                   (sum_hi[9])  ? 6'd38 :
                   (sum_hi[8])  ? 6'd39 :
                   (sum_hi[7])  ? 6'd40 :
                   (sum_hi[6])  ? 6'd41 :
                   (sum_hi[5])  ? 6'd42 :
                   (sum_hi[4])  ? 6'd43 :
                   (sum_hi[3])  ? 6'd44 :
                   (sum_hi[2])  ? 6'd45 :
                   (sum_hi[1])  ? 6'd46 :
                   (sum_hi[0])  ? 6'd47 :
                                   6'd48;

    wire [4:0] lz_lo;
    assign lz_lo = (sum_lo[27]) ? 5'd0 :
                   (sum_lo[26]) ? 5'd1 :
                   (sum_lo[25]) ? 5'd2 :
                   (sum_lo[24]) ? 5'd3 :
                   (sum_lo[23]) ? 5'd4 :
                   (sum_lo[22]) ? 5'd5 :
                   (sum_lo[21]) ? 5'd6 :
                   (sum_lo[20]) ? 5'd7 :
                   (sum_lo[19]) ? 5'd8 :
                   (sum_lo[18]) ? 5'd9 :
                   (sum_lo[17]) ? 5'd10 :
                   (sum_lo[16]) ? 5'd11 :
                   (sum_lo[15]) ? 5'd12 :
                   (sum_lo[14]) ? 5'd13 :
                   (sum_lo[13]) ? 5'd14 :
                   (sum_lo[12]) ? 5'd15 :
                   (sum_lo[11]) ? 5'd16 :
                   (sum_lo[10]) ? 5'd17 :
                   (sum_lo[9])  ? 5'd18 :
                   (sum_lo[8])  ? 5'd19 :
                   (sum_lo[7])  ? 5'd20 :
                   (sum_lo[6])  ? 5'd21 :
                   (sum_lo[5])  ? 5'd22 :
                   (sum_lo[4])  ? 5'd23 :
                   (sum_lo[3])  ? 5'd24 :
                   (sum_lo[2])  ? 5'd25 :
                   (sum_lo[1])  ? 5'd26 :
                   (sum_lo[0])  ? 5'd27 :
                                  5'd28;

    wire hi_all_zero = (sum_hi == 48'b0);
    wire [6:0] lz = hi_all_zero ? {1'b1, lz_lo} + 7'd48 : {1'b0, lz_hi};

    // Use 103-bit extended value for left shift to preserve rounding info
    // After shift, MSB is at bit 102. Mantissa at [102:79], G/R/S at [78:76]
    wire [102:0] sub_extended = {ad_sum, 27'b0};
    wire [102:0] sub_shifted  = sub_extended << lz;

    // Extract normalized mantissa and rounding bits
    wire [23:0] sub_norm_mant24 = sub_shifted[102:79];
    wire        sub_norm_g      = sub_shifted[78];
    wire        sub_norm_r      = sub_shifted[77];
    wire        sub_norm_s      = |sub_shifted[76:0] | ad_sticky;
    wire [26:0] norm_mant_sub   = {sub_norm_mant24, sub_norm_g, sub_norm_r, sub_norm_s};

    // Normalized exponent: binary point is at bit 73, LZ counts from bit 75,
    // so the true exponent is ad_exp - lz + 2
    wire [9:0]  norm_exp_sub_raw = ad_exp - lz + 10'd2;

    // Check if result is zero
    wire sub_is_zero = (ad_sum == 76'b0);

    // Check if subnormal (exponent <= 0 after normalization)
    // norm_exp_sub_raw = ad_exp - lz + 2; subnormal when ad_exp + 2 <= lz
    // ad_exp is 10-bit two's complement; negative values (bit 9 set) are always subnormal
    wire sub_is_subnormal = (~sub_is_zero) & (ad_exp[9] | ((ad_exp + 10'd2) <= {3'b0, lz}));

    // For subnormal result: denormalize
    // right_shift = 1 - (ad_exp - lz + 2) = lz - ad_exp - 1
    // ad_exp can be negative (10-bit two's complement), so shift can exceed 31
    wire [9:0]  subnormal_rshift_full = {3'b0, lz} - ad_exp - 10'd1;
    // Cap at 102 (max useful for 103-bit field); prevents [6:0] wraparound
    wire [6:0]  subnormal_rshift = (subnormal_rshift_full > 10'd102) ? 7'd102 : subnormal_rshift_full[6:0];

    // Denormalize: shift the already-normalized 103-bit value right
    wire [102:0] sub_denorm_shifted = sub_shifted >> subnormal_rshift;
    wire [23:0]  sub_denorm_mant24  = sub_denorm_shifted[102:79];
    wire         sub_denorm_g       = sub_denorm_shifted[78];
    wire         sub_denorm_r       = sub_denorm_shifted[77];
    wire         sub_denorm_s       = |sub_denorm_shifted[76:0] | ad_sticky;
    wire [26:0]  norm_mant_denorm   = {sub_denorm_mant24, sub_denorm_g, sub_denorm_r, sub_denorm_s};

    // Select between normal and subnormal
    wire [26:0] norm_mant_sub_final = sub_is_subnormal ? norm_mant_denorm : norm_mant_sub;
    wire [9:0]  norm_exp_sub_final  = sub_is_subnormal ? 10'b0 : norm_exp_sub_raw;

    // Zero result sign for subtraction cancellation
    wire zero_sign_sub = (rm_r == 3'b010) ? 1'b1 : 1'b0; // RDN => -0

    // --- Carry subnormal handling ---
    // When carry produces exponent <= 0, result is subnormal
    // norm_exp_carry = ad_exp + 1 (carry1) or ad_exp + 2 (carry2)
    wire carry_subnormal = (norm_exp_carry[9] | (norm_exp_carry == 10'b0));

    // Denormalization right shift for carry: 1 - norm_exp_carry
    wire [9:0]  carry_denorm_rshift_full = 10'd1 - norm_exp_carry;
    // Cap at 26 (max useful for 27-bit mantissa in 54-bit extended field)
    wire [4:0]  carry_denorm_rshift = (carry_denorm_rshift_full > 10'd26) ?
                                      5'd26 : carry_denorm_rshift_full[4:0];

    // Extend mantissa for denormalization: {mant[26:0], 27'b0}
    wire [53:0] carry_ext = {norm_mant_carry, 27'b0};
    wire [53:0] carry_denorm_shifted = carry_ext >> carry_denorm_rshift;
    wire [23:0] carry_denorm_mant24 = carry_denorm_shifted[53:30];
    wire        carry_denorm_g       = carry_denorm_shifted[29];
    wire        carry_denorm_r       = carry_denorm_shifted[28];
    wire        carry_denorm_s       = |carry_denorm_shifted[27:0];
    wire [26:0] norm_mant_carry_denorm = {carry_denorm_mant24,
                                          carry_denorm_g,
                                          carry_denorm_r,
                                          carry_denorm_s};

    // Select between normal and subnormal carry
    wire [26:0] norm_mant_carry_final = carry_subnormal ?
                                        norm_mant_carry_denorm : norm_mant_carry;
    wire [9:0]  norm_exp_carry_final  = carry_subnormal ?
                                        10'b0 : norm_exp_carry;

    // Combine all normalization cases
    // norm_carry: sum >= 2.0 (bit 74 or 75 set) — right-shift normalization
    // ~norm_carry & ~sub_is_zero: left-shift normalization
    // sub_is_zero: zero result
    wire [26:0] norm_mant_comb = norm_carry  ? norm_mant_carry_final :
                                 sub_is_zero ? 27'b0 :
                                               norm_mant_sub_final;
    wire [9:0]  norm_exp_comb  = norm_carry  ? norm_exp_carry_final :
                                 sub_is_zero ? 10'b0 :
                                               norm_exp_sub_final;
    wire norm_is_zero_comb = sub_is_zero & ~norm_carry;

    // Result sign: for subtract, flip if addend was larger
    wire norm_sign_comb = norm_is_zero_comb ?
                          (ad_eff_sub ? zero_sign_sub : ad_sign) :
                          (ad_sub_sign_flip ? ~ad_sign : ad_sign);

    // Overflow: exponent >= 255 before rounding
    // Must check exponent is non-negative (bit 9 clear) to avoid false
    // overflow on negative 10-bit two's complement values
    wire norm_exp_overflow_pre = (~norm_exp_comb[9]) & (norm_exp_comb >= 10'd255);

    // Underflow: result is subnormal and non-zero
    wire norm_uf_comb = (norm_carry & carry_subnormal) |
                        (~norm_carry & sub_is_subnormal & ~sub_is_zero);

    // Inexact from subnormal denormalization
    wire norm_nx_denorm = (norm_carry & carry_subnormal &
                           (carry_denorm_g | carry_denorm_r | carry_denorm_s)) |
                          (~norm_carry & sub_is_subnormal &
                           (sub_denorm_g | sub_denorm_r | sub_denorm_s));

    // ===================================================================
    // Pipeline registers (S_NORM -> S_ROUND)
    // ===================================================================
    reg [9:0]  nm_exp;
    reg [26:0] nm_mant;
    reg        nm_sign;
    reg        nm_is_zero;
    reg        nm_exp_overflow_pre;
    reg        nm_uf;
    reg        nm_nx_denorm;
    reg        nm_is_special;
    reg [31:0] nm_spec_res;
    reg [4:0]  nm_spec_flags;

    // ===================================================================
    // S_ROUND stage: Single rounding via fpu_round
    // ===================================================================
    wire [23:0] rounded_mant;
    wire        round_up_w;
    wire        round_overflow;

    fpu_round rnd(
        .rm(rm_r),
        .sign(nm_sign),
        .mantissa(nm_mant),
        .rounded(rounded_mant),
        .round_up(round_up_w),
        .overflow(round_overflow)
    );

    // Exponent after rounding overflow (9-bit to catch wrap-around)
    wire [8:0] exp_after_round_9 = {1'b0, nm_exp[7:0]} + {8'b0, round_overflow};
    wire [7:0] exp_after_round   = exp_after_round_9[7:0];

    // Detect exponent overflow
    wire exp_overflow = (exp_after_round_9 >= 9'd255) | nm_exp_overflow_pre;

    // Detect inexact
    wire inexact = (nm_mant[2] | nm_mant[1] | nm_mant[0]) | round_up_w;

    // Underflow: subnormal result and inexact
    wire underflow = nm_uf & (inexact | nm_nx_denorm);

    // Pack result
    wire [31:0] packed_normal = {nm_sign, exp_after_round, rounded_mant[22:0]};
    wire [31:0] packed_inf    = {nm_sign, 8'hFF, 23'b0};

    // Overflow result depends on rounding mode
    wire ovf_to_inf = (rm_r == 3'b000) |  // RNE
                      (rm_r == 3'b100) |  // RMM
                      ((rm_r == 3'b011) & ~nm_sign) |  // RUP & positive
                      ((rm_r == 3'b010) & nm_sign);    // RDN & negative
    wire [31:0] packed_max    = {nm_sign, 8'hFE, 23'h7FFFFF};
    wire [31:0] overflow_res  = ovf_to_inf ? packed_inf : packed_max;

    // Zero result
    wire [31:0] packed_zero = {nm_sign, 31'b0};
    wire result_is_zero = (rounded_mant == 24'b0) & (nm_exp[7:0] == 8'b0);

    // Final result and flags
    wire [31:0] round_res_comb = nm_is_zero   ? packed_zero :
                                 exp_overflow  ? overflow_res :
                                                 packed_normal;
    wire [4:0] round_flags_comb = nm_is_zero ? 5'b0 :
                                 {1'b0,                        // NV
                                  1'b0,                        // DZ
                                  exp_overflow,                // OF
                                  underflow,                   // UF
                                  exp_overflow | inexact | nm_nx_denorm}; // NX

    // ===================================================================
    // Output registers
    // ===================================================================
    reg [31:0] result_r;
    reg [4:0]  fflags_r;
    reg        done_r;

    assign result = result_r;
    assign fflags = fflags_r;
    assign done   = done_r;

    // ===================================================================
    // FSM
    // ===================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state              <= S_IDLE;
            done_r             <= 1'b0;
            result_r           <= 32'b0;
            fflags_r           <= 5'b0;
            src1_r             <= 32'b0;
            src2_r             <= 32'b0;
            src3_r             <= 32'b0;
            fma_funct_r        <= 7'b0;
            rm_r               <= 3'b0;
            // S_MUL -> S_ALIGN pipeline
            mul_product        <= 48'b0;
            mul_exp_product    <= 10'b0;
            mul_prod_sign_eff  <= 1'b0;
            mul_addend_sign_eff<= 1'b0;
            mul_eff_sub        <= 1'b0;
            mul_is_special     <= 1'b0;
            mul_spec_res       <= 32'b0;
            mul_spec_flags     <= 5'b0;
            // S_ALIGN -> S_ADD pipeline
            al_prod_field      <= 75'b0;
            al_addend_field    <= 75'b0;
            al_exp             <= 10'b0;
            al_eff_sub         <= 1'b0;
            al_sign            <= 1'b0;
            al_sticky          <= 1'b0;
            al_is_special      <= 1'b0;
            al_spec_res        <= 32'b0;
            al_spec_flags      <= 5'b0;
            // S_ADD -> S_NORM pipeline
            ad_sum             <= 76'b0;
            ad_exp             <= 10'b0;
            ad_sign            <= 1'b0;
            ad_eff_sub         <= 1'b0;
            ad_sub_sign_flip   <= 1'b0;
            ad_sticky          <= 1'b0;
            ad_is_special      <= 1'b0;
            ad_spec_res        <= 32'b0;
            ad_spec_flags      <= 5'b0;
            // S_NORM -> S_ROUND pipeline
            nm_exp             <= 10'b0;
            nm_mant            <= 27'b0;
            nm_sign            <= 1'b0;
            nm_is_zero         <= 1'b0;
            nm_exp_overflow_pre<= 1'b0;
            nm_uf              <= 1'b0;
            nm_nx_denorm      <= 1'b0;
            nm_is_special      <= 1'b0;
            nm_spec_res        <= 32'b0;
            nm_spec_flags      <= 5'b0;
        end else if (flush) begin
            state              <= S_IDLE;
            done_r             <= 1'b0;
            // Clear all pipeline registers on flush
            mul_is_special     <= 1'b0;
            mul_spec_res       <= 32'b0;
            mul_spec_flags     <= 5'b0;
            mul_product        <= 48'b0;
            mul_exp_product    <= 10'b0;
            mul_prod_sign_eff  <= 1'b0;
            mul_addend_sign_eff<= 1'b0;
            mul_eff_sub        <= 1'b0;
            al_is_special      <= 1'b0;
            al_spec_res        <= 32'b0;
            al_spec_flags      <= 5'b0;
            al_prod_field      <= 75'b0;
            al_addend_field    <= 75'b0;
            al_exp             <= 10'b0;
            al_eff_sub         <= 1'b0;
            al_sign            <= 1'b0;
            al_sticky          <= 1'b0;
            ad_is_special      <= 1'b0;
            ad_spec_res        <= 32'b0;
            ad_spec_flags      <= 5'b0;
            ad_sum             <= 76'b0;
            ad_exp             <= 10'b0;
            ad_sign            <= 1'b0;
            ad_eff_sub         <= 1'b0;
            ad_sub_sign_flip   <= 1'b0;
            ad_sticky          <= 1'b0;
            nm_is_special      <= 1'b0;
            nm_spec_res        <= 32'b0;
            nm_spec_flags      <= 5'b0;
            nm_exp             <= 10'b0;
            nm_mant            <= 27'b0;
            nm_sign            <= 1'b0;
            nm_is_zero         <= 1'b0;
            nm_exp_overflow_pre<= 1'b0;
            nm_uf              <= 1'b0;
            nm_nx_denorm      <= 1'b0;
        end else begin
            done_r <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        src1_r      <= src1;
                        src2_r      <= src2;
                        src3_r      <= src3;
                        fma_funct_r <= fma_funct;
                        rm_r        <= rm;
                        state       <= S_MUL;
                    end
                end

                // -------------------------------------------------------
                // S_MUL: Compute product and detect special cases.
                // Pipeline derived values to break the long combinational
                // path from DSP48 output through alignment logic.
                // -------------------------------------------------------
                S_MUL: begin
                    mul_product         <= product;
                    mul_exp_product     <= exp_product;
                    mul_prod_sign_eff   <= prod_sign_eff;
                    mul_addend_sign_eff <= addend_sign_eff;
                    mul_eff_sub         <= eff_sub;
                    if (is_special) begin
                        mul_is_special  <= 1'b1;
                        mul_spec_res    <= special_res;
                        mul_spec_flags  <= special_flags;
                    end else begin
                        mul_is_special  <= 1'b0;
                        mul_spec_res    <= 32'b0;
                        mul_spec_flags  <= 5'b0;
                    end
                    state <= S_ALIGN;
                end

                // -------------------------------------------------------
                // S_ALIGN: Align addend with product.
                // -------------------------------------------------------
                S_ALIGN: begin
                    if (mul_is_special) begin
                        al_is_special   <= 1'b1;
                        al_spec_res     <= mul_spec_res;
                        al_spec_flags   <= mul_spec_flags;
                        al_prod_field   <= 75'b0;
                        al_addend_field <= 75'b0;
                        al_exp          <= 10'b0;
                        al_eff_sub      <= 1'b0;
                        al_sign         <= 1'b0;
                        al_sticky       <= 1'b0;
                    end else begin
                        al_is_special   <= 1'b0;
                        al_prod_field   <= prod_field;
                        al_addend_field <= addend_field;
                        al_exp          <= align_exp;
                        al_eff_sub      <= mul_eff_sub;
                        al_sign         <= mul_prod_sign_eff;
                        al_sticky       <= align_sticky;
                        al_spec_res     <= 32'b0;
                        al_spec_flags   <= 5'b0;
                    end
                    state <= S_ADD;
                end

                // -------------------------------------------------------
                // S_ADD: Add/subtract aligned mantissas.
                // -------------------------------------------------------
                S_ADD: begin
                    if (al_is_special) begin
                        ad_is_special    <= 1'b1;
                        ad_spec_res      <= al_spec_res;
                        ad_spec_flags    <= al_spec_flags;
                        ad_sum           <= 76'b0;
                        ad_exp           <= 10'b0;
                        ad_sign          <= 1'b0;
                        ad_eff_sub       <= 1'b0;
                        ad_sub_sign_flip <= 1'b0;
                        ad_sticky        <= 1'b0;
                    end else begin
                        ad_is_special    <= 1'b0;
                        ad_sum           <= sum_comb;
                        ad_exp           <= al_exp;
                        ad_sign          <= al_sign;
                        ad_eff_sub       <= al_eff_sub;
                        ad_sub_sign_flip <= sub_sign_flip;
                        ad_sticky        <= al_sticky;
                        ad_spec_res      <= 32'b0;
                        ad_spec_flags    <= 5'b0;
                    end
                    state <= S_NORM;
                end

                // -------------------------------------------------------
                // S_NORM: Normalize result.
                // -------------------------------------------------------
                S_NORM: begin
                    if (ad_is_special) begin
                        nm_is_special      <= 1'b1;
                        nm_spec_res        <= ad_spec_res;
                        nm_spec_flags      <= ad_spec_flags;
                        nm_exp             <= 10'b0;
                        nm_mant            <= 27'b0;
                        nm_sign            <= 1'b0;
                        nm_is_zero         <= 1'b0;
                        nm_exp_overflow_pre<= 1'b0;
                        nm_uf              <= 1'b0;
                        nm_nx_denorm      <= 1'b0;
                    end else begin
                        nm_is_special      <= 1'b0;
                        nm_exp             <= norm_exp_comb;
                        nm_mant            <= norm_mant_comb;
                        nm_sign            <= norm_sign_comb;
                        nm_is_zero         <= norm_is_zero_comb;
                        nm_exp_overflow_pre<= norm_exp_overflow_pre;
                        nm_uf              <= norm_uf_comb;
                        nm_nx_denorm      <= norm_nx_denorm;
                        nm_spec_res        <= 32'b0;
                        nm_spec_flags      <= 5'b0;
                    end
                    state <= S_ROUND;
                end

                // -------------------------------------------------------
                // S_ROUND: Single rounding and result packing.
                // -------------------------------------------------------
                S_ROUND: begin
                    if (nm_is_special) begin
                        result_r  <= nm_spec_res;
                        fflags_r  <= nm_spec_flags;
                    end else begin
                        result_r  <= round_res_comb;
                        fflags_r  <= round_flags_comb;
                    end
                    state <= S_DONE;
                end

                // -------------------------------------------------------
                S_DONE: begin
                    done_r <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
