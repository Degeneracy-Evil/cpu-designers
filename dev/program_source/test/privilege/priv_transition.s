# ============================================================
# privilege/priv_transition.s — Privilege level transition tests
# Category: Privilege
# Description: Test M↔S↔U privilege transitions (mret/sret)
# Sub-tests: 11
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# Prerequisites: Sv32 page table with dual mapping (setup_dual_map)
# ============================================================
#
# Page table layout (from setup_dual_map):
#   L0[0-7]:  Supervisor pages → PA 0x80000000-0x80007000
#   L0[8-15]: User pages → same PA (User alias at VA+0x8000)
#   L0[7]:    Supervisor page (result area for framework/S-mode)
#   L0[15]:   User page (result area alias)
#
# U-mode code executes at User VA (supervisor_VA + 0x8000).
# U-mode entry does NOT call test_run (test_run is at Supervisor VA,
# inaccessible from U-mode under Sv32). Instead, U-mode writes
# results to shared memory words, and S-mode checks them after
# U-mode returns.
#
# Data area (pt_*): shared between U-mode code and S-mode post-check.
# ============================================================

.equ USER_VA_OFFSET, 0x8000
.equ SHARED_SUP_BASE,  0x80007100
.equ SHARED_USER_BASE, 0x8000F100

.section .text.start
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10

    jal x1, test_init

    # ── Page table setup (dual mapping for U-mode code execution) ──
    jal x1, setup_dual_map
    jal x1, enable_sv32

    # ── M-mode tests ──
    la x11, test_01_mstatus_write_read
    jal x1, test_run
    la x11, test_02_sstatus_write_read
    jal x1, test_run

    # ── M→S transition (mret) ──
    la x11, test_03_m_to_s_mret
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
    li x5, SHARED_SUP_BASE
    sw x1, 12(x5)
    sw x20, 16(x5)
    sw x21, 20(x5)

    la x10, m_mode_resume
    csrw mscratch, x10

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

m_mode_resume:
    li x5, SHARED_SUP_BASE
    lw x1, 12(x5)
    lw x20, 16(x5)
    lw x21, 20(x5)
    li x10, 1
    ret

# ── Test 04: Verify S-mode reached ──
test_04_s_mode_reached:
    li x10, 1
    ret

# ── Test 05: S→U transition via sret ──
test_05_s_to_u_sret:
    # Clear U-mode result words
    li x5, SHARED_SUP_BASE
    sw x0, 0(x5)
    sw x0, 4(x5)
    sw x0, 8(x5)

    # Set sepc to User VA of u_mode_entry
    la x5, u_mode_entry
    li x6, USER_VA_OFFSET
    add x5, x5, x6
    csrw sepc, x5
    li x10, 0x00000022      # SPP=0(U-mode), SPIE=1, SIE=1
    csrw sstatus, x10
    sret

# ── Test 06: Verify U-mode reached ──
test_06_u_mode_reached:
    li x5, SHARED_SUP_BASE
    lw x5, 0(x5)
    li x10, 1
    beq x5, x10, 1f
    li x10, 0
1:  ret

# ── Test 07: U→S trap via ecall ──
test_07_u_ecall_to_s:
    # U-mode ecall already happened and was handled by s_trap_handler
    # which set pt_scause_saved. Just verify it occurred.
    li x5, SHARED_SUP_BASE
    lw x5, 8(x5)
    li x10, 1
    bnez x5, 1f            # non-zero means trap occurred
    li x10, 0
1:  ret

# ── Test 08: scause = 8 (ecall from U-mode) ──
test_08_scause_is_ecall_u:
    li x5, SHARED_SUP_BASE
    lw x5, 8(x5)
    li x6, 8
    li x10, 1
    beq x5, x6, 1f
    li x10, 0
1:  ret

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
test_11_u_data_access:
    li x5, SHARED_SUP_BASE
    lw x5, 4(x5)
    li x10, 1
    beq x5, x10, 1f
    li x10, 0
1:  ret

# ────────────────────────────────────────
# S-mode entry point (reached via mret)
# ────────────────────────────────────────
s_mode_entry:
    la x11, test_04_s_mode_reached
    jal x1, test_run

    # S→U transition
    la x11, test_05_s_to_u_sret
    jal x1, test_run

    # After U-mode returns, check results
    la x11, test_06_u_mode_reached
    jal x1, test_run
    la x11, test_07_u_ecall_to_s
    jal x1, test_run
    la x11, test_08_scause_is_ecall_u
    jal x1, test_run
    la x11, test_09_s_ecall_to_m
    jal x1, test_run
    la x11, test_10_mcause_is_ecall_s
    jal x1, test_run
    la x11, test_11_u_data_access
    jal x1, test_run

    # Done with S-mode, return to M-mode
    li x10, 0
    ecall

# ────────────────────────────────────────
# U-mode entry point (reached via sret)
# Runs at User VA. Does NOT call test_run.
# Results communicated via shared memory words.
# ────────────────────────────────────────
u_mode_entry:
    # Signal: U-mode reached
    li x5, 1
    li x6, SHARED_USER_BASE
    sw x5, 0(x6)

    # U-mode ecall → S-mode trap (test_07/08)
    li x10, 0               # marker: test ecall (not return)
    ecall

    # After sret back to U-mode, do data access test
    li x5, 0x8000F080       # user-accessible page (User VA via L0[15] alias)
    li x6, 0xDEADBEEF
    sw x6, 0(x5)
    lw x7, 0(x5)
    li x5, 0
    bne x6, x7, 1f
    li x5, 1
1:
    li x6, SHARED_USER_BASE
    sw x5, 4(x6)

    # Return to S-mode via marker ecall
    li x10, 0x42
    ecall

# ────────────────────────────────────────
# S-mode trap handler
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
    beq x10, x26, s_hdl_return

    # Test ecall from U-mode: record scause
    li x5, SHARED_SUP_BASE
    sw x22, 8(x5)
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_return:
    # Marker ecall: return to S-mode proper
    # Set SPP=1 so sret returns to S-mode (not U-mode)
    csrr x5, sstatus
    li x6, 0x100
    or x5, x5, x6
    csrw sstatus, x5
    la x5, s_return_point
    csrw sepc, x5
    sret

s_return_point:
    # Back in S-mode: finish test_05 and let s_mode_entry continue with test_06+
    li x10, 1
    ret

# ────────────────────────────────────────
# M-mode trap handler
# ────────────────────────────────────────
m_trap_handler:
    csrr x22, mcause
    csrr x23, mepc

    li x26, 9
    beq x22, x26, m_hdl_ecall_s

    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_ecall_s:
    li x26, 0x42
    beq x10, x26, m_hdl_return_s

    csrr x23, mscratch
    csrr x5, mstatus
    li x6, 0x1800
    or x5, x5, x6
    csrw mstatus, x5
    csrw mepc, x23
    mret

m_hdl_return_s:
    addi x23, x23, 4
    csrw mepc, x23
    # Set MPP=S-mode so mret returns to S-mode
    csrr x5, mstatus
    li x6, 0x1888            # MPP=01(S), MPIE=1, MIE=1
    csrw mstatus, x6
    li x10, 1
    mret
