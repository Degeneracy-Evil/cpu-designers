`timescale 1ns / 1ps
module tb_regression_reg_mmio_ready;
    localparam integer EXPECTED_TOTAL = 4;
    localparam integer SIM_CYCLES    = 15000000;

    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    reg [31:0] _val;
    initial begin
        pass_count = 0; fail_count = 0; repeat (SIM_CYCLES) @(posedge clk);
        $display(""); $display("--- Regression mmio_ready Results ---");
        read_reg(5'd28, _val); $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val); $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val); $display("  x30 (first_fail_id) = %0d", _val);
        $display("");
        $display("  dbg pc              = 0x%08h", u_soc.cpu.pc);
        $display("  dbg fsm_state       = %0d", u_soc.cpu.fsm_state);
        $display("  dbg if_valid/done   = %0b/%0b", u_soc.cpu.if_valid, u_soc.cpu.if_done);
        $display("  dbg id_valid/done   = %0b/%0b", u_soc.cpu.id_valid, u_soc.cpu.id_done);
        $display("  dbg exe_valid/done  = %0b/%0b", u_soc.cpu.exe_valid, u_soc.cpu.exe_done);
        $display("  dbg mem_valid/done  = %0b/%0b", u_soc.cpu.mem_valid, u_soc.cpu.mem_done);
        $display("  dbg wb_valid/done   = %0b/%0b", u_soc.cpu.wb_valid, u_soc.cpu.wb_done);
        $display("  dbg inst_valid_mux  = %0b", u_soc.cpu.inst_valid_mux);
        $display("  dbg ic_mmio_req/acc = %0b/%0b", u_soc.cpu.icache_mmio_req, u_soc.cpu.icache_mmio_accept);
        $display("  dbg ahb_inst_valid  = %0b", u_soc.cpu.ahb_inst_valid);
        $display("  dbg trap_pend/enter = %0b/%0b", u_soc.cpu.trap_pending, u_soc.cpu.trap_enter_valid);
        $display("");
        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin pass_count = pass_count + 1; $display("  PASS pass_count = %0d", EXPECTED_TOTAL); end
        else begin fail_count = fail_count + 1; $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val); end
        read_reg(5'd30, _val);
        if (_val === 32'd0) begin pass_count = pass_count + 1; $display("  PASS first_fail_id = 0"); end
        else begin fail_count = fail_count + 1; $display("  FAIL first_fail_id = %0d", _val); end
        $display(""); $display("========================================");
        $display("Regression mmio_ready summary"); $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED"); else $display("TEST FAILED");
        $display("========================================"); $finish;
    end

endmodule
