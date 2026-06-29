`timescale 1ns / 1ps

// ===================================================================
// IEEE 754 double-precision floating-point adder/subtractor (FADD.D/FSUB.D)
//
// Architecture mirrors fpu_adder.sv (single-precision) with widened
// datapath:
//   - Exponent:  8  -> 11 bits (bias 127 -> 1023)
//   - Mantissa:  23 -> 52 bits (plus implicit 1 = 53-bit significand)
//   - Result:    32 -> 64 bits
//
// Special-case detection (fpu_special) and rounding (fpu_round) are
// inlined here to avoid creating D-precision helper modules.  The
// algorithm and FSM are identical to the single-precision reference.
//
// FSM: S_IDLE -> S_ALIGN -> S_ADD -> S_NORM -> S_ROUND -> S_DONE
// ===================================================================

module fpu_adder_d(
    input         clk,
    input         resetn,
    input  [63:0] src1,
    input  [63:0] src2,
    input         is_sub,      // 1 for FSUB.D
    input  [2:0]  rm,          // rounding mode
    input         start,
    input         flush,
    output [63:0] result,
    output [4:0]  fflags,      // {NV, DZ, OF, UF, NX}
    output        done
);

    // ===================================================================
    // Field constants
    // ===================================================================
    localparam [10:0] EXP_INF  = 11'h7FF;   // all-ones exponent
    localparam [63:0] CANON_QNAN = 64'h7FF8000000000000;

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
    reg [63:0] src1_r, src2_r;
    reg        is_sub_r;
    reg [2:0]  rm_r;

    // ===================================================================
    // Inlined fpu_special — field extraction on latched inputs
    // ===================================================================
    wire        s1_sign = src1_r[63];
    wire [10:0] s1_exp  = src1_r[62:52];
    wire [51:0] s1_frac = src1_r[51:0];

    wire        s2_sign = src2_r[63];
    wire [10:0] s2_exp  = src2_r[62:52];
    wire [51:0] s2_frac = src2_r[51:0];

    wire        s1_nan  = (s1_exp == EXP_INF) & (s1_frac != 52'b0);
    wire        s2_nan  = (s2_exp == EXP_INF) & (s2_frac != 52'b0);

    wire        s1_snan = s1_nan & ~s1_frac[51];
    wire        s2_snan = s2_nan & ~s2_frac[51];

    wire        s1_inf  = (s1_exp == EXP_INF) & (s1_frac == 52'b0);
    wire        s2_inf  = (s2_exp == EXP_INF) & (s2_frac == 52'b0);

    wire        s1_zero = (s1_exp == 11'b0) & (s1_frac == 52'b0);
    wire        s2_zero = (s2_exp == 11'b0) & (s2_frac == 52'b0);

    // ===================================================================
    // ALIGN-stage combinational logic
    // ===================================================================
    wire        eff_sign2 = is_sub_r ? ~s2_sign : s2_sign;
    wire        eff_sub   = (s1_sign != eff_sign2);

    // Biased exponent: subnormals use 1, normals use exp
    wire [10:0] bexp1 = (s1_exp == 11'b0) ? 11'd1 : s1_exp;
    wire [10:0] bexp2 = (s2_exp == 11'b0) ? 11'd1 : s2_exp;

    // Hidden bits
    wire        h1 = (s1_exp != 11'b0);
    wire        h2 = (s2_exp != 11'b0);

    // 56-bit extended mantissas: {hidden, frac, 3'b000}
    wire [55:0] m1_ext = {h1, s1_frac, 3'b000};
    wire [55:0] m2_ext = {h2, s2_frac, 3'b000};

    // Determine which operand is larger (magnitude)
    wire        exp1_gt_exp2  = (bexp1 > bexp2);
    wire        exp1_eq_exp2  = (bexp1 == bexp2);
    wire        mant1_gt_mant2 = (m1_ext > m2_ext);
    wire        swap = exp1_gt_exp2 ? 1'b0 :
                       exp1_eq_exp2 ? ~mant1_gt_mant2 : 1'b1;

    // After possible swap: a is the larger, b is the smaller
    wire [10:0] bexp_a = swap ? bexp2   : bexp1;
    wire [10:0] bexp_b = swap ? bexp1   : bexp2;
    wire [55:0] mant_a = swap ? m2_ext  : m1_ext;
    wire [55:0] mant_b = swap ? m1_ext  : m2_ext;
    wire        sign_a = swap ? s2_sign : s1_sign;
    wire        sign_b = swap ? s1_sign : s2_sign;

    // Result sign for effective subtract (use effective sign of larger)
    wire        eff_sign_a    = swap ? eff_sign2 : s1_sign;
    wire        res_sign_sub  = eff_sign_a;

    // Result sign for effective add
    wire        res_sign_add  = s1_sign;

    // Exponent difference
    wire [10:0] exp_diff = bexp_a - bexp_b;

    // Alignment: shift mant_b right by exp_diff, compute sticky
    wire [111:0] mant_b_padded   = {mant_b, 56'b0};
    wire [111:0] mant_b_shifted  = mant_b_padded >> exp_diff[5:0];
    wire [55:0]  mant_b_aligned  = (exp_diff >= 11'd56) ? 56'b0 : mant_b_shifted[111:56];
    wire         sticky_align    = (exp_diff >= 11'd56) ? (|mant_b) : |mant_b_shifted[55:0];

    // Combine sticky into aligned mantissa bit[0]
    wire [55:0]  mant_b_final = {mant_b_aligned[55:1],
                                 mant_b_aligned[0] | sticky_align};

    // Special-case detection
    wire        any_nan   = s1_nan | s2_nan;
    wire        any_snan  = s1_snan | s2_snan;
    wire        both_inf  = s1_inf & s2_inf;
    wire        any_inf   = s1_inf | s2_inf;
    wire        both_zero = s1_zero & s2_zero;

    // Inf + (-Inf) => qNaN
    wire        inf_invalid = both_inf & (s1_sign != eff_sign2);

    // Special-case result
    wire [63:0] special_res_comb = any_nan     ? CANON_QNAN :
                                   inf_invalid ? CANON_QNAN :
                                   s1_inf      ? {s1_sign,    EXP_INF, 52'b0} :
                                   s2_inf      ? {eff_sign2,  EXP_INF, 52'b0} :
                                                 64'b0;  // placeholder for zero

    // Zero result sign: same-sign zero => that sign; opposite-sign zero => per RM
    wire        zero_sign_comb = (s1_sign == eff_sign2) ? s1_sign :
                                 (rm_r == 3'b010) ? 1'b1 : 1'b0;  // RDN => -0

    wire [63:0] zero_res_comb = {zero_sign_comb, 63'b0};

    wire        is_special_comb = any_nan | any_inf | both_zero |
                                  (s1_zero & ~s2_zero) | (~s1_zero & s2_zero);

    // Flags for special cases
    wire [4:0]  special_flags_comb = (any_nan | inf_invalid) ?
                                     {any_snan | inf_invalid, 4'b0} : 5'b0;

    // One operand is zero => result is the other
    wire [63:0] one_zero_res_comb = s1_zero ? {eff_sign2, s2_exp, s2_frac} :
                                         {s1_sign,   s1_exp, s1_frac};

    // ===================================================================
    // Pipeline registers (ALIGN -> ADD)
    // ===================================================================
    reg [10:0] al_exp;
    reg [55:0] al_mant_a;
    reg [55:0] al_mant_b;
    reg        al_eff_sub;
    reg        al_sign;
    reg        al_special;
    reg [63:0] al_spec_res;
    reg [4:0]  al_spec_flags;

    // ===================================================================
    // ADD-stage combinational logic
    // ===================================================================
    wire [56:0] add_result  = {1'b0, al_mant_a} + {1'b0, al_mant_b};
    wire [56:0] sub_result  = {1'b0, al_mant_a} - {1'b0, al_mant_b};

    wire [56:0] sum_comb    = al_eff_sub ? sub_result : add_result;
    wire        carry_comb  = ~al_eff_sub & add_result[56];

    // ===================================================================
    // Pipeline registers (ADD -> NORM)
    // ===================================================================
    reg [10:0] ad_exp;
    reg [56:0] ad_sum;
    reg        ad_sign;
    reg        ad_eff_sub;
    reg        ad_carry;
    reg        ad_special;
    reg [63:0] ad_spec_res;
    reg [4:0]  ad_spec_flags;

    // ===================================================================
    // NORM-stage combinational logic
    // ===================================================================

    // --- Case 1: effective ADD with carry ---
    // Shift right by 1: {1, sum[55:1]}, sticky = sum[0]
    wire [55:0] norm_mant_add_carry = {1'b1, ad_sum[55:4],
                                       ad_sum[3], ad_sum[2],
                                       ad_sum[1] | ad_sum[0]};
    wire [10:0] norm_exp_add_carry  = ad_exp + 11'd1;

    // --- Case 2: effective SUB (or ADD without carry) ---
    // Count leading zeros in the 53-bit mantissa portion sum[55:3]
    wire [52:0] sub_mant53 = ad_sum[55:3];
    wire [5:0]  lz;
    assign lz = (sub_mant53[52]) ? 6'd0 :
                (sub_mant53[51]) ? 6'd1 :
                (sub_mant53[50]) ? 6'd2 :
                (sub_mant53[49]) ? 6'd3 :
                (sub_mant53[48]) ? 6'd4 :
                (sub_mant53[47]) ? 6'd5 :
                (sub_mant53[46]) ? 6'd6 :
                (sub_mant53[45]) ? 6'd7 :
                (sub_mant53[44]) ? 6'd8 :
                (sub_mant53[43]) ? 6'd9 :
                (sub_mant53[42]) ? 6'd10 :
                (sub_mant53[41]) ? 6'd11 :
                (sub_mant53[40]) ? 6'd12 :
                (sub_mant53[39]) ? 6'd13 :
                (sub_mant53[38]) ? 6'd14 :
                (sub_mant53[37]) ? 6'd15 :
                (sub_mant53[36]) ? 6'd16 :
                (sub_mant53[35]) ? 6'd17 :
                (sub_mant53[34]) ? 6'd18 :
                (sub_mant53[33]) ? 6'd19 :
                (sub_mant53[32]) ? 6'd20 :
                (sub_mant53[31]) ? 6'd21 :
                (sub_mant53[30]) ? 6'd22 :
                (sub_mant53[29]) ? 6'd23 :
                (sub_mant53[28]) ? 6'd24 :
                (sub_mant53[27]) ? 6'd25 :
                (sub_mant53[26]) ? 6'd26 :
                (sub_mant53[25]) ? 6'd27 :
                (sub_mant53[24]) ? 6'd28 :
                (sub_mant53[23]) ? 6'd29 :
                (sub_mant53[22]) ? 6'd30 :
                (sub_mant53[21]) ? 6'd31 :
                (sub_mant53[20]) ? 6'd32 :
                (sub_mant53[19]) ? 6'd33 :
                (sub_mant53[18]) ? 6'd34 :
                (sub_mant53[17]) ? 6'd35 :
                (sub_mant53[16]) ? 6'd36 :
                (sub_mant53[15]) ? 6'd37 :
                (sub_mant53[14]) ? 6'd38 :
                (sub_mant53[13]) ? 6'd39 :
                (sub_mant53[12]) ? 6'd40 :
                (sub_mant53[11]) ? 6'd41 :
                (sub_mant53[10]) ? 6'd42 :
                (sub_mant53[9])  ? 6'd43 :
                (sub_mant53[8])  ? 6'd44 :
                (sub_mant53[7])  ? 6'd45 :
                (sub_mant53[6])  ? 6'd46 :
                (sub_mant53[5])  ? 6'd47 :
                (sub_mant53[4])  ? 6'd48 :
                (sub_mant53[3])  ? 6'd49 :
                (sub_mant53[2])  ? 6'd50 :
                (sub_mant53[1])  ? 6'd51 :
                (sub_mant53[0])  ? 6'd52 :
                                   6'd53;

    // Use 109-bit extended value for left shift to preserve rounding info
    // extended = {sum[55:0], 53'b0}
    wire [108:0] sub_extended = {ad_sum[55:0], 53'b0};
    wire [108:0] sub_shifted  = sub_extended << lz;

    // Extract normalized mantissa and rounding bits
    wire [52:0] sub_norm_mant53 = sub_shifted[108:56];
    wire        sub_norm_g      = sub_shifted[55];
    wire        sub_norm_r      = sub_shifted[54];
    wire        sub_norm_s      = |sub_shifted[53:0];
    wire [55:0] norm_mant_sub   = {sub_norm_mant53, sub_norm_g, sub_norm_r, sub_norm_s};

    // Normalized exponent
    wire [10:0] norm_exp_sub_raw = ad_exp - {5'b0, lz};

    // Check if result is zero (all 53 mantissa bits are zero)
    wire        sub_is_zero = (sub_mant53 == 53'b0);

    // Check if subnormal (exponent <= 0 after normalization)
    wire        sub_is_subnormal = (~sub_is_zero) & (ad_exp <= {5'b0, lz});

    // For subnormal result: need to denormalize
    // right_shift = 1 - (ad_exp - lz) = 1 - ad_exp + lz
    wire [6:0]  subnormal_rshift = 7'd1 + {1'b0, lz} - {1'b0, ad_exp[5:0]};

    // Denormalize: shift the already-normalized 109-bit value right
    wire [108:0] sub_denorm_shifted = sub_shifted >> subnormal_rshift[5:0];
    wire [52:0]  sub_denorm_mant53  = sub_denorm_shifted[108:56];
    wire         sub_denorm_g       = sub_denorm_shifted[55];
    wire         sub_denorm_r       = sub_denorm_shifted[54];
    wire         sub_denorm_s       = |sub_denorm_shifted[53:0];
    wire [55:0]  norm_mant_denorm   = {sub_denorm_mant53, sub_denorm_g,
                                       sub_denorm_r, sub_denorm_s};

    // Select between normal and subnormal
    wire [55:0] norm_mant_sub_final = sub_is_subnormal ? norm_mant_denorm : norm_mant_sub;
    wire [10:0] norm_exp_sub_final  = sub_is_subnormal ? 11'b0 : norm_exp_sub_raw;

    // Zero result sign for subtraction cancellation
    wire        zero_sign_sub = (rm_r == 3'b010) ? 1'b1 : 1'b0;  // RDN => -0

    // Combine all normalization cases
    wire        norm_is_add_carry = ~ad_eff_sub & ad_carry;
    wire [55:0] norm_mant_comb = norm_is_add_carry ? norm_mant_add_carry :
                                 sub_is_zero       ? 56'b0 :
                                                     norm_mant_sub_final;
    wire [10:0] norm_exp_comb  = norm_is_add_carry ? norm_exp_add_carry :
                                 sub_is_zero       ? 11'b0 :
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
    // Pipeline registers (NORM -> ROUND)
    // ===================================================================
    reg [10:0] nm_exp;
    reg [55:0] nm_mant;
    reg        nm_sign;
    reg        nm_is_zero;
    reg        nm_uf;
    reg        nm_nx_denorm;
    reg        nm_special;
    reg [63:0] nm_spec_res;
    reg [4:0]  nm_spec_flags;

    // ===================================================================
    // ROUND-stage: inlined fpu_round (double-precision)
    //
    // Mantissa format: {1.hidden, 52.fraction, guard, round, sticky}
    //   bit[55]     = hidden
    //   bit[54:3]   = fraction (52 bits)
    //   bit[2]      = guard
    //   bit[1]      = round
    //   bit[0]      = sticky
    // ===================================================================
    wire        hidden_d  = nm_mant[55];
    wire [51:0] frac_d    = nm_mant[54:3];
    wire        guard_d   = nm_mant[2];
    wire        round_d   = nm_mant[1];
    wire        sticky_d  = nm_mant[0];

    wire        frac_lsb_d = frac_d[0];

    // Per-mode round-up logic
    wire        rne_up_d = guard_d & (round_d | sticky_d | frac_lsb_d);
    wire        rtz_up_d = 1'b0;
    wire        rdn_up_d = nm_sign & (guard_d | round_d | sticky_d);
    wire        rup_up_d = ~nm_sign & (guard_d | round_d | sticky_d);
    wire        rmm_up_d = guard_d;

    wire        round_up_d = (rm_r == 3'b000) ? rne_up_d :
                            (rm_r == 3'b001) ? rtz_up_d :
                            (rm_r == 3'b010) ? rdn_up_d :
                            (rm_r == 3'b011) ? rup_up_d :
                                               rmm_up_d;  // rm == 3'b100

    // Apply rounding with overflow detection
    wire [52:0] mantissa_pre_d = {hidden_d, frac_d};

    // 54-bit result to capture carry
    wire [53:0] mantissa_result_d = {1'b0, mantissa_pre_d} + {{52{1'b0}}, round_up_d};

    // Overflow: carry into bit 53 (e.g., 1.111..1 + 1 = 10.000..0)
    wire        round_overflow_d = mantissa_result_d[53];

    // If overflow, result is 10.000..0 (hidden=1, frac=0)
    wire [52:0] rounded_mant_d = round_overflow_d ? 53'h10000000000000 :
                                                    mantissa_result_d[52:0];

    // Exponent after rounding overflow (12-bit to catch wrap-around)
    wire [11:0] exp_after_round_12 = {1'b0, nm_exp} + {11'b0, round_overflow_d};
    wire [10:0] exp_after_round    = exp_after_round_12[10:0];

    // Detect exponent overflow (result too large => Inf)
    wire        exp_overflow = (exp_after_round_12 >= 12'd2047) & ~nm_is_zero;

    // Detect inexact (any rounding bits were non-zero)
    wire        inexact = (nm_mant[2] | nm_mant[1] | nm_mant[0]) | round_up_d;

    // Pack result
    wire [63:0] packed_normal = {nm_sign, exp_after_round, rounded_mant_d[51:0]};
    wire [63:0] packed_inf    = {nm_sign, EXP_INF, 52'b0};

    // Overflow result depends on rounding mode
    wire        ovf_to_inf = (rm_r == 3'b000) |  // RNE
                             (rm_r == 3'b100) |  // RMM
                             ((rm_r == 3'b011) & ~nm_sign) |  // RUP & positive
                             ((rm_r == 3'b010) & nm_sign);    // RDN & negative
    wire [63:0] packed_max  = {nm_sign, 11'h7FE, 52'hFFFFFFFFFFFFF};
    wire [63:0] overflow_res = ovf_to_inf ? packed_inf : packed_max;

    // Zero result
    wire [63:0] packed_zero = {nm_sign, 63'b0};

    // Final result and flags
    wire [63:0] round_res_comb = nm_is_zero  ? packed_zero :
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
            state      <= S_IDLE;
            done_r     <= 1'b0;
            result_r   <= 64'b0;
            fflags_r   <= 5'b0;
            src1_r     <= 64'b0;
            src2_r     <= 64'b0;
            is_sub_r   <= 1'b0;
            rm_r       <= 3'b0;
            al_exp     <= 11'b0;
            al_mant_a  <= 56'b0;
            al_mant_b  <= 56'b0;
            al_eff_sub <= 1'b0;
            al_sign    <= 1'b0;
            al_special <= 1'b0;
            al_spec_res<= 64'b0;
            al_spec_flags<= 5'b0;
            ad_exp     <= 11'b0;
            ad_sum     <= 57'b0;
            ad_sign    <= 1'b0;
            ad_eff_sub <= 1'b0;
            ad_carry   <= 1'b0;
            ad_special <= 1'b0;
            ad_spec_res<= 64'b0;
            ad_spec_flags<= 5'b0;
            nm_exp     <= 11'b0;
            nm_mant    <= 56'b0;
            nm_sign    <= 1'b0;
            nm_is_zero <= 1'b0;
            nm_uf      <= 1'b0;
            nm_nx_denorm<= 1'b0;
            nm_special <= 1'b0;
            nm_spec_res<= 64'b0;
            nm_spec_flags<= 5'b0;
        end else if (flush) begin
            state      <= S_IDLE;
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
                            al_spec_res  <= CANON_QNAN;
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
                        al_spec_res  <= 64'b0;
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
                        ad_exp    <= 11'b0;
                        ad_sum    <= 57'b0;
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
                        ad_spec_res   <= 64'b0;
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
                        nm_exp    <= 11'b0;
                        nm_mant   <= 56'b0;
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
                        nm_spec_res   <= 64'b0;
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
