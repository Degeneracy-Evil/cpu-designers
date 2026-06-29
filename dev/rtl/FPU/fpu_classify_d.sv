`timescale 1ns / 1ps

// Double-precision floating-point classify (FCLASS.D)
// Pure combinational. IEEE 754 double: 1+11+52, bias 1023.
// result: 10-bit mask in lower 10 bits, zero-extended to 64-bit.
//   bit[0] = -Inf        bit[1] = -normal     bit[2] = -subnormal
//   bit[3] = -0          bit[4] = +0          bit[5] = +subnormal
//   bit[6] = +normal     bit[7] = +Inf        bit[8] = sNaN
//   bit[9] = qNaN
// fflags: always 0 (FCLASS never raises exceptions per RISC-V spec).

module fpu_classify_d(
    input  [63:0] src1,
    output [63:0] result,      // 10-bit mask written to integer register
    output [4:0]  fflags       // always 0 (FCLASS never raises exceptions)
);

    wire         sign = src1[63];
    wire [10:0]  exp  = src1[62:52];
    wire [51:0]  frac = src1[51:0];

    // Classify the input (double: exp all-ones = 11'h7FF)
    wire is_inf       = (exp == 11'h7FF) && (frac == 52'b0);
    wire is_nan       = (exp == 11'h7FF) && (frac != 52'b0);
    wire is_snan      = is_nan && !frac[51];   // signaling NaN: exp=7FF, frac[51]=0, frac!=0
    wire is_qnan      = is_nan && frac[51];    // quiet NaN:   exp=7FF, frac[51]=1
    wire is_zero      = (exp == 11'b0) && (frac == 52'b0);
    wire is_subnormal = (exp == 11'b0) && (frac != 52'b0);
    wire is_normal    = (exp != 11'b0) && (exp != 11'h7FF);

    // 10-bit mask (only one bit set at a time), per RISC-V D extension spec:
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

    assign result = {54'b0, mask};
    assign fflags = 5'b00000;  // FCLASS never raises exceptions

endmodule
