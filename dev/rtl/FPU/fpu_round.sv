`timescale 1ns / 1ps

module fpu_round(
    input  [2:0]  rm,          // 0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM
    input         sign,        // result sign
    input  [26:0] mantissa,   // {1.hidden, 23.fraction, guard, round, sticky}
    output [23:0] rounded,    // {1.hidden, 23.fraction} after rounding
    output        round_up,   // whether rounding incremented
    output        overflow    // rounding caused overflow (1.111..1 -> 10.000..0)
);

    // ---------------------------------------------------------------------------
    // Mantissa field extraction
    //   bit[26]    = hidden
    //   bit[25:3]  = fraction (23 bits)
    //   bit[2]     = guard
    //   bit[1]     = round
    //   bit[0]     = sticky
    // ---------------------------------------------------------------------------
    wire        hidden  = mantissa[26];
    wire [22:0] frac    = mantissa[25:3];
    wire        guard   = mantissa[2];
    wire        round_b = mantissa[1];
    wire        sticky  = mantissa[0];

    // LSB of fraction for RNE tie-breaking
    wire frac_lsb = frac[0];

    // ---------------------------------------------------------------------------
    // Per-mode round-up logic
    // ---------------------------------------------------------------------------
    // RNE: round up if guard=1 AND (round OR sticky OR frac_lsb)
    wire rne_up = guard & (round_b | sticky | frac_lsb);
    // RTZ: never round up
    wire rtz_up = 1'b0;
    // RDN: round up if sign=1 AND (guard OR round OR sticky)
    wire rdn_up = sign & (guard | round_b | sticky);
    // RUP: round up if sign=0 AND (guard OR round OR sticky)
    wire rup_up = ~sign & (guard | round_b | sticky);
    // RMM: round up if guard=1
    wire rmm_up = guard;

    // ---------------------------------------------------------------------------
    // Select rounding based on mode
    // ---------------------------------------------------------------------------
    assign round_up = (rm == 3'b000) ? rne_up :
                      (rm == 3'b001) ? rtz_up :
                      (rm == 3'b010) ? rdn_up :
                      (rm == 3'b011) ? rup_up :
                                      rmm_up;  // rm == 3'b100

    // ---------------------------------------------------------------------------
    // Apply rounding with overflow detection
    // ---------------------------------------------------------------------------
    wire [23:0] mantissa_pre = {hidden, frac};

    // 25-bit result to capture carry
    wire [24:0] mantissa_result = {1'b0, mantissa_pre} + {{23{1'b0}}, round_up};

    // Overflow: carry into bit 24 (e.g., 1.111..1 + 1 = 10.000..0)
    assign overflow = mantissa_result[24];

    // If overflow, result is 10.000..0 (hidden=1, frac=0)
    // Caller should increment exponent by 1
    assign rounded = overflow ? 24'h800000 : mantissa_result[23:0];

endmodule
