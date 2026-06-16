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
    input       [31:0] csr_sie,
    input       [31:0] csr_sip,

    input              ext_mtip,

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
    wire meie_bit   = csr_mie[11];
    wire mtie_bit   = csr_mie[7];
    wire msie_bit   = csr_mie[3];
    wire seie_bit   = csr_sie[9];
    wire stie_bit   = csr_sie[5];
    wire ssie_bit   = csr_sie[1];
    wire meip_bit   = csr_mip[11];
    wire seip_bit   = csr_mip[9];   // S-mode external interrupt pending (PLIC ctx1)
    wire mtip_bit   = ext_mtip;
    wire msip_bit   = csr_mip[3];
    // BUG-FIX (sub-issue ②): Use csr_mip[5] (STIP) for S-mode timer pending
    // instead of ext_mtip (raw CLINT MTIP). This allows STIP to be set either
    // by hardware (when timer interrupt is delegated via mideleg[5]) or by
    // software writing to sip[5]. Previously, using ext_mtip directly bypassed
    // the mip register and prevented software from setting STIP.
    wire stip_bit   = csr_mip[5];
    wire mpie_bit   = csr_mstatus[7];
    wire spie_bit   = csr_mstatus[5];
    wire mpp_field  = csr_mstatus[12:11];
    wire spp_field  = csr_mstatus[8];

    wire m_interrupt_pending = mie_bit && ((msie_bit && msip_bit) ||
                                           (mtie_bit && mtip_bit) ||
                                           (meie_bit && meip_bit));

    // BUG-FIX (sub-issue ②): S-mode timer uses stip_bit (csr_mip[5]) instead
    // of mtip_bit (ext_mtip). This correctly reflects the STIP value from the
    // mip register, which includes both hardware MTIP and software-written sip[5].
    wire s_interrupt_pending = sie_bit && ((ssie_bit && (csr_sip[1] | msip_bit)) ||
                                           (stie_bit && stip_bit) ||
                                           (seie_bit && seip_bit));

    wire [31:0] m_interrupt_cause;
    assign m_interrupt_cause = (meie_bit && meip_bit) ? 32'h8000000B :
                               (msie_bit && msip_bit) ? 32'h80000003 :
                               (mtie_bit && mtip_bit) ? 32'h80000007 :
                               32'h8000000B;

    wire [31:0] s_interrupt_cause;
    // BUG-FIX (sub-issue ②): Use stip_bit (csr_mip[5]) for S-mode timer cause.
    // Use seip_bit (csr_mip[9]) for S-mode external cause (PLIC context 1).
    assign s_interrupt_cause = (seie_bit && seip_bit) ? 32'h80000009 :
                               (ssie_bit && (csr_sip[1] | msip_bit)) ? 32'h80000001 :
                               (stie_bit && stip_bit) ? 32'h80000005 :
                               32'h80000009;

    wire [5:0] m_int_idx;
    assign m_int_idx = (meie_bit && meip_bit) ? 6'd11 :
                       (msie_bit && msip_bit) ? 6'd3  :
                       (mtie_bit && mtip_bit) ? 6'd7  : 6'd11;

    wire [5:0] s_int_idx;
    // BUG-FIX (sub-issue ②): Use stip_bit (csr_mip[5]) for S-mode timer index.
    // Use seip_bit (csr_mip[9]) for S-mode external index (PLIC context 1).
    assign s_int_idx = (seie_bit && seip_bit) ? 6'd9 :
                       (ssie_bit && (csr_sip[1] | msip_bit)) ? 6'd1 :
                       (stie_bit && stip_bit) ? 6'd5 : 6'd9;

    wire m_int_delegated = m_interrupt_pending && csr_mideleg[m_int_idx];
    // BUG-FIX (sub-issue ③): M/S interrupt priority fix.
    // Previously: s_int_taken = s_interrupt_pending && !m_int_delegated
    // This was WRONG: if M-mode interrupt is pending and NOT delegated,
    // !m_int_delegated=1, so S-mode could preempt M-mode — violating
    // RISC-V privilege priority (M > S).
    //
    // Correct logic: S-mode can only take its interrupt when no un-delegated
    // M-mode interrupt is pending. An un-delegated M-mode interrupt must be
    // taken in M-mode and has higher priority than any S-mode interrupt.
    //   s_int_taken = s_interrupt_pending && !(m_interrupt_pending && !m_int_delegated)
    // Which simplifies to:
    //   s_int_taken = s_interrupt_pending && (!m_interrupt_pending || m_int_delegated)
    wire m_int_not_delegated = m_interrupt_pending && !m_int_delegated;
    wire s_int_taken         = s_interrupt_pending && !m_int_not_delegated;

    wire [5:0] exc_code_idx;
    assign exc_code_idx = exception_cause[5:0];

    wire exc_delegated = exception_valid && csr_medeleg[exc_code_idx];

    wire trap_to_s;
    wire trap_to_m;
    assign trap_to_s = (exception_valid && exc_delegated) ||
                       (m_interrupt_pending && m_int_delegated) ||
                       (!exception_valid && s_int_taken);
    assign trap_to_m = !trap_to_s;

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

    assign hw_mstatus_wdata = trap_enter ?
        {csr_mstatus[31:13], priv_mode, csr_mstatus[10:8], mie_bit, csr_mstatus[6:4], 1'b0, csr_mstatus[2:0]} :
        {csr_mstatus[31:13], PRIV_U, csr_mstatus[10:8], 1'b1, csr_mstatus[6:4], mpie_bit, csr_mstatus[2:0]};

    assign hw_sepc_wdata = exception_valid ? exception_pc : interrupt_pc;
    assign hw_scause_wdata = exception_valid ? exception_cause :
                             s_interrupt_cause;
    assign hw_stval_wdata = exception_valid ? exception_mtval : 32'b0;

    assign hw_sstatus_wdata = trap_enter ?
        {csr_mstatus[31:9], priv_mode[0], csr_mstatus[7:6], sie_bit, csr_mstatus[4:2], 1'b0, csr_mstatus[0]} :
        {csr_mstatus[31:9], 1'b0, csr_mstatus[7:6], 1'b1, csr_mstatus[4:2], spie_bit, csr_mstatus[0]};

endmodule
