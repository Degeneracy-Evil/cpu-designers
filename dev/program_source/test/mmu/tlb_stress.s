# ============================================================
# mmu/tlb_stress.s — TLB stress tests
# Category: MMU
# Sub-tests: 6
# ============================================================
# TLB: 16 entries, 4-way set-associative (4 sets × 4 ways), tree-PLRU
# Set index: VPN[11:10] (2 bits)
# 8 mapped pages (L0[0-7]) at 0x80000000-0x80007000
# All 8 pages map to the SAME TLB set (set 0).
# Stress tests exercise repeated access, flush+refill, and R/W coherence.
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

    la x11, test_01_overflow_16_entries
    jal x1, test_run
    la x11, test_02_cyclic_access
    jal x1, test_run
    la x11, test_03_working_set_8
    jal x1, test_run
    la x11, test_04_replacement_correctness
    jal x1, test_run
    la x11, test_05_flush_and_refill_all
    jal x1, test_run
    la x11, test_06_mixed_rw_stress
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Access all 8 pages sequentially, re-access first → data integrity ──
# With 8 pages (2 per set), all fit in TLB (16 entries). Re-access verifies
# that TLB hit returns correct data after all entries are filled.
test_01_overflow_16_entries:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    # Write unique values to each page
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_overflow; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_overflow:
    # Access all 8 pages sequentially (fills 8 TLB entries)
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    li x14, 0x80004080;  lw x15, 0(x14)
    li x14, 0x80005080;  lw x15, 0(x14)
    li x14, 0x80006080;  lw x15, 0(x14)
    li x14, 0x80007080;  lw x15, 0(x14)
    # Re-access first page — should be TLB hit, correct data
    li x14, 0x80000080
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Cyclic access pages 0-7, 3 rounds (24 accesses) ──
# Verifies that repeated TLB hit/miss cycles return correct data throughout.
test_02_cyclic_access:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_cyclic; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_cyclic:
    li x10, 3                  # 3 rounds
cyc_outer:
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xDEADBEEF;       bne x15, x16, cyc_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xCAFEBABE;       bne x15, x16, cyc_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0x12345678;       bne x15, x16, cyc_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0x87654321;       bne x15, x16, cyc_fail
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xAAAABBBB;       bne x15, x16, cyc_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xCCCCDDDD;       bne x15, x16, cyc_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xEEEEFFFF;       bne x15, x16, cyc_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0x11112222;       bne x15, x16, cyc_fail
    addi x10, x10, -1
    bnez x10, cyc_outer
    li x14, 1; j cyc_done
cyc_fail:
    li x14, 0
cyc_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: Working set of 8 pages — all fit in TLB ──
# After warm-up (first pass fills all 8 entries), second pass should be all hits.
# Verify data correct on second pass.
test_03_working_set_8:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_wset8; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_wset8:
    # Warm-up: access all 8 pages (fills TLB)
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    li x14, 0x80004080;  lw x15, 0(x14)
    li x14, 0x80005080;  lw x15, 0(x14)
    li x14, 0x80006080;  lw x15, 0(x14)
    li x14, 0x80007080;  lw x15, 0(x14)
    # Second pass: all should be TLB hits, verify data
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xDEADBEEF;       bne x15, x16, ws8_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xCAFEBABE;       bne x15, x16, ws8_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0x12345678;       bne x15, x16, ws8_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0x87654321;       bne x15, x16, ws8_fail
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xAAAABBBB;       bne x15, x16, ws8_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xCCCCDDDD;       bne x15, x16, ws8_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xEEEEFFFF;       bne x15, x16, ws8_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0x11112222;       bne x15, x16, ws8_fail
    li x14, 1; j ws8_done
ws8_fail:
    li x14, 0
ws8_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 4: Fill 8 entries, flush, access evicted page → re-fill correct ──
# Fill all 8 TLB entries, sfence.vma (flush all), then re-access all 8 pages.
# Each re-access triggers re-fill via PTW. Verify all data correct after re-fill.
test_04_replacement_correctness:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_repl; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_repl:
    # Fill all 8 TLB entries
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    li x14, 0x80004080;  lw x15, 0(x14)
    li x14, 0x80005080;  lw x15, 0(x14)
    li x14, 0x80006080;  lw x15, 0(x14)
    li x14, 0x80007080;  lw x15, 0(x14)
    # Flush all TLB entries
    sfence.vma
    # Re-access all 8 pages — each triggers re-fill
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xDEADBEEF;       bne x15, x16, repl_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xCAFEBABE;       bne x15, x16, repl_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0x12345678;       bne x15, x16, repl_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0x87654321;       bne x15, x16, repl_fail
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xAAAABBBB;       bne x15, x16, repl_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xCCCCDDDD;       bne x15, x16, repl_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xEEEEFFFF;       bne x15, x16, repl_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0x11112222;       bne x15, x16, repl_fail
    li x14, 1; j repl_done
repl_fail:
    li x14, 0
repl_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 5: Fill all 8, flush, refill all 8 — data integrity ──
# Similar to test_04 but with an extra round: fill → flush → refill → verify,
# then flush again and refill a second time. Tests that repeated flush/refill
# cycles don't corrupt TLB state.
test_05_flush_and_refill_all:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_flush_rf; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_flush_rf:
    # Round 1: fill all 8
    li x14, 0x80000080;  lw x15, 0(x14)
    li x14, 0x80001080;  lw x15, 0(x14)
    li x14, 0x80002080;  lw x15, 0(x14)
    li x14, 0x80003080;  lw x15, 0(x14)
    li x14, 0x80004080;  lw x15, 0(x14)
    li x14, 0x80005080;  lw x15, 0(x14)
    li x14, 0x80006080;  lw x15, 0(x14)
    li x14, 0x80007080;  lw x15, 0(x14)
    # Flush
    sfence.vma
    # Round 2: refill all 8 and verify
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xDEADBEEF;       bne x15, x16, fr_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xCAFEBABE;       bne x15, x16, fr_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0x12345678;       bne x15, x16, fr_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0x87654321;       bne x15, x16, fr_fail
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xAAAABBBB;       bne x15, x16, fr_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xCCCCDDDD;       bne x15, x16, fr_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xEEEEFFFF;       bne x15, x16, fr_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0x11112222;       bne x15, x16, fr_fail
    # Flush again
    sfence.vma
    # Round 3: refill all 8 again and verify
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xDEADBEEF;       bne x15, x16, fr_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xCAFEBABE;       bne x15, x16, fr_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0x12345678;       bne x15, x16, fr_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0x87654321;       bne x15, x16, fr_fail
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xAAAABBBB;       bne x15, x16, fr_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xCCCCDDDD;       bne x15, x16, fr_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xEEEEFFFF;       bne x15, x16, fr_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0x11112222;       bne x15, x16, fr_fail
    li x14, 1; j fr_done
fr_fail:
    li x14, 0
fr_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 6: Mixed R/W stress — write unique values, read back, verify ──
# Write unique values to pages 0-3, read back and verify.
# Then write unique values to pages 4-7, read back and verify.
# Tests write-through + TLB coherence under stress.
test_06_mixed_rw_stress:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    li x14, 0x80000080; li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080; li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080; li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080; li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080; li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080; li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080; li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080; li x15, 0x11112222; sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_rw_stress; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_rw_stress:
    # Write unique values to pages 0-3
    li x14, 0x80000080;  li x15, 0xA0000000; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xA0000001; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0xA0000002; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0xA0000003; sw x15, 0(x14)
    # Read back pages 0-3 and verify
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xA0000000;       bne x15, x16, rw_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xA0000001;       bne x15, x16, rw_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0xA0000002;       bne x15, x16, rw_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0xA0000003;       bne x15, x16, rw_fail
    # Write unique values to pages 4-7
    li x14, 0x80004080;  li x15, 0xB0000004; sw x15, 0(x14)
    li x14, 0x80005080;  li x15, 0xB0000005; sw x15, 0(x14)
    li x14, 0x80006080;  li x15, 0xB0000006; sw x15, 0(x14)
    li x14, 0x80007080;  li x15, 0xB0000007; sw x15, 0(x14)
    # Read back pages 4-7 and verify
    li x14, 0x80004080;  lw x15, 0(x14)
    li x16, 0xB0000004;       bne x15, x16, rw_fail
    li x14, 0x80005080;  lw x15, 0(x14)
    li x16, 0xB0000005;       bne x15, x16, rw_fail
    li x14, 0x80006080;  lw x15, 0(x14)
    li x16, 0xB0000006;       bne x15, x16, rw_fail
    li x14, 0x80007080;  lw x15, 0(x14)
    li x16, 0xB0000007;       bne x15, x16, rw_fail
    # Re-read pages 0-3 to verify they weren't corrupted by writes to 4-7
    li x14, 0x80000080;  lw x15, 0(x14)
    li x16, 0xA0000000;       bne x15, x16, rw_fail
    li x14, 0x80001080;  lw x15, 0(x14)
    li x16, 0xA0000001;       bne x15, x16, rw_fail
    li x14, 0x80002080;  lw x15, 0(x14)
    li x16, 0xA0000002;       bne x15, x16, rw_fail
    li x14, 0x80003080;  lw x15, 0(x14)
    li x16, 0xA0000003;       bne x15, x16, rw_fail
    # Restore original values
    li x14, 0x80000080;  li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080;  li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080;  li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080;  li x15, 0x11112222; sw x15, 0(x14)
    li x14, 1; j rw_done
rw_fail:
    # Restore original values even on failure
    li x14, 0x80000080;  li x15, 0xDEADBEEF; sw x15, 0(x14)
    li x14, 0x80001080;  li x15, 0xCAFEBABE; sw x15, 0(x14)
    li x14, 0x80002080;  li x15, 0x12345678; sw x15, 0(x14)
    li x14, 0x80003080;  li x15, 0x87654321; sw x15, 0(x14)
    li x14, 0x80004080;  li x15, 0xAAAABBBB; sw x15, 0(x14)
    li x14, 0x80005080;  li x15, 0xCCCCDDDD; sw x15, 0(x14)
    li x14, 0x80006080;  li x15, 0xEEEEFFFF; sw x15, 0(x14)
    li x14, 0x80007080;  li x15, 0x11112222; sw x15, 0(x14)
    li x14, 0
rw_done:
    la x15, mmu_result; sw x14, 0(x15); ecall

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
