`timescale 1ns / 1ps

/**
 * ⚠ DEPRECATED — 此文件已不再需要。v3 仿真脚本 (run_ddr3_sim.tcl) 直接在
 * testbench 中生成时钟，bypass clk_wiz_0 / clk_wiz_0_passthrough。
 * 保留仅供参考/回退。
 *
 * clk_wiz_0_passthrough.sv — Simulation-only replacement for clk_wiz_0.
 *
 * When DDR3_BYPASS_CLK_WIZ is defined, this module replaces the Xilinx
 * clk_wiz_0 IP (which contains an MMCME2_ADV that cannot lock properly
 * in XSim behavioral simulation when its outputs are force-overridden).
 *
 * This module:
 *   - Passes clk_in1 through to clk_out1 (100MHz → 100MHz)
 *   - Generates clk_out2 at 2× frequency (200MHz) using a direct
 *     clock generator (matching tb_ddr3_ahb_ex approach)
 *   - Asserts locked after a short delay (simulating MMCM lock time)
 *
 * This matches the architecture of the Xilinx MIG example testbench
 * (bd_soc_mig_7series_0_1_ex) which provides MIG clocks directly
 * from independent clock generators without a clock wizard.
 *
 * Port interface matches clk_wiz_0 exactly for drop-in replacement.
 *
 * NOTE: Previous XOR-based 200MHz generation was broken — it produced
 * 50MHz instead of 200MHz (clk_200mhz toggles on negedge only → 20ns
 * period; XOR with 100MHz input → 50MHz output). MIG requires 200MHz
 * on clk_ref_i; 50MHz prevents internal MMCM from ever locking.
 */
module clk_wiz_0_passthrough (
    input  wire        clk_in1,    // 100MHz input (from external crystal)
    output wire        clk_out1,   // 100MHz passthrough
    output wire        clk_out2,   // 200MHz (direct generator, phase-aligned at t=0)
    input  wire        resetn,     // Active-low reset (unused in passthrough)
    output wire        locked      // Locked after initial delay
);

    // Pass clk_in1 directly to clk_out1 — no MMCM, no phase shift
    assign clk_out1 = clk_in1;

    // Generate 200MHz clock directly — same approach as tb_ddr3_ahb_ex.
    // Both clocks start at 0 at t=0, giving deterministic phase alignment:
    //   clk_in1  (100MHz): _|‾‾‾‾|____|‾‾‾‾|____|   (10ns period)
    //   clk_out2 (200MHz): _|‾‾|__|‾‾|__|‾‾|__|‾‾|   (5ns period)
    //
    // With 1ns/1ps timescale: #2.5 = 2.5ns half-period = 200MHz.
    reg clk_out2_r = 1'b0;
    always #2.5 clk_out2_r = ~clk_out2_r;
    assign clk_out2 = clk_out2_r;

    // Assert locked after 10µs (matching typical MMCM lock time).
    // With 1ns/1ps timescale: #10000 = 10,000ns = 10µs.
    reg locked_r = 1'b0;
    initial begin
        #10000;
        locked_r = 1'b1;
    end
    assign locked = locked_r;

endmodule
