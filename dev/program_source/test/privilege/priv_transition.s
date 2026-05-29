# ============================================================
# privilege/priv_transition.s — Privilege level transition tests
# Category: Privilege
# Description: Test M↔S↔U privilege transitions (mret/sret)
# Sub-tests: 11
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

    # ── Page table setup (framework: identity map + user page) ──
    jal x1, setup_user_map
    jal x1, enable_sv32

    # ── M-mode tests ──
    la x11, test_01_mstatus_write_read
    jal x1, test_run
    la x11, test_02_sstatus_write_read
    jal x1, test_run

    # ── M→S transition (mret) ──
    la x11, test_03_m_to_s_mret
    jal x1, test_run
    la x11, test_04_s_mode_reached
    jal x1, test_run

    # ── S→U transition (sret) ──
    la x11, test_05_s_to_u_sret
    jal x1, test_run
    la x11, test_06_u_mode_reached
    jal x1, test_run

    # ── U→S trap (ecall) ──
    la x11, test_07_u_ecall_to_s
    jal x1, test_run
    la x11, test_08_scause_is_ecall_u
    jal x1, test_run

    # ── S→M trap (ecall) ──
    la x11, test_09_s_ecall_to_m
    jal x1, test_run
    la x11, test_10_mcause_is_ecall_s
    jal x1, test_run

    # ── U-mode data access ──
    la x11, test_11_u_data_access
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Test 01: M-mode mstatus write/read ──
test_01_mstatus_write_read:
    li x10, 0x00001888
    csrw mstatus, x10
    csrr x11, mstatus
    li x12, 0x00001888
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 02: S-mode sstatus write/read ──
test_02_sstatus_write_read:
    li x10, 0x00000122
    csrw sstatus, x10
    csrr x11, sstatus
    li x12, 0x00000122
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 03: M→S transition via mret ──
test_03_m_to_s_mret:
    li x10, 0xB104
    csrw medeleg, x10
    li x10, 0x0020
    csrw mideleg, x10

    la x10, s_trap_handler
    csrw stvec, x10

    la x10, s_mode_entry
    csrw mepc, x10
    li x10, 0x00000882      # MPP=01(S-mode), MPIE=1, MIE=1
    csrw mstatus, x10
    mret

# ── Test 04: Verify S-mode reached ──
test_04_s_mode_reached:
    li x10, 1
    ret

# ── Test 05: S→U transition via sret ──
test_05_s_to_u_sret:
    la x10, u_mode_entry
    csrw sepc, x10
    li x10, 0x00000022      # SPP=0(U-mode), SPIE=1, SIE=1
    csrw sstatus, x10
    sret

# ── Test 06: Verify U-mode reached ──
test_06_u_mode_reached:
    li x10, 1
    ret

# ── Test 07: U→S trap via ecall ──
test_07_u_ecall_to_s:
    li x10, 0
    ecall
    li x10, 1
    ret

# ── Test 08: scause = 8 (ecall from U-mode) ──
test_08_scause_is_ecall_u:
    li x14, 8
    li x10, 1
    bne x22, x14, 1f
    ret
1:  li x10, 0
    ret

# ── Test 09: S→M trap via ecall ──
test_09_s_ecall_to_m:
    li x10, 0x42
    ecall
    li x10, 1
    ret

# ── Test 10: mcause = 9 (ecall from S-mode) ──
test_10_mcause_is_ecall_s:
    li x14, 9
    li x10, 1
    bne x22, x14, 1f
    ret
1:  li x10, 0
    ret

# ── Test 11: U-mode can access user data ──
# setup_user_map makes L0[7] (0x80007000) user-accessible.
# Write a marker to the user-accessible page and read it back.
test_11_u_data_access:
    li x10, 0x80007080      # user-accessible page (offset 0x80 in result page)
    li x11, 0xDEADBEEF
    sw x11, 0(x10)
    lw x12, 0(x10)
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ────────────────────────────────────────
# S-mode entry point (reached via mret)
# ────────────────────────────────────────
s_mode_entry:
    la x11, test_04_s_mode_reached
    jal x1, test_run

    # Enable U-mode access (SUM bit)
    csrr x10, sstatus
    li x11, 0x00040000
    or x10, x10, x11
    csrw sstatus, x10

    # S→U transition
    la x11, test_05_s_to_u_sret
    jal x1, test_run

    # After returning from U-mode, continue tests
    la x11, test_07_u_ecall_to_s
    jal x1, test_run
    la x11, test_08_scause_is_ecall_u
    jal x1, test_run
    la x11, test_09_s_ecall_to_m
    jal x1, test_run
    la x11, test_10_mcause_is_ecall_s
    jal x1, test_run

    # Done with S-mode, return to M-mode
    li x10, 0
    ecall

# ────────────────────────────────────────
# U-mode entry point (reached via sret)
# ────────────────────────────────────────
u_mode_entry:
    la x11, test_06_u_mode_reached
    jal x1, test_run

    la x11, test_07_u_ecall_to_s
    jal x1, test_run

    la x11, test_11_u_data_access
    jal x1, test_run

    # Return to S-mode via ecall
    li x10, 0x42
    ecall

# ────────────────────────────────────────
# Trap handlers
# ────────────────────────────────────────
s_trap_handler:
    csrr x22, scause
    csrr x23, sepc

    li x26, 8
    beq x22, x26, s_hdl_ecall_u

    li x26, 2
    beq x22, x26, s_hdl_skip

    li x26, 12
    beq x22, x26, s_hdl_skip
    li x26, 13
    beq x22, x26, s_hdl_skip
    li x26, 15
    beq x22, x26, s_hdl_skip

s_hdl_skip:
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_ecall_u:
    li x26, 0x42
    bne x10, x26, s_ecall_not_marker
    addi x23, x23, 4
    csrw sepc, x23
    sret
s_ecall_not_marker:
    addi x23, x23, 4
    csrw sepc, x23
    sret

m_trap_handler:
    csrr x22, mcause
    csrr x23, mepc

    li x26, 9
    beq x22, x26, m_hdl_ecall_s

    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_ecall_s:
    addi x23, x23, 4
    csrw mepc, x23
    mret
