`timescale 1ns / 1ps

module fpu_cvt(
    input         clk,
    input         reset,
    input  [31:0] src1,
    input  [2:0]  cvt_funct,   // 000=FCVT.W.S, 001=FCVT.WU.S, 010=FCVT.S.W, 011=FCVT.S.WU
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
    localparam [1:0] IDLE       = 2'd0;
    localparam [1:0] COMPUTE    = 2'd1;
    localparam [1:0] ROUND_S   = 2'd2;
    localparam [1:0] DONE_STATE = 2'd3;

    // Conversion function codes
    localparam [2:0] FCVT_W_S  = 3'd0;   // float -> signed int32
    localparam [2:0] FCVT_WU_S = 3'd1;   // float -> unsigned int32
    localparam [2:0] FCVT_S_W  = 3'd2;   // signed int32 -> float
    localparam [2:0] FCVT_S_WU = 3'd3;   // unsigned int32 -> float

    localparam [31:0] QNAN = 32'h7FC00000;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [1:0]  state;
    reg [31:0] src1_r;
    reg [2:0]  cvt_r, rm_r;
    reg [31:0] result_r;
    reg [4:0]  flags_r;

    // ----------------------------------------------------------------
    // Float fields (for float->int)
    // ----------------------------------------------------------------
    wire        f_sign = src1_r[31];
    wire [7:0]  f_exp  = src1_r[30:23];
    wire [22:0] f_frac = src1_r[22:0];
    wire [23:0] f_mant = {1'b1, f_frac};  // with implicit 1

    wire f_is_nan  = (f_exp == 8'hFF) && (f_frac != 23'b0);
    wire f_is_snan = f_is_nan && !f_frac[22];
    wire f_is_inf  = (f_exp == 8'hFF) && (f_frac == 23'b0);
    wire f_is_zero = (f_exp == 8'b0)  && (f_frac == 23'b0);
    wire f_is_sub  = (f_exp == 8'b0)  && (f_frac != 23'b0);

    // ----------------------------------------------------------------
    // Leading-zero count functions
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

    function [5:0] clz32;
        input [31:0] val;
        begin
            if      (val[31]) clz32 = 6'd0;
            else if (val[30]) clz32 = 6'd1;
            else if (val[29]) clz32 = 6'd2;
            else if (val[28]) clz32 = 6'd3;
            else if (val[27]) clz32 = 6'd4;
            else if (val[26]) clz32 = 6'd5;
            else if (val[25]) clz32 = 6'd6;
            else if (val[24]) clz32 = 6'd7;
            else if (val[23]) clz32 = 6'd8;
            else if (val[22]) clz32 = 6'd9;
            else if (val[21]) clz32 = 6'd10;
            else if (val[20]) clz32 = 6'd11;
            else if (val[19]) clz32 = 6'd12;
            else if (val[18]) clz32 = 6'd13;
            else if (val[17]) clz32 = 6'd14;
            else if (val[16]) clz32 = 6'd15;
            else if (val[15]) clz32 = 6'd16;
            else if (val[14]) clz32 = 6'd17;
            else if (val[13]) clz32 = 6'd18;
            else if (val[12]) clz32 = 6'd19;
            else if (val[11]) clz32 = 6'd20;
            else if (val[10]) clz32 = 6'd21;
            else if (val[9])  clz32 = 6'd22;
            else if (val[8])  clz32 = 6'd23;
            else if (val[7])  clz32 = 6'd24;
            else if (val[6])  clz32 = 6'd25;
            else if (val[5])  clz32 = 6'd26;
            else if (val[4])  clz32 = 6'd27;
            else if (val[3])  clz32 = 6'd28;
            else if (val[2])  clz32 = 6'd29;
            else if (val[1])  clz32 = 6'd30;
            else if (val[0])  clz32 = 6'd31;
            else              clz32 = 6'd32;
        end
    endfunction

    // ====================================================================
    // Float → Int conversion (combinational, used in COMPUTE state)
    // ====================================================================
    // Normalize subnormal float
    wire [4:0]  f_lz    = clz23(f_frac);
    wire [22:0] f_frac_shft = f_frac << f_lz;
    wire [23:0] f_mant_norm = f_is_sub ? {1'b1, f_frac_shft[21:0]} : f_mant;
    wire [9:0]  f_eff_exp   = f_is_sub ? (10'sd1 - {{5'd0}, f_lz}) : {2'b0, f_exp};

    // |value| = f_mant_norm * 2^(f_eff_exp - 150)
    // shift = 150 - f_eff_exp  (bits to shift right to get integer)
    wire [9:0] f_shift = 10'sd150 - f_eff_exp;

    // For large values (shift negative), shift left instead
    wire        f_large    = (f_shift[9] == 1'b1);  // negative shift => large value
    wire [9:0]  f_lshift   = -f_shift;               // left shift amount
    // BUG-7 fix: detect overflow when left shift >= 32 (result exceeds int32 range)
    wire        f_lshift_of = f_large && (f_lshift >= 10'd32);
    wire [31:0] f_val_shl  = {8'b0, f_mant_norm} << f_lshift[4:0];  // shift left

    // For small values (shift positive), shift right with GRS
    // BUG-8 fix: detect when right shift >= 56 (all mantissa bits shifted out → integer = 0)
    wire        f_rshift_zero = !f_large && (f_shift >= 10'd56);
    wire [55:0] f_ext_mant = {f_mant_norm, 32'b0};   // 56-bit: 24 mant + 32 extra
    wire [55:0] f_val_shr  = f_rshift_zero ? 56'b0 : (f_ext_mant >> f_shift[5:0]);  // shift right
    wire [23:0] f_int_part = f_val_shr[55:32];        // integer part (24 bits)
    wire        f_grd      = f_val_shr[31];            // guard
    wire        f_rnd      = f_val_shr[30];            // round
    wire        f_stk      = |f_val_shr[29:0] | f_rshift_zero;  // sticky (includes shifted-out bits)

    // Select shifted result (32-bit to handle large values from left-shift)
    wire [31:0] f_abs_int  = f_large ? f_val_shl : {8'b0, f_int_part};
    wire        f_guard    = f_large ? 1'b0 : f_grd;
    wire        f_round    = f_large ? 1'b0 : f_rnd;
    wire        f_sticky   = f_large ? 1'b0 : f_stk;
    wire        f_grs_any  = f_guard | f_round | f_sticky;

    // Rounding for float→int (round the absolute value, then apply sign)
    wire fi_lsb    = f_abs_int[0];
    wire fi_rne    = f_guard & (f_round | f_sticky | fi_lsb);
    wire fi_rtz    = 1'b0;
    wire fi_rdn    = f_sign & f_grs_any;   // toward -inf: round up if negative
    wire fi_rup    = ~f_sign & f_grs_any;  // toward +inf: round up if positive
    wire fi_rmm    = f_guard;

    wire fi_round_up = (rm_r == 3'b000) ? fi_rne :
                       (rm_r == 3'b001) ? fi_rtz :
                       (rm_r == 3'b010) ? fi_rdn :
                       (rm_r == 3'b011) ? fi_rup :
                                           fi_rmm;

    wire [32:0] f_abs_rounded = {1'b0, f_abs_int} + fi_round_up;
    wire        f_rnd_overflow = f_abs_rounded[32];

    // Signed int result
    wire [31:0] f_pos_int  = f_abs_rounded[31:0];
    wire [31:0] f_neg_int  = -f_abs_rounded[31:0];  // two's complement
    wire [31:0] f_signed_res = f_sign ? f_neg_int : f_pos_int;

    // Overflow detection for signed int32:
    //   Positive: overflow if abs > INT_MAX (0x7FFFFFFF)
    //   Negative: overflow if abs > |INT_MIN| (0x80000000), i.e. abs >= 0x80000001
    //   -2^31 (abs=0x80000000) is NOT overflow — it is exactly representable
    //   BUG-7 fix: also overflow if left shift >= 32 (value exceeds int32 range)
    wire f_ovf_w  = f_lshift_of | f_rnd_overflow |
                    (f_sign ? (f_abs_rounded[31:0] > 32'h80000000) :
                              (f_abs_rounded[31:0] > 32'h7FFFFFFF));
    // Overflow detection for unsigned int32
    wire f_ovf_wu = f_lshift_of | f_rnd_overflow | (f_abs_rounded[31:0] > 32'hFFFFFFFF) | f_sign;

    // Saturated results
    wire [31:0] sat_w  = f_sign ? 32'h80000000 : 32'h7FFFFFFF;
    wire [31:0] sat_wu = f_sign ? 32'h00000000 : 32'hFFFFFFFF;

    // Final float→int results
    wire [31:0] fcvt_w_res  = f_ovf_w  ? sat_w  : f_signed_res;
    wire [31:0] fcvt_wu_res = f_ovf_wu ? sat_wu : f_pos_int;
    wire        fcvt_w_nv   = f_is_nan | f_is_inf | f_ovf_w;
    wire        fcvt_wu_nv  = f_is_nan | f_is_inf | f_ovf_wu;
    wire        fcvt_w_nx   = f_grs_any | fi_round_up | f_ovf_w;
    wire        fcvt_wu_nx  = f_grs_any | fi_round_up | f_ovf_wu;

    // NaN/Inf special: return INT_MAX, set NV
    wire [31:0] fcvt_w_special  = f_is_snan ? 32'h7FFFFFFF : (f_is_nan ? 32'h7FFFFFFF : sat_w);
    wire [31:0] fcvt_wu_special = f_is_snan ? 32'hFFFFFFFF : (f_is_nan ? 32'hFFFFFFFF : sat_wu);

    // ====================================================================
    // Int → Float conversion (combinational)
    // ====================================================================
    // Treat src1 as signed or unsigned int
    wire [31:0] i_val_w  = src1;                          // signed
    wire [31:0] i_val_wu = src1;                          // unsigned
    wire        i_sign_w = i_val_w[31];                   // sign of signed int
    wire [31:0] i_abs_w  = i_sign_w ? (-i_val_w) : i_val_w;  // absolute value
    wire [31:0] i_abs_wu = i_val_wu;                     // already positive

    wire is_int_to_flt = (cvt_r == FCVT_S_W) || (cvt_r == FCVT_S_WU);

    wire [31:0] i_abs   = (cvt_r == FCVT_S_W) ? i_abs_w : i_abs_wu;
    wire        i_sign  = (cvt_r == FCVT_S_W) ? i_sign_w : 1'b0;

    wire [5:0]  i_lz    = clz32(i_abs);
    wire        i_is_zero = (i_abs == 32'b0);

    // Exponent: leading 1 is at bit (31 - i_lz), so exp = (31 - i_lz) + 127
    wire [7:0]  i_exp   = 8'd158 - {2'b0, i_lz};  // 31 + 127 - lz = 158 - lz

    // Mantissa: shift i_abs left by i_lz to remove leading zeros, putting
    // the leading 1 at bit 31. Then bits [30:8] are the 23-bit fraction.
    wire [31:0] i_shft     = i_abs << i_lz;
    wire [22:0] i_frac     = i_shft[30:8];

    // Rounding for int→float: bits beyond 23-bit fraction
    // Use wider shift to capture guard/round/sticky properly
    // After shifting {i_abs, 24'b0} left by i_lz, the leading 1 is at bit 55.
    // Bits [54:32] = 23-bit fraction, bit [31] = guard, bit [30] = round,
    // bits [29:0] = sticky
    wire [55:0] i_ext_shft = {i_abs, 24'b0} << i_lz;
    wire [22:0] i_frac_r   = i_ext_shft[54:32];  // 23 fraction bits
    wire        i_g        = i_ext_shft[31];       // guard
    wire        i_r        = i_ext_shft[30];       // round
    wire        i_s        = |i_ext_shft[29:0];    // sticky
    wire        i_grs      = i_g | i_r | i_s;

    // Rounding for int→float
    wire i_lsb_frac = i_frac_r[0];
    wire i_rne = i_g & (i_r | i_s | i_lsb_frac);
    wire i_rtz = 1'b0;
    wire i_rdn = i_sign & i_grs;
    wire i_rup = ~i_sign & i_grs;
    wire i_rmm = i_g;

    wire i_round_up = (rm_r == 3'b000) ? i_rne :
                      (rm_r == 3'b001) ? i_rtz :
                      (rm_r == 3'b010) ? i_rdn :
                      (rm_r == 3'b011) ? i_rup :
                                          i_rmm;

    wire [24:0] i_mant_wide    = {1'b0, 1'b1, i_frac_r} + i_round_up;
    wire        i_mant_overflow = i_mant_wide[24];
    wire [23:0] i_mant_rounded = i_mant_wide[23:0];
    wire [22:0] i_final_frac   = i_mant_rounded[22:0];
    wire [7:0]  i_final_exp    = i_mant_overflow ? (i_exp + 8'd1) : i_exp;

    wire [31:0] i_float_result = i_is_zero ? {i_sign, 31'b0} :
                                 {i_sign, i_final_exp, i_final_frac};
    wire        i_nx = i_grs | i_round_up;

    // ====================================================================
    // FSM
    // ====================================================================
    wire is_f2i = (cvt_r == FCVT_W_S) || (cvt_r == FCVT_WU_S);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= IDLE;
            src1_r   <= 32'b0;
            cvt_r    <= 3'b0;
            rm_r     <= 3'b0;
            result_r <= 32'b0;
            flags_r  <= 5'b0;
        end else if (flush) begin
            state    <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        src1_r  <= src1;
                        cvt_r   <= cvt_funct;
                        rm_r    <= rm;
                        flags_r <= 5'b0;
                        state   <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    if (is_int_to_flt) begin
                        // Int→float: combinational from registered values
                        result_r   <= i_float_result;
                        flags_r[4] <= 1'b0;       // NV: never for int→float
                        flags_r[0] <= i_nx;        // NX
                        state      <= DONE_STATE;
                    end
                    // Float→int: handle special cases, compute result
                    else if (f_is_nan) begin
                        result_r   <= (cvt_r == FCVT_W_S) ? 32'h7FFFFFFF : 32'hFFFFFFFF;
                        flags_r[4] <= 1'b1;  // NV
                        flags_r[0] <= 1'b1;  // NX
                    end
                    else if (f_is_inf) begin
                        result_r   <= f_sign ? 32'h80000000 : 32'h7FFFFFFF;
                        if (cvt_r == FCVT_WU_S)
                            result_r <= f_sign ? 32'h0 : 32'hFFFFFFFF;
                        flags_r[4] <= 1'b1;  // NV
                        flags_r[0] <= 1'b1;  // NX
                    end
                    else if (f_is_zero) begin
                        result_r <= 32'b0;
                    end
                    else begin
                        // Normal/subnormal float → int
                        if (cvt_r == FCVT_W_S) begin
                            result_r   <= fcvt_w_res;
                            flags_r[4] <= fcvt_w_nv;
                            flags_r[0] <= fcvt_w_nx;
                        end else begin
                            result_r   <= fcvt_wu_res;
                            flags_r[4] <= fcvt_wu_nv;
                            flags_r[0] <= fcvt_wu_nx;
                        end
                    end
                    state <= DONE_STATE;
                end

                DONE_STATE: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    assign result = result_r;
    assign fflags = flags_r;
    assign done   = (state == DONE_STATE);

endmodule
