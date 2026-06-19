`timescale 1ns / 1ps

module cpu_regfile(
    input         clk,
    input         resetn,
    input         wen,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    input  [4:0]  waddr,
    input  [31:0] wdata,
    output [31:0] rdata1,
    output [31:0] rdata2,
    input  [4:0]  dbg_raddr,
    output [31:0] dbg_rdata,
    input  [4:0]  dbg_raddr2,
    output [31:0] dbg_rdata2,
    input  [4:0]  dbg_raddr3,
    output [31:0] dbg_rdata3
);

    reg [31:0] rf[0:31];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (integer i = 0; i < 32; i = i + 1) rf[i] <= 32'b0;
        end else if (wen && (waddr != 5'd0)) begin
            rf[waddr] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : rf[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : rf[raddr2];
    assign dbg_rdata  = (dbg_raddr  == 5'd0) ? 32'b0 : rf[dbg_raddr];
    assign dbg_rdata2 = (dbg_raddr2 == 5'd0) ? 32'b0 : rf[dbg_raddr2];
    assign dbg_rdata3 = (dbg_raddr3 == 5'd0) ? 32'b0 : rf[dbg_raddr3];

endmodule
