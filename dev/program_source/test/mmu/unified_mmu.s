# ============================================================
# mmu/unified_mmu.s — Unified MMU concurrent i/d tests
# Category: MMU
# Sub-tests: 8
# ============================================================
# Tests the Phase 3 unified MMU architecture:
#   - Dual-port TLB (Port A=i-side fetch, Port B=d-side load/store)
#   - Single shared PTW with walk arbiter (d-priority)
#   - Miss queuing (pending_i_walk / pending_d_walk)
#
# Memory layout (32KB SRAM):
#   0x80000000: code (.text.start)       [page 0]
#   0x80001000: L1 page table            [page 1]
#   0x80002000: L0 page table            [page 2]
#   0x80003000: auxiliary code / data    [page 3]
#   0x80004000: data page A              [page 4]
#   0x80005000: data page B              [page 5]
#   0x80006000: data page C              [page 6]
#   0x80007000: TEST_RESULT_BASE         [page 7]
#
# Data values at offset 0x80 within pages to avoid code overlap.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_concurrent_hit
    jal x1, test_run
    la x11, test_02_fresh_sv32_startup
    jal x1, test_run
    la x11, test_03_jump_target_and_data
    jal x1, test_run
    la x11, test_04_dwalk_with_imiss_queued
    jal x1, test_run
    la x11, test_05_back_to_back_misses
    jal x1, test_run
    la x11, test_06_sfence_during_fill
    jal x1, test_run
    la x11, test_07_mixed_rw_across_pages
    jal x1, test_run
    la x11, test_08_stress_loop
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ============================================================
# Sub-test 1: Concurrent i+d hit
# Fill TLB, then in S-mode execute loads from 3 data pages.
# Both i-side (fetch) and d-side (load) hit TLB simultaneously.
# ============================================================
test_01_concurrent_hit:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0x12345678; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_chit; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_chit:
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xDEADBEEF; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xCAFEBABE; bne x15, x16, 1f
    li x14, 0x80006080; lw x15, 0(x14)
    li x16, 0x12345678; bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 2: Fresh Sv32 startup — i-miss then d-miss
# Clean TLB, enable Sv32. First instruction fetch triggers
# i-miss → PTW → fill. Then load triggers d-miss → PTW → fill.
# ============================================================
test_02_fresh_sv32_startup:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0xFACE0002; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_fresh; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_fresh:
    li x14, 0x80004080
    lw x15, 0(x14)
    li x16, 0xFACE0002
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 3: Jump target + data on different pages
# Jump to ummu_aux_code (on page 0, but at a far offset that
# exercises TLB behavior). The jump ensures the i-side continues
# fetching from the correct address. Then load from page 5.
# Verify all data correct.
# ============================================================
test_03_jump_target_and_data:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    la x14, mmu_expected_val
    li x15, 0xBEEF0003; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xBEEF0003; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_jt_main; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_jt_main:
    # Jump to auxiliary code — i-side fetches from new address
    la x14, ummu_aux_code
    jalr x0, x14, 0

# ============================================================
# Sub-test 4: d-walk with i-miss queued
# Load from page 4 (d-walk), meanwhile next instructions also
# fetch from page 0. If i-side misses (new page), queued.
# Verify both loads return correct data.
# ============================================================
test_04_dwalk_with_imiss_queued:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    la x14, mmu_expected_val
    li x15, 0xB0B00004; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xDADA0004; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xB0B00004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_dw_im_main; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_dw_im_main:
    # Load from page 4 (d-walk)
    li x14, 0x80004080
    lw x15, 0(x14)
    li x16, 0xDADA0004
    bne x15, x16, 1f
    # Jump to auxiliary code for second verification
    la x14, ummu_aux_code
    jalr x0, x14, 0
1:  li x14, 0
    la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 5: Back-to-back d-misses on different pages
# ============================================================
test_05_back_to_back_misses:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0xAAA00005; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xBBB00005; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xCCC00005; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_btb; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_btb:
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xAAA00005; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xBBB00005; bne x15, x16, 1f
    li x14, 0x80006080; lw x15, 0(x14)
    li x16, 0xCCC00005; bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 6: sfence.vma during TLB fill sequence
# ============================================================
test_06_sfence_during_fill:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0xDDDD0006; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xEEEE0006; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_sfence; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_sfence:
    li x14, 0x80004080; lw x15, 0(x14)
    li x14, 0x80005080; lw x15, 0(x14)
    sfence.vma
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xDDDD0006; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xEEEE0006; bne x15, x16, 1f
    sfence.vma
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xDDDD0006; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xEEEE0006; bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 7: Mixed R/W across pages
# ============================================================
test_07_mixed_rw_across_pages:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0x11110007; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0x22220007; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0x33330007; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_mixed; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mixed:
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0x11110007; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0x22220007; bne x15, x16, 1f
    li x14, 0x80006080; lw x15, 0(x14)
    li x16, 0x33330007; bne x15, x16, 1f
    li x14, 0x80004080; li x15, 0xAAAA0007; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xBBBB0007; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xCCCC0007; sw x15, 0(x14)
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xAAAA0007; bne x15, x16, 1f
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xBBBB0007; bne x15, x16, 1f
    li x14, 0x80006080; lw x15, 0(x14)
    li x16, 0xCCCC0007; bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Sub-test 8: Stress loop — rapid page switching
# ============================================================
test_08_stress_loop:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    jal x1, setup_identity_map
    li x14, 0x80004080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0x12345678; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_stress; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_stress:
    li x10, 3
stress_outer:
    li x14, 0x80004080; lw x15, 0(x14)
    li x16, 0xDEADBEEF; bne x15, x16, stress_fail
    li x14, 0x80005080; lw x15, 0(x14)
    li x16, 0xCAFEBABE; bne x15, x16, stress_fail
    li x14, 0x80006080; lw x15, 0(x14)
    li x16, 0x12345678; bne x15, x16, stress_fail
    addi x10, x10, -1
    bnez x10, stress_outer
    li x14, 1; j stress_done
stress_fail:
    li x14, 0
stress_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

# ============================================================
# Auxiliary code — jump target for subtest 3 and 4.
# Loads from page 5, compares with mmu_expected_val, sets result.
# ============================================================
ummu_aux_code:
    li x14, 0x80005080
    lw x15, 0(x14)
    la x14, mmu_expected_val
    lw x16, 0(x14)
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
    li x5, 11; beq x22, x5, _mth_ecall
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

# ============================================================
# Data areas
# ============================================================
.section .text
.balign 4
mmu_saved_ra:     .word 0
mmu_return_pc:    .word 0
mmu_result:       .word 0
mmu_got_fault:    .word 0
mmu_fault_cause:  .word 0
mmu_fault_val:    .word 0
mmu_expected_val: .word 0
