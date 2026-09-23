`timescale 1ns / 1ps
`include "core/interface/types.svh"

module cpu_trap_manager(
    input         clk,
    input         resetn,

    input exception_t sync_exception_now,
    input         trap_enter_valid,
    input         trap_return_valid,
    input trap_return_kind_t trap_return_kind,

    input priv_mode_t priv_mode,
    input  [31:0] csr_mstatus,
    input  [31:0] csr_mie,
    input  [31:0] csr_mtvec,
    input  [31:0] csr_mepc,
    input  [31:0] csr_mip,
    input  [31:0] csr_medeleg,
    input  [31:0] csr_mideleg,
    input  [31:0] csr_stvec,
    input  [31:0] csr_sepc,
    input  [31:0] current_pc,

    output        sync_exception_pending,
    output        interrupt_pending,
    output [31:0] trap_pc,
    output priv_mode_t target_priv,

    output        hw_csr_wen,
    output        hw_trap_is_enter,
    output priv_mode_t hw_status_priv,
    output [31:0] hw_mepc_wdata,
    output [31:0] hw_mcause_wdata,
    output [31:0] hw_mtval_wdata,
    output [31:0] hw_mstatus_wdata,
    output [31:0] hw_sepc_wdata,
    output [31:0] hw_scause_wdata,
    output [31:0] hw_stval_wdata,
    output [31:0] hw_sstatus_wdata
);
    exception_t exception_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            exception_r <= '0;
        end else if (trap_enter_valid || trap_return_valid) begin
            exception_r.valid <= 1'b0;
        end else if (sync_exception_now.valid && !exception_r.valid) begin
            exception_r <= sync_exception_now;
        end
    end

    assign sync_exception_pending = exception_r.valid;

    cpu_trap_router u_trap_router(
        .exception(exception_r),
        .trap_return_valid(trap_return_valid),
        .trap_return_kind(trap_return_kind),
        .trap_enter_valid(trap_enter_valid),
        .interrupt_pc(current_pc),
        .priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mip(csr_mip),
        .csr_medeleg(csr_medeleg),
        .csr_mideleg(csr_mideleg),
        .csr_stvec(csr_stvec),
        .csr_sepc(csr_sepc),
        .trap_enter(),
        .interrupt_pending(interrupt_pending),
        .trap_return(),
        .trap_pc(trap_pc),
        .target_priv(target_priv),
        .hw_csr_wen(hw_csr_wen),
        .hw_trap_is_enter(hw_trap_is_enter),
        .hw_status_priv(hw_status_priv),
        .hw_mepc_wdata(hw_mepc_wdata),
        .hw_mcause_wdata(hw_mcause_wdata),
        .hw_mtval_wdata(hw_mtval_wdata),
        .hw_mstatus_wdata(hw_mstatus_wdata),
        .hw_sepc_wdata(hw_sepc_wdata),
        .hw_scause_wdata(hw_scause_wdata),
        .hw_stval_wdata(hw_stval_wdata),
        .hw_sstatus_wdata(hw_sstatus_wdata)
    );

endmodule
