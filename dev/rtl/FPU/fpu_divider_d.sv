`timescale 1ns / 1ps

// ----------------------------------------------------------------
// IEEE 754 double-precision floating-point divider (FDIV.D)
//
// Widened from fpu_divider.sv (single-precision):
//   - Exponent:  8  -> 11 bits, bias 127 -> 1023
//   - Mantissa:  23 -> 52 bits (53-bit with implicit 1)
//   - Iterations: 26 -> 55 (1 integer + 52 fraction + G + R)
//   - Result:    32 -> 64 bits
//
// Iterative restoring division: each cycle produces one quotient bit.
// Special cases (NaN, Inf, zero, divide-by-zero) handled in SPECIAL_CHECK.
// ----------------------------------------------------------------
module fpu_divider_d(
    input         clk,
    input         resetn,
    input  [63:0] src1,        // dividend
    input  [63:0] src2,        // divisor
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
    localparam [2:0] ITERATE       = 3'd2;
    localparam [2:0] NORM          = 3'd3;
    localparam [2:0] ROUND_S       = 3'd4;
    localparam [2:0] DONE_STATE    = 3'd5;

    // IEEE 754 double-precision constants
    localparam [63:0] QNAN     = 64'h7FF8000000000000;
    localparam [63:0] POS_INF  = 64'h7FF0000000000000;
    localparam [63:0] NEG_INF  = 64'hFFF0000000000000;
    localparam [63:0] POS_ZERO = 64'h0000000000000000;
    localparam [63:0] NEG_ZERO = 64'h8000000000000000;

    // Datapath widths
    localparam integer MANT_W = 53;   // 1 implicit + 52 fraction
    localparam integer QUOT_W = 55;   // 1 integer + 52 fraction + G + R
    localparam integer ITER_N = 55;   // iterations to fill QUOT_W bits
    localparam integer EXP_W  = 13;   // signed intermediate exponent

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [2:0]   state;
    reg [63:0]  src1_r, src2_r;
    reg [2:0]   rm_r;
    reg         sign_res;
    reg [EXP_W-1:0] exp_res;          // signed exponent (intermediate)
    reg [QUOT_W-1:0] quot;            // quotient (1 int + 52 frac + G + R)
    reg [QUOT_W-1:0] rem_r;           // remainder
    reg [MANT_W-1:0] div_mant;        // divisor mantissa {1, frac}
    reg         sticky;
    reg [4:0]   flags_r;              // {NV, DZ, OF, UF, NX}
    reg [63:0]  result_r;
    reg [5:0]   iter_cnt;

    // ----------------------------------------------------------------
    // Extract fields from latched inputs
    // ----------------------------------------------------------------
    wire        s1 = src1_r[63];
    wire [10:0] e1 = src1_r[62:52];
    wire [51:0] f1 = src1_r[51:0];
    wire        s2 = src2_r[63];
    wire [10:0] e2 = src2_r[62:52];
    wire [51:0] f2 = src2_r[51:0];

    // Special-case detection
    wire is_nan1  = (e1 == 11'h7FF) && (f1 != 52'b0);
    wire is_nan2  = (e2 == 11'h7FF) && (f2 != 52'b0);
    wire is_snan1 = is_nan1 && !f1[51];
    wire is_snan2 = is_nan2 && !f2[51];
    wire is_inf1  = (e1 == 11'h7FF) && (f1 == 52'b0);
    wire is_inf2  = (e2 == 11'h7FF) && (f2 == 52'b0);
    wire is_zero1 = (e1 == 11'b0)   && (f1 == 52'b0);
    wire is_zero2 = (e2 == 11'b0)   && (f2 == 52'b0);

    // ----------------------------------------------------------------
    // Leading-zero count (priority encoder, 52-bit input)
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
    // Normalization of subnormal inputs (combinational)
    // ----------------------------------------------------------------
    wire [5:0]  lz1_c = clz52(f1);
    wire [5:0]  lz2_c = clz52(f2);
    wire        sub1_c = (e1 == 11'b0) && (f1 != 52'b0);
    wire        sub2_c = (e2 == 11'b0) && (f2 != 52'b0);

    wire [51:0] f1_shft = f1 << lz1_c;
    wire [51:0] f2_shft = f2 << lz2_c;

    wire [MANT_W-1:0] mant1_c = sub1_c ? {1'b1, f1_shft[50:0]} : {1'b1, f1};
    wire [EXP_W-1:0]  eff_e1_c = sub1_c ? (13'sd1 - {{7'd0}, lz1_c}) : {2'b0, e1};

    wire [MANT_W-1:0] mant2_c = sub2_c ? {1'b1, f2_shft[50:0]} : {1'b1, f2};
    wire [EXP_W-1:0]  eff_e2_c = sub2_c ? (13'sd1 - {{7'd0}, lz2_c}) : {2'b0, e2};

    wire [EXP_W-1:0] div_exp_c = eff_e1_c - eff_e2_c + 13'sd1023;

    // ----------------------------------------------------------------
    // Division iteration combinational logic
    // ----------------------------------------------------------------
    // Shifted remainder (for iterations > 0)
    wire [QUOT_W-1:0] rem_shifted  = rem_r << 1;
    wire [QUOT_W-1:0] rem_sub      = rem_shifted - {{(QUOT_W-MANT_W){1'b0}}, div_mant};
    wire              rem_ge_div   = (rem_shifted >= {{(QUOT_W-MANT_W){1'b0}}, div_mant});

    // First iteration (no shift)
    wire [QUOT_W-1:0] rem_first_sub = rem_r - {{(QUOT_W-MANT_W){1'b0}}, div_mant};
    wire              rem_first_ge  = (rem_r >= {{(QUOT_W-MANT_W){1'b0}}, div_mant});

    // ----------------------------------------------------------------
    // Rounding combinational logic (evaluated in ROUND_S state)
    // ----------------------------------------------------------------
    // Build 56-bit mantissa with GRS from quot and sticky
    //   [55]    = integer bit (implicit 1)
    //   [54:3]  = 52-bit fraction
    //   [2]     = guard
    //   [1]     = round
    //   [0]     = sticky
    wire [55:0] mantissa_56 = {quot, sticky};

    // Subnormal shift
    localparam signed [EXP_W-1:0] EXP_NEG56 = -56;
    wire [EXP_W-1:0] sub_shift_raw = 13'sd1 - exp_res;
    wire             is_subnormal  = ($signed(exp_res) <= 13'sd0) && ($signed(exp_res) > EXP_NEG56);
    wire             is_underflow  = ($signed(exp_res) <= 13'sd0);
    wire             is_tiny_zero  = ($signed(exp_res) <= EXP_NEG56);  // shift >= 56 => result is zero

    wire [5:0] sub_shift_amt = sub_shift_raw[5:0];  // 0..56

    // Extended mantissa for subnormal right-shift (111 bits)
    wire [110:0] ext_mant     = {mantissa_56[55:1], 56'b0};
    wire [110:0] shifted_m    = ext_mant >> sub_shift_amt;
    wire [54:0]  sub_mant55   = shifted_m[110:56];
    wire         sub_sticky_x = |shifted_m[55:0];
    wire         sub_sticky   = sub_sticky_x | mantissa_56[0];
    wire [55:0]  sub_mant56   = {sub_mant55, sub_sticky};

    // Select mantissa after subnormal handling
    wire [55:0] pre_rnd_mant = is_subnormal ? sub_mant56 : mantissa_56;
    wire [EXP_W-1:0] pre_rnd_exp = is_subnormal ? 13'sd0 : exp_res;

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

    // Apply rounding
    wire [53:0] mant_rounded   = {1'b0, pre_rnd_mant[55:3]} + round_up;
    wire        round_overflow = mant_rounded[53];
    wire [52:0] final_mant     = round_overflow ? mant_rounded[53:1] : mant_rounded[52:0];
    wire [EXP_W-1:0] final_exp_raw = pre_rnd_exp + (round_overflow ? 13'sd1 : 13'sd0);

    // Overflow / final packing
    wire        result_overflow = ($signed(final_exp_raw) >= 13'sd2047);
    wire [10:0] final_exp  = result_overflow ? 11'h7FE : final_exp_raw[10:0];
    wire [63:0] packed_result = {sign_res, final_exp, final_mant[51:0]};

    // Overflow result depends on rounding mode (IEEE 754)
    wire ovf_to_inf = (rm_r == 3'b000) |  // RNE -> +/-Infinity
                      (rm_r == 3'b100) |  // RMM -> +/-Infinity
                      ((rm_r == 3'b011) & ~sign_res) |  // RUP & positive -> +Infinity
                      ((rm_r == 3'b010) & sign_res);    // RDN & negative -> -Infinity
    wire [63:0] packed_max    = {sign_res, 11'h7FE, 52'hFFFFFFFFFFFFF};  // +/-Max finite double
    wire [63:0] overflow_res  = ovf_to_inf ? (sign_res ? NEG_INF : POS_INF) : packed_max;

    // Flags for normal path
    wire flag_of = result_overflow;
    wire flag_uf = is_underflow & grs;
    wire flag_nx = grs | round_up;  // inexact if GRS non-zero or rounding changed value

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= IDLE;
            src1_r    <= 64'b0;
            src2_r    <= 64'b0;
            rm_r      <= 3'b0;
            sign_res  <= 1'b0;
            exp_res   <= {EXP_W{1'b0}};
            quot      <= {QUOT_W{1'b0}};
            rem_r     <= {QUOT_W{1'b0}};
            div_mant  <= {MANT_W{1'b0}};
            sticky    <= 1'b0;
            flags_r   <= 5'b0;
            result_r  <= 64'b0;
            iter_cnt  <= 6'b0;
        end else if (flush) begin
            state     <= IDLE;
        end else begin
            case (state)
                // ----------------------------------------------------
                IDLE: begin
                    if (start) begin
                        src1_r   <= src1;
                        src2_r   <= src2;
                        rm_r     <= rm;
                        flags_r  <= 5'b0;
                        result_r <= 64'b0;
                        state    <= SPECIAL_CHECK;
                    end
                end

                // ----------------------------------------------------
                SPECIAL_CHECK: begin
                    if (is_nan1 || is_nan2) begin
                        // NaN / anything = qNaN; NV if sNaN
                        result_r       <= QNAN;
                        flags_r[4]     <= is_snan1 | is_snan2;
                        state          <= DONE_STATE;
                    end
                    else if (is_zero2) begin
                        if (is_zero1 || is_inf1) begin
                            // 0/0 or Inf/0 => qNaN, NV
                            result_r   <= QNAN;
                            flags_r[4] <= 1'b1;
                        end else begin
                            // x/0 => Inf, DZ
                            result_r   <= (s1 ^ s2) ? NEG_INF : POS_INF;
                            flags_r[3] <= 1'b1;
                        end
                        state <= DONE_STATE;
                    end
                    else if (is_inf1) begin
                        if (is_inf2) begin
                            // Inf/Inf => qNaN, NV
                            result_r   <= QNAN;
                            flags_r[4] <= 1'b1;
                        end else begin
                            // Inf/x => Inf (sign XOR)
                            result_r <= (s1 ^ s2) ? NEG_INF : POS_INF;
                        end
                        state <= DONE_STATE;
                    end
                    else if (is_inf2) begin
                        // x/Inf => 0 (sign XOR)
                        result_r <= (s1 ^ s2) ? NEG_ZERO : POS_ZERO;
                        state    <= DONE_STATE;
                    end
                    else if (is_zero1) begin
                        // 0/x => 0 (sign XOR), x != 0
                        result_r <= (s1 ^ s2) ? NEG_ZERO : POS_ZERO;
                        state    <= DONE_STATE;
                    end
                    else begin
                        // Normal / subnormal — set up iteration
                        sign_res <= s1 ^ s2;
                        exp_res  <= div_exp_c;
                        rem_r    <= {{(QUOT_W-MANT_W){1'b0}}, mant1_c};
                        div_mant <= mant2_c;
                        quot     <= {QUOT_W{1'b0}};
                        iter_cnt <= 6'd0;
                        state    <= ITERATE;
                    end
                end

                // ----------------------------------------------------
                ITERATE: begin
                    if (iter_cnt < ITER_N) begin
                        if (iter_cnt == 6'd0) begin
                            // First iteration: no shift, determine integer bit
                            if (rem_first_ge) begin
                                rem_r <= rem_first_sub;
                                quot  <= {quot[QUOT_W-2:0], 1'b1};
                            end else begin
                                quot  <= {quot[QUOT_W-2:0], 1'b0};
                            end
                        end else begin
                            // Subsequent iterations: shift then compare
                            if (rem_ge_div) begin
                                rem_r <= rem_sub;
                                quot  <= {quot[QUOT_W-2:0], 1'b1};
                            end else begin
                                rem_r <= rem_shifted;
                                quot  <= {quot[QUOT_W-2:0], 1'b0};
                            end
                        end
                        iter_cnt <= iter_cnt + 6'd1;
                    end else begin
                        // All iterations done — capture sticky
                        sticky <= (rem_r != {QUOT_W{1'b0}});
                        state  <= NORM;
                    end
                end

                // ----------------------------------------------------
                NORM: begin
                    if (!quot[QUOT_W-1]) begin
                        // Quotient in [0.5, 1.0): shift left by 1, decrement exp
                        quot    <= {quot[QUOT_W-2:0], 1'b0};
                        exp_res <= exp_res - 13'sd1;
                    end
                    state <= ROUND_S;
                end

                // ----------------------------------------------------
                ROUND_S: begin
                    if (is_tiny_zero) begin
                        // Result is zero (all bits shifted out)
                        result_r       <= sign_res ? NEG_ZERO : POS_ZERO;
                        flags_r[1]     <= is_underflow & (mantissa_56 != 56'b0);  // UF
                        flags_r[0]     <= (mantissa_56 != 56'b0);                  // NX
                    end else if (result_overflow) begin
                        // Overflow result depends on rounding mode
                        result_r       <= overflow_res;
                        flags_r[2]     <= 1'b1;  // OF
                        flags_r[0]     <= 1'b1;  // NX
                    end else begin
                        result_r   <= packed_result;
                        flags_r[1] <= flag_uf;    // UF
                        flags_r[0] <= flag_nx;    // NX
                    end
                    state <= DONE_STATE;
                end

                // ----------------------------------------------------
                DONE_STATE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;  // prevent FSM stuck in illegal state
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Outputs
    // ----------------------------------------------------------------
    assign result = result_r;
    assign fflags = flags_r;
    assign done   = (state == DONE_STATE);

endmodule
