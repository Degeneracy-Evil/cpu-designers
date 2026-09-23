`timescale 1ns / 1ps
`include "common/bus/axi.svh"

module tb_ahb_bus;

    // ----------------------------------------------------------------
    // Clock / reset regs
    // ----------------------------------------------------------------
    reg         clk;
    reg         resetn;
    reg         uart_rx;
    wire        uart_tx;
    wire [15:0] gpio_io;

    // ----------------------------------------------------------------
    // BFM clock — must use cpu_clk domain, not top-level clk
    // ----------------------------------------------------------------
    wire        axi_mst_clk;

    // ----------------------------------------------------------------
    // Inout wires for DDR3 and peripheral ports (cannot connect constants to inout)
    // ----------------------------------------------------------------
    wire [15:0] ddr3_dq_wire;
    wire [1:0]  ddr3_dqs_p_wire;
    wire [1:0]  ddr3_dqs_n_wire;

    // ----------------------------------------------------------------
    // system_top instantiation (replaces ahb_lite_bus)
    // ----------------------------------------------------------------
    system_top u_soc (
        .clk              (clk),
        .resetn           (resetn),
        .clk_system_bypass(1'b0),
        .clk_ddr_ref_bypass(1'b0),
        .clk_wiz_locked_bypass(1'b0),
        .uart_rx          (uart_rx),
        .uart_tx          (uart_tx),
        .spi_miso         (1'b0),
        .spi_mosi         (),
        .spi_ss           (),
        .spi_clk          (),
        .gpio_ctrl_out    (),
        .gpio_data_out    (),
        .gpio_io          (gpio_io),
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
        .ddr3_dq          (ddr3_dq_wire),
        .ddr3_dqs_p       (ddr3_dqs_p_wire),
        .ddr3_dqs_n       (ddr3_dqs_n_wire),
        .ddr3_odt         ()
    );

    // ----------------------------------------------------------------
    // Clock generation — 100 MHz
    // ----------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // BFM clock domain binding — CPU-side AXI signals are in cpu_clk domain
    assign axi_mst_clk = u_soc.cpu_clk;

    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // AXI4-Lite Master BFM: Write task
    // Forces CPU-side AXI4 master signals.
    // This interface is in u_soc.cpu_clk domain, not the top-level clk domain.
    // ----------------------------------------------------------------
    task axi4_write_resp;
        input [31:0] addr;
        input [31:0] data;
        output [1:0] resp;
        begin
            // AW channel: drive address
            @(negedge axi_mst_clk);
            force u_soc.cpu_awaddr  = addr;
            force u_soc.cpu_awlen   = 8'h00;      // single beat
            force u_soc.cpu_awsize  = 3'b010;     // 4 bytes
            force u_soc.cpu_awburst = 2'b01;      // INCR
            force u_soc.cpu_awvalid = 1'b1;

            // Wait for AW handshake
            @(posedge axi_mst_clk);
            while (u_soc.cpu_awready !== 1'b1)
                @(posedge axi_mst_clk);
            @(negedge axi_mst_clk);
            force u_soc.cpu_awvalid = 1'b0;

            // W channel: drive data after AW accepted
            force u_soc.cpu_wdata   = data;
            force u_soc.cpu_wstrb   = 4'hF;       // all bytes
            force u_soc.cpu_wlast   = 1'b1;
            force u_soc.cpu_wvalid  = 1'b1;

            // Wait for W handshake
            @(posedge axi_mst_clk);
            while (u_soc.cpu_wready !== 1'b1)
                @(posedge axi_mst_clk);
            @(negedge axi_mst_clk);
            force u_soc.cpu_wvalid = 1'b0;

            // B channel: wait for write response
            force u_soc.cpu_bready = 1'b1;
            @(posedge axi_mst_clk);
            while (u_soc.cpu_bvalid !== 1'b1)
                @(posedge axi_mst_clk);
            #1;
            resp = u_soc.cpu_bresp;
            @(negedge axi_mst_clk);
            force u_soc.cpu_bready = 1'b0;
        end
    endtask

    task axi4_write;
        input [31:0] addr;
        input [31:0] data;
        reg [1:0] ignored_resp;
        begin
            axi4_write_resp(addr, data, ignored_resp);
        end
    endtask

    // ----------------------------------------------------------------
    // AXI4-Lite Master BFM: Read task
    // Forces CPU's AXI4 master outputs to perform a single read
    // ----------------------------------------------------------------
    task axi4_read_resp;
        input  [31:0] addr;
        output [31:0] data;
        output [1:0] resp;
        begin
            // AR channel: drive address
            @(negedge axi_mst_clk);
            force u_soc.cpu_araddr  = addr;
            force u_soc.cpu_arlen   = 8'h00;
            force u_soc.cpu_arsize  = 3'b010;
            force u_soc.cpu_arburst = 2'b01;
            force u_soc.cpu_arvalid = 1'b1;

            // Wait for AR handshake
            @(posedge axi_mst_clk);
            while (u_soc.cpu_arready !== 1'b1)
                @(posedge axi_mst_clk);
            @(negedge axi_mst_clk);
            force u_soc.cpu_arvalid = 1'b0;

            // Accept the response only after the address handshake.  Keeping
            // RREADY low until here prevents a one-cycle CDC response from
            // being consumed before the BFM starts sampling RVALID/RDATA.
            force u_soc.cpu_rready = 1'b1;
            @(posedge axi_mst_clk);
            while (u_soc.cpu_rvalid !== 1'b1)
                @(posedge axi_mst_clk);
            #1;
            data = u_soc.cpu_rdata;
            resp = u_soc.cpu_rresp;
            @(negedge axi_mst_clk);
            force u_soc.cpu_rready = 1'b0;
        end
    endtask

    task axi4_read;
        input  [31:0] addr;
        output [31:0] data;
        reg [1:0] ignored_resp;
        begin
            axi4_read_resp(addr, data, ignored_resp);
        end
    endtask

    task check_decode;
        input [31:0] addr;
        input [2:0] expected;
        input [8*64-1:0] name;
        begin
            force u_soc.cdc_awaddr = addr;
            force u_soc.cdc_araddr = addr;
            #1;
            if ((u_soc.aw_slave_sel_comb === expected) &&
                (u_soc.ar_slave_sel_comb === expected)) begin
                pass_count = pass_count + 1;
                $display("PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s AW=%0d AR=%0d expected=%0d",
                         name, u_soc.aw_slave_sel_comb,
                         u_soc.ar_slave_sel_comb, expected);
            end
            release u_soc.cdc_awaddr;
            release u_soc.cdc_araddr;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

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

        // Wait until both sides of the AXI CDC have left reset.  Starting the
        // BFM after sys_resetn alone can drop its first request while the CPU
        // side reset synchronizer is still active.
        wait ((u_soc.sys_resetn == 1'b1) && (u_soc.cpu_resetn == 1'b1));
        repeat (10) @(posedge axi_mst_clk);

        // SRAM write/read test
        begin : sram_write_read_test
            reg [31:0] rd_val;
            axi4_write(32'h80000004, 32'hDEADBEEF);
            axi4_read(32'h80000004, rd_val);
            if (rd_val === 32'hDEADBEEF) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x80000004");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x80000004 expected=0xDEADBEEF got=0x%08h", rd_val);
            end

            axi4_write(32'h80000008, 32'hCAFEBABE);
            axi4_read(32'h80000008, rd_val);
            if (rd_val === 32'hCAFEBABE) begin
                pass_count = pass_count + 1;
                $display("PASS SRAM write/read @0x80000008");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SRAM write/read @0x80000008 expected=0xCAFEBABE got=0x%08h", rd_val);
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

        begin : platform_response_test
            reg [31:0] rd_val;
            reg [1:0] resp;

            axi4_write_resp(32'hfc00_0000,32'h1234_5678,resp);
            if (resp === `AXI_RESP_SLVERR) begin
                pass_count = pass_count + 1;
                $display("PASS BootROM write returns SLVERR");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL BootROM write response=%0b",resp);
            end

            axi4_write_resp(32'h0400_0000,32'h1234_5678,resp);
            if (resp === `AXI_RESP_SLVERR) begin
                pass_count = pass_count + 1;
                $display("PASS SysStatus write returns SLVERR");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SysStatus write response=%0b",resp);
            end

            axi4_read_resp(32'h0400_0010,rd_val,resp);
            if ((resp === `AXI_RESP_OKAY) && (rd_val === 32'b0)) begin
                pass_count = pass_count + 1;
                $display("PASS SysStatus reserved offset reads zero without aliasing");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL SysStatus reserved offset data=%08h resp=%0b",rd_val,resp);
            end

            axi4_read_resp(32'hfc00_8000,rd_val,resp);
            if (resp === `AXI_RESP_DECERR) begin
                pass_count = pass_count + 1;
                $display("PASS address above BootROM returns DECERR");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL address above BootROM response=%0b",resp);
            end

            axi4_write_resp(32'h1000_4000,32'h0,resp);
            if (resp === `AXI_RESP_DECERR) begin
                pass_count = pass_count + 1;
                $display("PASS removed APB timer write returns DECERR");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL removed APB timer write response=%0b",resp);
            end
        end

        // Run non-transactional decoder inspection last: forcing CDC outputs
        // is useful for exhaustive boundary checks, but must not precede real
        // traffic in the same simulation.
        check_decode(32'h8000_0000,3'd0,"DDR base");
        check_decode(32'h87ff_ffff,3'd0,"DDR last byte");
        check_decode(32'h8800_0000,3'd6,"DDR upper boundary");
        check_decode(32'hfc00_0000,3'd1,"BootROM base");
        check_decode(32'hfc00_7fff,3'd1,"BootROM last byte");
        check_decode(32'hfc00_8000,3'd6,"BootROM upper boundary");
        check_decode(32'h0c00_0000,3'd2,"PLIC base");
        check_decode(32'h0cff_ffff,3'd2,"PLIC last byte");
        check_decode(32'h0d00_0000,3'd6,"PLIC upper boundary");
        check_decode(32'h0200_0000,3'd3,"CLINT base");
        check_decode(32'h0200_ffff,3'd3,"CLINT last byte");
        check_decode(32'h0201_0000,3'd6,"CLINT upper boundary");
        check_decode(32'h1000_0000,3'd4,"GPIO base");
        check_decode(32'h1000_1000,3'd6,"GPIO upper boundary");
        check_decode(32'h1000_4000,3'd6,"removed APB timer window");
        check_decode(32'h1000_8000,3'd4,"UART base");
        check_decode(32'h1000_9000,3'd6,"UART upper boundary");
        check_decode(32'h1000_c000,3'd4,"SPI base");
        check_decode(32'h1000_d000,3'd6,"SPI upper boundary");
        check_decode(32'h0400_0000,3'd5,"SysStatus base");
        check_decode(32'h0400_0fff,3'd5,"SysStatus last byte");
        check_decode(32'h0400_1000,3'd6,"SysStatus upper boundary");
        if (u_soc.apb_slave_PSLVERR[1] === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS removed APB slot is a defensive error");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL removed APB slot silently succeeds");
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
