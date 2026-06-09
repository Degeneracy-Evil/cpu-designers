// ============================================================================
// tb_soc_includes.svh — Shared testbench boilerplate for system_top
//
// This file is included via `include "tb_soc_includes.svh" inside each
// testbench module.  It provides:
//   - system_top instantiation (u_soc) with all IO tied off for SRAM sim
//   - 100 MHz clock generation
//   - Reset sequencing + ddr_data_init force-release
//   - Debug signal wires (rf_data, if_pc, …) via hierarchical access
//   - check_reg / check_mem_word tasks
//   - pass/fail counters
//
// Usage:
//   module tb_my_test;
//       localparam integer EXPECTED_TOTAL = 4;
//       `include "tb_soc_includes.svh"
//       // … test body …
//   endmodule
// ============================================================================

// ----------------------------------------------------------------
// Clock / reset regs
// ----------------------------------------------------------------
reg         clk;
reg         resetn;
reg  [7:0]  sw;
reg         uart_rx;
wire        uart_tx;

// ----------------------------------------------------------------
// GPIO inout wire (needed for LED/GPIO tests)
// ----------------------------------------------------------------
wire [15:0] gpio_io;

// ----------------------------------------------------------------
// system_top instantiation (replaces core_top + ahb_lite_bus)
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

// ----------------------------------------------------------------
// Reset + ddr_data_init release
// ----------------------------------------------------------------
initial begin
    sw      = 8'b0;
    uart_rx = 1'b1;   // idle
    resetn  = 1'b0;

    repeat (5) @(posedge clk);
    resetn = 1'b1;

    // Wait for reset to propagate through reset_sync stages
    repeat (10) @(posedge clk);

    // Release ddr_data_init so CPU can start executing
    force u_soc.ddr_data_init = 1'b1;
end

// ----------------------------------------------------------------
// Debug signal access via hierarchy
//   These wires read core_top's debug outputs through system_top's
//   internal wire declarations (rf_data, if_pc, etc.).
// ----------------------------------------------------------------
wire [31:0] rf_data       = u_soc.rf_data;
wire [31:0] if_pc         = u_soc.if_pc;
wire [31:0] if_inst       = u_soc.if_inst;
wire [31:0] id_pc         = u_soc.id_pc;
wire [31:0] id_inst       = u_soc.id_inst;
wire [31:0] exe_pc        = u_soc.exe_pc;
wire [31:0] exe_inst      = u_soc.exe_inst;
wire [31:0] mem_pc        = u_soc.mem_pc;
wire [31:0] mem_inst      = u_soc.mem_inst;
wire [31:0] wb_pc         = u_soc.wb_pc;
wire [31:0] wb_inst       = u_soc.wb_inst;
wire [31:0] display_state = u_soc.display_state;

// ----------------------------------------------------------------
// Pass / fail counters
// ----------------------------------------------------------------
integer pass_count;
integer fail_count;

// ----------------------------------------------------------------
// check_reg — force rf_addr into core_top, read rf_data
//   rf_addr is a wire in system_top driven by a continuous assignment
//   (display_number - 11).  The force overrides it during the check.
// ----------------------------------------------------------------
task check_reg;
    input  [4:0]  addr;
    input  [31:0] expected;
    reg    [31:0] actual;
    begin
        force u_soc.rf_addr = addr;
        #1;
        actual = u_soc.rf_data;
        release u_soc.rf_addr;
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("  PASS x%0d = 0x%08h", addr, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL x%0d expected=0x%08h got=0x%08h", addr, expected, actual);
        end
    end
endtask

// ----------------------------------------------------------------
// check_mem_word — read directly from axi_wrap_ram BRAM array
//   Only works in SRAM mode (SIMU_USE_DDR=0) where the behavioral
//   BRAM model is instantiated inside the sim_ram generate block.
// ----------------------------------------------------------------
task check_mem_word;
    input  [31:0] addr;
    input  [31:0] expected;
    reg    [31:0] actual;
    begin
        // addr is byte address, BRAM is word-addressed
        actual = u_soc.sim_ram.u_axi_ram.BRAM[addr[19:2]];
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("  PASS mem[0x%08h] = 0x%08h", addr, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, actual);
        end
    end
endtask

// ----------------------------------------------------------------
// read_reg — non-checking read, returns value in actual
//   Useful for framework-style TBs that read x28/x29/x30
//   and do their own pass/fail logic.
// ----------------------------------------------------------------
task read_reg;
    input  [4:0]  addr;
    output [31:0] val;
    begin
        force u_soc.rf_addr = addr;
        #1;
        val = u_soc.rf_data;
        release u_soc.rf_addr;
    end
endtask
