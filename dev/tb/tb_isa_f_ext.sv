`timescale 1ns / 1ps

// ============================================================
// tb_isa_f_ext.sv — ISA F-extension (single-precision float) testbench
// ============================================================
//
// Tests: FADD/FSUB/FMUL/FDIV/FSQRT/FMIN/FMAX/FSGNJ/FSGNJN/FSGNJX/
//        FEQ/FLT/FLE/FCLASS/FMV.W.X/FMV.X.W/FCVT/FLW/FSW
// Subtests: 26
//
// ============================================================

module tb_isa_f_ext;

    // ── 参数 ──
    localparam integer EXPECTED_TOTAL = 30;
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
        $display("ISA F_EXT test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

