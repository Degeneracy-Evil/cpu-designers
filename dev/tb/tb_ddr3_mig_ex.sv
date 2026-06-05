/**
 * tb_ddr3_mig_ex.sv — Phase 1: MIG 7 Series + DDR3 model verification.
 *
 * Directly instantiates bd_soc_mig_7series_0_1 and drives its AXI4 S_AXI
 * interface with a simple BFM (write then read back). Uses WireDelay for
 * DQ/DQS bi-directional bus modeling, matching the Xilinx example testbench.
 *
 * Test flow:
 *   1. Wait for MIG init_calib_complete
 *   2. Write 4 words via AXI4 at addresses 0x00–0x0C
 *   3. Read them back
 *   4. Compare and report PASS/FAIL
 *
 * Compile note: Set SIM_BYPASS_INIT_CAL="FAST" for reasonable sim time.
 *   Vivado: set_property -name {xsim.simulate.xsim.more_options} \
 *           -value {-g bd_soc_mig_7series_0_1.u_bd_soc_mig_7series_0_1_mig.SIM_BYPASS_INIT_CAL="FAST"} \
 *           [current_run]
 */
`timescale 1ps/100fs

module tb_ddr3_mig_ex;

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
    parameter C_S_AXI_ID_WIDTH      = 8;
    parameter C_S_AXI_ADDR_WIDTH    = 27;
    parameter C_S_AXI_DATA_WIDTH    = 32;
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
    localparam CALIB_TIMEOUT           = 100000000;    // 100us in ps
    localparam SIM_TIMEOUT             = 500000000;    // 500us in ps

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
    // MIG Status Wires
    // ========================================================================
    wire            init_calib_complete;
    wire            ui_clk;
    wire            ui_clk_sync_rst;
    wire            mmcm_locked;
    reg             aresetn;
    wire [11:0]     device_temp;
    wire            app_sr_active;
    wire            app_ref_ack;
    wire            app_zq_ack;

    // Drive aresetn from MIG outputs (same as Xilinx example_top)
    initial aresetn = 1'b0;
    always @(posedge ui_clk) begin
        aresetn <= ~ui_clk_sync_rst;
    end

    // ========================================================================
    // AXI4 Slave Interface Signals (driven by BFM)
    // ========================================================================
    reg  [C_S_AXI_ID_WIDTH-1:0]    s_axi_awid;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]  s_axi_awaddr;
    reg  [7:0]                      s_axi_awlen;
    reg  [2:0]                      s_axi_awsize;
    reg  [1:0]                      s_axi_awburst;
    reg  [0:0]                      s_axi_awlock;
    reg  [3:0]                      s_axi_awcache;
    reg  [2:0]                      s_axi_awprot;
    reg                             s_axi_awvalid;
    wire                            s_axi_awready;

    reg  [C_S_AXI_DATA_WIDTH-1:0]  s_axi_wdata;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
    reg                             s_axi_wlast;
    reg                             s_axi_wvalid;
    wire                            s_axi_wready;

    reg                             s_axi_bready;
    wire [C_S_AXI_ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]                      s_axi_bresp;
    wire                            s_axi_bvalid;

    reg  [C_S_AXI_ID_WIDTH-1:0]    s_axi_arid;
    reg  [C_S_AXI_ADDR_WIDTH-1:0]  s_axi_araddr;
    reg  [7:0]                      s_axi_arlen;
    reg  [2:0]                      s_axi_arsize;
    reg  [1:0]                      s_axi_arburst;
    reg  [0:0]                      s_axi_arlock;
    reg  [3:0]                      s_axi_arcache;
    reg  [2:0]                      s_axi_arprot;
    reg                             s_axi_arvalid;
    wire                            s_axi_arready;

    reg                             s_axi_rready;
    wire [C_S_AXI_ID_WIDTH-1:0]    s_axi_rid;
    wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]                      s_axi_rresp;
    wire                            s_axi_rlast;
    wire                            s_axi_rvalid;

    // ========================================================================
    // DDR3 FPGA-side Wires (from MIG)
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
    // MIG Instance
    // ========================================================================
    bd_soc_mig_7series_0_1 u_mig (
        // Memory interface
        .ddr3_dq              (ddr3_dq_fpga),
        .ddr3_dqs_n           (ddr3_dqs_n_fpga),
        .ddr3_dqs_p           (ddr3_dqs_p_fpga),
        .ddr3_addr            (ddr3_addr_fpga),
        .ddr3_ba              (ddr3_ba_fpga),
        .ddr3_ras_n           (ddr3_ras_n_fpga),
        .ddr3_cas_n           (ddr3_cas_n_fpga),
        .ddr3_we_n            (ddr3_we_n_fpga),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_ck_p            (ddr3_ck_p_fpga),
        .ddr3_ck_n            (ddr3_ck_n_fpga),
        .ddr3_cke             (ddr3_cke_fpga),
        .ddr3_dm              (ddr3_dm_fpga),
        .ddr3_odt             (ddr3_odt_fpga),
        // Status
        .init_calib_complete  (init_calib_complete),
        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),
        // Application interface (tie off)
        .app_sr_req           (1'b0),
        .app_ref_req          (1'b0),
        .app_zq_req           (1'b0),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),
        // AXI4 AW channel
        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awlen          (s_axi_awlen),
        .s_axi_awsize         (s_axi_awsize),
        .s_axi_awburst        (s_axi_awburst),
        .s_axi_awlock         (s_axi_awlock),
        .s_axi_awcache        (s_axi_awcache),
        .s_axi_awprot         (s_axi_awprot),
        .s_axi_awqos          (4'h0),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),
        // AXI4 W channel
        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wlast          (s_axi_wlast),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),
        // AXI4 B channel
        .s_axi_bready         (s_axi_bready),
        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        // AXI4 AR channel
        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arlen          (s_axi_arlen),
        .s_axi_arsize         (s_axi_arsize),
        .s_axi_arburst        (s_axi_arburst),
        .s_axi_arlock         (s_axi_arlock),
        .s_axi_arcache        (s_axi_arcache),
        .s_axi_arprot         (s_axi_arprot),
        .s_axi_arqos          (4'h0),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),
        // AXI4 R channel
        .s_axi_rready         (s_axi_rready),
        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        // Clock & Reset
        .sys_clk_i            (sys_clk_i),
        .clk_ref_i            (clk_ref_i),
        .device_temp          (device_temp),
        .sys_rst              (sys_rst)
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
    // AXI4 Bus Functional Model (BFM)
    // ========================================================================

    // Set all AXI4 signals to idle state
    task axi4_idle;
        begin
            s_axi_awid    = 8'b0;
            s_axi_awaddr  = 27'b0;
            s_axi_awlen   = 8'b0;
            s_axi_awsize  = 3'b0;
            s_axi_awburst = 2'b0;
            s_axi_awlock  = 1'b0;
            s_axi_awcache = 4'b0;
            s_axi_awprot  = 3'b0;
            s_axi_awvalid = 1'b0;
            s_axi_wdata   = 32'b0;
            s_axi_wstrb   = 4'b0;
            s_axi_wlast   = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_bready  = 1'b0;
            s_axi_arid    = 8'b0;
            s_axi_araddr  = 27'b0;
            s_axi_arlen   = 8'b0;
            s_axi_arsize  = 3'b0;
            s_axi_arburst = 2'b0;
            s_axi_arlock  = 1'b0;
            s_axi_arcache = 4'b0;
            s_axi_arprot  = 3'b0;
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b0;
        end
    endtask

    // AXI4 single-word write: AW -> W -> B handshake
    task axi4_write;
        input [26:0] addr;
        input [31:0] data;
        begin
            // AW channel: drive address and assert valid
            s_axi_awid    = 8'b0;
            s_axi_awaddr  = addr;
            s_axi_awlen   = 8'h00;      // 1 beat (len=0)
            s_axi_awsize  = 3'b010;     // 4 bytes
            s_axi_awburst = 2'b01;     // INCR
            s_axi_awlock  = 1'b0;
            s_axi_awcache = 4'b0011;
            s_axi_awprot  = 3'b000;
            s_axi_awvalid = 1'b1;

            // W channel: drive data and assert valid
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wlast   = 1'b1;
            s_axi_wvalid  = 1'b1;

            // B channel: ready to accept response
            s_axi_bready  = 1'b1;

            // Wait for AW handshake
            @(posedge ui_clk);
            while (!s_axi_awready) @(posedge ui_clk);
            s_axi_awvalid = 1'b0;

            // Wait for W handshake
            while (!s_axi_wready) @(posedge ui_clk);
            s_axi_wvalid = 1'b0;

            // Wait for B handshake
            while (!s_axi_bvalid) @(posedge ui_clk);
            s_axi_bready = 1'b0;
        end
    endtask

    // AXI4 single-word read: AR -> R handshake
    task axi4_read;
        input  [26:0] addr;
        output [31:0] data;
        begin
            // AR channel: drive address and assert valid
            s_axi_arid    = 8'b0;
            s_axi_araddr  = addr;
            s_axi_arlen   = 8'h00;      // 1 beat
            s_axi_arsize  = 3'b010;     // 4 bytes
            s_axi_arburst = 2'b01;     // INCR
            s_axi_arlock  = 1'b0;
            s_axi_arcache = 4'b0011;
            s_axi_arprot  = 3'b000;
            s_axi_arvalid = 1'b1;

            // R channel: ready to accept data
            s_axi_rready  = 1'b1;

            // Wait for AR handshake
            @(posedge ui_clk);
            while (!s_axi_arready) @(posedge ui_clk);
            s_axi_arvalid = 1'b0;

            // Wait for R handshake, capture data
            while (!s_axi_rvalid) @(posedge ui_clk);
            data = s_axi_rdata;
            s_axi_rready = 1'b0;
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
    // AXI4 Signal Initialization
    // ========================================================================
    initial begin
        axi4_idle();
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // Initialize test data
        write_data[0] = 32'hDEADBEEF;
        write_data[1] = 32'hCAFEBABE;
        write_data[2] = 32'h12345678;
        write_data[3] = 32'h87654321;
        pass_count = 0;
        fail_count = 0;

        // Wait for MIG calibration
        $display("[TB_MIG_EX] Waiting for MIG init_calib_complete...");
        fork
            begin : calib_wait
                wait (init_calib_complete === 1'b1);
                $display("[TB_MIG_EX] Calibration complete at time %0t", $time);
            end
            begin : calib_timeout
                #CALIB_TIMEOUT;
                $display("[TB_MIG_EX] ERROR: Calibration timeout at %0t", $time);
                $finish;
            end
        join_any
        disable fork;

        // Settle time after calibration
        repeat(100) @(posedge ui_clk);

        // ---------------------------------------------------------------
        // Write Phase
        // ---------------------------------------------------------------
        $display("[TB_MIG_EX] === WRITE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            $display("[TB_MIG_EX] AXI4 write addr=0x%08H data=0x%08H",
                     i * 4, write_data[i]);
            axi4_write(i * 4, write_data[i]);
        end

        // Allow time for writes to propagate through MIG pipeline
        repeat(50) @(posedge ui_clk);

        // ---------------------------------------------------------------
        // Read Phase
        // ---------------------------------------------------------------
        $display("[TB_MIG_EX] === READ PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            axi4_read(i * 4, read_data[i]);
            $display("[TB_MIG_EX] AXI4 read  addr=0x%08H data=0x%08H (expected=0x%08H)",
                     i * 4, read_data[i], write_data[i]);
        end

        // ---------------------------------------------------------------
        // Compare Phase
        // ---------------------------------------------------------------
        $display("[TB_MIG_EX] === COMPARE PHASE ===");
        for (i = 0; i < NUM_TEST_WORDS; i = i + 1) begin
            if (read_data[i] === write_data[i]) begin
                $display("[TB_MIG_EX] PASS: addr=0x%08H data=0x%08H", i * 4, read_data[i]);
                pass_count = pass_count + 1;
            end else begin
                $display("[TB_MIG_EX] FAIL: addr=0x%08H expected=0x%08H got=0x%08H",
                         i * 4, write_data[i], read_data[i]);
                fail_count = fail_count + 1;
            end
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("[TB_MIG_EX] ========================================");
        $display("[TB_MIG_EX] RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("[TB_MIG_EX] *** ALL TESTS PASSED ***");
        else
            $display("[TB_MIG_EX] *** SOME TESTS FAILED ***");
        $display("[TB_MIG_EX] ========================================");

        #(10000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #SIM_TIMEOUT;
        $display("[TB_MIG_EX] ERROR: Simulation timeout at %0t", $time);
        $finish;
    end

    // ========================================================================
    // Waveform Dump (Vivado XSim)
    // ========================================================================
    initial begin
        $dumpfile("tb_ddr3_mig_ex.vcd");
        $dumpvars(0, tb_ddr3_mig_ex);
    end

endmodule
