`timescale 1ns / 1ps

module tb_mmu_pmp_violation;

    // TODO: PMP is currently a PLACEHOLDER in core_top.sv.
    // ptw_pmp_grant is hardwired to 1'b1 and ptw_pmp_fault_type
    // is hardwired to 2'b00. This means PMP violations CANNOT
    // actually occur in the current implementation. This test
    // will FAIL until PMP is properly implemented.
    //
    // Once PMP is functional, this test verifies:
    //   - When PMP denies read access to a PTE address during
    //     a PTW walk, the PTW raises an ACCESS FAULT
    //     (mcause=1/5/7), NOT a page fault (mcause=12/13/15).
    //   - The fault cause matches the original access type:
    //       FETCH → 1, LOAD → 5, STORE → 7

    localparam integer EXPECTED_TOTAL = 3;
    localparam integer SIM_CYCLES    = 200000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- MMU pmp_violation Results ---");

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
        $display("MMU pmp_violation summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule
