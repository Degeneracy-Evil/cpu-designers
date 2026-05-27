# ============================================================
# exception/ebreak.s — EBREAK exception tests
# Category: Exception
# Description: Test EBREAK breakpoint (mcause=3)
# Sub-tests: 3
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# Trap handler output: x22=mcause (from m_trap_ebreak_handler)
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_ebreak_handler
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_ebreak_continues
    jal x1, test_run
    la x11, test_ebreak_mcause
    jal x1, test_run
    la x11, test_ebreak_multiple
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── EBREAK: execution continues after trap ──
test_ebreak_continues:
    li x10, 0
    ebreak                   # triggers trap, handler skips
    li x10, 1               # reached = PASS
    ret

# ── EBREAK mcause = 3 ──
test_ebreak_mcause:
    li x10, 0
    ebreak                   # m_trap_ebreak_handler sets x22 = mcause
    li x14, 3
    bne x22, x14, 1f
    li x10, 1
1:
    ret

# ── Multiple EBREAK: all handled correctly ──
test_ebreak_multiple:
    li x10, 0
    ebreak
    ebreak
    ebreak
    li x10, 1               # reached = PASS
    ret
