`timescale 1ns / 1ps

// 32 x 32-bit integer register file.
// - Two combinational read ports (rs1/rs2).
// - One synchronous write port (rd).
// - x0 is hardwired to zero.
module regfile(
    // Global clock.
    input         clk,
    // Asynchronous active-high reset.
    input         reset,
    // Register write enable.
    input         write_en,
    // Source register 1 address.
    input  [4:0]  rs1_addr,
    // Source register 2 address.
    input  [4:0]  rs2_addr,
    // Destination register address.
    input  [4:0]  rd_addr,
    // Destination register write data.
    input  [31:0] rd_data,
    // Source register 1 read data.
    output [31:0] rs1_data,
    // Source register 2 read data.
    output [31:0] rs2_data
);

    // Physical register array.
    reg [31:0] regs[0:31];
    integer i;

    // Combinational read ports with x0 hardwired to zero.
    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];

    // Synchronous write and reset logic.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Clear all registers on reset.
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else begin
            // Ignore writes to x0.
            if (write_en && (rd_addr != 5'b0))
                regs[rd_addr] <= rd_data;
            // Keep x0 at zero every cycle.
            regs[0] <= 32'b0;
        end
    end

endmodule
