`timescale 1ns / 1ps
module tb_regression_reg_sfence_wb_error;
    localparam integer EXPECTED_TOTAL = 1;
    localparam integer SIM_CYCLES    = 120000;

    `include "tb_soc_includes.svh"

    initial begin
        wait (resetn === 1'b1);
        repeat (20) @(posedge clk);
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_addr    = 32'h8000_3000;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_code    = 2'b10;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_pending = 1'b1;
    end

    reg [31:0] _val;
    initial begin
        pass_count = 0; fail_count = 0; repeat (SIM_CYCLES) @(posedge clk);
        $display(""); $display("--- Regression sfence_wb_error Results ---");
        read_reg(5'd28, _val); $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val); $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val); $display("  x30 (first_fail_id) = %0d", _val);
        $display("");
        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin pass_count = pass_count + 1; $display("  PASS pass_count = %0d", EXPECTED_TOTAL); end
        else begin fail_count = fail_count + 1; $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val); end
        read_reg(5'd30, _val);
        if (_val === 32'd0) begin pass_count = pass_count + 1; $display("  PASS first_fail_id = 0"); end
        else begin fail_count = fail_count + 1; $display("  FAIL first_fail_id = %0d", _val); end
        $display(""); $display("========================================");
        $display("Regression sfence_wb_error summary"); $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED"); else $display("TEST FAILED");
        $display("========================================"); $finish;
    end
endmodule
