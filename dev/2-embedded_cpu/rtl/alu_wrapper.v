`timescale 1ns / 1ps

// Wrapper to adapt CPU execute stage to dev/1-alu protocol ALU.
// Keeps top-level interface naming aligned with CPU pipeline/FSM terminology.
module alu_wrapper(
    // Global clock.
    input         clk,
    // Asynchronous active-high reset.
    input         reset,
    // Execute request valid.
    input         req_valid,
    // Flush ongoing operation/result in ALU wrapper.
    input         flush,
    // One-hot ALU control code.
    input  [15:0] alu_control,
    // ALU source operand A.
    input  [31:0] src1,
    // ALU source operand B.
    input  [31:0] src2,
    // ALU result.
    output [31:0] result,
    // ALU can accept request.
    output        ready,
    // ALU result is valid.
    output        result_valid,
    // ALU busy executing multi-cycle op.
    output        busy,
    // Illegal ALU one-hot code detected.
    output        illegal_op,
    // Division-by-zero status from ALU.
    output        div_by_zero
);

    // dev/1-alu top instance.
    alu_32bit u_alu_32bit(
        .clk(clk),
        .reset(reset),
        .alu_control(alu_control),
        .src1(src1),
        .src2(src2),
        .req_valid(req_valid),
        .flush(flush),
        // Phase-1 uses immediate consume policy for execute result.
        .result_ready(1'b1),
        .result(result),
        .alu_busy(busy),
        .alu_ready(ready),
        .result_valid(result_valid),
        .illegal_op(illegal_op),
        .div_by_zero(div_by_zero)
    );

endmodule
