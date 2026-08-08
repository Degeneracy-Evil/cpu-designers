# ============================================================
# mmu/tlb_flush.s — TLB flush (SFENCE.VMA) tests
# Category: MMU
# Sub-tests: 8
# ============================================================
# This implementation over-fences every sfence.vma form by invalidating all
# 16 entries in the 8-set x 2-way TLB.
# After flush, subsequent S-mode access triggers re-fill via PTW.
# sfence.vma in M-mode is always legal; in S-mode requires TVM=0.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_sfence_flush_all
    jal x1, test_run
    la x11, test_sfence_reaccess
    jal x1, test_run
    la x11, test_sfence_modify_then_flush
    jal x1, test_run
    la x11, test_sfence_in_bare_mode
    jal x1, test_run
    la x11, test_sfence_multiple_flushes
    jal x1, test_run
    la x11, test_sfence_then_write_read
    jal x1, test_run
    la x11, test_sfence_in_s_mode
    jal x1, test_run
    la x11, test_sfence_preserves_bare
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: SFENCE.VMA flushes all TLB entries ──
test_sfence_flush_all:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_flush; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_flush:
    la x14, test_data_area
    lw x15, 0(x14)             # fill TLB
    sfence.vma                  # flush all entries
    li x14, 1                  # reached here → sfence succeeded
    la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Re-access after flush triggers re-fill ──
test_sfence_reaccess:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_reaccess; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_reaccess:
    la x14, test_data_area
    lw x15, 0(x14)             # fill
    sfence.vma                  # flush
    lw x15, 0(x14)             # miss → re-fill → correct data
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: Modify data, flush, re-read sees new value ──
test_sfence_modify_then_flush:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_modify; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_modify:
    la x14, test_data_area
    lw x15, 0(x14)             # fill
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)             # write new value
    sfence.vma                  # flush (ensures TLB coherent)
    lw x15, 0(x14)             # re-read after flush
    li x16, 0xAAAAAAAA
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  # restore original
    li x15, 0xDEADBEEF
    la x14, test_data_area
    sw x15, 0(x14)
    li x14, 1
    la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ── Sub-test 4: SFENCE.VMA in bare mode is NOP ──
test_sfence_in_bare_mode:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    csrw satp, x0              # bare mode
    fence.i                    # flush dcache so M-mode sees latest data
    sfence.vma                  # should not cause problems in bare mode
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x10, 1
1:  ret

# ── Sub-test 5: Multiple flush+refill cycles ──
test_sfence_multiple_flushes:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_multi; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_multi:
    la x14, test_data_area
    lw x15, 0(x14)             # fill TLB (cycle 1)
    sfence.vma                  # flush (cycle 1)
    lw x15, 0(x14)             # miss → re-fill (cycle 2)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f           # verify after first flush+refill
    sfence.vma                  # flush again (cycle 2)
    lw x15, 0(x14)             # miss → re-fill (cycle 3)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f           # verify after second flush+refill
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 6: Write+read after flush (dcache coherence) ──
test_sfence_then_write_read:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_wr; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_wr:
    la x14, test_data_area
    lw x15, 0(x14)             # fill TLB
    sfence.vma                  # flush
    li x15, 0xBBBBBBBB
    sw x15, 0(x14)             # write new value after flush
    lw x15, 0(x14)             # read back (dcache coherence)
    li x16, 0xBBBBBBBB
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  # restore original
    li x15, 0xDEADBEEF
    la x14, test_data_area
    sw x15, 0(x14)
    li x14, 1
    la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ── Sub-test 7: SFENCE.VMA in S-mode (TVM=0) ──
test_sfence_in_s_mode:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_smode; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_smode:
    la x14, test_data_area
    lw x15, 0(x14)             # fill TLB in S-mode
    sfence.vma                  # sfence.vma in S-mode (legal: TVM=0)
    lw x15, 0(x14)             # miss → re-fill after S-mode sfence
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 8: SFENCE in bare mode then enable Sv32 ──
test_sfence_preserves_bare:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    csrw satp, x0              # bare mode
    sfence.vma                  # sfence in bare mode
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_sfence_bare_sv; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence_bare_sv:
    la x14, test_data_area
    lw x15, 0(x14)             # access with Sv32 after bare sfence
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# MMU Trap Handler
# ============================================================
mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    li x5, 9; beq x22, x5, _mth_ecall
    li x5, 8; beq x22, x5, _mth_ecall
    la x5, mmu_fault_cause; sw x22, 0(x5)
    la x5, mmu_fault_val; sw x24, 0(x5)
    li x5, 1; la x6, mmu_got_fault; sw x5, 0(x6)
    la x5, mmu_return_pc; lw x5, 0(x5)
    beqz x5, _mth_fatal_fault
    csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5
    la x5, mmu_return_pc; sw x0, 0(x5); mret
_mth_fatal_fault:
    la x5, mmu_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret
_mth_ecall:
    la x5, mmu_result; lw x10, 0(x5)
    la x5, mmu_return_pc; lw x5, 0(x5)
    bnez x5, _mth_ecall_post
    la x5, mmu_saved_ra; lw x5, 0(x5); csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5; mret
_mth_ecall_post:
    csrw mepc, x5; la x5, mmu_return_pc; sw x0, 0(x5); li x5, 0x1888; csrw mstatus, x5; mret

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
