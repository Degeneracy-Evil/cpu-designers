`timescale 1ns / 1ps
module tb_regression_reg_dcache_store_error;
    localparam integer EXPECTED_TOTAL = 1;
    localparam integer SIM_CYCLES = 160000;

    `include "tb_soc_includes.svh"

    initial begin
        wait (resetn === 1'b1);
        repeat (20) @(posedge clk);
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_addr = 32'h8000_3000;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_code = 2'b10;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_pending = 1'b1;
    end

    reg [31:0] value;
    initial begin
        pass_count = 0;
        fail_count = 0;
        repeat (SIM_CYCLES) @(posedge clk);
        $display("");
        $display("--- Regression dcache_store_error Results ---");
        read_reg(5'd28, value);
        $display("  x28 (pass_count)    = %0d", value);
        if (value === EXPECTED_TOTAL) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = %0d", EXPECTED_TOTAL);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, value);
        end
        read_reg(5'd30, value);
        if (value === 32'd0) begin
            pass_count = pass_count + 1;
            $display("  PASS first_fail_id = 0");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL first_fail_id = %0d", value);
        end
        read_reg(5'd22, value);
        $display("  x22 (mcause)        = 0x%08h", value);
        read_reg(5'd23, value);
        $display("  x23 (mtval)         = 0x%08h", value);
        $display("dcache_store_error summary: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
