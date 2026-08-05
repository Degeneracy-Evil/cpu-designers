`timescale 1ns / 1ps

module tb_mmu_sv32_basic;

    localparam integer EXPECTED_TOTAL = 6;
    localparam integer SIM_CYCLES    = 200000;


    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    integer cycle_cnt;
    integer trap_count;

    initial begin
        cycle_cnt = 0;
        trap_count = 0;
        @(posedge resetn);
        forever begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;

            // Cycle-by-cycle around first traps (3800-3960) and mepc=0 transition (4600-4800)
            if ((cycle_cnt >= 3820 && cycle_cnt <= 3960) ||
                (cycle_cnt >= 4600 && cycle_cnt <= 4800)) begin
                $display("[t=%0d] pc=0x%08h priv=%0d trap=%0b mret=%0b mstatus=0x%08h mepc=0x%08h",
                    cycle_cnt, exe_pc, u_soc.cpu.priv_mode, u_soc.cpu.trap_enter_valid, u_soc.cpu.dec_is_mret,
                    u_soc.cpu.csr_mstatus, u_soc.cpu.csr_mepc);
            end

            // Detect trap entry (print first 6)
            if (u_soc.cpu.trap_enter_valid && cycle_cnt > 100) begin
                trap_count = trap_count + 1;
                if (trap_count <= 6) begin
                    $display("[t=%0d] >>> TRAP #%0d: exe_pc=0x%08h mepc_csr=0x%08h mstatus=0x%08h priv=%0d",
                        cycle_cnt, trap_count, exe_pc, u_soc.cpu.csr_mepc, u_soc.cpu.csr_mstatus, u_soc.cpu.priv_mode);
                end
            end

            // Detect mret execution
            if (u_soc.cpu.dec_is_mret && cycle_cnt > 100 && cycle_cnt <= 5000) begin
                $display("[t=%0d] >>> MRET: exe_pc=0x%08h mepc_csr=0x%08h mstatus=0x%08h priv=%0d",
                    cycle_cnt, exe_pc, u_soc.cpu.csr_mepc, u_soc.cpu.csr_mstatus, u_soc.cpu.priv_mode);
            end
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- MMU sv32_basic Results ---");

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
        $display("    mepc   = 0x%08h", u_soc.cpu.csr_mepc);
        $display("    mtvec  = 0x%08h", u_soc.cpu.csr_mtvec);

        // Read x5-x6, x10, x14, x22-x24 for debug
        read_reg(5'd10, _val);
        $display("    x10    = 0x%08h (%0d)", _val, _val);
        read_reg(5'd22, _val);
        $display("    x22(mcause)= 0x%08h", _val);
        read_reg(5'd23, _val);
        $display("    x23(mepc)  = 0x%08h", _val);
        read_reg(5'd24, _val);
        $display("    x24(mtval) = 0x%08h", _val);

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
        $display("MMU sv32_basic summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

