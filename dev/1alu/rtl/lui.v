`timescale 1ns / 1ps

module lui(
    input  [31:0] imm,
    output [31:0] result
  );
  assign result = {imm[15:0], 16'b0};
endmodule
