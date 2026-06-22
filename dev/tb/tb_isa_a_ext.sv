`timescale 1ns / 1ps

// ============================================================
// tb_isa_a_ext.sv — A extension (Atomic) ISA testbench
// ============================================================
//
// Tests: LR.W/SC.W/AMOSWAP/AMOADD/AMOAND/AMOOR/AMOXOR/AMOMIN/AMOMAX/AMOMINU/AMOMAXU
// Sub-tests: 52 (comprehensive: basic + edge/boundary + LR/SC-AMO interaction + rd=x0)
//
// ============================================================

module tb_isa_a_ext;

    // ── Parameters ──
    localparam integer EXPECTED_TOTAL = 52;
    // Cycles to wait AFTER program starts executing (PC reaches 0x80000000)
    localparam integer SIM_CYCLES    = 1000000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Wait for bootloader to finish UART loading and jump to program
        // (PC enters 0x80000000 range = program entry point)
        wait (resetn && if_pc >= 32'h80000000 && if_pc < 32'h90000000);
        $display("[TB] %0t: Program execution detected at PC=0x%08h, waiting %0d cycles for test completion...",
                 $time, if_pc, SIM_CYCLES);
        $fflush;

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
        $display("ISA A-extension test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule
