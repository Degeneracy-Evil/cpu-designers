/**
 * ddr3_bridge_wrapper.sv — AHB-Lite to AXI4 Bridge ↔ MIG 7 Series connection wrapper.
 *
 * Instantiates:
 *   1. ahblite_axi_bridge_0  — AHB-Lite slave → AXI4 master
 *   2. bd_soc_mig_7series_0_1 — AXI4 slave → DDR3 SDRAM
 *
 * Width adaptation (Bridge M_AXI → MIG S_AXI):
 *   - Address:  Bridge 32-bit → MIG 27-bit  (truncate upper 5 bits)
 *   - ID:       Bridge 0-bit (no port) → MIG 8-bit  (zero-pad)
 *   - QoS:      Bridge none → MIG 4-bit  (tie to 0)
 *   - Region:   Bridge none → MIG 4-bit  (tie to 0)
 *   - Lock:     Bridge 1-bit → MIG 1-bit  (direct)
 *   - All other AXI signals: direct 1:1 connection
 *
 * AHB-Lite slave interface matches the existing ahb_sram_slave port convention
 * so this module can be dropped into ahb_lite_bus.sv as a slave replacement.
 */
`include "ahb_def.svh"
`timescale 1ns / 1ps

module ddr3_bridge_wrapper (
    // --- AHB-Lite Slave Interface (from AHB bus) ---
    input  wire                    HCLK,
    input  wire                    HRESETn,
    input  wire                    HSEL,
    input  wire  [31:0]           HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire  [2:0]             HSIZE,
    input  wire  [2:0]             HBURST,
    input  wire  [3:0]             HPROT,
    input  wire  [31:0]           HWDATA,
    input  wire                    HREADY,

    output wire                    HREADYOUT,
    output wire                    HRESP,
    output wire  [31:0]           HRDATA,

    // --- MIG Clock/Reset ---
    input  wire                    mig_sys_clk_i,    // 100MHz external crystal
    input  wire                    mig_clk_ref_i,    // 200MHz DDR reference clock
    input  wire                    mig_sys_rst_n,    // Active-LOW system reset (MIG RST_ACT_LOW=1: 0=reset, 1=normal)

    // --- MIG Status ---
    output wire                    init_calib_complete,
    output wire                    ui_clk,           // MIG output 100MHz (= system clock)
    output wire                    ui_clk_sync_rst,  // MIG sync reset (active-high)
    output wire                    mmcm_locked,      // MIG internal MMCM locked
    input  wire                    aresetn,          // MIG AXI reset (active-low) — INPUT to MIG

    // --- MIG Application Interface (optional, tie low for normal operation) ---
    input  wire                    app_sr_req,       // Self-refresh request
    input  wire                    app_ref_req,      // Refresh request
    input  wire                    app_zq_req,       // ZQ calibration request
    output wire                    app_sr_active,    // Self-refresh active
    output wire                    app_ref_ack,      // Refresh acknowledge
    output wire                    app_zq_ack,       // ZQ calibration acknowledge

    // --- DDR3 SDRAM Pins ---
    output wire  [12:0]           ddr3_addr,
    output wire  [2:0]            ddr3_ba,
    output wire                    ddr3_ras_n,
    output wire                    ddr3_cas_n,
    output wire                    ddr3_we_n,
    output wire                    ddr3_reset_n,
    output wire  [0:0]            ddr3_ck_p,
    output wire  [0:0]            ddr3_ck_n,
    output wire  [0:0]            ddr3_cke,
    output wire  [1:0]            ddr3_dm,
    inout   wire  [15:0]          ddr3_dq,
    inout   wire  [1:0]            ddr3_dqs_p,
    inout   wire  [1:0]            ddr3_dqs_n,
    output wire  [0:0]            ddr3_odt
);

    // ========================================================================
    // AHB-Lite to AXI4 Bridge Instance
    // ========================================================================

    // Bridge M_AXI signals (outputs from Bridge)
    wire [7:0]   bridge_m_axi_awlen;
    wire [2:0]   bridge_m_axi_awsize;
    wire [1:0]   bridge_m_axi_awburst;
    wire [3:0]   bridge_m_axi_awcache;
    wire [31:0]  bridge_m_axi_awaddr;
    wire [2:0]   bridge_m_axi_awprot;
    wire         bridge_m_axi_awvalid;
    wire         bridge_m_axi_awready;
    wire         bridge_m_axi_awlock;
    wire [31:0]  bridge_m_axi_wdata;
    wire [3:0]   bridge_m_axi_wstrb;
    wire         bridge_m_axi_wlast;
    wire         bridge_m_axi_wvalid;
    wire         bridge_m_axi_wready;
    wire [1:0]   bridge_m_axi_bresp;
    wire         bridge_m_axi_bvalid;
    wire         bridge_m_axi_bready;
    wire [7:0]   bridge_m_axi_arlen;
    wire [2:0]   bridge_m_axi_arsize;
    wire [1:0]   bridge_m_axi_arburst;
    wire [2:0]   bridge_m_axi_arprot;
    wire [3:0]   bridge_m_axi_arcache;
    wire         bridge_m_axi_arvalid;
    wire [31:0]  bridge_m_axi_araddr;
    wire         bridge_m_axi_arlock;
    wire         bridge_m_axi_arready;
    wire [31:0]  bridge_m_axi_rdata;
    wire [1:0]   bridge_m_axi_rresp;
    wire         bridge_m_axi_rvalid;
    wire         bridge_m_axi_rlast;
    wire         bridge_m_axi_rready;

    ahblite_axi_bridge_0 u_ahb_bridge (
        // AHB-Lite Slave
        .s_ahb_hclk       (HCLK),
        .s_ahb_hresetn    (HRESETn),
        .s_ahb_hsel       (HSEL),
        .s_ahb_haddr      (HADDR),
        .s_ahb_hprot      (HPROT),
        .s_ahb_htrans     (HTRANS),
        .s_ahb_hsize      (HSIZE),
        .s_ahb_hwrite     (HWRITE),
        .s_ahb_hburst     (HBURST),
        .s_ahb_hwdata     (HWDATA),
        .s_ahb_hready_out (HREADYOUT),
        .s_ahb_hready_in  (HREADY),
        .s_ahb_hrdata     (HRDATA),
        .s_ahb_hresp      (HRESP),

        // AXI4 Master — AW channel
        .m_axi_awlen      (bridge_m_axi_awlen),
        .m_axi_awsize     (bridge_m_axi_awsize),
        .m_axi_awburst    (bridge_m_axi_awburst),
        .m_axi_awcache    (bridge_m_axi_awcache),
        .m_axi_awaddr     (bridge_m_axi_awaddr),
        .m_axi_awprot     (bridge_m_axi_awprot),
        .m_axi_awvalid    (bridge_m_axi_awvalid),
        .m_axi_awready    (bridge_m_axi_awready),
        .m_axi_awlock     (bridge_m_axi_awlock),

        // AXI4 Master — W channel
        .m_axi_wdata      (bridge_m_axi_wdata),
        .m_axi_wstrb      (bridge_m_axi_wstrb),
        .m_axi_wlast      (bridge_m_axi_wlast),
        .m_axi_wvalid     (bridge_m_axi_wvalid),
        .m_axi_wready     (bridge_m_axi_wready),

        // AXI4 Master — B channel
        .m_axi_bresp      (bridge_m_axi_bresp),
        .m_axi_bvalid     (bridge_m_axi_bvalid),
        .m_axi_bready     (bridge_m_axi_bready),

        // AXI4 Master — AR channel
        .m_axi_arlen      (bridge_m_axi_arlen),
        .m_axi_arsize     (bridge_m_axi_arsize),
        .m_axi_arburst    (bridge_m_axi_arburst),
        .m_axi_arprot     (bridge_m_axi_arprot),
        .m_axi_arcache    (bridge_m_axi_arcache),
        .m_axi_arvalid    (bridge_m_axi_arvalid),
        .m_axi_araddr     (bridge_m_axi_araddr),
        .m_axi_arlock     (bridge_m_axi_arlock),
        .m_axi_arready    (bridge_m_axi_arready),

        // AXI4 Master — R channel
        .m_axi_rdata      (bridge_m_axi_rdata),
        .m_axi_rresp      (bridge_m_axi_rresp),
        .m_axi_rvalid     (bridge_m_axi_rvalid),
        .m_axi_rlast      (bridge_m_axi_rlast),
        .m_axi_rready     (bridge_m_axi_rready)
    );

    // ========================================================================
    // MIG 7 Series DDR3 Controller Instance
    // ========================================================================

    // MIG response ID signals (discarded — Bridge has no ID ports)
    wire [7:0] mig_s_axi_bid;
    wire [7:0] mig_s_axi_rid;

    bd_soc_mig_7series_0_1 u_mig (
        // Clock & Reset
        .sys_clk_i            (mig_sys_clk_i),
        .clk_ref_i            (mig_clk_ref_i),
        .sys_rst              (mig_sys_rst_n),    // MIG IP port sys_rst: active-LOW per RST_ACT_LOW=1

        // MIG Status
        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),
        .init_calib_complete  (init_calib_complete),

        // MIG Application Interface
        .app_sr_req           (app_sr_req),
        .app_ref_req          (app_ref_req),
        .app_zq_req           (app_zq_req),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),

        // S_AXI — AW channel
        .s_axi_awid           (8'b0),                           // ID_WIDTH=0 → zero-pad
        .s_axi_awaddr         (bridge_m_axi_awaddr[26:0]),      // 32→27 bit truncate
        .s_axi_awlen          (bridge_m_axi_awlen),
        .s_axi_awsize         (bridge_m_axi_awsize),
        .s_axi_awburst        (bridge_m_axi_awburst),
        .s_axi_awlock         (bridge_m_axi_awlock),
        .s_axi_awcache        (bridge_m_axi_awcache),
        .s_axi_awprot         (bridge_m_axi_awprot),
        .s_axi_awqos          (4'b0),                           // Bridge has no QoS
        .s_axi_awvalid        (bridge_m_axi_awvalid),
        .s_axi_awready        (bridge_m_axi_awready),

        // S_AXI — W channel
        .s_axi_wdata          (bridge_m_axi_wdata),
        .s_axi_wstrb          (bridge_m_axi_wstrb),
        .s_axi_wlast          (bridge_m_axi_wlast),
        .s_axi_wvalid         (bridge_m_axi_wvalid),
        .s_axi_wready         (bridge_m_axi_wready),

        // S_AXI — B channel
        .s_axi_bready         (bridge_m_axi_bready),
        .s_axi_bid            (mig_s_axi_bid),                  // discard (Bridge has no bid)
        .s_axi_bresp          (bridge_m_axi_bresp),
        .s_axi_bvalid         (bridge_m_axi_bvalid),

        // S_AXI — AR channel
        .s_axi_arid           (8'b0),                           // ID_WIDTH=0 → zero-pad
        .s_axi_araddr         (bridge_m_axi_araddr[26:0]),      // 32→27 bit truncate
        .s_axi_arlen          (bridge_m_axi_arlen),
        .s_axi_arsize         (bridge_m_axi_arsize),
        .s_axi_arburst        (bridge_m_axi_arburst),
        .s_axi_arlock         (bridge_m_axi_arlock),
        .s_axi_arcache        (bridge_m_axi_arcache),
        .s_axi_arprot         (bridge_m_axi_arprot),
        .s_axi_arqos          (4'b0),                           // Bridge has no QoS
        .s_axi_arvalid        (bridge_m_axi_arvalid),
        .s_axi_arready        (bridge_m_axi_arready),

        // S_AXI — R channel
        .s_axi_rready         (bridge_m_axi_rready),
        .s_axi_rid            (mig_s_axi_rid),                  // discard (Bridge has no rid)
        .s_axi_rdata          (bridge_m_axi_rdata),
        .s_axi_rresp          (bridge_m_axi_rresp),
        .s_axi_rlast          (bridge_m_axi_rlast),
        .s_axi_rvalid         (bridge_m_axi_rvalid),

        // DDR3 SDRAM Pins
        .ddr3_addr            (ddr3_addr),
        .ddr3_ba              (ddr3_ba),
        .ddr3_ras_n           (ddr3_ras_n),
        .ddr3_cas_n           (ddr3_cas_n),
        .ddr3_we_n            (ddr3_we_n),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_ck_p            (ddr3_ck_p),
        .ddr3_ck_n            (ddr3_ck_n),
        .ddr3_cke             (ddr3_cke),
        .ddr3_dm              (ddr3_dm),
        .ddr3_dq              (ddr3_dq),
        .ddr3_dqs_p           (ddr3_dqs_p),
        .ddr3_dqs_n           (ddr3_dqs_n),
        .ddr3_odt             (ddr3_odt)
    );

endmodule
