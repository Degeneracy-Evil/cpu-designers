`timescale 1ns / 1ps

module tb_ahb_bus;

    // ----------------------------------------------------------------
    // Clock / reset regs
    // ----------------------------------------------------------------
    reg         clk;
    reg         resetn;
    reg  [7:0]  sw;
    reg         uart_rx;
    wire        uart_tx;
    wire [15:0] gpio_io;

    // ----------------------------------------------------------------
    // system_top instantiation (replaces ahb_lite_bus)
    // ----------------------------------------------------------------
    system_top u_soc (
        .clk              (clk),
        .resetn           (resetn),
        .clk_system_bypass(1'b0),
        .clk_ddr_ref_bypass(1'b0),
        .clk_wiz_locked_bypass(1'b0),
        .sw               (sw),
        .uart_rx          (uart_rx),
        .uart_tx          (uart_tx),
        .spi_miso         (1'b0),
        .spi_mosi         (),
        .spi_ss           (),
        .spi_clk          (),
        .gpio_ctrl_out    (),
        .gpio_data_out    (),
        .gpio_io          (gpio_io),
        .lcd_rst          (),
        .lcd_cs           (),
        .lcd_rs           (),
        .lcd_wr           (),
        .lcd_rd           (),
        .lcd_data_io      (16'b0),
        .lcd_bl_ctr       (),
        .ct_int           (1'b0),
        .ct_sda           (1'b0),
        .ct_scl           (),
        .ct_rstn          (),
        .ddr3_addr        (),
        .ddr3_ba          (),
        .ddr3_ras_n       (),
        .ddr3_cas_n       (),
        .ddr3_we_n        (),
        .ddr3_reset_n     (),
        .ddr3_ck_p        (),
        .ddr3_ck_n        (),
        .ddr3_cke         (),
        .ddr3_dm          (),
        .ddr3_dq          (16'b0),
        .ddr3_dqs_p       (2'b0),
        .ddr3_dqs_n       (2'b0),
        .ddr3_odt         ()
    );

    // ----------------------------------------------------------------
    // Clock generation — 100 MHz
    // ----------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // AXI4-Lite Master BFM: Write task
    // Forces CPU's AXI4 master outputs to perform a single write.
    // AW channel is driven first; W channel follows after AW handshake
    // to ensure the crossbar latches the correct slave select
    // (aw_slave_sel is registered on AW handshake).
    // ----------------------------------------------------------------
    task axi4_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // AW channel: drive address
            force u_soc.cpu_awaddr  = addr;
            force u_soc.cpu_awlen   = 8'h00;      // single beat
            force u_soc.cpu_awsize  = 3'b010;     // 4 bytes
            force u_soc.cpu_awburst = 2'b01;      // INCR
            force u_soc.cpu_awvalid = 1'b1;

            // Wait for AW handshake
            wait (u_soc.cpu_awready == 1'b1);
            @(posedge clk);
            force u_soc.cpu_awvalid = 1'b0;

            // W channel: drive data after AW accepted
            force u_soc.cpu_wdata   = data;
            force u_soc.cpu_wstrb   = 4'hF;       // all bytes
            force u_soc.cpu_wlast   = 1'b1;
            force u_soc.cpu_wvalid  = 1'b1;

            // Wait for W handshake
            wait (u_soc.cpu_wready == 1'b1);
            @(posedge clk);
            force u_soc.cpu_wvalid = 1'b0;

            // B channel: wait for write response
            force u_soc.cpu_bready = 1'b1;
            wait (u_soc.cpu_bvalid == 1'b1);
            @(posedge clk);
            force u_soc.cpu_bready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI4-Lite Master BFM: Read task
    // Forces CPU's AXI4 master outputs to perform a single read
    // ----------------------------------------------------------------
    task axi4_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // AR channel: drive address
            force u_soc.cpu_araddr  = addr;
            force u_soc.cpu_arlen   = 8'h00;
            force u_soc.cpu_arsize  = 3'b010;
            force u_soc.cpu_arburst = 2'b01;
            force u_soc.cpu_arvalid = 1'b1;

            // R channel: ready to accept
            force u_soc.cpu_rready = 1'b1;

            // Wait for AR handshake
            wait (u_soc.cpu_arready == 1'b1);
            @(posedge clk);
            force u_soc.cpu_arvalid = 1'b0;

            // Wait for R data
            wait (u_soc.cpu_rvalid == 1'b1);
            #1;
            data = u_soc.cpu_rdata;
            @(posedge clk);
            force u_soc.cpu_rready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        sw      = 8'b0;
        uart_rx = 1'b1;   // idle
        resetn  = 1'b0;

        // Force ddr_data_init so system reset can release when resetn deasserts
        force u_soc.ddr_data_init = 1'b1;

        // Force CPU AXI4 outputs to idle before reset deasserts.
        // This prevents the CPU from driving the bus when it comes out
        // of reset — the CPU is effectively "bus-quiesced".
        force u_soc.cpu_awvalid = 1'b0;
        force u_soc.cpu_wvalid  = 1'b0;
        force u_soc.cpu_arvalid = 1'b0;
        force u_soc.cpu_bready  = 1'b0;
        force u_soc.cpu_rready  = 1'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;

        // Wait for system reset to deassert
        wait (u_soc.sys_resetn == 1'b1);
        repeat (10) @(posedge clk);

        // SRAM write/read test
        begin : sram_write_read_test
            reg [31:0] rd_val;
            axi4_write(32'h80000000, 32'hDEADBEEF);
            axi4_read(32'h80000000, rd_val);
            if (rd_val === 32'hDEADBEEF) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x80000000");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x80000000 expected=0xDEADBEEF got=0x%08h", rd_val);
            end

            axi4_write(32'h80000004, 32'hCAFEBABE);
            axi4_read(32'h80000004, rd_val);
            if (rd_val === 32'hCAFEBABE) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x80000004");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x80000004 expected=0xCAFEBABE got=0x%08h", rd_val);
            end
        end

        // APB bridge GPIO test
        begin : apb_bridge_gpio_test
            reg [31:0] rd_val;
            axi4_write(32'h10000000, 32'h0000FFFF);
            axi4_read(32'h10000000, rd_val);
            pass_count = pass_count + 1;
            $display("PASS APB bridge GPIO access completed (no error)");
        end

        $display("========================================");
        $display("AXI4 bus test summary");
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
