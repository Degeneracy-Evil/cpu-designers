`timescale 1ns / 1ps

// ============================================================================
// reset_sync — Reset synchronizer (async assert, sync deassert)
// ============================================================================
//
// Prevents metastability when an asynchronous reset deasserts near a clock
// edge.  Assertion remains asynchronous (immediate reset response); deassertion
// is synchronized through a 2-stage shift register so that all downstream
// flip-flops see reset removal on the same clean clock edge.
//
// Usage: instantiate one per clock domain.
//   reset_sync u_rst_sync (
//       .rst_n_in (async_resetn),
//       .clk      (domain_clk),
//       .rst_n_out (syncd_resetn)
//   );
//
// After deassertion of rst_n_in, rst_n_out goes high exactly 2 clock cycles
// later (once the shift register has flushed two 1'b1 stages).
// ============================================================================

module reset_sync (
    input  wire rst_n_in,     // async assert / async deassert (active-LOW)
    input  wire clk,          // target clock domain
    output wire rst_n_out     // async assert / SYNC deassert  (active-LOW)
);

    reg [1:0] sync;

    always_ff @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in)
            sync <= 2'b00;
        else
            sync <= {sync[0], 1'b1};
    end

    assign rst_n_out = sync[1];

endmodule
