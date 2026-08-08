`timescale 1ns / 1ps

module tb_mmu_permission;

    localparam integer EXPECTED_TOTAL = 14;
    localparam integer SIM_CYCLES    = 200000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- MMU permission Results ---");

        // Live framework registers make timeout failures diagnosable even
        // when test_report has not yet copied them to x28-x30.
        read_reg(5'd8, _val);
        $display("  x8  (live pass_count)  = %0d", _val);
        read_reg(5'd9, _val);
        $display("  x9  (live total_count) = %0d", _val);
        read_reg(5'd18, _val);
        $display("  x18 (live first_fail)  = %0d", _val);
        $display("  PC=0x%08h state=%0d priv=%0d mcause=0x%08h",
                 if_pc, u_soc.cpu.fsm_state, u_soc.cpu.priv_mode,
                 u_soc.cpu.csr_mcause);

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
            $display("  PASS first_fail_id = 0");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL first_fail_id = %0d", _val);
        end

        $display("");
        $display("========================================");
        $display("MMU permission: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule
