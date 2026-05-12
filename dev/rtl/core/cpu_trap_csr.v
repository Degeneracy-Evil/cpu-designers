`timescale 1ns / 1ps

module cpu_trap_csr(
    input         clk,
    input         reset,

    input         id_valid,
    input         id_done,
    input         dec_illegal,
    input         dec_is_ecall,
    input         dec_is_ebreak,
    input  [31:0] id_pc,
    input  [31:0] id_inst,
    input  [11:0] dec_csr_addr,

    input         mem_valid,
    input         mem_done,
    input         mem_misalign_load,
    input         mem_misalign_store,
    input  [31:0] mem_misalign_addr,
    input  [31:0] mem_pc,

    input  [319:0] id_exe_bus_r,

    input         csr_valid,
    input         trap_enter_valid,
    input         trap_return_valid,

    input         timer_irq,
    input  [31:0] current_pc,

    input         exe_misalign_valid,
    input  [31:0] exe_misalign_target,
    input  [31:0] exe_pc,

    input         cycle_en,
    input         inst_retire,

    output        exception_at_decode,
    output        trap_pending,
    output [31:0] csr_read_data,
    output [167:0] csr_wb_bus,
    output [31:0] trap_pc,
    output [31:0] csr_pc_plus4
);

    wire        hw_csr_wen;
    wire [31:0] hw_mepc_wdata;
    wire [31:0] hw_mcause_wdata;
    wire [31:0] hw_mtval_wdata;
    wire [31:0] hw_mstatus_wdata;

    wire [31:0] csr_mstatus;
    wire [31:0] csr_mie;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;
    wire [31:0] csr_mip;

    cpu_trap_manager u_trap_mgr(
        .clk              (clk),
        .reset            (reset),
        .id_valid         (id_valid),
        .id_done          (id_done),
        .dec_illegal      (dec_illegal),
        .dec_is_ecall     (dec_is_ecall),
        .dec_is_ebreak    (dec_is_ebreak),
        .id_pc            (id_pc),
        .id_inst          (id_inst),
        .mem_valid        (mem_valid),
        .mem_done         (mem_done),
        .mem_misalign_load(mem_misalign_load),
        .mem_misalign_store(mem_misalign_store),
        .mem_misalign_addr(mem_misalign_addr),
        .mem_pc           (mem_pc),
        .trap_enter_valid (trap_enter_valid),
        .trap_return_valid(trap_return_valid),
        .csr_mstatus      (csr_mstatus),
        .csr_mie          (csr_mie),
        .csr_mtvec        (csr_mtvec),
        .csr_mepc         (csr_mepc),
        .csr_mip          (csr_mip),
        .timer_irq        (timer_irq),
        .current_pc       (current_pc),
        .exe_misalign_valid(exe_misalign_valid),
        .exe_misalign_target(exe_misalign_target),
        .exe_pc           (exe_pc),
        .exception_at_decode(exception_at_decode),
        .trap_pending     (trap_pending),
        .trap_pc          (trap_pc),
        .hw_csr_wen       (hw_csr_wen),
        .hw_mepc_wdata    (hw_mepc_wdata),
        .hw_mcause_wdata  (hw_mcause_wdata),
        .hw_mtval_wdata   (hw_mtval_wdata),
        .hw_mstatus_wdata (hw_mstatus_wdata)
    );

    cpu_csr_interface u_csr_if(
        .clk              (clk),
        .reset            (reset),
        .id_exe_bus_r     (id_exe_bus_r),
        .dec_csr_addr     (dec_csr_addr),
        .csr_valid        (csr_valid),
        .hw_csr_wen       (hw_csr_wen),
        .hw_mepc_wdata    (hw_mepc_wdata),
        .hw_mcause_wdata  (hw_mcause_wdata),
        .hw_mtval_wdata   (hw_mtval_wdata),
        .hw_mstatus_wdata (hw_mstatus_wdata),
        .timer_irq        (timer_irq),
        .cycle_en         (cycle_en),
        .inst_retire      (inst_retire),
        .csr_read_data    (csr_read_data),
        .csr_wb_bus       (csr_wb_bus),
        .csr_pc_plus4     (csr_pc_plus4),
        .csr_mstatus      (csr_mstatus),
        .csr_mie          (csr_mie),
        .csr_mtvec        (csr_mtvec),
        .csr_mepc         (csr_mepc),
        .csr_mip          (csr_mip)
    );

endmodule
