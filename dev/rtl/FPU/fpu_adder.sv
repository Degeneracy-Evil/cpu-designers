`timescale 1ns / 1ps

module fpu_adder(
    input         clk,
    input         reset,
    input  [31:0] src1,
    input  [31:0] src2,
    input         is_sub,      // 1 for FSUB.S
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
    localparam S_ALIGN = 3'd1;
    localparam S_ADD   = 3'd2;
    localparam S_NORM  = 3'd3;
    localparam S_ROUND = 3'd4;
    localparam S_DONE  = 3'd5;

    reg [2:0] state;

    // ===================================================================
    // Latched inputs
    // ===================================================================
    reg [31:0] src1_r, src2_r;
    reg        is_sub_r;
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
    // ALIGN-stage combinational logic
    // ===================================================================
    wire        eff_sign2 = is_sub_r ? ~s2_sign : s2_sign;
    wire        eff_sub   = (s1_sign != eff_sign2);

    // Biased exponent: subnormals use 1, normals use exp
    wire [7:0]  bexp1 = (s1_exp == 8'b0) ? 8'd1 : s1_exp;
    wire [7:0]  bexp2 = (s2_exp == 8'b0) ? 8'd1 : s2_exp;

    // Hidden bits
    wire        h1 = (s1_exp != 8'b0);
    wire        h2 = (s2_exp != 8'b0);

    // 27-bit extended mantissas: {hidden, frac, 3'b000}
    wire [26:0] m1_ext = {h1, s1_frac, 3'b000};
    wire [26:0] m2_ext = {h2, s2_frac, 3'b000};

    // Determine which operand is larger (magnitude)
    wire        exp1_gt_exp2 = (bexp1 > bexp2);
    wire        exp1_eq_exp2 = (bexp1 == bexp2);
    wire        mant1_gt_mant2 = (m1_ext > m2_ext);
    wire        swap = exp1_gt_exp2 ? 1'b0 :
                       exp1_eq_exp2 ? ~mant1_gt_mant2 : 1'b1;

    // After possible swap: a is the larger, b is the smaller
    wire [7:0]  bexp_a   = swap ? bexp2   : bexp1;
    wire [7:0]  bexp_b   = swap ? bexp1   : bexp2;
    wire [26:0] mant_a   = swap ? m2_ext  : m1_ext;
    wire [26:0] mant_b   = swap ? m1_ext  : m2_ext;
    wire        sign_a   = swap ? s2_sign : s1_sign;
    wire        sign_b   = swap ? s1_sign : s2_sign;

    // Result sign for effective subtract
    // Must use effective sign of the larger magnitude operand, not original sign.
    // When swap=1, the larger operand is src2 with effective sign eff_sign2.
    // When swap=0, the larger operand is src1 with sign s1_sign.
    wire        eff_sign_a  = swap ? eff_sign2 : s1_sign;
    wire        res_sign_sub = eff_sign_a;

    // Result sign for effective add
    wire        res_sign_add = s1_sign;  // both have same effective sign

    // Exponent difference
    wire [7:0]  exp_diff = bexp_a - bexp_b;

    // Alignment: shift mant_b right by exp_diff, compute sticky
    wire [53:0] mant_b_padded = {mant_b, 27'b0};
    wire [53:0] mant_b_shifted = mant_b_padded >> exp_diff[4:0];
    wire [26:0] mant_b_aligned_comb = (exp_diff >= 8'd27) ? 27'b0 : mant_b_shifted[53:27];
    wire        sticky_align_comb   = (exp_diff >= 8'd27) ? (|mant_b) : |mant_b_shifted[26:0];

    // Combine sticky into aligned mantissa bit[0]
    wire [26:0] mant_b_final = {mant_b_aligned_comb[26:1],
                                mant_b_aligned_comb[0] | sticky_align_comb};

    // Special-case detection
    wire        any_nan     = s1_nan | s2_nan;
    wire        any_snan    = s1_snan | s2_snan;
    wire        both_inf    = s1_inf & s2_inf;
    wire        any_inf     = s1_inf | s2_inf;
    wire        both_zero   = s1_zero & s2_zero;

    // Inf + (-Inf) => qNaN
    wire        inf_invalid = both_inf & (s1_sign != eff_sign2);

    // Special-case result
    wire [31:0] special_res_comb = any_nan   ? qnan :
                                   inf_invalid ? qnan :
                                   s1_inf     ? {s1_sign, 8'hFF, 23'b0} :
                                   s2_inf     ? {eff_sign2, 8'hFF, 23'b0} :
                                                32'b0;  // placeholder for zero

    // Zero result sign: same-sign zero => that sign; opposite-sign zero => per RM
    wire        zero_sign_comb = (s1_sign == eff_sign2) ? s1_sign :
                                (rm_r == 3'b010) ? 1'b1 : 1'b0;  // RDN => -0

    wire [31:0] zero_res_comb = {zero_sign_comb, 31'b0};

    wire        is_special_comb = any_nan | any_inf | both_zero |
                                 (s1_zero & ~s2_zero) | (~s1_zero & s2_zero);

    // Flags for special cases
    wire [4:0]  special_flags_comb = (any_nan | inf_invalid) ? {any_snan | inf_invalid, 4'b0} : 5'b0;

    // One operand is zero => result is the other
    wire [31:0] one_zero_res_comb = s1_zero ? {eff_sign2, s2_exp, s2_frac} :
                                      {s1_sign, s1_exp, s1_frac};

    // ===================================================================
    // Pipeline registers (ALIGN → ADD)
    // ===================================================================
    reg [7:0]  al_exp;
    reg [26:0] al_mant_a;
    reg [26:0] al_mant_b;
    reg        al_eff_sub;
    reg        al_sign;
    reg        al_special;
    reg [31:0] al_spec_res;
    reg [4:0]  al_spec_flags;

    // ===================================================================
    // ADD-stage combinational logic
    // ===================================================================
    wire [27:0] add_result = al_mant_a + al_mant_b;
    wire [27:0] sub_result = al_mant_a - al_mant_b;

    wire [27:0] sum_comb  = al_eff_sub ? sub_result : add_result;
    wire        carry_comb = ~al_eff_sub & add_result[27];

    // ===================================================================
    // Pipeline registers (ADD → NORM)
    // ===================================================================
    reg [7:0]  ad_exp;
    reg [27:0] ad_sum;
    reg        ad_sign;
    reg        ad_eff_sub;
    reg        ad_carry;
    reg        ad_special;
    reg [31:0] ad_spec_res;
    reg [4:0]  ad_spec_flags;

    // ===================================================================
    // NORM-stage combinational logic
    // ===================================================================

    // --- Case 1: effective ADD with carry ---
    // Shift right by 1: {1, sum[26:1]}, sticky = sum[0]
    wire [26:0] norm_mant_add_carry = {1'b1, ad_sum[26:4],
                                        ad_sum[3], ad_sum[2],
                                        ad_sum[1] | ad_sum[0]};
    wire [7:0]  norm_exp_add_carry  = ad_exp + 8'd1;

    // --- Case 2: effective SUB (or ADD without carry) ---
    // Count leading zeros in the 24-bit mantissa portion sum[26:3]
    wire [23:0] sub_mant24 = ad_sum[26:3];
    wire [4:0]  lz;
    assign lz = (sub_mant24[23]) ? 5'd0 :
                (sub_mant24[22]) ? 5'd1 :
                (sub_mant24[21]) ? 5'd2 :
                (sub_mant24[20]) ? 5'd3 :
                (sub_mant24[19]) ? 5'd4 :
                (sub_mant24[18]) ? 5'd5 :
                (sub_mant24[17]) ? 5'd6 :
                (sub_mant24[16]) ? 5'd7 :
                (sub_mant24[15]) ? 5'd8 :
                (sub_mant24[14]) ? 5'd9 :
                (sub_mant24[13]) ? 5'd10 :
                (sub_mant24[12]) ? 5'd11 :
                (sub_mant24[11]) ? 5'd12 :
                (sub_mant24[10]) ? 5'd13 :
                (sub_mant24[9])  ? 5'd14 :
                (sub_mant24[8])  ? 5'd15 :
                (sub_mant24[7])  ? 5'd16 :
                (sub_mant24[6])  ? 5'd17 :
                (sub_mant24[5])  ? 5'd18 :
                (sub_mant24[4])  ? 5'd19 :
                (sub_mant24[3])  ? 5'd20 :
                (sub_mant24[2])  ? 5'd21 :
                (sub_mant24[1])  ? 5'd22 :
                (sub_mant24[0])  ? 5'd23 :
                                    5'd24;

    // Use 51-bit extended value for left shift to preserve rounding info
    // extended = {sum[26:0], 24'b0}
    wire [50:0] sub_extended = {ad_sum[26:0], 24'b0};
    wire [50:0] sub_shifted  = sub_extended << lz;

    // Extract normalized mantissa and rounding bits
    wire [23:0] sub_norm_mant24 = sub_shifted[50:27];
    wire        sub_norm_g      = sub_shifted[26];
    wire        sub_norm_r      = sub_shifted[25];
    wire        sub_norm_s      = |sub_shifted[24:0];
    wire [26:0] norm_mant_sub   = {sub_norm_mant24, sub_norm_g, sub_norm_r, sub_norm_s};

    // Normalized exponent
    wire [7:0]  norm_exp_sub_raw = ad_exp - lz;

    // Check if result is zero (all 24 mantissa bits are zero)
    wire        sub_is_zero = (sub_mant24 == 24'b0);

    // Check if subnormal (exponent <= 0 after normalization)
    wire        sub_is_subnormal = (~sub_is_zero) & (ad_exp <= lz);

    // For subnormal result: need to denormalize
    // right_shift = 1 - (ad_exp - lz) = 1 - ad_exp + lz
    wire [5:0]  subnormal_rshift = 6'd1 + {1'b0, lz} - {2'b0, ad_exp};

    // Denormalize: shift the already-normalized 51-bit value right
    wire [50:0] sub_denorm_shifted = sub_shifted >> subnormal_rshift[4:0];
    wire [23:0] sub_denorm_mant24  = sub_denorm_shifted[50:27];
    wire        sub_denorm_g       = sub_denorm_shifted[26];
    wire        sub_denorm_r       = sub_denorm_shifted[25];
    wire        sub_denorm_s       = |sub_denorm_shifted[24:0];
    wire [26:0] norm_mant_denorm   = {sub_denorm_mant24, sub_denorm_g, sub_denorm_r, sub_denorm_s};

    // Select between normal and subnormal
    wire [26:0] norm_mant_sub_final = sub_is_subnormal ? norm_mant_denorm : norm_mant_sub;
    wire [7:0]  norm_exp_sub_final  = sub_is_subnormal ? 8'b0 : norm_exp_sub_raw;

    // Zero result sign for subtraction cancellation
    wire        zero_sign_sub = (rm_r == 3'b010) ? 1'b1 : 1'b0;  // RDN => -0

    // Combine all normalization cases
    wire        norm_is_add_carry = ~ad_eff_sub & ad_carry;
    wire [26:0] norm_mant_comb = norm_is_add_carry ? norm_mant_add_carry :
                                 sub_is_zero       ? 27'b0 :
                                                     norm_mant_sub_final;
    wire [7:0]  norm_exp_comb  = norm_is_add_carry ? norm_exp_add_carry :
                                 sub_is_zero       ? 8'b0 :
                                                     norm_exp_sub_final;
    wire        norm_is_zero_comb = sub_is_zero & ~norm_is_add_carry;
    wire        norm_sign_comb = norm_is_zero_comb ?
                                (ad_eff_sub ? zero_sign_sub : ad_sign) :
                                ad_sign;

    // Underflow: result is subnormal and non-zero
    wire norm_uf_comb = sub_is_subnormal & ~sub_is_zero;

    // Inexact from subnormal denormalization (bits were discarded)
    wire norm_nx_denorm = sub_is_subnormal &
                          (sub_denorm_g | sub_denorm_r | sub_denorm_s);

    // ===================================================================
    // Pipeline registers (NORM → ROUND)
    // ===================================================================
    reg [7:0]  nm_exp;
    reg [26:0] nm_mant;
    reg        nm_sign;
    reg        nm_is_zero;
    reg        nm_uf;
    reg        nm_nx_denorm;
    reg        nm_special;
    reg [31:0] nm_spec_res;
    reg [4:0]  nm_spec_flags;

    // ===================================================================
    // ROUND-stage: instantiate fpu_round
    // ===================================================================
    wire [23:0] rounded_mant;
    wire        round_up;
    wire        round_overflow;

    fpu_round rnd(
        .rm(rm_r),
        .sign(nm_sign),
        .mantissa(nm_mant),
        .rounded(rounded_mant),
        .round_up(round_up),
        .overflow(round_overflow)
    );

    // Exponent after rounding overflow (9-bit to catch wrap-around)
    wire [8:0]  exp_after_round_9 = {1'b0, nm_exp} + {8'b0, round_overflow};
    wire [7:0]  exp_after_round   = exp_after_round_9[7:0];

    // Detect exponent overflow (result too large => Inf)
    wire        exp_overflow = (exp_after_round_9 >= 9'd255) & ~nm_is_zero;

    // Detect inexact (any rounding bits were non-zero)
    wire        inexact = (nm_mant[2] | nm_mant[1] | nm_mant[0]) | round_up;

    // Pack result
    wire [31:0] packed_normal = {nm_sign, exp_after_round, rounded_mant[22:0]};
    wire [31:0] packed_inf    = {nm_sign, 8'hFF, 23'b0};

    // Overflow result depends on rounding mode
    wire        ovf_to_inf = (rm_r == 3'b000) |  // RNE
                             (rm_r == 3'b100) |  // RMM
                             ((rm_r == 3'b011) & ~nm_sign) |  // RUP & positive
                             ((rm_r == 3'b010) & nm_sign);    // RDN & negative
    wire [31:0] packed_max  = {nm_sign, 8'hFE, 23'h7FFFFF};
    wire [31:0] overflow_res = ovf_to_inf ? packed_inf : packed_max;

    // Zero result
    wire [31:0] packed_zero = {nm_sign, 31'b0};

    // Final result and flags
    wire [31:0] round_res_comb = nm_is_zero  ? packed_zero :
                                 exp_overflow ? overflow_res :
                                                packed_normal;
    wire [4:0]  round_flags_comb = nm_is_zero ? 5'b0 :
                                  {1'b0, 1'b0,                             // NV, DZ
                                   exp_overflow,                           // OF
                                   nm_uf & (inexact | nm_nx_denorm),      // UF
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
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= S_IDLE;
            done_r    <= 1'b0;
            result_r  <= 32'b0;
            fflags_r  <= 5'b0;
            src1_r    <= 32'b0;
            src2_r    <= 32'b0;
            is_sub_r  <= 1'b0;
            rm_r      <= 3'b0;
            al_exp    <= 8'b0;
            al_mant_a <= 27'b0;
            al_mant_b <= 27'b0;
            al_eff_sub<= 1'b0;
            al_sign   <= 1'b0;
            al_special<= 1'b0;
            al_spec_res<= 32'b0;
            al_spec_flags<= 5'b0;
            ad_exp    <= 8'b0;
            ad_sum    <= 28'b0;
            ad_sign   <= 1'b0;
            ad_eff_sub<= 1'b0;
            ad_carry  <= 1'b0;
            ad_special<= 1'b0;
            ad_spec_res<= 32'b0;
            ad_spec_flags<= 5'b0;
            nm_exp    <= 8'b0;
            nm_mant   <= 27'b0;
            nm_sign   <= 1'b0;
            nm_is_zero<= 1'b0;
            nm_uf     <= 1'b0;
            nm_nx_denorm<= 1'b0;
            nm_special<= 1'b0;
            nm_spec_res<= 32'b0;
            nm_spec_flags<= 5'b0;
        end else if (flush) begin
            state     <= S_IDLE;
        end else begin
            done_r <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        src1_r   <= src1;
                        src2_r   <= src2;
                        is_sub_r <= is_sub;
                        rm_r     <= rm;
                        state    <= S_ALIGN;
                    end
                end

                // -------------------------------------------------------
                S_ALIGN: begin
                    if (is_special_comb) begin
                        al_special   <= 1'b1;
                        if (any_nan | inf_invalid) begin
                            al_spec_res  <= qnan;
                            al_spec_flags<= {any_snan | inf_invalid, 4'b0};
                        end else if (any_inf) begin
                            al_spec_res  <= special_res_comb;
                            al_spec_flags<= 5'b0;
                        end else if (both_zero) begin
                            al_spec_res  <= zero_res_comb;
                            al_spec_flags<= 5'b0;
                        end else begin
                            // One operand is zero
                            al_spec_res  <= one_zero_res_comb;
                            al_spec_flags<= 5'b0;
                        end
                    end else begin
                        al_special   <= 1'b0;
                        al_exp       <= bexp_a;
                        al_mant_a    <= mant_a;
                        al_mant_b    <= mant_b_final;
                        al_eff_sub   <= eff_sub;
                        al_sign      <= eff_sub ? res_sign_sub : res_sign_add;
                        al_spec_res  <= 32'b0;
                        al_spec_flags<= 5'b0;
                    end
                    state <= S_ADD;
                end

                // -------------------------------------------------------
                S_ADD: begin
                    if (al_special) begin
                        ad_special    <= 1'b1;
                        ad_spec_res   <= al_spec_res;
                        ad_spec_flags <= al_spec_flags;
                        ad_exp    <= 8'b0;
                        ad_sum    <= 28'b0;
                        ad_sign   <= 1'b0;
                        ad_eff_sub<= 1'b0;
                        ad_carry  <= 1'b0;
                    end else begin
                        ad_special    <= 1'b0;
                        ad_exp        <= al_exp;
                        ad_sum        <= sum_comb;
                        ad_sign       <= al_sign;
                        ad_eff_sub    <= al_eff_sub;
                        ad_carry      <= carry_comb;
                        ad_spec_res   <= 32'b0;
                        ad_spec_flags <= 5'b0;
                    end
                    state <= S_NORM;
                end

                // -------------------------------------------------------
                S_NORM: begin
                    if (ad_special) begin
                        nm_special    <= 1'b1;
                        nm_spec_res   <= ad_spec_res;
                        nm_spec_flags <= ad_spec_flags;
                        nm_exp    <= 8'b0;
                        nm_mant   <= 27'b0;
                        nm_sign   <= 1'b0;
                        nm_is_zero<= 1'b0;
                        nm_uf     <= 1'b0;
                        nm_nx_denorm<= 1'b0;
                    end else begin
                        nm_special    <= 1'b0;
                        nm_exp        <= norm_exp_comb;
                        nm_mant       <= norm_mant_comb;
                        nm_sign       <= norm_sign_comb;
                        nm_is_zero    <= norm_is_zero_comb;
                        nm_uf         <= norm_uf_comb;
                        nm_nx_denorm  <= norm_nx_denorm;
                        nm_spec_res   <= 32'b0;
                        nm_spec_flags <= 5'b0;
                    end
                    state <= S_ROUND;
                end

                // -------------------------------------------------------
                S_ROUND: begin
                    if (nm_special) begin
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
