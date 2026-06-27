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
            $fwrite(dbg_deleg_fd, "# Cycle\tTime\tEvent\tPC\t\tPriv\tTPriv\tCSR_MCAUSE\tHW_CAUSE\tCSR_SCAUSE\tCSR_STVAL\tCSR_SEPC\tDeleg\tToS\tEPC\t\tEMTVAL\t\tIPF_VA\t\tHW_EPC\t\tHW_TVAL\t\tHW_WEN\tHW_TPRIV\tMEDELEG\n");
        end
        dbg_deleg_count = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_deleg_fd != 0) begin
            // Log on trap_enter_valid — the cycle where CSR writes happen
            if (u_soc.cpu.trap_enter_valid) begin
                dbg_deleg_count = dbg_deleg_count + 1;
                $fwrite(dbg_deleg_fd, "%0d\t%0t\tTRAP_IN\t%08h\t%0d\t%0d\t%08h\t%08h\t%08h\t%08h\t%08h\t%b\t%b\t%08h\t%08h\t%08h\t%08h\t%08h\t%b\t%0d\t%08h\n",
                        dbg_deleg_count, $time, if_pc,
                        u_soc.cpu.priv_mode,           // current privilege
                        u_soc.cpu.target_priv,          // target privilege
                        u_soc.cpu.csr_mcause,           // stale for S-mode traps; kept for comparison
                        u_soc.cpu.hw_trap_cause,        // current trap write-data cause
                        u_soc.cpu.csr_scause,           // S-mode CSR state before this posedge update
                        u_soc.cpu.csr_stval,
                        u_soc.cpu.csr_sepc,
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
                $fwrite(dbg_deleg_fd, "%0d\t%0t\tRET\t%08h\t%0d\t--\t--\t--\t--\t%08h\t%08h\t%08h\t--\t--\t--\t--\t--\t%08h\t%08h\t--\t--\t%08h\n",
                        dbg_deleg_count, $time, if_pc,
                        u_soc.cpu.priv_mode,
                        u_soc.cpu.csr_scause,
                        u_soc.cpu.csr_stval,
                        u_soc.cpu.csr_sepc,
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
    integer dbg_dmmu_fd;
    integer dbg_pte_fd;
    integer dbg_dcache_pte_fd;
    integer dbg_ptw_fd;
    integer dbg_axi_pte_fd;
    integer dbg_vmalloc_fd;
    integer dbg_maint_fd;
    integer dbg_pte_final_fd;
    integer dbg_if_cycle;
    reg     dbg_if_miss_prev;
    reg     dbg_ptw_active_prev;
    reg     dbg_refill_prev;
    reg [31:0] dbg_expected_inst;
    reg [31:0] dbg_last_map_vaddr;
    reg [31:0] dbg_last_map_paddr;
    reg        dbg_last_map_valid;
    reg [31:0] dbg_last_pte_word;
    reg [31:0] dbg_last_pte_line_word0;
    reg [31:0] dbg_last_pte_line_word1;
    reg [31:0] dbg_last_pte_line_word2;
    reg [31:0] dbg_last_pte_line_word3;
    reg        dbg_pte_shadow_valid;
    reg        dbg_vmalloc_window;
    reg [31:0] dbg_vmalloc_start_cycle;
    reg        dbg_prev_sfence_vma_req;
    reg        dbg_prev_dcache_flush_req;
    reg        dbg_prev_dcache_flush_done;
    reg        dbg_prev_icache_invalidate_req;
    reg        dbg_prev_icache_invalidate_done;
    reg        dbg_prev_mmu_sfence_done;
    reg        dbg_prev_ptw_ad_inv_req;
    reg        dbg_prev_ptw_ad_inv_done;

    localparam integer IF_SANITY_ENABLE_CYCLE = 200000000;
    localparam integer FORENSIC_DEPTH = 128;
    localparam [31:0] PTE_WATCH_ADDR      = 32'h809b7084;
    localparam [31:0] PTE_WATCH_LINE_ADDR = 32'h809b7080;
    localparam [31:0] PTE_WATCH_PAGE_BASE = 32'h809b7000;
    localparam [31:0] PTE_WATCH_PAGE_END  = 32'h809b7fff;
    localparam [31:0] VMALLOC_WATCH_BASE  = 32'ha0021000;
    localparam [31:0] VMALLOC_WATCH_END   = 32'ha0021fff;

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
    reg [31:0] forensic_mem_pc       [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_mem_inst     [0:FORENSIC_DEPTH-1];
    reg        forensic_mem_valid    [0:FORENSIC_DEPTH-1];
    reg        forensic_mem_done     [0:FORENSIC_DEPTH-1];
    reg        forensic_mem_en       [0:FORENSIC_DEPTH-1];
    reg        forensic_mem_we       [0:FORENSIC_DEPTH-1];
    reg [2:0]  forensic_mem_size     [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_mem_vaddr    [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_mem_wdata    [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_d_paddr      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_ready      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_miss       [0:FORENSIC_DEPTH-1];
    reg        forensic_d_pf         [0:FORENSIC_DEPTH-1];
    reg [3:0]  forensic_d_pf_cause   [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_d_pf_vaddr   [0:FORENSIC_DEPTH-1];
    reg [2:0]  forensic_d_state      [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_d_lat_vaddr  [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_d_lat_atype  [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_d_lat_priv   [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_d_lat_satp   [0:FORENSIC_DEPTH-1];
    reg        forensic_d_lat_sum    [0:FORENSIC_DEPTH-1];
    reg        forensic_d_lat_mxr    [0:FORENSIC_DEPTH-1];
    reg        forensic_d_inchg      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_hit    [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_valid  [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_perm   [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_miss   [0:FORENSIC_DEPTH-1];
    reg [21:0] forensic_d_tlb_ppn    [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_r      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_w      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_x      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_u      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_a      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_d      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_g      [0:FORENSIC_DEPTH-1];
    reg        forensic_d_tlb_mega   [0:FORENSIC_DEPTH-1];
    reg        forensic_d_pf_ptw     [0:FORENSIC_DEPTH-1];
    reg        forensic_store_pf     [0:FORENSIC_DEPTH-1];
    reg        forensic_load_pf      [0:FORENSIC_DEPTH-1];
    reg        forensic_store_af     [0:FORENSIC_DEPTH-1];
    reg        forensic_load_af      [0:FORENSIC_DEPTH-1];
    reg        forensic_ptw_done     [0:FORENSIC_DEPTH-1];
    reg        forensic_ptw_fault    [0:FORENSIC_DEPTH-1];
    reg [3:0]  forensic_ptw_fcause   [0:FORENSIC_DEPTH-1];
    reg [31:0] forensic_ptw_fvaddr   [0:FORENSIC_DEPTH-1];
    reg [1:0]  forensic_ptw_fkind    [0:FORENSIC_DEPTH-1];
    reg        forensic_tlb_fill     [0:FORENSIC_DEPTH-1];
    reg [19:0] forensic_fill_vpn     [0:FORENSIC_DEPTH-1];
    reg [21:0] forensic_fill_ppn     [0:FORENSIC_DEPTH-1];
    reg [8:0]  forensic_fill_asid    [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_r       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_w       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_x       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_u       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_a       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_d       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_g       [0:FORENSIC_DEPTH-1];
    reg        forensic_fill_mega    [0:FORENSIC_DEPTH-1];
    reg        forensic_tlb_coll_i   [0:FORENSIC_DEPTH-1];
    reg        forensic_tlb_coll_d   [0:FORENSIC_DEPTH-1];

    function is_sram_cacheable_addr;
        input [31:0] addr;
        begin
            is_sram_cacheable_addr = addr[31] && !addr[30] && (addr[29:27] == 3'b000);
        end
    endfunction

    function is_pte_page_addr;
        input [31:0] addr;
        begin
            is_pte_page_addr = (addr >= PTE_WATCH_PAGE_BASE) && (addr <= PTE_WATCH_PAGE_END);
        end
    endfunction

    function is_pte_line_addr;
        input [31:0] addr;
        begin
            is_pte_line_addr = ({addr[31:5], 5'b0} == PTE_WATCH_LINE_ADDR);
        end
    endfunction

    function is_vmalloc_watch_addr;
        input [31:0] addr;
        begin
            is_vmalloc_watch_addr = (addr >= VMALLOC_WATCH_BASE) && (addr <= VMALLOC_WATCH_END);
        end
    endfunction

    function is_vmalloc_trace_pc;
        input [31:0] pc;
        begin
            is_vmalloc_trace_pc =
                ((pc >= 32'hc00e0000) && (pc <= 32'hc00e8000)) ||
                ((pc >= 32'hc00cfc00) && (pc <= 32'hc00d4a00)) ||
                ((pc >= 32'hc00118c0) && (pc <= 32'hc0011960)) ||
                ((pc >= 32'hc01df360) && (pc <= 32'hc01df470));
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

    function dmmu_focus_active;
        begin
            dmmu_focus_active =
                if_sanity_window_active() &&
                (u_soc.cpu.mem_en ||
                 u_soc.cpu.mmu_data_page_fault ||
                 u_soc.cpu.u_trap_csr.u_trap_mgr.store_page_fault_r ||
                 u_soc.cpu.u_trap_csr.u_trap_mgr.load_page_fault_r ||
                 u_soc.cpu.u_mmu.tlb_fill_req ||
                 u_soc.cpu.u_mmu.ptw_walk_fault ||
                 u_soc.cpu.u_mmu.ptw_walk_done) &&
                (((u_soc.cpu.mem_dataAddr_32[31:12] == 20'ha0021) ||
                  (u_soc.cpu.u_mmu.d_latched_vaddr[31:12] == 20'ha0021)) ||
                 ((u_soc.cpu.mem_pc >= 32'hc01df390) && (u_soc.cpu.mem_pc <= 32'hc01df410)) ||
                 ((u_soc.cpu.u_mmu.fill_vpn >= 20'ha0020) && (u_soc.cpu.u_mmu.fill_vpn <= 20'ha0022)));
        end
    endfunction

    function [31:0] sram_read_word;
        input [31:0] addr;
        begin
`ifndef SIMU_DDR_MODE
            if (is_sram_cacheable_addr(addr))
                sram_read_word = u_soc.sim_ram.u_axi_ram.BRAM[addr[26:2]];
            else
                sram_read_word = 32'hXXXXXXXX;
`else
            sram_read_word = 32'hXXXXXXXX;
`endif
        end
    endfunction

    task dump_sv32_truth;
        input [31:0] vaddr;
        reg [31:0] root_addr;
        reg [31:0] l1_addr;
        reg [31:0] l1_pte;
        reg [31:0] l0_addr;
        reg [31:0] l0_pte;
        reg [21:0] l1_ppn;
        reg [21:0] l0_ppn;
        reg [31:0] expected_paddr;
        begin
            root_addr = {u_soc.cpu.csr_satp[19:0], 12'b0};
            l1_addr = root_addr + {20'b0, vaddr[31:22], 2'b0};
            l1_pte = sram_read_word(l1_addr);
            l1_ppn = {l1_pte[31:20], l1_pte[19:10]};
            l0_addr = {l1_ppn[19:0], 12'b0} + {20'b0, vaddr[21:12], 2'b0};
            l0_pte = sram_read_word(l0_addr);
            l0_ppn = {l0_pte[31:20], l0_pte[19:10]};
            expected_paddr = ((l1_pte[1] || l1_pte[3]) && l1_pte[0]) ?
                             {l1_ppn[19:10], vaddr[21:0]} :
                             {l0_ppn[19:0], vaddr[11:0]};

            if (dbg_forensic_fd != 0) begin
                $fwrite(dbg_forensic_fd, "# SV32_TRUTH vaddr=%08h satp=%08h root=%08h\n",
                        vaddr, u_soc.cpu.csr_satp, root_addr);
                $fwrite(dbg_forensic_fd, "# SV32_L1 addr=%08h pte=%08h V=%0b R=%0b W=%0b X=%0b U=%0b G=%0b A=%0b D=%0b ppn=%05h leaf=%0b\n",
                        l1_addr, l1_pte, l1_pte[0], l1_pte[1], l1_pte[2], l1_pte[3],
                        l1_pte[4], l1_pte[5], l1_pte[6], l1_pte[7], l1_ppn,
                        (l1_pte[1] || l1_pte[3]));
                $fwrite(dbg_forensic_fd, "# SV32_L0 addr=%08h pte=%08h V=%0b R=%0b W=%0b X=%0b U=%0b G=%0b A=%0b D=%0b ppn=%05h expected_paddr=%08h\n",
                        l0_addr, l0_pte, l0_pte[0], l0_pte[1], l0_pte[2], l0_pte[3],
                        l0_pte[4], l0_pte[5], l0_pte[6], l0_pte[7], l0_ppn, expected_paddr);
                $fflush(dbg_forensic_fd);
            end
        end
    endtask

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
                dump_sv32_truth(u_soc.cpu.hw_trap_tval);
                $fwrite(dbg_forensic_fd, "# idx cyc time if_pc if_inst ifd iv idv idd id_pc id_inst de decill debrk exd exv excause expc exmt exvr excr expr extr afv pfv msv exev decc dect trap hwc hwe hwt tpend tpc priv tpriv satp fva mpa mrdy mmiss mpf mpfc mpfv mis ws th tv wa pi ics rr rv ra rd sw wo arv arr ara rvv rry rls rdt shadow mempc meminst memv memdone memen memwe msize mvaddr mwdata dpaddr drdy dmiss dpf dpfc dpfv ds dlatv dlatatype dlatpriv dlatsatp dlatsum dlatmxr dinchg dth dtv dtperm dtmiss dtppn dtr dtw dtx dtu dta dtd dtg dtmega dpfptw spf lpf saf laf ptwd ptwf ptwfc ptwfv ptwfk fill fillvpn fillppn fillasid fillr fillw fillx fillu filla filld fillg fillmega coll_i coll_d\n");
                start_idx = (dbg_forensic_wr_ptr - dbg_forensic_count + FORENSIC_DEPTH) % FORENSIC_DEPTH;
                for (line_idx = 0; line_idx < dbg_forensic_count; line_idx = line_idx + 1) begin
                    dump_idx = (start_idx + line_idx) % FORENSIC_DEPTH;
                    $fwrite(dbg_forensic_fd,
                            "%0d %0d %0t %08h %08h %0b %0b %0b %0b %08h %08h %0b %0b %0b %0b %0b %08h %08h %08h %0b %08h %08h %08h %0b %0b %0b %0b %08h %08h %0b %08h %08h %08h %0b %08h %0d %0d %08h %08h %08h %0b %0b %0b %0d %08h %0d %0d %0b %0b %0d %0b %0b %0b %0b %08h %08h %08h %0d %0b %0b %08h %0b %0b %0b %08h %08h %08h %08h %0b %0b %0b %0b %0d %08h %08h %08h %0b %0b %0b %0d %08h %0d %08h %0d %0d %08h %0b %0b %0b %0b %0b %0b %0b %06h %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %01h %08h %0d %0b %05h %06h %03h %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b\n",
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
                            forensic_shadow_inst[dump_idx],
                            forensic_mem_pc[dump_idx], forensic_mem_inst[dump_idx],
                            forensic_mem_valid[dump_idx], forensic_mem_done[dump_idx],
                            forensic_mem_en[dump_idx], forensic_mem_we[dump_idx],
                            forensic_mem_size[dump_idx], forensic_mem_vaddr[dump_idx],
                            forensic_mem_wdata[dump_idx], forensic_d_paddr[dump_idx],
                            forensic_d_ready[dump_idx], forensic_d_miss[dump_idx],
                            forensic_d_pf[dump_idx], forensic_d_pf_cause[dump_idx],
                            forensic_d_pf_vaddr[dump_idx], forensic_d_state[dump_idx],
                            forensic_d_lat_vaddr[dump_idx], forensic_d_lat_atype[dump_idx],
                            forensic_d_lat_priv[dump_idx], forensic_d_lat_satp[dump_idx],
                            forensic_d_lat_sum[dump_idx], forensic_d_lat_mxr[dump_idx],
                            forensic_d_inchg[dump_idx], forensic_d_tlb_hit[dump_idx],
                            forensic_d_tlb_valid[dump_idx], forensic_d_tlb_perm[dump_idx],
                            forensic_d_tlb_miss[dump_idx], forensic_d_tlb_ppn[dump_idx],
                            forensic_d_tlb_r[dump_idx], forensic_d_tlb_w[dump_idx],
                            forensic_d_tlb_x[dump_idx], forensic_d_tlb_u[dump_idx],
                            forensic_d_tlb_a[dump_idx], forensic_d_tlb_d[dump_idx],
                            forensic_d_tlb_g[dump_idx], forensic_d_tlb_mega[dump_idx],
                            forensic_d_pf_ptw[dump_idx], forensic_store_pf[dump_idx],
                            forensic_load_pf[dump_idx], forensic_store_af[dump_idx],
                            forensic_load_af[dump_idx], forensic_ptw_done[dump_idx],
                            forensic_ptw_fault[dump_idx], forensic_ptw_fcause[dump_idx],
                            forensic_ptw_fvaddr[dump_idx], forensic_ptw_fkind[dump_idx],
                            forensic_tlb_fill[dump_idx], forensic_fill_vpn[dump_idx],
                            forensic_fill_ppn[dump_idx], forensic_fill_asid[dump_idx],
                            forensic_fill_r[dump_idx], forensic_fill_w[dump_idx],
                            forensic_fill_x[dump_idx], forensic_fill_u[dump_idx],
                            forensic_fill_a[dump_idx], forensic_fill_d[dump_idx],
                            forensic_fill_g[dump_idx], forensic_fill_mega[dump_idx],
                            forensic_tlb_coll_i[dump_idx], forensic_tlb_coll_d[dump_idx]);
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
        dbg_dmmu_fd = $fopen("dmmu_fault_trace.log", "w");
        dbg_pte_fd = $fopen("pte_lifecycle.log", "w");
        dbg_dcache_pte_fd = $fopen("dcache_pte_deep.log", "w");
        dbg_ptw_fd = $fopen("ptw_deep.log", "w");
        dbg_axi_pte_fd = $fopen("axi_pte_trace.log", "w");
        dbg_vmalloc_fd = $fopen("vmalloc_exec_trace.log", "w");
        dbg_maint_fd = $fopen("maintenance_trace.log", "w");
        dbg_pte_final_fd = $fopen("pte_final_snapshot.log", "w");
        if (dbg_if_fd != 0) begin
            $fwrite(dbg_if_fd, "# IF sanity event log\n");
            $fwrite(dbg_if_fd, "# Cycle\tTime\tEvent\tPC\tINST\tPADDR\tAUX0\tAUX1\tAUX2\tAUX3\tAUX4\n");
        end
        if (dbg_dmmu_fd != 0) begin
            $fwrite(dbg_dmmu_fd, "# DMMU focused trace\n");
            $fwrite(dbg_dmmu_fd, "# cyc time event mem_pc mem_inst mem_en mem_we mem_vaddr mem_wdata d_paddr d_ready d_miss d_pf d_pfc d_pfv d_state d_lat_vaddr d_atype d_priv d_sum d_mxr d_tlb_v d_tlb_h d_tlb_perm d_tlb_miss d_ppn d_r d_w d_x d_u d_a d_d d_g d_mega ptw_done ptw_fault ptw_fc ptw_fv fill fill_vpn fill_ppn fill_r fill_w fill_x fill_u fill_a fill_d coll_i coll_d hwc hwe hwt scause stval sepc\n");
        end
        if (dbg_pte_fd != 0) begin
            $fwrite(dbg_pte_fd, "# PTE lifecycle trace for pte=%08h line=%08h page=%08h-%08h vmalloc=%08h-%08h\n",
                    PTE_WATCH_ADDR, PTE_WATCH_LINE_ADDR, PTE_WATCH_PAGE_BASE, PTE_WATCH_PAGE_END,
                    VMALLOC_WATCH_BASE, VMALLOC_WATCH_END);
            $fwrite(dbg_pte_fd, "# cyc time event pc inst vaddr paddr wdata wstrb size dready dmiss dpf dstate dcstate dchit way set tag dirty sram_pte ptw_addr ptw_we ptw_wdata ptw_rdata ptw_done ptw_fault hwc hwe hwt\n");
        end
        if (dbg_dcache_pte_fd != 0) begin
            $fwrite(dbg_dcache_pte_fd, "# DCache deep trace for PTE page/line\n");
            $fwrite(dbg_dcache_pte_fd, "# cyc time event state cpu_valid hwrite hsize mmu_ready addr vaddr wdata req_tag set word hit way hitmask tag0 tag1 tag2 tag3 victim vdirty lat_addr lat_wdata lat_set lat_way lat_vtag refill_req refill_addr refill_valid refill_done refill_word wb_req wb_addr wb_done wb_word inv_req inv_addr inv_done sram_pte\n");
        end
        if (dbg_ptw_fd != 0) begin
            $fwrite(dbg_ptw_fd, "# PTW deep trace\n");
            $fwrite(dbg_ptw_fd, "# cyc time event walk_state dstate istate walk_vaddr walk_access satp req addr we wdata rdata done error fault fcause fvaddr fkind fill_vpn fill_ppn fill_perm sram_pte dc_state dc_hit dc_tags\n");
        end
        if (dbg_axi_pte_fd != 0) begin
            $fwrite(dbg_axi_pte_fd, "# AXI/SRAM trace for PTE page\n");
            $fwrite(dbg_axi_pte_fd, "# cyc time event cpu_awv cpu_awr cpu_awaddr cpu_awlen cpu_wv cpu_wr cpu_wdata cpu_wstrb cpu_wlast cpu_bv cpu_br cpu_arv cpu_arr cpu_araddr ddr_awv ddr_awr ddr_awaddr ddr_wv ddr_wr ddr_wdata ddr_wstrb sram_waddr sram_wdata sram_wstrb sram_old sram_new\n");
        end
        if (dbg_vmalloc_fd != 0) begin
            $fwrite(dbg_vmalloc_fd, "# vmalloc/set_pte execution focused trace\n");
            $fwrite(dbg_vmalloc_fd, "# cyc time event if_pc if_inst mem_pc mem_inst mem_valid mem_done mem_en mem_we vaddr paddr wdata size dready dmiss dpf wb_pc wb_inst rf_wen rf_waddr rf_wdata ra sp a0 a1 a2 a3 s1 s2 satp\n");
        end
        if (dbg_maint_fd != 0) begin
            $fwrite(dbg_maint_fd, "# maintenance/sfence/flush trace\n");
            $fwrite(dbg_maint_fd, "# cyc time event pc inst sfence_req dflush_req dflush_done iflush_req iflush_done mmu_sfence_done ptw_inv_req ptw_inv_addr ptw_inv_done dc_state flush_set flush_way inv_set inv_tag wb_req wb_addr wb_done wb_word sram_pte\n");
        end
        dbg_if_cycle = 0;
        dbg_if_miss_prev = 1'b0;
        dbg_ptw_active_prev = 1'b0;
        dbg_refill_prev = 1'b0;
        dbg_expected_inst = 32'b0;
        dbg_last_map_vaddr = 32'b0;
        dbg_last_map_paddr = 32'b0;
        dbg_last_map_valid = 1'b0;
        dbg_last_pte_word = 32'b0;
        dbg_last_pte_line_word0 = 32'b0;
        dbg_last_pte_line_word1 = 32'b0;
        dbg_last_pte_line_word2 = 32'b0;
        dbg_last_pte_line_word3 = 32'b0;
        dbg_pte_shadow_valid = 1'b0;
        dbg_vmalloc_window = 1'b0;
        dbg_vmalloc_start_cycle = 32'b0;
        dbg_prev_sfence_vma_req = 1'b0;
        dbg_prev_dcache_flush_req = 1'b0;
        dbg_prev_dcache_flush_done = 1'b0;
        dbg_prev_icache_invalidate_req = 1'b0;
        dbg_prev_icache_invalidate_done = 1'b0;
        dbg_prev_mmu_sfence_done = 1'b0;
        dbg_prev_ptw_ad_inv_req = 1'b0;
        dbg_prev_ptw_ad_inv_done = 1'b0;
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
                forensic_mem_pc[dbg_forensic_wr_ptr]       = u_soc.cpu.mem_pc;
                forensic_mem_inst[dbg_forensic_wr_ptr]     = u_soc.cpu.mem_inst;
                forensic_mem_valid[dbg_forensic_wr_ptr]    = u_soc.cpu.mem_valid;
                forensic_mem_done[dbg_forensic_wr_ptr]     = u_soc.cpu.mem_done;
                forensic_mem_en[dbg_forensic_wr_ptr]       = u_soc.cpu.mem_en;
                forensic_mem_we[dbg_forensic_wr_ptr]       = u_soc.cpu.mem_hwrite;
                forensic_mem_size[dbg_forensic_wr_ptr]     = u_soc.cpu.mem_hsize;
                forensic_mem_vaddr[dbg_forensic_wr_ptr]    = u_soc.cpu.mem_dataAddr_32;
                forensic_mem_wdata[dbg_forensic_wr_ptr]    = u_soc.cpu.mem_writeData_32;
                forensic_d_paddr[dbg_forensic_wr_ptr]      = u_soc.cpu.mmu_data_paddr;
                forensic_d_ready[dbg_forensic_wr_ptr]      = u_soc.cpu.mmu_data_ready;
                forensic_d_miss[dbg_forensic_wr_ptr]       = u_soc.cpu.mmu_data_miss;
                forensic_d_pf[dbg_forensic_wr_ptr]         = u_soc.cpu.mmu_data_page_fault;
                forensic_d_pf_cause[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_data_pf_cause;
                forensic_d_pf_vaddr[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_data_pf_vaddr;
                forensic_d_state[dbg_forensic_wr_ptr]      = u_soc.cpu.mmu_dbg_d_state;
                forensic_d_lat_vaddr[dbg_forensic_wr_ptr]  = u_soc.cpu.u_mmu.d_latched_vaddr;
                forensic_d_lat_atype[dbg_forensic_wr_ptr]  = u_soc.cpu.u_mmu.d_latched_access_type;
                forensic_d_lat_priv[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.d_latched_priv_mode;
                forensic_d_lat_satp[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.d_latched_satp;
                forensic_d_lat_sum[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.d_latched_mstatus_sum;
                forensic_d_lat_mxr[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.d_latched_mstatus_mxr;
                forensic_d_inchg[dbg_forensic_wr_ptr]      = u_soc.cpu.mmu_dbg_d_input_changed;
                forensic_d_tlb_hit[dbg_forensic_wr_ptr]    = u_soc.cpu.mmu_dbg_d_tlb_hit;
                forensic_d_tlb_valid[dbg_forensic_wr_ptr]  = u_soc.cpu.mmu_dbg_d_tlb_valid;
                forensic_d_tlb_perm[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_dbg_d_tlb_perm_fault;
                forensic_d_tlb_miss[dbg_forensic_wr_ptr]   = u_soc.cpu.mmu_dbg_d_tlb_miss;
                forensic_d_tlb_ppn[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.d_tlb_ppn;
                forensic_d_tlb_r[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_r;
                forensic_d_tlb_w[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_w;
                forensic_d_tlb_x[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_x;
                forensic_d_tlb_u[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_u;
                forensic_d_tlb_a[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_a;
                forensic_d_tlb_d[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_d;
                forensic_d_tlb_g[dbg_forensic_wr_ptr]      = u_soc.cpu.u_mmu.d_tlb_g;
                forensic_d_tlb_mega[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.d_tlb_is_megapage;
                forensic_d_pf_ptw[dbg_forensic_wr_ptr]     = u_soc.cpu.mmu_dbg_d_pf_from_ptw;
                forensic_store_pf[dbg_forensic_wr_ptr]     = u_soc.cpu.u_trap_csr.u_trap_mgr.store_page_fault_r;
                forensic_load_pf[dbg_forensic_wr_ptr]      = u_soc.cpu.u_trap_csr.u_trap_mgr.load_page_fault_r;
                forensic_store_af[dbg_forensic_wr_ptr]     = u_soc.cpu.u_trap_csr.u_trap_mgr.store_access_fault_r;
                forensic_load_af[dbg_forensic_wr_ptr]      = u_soc.cpu.u_trap_csr.u_trap_mgr.load_access_fault_r;
                forensic_ptw_done[dbg_forensic_wr_ptr]     = u_soc.cpu.u_mmu.ptw_walk_done;
                forensic_ptw_fault[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.ptw_walk_fault;
                forensic_ptw_fcause[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.ptw_fault_cause_out;
                forensic_ptw_fvaddr[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.ptw_fault_vaddr_out;
                forensic_ptw_fkind[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.ptw_fault_kind_out;
                forensic_tlb_fill[dbg_forensic_wr_ptr]     = u_soc.cpu.u_mmu.tlb_fill_req;
                forensic_fill_vpn[dbg_forensic_wr_ptr]     = u_soc.cpu.u_mmu.fill_vpn;
                forensic_fill_ppn[dbg_forensic_wr_ptr]     = u_soc.cpu.u_mmu.ptw_fill_ppn;
                forensic_fill_asid[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.fill_asid;
                forensic_fill_r[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_r;
                forensic_fill_w[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_w;
                forensic_fill_x[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_x;
                forensic_fill_u[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_u;
                forensic_fill_a[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_a;
                forensic_fill_d[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_d;
                forensic_fill_g[dbg_forensic_wr_ptr]       = u_soc.cpu.u_mmu.ptw_fill_g;
                forensic_fill_mega[dbg_forensic_wr_ptr]    = u_soc.cpu.u_mmu.ptw_fill_is_megapage;
                forensic_tlb_coll_i[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.u_tlb.portb_fill &&
                                                             u_soc.cpu.u_mmu.u_tlb.flag_bram_ena &&
                                                             (u_soc.cpu.u_mmu.u_tlb.flag_bram_addra == u_soc.cpu.u_mmu.u_tlb.flag_bram_addrb);
                forensic_tlb_coll_d[dbg_forensic_wr_ptr]   = u_soc.cpu.u_mmu.u_tlb.portb_fill &&
                                                             u_soc.cpu.u_mmu.u_tlb.d_lookup_req &&
                                                             (u_soc.cpu.u_mmu.u_tlb.d_lookup_set_idx == u_soc.cpu.u_mmu.u_tlb.fill_set_idx);
                dbg_forensic_wr_ptr = (dbg_forensic_wr_ptr + 1) % FORENSIC_DEPTH;
                if (dbg_forensic_count < FORENSIC_DEPTH)
                    dbg_forensic_count = dbg_forensic_count + 1;
            end

            if (dbg_dmmu_fd != 0 && dmmu_focus_active()) begin
                $fwrite(dbg_dmmu_fd,
                        "%0d %0t DMMU %08h %08h %0b %0b %08h %08h %08h %0b %0b %0b %0d %08h %0d %08h %0d %0d %0b %0b %0b %0b %0b %0b %05h %0b %0b %0b %0b %0b %0b %0b %0b %0b %0b %0d %08h %0b %05h %05h %0b %0b %0b %0b %0b %0b %0b %0b %08h %08h %08h %08h %08h %08h\n",
                        dbg_if_cycle, $time,
                        u_soc.cpu.mem_pc, u_soc.cpu.mem_inst, u_soc.cpu.mem_en, u_soc.cpu.mem_hwrite,
                        u_soc.cpu.mem_dataAddr_32, u_soc.cpu.mem_writeData_32, u_soc.cpu.mmu_data_paddr,
                        u_soc.cpu.mmu_data_ready, u_soc.cpu.mmu_data_miss, u_soc.cpu.mmu_data_page_fault,
                        u_soc.cpu.mmu_data_pf_cause, u_soc.cpu.mmu_data_pf_vaddr,
                        u_soc.cpu.mmu_dbg_d_state, u_soc.cpu.u_mmu.d_latched_vaddr,
                        u_soc.cpu.u_mmu.d_latched_access_type, u_soc.cpu.u_mmu.d_latched_priv_mode,
                        u_soc.cpu.u_mmu.d_latched_mstatus_sum, u_soc.cpu.u_mmu.d_latched_mstatus_mxr,
                        u_soc.cpu.mmu_dbg_d_tlb_valid, u_soc.cpu.mmu_dbg_d_tlb_hit,
                        u_soc.cpu.mmu_dbg_d_tlb_perm_fault, u_soc.cpu.mmu_dbg_d_tlb_miss,
                        u_soc.cpu.u_mmu.d_tlb_ppn, u_soc.cpu.u_mmu.d_tlb_r,
                        u_soc.cpu.u_mmu.d_tlb_w, u_soc.cpu.u_mmu.d_tlb_x,
                        u_soc.cpu.u_mmu.d_tlb_u, u_soc.cpu.u_mmu.d_tlb_a,
                        u_soc.cpu.u_mmu.d_tlb_d, u_soc.cpu.u_mmu.d_tlb_g,
                        u_soc.cpu.u_mmu.d_tlb_is_megapage, u_soc.cpu.u_mmu.ptw_walk_done,
                        u_soc.cpu.u_mmu.ptw_walk_fault, u_soc.cpu.u_mmu.ptw_fault_cause_out,
                        u_soc.cpu.u_mmu.ptw_fault_vaddr_out, u_soc.cpu.u_mmu.tlb_fill_req,
                        u_soc.cpu.u_mmu.fill_vpn, u_soc.cpu.u_mmu.ptw_fill_ppn,
                        u_soc.cpu.u_mmu.ptw_fill_r, u_soc.cpu.u_mmu.ptw_fill_w,
                        u_soc.cpu.u_mmu.ptw_fill_x, u_soc.cpu.u_mmu.ptw_fill_u,
                        u_soc.cpu.u_mmu.ptw_fill_a, u_soc.cpu.u_mmu.ptw_fill_d,
                        (u_soc.cpu.u_mmu.u_tlb.portb_fill && u_soc.cpu.u_mmu.u_tlb.flag_bram_ena && (u_soc.cpu.u_mmu.u_tlb.flag_bram_addra == u_soc.cpu.u_mmu.u_tlb.flag_bram_addrb)),
                        (u_soc.cpu.u_mmu.u_tlb.portb_fill && u_soc.cpu.u_mmu.u_tlb.d_lookup_req && (u_soc.cpu.u_mmu.u_tlb.d_lookup_set_idx == u_soc.cpu.u_mmu.u_tlb.fill_set_idx)),
                        u_soc.cpu.hw_trap_cause, u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval,
                        u_soc.cpu.csr_scause, u_soc.cpu.csr_stval, u_soc.cpu.csr_sepc);
                $fflush(dbg_dmmu_fd);
            end

`ifndef SIMU_DDR_MODE
            if (if_sanity_window_active()) begin
                if (!dbg_pte_shadow_valid) begin
                    dbg_last_pte_word = sram_read_word(PTE_WATCH_ADDR);
                    dbg_last_pte_line_word0 = sram_read_word(PTE_WATCH_LINE_ADDR + 32'h00);
                    dbg_last_pte_line_word1 = sram_read_word(PTE_WATCH_LINE_ADDR + 32'h04);
                    dbg_last_pte_line_word2 = sram_read_word(PTE_WATCH_LINE_ADDR + 32'h08);
                    dbg_last_pte_line_word3 = sram_read_word(PTE_WATCH_LINE_ADDR + 32'h0c);
                    dbg_pte_shadow_valid = 1'b1;
                end

                if (u_soc.cpu.mem_pc == 32'hc00e7394 || u_soc.cpu.mem_pc == 32'hc00e7248) begin
                    dbg_vmalloc_window = 1'b1;
                    if (dbg_vmalloc_start_cycle == 32'b0)
                        dbg_vmalloc_start_cycle = dbg_if_cycle;
                end
                if (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_epc != 32'hc0010bbc))
                    dbg_vmalloc_window = 1'b0;

                if (dbg_pte_fd != 0 &&
                    ((u_soc.cpu.mem_en && (is_pte_page_addr(u_soc.cpu.mmu_data_paddr) ||
                                           is_vmalloc_watch_addr(u_soc.cpu.mem_dataAddr_32))) ||
                     (u_soc.cpu.u_mmu.ptw_bus_req && (is_pte_page_addr(u_soc.cpu.u_mmu.ptw_bus_addr) ||
                                                      is_pte_line_addr(u_soc.cpu.u_mmu.ptw_bus_addr))) ||
                     (u_soc.cpu.u_mmu.ptw_bus_done && (is_pte_page_addr(u_soc.cpu.u_mmu.ptw_bus_addr) ||
                                                       is_pte_line_addr(u_soc.cpu.u_mmu.ptw_bus_addr))) ||
                     u_soc.cpu.u_mmu.ptw_walk_fault ||
                     (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_epc != 32'hc0010bbc)))) begin
                    $fwrite(dbg_pte_fd,
                            "%0d %0t PTE %08h %08h %08h %08h %08h %04b %0d %0b %0b %0b %0d %0d %0b %0d %0d %05h %0b %08h %08h %0b %08h %08h %0b %0b %08h %08h %08h\n",
                            dbg_if_cycle, $time,
                            u_soc.cpu.mem_pc, u_soc.cpu.mem_inst,
                            u_soc.cpu.mem_dataAddr_32, u_soc.cpu.mmu_data_paddr,
                            u_soc.cpu.mem_writeData_32,
                            (u_soc.cpu.mem_hsize == 3'd0) ? (4'b0001 << u_soc.cpu.mmu_data_paddr[1:0]) :
                            (u_soc.cpu.mem_hsize == 3'd1) ? (u_soc.cpu.mmu_data_paddr[1] ? 4'b1100 : 4'b0011) :
                                                            4'b1111,
                            u_soc.cpu.mem_hsize,
                            u_soc.cpu.mmu_data_ready, u_soc.cpu.mmu_data_miss,
                            u_soc.cpu.mmu_data_page_fault, u_soc.cpu.mmu_dbg_d_state,
                            u_soc.cpu.u_dcache_wrap.state, u_soc.cpu.u_dcache_wrap.cache_hit,
                            u_soc.cpu.u_dcache_wrap.hit_way, u_soc.cpu.u_dcache_wrap.set_idx,
                            u_soc.cpu.u_dcache_wrap.req_tag,
                            u_soc.cpu.u_dcache_wrap.tag_r_hit[19],
                            sram_read_word(PTE_WATCH_ADDR),
                            u_soc.cpu.u_mmu.ptw_bus_addr, u_soc.cpu.u_mmu.ptw_bus_we,
                            u_soc.cpu.u_mmu.ptw_bus_wdata, u_soc.cpu.u_mmu.ptw_bus_rdata,
                            u_soc.cpu.u_mmu.ptw_bus_done, u_soc.cpu.u_mmu.ptw_walk_fault,
                            u_soc.cpu.hw_trap_cause, u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval);
                    $fflush(dbg_pte_fd);
                end

                if (dbg_dcache_pte_fd != 0 &&
                    (is_pte_page_addr(u_soc.cpu.u_dcache_wrap.cpu_req_addr) ||
                     is_pte_page_addr(u_soc.cpu.u_dcache_wrap.latched_addr) ||
                     is_pte_page_addr(u_soc.cpu.u_dcache_wrap.refill_addr) ||
                     is_pte_page_addr(u_soc.cpu.u_dcache_wrap.wb_addr) ||
                     is_pte_line_addr(u_soc.cpu.u_dcache_wrap.cpu_req_addr) ||
                     is_pte_line_addr(u_soc.cpu.u_dcache_wrap.latched_addr) ||
                     is_pte_line_addr(u_soc.cpu.u_dcache_wrap.refill_addr) ||
                     is_pte_line_addr(u_soc.cpu.u_dcache_wrap.wb_addr) ||
                     (u_soc.cpu.u_dcache_wrap.inv_line_req && is_pte_page_addr(u_soc.cpu.u_dcache_wrap.inv_line_addr)) ||
                     (u_soc.cpu.mem_en && is_vmalloc_watch_addr(u_soc.cpu.mem_dataAddr_32)))) begin
                    $fwrite(dbg_dcache_pte_fd,
                            "%0d %0t DCACHE %0d %0b %0b %0d %0b %08h %08h %08h %05h %0d %0d %0b %0d %04b %06h %06h %06h %06h %0d %0b %08h %08h %0d %0d %05h %0b %08h %0b %0b %08h %0b %08h %0b %08h %0b %08h %0b %08h\n",
                            dbg_if_cycle, $time,
                            u_soc.cpu.u_dcache_wrap.state,
                            u_soc.cpu.u_dcache_wrap.cpu_req_valid,
                            u_soc.cpu.u_dcache_wrap.cpu_req_hwrite,
                            u_soc.cpu.u_dcache_wrap.cpu_req_hsize,
                            u_soc.cpu.u_dcache_wrap.mmu_ready,
                            u_soc.cpu.u_dcache_wrap.cpu_req_addr,
                            u_soc.cpu.u_dcache_wrap.cpu_req_vaddr,
                            u_soc.cpu.u_dcache_wrap.cpu_req_wdata,
                            u_soc.cpu.u_dcache_wrap.req_tag,
                            u_soc.cpu.u_dcache_wrap.set_idx,
                            u_soc.cpu.u_dcache_wrap.word_off,
                            u_soc.cpu.u_dcache_wrap.cache_hit,
                            u_soc.cpu.u_dcache_wrap.hit_way,
                            {u_soc.cpu.u_dcache_wrap.hit3, u_soc.cpu.u_dcache_wrap.hit2,
                             u_soc.cpu.u_dcache_wrap.hit1, u_soc.cpu.u_dcache_wrap.hit0},
                            u_soc.cpu.u_dcache_wrap.tag_r0,
                            u_soc.cpu.u_dcache_wrap.tag_r1,
                            u_soc.cpu.u_dcache_wrap.tag_r2,
                            u_soc.cpu.u_dcache_wrap.tag_r3,
                            u_soc.cpu.u_dcache_wrap.victim_way,
                            u_soc.cpu.u_dcache_wrap.victim_dirty,
                            u_soc.cpu.u_dcache_wrap.latched_addr,
                            u_soc.cpu.u_dcache_wrap.latched_wdata,
                            u_soc.cpu.u_dcache_wrap.latched_set,
                            u_soc.cpu.u_dcache_wrap.latched_victim_way,
                            u_soc.cpu.u_dcache_wrap.latched_victim_tag,
                            u_soc.cpu.u_dcache_wrap.refill_req,
                            u_soc.cpu.u_dcache_wrap.refill_addr,
                            u_soc.cpu.u_dcache_wrap.refill_valid,
                            u_soc.cpu.u_dcache_wrap.refill_done,
                            u_soc.cpu.u_dcache_wrap.refill_data[32*1 +: 32],
                            u_soc.cpu.u_dcache_wrap.wb_req,
                            u_soc.cpu.u_dcache_wrap.wb_addr,
                            u_soc.cpu.u_dcache_wrap.wb_done,
                            u_soc.cpu.u_dcache_wrap.wb_data[32*1 +: 32],
                            u_soc.cpu.u_dcache_wrap.inv_line_req,
                            u_soc.cpu.u_dcache_wrap.inv_line_addr,
                            u_soc.cpu.u_dcache_wrap.inv_line_done,
                            sram_read_word(PTE_WATCH_ADDR));
                    $fflush(dbg_dcache_pte_fd);
                end

                if (dbg_ptw_fd != 0 &&
                    (u_soc.cpu.u_mmu.ptw_bus_req || u_soc.cpu.u_mmu.ptw_bus_done ||
                     u_soc.cpu.u_mmu.ptw_walk_done || u_soc.cpu.u_mmu.ptw_walk_fault ||
                     ((u_soc.cpu.u_mmu.walk_vaddr[31:12] == 20'ha0021) && (u_soc.cpu.u_mmu.walk_state != 2'd0)) ||
                     is_pte_page_addr(u_soc.cpu.u_mmu.ptw_bus_addr))) begin
                    $fwrite(dbg_ptw_fd,
                            "%0d %0t PTW %0d %0d %0d %08h %0d %08h %0b %08h %0b %08h %08h %0b %0b %0b %0d %08h %0d %05h %05h %0b%0b%0b%0b%0b%0b %08h %0d %0b %06h_%06h_%06h_%06h\n",
                            dbg_if_cycle, $time,
                            u_soc.cpu.u_mmu.walk_state,
                            u_soc.cpu.mmu_dbg_d_state,
                            u_soc.cpu.mmu_dbg_i_state,
                            u_soc.cpu.u_mmu.walk_vaddr,
                            u_soc.cpu.u_mmu.walk_access,
                            u_soc.cpu.u_mmu.walk_satp,
                            u_soc.cpu.u_mmu.ptw_bus_req,
                            u_soc.cpu.u_mmu.ptw_bus_addr,
                            u_soc.cpu.u_mmu.ptw_bus_we,
                            u_soc.cpu.u_mmu.ptw_bus_wdata,
                            u_soc.cpu.u_mmu.ptw_bus_rdata,
                            u_soc.cpu.u_mmu.ptw_bus_done,
                            u_soc.cpu.u_mmu.ptw_bus_error,
                            u_soc.cpu.u_mmu.ptw_walk_fault,
                            u_soc.cpu.u_mmu.ptw_fault_cause_out,
                            u_soc.cpu.u_mmu.ptw_fault_vaddr_out,
                            u_soc.cpu.u_mmu.ptw_fault_kind_out,
                            u_soc.cpu.u_mmu.fill_vpn,
                            u_soc.cpu.u_mmu.ptw_fill_ppn,
                            u_soc.cpu.u_mmu.ptw_fill_r, u_soc.cpu.u_mmu.ptw_fill_w,
                            u_soc.cpu.u_mmu.ptw_fill_x, u_soc.cpu.u_mmu.ptw_fill_u,
                            u_soc.cpu.u_mmu.ptw_fill_a, u_soc.cpu.u_mmu.ptw_fill_d,
                            sram_read_word(PTE_WATCH_ADDR),
                            u_soc.cpu.u_dcache_wrap.state,
                            u_soc.cpu.u_dcache_wrap.cache_hit,
                            u_soc.cpu.u_dcache_wrap.tag_r0,
                            u_soc.cpu.u_dcache_wrap.tag_r1,
                            u_soc.cpu.u_dcache_wrap.tag_r2,
                            u_soc.cpu.u_dcache_wrap.tag_r3);
                    $fflush(dbg_ptw_fd);
                end

                if (dbg_axi_pte_fd != 0 &&
                    (is_pte_page_addr(u_soc.cpu_awaddr) ||
                     is_pte_page_addr(u_soc.cpu_araddr) ||
                     is_pte_page_addr(u_soc.ddr_awaddr) ||
                     is_pte_page_addr(u_soc.ddr_araddr) ||
                     is_pte_page_addr(u_soc.sim_ram.u_axi_ram.w_addr) ||
                     is_pte_line_addr(u_soc.sim_ram.u_axi_ram.w_addr))) begin
                    $fwrite(dbg_axi_pte_fd,
                            "%0d %0t AXI %0b %0b %08h %0d %0b %0b %08h %04b %0b %0b %0b %0b %0b %08h %0b %0b %08h %0b %0b %08h %04b %08h %08h %04b %08h %08h\n",
                            dbg_if_cycle, $time,
                            u_soc.cpu_awvalid, u_soc.cpu_awready, u_soc.cpu_awaddr, u_soc.cpu_awlen,
                            u_soc.cpu_wvalid, u_soc.cpu_wready, u_soc.cpu_wdata, u_soc.cpu_wstrb, u_soc.cpu_wlast,
                            u_soc.cpu_bvalid, u_soc.cpu_bready,
                            u_soc.cpu_arvalid, u_soc.cpu_arready, u_soc.cpu_araddr,
                            u_soc.ddr_awvalid, u_soc.ddr_awready, u_soc.ddr_awaddr,
                            u_soc.ddr_wvalid, u_soc.ddr_wready, u_soc.ddr_wdata, u_soc.ddr_wstrb,
                            u_soc.sim_ram.u_axi_ram.w_addr,
                            u_soc.sim_ram.u_axi_ram.axi_wdata,
                            u_soc.sim_ram.u_axi_ram.axi_wstrb,
                            sram_read_word(u_soc.sim_ram.u_axi_ram.w_addr),
                            sram_read_word(PTE_WATCH_ADDR));
                    $fflush(dbg_axi_pte_fd);
                end

                if (dbg_vmalloc_fd != 0 &&
                    (dbg_vmalloc_window || is_vmalloc_trace_pc(if_pc) || is_vmalloc_trace_pc(u_soc.cpu.mem_pc) ||
                     (u_soc.cpu.mem_en && (is_pte_page_addr(u_soc.cpu.mmu_data_paddr) ||
                                           is_vmalloc_watch_addr(u_soc.cpu.mem_dataAddr_32))))) begin
                    $fwrite(dbg_vmalloc_fd,
                            "%0d %0t EXEC %08h %08h %08h %08h %0b %0b %0b %0b %08h %08h %08h %0d %0b %0b %0b %08h %08h %0b %0d %08h %08h %08h %08h %08h %08h %08h %08h %08h %08h\n",
                            dbg_if_cycle, $time,
                            if_pc, if_inst,
                            u_soc.cpu.mem_pc, u_soc.cpu.mem_inst,
                            u_soc.cpu.mem_valid, u_soc.cpu.mem_done,
                            u_soc.cpu.mem_en, u_soc.cpu.mem_hwrite,
                            u_soc.cpu.mem_dataAddr_32, u_soc.cpu.mmu_data_paddr,
                            u_soc.cpu.mem_writeData_32, u_soc.cpu.mem_hsize,
                            u_soc.cpu.mmu_data_ready, u_soc.cpu.mmu_data_miss,
                            u_soc.cpu.mmu_data_page_fault,
                            u_soc.cpu.wb_pc, u_soc.cpu.wb_inst,
                            u_soc.cpu.rf_wen, u_soc.cpu.rf_waddr, u_soc.cpu.rf_wdata,
                            u_soc.cpu.gpr_ra, u_soc.cpu.gpr_sp, u_soc.cpu.gpr_a0,
                            u_soc.cpu.gpr_a1, u_soc.cpu.gpr_a2, u_soc.cpu.gpr_a3,
                            u_soc.cpu.gpr_s1, u_soc.cpu.gpr_s2, u_soc.cpu.csr_satp);
                    $fflush(dbg_vmalloc_fd);
                end

                if (dbg_maint_fd != 0 &&
                    (u_soc.cpu.sfence_vma_req != dbg_prev_sfence_vma_req ||
                     u_soc.cpu.dcache_flush_req != dbg_prev_dcache_flush_req ||
                     u_soc.cpu.dcache_flush_done != dbg_prev_dcache_flush_done ||
                     u_soc.cpu.icache_invalidate_req != dbg_prev_icache_invalidate_req ||
                     u_soc.cpu.icache_invalidate_done != dbg_prev_icache_invalidate_done ||
                     u_soc.cpu.mmu_sfence_done != dbg_prev_mmu_sfence_done ||
                     u_soc.cpu.ptw_ad_inv_req != dbg_prev_ptw_ad_inv_req ||
                     u_soc.cpu.ptw_ad_inv_done != dbg_prev_ptw_ad_inv_done ||
                     (u_soc.cpu.u_dcache_wrap.wb_req && is_pte_page_addr(u_soc.cpu.u_dcache_wrap.wb_addr)) ||
                     (u_soc.cpu.u_dcache_wrap.state >= 4'd6 && u_soc.cpu.u_dcache_wrap.state <= 4'd13))) begin
                    $fwrite(dbg_maint_fd,
                            "%0d %0t MAINT %08h %08h %0b %0b %0b %0b %0b %0b %0b %08h %0b %0d %0d %0d %0d %05h %0b %08h %0b %08h %08h\n",
                            dbg_if_cycle, $time, if_pc, if_inst,
                            u_soc.cpu.sfence_vma_req,
                            u_soc.cpu.dcache_flush_req, u_soc.cpu.dcache_flush_done,
                            u_soc.cpu.icache_invalidate_req, u_soc.cpu.icache_invalidate_done,
                            u_soc.cpu.mmu_sfence_done,
                            u_soc.cpu.ptw_ad_inv_req, u_soc.cpu.ptw_ad_inv_addr,
                            u_soc.cpu.ptw_ad_inv_done,
                            u_soc.cpu.u_dcache_wrap.state,
                            u_soc.cpu.u_dcache_wrap.flush_set,
                            u_soc.cpu.u_dcache_wrap.flush_way,
                            u_soc.cpu.u_dcache_wrap.invalidate_set,
                            u_soc.cpu.u_dcache_wrap.inv_latched_tag,
                            u_soc.cpu.u_dcache_wrap.wb_req,
                            u_soc.cpu.u_dcache_wrap.wb_addr,
                            u_soc.cpu.u_dcache_wrap.wb_done,
                            u_soc.cpu.u_dcache_wrap.wb_data[32*1 +: 32],
                            sram_read_word(PTE_WATCH_ADDR));
                    $fflush(dbg_maint_fd);
                end

                if (sram_read_word(PTE_WATCH_ADDR) !== dbg_last_pte_word) begin
                    if (dbg_pte_fd != 0) begin
                        $fwrite(dbg_pte_fd, "%0d %0t SRAM_PTE_CHANGE old=%08h new=%08h line0=%08h line1=%08h line2=%08h line3=%08h\n",
                                dbg_if_cycle, $time, dbg_last_pte_word, sram_read_word(PTE_WATCH_ADDR),
                                sram_read_word(PTE_WATCH_LINE_ADDR + 32'h00),
                                sram_read_word(PTE_WATCH_LINE_ADDR + 32'h04),
                                sram_read_word(PTE_WATCH_LINE_ADDR + 32'h08),
                                sram_read_word(PTE_WATCH_LINE_ADDR + 32'h0c));
                        $fflush(dbg_pte_fd);
                    end
                    dbg_last_pte_word = sram_read_word(PTE_WATCH_ADDR);
                end

                dbg_prev_sfence_vma_req = u_soc.cpu.sfence_vma_req;
                dbg_prev_dcache_flush_req = u_soc.cpu.dcache_flush_req;
                dbg_prev_dcache_flush_done = u_soc.cpu.dcache_flush_done;
                dbg_prev_icache_invalidate_req = u_soc.cpu.icache_invalidate_req;
                dbg_prev_icache_invalidate_done = u_soc.cpu.icache_invalidate_done;
                dbg_prev_mmu_sfence_done = u_soc.cpu.mmu_sfence_done;
                dbg_prev_ptw_ad_inv_req = u_soc.cpu.ptw_ad_inv_req;
                dbg_prev_ptw_ad_inv_done = u_soc.cpu.ptw_ad_inv_done;
            end
`endif

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
                if (u_soc.cpu.trap_enter_valid &&
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

            if (if_sanity_window_active() && u_soc.cpu.trap_enter_valid &&
                (u_soc.cpu.hw_trap_epc != 32'hc0010bbc)) begin
                dump_forensic_buffer("FIRST_NON_SBI_TRAP");
                dump_if_sanity_snapshot("FIRST_NON_SBI_TRAP");
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
`ifndef SIMU_DDR_MODE
        if (dbg_pte_final_fd != 0) begin
            $fwrite(dbg_pte_final_fd, "# Final PTE snapshot at cycle=%0d time=%0t\n", dbg_if_cycle, $time);
            $fwrite(dbg_pte_final_fd, "CSR satp=%08h priv=%0d hwc=%08h hwe=%08h hwt=%08h\n",
                    u_soc.cpu.csr_satp, u_soc.cpu.priv_mode,
                    u_soc.cpu.hw_trap_cause, u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval);
            $fwrite(dbg_pte_final_fd, "SRAM pte_addr=%08h pte=%08h line=%08h %08h %08h %08h %08h %08h %08h %08h\n",
                    PTE_WATCH_ADDR, sram_read_word(PTE_WATCH_ADDR),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h00),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h04),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h08),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h0c),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h10),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h14),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h18),
                    sram_read_word(PTE_WATCH_LINE_ADDR + 32'h1c));
            $fwrite(dbg_pte_final_fd, "DCACHE state=%0d req_addr=%08h latched_addr=%08h refill_addr=%08h wb_addr=%08h set=%0d req_tag=%05h hit=%0b way=%0d victim=%0d victim_dirty=%0b\n",
                    u_soc.cpu.u_dcache_wrap.state,
                    u_soc.cpu.u_dcache_wrap.cpu_req_addr,
                    u_soc.cpu.u_dcache_wrap.latched_addr,
                    u_soc.cpu.u_dcache_wrap.refill_addr,
                    u_soc.cpu.u_dcache_wrap.wb_addr,
                    u_soc.cpu.u_dcache_wrap.set_idx,
                    u_soc.cpu.u_dcache_wrap.req_tag,
                    u_soc.cpu.u_dcache_wrap.cache_hit,
                    u_soc.cpu.u_dcache_wrap.hit_way,
                    u_soc.cpu.u_dcache_wrap.victim_way,
                    u_soc.cpu.u_dcache_wrap.victim_dirty);
            $fwrite(dbg_pte_final_fd, "DCACHE tags tag0=%06h tag1=%06h tag2=%06h tag3=%06h inv_req=%0b inv_addr=%08h inv_done=%0b\n",
                    u_soc.cpu.u_dcache_wrap.tag_r0,
                    u_soc.cpu.u_dcache_wrap.tag_r1,
                    u_soc.cpu.u_dcache_wrap.tag_r2,
                    u_soc.cpu.u_dcache_wrap.tag_r3,
                    u_soc.cpu.u_dcache_wrap.inv_line_req,
                    u_soc.cpu.u_dcache_wrap.inv_line_addr,
                    u_soc.cpu.u_dcache_wrap.inv_line_done);
            $fwrite(dbg_pte_final_fd, "MMU walk_state=%0d dstate=%0d istate=%0d walk_vaddr=%08h walk_satp=%08h ptw_addr=%08h ptw_we=%0b ptw_rdata=%08h ptw_done=%0b ptw_fault=%0b\n",
                    u_soc.cpu.u_mmu.walk_state,
                    u_soc.cpu.mmu_dbg_d_state,
                    u_soc.cpu.mmu_dbg_i_state,
                    u_soc.cpu.u_mmu.walk_vaddr,
                    u_soc.cpu.u_mmu.walk_satp,
                    u_soc.cpu.u_mmu.ptw_bus_addr,
                    u_soc.cpu.u_mmu.ptw_bus_we,
                    u_soc.cpu.u_mmu.ptw_bus_rdata,
                    u_soc.cpu.u_mmu.ptw_bus_done,
                    u_soc.cpu.u_mmu.ptw_walk_fault);
            $fflush(dbg_pte_final_fd);
        end
`endif
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
        if (dbg_dmmu_fd != 0) begin
            $fflush(dbg_dmmu_fd);
            $fclose(dbg_dmmu_fd);
            $display("[DEBUG-DMMU] DMMU focused trace closed");
        end
        if (dbg_pte_fd != 0) begin
            $fflush(dbg_pte_fd);
            $fclose(dbg_pte_fd);
            $display("[DEBUG-PTE] PTE lifecycle trace closed");
        end
        if (dbg_dcache_pte_fd != 0) begin
            $fflush(dbg_dcache_pte_fd);
            $fclose(dbg_dcache_pte_fd);
            $display("[DEBUG-DCACHE-PTE] DCache PTE trace closed");
        end
        if (dbg_ptw_fd != 0) begin
            $fflush(dbg_ptw_fd);
            $fclose(dbg_ptw_fd);
            $display("[DEBUG-PTW] PTW deep trace closed");
        end
        if (dbg_axi_pte_fd != 0) begin
            $fflush(dbg_axi_pte_fd);
            $fclose(dbg_axi_pte_fd);
            $display("[DEBUG-AXI-PTE] AXI PTE trace closed");
        end
        if (dbg_vmalloc_fd != 0) begin
            $fflush(dbg_vmalloc_fd);
            $fclose(dbg_vmalloc_fd);
            $display("[DEBUG-VMALLOC] vmalloc execution trace closed");
        end
        if (dbg_maint_fd != 0) begin
            $fflush(dbg_maint_fd);
            $fclose(dbg_maint_fd);
            $display("[DEBUG-MAINT] maintenance trace closed");
        end
        if (dbg_pte_final_fd != 0) begin
            $fflush(dbg_pte_final_fd);
            $fclose(dbg_pte_final_fd);
            $display("[DEBUG-PTE-FINAL] final PTE snapshot closed");
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
