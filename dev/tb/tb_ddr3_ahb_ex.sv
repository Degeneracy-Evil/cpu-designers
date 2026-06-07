/**
 * tb_ddr3_ahb_ex.sv — Phase 2: AHB-Lite -> AXI4 Bridge -> MIG -> DDR3 verification.
 *
 * Instantiates ddr3_bridge_wrapper and drives its AHB-Lite interface with
 * a BFM (write then read back). Uses WireDelay for DQ/DQS bi-directional
 * bus modeling, matching the Xilinx example testbench pattern.
 *
 * Test flow:
 *   1. Wait for MIG init_calib_complete
 *   2. Write 4 words via AHB-Lite at addresses 0x00–0x0C
 *   3. Read them back
 *   4. Compare and report PASS/FAIL
 *
 * Compile note: Set SIM_BYPASS_INIT_CAL="FAST" for reasonable sim time.
 */
`include "ahb_def.svh"
`timescale 1ps/100fs

module tb_ddr3_ahb_ex;

    // ========================================================================
    // Parameters (matching Xilinx MIG example)
    // ========================================================================
    parameter SIMULATION            = "TRUE";
    parameter SIM_BYPASS_INIT_CAL   = "FAST";
    parameter DQ_WIDTH              = 16;
    parameter DQS_WIDTH             = 2;
    parameter DQS_CNT_WIDTH         = 1;
    parameter DM_WIDTH              = 2;
    parameter DRAM_WIDTH            = 8;
    parameter ROW_WIDTH             = 13;
    parameter COL_WIDTH             = 10;
    parameter ADDR_WIDTH            = 27;
    parameter BANK_WIDTH            = 3;
    parameter CS_WIDTH              = 1;
    parameter ODT_WIDTH             = 1;
    parameter CK_WIDTH              = 1;
    parameter RANKS                 = 1;
    parameter ECC                   = "OFF";
    parameter BURST_MODE            = "8";
    parameter CA_MIRROR             = "OFF";
    parameter nCK_PER_CLK           = 4;
    parameter CLKIN_PERIOD          = 10000;    // ps (10ns = 100MHz)
    parameter tCK                   = 2500;     // ps
    parameter REFCLK_FREQ          = 200.0;    // MHz
    parameter TCQ                   = 100;
    parameter RST_ACT_LOW           = 1;
    parameter NUM_TEST_WORDS        = 4;

    // ========================================================================
    // Local parameters
    // ========================================================================
    localparam real TPROP_DQS          = 0.00;
    localparam real TPROP_DQS_RD       = 0.00;
    localparam real TPROP_PCB_CTRL     = 0.00;
    localparam real TPROP_PCB_DATA     = 0.00;
    localparam real TPROP_PCB_DATA_RD  = 0.00;
    localparam MEMORY_WIDTH            = 16;
    localparam NUM_COMP                = DQ_WIDTH / MEMORY_WIDTH;
    localparam real REFCLK_PERIOD_L    = (1000000.0 / (2 * REFCLK_FREQ));
    localparam RESET_PERIOD            = 200000;       // 200ns in ps
    localparam real SYSCLK_PERIOD      = tCK;
    localparam CALIB_TIMEOUT           = 500000000;    // 500us in ps (full calib needs ~200-400us)
    localparam SIM_TIMEOUT             = 1000000000;   // 1000us in ps

    // ========================================================================
    // Clock & Reset Generation
    // ========================================================================
    reg  sys_rst_n;
    wire sys_rst;
    reg  sys_clk_i;
    reg  clk_ref_i;

    initial sys_rst_n = 1'b0;
    initial begin
        #RESET_PERIOD
        sys_rst_n = 1'b1;
    end
    assign sys_rst = RST_ACT_LOW ? sys_rst_n : ~sys_rst_n;

    initial sys_clk_i = 1'b0;
    always sys_clk_i = #(CLKIN_PERIOD / 2.0) ~sys_clk_i;

    initial clk_ref_i = 1'b0;
    always clk_ref_i = #REFCLK_PERIOD_L ~clk_ref_i;

    // ========================================================================
    // AHB-Lite Signals (driven by BFM)
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

    // Single slave: HREADY = HREADYOUT
    wire HREADY = HREADYOUT;

    // ========================================================================
    // DUT Status Wires
    // ========================================================================
    wire init_calib_complete;
    wire ui_clk;
    wire ui_clk_sync_rst;
    wire mmcm_locked;
    // BUG-45 fix: aresetn is an INPUT to MIG, must be driven by testbench.
    // Initialize to 0 (in reset), then release after calibration.
    reg  aresetn = 1'b0;

    // ========================================================================
    // DDR3 FPGA-side Wires (from wrapper)
    // ========================================================================
    wire [DQ_WIDTH-1:0]    ddr3_dq_fpga;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_p_fpga;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_n_fpga;
    wire [ROW_WIDTH-1:0]   ddr3_addr_fpga;
    wire [BANK_WIDTH-1:0]  ddr3_ba_fpga;
    wire                   ddr3_ras_n_fpga;
    wire                   ddr3_cas_n_fpga;
    wire                   ddr3_we_n_fpga;
    wire                   ddr3_reset_n;
    wire [CK_WIDTH-1:0]    ddr3_ck_p_fpga;
    wire [CK_WIDTH-1:0]    ddr3_ck_n_fpga;
    wire [CK_WIDTH-1:0]    ddr3_cke_fpga;
    wire [DM_WIDTH-1:0]    ddr3_dm_fpga;
    wire [ODT_WIDTH-1:0]   ddr3_odt_fpga;

    // ========================================================================
    // DDR3 SDRAM-side Wires (to ddr3_model)
    // ========================================================================
    wire [DQ_WIDTH-1:0]    ddr3_dq_sdram;
    reg  [ROW_WIDTH-1:0]   ddr3_addr_sdram [0:CS_WIDTH-1];
    reg  [BANK_WIDTH-1:0]  ddr3_ba_sdram [0:CS_WIDTH-1];
    reg                    ddr3_ras_n_sdram;
    reg                    ddr3_cas_n_sdram;
    reg                    ddr3_we_n_sdram;
    wire [(CS_WIDTH*1)-1:0] ddr3_cs_n_sdram;
    wire [ODT_WIDTH-1:0]   ddr3_odt_sdram;
    reg  [CK_WIDTH-1:0]    ddr3_cke_sdram;
    wire [DM_WIDTH-1:0]    ddr3_dm_sdram;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_p_sdram;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_n_sdram;
    reg  [CK_WIDTH-1:0]    ddr3_ck_p_sdram;
    reg  [CK_WIDTH-1:0]    ddr3_ck_n_sdram;
    reg  [DM_WIDTH-1:0]    ddr3_dm_sdram_tmp;
    reg  [ODT_WIDTH-1:0]   ddr3_odt_sdram_tmp;

    // ========================================================================
    // DUT: ddr3_bridge_wrapper
    // ========================================================================
    ddr3_bridge_wrapper u_dut (
        // AHB-Lite Slave Interface
        .HCLK                (ui_clk),
        .HRESETn             (aresetn),
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
        // MIG Clock/Reset
        .mig_sys_clk_i       (sys_clk_i),
        .mig_clk_ref_i       (clk_ref_i),
        .mig_sys_rst         (sys_rst),
        // MIG Status
        .init_calib_complete (init_calib_complete),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .mmcm_locked         (mmcm_locked),
        .aresetn             (aresetn),
        // MIG Application Interface (tie off)
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),
        // DDR3 SDRAM Pins
        .ddr3_addr           (ddr3_addr_fpga),
        .ddr3_ba             (ddr3_ba_fpga),
        .ddr3_ras_n          (ddr3_ras_n_fpga),
        .ddr3_cas_n          (ddr3_cas_n_fpga),
        .ddr3_we_n           (ddr3_we_n_fpga),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_ck_p           (ddr3_ck_p_fpga),
        .ddr3_ck_n           (ddr3_ck_n_fpga),
        .ddr3_cke            (ddr3_cke_fpga),
        .ddr3_dm             (ddr3_dm_fpga),
        .ddr3_dq             (ddr3_dq_fpga),
        .ddr3_dqs_p          (ddr3_dqs_p_fpga),
        .ddr3_dqs_n          (ddr3_dqs_n_fpga),
        .ddr3_odt            (ddr3_odt_fpga)
    );

    // ========================================================================
    // Control Signal Delays (FPGA -> SDRAM)
    // ========================================================================
    always @(*) begin
        ddr3_ck_p_sdram    <= #(TPROP_PCB_CTRL) ddr3_ck_p_fpga;
        ddr3_ck_n_sdram    <= #(TPROP_PCB_CTRL) ddr3_ck_n_fpga;
        ddr3_addr_sdram[0] <= #(TPROP_PCB_CTRL) ddr3_addr_fpga;
        ddr3_ba_sdram[0]   <= #(TPROP_PCB_CTRL) ddr3_ba_fpga;
        ddr3_ras_n_sdram   <= #(TPROP_PCB_CTRL) ddr3_ras_n_fpga;
        ddr3_cas_n_sdram   <= #(TPROP_PCB_CTRL) ddr3_cas_n_fpga;
        ddr3_we_n_sdram    <= #(TPROP_PCB_CTRL) ddr3_we_n_fpga;
        ddr3_cke_sdram     <= #(TPROP_PCB_CTRL) ddr3_cke_fpga;
    end

    assign ddr3_cs_n_sdram = {(CS_WIDTH * 1){1'b0}};

    always @(*) ddr3_dm_sdram_tmp <= #(TPROP_PCB_DATA) ddr3_dm_fpga;
    assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;

    always @(*) ddr3_odt_sdram_tmp <= #(TPROP_PCB_CTRL) ddr3_odt_fpga;
    assign ddr3_odt_sdram = ddr3_odt_sdram_tmp;

    // ========================================================================
    // WireDelay for DQ[15:0] (bi-directional)
    // ========================================================================
    genvar dqwd;
    generate
        for (dqwd = 1; dqwd < DQ_WIDTH; dqwd = dqwd + 1) begin : dq_delay
            WireDelay #(
                .Delay_g    (TPROP_PCB_DATA),
                .Delay_rd   (TPROP_PCB_DATA_RD),
                .ERR_INSERT ("OFF")
            ) u_delay_dq (
                .A             (ddr3_dq_fpga[dqwd]),
                .B             (ddr3_dq_sdram[dqwd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );
        end
        WireDelay #(
            .Delay_g    (TPROP_PCB_DATA),
            .Delay_rd   (TPROP_PCB_DATA_RD),
            .ERR_INSERT ("OFF")
        ) u_delay_dq_0 (
            .A             (ddr3_dq_fpga[0]),
            .B             (ddr3_dq_sdram[0]),
            .reset         (sys_rst_n),
            .phy_init_done (init_calib_complete)
        );
    endgenerate

    // ========================================================================
    // WireDelay for DQS_p/n[1:0] (bi-directional)
    // ========================================================================
    genvar dqswd;
    generate
        for (dqswd = 0; dqswd < DQS_WIDTH; dqswd = dqswd + 1) begin : dqs_delay
            WireDelay #(
                .Delay_g    (TPROP_DQS),
                .Delay_rd   (TPROP_DQS_RD),
                .ERR_INSERT ("OFF")
            ) u_delay_dqs_p (
                .A             (ddr3_dqs_p_fpga[dqswd]),
                .B             (ddr3_dqs_p_sdram[dqswd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );
            WireDelay #(
                .Delay_g    (TPROP_DQS),
                .Delay_rd   (TPROP_DQS_RD),
                .ERR_INSERT ("OFF")
            ) u_delay_dqs_n (
                .A             (ddr3_dqs_n_fpga[dqswd]),
                .B             (ddr3_dqs_n_sdram[dqswd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );
        end
    endgenerate

    // ========================================================================
    // DDR3 SDRAM Behavioral Model (Micron) — x16, single rank
    // ========================================================================
    ddr3_model u_comp_ddr3 (
        .rst_n   (ddr3_reset_n),
        .ck      (ddr3_ck_p_sdram),
        .ck_n    (ddr3_ck_n_sdram),
        .cke     (ddr3_cke_sdram[0]),
        .cs_n    (ddr3_cs_n_sdram[0]),
        .ras_n   (ddr3_ras_n_sdram),
        .cas_n   (ddr3_cas_n_sdram),
        .we_n    (ddr3_we_n_sdram),
        .dm_tdqs (ddr3_dm_sdram[1:0]),
        .ba      (ddr3_ba_sdram[0]),
        .addr    (ddr3_addr_sdram[0]),
        .dq      (ddr3_dq_sdram[15:0]),
        .dqs     (ddr3_dqs_p_sdram[1:0]),
        .dqs_n   (ddr3_dqs_n_sdram[1:0]),
        .tdqs_n  (),
        .odt     (ddr3_odt_sdram[0])
    );

    // ========================================================================
    // AHB-Lite Bus Functional Model (BFM)
    // ========================================================================

    // Initialize AHB bus to idle state
    task ahb_idle;
        begin
            HSEL   = 1'b0;
            HTRANS = `AHB_TRANS_IDLE;
            HADDR  = 32'b0;
            HWRITE = 1'b0;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;   // data, privileged
            HWDATA = 32'b0;
        end
    endtask

    // AHB-Lite single write: address phase + data phase
    // Per AHB-Lite protocol: HWDATA is valid in the data phase (cycle after address phase).
    // The bridge samples HWDATA on the clock edge when HREADYOUT=1 (data phase completion).
    // We must hold HWDATA stable until that clock edge, then wait one more edge
    // before calling ahb_idle() to avoid zeroing HWDATA before the bridge samples it.
    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Address phase: set up control signals
            @(posedge ui_clk);
            #1;
            HSEL   = 1'b1;
            HTRANS = `AHB_TRANS_NONSEQ;
            HADDR  = addr;
            HWRITE = 1'b1;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;

            // Data phase: drive HWDATA on next clock
            @(posedge ui_clk);
            #1;
            HWDATA = data;

            // Wait for slave to accept (HREADYOUT high)
            // HWDATA must remain stable until the bridge samples it.
            while (!HREADYOUT) begin
                @(posedge ui_clk);
            end

            // CRITICAL: Hold HWDATA stable for one more clock edge.
            // The bridge samples HWDATA on the posedge where HREADYOUT=1.
            // If we call ahb_idle() immediately, HWDATA gets zeroed before
            // the bridge's register samples it on the next posedge.
            @(posedge ui_clk);

            // Now safe to return to idle
            ahb_idle();
            @(posedge ui_clk);
        end
    endtask

    // AHB-Lite single read: address phase, then capture HRDATA
    // NOTE: The AHB-AXI bridge has a 1-cycle pipeline delay — HRDATA
    // returns the data for the PREVIOUS transaction on the first HREADYOUT.
    // We need to wait for the SECOND HREADYOUT to get the correct data.
    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Address phase
            @(posedge ui_clk);
            #1;
            HSEL   = 1'b1;
            HTRANS = `AHB_TRANS_NONSEQ;
            HADDR  = addr;
            HWRITE = 1'b0;
            HSIZE  = `AHB_SIZE_WORD;
            HBURST = `AHB_BURST_SINGLE;
            HPROT  = 4'b0011;

            // Wait for first HREADYOUT (bridge accepts address phase)
            @(posedge ui_clk);
            while (!HREADYOUT) begin
                @(posedge ui_clk);
            end

            // Wait for second HREADYOUT (bridge returns data)
            // The bridge has a 1-cycle pipeline — the first HREADYOUT
            // acknowledges the address, the second returns the data.
            @(posedge ui_clk);
            while (!HREADYOUT) begin
                @(posedge ui_clk);
            end

            // Capture read data
            data = HRDATA;

            // Hold bus stable for one more edge before returning to idle
            @(posedge ui_clk);

            // Return to idle
            ahb_idle();
            @(posedge ui_clk);
        end
    endtask

    // ========================================================================
    // Test Data & Counters
    // ========================================================================
    reg  [31:0] write_data [0:NUM_TEST_WORDS-1];
    reg  [31:0] read_data  [0:NUM_TEST_WORDS-1];
    integer     pass_count;
    integer     fail_count;
    integer     i;

    // ========================================================================
    // BUG-45 fix: Drive aresetn (MIG AXI reset input)
    // Release after MIG calibration completes. aresetn is active-low.
    // ========================================================================
    always @(posedge ui_clk) begin
        if (init_calib_complete && mmcm_locked)
            aresetn <= 1'b1;
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
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

        // Wait for MIG calibration
        $display("[TB_AHB_EX] Waiting for MIG init_calib_complete...");
        $display("[TB_AHB_EX] DBG: ui_clk=%b aresetn=%b init_calib=%b mmcm_locked=%b",
                 ui_clk, aresetn, init_calib_complete, mmcm_locked);
        fork
            begin : calib_wait
                wait (init_calib_complete === 1'b1);
                $display("[TB_AHB_EX] Calibration complete at time %0t", $time);
            end
            begin : calib_timeout
                #CALIB_TIMEOUT;
                $display("[TB_AHB_EX] ERROR: Calibration timeout at %0t", $time);
                $finish;
            end
        join_any
        disable fork;

        // Settle time after calibration
        repeat(100) @(posedge ui_clk);
        $display("[TB_AHB_EX] DBG after settle: aresetn=%b HROUT=%b HRDATA=0x%08H ARV=%b RR=%b",
                 aresetn, HREADYOUT, HRDATA,
                 u_dut.bridge_m_axi_arvalid, u_dut.bridge_m_axi_rready);

        // ---------------------------------------------------------------
        // Write Phase (with AXI W channel debug)
        // ---------------------------------------------------------------
        $display("[TB_AHB_EX] === WRITE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            $display("[TB_AHB_EX] AHB write addr=0x%08H data=0x%08H",
                     i * 4, write_data[i]);
            ahb_write(i * 4, write_data[i]);
            // Wait for AXI B channel response (write commit) before next write
            // This ensures MIG has fully processed the write before we start the next one
            repeat(20) @(posedge ui_clk);
            // Debug: snapshot AXI AW/W/B channel after each write
            $display("[TB_AHB_EX] DBG AXI after write[%0d]: AWV=%b AWR=%b AWADDR=0x%08H WV=%b WR=%b WDATA=0x%08H WSTRB=0x%H BV=%b BR=%b",
                     i, u_dut.bridge_m_axi_awvalid, u_dut.bridge_m_axi_awready,
                     u_dut.bridge_m_axi_awaddr,
                     u_dut.bridge_m_axi_wvalid, u_dut.bridge_m_axi_wready,
                     u_dut.bridge_m_axi_wdata, u_dut.bridge_m_axi_wstrb,
                     u_dut.bridge_m_axi_bvalid, u_dut.bridge_m_axi_bready);
        end

        // Allow time for writes to propagate through Bridge + MIG pipeline
        repeat(50) @(posedge ui_clk);

        // ---------------------------------------------------------------
        // Read Phase (with AXI debug monitoring)
        // ---------------------------------------------------------------
        $display("[TB_AHB_EX] === READ PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            // Debug: snapshot AXI AR/R channel BEFORE read
            $display("[TB_AHB_EX] DBG before read[%0d]: ARV=%b ARR=%b ARADDR=0x%08H RV=%b RR=%b HROUT=%b HRDATA=0x%08H",
                     i, u_dut.bridge_m_axi_arvalid, u_dut.bridge_m_axi_arready,
                     u_dut.bridge_m_axi_araddr,
                     u_dut.bridge_m_axi_rvalid, u_dut.bridge_m_axi_rready,
                     HREADYOUT, HRDATA);
            ahb_read(i * 4, read_data[i]);
            // Debug: snapshot AXI AR/R channel AFTER read
            $display("[TB_AHB_EX] DBG after  read[%0d]: ARV=%b ARR=%b ARADDR=0x%08H RV=%b RR=%b HROUT=%b HRDATA=0x%08H",
                     i, u_dut.bridge_m_axi_arvalid, u_dut.bridge_m_axi_arready,
                     u_dut.bridge_m_axi_araddr,
                     u_dut.bridge_m_axi_rvalid, u_dut.bridge_m_axi_rready,
                     HREADYOUT, HRDATA);
            $display("[TB_AHB_EX] AHB read  addr=0x%08H data=0x%08H (expected=0x%08H)",
                     i * 4, read_data[i], write_data[i]);
        end

        // ---------------------------------------------------------------
        // Compare Phase
        // ---------------------------------------------------------------
        $display("[TB_AHB_EX] === COMPARE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            if (read_data[i] === write_data[i]) begin
                $display("[TB_AHB_EX] PASS: addr=0x%08H data=0x%08H", i * 4, read_data[i]);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB_AHB_EX] FAIL: addr=0x%08H expected=0x%08H got=0x%08H",
                         i * 4, write_data[i], read_data[i]);
                fail_count = fail_count + 1;
            end
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("[TB_AHB_EX] ========================================");
        $display("[TB_AHB_EX] RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("[TB_AHB_EX] *** ALL TESTS PASSED ***");
        else
            $display("[TB_AHB_EX] *** SOME TESTS FAILED ***");
        $display("[TB_AHB_EX] ========================================");

        #(10000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #SIM_TIMEOUT;
        $display("[TB_AHB_EX] ERROR: Simulation timeout at %0t", $time);
        $finish;
    end

    // ========================================================================
    // Waveform Dump (Vivado XSim)
    // ========================================================================
    initial begin
        $dumpfile("tb_ddr3_ahb_ex.vcd");
        $dumpvars(0, tb_ddr3_ahb_ex);
    end

endmodule
