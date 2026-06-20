# ============================================================
# regression/reg_linux_field_values.s — Field-value Linux pointer regression
# Category: Regression | Sub-tests: 1
# ============================================================
# Goal:
#   Use the same key values observed on FPGA:
#     s1  = 0xC03B21FC
#     *s1 = 0xC7BD6000
#     a5  = 0xC0522DC0
#     lw s2, 0(s1)
#     sw a5, 4(s2)
#
#   If the reload path corrupts the pointer, this should either:
#     - expose wrong x25 directly, or
#     - trap on the final store through x12.
# ============================================================

.equ PTE_V, 0x001
.equ PTE_R, 0x002
.equ PTE_W, 0x004
.equ PTE_X, 0x008
.equ PTE_A, 0x040
.equ PTE_D, 0x080
.equ PTE_PTR, PTE_V
.equ PTE_LEAF, (PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D)

.equ VA_WATCH,    0xC03B21FC
.equ VA_THRASH1,  0xC03B31FC
.equ VA_THRASH2,  0xC03B41FC
.equ VA_THRASH3,  0xC03B51FC
.equ VA_THRASH4,  0xC03B61FC
.equ VA_THRASH5,  0xC03B71FC
.equ VA_TARGET,   0xC7BD6000
.equ A5_VALUE,    0xC0522DC0

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    la x11, test_01_field_value_chain
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

test_01_field_value_chain:
    la x5, mmu_saved_ra
    sw x1, 0(x5)
    jal x1, prep_field_map
    la x5, s_field_chain
    csrw mepc, x5
    li x5, 0x880
    csrw mstatus, x5
    mret

s_field_chain:
    li x9, VA_WATCH
    li x10, VA_TARGET
    sw x10, 0(x9)

    jal x1, thrash_same_set

    lw x12, 0(x9)
    add x25, x12, x0
    bne x12, x10, s_fail

    li x15, A5_VALUE
    sw x15, 4(x12)
    lw x14, 4(x12)
    add x26, x14, x0
    bne x14, x15, s_fail

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
    ret

prep_field_map:
    add x27, x1, x0
    jal x1, disable_sv32
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0

    jal x1, clear_page_tables
    jal x1, setup_identity_map

    # L1[0x300] -> l0_high_a (watch + thrash pages)
    la x14, l1_page_table
    la x15, l0_high_a
    srli x16, x15, 12
    slli x16, x16, 10
    ori x16, x16, PTE_PTR
    li x17, (0x300 * 4)
    add x17, x14, x17
    sw x16, 0(x17)

    # L1[0x31e] -> 4MB megapage at PA 0x80400000
    li x16, 0x80400
    slli x16, x16, 10
    ori x16, x16, PTE_LEAF
    li x17, (0x31e * 4)
    add x17, x14, x17
    sw x16, 0(x17)

    # VA 0xC03B2xxx..0xC03B7xxx -> PA 0x80002xxx..0x80007xxx
    la x14, l0_high_a
    li x16, PTE_LEAF

    li x15, 0x80002
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b2 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    li x15, 0x80003
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b3 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    li x15, 0x80004
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b4 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    li x15, 0x80005
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b5 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    li x15, 0x80006
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b6 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    li x15, 0x80007
    slli x15, x15, 10
    or x15, x15, x16
    li x17, (0x3b7 * 4)
    add x17, x14, x17
    sw x15, 0(x17)

    # Backing memory init in M-mode.
    li x14, 0x800021FC
    li x15, VA_TARGET
    sw x15, 0(x14)
    li x14, 0x807D6004
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

.balign 4096
l0_high_a:
    .fill 1024, 4, 0
