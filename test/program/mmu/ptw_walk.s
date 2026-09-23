# ============================================================
# mmu/ptw_walk.s — Page Table Walker (PTW) tests
# Category: MMU
# Sub-tests: 4
# ============================================================
# PTW FSM: S_IDLE → S_L1_READ → S_L1_CHECK → S_L0_READ →
#          S_L0_CHECK → S_PERM_CHECK → S_AD_UPDATE → S_AD_WAIT →
#          S_DONE / S_FAULT
#
# L1 PTE addr: {satp.PPN[19:0], 12'b0} + {20'b0, VPN[1], 2'b0}
#   VPN[1] = vaddr[31:22]
# L0 PTE addr: {PTE.PPN[19:0], 12'b0} + {20'b0, VPN[0], 2'b0}
#   VPN[0] = vaddr[21:12]
#
# Leaf detection: PTE.R || PTE.X (either set → leaf)
# Reserved check: !PTE.R && PTE.W (W=1,R=0 → fault)
# Page fault causes: 12=fetch PF, 13=load PF, 15=store PF
# Access fault causes: 5=load access fault, 7=store access fault
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_two_level_walk
    jal x1, test_run
    la x11, test_02_invalid_pte_v0
    jal x1, test_run
    la x11, test_03_reserved_pte_w1_r0
    jal x1, test_run
    la x11, test_04_non_leaf_pte_no_execute
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Two-level page table walk (L1→L0→PTE) ──
# Set up proper 2-level page table. Access a page that requires
# both L1 and L0 walk. Verify correct data returned.
test_01_two_level_walk:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    # Build identity map from scratch (L1[512]→L0, L0[0-7] identity)
    jal x1, setup_identity_map
    # Write known value to 0x80004000 before enabling Sv32
    li x14, 0x80004000
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_two_level; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_two_level:
    li x14, 0x80004000
    lw x15, 0(x14)             # PTW walks L1→L0, should return data
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Invalid PTE with V=0 at L0 ──
# Set up page table where L0 PTE has V=0 (invalid).
# Access the page → should get load page fault.
# Verify mcause=13 (load PF) or mcause=5 (load access fault).
test_02_invalid_pte_v0:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_v0_check; la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    # Invalidate L0[4] (VA 0x80004000): set V=0
    la x14, l0_page_table
    sw x0, 16(x14)            # L0[4] = 0 (V=0, invalid)
    fence.i                     # flush dcache so PTW sees updated PTE
    sfence.vma                  # flush TLB so next access re-walks
    la x5, s_v0_fault; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_v0_fault:
    li x14, 0x80004000
    lw x15, 0(x14)             # should trigger load PF (V=0)
    li x14, 0                  # no fault → FAIL
    la x15, mmu_result; sw x14, 0(x15); ecall

post_v0_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f                # no fault → FAIL
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 2f  # load PF
    li x6, 5;  beq x5, x6, 2f  # load access fault
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 3: Reserved PTE encoding (W=1, R=0) at L0 ──
# Set up L0 PTE with W=1, R=0 (reserved encoding per Sv32 spec).
# Access → should get page fault.
test_03_reserved_pte_w1_r0:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_reserved_check; la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    # Modify L0[4] to reserved encoding: W=1, R=0 (V=1, W=1)
    la x14, l0_page_table
    li x15, 0x80004
    slli x15, x15, 10
    li x16, 0x005               # V=1, W=1, R=0 (reserved!)
    or x15, x15, x16
    sw x15, 16(x14)            # L0[4] → reserved PTE
    fence.i                     # flush dcache so PTW sees updated PTE
    sfence.vma                  # flush TLB so next access re-walks
    la x5, s_reserved_fault; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_reserved_fault:
    li x14, 0x80004000
    lw x15, 0(x14)             # should trigger PF (reserved encoding)
    li x14, 0                  # no fault → FAIL
    la x15, mmu_result; sw x14, 0(x15); ecall

post_reserved_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f                # no fault → FAIL
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 2f  # load PF
    li x6, 5;  beq x5, x6, 2f  # load access fault
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 4: Non-leaf PTE (pointer to L0, no execute) ──
# Set up L1 PTE as non-leaf: V=1, R=0, W=0, X=0 (pointer to L0).
# This is the normal case for a page table pointer.
# Verify normal access works (confirms PTW correctly identifies non-leaf PTEs).
test_04_non_leaf_pte_no_execute:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    # Build page tables from scratch, explicitly setting L1[512] as non-leaf
    jal x1, clear_page_tables
    la x14, l1_page_table
    la x15, l0_page_table
    # L1[512] → non-leaf pointer to L0 (V=1, R=0, W=0, X=0)
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, 0x001        # V only (R=0, W=0, X=0 → non-leaf)
    li  x17, 0x800
    add x17, x14, x17          # x17 = &l1_page_table[512]
    sw x16, 0(x17)             # L1[512] → non-leaf pointer
    # L0[0-7] with full permissions for code/data safety
    li x17, 0x0CF               # V|R|W|X|A|D
    li x16, 0x80000; slli x16, x16, 10; or x16, x16, x17; sw x16, 0(x15)
    li x16, 0x80001; slli x16, x16, 10; or x16, x16, x17; sw x16, 4(x15)
    li x16, 0x80002; slli x16, x16, 10; or x16, x16, x17; sw x16, 8(x15)
    li x16, 0x80003; slli x16, x16, 10; or x16, x16, x17; sw x16, 12(x15)
    li x16, 0x80004; slli x16, x16, 10; or x16, x16, x17; sw x16, 16(x15)
    li x16, 0x80005; slli x16, x16, 10; or x16, x16, x17; sw x16, 20(x15)
    li x16, 0x80006; slli x16, x16, 10; or x16, x16, x17; sw x16, 24(x15)
    li x16, 0x80007; slli x16, x16, 10; or x16, x16, x17; sw x16, 28(x15)
    # Write known value to 0x80004000 before enabling Sv32
    li x14, 0x80004000
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_non_leaf; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_non_leaf:
    li x14, 0x80004000
    lw x15, 0(x14)             # PTW sees non-leaf L1, walks to L0 → OK
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
