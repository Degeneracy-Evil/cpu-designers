`timescale 1ns / 1ps

// Program counter register.
// - Asynchronous active-high reset clears PC to 0.
// - PC updates on rising clock edge when write_en is asserted.
module pc_reg(
    // Global clock.
    input         clk,
    // Asynchronous active-high reset.
    input         reset,
    // PC write enable from main controller.
    input         write_en,
    // Next PC value selected by control/data path.
    input  [31:0] next_pc,
    // Current PC value.
    output reg [31:0] pc
);

    // Sequential PC update logic.
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (write_en)
            pc <= next_pc;
    end

endmodule
