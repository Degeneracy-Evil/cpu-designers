`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_wb(
    input              wb_valid,
    input      wb_bus_t mem_wb_bus_r,
    output             rf_wen,
    output     [4:0]   rf_waddr,
    output     [31:0]  rf_wdata,
    output             wb_done,
    output             wb_is_jal_like,
    output     [31:0]  wb_pc_plus4,
    output     [31:0]  wb_pc,
    output     [31:0]  wb_inst
);

    wire [31:0] pc_plus4;
    wire is_jal_like;
    wire is_csr;
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;
    wire [31:0] csr_rdata;
    wire [31:0] pc;
    wire [31:0] inst;

    assign pc_plus4      = mem_wb_bus_r.pc_plus4;
    assign is_jal_like   = mem_wb_bus_r.is_jal_like;
    assign is_csr        = mem_wb_bus_r.is_csr;
    assign wb_we         = mem_wb_bus_r.wb_we;
    assign wb_rd         = mem_wb_bus_r.wb_rd;
    assign wb_data       = mem_wb_bus_r.wb_data;
    assign csr_rdata     = mem_wb_bus_r.csr_rdata;
    assign pc            = mem_wb_bus_r.pc;
    assign inst          = mem_wb_bus_r.inst;

    wire [31:0] actual_wb_data;
    assign actual_wb_data = is_csr ? csr_rdata : wb_data;

    assign rf_wen = wb_valid && wb_we;
    assign rf_waddr = wb_rd;
    assign rf_wdata = actual_wb_data;
    assign wb_done = wb_valid;

    assign wb_is_jal_like = is_jal_like;
    assign wb_pc_plus4 = pc_plus4;
    assign wb_pc = pc;
    assign wb_inst = inst;

endmodule
