`timescale 1ns / 1ps

module fpu_regfile(
    input         clk,
    input         resetn,
    input         wen,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    input  [4:0]  raddr3,       // third read port for FMA rs3
    input  [4:0]  waddr,
    input  [63:0] wdata,
    output [63:0] rdata1,
    output [63:0] rdata2,
    output [63:0] rdata3,       // third read port for FMA rs3
    input  [4:0]  dbg_faddr,
    output [63:0] dbg_fdata
);

    // f0 (ft0) is a normal writable scratch register per RISC-V F-extension
    // spec. Unlike x0 in the integer register file, f0 has no hardwired value.
    // Reset initializes all registers (including f0) to 0 for determinism.
    //
    // Storage widened to 64-bit for D extension support (Task 12). F operations
    // write 32-bit results zero-extended to 64-bit (upper 32=0) for now. Task 13
    // will add NaN-boxing (upper 32=0xFFFFFFFF) on F writes.

    reg [63:0] rf[0:31];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (integer i = 0; i < 32; i = i + 1) rf[i] <= 64'b0;
        end else if (wen) begin
            rf[waddr] <= wdata;
        end
    end

    assign rdata1 = rf[raddr1];
    assign rdata2 = rf[raddr2];
    assign rdata3 = rf[raddr3];
    assign dbg_fdata = rf[dbg_faddr];

endmodule
