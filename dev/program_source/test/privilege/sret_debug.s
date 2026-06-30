# ============================================================
# privilege/sret_debug.s — S→U sret 调试测试
# ============================================================
#
# 复现 Linux sret-to-U 场景:
#   1. M-mode: 设置页表 + satp + 委托
#   2. M→S via mret
#   3. S-mode: 设置 sepc=user_addr, sstatus(SPP=0,SPIE=1,SIE=0)
#   4. sret → 应该到 U-mode
#   5. U-mode: 写标记 + ecall 返回 S
#
# 关键区别: SIE=0 (关闭 S-mode 中断), 测试纯 sret 行为
#
# Sub-tests: 5
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

    # ── 页表设置 ──
    jal x1, setup_dual_map
    jal x1, enable_sv32

    # ── 设置委托: U-ecall → S-mode ──
    li x10, 0x0100      # medeleg bit 8 (U-ecall)
    csrw medeleg, x10
    li x10, 0x0000      # mideleg: 不委托任何中断
    csrw mideleg, x10

    # ── M→S transition ──
    la x10, s_trap_handler
    csrw stvec, x10

    la x10, s_mode_entry
    csrw mepc, x10
    li x10, 0x00000880  # MPP=01(S), MPIE=1, MIE=0
    csrw mstatus, x10
    mret

# ────────────────────────────────────────
# S-mode entry point
# ────────────────────────────────────────
s_mode_entry:
    # ── Test 1: S-mode reached ──
    li x10, 1
    jal x1, test_run_inline

    # ── Test 2: sstatus write SPP=0 readback ──
    li x10, 0x00000020  # SPP=0, SPIE=1, SIE=0
    csrw sstatus, x10
    csrr x11, sstatus
    li x12, 0x00000020
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
    # Save actual value for debug
    li x5, SHARED_SUP_BASE
    sw x11, 20(x5)
1:
    jal x1, test_run_inline

    # ── Test 3: S→U sret (core test) ──
    # Clear U-mode result words
    li x5, SHARED_SUP_BASE
    sw x0, 0(x5)
    sw x0, 4(x5)

    # Set sepc to User VA of u_mode_entry
    la x5, u_mode_entry
    li x6, USER_VA_OFFSET
    add x5, x5, x6
    csrw sepc, x5

    # SPP=0(U), SPIE=1, SIE=0 (interrupts OFF)
    li x10, 0x00000020
    csrw sstatus, x10

    # Read back sstatus to verify SPP=0 RIGHT BEFORE sret
    csrr x11, sstatus
    li x5, SHARED_SUP_BASE
    sw x11, 24(x5)   # debug: sstatus before sret

    sret

    # If we get here, sret returned to S-mode (BUG!)
    li x5, SHARED_SUP_BASE
    li x6, 0xDEAD0001
    sw x6, 28(x5)   # debug: sret returned to S-mode
    j s_loop_end

# ── S-mode resume after U-mode returns via ecall ──
s_mode_resume:
    # ── Test 4: Verify U-mode was reached ──
    li x5, SHARED_SUP_BASE
    lw x5, 0(x5)
    li x10, 1
    beq x5, x10, 1f
    li x10, 0
1:
    jal x1, test_run_inline

    # ── Test 5: scause = 8 (ecall from U) ──
    li x5, SHARED_SUP_BASE
    lw x5, 4(x5)
    li x6, 8
    li x10, 1
    beq x5, x6, 1f
    li x10, 0
1:
    jal x1, test_run_inline

    # Report results
    jal x1, test_report

s_loop_end:
    j s_loop_end

# ────────────────────────────────────────
# U-mode entry point (reached via sret)
# ────────────────────────────────────────
u_mode_entry:
    # Signal: U-mode reached
    li x5, 1
    li x6, SHARED_USER_BASE
    sw x5, 0(x6)

    # Read current priv mode indicator (debug)
    # We can't read priv_mode directly, but if we're in U-mode,
    # accessing a supervisor CSR should trap
    # Instead, just ecall back to S-mode
    li x10, 0x42
    ecall

    # Should not reach here
    j u_mode_entry

# ────────────────────────────────────────
# S-mode trap handler
# ────────────────────────────────────────
s_trap_handler:
    csrr x22, scause
    csrr x23, sepc
    mv   x24, x10            # save original a0 (marker from U-mode)

    # Save sstatus at trap entry for debug
    csrr x5, sstatus
    li x6, SHARED_SUP_BASE
    sw x5, 32(x6)   # debug: sstatus at S-trap entry
    sw x22, 4(x6)   # save scause
    sw x23, 36(x6)  # debug: sepc at trap

    # ecall from U-mode (scause=8)
    li x10, 8
    beq x22, x10, s_hdl_ecall_u

    # Other: skip and sret
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_ecall_u:
    # Check marker (x24 has original a0 from U-mode)
    li x10, 0x42
    beq x24, x10, s_hdl_return

    # Test ecall: record scause, advance sepc, sret back
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_return:
    # Return to S-mode proper
    # Set SPP=1 so sret returns to S-mode
    csrr x5, sstatus
    li x6, 0x100
    or x5, x5, x6
    csrw sstatus, x5
    la x5, s_mode_resume
    csrw sepc, x5
    sret

# ────────────────────────────────────────
# M-mode trap handler
# ────────────────────────────────────────
m_trap_handler:
    csrr x22, mcause
    csrr x23, mepc

    # Save debug info
    li x5, SHARED_SUP_BASE
    sw x22, 40(x5)   # debug: mcause
    sw x23, 44(x5)   # debug: mepc
    csrr x5, mstatus
    sw x5, 48(x5)    # debug: mstatus at M-trap

    # ecall from S-mode (mcause=9)
    li x10, 9
    beq x22, x10, m_hdl_ecall_s

    # Default: skip and mret
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_ecall_s:
    addi x23, x23, 4
    csrw mepc, x23
    # Set MPP=S, return to S-mode
    li x10, 0x00001880  # MPP=01(S), MPIE=1, MIE=0
    csrw mstatus, x10
    mret

# ────────────────────────────────────────
# Inline test runner (same logic as test_run but inlined)
# Input: x10 = 1(PASS) or 0(FAIL)
# ────────────────────────────────────────
test_run_inline:
    addi x9, x9, 1
    addi x19, x19, 1

    li x5, 0x80007000
    addi x6, x19, 3
    slli x6, x6, 2
    add x5, x5, x6
    sw x10, 0(x5)

    li x5, 1
    beq x10, x5, 1f
    j 2f
1:
    addi x8, x8, 1
2:
    bnez x18, 3f
    bnez x10, 3f
    add x18, x19, x0
3:
    ret
