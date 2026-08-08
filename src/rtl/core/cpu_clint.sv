`timescale 1ns / 1ps

module cpu_clint(
    input              clk,
    input              resetn,

    input              exception_valid,
    input       [31:0] exception_cause,
    input       [31:0] exception_pc,
    input       [31:0] exception_mtval,

    input              mret_req,
    input              sret_req,

    input              trap_enter_valid,

    input       [31:0] interrupt_pc,

    input       [1:0]  priv_mode,

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
    output             trap_return,
    output      [31:0] trap_pc,
    output      [1:0]  target_priv,

    output             hw_csr_wen,
    output             hw_trap_is_enter,
    output      [1:0]  hw_target_priv,
    output      [31:0] hw_mepc_wdata,
    output      [31:0] hw_mcause_wdata,
    output      [31:0] hw_mtval_wdata,
    output      [31:0] hw_mstatus_wdata,
    output      [31:0] hw_sepc_wdata,
    output      [31:0] hw_scause_wdata,
    output      [31:0] hw_stval_wdata,
    output      [31:0] hw_sstatus_wdata
);
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;

    wire mie_bit    = csr_mstatus[3];
    wire sie_bit    = csr_mstatus[1];
    wire mpie_bit   = csr_mstatus[7];
    wire spie_bit   = csr_mstatus[5];
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

    wire [5:0] exc_code_idx;
    assign exc_code_idx = exception_cause[5:0];

    wire exc_delegated = exception_valid && csr_medeleg[exc_code_idx];

    // BUG-FIX (sub-issue ④): Per RISC-V Privileged Spec §3.1.10, delegation only
    // applies when the trap originates from a LOWER privilege level. Traps from
    // M-mode must ALWAYS go to M-mode regardless of medeleg/mideleg settings.
    // Without this gate, an M-mode exception (e.g., during OpenSBI's trap handler)
    // with medeleg[cause]=1 would incorrectly trap to S-mode, bypassing OpenSBI
    // and corrupting the S-mode context — causing immediate re-trap / crash.
    wire trap_to_s;
    assign trap_to_s = (exception_valid && exc_delegated && (priv_mode != PRIV_M)) ||
                       (!exception_valid && !m_interrupt_pending && s_interrupt_pending);

    assign target_priv = trap_to_s ? PRIV_S : PRIV_M;

    assign trap_enter  = exception_valid || m_interrupt_pending || s_interrupt_pending;
    assign trap_return = mret_req || sret_req;

    assign trap_pc = sret_req ? csr_sepc :
                     mret_req ? csr_mepc :
                     trap_to_s ? {csr_stvec[31:2], 2'b00} :
                     {csr_mtvec[31:2], 2'b00};

    assign hw_csr_wen = (trap_enter && trap_enter_valid) || trap_return;
    assign hw_trap_is_enter = trap_enter && trap_enter_valid;
    assign hw_target_priv = trap_return ? priv_mode : target_priv;

    assign hw_mepc_wdata = exception_valid ? exception_pc : interrupt_pc;
    assign hw_mcause_wdata = exception_valid ? exception_cause :
                            m_interrupt_cause;
    assign hw_mtval_wdata = exception_valid ? exception_mtval : 32'b0;

    wire [31:0] m_trap_status =
        {csr_mstatus[31:13], priv_mode, csr_mstatus[10:8], mie_bit, csr_mstatus[6:4], 1'b0, csr_mstatus[2:0]};
    wire [31:0] m_return_status =
        {csr_mstatus[31:13], PRIV_U, csr_mstatus[10:8], 1'b1, csr_mstatus[6:4], mpie_bit, csr_mstatus[2:0]};
    // MRET clears MPRV whenever it returns below M-mode.
    wire [31:0] m_return_status_mprv = (csr_mstatus[12:11] == PRIV_M) ?
                                        m_return_status :
                                        (m_return_status & ~32'h0002_0000);
    assign hw_mstatus_wdata = trap_enter ? m_trap_status : m_return_status_mprv;

    assign hw_sepc_wdata = exception_valid ? exception_pc : interrupt_pc;
    assign hw_scause_wdata = exception_valid ? exception_cause :
                             s_interrupt_cause;
    assign hw_stval_wdata = exception_valid ? exception_mtval : 32'b0;

    wire [31:0] s_trap_status =
        {csr_mstatus[31:9], priv_mode[0], csr_mstatus[7:6], sie_bit, csr_mstatus[4:2], 1'b0, csr_mstatus[0]};
    wire [31:0] s_return_status =
        {csr_mstatus[31:9], 1'b0, csr_mstatus[7:6], 1'b1, csr_mstatus[4:2], spie_bit, csr_mstatus[0]};
    // SRET always executes below M-mode; clear any stale machine MPRV state.
    assign hw_sstatus_wdata = trap_enter ? s_trap_status :
                              (s_return_status & ~32'h0002_0000);

endmodule
