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
//   - DDR3 simulation support (when SIMU_USE_DDR=1):
//       ddr3_model, axi4_write task, write_hex_file task, ddr_data_init sequencing
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
// Inout wires for DDR3 and peripheral ports (cannot connect constants to inout)
// ----------------------------------------------------------------
wire [15:0] ddr3_dq_wire;
wire [1:0]  ddr3_dqs_p_wire;
wire [1:0]  ddr3_dqs_n_wire;
wire [15:0] lcd_data_io_wire;
wire        ct_int_wire;
wire        ct_sda_wire;

// ----------------------------------------------------------------
// DDR3 output wires (driven by system_top, read by ddr3_model)
// ----------------------------------------------------------------
wire [12:0] ddr3_addr_wire;
wire [2:0]  ddr3_ba_wire;
wire        ddr3_ras_n_wire;
wire        ddr3_cas_n_wire;
wire        ddr3_we_n_wire;
wire        ddr3_reset_n_wire;
wire [0:0]  ddr3_ck_p_wire;
wire [0:0]  ddr3_ck_n_wire;
wire [0:0]  ddr3_cke_wire;
wire [1:0]  ddr3_dm_wire;
wire [0:0]  ddr3_odt_wire;

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
    .lcd_data_io      (lcd_data_io_wire),
    .lcd_bl_ctr       (),
    .ct_int           (ct_int_wire),
    .ct_sda           (ct_sda_wire),
    .ct_scl           (),
    .ct_rstn          (),
    .ddr3_addr        (ddr3_addr_wire),
    .ddr3_ba          (ddr3_ba_wire),
    .ddr3_ras_n       (ddr3_ras_n_wire),
    .ddr3_cas_n       (ddr3_cas_n_wire),
    .ddr3_we_n        (ddr3_we_n_wire),
    .ddr3_reset_n     (ddr3_reset_n_wire),
    .ddr3_ck_p        (ddr3_ck_p_wire),
    .ddr3_ck_n        (ddr3_ck_n_wire),
    .ddr3_cke         (ddr3_cke_wire),
    .ddr3_dm          (ddr3_dm_wire),
    .ddr3_dq          (ddr3_dq_wire),
    .ddr3_dqs_p       (ddr3_dqs_p_wire),
    .ddr3_dqs_n       (ddr3_dqs_n_wire),
    .ddr3_odt         (ddr3_odt_wire)
);

// ----------------------------------------------------------------
// Clock generation — 100 MHz
// ----------------------------------------------------------------
initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// ----------------------------------------------------------------
// Reset sequencing
// ----------------------------------------------------------------
initial begin
    sw      = 8'b0;
    uart_rx = 1'b1;   // idle
    resetn  = 1'b0;

    repeat (5) @(posedge clk);
    resetn = 1'b1;

    // Wait for reset to propagate through reset_sync stages
    repeat (10) @(posedge clk);
end

// ----------------------------------------------------------------
// SRAM / DDR3 generate block
//   SRAM mode  (SIMU_USE_DDR=0): force ddr_data_init so CPU starts
//   DDR3 mode  (SIMU_USE_DDR=1): ddr3_model + AXI write tasks +
//              ddr_data_init sequencing (wait calib → load → release)
// ----------------------------------------------------------------
generate if (`SIMU_USE_DDR == 0) begin: sim_ram_tb

    // SRAM mode: release ddr_data_init immediately after reset
    // Also force SYS_STATUS signals so full bootloader can proceed
    // (In SRAM mode there is no MIG, so init_calib_complete is hardcoded 0;
    //  the force overrides this so the bootloader's poll succeeds.)
    initial begin
        force u_soc.ddr_data_init = 1'b1;
        force u_soc.mig_init_calib_complete_proxy = 1'b1;
        force u_soc.mig_mmcm_locked_proxy        = 1'b1;
    end

    // ----------------------------------------------------------------
    // UART TX simulation — drive uart_rx to send bytes to CPU
    // Accelerated baud rate for simulation (divider=16 vs default 868)
    // ----------------------------------------------------------------
    localparam SIM_UART_CYCLE = 16;  // cycles per bit (must match forced baud divider)
                                       // 16 ≈ 54× faster than real 115200 (868 cycles/bit)
                                       // FIFO-count flow control prevents overflow

    task uart_send_byte;
        input [7:0] byte_data;
        integer i;
        begin
            // Start bit
            uart_rx = 1'b0;
            repeat(SIM_UART_CYCLE) @(posedge clk);
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = byte_data[i];
                repeat(SIM_UART_CYCLE) @(posedge clk);
            end
            // Stop bit
            uart_rx = 1'b1;
            repeat(SIM_UART_CYCLE) @(posedge clk);

            // Flow control: wait for FIFO to have space before next byte.
            // CPU bug causes duplicate AXI transactions, slowing consumption
            // to ~270 cycles/byte.  We need headroom: wait until FIFO
            // count drops below 12 (of 16) to avoid overflow.
            // Use while+@(posedge clk) for XSim robustness.
            while (u_soc.u_apb_perips.u_uart.rx_fifo_count >= 4'd14) begin
                @(posedge clk);
            end
        end
    endtask

    task uart_send_word;
        input [31:0] word_data;
        begin
            // Little-endian: LSB byte first
            uart_send_byte(word_data[7:0]);
            uart_send_byte(word_data[15:8]);
            uart_send_byte(word_data[23:16]);
            uart_send_byte(word_data[31:24]);
        end
    endtask

    // ----------------------------------------------------------------
    // uart_send_program — send program hex file via UART to bootloader
    // Protocol: magic(4B) + length(4B) + load_addr(4B) + entry_addr(4B) + data
    // ----------------------------------------------------------------
    task uart_send_program;
        input [256*8-1:0] filename;
        reg  [31:0] data;
        integer fd, code, word_cnt, total_words;
        begin
            // First pass: count words
            fd = $fopen(filename, "r");
            if (fd == 0) begin
                $display("[UART-TB] ERROR: Cannot open %s", filename);
                return;
            end
            total_words = 0;
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", data);
                if (code == 1) total_words = total_words + 1;
            end
            $fclose(fd);

            $display("[UART-TB] Sending header: magic=0x52495343 length=%0d load=0x80000000 entry=0x80000000",
                     total_words * 4);
            $fflush;

            // Send header
            uart_send_word(32'h52495343);     // Magic "RISC"
            uart_send_word(total_words * 4);  // Length in bytes
            uart_send_word(32'h80000000);     // Load address
            uart_send_word(32'h80000000);     // Entry address

            // Second pass: send program data
            fd = $fopen(filename, "r");
            word_cnt = 0;
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", data);
                if (code == 1) begin
                    uart_send_word(data);
                    word_cnt = word_cnt + 1;
                    if (word_cnt % 200 == 0) begin
                        $display("[UART-TB] Sent %0d/%0d words via UART", word_cnt, total_words);
                        $fflush;
                    end
                end
            end
            $fclose(fd);
            $display("[UART-TB] Program delivery complete: %0d words (%0d bytes)",
                     word_cnt, word_cnt * 4);
            $fflush;
        end
    endtask

    // ----------------------------------------------------------------
    // UART program delivery initial block
    // Waits for bootloader to initialize UART, then sends program
    // ----------------------------------------------------------------
    initial begin
        // Wait for reset to fully propagate
        repeat (100) @(posedge clk);

        // Force accelerated UART baud divider for simulation speedup
        // (Default 868 cycles/bit → 16 cycles/bit, ~54× faster)
        force u_soc.u_apb_perips.u_uart.uart_baud = 32'd16;

        // Wait for the bootloader to actually enable UART RX before sending.
        // A fixed delay is fragile because the boot path length changes with
        // reset timing, BRAM latency, and extra bootloader instrumentation.
        wait (u_soc.u_apb_perips.u_uart.rx_en === 1'b1);
        repeat (4) @(posedge clk);

        $display("[UART-TB] %0t: Starting UART program delivery (rx_en=1 ctrl=0x%h baud=0x%h)...",
                 $time,
                 u_soc.u_apb_perips.u_uart.uart_ctrl,
                 u_soc.u_apb_perips.u_uart.uart_baud);
        $fflush;

        // Send program via UART
        uart_send_program("prog.hex");

        $display("[UART-TB] %0t: UART delivery done, CPU should start executing program", $time);
        $fflush;
    end

end
else begin: ddr3_tb

    // ------------------------------------------------------------
    // ddr3_model instantiation — Micron behavioral DDR3 model
    // ------------------------------------------------------------
    ddr3_model u_ddr3_model (
        .rst_n      (resetn),
        .ck         (ddr3_ck_p_wire[0]),   // [0:0] → scalar
        .ck_n       (ddr3_ck_n_wire[0]),
        .cke        (ddr3_cke_wire[0]),
        .cs_n       (1'b0),
        .ras_n      (ddr3_ras_n_wire),
        .cas_n      (ddr3_cas_n_wire),
        .we_n       (ddr3_we_n_wire),
        .dm_tdqs    (ddr3_dm_wire),
        .ba         (ddr3_ba_wire),
        .addr       (ddr3_addr_wire),
        .dq         (ddr3_dq_wire),
        .dqs        (ddr3_dqs_p_wire),
        .dqs_n      (ddr3_dqs_n_wire),
        .tdqs_n     (),
        .odt        (ddr3_odt_wire[0])
    );

    // ------------------------------------------------------------
    // axi4_write — write one 32-bit word via MIG AXI4 slave interface
    //   Uses force on MIG AXI signals (matching chiplab pattern).
    //   Hierarchy: u_soc.ddr3.u_axi_wrap_ddr.mig_axi
    // ------------------------------------------------------------
    // Global counter for AXI write progress (shared with write_hex_file)
    integer axi_write_cnt;

    task axi4_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Write address channel
            @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
            if (axi_write_cnt < 5 || axi_write_cnt % 1024 == 0) begin
                $display("[AXI-W] %0t: #%0d AW addr=0x%08h awready=%b wready=%b",
                         $time, axi_write_cnt, addr,
                         u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awready,
                         u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wready);
                $fflush;
            end
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awid    = 4'b0001;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awaddr  = addr[26:0];
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awlen   = 8'h00;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awsize  = 3'b010;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awburst = 2'b01;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awlock  = 1'b0;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awcache = 4'b0000;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awprot  = 3'b000;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awqos   = 4'b0000;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awvalid = 1'b1;

            // Wait for write address handshake
            wait(u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awready);
            @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awvalid = 1'b0;

            // Write data channel
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wdata  = data;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wstrb  = 4'b1111;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wlast  = 1'b1;
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wvalid = 1'b1;

            // Wait for write data handshake
            wait(u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wready);
            @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wvalid = 1'b0;

            // Wait for write response
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_bready = 1'b1;
            wait(u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_bvalid);
            @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
            force u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_bready = 1'b0;
            axi_write_cnt = axi_write_cnt + 1;
            if (axi_write_cnt <= 5 || axi_write_cnt % 1024 == 0) begin
                $display("[AXI-W] %0t: #%0d DONE addr=0x%08h", $time, axi_write_cnt, addr);
                $fflush;
            end
        end
    endtask

    // ------------------------------------------------------------
    // write_hex_file — load hex text file into DDR3 via AXI4 writes
    //   Each line is one 32-bit word in hex (e.g. "00000297").
    //   This matches our .hex output format from rv2coe.py.
    // ------------------------------------------------------------
    task write_hex_file;
        input [31:0]   base_addr;
        input [256*8-1:0] filename;
        reg  [31:0]    data;
        integer        fd;
        integer        addr_offset;
        integer        code;
        integer        word_cnt;
        begin
            fd = $fopen(filename, "r");
            if (fd == 0) begin
                $display("ERROR: Unable to open file %s", filename);
                return;
            end

            addr_offset = 0;
            word_cnt    = 0;
            axi_write_cnt = 0;

            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", data);
                if (code == 1) begin
                    axi4_write(base_addr + addr_offset, data);
                    addr_offset = addr_offset + 4;
                    word_cnt = word_cnt + 1;
                    if (word_cnt % 512 == 1) begin
                        $display("[PROBE] %0t: AXI write progress: word %0d addr=0x%08h awready=%b wready=%b bvalid=%b",
                                 $time, word_cnt, base_addr + addr_offset,
                                 u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awready,
                                 u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wready,
                                 u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_bvalid);
                        $fflush;
                    end
                end
            end

            $fclose(fd);

            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awid;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awaddr;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awlen;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awsize;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awburst;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awlock;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awcache;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awprot;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awqos;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_awvalid;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wdata;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wstrb;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wlast;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_wvalid;
            release u_soc.ddr3.u_axi_wrap_ddr.mig_axi.s_axi_bready;

            $display("write_hex_file: %s loaded, %0d bytes total", filename, addr_offset);
        end
    endtask

    // ------------------------------------------------------------
    // ddr_data_init sequencing for DDR3 mode:
    //   1. Force ddr_data_init = 0 (hold CPU in reset)
    //   2. Wait for MIG init_calib_complete
    //   3. Load hex file into DDR3 via write_hex_file
    //   4. Reset Axi_CDC (toggle axiOutRst)
    //   5. Force ddr_data_init = 1 (release CPU)
    // ------------------------------------------------------------
    initial begin
        force u_soc.ddr_data_init = 1'b0;
        $display("[PROBE] %0t: Waiting for MIG init_calib_complete...", $time);
        $fflush;
        wait(u_soc.ddr3.u_axi_wrap_ddr.mig_axi.init_calib_complete);
        $display("[PROBE] %0t: MIG init_calib_complete = 1, loading hex file...", $time);
        $fflush;
        write_hex_file(32'h80000000, "prog.hex");
        $display("[PROBE] %0t: Hex file loaded, resetting Axi_CDC...", $time);
        $fflush;
        @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
        force u_soc.ddr3.u_axi_wrap_ddr.u_Axi_CDC.axiOutRst = 1'b0;
        @(posedge u_soc.ddr3.u_axi_wrap_ddr.mig_axi.ui_clk);
        force u_soc.ddr3.u_axi_wrap_ddr.u_Axi_CDC.axiOutRst = 1'b1;
        force u_soc.ddr_data_init = 1'b1;
        $display("[PROBE] %0t: ddr_data_init released, CPU starting!", $time);
        $fflush;
    end

end
endgenerate

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
//   In DDR3 mode, prints warning and skips (cannot directly read
//   DDR3 model memory from testbench hierarchy).
// ----------------------------------------------------------------
task check_mem_word;
    input  [31:0] addr;
    input  [31:0] expected;
    reg    [31:0] actual;
    begin
`ifndef SIMU_DDR_MODE
        // SRAM mode: read directly from axi_wrap_ram BRAM array
        // addr is byte address, BRAM is word-addressed
        actual = u_soc.sim_ram.u_axi_ram.BRAM[addr[20:2]];
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("  PASS mem[0x%08h] = 0x%08h", addr, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, actual);
        end
`else
        // DDR3 mode: cannot directly read DDR3 model memory from TB hierarchy
        $display("  WARN: check_mem_word skipped in DDR3 mode");
        pass_count = pass_count + 1;
`endif
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

// ============================================================================
// Debug trace infrastructure (conditional compilation — each feature independent)
//
// Enable via Verilog defines at compile time:
//   xvlog -sv -d DEBUG_TRACE ...
//   xvlog -sv -d DEBUG_TRACE -d DEBUG_TRAP -d DEBUG_WAVE ...
//
// Runtime control via plusargs:
//   xsim ... +trace_enable=0 +trace_file=my_trace.log
// ============================================================================

// ── 1.1 Instruction trace log (DEBUG_TRACE) ──────────────────────────────────
// Format: Cycle  Time  PC         Inst      Event  RD   Value
// Events: N=normal, BR=branch, TR=trap_enter, MR=mret_return
`ifdef DEBUG_TRACE
    integer dbg_trace_fd;
    integer dbg_trace_cycle;
    logic   dbg_trace_enable;
    string  dbg_trace_file;

    initial begin
        dbg_trace_enable = 1'b1;
        dbg_trace_file   = "instr_trace.log";
        void'($value$plusargs("trace_enable=%b", dbg_trace_enable));
        void'($value$plusargs("trace_file=%s", dbg_trace_file));
        if (dbg_trace_enable) begin
            dbg_trace_fd = $fopen(dbg_trace_file, "w");
            if (dbg_trace_fd == 0) begin
                $display("[DEBUG-TRACE] ERROR: Cannot open trace file: %s", dbg_trace_file);
            end else begin
                $fwrite(dbg_trace_fd, "# Instruction Trace Log\n");
                $fwrite(dbg_trace_fd, "# Cycle\tTime\tPC\t\tInst\t\tEv\tRD\tValue\n");
            end
        end
        dbg_trace_cycle = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_trace_enable && dbg_trace_fd != 0 && u_soc.cpu.if_done) begin
            dbg_trace_cycle = dbg_trace_cycle + 1;
            $fwrite(dbg_trace_fd, "%0d\t%0t\t%08h\t%08h",
                    dbg_trace_cycle, $time, if_pc, if_inst);
            // Event classification
            if (u_soc.cpu.exe_branch_taken)
                $fwrite(dbg_trace_fd, "\tBR");
            else if (u_soc.cpu.trap_enter_valid)
                $fwrite(dbg_trace_fd, "\tTR");
            else if (u_soc.cpu.trap_return_valid)
                $fwrite(dbg_trace_fd, "\tMR");
            else
                $fwrite(dbg_trace_fd, "\tN ");
            // WB register writeback
            if (u_soc.cpu.rf_wen && u_soc.cpu.rf_waddr != 5'd0)
                $fwrite(dbg_trace_fd, "\tx%0d\t%08h", u_soc.cpu.rf_waddr, u_soc.cpu.actual_rf_wdata);
            else
                $fwrite(dbg_trace_fd, "\t---\t--------");
            $fwrite(dbg_trace_fd, "\n");
            if (dbg_trace_cycle % 10000 == 0) $fflush(dbg_trace_fd);
        end
    end

    final begin
        if (dbg_trace_fd != 0) begin
            $fflush(dbg_trace_fd);
            $fclose(dbg_trace_fd);
            $display("[DEBUG-TRACE] Trace log closed: %0d instructions, file: %s",
                     dbg_trace_cycle, dbg_trace_file);
        end
    end
`endif

// ── 1.2 Pipeline state dump (DEBUG_PIPELINE) ─────────────────────────────────
// Dumps all five pipeline stages each cycle: PC, Inst, valid
`ifdef DEBUG_PIPELINE
    integer dbg_pipe_fd;
    integer dbg_pipe_cycle;

    initial begin
        dbg_pipe_fd = $fopen("pipeline_dump.log", "w");
        if (dbg_pipe_fd != 0) begin
            $fwrite(dbg_pipe_fd, "# Pipeline State Dump\n");
            $fwrite(dbg_pipe_fd, "# Cycle\tTime\tIF_PC\tIF_Inst\tID_PC\tID_Inst\tEX_PC\tEX_Inst\tMEM_PC\tMEM_Inst\tWB_PC\tWB_Inst\tFSM\tPriv\n");
        end
        dbg_pipe_cycle = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_pipe_fd != 0) begin
            dbg_pipe_cycle = dbg_pipe_cycle + 1;
            $fwrite(dbg_pipe_fd, "%0d\t%0t\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                    dbg_pipe_cycle, $time,
                    if_pc, if_inst,
                    u_soc.cpu.id_pc, u_soc.cpu.id_inst,
                    exe_pc, exe_inst,
                    u_soc.cpu.mem_pc, u_soc.cpu.mem_inst,
                    wb_pc, wb_inst,
                    u_soc.cpu.fsm_state, u_soc.cpu.priv_mode);
            if (dbg_pipe_cycle % 10000 == 0) $fflush(dbg_pipe_fd);
        end
    end

    final begin
        if (dbg_pipe_fd != 0) begin
            $fflush(dbg_pipe_fd);
            $fclose(dbg_pipe_fd);
            $display("[DEBUG-PIPELINE] Pipeline dump closed: %0d cycles", dbg_pipe_cycle);
        end
    end
`endif

// ── 1.3 Trap/exception trace (DEBUG_TRAP) ────────────────────────────────────
// Logs trap entry, mret return, and CSR state changes
`ifdef DEBUG_TRAP
    integer dbg_trap_fd;
    integer dbg_trap_count;

    initial begin
        dbg_trap_fd = $fopen("trap_trace.log", "w");
        if (dbg_trap_fd != 0) begin
            $fwrite(dbg_trap_fd, "# Trap/Exception Trace Log\n");
            $fwrite(dbg_trap_fd, "# Cycle\tTime\tEvent\tPC\t\tmstatus\t\tmepc\t\tmcause\t\tPriv\n");
        end
        dbg_trap_count = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_trap_fd != 0) begin
            if (u_soc.cpu.trap_enter_valid) begin
                dbg_trap_count = dbg_trap_count + 1;
                $fwrite(dbg_trap_fd, "%0d\t%0t\tTRAP_IN\t%08h\t%08h\t%08h\t%08h\t%0d\n",
                        dbg_trap_count, $time, if_pc,
                        u_soc.cpu.csr_mstatus, u_soc.cpu.csr_mepc,
                        u_soc.cpu.csr_mcause, u_soc.cpu.priv_mode);
                $fflush(dbg_trap_fd);
            end
            if (u_soc.cpu.trap_return_valid) begin
                dbg_trap_count = dbg_trap_count + 1;
                $fwrite(dbg_trap_fd, "%0d\t%0t\tMRET\t%08h\t%08h\t%08h\t%08h\t%0d\n",
                        dbg_trap_count, $time, if_pc,
                        u_soc.cpu.csr_mstatus, u_soc.cpu.csr_mepc,
                        u_soc.cpu.csr_mcause, u_soc.cpu.priv_mode);
                $fflush(dbg_trap_fd);
            end
        end
    end

    final begin
        if (dbg_trap_fd != 0) begin
            $fflush(dbg_trap_fd);
            $fclose(dbg_trap_fd);
            $display("[DEBUG-TRAP] Trap trace closed: %0d events", dbg_trap_count);
        end
    end
`endif

// ── 1.4 Spike-compatible commit log (DEBUG_SPIKE) ────────────────────────────
// Format: priv pc (inst) rd val  (matches Spike ISA simulator commit log)
`ifdef DEBUG_SPIKE
    integer dbg_spike_fd;
    integer dbg_spike_cycle;

    initial begin
        dbg_spike_fd = $fopen("spike_commit.log", "w");
        if (dbg_spike_fd == 0) begin
            $display("[DEBUG-SPIKE] ERROR: Cannot open spike_commit.log");
        end
        dbg_spike_cycle = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_spike_fd != 0 && u_soc.cpu.if_done) begin
            dbg_spike_cycle = dbg_spike_cycle + 1;
            // Spike format: priv pc (inst)
            $fwrite(dbg_spike_fd, "%0d 0x%08h (0x%08h)",
                    u_soc.cpu.priv_mode, if_pc, if_inst);
            // Register writeback (Spike: rd val)
            if (u_soc.cpu.rf_wen && u_soc.cpu.rf_waddr != 5'd0) begin
                $fwrite(dbg_spike_fd, " x%0d 0x%08h", u_soc.cpu.rf_waddr, u_soc.cpu.actual_rf_wdata);
            end
            $fwrite(dbg_spike_fd, "\n");
            if (dbg_spike_cycle % 10000 == 0) $fflush(dbg_spike_fd);
        end
    end

    final begin
        if (dbg_spike_fd != 0) begin
            $fflush(dbg_spike_fd);
            $fclose(dbg_spike_fd);
            $display("[DEBUG-SPIKE] Spike commit log closed: %0d instructions", dbg_spike_cycle);
        end
    end
`endif

// ── 1.5 VCD waveform generation (DEBUG_WAVE) ─────────────────────────────────
// Generates VCD dump for open-source waveform viewers (GTKWave, etc.)
// XSim also generates WDB natively; this provides VCD for portability.
`ifdef DEBUG_WAVE
    initial begin
        $dumpfile("sim_dump.vcd");
        $dumpvars(0, u_soc);
    end
`endif
