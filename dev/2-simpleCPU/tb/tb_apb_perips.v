`timescale 1ns / 1ps

module tb_apb_perips;

    reg         HCLK;
    reg         HRESETn;
    reg         req_valid;
    reg         req_write;
    reg  [31:0] req_addr;
    reg  [31:0] req_wdata;
    reg  [2:0]  req_size;
    reg  [2:0]  req_burst;
    reg  [3:0]  req_prot;
    reg         req_lock;

    wire        req_ready;
    wire        resp_valid;
    wire        resp_error;
    wire [31:0] resp_rdata;

    wire        o_timer_irq;
    wire [15:0] io_gpioPin;
    wire        o_uart_tx;
    wire        o_spiMosi;
    wire        o_spiSs;
    wire        o_spiClk;

    integer pass_count;
    integer fail_count;

    ahb_periph_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (4),
        .MEM_DEPTH   (262144),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (25)
    ) u_dut (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .req_valid  (req_valid),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .req_size   (req_size),
        .req_burst  (req_burst),
        .req_prot   (req_prot),
        .req_lock   (req_lock),
        .req_ready  (req_ready),
        .resp_valid (resp_valid),
        .resp_error (resp_error),
        .resp_rdata (resp_rdata),
        .o_timer_irq(o_timer_irq),
        .io_gpioPin (io_gpioPin),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (o_uart_tx),
        .o_spiMosi  (o_spiMosi),
        .i_spiMiso  (1'b0),
        .o_spiSs    (o_spiSs),
        .o_spiClk   (o_spiClk)
    );

    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge HCLK);
            while (!req_ready) @(posedge HCLK);
            req_valid = 1'b1;
            req_write = 1'b1;
            req_addr  = addr;
            req_wdata = data;
            req_size  = 3'b010;
            req_burst = 3'b000;
            req_prot  = 4'b0011;
            req_lock  = 1'b0;
            @(posedge HCLK);
            req_valid = 1'b0;
            while (!resp_valid) @(posedge HCLK);
        end
    endtask

    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge HCLK);
            while (!req_ready) @(posedge HCLK);
            req_valid = 1'b1;
            req_write = 1'b0;
            req_addr  = addr;
            req_wdata = 32'b0;
            req_size  = 3'b010;
            req_burst = 3'b000;
            req_prot  = 4'b0011;
            req_lock  = 1'b0;
            @(posedge HCLK);
            req_valid = 1'b0;
            while (!resp_valid) @(posedge HCLK);
            data = resp_rdata;
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
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr  = 32'b0;
        req_wdata = 32'b0;
        req_size  = 3'b010;
        req_burst = 3'b000;
        req_prot  = 4'b0011;
        req_lock  = 1'b0;

        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        repeat (2) @(posedge HCLK);

        begin : gpio_test
            ahb_write(32'h00100000, 32'h0000FFFF);
            ahb_read(32'h00100000, rd_val);
            check("GPIO_CTRL write/read", rd_val, 32'h0000FFFF);

            ahb_write(32'h00100004, 32'h0000AAAA);
            ahb_read(32'h00100004, rd_val);
            check("GPIO_DATA write/read", rd_val, 32'h0000AAAA);
        end

        begin : timer_test
            ahb_write(32'h00104000, 32'd200);
            ahb_read(32'h00104000, rd_val);
            check("Timer_EXPR write/read", rd_val, 32'd200);

            ahb_write(32'h00104004, 32'h00000003);
            ahb_read(32'h00104004, rd_val);
            check("Timer_CTRL write/read", rd_val, 32'h00000003);

            ahb_read(32'h00104008, rd_val);
            check("Timer_IRQ initial", rd_val[0], 1'b0);
        end

        begin : uart_test
            ahb_write(32'h00108000, 32'h00000003);
            ahb_read(32'h00108000, rd_val);
            check("UART_CTRL write/read", rd_val, 32'h00000003);

            ahb_read(32'h00108004, rd_val);
            check("UART_STATUS read", rd_val, 32'h00000000);
        end

        begin : spi_test
            ahb_write(32'h0010C000, 32'h0000000F);
            ahb_read(32'h0010C000, rd_val);
            check("SPI_CTRL write/read", rd_val, 32'h0000000F);

            ahb_write(32'h0010C004, 32'h000000AB);
            ahb_read(32'h0010C004, rd_val);
            check("SPI_DATA write/read", rd_val, 32'h000000AB);

            ahb_read(32'h0010C008, rd_val);
            check("SPI_STATUS read", rd_val, 32'h00000000);
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
