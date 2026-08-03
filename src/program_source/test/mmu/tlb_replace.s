# ============================================================
# mmu/tlb_replace.s — TLB replacement (tree-PLRU) tests
# Category: MMU
# Sub-tests: 6
# ============================================================
# TLB: 16 entries, 4-way set-associative (4 sets × 4 ways), tree-PLRU
# Set index: VPN[11:10] (2 bits)
#
# All mapped pages (0x80000000-0x80007000, L0[0-7]) map to
# the SAME TLB set (set 0) because VPN[11:10] = VA[23:22] = 0b00.
# With 4 ways per set, accessing 5+ different pages triggers
# tree-PLRU replacement.
#
# IMPORTANT: Pages 0-1 contain code, pages 2-3 contain page tables,
# page 4 has data variables (up to offset 0xEB4). Test data must
# use offset 0xF00 (past all code/data) to avoid overwriting them.
# We use 6 safe pages at offset 0xF00:
#   A=0x80000F00 (page 0)  B=0x80001F00 (page 1)
#   C=0x80004F00 (page 4)  D=0x80005F00 (page 5)
#   E=0x80006F00 (page 6)  F=0x80007F00 (page 7)
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
# Write unique values to pages A-E, then in S-mode:
# Fill pages A-D (fills ways 0-3, all invalid), then access page E.
# Page E → TLB miss → all ways valid → PLRU victim replacement.
# Verify page E data is correct after replacement fill.
test_01_fill_4_then_5th_replaces:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    # Write unique values to each safe page (offset 0xF00)
    li x14, 0x80000F00;  li x15, 0xA0000000; sw x15, 0(x14)  # page A
    li x14, 0x80001F00;  li x15, 0xA0000001; sw x15, 0(x14)  # page B
    li x14, 0x80004F00;  li x15, 0xA0000002; sw x15, 0(x14)  # page C
    li x14, 0x80005F00;  li x15, 0xA0000003; sw x15, 0(x14)  # page D
    li x14, 0x80006F00;  li x15, 0xA0000004; sw x15, 0(x14)  # page E
    jal x1, enable_sv32
    la x5, s_replace_5th; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_replace_5th:
    # Fill ways 0-3 with pages A-D
    li x14, 0x80000F00;  lw x15, 0(x14)   # page A → way 0
    li x14, 0x80001F00;  lw x15, 0(x14)   # page B → way 1
    li x14, 0x80004F00;  lw x15, 0(x14)   # page C → way 2
    li x14, 0x80005F00;  lw x15, 0(x14)   # page D → way 3
    # 5th page → replacement (PLRU victim = way 0 after filling 0,1,2,3)
    li x14, 0x80006F00;  lw x15, 0(x14)   # page E → replaces way 0
    li x16, 0xA0000004
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Re-access evicted page triggers re-fill ──
# After replacement evicts page A, re-access page A → TLB miss →
# re-fill (replaces another way). Verify page A data correct.
test_02_evicted_page_refill:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000F00;  li x15, 0xB0000000; sw x15, 0(x14)
    li x14, 0x80001F00;  li x15, 0xB0000001; sw x15, 0(x14)
    li x14, 0x80004F00;  li x15, 0xB0000002; sw x15, 0(x14)
    li x14, 0x80005F00;  li x15, 0xB0000003; sw x15, 0(x14)
    li x14, 0x80006F00;  li x15, 0xB0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_evicted_refill; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_evicted_refill:
    # Fill all 4 ways
    li x14, 0x80000F00;  lw x15, 0(x14)   # page A → way 0
    li x14, 0x80001F00;  lw x15, 0(x14)   # page B → way 1
    li x14, 0x80004F00;  lw x15, 0(x14)   # page C → way 2
    li x14, 0x80005F00;  lw x15, 0(x14)   # page D → way 3
    # Trigger replacement: page E evicts way 0 (page A)
    li x14, 0x80006F00;  lw x15, 0(x14)
    # Re-access evicted page A → miss → re-fill
    li x14, 0x80000F00;  lw x15, 0(x14)
    li x16, 0xB0000000
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: Sequential replacement — 2 replacements in a row ──
# Fill pages A-D, then access pages E,F in sequence.
# Each access after the 4th triggers a replacement.
# Verify both new pages have correct data after sequential replacement.
test_03_sequential_replacement:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000F00;  li x15, 0xC0000000; sw x15, 0(x14)
    li x14, 0x80001F00;  li x15, 0xC0000001; sw x15, 0(x14)
    li x14, 0x80004F00;  li x15, 0xC0000002; sw x15, 0(x14)
    li x14, 0x80005F00;  li x15, 0xC0000003; sw x15, 0(x14)
    li x14, 0x80006F00;  li x15, 0xC0000004; sw x15, 0(x14)
    li x14, 0x80007F00;  li x15, 0xC0000005; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_seq_replace; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_seq_replace:
    # Fill all 4 ways with pages A-D
    li x14, 0x80000F00;  lw x15, 0(x14)
    li x14, 0x80001F00;  lw x15, 0(x14)
    li x14, 0x80004F00;  lw x15, 0(x14)
    li x14, 0x80005F00;  lw x15, 0(x14)
    # Sequential replacement: pages E,F replace 2 ways
    li x14, 0x80006F00;  lw x15, 0(x14)   # replacement 1
    li x14, 0x80007F00;  lw x15, 0(x14)   # replacement 2
    # Verify both new pages have correct data
    li x14, 0x80006F00;  lw x15, 0(x14)
    li x16, 0xC0000004;  bne x15, x16, 1f
    li x14, 0x80007F00;  lw x15, 0(x14)
    li x16, 0xC0000005;  bne x15, x16, 1f
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
    li x14, 0x80000F00;  li x15, 0xD0000000; sw x15, 0(x14)
    li x14, 0x80001F00;  li x15, 0xD0000001; sw x15, 0(x14)
    li x14, 0x80004F00;  li x15, 0xD0000002; sw x15, 0(x14)
    li x14, 0x80005F00;  li x15, 0xD0000003; sw x15, 0(x14)
    li x14, 0x80006F00;  li x15, 0xD0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_replace_flush; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_replace_flush:
    # Fill all 4 ways
    li x14, 0x80000F00;  lw x15, 0(x14)
    li x14, 0x80001F00;  lw x15, 0(x14)
    li x14, 0x80004F00;  lw x15, 0(x14)
    li x14, 0x80005F00;  lw x15, 0(x14)
    # Flush TLB
    sfence.vma
    # Re-fill 4 ways (reuse C,D after flush + new E,F)
    li x14, 0x80004F00;  lw x15, 0(x14)   # page C → way 0
    li x14, 0x80005F00;  lw x15, 0(x14)   # page D → way 1
    li x14, 0x80006F00;  lw x15, 0(x14)   # page E → way 2
    li x14, 0x80007F00;  lw x15, 0(x14)   # page F → way 3
    # 5th access → replacement
    li x14, 0x80000F00;  lw x15, 0(x14)   # page A → replaces PLRU victim
    li x16, 0xD0000000
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 5: Write to replaced page, read back ──
# Fill 4 ways, trigger replacement with page E, write unique value
# to page E, read back. Verify write/read coherence after replacement.
test_05_write_after_replace:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000F00;  li x15, 0xE0000000; sw x15, 0(x14)
    li x14, 0x80001F00;  li x15, 0xE0000001; sw x15, 0(x14)
    li x14, 0x80004F00;  li x15, 0xE0000002; sw x15, 0(x14)
    li x14, 0x80005F00;  li x15, 0xE0000003; sw x15, 0(x14)
    li x14, 0x80006F00;  li x15, 0xE0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_write_replace; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_write_replace:
    # Fill all 4 ways
    li x14, 0x80000F00;  lw x15, 0(x14)
    li x14, 0x80001F00;  lw x15, 0(x14)
    li x14, 0x80004F00;  lw x15, 0(x14)
    li x14, 0x80005F00;  lw x15, 0(x14)
    # Trigger replacement with page E
    li x14, 0x80006F00;  lw x15, 0(x14)
    # Write unique value to replaced page
    li x14, 0x80006F00
    li x15, 0x5678ABCD
    sw x15, 0(x14)
    # Read back
    li x14, 0x80006F00
    lw x15, 0(x14)
    li x16, 0x5678ABCD
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 6: Non-evicted entries still hit after replacement ──
# Fill pages A-D, trigger replacement (evicts one way),
# then access pages that were NOT evicted → should be TLB hit.
# Verify data correct (functional check: correct data returned).
test_06_non_evicted_hit:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000F00;  li x15, 0xF0000000; sw x15, 0(x14)
    li x14, 0x80001F00;  li x15, 0xF0000001; sw x15, 0(x14)
    li x14, 0x80004F00;  li x15, 0xF0000002; sw x15, 0(x14)
    li x14, 0x80005F00;  li x15, 0xF0000003; sw x15, 0(x14)
    li x14, 0x80006F00;  li x15, 0xF0000004; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_non_evicted; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_non_evicted:
    # Fill all 4 ways with pages A-D
    li x14, 0x80000F00;  lw x15, 0(x14)   # page A → way 0
    li x14, 0x80001F00;  lw x15, 0(x14)   # page B → way 1
    li x14, 0x80004F00;  lw x15, 0(x14)   # page C → way 2
    li x14, 0x80005F00;  lw x15, 0(x14)   # page D → way 3
    # Trigger replacement: page E evicts way 0 (page A)
    li x14, 0x80006F00;  lw x15, 0(x14)
    # Access page B (way 1, NOT evicted) → should be TLB hit
    li x14, 0x80001F00;  lw x15, 0(x14)
    li x16, 0xF0000001
    bne x15, x16, 1f
    # Access page C (way 2, NOT evicted) → should be TLB hit
    li x14, 0x80004F00;  lw x15, 0(x14)
    li x16, 0xF0000002
    bne x15, x16, 1f
    # Access page D (way 3, NOT evicted) → should be TLB hit
    li x14, 0x80005F00;  lw x15, 0(x14)
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
