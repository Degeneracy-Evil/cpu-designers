`timescale 1ns / 1ps

module fpu_classify(
    input  [31:0] src1,
    output [31:0] result,      // 10-bit mask written to integer register
    output [4:0]  fflags       // NV if sNaN input
);

    wire        sign = src1[31];
    wire [7:0]  exp  = src1[30:23];
    wire [22:0] frac = src1[22:0];

    // Classify the input
    wire is_inf       = (exp == 8'hFF) && (frac == 23'b0);
    wire is_nan       = (exp == 8'hFF) && (frac != 23'b0);
    wire is_snan      = is_nan && !frac[22];   // signaling NaN: exp=FF, frac[22]=0, frac!=0
    wire is_qnan      = is_nan && frac[22];    // quiet NaN:   exp=FF, frac[22]=1
    wire is_zero      = (exp == 8'b0) && (frac == 23'b0);
    wire is_subnormal = (exp == 8'b0) && (frac != 23'b0);
    wire is_normal    = (exp != 8'b0) && (exp != 8'hFF);

    // 10-bit mask (only one bit set at a time), per RISC-V F extension spec:
    // bit[0] = -Inf        bit[1] = -normal     bit[2] = -subnormal
    // bit[3] = -0          bit[4] = +0          bit[5] = +subnormal
    // bit[6] = +normal     bit[7] = +Inf        bit[8] = sNaN
    // bit[9] = qNaN
    wire [9:0] mask;
    assign mask[0] = sign && is_inf;
    assign mask[1] = sign && is_normal;
    assign mask[2] = sign && is_subnormal;
    assign mask[3] = sign && is_zero;
    assign mask[4] = !sign && is_zero;
    assign mask[5] = !sign && is_subnormal;
    assign mask[6] = !sign && is_normal;
    assign mask[7] = !sign && is_inf;
    assign mask[8] = is_snan;
    assign mask[9] = is_qnan;

    assign result = {22'b0, mask};
    assign fflags = is_snan ? 5'b10000 : 5'b00000;  // NV if sNaN

endmodule
