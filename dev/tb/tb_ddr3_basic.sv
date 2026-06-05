/**
 * tb_ddr3_basic.sv — Basic DDR3 testbench: AHB write → read → compare.
 *
 * Instantiates:
 *   1. ddr3_bridge_wrapper  (AHB-Lite → AXI4 Bridge → MIG 7 Series)
 *   2. ddr3_model            (Micron DDR3 SDRAM behavioral model)
 *   3. clk_wiz_0             (Clocking Wizard for 200MHz ref clock)
 *
 * Test flow:
 *   1. Wait for MIG init_calib_complete
 *   2. Write 4 words to DDR3 via AHB-Lite at addresses 0x0000_0000–0x0000_000C
 *   3. Read them back
 *   4. Compare and report PASS/FAIL
 *
 * NOTE: This testbench uses SIM_BYPASS_INIT_CAL="FAST" for reasonable
 * simulation time. Full calibration takes ~50µs; FAST mode completes in ~2µs.
 */
`include "ahb_def.svh"
`timescale 1ns / 1ps

module tb_ddr3_basic;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter SYSCLK_PERIOD   = 10.0;   // 100MHz (10ns)
    parameter REFCLK_PERIOD  = 5.0;    // 200MHz (5ns)
    parameter RESET_PERIOD   = 200;    // 200ns reset
    parameter CALIB_TIMEOUT  = 100000; // 100µs max wait for calibration
    parameter NUM_TEST_WORDS = 4;

    // ========================================================================
    // Clock & Reset Generation
    // ========================================================================
    reg sys_clk_i;    // 100MHz system clock (MIG sys_clk_i)
    reg clk_ref_i;    // 200MHz DDR reference clock (MIG clk_ref_i)
    reg sys_rst;      // Active-high system reset

    initial sys_clk_i = 1'b0;
    always #(SYSCLK_PERIOD/2.0) sys_clk_i = ~sys_clk_i;

    initial clk_ref_i = 1'b0;
    always #(REFCLK_PERIOD/2.0) clk_ref_i = ~clk_ref_i;

    initial begin
        sys_rst = 1'b1;
        #(RESET_PERIOD);
        sys_rst = 1'b0;
    end

    // ========================================================================
    // AHB-Lite Signals (driven by testbench BFM)
    // ========================================================================
    reg         HSEL;
    reg  [31:0] HADDR;
    reg  [1:0]  HTRANS;
    reg         HWRITE;
    reg  [2:0]  HSIZE;
    reg  [2:0]  HBURST;
    reg  [3:0]  HPROT;
    reg  [31:0] HWDATA;
    wire        HREADYOUT;
    wire        HRESP;
    wire [31:0] HRDATA;

    // HREADY is the OR of all slave HREADYOUT signals.
    // In this testbench there's only one slave (DDR3), so HREADY = HREADYOUT.
    wire HREADY = HREADYOUT;

    // ========================================================================
    // DUT: ddr3_bridge_wrapper
    // ========================================================================
    wire        init_calib_complete;
    wire        ui_clk;
    wire        ui_clk_sync_rst;
    wire        mmcm_locked;
    wire        aresetn;

    wire [12:0] ddr3_addr;
    wire [2:0]  ddr3_ba;
    wire        ddr3_ras_n;
    wire        ddr3_cas_n;
    wire        ddr3_we_n;
    wire        ddr3_reset_n;
    wire [0:0]  ddr3_ck_p;
    wire [0:0]  ddr3_ck_n;
    wire [0:0]  ddr3_cke;
    wire [1:0]  ddr3_dm;
    wire [15:0] ddr3_dq;
    wire [1:0]  ddr3_dqs_p;
    wire [1:0]  ddr3_dqs_n;
    wire [0:0]  ddr3_odt;

    ddr3_bridge_wrapper u_dut (
        .HCLK                (ui_clk),           // AHB clock = MIG ui_clk (100MHz)
        .HRESETn             (aresetn),          // AHB reset = MIG aresetn (active-low)
        .HSEL                (HSEL),
        .HADDR               (HADDR),
        .HTRANS              (HTRANS),
        .HWRITE              (HWRITE),
        .HSIZE               (HSIZE),
        .HBURST              (HBURST),
        .HPROT               (HPROT),
        .HWDATA              (HWDATA),
        .HREADY              (HREADY),

        .HREADYOUT           (HREADYOUT),
        .HRESP               (HRESP),
        .HRDATA              (HRDATA),

        .mig_sys_clk_i       (sys_clk_i),
        .mig_clk_ref_i       (clk_ref_i),
        .mig_sys_rst         (sys_rst),

        .init_calib_complete (init_calib_complete),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .mmcm_locked         (mmcm_locked),
        .aresetn             (aresetn),

        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        // app outputs left unconnected
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),

        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_cke            (ddr3_cke),
        .ddr3_dm             (ddr3_dm),
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_odt            (ddr3_odt)
    );

    // ========================================================================
    // DDR3 SDRAM Behavioral Model (Micron)
    // ========================================================================
    // The ddr3_model port names match the MIG example testbench.
    // For x16 data width: DQ=16, DQS=2, DM=2

    ddr3_model u_ddr3_model (
        .rst_n   (ddr3_reset_n),
        .ck      (ddr3_ck_p[0]),
        .ck_n    (ddr3_ck_n[0]),
        .cke     (ddr3_cke[0]),
        .cs_n    (1'b0),
        .ras_n   (ddr3_ras_n),
        .cas_n   (ddr3_cas_n),
        .we_n    (ddr3_we_n),
        .dm_tdqs ({ddr3_dm[1], ddr3_dm[0]}),
        .ba      (ddr3_ba),
        .addr    (ddr3_addr),
        .dq      (ddr3_dq),
        .dqs     ({ddr3_dqs_p[1], ddr3_dqs_p[0]}),
        .dqs_n   ({ddr3_dqs_n[1], ddr3_dqs_n[0]}),
        .tdqs_n  (),
        .odt     (ddr3_odt[0])
    );

    // ========================================================================
    // AHB-Lite Bus Functional Model (BFM)
    // ========================================================================

    // Test data
    reg [31:0] write_data [0:NUM_TEST_WORDS-1];
    reg [31:0] read_data  [0:NUM_TEST_WORDS-1];
    integer    pass_count;
    integer    fail_count;

    // Initialize AHB bus to idle state
    task ahb_idle;
        begin
            HSEL   = 1'b0;
            HTRANS = `AHB_TRANS_IDLE;
            HADDR  = 32'b0;
            HWRITE = 1'b0;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;  // data, privileged
            HWDATA = 32'b0;
        end
    endtask

    // AHB-Lite single write: address phase + data phase
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Address phase: set up control signals
            @(posedge ui_clk);
            HSEL   = 1'b1;
            HTRANS = `AHB_TRANS_NONSEQ;
            HADDR  = addr;
            HWRITE = 1'b1;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;

            // Data phase: drive HWDATA on next clock
            @(posedge ui_clk);
            HWDATA = data;

            // Wait for slave to accept (HREADYOUT high)
            while (!HREADYOUT) begin
                @(posedge ui_clk);
            end

            // Return to idle
            ahb_idle();
            @(posedge ui_clk);
        end
    endtask

    // AHB-Lite single read: address phase, then capture HRDATA
    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Address phase
            @(posedge ui_clk);
            HSEL   = 1'b1;
            HTRANS = `AHB_TRANS_NONSEQ;
            HADDR  = addr;
            HWRITE = 1'b0;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;

            // Wait for valid data (HREADYOUT high)
            @(posedge ui_clk);
            while (!HREADYOUT) begin
                @(posedge ui_clk);
            end

            // Capture read data
            data = HRDATA;

            // Return to idle
            ahb_idle();
            @(posedge ui_clk);
        end
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    integer i;

    initial begin
        // Initialize bus
        ahb_idle();

        // Initialize test data
        write_data[0] = 32'hDEADBEEF;
        write_data[1] = 32'hCAFEBABE;
        write_data[2] = 32'h12345678;
        write_data[3] = 32'h87654321;
        pass_count = 0;
        fail_count = 0;

        // Wait for MIG calibration to complete
        $display("[TB] Waiting for MIG init_calib_complete...");
        fork
            begin
                : calib_wait
                wait (init_calib_complete === 1'b1);
                $display("[TB] MIG calibration complete at time %0t", $time);
            end
            begin
                : calib_timeout
                #(CALIB_TIMEOUT);
                $display("[TB] ERROR: MIG calibration timeout at %0t", $time);
                $finish;
            end
        join_any
        disable fork;

        // Additional settle time after calibration
        repeat(100) @(posedge ui_clk);

        // ---------------------------------------------------------------
        // Phase 1: Write 4 words to DDR3
        // ---------------------------------------------------------------
        $display("[TB] === WRITE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            $display("[TB] Writing addr=0x%08H data=0x%08H", i*4, write_data[i]);
            ahb_write(i*4, write_data[i]);
        end

        // Allow time for writes to complete through Bridge + MIG pipeline
        repeat(50) @(posedge ui_clk);

        // ---------------------------------------------------------------
        // Phase 2: Read 4 words back from DDR3
        // ---------------------------------------------------------------
        $display("[TB] === READ PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            ahb_read(i*4, read_data[i]);
            $display("[TB] Reading addr=0x%08H data=0x%08H (expected=0x%08H)",
                     i*4, read_data[i], write_data[i]);
        end

        // ---------------------------------------------------------------
        // Phase 3: Compare
        // ---------------------------------------------------------------
        $display("[TB] === COMPARE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            if (read_data[i] === write_data[i]) begin
                $display("[TB] PASS: addr=0x%08H data=0x%08H", i*4, read_data[i]);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB] FAIL: addr=0x%08H expected=0x%08H got=0x%08H",
                         i*4, write_data[i], read_data[i]);
                fail_count = fail_count + 1;
            end
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("[TB] ========================================");
        $display("[TB] RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("[TB] *** ALL TESTS PASSED ***");
        else
            $display("[TB] *** SOME TESTS FAILED ***");
        $display("[TB] ========================================");

        #(1000);
        $finish;
    end

    // ========================================================================
    // Timeout watchdog
    // ========================================================================
    initial begin
        #(500000); // 500µs absolute timeout
        $display("[TB] ERROR: Simulation timeout at %0t", $time);
        $finish;
    end

    // ========================================================================
    // Waveform dump (for Vivado XSim)
    // ========================================================================
    initial begin
        $dumpfile("tb_ddr3_basic.vcd");
        $dumpvars(0, tb_ddr3_basic);
    end

endmodule
