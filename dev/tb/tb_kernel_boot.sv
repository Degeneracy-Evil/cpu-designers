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
    // IF sanity checker (enabled together with DEBUG_TRAP)
    // Stops at the first impossible fetch/decode fact instead of waiting for
    // trap-loop, and logs a compact event stream for the fetch path.
    // ========================================================================
`ifdef DEBUG_TRAP
    integer dbg_if_fd;
    integer dbg_forensic_fd;
    integer dbg_if_cycle;
    reg     dbg_if_miss_prev;
    reg     dbg_ptw_active_prev;
    reg     dbg_refill_prev;
    reg [31:0] dbg_expected_inst;
    reg [31:0] dbg_last_map_vaddr;
    reg [31:0] dbg_last_map_paddr;
    reg        dbg_last_map_valid;

    localparam integer IF_SANITY_ENABLE_CYCLE = 200000000;
    localparam integer FORENSIC_DEPTH = 128;

    integer dbg_forensic_wr_ptr;
    integer dbg_forensic_count;
    reg     dbg_forensic_dumped;
    integer dbg_forensic_i;

    time     forensic_time           [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_cycle        [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_if_pc        [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_if_inst      [0:FORENSIC_DEPTH-1];
    reg        forensic_if_done      [0:FORENSIC_DEPTH-1];
    reg        forensic_inst_valid   [0:FORENSIC_DEPTH-1];
    reg        forensic_id_valid     [0:FORENSIC_DEPTH-1];
    reg        forensic_id_done      [0:FORENSIC_DEPTH-1];
    reg [95:0] forensic_if_id_bus_r  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_id_pc        [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_id_inst      [0:FORENSIC_DEPTH-1];
    reg        forensic_dec_ecall    [0:FORENSIC_DEPTH-1];
    reg        forensic_dec_illegal  [0:FORENSIC_DEPTH-1];
    reg        forensic_dec_ebreak   [0:FORENSIC_DEPTH-1];
    reg        forensic_exc_at_dec   [0:FORENSIC_DEPTH-1];
    reg        forensic_exc_valid    [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_cause    [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_pc       [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_mtval    [0:FORENSIC_DEPTH-1];
    reg        forensic_exc_valid_r  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_cause_r  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_pc_r     [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_exc_mtval_r  [0:FORENSIC_DEPTH-1];
    reg        forensic_af_valid     [0:FORENSIC_DEPTH-1];
    reg        forensic_pf_valid     [0:FORENSIC_DEPTH-1];
    reg        forensic_misalign_val [0:FORENSIC_DEPTH-1];
    reg        forensic_exe_exc_val  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_dec_exc_cause[0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_dec_exc_tval [0:FORENSIC_DEPTH-1];
    reg        forensic_trap_enter   [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_hw_cause     [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_hw_epc       [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_hw_tval      [0:FORENSIC_DEPTH-1];
    reg        forensic_trap_pending [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_trap_pc      [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_priv         [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_target_priv  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_satp         [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_fetch_vaddr  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_mmu_paddr    [0:FORENSIC_DEPTH-1];
    reg        forensic_mmu_ready    [0:FORENSIC_DEPTH-1];
    reg        forensic_mmu_miss     [0:FORENSIC_DEPTH-1];
    reg        forensic_mmu_pf       [0:FORENSIC_DEPTH-1];
    reg [3:0]  forensic_mmu_pf_cause [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_mmu_pf_vaddr [0:FORENSIC_DEPTH-1];
    reg [2:0]  forensic_mmu_i_state  [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_walk_state   [0:FORENSIC_DEPTH-1];
    reg        forensic_tlb_hit      [0:FORENSIC_DEPTH-1];
    reg        forensic_tlb_valid    [0:FORENSIC_DEPTH-1];
    reg        forensic_walk_active  [0:FORENSIC_DEPTH-1];
    reg        forensic_pending_i    [0:FORENSIC_DEPTH-1];
    reg [2:0]  forensic_ic_state     [0:FORENSIC_DEPTH-1];
    reg        forensic_refill_req   [0:FORENSIC_DEPTH-1];
    reg        forensic_refill_valid [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_refill_addr  [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_refill_data0 [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_sel_word     [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_sel_woff     [0:FORENSIC_DEPTH-1];
    reg        forensic_arvalid      [0:FORENSIC_DEPTH-1];
    reg        forensic_arready      [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_araddr       [0:FORENSIC_DEPTH-1];
    reg        forensic_rvalid       [0:FORENSIC_DEPTH-1];
    reg        forensic_rready       [0:FORENSIC_DEPTH-1];
    reg        forensic_rlast        [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_rdata        [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_shadow_inst  [0:FORENSIC_DEPTH-1];

    function is_sram_cacheable_addr;
        input [31:0] addr;
        begin
            is_sram_cacheable_addr = addr[31] && !addr[30] && (addr[29:27] == 3'b000);
        end
    endfunction

    function if_sanity_window_active;
        begin
            if_sanity_window_active =
                (dbg_if_cycle >= IF_SANITY_ENABLE_CYCLE) &&
                (u_soc.cpu.priv_mode == 2'b01) &&
                u_soc.cpu.csr_satp[31];
        end
    endfunction

    task dump_forensic_buffer;
        input [255:0] reason;
        integer start_idx;
        integer dump_idx;
        integer line_idx;
        begin
            if (dbg_forensic_dumped)
                disable dump_forensic_buffer;
            dbg_forensic_dumped = 1'b1;

            if (dbg_forensic_fd != 0) begin
                $fwrite(dbg_forensic_fd, "# ================================================================\n");
                $fwrite(dbg_forensic_fd, "# Trap forensic dump: reason=%0s cycle=%0d time=%0t\n", reason, dbg_if_cycle, $time);
                $fwrite(dbg_forensic_fd, "# idx cyc time if_pc if_inst ifd iv idv idd id_pc id_inst de decill debrk exd exv excause expc exmt exvr excr expr extr afv pfv msv exev decc dect trap hwc hwe hwt tpend tpc priv tpriv satp fva mpa mrdy mmiss mpf mpfc mpfv mis ws th tv wa pi ics rr rv ra rd sw wo arv arr ara rvv rry rls rdt shadow\n");
                start_idx = (dbg_forensic_wr_ptr - dbg_forensic_count + FORENSIC_DEPTH) % FORENSIC_DEPTH;
                for (line_idx = 0; line_idx < dbg_forensic_count; line_idx = line_idx + 1) begin
                    dump_idx = (start_idx + line_idx) % FORENSIC_DEPTH;
                    $fwrite(dbg_forensic_fd,
                            "%0d %0d %0t %08h %08h %0b %0b %0b %0b %08h %08h %0b %0b %0b %0b %0b %08h %08h %08h %0b %08h %08h %08h %0b %0b %0b %0b %08h %08h %0b %08h %08h %08h %0b %08h %0d %0d %08h %08h %08h %0b %0b %0b %0d %08h %0d %0d %0b %0b %0d %0b %0b %0b %0b %08h %08h %08h %0d %0b %0b %08h %0b %0b %0b %08h %08h\n",
                            line_idx, forensic_cycle[dump_idx], forensic_time[dump_idx],
                            forensic_if_pc[dump_idx], forensic_if_inst[dump_idx],
                            forensic_if_done[dump_idx], forensic_inst_valid[dump_idx],
                            forensic_id_valid[dump_idx], forensic_id_done[dump_idx],
                            forensic_id_pc[dump_idx], forensic_id_inst[dump_idx],
                            forensic_dec_ecall[dump_idx], forensic_dec_illegal[dump_idx], forensic_dec_ebreak[dump_idx],
                            forensic_exc_at_dec[dump_idx], forensic_exc_valid[dump_idx],
                            forensic_exc_cause[dump_idx], forensic_exc_pc[dump_idx], forensic_exc_mtval[dump_idx],
                            forensic_exc_valid_r[dump_idx], forensic_exc_cause_r[dump_idx],
                            forensic_exc_pc_r[dump_idx], forensic_exc_mtval_r[dump_idx],
                            forensic_af_valid[dump_idx], forensic_pf_valid[dump_idx],
                            forensic_misalign_val[dump_idx], forensic_exe_exc_val[dump_idx],
                            forensic_dec_exc_cause[dump_idx], forensic_dec_exc_tval[dump_idx],
                            forensic_trap_enter[dump_idx], forensic_hw_cause[dump_idx],
                            forensic_hw_epc[dump_idx], forensic_hw_tval[dump_idx],
                            forensic_trap_pending[dump_idx], forensic_trap_pc[dump_idx],
                            forensic_priv[dump_idx], forensic_target_priv[dump_idx],
                            forensic_satp[dump_idx], forensic_fetch_vaddr[dump_idx],
                            forensic_mmu_paddr[dump_idx], forensic_mmu_ready[dump_idx],
                            forensic_mmu_miss[dump_idx], forensic_mmu_pf[dump_idx],
                            forensic_mmu_pf_cause[dump_idx], forensic_mmu_pf_vaddr[dump_idx],
                            forensic_mmu_i_state[dump_idx], forensic_walk_state[dump_idx],
                            forensic_tlb_hit[dump_idx], forensic_tlb_valid[dump_idx],
                            forensic_walk_active[dump_idx], forensic_pending_i[dump_idx],
                            forensic_ic_state[dump_idx], forensic_refill_req[dump_idx],
                            forensic_refill_valid[dump_idx], forensic_refill_addr[dump_idx],
                            forensic_refill_data0[dump_idx], forensic_sel_word[dump_idx],
                            forensic_sel_woff[dump_idx], forensic_arvalid[dump_idx],
                            forensic_arready[dump_idx], forensic_araddr[dump_idx],
                            forensic_rvalid[dump_idx], forensic_rready[dump_idx],
                            forensic_rlast[dump_idx], forensic_rdata[dump_idx],
                            forensic_shadow_inst[dump_idx]);
                end
                $fflush(dbg_forensic_fd);
            end
        end
    endtask

    task dump_if_sanity_snapshot;
        input [255:0] reason;
        reg [31:0] shadow_word;
        begin
`ifndef SIMU_DDR_MODE
            if (is_sram_cacheable_addr(u_soc.cpu.mmu_inst_paddr))
                shadow_word = u_soc.sim_ram.u_axi_ram.BRAM[u_soc.cpu.mmu_inst_paddr[26:2]];
            else
                shadow_word = 32'hXXXXXXXX;
`else
            shadow_word = 32'hXXXXXXXX;
`endif
            $display("");
            $display("========================================");
            $display("[IF-SANITY] %0t cycle=%0d reason=%0s", $time, dbg_if_cycle, reason);
            $display("========================================");
            $display("[IF-SANITY] if_pc=0x%08h if_inst=0x%08h id_pc=0x%08h id_inst=0x%08h",
                     if_pc, if_inst, id_pc, id_inst);
            $display("[IF-SANITY] if_done=%0b inst_valid=%0b dec_is_ecall=%0b priv=%0d",
                     u_soc.cpu.if_done, u_soc.cpu.inst_valid_mux, u_soc.cpu.dec_is_ecall, u_soc.cpu.priv_mode);
            $display("[IF-SANITY] mmu_paddr=0x%08h mmu_ready=%0b mmu_miss=%0b i_pf=%0b satp=0x%08h",
                     u_soc.cpu.mmu_inst_paddr, u_soc.cpu.mmu_inst_ready, u_soc.cpu.mmu_inst_miss,
                     u_soc.cpu.mmu_inst_page_fault, u_soc.cpu.csr_satp);
            $display("[IF-SANITY] shadow_inst=0x%08h fetch_vaddr=0x%08h latched_vaddr=0x%08h",
                     shadow_word, u_soc.cpu.fetch_vaddr, u_soc.cpu.mmu_dbg_i_latched_vaddr);
            $display("[IF-SANITY] icache: state=%0d mmio_req=%0b refill_req=%0b refill_valid=%0b refill_addr=0x%08h",
                     u_soc.cpu.icache_dbg_state, u_soc.cpu.icache_mmio_req,
                     u_soc.cpu.icache_refill_req, u_soc.cpu.icache_refill_valid,
                     u_soc.cpu.icache_refill_addr);
            $display("[IF-SANITY] mmu: i_state=%0d walk_state=%0d tlb_hit=%0b tlb_valid=%0b tlb_pf=%0b input_changed=%0b",
                     u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.mmu_dbg_walk_state,
                     u_soc.cpu.mmu_dbg_i_tlb_hit, u_soc.cpu.mmu_dbg_i_tlb_valid,
                     u_soc.cpu.mmu_dbg_i_tlb_perm_fault, u_soc.cpu.mmu_dbg_i_input_changed);
            $display("[IF-SANITY] trap: enter=%0b cause=0x%08h epc=0x%08h tval=0x%08h",
                     u_soc.cpu.trap_enter_valid, u_soc.cpu.hw_trap_cause,
                     u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval);
            $fflush;
            if (dbg_if_fd != 0) begin
                $fwrite(dbg_if_fd, "SNAPSHOT\t%0d\t%0t\t%0s\t%08h\t%08h\t%08h\t%08h\t%0b\t%0b\t%0b\t%0b\t%08h\t%08h\t%0d\t%0d\t%0b\t%0b\t%08h\t%0b\t%08h\t%08h\t%08h\n",
                        dbg_if_cycle, $time, reason,
                        if_pc, if_inst, shadow_word, u_soc.cpu.mmu_inst_paddr,
                        u_soc.cpu.if_done, u_soc.cpu.inst_valid_mux, u_soc.cpu.dec_is_ecall,
                        u_soc.cpu.mmu_inst_ready, u_soc.cpu.fetch_vaddr, u_soc.cpu.mmu_dbg_i_latched_vaddr,
                        u_soc.cpu.icache_dbg_state, u_soc.cpu.mmu_dbg_i_state,
                        u_soc.cpu.icache_refill_req, u_soc.cpu.icache_refill_valid, u_soc.cpu.icache_refill_addr,
                        u_soc.cpu.trap_enter_valid, u_soc.cpu.hw_trap_cause,
                        u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval);
                $fflush(dbg_if_fd);
            end
        end
    endtask

    initial begin
        dbg_if_fd = $fopen("if_sanity.log", "w");
        dbg_forensic_fd = $fopen("trap_forensics_dump.log", "w");
        if (dbg_if_fd != 0) begin
            $fwrite(dbg_if_fd, "# IF sanity event log\n");
            $fwrite(dbg_if_fd, "# Cycle\tTime\tEvent\tPC\tINST\tPADDR\tAUX0\tAUX1\tAUX2\tAUX3\tAUX4\n");
        end
        dbg_if_cycle = 0;
        dbg_if_miss_prev = 1'b0;
        dbg_ptw_active_prev = 1'b0;
        dbg_refill_prev = 1'b0;
        dbg_expected_inst = 32'b0;
        dbg_last_map_vaddr = 32'b0;
        dbg_last_map_paddr = 32'b0;
        dbg_last_map_valid = 1'b0;
        dbg_forensic_wr_ptr = 0;
        dbg_forensic_count = 0;
        dbg_forensic_dumped = 1'b0;
    end

    always @(posedge clk) begin
        if (resetn) begin
            dbg_if_cycle = dbg_if_cycle + 1;

            if (if_sanity_window_active()) begin
                forensic_time[dbg_forensic_wr_ptr]          = $time;
                forensic_cycle[dbg_forensic_wr_ptr]         = dbg_if_cycle;
                forensic_if_pc[dbg_forensic_wr_ptr]         = if_pc;
                forensic_if_inst[dbg_forensic_wr_ptr]       = if_inst;
                forensic_if_done[dbg_forensic_wr_ptr]       = u_soc.cpu.if_done;
                forensic_inst_valid[dbg_forensic_wr_ptr]    = u_soc.cpu.inst_valid_mux;
                forensic_id_valid[dbg_forensic_wr_ptr]      = u_soc.cpu.id_valid;
                forensic_id_done[dbg_forensic_wr_ptr]       = u_soc.cpu.id_done;
                forensic_if_id_bus_r[dbg_forensic_wr_ptr]   = u_soc.cpu.if_id_bus_r;
                forensic_id_pc[dbg_forensic_wr_ptr]         = u_soc.cpu.id_pc_wire;
                forensic_id_inst[dbg_forensic_wr_ptr]       = u_soc.cpu.id_inst_wire;
                forensic_dec_ecall[dbg_forensic_wr_ptr]     = u_soc.cpu.dec_is_ecall;
                forensic_dec_illegal[dbg_forensic_wr_ptr]   = u_soc.cpu.dec_illegal;
                forensic_dec_ebreak[dbg_forensic_wr_ptr]    = u_soc.cpu.dec_is_ebreak;
                forensic_exc_at_dec[dbg_forensic_wr_ptr]    = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_at_decode;
                forensic_exc_valid[dbg_forensic_wr_ptr]     = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_valid;
                forensic_exc_cause[dbg_forensic_wr_ptr]     = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_cause;
                forensic_exc_pc[dbg_forensic_wr_ptr]        = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_pc;
                forensic_exc_mtval[dbg_forensic_wr_ptr]     = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_mtval;
                forensic_exc_valid_r[dbg_forensic_wr_ptr]   = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_valid_r;
                forensic_exc_cause_r[dbg_forensic_wr_ptr]   = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_cause_r;
                forensic_exc_pc_r[dbg_forensic_wr_ptr]      = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_pc_r;
                forensic_exc_mtval_r[dbg_forensic_wr_ptr]   = u_soc.cpu.u_trap_csr.u_trap_mgr.exception_mtval_r;
                forensic_af_valid[dbg_forensic_wr_ptr]      = u_soc.cpu.u_trap_csr.u_trap_mgr.access_fault_valid;
                forensic_pf_valid[dbg_forensic_wr_ptr]      = u_soc.cpu.u_trap_csr.u_trap_mgr.pf_valid;
                forensic_misalign_val[dbg_forensic_wr_ptr]  = u_soc.cpu.u_trap_csr.u_trap_mgr.misalign_exception_valid;
                forensic_exe_exc_val[dbg_forensic_wr_ptr]   = u_soc.cpu.u_trap_csr.u_trap_mgr.exe_exception_valid;
                forensic_dec_exc_cause[dbg_forensic_wr_ptr] = u_soc.cpu.u_trap_csr.u_trap_mgr.decode_exception_cause;
                forensic_dec_exc_tval[dbg_forensic_wr_ptr]  = u_soc.cpu.u_trap_csr.u_trap_mgr.decode_exception_mtval;
                forensic_trap_enter[dbg_forensic_wr_ptr]    = u_soc.cpu.trap_enter_valid;
                forensic_hw_cause[dbg_forensic_wr_ptr]      = u_soc.cpu.hw_trap_cause;
                forensic_hw_epc[dbg_forensic_wr_ptr]        = u_soc.cpu.hw_trap_epc;
                forensic_hw_tval[dbg_forensic_wr_ptr]       = u_soc.cpu.hw_trap_tval;
                forensic_trap_pending[dbg_forensic_wr_ptr]  = u_soc.cpu.trap_pending;
                forensic_trap_pc[dbg_forensic_wr_ptr]       = u_soc.cpu.trap_csr_pc;
                forensic_priv[dbg_forensic_wr_ptr]          = u_soc.cpu.priv_mode;
                forensic_target_priv[dbg_forensic_wr_ptr]   = u_soc.cpu.target_priv;
                forensic_satp[dbg_forensic_wr_ptr]          = u_soc.cpu.csr_satp;
                forensic_fetch_vaddr[dbg_forensic_wr_ptr]   = u_soc.cpu.fetch_vaddr;
                forensic_mmu_paddr[dbg_forensic_wr_ptr]     = u_soc.cpu.mmu_inst_paddr;
                forensic_mmu_ready[dbg_forensic_wr_ptr]     = u_soc.cpu.mmu_inst_ready;
                forensic_mmu_miss[dbg_forensic_wr_ptr]      = u_soc.cpu.mmu_inst_miss;
                forensic_mmu_pf[dbg_forensic_wr_ptr]        = u_soc.cpu.mmu_inst_page_fault;
                forensic_mmu_pf_cause[dbg_forensic_wr_ptr]  = u_soc.cpu.mmu_inst_pf_cause;
                forensic_mmu_pf_vaddr[dbg_forensic_wr_ptr]  = u_soc.cpu.mmu_inst_pf_vaddr;
                forensic_mmu_i_state[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_dbg_i_state;
                forensic_walk_state[dbg_forensic_wr_ptr]    = u_soc.cpu.mmu_dbg_walk_state;
                forensic_tlb_hit[dbg_forensic_wr_ptr]       = u_soc.cpu.mmu_dbg_i_tlb_hit;
                forensic_tlb_valid[dbg_forensic_wr_ptr]     = u_soc.cpu.mmu_dbg_i_tlb_valid;
                forensic_walk_active[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_dbg_i_walk_active;
                forensic_pending_i[dbg_forensic_wr_ptr]     = u_soc.cpu.mmu_dbg_pending_i_walk;
                forensic_ic_state[dbg_forensic_wr_ptr]      = u_soc.cpu.icache_dbg_state;
                forensic_refill_req[dbg_forensic_wr_ptr]    = u_soc.cpu.icache_refill_req;
                forensic_refill_valid[dbg_forensic_wr_ptr]  = u_soc.cpu.icache_refill_valid;
                forensic_refill_addr[dbg_forensic_wr_ptr]   = u_soc.cpu.icache_refill_addr;
                forensic_refill_data0[dbg_forensic_wr_ptr]  = u_soc.cpu.icache_refill_data[31:0];
                forensic_sel_word[dbg_forensic_wr_ptr]      = u_soc.cpu.u_icache_wrap.sel_word;
                forensic_sel_woff[dbg_forensic_wr_ptr]      = u_soc.cpu.u_icache_wrap.sel_word_off;
                forensic_arvalid[dbg_forensic_wr_ptr]       = u_soc.cpu.arvalid;
                forensic_arready[dbg_forensic_wr_ptr]       = u_soc.cpu.arready;
                forensic_araddr[dbg_forensic_wr_ptr]        = u_soc.cpu.araddr;
                forensic_rvalid[dbg_forensic_wr_ptr]        = u_soc.cpu.rvalid;
                forensic_rready[dbg_forensic_wr_ptr]        = u_soc.cpu.rready;
                forensic_rlast[dbg_forensic_wr_ptr]         = u_soc.cpu.rlast;
                forensic_rdata[dbg_forensic_wr_ptr]         = u_soc.cpu.rdata;
`ifndef SIMU_DDR_MODE
                if (is_sram_cacheable_addr(u_soc.cpu.mmu_inst_paddr))
                    forensic_shadow_inst[dbg_forensic_wr_ptr] = u_soc.sim_ram.u_axi_ram.BRAM[u_soc.cpu.mmu_inst_paddr[26:2]];
                else
                    forensic_shadow_inst[dbg_forensic_wr_ptr] = 32'hXXXXXXXX;
`else
                forensic_shadow_inst[dbg_forensic_wr_ptr] = 32'hXXXXXXXX;
`endif
                dbg_forensic_wr_ptr = (dbg_forensic_wr_ptr + 1) % FORENSIC_DEPTH;
                if (dbg_forensic_count < FORENSIC_DEPTH)
                    dbg_forensic_count = dbg_forensic_count + 1;
            end

            if (dbg_if_fd != 0) begin
                if (u_soc.cpu.mmu_inst_miss && !dbg_if_miss_prev) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tI_MISS\t%08h\t%08h\t%08h\t%08h\t%0d\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.priv_mode,
                            u_soc.cpu.csr_satp, u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.mmu_dbg_walk_state);
                end
                if (u_soc.cpu.mmu_dbg_i_walk_active && !dbg_ptw_active_prev) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tPTW_START\t%08h\t%08h\t%08h\t%08h\t%0d\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.mmu_dbg_i_latched_vaddr, u_soc.cpu.priv_mode,
                            u_soc.cpu.csr_satp, u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.mmu_dbg_walk_state);
                end
                if (!u_soc.cpu.mmu_dbg_i_walk_active && dbg_ptw_active_prev) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tPTW_DONE\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.mmu_dbg_i_latched_vaddr,
                            u_soc.cpu.mmu_dbg_i_tlb_hit, u_soc.cpu.mmu_dbg_i_tlb_valid);
                end
                if (u_soc.cpu.icache_refill_req && !dbg_refill_prev) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tIC_REFILL_REQ\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.icache_refill_addr,
                            u_soc.cpu.icache_dbg_state, u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.mmu_dbg_walk_state);
                end
                if (u_soc.cpu.icache_refill_valid) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tIC_REFILL_DONE\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.icache_refill_addr,
                            u_soc.cpu.icache_refill_data[31:0], u_soc.cpu.icache_dbg_state,
                            u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.mmu_dbg_walk_state);
                end
                if (if_sanity_window_active() &&
                    u_soc.cpu.if_done && u_soc.cpu.inst_valid_mux && u_soc.cpu.mmu_inst_ready &&
                    (!dbg_last_map_valid ||
                     (u_soc.cpu.fetch_vaddr != dbg_last_map_vaddr) ||
                     (u_soc.cpu.mmu_inst_paddr != dbg_last_map_paddr))) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tIF_MAP\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.csr_satp,
                            u_soc.cpu.icache_dbg_state, u_soc.cpu.mmu_dbg_i_state);
                end
                if (u_soc.cpu.dec_is_ecall) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tECALL_DECODE\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0b\n",
                            dbg_if_cycle, $time, u_soc.cpu.id_pc_wire, u_soc.cpu.id_inst_wire, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.fetch_vaddr, u_soc.cpu.csr_satp, u_soc.cpu.icache_dbg_state,
                            u_soc.cpu.mmu_dbg_i_state, u_soc.cpu.inst_valid_mux);
                end
                if (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_cause == 32'd9) &&
                    (u_soc.cpu.hw_trap_epc != 32'hc0010bbc)) begin
                    $fwrite(dbg_if_fd, "%0d\t%0t\tTRAP_PRE\t%08h\t%08h\t%08h\t%08h\t%08h\t%08h\t%0d\t%0d\n",
                            dbg_if_cycle, $time, if_pc, if_inst, u_soc.cpu.mmu_inst_paddr,
                            u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval, u_soc.cpu.csr_satp,
                            u_soc.cpu.icache_dbg_state, u_soc.cpu.mmu_dbg_i_state);
                end
                $fflush(dbg_if_fd);
            end

`ifndef SIMU_DDR_MODE
            if (if_sanity_window_active() &&
                u_soc.cpu.if_done && u_soc.cpu.inst_valid_mux &&
                u_soc.cpu.mmu_inst_ready && !u_soc.cpu.mmu_inst_page_fault &&
                is_sram_cacheable_addr(u_soc.cpu.mmu_inst_paddr)) begin
                dbg_expected_inst = u_soc.sim_ram.u_axi_ram.BRAM[u_soc.cpu.mmu_inst_paddr[26:2]];
                if (if_inst !== dbg_expected_inst) begin
                    dump_forensic_buffer("FETCH_TRUTH_MISMATCH");
                    dump_if_sanity_snapshot("FETCH_TRUTH_MISMATCH");
                    $finish;
                end
            end
`endif

            if (if_sanity_window_active() && u_soc.cpu.dec_is_ecall &&
                (u_soc.cpu.id_inst_wire !== 32'h00000073)) begin
                dump_forensic_buffer("DECODE_ECALL_MISMATCH");
                dump_if_sanity_snapshot("DECODE_ECALL_MISMATCH");
                $finish;
            end

            if (if_sanity_window_active() && u_soc.cpu.dec_is_ecall &&
                (u_soc.cpu.id_pc_wire != 32'hc0010bbc)) begin
                dump_forensic_buffer("UNEXPECTED_ECALL_DECODE");
                dump_if_sanity_snapshot("UNEXPECTED_ECALL_DECODE");
                $finish;
            end

            if (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_cause == 32'd9) &&
                (u_soc.cpu.hw_trap_epc != 32'hc0010bbc)) begin
                dump_forensic_buffer("SUSPICIOUS_ECALL_TRAP");
                dump_if_sanity_snapshot("SUSPICIOUS_ECALL_TRAP");
                $finish;
            end

            dbg_if_miss_prev = u_soc.cpu.mmu_inst_miss;
            dbg_ptw_active_prev = u_soc.cpu.mmu_dbg_i_walk_active;
            dbg_refill_prev = u_soc.cpu.icache_refill_req;
            if (if_sanity_window_active() &&
                u_soc.cpu.if_done && u_soc.cpu.inst_valid_mux && u_soc.cpu.mmu_inst_ready) begin
                dbg_last_map_vaddr = u_soc.cpu.fetch_vaddr;
                dbg_last_map_paddr = u_soc.cpu.mmu_inst_paddr;
                dbg_last_map_valid = 1'b1;
            end
        end
    end

    final begin
        if (dbg_if_fd != 0) begin
            $fflush(dbg_if_fd);
            $fclose(dbg_if_fd);
            $display("[DEBUG-IF-SANITY] IF sanity log closed at cycle %0d", dbg_if_cycle);
        end
        if (dbg_forensic_fd != 0) begin
            $fflush(dbg_forensic_fd);
            $fclose(dbg_forensic_fd);
            $display("[DEBUG-FORENSICS] Trap forensic dump file closed");
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
    // Stall watchdog: detect when CPU is stuck (if_done==0 for too long)
    // Prints comprehensive debug state and $finish to diagnose deadlocks
    // ========================================================================
    integer stall_cnt;
    reg [31:0] stall_pc_r;
    initial begin
        stall_cnt = 0;
        stall_pc_r = 32'b0;
        forever begin
            @(posedge clk);
            if (resetn && u_soc.ddr_data_init) begin
                if (!u_soc.cpu.if_done) begin
                    // CPU stalled — IF stage not completing
                    if (if_pc == stall_pc_r) begin
                        stall_cnt = stall_cnt + 1;
                    end else begin
                        stall_cnt = 0;
                        stall_pc_r <= if_pc;
                    end

                    // After 10000 cycles of stall at same PC, dump state
                    if (stall_cnt == 10000) begin
                        $display("");
                        $display("========================================");
                        $display("[STALL-WATCHDOG] %0t: CPU stalled at PC=0x%08h for 10000 cycles!", $time, if_pc);
                        $display("========================================");

                        // CPU core state
                        $display("[STALL] if_pc=0x%08h if_inst=0x%08h if_done=%0b priv=%0d",
                                 if_pc, if_inst, u_soc.cpu.if_done, u_soc.cpu.priv_mode);
                        $display("[STALL] satp=0x%08h mstatus=0x%08h",
                                 u_soc.cpu.csr_satp, u_soc.cpu.csr_mstatus);
                        $display("[STALL] mepc=0x%08h mcause=0x%08h",
                                 u_soc.cpu.csr_mepc, u_soc.cpu.csr_mcause);
                        $display("[STALL] sepc=0x%08h scause=0x%08h stval=0x%08h",
                                 u_soc.cpu.csr_sepc, u_soc.cpu.csr_scause, u_soc.cpu.csr_stval);

                        // MMU state
                        $display("[STALL] MMU: i_state=%0d d_state=%0d walk_state=%0d",
                                 u_soc.cpu.mmu_dbg_i_state,
                                 u_soc.cpu.mmu_dbg_d_state,
                                 u_soc.cpu.mmu_dbg_walk_state);
                        $display("[STALL] MMU: i_tlb_hit=%0b i_tlb_valid=%0b i_sv32=%0b",
                                 u_soc.cpu.mmu_dbg_i_tlb_hit,
                                 u_soc.cpu.mmu_dbg_i_tlb_valid,
                                 u_soc.cpu.mmu_dbg_i_sv32);
                        $display("[STALL] MMU: d_tlb_hit=%0b d_tlb_valid=%0b d_sv32=%0b d_tlb_miss=%0b",
                                 u_soc.cpu.mmu_dbg_d_tlb_hit,
                                 u_soc.cpu.mmu_dbg_d_tlb_valid,
                                 u_soc.cpu.mmu_dbg_d_latched_sv32,
                                 u_soc.cpu.mmu_dbg_d_tlb_miss);
                        $display("[STALL] MMU: i_input_changed=%0b d_input_changed=%0b",
                                 u_soc.cpu.mmu_dbg_i_input_changed,
                                 u_soc.cpu.mmu_dbg_d_input_changed);
                        $display("[STALL] MMU: i_latched_vaddr=0x%08h d_latched_vaddr=0x%08h",
                                 u_soc.cpu.mmu_dbg_i_latched_vaddr,
                                 u_soc.cpu.mmu_dbg_d_latched_vaddr);
                        $display("[STALL] MMU: i_walk_active=%0b pending_i_walk=%0b pending_d_walk=%0b",
                                 u_soc.cpu.mmu_dbg_i_walk_active,
                                 u_soc.cpu.mmu_dbg_pending_i_walk,
                                 u_soc.cpu.mmu_dbg_pending_d_walk);
                        $display("[STALL] MMU: mmu_inst_ready=%0b mmu_data_ready=%0b",
                                 u_soc.cpu.mmu_inst_ready,
                                 u_soc.cpu.mmu_data_ready);

                        // Icache state
                        $display("[STALL] Icache: state=%0d mmio_req=%0b refill_req=%0b",
                                 u_soc.cpu.dbg_icache_state,
                                 u_soc.cpu.icache_mmio_req,
                                 u_soc.cpu.icache_refill_req);

                        // Dcache state
                        $display("[STALL] Dcache: refill_req=%0b wb_req=%0b",
                                 u_soc.cpu.dcache_refill_req,
                                 u_soc.cpu.dcache_wb_req);

                        // Bus bridge state (hierarchical reference)
                        $display("[STALL] BusBridge: state=%0d", u_soc.cpu.u_bus_bridge.state);
                        $display("[STALL] BusBridge: arvalid=%0b arready=%0b",
                                 u_soc.cpu.u_bus_bridge.arvalid,
                                 u_soc.cpu.u_bus_bridge.arready);
                        $display("[STALL] BusBridge: awvalid=%0b awready=%0b wvalid=%0b wready=%0b bvalid=%0b",
                                 u_soc.cpu.u_bus_bridge.awvalid,
                                 u_soc.cpu.u_bus_bridge.awready,
                                 u_soc.cpu.u_bus_bridge.wvalid,
                                 u_soc.cpu.u_bus_bridge.wready,
                                 u_soc.cpu.u_bus_bridge.bvalid);

                        // PTW state (hierarchical reference)
                        $display("[STALL] PTW: state=%0d bus_req_pending=%0d",
                                 u_soc.cpu.u_mmu.u_ptw.state,
                                 u_soc.cpu.u_mmu.u_ptw.bus_req_pending_r);

                        $fflush;
                        $finish;
                    end
                end else begin
                    stall_cnt = 0;
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
