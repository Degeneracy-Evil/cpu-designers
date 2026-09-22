`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_trap_csr(
    input         clk,
    input         resetn,

    input exception_t sync_exception_now,

    input  id_exe_bus_t id_exe_bus_r,

    input         csr_valid,
    input         trap_enter_valid,
    input         trap_return_valid,

    input  priv_mode_t priv_mode,

    input         ext_meip_in,
    input         ext_seip_in,
    input         timer_irq,
    input         ext_msip_in,
    input  [63:0] ext_mtime,
    input  [31:0] current_pc,

    input         cycle_en,
    input         inst_retire,

    output        sync_exception_pending,
    output        interrupt_pending,
    output wb_bus_t csr_wb_bus,
    output [31:0] trap_pc,
    output [31:0] csr_pc_plus4,
    output priv_mode_t target_priv,

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
    priv_mode_t hw_target_priv;
    wire [31:0] hw_mepc_wdata;
    wire [31:0] hw_mcause_wdata;
    wire [31:0] hw_mtval_wdata;
    wire [31:0] hw_mstatus_wdata;
    wire [31:0] hw_sepc_wdata;
    wire [31:0] hw_scause_wdata;
    wire [31:0] hw_stval_wdata;
    wire [31:0] hw_sstatus_wdata;
    wire [31:0] csr_read_data;

    cpu_trap_manager u_trap_mgr(
        .clk              (clk),
        .resetn            (resetn),
        .sync_exception_now(sync_exception_now),
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
        .sync_exception_pending(sync_exception_pending),
        .interrupt_pending(interrupt_pending),
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
        .hw_sstatus_wdata (hw_sstatus_wdata)
    );

    cpu_csr_interface u_csr_if(
        .clk              (clk),
        .resetn            (resetn),
        .id_exe_bus_r     (id_exe_bus_r),
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
