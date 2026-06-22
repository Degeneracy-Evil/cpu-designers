`timescale 1ns / 1ps

module tb_audit_mmu_bugs;

    localparam integer EXPECTED_TOTAL = 6;
    localparam integer SIM_CYCLES    = 300000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        integer result_idx;
        pass_count = 0; fail_count = 0; repeat (SIM_CYCLES) @(posedge clk);

        $display(""); $display("--- Audit mmu_bugs Results ---");
        read_reg(5'd28, _val); $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val); $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val); $display("  x30 (first_fail_id) = %0d", _val);
        for (integer i = 0; i < EXPECTED_TOTAL; i = i + 1) begin
            result_idx = (32'h80007000 >> 2) + 4 + i;
            _val = u_soc.sim_ram.u_axi_ram.BRAM[result_idx];
            if (_val === 32'd1) $display("  test_%0d: PASS", i+1);
            else if (_val === 32'd0) $display("  test_%0d: FAIL", i+1);
            else $display("  test_%0d: UNRUN (val=0x%08h)", i+1, _val);
        end
        $display("");
        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin pass_count = pass_count + 1; $display("  PASS pass_count = %0d", EXPECTED_TOTAL); end
        else begin fail_count = fail_count + 1; $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val); end
        read_reg(5'd30, _val);
        if (_val === 32'd0) begin pass_count = pass_count + 1; $display("  PASS first_fail_id = 0"); end
        else begin fail_count = fail_count + 1; $display("  FAIL first_fail_id = %0d", _val); end
        $display(""); $display("========================================");
        $display("Audit mmu_bugs summary"); $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED"); else $display("TEST FAILED");
        $display("========================================"); $finish;
    end

endmodule
