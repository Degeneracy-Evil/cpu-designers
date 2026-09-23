# ============================================================
# exception/illegal_inst.s — Illegal instruction exception tests
# Category: Exception
# Description: Test illegal instruction trap (mcause=2)
# Sub-tests: 3
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

    la x11, test_illegal_continues
    jal x1, test_run
    la x11, test_illegal_mcause
    jal x1, test_run
    la x11, test_illegal_multiple
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Illegal instruction: execution continues after trap ──
test_illegal_continues:
    li x10, 0
    .word 0x00000000         # illegal instruction (all zeros = not valid RV32I)
    li x10, 1               # reached = PASS
    ret

# ── Illegal instruction mcause = 2 ──
test_illegal_mcause:
    li x10, 0
    .word 0x00000000         # illegal instruction
    # m_trap_record sets x22 = mcause
    li x14, 2
    bne x22, x14, 1f
    li x10, 1
1:
    ret

# ── Multiple illegal instructions: all handled ──
test_illegal_multiple:
    li x10, 0
    .word 0x00000000         # first illegal
    .word 0x00000000         # second illegal
    li x10, 1               # reached = PASS
    ret
