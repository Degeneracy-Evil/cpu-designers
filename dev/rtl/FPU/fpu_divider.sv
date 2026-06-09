`timescale 1ns / 1ps

module fpu_divider(
    input         clk,
    input         resetn,
    input  [31:0] src1,        // dividend
    input  [31:0] src2,        // divisor
    input  [2:0]  rm,
    input         start,
    input         flush,
    output [31:0] result,
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

    // IEEE 754 constants
    localparam [31:0] QNAN     = 32'h7FC00000;
    localparam [31:0] POS_INF  = 32'h7F800000;
    localparam [31:0] NEG_INF  = 32'hFF800000;
    localparam [31:0] POS_ZERO = 32'h00000000;
    localparam [31:0] NEG_ZERO = 32'h80000000;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [2:0]  state;
    reg [31:0] src1_r, src2_r;
    reg [2:0]  rm_r;
    reg        sign_res;
    reg [9:0]  exp_res;           // 10-bit signed exponent (intermediate)
    reg [25:0] quot;              // 26-bit quotient (1 int + 23 frac + G + R)
    reg [25:0] rem_r;             // 26-bit remainder
    reg [23:0] div_mant;          // 24-bit divisor mantissa {1, frac}
    reg        sticky;
    reg [4:0]  flags_r;           // {NV, DZ, OF, UF, NX}
    reg [31:0] result_r;
    reg [5:0]  iter_cnt;

    // ----------------------------------------------------------------
    // Extract fields from latched inputs
    // ----------------------------------------------------------------
    wire        s1 = src1_r[31];
    wire [7:0]  e1 = src1_r[30:23];
    wire [22:0] f1 = src1_r[22:0];
    wire        s2 = src2_r[31];
    wire [7:0]  e2 = src2_r[30:23];
    wire [22:0] f2 = src2_r[22:0];

    // Special-case detection
    wire is_nan1  = (e1 == 8'hFF) && (f1 != 23'b0);
    wire is_nan2  = (e2 == 8'hFF) && (f2 != 23'b0);
    wire is_snan1 = is_nan1 && !f1[22];
    wire is_snan2 = is_nan2 && !f2[22];
    wire is_inf1  = (e1 == 8'hFF) && (f1 == 23'b0);
    wire is_inf2  = (e2 == 8'hFF) && (f2 == 23'b0);
    wire is_zero1 = (e1 == 8'b0)  && (f1 == 23'b0);
    wire is_zero2 = (e2 == 8'b0)  && (f2 == 23'b0);

    // ----------------------------------------------------------------
    // Leading-zero count (priority encoder, 23-bit input)
    // ----------------------------------------------------------------
    function [4:0] clz23;
        input [22:0] val;
        begin
            if      (val[22]) clz23 = 5'd0;
            else if (val[21]) clz23 = 5'd1;
            else if (val[20]) clz23 = 5'd2;
            else if (val[19]) clz23 = 5'd3;
            else if (val[18]) clz23 = 5'd4;
            else if (val[17]) clz23 = 5'd5;
            else if (val[16]) clz23 = 5'd6;
            else if (val[15]) clz23 = 5'd7;
            else if (val[14]) clz23 = 5'd8;
            else if (val[13]) clz23 = 5'd9;
            else if (val[12]) clz23 = 5'd10;
            else if (val[11]) clz23 = 5'd11;
            else if (val[10]) clz23 = 5'd12;
            else if (val[9])  clz23 = 5'd13;
            else if (val[8])  clz23 = 5'd14;
            else if (val[7])  clz23 = 5'd15;
            else if (val[6])  clz23 = 5'd16;
            else if (val[5])  clz23 = 5'd17;
            else if (val[4])  clz23 = 5'd18;
            else if (val[3])  clz23 = 5'd19;
            else if (val[2])  clz23 = 5'd20;
            else if (val[1])  clz23 = 5'd21;
            else if (val[0])  clz23 = 5'd22;
            else              clz23 = 5'd23;
        end
    endfunction

    // ----------------------------------------------------------------
    // Normalization of subnormal inputs (combinational)
    // ----------------------------------------------------------------
    wire [4:0]  lz1_c = clz23(f1);
    wire [4:0]  lz2_c = clz23(f2);
    wire        sub1_c = (e1 == 8'b0) && (f1 != 23'b0);
    wire        sub2_c = (e2 == 8'b0) && (f2 != 23'b0);

    wire [22:0] f1_shft = f1 << lz1_c;
    wire [22:0] f2_shft = f2 << lz2_c;

    wire [23:0] mant1_c = sub1_c ? {1'b1, f1_shft[21:0]} : {1'b1, f1};
    wire [9:0]  eff_e1_c = sub1_c ? (10'sd1 - {{5'd0}, lz1_c}) : {2'b0, e1};

    wire [23:0] mant2_c = sub2_c ? {1'b1, f2_shft[21:0]} : {1'b1, f2};
    wire [9:0]  eff_e2_c = sub2_c ? (10'sd1 - {{5'd0}, lz2_c}) : {2'b0, e2};

    wire [9:0]  div_exp_c = eff_e1_c - eff_e2_c + 10'sd127;

    // ----------------------------------------------------------------
    // Division iteration combinational logic
    // ----------------------------------------------------------------
    // Shifted remainder (for iterations > 0)
    wire [25:0] rem_shifted  = rem_r << 1;
    wire [25:0] rem_sub      = rem_shifted - {2'b0, div_mant};
    wire        rem_ge_div   = (rem_shifted >= {2'b0, div_mant});

    // First iteration (no shift)
    wire [25:0] rem_first_sub = rem_r - {2'b0, div_mant};
    wire        rem_first_ge  = (rem_r >= {2'b0, div_mant});

    // ----------------------------------------------------------------
    // Rounding combinational logic (evaluated in ROUND_S state)
    // ----------------------------------------------------------------
    // Build 27-bit mantissa with GRS from quot and sticky
    wire [26:0] mantissa_27 = {quot[25:0], sticky};

    // Subnormal shift
    localparam signed [9:0] EXP_NEG27 = -27;
    wire [9:0] sub_shift_raw = 10'sd1 - exp_res;
    wire       is_subnormal  = (exp_res <= 10'sd0) && ($signed(exp_res) > EXP_NEG27);
    wire       is_underflow  = (exp_res <= 10'sd0);
    wire       is_tiny_zero  = ($signed(exp_res) <= EXP_NEG27);  // shift >= 27 => result is zero

    wire [4:0] sub_shift_amt = sub_shift_raw[4:0];  // clamped to 0..31

    // Extended mantissa for subnormal right-shift (53 bits)
    wire [52:0] ext_mant  = {mantissa_27[26:1], 27'b0};
    wire [52:0] shifted_m = ext_mant >> sub_shift_amt;
    wire [25:0] sub_mant26   = shifted_m[52:27];
    wire        sub_sticky_x = |shifted_m[26:0];
    wire        sub_sticky   = sub_sticky_x | mantissa_27[0];
    wire [26:0] sub_mant27   = {sub_mant26, sub_sticky};

    // Select mantissa after subnormal handling
    wire [26:0] pre_rnd_mant = is_subnormal ? sub_mant27 : mantissa_27;
    wire [9:0]  pre_rnd_exp  = is_subnormal ? 10'sd0     : exp_res;

    // Rounding decision
    wire guard_bit = pre_rnd_mant[2];
    wire round_bit = pre_rnd_mant[1];
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
    wire [24:0] mant_rounded   = {1'b0, pre_rnd_mant[26:3]} + round_up;
    wire        round_overflow = mant_rounded[24];
    wire [23:0] final_mant     = round_overflow ? mant_rounded[24:1] : mant_rounded[23:0];
    wire [9:0]  final_exp_raw  = pre_rnd_exp + (round_overflow ? 10'sd1 : 10'sd0);

    // Overflow / final packing
    wire result_overflow = (final_exp_raw >= 10'sd255);
    wire [7:0]  final_exp  = result_overflow ? 8'hFE : final_exp_raw[7:0];
    wire [31:0] packed_result = {sign_res, final_exp, final_mant[22:0]};

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
            src1_r    <= 32'b0;
            src2_r    <= 32'b0;
            rm_r      <= 3'b0;
            sign_res  <= 1'b0;
            exp_res   <= 10'b0;
            quot      <= 26'b0;
            rem_r     <= 26'b0;
            div_mant  <= 24'b0;
            sticky    <= 1'b0;
            flags_r   <= 5'b0;
            result_r  <= 32'b0;
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
                        result_r <= 32'b0;
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
                        rem_r    <= {2'b0, mant1_c};
                        div_mant <= mant2_c;
                        quot     <= 26'b0;
                        iter_cnt <= 6'd0;
                        state    <= ITERATE;
                    end
                end

                // ----------------------------------------------------
                ITERATE: begin
                    if (iter_cnt < 6'd26) begin
                        if (iter_cnt == 6'd0) begin
                            // First iteration: no shift, determine integer bit
                            if (rem_first_ge) begin
                                rem_r <= rem_first_sub;
                                quot  <= {quot[24:0], 1'b1};
                            end else begin
                                quot  <= {quot[24:0], 1'b0};
                            end
                        end else begin
                            // Subsequent iterations: shift then compare
                            if (rem_ge_div) begin
                                rem_r <= rem_sub;
                                quot  <= {quot[24:0], 1'b1};
                            end else begin
                                rem_r <= rem_shifted;
                                quot  <= {quot[24:0], 1'b0};
                            end
                        end
                        iter_cnt <= iter_cnt + 6'd1;
                    end else begin
                        // All 26 iterations done — capture sticky
                        sticky <= (rem_r != 26'b0);
                        state  <= NORM;
                    end
                end

                // ----------------------------------------------------
                NORM: begin
                    if (!quot[25]) begin
                        // Quotient in [0.5, 1.0): shift left by 1, decrement exp
                        quot    <= {quot[24:0], 1'b0};
                        exp_res <= exp_res - 10'sd1;
                    end
                    state <= ROUND_S;
                end

                // ----------------------------------------------------
                ROUND_S: begin
                    if (is_tiny_zero) begin
                        // Result is zero (all bits shifted out)
                        result_r       <= sign_res ? NEG_ZERO : POS_ZERO;
                        flags_r[1]     <= is_underflow & (mantissa_27 != 27'b0);  // UF
                        flags_r[0]     <= (mantissa_27 != 27'b0);                  // NX
                    end else if (result_overflow) begin
                        // Overflow => Inf
                        result_r       <= sign_res ? NEG_INF : POS_INF;
                        flags_r[2]     <= 1'b1;  // OF
                        flags_r[0]     <= 1'b1;  // NX
                    end else begin
                        result_r <= packed_result;
                        flags_r[1] <= flag_uf;    // UF
                        flags_r[0] <= flag_nx;    // NX
                    end
                    state <= DONE_STATE;
                end

                // ----------------------------------------------------
                DONE_STATE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;  // BUG-FIX: 防止状态机卡死在非法状态
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
