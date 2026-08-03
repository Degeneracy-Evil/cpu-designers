`timescale 1ns / 1ps

// ============================================================
// tb_isa_template.sv — ISA 测试通用 testbench 模板
// ============================================================
//
// 使用: 复制此文件，修改 module 名和参数:
//   1. 将 TB_NAME 改为实际 testbench 名
//   2. 修改 EXPECTED_TOTAL 为预期子测试数
//   3. 修改 SIM_CYCLES 为足够仿真周期数
//
// 检查逻辑:
//   x28 (pass_count) == EXPECTED_TOTAL → PASS
//   x30 (first_fail_id) == 0 → 无失败
//
// ============================================================

module tb_isa_template;

    // ── 参数 (复制时修改) ──
    localparam integer EXPECTED_TOTAL = 20;
    localparam integer SIM_CYCLES    = 50000;


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
        $display("ISA test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

