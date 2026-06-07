`timescale 1ns / 1ps

module fpu_regfile(
    input         clk,
    input         reset,
    input         wen,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    input  [4:0]  waddr,
    input  [31:0] wdata,
    output [31:0] rdata1,
    output [31:0] rdata2,
    input  [4:0]  dbg_faddr,
    output [31:0] dbg_fdata
);

    // Design choice: f0 is hardwired to zero, matching the integer register file
    // pattern. The RISC-V spec does NOT require f0=0 (unlike x0), but this
    // simplifies the design and is a common implementation choice.

    reg [31:0] rf[0:31];

    initial begin
        foreach (rf[i]) rf[i] = 32'b0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            foreach (rf[i]) rf[i] <= 32'b0;
        end else if (wen && (waddr != 5'd0)) begin
            rf[waddr] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : rf[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : rf[raddr2];
    assign dbg_fdata = (dbg_faddr == 5'd0) ? 32'b0 : rf[dbg_faddr];

endmodule
