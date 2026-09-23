`timescale 1ns / 1ps

module tb_cpu_compute;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "support/soc_fixture.svh"

    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (50000) @(posedge clk);

        check_reg(5'd1,  32'h000000ac);
        check_reg(5'd2,  32'h00001800);
        check_reg(5'd3,  32'h00000000);
        check_reg(5'd4,  32'h00000000);
        check_reg(5'd5,  32'hffffffff);
        check_reg(5'd6,  32'h00000007);
        check_reg(5'd7,  32'h00000003);
        check_reg(5'd8,  32'h00005555);
        check_reg(5'd9,  32'h00005555);
        check_reg(5'd10, 32'h00000100);
        check_reg(5'd11, 32'h00005555);
        check_reg(5'd12, 32'h00005554);
        check_reg(5'd13, 32'h00005454);
        check_reg(5'd14, 32'h00000000);
        check_reg(5'd15, 32'h00000005);
        check_reg(5'd16, 32'h00000007);
        check_reg(5'd17, 32'h00000007);
        check_reg(5'd18, 32'h00000006);
        check_reg(5'd19, 32'h00000012);
        check_reg(5'd20, 32'h00005678);
        check_reg(5'd21, 32'h80001000);
        check_reg(5'd22, 32'hffffffff);
        check_reg(5'd23, 32'h00000000);
        check_reg(5'd24, 32'h00000000);
        check_reg(5'd25, 32'hffffffff);
        check_reg(5'd26, 32'h00000007);
        check_reg(5'd27, 32'h00000007);
        check_reg(5'd28, 32'h00000000);
        check_reg(5'd29, 32'h00000000);
        check_reg(5'd30, 32'h00000000);
        check_reg(5'd31, 32'h800000b0);

        // cpu_compute.s uses x21 = 0x8000_1000 as its data base. The SRAM
        // model aliases away the high memory base but preserves offset 0x1000.
        check_mem_word(32'h1000, 32'habcd5678);
        check_mem_word(32'h1004, 32'h12345678);
        check_mem_word(32'h1008, 32'hff0000ff);

        check_mem_word(32'h1010, 32'h000002bc);
        check_mem_word(32'h1014, 32'h00000000);
        check_mem_word(32'h1018, 32'hffffffff);
        check_mem_word(32'h101C, 32'hfffffffe);
        check_mem_word(32'h1020, 32'h0000000e);
        check_mem_word(32'h1024, 32'h24924924);
        check_mem_word(32'h1028, 32'h00000002);
        check_mem_word(32'h102C, 32'h00000003);

        $display("========================================");
        $display("compute test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $fatal(1, "TEST FAILED");
        end
        $display("========================================");
        $finish;
    end


endmodule
