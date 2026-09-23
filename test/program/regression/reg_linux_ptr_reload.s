# ============================================================
# regression/reg_linux_ptr_reload.s — Near-Linux pointer reload regression
# Category: Regression | Sub-tests: 2
# ============================================================
# Goal:
#   Reproduce the Linux-like sequence:
#     sw ptr, 0(s1)
#     ... dirty-evict/refill same cache set ...
#     lw a5, 32(s1)
#     lw s2, 0(s1)
#     sw a5, 4(s2)
#
#   The watched pointer lives at a high S-mode VA with VA!=PA.
#   The target pointer is another high S-mode VA. If the reload path
#   corrupts the `lw s2, 0(s1)` result, sub-test 2 should either:
#     - observe wrong s2 directly, or
#     - take a store page fault on sw a5, 4(s2)
# ============================================================

.equ PTE_V, 0x001
.equ PTE_R, 0x002
.equ PTE_W, 0x004
.equ PTE_X, 0x008
.equ PTE_A, 0x040
.equ PTE_D, 0x080
.equ PTE_PTR, PTE_V
.equ PTE_LEAF, (PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D)

.equ VA_WATCH,    0xC00021FC
.equ VA_THRASH1,  0xC00031FC
.equ VA_THRASH2,  0xC00041FC
.equ VA_THRASH3,  0xC00051FC
.equ VA_THRASH4,  0xC00061FC
.equ VA_THRASH5,  0xC00071FC
.equ VA_TARGET,   0xC0403000
.equ VA_A5SRC,    (VA_WATCH + 32)
.equ A5_VALUE,    0xC0522DC0

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_reload_after_evict
    jal x1, test_run
    la x11, test_02_linux_like_store
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

test_01_reload_after_evict:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, prep_sparse_map
    la x5, s_reload_check
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_reload_check:
    li x9, VA_WATCH
    li x10, VA_TARGET
    sw x10, 0(x9)
    li x11, A5_VALUE
    sw x11, 32(x9)

    jal x1, thrash_same_set

    lw x12, 0(x9)
    add x25, x12, x0      # debug: reloaded pointer
    li x13, VA_TARGET
    bne x12, x13, s_fail

    li x10, 1
    ecall

test_02_linux_like_store:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    jal x1, prep_sparse_map
    la x5, s_linux_like
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_linux_like:
    li x9, VA_WATCH
    li x10, VA_TARGET
    sw x10, 0(x9)
    li x11, A5_VALUE
    sw x11, 32(x9)

    jal x1, thrash_same_set

    lw x15, 32(x9)
    lw x12, 0(x9)
    add x25, x12, x0      # debug: reloaded pointer
    li x13, VA_TARGET
    bne x12, x13, s_fail

    sw x15, 4(x12)
    lw x14, 4(x12)
    add x26, x14, x0      # debug: final stored data
    li x13, A5_VALUE
    bne x14, x13, s_fail

    li x10, 1
    ecall

s_fail:
    li x10, 0
    ecall

thrash_same_set:
    li x12, VA_THRASH1
    li x13, 0x11111111
    sw x13, 0(x12)
    li x12, VA_THRASH2
    li x13, 0x22222222
    sw x13, 0(x12)
    li x12, VA_THRASH3
    li x13, 0x33333333
    sw x13, 0(x12)
    li x12, VA_THRASH4
    li x13, 0x44444444
    sw x13, 0(x12)
    li x12, VA_THRASH5
    li x13, 0x55555555
    sw x13, 0(x12)

    # Re-access two thrash lines to perturb PLRU before the watched reload.
    li x12, VA_THRASH2
    lw x13, 0(x12)
    li x12, VA_THRASH4
    lw x13, 0(x12)
    ret

prep_sparse_map:
    add x27, x1, x0       # save caller ra; this helper is non-leaf
    jal x1, disable_sv32
    li x22, 0             # debug: trap cause
    li x23, 0             # debug: trap epc
    li x24, 0             # debug: trap tval
    li x25, 0             # debug: reloaded pointer
    li x26, 0             # debug: stored data

    jal x1, clear_page_tables

    # Identity-map the low 0x80000000 region so M/S test code and result page work.
    jal x1, setup_identity_map

    # L1[0x300] -> l0_high_a
    la x14, l1_page_table
    la x15, l0_high_a
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, PTE_PTR
    li x17, 0xC00
    add x17, x14, x17
    sw x16, 0(x17)

    # L1[0x301] -> l0_high_b
    la x15, l0_high_b
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, PTE_PTR
    li x17, 0xC04
    add x17, x14, x17
    sw x16, 0(x17)

    # VA 0xC0002000..0xC0007FFF -> PA 0x80002000..0x80007FFF
    la x14, l0_high_a
    li x16, PTE_LEAF
    li x15, 0x80002
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 8(x14)        # vpn0=2
    li x15, 0x80003
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 12(x14)       # vpn0=3
    li x15, 0x80004
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 16(x14)       # vpn0=4
    li x15, 0x80005
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 20(x14)       # vpn0=5
    li x15, 0x80006
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 24(x14)       # vpn0=6
    li x15, 0x80007
    slli x15, x15, 10
    or x15, x15, x16
    sw x15, 28(x14)       # vpn0=7

    # VA 0xC0403000 -> PA 0x80004000
    la x14, l0_high_b
    li x15, 0x80004
    slli x15, x15, 10
    li x16, PTE_LEAF
    or x15, x15, x16
    li x17, 12            # vpn0=3
    add x17, x14, x17
    sw x15, 0(x17)

    # Backing memory init in M-mode.
    li x14, 0x800021FC
    li x15, VA_TARGET
    sw x15, 0(x14)
    li x15, A5_VALUE
    sw x15, 32(x14)
    li x14, 0x80004004
    sw x0, 0(x14)

    jal x1, enable_sv32
    add x1, x27, x0
    ret

mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval

    li x5, 9
    beq x22, x5, _mth_ecall
    li x5, 8
    beq x22, x5, _mth_ecall
    li x5, 11
    beq x22, x5, _mth_ecall

    # Unexpected trap during sub-test: return FAIL to framework.
    li x10, 0
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5
    li x5, 0x1888
    csrw mstatus, x5
    mret

_mth_ecall:
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5
    li x5, 0x1888
    csrw mstatus, x5
    mret

.section .text
.balign 4
mmu_saved_ra:  .word 0
mmu_return_pc: .word 0

.balign 4096
l0_high_a:
    .fill 1024, 4, 0

.balign 4096
l0_high_b:
    .fill 1024, 4, 0
