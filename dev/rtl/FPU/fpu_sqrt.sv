`timescale 1ns / 1ps

module fpu_sqrt(
    input         clk,
    input         resetn,
    input  [31:0] src1,
    input  [2:0]  rm,
    input         start,
    input         flush,
    output [31:0] result,
    output [4:0]  fflags,
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

    // IEEE 754 constants
    localparam [31:0] QNAN     = 32'h7FC00000;
    localparam [31:0] POS_INF  = 32'h7F800000;
    localparam [31:0] POS_ZERO = 32'h00000000;
    localparam [31:0] NEG_ZERO = 32'h80000000;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [2:0]  state;
    reg [31:0] src1_r;
    reg [2:0]  rm_r;
    reg        sign_res;
    reg [9:0]  exp_res;           // 10-bit signed exponent
    reg [27:0] root;              // 28-bit partial root (27 result bits + 1 safety)
    reg [31:0] sqrt_rem;          // 32-bit remainder
    reg [55:0] s_shift;           // 56-bit shift register for input
    reg [4:0]  iter_cnt;
    reg        sticky;
    reg [4:0]  flags_r;
    reg [31:0] result_r;

    // ----------------------------------------------------------------
    // Extract fields
    // ----------------------------------------------------------------
    wire        s1 = src1_r[31];
    wire [7:0]  e1 = src1_r[30:23];
    wire [22:0] f1 = src1_r[22:0];

    wire is_nan  = (e1 == 8'hFF) && (f1 != 23'b0);
    wire is_snan = is_nan && !f1[22];
    wire is_inf  = (e1 == 8'hFF) && (f1 == 23'b0);
    wire is_zero = (e1 == 8'b0)  && (f1 == 23'b0);
    wire is_sub  = (e1 == 8'b0)  && (f1 != 23'b0);
    wire is_neg  = s1 && !is_zero && !is_nan;  // negative normal/subnormal

    // ----------------------------------------------------------------
    // Leading-zero count (23-bit)
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
    // Normalization of subnormal input (combinational)
    // ----------------------------------------------------------------
    wire [4:0]  lz_c    = clz23(f1);
    wire [22:0] f1_shft = f1 << lz_c;
    wire [23:0] mant_c  = is_sub ? {1'b1, f1_shft[21:0]} : {1'b1, f1};
    wire [9:0]  eff_e_c = is_sub ? (10'sd1 - {{5'd0}, lz_c}) : {2'b0, e1};

    // Exponent calculation for sqrt
    // If (eff_e - 127) is even => result_exp = (eff_e - 127)/2 + 127, no mantissa shift
    // If (eff_e - 127) is odd  => result_exp = (eff_e - 128)/2 + 127, shift mantissa left by 1
    wire [9:0]  unbiased = eff_e_c - 10'sd127;
    wire        exp_odd  = unbiased[0];  // odd unbiased exponent

    wire [9:0]  sqrt_exp_even = (eff_e_c + 10'sd127) >> 1;  // (eff_e + 127) / 2
    wire [9:0]  sqrt_exp_odd  = (eff_e_c + 10'sd126) >> 1;  // (eff_e + 126) / 2
    wire [9:0]  sqrt_exp_c    = exp_odd ? sqrt_exp_odd : sqrt_exp_even;

    // Adjusted mantissa: if exp_odd, shift left by 1 (range [2.0, 4.0))
    wire [24:0] adj_mant_c = exp_odd ? {mant_c, 1'b0} : {1'b0, mant_c};  // 25 bits

    // Form 54-bit input for digit-by-digit sqrt: {adj_mant, 29'b0}
    wire [53:0] sqrt_input_c = {adj_mant_c, 29'b0};

    // ----------------------------------------------------------------
    // Digit-by-digit sqrt iteration logic (combinational)
    // ----------------------------------------------------------------
    // Bring in next 2 bits from s_shift
    wire [31:0] rem_new = {sqrt_rem[29:0], s_shift[55:54]};
    wire [29:0] trial   = {root, 2'b01};   // (root << 2) | 1, 30 bits
    wire        rem_ge_trial = (rem_new >= {2'b0, trial});

    wire [31:0] rem_sub_trial = rem_new - {2'b0, trial};

    // ----------------------------------------------------------------
    // Rounding combinational logic
    // ----------------------------------------------------------------
    // After 27 iterations, root[26:0] is the 27-bit result
    // mantissa_27 = {root[26:1], root[0] | sticky}
    wire [26:0] mantissa_27 = {root[26:1], root[0] | sticky};

    // Subnormal shift (rare for sqrt, but handle for completeness)
    localparam signed [9:0] EXP_NEG27 = -27;
    wire [9:0] sub_shift_raw = 10'sd1 - exp_res;
    wire       is_subnormal  = (exp_res <= 10'sd0) && ($signed(exp_res) > EXP_NEG27);
    wire       is_underflow  = (exp_res <= 10'sd0);
    wire       is_tiny_zero  = ($signed(exp_res) <= EXP_NEG27);

    wire [4:0] sub_shift_amt = sub_shift_raw[4:0];
    wire [52:0] ext_mant  = {mantissa_27[26:1], 27'b0};
    wire [52:0] shifted_m = ext_mant >> sub_shift_amt;
    wire [25:0] sub_mant26   = shifted_m[52:27];
    wire        sub_sticky_x = |shifted_m[26:0];
    wire        sub_sticky   = sub_sticky_x | mantissa_27[0];
    wire [26:0] sub_mant27   = {sub_mant26, sub_sticky};

    wire [26:0] pre_rnd_mant = is_subnormal ? sub_mant27 : mantissa_27;
    wire [9:0]  pre_rnd_exp  = is_subnormal ? 10'sd0     : exp_res;

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

    wire [24:0] mant_rounded   = {1'b0, pre_rnd_mant[26:3]} + round_up;
    wire        round_overflow = mant_rounded[24];
    wire [23:0] final_mant     = round_overflow ? mant_rounded[24:1] : mant_rounded[23:0];
    wire [9:0]  final_exp_raw  = pre_rnd_exp + (round_overflow ? 10'sd1 : 10'sd0);

    wire result_overflow = (final_exp_raw >= 10'sd255);
    wire [7:0]  final_exp  = result_overflow ? 8'hFE : final_exp_raw[7:0];
    wire [31:0] packed_result = {sign_res, final_exp, final_mant[22:0]};

    wire flag_of = result_overflow;
    wire flag_uf = is_underflow & grs;
    wire flag_nx = grs | round_up;

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= IDLE;
            src1_r    <= 32'b0;
            rm_r      <= 3'b0;
            sign_res  <= 1'b0;
            exp_res   <= 10'b0;
            root      <= 28'b0;
            sqrt_rem  <= 32'b0;
            s_shift   <= 56'b0;
            iter_cnt  <= 5'b0;
            sticky    <= 1'b0;
            flags_r   <= 5'b0;
            result_r  <= 32'b0;
        end else if (flush) begin
            state     <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        src1_r   <= src1;
                        rm_r     <= rm;
                        flags_r  <= 5'b0;
                        result_r <= 32'b0;
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
                        // sqrt(±0) = ±0
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
                    // Load the 54-bit input into shift register and init algorithm
                    s_shift  <= {sqrt_input_c, 2'b0};  // 56 bits: 54 data + 2 padding
                    sqrt_rem <= 32'b0;
                    root     <= 28'b0;
                    iter_cnt <= 5'd0;
                    state    <= ITERATE;
                end

                ITERATE: begin
                    if (iter_cnt < 5'd27) begin
                        // Digit-by-digit sqrt step
                        s_shift <= s_shift << 2;
                        if (rem_ge_trial) begin
                            sqrt_rem <= rem_sub_trial;
                            root     <= {root[26:0], 1'b1};
                        end else begin
                            sqrt_rem <= rem_new;
                            root     <= {root[26:0], 1'b0};
                        end
                        iter_cnt <= iter_cnt + 5'd1;
                    end else begin
                        // Done — compute sticky from remainder
                        sticky <= (sqrt_rem != 32'b0);
                        state  <= NORM;
                    end
                end

                NORM: begin
                    // Result is always normalized for sqrt (bit 26 = 1)
                    // but check just in case of subnormal result
                    if (!root[26] && root[25]) begin
                        // Shift left by 1 to normalize
                        root    <= {root[25:0], 1'b0};
                        exp_res <= exp_res - 10'sd1;
                    end
                    state <= ROUND_S;
                end

                ROUND_S: begin
                    if (is_tiny_zero) begin
                        result_r   <= sign_res ? NEG_ZERO : POS_ZERO;
                        flags_r[1] <= is_underflow & (mantissa_27 != 27'b0);
                        flags_r[0] <= (mantissa_27 != 27'b0);
                    end else if (result_overflow) begin
                        result_r   <= POS_INF;
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

                default: state <= IDLE;  // BUG-FIX: 防止状态机卡死在非法状态
            endcase
        end
    end

    assign result = result_r;
    assign fflags = flags_r;
    assign done   = (state == DONE_STATE);

endmodule
