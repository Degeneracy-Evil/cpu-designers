`timescale 1ns / 1ps

module tb_dcache_refill_error;
    `include "support/soc_fixture.svh"

    initial begin
        wait (resetn === 1'b1);
        repeat (20) @(posedge clk);

        u_soc.sim_ram.u_axi_ram.BRAM[(32'h8000_4000 & 32'h000f_ffff) >> 2]
            = 32'ha5a5_5a5a;
        u_soc.sim_ram.u_axi_ram.sim_inject_rresp_addr = 32'h8000_4000;
        u_soc.sim_ram.u_axi_ram.sim_inject_rresp_code = 2'b10;
        u_soc.sim_ram.u_axi_ram.sim_inject_rresp_pending = 1'b1;
    end

    initial begin
        finish_framework_test(120000);
    end
endmodule
