.section .data
.globl test_data
test_data:
    .word 0xDEADBEEF
    .word 0xCAFEBABE
    .word 0x12345678
    .word 0x87654321
    .half 0xABCD
    .half 0xEF01
    .byte 0x11, 0x22, 0x33, 0x44
    .word 0x00000000
    .word 0xFFFFFFFF

.section .text
.globl _start

_start:
    addi  x1, x0, 0

    lw    x5, 0(x0)
    lw    x6, 4(x0)
    lw    x7, 8(x0)
    lw    x8, 12(x0)
    lh    x9, 16(x0)
    lhu   x10, 16(x0)
    lb    x11, 20(x0)
    lbu   x12, 20(x0)

    addi  x5, x0, 5
    addi  x6, x0, 7
    add   x7, x5, x6
    sub   x8, x7, x5
    sll   x9, x5, x5
    slt   x10, x5, x6
    sltu  x11, x6, x5
    xor   x12, x5, x6
    srl   x13, x12, x5
    sra   x14, x12, x5
    or    x15, x5, x6
    and   x16, x5, x6

    slti  x17, x5, 6
    sltiu x18, x5, -1
    xori  x19, x5, 3
    ori   x20, x5, 8
    andi  x21, x20, 9
    slli  x22, x5, 3
    srli  x23, x22, 1
    srai  x24, x22, 2

    lui   x25, 0x12345
    auipc x26, 0x0

    sw    x7, 0(x0)
    sb    x5, 4(x0)
    sh    x6, 6(x0)
    lw    x27, 0(x0)
    lb    x28, 4(x0)
    lbu   x29, 4(x0)
    lh    x30, 6(x0)
    lhu   x31, 6(x0)

    beq   x27, x7, beq_ok
    addi  x1, x1, 1
beq_ok:
    bne   x27, x5, bne_ok
    addi  x1, x1, 2
bne_ok:
    blt   x5, x6, blt_ok
    addi  x1, x1, 4
blt_ok:
    bge   x6, x5, bge_ok
    addi  x1, x1, 8
bge_ok:
    bltu  x5, x6, bltu_ok
    addi  x1, x1, 16
bltu_ok:
    bgeu  x6, x5, bgeu_ok
    addi  x1, x1, 32
bgeu_ok:

    jal   x10, jal_target
    addi  x1, x1, 64
jal_target:
    addi  x11, x0, 0
    auipc x12, 0
    addi  x12, x12, 8
    jalr  x13, x12, 0
    addi  x1, x1, 128
jalr_skip:

    li    x10, 0x80
    csrrw x14, mstatus, x10
    li    x10, 0x100
    csrrw x15, mtvec, x10

    li    x10, 0xABCD
    csrrw x16, mscratch, x10
    csrrs x17, mscratch, x0
    li    x10, 0x0001
    csrrs x18, mscratch, x10
    li    x10, 0x0001
    csrrc x19, mscratch, x10
    csrrwi x20, mscratch, 5
    csrrsi x21, mscratch, 2
    csrrci x22, mscratch, 1

    la    x10, trap_handler
    csrrw x0,  mtvec, x10
    li    x10, 0x88
    csrrw x0,  mstatus, x10
    li    x10, 0x800
    csrrw x0,  mie, x10
    csrw  mscratch, x0

    addi  x2, x0, 0
    ecall

    addi  x2, x0, 1

    ebreak

    addi  x2, x0, 2

    li    x10, 0x80
    csrrw x0,  mstatus, x10
    li    x10, 0x000
    csrrw x0,  mie, x10

    sw    x7,  0(x0)
    sw    x8,  4(x0)
    sw    x9,  8(x0)
    sw    x10, 12(x0)
    sw    x1,  16(x0)
    sw    x2,  20(x0)

end_loop:
    j     end_loop

trap_handler:
    csrrs x23, mcause, x0
    csrrs x24, mepc, x0
    addi  x24, x24, 4
    csrw  mepc, x24
    li    x10, 0x80
    csrw  mstatus, x10
    mret
