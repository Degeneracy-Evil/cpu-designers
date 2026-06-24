`timescale 1ns / 1ps

// ============================================================================
// tb_kernel_boot.sv — Linux kernel boot simulation testbench
//
// Loads OpenSBI+kernel payload (fw_payload.hex) into DDR3 via AXI4 force
// writes, then releases the CPU to boot. Captures:
//   - Trap delegation debug (exc_delegated, trap_to_s, exception_mtval_r, etc.)
//   - UART TX output (kernel printk)
//   - Instruction trace (if DEBUG_TRACE enabled)
//   - Trap trace (if DEBUG_TRAP enabled)
//
// Usage:
//   python3 -m tools.vivado_cli -task kernel_boot_ddr3 -create -sim \
//          --debug trace,trap,wave
//
// Debug defines:
//   DEBUG_TRAP_DELEG — trap delegation detail log (trap_deleg.log)
//   DEBUG_UART_TX    — UART TX character capture (uart_tx.log)
//   DEBUG_TRACE      — instruction trace (instr_trace.log) [from includes]
//   DEBUG_TRAP       — trap event trace (trap_trace.log) [from includes]
//   DEBUG_WAVE       — VCD waveform [from includes]
// ============================================================================

module tb_kernel_boot;

    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg
    `include "tb_soc_includes.svh"

    // ========================================================================
    // Trap Delegation Debug Log (DEBUG_TRAP_DELEG)
    // Logs every trap_enter_valid cycle with full delegation decision path:
    //   exc_delegated, trap_to_s, target_priv, exception_mtval_r, etc.
    // ========================================================================
`ifdef DEBUG_TRAP_DELEG
    integer dbg_deleg_fd;
    integer dbg_deleg_count;

    initial begin
        dbg_deleg_fd = $fopen("trap_deleg.log", "w");
        if (dbg_deleg_fd != 0) begin
            $fwrite(dbg_deleg_fd, "# Trap Delegation Debug Log\n");
            $fwrite(dbg_deleg_fd, "# Cycle\tTime\tEvent\tPC\t\tPriv\tTPriv\tCause\tDeleg\tToS\tEPC\t\tEMTVAL\t\tIPF_VA\t\tHW_EPC\t\tHW_TVAL\t\tHW_WEN\tHW_TPRIV\tMEDELEG\n");
        end
        dbg_deleg_count = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_deleg_fd != 0) begin
            // Log on trap_enter_valid — the cycle where CSR writes happen
            if (u_soc.cpu.trap_enter_valid) begin
                dbg_deleg_count = dbg_deleg_count + 1;
                $fwrite(dbg_deleg_fd, "%0d\t%0t\tTRAP_IN\t%08h\t%0d\t%0d\t%08h\t%b\t%b\t%08h\t%08h\t%08h\t%08h\t%08h\t%b\t%0d\t%08h\n",
                        dbg_deleg_count, $time, if_pc,
                        u_soc.cpu.priv_mode,           // current privilege
                        u_soc.cpu.target_priv,          // target privilege
                        u_soc.cpu.csr_mcause,           // mcause (raw cause)
                        u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.exc_delegated,  // delegation decision
                        u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.trap_to_s,      // trap to S-mode?
                        u_soc.cpu.u_trap_csr.u_trap_mgr.exception_pc_r,         // exception PC (→mepc/sepc)
                        u_soc.cpu.u_trap_csr.u_trap_mgr.exception_mtval_r,      // exception mtval (→mtval/stval)
                        u_soc.cpu.u_trap_csr.u_trap_mgr.inst_page_fault_vaddr_r, // inst PF vaddr
                        u_soc.cpu.hw_trap_epc,          // hw mepc/sepc write data
                        u_soc.cpu.hw_trap_tval,         // hw mtval/stval write data
                        u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.hw_csr_wen,     // CSR write enable
                        u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.hw_target_priv, // hw target priv
                        u_soc.cpu.csr_medeleg           // medeleg register
                );
                $fflush(dbg_deleg_fd);
            end
            // Log on trap_return_valid — mret/sret
            if (u_soc.cpu.trap_return_valid) begin
                dbg_deleg_count = dbg_deleg_count + 1;
                $fwrite(dbg_deleg_fd, "%0d\t%0t\tRET\t%08h\t%0d\t--\t--\t--\t--\t--\t--\t--\t%08h\t%08h\t--\t--\t%08h\n",
                        dbg_deleg_count, $time, if_pc,
                        u_soc.cpu.priv_mode,
                        u_soc.cpu.hw_trap_epc,          // return PC (mepc/sepc)
                        u_soc.cpu.hw_trap_tval,
                        u_soc.cpu.csr_medeleg
                );
                $fflush(dbg_deleg_fd);
            end
        end
    end

    final begin
        if (dbg_deleg_fd != 0) begin
            $fflush(dbg_deleg_fd);
            $fclose(dbg_deleg_fd);
            $display("[DEBUG-TRAP-DELEG] Trap delegation log closed: %0d events", dbg_deleg_count);
        end
    end
`endif

    // ========================================================================
    // UART TX Capture (DEBUG_UART_TX)
    // Captures characters transmitted on uart_tx line, mimicking a real
    // UART receiver. Outputs to uart_tx.log as raw text.
    // ========================================================================
`ifdef DEBUG_UART_TX
    integer dbg_uart_fd;
    integer dbg_uart_bits;
    reg [7:0] dbg_uart_byte;
    reg       dbg_uart_capturing;

    initial begin
        dbg_uart_fd = $fopen("uart_tx.log", "w");
        if (dbg_uart_fd != 0) begin
            $fwrite(dbg_uart_fd, "# UART TX Capture Log (kernel printk output)\n");
        end
        dbg_uart_bits = 0;
        dbg_uart_capturing = 0;
        dbg_uart_byte = 8'b0;
    end

    // UART receiver state machine — uses the UART's internal enable signal
    // for accurate bit timing. The enable pulses once per dl clock cycles,
    // and the transmitter counts 16 enable pulses per bit.
    // By counting enable pulses instead of raw clock cycles, we avoid
    // misalignment between the enable signal and state transitions.
    //
    // Timing: enable is a registered 1-cycle pulse. The transmitter updates
    // stx_o_tmp via non-blocking assignment during an enable pulse. The TB
    // reads both enable and uart_tx at posedge clk, seeing values from the
    // previous cycle's assignments. When the TB detects uart_tx=0 on an
    // enable pulse, the start bit was set by the transmitter on that same
    // enable pulse (non-blocking: both see the same "before" state, then
    // both update). So cnt=0 is the first enable of the start bit.
    // We sample at mid-bit: start at cnt=8, data bit N at cnt=24+N*16.

    integer uart_rx_enable_cnt;

    initial begin
        uart_rx_enable_cnt = 0;
        forever begin
            @(posedge clk);
            if (resetn) begin
                if (u_soc.u_apb_perips.u_uart.regs.enable) begin
                    if (!dbg_uart_capturing) begin
                        if (uart_tx === 1'b0) begin
                            dbg_uart_capturing = 1;
                            dbg_uart_bits = 0;
                            dbg_uart_byte = 8'b0;
                            uart_rx_enable_cnt = 0;
                        end
                    end else begin
                        uart_rx_enable_cnt = uart_rx_enable_cnt + 1;
                        if (uart_rx_enable_cnt == 8 && dbg_uart_bits == 0) begin
                            if (uart_tx !== 1'b0) begin
                                dbg_uart_capturing = 0;
                            end
                        end else if (dbg_uart_bits < 8 &&
                                    uart_rx_enable_cnt == 24 + dbg_uart_bits * 16) begin
                            dbg_uart_byte[dbg_uart_bits] = uart_tx;
                            dbg_uart_bits = dbg_uart_bits + 1;
                        end else if (dbg_uart_bits == 8 &&
                                    uart_rx_enable_cnt >= 24 + 8 * 16) begin
                            if (dbg_uart_fd != 0) begin
                                if (dbg_uart_byte == 8'h0A) begin
                                    $fwrite(dbg_uart_fd, "\n");
                                end else if (dbg_uart_byte >= 8'h20 && dbg_uart_byte < 8'h7F) begin
                                    $fwrite(dbg_uart_fd, "%c", dbg_uart_byte);
                                end else begin
                                    $fwrite(dbg_uart_fd, "[0x%02h]", dbg_uart_byte);
                                end
                                $fflush(dbg_uart_fd);
                            end
                            dbg_uart_capturing = 0;
                        end
                    end
                end
            end
        end
    end
    final begin
        if (dbg_uart_fd != 0) begin
            $fflush(dbg_uart_fd);
            $fclose(dbg_uart_fd);
            $display("[DEBUG-UART-TX] UART TX log closed");
        end
    end
`endif

    // ========================================================================
    // Progress probe: print PC + key state every 1M cycles
    // ========================================================================
    integer probe_cnt;
    initial begin
        probe_cnt = 0;
        forever begin
            @(posedge clk);
            probe_cnt = probe_cnt + 1;
            if (probe_cnt % 1000000 == 0) begin
                $display("[PROBE] %0t: cycle=%0dM PC=0x%08h inst=0x%08h priv=%0d ddr_init=%b",
                         $time, probe_cnt/1000000, if_pc, if_inst,
                         u_soc.cpu.priv_mode, u_soc.ddr_data_init);
                $fflush;
            end
        end
    end

    // ========================================================================
    // PC watchdog: detect when PC enters the BSS region (0xC04F_0000-0xC050_0000)
    // This is where the kernel crash occurs on FPGA.
    // ========================================================================
    initial begin
        forever begin
            @(posedge clk);
            if (resetn && u_soc.cpu.if_done) begin
                if (if_pc[31:24] == 8'hC0 && if_pc[23:16] == 8'h4F) begin
                    $display("[WATCHDOG] %0t: PC entered BSS region! PC=0x%08h inst=0x%08h priv=%0d",
                             $time, if_pc, if_inst, u_soc.cpu.priv_mode);
                    $display("[WATCHDOG]   mepc=0x%08h mcause=0x%08h sepc=0x%08h scause=0x%08h stval=0x%08h",
                             u_soc.cpu.csr_mepc, u_soc.cpu.csr_mcause,
                             u_soc.cpu.csr_sepc, u_soc.cpu.csr_scause, u_soc.cpu.csr_stval);
                    $display("[WATCHDOG]   medeleg=0x%08h mstatus=0x%08h satp=0x%08h",
                             u_soc.cpu.csr_medeleg, u_soc.cpu.csr_mstatus, u_soc.cpu.csr_satp);
                    $fflush;
                end
            end
        end
    end

    // ========================================================================
    // Main simulation body
    // ========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        // DDR3 mode: wait for ddr_data_init (set by tb_soc_includes after
        // MIG calibration + hex file loading via AXI4 force writes)
        $display("[PROBE] %0t: Kernel boot sim: waiting for ddr_data_init...", $time);
        $fflush;
        wait(u_soc.ddr_data_init);
        $display("[PROBE] %0t: ddr_data_init=1, CPU released! Kernel boot starting...", $time);
        $fflush;

        // Run for a very long time — kernel boot takes millions of cycles
        // 3B cycles at 100MHz = 30 seconds of sim time (kernel panic at ~0.63s)
        // The sim will be killed by timeout or $finish before this completes
        repeat (2000000000) @(posedge clk);

        $display("========================================");
        $display("[PROBE] %0t: Kernel boot simulation complete (3B cycles reached).", $time);
        $display("Check trap_deleg.log, trap_trace.log, instr_trace.log, uart_tx.log");
        $display("========================================");
        $finish;
    end

endmodule
