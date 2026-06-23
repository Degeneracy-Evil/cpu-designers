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
    output [31:0] dbg_rdata3,
    output [31:0] dbg_x1,
    output [31:0] dbg_x9,
    output [31:0] dbg_x10,
    output [31:0] dbg_x11,
    output [31:0] dbg_x12,
    output [31:0] dbg_x13,
    output [31:0] dbg_x14,
    output [31:0] dbg_x15,
    output [31:0] dbg_x16,
    output [31:0] dbg_x17,
    output [31:0] dbg_x18,
    output [31:0] dbg_x19
);

    reg [31:0] rf[0:31];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (integer i = 0; i < 32; i = i + 1) rf[i] <= 32'b0;
        end else if (wen && (waddr != 5'd0)) begin
            rf[waddr] <= wdata;
        end
    end

    // Provide same-cycle write-through so decode sees the architecturally
    // newest GPR value when WB and register read target the same address.
    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 :
                    (wen && (waddr == raddr1) && (waddr != 5'd0)) ? wdata :
                    rf[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 :
                    (wen && (waddr == raddr2) && (waddr != 5'd0)) ? wdata :
                    rf[raddr2];
    assign dbg_rdata  = (dbg_raddr  == 5'd0) ? 32'b0 : rf[dbg_raddr];
    assign dbg_rdata2 = (dbg_raddr2 == 5'd0) ? 32'b0 : rf[dbg_raddr2];
    assign dbg_rdata3 = (dbg_raddr3 == 5'd0) ? 32'b0 : rf[dbg_raddr3];
    assign dbg_x1     = rf[1];   // ra
    assign dbg_x9     = rf[9];   // s1
    assign dbg_x10    = rf[10];  // a0
    assign dbg_x11    = rf[11];  // a1
    assign dbg_x12    = rf[12];  // a2
    assign dbg_x13    = rf[13];  // a3
    assign dbg_x14    = rf[14];  // a4
    assign dbg_x15    = rf[15];  // a5
    assign dbg_x16    = rf[16];  // a6
    assign dbg_x17    = rf[17];  // a7
    assign dbg_x18    = rf[18];  // s2
    assign dbg_x19    = rf[19];  // s3

endmodule
