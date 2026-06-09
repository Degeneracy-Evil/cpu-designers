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
    // FSM states
    // ===================================================================
    localparam S_IDLE    = 2'd0;
    localparam S_COMPUTE = 2'd1;
    localparam S_DONE    = 2'd2;

    reg [1:0] state;

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
    // Combinational computation
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
    // Normal multiplication path
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
    // Use 10-bit to avoid overflow: max bexp1+bexp2 = 510, 510-127 = 383
    wire [9:0] exp_sum_10  = {2'b0, bexp1} + {2'b0, bexp2};
    wire [9:0] exp_raw_10  = exp_sum_10 - 10'd127;

    // Normalize: check if product[47] is set (carry case)
    wire prod_carry = product[47];

    // Extract mantissa and rounding bits based on carry
    // Carry case: product[47]=1, result mant = product[47:24], G/R/S from product[23:0]
    // Normal case: product[47]=0, result mant = product[46:23], G/R/S from product[22:0]
    wire [23:0] norm_mant24 = prod_carry ? product[47:24] : product[46:23];
    wire        norm_g      = prod_carry ? product[23]    : product[22];
    wire        norm_r      = prod_carry ? product[22]    : product[21];
    wire        norm_s      = prod_carry ? (|product[21:0]) : (|product[20:0]);

    // 27-bit mantissa for fpu_round: {mant24, G, R, S}
    wire [26:0] norm_mant = {norm_mant24, norm_g, norm_r, norm_s};

    // Exponent after normalization (10-bit)
    wire [9:0] exp_normed_10 = prod_carry ? (exp_raw_10 + 10'd1) : exp_raw_10;

    // Overflow: exponent >= 255 before rounding (result too large)
    wire exp_overflow_pre = (exp_normed_10 >= 10'd255);

    // Underflow: exponent <= 0
    // In 10-bit unsigned, values >= 512 represent "negative" (wrap-around from
    // the subtraction exp_sum - 127 when exp_sum < 127).  bit[9] detects this.
    wire exp_le_zero = exp_normed_10[9] | (exp_normed_10 == 10'd0);

    // For subnormal: denormalize by shifting mantissa right
    // right_shift = 1 - exp_normed (when exp_normed <= 0)
    // Modular arithmetic: 1 - exp_normed_10[7:0] gives correct result
    wire [7:0] denorm_rshift = 8'd1 - exp_normed_10[7:0];

    // Guard: if denorm_rshift >= 27, all mantissa bits are shifted out
    wire denorm_too_small = (denorm_rshift >= 8'd27);

    // Denormalize: shift the 27-bit mantissa right
    // Extend to 51 bits for the shift: {norm_mant, 24'b0}
    wire [50:0] denorm_extended = {norm_mant, 24'b0};
    wire [50:0] denorm_shifted  = denorm_extended >> denorm_rshift[4:0];

    wire [23:0] denorm_mant24 = denorm_too_small ? 24'b0         : denorm_shifted[50:27];
    wire        denorm_g      = denorm_too_small ? 1'b0          : denorm_shifted[26];
    wire        denorm_r      = denorm_too_small ? 1'b0          : denorm_shifted[25];
    wire        denorm_s      = denorm_too_small ? (|norm_mant)  : (|denorm_shifted[24:0]);
    wire [26:0] denorm_mant   = {denorm_mant24, denorm_g, denorm_r, denorm_s};

    // Select between normal and subnormal
    wire [26:0] final_mant = exp_le_zero ? denorm_mant : norm_mant;
    wire [7:0]  final_exp  = exp_le_zero ? 8'b0 : exp_normed_10[7:0];

    // ===================================================================
    // Rounding
    // ===================================================================
    wire [23:0] rounded_mant;
    wire        round_up_w;
    wire        round_overflow;

    fpu_round rnd(
        .rm(rm_r),
        .sign(res_sign),
        .mantissa(final_mant),
        .rounded(rounded_mant),
        .round_up(round_up_w),
        .overflow(round_overflow)
    );

    // Exponent after rounding overflow (9-bit to catch wrap-around)
    wire [8:0] exp_after_round_9 = {1'b0, final_exp} + {8'b0, round_overflow};
    wire [7:0] exp_after_round   = exp_after_round_9[7:0];

    // Detect exponent overflow (from rounding or pre-existing)
    wire exp_overflow = (exp_after_round_9 >= 9'd255) | exp_overflow_pre;

    // Detect inexact
    wire inexact = (final_mant[2] | final_mant[1] | final_mant[0]) | round_up_w;

    // Underflow: subnormal result and inexact
    wire underflow = exp_le_zero & inexact;

    // Pack result
    wire [31:0] packed_normal = {res_sign, exp_after_round, rounded_mant[22:0]};
    wire [31:0] packed_inf    = {res_sign, 8'hFF, 23'b0};

    // Overflow result depends on rounding mode
    wire ovf_to_inf = (rm_r == 3'b000) |  // RNE
                      (rm_r == 3'b100) |  // RMM
                      ((rm_r == 3'b011) & ~res_sign) |  // RUP & positive
                      ((rm_r == 3'b010) & res_sign);    // RDN & negative
    wire [31:0] packed_max    = {res_sign, 8'hFE, 23'h7FFFFF};
    wire [31:0] overflow_res  = ovf_to_inf ? packed_inf : packed_max;

    // Zero result (from subnormal that rounds to zero)
    wire [31:0] packed_zero = {res_sign, 31'b0};
    wire result_is_zero = (rounded_mant == 24'b0) & exp_le_zero;

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
            state    <= S_IDLE;
            done_r   <= 1'b0;
            result_r <= 32'b0;
            fflags_r <= 5'b0;
            src1_r   <= 32'b0;
            src2_r   <= 32'b0;
            rm_r     <= 3'b0;
        end else if (flush) begin
            state    <= S_IDLE;
        end else begin
            done_r <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        src1_r <= src1;
                        src2_r <= src2;
                        rm_r   <= rm;
                        state  <= S_COMPUTE;
                    end
                end

                // -------------------------------------------------------
                S_COMPUTE: begin
                    if (is_special) begin
                        result_r <= special_res;
                        fflags_r <= special_flags;
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
