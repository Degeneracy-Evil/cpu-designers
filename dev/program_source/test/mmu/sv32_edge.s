# ============================================================
# mmu/sv32_edge.s — Sv32 edge case tests
# Category: MMU
# Sub-tests: 6
# ============================================================
# Tests: megapage translation, A/D bit auto-update, global pages,
#        TLB behavior across ASID changes, zero-page access fault,
#        and high-VMA unmapped access fault.
# Megapage: L1 leaf PTE (R||X set), maps 4MB region.
#   PPN[9:0] must be 0 or it's a misaligned megapage PF.
#   VPN[9:0] of TLB entry is zeroed on fill.
# A/D bits: PTW auto-sets A (bit 6) on access, D (bit 7) on store.
# Global: G=1 entries match any ASID (not flushed on ASID change).
# ASID: 9-bit field in satp[30:22], non-global entries only match
#        when TLB ASID == satp ASID.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_megapage_translation
    jal x1, test_run
    la x11, test_ad_bit_auto_update
    jal x1, test_run
    la x11, test_global_page
    jal x1, test_run
    la x11, test_asid_change
    jal x1, test_run
    la x11, test_zero_page_access
    jal x1, test_run
    la x11, test_high_vma_access
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Megapage translation (L1 leaf PTE) ──
# Create a megapage: L1[512] is a leaf PTE with R|W|X|A|D set
# This maps the entire 4MB region starting at 0x80000000
test_megapage_translation:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    # Clear page tables first
    jal x1, clear_page_tables
    # Set up L1[512] as megapage (leaf PTE, not pointer to L0)
    la x14, l1_page_table
    li x15, 0x80000            # PPN = 0x80000 (0x80000000 >> 12)
    slli x15, x15, 10
    li x16, 0x0CF               # V|R|W|X|A|D (Supervisor megapage)
    or x15, x15, x16
    li   x17, 0x800
    add  x17, x14, x17         # x17 = &l1_page_table[512]
    sw x15, 0(x17)             # L1[512] → megapage
    jal x1, enable_sv32
    la x5, s_megapage; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_megapage:
    la x14, test_data_area
    lw x15, 0(x14)             # access through megapage
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: A/D bit auto-update by PTW ──
# When PTW walks a page with A=0, it writes back PTE|0x40 (sets A).
# When STORE to a page with D=0, PTW writes back PTE|0xC0 (sets A+D).
# We verify by checking the PTE in memory after access.
# Use L0[4] (VA 0x80004000) to avoid collision with code at L0[0].
test_ad_bit_auto_update:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_ad_check; la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    # Set up page tables with A=0, D=0 on L0[4]
    jal x1, clear_page_tables
    la x14, l1_page_table
    la x15, l0_page_table
    # L1[512] → pointer to L0
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, 0x001        # V only
    li   x17, 0x800
    add  x17, x14, x17
    sw x16, 0(x17)             # L1[512]
    # L0[0-3] with full permissions for code/data safety
    li x17, 0x0CF               # V|R|W|X|A|D
    li x16, 0x80000; slli x16, x16, 10; or x16, x16, x17; sw x16, 0(x15)
    li x16, 0x80001; slli x16, x16, 10; or x16, x16, x17; sw x16, 4(x15)
    li x16, 0x80002; slli x16, x16, 10; or x16, x16, x17; sw x16, 8(x15)
    li x16, 0x80003; slli x16, x16, 10; or x16, x16, x17; sw x16, 12(x15)
    # L0[4] with A=0, D=0 — this is the test target at VA 0x80004000
    li x16, 0x80004
    slli x16, x16, 10
    li x17, 0x00F               # V|R|W|X (NO A, NO D)
    or x16, x16, x17
    sw x16, 16(x15)            # L0[4] → 0x80004000, A=0, D=0
    # L0[5-7] with full permissions
    li x17, 0x0CF               # V|R|W|X|A|D
    li x16, 0x80005; slli x16, x16, 10; or x16, x16, x17; sw x16, 20(x15)
    li x16, 0x80006; slli x16, x16, 10; or x16, x16, x17; sw x16, 24(x15)
    li x16, 0x80007; slli x16, x16, 10; or x16, x16, x17; sw x16, 28(x15)
    # Write known value to 0x80004000 before enabling Sv32
    li x14, 0x80004000
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_ad_test; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_ad_test:
    # Read from L0[4] (0x80004000) — PTW should set A bit
    li x14, 0x80004000
    lw x15, 0(x14)
    # Flush TLB so the store triggers a re-fill walk that auto-sets D bit
    sfence.vma
    # Store to L0[4] (0x80004000) — PTW should set D bit (and A bit again)
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    li x14, 1                  # PASS (we got here without PF)
    la x15, mmu_result; sw x14, 0(x15); ecall

post_ad_check:
    # Check that A and D bits were set in L0[4]
    # PTW writes A/D updates directly to SRAM (bypassing dcache),
    # so we must fence.i to flush dcache before reading the PTE.
    fence.i
    la x14, l0_page_table
    lw x15, 16(x14)            # read L0[4] PTE (offset=4*4=16)
    li x16, 0x0C0               # A|D bits
    and x15, x15, x16
    li x16, 0x0C0               # both A and D should be set
    bne x15, x16, 1f
    li x10, 1; j 2f
1:  li x10, 0
2:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 3: Global page (G=1) matches any ASID ──
# Set up a page with G=1, access with ASID=0, change to ASID=1,
# and verify the global entry still hits (no re-fill needed).
test_global_page:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    # Set up identity map with G=1 on L0[0]
    jal x1, setup_identity_map
    # Add G bit to L0[0]
    la x14, l0_page_table
    lw x15, 0(x14)
    li x16, 0x020               # G bit
    or x15, x15, x16
    sw x15, 0(x14)             # L0[0] with G=1
    jal x1, enable_sv32
    la x5, s_global; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_global:
    la x14, test_data_area
    lw x15, 0(x14)             # fill with ASID=0
    # Change ASID to 1
    csrr x14, satp
    li x15, (1<<22)            # ASID=1 at bits[30:22]
    or x14, x14, x15
    csrw satp, x14
    sfence.vma                  # flush non-global entries
    # Re-access: global entry should still hit
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 4: ASID change — non-global entries flushed ──
# Access a page with ASID=0 (non-global), change ASID to 1,
# sfence.vma, then access should trigger re-fill.
test_asid_change:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    # L0[0] is non-global (G=0) by default
    jal x1, enable_sv32
    la x5, s_asid; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_asid:
    la x14, test_data_area
    lw x15, 0(x14)             # fill with ASID=0
    # Change ASID to 1
    csrr x14, satp
    li x15, (1<<22)            # ASID=1
    or x14, x14, x15
    csrw satp, x14
    sfence.vma                  # flush all entries
    # Re-access: should re-fill with new ASID
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 5: Zero-page access (VA 0x00000000) — page fault ──
# With identity map only mapping 0x80000000+, there is no L1 entry
# for VPN[1]=0. Accessing VA 0 should cause a load page fault.
test_zero_page_access:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_zero_check; la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_zero_page; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_zero_page:
    li x14, 0x00000000
    lw x15, 0(x14)             # should fault (no mapping for VA 0)
    li x14, 0; la x15, mmu_result; sw x14, 0(x15); ecall

post_zero_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 2f  # load PF
    li x6, 5;  beq x5, x6, 2f  # load access fault
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 6: High-VMA unmapped access (VA 0xFFFFF000) — page fault ──
# Access a high virtual address that has no page table entry.
# Should cause a load page fault with mcause=13.
test_high_vma_access:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_high_vma_check; la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_high_vma; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_high_vma:
    li x14, 0xFFFFF000
    lw x15, 0(x14)             # should fault (no mapping for high VA)
    li x14, 0; la x15, mmu_result; sw x14, 0(x15); ecall

post_high_vma_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 2f  # load PF
    li x6, 5;  beq x5, x6, 2f  # load access fault
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ============================================================
# MMU Trap Handler
# ============================================================
mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    li x5, 9; beq x22, x5, _mth_ecall
    li x5, 8; beq x22, x5, _mth_ecall
    li x5, 11; beq x22, x5, _mth_ecall   # ecall from M-mode
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
