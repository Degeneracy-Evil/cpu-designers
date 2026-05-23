`timescale 1ns / 1ps

module tb_led_marquee;

    reg clk;
    reg reset;
    reg [4:0] rf_addr;

    wire [31:0] rf_data;
    wire [31:0] if_pc;
    wire [31:0] if_inst;
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [31:0] exe_pc;
    wire [31:0] exe_inst;
    wire [31:0] mem_pc;
    wire [31:0] mem_inst;
    wire [31:0] wb_pc;
    wire [31:0] wb_inst;
    wire [31:0] display_state;

    wire [31:0] cpu_HADDR;
    wire [1:0]  cpu_HTRANS;
    wire        cpu_HWRITE;
    wire [2:0]  cpu_HSIZE;
    wire [2:0]  cpu_HBURST;
    wire [3:0]  cpu_HPROT;
    wire        cpu_HMASTLOCK;
    wire [31:0] cpu_HWDATA;
    wire [31:0] cpu_HRDATA;
    wire        cpu_HREADY;
    wire        cpu_HRESP;

    wire        timer_irq;
    wire        plic_eip;
    wire        clint_mtip;
    wire        clint_msip;

    integer pass_count;
    integer fail_count;

    core_top dut(
        .clk(clk),
        .reset(reset),
        .rf_addr(rf_addr),
        .rf_data(rf_data),
        .if_pc(if_pc),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_inst(id_inst),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst),
        .display_state(display_state),
        .HADDR(cpu_HADDR),
        .HTRANS(cpu_HTRANS),
        .HWRITE(cpu_HWRITE),
        .HSIZE(cpu_HSIZE),
        .HBURST(cpu_HBURST),
        .HPROT(cpu_HPROT),
        .HMASTLOCK(cpu_HMASTLOCK),
        .HWDATA(cpu_HWDATA),
        .HRDATA(cpu_HRDATA),
        .HREADY(cpu_HREADY),
        .HRESP(cpu_HRESP),
        .init_sig(1'b0),
        .timer_irq(clint_mtip),
        .ext_meip_in(plic_eip),
        .ext_msip_in(clint_msip)
    );

    wire [15:0] gpio_io;

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (4),
        .MEM_DEPTH   (8192),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_bus (
        .HCLK       (clk),
        .HRESETn    (~reset),
        .HADDR      (cpu_HADDR),
        .HTRANS     (cpu_HTRANS),
        .HWRITE     (cpu_HWRITE),
        .HSIZE      (cpu_HSIZE),
        .HBURST     (cpu_HBURST),
        .HPROT      (cpu_HPROT),
        .HMASTLOCK  (cpu_HMASTLOCK),
        .HWDATA     (cpu_HWDATA),
        .HRDATA     (cpu_HRDATA),
        .HREADY     (cpu_HREADY),
        .HRESP      (cpu_HRESP),
        .o_timer_irq(timer_irq),
        .o_gpio_irq (),
        .o_uart_irq (),
        .o_spi_irq  (),
        .o_plic_eip (plic_eip),
        .o_clint_mtip(clint_mtip),
        .o_clint_msip(clint_msip),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (),
        .o_spiMosi  (),
        .i_spiMiso  (1'b0),
        .o_spiSs    (),
        .o_spiClk   (),
        .o_gpioCtrl (),
        .o_gpioData ()
    );

    initial begin
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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
            $display("t=%0t gpio_io=0x%04h gpio_data=0x%08h", $time, gpio_io, {u_bus.u_apb_perips.u_gpio.gpio_data_hi, u_bus.u_apb_perips.u_gpio.gpio_data_lo});
            prev_gpio <= gpio_io;
            change_count = change_count + 1;
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;
        change_count = 0;
        prev_gpio = 16'hFFFF;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

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
