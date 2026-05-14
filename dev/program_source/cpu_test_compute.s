.section .text
.globl _start

_start:

    addi  x1, x0, 5
    addi  x2, x0, 7
    add   x3, x1, x2
    sub   x4, x3, x1
    sll   x5, x1, x1
    slt   x6, x1, x2
    sltu  x7, x2, x1
    xor   x8, x1, x2
    srl   x9, x8, x1
    sra   x10, x8, x1
    or    x11, x1, x2
    and   x12, x1, x2
    slti  x13, x1, 6
    sltiu x14, x1, -1
    xori  x15, x1, 3
    ori   x16, x1, 8
    andi  x17, x16, 9
    slli  x18, x1, 3
    srli  x19, x18, 1
    srai  x20, x18, 2
    lui   x21, 0x12345
    auipc x22, 0x0
    sw    x3, 0(x0)
    sb    x1, 4(x0)
    sh    x2, 6(x0)
    lw    x23, 0(x0)
    lb    x24, 4(x0)
    lbu   x25, 4(x0)
    lh    x26, 6(x0)
    lhu   x27, 6(x0)
    beq   x23, x3, beq_skip
    addi  x28, x0, 111
beq_skip:
    bne   x23, x1, bne_skip
    addi  x28, x0, 222
bne_skip:
    blt   x1, x2, blt_skip
    addi  x29, x0, 1
blt_skip:
    bge   x2, x1, bge_skip
    addi  x29, x0, 2
bge_skip:
    bltu  x1, x2, bltu_skip
    addi  x30, x0, 3
bltu_skip:
    bgeu  x2, x1, bgeu_skip
    addi  x30, x0, 4
bgeu_skip:
    jal   x31, jal_skip
    addi  x1, x0, 99
jal_skip:
    addi  x5, x22, 116
    jalr  x4, x5, 0
    addi  x2, x0, 88
    addi  x2, x0, 99
    addi  x2, x0, 111
    addi  x2, x0, 122
jalr_target:
    addi  x2, x0, 77

    li x10, 0xC1
    sb x10, 0(x0)
    lb x2, 0(x0)
    lbu x3, 0(x0)

    li x10, 0xC2
    sb x10, 1(x0)
    lb x4, 1(x0)
    lbu x5, 1(x0)

    li x10, 0xC3
    sb x10, 2(x0)
    lb x6, 2(x0)
    lbu x7, 2(x0)

    li x10, 0xC4
    sb x10, 3(x0)
    lb x8, 3(x0)
    lbu x9, 3(x0)

    li x10, 0x5678
    sh x10, 0(x0)
    lh x20, 0(x0)
    lhu x11, 0(x0)

    li x10, 0xABCD
    sh x10, 2(x0)
    lh x12, 2(x0)
    lhu x13, 2(x0)

    lw x14, 0(x0)

    li x10, 0x12345678
    sw x10, 4(x0)
    lw x15, 4(x0)

    lb x16, 4(x0)
    lb x17, 5(x0)
    lb x18, 6(x0)
    lb x19, 7(x0)

    li x10, 0x00FF
    sh x10, 8(x0)
    lb x22, 8(x0)
    lb x23, 9(x0)

    li x10, 0xFF00
    sh x10, 10(x0)
    lb x24, 10(x0)
    lb x25, 11(x0)

    li x10, 0x80
    csrrw x2, mstatus, x10
    csrrw x3, mie, x10
    li x10, 0x100
    csrrw x4, mtvec, x10

    li x10, 0xAAAA
    csrrw x5, mscratch, x10
    csrrw x6, mscratch, x0
    li x10, 0x5555
    csrrw x7, mscratch, x10

    li x10, 0x0001
    csrrs x8, mscratch, x10
    li x10, 0x0100
    csrrs x9, mscratch, x10

    li x10, 0x0001
    csrrc x11, mscratch, x10
    li x10, 0x0100
    csrrc x12, mscratch, x10

    csrrwi x13, mscratch, 0
    csrrwi x14, mscratch, 5

    csrrsi x15, mscratch, 2
    csrrsi x16, mscratch, 0

    csrrci x17, mscratch, 1
    csrrci x18, mscratch, 0

    li    x5, 100
    li    x6, 7
    mul   x7, x5, x6
    sw    x7, 0x10(x0)

    li    x5, -1
    li    x6, -1
    mulh  x7, x5, x6
    sw    x7, 0x14(x0)

    mulhsu x7, x5, x6
    sw    x7, 0x18(x0)

    mulhu  x7, x5, x6
    sw    x7, 0x1C(x0)

    li    x5, 100
    li    x6, 7
    div   x7, x5, x6
    sw    x7, 0x20(x0)

    li    x5, -1
    divu  x7, x5, x6
    sw    x7, 0x24(x0)

    li    x5, 100
    rem   x7, x5, x6
    sw    x7, 0x28(x0)

    li    x5, -1
    remu  x7, x5, x6
    sw    x7, 0x2C(x0)

    addi  x1, x0, 0xAC

end_loop:
    j end_loop
