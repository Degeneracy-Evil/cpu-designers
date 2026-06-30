# ============================================================
# privilege/delegation.s — Exception/interrupt delegation tests
# Category: Privilege
# Description: Test medeleg/mideleg delegation (traps go to S instead of M)
# Sub-tests: 8
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# Prerequisites: Sv32 page table with dual mapping (setup_dual_map)
# ============================================================
#
# Page table layout (from setup_dual_map):
#   L0[0-7]:  Supervisor pages → PA 0x80000000-0x80007000
#   L0[8-15]: User pages → same PA (User alias at VA+0x8000)
#   L0[7]:    User page (result area)
#   L0[15]:   User page (result area alias)
#
# U-mode code executes at User VA (supervisor_VA + 0x8000).
# S-mode trap handler at Supervisor VA (S-mode can fetch from U=0 pages).
# M-mode trap handler at Supervisor VA (M-mode can access anything).
#
# Trap flow for delegated exceptions:
#   U-mode ecall → S-mode handler (medeleg[8]=1)
#   U-mode illegal → S-mode handler (medeleg[2]=1)
#   S-mode ecall → M-mode handler (medeleg[9]=0 always)
#
# Data area (deleg_*): shared between trap handlers and post-check code.
# ============================================================

.equ USER_VA_OFFSET, 0x8000

.section .text.start
.globl _start

_start:
    la x10, m_deleg_handler
    csrw mtvec, x10

    jal x1, test_init

    # ── CSR read/write tests (M-mode, no page table needed) ──
    la x11, test_01_medeleg_write_read
    jal x1, test_run
    la x11, test_02_mideleg_write_read
    jal x1, test_run
    la x11, test_03_medeleg_multi_write
    jal x1, test_run

    # ── Delegation behavior tests (need Sv32 + mode transitions) ──
    la x11, test_04_ecall_u_to_s_delegated
    jal x1, test_run
    la x11, test_05_ecall_s_to_m_not_delegated
    jal x1, test_run
    la x11, test_06_illegal_u_to_s_delegated
    jal x1, test_run
    la x11, test_07_ecall_u_to_m_not_delegated
    jal x1, test_run
    la x11, test_08_deleg_sepc_correct
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ────────────────────────────────────────────
# Test 01: medeleg[8] write/read
# ────────────────────────────────────────────
test_01_medeleg_write_read:
    li x10, 0x100
    csrw medeleg, x10
    csrr x11, medeleg
    li x12, 0x100
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ────────────────────────────────────────────
# Test 02: mideleg[5] write/read
# ────────────────────────────────────────────
test_02_mideleg_write_read:
    li x10, 0x0080
    csrw mideleg, x10
    csrr x11, mideleg
    li x12, 0x0080
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ────────────────────────────────────────────
# Test 03: medeleg multi-bit write/read
# ────────────────────────────────────────────
test_03_medeleg_multi_write:
    li x10, 0x124           # delegate ecall-U(8) + illegal(2) + ecall-S(4..wait)
    # Actually: bit 8=ecall-from-U, bit 2=illegal, bit 1=instr access fault
    li x10, 0x104           # medeleg[8]=1, [2]=1
    csrw medeleg, x10
    csrr x11, medeleg
    li x12, 0x104
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ────────────────────────────────────────────
# Test 04: ecall from U → S (medeleg[8]=1)
# ────────────────────────────────────────────
test_04_ecall_u_to_s_delegated:
    la x5, deleg_saved_ra; sw x1, 0(x5)
    la x5, post_04; la x6, deleg_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)   # clear got_s_trap, got_m_trap
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x104; csrw medeleg, x10    # delegate ecall-U + illegal
    li x10, 0x020; csrw mideleg, x10    # delegate timer
    la x10, s_deleg_handler; csrw stvec, x10
    la x5, s_entry_04; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_04:
    la x5, u_entry_04
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_04:
    ecall                    # ecall from U → should trap to S (delegated)
    li x10, 0x42; ecall      # marker: return to S-mode

post_04:
    la x5, deleg_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, deleg_scause; lw x5, 0(x5)
    li x6, 8; beq x5, x6, 2f  # scause=8 (ecall from U)
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, deleg_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# Test 05: ecall from S → M (ecall-from-S never delegable)
# ────────────────────────────────────────────
test_05_ecall_s_to_m_not_delegated:
    la x5, deleg_saved_ra; sw x1, 0(x5)
    la x5, post_05; la x6, deleg_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x104; csrw medeleg, x10
    li x10, 0x020; csrw mideleg, x10
    la x10, s_deleg_handler; csrw stvec, x10
    la x5, s_entry_05; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_05:
    ecall                    # ecall from S → always traps to M (mcause=9)
    li x10, 0x42; ecall      # marker: return from S

post_05:
    la x5, deleg_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, deleg_mcause; lw x5, 0(x5)
    li x6, 9; beq x5, x6, 2f  # mcause=9 (ecall from S)
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, deleg_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# Test 06: illegal instruction from U → S (medeleg[2]=1)
# ────────────────────────────────────────────
test_06_illegal_u_to_s_delegated:
    la x5, deleg_saved_ra; sw x1, 0(x5)
    la x5, post_06; la x6, deleg_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x104; csrw medeleg, x10    # delegate illegal(2) + ecall-U(8)
    li x10, 0x020; csrw mideleg, x10
    la x10, s_deleg_handler; csrw stvec, x10
    la x5, s_entry_06; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_06:
    la x5, u_entry_06
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_06:
    .word 0x00000000         # illegal instruction in U-mode → S (delegated)
    li x10, 0x42; ecall      # marker: return to S-mode

post_06:
    la x5, deleg_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, deleg_scause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f  # scause=2 (illegal instruction)
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, deleg_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# Test 07: ecall from U → M (medeleg[8]=0, NOT delegated)
# ────────────────────────────────────────────
test_07_ecall_u_to_m_not_delegated:
    la x5, deleg_saved_ra; sw x1, 0(x5)
    la x5, post_07; la x6, deleg_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    csrw medeleg, x0           # NO delegation
    csrw mideleg, x0
    la x10, s_deleg_handler; csrw stvec, x10
    la x5, s_entry_07; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_07:
    la x5, u_entry_07
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_07:
    ecall                    # ecall from U → M (NOT delegated)
    li x10, 0x42; ecall      # marker (won't reach here, M handler takes over)

post_07:
    la x5, deleg_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, deleg_mcause; lw x5, 0(x5)
    li x6, 8; beq x5, x6, 2f  # mcause=8 (ecall from U, not delegated)
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, deleg_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# Test 08: delegated trap: sepc points to faulting instruction
# ────────────────────────────────────────────
test_08_deleg_sepc_correct:
    la x5, deleg_saved_ra; sw x1, 0(x5)
    la x5, post_08; la x6, deleg_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x104; csrw medeleg, x10
    li x10, 0x020; csrw mideleg, x10
    la x10, s_deleg_handler; csrw stvec, x10
    la x5, s_entry_08; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_08:
    la x5, u_entry_08
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_08:
    ecall                    # sepc should = VA of this ecall
    li x10, 0x42; ecall

post_08:
    # Verify: deleg_sepc_val == expected User VA of ecall in u_entry_08
    la x5, deleg_sepc_val; lw x5, 0(x5)
    la x6, u_entry_08
    li x7, USER_VA_OFFSET; add x6, x6, x7   # expected User VA
    li x10, 1
    beq x5, x6, 1f
    li x10, 0
1:  la x5, deleg_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# S-mode trap handler (for delegated exceptions)
# ────────────────────────────────────────────
s_deleg_handler:
    csrr x22, scause
    csrr x23, sepc

    # ecall from U (scause=8)
    li x26, 8
    beq x22, x26, s_hdl_ecall_u

    # illegal instruction (scause=2)
    li x26, 2
    beq x22, x26, s_hdl_illegal

    # instruction page fault (scause=12) — U-mode fetch from S-page
    li x26, 12
    beq x22, x26, s_hdl_skip

    # load page fault (scause=13)
    li x26, 13
    beq x22, x26, s_hdl_skip

    # store page fault (scause=15)
    li x26, 15
    beq x22, x26, s_hdl_skip

    # store/AMO access fault (scause=7)
    li x26, 7
    beq x22, x26, s_hdl_skip

s_hdl_skip:
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_ecall_u:
    # Check marker (x10=0x42 means return to S-mode)
    li x26, 0x42
    beq x10, x26, s_hdl_return
    # Test ecall: record scause and sepc
    li x5, 1; la x6, deleg_got_s_trap; sw x5, 0(x6)
    la x5, deleg_scause; sw x22, 0(x5)
    la x5, deleg_sepc_val; sw x23, 0(x5)
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_hdl_illegal:
    # Record illegal instruction delegation
    li x5, 1; la x6, deleg_got_s_trap; sw x5, 0(x6)
    la x5, deleg_scause; sw x22, 0(x5)
    la x5, deleg_sepc_val; sw x23, 0(x5)
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
    # Back in S-mode, ecall to M-mode to continue
    ecall

# ────────────────────────────────────────────
# M-mode trap handler
# ────────────────────────────────────────────
m_deleg_handler:
    csrr x22, mcause
    csrr x23, mepc

    # ecall from S (mcause=9): jump to return_pc
    li x26, 9
    beq x22, x26, m_hdl_ecall_s

    # ecall from U (mcause=8): NOT delegated, record
    li x26, 8
    beq x22, x26, m_hdl_ecall_u_nodeleg

    # ecall from M (mcause=11): skip
    li x26, 11
    beq x22, x26, m_hdl_skip

    # illegal instruction (mcause=2): record as M-trap
    li x26, 2
    beq x22, x26, m_hdl_illegal_m

    # Other fault: record and jump to return_pc
    li x5, 1; la x6, deleg_got_m_trap; sw x5, 0(x6)
    la x5, deleg_mcause; sw x22, 0(x5)
    la x5, deleg_return_pc; lw x5, 0(x5)
    beqz x5, m_hdl_fatal
    csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, deleg_return_pc; sw x0, 0(x5)
    mret

m_hdl_skip:
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_ecall_s:
    # S-mode ecall: record trap info, then jump to return_pc
    li x5, 1; la x6, deleg_got_m_trap; sw x5, 0(x6)
    la x5, deleg_mcause; sw x22, 0(x5)       # x22 = mcause = 9
    la x5, deleg_return_pc; lw x5, 0(x5)
    beqz x5, m_hdl_fatal
    csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, deleg_return_pc; sw x0, 0(x5)
    mret

m_hdl_ecall_u_nodeleg:
    # U-mode ecall reached M: NOT delegated, record
    li x5, 1; la x6, deleg_got_m_trap; sw x5, 0(x6)
    la x5, deleg_mcause; sw x22, 0(x5)
    # Jump to return_pc for post-check
    la x5, deleg_return_pc; lw x5, 0(x5)
    beqz x5, m_hdl_fatal
    csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, deleg_return_pc; sw x0, 0(x5)
    mret

m_hdl_illegal_m:
    # Illegal instruction reached M: record
    li x5, 1; la x6, deleg_got_m_trap; sw x5, 0(x6)
    la x5, deleg_mcause; sw x22, 0(x5)
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_fatal:
    la x5, deleg_saved_ra; lw x5, 0(x5)
    csrw mepc, x5
    li x10, 0
    li x5, 0x1888; csrw mstatus, x5
    mret

# ────────────────────────────────────────────
# Data area
# ────────────────────────────────────────────
.section .text
.balign 4
deleg_saved_ra:    .word 0
deleg_return_pc:   .word 0
deleg_got_s_trap:  .word 0
deleg_got_m_trap:  .word 0
deleg_scause:      .word 0
deleg_mcause:      .word 0
deleg_sepc_val:    .word 0
