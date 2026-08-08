# ============================================================
# mmu/tlb_basic.s — TLB basic operation tests
# Category: MMU
# Sub-tests: 12
# ============================================================
# TLB: 16 entries, 2-way set-associative (8 sets × 2 ways), register arrays
# Set index: VPN[12:10] (3 bits; excludes a megapage's VPN[9:0])
# After enable_sv32 (which includes sfence.vma), TLB is empty.
# First S-mode access → TLB miss → PTW → fill → data returned.
# Second access to same page → TLB hit.
# Access to different page → TLB miss → fill.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_tlb_fill_first_access
    jal x1, test_run
    la x11, test_tlb_hit_same_page
    jal x1, test_run
    la x11, test_tlb_miss_different_page
    jal x1, test_run
    la x11, test_tlb_fill_multiple_pages
    jal x1, test_run
    la x11, test_tlb_hit_after_fill
    jal x1, test_run
    la x11, test_tlb_bare_to_sv32
    jal x1, test_run
    la x11, test_07_fill_after_flush
    jal x1, test_run
    la x11, test_08_hit_across_pages
    jal x1, test_run
    la x11, test_09_miss_new_set
    jal x1, test_run
    la x11, test_10_multiple_miss_sequence
    jal x1, test_run
    la x11, test_11_write_then_read_hit
    jal x1, test_run
    la x11, test_12_bare_mode_passthrough
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: TLB fill — first access after enabling Sv32 ──
test_tlb_fill_first_access:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_fill; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_fill:
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: TLB hit — second access to same page ──
test_tlb_hit_same_page:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_hit; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_hit:
    la x14, test_data_area
    lw x15, 0(x14)             # first access (fill)
    lw x16, 0(x14)             # second access (hit)
    li x17, 0xDEADBEEF
    bne x16, x17, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: TLB miss — access different 4KB page ──
test_tlb_miss_different_page:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_miss; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_miss:
    la x14, test_data_area
    lw x15, 0(x14)             # page 0 (fill)
    la x14, test_data_area2
    lw x15, 0(x14)             # page 1 (miss → fill)
    li x16, 0xCAFEBABE
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 4: TLB fill — multiple pages accessible ──
test_tlb_fill_multiple_pages:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_multi; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_multi:
    la x14, test_data_area
    lw x15, 0(x14)
    la x14, test_data_area2
    lw x16, 0(x14)
    li x14, 0xDEADBEEF
    bne x15, x14, 1f
    li x14, 0xCAFEBABE
    bne x16, x14, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 5: TLB hit — repeat access after multiple fills ──
test_tlb_hit_after_fill:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_hit2; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_hit2:
    la x14, test_data_area
    lw x15, 0(x14)             # fill page 0
    la x14, test_data_area2
    lw x16, 0(x14)             # fill page 1
    la x14, test_data_area
    lw x15, 0(x14)             # hit page 0 (still in TLB)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 6: Bare→Sv32 transition ──
test_tlb_bare_to_sv32:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    csrw satp, x0              # bare mode
    la x14, test_data_area
    lw x15, 0(x14)             # access in bare mode
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_transition; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_transition:
    la x14, test_data_area
    lw x16, 0(x14)             # access through TLB
    li x17, 0xDEADBEEF
    bne x16, x17, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 7: TLB re-fill after flush ──
test_07_fill_after_flush:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_fill_flush; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_fill_flush:
    la x14, test_data_area
    lw x15, 0(x14)             # first access (fill)
    sfence.vma                 # flush entire TLB
    la x14, test_data_area
    lw x15, 0(x14)             # re-fill after flush
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 8: TLB hit across page boundary ──
test_08_hit_across_pages:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_hit_cross; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_hit_cross:
    la x14, test_data_area
    lw x15, 0(x14)             # fill page 0
    la x14, test_data_area2
    lw x16, 0(x14)             # fill page 1
    la x14, test_data_area
    lw x17, 0(x14)             # hit page 0 (still in TLB)
    li x14, 0xDEADBEEF
    bne x17, x14, 1f           # verify page 0 hit data
    la x14, test_data_area2
    lw x17, 0(x14)             # hit page 1 (still in TLB)
    li x14, 0xCAFEBABE
    bne x17, x14, 1f           # verify page 1 hit data
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 9: TLB miss in different sets ──
test_09_miss_new_set:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_new_set; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_new_set:
    li x14, 0x80005000         # set 1 (safe: above page tables+data)
    li x15, 0xAAAA0000
    sw x15, 0(x14)             # write to set 1 page (fill)
    li x14, 0x80006000         # set 2 (safe: above page tables+data)
    li x15, 0xBBBB0000
    sw x15, 0(x14)             # write to set 2 page (fill)
    li x14, 0x80005000
    lw x15, 0(x14)             # read set 1 (hit)
    li x16, 0xAAAA0000
    bne x15, x16, 1f
    li x14, 0x80006000
    lw x15, 0(x14)             # read set 2 (hit)
    li x16, 0xBBBB0000
    bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 10: Multiple TLB miss in sequence ──
test_10_multiple_miss_sequence:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_multi_miss; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_multi_miss:
    li x14, 0x80005000
    li x15, 0x11110000
    sw x15, 0(x14)             # page 5 fill (set 1)
    li x14, 0x80006000
    li x15, 0x22220000
    sw x15, 0(x14)             # page 6 fill (set 2)
    li x14, 0x80003000
    li x15, 0x33330000
    sw x15, 0(x14)             # page 3 fill (set 3)
    li x14, 0x80004000
    li x15, 0x44440000
    sw x15, 0(x14)             # page 4 fill (set 0)
    li x14, 0x80005000
    lw x15, 0(x14)
    li x16, 0x11110000
    bne x15, x16, 1f
    li x14, 0x80006000
    lw x15, 0(x14)
    li x16, 0x22220000
    bne x15, x16, 1f
    li x14, 0x80003000
    lw x15, 0(x14)
    li x16, 0x33330000
    bne x15, x16, 1f
    li x14, 0x80004000
    lw x15, 0(x14)
    li x16, 0x44440000
    bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 11: Write then read hit ──
test_11_write_then_read_hit:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_tlb_wr_hit; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_tlb_wr_hit:
    la x14, test_data_area
    li x15, 0x12345678
    sw x15, 0(x14)             # write (fill TLB for this page)
    la x14, test_data_area
    lw x15, 0(x14)             # read (hit)
    li x16, 0x12345678
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 12: Bare mode passthrough ──
test_12_bare_mode_passthrough:
    csrw satp, x0
    la x14, test_data_area
    li x15, 0xDEADBEEF
    sw x15, 0(x14)             # restore original value
    lw x15, 0(x14)             # read back in bare mode
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x10, 1; j 2f
1:  li x10, 0
2:  ret

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

# ============================================================
# Data areas (2 page-aligned regions for multi-page testing)
# Reduced from 1023 fill words to 1 to avoid SRAM overflow
# ============================================================
.section .text
.balign 4096
test_data_area:
    .word 0xDEADBEEF
    .word 0

.balign 4096
test_data_area2:
    .word 0xCAFEBABE
    .word 0

.balign 4
mmu_saved_ra:    .word 0
mmu_return_pc:   .word 0
mmu_result:      .word 0
mmu_got_fault:   .word 0
mmu_fault_cause: .word 0
mmu_fault_val:   .word 0
