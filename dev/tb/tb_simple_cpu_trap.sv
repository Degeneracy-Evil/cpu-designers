`timescale 1ns / 1ps

module tb_simple_cpu_trap;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"

    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (30000) @(posedge clk);

        check_reg(5'd1,  32'h00000008);
        check_reg(5'd2,  32'h00000000);
        check_reg(5'd3,  32'h00000000);
        check_reg(5'd4,  32'h00000000);
        check_reg(5'd19, 32'h80000007);
        check_reg(5'd20, 32'h8000003c);
        check_reg(5'd21, 32'h00000003);
        check_reg(5'd23, 32'h00000001);
        check_reg(5'd24, 32'h00000001);

        check_mem_word(32'h48, 32'h0000000b);
        check_mem_word(32'h4C, 32'h00000003);
        check_mem_word(32'h50, 32'h00000002);
        check_mem_word(32'h54, 32'h00000001);
        check_mem_word(32'h58, 32'h80000007);

        $display("========================================");
        $display("trap test summary");
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

