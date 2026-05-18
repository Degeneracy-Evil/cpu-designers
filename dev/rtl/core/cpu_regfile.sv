`timescale 1ns / 1ps

module cpu_regfile(
    input         clk,
    input         reset,
    input         wen,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    input  [4:0]  waddr,
    input  [31:0] wdata,
    output [31:0] rdata1,
    output [31:0] rdata2,
    input  [4:0]  dbg_raddr,
    output [31:0] dbg_rdata
);

    reg [31:0] rf[0:31];

    initial begin
        foreach (rf[i]) rf[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (reset) begin
            foreach (rf[i]) rf[i] <= 32'b0;
        end else if (wen && (waddr != 5'd0)) begin
            rf[waddr] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : rf[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : rf[raddr2];
    assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'b0 : rf[dbg_raddr];

endmodule
