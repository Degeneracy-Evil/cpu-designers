`timescale 1ns / 1ps

module tb_apb_perips;

    reg         HCLK;
    reg         HRESETn;
    reg  [31:0] HADDR;
    reg  [1:0]  HTRANS;
    reg         HWRITE;
    reg  [2:0]  HSIZE;
    reg  [2:0]  HBURST;
    reg  [3:0]  HPROT;
    reg         HMASTLOCK;
    reg  [31:0] HWDATA;

    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;

    wire        o_timer_irq;
    wire        o_gpio_irq;
    wire [15:0] io_gpioPin;
    wire        o_uart_tx;
    wire        o_uart_irq;
    wire        o_spiMosi;
    wire        o_spiSs;
    wire        o_spiClk;
    wire        o_spi_irq;
    wire [31:0] o_gpioCtrl;
    wire [31:0] o_gpioData;

    integer pass_count;
    integer fail_count;

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (5),
        .MEM_DEPTH   (8192),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_dut (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HPROT      (HPROT),
        .HMASTLOCK  (HMASTLOCK),
        .HWDATA     (HWDATA),
        .HRDATA     (HRDATA),
        .HREADY     (HREADY),
        .HRESP      (HRESP),
        .o_timer_irq(o_timer_irq),
        .o_gpio_irq (o_gpio_irq),
        .o_uart_irq (o_uart_irq),
        .o_spi_irq  (o_spi_irq),
        .o_plic_eip (),
        .o_clint_mtip(),
        .o_clint_msip(),
        .io_gpioPin (io_gpioPin),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (o_uart_tx),
        .o_spiMosi  (o_spiMosi),
        .i_spiMiso  (1'b0),
        .o_spiSs    (o_spiSs),
        .o_spiClk   (o_spiClk),
        .o_gpioCtrl (o_gpioCtrl),
        .o_gpioData (o_gpioData)
    );

    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    reg [31:0] latch_wdata;
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge HCLK);
            #1;
            HADDR     = addr;
            HTRANS    = 2'b10; // NONSEQ
            HWRITE    = 1'b1;
            HSIZE     = 3'b010; // WORD
            HBURST    = 3'b000;
            HPROT     = 4'b0011;
            HMASTLOCK = 1'b0;
            latch_wdata = data;
            @(posedge HCLK);
            #1;
            HWDATA = latch_wdata;
            HTRANS = 2'b00; // IDLE
            while (!HREADY) @(posedge HCLK);
        end
    endtask

    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge HCLK);
            #1;
            HADDR     = addr;
            HTRANS    = 2'b10; // NONSEQ
            HWRITE    = 1'b0;
            HSIZE     = 3'b010; // WORD
            HBURST    = 3'b000;
            HPROT     = 4'b0011;
            HMASTLOCK = 1'b0;
            @(posedge HCLK);
            #1;
            HTRANS = 2'b00; // IDLE
            while (!HREADY) @(posedge HCLK);
            #1;
            data = HRDATA;
        end
    endtask

    task check;
        input [255:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, actual);
            end
        end
    endtask

    initial begin
        reg [31:0] rd_val;

        pass_count = 0;
        fail_count = 0;

        HRESETn   = 1'b0;
        HADDR     = 32'b0;
        HTRANS    = 2'b00;
        HWRITE    = 1'b0;
        HWDATA    = 32'b0;
        HSIZE     = 3'b010;
        HBURST    = 3'b000;
        HPROT     = 4'b0011;
        HMASTLOCK = 1'b0;

        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        repeat (2) @(posedge HCLK);

        begin : gpio_test
            ahb_write(32'h10000000, 32'h0000FFFF);
            ahb_read(32'h10000000, rd_val);
            check("GPIO_CTRL write/read", rd_val, 32'h0000FFFF);

            ahb_write(32'h10000004, 32'h0000AAAA);
            ahb_read(32'h10000004, rd_val);
            check("GPIO_DATA write/read", rd_val, 32'h0000AAAA);

            // GPIO IRQ_EN register (new)
            ahb_write(32'h10000008, 32'h000000FF);
            ahb_read(32'h10000008, rd_val);
            check("GPIO_IRQ_EN write/read", rd_val, 32'h000000FF);

            // GPIO IRQ_STAT register (new)
            ahb_read(32'h1000000C, rd_val);
            check("GPIO_IRQ_STAT initial", rd_val, 32'h00000000);
        end

        begin : timer_test
            ahb_write(32'h10004000, 32'd200);
            ahb_read(32'h10004000, rd_val);
            check("Timer_EXPR write/read", rd_val, 32'd200);

            ahb_write(32'h10004004, 32'h00000003);
            ahb_read(32'h10004004, rd_val);
            check("Timer_CTRL write/read", rd_val, 32'h00000003);

            ahb_read(32'h10004008, rd_val);
            check("Timer_IRQ initial", rd_val[0], 1'b0);
        end

        begin : uart_test
            ahb_write(32'h10008000, 32'h00000003);
            ahb_read(32'h10008000, rd_val);
            check("UART_CTRL write/read", rd_val, 32'h00000003);

            ahb_read(32'h10008004, rd_val);
            check("UART_STATUS read", rd_val[5:2], 4'b0100); // TX empty, RX empty

            // UART BAUD register (new)
            ahb_write(32'h10008010, 32'd868);
            ahb_read(32'h10008010, rd_val);
            check("UART_BAUD write/read", rd_val, 32'd868);

            // UART IRQ_STAT register (new)
            ahb_read(32'h10008014, rd_val);
            check("UART_IRQ_STAT initial", rd_val, 32'h00000000);
        end

        begin : spi_test
            ahb_write(32'h1000C000, 32'h0000000F);
            ahb_read(32'h1000C000, rd_val);
            check("SPI_CTRL write/read", rd_val, 32'h0000000F);

            ahb_write(32'h1000C004, 32'h000000AB);
            ahb_read(32'h1000C004, rd_val);
            check("SPI_DATA write/read", rd_val, 32'h000000AB);

            ahb_read(32'h1000C008, rd_val);
            check("SPI_STATUS read", rd_val[1:0], 2'b00); // not busy, no irq pending
        end

        $display("========================================");
        $display("APB peripherals test summary");
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
