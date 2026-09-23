`timescale 1ns / 1ps
`include "core_bus_types.svh"

module cpu_trap_router(
    input exception_t  exception,

    input              trap_return_valid,
    input trap_return_kind_t trap_return_kind,

    input              trap_enter_valid,

    input       [31:0] interrupt_pc,

    input       priv_mode_t priv_mode,

    input       [31:0] csr_mstatus,
    input       [31:0] csr_mie,
    input       [31:0] csr_mtvec,
    input       [31:0] csr_mepc,
    input       [31:0] csr_mip,
    input       [31:0] csr_medeleg,
    input       [31:0] csr_mideleg,
    input       [31:0] csr_stvec,
    input       [31:0] csr_sepc,
    output             trap_enter,
    output             interrupt_pending,
    output             trap_return,
    output      [31:0] trap_pc,
    output      priv_mode_t target_priv,

    output             hw_csr_wen,
    output             hw_trap_is_enter,
    output      priv_mode_t hw_status_priv,
    output      [31:0] hw_mepc_wdata,
    output      [31:0] hw_mcause_wdata,
    output      [31:0] hw_mtval_wdata,
    output      [31:0] hw_mstatus_wdata,
    output      [31:0] hw_sepc_wdata,
    output      [31:0] hw_scause_wdata,
    output      [31:0] hw_stval_wdata,
    output      [31:0] hw_sstatus_wdata
);
    wire mie_bit    = csr_mstatus[3];
    wire sie_bit    = csr_mstatus[1];
    wire [31:0] enabled_pending = csr_mip & csr_mie;
    wire [31:0] supported_interrupts = 32'h0000_0AAA;

    // Global xIE only gates interrupts while executing at the target
    // privilege. An interrupt targeting a higher privilege is enabled
    // regardless of that higher privilege's xIE bit.
    wire m_global_enable = (priv_mode != PRIV_M) || mie_bit;
    wire s_global_enable = (priv_mode == PRIV_U) ||
                           ((priv_mode == PRIV_S) && sie_bit);

    wire [31:0] m_interrupts = enabled_pending & supported_interrupts &
                               ~csr_mideleg & {32{m_global_enable}};
    wire [31:0] s_interrupts = enabled_pending & supported_interrupts &
                               csr_mideleg & {32{s_global_enable}};
    wire m_interrupt_pending = |m_interrupts;
    wire s_interrupt_pending = |s_interrupts;

    // Higher-privilege traps win first. Within one target privilege use the
    // standard platform order: external, software, timer.
    wire [5:0] m_int_idx = m_interrupts[11] ? 6'd11 :
                           m_interrupts[3]  ? 6'd3  :
                           m_interrupts[7]  ? 6'd7  :
                           m_interrupts[9]  ? 6'd9  :
                           m_interrupts[1]  ? 6'd1  : 6'd5;
    wire [5:0] s_int_idx = s_interrupts[9] ? 6'd9 :
                           s_interrupts[1] ? 6'd1 : 6'd5;
    wire [31:0] m_interrupt_cause = 32'h8000_0000 | {26'b0, m_int_idx};
    wire [31:0] s_interrupt_cause = 32'h8000_0000 | {26'b0, s_int_idx};

    wire [4:0] exc_code_idx;
    assign exc_code_idx = exception.cause[4:0];

    wire exc_delegated = exception.valid && csr_medeleg[exc_code_idx];

    // Delegation applies only to traps originating below M-mode.
    wire trap_to_s;
    assign trap_to_s = (exception.valid && exc_delegated && (priv_mode != PRIV_M)) ||
                       (!exception.valid && !m_interrupt_pending && s_interrupt_pending);

    wire return_m = trap_return_valid && (trap_return_kind == RET_M);
    wire return_s = trap_return_valid && (trap_return_kind == RET_S);

    reg [31:0] mstatus_on_trap_to_m;
    reg [31:0] mstatus_on_trap_to_s;
    reg [31:0] mstatus_on_mret;
    reg [31:0] mstatus_on_sret;

    always_comb begin
        mstatus_on_trap_to_m = csr_mstatus;
        mstatus_on_trap_to_m[12:11] = priv_mode;
        mstatus_on_trap_to_m[7] = csr_mstatus[3];
        mstatus_on_trap_to_m[3] = 1'b0;

        mstatus_on_trap_to_s = csr_mstatus;
        mstatus_on_trap_to_s[8] = (priv_mode == PRIV_S);
        mstatus_on_trap_to_s[5] = csr_mstatus[1];
        mstatus_on_trap_to_s[1] = 1'b0;

        mstatus_on_mret = csr_mstatus;
        mstatus_on_mret[3] = csr_mstatus[7];
        mstatus_on_mret[7] = 1'b1;
        mstatus_on_mret[12:11] = PRIV_U;
        if (csr_mstatus[12:11] != PRIV_M)
            mstatus_on_mret[17] = 1'b0;

        mstatus_on_sret = csr_mstatus;
        mstatus_on_sret[1] = csr_mstatus[5];
        mstatus_on_sret[5] = 1'b1;
        mstatus_on_sret[8] = 1'b0;
        mstatus_on_sret[17] = 1'b0;
    end

    assign target_priv = return_m ? priv_mode_t'(csr_mstatus[12:11]) :
                         return_s ? priv_mode_t'(csr_mstatus[8] ? PRIV_S : PRIV_U) :
                         priv_mode_t'(trap_to_s ? PRIV_S : PRIV_M);

    assign interrupt_pending = m_interrupt_pending || s_interrupt_pending;
    assign trap_enter  = exception.valid || interrupt_pending;
    assign trap_return = return_m || return_s;

    assign trap_pc = return_s ? csr_sepc :
                     return_m ? csr_mepc :
                     trap_to_s ? {csr_stvec[31:2], 2'b00} :
                     {csr_mtvec[31:2], 2'b00};

    assign hw_csr_wen = (trap_enter && trap_enter_valid) || trap_return;
    assign hw_trap_is_enter = trap_enter && trap_enter_valid;
    assign hw_status_priv = return_m ? PRIV_M :
                            return_s ? PRIV_S :
                            priv_mode_t'(trap_to_s ? PRIV_S : PRIV_M);

    assign hw_mepc_wdata = exception.valid ? exception.epc : interrupt_pc;
    assign hw_mcause_wdata = exception.valid ? exception.cause :
                            m_interrupt_cause;
    assign hw_mtval_wdata = exception.valid ? exception.tval : 32'b0;

    assign hw_mstatus_wdata = trap_enter ? mstatus_on_trap_to_m :
                              mstatus_on_mret;

    assign hw_sepc_wdata = exception.valid ? exception.epc : interrupt_pc;
    assign hw_scause_wdata = exception.valid ? exception.cause :
                             s_interrupt_cause;
    assign hw_stval_wdata = exception.valid ? exception.tval : 32'b0;

    assign hw_sstatus_wdata = trap_enter ? mstatus_on_trap_to_s :
                              mstatus_on_sret;

endmodule
