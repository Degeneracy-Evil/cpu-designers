`timescale 1ns / 1ps

module tb_cache_cache_mmu_interact;

    localparam integer EXPECTED_TOTAL = 6;
    // PTW-through-dcache: PTW reads consume dcache bandwidth, can cause cache
    // misses (refills ~20-30 cycles each), and PTW priority > CPU can stall
    // normal loads/stores.  Doubled from 200k to 400k for headroom.
    localparam integer SIM_CYCLES    = 400000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- Cache cache_mmu_interact Results ---");

        read_reg(5'd28, _val);
        $display("  x28 (pass_count)    = %0d", _val);

        read_reg(5'd29, _val);
        $display("  x29 (total_count)   = %0d", _val);

        read_reg(5'd30, _val);
        $display("  x30 (first_fail_id) = %0d", _val);

        $display("");

        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = %0d", EXPECTED_TOTAL);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val);
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
        $display("Cache cache_mmu_interact summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

