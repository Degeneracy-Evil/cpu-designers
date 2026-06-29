`timescale 1ns / 1ps

// ====================================================================
// fpu_cvt_d : IEEE 754 double-precision conversion unit
//   0=FCVT.W.D   : double -> signed   int32
//   1=FCVT.WU.D  : double -> unsigned int32
//   2=FCVT.D.W   : signed   int32 -> double
//   3=FCVT.D.WU  : unsigned int32 -> double
//   4=FCVT.S.D   : double -> single
//   5=FCVT.D.S   : single -> double
// ====================================================================
module fpu_cvt_d(
    input         clk,
    input         resetn,
    input  [63:0] src1,
    input  [2:0]  cvt_funct,
    input  [2:0]  rm,
    input         start,
    input         flush,
    output [63:0] result,
    output [4:0]  fflags,
    output        done
);

    // ----------------------------------------------------------------
    // FSM states
    // ----------------------------------------------------------------
    localparam [1:0] IDLE       = 2'd0;
    localparam [1:0] COMPUTE    = 2'd1;
    localparam [1:0] DONE_STATE = 2'd2;

    // Conversion function codes
    localparam [2:0] FCVT_W_D   = 3'd0;   // double -> signed   int32
    localparam [2:0] FCVT_WU_D  = 3'd1;   // double -> unsigned int32
    localparam [2:0] FCVT_D_W   = 3'd2;   // signed   int32 -> double
    localparam [2:0] FCVT_D_WU  = 3'd3;   // unsigned int32 -> double
    localparam [2:0] FCVT_S_D   = 3'd4;   // double -> single
    localparam [2:0] FCVT_D_S   = 3'd5;   // single -> double

    // Canonical NaNs
    localparam [63:0] QNAN_D = 64'h7FF8000000000000;
    localparam [31:0] QNAN_S = 32'h7FC00000;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg  [1:0]  state;
    reg  [63:0] src1_r;
    reg  [2:0]  cvt_r, rm_r;
    reg  [63:0] result_r;
    reg  [4:0]  flags_r;

    // ====================================================================
    // Double-precision field extraction (src1_r)
    // ====================================================================
    wire        d_sign = src1_r[63];
    wire [10:0] d_exp  = src1_r[62:52];
    wire [51:0] d_frac = src1_r[51:0];
    wire [52:0] d_mant = {1'b1, d_frac};   // with implicit 1

    wire d_is_nan  = (d_exp == 11'h7FF) && (d_frac != 52'b0);
    wire d_is_snan = d_is_nan && !d_frac[51];
    wire d_is_inf  = (d_exp == 11'h7FF) && (d_frac == 52'b0);
    wire d_is_zero = (d_exp == 11'b0)    && (d_frac == 52'b0);
    wire d_is_sub  = (d_exp == 11'b0)    && (d_frac != 52'b0);

    // ====================================================================
    // Single-precision field extraction (src1_r[31:0])
    // ====================================================================
    wire        s_sign = src1_r[31];
    wire [7:0]  s_exp  = src1_r[30:23];
    wire [22:0] s_frac = src1_r[22:0];
    wire [23:0] s_mant = {1'b1, s_frac};

    wire s_is_nan  = (s_exp == 8'hFF) && (s_frac != 23'b0);
    wire s_is_snan = s_is_nan && !s_frac[22];
    wire s_is_inf  = (s_exp == 8'hFF) && (s_frac == 23'b0);
    wire s_is_zero = (s_exp == 8'b0)  && (s_frac == 23'b0);
    wire s_is_sub  = (s_exp == 8'b0)  && (s_frac != 23'b0);

    // ====================================================================
    // Leading-zero count functions
    // ====================================================================
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

    // ====================================================================
    // Double -> Int32 conversion (FCVT.W.D / FCVT.WU.D)
    // ====================================================================
    // Normalize subnormal double
    wire [5:0]  d_lz       = clz52(d_frac);
    wire [51:0] d_frac_sh  = d_frac << d_lz;
    wire [52:0] d_mant_nrm = d_is_sub ? {1'b1, d_frac_sh[51:1]} : d_mant;
    // effective exponent: subnormal => 1 - lz ; normal => d_exp
    wire [11:0] d_eff_exp  = d_is_sub ? (12'sd1 - {{6'd0}, d_lz}) : {1'b0, d_exp};

    // |value| = d_mant_nrm * 2^(d_eff_exp - 1075)
    // shift = 1075 - d_eff_exp  (bits to shift right to get integer)
    wire [11:0] d_shift    = 12'sd1075 - d_eff_exp;

    // For large values (shift negative), shift left instead
    wire        d_large     = (d_shift[11] == 1'b1);   // negative shift => large value
    wire [11:0] d_lshift    = -d_shift;                 // left shift amount
    wire        d_lshift_of = d_large && (d_lshift >= 12'd64);
    wire [63:0] d_val_shl   = {8'b0, d_mant_nrm} << d_lshift[5:0];

    // For small values (shift positive), shift right with GRS
    wire        d_rshift_zero = !d_large && (d_shift >= 12'd84);
    wire [83:0] d_ext_mant   = {d_mant_nrm, 31'b0};     // 84-bit: 53 mant + 31 extra
    wire [83:0] d_val_shr    = d_rshift_zero ? 84'b0 : (d_ext_mant >> d_shift[6:0]);
    wire [52:0] d_int_part   = d_val_shr[83:31];        // integer part (53 bits)
    wire        d_grd        = d_val_shr[30];
    wire        d_rnd        = d_val_shr[29];
    wire        d_stk        = |d_val_shr[28:0] | d_rshift_zero;

    // Select shifted result
    wire [63:0] d_abs_int  = d_large ? d_val_shl : {11'b0, d_int_part};
    wire        d_guard    = d_large ? 1'b0 : d_grd;
    wire        d_round    = d_large ? 1'b0 : d_rnd;
    wire        d_sticky   = d_large ? 1'b0 : d_stk;
    wire        d_grs_any  = d_guard | d_round | d_sticky;

    // Rounding for double->int (round absolute value, then apply sign)
    wire di_lsb    = d_abs_int[0];
    wire di_rne    = d_guard & (d_round | d_sticky | di_lsb);
    wire di_rtz    = 1'b0;
    wire di_rdn    = d_sign & d_grs_any;
    wire di_rup    = ~d_sign & d_grs_any;
    wire di_rmm    = d_guard;

    wire di_round_up = (rm_r == 3'b000) ? di_rne :
                       (rm_r == 3'b001) ? di_rtz :
                       (rm_r == 3'b010) ? di_rdn :
                       (rm_r == 3'b011) ? di_rup :
                                          di_rmm;

    wire [64:0] d_abs_rounded = {1'b0, d_abs_int} + di_round_up;
    wire        d_rnd_overflow = d_abs_rounded[64];

    // Signed int result
    wire [31:0] d_pos_int    = d_abs_rounded[31:0];
    wire [31:0] d_neg_int    = -d_abs_rounded[31:0];
    wire [31:0] d_signed_res = d_sign ? d_neg_int : d_pos_int;

    // Overflow detection for signed int32
    // Use full 65-bit d_abs_rounded (not just [31:0]) so values >= 2^32
    // are correctly detected as overflow even when lower 32 bits are 0.
    wire d_ovf_w  = d_lshift_of | d_rnd_overflow |
                    (d_sign ? (d_abs_rounded > 65'h80000000) :
                              (d_abs_rounded > 65'h7FFFFFFF));
    // Overflow detection for unsigned int32
    wire d_ovf_wu = d_lshift_of | d_rnd_overflow |
                    (d_abs_rounded > 65'hFFFFFFFF) | d_sign;

    // Saturated results
    wire [31:0] sat_w  = d_sign ? 32'h80000000 : 32'h7FFFFFFF;
    wire [31:0] sat_wu = d_sign ? 32'h00000000 : 32'hFFFFFFFF;

    // Final double->int results
    wire [31:0] fcvt_w_d_res  = d_ovf_w  ? sat_w  : d_signed_res;
    wire [31:0] fcvt_wu_d_res = d_ovf_wu ? sat_wu : d_pos_int;
    wire        fcvt_w_d_nv   = d_is_nan | d_is_inf | d_ovf_w;
    wire        fcvt_wu_d_nv  = d_is_nan | d_is_inf | d_ovf_wu;
    wire        fcvt_w_d_nx   = d_grs_any | di_round_up | d_ovf_w;
    wire        fcvt_wu_d_nx  = d_grs_any | di_round_up | d_ovf_wu;

    // ====================================================================
    // Int32 -> Double conversion (FCVT.D.W / FCVT.D.WU)
    // ====================================================================
    wire [31:0] i_val_w  = src1_r[31:0];
    wire [31:0] i_val_wu = src1_r[31:0];
    wire        i_sign_w = i_val_w[31];
    wire [31:0] i_abs_w  = i_sign_w ? (-i_val_w) : i_val_w;
    wire [31:0] i_abs_wu = i_val_wu;

    wire        is_int_to_dbl = (cvt_r == FCVT_D_W) || (cvt_r == FCVT_D_WU);

    wire [31:0] i_abs   = (cvt_r == FCVT_D_W) ? i_abs_w : i_abs_wu;
    wire        i_sign  = (cvt_r == FCVT_D_W) ? i_sign_w : 1'b0;

    wire [5:0]  i_lz    = clz32(i_abs);
    wire        i_is_zero = (i_abs == 32'b0);

    // Exponent: leading 1 is at bit (31 - i_lz), so exp = (31 - i_lz) + 1023
    wire [10:0] i_exp   = 11'd1054 - {5'd0, i_lz};   // 31 + 1023 - lz = 1054 - lz

    // Mantissa: shift i_abs left by i_lz to remove leading zeros, putting
    // the leading 1 at bit 31. Then bits [30:0] become top of 52-bit frac.
    // For double, we need 52-bit fraction. After left shift, leading 1 at
    // bit 31, so fraction = {i_shft[30:0], 21'b0} (zero-extended to 52 bits).
    wire [31:0] i_shft  = i_abs << i_lz;
    wire [51:0] i_frac  = {i_shft[30:0], 21'b0};

    // Int32 -> double is always exact (32-bit int fits in 52-bit mantissa),
    // so no rounding is needed.
    wire [63:0] i_dbl_result = i_is_zero ? {i_sign, 63'b0} :
                               {i_sign, i_exp, i_frac};

    // ====================================================================
    // Single -> Double conversion (FCVT.D.S)
    // ====================================================================
    // Exact conversion for normal: exp_d = exp_s + (1023 - 127) = exp_s + 896
    // frac_d = {frac_s, 29'b0}
    wire [10:0] sd_exp_d  = {3'b0, s_exp} + 11'd896;
    wire [51:0] sd_frac_d = {s_frac, 29'b0};

    // Subnormal single -> normal double normalization.
    // S subnormal value = 0.s_frac × 2^-126 = s_frac × 2^-149.
    // Find leading 1 in s_frac (23-bit). lz = clz of {s_frac, 9'b0} (32-bit).
    // Leading 1 at bit k = 22 - lz. Normalized: 1.xxx × 2^(k-149).
    // D exp = (k - 149) + 1023 = (22 - lz) + 874 = 896 - lz.
    // D frac = {(s_frac << lz)[21:0], 30'b0} (22 fraction bits + 30 zeros = 52).
    wire [5:0]  s_sub_lz    = clz32({s_frac, 9'b0});
    wire [22:0] s_frac_nrm  = s_frac << s_sub_lz;        // leading 1 now at bit 22
    wire [10:0] sd_sub_exp  = 11'd896 - {5'd0, s_sub_lz};
    wire [51:0] sd_sub_frac = {s_frac_nrm[21:0], 30'b0};

    // Handle special cases for single
    wire [63:0] sd_result =
        s_is_nan  ? {s_sign, 11'h7FF, 1'b1, s_frac[21:0], 29'b0} :  // propagate NaN
        s_is_inf  ? {s_sign, 11'h7FF, 52'b0} :                      // Inf
        s_is_zero ? {s_sign, 63'b0} :                               // Zero
        s_is_sub  ? {s_sign, sd_sub_exp, sd_sub_frac} :             // subnormal S -> normal D
                   {s_sign, sd_exp_d, sd_frac_d};                   // normal

    // FCVT.D.S is always exact (no rounding needed for widening).
    // S subnormals (2^-149 .. 2^-127) all map to D normals (exp 874..896),
    // well above D subnormal range (exp < 1).

    // ====================================================================
    // Double -> Single conversion (FCVT.S.D)
    // ====================================================================
    // Normalize subnormal double for conversion
    wire [5:0]  ds_lz       = clz52(d_frac);
    wire [51:0] ds_frac_sh  = d_frac << ds_lz;
    wire [52:0] ds_mant_nrm = d_is_sub ? {1'b1, ds_frac_sh[51:1]} : d_mant;
    wire [11:0] ds_eff_exp  = d_is_sub ? (12'sd1 - {{6'd0}, ds_lz}) : {1'b0, d_exp};

    // Target single exponent: exp_s = ds_eff_exp - (1023 - 127) = ds_eff_exp - 896
    wire [11:0] ds_exp_s    = ds_eff_exp - 12'sd896;

    // We need to extract 23-bit fraction from 52-bit mantissa with rounding.
    // mantissa is 53 bits (1.mant). After removing implicit 1, we have 52 frac bits.
    // Single needs 23 frac bits, so we shift right by 29 bits.
    // Build a wide field: {mant[52:29], guard=mant[28], round=mant[27], sticky=|mant[26:0]}
    wire [22:0] ds_frac_int = ds_mant_nrm[51:29];
    wire        ds_guard    = ds_mant_nrm[28];
    wire        ds_round    = ds_mant_nrm[27];
    wire        ds_sticky   = |ds_mant_nrm[26:0];
    wire        ds_grs_any  = ds_guard | ds_round | ds_sticky;

    // Rounding for double->single
    wire ds_lsb    = ds_frac_int[0];
    wire ds_rne    = ds_guard & (ds_round | ds_sticky | ds_lsb);
    wire ds_rtz    = 1'b0;
    wire ds_rdn    = d_sign & ds_grs_any;
    wire ds_rup    = ~d_sign & ds_grs_any;
    wire ds_rmm    = ds_guard;

    wire ds_round_up = (rm_r == 3'b000) ? ds_rne :
                       (rm_r == 3'b001) ? ds_rtz :
                       (rm_r == 3'b010) ? ds_rdn :
                       (rm_r == 3'b011) ? ds_rup :
                                          ds_rmm;

    wire [23:0] ds_mant_wide    = {1'b0, ds_frac_int} + ds_round_up;
    wire        ds_mant_ovf     = ds_mant_wide[23];
    wire [22:0] ds_final_frac   = ds_mant_wide[22:0];
    wire [10:0] ds_final_exp    = ds_exp_s + (ds_mant_ovf ? 11'sd1 : 11'sd0);

    // Overflow / underflow detection for single
    // Single exp range: 1..254 (normal), 0 (zero/subnormal), 255 (inf/nan)
    wire ds_ovf_s  = (ds_final_exp >= 11'd255);   // overflow to infinity
    wire ds_unf_s  = (ds_final_exp == 11'd0) && !ds_mant_ovf;  // underflow

    // Build single result
    wire [31:0] ds_single_normal = {d_sign, ds_final_exp[7:0], ds_final_frac};

    // Overflow: return infinity with sign
    wire [31:0] ds_single_ovf = {d_sign, 8'hFF, 23'b0};

    // Underflow: return zero (simplified; could produce subnormal single)
    wire [31:0] ds_single_unf = {d_sign, 31'b0};

    wire [31:0] ds_single_res =
        d_is_nan ? {d_sign, 8'hFF, 1'b1, d_frac[50:29]} :   // propagate NaN
        d_is_inf ? {d_sign, 8'hFF, 23'b0} :                 // Inf
        d_is_zero ? {d_sign, 31'b0} :                       // Zero (preserve sign)
        ds_ovf_s  ? ds_single_ovf :
        ds_unf_s  ? ds_single_unf :
                    ds_single_normal;

    // Flags for double->single
    wire ds_of = ds_ovf_s & ~d_is_nan & ~d_is_inf & ~d_is_zero;
    wire ds_uf = ds_unf_s & ~d_is_nan & ~d_is_inf & ~d_is_zero;
    wire ds_nx = ds_grs_any | ds_round_up | ds_of | ds_uf;
    wire ds_nv = d_is_snan;   // signaling NaN -> invalid

    // ====================================================================
    // FSM
    // ====================================================================
    wire is_d2i = (cvt_r == FCVT_W_D)  || (cvt_r == FCVT_WU_D);
    wire is_i2d = (cvt_r == FCVT_D_W)  || (cvt_r == FCVT_D_WU);
    wire is_s2d = (cvt_r == FCVT_D_S);
    wire is_d2s = (cvt_r == FCVT_S_D);

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state    <= IDLE;
            src1_r   <= 64'b0;
            cvt_r    <= 3'b0;
            rm_r     <= 3'b0;
            result_r <= 64'b0;
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
                    if (is_i2d) begin
                        // Int32 -> double: exact, no rounding
                        result_r   <= i_dbl_result;
                        flags_r    <= 5'b0;
                    end
                    else if (is_s2d) begin
                        // Single -> double: exact widening
                        result_r   <= sd_result;
                        flags_r[4] <= s_is_snan;   // NV if signaling NaN
                        flags_r[0] <= 1'b0;         // exact
                    end
                    else if (is_d2s) begin
                        // Double -> single: may round
                        result_r   <= {32'hFFFFFFFF, ds_single_res};
                        flags_r[4] <= ds_nv;
                        flags_r[2] <= ds_of;
                        flags_r[1] <= ds_uf;
                        flags_r[0] <= ds_nx;
                    end
                    else if (is_d2i) begin
                        // Double -> int32
                        if (d_is_nan) begin
                            result_r   <= (cvt_r == FCVT_W_D) ?
                                          {32'b0, 32'h7FFFFFFF} :
                                          {32'b0, 32'hFFFFFFFF};
                            flags_r[4] <= 1'b1;  // NV
                            flags_r[0] <= 1'b1;  // NX
                        end
                        else if (d_is_inf) begin
                            result_r   <= (cvt_r == FCVT_W_D) ?
                                          (d_sign ? {32'b0, 32'h80000000} :
                                                    {32'b0, 32'h7FFFFFFF}) :
                                          (d_sign ? {32'b0, 32'h00000000} :
                                                    {32'b0, 32'hFFFFFFFF});
                            flags_r[4] <= 1'b1;  // NV
                            flags_r[0] <= 1'b1;  // NX
                        end
                        else if (d_is_zero) begin
                            result_r <= 64'b0;
                        end
                        else begin
                            // Normal/subnormal double -> int
                            if (cvt_r == FCVT_W_D) begin
                                result_r   <= {32'b0, fcvt_w_d_res};
                                flags_r[4] <= fcvt_w_d_nv;
                                flags_r[0] <= fcvt_w_d_nx;
                            end else begin
                                result_r   <= {32'b0, fcvt_wu_d_res};
                                flags_r[4] <= fcvt_wu_d_nv;
                                flags_r[0] <= fcvt_wu_d_nx;
                            end
                        end
                    end
                    state <= DONE_STATE;
                end

                DONE_STATE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign result = result_r;
    assign fflags = flags_r;
    assign done   = (state == DONE_STATE);

endmodule
