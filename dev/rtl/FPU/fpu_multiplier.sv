`timescale 1ns / 1ps

module fpu_multiplier(
    input         clk,
    input         resetn,
    input  [31:0] src1,
    input  [31:0] src2,
    input  [2:0]  rm,          // rounding mode
    input         start,
    input         flush,
    output [31:0] result,
    output [4:0]  fflags,      // {NV, DZ, OF, UF, NX}
    output        done
);

    // ===================================================================
    // FSM states (BUG-93 fix: S_COMPUTE split into S_MUL + S_NORM)
    // ===================================================================
    localparam S_IDLE = 3'd0;
    localparam S_MUL  = 3'd1;   // compute product, extract normalized values
    localparam S_NORM = 3'd2;   // subnormal handling, rounding, pack result
    localparam S_DONE = 3'd3;

    reg [2:0] state;

    // ===================================================================
    // Latched inputs
    // ===================================================================
    reg [31:0] src1_r, src2_r;
    reg [2:0]  rm_r;

    // ===================================================================
    // Instantiate fpu_special on latched inputs
    // ===================================================================
    wire        s1_nan, s2_nan, s1_snan, s2_snan, s1_qnan, s2_qnan;
    wire        s1_inf, s2_inf, s1_zero, s2_zero;
    wire        s1_subn, s2_subn;
    wire        s1_sign, s2_sign;
    wire [7:0]  s1_exp, s2_exp;
    wire [22:0] s1_frac, s2_frac;
    wire [31:0] qnan;

    fpu_special sp(
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
        .canonical_qnan(qnan)
    );

    // ===================================================================
    // Combinational computation (S_MUL stage)
    // ===================================================================

    // Result sign
    wire res_sign = s1_sign ^ s2_sign;

    // Special-case detection
    wire any_nan   = s1_nan | s2_nan;
    wire any_snan  = s1_snan | s2_snan;
    wire inf_times_zero = (s1_inf & s2_zero) | (s1_zero & s2_inf);
    wire any_inf   = s1_inf | s2_inf;
    wire any_zero  = s1_zero | s2_zero;

    wire is_special = any_nan | inf_times_zero | any_inf | any_zero;

    // Special-case result
    wire [31:0] special_res = any_nan       ? qnan :
                              inf_times_zero ? qnan :
                              any_inf       ? {res_sign, 8'hFF, 23'b0} :
                                              {res_sign, 31'b0};  // zero

    // Special-case flags: NV for NaN or Inf*0
    wire [4:0] special_flags = {(any_snan | inf_times_zero), 4'b0};

    // ===================================================================
    // Normal multiplication path (S_MUL stage)
    // ===================================================================

    // Biased exponent: subnormals use 1, normals use exp
    wire [7:0] bexp1 = (s1_exp == 8'b0) ? 8'd1 : s1_exp;
    wire [7:0] bexp2 = (s2_exp == 8'b0) ? 8'd1 : s2_exp;

    // Hidden bits
    wire h1 = (s1_exp != 8'b0);
    wire h2 = (s2_exp != 8'b0);

    // 24-bit mantissas: {hidden, frac}
    wire [23:0] mant1 = {h1, s1_frac};
    wire [23:0] mant2 = {h2, s2_frac};

    // 48-bit product
    wire [47:0] product = mant1 * mant2;

    // Exponent: bexp1 + bexp2 - 127 (bias adjustment)
    wire [9:0] exp_sum_10  = {2'b0, bexp1} + {2'b0, bexp2};
    wire [9:0] exp_raw_10  = exp_sum_10 - 10'd127;

    // Normalize: check if product[47] is set (carry case)
    wire prod_carry = product[47];

    // Extract mantissa and rounding bits based on carry
    wire [23:0] norm_mant24 = prod_carry ? product[47:24] : product[46:23];
    wire        norm_g      = prod_carry ? product[23]    : product[22];
    wire        norm_r      = prod_carry ? product[22]    : product[21];
    wire        norm_s      = prod_carry ? (|product[21:0]) : (|product[20:0]);

    // 27-bit mantissa for fpu_round: {mant24, G, R, S}
    wire [26:0] norm_mant = {norm_mant24, norm_g, norm_r, norm_s};

    // Exponent after normalization (10-bit)
    wire [9:0] exp_normed_10 = prod_carry ? (exp_raw_10 + 10'd1) : exp_raw_10;

    // Overflow: exponent >= 255 before rounding.
    // BUG-93 follow-up: exp_normed_10 is a 10-bit signed value. Negative
    // exponents (extreme underflow) have bit 9 set, making the unsigned
    // comparison >= 255 spuriously true. Only flag overflow when the
    // exponent is positive (bit 9 == 0) AND >= 255.
    wire exp_overflow_pre = (exp_normed_10[9] == 1'b0) && (exp_normed_10 >= 10'd255);

    // Underflow: exponent <= 0
    wire exp_le_zero = exp_normed_10[9] | (exp_normed_10 == 10'd0);

    // For subnormal: denormalize by shifting mantissa right
    wire [7:0] denorm_rshift = 8'd1 - exp_normed_10[7:0];

    // Guard: if denorm_rshift >= 27, all mantissa bits are shifted out
    wire denorm_too_small = (denorm_rshift >= 8'd27);

    // ===================================================================
    // Pipeline registers (S_MUL → S_NORM)
    // BUG-93 fix: register derived values to break the long combinational
    // path from DSP48 output through barrel shifter + rounding.
    // ===================================================================
    reg        mul_res_sign;
    reg        mul_is_special;
    reg [31:0] mul_spec_res;
    reg [4:0]  mul_spec_flags;
    reg [26:0] mul_norm_mant;
    reg [9:0]  mul_exp_normed_10;
    reg        mul_exp_overflow_pre;
    reg        mul_exp_le_zero;
    reg [7:0]  mul_denorm_rshift;
    reg        mul_denorm_too_small;
    reg [2:0]  mul_rm_r;

    // ===================================================================
    // S_NORM stage combinational logic
    // ===================================================================

    // Denormalize: shift the 27-bit mantissa right
    wire [50:0] denorm_extended = {mul_norm_mant, 24'b0};
    wire [50:0] denorm_shifted  = denorm_extended >> mul_denorm_rshift[4:0];

    wire [23:0] denorm_mant24 = mul_denorm_too_small ? 24'b0         : denorm_shifted[50:27];
    wire        denorm_g      = mul_denorm_too_small ? 1'b0          : denorm_shifted[26];
    wire        denorm_r      = mul_denorm_too_small ? 1'b0          : denorm_shifted[25];
    wire        denorm_s      = mul_denorm_too_small ? (|mul_norm_mant)  : (|denorm_shifted[24:0]);
    wire [26:0] denorm_mant   = {denorm_mant24, denorm_g, denorm_r, denorm_s};

    // Select between normal and subnormal
    wire [26:0] final_mant = mul_exp_le_zero ? denorm_mant : mul_norm_mant;
    wire [7:0]  final_exp  = mul_exp_le_zero ? 8'b0 : mul_exp_normed_10[7:0];

    // ===================================================================
    // Rounding (S_NORM stage)
    // ===================================================================
    wire [23:0] rounded_mant;
    wire        round_up_w;
    wire        round_overflow;

    fpu_round rnd(
        .rm(mul_rm_r),
        .sign(mul_res_sign),
        .mantissa(final_mant),
        .rounded(rounded_mant),
        .round_up(round_up_w),
        .overflow(round_overflow)
    );

    // Exponent after rounding overflow (9-bit to catch wrap-around)
    wire [8:0] exp_after_round_9 = {1'b0, final_exp} + {8'b0, round_overflow};
    wire [7:0] exp_after_round   = exp_after_round_9[7:0];

    // Detect exponent overflow (from rounding or pre-existing)
    wire exp_overflow = (exp_after_round_9 >= 9'd255) | mul_exp_overflow_pre;

    // Detect inexact
    wire inexact = (final_mant[2] | final_mant[1] | final_mant[0]) | round_up_w;

    // Underflow: subnormal result and inexact
    wire underflow = mul_exp_le_zero & inexact;

    // Pack result
    wire [31:0] packed_normal = {mul_res_sign, exp_after_round, rounded_mant[22:0]};
    wire [31:0] packed_inf    = {mul_res_sign, 8'hFF, 23'b0};

    // Overflow result depends on rounding mode
    wire ovf_to_inf = (mul_rm_r == 3'b000) |  // RNE
                      (mul_rm_r == 3'b100) |  // RMM
                      ((mul_rm_r == 3'b011) & ~mul_res_sign) |  // RUP & positive
                      ((mul_rm_r == 3'b010) & mul_res_sign);    // RDN & negative
    wire [31:0] packed_max    = {mul_res_sign, 8'hFE, 23'h7FFFFF};
    wire [31:0] overflow_res  = ovf_to_inf ? packed_inf : packed_max;

    // Zero result (from subnormal that rounds to zero)
    wire [31:0] packed_zero = {mul_res_sign, 31'b0};
    wire result_is_zero = (rounded_mant == 24'b0) & mul_exp_le_zero;

    // Final result and flags
    wire [31:0] compute_res = result_is_zero  ? packed_zero :
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
            rm_r               <= 3'b0;
            // Pipeline registers
            mul_res_sign       <= 1'b0;
            mul_is_special     <= 1'b0;
            mul_spec_res       <= 32'b0;
            mul_spec_flags     <= 5'b0;
            mul_norm_mant      <= 27'b0;
            mul_exp_normed_10  <= 10'b0;
            mul_exp_overflow_pre <= 1'b0;
            mul_exp_le_zero    <= 1'b0;
            mul_denorm_rshift  <= 8'b0;
            mul_denorm_too_small <= 1'b0;
            mul_rm_r           <= 3'b0;
        end else if (flush) begin
            state              <= S_IDLE;
            done_r             <= 1'b0;
            // BUG-6 fix: clear pipeline registers on flush to prevent
            // stale data leakage after flush→idle transition
            mul_is_special     <= 1'b0;
            mul_spec_res       <= 32'b0;
            mul_spec_flags     <= 5'b0;
            mul_norm_mant      <= 27'b0;
            mul_exp_normed_10  <= 10'b0;
            mul_res_sign       <= 1'b0;
            mul_exp_overflow_pre <= 1'b0;
            mul_exp_le_zero    <= 1'b0;
            mul_denorm_rshift  <= 8'b0;
            mul_denorm_too_small <= 1'b0;
            mul_rm_r           <= 3'b0;
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
                // BUG-93 fix: S_MUL — compute product and extract
                // normalized intermediate values into pipeline registers.
                // This breaks the long combinational path from DSP48
                // output through barrel shifter + rounding.
                // -------------------------------------------------------
                S_MUL: begin
                    mul_res_sign       <= res_sign;
                    mul_rm_r           <= rm_r;
                    if (is_special) begin
                        mul_is_special <= 1'b1;
                        mul_spec_res   <= special_res;
                        mul_spec_flags <= special_flags;
                    end else begin
                        mul_is_special     <= 1'b0;
                        mul_norm_mant      <= norm_mant;
                        mul_exp_normed_10  <= exp_normed_10;
                        mul_exp_overflow_pre <= exp_overflow_pre;
                        mul_exp_le_zero    <= exp_le_zero;
                        mul_denorm_rshift  <= denorm_rshift;
                        mul_denorm_too_small <= denorm_too_small;
                    end
                    state <= S_NORM;
                end

                // -------------------------------------------------------
                // BUG-93 fix: S_NORM — subnormal denormalization,
                // rounding, overflow/underflow, result packing.
                // All inputs come from pipeline registers (mul_*),
                // breaking the previous single-cycle critical path.
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
