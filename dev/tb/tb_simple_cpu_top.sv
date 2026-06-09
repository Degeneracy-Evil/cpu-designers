`timescale 1ns / 1ps

module tb_simple_cpu_top;

    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"



    initial begin
        pass_count = 0;
        fail_count = 0;

         repeat (4000000) @(posedge clk);

        check_reg(5'd1,  32'h00000008);
        check_reg(5'd2,  32'h00001800);
        check_reg(5'd3,  32'h00000000);
        check_reg(5'd4,  32'h00000000);
        check_reg(5'd5, 32'hffffffff);
        check_reg(5'd6, 32'h00000007);
        check_reg(5'd7, 32'h00000003);
        check_reg(5'd8,  32'h00005555);
        check_reg(5'd9,  32'h00005555);
        check_reg(5'd10, 32'h00000080);  // timing-dependent: x10 last set by csrw mstatus,x10 in timer_handler
        check_reg(5'd11, 32'h0001952f);  // timing-dependent: x11 = mtime + 100000; BRAM/MMIO latency shifts the sample point
        check_reg(5'd12, 32'h000186a0);
        check_reg(5'd13, 32'h00000000);
        check_reg(5'd14, 32'h00000000);
        check_reg(5'd15, 32'h00000005);
        check_reg(5'd16, 32'h00000007);
        check_reg(5'd17, 32'h00000007);
        check_reg(5'd18, 32'h00000006);
        check_reg(5'd19, 32'h00000002);
        check_reg(5'd20, 32'h80000230);  // timing-dependent: x20 = mepc from last ecall trap
        check_reg(5'd21, 32'h80001000);
        check_reg(5'd22, 32'h80001050);
        check_reg(5'd23, 32'h00000000);
        check_reg(5'd24, 32'h00000000);
        check_reg(5'd25, 32'hffffffff);
        check_reg(5'd26, 32'h00000007);
        check_reg(5'd27, 32'h00000007);
        check_reg(5'd28, 32'h00000000);
        check_reg(5'd29, 32'h00000000);
        check_reg(5'd30, 32'h00000000);
        check_reg(5'd31, 32'h800000b0);

        // Data stored at x21 = 0x80001000 (lui x21, 0x80001)
        check_mem_word(32'h80001000, 32'habcd5678);
        check_mem_word(32'h80001004, 32'h12345678);
        check_mem_word(32'h80001008, 32'hff0000ff);

        check_mem_word(32'h80001010, 32'h000002bc);
        check_mem_word(32'h80001014, 32'h00000000);
        check_mem_word(32'h80001018, 32'hffffffff);
        check_mem_word(32'h8000101c, 32'hfffffffe);
        check_mem_word(32'h80001020, 32'h0000000e);
        check_mem_word(32'h80001024, 32'h24924924);
        check_mem_word(32'h80001028, 32'h00000002);
        check_mem_word(32'h8000102c, 32'h00000003);

        $display("========================================");
        $display("simpleCPU test summary");
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
