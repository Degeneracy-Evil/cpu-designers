# ============================================================
# exception/ecall.s — ECALL exception tests
# Category: Exception
# Description: Test ECALL from M-mode (mcause=11)
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# Trap handler output: x22=mcause, x23=mepc (from m_trap_record)
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_record
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_ecall_m_mode
    jal x1, test_run
    la x11, test_ecall_mcause_value
    jal x1, test_run
    la x11, test_ecall_mepc_correct
    jal x1, test_run
    la x11, test_ecall_continues
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── ECALL from M-mode: execution continues after trap ──
test_ecall_m_mode:
    li x10, 0
    ecall                    # triggers trap, m_trap_record skips to next
    li x10, 1               # reached = PASS
    ret

# ── ECALL mcause = 11 (Environment call from M-mode) ──
test_ecall_mcause_value:
    li x10, 0
    ecall                    # m_trap_record sets x22 = mcause
    li x14, 11
    bne x22, x14, 1f
    li x10, 1
1:
    ret

# ── ECALL mepc points to the ecall instruction ──
# m_trap_record sets x23 = mepc+4
test_ecall_mepc_correct:
    li x10, 0
    auipc x14, 0            # x14 = PC of this auipc
    addi x14, x14, 8        # x14 = PC of ecall (auipc is 2 instr before ecall)
    ecall                    # mepc = ecall_PC = x14; x23 = mepc+4
    addi x15, x14, 4        # x15 = ecall_PC + 4 = x23 expected
    bne x23, x15, 1f
    li x10, 1
1:
    ret

# ── ECALL: execution continues correctly after multiple ecall ──
test_ecall_continues:
    li x10, 0
    ecall                    # first ecall
    ecall                    # second ecall
    li x10, 1               # reached = PASS
    ret
