`timescale 1ns / 1ps

module cpu_wb(
    input              wb_valid,
    input      [134:0] mem_wb_bus_r,
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
    wire wb_we;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;
    wire [31:0] pc;
    wire [31:0] inst;

    assign {pc_plus4, is_jal_like, wb_we, wb_rd, wb_data, pc, inst} = mem_wb_bus_r;

    assign rf_wen = wb_valid && wb_we;
    assign rf_waddr = wb_rd;
    assign rf_wdata = wb_data;
    assign wb_done = wb_valid;

    assign wb_is_jal_like = is_jal_like;
    assign wb_pc_plus4 = pc_plus4;
    assign wb_pc = pc;
    assign wb_inst = inst;

endmodule
