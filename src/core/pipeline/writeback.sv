`timescale 1ns / 1ps
`include "core/interface/types.svh"

module cpu_wb(
    input              wb_valid,
    input      wb_bus_t mem_wb_bus_r,
    output             rf_wen,
    output     [4:0]   rf_waddr,
    output     [31:0]  rf_wdata,
    output             wb_done,
    output     [31:0]  wb_pc,
    output     [31:0]  wb_inst
);

    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;
    wire [31:0] pc;
    wire [31:0] inst;

    assign wb_we         = mem_wb_bus_r.wb_we;
    assign wb_rd         = mem_wb_bus_r.wb_rd;
    assign wb_data       = mem_wb_bus_r.wb_data;
    assign pc            = mem_wb_bus_r.pc;
    assign inst          = mem_wb_bus_r.inst;

    assign rf_wen = wb_valid && wb_we;
    assign rf_waddr = wb_rd;
    assign rf_wdata = wb_data;
    assign wb_done = wb_valid;

    assign wb_pc = pc;
    assign wb_inst = inst;

endmodule
