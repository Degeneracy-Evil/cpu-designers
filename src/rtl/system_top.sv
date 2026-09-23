`timescale 1ns / 1ps
`include "soc_config.vh"
`include "axi4_def.svh"
`include "soc_addr_map.svh"

module system_top(
    input         clk,
    input         resetn,

    // DDR3_BYPASS_CLK_WIZ direct clock ports — when defined, the testbench
    // drives these directly, bypassing clk_wiz_0 / clk_wiz_0_passthrough
    // entirely. This gives the testbench full control over clock generation
    // (matching tb_ddr3_ahb_ex dual-clock architecture).
    // When DDR3_BYPASS_CLK_WIZ is NOT defined, these ports are unused.
    input         clk_system_bypass,      // 100MHz system clock (bypass mode)
    input         clk_ddr_ref_bypass,     // 200MHz DDR reference clock (bypass mode)
    input         clk_wiz_locked_bypass,  // MMCM locked indicator (bypass mode)

    input         uart_rx,
    output        uart_tx,

    input         spi_miso,
    output        spi_mosi,
    output        spi_ss,
    output        spi_clk,

    output [15:0] gpio_ctrl_out,
    output [15:0] gpio_data_out,

    inout  [15:0] gpio_io,

    // DDR3 SDRAM pins
    output [12:0] ddr3_addr,
    output [2:0]  ddr3_ba,
    output        ddr3_ras_n,
    output        ddr3_cas_n,
    output        ddr3_we_n,
    output        ddr3_reset_n,
    output [0:0]  ddr3_ck_p,
    output [0:0]  ddr3_ck_n,
    output [0:0]  ddr3_cke,
    output [1:0]  ddr3_dm,
    inout  [15:0] ddr3_dq,
    inout  [1:0]  ddr3_dqs_p,
    inout  [1:0]  ddr3_dqs_n,
    output [0:0]  ddr3_odt
);

    // ========================================================================
    // Clock + Reset Architecture — 3-branch generate (aligned with chiplab)
    // ========================================================================
    // Each branch generates clocks AND the corresponding reset chain.
    // Reset conditions differ per branch:
    //   sim_clk:      resetn & ddr_data_init            (clk_wiz_locked=1)
    //   sim_pll_clk:  resetn & clk_wiz_locked & ddr_data_init
    //   fpga_clk:     resetn & clk_wiz_locked & ddr_aresetn
    //
    // ddr_aresetn comes from axi_wrap_ddr (MIG init_calib_complete).
    // In SRAM mode, ddr_aresetn is tied to 1'b1 (no DDR3 calibration).
    // In simulation, ddr_data_init replaces ddr_aresetn (TB force-override).
    // ========================================================================
    wire cpu_clk;       // CPU clock domain
    wire sys_clk;       // System/interconnect clock domain (100MHz)
    wire ddr_clk_ref;   // 200MHz DDR reference clock
    wire clk_wiz_locked; // Clocking Wizard locked (FPGA path only; sim ties to 1)
    wire sys_resetn;    // Synchronized system reset (active-LOW)
    wire cpu_resetn;    // Synchronized CPU reset (active-LOW)

    // ddr_data_init: simulation-only gating signal
    // In simulation: TB forces to 0 initially, then 1 after DDR3 init + program load
    // In FPGA: tied to 1 (CPU boots from ROM, no DDR3 init gating)
    wire ddr_data_init;
`ifdef SIMULATION
    assign ddr_data_init = 1'b0;  // Default: system held in reset; TB overrides with force
`else
    assign ddr_data_init = 1'b1;  // FPGA: not used (ddr_aresetn gates reset instead)
`endif

    // ddr_aresetn: DDR3 calibration complete signal from axi_wrap_ddr
    // Declared here so the reset chain can reference it before the DDR3 generate block.
    // Driven by axi_wrap_ddr in DDR3 mode, or tied to 1'b1 in SRAM mode.
    wire ddr_aresetn;

`ifdef SIMULATION
    if (`SIMU_USE_PLL == 0) begin: sim_clk
        // Simulation: TB drives clocks directly, no PLL IP
        reg clk_91m, clk_200m;
        initial begin clk_91m = 1'b0; clk_200m = 1'b0; end
        always #5.5  clk_91m  = ~clk_91m;   // ~91MHz CPU
        always #2.5  clk_200m = ~clk_200m;  // 200MHz DDR ref
        assign cpu_clk     = clk_91m;
        assign sys_clk     = clk;            // 100MHz external
        assign ddr_clk_ref = clk_200m;
        assign clk_wiz_locked = 1'b1;        // No PLL in sim, always "locked"

        // Reset: resetn & ddr_data_init (clk_wiz_locked=1, so omitted)
        reset_sync u_rst_sys (
            .rst_n_in (resetn & ddr_data_init),
            .clk      (sys_clk),
            .rst_n_out(sys_resetn)
        );
        reset_sync u_rst_cpu (
            .rst_n_in (sys_resetn),
            .clk      (cpu_clk),
            .rst_n_out(cpu_resetn)
        );
    end
    else begin: sim_pll_clk
        // Simulation + PLL: use clk_wiz_0 (slow but more realistic)
        wire clk_wiz_locked_local;
        clk_wiz_0 u_clk_wiz_0 (
            .clk_in1  (clk),
            .clk_out1 (cpu_clk),     // 50MHz CPU core
            .clk_out2 (sys_clk),     // 100MHz AXI interconnect
            .clk_out3 (ddr_clk_ref), // 200MHz DDR reference
            .resetn   (resetn),
            .locked   (clk_wiz_locked_local)
        );
        assign clk_wiz_locked = clk_wiz_locked_local;

        // Reset: resetn & clk_wiz_locked & ddr_data_init
        reset_sync u_rst_sys (
            .rst_n_in (resetn & clk_wiz_locked & ddr_data_init),
            .clk      (sys_clk),
            .rst_n_out(sys_resetn)
        );
        reset_sync u_rst_cpu (
            .rst_n_in (sys_resetn),
            .clk      (cpu_clk),
            .rst_n_out(cpu_resetn)
        );
    end
`else
    // FPGA: use clk_wiz_0
    begin: fpga_clk
`ifdef DDR3_BYPASS_CLK_WIZ
        assign cpu_clk     = clk_system_bypass;
        assign sys_clk     = clk_system_bypass;
        assign ddr_clk_ref = clk_ddr_ref_bypass;
        assign clk_wiz_locked = clk_wiz_locked_bypass;
`else
        wire clk_wiz_locked_local;
        clk_wiz_0 u_clk_wiz_0 (
            .clk_in1  (clk),          // 100MHz external crystal
            .clk_out1 (cpu_clk),      // 50MHz CPU core
            .clk_out2 (sys_clk),      // 100MHz AXI interconnect
            .clk_out3 (ddr_clk_ref),  // 200MHz DDR reference
            .resetn   (resetn),
            .locked   (clk_wiz_locked_local)
        );
        assign clk_wiz_locked = clk_wiz_locked_local;
`endif

        // Reset: resetn & clk_wiz_locked & ddr_aresetn
        // ddr_aresetn = 1 only after MIG init_calib_complete,
        // ensuring system stays in reset until DDR3 is calibrated.
        reset_sync u_rst_sys (
            .rst_n_in (resetn & clk_wiz_locked & ddr_aresetn),
            .clk      (sys_clk),
            .rst_n_out(sys_resetn)
        );
        reset_sync u_rst_cpu (
            .rst_n_in (sys_resetn),
            .clk      (cpu_clk),
            .rst_n_out(cpu_resetn)
        );
    end
`endif

    // ========================================================================
    // CPU Instantiation — AXI4 ports
    // ========================================================================
    // CPU AXI4 master wires (cpu_clk domain)
    wire [3:0]  cpu_awid;
    wire [31:0] cpu_awaddr;
    wire [7:0]  cpu_awlen;
    wire [2:0]  cpu_awsize;
    wire [1:0]  cpu_awburst;
    wire        cpu_awlock;
    wire [3:0]  cpu_awcache;
    wire [2:0]  cpu_awprot;
    wire [3:0]  cpu_awqos;
    wire [3:0]  cpu_awregion;
    wire        cpu_awvalid;
    wire        cpu_awready;
    wire [31:0] cpu_wdata;
    wire [3:0]  cpu_wstrb;
    wire        cpu_wlast;
    wire        cpu_wvalid;
    wire        cpu_wready;
    wire [1:0]  cpu_bresp;
    wire        cpu_bvalid;
    wire        cpu_bready;
    wire [3:0]  cpu_arid;
    wire [31:0] cpu_araddr;
    wire [7:0]  cpu_arlen;
    wire [2:0]  cpu_arsize;
    wire [1:0]  cpu_arburst;
    wire        cpu_arlock;
    wire [3:0]  cpu_arcache;
    wire [2:0]  cpu_arprot;
    wire [3:0]  cpu_arqos;
    wire [3:0]  cpu_arregion;
    wire        cpu_arvalid;
    wire        cpu_arready;
    wire [31:0] cpu_rdata;
    wire [1:0]  cpu_rresp;
    wire        cpu_rlast;
    wire        cpu_rvalid;
    wire        cpu_rready;

    // Debug wires (preserved from original)
    wire [ 4:0] rf_addr;
    wire [31:0] rf_data;
    wire [31:0] if_pc;
    wire [31:0] if_inst;
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [31:0] exe_pc;
    wire [31:0] exe_inst;
    wire [31:0] mem_pc;
    wire [31:0] mem_inst;
    wire [31:0] wb_pc;
    wire [31:0] wb_inst;
    // IRQ wires
    wire [1:0]  plic_eip;
    wire        clint_mtip;
    wire        clint_msip;
    wire [63:0] clint_mtime;
    wire [63:0] clint_mtimecmp;
    logic       plic_eip_cpuclk_ff1, plic_eip_cpuclk_ff2;
    logic       plic_seip_cpuclk_ff1, plic_seip_cpuclk_ff2;
    logic       clint_mtip_cpuclk_ff1, clint_mtip_cpuclk_ff2;
    logic       clint_msip_cpuclk_ff1, clint_msip_cpuclk_ff2;
    // 64-bit mtime CDC: Gray-code synchronizer (sys_clk → cpu_clk)
    // Multi-bit shift-register sync would tear; Gray code guarantees
    // only 1 bit flips per increment, so 2-stage per-bit sync is safe.
    logic [63:0] clint_mtime_gray_r;     // Registered Gray-coded mtime (sys_clk domain)
    logic [63:0] clint_mtime_gray_sync1, clint_mtime_gray_sync2;  // 2-stage sync (cpu_clk domain)
    wire [63:0] clint_mtime_cpuclk;     // Decoded binary mtime (cpu_clk domain)
    wire        gpio_irq;
    wire        uart_irq;
    wire        spi_irq;

    wire        cpu_uart_tx;

    // Register the Gray encoder output before CDC so binary-counter bit skew
    // cannot appear as a combinational Gray-code glitch at the synchronizer.
    always_ff @(posedge sys_clk or negedge sys_resetn) begin
        if (!sys_resetn)
            clint_mtime_gray_r <= 64'b0;
        else
            clint_mtime_gray_r <= clint_mtime ^ (clint_mtime >> 1);
    end

    always_ff @(posedge cpu_clk or negedge cpu_resetn) begin
        if (!cpu_resetn) begin
            plic_eip_cpuclk_ff1   <= 1'b0;
            plic_eip_cpuclk_ff2   <= 1'b0;
            plic_seip_cpuclk_ff1  <= 1'b0;
            plic_seip_cpuclk_ff2  <= 1'b0;
            clint_mtip_cpuclk_ff1 <= 1'b0;
            clint_mtip_cpuclk_ff2 <= 1'b0;
            clint_msip_cpuclk_ff1 <= 1'b0;
            clint_msip_cpuclk_ff2 <= 1'b0;
            clint_mtime_gray_sync1 <= 64'b0;
            clint_mtime_gray_sync2 <= 64'b0;
        end else begin
            plic_eip_cpuclk_ff1   <= plic_eip[0];
            plic_eip_cpuclk_ff2   <= plic_eip_cpuclk_ff1;
            plic_seip_cpuclk_ff1  <= plic_eip[1];
            plic_seip_cpuclk_ff2  <= plic_seip_cpuclk_ff1;
            clint_mtip_cpuclk_ff1 <= clint_mtip;
            clint_mtip_cpuclk_ff2 <= clint_mtip_cpuclk_ff1;
            clint_msip_cpuclk_ff1 <= clint_msip;
            clint_msip_cpuclk_ff2 <= clint_msip_cpuclk_ff1;
            clint_mtime_gray_sync1 <= clint_mtime_gray_r;
            clint_mtime_gray_sync2 <= clint_mtime_gray_sync1;
        end
    end

    // Gray decoder: Gray code → binary (combinational, cpu_clk domain)
    // Prefix-XOR chain: bin[63]=gray[63], bin[i]=gray[i]^bin[i+1]
    assign clint_mtime_cpuclk[63] = clint_mtime_gray_sync2[63];
    genvar ggi;
    generate
        for (ggi = 0; ggi < 63; ggi = ggi + 1) begin : gen_gray_dec
            assign clint_mtime_cpuclk[ggi] = clint_mtime_gray_sync2[ggi] ^ clint_mtime_cpuclk[ggi+1];
        end
    endgenerate

    core_top cpu(
        .clk          (cpu_clk),
        .resetn       (cpu_resetn),
        .rf_addr      (rf_addr),
        .rf_data      (rf_data),
        .if_pc        (if_pc),
        .if_inst      (if_inst),
        .id_pc        (id_pc),
        .id_inst      (id_inst),
        .exe_pc       (exe_pc),
        .exe_inst     (exe_inst),
        .mem_pc       (mem_pc),
        .mem_inst     (mem_inst),
        .wb_pc        (wb_pc),
        .wb_inst      (wb_inst),
        // AXI4 AW Channel
        .awid         (cpu_awid),
        .awaddr       (cpu_awaddr),
        .awlen        (cpu_awlen),
        .awsize       (cpu_awsize),
        .awburst      (cpu_awburst),
        .awlock       (cpu_awlock),
        .awcache      (cpu_awcache),
        .awprot       (cpu_awprot),
        .awqos        (cpu_awqos),
        .awregion     (cpu_awregion),
        .awvalid      (cpu_awvalid),
        .awready      (cpu_awready),
        // AXI4 W Channel
        .wdata        (cpu_wdata),
        .wstrb        (cpu_wstrb),
        .wlast        (cpu_wlast),
        .wvalid       (cpu_wvalid),
        .wready       (cpu_wready),
        // AXI4 B Channel
        .bresp        (cpu_bresp),
        .bvalid       (cpu_bvalid),
        .bready       (cpu_bready),
        // AXI4 AR Channel
        .arid         (cpu_arid),
        .araddr       (cpu_araddr),
        .arlen        (cpu_arlen),
        .arsize       (cpu_arsize),
        .arburst      (cpu_arburst),
        .arlock       (cpu_arlock),
        .arcache      (cpu_arcache),
        .arprot       (cpu_arprot),
        .arqos        (cpu_arqos),
        .arregion     (cpu_arregion),
        .arvalid      (cpu_arvalid),
        .arready      (cpu_arready),
        // AXI4 R Channel
        .rdata        (cpu_rdata),
        .rresp        (cpu_rresp),
        .rlast        (cpu_rlast),
        .rvalid       (cpu_rvalid),
        .rready       (cpu_rready),
        // IRQ
        .init_sig     (1'b0),
        .timer_irq    (clint_mtip_cpuclk_ff2),
        .ext_meip_in  (plic_eip_cpuclk_ff2),
        .ext_seip_in  (plic_seip_cpuclk_ff2),
        .ext_msip_in  (clint_msip_cpuclk_ff2),
        .ext_mtime    (clint_mtime_cpuclk)
    );

    // ========================================================================
    // Axi_CDC: cpu_clk domain → sys_clk domain
    // ========================================================================
    // CDC output wires (sys_clk domain, full AXI4)
    wire        cdc_awvalid;
    wire        cdc_awready;
    wire [31:0] cdc_awaddr;
    wire [3:0]  cdc_awid;
    wire [7:0]  cdc_awlen;
    wire [2:0]  cdc_awsize;
    wire [1:0]  cdc_awburst;
    wire [0:0]  cdc_awlock;
    wire [3:0]  cdc_awcache;
    wire [2:0]  cdc_awprot;
    wire [3:0]  cdc_awqos;
    wire [3:0]  cdc_awregion;
    wire        cdc_wvalid;
    wire        cdc_wready;
    wire [31:0] cdc_wdata;
    wire [3:0]  cdc_wstrb;
    wire        cdc_wlast;
    wire        cdc_bvalid;
    wire        cdc_bready;
    wire [3:0]  cdc_bid;
    wire [1:0]  cdc_bresp;
    wire        cdc_arvalid;
    wire        cdc_arready;
    wire [31:0] cdc_araddr;
    wire [3:0]  cdc_arid;
    wire [7:0]  cdc_arlen;
    wire [2:0]  cdc_arsize;
    wire [1:0]  cdc_arburst;
    wire [0:0]  cdc_arlock;
    wire [3:0]  cdc_arcache;
    wire [2:0]  cdc_arprot;
    wire [3:0]  cdc_arqos;
    wire [3:0]  cdc_arregion;

    // QoS/Region not passed through CDC — tie to zero
    assign cdc_awqos    = 4'b0000;
    assign cdc_awregion = 4'b0000;
    assign cdc_arqos    = 4'b0000;
    assign cdc_arregion = 4'b0000;

    wire        cdc_rvalid;
    wire        cdc_rready;
    wire [31:0] cdc_rdata;
    wire [3:0]  cdc_rid;
    wire [1:0]  cdc_rresp;
    wire        cdc_rlast;

    Axi_CDC u_axi_cdc (
        .axiInClk       (cpu_clk),
        .axiInRst       (cpu_resetn),
        .axiOutClk      (sys_clk),
        .axiOutRst      (sys_resetn),
        // axiIn = CPU master side (cpu_clk domain)
        .axiIn_awvalid  (cpu_awvalid),
        .axiIn_awready  (cpu_awready),
        .axiIn_awaddr   (cpu_awaddr),
        .axiIn_awid     (cpu_awid),
        .axiIn_awlen    (cpu_awlen),
        .axiIn_awsize   (cpu_awsize),
        .axiIn_awburst  (cpu_awburst),
        .axiIn_awlock   (cpu_awlock),     // CPU 1-bit → CDC [0:0] compatible
        .axiIn_awcache  (cpu_awcache),
        .axiIn_awprot   (cpu_awprot),
        .axiIn_wvalid   (cpu_wvalid),
        .axiIn_wready   (cpu_wready),
        .axiIn_wdata    (cpu_wdata),
        .axiIn_wstrb    (cpu_wstrb),
        .axiIn_wlast    (cpu_wlast),
        .axiIn_bvalid   (cpu_bvalid),
        .axiIn_bready   (cpu_bready),
        .axiIn_bid      (),                   // CDC output (core_top has no bid input)
        .axiIn_bresp    (cpu_bresp),          // Connects to core_top.bresp
        .axiIn_arvalid  (cpu_arvalid),
        .axiIn_arready  (cpu_arready),
        .axiIn_araddr   (cpu_araddr),
        .axiIn_arid     (cpu_arid),
        .axiIn_arlen    (cpu_arlen),
        .axiIn_arsize   (cpu_arsize),
        .axiIn_arburst  (cpu_arburst),
        .axiIn_arlock   (cpu_arlock),     // CPU 1-bit → CDC [0:0] compatible
        .axiIn_arcache  (cpu_arcache),
        .axiIn_arprot   (cpu_arprot),
        .axiIn_rvalid   (cpu_rvalid),
        .axiIn_rready   (cpu_rready),
        .axiIn_rdata    (cpu_rdata),          // Connects to core_top.rdata
        .axiIn_rid      (),                   // CDC output (core_top has no rid input)
        .axiIn_rresp    (cpu_rresp),           // Connects to core_top.rresp
        .axiIn_rlast    (cpu_rlast),           // Connects to core_top.rlast
        // axiOut = crossbar side (sys_clk domain)
        .axiOut_awvalid (cdc_awvalid),
        .axiOut_awready (cdc_awready),
        .axiOut_awaddr  (cdc_awaddr),
        .axiOut_awid    (cdc_awid),
        .axiOut_awlen   (cdc_awlen),
        .axiOut_awsize  (cdc_awsize),
        .axiOut_awburst (cdc_awburst),
        .axiOut_awlock  (cdc_awlock),
        .axiOut_awcache (cdc_awcache),
        .axiOut_awprot  (cdc_awprot),
        .axiOut_wvalid  (cdc_wvalid),
        .axiOut_wready  (cdc_wready),
        .axiOut_wdata   (cdc_wdata),
        .axiOut_wstrb   (cdc_wstrb),
        .axiOut_wlast   (cdc_wlast),
        .axiOut_bvalid  (cdc_bvalid),
        .axiOut_bready  (cdc_bready),
        .axiOut_bid     (cdc_bid),
        .axiOut_bresp   (cdc_bresp),
        .axiOut_arvalid (cdc_arvalid),
        .axiOut_arready (cdc_arready),
        .axiOut_araddr  (cdc_araddr),
        .axiOut_arid    (cdc_arid),
        .axiOut_arlen   (cdc_arlen),
        .axiOut_arsize  (cdc_arsize),
        .axiOut_arburst (cdc_arburst),
        .axiOut_arlock  (cdc_arlock),
        .axiOut_arcache (cdc_arcache),
        .axiOut_arprot  (cdc_arprot),
        .axiOut_rvalid  (cdc_rvalid),
        .axiOut_rready  (cdc_rready),
        .axiOut_rdata   (cdc_rdata),
        .axiOut_rid     (cdc_rid),
        .axiOut_rresp   (cdc_rresp),
        .axiOut_rlast   (cdc_rlast)
    );

    // ========================================================================
    // Manual Address Decoder + Slave Mux (sys_clk domain, after CDC)
    // ========================================================================
    // Slave indices follow the exact base/size regions in soc_addr_map.svh:
    //   0: DDR3/RAM
    //   1: Boot ROM
    //   2: PLIC
    //   3: CLINT
    //   4: APB Bridge (GPIO, UART, or SPI only)
    //   5: Sys Status
    //   6: Default    (none of the above)

    function automatic logic addr_in_region(
        input logic [31:0] addr,
        input logic [31:0] base,
        input logic [31:0] size
    );
        logic [32:0] endpoint;
        begin
            endpoint = {1'b0, base} + {1'b0, size};
            addr_in_region = ({1'b0, addr} >= {1'b0, base}) &&
                             ({1'b0, addr} < endpoint);
        end
    endfunction

    wire aw_is_ddr       = addr_in_region(cdc_awaddr, `SOC_DDR_BASE, `SOC_DDR_SIZE);
    wire aw_is_bootrom   = addr_in_region(cdc_awaddr, `SOC_BOOTROM_BASE, `SOC_BOOTROM_SIZE);
    wire aw_is_plic      = addr_in_region(cdc_awaddr, `SOC_PLIC_BASE, `SOC_PLIC_SIZE);
    wire aw_is_clint     = addr_in_region(cdc_awaddr, `SOC_CLINT_BASE, `SOC_CLINT_SIZE);
    wire aw_is_gpio      = addr_in_region(cdc_awaddr, `SOC_APB_GPIO_BASE, `SOC_APB_GPIO_SIZE);
    wire aw_is_uart      = addr_in_region(cdc_awaddr, `SOC_APB_UART_BASE, `SOC_APB_UART_SIZE);
    wire aw_is_spi       = addr_in_region(cdc_awaddr, `SOC_APB_SPI_BASE, `SOC_APB_SPI_SIZE);
    wire aw_is_sysstatus = addr_in_region(cdc_awaddr, `SOC_SYSSTATUS_BASE, `SOC_SYSSTATUS_SIZE);
    wire aw_is_apb       = aw_is_gpio || aw_is_uart || aw_is_spi;

    wire ar_is_ddr       = addr_in_region(cdc_araddr, `SOC_DDR_BASE, `SOC_DDR_SIZE);
    wire ar_is_bootrom   = addr_in_region(cdc_araddr, `SOC_BOOTROM_BASE, `SOC_BOOTROM_SIZE);
    wire ar_is_plic      = addr_in_region(cdc_araddr, `SOC_PLIC_BASE, `SOC_PLIC_SIZE);
    wire ar_is_clint     = addr_in_region(cdc_araddr, `SOC_CLINT_BASE, `SOC_CLINT_SIZE);
    wire ar_is_gpio      = addr_in_region(cdc_araddr, `SOC_APB_GPIO_BASE, `SOC_APB_GPIO_SIZE);
    wire ar_is_uart      = addr_in_region(cdc_araddr, `SOC_APB_UART_BASE, `SOC_APB_UART_SIZE);
    wire ar_is_spi       = addr_in_region(cdc_araddr, `SOC_APB_SPI_BASE, `SOC_APB_SPI_SIZE);
    wire ar_is_sysstatus = addr_in_region(cdc_araddr, `SOC_SYSSTATUS_BASE, `SOC_SYSSTATUS_SIZE);
    wire ar_is_apb       = ar_is_gpio || ar_is_uart || ar_is_spi;

    // AW channel address decode (combinational)
    wire [2:0] aw_slave_sel_comb;
    assign aw_slave_sel_comb = aw_is_ddr       ? 3'd0 :
                               aw_is_bootrom   ? 3'd1 :
                               aw_is_plic      ? 3'd2 :
                               aw_is_clint     ? 3'd3 :
                               aw_is_apb       ? 3'd4 :
                               aw_is_sysstatus ? 3'd5 :
                               3'd6;

    // AR channel address decode (combinational)
    wire [2:0] ar_slave_sel_comb;
    assign ar_slave_sel_comb = ar_is_ddr       ? 3'd0 :
                               ar_is_bootrom   ? 3'd1 :
                               ar_is_plic      ? 3'd2 :
                               ar_is_clint     ? 3'd3 :
                               ar_is_apb       ? 3'd4 :
                               ar_is_sysstatus ? 3'd5 :
                               3'd6;

    // Handshake-owned routing state.
    // This interconnect supports one outstanding write and one outstanding
    // read at a time. Route selection is captured on the accepted address
    // handshake and held until the corresponding response completes.
    reg [2:0] aw_slave_sel;
    reg       write_busy_r;
    always_ff @(posedge sys_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            aw_slave_sel <= 3'd6;
            write_busy_r <= 1'b0;
        end else begin
            if (!write_busy_r && cdc_awvalid && cdc_awready) begin
                aw_slave_sel <= aw_slave_sel_comb;
                write_busy_r <= 1'b1;
            end else if (write_busy_r && cdc_bvalid && cdc_bready) begin
                write_busy_r <= 1'b0;
            end
        end
    end

    reg [2:0] ar_slave_sel;
    reg       read_busy_r;
    always_ff @(posedge sys_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            ar_slave_sel <= 3'd6;
            read_busy_r  <= 1'b0;
        end else begin
            if (!read_busy_r && cdc_arvalid && cdc_arready) begin
                ar_slave_sel <= ar_slave_sel_comb;
                read_busy_r  <= 1'b1;
            end else if (read_busy_r && cdc_rvalid && cdc_rready && cdc_rlast) begin
                read_busy_r <= 1'b0;
            end
        end
    end

    // ========================================================================
    // DDR3/RAM slave wires (full AXI4)
    // ========================================================================
    wire        ddr_awvalid,  ddr_awready;
    wire [31:0] ddr_awaddr;
    wire [3:0]  ddr_awid;
    wire [7:0]  ddr_awlen;
    wire [2:0]  ddr_awsize;
    wire [1:0]  ddr_awburst;
    wire        ddr_awlock;
    wire [3:0]  ddr_awcache;
    wire [2:0]  ddr_awprot;
    wire        ddr_wvalid,   ddr_wready;
    wire [31:0] ddr_wdata;
    wire [3:0]  ddr_wstrb;
    wire        ddr_wlast;
    wire        ddr_bvalid,   ddr_bready;
    wire [3:0]  ddr_bid;
    wire [1:0]  ddr_bresp;
    wire        ddr_arvalid,  ddr_arready;
    wire [31:0] ddr_araddr;
    wire [3:0]  ddr_arid;
    wire [7:0]  ddr_arlen;
    wire [2:0]  ddr_arsize;
    wire [1:0]  ddr_arburst;
    wire        ddr_arlock;
    wire [3:0]  ddr_arcache;
    wire [2:0]  ddr_arprot;
    wire        ddr_rvalid,   ddr_rready;
    wire [31:0] ddr_rdata;
    wire [3:0]  ddr_rid;
    wire [1:0]  ddr_rresp;
    wire        ddr_rlast;

    // ========================================================================
    // AXI4-Lite slave wires — Boot ROM
    // ========================================================================
    wire        bootrom_awvalid,  bootrom_awready;
    wire [31:0] bootrom_awaddr;
    wire [2:0]  bootrom_awprot;
    wire        bootrom_wvalid,   bootrom_wready;
    wire [31:0] bootrom_wdata;
    wire [3:0]  bootrom_wstrb;
    wire        bootrom_bvalid,   bootrom_bready;
    wire [1:0]  bootrom_bresp;
    wire        bootrom_arvalid,  bootrom_arready;
    wire [31:0] bootrom_araddr;
    wire [2:0]  bootrom_arprot;
    wire        bootrom_rvalid,   bootrom_rready;
    wire [31:0] bootrom_rdata;
    wire [1:0]  bootrom_rresp;

    // ========================================================================
    // AXI4-Lite slave wires — PLIC
    // ========================================================================
    wire        plic_awvalid,  plic_awready;
    wire [31:0] plic_awaddr;
    wire [2:0]  plic_awprot;
    wire        plic_wvalid,   plic_wready;
    wire [31:0] plic_wdata;
    wire [3:0]  plic_wstrb;
    wire        plic_bvalid,   plic_bready;
    wire [1:0]  plic_bresp;
    wire        plic_arvalid,  plic_arready;
    wire [31:0] plic_araddr;
    wire [2:0]  plic_arprot;
    wire        plic_rvalid,   plic_rready;
    wire [31:0] plic_rdata;
    wire [1:0]  plic_rresp;

    // ========================================================================
    // AXI4-Lite slave wires — CLINT
    // ========================================================================
    wire        clint_awvalid,  clint_awready;
    wire [31:0] clint_awaddr;
    wire [2:0]  clint_awprot;
    wire        clint_wvalid,   clint_wready;
    wire [31:0] clint_wdata;
    wire [3:0]  clint_wstrb;
    wire        clint_bvalid,   clint_bready;
    wire [1:0]  clint_bresp;
    wire        clint_arvalid,  clint_arready;
    wire [31:0] clint_araddr;
    wire [2:0]  clint_arprot;
    wire        clint_rvalid,   clint_rready;
    wire [31:0] clint_rdata;
    wire [1:0]  clint_rresp;

    // ========================================================================
    // AXI4-Lite slave wires — APB Bridge
    // ========================================================================
    wire        apb_awvalid,  apb_awready;
    wire [31:0] apb_awaddr;
    wire [2:0]  apb_awprot;
    wire        apb_wvalid,   apb_wready;
    wire [31:0] apb_wdata;
    wire [3:0]  apb_wstrb;
    wire        apb_bvalid,   apb_bready;
    wire [1:0]  apb_bresp;
    wire        apb_arvalid,  apb_arready;
    wire [31:0] apb_araddr;
    wire [2:0]  apb_arprot;
    wire        apb_rvalid,   apb_rready;
    wire [31:0] apb_rdata;
    wire [1:0]  apb_rresp;

    // ========================================================================
    // AXI4-Lite slave wires — Sys Status
    // ========================================================================
    wire        syssts_awvalid,  syssts_awready;
    wire [31:0] syssts_awaddr;
    wire [2:0]  syssts_awprot;
    wire        syssts_wvalid,   syssts_wready;
    wire [31:0] syssts_wdata;
    wire [3:0]  syssts_wstrb;
    wire        syssts_bvalid,   syssts_bready;
    wire [1:0]  syssts_bresp;
    wire        syssts_arvalid,  syssts_arready;
    wire [31:0] syssts_araddr;
    wire [2:0]  syssts_arprot;
    wire        syssts_rvalid,   syssts_rready;
    wire [31:0] syssts_rdata;
    wire [1:0]  syssts_rresp;

    // ========================================================================
    // AXI4-Lite slave wires — Default Slave
    // ========================================================================
    wire        default_awvalid,  default_awready;
    wire [31:0] default_awaddr;
    wire [2:0]  default_awprot;
    wire        default_wvalid,   default_wready;
    wire [31:0] default_wdata;
    wire [3:0]  default_wstrb;
    wire        default_bvalid,   default_bready;
    wire [1:0]  default_bresp;
    wire        default_arvalid,  default_arready;
    wire [31:0] default_araddr;
    wire [2:0]  default_arprot;
    wire        default_rvalid,   default_rready;
    wire [31:0] default_rdata;
    wire [1:0]  default_rresp;

    // ========================================================================
    // Address Decoder: Route CDC master to slaves
    // ========================================================================

    // --- AW channel routing ---
    // DDR3/RAM (slave 0) — full AXI4
    assign ddr_awvalid  = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd0);
    assign ddr_awaddr   = cdc_awaddr;
    assign ddr_awid     = cdc_awid;
    assign ddr_awlen    = cdc_awlen;
    assign ddr_awsize   = cdc_awsize;
    assign ddr_awburst  = cdc_awburst;
    assign ddr_awlock   = cdc_awlock;
    assign ddr_awcache  = cdc_awcache;


    assign ddr_awprot   = cdc_awprot;

    // Boot ROM (slave 1) — AXI4-Lite
    assign bootrom_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd1);
    assign bootrom_awaddr  = cdc_awaddr;
    assign bootrom_awprot  = cdc_awprot;

    // PLIC (slave 2) — AXI4-Lite
    assign plic_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd2);
    assign plic_awaddr  = cdc_awaddr;
    assign plic_awprot  = cdc_awprot;

    // CLINT (slave 3) — AXI4-Lite
    assign clint_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd3);
    assign clint_awaddr  = cdc_awaddr;
    assign clint_awprot  = cdc_awprot;

    // APB Bridge (slave 4) — AXI4-Lite
    assign apb_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd4);
    assign apb_awaddr  = cdc_awaddr;
    assign apb_awprot  = cdc_awprot;

    // Sys Status (slave 5) — AXI4-Lite
    assign syssts_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd5);
    assign syssts_awaddr  = cdc_awaddr;
    assign syssts_awprot  = cdc_awprot;

    // Default (slave 6) — AXI4-Lite
    assign default_awvalid = !write_busy_r && cdc_awvalid && (aw_slave_sel_comb == 3'd6);
    assign default_awaddr  = cdc_awaddr;
    assign default_awprot  = cdc_awprot;

    // AW ready mux back to CDC master
    wire aw_ready_mux = (aw_slave_sel_comb == 3'd0) ? ddr_awready    :
                        (aw_slave_sel_comb == 3'd1) ? bootrom_awready :
                        (aw_slave_sel_comb == 3'd2) ? plic_awready    :
                        (aw_slave_sel_comb == 3'd3) ? clint_awready   :
                        (aw_slave_sel_comb == 3'd4) ? apb_awready     :
                        (aw_slave_sel_comb == 3'd5) ? syssts_awready  :
                                                     default_awready;
    assign cdc_awready = !write_busy_r && aw_ready_mux;

    // --- W channel routing (follows the active write transaction) ---
    // W may legally be presented before or alongside AW. This interconnect
    // stalls W until the AW handshake captures the target slave.
    wire w_handshake_starts = !write_busy_r && cdc_awvalid && cdc_awready;
    wire w_route_valid = write_busy_r || w_handshake_starts;
    wire [2:0] w_slave_sel = write_busy_r ? aw_slave_sel :
                             w_handshake_starts ? aw_slave_sel_comb :
                             3'd6;

    assign ddr_wvalid    = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd0);
    assign ddr_wdata     = cdc_wdata;
    assign ddr_wstrb     = cdc_wstrb;
    assign ddr_wlast     = cdc_wlast;

    assign bootrom_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd1);
    assign bootrom_wdata  = cdc_wdata;
    assign bootrom_wstrb  = cdc_wstrb;

    assign plic_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd2);
    assign plic_wdata  = cdc_wdata;
    assign plic_wstrb  = cdc_wstrb;

    assign clint_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd3);
    assign clint_wdata  = cdc_wdata;
    assign clint_wstrb  = cdc_wstrb;

    assign apb_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd4);
    assign apb_wdata  = cdc_wdata;
    assign apb_wstrb  = cdc_wstrb;

    assign syssts_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd5);
    assign syssts_wdata  = cdc_wdata;
    assign syssts_wstrb  = cdc_wstrb;

    assign default_wvalid = w_route_valid && cdc_wvalid && (w_slave_sel == 3'd6);
    assign default_wdata  = cdc_wdata;
    assign default_wstrb  = cdc_wstrb;

    // W ready mux back to CDC master
    assign cdc_wready = !w_route_valid ? 1'b0 :
                        (w_slave_sel == 3'd0) ? ddr_wready    :
                        (w_slave_sel == 3'd1) ? bootrom_wready :
                        (w_slave_sel == 3'd2) ? plic_wready    :
                        (w_slave_sel == 3'd3) ? clint_wready   :
                        (w_slave_sel == 3'd4) ? apb_wready     :
                        (w_slave_sel == 3'd5) ? syssts_wready  :
                        default_wready;

    // --- B channel routing (follows aw_slave_sel, per AXI spec BID=AWID) ---
    assign ddr_bready    = write_busy_r && cdc_bready && (aw_slave_sel == 3'd0);
    assign bootrom_bready = write_busy_r && cdc_bready && (aw_slave_sel == 3'd1);
    assign plic_bready    = write_busy_r && cdc_bready && (aw_slave_sel == 3'd2);
    assign clint_bready   = write_busy_r && cdc_bready && (aw_slave_sel == 3'd3);
    assign apb_bready     = write_busy_r && cdc_bready && (aw_slave_sel == 3'd4);
    assign syssts_bready  = write_busy_r && cdc_bready && (aw_slave_sel == 3'd5);
    assign default_bready = write_busy_r && cdc_bready && (aw_slave_sel == 3'd6);

    // B response mux back to CDC master
    assign cdc_bvalid = !write_busy_r ? 1'b0 :
                        (aw_slave_sel == 3'd0) ? ddr_bvalid    :
                        (aw_slave_sel == 3'd1) ? bootrom_bvalid :
                        (aw_slave_sel == 3'd2) ? plic_bvalid    :
                        (aw_slave_sel == 3'd3) ? clint_bvalid   :
                        (aw_slave_sel == 3'd4) ? apb_bvalid     :
                        (aw_slave_sel == 3'd5) ? syssts_bvalid  :
                        default_bvalid;

    assign cdc_bresp = !write_busy_r ? 2'b00 :
                       (aw_slave_sel == 3'd0) ? ddr_bresp    :
                       (aw_slave_sel == 3'd1) ? bootrom_bresp :
                       (aw_slave_sel == 3'd2) ? plic_bresp    :
                       (aw_slave_sel == 3'd3) ? clint_bresp   :
                       (aw_slave_sel == 3'd4) ? apb_bresp     :
                       (aw_slave_sel == 3'd5) ? syssts_bresp  :
                       default_bresp;

    assign cdc_bid = (write_busy_r && (aw_slave_sel == 3'd0)) ? ddr_bid : 4'b0;

    // --- AR channel routing ---
    assign ddr_arvalid  = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd0);
    assign ddr_araddr   = cdc_araddr;
    assign ddr_arid     = cdc_arid;
    assign ddr_arlen    = cdc_arlen;
    assign ddr_arsize   = cdc_arsize;
    assign ddr_arburst  = cdc_arburst;
    assign ddr_arlock   = cdc_arlock;
    assign ddr_arcache  = cdc_arcache;
    assign ddr_arprot   = cdc_arprot;

    assign bootrom_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd1);
    assign bootrom_araddr  = cdc_araddr;
    assign bootrom_arprot  = cdc_arprot;

    assign plic_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd2);
    assign plic_araddr  = cdc_araddr;
    assign plic_arprot  = cdc_arprot;

    assign clint_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd3);
    assign clint_araddr  = cdc_araddr;
    assign clint_arprot  = cdc_arprot;

    assign apb_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd4);
    assign apb_araddr  = cdc_araddr;
    assign apb_arprot  = cdc_arprot;

    assign syssts_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd5);
    assign syssts_araddr  = cdc_araddr;
    assign syssts_arprot  = cdc_arprot;

    assign default_arvalid = !read_busy_r && cdc_arvalid && (ar_slave_sel_comb == 3'd6);
    assign default_araddr  = cdc_araddr;
    assign default_arprot  = cdc_arprot;

    // AR ready mux back to CDC master
    wire ar_ready_mux = (ar_slave_sel_comb == 3'd0) ? ddr_arready    :
                        (ar_slave_sel_comb == 3'd1) ? bootrom_arready :
                        (ar_slave_sel_comb == 3'd2) ? plic_arready    :
                        (ar_slave_sel_comb == 3'd3) ? clint_arready   :
                        (ar_slave_sel_comb == 3'd4) ? apb_arready     :
                        (ar_slave_sel_comb == 3'd5) ? syssts_arready  :
                                                     default_arready;
    assign cdc_arready = !read_busy_r && ar_ready_mux;

    // --- R channel routing (follows latched AR slave select) ---
    assign ddr_rready    = read_busy_r && cdc_rready && (ar_slave_sel == 3'd0);
    assign bootrom_rready = read_busy_r && cdc_rready && (ar_slave_sel == 3'd1);
    assign plic_rready    = read_busy_r && cdc_rready && (ar_slave_sel == 3'd2);
    assign clint_rready   = read_busy_r && cdc_rready && (ar_slave_sel == 3'd3);
    assign apb_rready     = read_busy_r && cdc_rready && (ar_slave_sel == 3'd4);
    assign syssts_rready  = read_busy_r && cdc_rready && (ar_slave_sel == 3'd5);
    assign default_rready = read_busy_r && cdc_rready && (ar_slave_sel == 3'd6);

    // R response mux back to CDC master
    assign cdc_rvalid = !read_busy_r ? 1'b0 :
                        (ar_slave_sel == 3'd0) ? ddr_rvalid    :
                        (ar_slave_sel == 3'd1) ? bootrom_rvalid :
                        (ar_slave_sel == 3'd2) ? plic_rvalid    :
                        (ar_slave_sel == 3'd3) ? clint_rvalid   :
                        (ar_slave_sel == 3'd4) ? apb_rvalid     :
                        (ar_slave_sel == 3'd5) ? syssts_rvalid  :
                        default_rvalid;

    assign cdc_rdata = !read_busy_r ? 32'b0 :
                       (ar_slave_sel == 3'd0) ? ddr_rdata    :
                       (ar_slave_sel == 3'd1) ? bootrom_rdata :
                       (ar_slave_sel == 3'd2) ? plic_rdata    :
                       (ar_slave_sel == 3'd3) ? clint_rdata   :
                       (ar_slave_sel == 3'd4) ? apb_rdata     :
                       (ar_slave_sel == 3'd5) ? syssts_rdata  :
                       default_rdata;

    assign cdc_rresp = !read_busy_r ? 2'b00 :
                       (ar_slave_sel == 3'd0) ? ddr_rresp    :
                       (ar_slave_sel == 3'd1) ? bootrom_rresp :
                       (ar_slave_sel == 3'd2) ? plic_rresp    :
                       (ar_slave_sel == 3'd3) ? clint_rresp   :
                       (ar_slave_sel == 3'd4) ? apb_rresp     :
                       (ar_slave_sel == 3'd5) ? syssts_rresp  :
                       default_rresp;

    assign cdc_rlast = !read_busy_r ? 1'b0 :
                       (ar_slave_sel == 3'd0) ? ddr_rlast : 1'b1;
    // AXI4-Lite slaves always return rlast=1 (single beat)

    assign cdc_rid = (read_busy_r && (ar_slave_sel == 3'd0)) ? ddr_rid : 4'b0;

    // ========================================================================
    // DDR3/SRAM Conditional Generate
    // ========================================================================
    // ddr_aresetn is declared above (in clock/reset section) so the reset
    // chain can reference it.  Here we drive it:
    //   SRAM mode:  ddr_aresetn = 1 (no DDR3 calibration to wait for)
    //   DDR3 mode:  driven by axi_wrap_ddr output

`ifdef SIMULATION
    if (`SIMU_USE_DDR == 0) begin: sim_ram
        // SRAM model — fast simulation
        axi_wrap_ram u_axi_ram (
            .aclk           (sys_clk),
            .aresetn        (sys_resetn),
            // AR channel
            .axi_arid       (ddr_arid),
            .axi_araddr     (ddr_araddr),
            .axi_arlen      (ddr_arlen),
            .axi_arsize     (ddr_arsize),
            .axi_arburst    (ddr_arburst),
            .axi_arlock     (ddr_arlock),
            .axi_arcache    (ddr_arcache),
            .axi_arprot     (ddr_arprot),
            .axi_arvalid    (ddr_arvalid),
            .axi_arready    (ddr_arready),
            // R channel
            .axi_rid        (ddr_rid),
            .axi_rdata      (ddr_rdata),
            .axi_rresp      (ddr_rresp),
            .axi_rlast      (ddr_rlast),
            .axi_rvalid     (ddr_rvalid),
            .axi_rready     (ddr_rready),
            // AW channel
            .axi_awid       (ddr_awid),
            .axi_awaddr     (ddr_awaddr),
            .axi_awlen      (ddr_awlen),
            .axi_awsize     (ddr_awsize),
            .axi_awburst    (ddr_awburst),
            .axi_awlock     (ddr_awlock),
            .axi_awcache    (ddr_awcache),
            .axi_awprot     (ddr_awprot),
            .axi_awvalid    (ddr_awvalid),
            .axi_awready    (ddr_awready),
            // W channel
            .axi_wdata      (ddr_wdata),
            .axi_wstrb      (ddr_wstrb),
            .axi_wlast      (ddr_wlast),
            .axi_wvalid     (ddr_wvalid),
            .axi_wready     (ddr_wready),
            // B channel
            .axi_bid        (ddr_bid),
            .axi_bresp      (ddr_bresp),
            .axi_bvalid     (ddr_bvalid),
            .axi_bready     (ddr_bready),
            .ram_random_mask(5'b0)
        );
        // No DDR3 pins in SRAM mode — tie off top-level outputs
        // ddr_aresetn = 1: no DDR3 calibration to wait for;
        // using 1'b1 (not sys_resetn) avoids circular dependency
        // now that FPGA reset chain gates on ddr_aresetn.
        assign ddr_aresetn   = 1'b1;
        assign ddr3_addr     = 13'b0;
        assign ddr3_ba       = 3'b0;
        assign ddr3_ras_n    = 1'b1;
        assign ddr3_cas_n    = 1'b1;
        assign ddr3_we_n     = 1'b1;
        assign ddr3_reset_n  = 1'b0;
        assign ddr3_ck_p     = 1'b0;
        assign ddr3_ck_n     = 1'b1;
        assign ddr3_cke      = 1'b0;
        assign ddr3_dm       = 2'b0;
        assign ddr3_odt      = 1'b0;
    end
    else begin: ddr3
        // DDR3 via MIG
        axi_wrap_ddr u_axi_wrap_ddr (
            .aclk           (sys_clk),
            .aresetn        (sys_resetn),
            .xtal_clk       (clk),           // 100MHz external crystal
            .button_resetn  (resetn),
            .ddr_clk_ref    (ddr_clk_ref),
            .ddr_aresetn    (ddr_aresetn),
            // AR channel
            .axi_arid       (ddr_arid),
            .axi_araddr     (ddr_araddr),
            .axi_arlen      (ddr_arlen),
            .axi_arsize     (ddr_arsize),
            .axi_arburst    (ddr_arburst),
            .axi_arlock     (ddr_arlock),
            .axi_arcache    (ddr_arcache),
            .axi_arprot     (ddr_arprot),
            .axi_arvalid    (ddr_arvalid),
            .axi_arready    (ddr_arready),
            // R channel
            .axi_rid        (ddr_rid),
            .axi_rdata      (ddr_rdata),
            .axi_rresp      (ddr_rresp),
            .axi_rlast      (ddr_rlast),
            .axi_rvalid     (ddr_rvalid),
            .axi_rready     (ddr_rready),
            // AW channel
            .axi_awid       (ddr_awid),
            .axi_awaddr     (ddr_awaddr),
            .axi_awlen      (ddr_awlen),
            .axi_awsize     (ddr_awsize),
            .axi_awburst    (ddr_awburst),
            .axi_awlock     (ddr_awlock),
            .axi_awcache    (ddr_awcache),
            .axi_awprot     (ddr_awprot),
            .axi_awvalid    (ddr_awvalid),
            .axi_awready    (ddr_awready),
            // W channel
            .axi_wdata      (ddr_wdata),
            .axi_wstrb      (ddr_wstrb),
            .axi_wlast      (ddr_wlast),
            .axi_wvalid     (ddr_wvalid),
            .axi_wready     (ddr_wready),
            // B channel
            .axi_bid        (ddr_bid),
            .axi_bresp      (ddr_bresp),
            .axi_bvalid     (ddr_bvalid),
            .axi_bready     (ddr_bready),
            .ram_random_mask(5'b0),
            // DDR3 physical pins
            .ddr3_dq        (ddr3_dq),
            .ddr3_addr      (ddr3_addr),
            .ddr3_ba        (ddr3_ba),
            .ddr3_ras_n     (ddr3_ras_n),
            .ddr3_cas_n     (ddr3_cas_n),
            .ddr3_we_n      (ddr3_we_n),
            .ddr3_odt       (ddr3_odt),
            .ddr3_reset_n   (ddr3_reset_n),
            .ddr3_cke       (ddr3_cke),
            .ddr3_dm        (ddr3_dm),
            .ddr3_dqs_p     (ddr3_dqs_p),
            .ddr3_dqs_n     (ddr3_dqs_n),
            .ddr3_ck_p      (ddr3_ck_p[0]),   // scalar, not [0:0]
            .ddr3_ck_n      (ddr3_ck_n[0])
        );
    end
`else
    // FPGA: always DDR3
    begin: ddr3
        axi_wrap_ddr u_axi_wrap_ddr (
            .aclk           (sys_clk),
            .aresetn        (sys_resetn),
            .xtal_clk       (clk),
            .button_resetn  (resetn),
            .ddr_clk_ref    (ddr_clk_ref),
            .ddr_aresetn    (ddr_aresetn),
            // AR channel
            .axi_arid       (ddr_arid),
            .axi_araddr     (ddr_araddr),
            .axi_arlen      (ddr_arlen),
            .axi_arsize     (ddr_arsize),
            .axi_arburst    (ddr_arburst),
            .axi_arlock     (ddr_arlock),
            .axi_arcache    (ddr_arcache),
            .axi_arprot     (ddr_arprot),
            .axi_arvalid    (ddr_arvalid),
            .axi_arready    (ddr_arready),
            // R channel
            .axi_rid        (ddr_rid),
            .axi_rdata      (ddr_rdata),
            .axi_rresp      (ddr_rresp),
            .axi_rlast      (ddr_rlast),
            .axi_rvalid     (ddr_rvalid),
            .axi_rready     (ddr_rready),
            // AW channel
            .axi_awid       (ddr_awid),
            .axi_awaddr     (ddr_awaddr),
            .axi_awlen      (ddr_awlen),
            .axi_awsize     (ddr_awsize),
            .axi_awburst    (ddr_awburst),
            .axi_awlock     (ddr_awlock),
            .axi_awcache    (ddr_awcache),
            .axi_awprot     (ddr_awprot),
            .axi_awvalid    (ddr_awvalid),
            .axi_awready    (ddr_awready),
            // W channel
            .axi_wdata      (ddr_wdata),
            .axi_wstrb      (ddr_wstrb),
            .axi_wlast      (ddr_wlast),
            .axi_wvalid     (ddr_wvalid),
            .axi_wready     (ddr_wready),
            // B channel
            .axi_bid        (ddr_bid),
            .axi_bresp      (ddr_bresp),
            .axi_bvalid     (ddr_bvalid),
            .axi_bready     (ddr_bready),
            .ram_random_mask(5'b0),
            // DDR3 physical pins
            .ddr3_dq        (ddr3_dq),
            .ddr3_addr      (ddr3_addr),
            .ddr3_ba        (ddr3_ba),
            .ddr3_ras_n     (ddr3_ras_n),
            .ddr3_cas_n     (ddr3_cas_n),
            .ddr3_we_n      (ddr3_we_n),
            .ddr3_odt       (ddr3_odt),
            .ddr3_reset_n   (ddr3_reset_n),
            .ddr3_cke       (ddr3_cke),
            .ddr3_dm        (ddr3_dm),
            .ddr3_dqs_p     (ddr3_dqs_p),
            .ddr3_dqs_n     (ddr3_dqs_n),
            .ddr3_ck_p      (ddr3_ck_p[0]),
            .ddr3_ck_n      (ddr3_ck_n[0])
        );
    end
`endif

    // ========================================================================
    // PLIC IRQ Sources
    // ========================================================================
    wire [7:0] plic_src_irq;
    assign plic_src_irq[0] = 1'b0;
    assign plic_src_irq[1] = 1'b0;   // APB Timer removed — source[1] unused
    assign plic_src_irq[2] = uart_irq;
    assign plic_src_irq[3] = spi_irq;
    assign plic_src_irq[4] = gpio_irq;
    assign plic_src_irq[5] = 1'b0;
    assign plic_src_irq[6] = 1'b0;
    assign plic_src_irq[7] = 1'b0;

    // ========================================================================
    // AXI4-Lite Slave: PLIC
    // ========================================================================
    axi4lite_plic u_plic (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (sys_resetn),
        .s_axi_awaddr  (plic_awaddr),
        .s_axi_awprot  (plic_awprot),
        .s_axi_awvalid (plic_awvalid),
        .s_axi_awready (plic_awready),
        .s_axi_wdata   (plic_wdata),
        .s_axi_wstrb   (plic_wstrb),
        .s_axi_wvalid  (plic_wvalid),
        .s_axi_wready  (plic_wready),
        .s_axi_bresp   (plic_bresp),
        .s_axi_bvalid  (plic_bvalid),
        .s_axi_bready  (plic_bready),
        .s_axi_araddr  (plic_araddr),
        .s_axi_arprot  (plic_arprot),
        .s_axi_arvalid (plic_arvalid),
        .s_axi_arready (plic_arready),
        .s_axi_rdata   (plic_rdata),
        .s_axi_rresp   (plic_rresp),
        .s_axi_rvalid  (plic_rvalid),
        .s_axi_rready  (plic_rready),
        .src_irq       (plic_src_irq),
        .o_eip         (plic_eip)    // [0]=M-mode, [1]=S-mode (future)
    );

    // ========================================================================
    // AXI4-Lite Slave: CLINT
    // ========================================================================
    axi4lite_clint u_clint (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (sys_resetn),
        .s_axi_awaddr  (clint_awaddr),
        .s_axi_awprot  (clint_awprot),
        .s_axi_awvalid (clint_awvalid),
        .s_axi_awready (clint_awready),
        .s_axi_wdata   (clint_wdata),
        .s_axi_wstrb   (clint_wstrb),
        .s_axi_wvalid  (clint_wvalid),
        .s_axi_wready  (clint_wready),
        .s_axi_bresp   (clint_bresp),
        .s_axi_bvalid  (clint_bvalid),
        .s_axi_bready  (clint_bready),
        .s_axi_araddr  (clint_araddr),
        .s_axi_arprot  (clint_arprot),
        .s_axi_arvalid (clint_arvalid),
        .s_axi_arready (clint_arready),
        .s_axi_rdata   (clint_rdata),
        .s_axi_rresp   (clint_rresp),
        .s_axi_rvalid  (clint_rvalid),
        .s_axi_rready  (clint_rready),
        .o_mtip        (clint_mtip),
        .o_msip        (clint_msip),
        .o_mtime       (clint_mtime),
        .o_mtimecmp    (clint_mtimecmp)
    );

    // ========================================================================
    // AXI4-Lite Slave: Boot ROM
    // ========================================================================
    axi4lite_bootrom u_bootrom (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (sys_resetn),
        .s_axi_awaddr  (bootrom_awaddr),
        .s_axi_awprot  (bootrom_awprot),
        .s_axi_awvalid (bootrom_awvalid),
        .s_axi_awready (bootrom_awready),
        .s_axi_wdata   (bootrom_wdata),
        .s_axi_wstrb   (bootrom_wstrb),
        .s_axi_wvalid  (bootrom_wvalid),
        .s_axi_wready  (bootrom_wready),
        .s_axi_bresp   (bootrom_bresp),
        .s_axi_bvalid  (bootrom_bvalid),
        .s_axi_bready  (bootrom_bready),
        .s_axi_araddr  (bootrom_araddr),
        .s_axi_arprot  (bootrom_arprot),
        .s_axi_arvalid (bootrom_arvalid),
        .s_axi_arready (bootrom_arready),
        .s_axi_rdata   (bootrom_rdata),
        .s_axi_rresp   (bootrom_rresp),
        .s_axi_rvalid  (bootrom_rvalid),
        .s_axi_rready  (bootrom_rready)
    );

    // ========================================================================
    // AXI4-Lite Slave: Default Slave (DECERR)
    // ========================================================================
    axi4lite_default_slave u_default_slave (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (sys_resetn),
        .s_axi_awaddr  (default_awaddr),
        .s_axi_awprot  (default_awprot),
        .s_axi_awvalid (default_awvalid),
        .s_axi_awready (default_awready),
        .s_axi_wdata   (default_wdata),
        .s_axi_wstrb   (default_wstrb),
        .s_axi_wvalid  (default_wvalid),
        .s_axi_wready  (default_wready),
        .s_axi_bresp   (default_bresp),
        .s_axi_bvalid  (default_bvalid),
        .s_axi_bready  (default_bready),
        .s_axi_araddr  (default_araddr),
        .s_axi_arprot  (default_arprot),
        .s_axi_arvalid (default_arvalid),
        .s_axi_arready (default_arready),
        .s_axi_rdata   (default_rdata),
        .s_axi_rresp   (default_rresp),
        .s_axi_rvalid  (default_rvalid),
        .s_axi_rready  (default_rready)
    );

    // ========================================================================
    // AXI4-Lite Slave: System Status
    // ========================================================================
    // MIG status proxies: use ddr_aresetn as init_calib_complete approximation
    // In SRAM mode, both tied to 0
    wire mig_init_calib_complete_proxy;
    wire mig_mmcm_locked_proxy;
`ifdef SIMULATION
    if (`SIMU_USE_DDR == 0) begin: syssts_sram_tie
        assign mig_init_calib_complete_proxy = 1'b0;
        assign mig_mmcm_locked_proxy        = 1'b0;
    end
    else begin: syssts_ddr_proxy
        assign mig_init_calib_complete_proxy = ddr_aresetn;
        assign mig_mmcm_locked_proxy        = 1'b1;
    end
`else
    begin: syssts_ddr_proxy
        assign mig_init_calib_complete_proxy = ddr_aresetn;
        assign mig_mmcm_locked_proxy        = 1'b1;
    end
`endif

    axi4lite_sys_status u_sys_status (
        .s_axi_aclk           (sys_clk),
        .s_axi_aresetn        (sys_resetn),
        .s_axi_awaddr         (syssts_awaddr),
        .s_axi_awprot         (syssts_awprot),
        .s_axi_awvalid        (syssts_awvalid),
        .s_axi_awready        (syssts_awready),
        .s_axi_wdata          (syssts_wdata),
        .s_axi_wstrb          (syssts_wstrb),
        .s_axi_wvalid         (syssts_wvalid),
        .s_axi_wready         (syssts_wready),
        .s_axi_bresp          (syssts_bresp),
        .s_axi_bvalid         (syssts_bvalid),
        .s_axi_bready         (syssts_bready),
        .s_axi_araddr         (syssts_araddr),
        .s_axi_arprot         (syssts_arprot),
        .s_axi_arvalid        (syssts_arvalid),
        .s_axi_arready        (syssts_arready),
        .s_axi_rdata          (syssts_rdata),
        .s_axi_rresp          (syssts_rresp),
        .s_axi_rvalid         (syssts_rvalid),
        .s_axi_rready         (syssts_rready),
        .i_init_calib_complete(mig_init_calib_complete_proxy),
        .i_mig_mmcm_locked    (mig_mmcm_locked_proxy),
        .i_clk_wiz_locked     (clk_wiz_locked)
    );

    // ========================================================================
    // APB Subsystem: axi4lite_to_apb → apb_decoder → apb_perips
    // ========================================================================
    // APB bridge wires
    wire [31:0] bridge_PADDR;
    wire [2:0]  bridge_PPROT;
    wire        bridge_PSEL;
    wire        bridge_PENABLE;
    wire        bridge_PWRITE;
    wire [31:0] bridge_PWDATA;
    wire [3:0]  bridge_PSTRB;
    logic       bridge_PREADY;
    logic [31:0] bridge_PRDATA;
    logic       bridge_PSLVERR;

    // APB slave select
    wire [3:0] apb_slave_PSELx;

    // APB slave response wires
    wire [3:0]  apb_slave_PREADY;
    wire [31:0] apb_slave0_PRDATA;
    wire [31:0] apb_slave1_PRDATA;
    wire [31:0] apb_slave2_PRDATA;
    wire [31:0] apb_slave3_PRDATA;
    wire [3:0]  apb_slave_PSLVERR;

    // GPIO output wires (32-bit, truncated to 16-bit for top-level)
    wire [31:0] gpio_ctrl_out_wire;
    wire [31:0] gpio_data_out_wire;

    // AXI4-Lite to APB bridge
    axi4lite_to_apb u_axi4lite_to_apb (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (sys_resetn),
        .s_axi_awaddr  (apb_awaddr),
        .s_axi_awprot  (apb_awprot),
        .s_axi_awvalid (apb_awvalid),
        .s_axi_awready (apb_awready),
        .s_axi_wdata   (apb_wdata),
        .s_axi_wstrb   (apb_wstrb),
        .s_axi_wvalid  (apb_wvalid),
        .s_axi_wready  (apb_wready),
        .s_axi_bresp   (apb_bresp),
        .s_axi_bvalid  (apb_bvalid),
        .s_axi_bready  (apb_bready),
        .s_axi_araddr  (apb_araddr),
        .s_axi_arprot  (apb_arprot),
        .s_axi_arvalid (apb_arvalid),
        .s_axi_arready (apb_arready),
        .s_axi_rdata   (apb_rdata),
        .s_axi_rresp   (apb_rresp),
        .s_axi_rvalid  (apb_rvalid),
        .s_axi_rready  (apb_rready),
        // APB Master outputs
        .PADDR         (bridge_PADDR),
        .PPROT         (bridge_PPROT),
        .PSEL          (bridge_PSEL),
        .PENABLE       (bridge_PENABLE),
        .PWRITE        (bridge_PWRITE),
        .PWDATA        (bridge_PWDATA),
        .PSTRB         (bridge_PSTRB),
        .PREADY        (bridge_PREADY),
        .PRDATA        (bridge_PRDATA),
        .PSLVERR       (bridge_PSLVERR)
    );

    // APB address decoder
    apb_decoder #(
        .ADDR_WIDTH (32),
        .SLAVE_NUM  (4)
    ) u_apb_decoder (
        .PADDR (bridge_PADDR),
        .PSELx (apb_slave_PSELx)
    );

    // APB peripherals
    apb_perips #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_apb_perips (
        .PCLK           (sys_clk),
        .PRESETn        (sys_resetn),
        .PADDR          (bridge_PADDR),
        .PPROT          (bridge_PPROT),
        .PSELx          (apb_slave_PSELx),
        .PENABLE        (bridge_PENABLE),
        .PWRITE         (bridge_PWRITE),
        .PWDATA         (bridge_PWDATA),
        .PSTRB          (bridge_PSTRB),
        .slave_PREADY   (apb_slave_PREADY),
        .slave0_PRDATA  (apb_slave0_PRDATA),
        .slave1_PRDATA  (apb_slave1_PRDATA),
        .slave2_PRDATA  (apb_slave2_PRDATA),
        .slave3_PRDATA  (apb_slave3_PRDATA),
        .slave_PSLVERR  (apb_slave_PSLVERR),
        .o_gpioCtrl     (gpio_ctrl_out_wire),
        .o_gpioData     (gpio_data_out_wire),
        .io_gpioPin     (gpio_io),
        .o_gpio_irq     (gpio_irq),
        .i_uart_rx      (uart_rx),
        .o_uart_tx      (cpu_uart_tx),
        .o_uart_irq     (uart_irq),
        .o_spiMosi      (spi_mosi),
        .i_spiMiso      (spi_miso),
        .o_spiSs        (spi_ss),
        .o_spiClk       (spi_clk),
        .o_spi_irq      (spi_irq)
    );

    assign uart_tx = cpu_uart_tx;

    // APB response mux (PREADY and PSLVERR)
    always_comb begin
        bridge_PREADY  = 1'b1;
        bridge_PSLVERR = 1'b0;
        if (apb_slave_PSELx[0] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[0];
            bridge_PSLVERR = apb_slave_PSLVERR[0];
        end else if (apb_slave_PSELx[1] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[1];
            bridge_PSLVERR = apb_slave_PSLVERR[1];
        end else if (apb_slave_PSELx[2] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[2];
            bridge_PSLVERR = apb_slave_PSLVERR[2];
        end else if (apb_slave_PSELx[3] & bridge_PSEL) begin
            bridge_PREADY  = apb_slave_PREADY[3];
            bridge_PSLVERR = apb_slave_PSLVERR[3];
        end
    end

    // APB read data mux
    always_comb begin
        bridge_PRDATA = 32'b0;
        if (apb_slave_PSELx[0] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave0_PRDATA;
        end else if (apb_slave_PSELx[1] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave1_PRDATA;
        end else if (apb_slave_PSELx[2] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave2_PRDATA;
        end else if (apb_slave_PSELx[3] & bridge_PSEL) begin
            bridge_PRDATA = apb_slave3_PRDATA;
        end
    end

    // ========================================================================
    // GPIO control/data outputs
    // ========================================================================
    assign gpio_ctrl_out = gpio_ctrl_out_wire[15:0];
    assign gpio_data_out = gpio_data_out_wire[15:0];

    // Testbenches may force this address to inspect the integer register file.
    assign rf_addr = 5'd0;
    // ========================================================================
    // ILA Debug Probes (FPGA only — enabled via ENABLE_ILA define)
    // ========================================================================
    // ENABLE_ILA is used only after the matching ILA IP cores have been added
    // to an FPGA project. Normal simulation and FPGA builds leave it undefined.
    // Trigger: set probe6[31:28] == 4'hC to capture if_pc entering 0xC... region
`ifdef ENABLE_ILA
    // ILA #1: cpu_clk domain — CPU-side AXI + if_pc
    ila_cpu_axi u_ila_cpu_axi (
        .clk   (cpu_clk),
        .probe0(cpu_awaddr),      // [31:0] CPU AXI write address
        .probe1({cpu_awvalid, cpu_awready, cpu_wvalid, cpu_wready,
                 cpu_arvalid, cpu_arready, cpu_rvalid, cpu_rready}),  // [7:0]
        .probe2(cpu_wdata),       // [31:0] CPU write data
        .probe3(cpu_araddr),      // [31:0] CPU read address (includes fetch addr)
        .probe4(cpu_rdata),       // [31:0] CPU read data
        .probe5({cpu_bvalid, cpu_bready, cpu_rvalid, cpu_rready}),   // [3:0]
        .probe6(if_pc)            // [31:0] instruction fetch PC
    );

    // ILA #2: sys_clk domain — reset status + CDC-side AXI
    ila_reset_axi u_ila_reset_axi (
        .clk   (sys_clk),
        .probe0({sys_resetn, cpu_resetn, clk_wiz_locked, ddr_aresetn, resetn}),  // [4:0]
        .probe1(cdc_awaddr),      // [31:0] CDC write address
        .probe2({cdc_awvalid, cdc_awready, cdc_wvalid, cdc_wready,
                 cdc_arvalid, cdc_arready, cdc_rvalid, cdc_rready}),  // [7:0]
        .probe3(cdc_wdata),       // [31:0] CDC write data
        .probe4(cdc_araddr),      // [31:0] CDC read address
        .probe5(cdc_rdata),       // [31:0] CDC read data
        .probe6({cdc_bvalid, cdc_bready, cdc_rvalid, cdc_rready})    // [3:0]
    );
`endif

endmodule
