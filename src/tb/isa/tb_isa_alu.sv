`timescale 1ns / 1ps

module tb_isa_alu;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Wait for test program to complete
        // isa/alu has 20 sub-tests, should complete in <50000 cycles
        repeat (50000) @(posedge clk);

        // Check framework registers:
        //   x28 = pass_count (should equal x29)
        //   x29 = total_count (should be 20)
        //   x30 = first_fail_id (should be 0 = all pass)
        $display("");
        $display("--- Framework Results ---");

        // Read x28 (pass_count)
        read_reg(5'd28, _val);
        $display("  x28 (pass_count)    = %0d", _val);

        // Read x29 (total_count)
        read_reg(5'd29, _val);
        $display("  x29 (total_count)   = %0d", _val);

        // Read x30 (first_fail_id)
        read_reg(5'd30, _val);
        $display("  x30 (first_fail_id) = %0d", _val);

        $display("");

        // Verify: all tests passed
        // x28 == x29 AND x30 == 0
        read_reg(5'd28, _val);
        if (_val === 32'd20) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = 20");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=20 got=%0d", _val);
        end

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
        $display("ISA ALU test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TEST FAILED");
        end
        $display("========================================");
        $finish;
    end


endmodule

