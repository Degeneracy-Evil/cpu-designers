`timescale 1ns / 1ps

// =============================================================================
// fpu_multiplier_d — IEEE 754 double-precision floating-point multiplier (FMUL.D)
//
// Widened from fpu_multiplier.sv (single-precision):
//   - Exponent:  8 → 11 bits, bias 127 → 1023
//   - Mantissa:  23 → 52 bits (53-bit with implicit 1)
//   - Product:   48 → 106 bits (53×53)
//   - Result:    32 → 64 bits
//
// Special-case detection and rounding are inlined (not using fpu_special /
// fpu_round) because those modules are single-precision specific.
//
// CRITICAL: Applies the Task 6 underflow-OF fix — the pre-rounding overflow
// check is gated on the exponent sign bit so that negative exponents
// (extreme underflow) do not spuriously trigger OF.
//
// Interface: clk, resetn, src1[63:0], src2[63:0], rm[2:0], start, flush,
//            result[63:0], fflags[4:0], done
// =============================================================================

module fpu_multiplier_d(
    input         clk,
    input         resetn,
    input  [63:0] src1,
    input  [63:0] src2,
    input  [2:0]  rm,          // rounding mode
    input         start,
    input         flush,
    output [63:0] result,
    output [4:0]  fflags,      // {NV, DZ, OF, UF, NX}
    output        done
);

    // ===================================================================
    // FSM states (mirrors fpu_multiplier.sv: S_COMPUTE split into S_MUL + S_NORM)
    // ===================================================================
    localparam S_IDLE = 3'd0;
    localparam S_MUL  = 3'd1;   // compute product, extract normalized values
    localparam S_NORM = 3'd2;   // subnormal handling, rounding, pack result
    localparam S_DONE = 3'd3;

    reg [2:0] state;

    // ===================================================================
    // Latched inputs
    // ===================================================================
    reg [63:0] src1_r, src2_r;
    reg [2:0]  rm_r;

    // ===================================================================
    // Inlined fpu_special_d — field extraction & special-case detection
    // ===================================================================
    wire        s1_sign = src1_r[63];
    wire [10:0] s1_exp  = src1_r[62:52];
    wire [51:0] s1_frac = src1_r[51:0];

    wire        s2_sign = src2_r[63];
    wire [10:0] s2_exp  = src2_r[62:52];
    wire [51:0] s2_frac = src2_r[51:0];

    // NaN: exponent = all-ones AND fraction != 0
    wire s1_nan = (s1_exp == 11'h7FF) & (s1_frac != 52'b0);
    wire s2_nan = (s2_exp == 11'h7FF) & (s2_frac != 52'b0);

    // sNaN: NaN AND quiet bit (frac[51]) == 0;  qNaN: quiet bit == 1
    wire s1_snan = s1_nan & ~s1_frac[51];
    wire s2_snan = s2_nan & ~s2_frac[51];

    // Inf: exponent = all-ones AND fraction == 0
    wire s1_inf = (s1_exp == 11'h7FF) & (s1_frac == 52'b0);
    wire s2_inf = (s2_exp == 11'h7FF) & (s2_frac == 52'b0);

    // Zero: exponent == 0 AND fraction == 0
    wire s1_zero = (s1_exp == 11'b0) & (s1_frac == 52'b0);
    wire s2_zero = (s2_exp == 11'b0) & (s2_frac == 52'b0);

    // Canonical qNaN: 0x7ff8000000000000
    wire [63:0] qnan = 64'h7ff8000000000000;

    // ===================================================================
    // Combinational computation (S_MUL stage)
    // ===================================================================

    // Result sign
    wire res_sign = s1_sign ^ s2_sign;

    // Special-case detection
    wire any_nan       = s1_nan | s2_nan;
    wire any_snan      = s1_snan | s2_snan;
    wire inf_times_zero = (s1_inf & s2_zero) | (s1_zero & s2_inf);
    wire any_inf       = s1_inf | s2_inf;
    wire any_zero      = s1_zero | s2_zero;

    wire is_special = any_nan | inf_times_zero | any_inf | any_zero;

    // Special-case result
    wire [63:0] special_res = any_nan       ? qnan :
                              inf_times_zero ? qnan :
                              any_inf       ? {res_sign, 11'h7FF, 52'b0} :
                                              {res_sign, 63'b0};  // zero

    // Special-case flags: NV for sNaN or Inf*0
    wire [4:0] special_flags = {(any_snan | inf_times_zero), 4'b0};

    // ===================================================================
    // Normal multiplication path (S_MUL stage)
    // ===================================================================

    // Biased exponent: subnormals use 1, normals use exp
    wire [10:0] bexp1 = (s1_exp == 11'b0) ? 11'd1 : s1_exp;
    wire [10:0] bexp2 = (s2_exp == 11'b0) ? 11'd1 : s2_exp;

    // Hidden bits
    wire h1 = (s1_exp != 11'b0);
    wire h2 = (s2_exp != 11'b0);

    // 53-bit mantissas: {hidden, frac}
    wire [52:0] mant1 = {h1, s1_frac};
    wire [52:0] mant2 = {h2, s2_frac};

    // 106-bit product
    wire [105:0] product = mant1 * mant2;

    // Exponent: bexp1 + bexp2 - 1023 (bias adjustment)
    // 13-bit to hold signed values (11+11=12 bit sum, minus bias → can be negative)
    wire [12:0] exp_sum_13  = {2'b0, bexp1} + {2'b0, bexp2};
    wire [12:0] exp_raw_13  = exp_sum_13 - 13'd1023;

    // Normalize: check if product[105] is set (carry case)
    wire prod_carry = product[105];

    // Extract mantissa and rounding bits based on carry
    wire [52:0] norm_mant53 = prod_carry ? product[105:53] : product[104:52];
    wire        norm_g      = prod_carry ? product[52]     : product[51];
    wire        norm_r      = prod_carry ? product[51]     : product[50];
    wire        norm_s      = prod_carry ? (|product[50:0])  : (|product[49:0]);

    // 56-bit mantissa for rounding: {mant53, G, R, S}
    wire [55:0] norm_mant = {norm_mant53, norm_g, norm_r, norm_s};

    // Exponent after normalization (13-bit)
    wire [12:0] exp_normed_13 = prod_carry ? (exp_raw_13 + 13'd1) : exp_raw_13;

    // -----------------------------------------------------------------
    // Task 6 fix (applied): Overflow pre-check gated on sign bit.
    //
    // exp_normed_13 is a 13-bit signed value. Negative exponents
    // (extreme underflow, e.g. SMALLEST_NORMAL_D × SMALLEST_NORMAL_D
    // = 2^-2046) have bit 12 set, making the unsigned comparison
    // >= 2047 spuriously true. Only flag overflow when the exponent
    // is positive (bit 12 == 0) AND >= 2047.
    // -----------------------------------------------------------------
    wire exp_overflow_pre = (exp_normed_13[12] == 1'b0) && (exp_normed_13 >= 13'd2047);

    // Underflow: exponent <= 0
    wire exp_le_zero = exp_normed_13[12] | (exp_normed_13 == 13'd0);

    // For subnormal: denormalize by shifting mantissa right
    wire [12:0] denorm_rshift = 13'd1 - exp_normed_13;

    // Guard: if denorm_rshift >= 56, all mantissa bits are shifted out
    wire denorm_too_small = (denorm_rshift >= 13'd56);

    // ===================================================================
    // Pipeline registers (S_MUL → S_NORM)
    // Breaks the long combinational path from multiplier output through
    // barrel shifter + rounding (same pattern as fpu_multiplier.sv BUG-93).
    // ===================================================================
    reg        mul_res_sign;
    reg        mul_is_special;
    reg [63:0] mul_spec_res;
    reg [4:0]  mul_spec_flags;
    reg [55:0] mul_norm_mant;
    reg [12:0] mul_exp_normed_13;
    reg        mul_exp_overflow_pre;
    reg        mul_exp_le_zero;
    reg [12:0] mul_denorm_rshift;
    reg        mul_denorm_too_small;
    reg [2:0]  mul_rm_r;

    // ===================================================================
    // S_NORM stage combinational logic
    // ===================================================================

    // Denormalize: shift the 56-bit mantissa right
    // Extended to 108-bit: {norm_mant(56), 52'b0 padding}
    wire [107:0] denorm_extended = {mul_norm_mant, 52'b0};
    wire [107:0] denorm_shifted  = denorm_extended >> mul_denorm_rshift[6:0];

    wire [52:0] denorm_mant53 = mul_denorm_too_small ? 53'b0            : denorm_shifted[107:55];
    wire        denorm_g      = mul_denorm_too_small ? 1'b0             : denorm_shifted[54];
    wire        denorm_r      = mul_denorm_too_small ? 1'b0             : denorm_shifted[53];
    wire        denorm_s      = mul_denorm_too_small ? (|mul_norm_mant) : (|denorm_shifted[52:0]);
    wire [55:0] denorm_mant   = {denorm_mant53, denorm_g, denorm_r, denorm_s};

    // Select between normal and subnormal
    wire [55:0] final_mant = mul_exp_le_zero ? denorm_mant : mul_norm_mant;
    wire [10:0] final_exp  = mul_exp_le_zero ? 11'b0 : mul_exp_normed_13[10:0];

    // ===================================================================
    // Inlined fpu_round_d — rounding (S_NORM stage)
    //   mantissa[55]    = hidden
    //   mantissa[54:3]  = fraction (52 bits)
    //   mantissa[2]     = guard
    //   mantissa[1]     = round
    //   mantissa[0]     = sticky
    // ===================================================================
    wire        hidden  = final_mant[55];
    wire [51:0] frac    = final_mant[54:3];
    wire        guard   = final_mant[2];
    wire        round_b = final_mant[1];
    wire        sticky  = final_mant[0];
    wire        frac_lsb = frac[0];

    // Per-mode round-up logic
    wire rne_up = guard & (round_b | sticky | frac_lsb);
    wire rtz_up = 1'b0;
    wire rdn_up = mul_res_sign & (guard | round_b | sticky);
    wire rup_up = ~mul_res_sign & (guard | round_b | sticky);
    wire rmm_up = guard;

    wire round_up = (mul_rm_r == 3'b000) ? rne_up :
                    (mul_rm_r == 3'b001) ? rtz_up :
                    (mul_rm_r == 3'b010) ? rdn_up :
                    (mul_rm_r == 3'b011) ? rup_up :
                                           rmm_up;  // rm == 3'b100

    // Apply rounding with overflow detection
    wire [52:0] mantissa_pre = {hidden, frac};

    // 54-bit result to capture carry
    wire [53:0] mantissa_result = {1'b0, mantissa_pre} + {{53{1'b0}}, round_up};

    // Overflow: carry into bit 53 (e.g., 1.111..1 + 1 = 10.000..0)
    wire round_overflow = mantissa_result[53];

    // If overflow, result is 10.000..0 (hidden=1, frac=0)
    wire [52:0] rounded_mant = round_overflow ? 53'h10000000000000 : mantissa_result[52:0];

    // ===================================================================
    // Exponent after rounding & overflow detection (S_NORM stage)
    // ===================================================================

    // Exponent after rounding overflow (12-bit to catch wrap-around)
    wire [11:0] exp_after_round_12 = {1'b0, final_exp} + {11'b0, round_overflow};
    wire [10:0] exp_after_round    = exp_after_round_12[10:0];

    // Detect exponent overflow (from rounding or pre-existing)
    wire exp_overflow = (exp_after_round_12 >= 12'd2047) | mul_exp_overflow_pre;

    // Detect inexact
    wire inexact = (final_mant[2] | final_mant[1] | final_mant[0]) | round_up;

    // Underflow: subnormal result and inexact
    wire underflow = mul_exp_le_zero & inexact;

    // ===================================================================
    // Pack result (S_NORM stage)
    // ===================================================================
    wire [63:0] packed_normal = {mul_res_sign, exp_after_round, rounded_mant[51:0]};
    wire [63:0] packed_inf    = {mul_res_sign, 11'h7FF, 52'b0};

    // Overflow result depends on rounding mode
    wire ovf_to_inf = (mul_rm_r == 3'b000) |  // RNE
                      (mul_rm_r == 3'b100) |  // RMM
                      ((mul_rm_r == 3'b011) & ~mul_res_sign) |  // RUP & positive
                      ((mul_rm_r == 3'b010) & mul_res_sign);    // RDN & negative
    wire [63:0] packed_max    = {mul_res_sign, 11'h7FE, 52'hFFFFFFFFFFFFF};
    wire [63:0] overflow_res  = ovf_to_inf ? packed_inf : packed_max;

    // Zero result (from subnormal that rounds to zero)
    wire [63:0] packed_zero = {mul_res_sign, 63'b0};
    wire result_is_zero = (rounded_mant == 53'b0) & mul_exp_le_zero;

    // Final result and flags
    wire [63:0] compute_res = result_is_zero  ? packed_zero :
                              exp_overflow    ? overflow_res :
                                                 packed_normal;
    wire [4:0] compute_flags = {1'b0,                        // NV
                                1'b0,                        // DZ
                                exp_overflow,                // OF
                                underflow,                   // UF
                                exp_overflow | inexact};     // NX

    // ===================================================================
    // Output registers
    // ===================================================================
    reg [63:0] result_r;
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
            state                <= S_IDLE;
            done_r               <= 1'b0;
            result_r             <= 64'b0;
            fflags_r             <= 5'b0;
            src1_r               <= 64'b0;
            src2_r               <= 64'b0;
            rm_r                 <= 3'b0;
            // Pipeline registers
            mul_res_sign         <= 1'b0;
            mul_is_special       <= 1'b0;
            mul_spec_res         <= 64'b0;
            mul_spec_flags       <= 5'b0;
            mul_norm_mant        <= 56'b0;
            mul_exp_normed_13    <= 13'b0;
            mul_exp_overflow_pre <= 1'b0;
            mul_exp_le_zero      <= 1'b0;
            mul_denorm_rshift    <= 13'b0;
            mul_denorm_too_small <= 1'b0;
            mul_rm_r             <= 3'b0;
        end else if (flush) begin
            state                <= S_IDLE;
            done_r               <= 1'b0;
            // Clear pipeline registers on flush to prevent stale data leakage
            mul_is_special       <= 1'b0;
            mul_spec_res         <= 64'b0;
            mul_spec_flags       <= 5'b0;
            mul_norm_mant        <= 56'b0;
            mul_exp_normed_13    <= 13'b0;
            mul_res_sign         <= 1'b0;
            mul_exp_overflow_pre <= 1'b0;
            mul_exp_le_zero      <= 1'b0;
            mul_denorm_rshift    <= 13'b0;
            mul_denorm_too_small <= 1'b0;
            mul_rm_r             <= 3'b0;
        end else begin
            done_r <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        src1_r <= src1;
                        src2_r <= src2;
                        rm_r   <= rm;
                        state  <= S_MUL;
                    end
                end

                // -------------------------------------------------------
                // S_MUL — compute product and extract normalized
                // intermediate values into pipeline registers.
                // -------------------------------------------------------
                S_MUL: begin
                    mul_res_sign <= res_sign;
                    mul_rm_r     <= rm_r;
                    if (is_special) begin
                        mul_is_special <= 1'b1;
                        mul_spec_res   <= special_res;
                        mul_spec_flags <= special_flags;
                    end else begin
                        mul_is_special       <= 1'b0;
                        mul_norm_mant        <= norm_mant;
                        mul_exp_normed_13    <= exp_normed_13;
                        mul_exp_overflow_pre <= exp_overflow_pre;
                        mul_exp_le_zero      <= exp_le_zero;
                        mul_denorm_rshift    <= denorm_rshift;
                        mul_denorm_too_small <= denorm_too_small;
                    end
                    state <= S_NORM;
                end

                // -------------------------------------------------------
                // S_NORM — subnormal denormalization, rounding,
                // overflow/underflow, result packing.
                // -------------------------------------------------------
                S_NORM: begin
                    if (mul_is_special) begin
                        result_r <= mul_spec_res;
                        fflags_r <= mul_spec_flags;
                    end else begin
                        result_r <= compute_res;
                        fflags_r <= compute_flags;
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
