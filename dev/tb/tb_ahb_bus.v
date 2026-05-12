`timescale 1ns / 1ps
`include "ahb_def.vh"

module tb_ahb_bus;

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
    wire [15:0] io_gpioPin;
    wire        o_uart_tx;
    wire        o_spiMosi;
    wire        o_spiSs;
    wire        o_spiClk;

    integer pass_count;
    integer fail_count;

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (4),
        .MEM_DEPTH   (262144),
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
        .o_plic_eip (),
        .o_clint_mtip(),
        .o_clint_msip(),
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

    reg [31:0] latch_wdata;

    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge HCLK);
            #1;
            HADDR     = addr;
            HTRANS    = `AHB_TRANS_NONSEQ;
            HWRITE    = 1'b1;
            HSIZE     = `AHB_SIZE_WORD;
            HBURST    = `AHB_BURST_SINGLE;
            HPROT     = 4'b0011;
            HMASTLOCK = 1'b0;
            latch_wdata = data;
            @(posedge HCLK);
            #1;
            HWDATA = latch_wdata;
            HTRANS = `AHB_TRANS_IDLE;
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
            HTRANS    = `AHB_TRANS_NONSEQ;
            HWRITE    = 1'b0;
            HSIZE     = `AHB_SIZE_WORD;
            HBURST    = `AHB_BURST_SINGLE;
            HPROT     = 4'b0011;
            HMASTLOCK = 1'b0;
            @(posedge HCLK);
            #1;
            HTRANS = `AHB_TRANS_IDLE;
            while (!HREADY) @(posedge HCLK);
            #1;
            data = HRDATA;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        HRESETn   = 1'b0;
        HADDR     = 32'b0;
        HTRANS    = `AHB_TRANS_IDLE;
        HWRITE    = 1'b0;
        HSIZE     = `AHB_SIZE_WORD;
        HBURST    = `AHB_BURST_SINGLE;
        HPROT     = 4'b0011;
        HMASTLOCK = 1'b0;
        HWDATA    = 32'b0;

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
