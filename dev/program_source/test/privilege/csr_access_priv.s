# ============================================================
# privilege/csr_access_priv.s — CSR privilege access control tests
# Category: Privilege
# Description: Test that CSR reads/writes are restricted by privilege level
# Sub-tests: 8
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# ============================================================
# RISC-V privilege spec:
#   U-mode cannot access S-mode or M-mode CSRs
#   S-mode cannot access M-mode CSRs
#   Violation → illegal instruction exception (mcause=2 or scause=2)
# ============================================================
#
# Pattern: Each sub-test that needs S/U-mode does its own
# M→S→M or M→S→U→S→M round trip. Results communicated via
# csr_got_fault / csr_fault_cause memory words.
#
# U-mode code executes at User VA (supervisor_VA + 0x8000).
# ============================================================

.equ USER_VA_OFFSET, 0x8000

.section .text.start
.globl _start

_start:
    la x10, m_csr_handler
    csrw mtvec, x10
    li x10, 0x1888          # MPP=M, MPIE=1, MIE=1
    csrw mstatus, x10

    jal x1, test_init

    # ── CSR privilege access tests ──
    la x11, test_01_m_mode_access_all_csr
    jal x1, test_run
    la x11, test_02_s_mode_read_s_csr_ok
    jal x1, test_run
    la x11, test_03_s_mode_write_m_csr_illegal
    jal x1, test_run
    la x11, test_04_s_mode_read_m_csr_illegal
    jal x1, test_run
    la x11, test_05_u_mode_read_s_csr_illegal
    jal x1, test_run
    la x11, test_06_u_mode_read_m_csr_illegal
    jal x1, test_run
    la x11, test_07_u_mode_write_s_csr_illegal
    jal x1, test_run
    la x11, test_08_s_mode_write_s_csr_ok
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Test 01: M-mode can access all CSRs ──
test_01_m_mode_access_all_csr:
    csrr x14, mstatus
    csrr x15, sstatus
    csrr x16, mcause
    li x10, 1
    ret

# ── Test 02: S-mode can read S-mode CSR (sstatus) ──
test_02_s_mode_read_s_csr_ok:
    la x5, csr_saved_ra; sw x1, 0(x5)
    sw x0, 4(x5)             # clear got_fault
    jal x1, setup_dual_map
    jal x1, enable_sv32
    la x5, s_csr_read_s; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_csr_read_s:
    csrr x14, sstatus        # S-mode read S-CSR → OK
    li x14, 1; la x5, csr_result; sw x14, 0(x5); ecall

post_02:
    la x5, csr_got_fault; lw x5, 0(x5)
    bnez x5, 1f              # got fault → FAIL (should be OK)
    la x5, csr_result; lw x10, 0(x5)
    j 2f
1:  li x10, 0
2:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 03: S-mode write M-mode CSR → illegal instruction ──
test_03_s_mode_write_m_csr_illegal:
    la x5, csr_saved_ra; sw x1, 0(x5)
    la x5, post_03; la x6, csr_return_pc; sw x5, 0(x6)
    sw x0, 4(x6)             # clear got_fault
    jal x1, setup_dual_map
    jal x1, enable_sv32
    la x5, s_csr_write_m; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_csr_write_m:
    csrw mepc, x0            # S-mode write M-CSR → illegal
    li x14, 0; la x5, csr_result; sw x14, 0(x5); ecall

post_03:
    la x5, csr_got_fault; lw x5, 0(x5)
    beqz x5, 1f              # no fault → FAIL
    la x5, csr_fault_cause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f  # illegal instruction → PASS
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 04: S-mode read M-mode CSR → illegal instruction ──
test_04_s_mode_read_m_csr_illegal:
    la x5, csr_saved_ra; sw x1, 0(x5)
    la x5, post_04; la x6, csr_return_pc; sw x5, 0(x6)
    sw x0, 4(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    la x5, s_csr_read_m; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_csr_read_m:
    csrr x14, mcause         # S-mode read M-CSR → illegal
    li x14, 0; la x5, csr_result; sw x14, 0(x5); ecall

post_04:
    la x5, csr_got_fault; lw x5, 0(x5)
    beqz x5, 1f
    la x5, csr_fault_cause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 05: U-mode read S-mode CSR → illegal instruction ──
test_05_u_mode_read_s_csr_illegal:
    la x5, csr_saved_ra; sw x1, 0(x5)
    la x5, post_05; la x6, csr_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)   # clear got_fault, got_s_trap
    jal x1, setup_dual_map
    jal x1, enable_sv32
    # Delegate illegal instruction so U-mode trap goes to S first
    # (then S handler ecall's to M for final check)
    li x10, 0x004; csrw medeleg, x10    # delegate illegal(2)
    la x10, s_csr_handler; csrw stvec, x10
    la x5, s_entry_05; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_05:
    la x5, u_entry_05
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_05:
    csrr x14, sstatus        # U-mode read S-CSR → illegal
    li x10, 0x42; ecall      # marker (won't reach if trap works)

post_05:
    # Illegal from U delegated to S, then S recorded it
    la x5, csr_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, csr_scause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f  # scause=2 (illegal)
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 06: U-mode read M-mode CSR → illegal instruction ──
test_06_u_mode_read_m_csr_illegal:
    la x5, csr_saved_ra; sw x1, 0(x5)
    la x5, post_06; la x6, csr_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x004; csrw medeleg, x10    # delegate illegal(2)
    la x10, s_csr_handler; csrw stvec, x10
    la x5, s_entry_06; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_06:
    la x5, u_entry_06
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_06:
    csrr x14, mstatus        # U-mode read M-CSR → illegal
    li x10, 0x42; ecall

post_06:
    la x5, csr_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, csr_scause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 07: U-mode write S-mode CSR → illegal instruction ──
test_07_u_mode_write_s_csr_illegal:
    la x5, csr_saved_ra; sw x1, 0(x5)
    la x5, post_07; la x6, csr_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x10, 0x004; csrw medeleg, x10
    la x10, s_csr_handler; csrw stvec, x10
    la x5, s_entry_07; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_entry_07:
    la x5, u_entry_07
    li x6, USER_VA_OFFSET; add x5, x5, x6
    csrw sepc, x5
    li x5, 0x0022; csrw sstatus, x5; sret

u_entry_07:
    csrw sstatus, x0         # U-mode write S-CSR → illegal
    li x10, 0x42; ecall

post_07:
    la x5, csr_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, csr_scause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ── Test 08: S-mode write S-mode CSR OK ──
test_08_s_mode_write_s_csr_ok:
    la x5, csr_saved_ra; sw x1, 0(x5)
    sw x0, 4(x5)             # clear got_fault
    jal x1, setup_dual_map
    jal x1, enable_sv32
    la x5, s_csr_write_s; csrw mepc, x5
    li x5, 0x0880; csrw mstatus, x5; mret

s_csr_write_s:
    csrw sstatus, x0         # S-mode write S-CSR → OK
    li x14, 1; la x5, csr_result; sw x14, 0(x5); ecall

post_08:
    la x5, csr_got_fault; lw x5, 0(x5)
    bnez x5, 1f              # got fault → FAIL
    la x5, csr_result; lw x10, 0(x5)
    j 2f
1:  li x10, 0
2:  la x5, csr_saved_ra; lw x1, 0(x5); ret

# ────────────────────────────────────────────
# S-mode trap handler (for U-mode CSR access tests)
# ────────────────────────────────────────────
s_csr_handler:
    csrr x22, scause
    csrr x23, sepc

    # illegal instruction (scause=2)
    li x26, 2
    beq x22, x26, s_csr_hdl_illegal

    # ecall from U (scause=8): marker return
    li x26, 8
    beq x22, x26, s_csr_hdl_ecall_u

    # page faults: skip
    li x26, 12; beq x22, x26, s_csr_hdl_skip
    li x26, 13; beq x22, x26, s_csr_hdl_skip
    li x26, 15; beq x22, x26, s_csr_hdl_skip

s_csr_hdl_skip:
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_csr_hdl_illegal:
    # Record illegal instruction from U-mode
    li x5, 1; la x6, csr_got_s_trap; sw x5, 0(x6)
    la x5, csr_scause; sw x22, 0(x5)
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_csr_hdl_ecall_u:
    # Marker ecall: return to S-mode proper
    li x26, 0x42
    beq x10, x26, s_csr_hdl_return
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_csr_hdl_return:
    csrr x5, sstatus
    li x6, 0x100
    or x5, x5, x6
    csrw sstatus, x5
    la x5, s_csr_return_point
    csrw sepc, x5
    sret

s_csr_return_point:
    ecall                    # return to M-mode

# ────────────────────────────────────────────
# M-mode trap handler
# ────────────────────────────────────────────
m_csr_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval

    # ecall from S (mcause=9): jump to return_pc
    li x5, 9; beq x22, x5, m_csr_hdl_ecall_s

    # ecall from M (mcause=11): skip
    li x5, 11; beq x22, x5, m_csr_hdl_skip

    # ecall from U (mcause=8): not delegated, record
    li x5, 8; beq x22, x5, m_csr_hdl_ecall_u

    # illegal instruction (mcause=2): record fault
    li x5, 2; beq x22, x5, m_csr_hdl_illegal

    # Other: record and jump to return_pc
    la x5, csr_fault_cause; sw x22, 0(x5)
    la x5, csr_fault_val; sw x24, 0(x5)
    li x5, 1; la x6, csr_got_fault; sw x5, 0(x6)
    la x5, csr_return_pc; lw x5, 0(x5)
    beqz x5, m_csr_hdl_fatal
    csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, csr_return_pc; sw x0, 0(x5)
    mret

m_csr_hdl_skip:
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_csr_hdl_ecall_s:
    la x5, csr_return_pc; lw x5, 0(x5)
    bnez x5, 1f
    # No return_pc: simple ecall, read result
    la x5, csr_result; lw x10, 0(x5)
    la x5, csr_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5; mret
1:  csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, csr_return_pc; sw x0, 0(x5)
    mret

m_csr_hdl_ecall_u:
    # U-mode ecall reached M (not delegated): just skip
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_csr_hdl_illegal:
    # Illegal instruction in S-mode: record fault
    la x5, csr_fault_cause; sw x22, 0(x5)
    la x5, csr_fault_val; sw x24, 0(x5)
    li x5, 1; la x6, csr_got_fault; sw x5, 0(x6)
    la x5, csr_return_pc; lw x5, 0(x5)
    beqz x5, m_csr_hdl_fatal
    csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5
    la x5, csr_return_pc; sw x0, 0(x5)
    mret

m_csr_hdl_fatal:
    la x5, csr_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li x10, 0
    li x5, 0x1888; csrw mstatus, x5; mret

# ────────────────────────────────────────────
# Data area
# ────────────────────────────────────────────
.section .text
.balign 4
csr_saved_ra:    .word 0
csr_return_pc:   .word 0
csr_result:      .word 0
csr_got_fault:   .word 0
csr_got_s_trap:  .word 0
csr_fault_cause: .word 0
csr_fault_val:   .word 0
csr_scause:      .word 0
