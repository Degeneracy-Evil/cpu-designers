# ============================================================
# mmu/sv32_basic.s — Sv32 basic translation tests
# Category: MMU
# Sub-tests: 6
# ============================================================
# CRITICAL: M-mode always bypasses TLB (i_sv32 = satp[31] && priv_mode!=M)
# All Sv32 tests must drop to S-mode via mret to exercise TLB.
# Pattern: M-mode setup → mret to S-mode → S-mode test → ecall → M-mode
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_bare_mode_access
    jal x1, test_run
    la x11, test_sv32_identity_code
    jal x1, test_run
    la x11, test_sv32_identity_data
    jal x1, test_run
    la x11, test_sv32_data_write_read
    jal x1, test_run
    la x11, test_sv32_disable_restore
    jal x1, test_run
    la x11, test_sv32_reenable
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Bare mode access (M-mode, no Sv32) ──
test_bare_mode_access:
    li x10, 0
    csrw satp, x0
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f
    li x10, 1
1:  ret

# ── Sub-test 2: Sv32 identity — code fetch in S-mode ──
test_sv32_identity_code:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)               # clear mmu_return_pc
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_test_identity_code
    csrw mepc, x5
    li x5, 0x880               # MPP=S(01), MPIE=1
    csrw mstatus, x5
    mret

s_test_identity_code:
    li x14, 1                  # reached S-mode → code fetch through TLB works
    la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ── Sub-test 3: Sv32 identity — data read in S-mode ──
test_sv32_identity_data:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_test_identity_data
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_test_identity_data:
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ── Sub-test 4: Sv32 — write and read back in S-mode ──
test_sv32_data_write_read:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_test_write_read
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_test_write_read:
    la x14, test_data_area
    li x15, 0xCAFEBABE
    sw x15, 0(x14)
    lw x16, 0(x14)
    li x17, 0xCAFEBABE
    bne x16, x17, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    li x14, 0xDEADBEEF
    la x15, test_data_area
    sw x14, 0(x15)             # restore original
    ecall

# ── Sub-test 5: Sv32 disable — bare mode restored ──
test_sv32_disable_restore:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    la x5, post_disable_check
    la x6, mmu_return_pc
    sw x5, 0(x6)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_test_disable
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_test_disable:
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall

post_disable_check:
    jal x1, disable_sv32
    la x5, mmu_result
    lw x10, 0(x5)
    beqz x10, 2f
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f
    li x10, 1
    j 2f
1:  li x10, 0
2:  la x5, mmu_saved_ra
    lw x1, 0(x5)
    ret

# ── Sub-test 6: Sv32 re-enable after disable ──
test_sv32_reenable:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    jal x1, disable_sv32
    jal x1, enable_sv32
    la x5, s_test_reenable
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_test_reenable:
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ============================================================
# MMU Trap Handler
# ============================================================
mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval

    li x5, 9
    beq x22, x5, _mth_ecall
    li x5, 8
    beq x22, x5, _mth_ecall

    # Fault: record info, return to M-mode check function
    la x5, mmu_fault_cause
    sw x22, 0(x5)
    la x5, mmu_fault_val
    sw x24, 0(x5)
    li x5, 1
    la x6, mmu_got_fault
    sw x5, 0(x6)
    la x5, mmu_return_pc
    lw x5, 0(x5)
    beqz x5, _mth_fatal_fault
    csrw mepc, x5
    li x5, 0x1888
    csrw mstatus, x5
    la x5, mmu_return_pc
    sw x0, 0(x5)
    mret

_mth_fatal_fault:
    # Unplanned fault: mark FAIL and force-return to M-mode test framework
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5
    li x10, 0
    li x5, 0x1888
    csrw mstatus, x5
    mret

_mth_ecall:
    la x5, mmu_result
    lw x10, 0(x5)
    la x5, mmu_return_pc
    lw x5, 0(x5)
    bnez x5, _mth_ecall_post
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5
    li x5, 0x1888
    csrw mstatus, x5
    mret

_mth_ecall_post:
    csrw mepc, x5
    la x5, mmu_return_pc
    sw x0, 0(x5)
    li x5, 0x1888
    csrw mstatus, x5
    mret

# ============================================================
# Data areas
# ============================================================
.section .text
.balign 4096
test_data_area:
    .word 0xDEADBEEF
    .fill 1023, 4, 0

.balign 4
mmu_saved_ra:    .word 0
mmu_return_pc:   .word 0
mmu_result:      .word 0
mmu_got_fault:   .word 0
mmu_fault_cause: .word 0
mmu_fault_val:   .word 0
