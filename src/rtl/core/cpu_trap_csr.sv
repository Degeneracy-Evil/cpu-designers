`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_trap_csr(
    input         clk,
    input         resetn,

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

    input  [329:0] id_exe_bus_r,

    input         csr_valid,
    input         trap_enter_valid,
    input         trap_return_valid,

    input  [1:0]  priv_mode,

    input         ext_meip_in,
    input         ext_seip_in,
    input         timer_irq,
    input         ext_msip_in,
    input  [63:0] ext_mtime,
    input  [31:0] current_pc,

    input         exe_misalign_valid,
    input  [31:0] exe_misalign_target,
    input  [31:0] exe_pc,

    input         inst_access_fault,
    input  [31:0] inst_access_fault_addr,
    input         load_access_fault,
    input  [31:0] load_access_fault_addr,
    input         store_access_fault,
    input  [31:0] store_access_fault_addr,
    input  [31:0] mem_access_fault_pc,

    input         inst_page_fault,
    input  [31:0] inst_page_fault_vaddr,
    input         load_page_fault,
    input  [31:0] load_page_fault_vaddr,
    input         store_page_fault,
    input  [31:0] store_page_fault_vaddr,
    input  [31:0] mem_page_fault_pc,

    input         cycle_en,
    input         inst_retire,

    output        exception_at_decode,
    output        trap_pending,
    output [31:0] csr_read_data,
    output wb_bus_t csr_wb_bus,
    output [31:0] trap_pc,
    output [31:0] csr_pc_plus4,
    output [1:0]  target_priv,

    output        inst_access_fault_pending,
    output        data_access_fault_pending,

    output        inst_page_fault_pending,
    output        data_page_fault_pending,

    output [31:0] csr_mstatus,
    output [31:0] csr_mie,
    output [31:0] csr_mtvec,
    output [31:0] csr_mepc,
    output [31:0] csr_mcause,
    output [31:0] csr_mip,
    output [31:0] csr_medeleg,
    output [31:0] csr_mideleg,
    output [31:0] csr_sstatus,
    output [31:0] csr_sie,
    output [31:0] csr_stvec,
    output [31:0] csr_sscratch,
    output [31:0] csr_sepc,
    output [31:0] csr_scause,
    output [31:0] csr_stval,
    output [31:0] csr_sip,
    output [31:0] csr_satp,
    output [31:0] csr_mcounteren,
    output [31:0] csr_scounteren,

    // ---------- Trap write-data outputs (for debug latch) ----------
    output [31:0] hw_trap_epc,       // faulting PC (mepc/sepc write value)
    output [31:0] hw_trap_cause,     // raw cause (mcause/scause write value)
    output [31:0] hw_trap_tval,      // trap value (mtval/stval write value)

    output        csr_access_ok,

    // PMP config outputs
    output [31:0] csr_pmpcfg0,
    output [31:0] csr_pmpcfg1,
    output [31:0] csr_pmpcfg2,
    output [31:0] csr_pmpcfg3,
    output [31:0] csr_pmpaddr0,
    output [31:0] csr_pmpaddr1,
    output [31:0] csr_pmpaddr2,
    output [31:0] csr_pmpaddr3,
    output [31:0] csr_pmpaddr4,
    output [31:0] csr_pmpaddr5,
    output [31:0] csr_pmpaddr6,
    output [31:0] csr_pmpaddr7,
    output [31:0] csr_pmpaddr8,
    output [31:0] csr_pmpaddr9,
    output [31:0] csr_pmpaddr10,
    output [31:0] csr_pmpaddr11,
    output [31:0] csr_pmpaddr12,
    output [31:0] csr_pmpaddr13,
    output [31:0] csr_pmpaddr14,
    output [31:0] csr_pmpaddr15
);

    wire        hw_csr_wen;
    wire        hw_trap_is_enter;
    wire [1:0]  hw_target_priv;
    wire [31:0] hw_mepc_wdata;
    wire [31:0] hw_mcause_wdata;
    wire [31:0] hw_mtval_wdata;
    wire [31:0] hw_mstatus_wdata;
    wire [31:0] hw_sepc_wdata;
    wire [31:0] hw_scause_wdata;
    wire [31:0] hw_stval_wdata;
    wire [31:0] hw_sstatus_wdata;

    cpu_trap_manager u_trap_mgr(
        .clk              (clk),
        .resetn            (resetn),
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
        .priv_mode        (priv_mode),
        .csr_mstatus      (csr_mstatus),
        .csr_mie          (csr_mie),
        .csr_mtvec        (csr_mtvec),
        .csr_mepc         (csr_mepc),
        .csr_mip          (csr_mip),
        .csr_medeleg      (csr_medeleg),
        .csr_mideleg      (csr_mideleg),
        .csr_stvec        (csr_stvec),
        .csr_sepc         (csr_sepc),
        .current_pc       (current_pc),
        .exe_misalign_valid(exe_misalign_valid),
        .exe_misalign_target(exe_misalign_target),
        .exe_pc           (exe_pc),
        .inst_access_fault(inst_access_fault),
        .inst_access_fault_addr(inst_access_fault_addr),
        .load_access_fault(load_access_fault),
        .load_access_fault_addr(load_access_fault_addr),
        .store_access_fault(store_access_fault),
        .store_access_fault_addr(store_access_fault_addr),
        .mem_access_fault_pc(mem_access_fault_pc),
        .inst_page_fault(inst_page_fault),
        .inst_page_fault_vaddr(inst_page_fault_vaddr),
        .load_page_fault(load_page_fault),
        .load_page_fault_vaddr(load_page_fault_vaddr),
        .store_page_fault(store_page_fault),
        .store_page_fault_vaddr(store_page_fault_vaddr),
        .mem_page_fault_pc(mem_page_fault_pc),
        .exception_at_decode(exception_at_decode),
        .trap_pending     (trap_pending),
        .trap_pc          (trap_pc),
        .target_priv      (target_priv),
        .hw_csr_wen       (hw_csr_wen),
        .hw_trap_is_enter (hw_trap_is_enter),
        .hw_target_priv   (hw_target_priv),
        .hw_mepc_wdata    (hw_mepc_wdata),
        .hw_mcause_wdata  (hw_mcause_wdata),
        .hw_mtval_wdata   (hw_mtval_wdata),
        .hw_mstatus_wdata (hw_mstatus_wdata),
        .hw_sepc_wdata    (hw_sepc_wdata),
        .hw_scause_wdata  (hw_scause_wdata),
        .hw_stval_wdata   (hw_stval_wdata),
        .hw_sstatus_wdata (hw_sstatus_wdata),
        .inst_access_fault_pending(inst_access_fault_pending),
        .data_access_fault_pending(data_access_fault_pending),
        .inst_page_fault_pending(inst_page_fault_pending),
        .data_page_fault_pending(data_page_fault_pending)
    );

    cpu_csr_interface u_csr_if(
        .clk              (clk),
        .resetn            (resetn),
        .id_exe_bus_r     (id_exe_bus_r),
        .dec_csr_addr     (dec_csr_addr),
        .csr_valid        (csr_valid),
        .priv_mode        (priv_mode),
        .hw_csr_wen       (hw_csr_wen),
        .hw_trap_is_enter (hw_trap_is_enter),
        .hw_target_priv   (hw_target_priv),
        .hw_mepc_wdata    (hw_mepc_wdata),
        .hw_mcause_wdata  (hw_mcause_wdata),
        .hw_mtval_wdata   (hw_mtval_wdata),
        .hw_mstatus_wdata (hw_mstatus_wdata),
        .hw_sepc_wdata    (hw_sepc_wdata),
        .hw_scause_wdata  (hw_scause_wdata),
        .hw_stval_wdata   (hw_stval_wdata),
        .hw_sstatus_wdata (hw_sstatus_wdata),
        .timer_irq        (timer_irq),
        .ext_meip_in      (ext_meip_in),
        .ext_seip_in      (ext_seip_in),
        .ext_msip_in      (ext_msip_in),
        .ext_mtime        (ext_mtime),
        .cycle_en         (cycle_en),
        .inst_retire      (inst_retire),
        .csr_read_data    (csr_read_data),
        .csr_wb_bus       (csr_wb_bus),
        .csr_pc_plus4     (csr_pc_plus4),
        .csr_mstatus      (csr_mstatus),
        .csr_mie          (csr_mie),
        .csr_mtvec        (csr_mtvec),
        .csr_mepc         (csr_mepc),
        .csr_mcause       (csr_mcause),
        .csr_mip          (csr_mip),
        .csr_medeleg      (csr_medeleg),
        .csr_mideleg      (csr_mideleg),
        .csr_sstatus      (csr_sstatus),
        .csr_sie          (csr_sie),
        .csr_stvec        (csr_stvec),
        .csr_sscratch     (csr_sscratch),
        .csr_sepc         (csr_sepc),
        .csr_scause       (csr_scause),
        .csr_stval        (csr_stval),
        .csr_sip          (csr_sip),
        .csr_satp         (csr_satp),
        .csr_mcounteren   (csr_mcounteren),
        .csr_scounteren   (csr_scounteren),
        .csr_access_ok    (csr_access_ok),
        .csr_pmpcfg0      (csr_pmpcfg0),
        .csr_pmpcfg1      (csr_pmpcfg1),
        .csr_pmpcfg2      (csr_pmpcfg2),
        .csr_pmpcfg3      (csr_pmpcfg3),
        .csr_pmpaddr0     (csr_pmpaddr0),
        .csr_pmpaddr1     (csr_pmpaddr1),
        .csr_pmpaddr2     (csr_pmpaddr2),
        .csr_pmpaddr3     (csr_pmpaddr3),
        .csr_pmpaddr4     (csr_pmpaddr4),
        .csr_pmpaddr5     (csr_pmpaddr5),
        .csr_pmpaddr6     (csr_pmpaddr6),
        .csr_pmpaddr7     (csr_pmpaddr7),
        .csr_pmpaddr8     (csr_pmpaddr8),
        .csr_pmpaddr9     (csr_pmpaddr9),
        .csr_pmpaddr10    (csr_pmpaddr10),
        .csr_pmpaddr11    (csr_pmpaddr11),
        .csr_pmpaddr12    (csr_pmpaddr12),
        .csr_pmpaddr13    (csr_pmpaddr13),
        .csr_pmpaddr14    (csr_pmpaddr14),
        .csr_pmpaddr15    (csr_pmpaddr15)
    );

    // Trap write-data outputs for debug latch
    // hw_mepc_wdata == hw_sepc_wdata, hw_mcause_wdata == hw_scause_wdata, etc.
    assign hw_trap_epc   = hw_mepc_wdata;
    assign hw_trap_cause = hw_mcause_wdata;
    assign hw_trap_tval  = hw_mtval_wdata;

endmodule
