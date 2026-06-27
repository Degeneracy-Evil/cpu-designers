`timescale 1ns / 1ps
module tb_regression_reg_wb_error_multi_dirty;
    localparam integer EXPECTED_TOTAL = 1;
    localparam integer SIM_CYCLES    = 160000;

    `include "tb_soc_includes.svh"

    initial begin
        wait (resetn === 1'b1);
        repeat (20) @(posedge clk);
        // Preload OLD values into memory (before test writes create dirty lines)
        u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_3000 & 32'hFFFFF) >> 2] = 32'hDEAD_BEEF; // OLD_1
        u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_4000 & 32'hFFFFF) >> 2] = 32'h1357_9BDF; // OLD_2 (retained)
        u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_5000 & 32'hFFFFF) >> 2] = 32'hFEED_FACE; // OLD_3
        // Inject BRESP SLVERR on LINE_2 writeback (middle dirty line)
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_addr    = 32'h8000_4000;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_code    = 2'b10;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_pending = 1'b1;
    end

    always @(posedge clk) begin
        if (u_soc.cpu.trap_enter_valid) begin
            $display("[multi_dirty_wb_error] trap_enter pc=0x%08h mcause=0x%08h mtval=0x%08h",
                     u_soc.cpu.pc, u_soc.cpu.csr_mcause, u_soc.cpu.csr_stval);
        end
    end

    reg [31:0] _val;
    initial begin
        pass_count = 0; fail_count = 0; repeat (SIM_CYCLES) @(posedge clk);
        $display(""); $display("--- Regression wb_error_multi_dirty Results ---");
        read_reg(5'd28, _val); $display("  x28 (pass_count)    = %0d", _val);
        read_reg(5'd29, _val); $display("  x29 (total_count)   = %0d", _val);
        read_reg(5'd30, _val); $display("  x30 (first_fail_id) = %0d", _val);
        read_reg(5'd22, _val); $display("  x22 (mcause)        = 0x%08h", _val);
        read_reg(5'd23, _val); $display("  x23 (mtval)         = 0x%08h", _val);
        $display("  LINE_1 mem [0x80003000] = 0x%08h (expect 0x1234ABCD)", u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_3000 & 32'hFFFFF) >> 2]);
        $display("  LINE_2 mem [0x80004000] = 0x%08h (expect 0x13579BDF)", u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_4000 & 32'hFFFFF) >> 2]);
        $display("  LINE_3 mem [0x80005000] = 0x%08h (expect 0xCAFEBABE)", u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_5000 & 32'hFFFFF) >> 2]);
        $display("  dcache state        = %0d", u_soc.cpu.u_dcache_wrap.state);
        $display("");
        read_reg(5'd28, _val);
        if (_val === EXPECTED_TOTAL) begin pass_count = pass_count + 1; $display("  PASS pass_count = %0d", EXPECTED_TOTAL); end
        else begin fail_count = fail_count + 1; $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, _val); end
        read_reg(5'd30, _val);
        if (_val === 32'd0) begin pass_count = pass_count + 1; $display("  PASS first_fail_id = 0"); end
        else begin fail_count = fail_count + 1; $display("  FAIL first_fail_id = %0d", _val); end
        $display(""); $display("========================================");
        $display("Regression wb_error_multi_dirty summary"); $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED"); else $display("TEST FAILED");
        $display("========================================"); $finish;
    end
endmodule
