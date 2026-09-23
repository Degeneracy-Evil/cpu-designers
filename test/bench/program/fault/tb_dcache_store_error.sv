`timescale 1ns / 1ps

module tb_dcache_store_error;
    `include "support/soc_fixture.svh"

    initial begin
        wait (resetn === 1'b1);
        repeat (20) @(posedge clk);

        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_addr = 32'h8000_3000;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_code = 2'b10;
        u_soc.sim_ram.u_axi_ram.sim_inject_bresp_pending = 1'b1;
    end

    initial begin
        finish_framework_test(160000);
    end
endmodule
