`timescale 1ns / 1ps

// ============================================================
// tb_privilege_priv_transition.sv — M↔S↔U privilege transition testbench
// ============================================================

module tb_privilege_priv_transition;

    localparam integer EXPECTED_TOTAL = 11;
    localparam integer SIM_CYCLES    = 200000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
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

    // ── fence.i / dcache flush trace + PTE check ──
    initial begin : fencei_trace
        $display("[CHK-PTE] START at time %0t", $time);
        repeat (10) @(posedge clk);
        $display("[CHK-PTE] cycle=%0d reached", cycle_cnt);
    end

    // ── S-mode trap debug + PTW walk trace ──
    initial begin : smode_trap_monitor
        forever begin
            @(posedge clk);
            if (u_soc.cpu.priv_mode == 2'b01 && (
                u_soc.cpu.u_mmu.t_state == 4'd3 ||
                u_soc.cpu.u_mmu.t_state == 4'd8)) begin
                $display("[MMU-PTW] cycle=%0d t_state=%0d ptw_state=%0d latched_vaddr=0x%08h ptw_walk_done=%b ptw_walk_fault=%b ptw_cache_req=%b ptw_cache_ready=%b ptw_cache_rdata=0x%08h",
                         cycle_cnt, u_soc.cpu.u_mmu.t_state, u_soc.cpu.u_mmu.u_ptw.state,
                         u_soc.cpu.u_mmu.latched_vaddr,
                         u_soc.cpu.u_mmu.ptw_walk_done, u_soc.cpu.u_mmu.ptw_walk_fault,
                         u_soc.cpu.u_mmu.ptw_cache_req, u_soc.cpu.u_mmu.ptw_cache_ready,
                         u_soc.cpu.u_mmu.ptw_cache_rdata);
            end
            if (u_soc.cpu.trap_enter_valid && u_soc.cpu.priv_mode == 2'b01) begin
                $display("[S-TRAP] cycle=%0d scause=0x%0h sepc=0x%08h stval=0x%08h",
                         cycle_cnt, u_soc.cpu.csr_scause, u_soc.cpu.csr_sepc, u_soc.cpu.csr_stval);
            end
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- Privilege PRIV_TRANSITION Results ---");

        read_reg(5'd28, _val);
        $display("  x28 (pass_count)    = %0d", _val);

        read_reg(5'd29, _val);
        $display("  x29 (total_count)   = %0d", _val);

        read_reg(5'd30, _val);
        $display("  x30 (first_fail_id) = %0d", _val);

        $display("");
        $display("  [DEBUG] Final CPU state:");
        $display("    if_pc  = 0x%08h", if_pc);
        $display("    exe_pc = 0x%08h", exe_pc);
        $display("    priv   = %0d", u_soc.cpu.priv_mode);
        $display("    mstatus= 0x%08h", u_soc.cpu.csr_mstatus);

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
        $display("========================================");
        $display("Privilege PRIV_TRANSITION summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule
