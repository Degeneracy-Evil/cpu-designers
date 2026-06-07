`timescale 1ns / 1ps
module system_top(
    input         clk,
    input         resetn,

    input  [7:0]  sw,

    input         uart_rx,
    output        uart_tx,

    input         spi_miso,
    output        spi_mosi,
    output        spi_ss,
    output        spi_clk,

    output [15:0] gpio_ctrl_out,
    output [15:0] gpio_data_out,

    inout  [15:0] gpio_io,

    output        lcd_rst,
    output        lcd_cs,
    output        lcd_rs,
    output        lcd_wr,
    output        lcd_rd,
    inout  [15:0] lcd_data_io,
    output        lcd_bl_ctr,
    inout         ct_int,
    inout         ct_sda,
    output        ct_scl,
    output        ct_rstn,

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

    wire reset;
    assign reset = ~resetn;

    // Clocking Wizard: 100MHz in → 100MHz clk_system + 200MHz clk_ddr_ref
    wire clk_system;     // 100MHz system clock (from clk_wiz or MIG ui_clk)
    wire clk_ddr_ref;    // 200MHz DDR reference clock
    wire clk_wiz_locked; // Clocking Wizard locked

    clk_wiz_0 u_clk_wiz_0 (
        .clk_in1  (clk),          // 100MHz external crystal
        .clk_out1 (clk_system),   // 100MHz (backup, not used when DDR3 active)
        .clk_out2 (clk_ddr_ref),  // 200MHz → MIG clk_ref_i
        .resetn   (resetn),        // Active-low reset
        .locked   (clk_wiz_locked)
    );

    // MIG status wires
    wire mig_init_calib_complete;
    wire mig_ui_clk;           // MIG 100MHz output = system clock
    wire mig_ui_clk_sync_rst;
    wire mig_mmcm_locked;
    // BUG-56 fix: aresetn must stay 0 until AFTER init_calib_complete.
    // In tb_ddr3_ahb_ex (which works), aresetn stays 0 until
    // init_calib_complete && mmcm_locked. Releasing aresetn early (after
    // mmcm_locked only) allows the AXI UI to become active before calibration
    // completes, which prevents MIG's internal calibration state machine from
    // completing in the full system (even though no AXI transactions arrive).
    // This matches the proven-working tb_ddr3_ahb_ex reset sequencing.
    // There is NO circular dependency: aresetn is an INPUT to MIG, and
    // init_calib_complete is an OUTPUT — the dependency is unidirectional.
    // tb_ddr3_ahb_ex proves calibration CAN complete with aresetn=0.
    reg mig_aresetn = 1'b0;

    // Drive mig_aresetn: release after MMCM locked (NOT waiting for init_calib_complete).
    // BUG-56 finding: With _mig_sim.v (SIM_BYPASS_INIT_CAL=FAST), waiting for
    // init_calib_complete creates a deadlock — aresetn stays 0, and calibration
    // may need aresetn=1 to complete in the full system (unlike tb_ddr3_ahb_ex
    // where the simpler design allows calibration with aresetn=0).
    // Releasing aresetn after mmcm_locked allows MIG AXI UI to activate,
    // which may be required for the calibration state machine to advance.
    // ahb_hresetn still waits for init_calib_complete to prevent CPU DDR3 access
    // before DRAM is ready.
    // BUG-55c: Add async reset (posedge reset) to sensitivity list so that
    // mig_aresetn is deterministically 0 during reset, preventing X propagation
    // through MIG when mmcm_locked may be undefined during power-on.
    always @(posedge mig_ui_clk or posedge reset) begin
        if (reset)
            mig_aresetn <= 1'b0;
        else if (mig_mmcm_locked)
            mig_aresetn <= 1'b1;
    end

    // AHB bus reset: hold until MIG calibration completes so CPU cannot
    // attempt DDR3 access before DRAM is ready.
    // BUG-55c: Same async reset fix — prevents X on ahb_hresetn from
    // propagating to ALL AHB slaves (HRESETn=X → every slave register stays X).
    reg ahb_hresetn = 1'b0;

    always @(posedge mig_ui_clk or posedge reset) begin
        if (reset)
            ahb_hresetn <= 1'b0;
        else if (mig_init_calib_complete && mig_mmcm_locked)
            ahb_hresetn <= 1'b1;
    end

    wire [31:0] cpu_HADDR;
    wire [1:0]  cpu_HTRANS;
    wire        cpu_HWRITE;
    wire [2:0]  cpu_HSIZE;
    wire [2:0]  cpu_HBURST;
    wire [3:0]  cpu_HPROT;
    wire        cpu_HMASTLOCK;
    wire [31:0] cpu_HWDATA;
    wire [31:0] cpu_HRDATA;
    wire        cpu_HREADY;
    wire        cpu_HRESP;

    wire        timer_irq;
    wire        plic_eip;
    wire        clint_mtip;
    wire        clint_msip;
    wire        gpio_irq;
    wire        uart_irq;
    wire        spi_irq;
    wire [31:0] gpio_ctrl_out_wire;
    wire [31:0] gpio_data_out_wire;

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
    wire [31:0] display_state;

    core_top cpu(
        .clk          (mig_ui_clk   ),
        .reset        (reset         ),
        .rf_addr      (rf_addr       ),
        .rf_data      (rf_data       ),
        .if_pc        (if_pc         ),
        .if_inst      (if_inst       ),
        .id_pc        (id_pc         ),
        .id_inst      (id_inst       ),
        .exe_pc       (exe_pc        ),
        .exe_inst     (exe_inst      ),
        .mem_pc       (mem_pc        ),
        .mem_inst     (mem_inst      ),
        .wb_pc        (wb_pc         ),
        .wb_inst      (wb_inst       ),
        .display_state(display_state ),
        .HADDR        (cpu_HADDR     ),
        .HTRANS       (cpu_HTRANS    ),
        .HWRITE       (cpu_HWRITE    ),
        .HSIZE        (cpu_HSIZE     ),
        .HBURST       (cpu_HBURST    ),
        .HPROT        (cpu_HPROT     ),
        .HMASTLOCK    (cpu_HMASTLOCK ),
        .HWDATA       (cpu_HWDATA    ),
        .HRDATA       (cpu_HRDATA    ),
        .HREADY       (cpu_HREADY    ),
        .HRESP        (cpu_HRESP     ),
        .init_sig     (1'b0          ),
        .timer_irq    (clint_mtip    ),
        .ext_meip_in  (plic_eip      ),
        .ext_msip_in  (clint_msip    )
    );

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (7),
        .MEM_DEPTH   (8192),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_ahb_lite_bus (
        .HCLK       (mig_ui_clk),
        .HRESETn    (ahb_hresetn),
        .HADDR      (cpu_HADDR),
        .HTRANS     (cpu_HTRANS),
        .HWRITE     (cpu_HWRITE),
        .HSIZE      (cpu_HSIZE),
        .HBURST     (cpu_HBURST),
        .HPROT      (cpu_HPROT),
        .HMASTLOCK  (cpu_HMASTLOCK),
        .HWDATA     (cpu_HWDATA),
        .HRDATA     (cpu_HRDATA),
        .HREADY     (cpu_HREADY),
        .HRESP      (cpu_HRESP),
        .o_timer_irq(timer_irq),
        .o_gpio_irq (gpio_irq),
        .o_uart_irq (uart_irq),
        .o_spi_irq  (spi_irq),
        .o_plic_eip (plic_eip),
        .o_clint_mtip(clint_mtip),
        .o_clint_msip(clint_msip),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (uart_rx),
        .o_uart_tx  (uart_tx),
        .o_spiMosi  (spi_mosi),
        .i_spiMiso  (spi_miso),
        .o_spiSs    (spi_ss),
        .o_spiClk   (spi_clk),
        .o_gpioCtrl (gpio_ctrl_out_wire),
        .o_gpioData (gpio_data_out_wire),
        .mig_sys_clk_i  (clk),              // 100MHz external crystal → MIG sys_clk_i
        .mig_clk_ref_i  (clk_ddr_ref),      // 200MHz from clk_wiz → MIG clk_ref_i
        .mig_sys_rst    (resetn),           // MIG RST_ACT_LOW=1: sys_rst is active-LOW (0=reset, 1=normal)
        .init_calib_complete(mig_init_calib_complete),
        .ui_clk         (mig_ui_clk),
        .mmcm_locked    (mig_mmcm_locked),
        .aresetn        (mig_aresetn),
        .i_clk_wiz_locked(clk_wiz_locked),
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

    reg         display_valid;
    reg  [39:0] display_name;
    reg  [31:0] display_value;
    wire [5 :0] display_number;
    wire        input_valid;
    wire [31:0] input_value;

    lcd_module lcd_module(
        .clk            (mig_ui_clk   ),
        .resetn         (resetn        ),
        .display_valid  (display_valid ),
        .display_name   (display_name  ),
        .display_value  (display_value ),
        .display_number (display_number),
        .input_valid    (input_valid   ),
        .input_value    (input_value   ),
        .lcd_rst        (lcd_rst       ),
        .lcd_cs         (lcd_cs        ),
        .lcd_rs         (lcd_rs        ),
        .lcd_wr         (lcd_wr        ),
        .lcd_rd         (lcd_rd        ),
        .lcd_data_io    (lcd_data_io   ),
        .lcd_bl_ctr     (lcd_bl_ctr    ),
        .ct_int         (ct_int        ),
        .ct_sda         (ct_sda        ),
        .ct_scl         (ct_scl        ),
        .ct_rstn        (ct_rstn       )
    );

    assign rf_addr = display_number - 6'd11;

    // GPIO control/data outputs
    assign gpio_ctrl_out = gpio_ctrl_out_wire[15:0];
    assign gpio_data_out = gpio_data_out_wire[15:0];

    always_ff @(posedge mig_ui_clk or posedge reset) begin
        if (reset) begin
            display_valid  <= 1'b0;
            display_name   <= 40'b0;
            display_value  <= 32'b0;
        end else if (display_number > 6'd10 && display_number < 6'd43) begin
            display_valid       <= 1'b1;
            display_name[39:16] <= "REG";
            display_name[15:8]  <= {4'b0011, 3'b000, rf_addr[4]};
            display_name[7:0]   <= {4'b0011, rf_addr[3:0]};
            display_value       <= rf_data;
        end else begin
            case(display_number)
                6'd1: begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_PC";
                    display_value <= if_pc;
                end
                6'd2: begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_IN";
                    display_value <= if_inst;
                end
                6'd3: begin
                    display_valid <= 1'b1;
                    display_name  <= "ID_PC";
                    display_value <= id_pc;
                end
                6'd4: begin
                    display_valid <= 1'b1;
                    display_name  <= "EXEPC";
                    display_value <= exe_pc;
                end
                6'd5: begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMPC";
                    display_value <= mem_pc;
                end
                6'd6: begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMIN";
                    display_value <= mem_inst;
                end
                6'd7: begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_PC";
                    display_value <= wb_pc;
                end
                6'd8: begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_IN";
                    display_value <= wb_inst;
                end
                6'd9: begin
                    display_valid <= 1'b1;
                    display_name  <= "DADDR";
                    display_value <= cpu_HADDR;
                end
                6'd10: begin
                    display_valid <= 1'b1;
                    display_name  <= "DDATA";
                    display_value <= cpu_HRDATA;
                end
                6'd43: begin
                    display_valid <= 1'b1;
                    display_name  <= "STATE";
                    display_value <= display_state;
                end
                6'd44: begin
                    display_valid <= 1'b1;
                    display_name  <= "SW   ";
                    display_value <= {24'b0, sw};
                end
                default: begin
                    display_valid <= 1'b0;
                    display_name  <= 40'd0;
                    display_value <= 32'b0;
                end
            endcase
        end
    end

endmodule
