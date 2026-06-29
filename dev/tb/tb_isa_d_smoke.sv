`timescale 1ns / 1ps

// ============================================================
// tb_isa_d_smoke.sv — D extension smoke test testbench
// ============================================================
//
// Minimal integration smoke test for D extension (Tasks 24-26).
// Verifies that D instructions (FADD.D, FLD, FSD) decode correctly
// and reach the FPU datapath.
//
// Subtests: 2
//   1. FADD.D — 1.0 + 2.0 = 3.0 (exercises fpu_adder_d + FSD writeback)
//   2. FLD/FSD — load/store 64-bit double roundtrip (exercises cpu_mem FLD/FSD)
//
// Self-checking protocol: x28=pass_count, x30=first_fail_id.
// Testbench checks x28==EXPECTED_TOTAL && x30==0.
//
// ============================================================

module tb_isa_d_smoke;

    // ── 参数 ──
    localparam integer EXPECTED_TOTAL = 2;
    localparam integer SIM_CYCLES    = 100000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        // ── Framework Results ──
        $display("");
        $display("--- Framework Results ---");

        read_reg(5'd28, _val);
        $display("  x28 (pass_count)    = %0d", _val);

        read_reg(5'd29, _val);
        $display("  x29 (total_count)   = %0d", _val);

        read_reg(5'd30, _val);
        $display("  x30 (first_fail_id) = %0d", _val);

        $display("");

        // Verify pass_count
        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = %0d", EXPECTED_TOTAL);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val);
        end

        // Verify first_fail_id
        read_reg(5'd30, _val);
        if (_val === 32'd0) begin
            pass_count = pass_count + 1;
            $display("  PASS first_fail_id = 0 (no failures)");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL first_fail_id = %0d (test %0d failed)", _val, _val);
        end

        $display("");
        $display("========================================");
        $display("ISA D_SMOKE test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule
