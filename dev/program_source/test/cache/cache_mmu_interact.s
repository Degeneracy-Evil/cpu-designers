# ============================================================
# cache/cache_mmu_interact.s — Cache + MMU interaction tests
# Category: Cache (MMU framework required)
# Description: Test dcache/icache behavior with Sv32 enabled in S-mode
# Sub-tests: 6
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# ============================================================
# Key interactions tested:
#   1. FENCE.I in S-mode flushes dcache through TLB
#   2. Store-load roundtrip in S-mode (dcache hit through TLB)
#   3. Self-modifying code in S-mode (icache refill after FENCE.I)
#   4. Cross-page dcache operations (multi-TLB-entry, same dcache)
#   5. Multiple dirty same-line stores → FENCE.I writeback
#   6. Byte/halfword ops under Sv32
#
# Memory layout (all identity-mapped by setup_identity_map):
#   0x80000000 - 0x80000FFF : .text.start (M-mode test functions)
#   0x80001000 - 0x80001FFF : L1 page table
#   0x80002000 - 0x80002FFF : L0 page table
#   0x80003000 - 0x80003FFF : S-mode code + mmu helper vars
#   0x80004000 - 0x80004FFF : test_data_area (page 4, for data tests)
#   0x80005000 - 0x80005FFF : test_data_area2 + SMC target (page 5)
#   0x80007000 - 0x80007FFF : TEST_RESULT_BASE (framework)
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_fencei_smode
    jal x1, test_run
    la x11, test_02_store_load_smode
    jal x1, test_run
    la x11, test_03_smc_smode
    jal x1, test_run
    la x11, test_04_cross_page
    jal x1, test_run
    la x11, test_05_multi_dirty
    jal x1, test_run
    la x11, test_06_byte_halfword
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ============================================================
# Sub-test 1: FENCE.I in S-mode flushes dcache through TLB
# Store value in S-mode (write to dcache), FENCE.I (flush),
# then load back (dcache miss → refill from SRAM)
# ============================================================
test_01_fencei_smode:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)               # clear mmu_return_pc
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_01_fencei
    csrw mepc, x5
    li x5, 0x880               # MPP=S, MPIE=1
    csrw mstatus, x5
    mret

s_01_fencei:
    # Store to test_data_area
    la x14, test_data_area
    li x15, 0xCAFEBABE
    sw x15, 0(x14)             # dcache dirty

    # FENCE.I: flush dcache (writeback to SRAM) + invalidate icache
    fence.i

    # Load back — dcache miss → refill from SRAM (which has 0xCAFEBABE)
    la x14, test_data_area
    lw x15, 0(x14)
    li x16, 0xCAFEBABE
    bne x15, x16, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# Sub-test 2: Store-load roundtrip in S-mode (dcache hit)
# Store then load without FENCE.I — result comes from dcache hit
# ============================================================
test_02_store_load_smode:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_02_store_load
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_02_store_load:
    # Store a known value
    la x14, test_data_area
    li x15, 0x12345678
    sw x15, 0(x14)

    # Load it back (should be dcache hit)
    lw x16, 0(x14)
    li x17, 0x12345678
    bne x16, x17, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# Sub-test 3: Self-modifying code in S-mode
# Write new instruction to smc_fn, FENCE.I, call smc_fn
# smc_fn returns 42 (new instruction: addi x10,x0,42)
# ============================================================
test_03_smc_smode:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_03_smc
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_03_smc:
    # Write new instruction to smc_fn: addi x10, x0, 42 = 0x02A00513
    la x14, smc_fn
    li x15, 0x02A00513         # addi x10, x0, 42
    sw x15, 0(x14)
    li x15, 0x00008067         # ret
    sw x15, 4(x14)

    # FENCE.I: flush dcache + invalidate icache
    fence.i

    # Call smc_fn — icache miss, fetch from SRAM, get new instruction
    la x14, smc_fn
    jalr x1, x14, 0            # x10 = smc_fn() = 42

    # Check result
    li x15, 42
    bne x10, x15, 1f
    li x14, 1
    j 2f
1:  li x14, 0
2:  la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# Sub-test 4: Cross-page dcache operations
# Store to two different pages (different TLB entries, same dcache),
# FENCE.I, verify both values survive
# ============================================================
test_04_cross_page:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_04_cross
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_04_cross:
    # Store to page 4 (0x80004000)
    lui x14, 0x80004
    li x15, 0xAAAA1111
    sw x15, 0(x14)

    # Store to page 5 (0x80005000) — different TLB entry
    lui x14, 0x80005
    li x15, 0xBBBB2222
    sw x15, 0(x14)

    fence.i                    # flush all dirty

    # Load page 4 back
    lui x14, 0x80004
    lw x16, 0(x14)
    li x17, 0xAAAA1111
    bne x16, x17, _s04_fail

    # Load page 5 back
    lui x14, 0x80005
    lw x16, 0(x14)
    li x17, 0xBBBB2222
    bne x16, x17, _s04_fail

    li x14, 1
    j _s04_done
_s04_fail:
    li x14, 0
_s04_done:
    la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# Sub-test 5: Multiple dirty same-line stores + FENCE.I
# Store 4 words to same cache line, FENCE.I, verify all 4
# ============================================================
test_05_multi_dirty:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_05_multi
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_05_multi:
    # Store 4 words to test_data_area (same cache line: set 0, tag 3)
    la x14, test_data_area
    li x15, 0xCCCC0001
    sw x15, 0(x14)
    li x15, 0xCCCC0002
    sw x15, 4(x14)
    li x15, 0xCCCC0003
    sw x15, 8(x14)
    li x15, 0xCCCC0004
    sw x15, 12(x14)

    fence.i                    # flush all dirty

    # Verify all 4
    la x14, test_data_area

    lw x16, 0(x14)
    li x17, 0xCCCC0001
    bne x16, x17, _s05_fail

    lw x16, 4(x14)
    li x17, 0xCCCC0002
    bne x16, x17, _s05_fail

    lw x16, 8(x14)
    li x17, 0xCCCC0003
    bne x16, x17, _s05_fail

    lw x16, 12(x14)
    li x17, 0xCCCC0004
    bne x16, x17, _s05_fail

    li x14, 1
    j _s05_done
_s05_fail:
    li x14, 0
_s05_done:
    la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# Sub-test 6: Byte/halfword operations under Sv32
# SB/SH in S-mode, then LBU/LHU to verify dcache handles sub-word ops
# ============================================================
test_06_byte_halfword:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_06_bh
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_06_bh:
    la x14, test_data_area2

    # Byte store + load
    li x15, 0xAB
    sb x15, 0(x14)
    lbu x16, 0(x14)
    bne x16, x15, _s06_fail

    # Halfword store + load
    li x15, 0x1234
    sh x15, 4(x14)
    lhu x16, 4(x14)
    bne x16, x15, _s06_fail

    # Signed byte load (-1)
    li x15, 0xFF
    sb x15, 8(x14)
    lb x16, 8(x14)
    li x17, -1
    bne x16, x17, _s06_fail

    # Signed halfword load (-2048)
    li x15, 0x800
    neg x15, x15              # 0xFFFFF800 = -2048
    sh x15, 12(x14)
    lh x16, 12(x14)
    li x17, -2048
    bne x16, x17, _s06_fail

    li x14, 1
    j _s06_done
_s06_fail:
    li x14, 0
_s06_done:
    la x15, mmu_result
    sw x14, 0(x15)
    ecall


# ============================================================
# MMU Trap Handler (same pattern as tlb_basic.s)
# Handles: ecall from S (returns to M), page faults (records info)
# ============================================================
mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    li x5, 9                    # ecall from S-mode
    beq x22, x5, _mth_ecall
    li x5, 8                    # ecall from U-mode
    beq x22, x5, _mth_ecall

    # Page fault: record and return to mmu_return_pc
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
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5
    li x10, 0
    li x5, 0x1888
    csrw mstatus, x5
    mret

_mth_ecall:
    # ecall from S: read mmu_result, return to M-mode
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
# SMC target function
# Initially: addi x10, x0, 0 (returns 0)
# After SMC: addi x10, x0, 42 (returns 42)
# .balign 32 for icache line alignment
# ============================================================
.section .text
.balign 32
smc_fn:
    addi x10, x0, 0            # 0x00000513 — returns 0 initially
    ret                         # 0x00008067


# ============================================================
# Data areas
# ============================================================

# Page-aligned test data area (page 4: 0x80004000 vicinity)
.balign 4096
test_data_area:
    .word 0
    .word 0
    .word 0
    .word 0

# Second page-aligned test data area (page 5: 0x80005000 vicinity)
.balign 4096
test_data_area2:
    .word 0
    .word 0
    .word 0
    .word 0

# MMU helper variables (word-aligned)
.balign 4
mmu_saved_ra:    .word 0
mmu_return_pc:   .word 0
mmu_result:      .word 0
mmu_got_fault:   .word 0
mmu_fault_cause: .word 0
mmu_fault_val:   .word 0
