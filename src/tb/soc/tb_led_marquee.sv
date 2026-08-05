`timescale 1ns / 1ps

module tb_led_marquee;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    wire reset = ~resetn;
    task wait_for_gpio;
        input [15:0] expected;
        input [255:0] name;
        integer timeout;
        begin
            timeout = 0;
            while (gpio_io !== expected && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (gpio_io === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s gpio_io=0x%04h (waited %0d cycles)", name, gpio_io, timeout);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%04h got=0x%04h (timeout)", name, expected, gpio_io);
            end
        end
    endtask

    reg [15:0] prev_gpio;
    integer change_count;

    always @(posedge clk) begin
        if (gpio_io !== prev_gpio && reset === 1'b0) begin
            $display("t=%0t gpio_io=0x%04h gpio_data=0x%08h", $time, gpio_io, {u_soc.u_apb_perips.u_gpio.gpio_data_hi, u_soc.u_apb_perips.u_gpio.gpio_data_lo});
            prev_gpio <= gpio_io;
            change_count = change_count + 1;
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;
        change_count = 0;
        prev_gpio = 16'hFFFF;

        repeat (100) @(posedge clk);

        wait_for_gpio(16'hFFFE, "step0_LED1_on");
        wait_for_gpio(16'hFFFD, "step1_LED2_on");
        wait_for_gpio(16'hFFFB, "step2_LED3_on");
        wait_for_gpio(16'hFFF7, "step3_LED4_on");
        wait_for_gpio(16'hFFEF, "step4_LED5_on");
        wait_for_gpio(16'hFFDF, "step5_LED6_on");
        wait_for_gpio(16'hFFBF, "step6_LED7_on");
        wait_for_gpio(16'hFF7F, "step7_LED8_on");
        wait_for_gpio(16'hFEFF, "step8_LED9_on");
        wait_for_gpio(16'hFDFF, "step9_LED10_on");
        wait_for_gpio(16'hFBFF, "step10_LED11_on");
        wait_for_gpio(16'hF7FF, "step11_LED12_on");
        wait_for_gpio(16'hEFFF, "step12_LED21_on");
        wait_for_gpio(16'hDFFF, "step13_LED22_on");
        wait_for_gpio(16'hBFFF, "step14_LED23_on");
        wait_for_gpio(16'h7FFF, "step15_LED24_on");

        $display("========================================");
        $display("LED marquee test summary");
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

