`timescale 1ns / 1ps

// ----------------------------------------------------------------
// IEEE 754 double-precision floating-point square root (FSQRT.D)
//
// Widened from fpu_sqrt.sv (single-precision):
//   - Exponent:  8  -> 11 bits, bias 127 -> 1023
//   - Mantissa:  23 -> 52 bits (53-bit with implicit 1)
//   - Iterations: 27 -> 56 (1 integer + 52 fraction + G + R + S)
//   - Result:    32 -> 64 bits
//
// Digit-by-digit restoring square root: each cycle produces one
// root bit.  Special cases (NaN, Inf, zero, negative) handled in
// SPECIAL_CHECK.  Subnormal inputs normalized to [1.0, 2.0) using
// the Task 7 fix pattern (trailing-zero concat).
// ----------------------------------------------------------------
module fpu_sqrt_d(
    input         clk,
    input         resetn,
    input  [63:0] src1,
    input  [2:0]  rm,
    input         start,
    input         flush,
    output [63:0] result,
    output [4:0]  fflags,      // {NV, DZ, OF, UF, NX}
    output        done
);

    // ----------------------------------------------------------------
    // FSM states
    // ----------------------------------------------------------------
    localparam [2:0] IDLE          = 3'd0;
    localparam [2:0] SPECIAL_CHECK = 3'd1;
    localparam [2:0] INIT          = 3'd2;
    localparam [2:0] ITERATE       = 3'd3;
    localparam [2:0] NORM          = 3'd4;
    localparam [2:0] ROUND_S       = 3'd5;
    localparam [2:0] DONE_STATE    = 3'd6;

    // IEEE 754 double-precision constants
    localparam [63:0] QNAN     = 64'h7FF8000000000000;
    localparam [63:0] POS_INF  = 64'h7FF0000000000000;
    localparam [63:0] POS_ZERO = 64'h0000000000000000;
    localparam [63:0] NEG_ZERO = 64'h8000000000000000;

    // Datapath widths
    localparam integer MANT_W   = 53;   // 1 implicit + 52 fraction
    localparam integer ROOT_W   = 57;   // 56 result bits + 1 safety
    localparam integer REM_W    = 61;   // remainder width
    localparam integer SHIFT_W  = 114;  // shift register (112 data + 2 pad)
    localparam integer ITER_N   = 56;   // iterations to fill 56 root bits
    localparam integer EXP_W    = 12;   // signed intermediate exponent

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [2:0]       state;
    reg [63:0]      src1_r;
    reg [2:0]       rm_r;
    reg             sign_res;
    reg [EXP_W-1:0] exp_res;            // signed exponent (intermediate)
    reg [ROOT_W-1:0] root;              // partial root (56 result + 1 safety)
    reg [REM_W-1:0]  sqrt_rem;          // remainder
    reg [SHIFT_W-1:0] s_shift;          // shift register for input bits
    reg [5:0]        iter_cnt;
    reg              sticky;
    reg [4:0]        flags_r;
    reg [63:0]       result_r;

    // ----------------------------------------------------------------
    // Extract fields from latched input
    // ----------------------------------------------------------------
    wire        s1 = src1_r[63];
    wire [10:0] e1 = src1_r[62:52];
    wire [51:0] f1 = src1_r[51:0];

    wire is_nan  = (e1 == 11'h7FF) && (f1 != 52'b0);
    wire is_snan = is_nan && !f1[51];
    wire is_inf  = (e1 == 11'h7FF) && (f1 == 52'b0);
    wire is_zero = (e1 == 11'b0)   && (f1 == 52'b0);
    wire is_sub  = (e1 == 11'b0)   && (f1 != 52'b0);
    wire is_neg  = s1 && !is_zero && !is_nan;  // negative normal/subnormal

    // ----------------------------------------------------------------
    // Leading-zero count (52-bit)
    // ----------------------------------------------------------------
    function [5:0] clz52;
        input [51:0] val;
        begin
            if      (val[51]) clz52 = 6'd0;
            else if (val[50]) clz52 = 6'd1;
            else if (val[49]) clz52 = 6'd2;
            else if (val[48]) clz52 = 6'd3;
            else if (val[47]) clz52 = 6'd4;
            else if (val[46]) clz52 = 6'd5;
            else if (val[45]) clz52 = 6'd6;
            else if (val[44]) clz52 = 6'd7;
            else if (val[43]) clz52 = 6'd8;
            else if (val[42]) clz52 = 6'd9;
            else if (val[41]) clz52 = 6'd10;
            else if (val[40]) clz52 = 6'd11;
            else if (val[39]) clz52 = 6'd12;
            else if (val[38]) clz52 = 6'd13;
            else if (val[37]) clz52 = 6'd14;
            else if (val[36]) clz52 = 6'd15;
            else if (val[35]) clz52 = 6'd16;
            else if (val[34]) clz52 = 6'd17;
            else if (val[33]) clz52 = 6'd18;
            else if (val[32]) clz52 = 6'd19;
            else if (val[31]) clz52 = 6'd20;
            else if (val[30]) clz52 = 6'd21;
            else if (val[29]) clz52 = 6'd22;
            else if (val[28]) clz52 = 6'd23;
            else if (val[27]) clz52 = 6'd24;
            else if (val[26]) clz52 = 6'd25;
            else if (val[25]) clz52 = 6'd26;
            else if (val[24]) clz52 = 6'd27;
            else if (val[23]) clz52 = 6'd28;
            else if (val[22]) clz52 = 6'd29;
            else if (val[21]) clz52 = 6'd30;
            else if (val[20]) clz52 = 6'd31;
            else if (val[19]) clz52 = 6'd32;
            else if (val[18]) clz52 = 6'd33;
            else if (val[17]) clz52 = 6'd34;
            else if (val[16]) clz52 = 6'd35;
            else if (val[15]) clz52 = 6'd36;
            else if (val[14]) clz52 = 6'd37;
            else if (val[13]) clz52 = 6'd38;
            else if (val[12]) clz52 = 6'd39;
            else if (val[11]) clz52 = 6'd40;
            else if (val[10]) clz52 = 6'd41;
            else if (val[9])  clz52 = 6'd42;
            else if (val[8])  clz52 = 6'd43;
            else if (val[7])  clz52 = 6'd44;
            else if (val[6])  clz52 = 6'd45;
            else if (val[5])  clz52 = 6'd46;
            else if (val[4])  clz52 = 6'd47;
            else if (val[3])  clz52 = 6'd48;
            else if (val[2])  clz52 = 6'd49;
            else if (val[1])  clz52 = 6'd50;
            else if (val[0])  clz52 = 6'd51;
            else              clz52 = 6'd52;
        end
    endfunction

    // ----------------------------------------------------------------
    // Normalization of subnormal input (combinational)
    // ----------------------------------------------------------------
    // For subnormal: exponent=0, mantissa=f1 (no implicit 1).
    // Actual value = (f1 / 2^52) * 2^-1022 = f1 * 2^-1074.
    // Normalize: shift f1 left so leading 1 is at bit 51, then form
    // 1.fraction (53-bit) and adjust exponent to compensate.
    //
    // Task 7 fix (applied from single-precision):
    //   {1'b1, f1_shft[50:0], 1'b0} = 53 bits (1 + 51 + 1), placing
    //   the mantissa in [1.0, 2.0) — matching the normal mantissa
    //   range.  The trailing 0 pads the 52nd fraction bit.
    //   Exponent uses -lz_c (not 1-lz_c) to preserve the same value.
    wire [5:0]  lz_c    = clz52(f1);
    wire [51:0] f1_shft = f1 << lz_c;
    wire [MANT_W-1:0] mant_c = is_sub ? {1'b1, f1_shft[50:0], 1'b0}
                                      : {1'b1, f1};
    wire [EXP_W-1:0]  eff_e_c = is_sub ? (12'sd0 - {{6'd0}, lz_c}) : {1'b0, e1};

    // Exponent calculation for sqrt
    // If (eff_e - 1023) is even => result_exp = (eff_e + 1023) / 2, no mantissa shift
    // If (eff_e - 1023) is odd  => result_exp = (eff_e + 1022) / 2, shift mantissa left by 1
    wire [EXP_W-1:0] unbiased = eff_e_c - 12'sd1023;
    wire             exp_odd  = unbiased[0];  // odd unbiased exponent

    wire [EXP_W-1:0] sqrt_exp_even = (eff_e_c + 12'sd1023) >> 1;  // (eff_e + 1023) / 2
    wire [EXP_W-1:0] sqrt_exp_odd  = (eff_e_c + 12'sd1022) >> 1;  // (eff_e + 1022) / 2
    wire [EXP_W-1:0] sqrt_exp_c    = exp_odd ? sqrt_exp_odd : sqrt_exp_even;

    // Adjusted mantissa: if exp_odd, shift left by 1 (range [2.0, 4.0))
    wire [MANT_W:0] adj_mant_c = exp_odd ? {mant_c, 1'b0} : {1'b0, mant_c};  // 54 bits

    // Form 112-bit input for digit-by-digit sqrt: {adj_mant, 58'b0}
    wire [111:0] sqrt_input_c = {adj_mant_c, 58'b0};

    // ----------------------------------------------------------------
    // Digit-by-digit sqrt iteration logic (combinational)
    // ----------------------------------------------------------------
    // Bring in next 2 bits from s_shift
    wire [REM_W-1:0] rem_new = {sqrt_rem[REM_W-3:0], s_shift[SHIFT_W-1:SHIFT_W-2]};
    wire [ROOT_W+1:0] trial   = {root, 2'b01};   // (root << 2) | 1, 59 bits
    wire             rem_ge_trial = (rem_new >= {{2{1'b0}}, trial});

    wire [REM_W-1:0] rem_sub_trial = rem_new - {{2{1'b0}}, trial};

    // ----------------------------------------------------------------
    // Rounding combinational logic
    // ----------------------------------------------------------------
    // After 56 iterations, root[55:0] is the 56-bit result
    // mantissa_56 = {root[55:1], root[0] | sticky}
    //   [55]    = integer bit (implicit 1)
    //   [54:3]  = 52-bit fraction
    //   [2]     = guard
    //   [1]     = round
    //   [0]     = sticky
    wire [55:0] mantissa_56 = {root[55:1], root[0] | sticky};

    // Subnormal shift (rare for sqrt, but handle for completeness)
    localparam signed [EXP_W-1:0] EXP_NEG56 = -56;
    wire [EXP_W-1:0] sub_shift_raw = 12'sd1 - exp_res;
    wire             is_subnormal  = ($signed(exp_res) <= 12'sd0) && ($signed(exp_res) > EXP_NEG56);
    wire             is_underflow  = ($signed(exp_res) <= 12'sd0);
    wire             is_tiny_zero  = ($signed(exp_res) <= EXP_NEG56);

    wire [5:0]   sub_shift_amt = sub_shift_raw[5:0];
    wire [110:0] ext_mant      = {mantissa_56[55:1], 56'b0};
    wire [110:0] shifted_m     = ext_mant >> sub_shift_amt;
    wire [54:0]  sub_mant55    = shifted_m[110:56];
    wire         sub_sticky_x  = |shifted_m[55:0];
    wire         sub_sticky    = sub_sticky_x | mantissa_56[0];
    wire [55:0]  sub_mant56    = {sub_mant55, sub_sticky};

    wire [55:0]      pre_rnd_mant = is_subnormal ? sub_mant56 : mantissa_56;
    wire [EXP_W-1:0] pre_rnd_exp  = is_subnormal ? 12'sd0     : exp_res;

    // Rounding decision
    wire guard_bit  = pre_rnd_mant[2];
    wire round_bit  = pre_rnd_mant[1];
    wire sticky_bit = pre_rnd_mant[0];
    wire lsb_bit    = pre_rnd_mant[3];
    wire grs        = guard_bit | round_bit | sticky_bit;

    wire round_rne = guard_bit & (round_bit | sticky_bit | lsb_bit);
    wire round_rtz = 1'b0;
    wire round_rdn = sign_res & grs;
    wire round_rup = ~sign_res & grs;
    wire round_rmm = guard_bit;

    wire round_up = (rm_r == 3'b000) ? round_rne :
                    (rm_r == 3'b001) ? round_rtz :
                    (rm_r == 3'b010) ? round_rdn :
                    (rm_r == 3'b011) ? round_rup :
                                       round_rmm;

    wire [53:0] mant_rounded   = {1'b0, pre_rnd_mant[55:3]} + round_up;
    wire        round_overflow = mant_rounded[53];
    wire [52:0] final_mant     = round_overflow ? mant_rounded[53:1] : mant_rounded[52:0];
    wire [EXP_W-1:0] final_exp_raw = pre_rnd_exp + (round_overflow ? 12'sd1 : 12'sd0);

    wire        result_overflow = ($signed(final_exp_raw) >= 12'sd2047);
    wire [10:0] final_exp  = result_overflow ? 11'h7FE : final_exp_raw[10:0];
    wire [63:0] packed_result = {sign_res, final_exp, final_mant[51:0]};

    // Overflow result depends on rounding mode (IEEE 754)
    // sqrt result is always non-negative (sign_res=0), so:
    // RNE/RMM/RUP -> +Infinity; RTZ/RDN -> +Max finite
    wire ovf_to_inf = (rm_r == 3'b000) |  // RNE
                      (rm_r == 3'b100) |  // RMM
                      (rm_r == 3'b011);    // RUP (positive -> +Inf)
    wire [63:0] packed_max    = {1'b0, 11'h7FE, 52'hFFFFFFFFFFFFF};  // +Max finite double
    wire [63:0] overflow_res  = ovf_to_inf ? POS_INF : packed_max;

    wire flag_of = result_overflow;
    wire flag_uf = is_underflow & grs;
    wire flag_nx = grs | round_up;

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= IDLE;
            src1_r    <= 64'b0;
            rm_r      <= 3'b0;
            sign_res  <= 1'b0;
            exp_res   <= {EXP_W{1'b0}};
            root      <= {ROOT_W{1'b0}};
            sqrt_rem  <= {REM_W{1'b0}};
            s_shift   <= {SHIFT_W{1'b0}};
            iter_cnt  <= 6'b0;
            sticky    <= 1'b0;
            flags_r   <= 5'b0;
            result_r  <= 64'b0;
        end else if (flush) begin
            state     <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        src1_r   <= src1;
                        rm_r     <= rm;
                        flags_r  <= 5'b0;
                        result_r <= 64'b0;
                        state    <= SPECIAL_CHECK;
                    end
                end

                SPECIAL_CHECK: begin
                    if (is_nan) begin
                        result_r   <= QNAN;
                        flags_r[4] <= is_snan;  // NV if sNaN
                        state      <= DONE_STATE;
                    end
                    else if (is_neg) begin
                        // sqrt(-x) = qNaN, NV (x > 0)
                        result_r   <= QNAN;
                        flags_r[4] <= 1'b1;     // NV
                        state      <= DONE_STATE;
                    end
                    else if (is_inf) begin
                        // sqrt(+Inf) = +Inf
                        result_r <= POS_INF;
                        state    <= DONE_STATE;
                    end
                    else if (is_zero) begin
                        // sqrt(+-0) = +-0
                        result_r <= s1 ? NEG_ZERO : POS_ZERO;
                        state    <= DONE_STATE;
                    end
                    else begin
                        // Normal / subnormal positive — compute sqrt
                        sign_res <= 1'b0;  // sqrt of positive is always positive
                        exp_res  <= sqrt_exp_c;
                        state    <= INIT;
                    end
                end

                INIT: begin
                    // Load the 112-bit input into shift register and init algorithm
                    s_shift  <= {sqrt_input_c, 2'b0};  // 114 bits: 112 data + 2 padding
                    sqrt_rem <= {REM_W{1'b0}};
                    root     <= {ROOT_W{1'b0}};
                    iter_cnt <= 6'd0;
                    state    <= ITERATE;
                end

                ITERATE: begin
                    if (iter_cnt < ITER_N) begin
                        // Digit-by-digit sqrt step
                        s_shift <= s_shift << 2;
                        if (rem_ge_trial) begin
                            sqrt_rem <= rem_sub_trial;
                            root     <= {root[ROOT_W-2:0], 1'b1};
                        end else begin
                            sqrt_rem <= rem_new;
                            root     <= {root[ROOT_W-2:0], 1'b0};
                        end
                        iter_cnt <= iter_cnt + 6'd1;
                    end else begin
                        // Done — compute sticky from remainder
                        sticky <= (sqrt_rem != {REM_W{1'b0}});
                        state  <= NORM;
                    end
                end

                NORM: begin
                    // Result is always normalized for sqrt (bit 55 = 1)
                    // but check just in case of subnormal result
                    if (!root[55] && root[54]) begin
                        // Shift left by 1 to normalize
                        root    <= {root[54:0], 1'b0};
                        exp_res <= exp_res - 12'sd1;
                    end
                    state <= ROUND_S;
                end

                ROUND_S: begin
                    if (is_tiny_zero) begin
                        result_r   <= sign_res ? NEG_ZERO : POS_ZERO;
                        flags_r[1] <= is_underflow & (mantissa_56 != 56'b0);
                        flags_r[0] <= (mantissa_56 != 56'b0);
                    end else if (result_overflow) begin
                        // Overflow result depends on rounding mode
                        result_r   <= overflow_res;
                        flags_r[2] <= 1'b1;  // OF
                        flags_r[0] <= 1'b1;  // NX
                    end else begin
                        result_r <= packed_result;
                        flags_r[1] <= flag_uf;
                        flags_r[0] <= flag_nx;
                    end
                    state <= DONE_STATE;
                end

                DONE_STATE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;  // prevent FSM stuck in illegal state
            endcase
        end
    end

    assign result = result_r;
    assign fflags = flags_r;
    assign done   = (state == DONE_STATE);

endmodule
