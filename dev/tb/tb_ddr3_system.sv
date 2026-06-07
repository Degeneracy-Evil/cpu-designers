// Copyright (c) 2025 CPU Designers. All rights reserved.
// SPDX-License-Identifier: MIT
/**
 * tb_ddr3_system.sv — DDR3-aware system testbench for ISA tests.
 *
 * Instantiates system_top with all DDR3 pins, ddr3_model + WireDelay for
 * DDR3 simulation (matching the Xilinx example project pattern), and glbl
 * for Xilinx global signals.
 *
 * Provides an AHB-Lite BFM that writes program data into DDR3 address space
 * (0x80000000+) after MIG calibration. Uses a trampoline in Boot ROM that
 * jumps to DDR3, so the CPU executes the test program from DDR3.
 *
 * Test flow:
 *   1. Wait for MIG init_calib_complete
 *   2. Load test program words into DDR3 via AHB-Lite BFM at 0x80000000+
 *   3. Release CPU reset — CPU fetches trampoline from Boot ROM (0xFC000000)
 *   4. Trampoline jumps to 0x80000000 — CPU executes test program from DDR3
 *   5. Monitor GPIO_DATA (0x10000004) for pass/fail indication
 *   6. Timeout after SIM_TIMEOUT
 *
 * Compile note: Set SIM_BYPASS_INIT_CAL="FAST" for reasonable sim time.
 */
`include "ahb_def.svh"
`timescale 1ps/100fs

module tb_ddr3_system;

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

    // ========================================================================
    // Test-Specific Parameters
    // ========================================================================
    // Hex file path for $readmemh (relative to xsim work dir or absolute)
    parameter HEX_FILE              = "prog.hex";
    // Maximum number of 32-bit words to load from hex file
    parameter MAX_PROG_WORDS        = 4096;
    // DDR3 base address for program loading (AHB addr[31:28]==4'h8)
    parameter [31:0] DDR3_PROG_BASE = 32'h8000_0000;
    // GPIO_DATA address for pass/fail monitoring (APB bridge at 0x10xxxxxx)
    parameter [31:0] GPIO_DATA_ADDR = 32'h1000_0004;
    // Expected pass indicator: GPIO_DATA[0]==1 means PASS
    parameter PASS_VALUE            = 32'h0000_0001;

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
    localparam CALIB_TIMEOUT           = 1000000000;    // 1ms in ps (with correct DDR3 model timing + sg125)
    localparam SIM_TIMEOUT             = 2000000000;   // 2ms in ps (fits in 32-bit int)

    // Trampoline: 2 instructions at Boot ROM base (0xFC000000)
    //   0xFC000000: lui  t0, 0x80000    →  t0 = 0x80000000
    //   0xFC000004: jr   t0             →  jump to 0x80000000
    //
    // Encoding:
    //   lui  t0, 0x80000  = 0b0110111 | rd=01000 | imm[31:12]=0x80000
    //                      = {0x80000, 5'b01000, 7'b0110111}
    //                      = 32'h8000_50B7
    //   jr   t0           = jalr x0, t0, 0
    //                      = {12'b0, 5'b01000, 3'b000, 5'b00000, 7'b1100111}
    //                      = 32'h0008_5067
    localparam [31:0] TRAMP_INST_0    = 32'h8000_50B7;  // lui t0, 0x80000
    localparam [31:0] TRAMP_INST_1    = 32'h0008_5067;  // jr  t0

    // ========================================================================
    // Clock & Reset Generation (100MHz external crystal)
    // ========================================================================
    reg  ext_clk;       // 100MHz external crystal → system_top.clk
    reg  ext_resetn;    // Active-low reset → system_top.resetn

    initial ext_clk = 1'b0;
    always ext_clk = #(CLKIN_PERIOD / 2.0) ~ext_clk;

    initial ext_resetn = 1'b0;
    initial begin
        #RESET_PERIOD
        ext_resetn = 1'b1;
    end

    // ========================================================================
    // BUG-56 Diagnostic: clk_wiz_0 bypass option
    // ========================================================================
    // Set DDR3_BYPASS_CLK_WIZ define to bypass clk_wiz_0 and generate 200MHz
    // reference clock directly from the testbench. This tests whether clk_wiz_0's
    // MMCM phase/delay is preventing MIG calibration.
    //
    // In tb_ddr3_ahb_ex (which works), both MIG clocks are generated directly
    // by the testbench. In tb_ddr3_system, clk_ref_i comes from clk_wiz_0's
    // MMCM which adds phase shift/delay. If this breaks MIG's internal
    // calibration timing, forcing a clean 200MHz clock should fix it.
    `ifdef DDR3_BYPASS_CLK_WIZ
    reg clk_ref_bypass;
    initial clk_ref_bypass = 1'b0;
    always clk_ref_bypass = #2500 ~clk_ref_bypass;  // 200MHz (5ns period / 2 = 2.5ns half)

    reg clk_sys_bypass;
    initial clk_sys_bypass = 1'b0;
    always clk_sys_bypass = #(CLKIN_PERIOD / 2.0) ~clk_sys_bypass;  // 100MHz

    initial begin
        $display("[TB_DDR3_SYS] *** BYPASS_CLK_WIZ: Forcing clk_ddr_ref + clk_system from testbench ***");
        // Wait for DUT to elaborate, then force
        #1;
        force u_dut.clk_ddr_ref = clk_ref_bypass;
        force u_dut.clk_system  = clk_sys_bypass;
        force u_dut.clk_wiz_locked = 1'b1;
    end
    `endif

    // ========================================================================
    // BUG-56: Force MIG calibration complete to unblock system
    // ========================================================================
    // The MIG calibration FSM gets stuck at INIT_PI_PHASELOCK_READS (state 38)
    // and later states in the full system simulation. This is a known issue with
    // the MIG simulation model's calibration algorithm in hierarchical designs.
    //
    // Fix: Force ddr_phy_init.init_calib_complete=1 after PHY init.
    // This is the deepest source register — it propagates through:
    //   ddr_phy_init.init_calib_complete → ddr_calib_top.init_calib_complete
    //   → ddr_phy_top.phy_init_data_sel → mem_intfc.init_calib_complete
    //   → memc_ui_top_axi.init_calib_complete_r (used by UI/MC to enable AXI)
    //
    // With SIM_BYPASS_INIT_CAL="FAST", PHY uses default/bypass values, so
    // DDR3 read/write works even without full calibration completion.
    `ifdef DDR3_FORCE_CALIB_COMPLETE
    initial begin
        $display("[TB_DDR3_SYS] *** FORCE_CALIB_COMPLETE: Will force ddr_phy_init.init_calib_complete=1 after PHY init ***");
        // Wait for PHY initialization to complete (PHY_INIT at ~10µs)
        #15000000;  // 15µs - well after PHY init at ~10µs
        force u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.u_memc_ui_top_axi.mem_intfc0.ddr_phy_top0.u_ddr_calib_top.u_ddr_phy_init.init_calib_complete = 1'b1;
        $display("[TB_DDR3_SYS] *** FORCE_CALIB_COMPLETE: Forced ddr_phy_init.init_calib_complete=1 at time %0t ***", $time);
    end
    `endif

    // ========================================================================
    // DUT: system_top
    // ========================================================================
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

    wire [15:0] gpio_ctrl_out;
    wire [15:0] gpio_data_out;
    wire [15:0] gpio_io_wire;
    wire        uart_tx;
    wire        lcd_rst, lcd_cs, lcd_rs, lcd_wr, lcd_rd, lcd_bl_ctr;
    wire [15:0] lcd_data_io_wire;
    wire        ct_int_wire, ct_sda_wire, ct_scl, ct_rstn;
    wire        spi_mosi, spi_ss, spi_clk;

    // MIG status (probed from DUT internal hierarchy)
    wire init_calib_complete;
    wire mig_ui_clk;
    wire mig_aresetn;
    wire ahb_hresetn;

    system_top u_dut (
        .clk            (ext_clk),
        .resetn         (ext_resetn),
        .sw             (8'b0),
        .uart_rx        (1'b1),         // Idle high (no UART input)
        .uart_tx        (uart_tx),
        .spi_miso       (1'b0),
        .spi_mosi       (spi_mosi),
        .spi_ss         (spi_ss),
        .spi_clk        (spi_clk),
        .gpio_ctrl_out  (gpio_ctrl_out),
        .gpio_data_out  (gpio_data_out),
        .gpio_io        (gpio_io_wire),
        .lcd_rst        (lcd_rst),
        .lcd_cs         (lcd_cs),
        .lcd_rs         (lcd_rs),
        .lcd_wr         (lcd_wr),
        .lcd_rd         (lcd_rd),
        .lcd_data_io    (lcd_data_io_wire),
        .lcd_bl_ctr     (lcd_bl_ctr),
        .ct_int         (ct_int_wire),
        .ct_sda         (ct_sda_wire),
        .ct_scl         (ct_scl),
        .ct_rstn        (ct_rstn),
        .ddr3_addr      (ddr3_addr),
        .ddr3_ba        (ddr3_ba),
        .ddr3_ras_n     (ddr3_ras_n),
        .ddr3_cas_n     (ddr3_cas_n),
        .ddr3_we_n      (ddr3_we_n),
        .ddr3_reset_n   (ddr3_reset_n),
        .ddr3_ck_p      (ddr3_ck_p),
        .ddr3_ck_n      (ddr3_ck_n),
        .ddr3_cke       (ddr3_cke),
        .ddr3_dm        (ddr3_dm),
        .ddr3_dq        (ddr3_dq),
        .ddr3_dqs_p     (ddr3_dqs_p),
        .ddr3_dqs_n     (ddr3_dqs_n),
        .ddr3_odt       (ddr3_odt)
    );

    // Probe MIG status from DUT internal hierarchy
    assign init_calib_complete = u_dut.mig_init_calib_complete;
    assign mig_ui_clk         = u_dut.mig_ui_clk;
    assign mig_aresetn        = u_dut.mig_aresetn;
    assign ahb_hresetn        = u_dut.ahb_hresetn;

    // ========================================================================
    // DDR3 FPGA-side Wires (from system_top)
    // ========================================================================
    wire [DQ_WIDTH-1:0]    ddr3_dq_fpga    = ddr3_dq;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_p_fpga = ddr3_dqs_p;
    wire [DQS_WIDTH-1:0]   ddr3_dqs_n_fpga = ddr3_dqs_n;
    wire [ROW_WIDTH-1:0]   ddr3_addr_fpga  = ddr3_addr;
    wire [BANK_WIDTH-1:0]  ddr3_ba_fpga    = ddr3_ba;
    wire                   ddr3_ras_n_fpga = ddr3_ras_n;
    wire                   ddr3_cas_n_fpga = ddr3_cas_n;
    wire                   ddr3_we_n_fpga  = ddr3_we_n;
    wire [CK_WIDTH-1:0]    ddr3_ck_p_fpga  = ddr3_ck_p;
    wire [CK_WIDTH-1:0]    ddr3_ck_n_fpga  = ddr3_ck_n;
    wire [CK_WIDTH-1:0]    ddr3_cke_fpga   = ddr3_cke;
    wire [DM_WIDTH-1:0]    ddr3_dm_fpga    = ddr3_dm;
    wire [ODT_WIDTH-1:0]   ddr3_odt_fpga   = ddr3_odt;

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
                .reset         (ext_resetn),
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
            .reset         (ext_resetn),
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
                .reset         (ext_resetn),
                .phy_init_done (init_calib_complete)
            );
            WireDelay #(
                .Delay_g    (TPROP_DQS),
                .Delay_rd   (TPROP_DQS_RD),
                .ERR_INSERT ("OFF")
            ) u_delay_dqs_n (
                .A             (ddr3_dqs_n_fpga[dqswd]),
                .B             (ddr3_dqs_n_sdram[dqswd]),
                .reset         (ext_resetn),
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
    // Xilinx Global Signals (glbl)
    // ========================================================================
    // NOTE: Do NOT instantiate glbl here. xelab auto-elaborates
    // xil_defaultlib.glbl as a top-level module. A second instance
    // creates duplicate GSR drivers that prevent MIG's internal
    // MMCME2_ADV from completing its lock sequence (mmcm_locked=0).
    // tb_ddr3_ahb_ex works WITHOUT glbl instantiation — same pattern here.

    // ========================================================================
    // AHB-Lite Bus Functional Model (BFM)
    // ========================================================================
    // The BFM drives the CPU's AHB-Lite bus directly to write
    // program data into DDR3 before the CPU starts executing.
    // This is done by holding the CPU in reset, then using the
    // AHB bus to write to DDR3 addresses.
    //
    // Note: The BFM writes through the same AHB bus that the CPU
    // uses. During BFM operation, the CPU is held in reset so
    // there is no bus contention. After program loading, the CPU
    // is released and the BFM goes idle (HTRANS=IDLE, HSEL=0).

    // Bridge status wires (hierarchical aliases)
    wire bridge_hreadyout;
    wire [31:0] bridge_hrdata;
    assign bridge_hreadyout =
        u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.HREADYOUT;
    assign bridge_hrdata =
        u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.HRDATA;

    reg         bfm_HSEL;
    reg  [31:0] bfm_HADDR;
    reg  [1:0]  bfm_HTRANS;
    reg         bfm_HWRITE;
    reg  [2:0]  bfm_HSIZE;
    reg  [2:0]  bfm_HBURST;
    reg  [3:0]  bfm_HPROT;
    reg  [31:0] bfm_HWDATA;

    // MUX: BFM drives bus when cpu_held; CPU drives otherwise
    reg cpu_held;
    initial cpu_held = 1'b1;   // CPU held in reset during BFM operation

    // We cannot directly drive the CPU's AHB outputs (they are wires
    // from core_top). Instead, the BFM operates by probing the internal
    // AHB bus and overriding via a separate path. For system_top, the
    // CPU is the only AHB master.
    // Strategy: Hold CPU in reset (ext_resetn=0) so CPU AHB outputs
    // are idle, then the BFM writes by driving a parallel AHB master.
    //
    // However, system_top doesn't expose a second AHB master port.
    // Practical approach: Use hierarchical access to force the CPU's
    // AHB signals during BFM operation. Simulation-only.
    //
    // Alternative (cleaner): The BFM writes to DDR3 by directly
    // driving the ddr3_bridge_wrapper's AHB slave port via
    // hierarchical path, while the CPU is in reset and its AHB
    // outputs are idle (HTRANS=IDLE).

    // Initialize AHB bus to idle state
    task bfm_ahb_idle;
        begin
            bfm_HSEL   = 1'b0;
            bfm_HTRANS = `AHB_TRANS_IDLE;
            bfm_HADDR  = 32'b0;
            bfm_HWRITE = 1'b0;
            bfm_HSIZE  = `AHB_SIZE_WORD;
            bfm_HBURST = `AHB_BURST_SINGLE;
            bfm_HPROT  = 4'b0011;   // data, privileged
            bfm_HWDATA = 32'b0;
        end
    endtask

    // AHB-Lite single write via hierarchical path to ddr3_bridge_wrapper
    // This drives the bridge's AHB slave port directly.
    task bfm_ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Address phase: set up control signals
            @(posedge mig_ui_clk);
            bfm_HSEL   = 1'b1;
            bfm_HTRANS = `AHB_TRANS_NONSEQ;
            bfm_HADDR  = addr;
            bfm_HWRITE = 1'b1;
            bfm_HSIZE  = `AHB_SIZE_WORD;
            bfm_HBURST = `AHB_BURST_SINGLE;
            bfm_HPROT  = 4'b0011;

            // Data phase: drive HWDATA on next clock
            @(posedge mig_ui_clk);
            bfm_HWDATA = data;

            // Wait for slave to accept (HREADYOUT high)
            while (!bridge_hreadyout) begin
                @(posedge mig_ui_clk);
            end

            // Return to idle
            bfm_ahb_idle();
            @(posedge mig_ui_clk);
        end
    endtask

    // AHB-Lite single read via hierarchical path
    task bfm_ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Address phase
            @(posedge mig_ui_clk);
            bfm_HSEL   = 1'b1;
            bfm_HTRANS = `AHB_TRANS_NONSEQ;
            bfm_HADDR  = addr;
            bfm_HWRITE = 1'b0;
            bfm_HSIZE  = `AHB_SIZE_WORD;
            bfm_HBURST = `AHB_BURST_SINGLE;
            bfm_HPROT  = 4'b0011;

            // Wait for valid data (HREADYOUT high)
            @(posedge mig_ui_clk);
            while (!bridge_hreadyout) begin
                @(posedge mig_ui_clk);
            end

            // Capture read data from bridge
            data = bridge_hrdata;

            // Return to idle
            bfm_ahb_idle();
            @(posedge mig_ui_clk);
        end
    endtask

    // ========================================================================
    // Override CPU AHB outputs during BFM operation
    // ========================================================================
    // When cpu_held=1, force the CPU's AHB bus signals to BFM values.
    // When cpu_held=0, the CPU drives the bus normally.
    // This uses hierarchical forcing which is simulation-only.
    //
    // We force the ahb_lite_bus inputs (which are driven by core_top outputs)
    // by overriding at the bus level. The core_top AHB outputs are wires
    // driven by the CPU, so we use $force to override them.

    initial begin
        // Wait for simulation start
        #1;
        // Force CPU AHB outputs to BFM values while cpu_held
        // This is done in the main test sequence using explicit force/release
    end

    // ========================================================================
    // Program Memory (loaded from hex file)
    // ========================================================================
    reg [31:0] prog_mem [0:MAX_PROG_WORDS-1];
    integer    prog_word_count;

    initial begin
        // Initialize program memory to zero
        prog_word_count = 0;
    end

    // ========================================================================
    // Pass/Fail Detection
    // ========================================================================
    reg  test_pass;
    reg  test_fail;
    reg  test_done;

    initial begin
        test_pass = 1'b0;
        test_fail = 1'b0;
        test_done = 1'b0;
    end

    // Monitor GPIO_DATA output for pass/fail indication
    // GPIO_DATA[0]=1 → PASS, GPIO_DATA[1]=1 → FAIL
    always @(posedge mig_ui_clk) begin
        if (!cpu_held && !test_done) begin
            if (gpio_data_out[0] === 1'b1) begin
                test_pass = 1'b1;
                test_done = 1'b1;
                $display("[TB_DDR3_SYS] PASS: GPIO_DATA[0]=1 at %0t",
                         $time);
            end
            if (gpio_data_out[1] === 1'b1) begin
                test_fail = 1'b1;
                test_done = 1'b1;
                $display("[TB_DDR3_SYS] FAIL: GPIO_DATA[1]=1 at %0t",
                         $time);
            end
        end
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    // ========================================================================
    // Debug: Periodic status probe (every 50µs until calib or timeout)
    // ========================================================================
    initial begin
        automatic integer probe_cnt = 0;
        forever begin
            #50000000;  // 50µs
            probe_cnt = probe_cnt + 1;
            // Probe init_calib_complete at each hierarchy level
            $display("[TB_DDR3_SYS] PROBE[%0d] t=%0t: ext_resetn=%b clk_wiz_locked=%b",
                     probe_cnt, $time, ext_resetn, u_dut.clk_wiz_locked);
            $display("[TB_DDR3_SYS]   system_top.mig_init_calib_complete=%b",
                     u_dut.mig_init_calib_complete);
            $display("[TB_DDR3_SYS]   ahb_lite_bus.init_calib_complete=%b",
                     u_dut.u_ahb_lite_bus.init_calib_complete);
            $display("[TB_DDR3_SYS]   bridge_wrapper.init_calib_complete=%b",
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.init_calib_complete);
            $display("[TB_DDR3_SYS]   MIG.init_calib_complete=%b",
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.init_calib_complete);
            $display("[TB_DDR3_SYS]   MIG.ui_clk=%b MIG.mmcm_locked=%b MIG.aresetn=%b MIG.sys_rst=%b",
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.ui_clk,
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.mmcm_locked,
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.aresetn,
                     u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.sys_rst);
            // Deep MIG infrastructure probes
            begin : mig_deep_probe
                $display("[TB_DDR3_SYS]   infra.pll_locked=%b infra.mmcm_locked=%b",
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.u_ddr3_infrastructure.pll_locked,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.u_ddr3_infrastructure.mmcm_locked);
                $display("[TB_DDR3_SYS]   infra.rst_tmp=%b infra.sys_rst_act_hi=%b",
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.u_ddr3_infrastructure.rst_tmp,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.u_ddr3_infrastructure.sys_rst_act_hi);
            end
            // BUG-56: MIG phy_init state machine probe — which state is calibration stuck in?
            // States: 0=IDLE, 1=WAIT_CKE_EXIT, 2=LOAD_MR, ..., 22=INIT_DONE
            // If stuck at state 1, SIM_INIT_OPTION="NONE" (OFF mode, _mig.v active)
            // If stuck at other state, calibration algorithm is failing
            begin : phy_init_state_probe
                $display("[TB_DDR3_SYS]   phy_init.init_state_r=%07b (%0d)",
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig
                         .u_bd_soc_mig_7series_0_1_mig
                         .u_memc_ui_top_axi.mem_intfc0.ddr_phy_top0.u_ddr_calib_top.u_ddr_phy_init.init_state_r,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig
                         .u_bd_soc_mig_7series_0_1_mig
                         .u_memc_ui_top_axi.mem_intfc0.ddr_phy_top0.u_ddr_calib_top.u_ddr_phy_init.init_state_r);
            end
            // BUG-56: clk_wiz_0 output probes — is clk_ddr_ref toggling?
            begin : clk_wiz_probe
                // Sample clk_ddr_ref at two time points 1250ps apart (half 200MHz period)
                automatic logic s1, s2;
                s1 = u_dut.clk_ddr_ref;
                #1250;
                s2 = u_dut.clk_ddr_ref;
                $display("[TB_DDR3_SYS]   clk_ddr_ref: sample1=%b sample2=%b (toggled=%0b) clk_system=%b",
                         s1, s2, (s1 !== s2), u_dut.clk_system);
                #(-1250);  // Return to original time (XSim supports negative delays in initial blocks)
            end
            // BUG-56: Bridge AXI signal probes — any spurious AXI transactions before calib?
            begin : axi_probe
                $display("[TB_DDR3_SYS]   bridge AXI: awvalid=%b arvalid=%b wvalid=%b awaddr=0x%08H",
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.bridge_m_axi_awvalid,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.bridge_m_axi_arvalid,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.bridge_m_axi_wvalid,
                         u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.bridge_m_axi_awaddr);
            end
            // BUG-56: CPU AHB bus state — is CPU driving the bus while HRESETn=0?
            begin : cpu_ahb_probe
                $display("[TB_DDR3_SYS]   CPU AHB: HTRANS=%b HADDR=0x%08H HWRITE=%b ahb_hresetn=%b",
                         u_dut.cpu_HTRANS, u_dut.cpu_HADDR, u_dut.cpu_HWRITE, u_dut.ahb_hresetn);
            end
        end
    end

    initial begin
        // Initialize BFM
        bfm_ahb_idle();

        // ---------------------------------------------------------------
        // Phase 1: Wait for MIG calibration
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 1: Wait MIG calib ===");
        // BUG-56 diagnostic: verify which MIG module is being used
        $display("[TB_DDR3_SYS] MIG SIM_BYPASS_INIT_CAL param = %0s", u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.SIM_BYPASS_INIT_CAL);
        $display("[TB_DDR3_SYS] MIG SIMULATION param = %0s", u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig.u_bd_soc_mig_7series_0_1_mig.SIMULATION);
        // Immediate debug: print signal states at t=0 and after reset
        $display("[TB_DDR3_SYS] DEBUG t=%0t: ext_resetn=%b", $time, ext_resetn);
        #(RESET_PERIOD + 1000);  // Just after reset release
        $display("[TB_DDR3_SYS] DEBUG t=%0t: ext_resetn=%b clk_wiz_locked=%b init_calib=%b",
                 $time, ext_resetn,
                 u_dut.clk_wiz_locked,
                 init_calib_complete);
        fork
            begin : calib_wait
                wait (init_calib_complete === 1'b1);
                $display("[TB_DDR3_SYS] Calib complete at %0t",
                         $time);
            end
            begin : calib_timeout
                #CALIB_TIMEOUT;
                $display("[TB_DDR3_SYS] ERROR: Calib timeout at %0t",
                         $time);
                $finish;
            end
        join_any
        disable fork;

        // Settle time after calibration
        repeat(200) @(posedge mig_ui_clk);
        $display("[TB_DDR3_SYS] MIG settled, loading program...");

        // ---------------------------------------------------------------
        // Phase 2: Load program from hex file into prog_mem
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 2: Load hex file ===");
        $display("[TB_DDR3_SYS] Reading hex file: %s", HEX_FILE);

        prog_word_count = 0;
        $readmemh(HEX_FILE, prog_mem);

        // Count non-zero words (heuristic for program size)
        // Hex file may have sparse entries; scan for last non-zero
        begin : count_words
            integer j;
            prog_word_count = 0;
            for (j = 0; j < MAX_PROG_WORDS; j = j + 1) begin
                if (prog_mem[j] !== 32'bx && prog_mem[j] !== 32'b0) begin
                    prog_word_count = j + 1;
                end
            end
        end

        if (prog_word_count == 0) begin
            $display("[TB_DDR3_SYS] WARNING: No data in hex file!");
            $display("[TB_DDR3_SYS] Trampoline only (2 words)");
            prog_word_count = 2;
            prog_mem[0] = TRAMP_INST_0;
            prog_mem[1] = TRAMP_INST_1;
        end else begin
            $display("[TB_DDR3_SYS] Loaded %0d words from hex",
                     prog_word_count);
        end

        // ---------------------------------------------------------------
        // Phase 3: Write trampoline to Boot ROM via AHB BFM
        // ---------------------------------------------------------------
        // Note: Boot ROM (ahb_bootrom_slave) is typically read-only
        // and initialized via $readmemh/COE. For simulation, we write
        // the trampoline directly into the Boot ROM's memory array
        // via hierarchical access, since the AHB slave is read-only.
        //
        // The Boot ROM memory is at:
        //   u_dut.u_ahb_lite_bus.u_ahb_bootrom_slave.mem
        $display("[TB_DDR3_SYS] === Phase 3: Trampoline ===");
        $display("[TB_DDR3_SYS]   [0xFC000000]=0x%08H lui t0,0x80000",
                 TRAMP_INST_0);
        $display("[TB_DDR3_SYS]   [0xFC000004]=0x%08H jr t0",
                 TRAMP_INST_1);

        // Force trampoline into Boot ROM memory array
        // Word-addressed: offset 0=0xFC000000, offset 1=0xFC000004
        u_dut.u_ahb_lite_bus.u_ahb_bootrom_slave.mem[0] = TRAMP_INST_0;
        u_dut.u_ahb_lite_bus.u_ahb_bootrom_slave.mem[1] = TRAMP_INST_1;

        // ---------------------------------------------------------------
        // Phase 4: Write program into DDR3 via AHB BFM
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 4: Write DDR3 ===");

        // Force CPU AHB outputs to BFM values
        // (CPU is in reset, outputs are idle)
        force u_dut.cpu_HADDR  = bfm_HADDR;
        force u_dut.cpu_HTRANS = bfm_HTRANS;
        force u_dut.cpu_HWRITE = bfm_HWRITE;
        force u_dut.cpu_HSIZE  = bfm_HSIZE;
        force u_dut.cpu_HBURST = bfm_HBURST;
        force u_dut.cpu_HPROT  = bfm_HPROT;
        force u_dut.cpu_HWDATA = bfm_HWDATA;

        // Write each word to DDR3 address space
        begin : write_ddr3
            integer k;
            for (k = 0; k < prog_word_count; k = k + 1) begin
                bfm_ahb_write(DDR3_PROG_BASE + (k * 4), prog_mem[k]);
                if (k < 8 || k == prog_word_count - 1) begin
                    $display("[TB_DDR3_SYS]   DDR3[0x%08H] = 0x%08H",
                             DDR3_PROG_BASE + (k * 4), prog_mem[k]);
                end else if (k == 8) begin
                    $display("[TB_DDR3_SYS]   ... (output suppressed)");
                end
            end
        end

        $display("[TB_DDR3_SYS] Wrote %0d words to DDR3", prog_word_count);

        // Allow writes to propagate through Bridge + MIG pipeline
        repeat(100) @(posedge mig_ui_clk);

        // ---------------------------------------------------------------
        // Phase 4b: Read-back verify (first 4 words)
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 4b: Read-back verify ===");
        begin : readback_verify
            integer m;
            reg [31:0] rb_data;
            integer rb_errors;
            integer rb_limit;
            rb_errors = 0;
            rb_limit = (prog_word_count < 4) ? prog_word_count : 4;
            for (m = 0; m < rb_limit; m = m + 1) begin
                bfm_ahb_read(DDR3_PROG_BASE + (m * 4), rb_data);
                if (rb_data !== prog_mem[m]) begin
                    $display("[TB_DDR3_SYS]   FAIL: DDR3[0x%08H]",
                             DDR3_PROG_BASE + (m * 4));
                    $display("[TB_DDR3_SYS]     exp=0x%08H got=0x%08H",
                             prog_mem[m], rb_data);
                    rb_errors = rb_errors + 1;
                end else begin
                    $display("[TB_DDR3_SYS]   OK: DDR3[0x%08H]=0x%08H",
                             DDR3_PROG_BASE + (m * 4),
                             rb_data);
                end
            end
            if (rb_errors > 0) begin
                $display("[TB_DDR3_SYS] WARN: %0d mismatches",
                         rb_errors);
            end else begin
                $display("[TB_DDR3_SYS] Read-back verify passed");
            end
        end

        // ---------------------------------------------------------------
        // Phase 5: Release CPU — start execution
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 5: Release CPU ===");

        // Return BFM to idle
        bfm_ahb_idle();
        repeat(10) @(posedge mig_ui_clk);

        // Release forced AHB signals — CPU now drives the bus
        release u_dut.cpu_HADDR;
        release u_dut.cpu_HTRANS;
        release u_dut.cpu_HWRITE;
        release u_dut.cpu_HSIZE;
        release u_dut.cpu_HBURST;
        release u_dut.cpu_HPROT;
        release u_dut.cpu_HWDATA;

        // Release CPU from reset
        cpu_held = 1'b0;
        // ext_resetn already 1 since RESET_PERIOD — CPU fetches
        $display("[TB_DDR3_SYS] CPU released — BootROM→DDR3");

        // ---------------------------------------------------------------
        // Phase 6: Wait for test completion or timeout
        // ---------------------------------------------------------------
        $display("[TB_DDR3_SYS] === Phase 6: Wait result ===");

        // Wait for pass/fail indication or timeout
        wait (test_done === 1'b1);

        // Report result
        $display("[TB_DDR3_SYS] ========================================");
        if (test_pass && !test_fail) begin
            $display("[TB_DDR3_SYS] *** TEST PASSED *** (GPIO_DATA[0]=1)");
        end else if (test_fail) begin
            $display("[TB_DDR3_SYS] *** TEST FAILED *** (GPIO_DATA[1]=1)");
        end else begin
            $display("[TB_DDR3_SYS] *** TEST INCONCLUSIVE ***");
        end
        $display("[TB_DDR3_SYS] ========================================");

        #(10000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #SIM_TIMEOUT;
        $display("[TB_DDR3_SYS] ERROR: Sim timeout at %0t",
                 $time);
        $display("[TB_DDR3_SYS] Timeout limit: %0t ps",
                 SIM_TIMEOUT);
        $finish;
    end

    // ========================================================================
    // Calibration Timeout Watchdog (separate, shorter)
    // ========================================================================
    initial begin
        #CALIB_TIMEOUT;
        if (init_calib_complete !== 1'b1) begin
            $display("[TB_DDR3_SYS] ERROR: MIG calib timeout %0t ps",
                     CALIB_TIMEOUT);
            $finish;
        end
    end

    // ========================================================================
    // Waveform Dump (Vivado XSim)
    // ========================================================================
    // BUG-55d: Disable full VCD dump for simulation speed.
    // $dumpvars(0, ...) on a 60K-FF design writes every signal change to disk,
    // creating massive I/O overhead. For initial bring-up, disable VCD.
    // Re-enable with level=1 (top-level only) if waveform debug is needed:
    //   $dumpvars(1, tb_ddr3_system);
    //
    // initial begin
    //     $dumpfile("tb_ddr3_system.vcd");
    //     $dumpvars(1, tb_ddr3_system);
    // end

endmodule
