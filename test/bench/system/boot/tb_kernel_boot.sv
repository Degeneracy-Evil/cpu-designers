`timescale 1ns / 1ps

// Generic OpenSBI/Linux boot monitor. Image-specific addresses and cache/PTW
// internals deliberately stay out of this testbench so it remains useful when
// the firmware, kernel, or cache implementation changes.
module tb_kernel_boot;

    `include "support/soc_fixture.svh"

    integer uart_fd;
    integer trap_fd;
    integer progress_fd;
    integer uart_phase;
    integer uart_bit;
    integer stall_limit;
    integer progress_interval;
    reg [7:0] uart_byte;
    reg       uart_receiving;
    reg [63:0] cycle_count;
    reg [63:0] retired_count;
    reg [63:0] trap_count;
    reg [63:0] no_progress_cycles;
    reg [31:0] last_progress_pc;

    initial begin
        pass_count = 0;
        fail_count = 0;
        uart_fd = $fopen("uart_tx.log", "w");
        trap_fd = $fopen("kernel_trap.log", "w");
        progress_fd = $fopen("kernel_progress.log", "w");
        uart_phase = 0;
        uart_bit = 0;
        uart_byte = 8'b0;
        uart_receiving = 1'b0;
        cycle_count = 0;
        retired_count = 0;
        trap_count = 0;
        no_progress_cycles = 0;
        last_progress_pc = 32'b0;
        stall_limit = 10000000;
        progress_interval = 1000000;
        void'($value$plusargs("kernel_stall_cycles=%d", stall_limit));
        void'($value$plusargs("kernel_progress_cycles=%d", progress_interval));

        if (trap_fd != 0)
            $fwrite(trap_fd, "# cycle pc priv target cause epc tval satp\n");
        if (progress_fd != 0)
            $fwrite(progress_fd, "# cycle retired pc priv satp traps\n");

        $display("[KERNEL] waiting for memory initialization");
        wait (u_soc.ddr_data_init === 1'b1);
        wait (u_soc.cpu_resetn === 1'b1);
        $display("[KERNEL] CPU released; stall_limit=%0d progress_interval=%0d",
                 stall_limit, progress_interval);
        $fflush;
    end

    // UART16550 receiver. The peripheral's baud-enable pulse is used as the
    // timing reference, so this works with both the normal and accelerated
    // simulation divisors.
    always @(posedge clk) begin
        if (!resetn) begin
            uart_phase = 0;
            uart_bit = 0;
            uart_receiving = 1'b0;
        end else if (u_soc.u_apb_perips.u_uart.regs.enable) begin
            if (!uart_receiving) begin
                if (uart_tx === 1'b0) begin
                    uart_receiving = 1'b1;
                    uart_phase = 0;
                    uart_bit = 0;
                    uart_byte = 8'b0;
                end
            end else begin
                uart_phase = uart_phase + 1;
                if ((uart_phase == 8) && (uart_tx !== 1'b0)) begin
                    uart_receiving = 1'b0;
                end else if ((uart_bit < 8) &&
                             (uart_phase == 24 + uart_bit * 16)) begin
                    uart_byte[uart_bit] = uart_tx;
                    uart_bit = uart_bit + 1;
                end else if ((uart_bit == 8) && (uart_phase >= 152)) begin
                    if (uart_fd != 0) begin
                        $fwrite(uart_fd, "%c", uart_byte);
                        $fflush(uart_fd);
                    end
                    uart_receiving = 1'b0;
                end
            end
        end
    end

    // Core-domain progress, trap and bounded no-progress monitoring.
    always @(posedge u_soc.cpu_clk) begin
        if (!u_soc.cpu_resetn) begin
            cycle_count = 0;
            retired_count = 0;
            trap_count = 0;
            no_progress_cycles = 0;
            last_progress_pc = 32'b0;
        end else begin
            cycle_count = cycle_count + 1;

            if (u_soc.cpu.wb_done)
                retired_count = retired_count + 1;

            if (u_soc.cpu.wb_done || u_soc.cpu.trap_enter_valid ||
                (if_pc != last_progress_pc)) begin
                no_progress_cycles = 0;
                last_progress_pc = if_pc;
            end else begin
                no_progress_cycles = no_progress_cycles + 1;
            end

            if (u_soc.cpu.trap_enter_valid) begin
                trap_count = trap_count + 1;
                if (trap_fd != 0) begin
                    $fwrite(trap_fd,
                            "%0d %08h %0d %0d %08h %08h %08h %08h\n",
                            cycle_count, if_pc, u_soc.cpu.priv_mode,
                            u_soc.cpu.target_priv, u_soc.cpu.hw_trap_cause,
                            u_soc.cpu.hw_trap_epc, u_soc.cpu.hw_trap_tval,
                            u_soc.cpu.csr_satp);
                    $fflush(trap_fd);
                end
            end

            if ((progress_interval > 0) &&
                ((cycle_count % progress_interval) == 0)) begin
                if (progress_fd != 0) begin
                    $fwrite(progress_fd, "%0d %0d %08h %0d %08h %0d\n",
                            cycle_count, retired_count, if_pc,
                            u_soc.cpu.priv_mode, u_soc.cpu.csr_satp, trap_count);
                    $fflush(progress_fd);
                end
                $display("[KERNEL] cycle=%0d retired=%0d pc=%08h priv=%0d traps=%0d",
                         cycle_count, retired_count, if_pc,
                         u_soc.cpu.priv_mode, trap_count);
                $fflush;
            end

            if ((stall_limit > 0) && (no_progress_cycles >= stall_limit)) begin
                $display("[KERNEL-WATCHDOG] no progress for %0d cycles", stall_limit);
                $display("[KERNEL-WATCHDOG] cycle=%0d retired=%0d pc=%08h inst=%08h priv=%0d",
                         cycle_count, retired_count, if_pc, if_inst,
                         u_soc.cpu.priv_mode);
                $display("[KERNEL-WATCHDOG] satp=%08h mepc=%08h mcause=%08h sepc=%08h scause=%08h stval=%08h",
                         u_soc.cpu.csr_satp, u_soc.cpu.csr_mepc,
                         u_soc.cpu.csr_mcause, u_soc.cpu.csr_sepc,
                         u_soc.cpu.csr_scause, u_soc.cpu.csr_stval);
                $fflush;
                $fatal(1, "kernel boot made no forward progress");
            end
        end
    end

    final begin
        $display("[KERNEL] summary cycles=%0d retired=%0d traps=%0d pc=%08h",
                 cycle_count, retired_count, trap_count, if_pc);
        if (uart_fd != 0) begin
            $fflush(uart_fd);
            $fclose(uart_fd);
        end
        if (trap_fd != 0) begin
            $fflush(trap_fd);
            $fclose(trap_fd);
        end
        if (progress_fd != 0) begin
            $fflush(progress_fd);
            $fclose(progress_fd);
        end
    end

endmodule
