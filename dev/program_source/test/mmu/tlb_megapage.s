# ============================================================
# mmu/tlb_megapage.s — Megapage (superpage) translation tests
# Category: MMU
# Sub-tests: 4
# ============================================================
# Megapage: L1 leaf PTE where R||X is set (not a pointer to L0).
# Maps a 4MB region instead of 4KB.
# Physical address: paddr = {PPN[21:10], vaddr[21:0]}
# VPN matching: only VPN[19:10] compared; VPN[9:0] zeroed in TLB on fill.
# PPN[9:0] must be 0 for properly aligned megapage (else misaligned PF).
# TLB marks entry as mega=1 on fill.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_megapage_basic
    jal x1, test_run
    la x11, test_02_megapage_vpn_low_ignored
    jal x1, test_run
    la x11, test_03_megapage_ppn_alignment
    jal x1, test_run
    la x11, test_04_megapage_vs_normal_page
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Megapage basic translation ──
# Set up L1[512] as a leaf PTE (megapage) mapping 0x80000000 region.
# Access data through megapage. Verify correct data returned.
# L1 index 512 = VPN[1]=512 = VA[31:22]=0x200 → VA 0x80000000-0x803FFFFF.
test_01_megapage_basic:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    la x14, l1_page_table
    li x15, 0x80000            # PPN = 0x80000 (0x80000000 >> 12)
    slli x15, x15, 10
    li x16, 0x0CF               # V|R|W|X|A|D (Supervisor megapage)
    or x15, x15, x16
    li  x17, 0x800
    add x17, x14, x17          # x17 = &l1_page_table[512]
    sw x15, 0(x17)             # L1[512] → megapage
    jal x1, enable_sv32
    la x5, s_mega_basic; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mega_basic:
    la x14, test_data_area
    lw x15, 0(x14)             # access through megapage
    li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 2: Megapage VPN[9:0] ignored — same megapage for different VAs ──
# Megapage only compares VPN[19:10] (upper 10 bits of VPN).
# VPN[9:0] is part of the 4MB page offset, not used for TLB match.
# Access two VAs within the same megapage that differ in VPN[9:0]:
#   VA1 = test_data_area       (e.g., 0x8000XXXX, VPN[0]=X)
#   VA2 = test_data_area2      (VA1 + 0x1000, VPN[0] differs)
# Both should hit the same megapage TLB entry and return correct data.
test_02_megapage_vpn_low_ignored:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    la x14, l1_page_table
    li x15, 0x80000            # PPN = 0x80000
    slli x15, x15, 10
    li x16, 0x0CF               # V|R|W|X|A|D
    or x15, x15, x16
    li  x17, 0x800
    add x17, x14, x17
    sw x15, 0(x17)             # L1[512] → megapage
    # Write known values at two VAs within the megapage before enabling Sv32
    la x14, test_data_area
    li x15, 0xDEADBEEF
    sw x15, 0(x14)             # value at VA1
    la x14, test_data_area2
    li x15, 0xCAFEBABE
    sw x15, 0(x14)             # value at VA2 (VA1 + 0x1000)
    jal x1, enable_sv32
    la x5, s_mega_vpn_low; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mega_vpn_low:
    la x14, test_data_area
    lw x15, 0(x14)             # access VA1 (megapage TLB fill)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f           # VA1 data mismatch → FAIL
    la x14, test_data_area2
    lw x15, 0(x14)             # access VA2 (same megapage, VPN[9:0] differs)
    li x16, 0xCAFEBABE
    bne x15, x16, 1f           # VA2 data mismatch → FAIL
    li x14, 1; j 2f            # both OK → PASS
1:  li x14, 0
2:  la x15, mmu_result; sw x14, 0(x15); ecall

# ── Sub-test 3: Megapage PPN alignment — PPN[9:0]=0 required ──
# Create a megapage with PPN[9:0]=0 (properly aligned).
# PPN=0x80000: binary 1000_0000_0000_0000_0000_00, PPN[9:0]=0x000 → aligned.
# Physical address: paddr = {PPN[21:10], vaddr[21:0]}
#   PPN[21:10] = 0x200, so paddr = {0x200, vaddr[21:0]} = identity for 0x80000000.
# Write a distinctive value, access through megapage, verify correct translation.
test_03_megapage_ppn_alignment:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    la x14, l1_page_table
    li x15, 0x80000            # PPN = 0x80000, PPN[9:0]=0 (aligned)
    slli x15, x15, 10
    li x16, 0x0CF               # V|R|W|X|A|D
    or x15, x15, x16
    li  x17, 0x800
    add x17, x14, x17
    sw x15, 0(x17)             # L1[512] → aligned megapage
    # Write distinctive test value before enabling Sv32
    la x14, test_data_area
    li x15, 0xAAAABBBB
    sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_mega_aligned; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mega_aligned:
    la x14, test_data_area
    lw x15, 0(x14)             # access through aligned megapage
    li x16, 0xAAAABBBB
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  # restore original value for subsequent tests
    li x15, 0xDEADBEEF
    la x14, test_data_area
    sw x15, 0(x14)
    li x14, 1
    la x15, mmu_result
    sw x14, 0(x15)
    ecall

# ── Sub-test 4: Megapage vs normal 2-level page translation ──
# Phase 1: L1[512] → pointer to L0 (normal 2-level), access a page.
# Phase 2: Change L1[512] to megapage leaf, sfence.vma, access same VA.
# Both should work correctly, demonstrating that the same VA can be
# translated through either a 2-level walk or a megapage.
test_04_megapage_vs_normal_page:
    la x5, mmu_saved_ra; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, clear_page_tables
    # Phase 1: Set up normal 2-level translation
    la x14, l1_page_table
    la x15, l0_page_table
    # L1[512] → pointer to L0
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, 0x001        # V only (pointer to L0)
    li  x17, 0x800
    add x17, x14, x17
    sw x16, 0(x17)             # L1[512] → L0 pointer
    # L0[0-7] with full permissions for code/data in 0x80000000 region
    li x17, 0x0CF               # V|R|W|X|A|D
    li x16, 0x80000; slli x16, x16, 10; or x16, x16, x17; sw x16, 0(x15)
    li x16, 0x80001; slli x16, x16, 10; or x16, x16, x17; sw x16, 4(x15)
    li x16, 0x80002; slli x16, x16, 10; or x16, x16, x17; sw x16, 8(x15)
    li x16, 0x80003; slli x16, x16, 10; or x16, x16, x17; sw x16, 12(x15)
    li x16, 0x80004; slli x16, x16, 10; or x16, x16, x17; sw x16, 16(x15)
    li x16, 0x80005; slli x16, x16, 10; or x16, x16, x17; sw x16, 20(x15)
    li x16, 0x80006; slli x16, x16, 10; or x16, x16, x17; sw x16, 24(x15)
    li x16, 0x80007; slli x16, x16, 10; or x16, x16, x17; sw x16, 28(x15)
    # Write test value before enabling Sv32
    la x14, test_data_area
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    jal x1, enable_sv32
    la x5, s_mega_vs_normal; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mega_vs_normal:
    # Phase 1: Access through normal 2-level translation
    la x14, test_data_area
    lw x15, 0(x14)             # access via L1→L0→PTE
    li x16, 0xDEADBEEF
    bne x15, x16, 1f           # Phase 1 data mismatch → FAIL
    # Phase 2: Switch L1[512] from pointer to megapage leaf
    la x14, l1_page_table
    li x15, 0x80000            # PPN = 0x80000
    slli x15, x15, 10
    li x16, 0x0CF               # V|R|W|X|A|D (megapage leaf)
    or x15, x15, x16
    li  x17, 0x800
    add x17, x14, x17
    sw x15, 0(x17)             # L1[512] → megapage (overwrite pointer)
    fence.i                     # flush dcache so PTW sees updated PTE
    sfence.vma                  # flush TLB
    # Re-access same VA through megapage
    la x14, test_data_area
    lw x15, 0(x14)             # access via megapage
    li x16, 0xDEADBEEF
    bne x15, x16, 1f           # Phase 2 data mismatch → FAIL
    li x14, 1; j 2f            # both phases OK → PASS
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

# ============================================================
# Data areas (2 page-aligned regions for multi-VA testing)
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
