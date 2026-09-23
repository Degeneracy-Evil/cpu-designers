`timescale 1ns / 1ps

`ifndef TB_MAX_CYCLES
`define TB_MAX_CYCLES 400000
`endif

module tb_program;
    `include "support/soc_fixture.svh"

    initial begin
        finish_framework_test(`TB_MAX_CYCLES);
    end
endmodule
