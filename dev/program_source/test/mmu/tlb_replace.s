# ============================================================
# mmu/tlb_replace.s — TLB replacement (tree-PLRU) tests
# Category: MMU
# Sub-tests: 6
# ============================================================
# TLB: 16 entries, 4-way set-associative (4 sets × 4 ways), tree-PLRU
# Set index: VPN[11:10] (2 bits)
#
# All 8 mapped pages (0x80000000-0x80007000, L0[0-7]) map to
# the SAME TLB set (set 0) because VPN[11:10] = VA[23:22] = 0b00.
# With 4 ways per set, accessing 5+ different pages triggers
# tree-PLRU replacement.
#
# Fill priority: invalid ways first (0→1→2→3), then PLRU victim.
# After all 4 ways valid, 5th access evicts PLRU victim way.
#
# Data strategy: write unique values to specific addresses in each
# page (offset 0x80 within each 4KB page to avoid code/page tables),
# then read back to verify TLB behavior.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_fill_4_then_5th_replaces
    jal x1, test_run
    la x11, test_02_evicted_page_refill
    jal x1, test_run
    la x11, test_03_sequential_replacement
    jal x1, test_run
    la x11, test_04_replace_after_flush
    jal x1, test_run
    la x11, test_05_write_after_replace
    jal x1, test_run
    la x11, test_06_non_evicted_hit
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Fill 4 ways, then 5th page triggers replacement ──
# Write unique values to pages 0-4, then in S-mode:
# Fill pages 0-3 (fills ways 0-3, all invalid), then access page 4.
# Page 4 → TLB miss → all ways valid → PLRU victim replacement.
# Verify page 4 data is correct after replacement fill.
test_01_fill_4_then_5th_replaces:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    # Write unique values to each page (offset 0x80 to avoid code/pt)
    li x14, 0x80000080;  li x15, 0xA0000000; sw x15, 0(x14)  # page 0
    li x14, 0x80001080;  li x15, 0xA0000001; sw x15, 0(x14)  # page 1
    li x14, 0x80002080;  li x15, 0xA0000002; sw x15, 0(x14)  # page 2
    li x14, 0x80003080;  li x15, 0xA0000003; sw x15, 0(x14)  # page 3
    li x14, 0x80004080;  li x15, 0xA0000004; sw x15, 0(x14)  # page 4
    jal x1, enable_sv32
    la x5, s_replace_5th; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_replace_5th:
    # Fill ways 0-3 with pages 0-3
    li x14, 0x80000080;  lw x15, 0(x14)   # page 0 → way 0
    li x14, 0x80001080;  lw x15, 0(x14)   # page 1 → way 1
    li x14, 0x80002080;  lw x15, 0(x14)   # page 2 → way 2
    li x14, 0x80003080;  lw x15, 0(x14)   # page 3 → way 3
    # 5th page → replacement (PLRU victim = way 0 after filling 0,1,2,3)
    li x14, 0x80004080;  lw x15, 0(x14)   # page 4 → replaces way 0
    li x16, 0xA0000004
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Re-access evicted page triggers re-fill ──
# After replacement evicts page 0, re-access page 0 → TLB miss →
# re-fill (replaces another way). Verify page 0 data correct.
test_02_evicted_page_refill:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080;  li x15, 0xB0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xB0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xB0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xB0000003; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xB0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_evicted_refill; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_evicted_refill:
    # Fill all 4 ways
    li x14, 0x80000080;  lw x15, 0(x14)   # page 0 → way 0
    li x14, 0x80001080;  lw x15, 0(x14)   # page 1 → way 1
    li x14, 0x80002080;  lw x15, 0(x14)   # page 2 → way 2
    li x14, 0x80003080;  lw x15, 0(x14)   # page 3 → way 3
    # Trigger replacement: page 4 evicts way 0 (page 0)
    li x14, 0x80004080;  lw x15, 0(x14)
    # Re-access evicted page 0 → miss → re-fill
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xB0000000
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: Sequential replacement — 4 replacements in a row ──
# Fill pages 0-3, then access pages 4,5,6,7 in sequence.
# Each access after the 4th triggers a replacement.
# Verify all 4 new pages have correct data after sequential replacement.
test_03_sequential_replacement:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080;  li x15, 0xC0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xC0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xC0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xC0000003; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xC0000004; sw x15, 0(x14)
    li x14, 0x80005080;  li x15, 0xC0000005; sw x15, 0(x14)
    li x14, 0x80006080;  li x15, 0xC0000006; sw x15, 0(x14)
    li x14, 0x80007080;  li x15, 0xC0000007; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_seq_replace; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_seq_replace:
    # Fill all 4 ways with pages 0-3
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    # Sequential replacement: pages 4-7 replace 4 ways
    li x14, 0x80004080;  lw x15, 0(x14)   # replacement 1
    li x14, 0x80005080;  lw x15, 0(x14)   # replacement 2
    li x14, 0x80006080;  lw x15, 0(x14)   # replacement 3
    li x14, 0x80007080;  lw x15, 0(x14)   # replacement 4
    # Verify all 4 new pages have correct data
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xC0000004;  bne x15, x16, 1f
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xC0000005;  bne x15, x16, 1f
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xC0000006;  bne x15, x16, 1f
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0xC0000007;  bne x15, x16, 1f
    li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 4: Replacement after TLB flush ──
# Fill 4 pages, flush TLB, re-fill 4 pages (different set),
# then access 5th page → replacement. Verify correct behavior
# after flush+refill cycle.
test_04_replace_after_flush:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080;  li x15, 0xD0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xD0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xD0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xD0000003; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xD0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_replace_flush; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_replace_flush:
    # Fill all 4 ways
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    # Flush TLB
    sfence.vma
    # Re-fill 4 ways (different pages)
    li x14, 0x80004080;  lw x15, 0(x14)   # page 4 → way 0
    li x14, 0x80005080;  lw x15, 0(x14)   # page 5 → way 1
    li x14, 0x80006080;  lw x15, 0(x14)   # page 6 → way 2
    li x14, 0x80007080;  lw x15, 0(x14)   # page 7 → way 3
    # 5th access → replacement
    li x14, 0x80000080;  lw x15, 0(x14)   # page 0 → replaces PLRU victim
    li x16, 0xD0000000
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 5: Write to replaced page, read back ──
# Fill 4 ways, trigger replacement with page 4, write unique value
# to page 4, read back. Verify write/read coherence after replacement.
test_05_write_after_replace:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080;  li x15, 0xE0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xE0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xE0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xE0000003; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xE0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_write_replace; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_write_replace:
    # Fill all 4 ways
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    # Trigger replacement with page 4
    li x14, 0x80004080;  lw x15, 0(x14)
    # Write unique value to replaced page
    li x14, 0x80004080
    li x15, 0x5678ABCD
    sw x15, 0(x14)
    # Read back
    li x14, 0x80004080
    lw x15, 0(x14)
    li x16, 0x5678ABCD
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 6: Non-evicted entries still hit after replacement ──
# Fill pages 0-3, trigger replacement (evicts one way),
# then access pages that were NOT evicted → should be TLB hit.
# Verify data correct (functional check: correct data returned).
test_06_non_evicted_hit:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080;  li x15, 0xF0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xF0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xF0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xF0000003; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xF0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_non_evicted; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_non_evicted:
    # Fill all 4 ways with pages 0-3
    li x14, 0x80000080;  lw x15, 0(x14)   # page 0 → way 0
    li x14, 0x80001080;  lw x15, 0(x14)   # page 1 → way 1
    li x14, 0x80002080;  lw x15, 0(x14)   # page 2 → way 2
    li x14, 0x80003080;  lw x15, 0(x14)   # page 3 → way 3
    # Trigger replacement: page 4 evicts way 0 (page 0)
    li x14, 0x80004080;  lw x15, 0(x14)
    # Access page 1 (way 1, NOT evicted) → should be TLB hit
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xF0000001
    bne x15, x16, 1f
    # Access page 2 (way 2, NOT evicted) → should be TLB hit
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0xF0000002
    bne x15, x16, 1f
    # Access page 3 (way 3, NOT evicted) → should be TLB hit
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0xF0000003
    bne x15, x16, 1f
    li x14, 1; j 2f
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

# ============================================================
# Data areas (minimal — just trap handler state)
# ============================================================
.section .text
.balign 4
mmu_saved_ra:    .word 0
mmu_return_pc:   .word 0
mmu_result:      .word 0
mmu_got_fault:   .word 0
mmu_fault_cause: .word 0
mmu_fault_val:   .word 0
