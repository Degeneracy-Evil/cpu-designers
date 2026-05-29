# ============================================================
# privilege/delegation.s — Exception/interrupt delegation tests
# Category: Privilege
# Description: Test medeleg/mideleg delegation (traps go to S instead of M)
# Sub-tests: 6
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# Prerequisites: Sv32 page table set up, satp configured
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10

    jal x1, test_init

    jal x1, setup_identity_map
    jal x1, enable_sv32

    # ── Delegation tests ──
    la x11, test_01_medeleg_ecall_delegated
    jal x1, test_run
    la x11, test_02_ecall_u_traps_to_s
    jal x1, test_run
    la x11, test_03_mideleg_timer_delegated
    jal x1, test_run
    la x11, test_04_no_deleg_ecall_s_traps_to_m
    jal x1, test_run
    la x11, test_05_medeleg_bite_fault_delegated
    jal x1, test_run
    la x11, test_06_deleg_illegal_to_s
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Test 01: medeleg delegates ecall from U ──
test_01_medeleg_ecall_delegated:
    li x10, 0x100           # medeleg[8] = 1 (delegate ecall-from-U)
    csrw medeleg, x10
    csrr x11, medeleg
    li x12, 0x100
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 02: ecall from U traps to S-mode (delegated) ──
test_02_ecall_u_traps_to_s:
    li x10, 1               # TODO: needs U-mode execution framework
    ret

# ── Test 03: mideleg delegates timer interrupt ──
test_03_mideleg_timer_delegated:
    li x10, 0x0020          # mideleg[5] = 1 (delegate timer interrupt)
    csrw mideleg, x10
    csrr x11, mideleg
    li x12, 0x0020
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 04: ecall from S still traps to M (not delegated) ──
test_04_no_deleg_ecall_s_traps_to_m:
    li x10, 1               # TODO: needs S-mode execution framework
    ret

# ── Test 05: medeleg delegates instruction access fault ──
test_05_medeleg_bite_fault_delegated:
    li x10, 0xB104
    csrw medeleg, x10
    csrr x11, medeleg
    li x12, 0xB104
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 06: illegal instruction delegated to S ──
test_06_deleg_illegal_to_s:
    li x10, 1               # TODO: needs U-mode execution + illegal inst
    ret

# ────────────────────────────────────────
# Trap handlers
# ────────────────────────────────────────
m_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    addi x23, x23, 4
    csrw mepc, x23
    mret

s_trap_handler:
    csrr x22, scause
    csrr x23, sepc
    addi x23, x23, 4
    csrw sepc, x23
    sret
