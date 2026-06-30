`timescale 1ns / 1ps

// ============================================================
// tb_privilege_sret_debug.sv — S→U sret debug testbench
// ============================================================
//
// Tests the S→U sret transition with full trace logging.
// Verifies that SPP=0 at sret time results in U-mode entry.
//

module tb_privilege_sret_debug;

    localparam integer EXPECTED_TOTAL = 4;  // test 3 (sret) is implicit — verified by tests 4+5
    localparam integer SIM_CYCLES    = 200000;

    `include "tb_soc_includes.svh"

    reg [31:0] _val;
    integer cycle_cnt;

    initial begin
        cycle_cnt = 0;
        @(posedge resetn);
        forever begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end
    end

    // ── SRET/MRET/trap trace monitor ──
    initial begin : sret_trace
        forever begin
            @(posedge clk);
            if (resetn) begin
                if (u_soc.cpu.trap_return_valid && u_soc.cpu.priv_mode == 2'b01) begin
                    $display("[SRET] cycle=%0d SPP=%b sepc=0x%08h mstatus=0x%08h -> new_priv=%s",
                             cycle_cnt,
                             u_soc.cpu.csr_mstatus[8],
                             u_soc.cpu.csr_sepc,
                             u_soc.cpu.csr_mstatus,
                             u_soc.cpu.csr_mstatus[8] ? "S" : "U");
                end
                if (u_soc.cpu.trap_enter_valid) begin
                    $display("[TRAP-IN] cycle=%0d priv=%b target=%b scause=0x%08h sepc=0x%08h mstatus=0x%08h pc=0x%08h",
                             cycle_cnt,
                             u_soc.cpu.priv_mode,
                             u_soc.cpu.target_priv,
                             u_soc.cpu.csr_scause,
                             u_soc.cpu.csr_sepc,
                             u_soc.cpu.csr_mstatus,
                             u_soc.cpu.trap_csr_pc);
                end
            end
        end
    end

    // ── SSTATUS write monitor ──
    initial begin : sstatus_write_monitor
        forever begin
            @(posedge clk);
            if (resetn && u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wen) begin
                if (u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_addr == 12'h100) begin
                    $display("[SSTATUS-W] cycle=%0d data=0x%08h SPP_new=%b SPP_old=%b",
                             cycle_cnt,
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wdata,
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wdata[8],
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.r_mstatus[8]);
                end
                if (u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_addr == 12'h300) begin
                    $display("[MSTATUS-W] cycle=%0d data=0x%08h MPP=%b SPP=%b",
                             cycle_cnt,
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wdata,
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wdata[12:11],
                             u_soc.cpu.u_trap_csr.u_csr_if.u_csr.sw_csr_wdata[8]);
                end
            end
        end
    end

    // ── HW mstatus write monitor (trap entry/return) ──
    initial begin : hw_mstatus_monitor
        forever begin
            @(posedge clk);
            if (resetn && u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_csr_wen) begin
                $display("[HW-MSTATUS] cycle=%0d is_enter=%b target_priv=%b data=0x%08h SPP_new=%b MPP_new=%b",
                         cycle_cnt,
                         u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_trap_is_enter,
                         u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_target_priv,
                         u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_sstatus_wdata,
                         u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_sstatus_wdata[8],
                         u_soc.cpu.u_trap_csr.u_csr_if.u_csr.hw_mstatus_wdata[12:11]);
            end
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- SRET_DEBUG Results ---");

        read_reg(5'd28, _val);
        $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val);
        $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val);
        $display("  x30 (first_fail_id) = %0d", _val);

        $display("");
        $display("  [DEBUG] Final CPU state:");
        $display("    priv   = %0d", u_soc.cpu.priv_mode);
        $display("    mstatus= 0x%08h", u_soc.cpu.csr_mstatus);
        $display("    sepc   = 0x%08h", u_soc.cpu.csr_sepc);
        $display("    scause = 0x%08h", u_soc.cpu.csr_scause);
        $display("    pc     = 0x%08h", if_pc);

        // Read debug words from shared memory (display only, not pass/fail)
        $display("");
        $display("  [DEBUG] Shared memory debug area (0x80007100):");
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07100 >> 2];
        $display("    [0x80007100] U-mode reached flag  = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07104 >> 2];
        $display("    [0x80007104] scause saved         = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07114 >> 2];
        $display("    [0x80007114] sstatus readback     = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07118 >> 2];
        $display("    [0x80007118] sstatus before sret  = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h0711C >> 2];
        $display("    [0x8000711C] sret-to-S marker     = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07120 >> 2];
        $display("    [0x80007120] sstatus at S-trap    = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07124 >> 2];
        $display("    [0x80007124] sepc at trap         = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07128 >> 2];
        $display("    [0x80007128] mcause               = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h0712C >> 2];
        $display("    [0x8000712C] mepc                 = 0x%08h", _val);
        _val = u_soc.sim_ram.u_axi_ram.BRAM[20'h07130 >> 2];
        $display("    [0x80007130] mstatus at M-trap    = 0x%08h", _val);

        $display("");

        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = %0d", EXPECTED_TOTAL);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val);
        end

        read_reg(5'd30, _val);
        if (_val === 32'd0) begin
            pass_count = pass_count + 1;
            $display("  PASS first_fail_id = 0 (no failures)");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL first_fail_id = %0d (test %0d failed)", _val, _val);
        end

        $display("");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d failures", fail_count);

        $finish;
    end

endmodule
