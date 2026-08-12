`timescale 1ns / 1ps
module tb_regression_reg_linux_field_values;
    localparam integer EXPECTED_TOTAL = 1;
    localparam integer SIM_CYCLES    = 300000;

    `include "tb_soc_includes.svh"

    reg [31:0] _val;
    initial begin
        pass_count = 0;
        fail_count = 0;
        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- Regression linux_field_values Results ---");
        read_reg(5'd28, _val); $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val); $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val); $display("  x30 (first_fail_id) = %0d", _val);
        read_reg(5'd22, _val); $display("  x22 (mcause)        = 0x%08h", _val);
        read_reg(5'd23, _val); $display("  x23 (mepc)          = 0x%08h", _val);
        read_reg(5'd24, _val); $display("  x24 (mtval)         = 0x%08h", _val);
        read_reg(5'd25, _val); $display("  x25 (reloaded ptr)  = 0x%08h", _val);
        read_reg(5'd26, _val); $display("  x26 (stored data)   = 0x%08h", _val);
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
        $display("Regression linux_field_values summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
