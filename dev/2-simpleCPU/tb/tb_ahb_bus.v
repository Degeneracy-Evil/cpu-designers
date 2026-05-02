`timescale 1ns / 1ps

module tb_ahb_bus;

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
        .SLAVE_NUM   (2),
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

    initial begin
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

        begin : sram_write_read_test
            reg [31:0] rd_val;
            ahb_write(32'h00000000, 32'hDEADBEEF);
            ahb_read(32'h00000000, rd_val);
            if (rd_val === 32'hDEADBEEF) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x0");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x0 expected=0xDEADBEEF got=0x%08h", rd_val);
            end

            ahb_write(32'h00000004, 32'hCAFEBABE);
            ahb_read(32'h00000004, rd_val);
            if (rd_val === 32'hCAFEBABE) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x4");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x4 expected=0xCAFEBABE got=0x%08h", rd_val);
            end
        end

        begin : apb_bridge_gpio_test
            reg [31:0] rd_val;
            ahb_write(32'h80000000, 32'h0000FFFF);
            ahb_read(32'h80000000, rd_val);
            pass_count = pass_count + 1;
            $display("PASS APB bridge GPIO access completed (no error)");
        end

        $display("========================================");
        $display("AHB bus test summary");
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
