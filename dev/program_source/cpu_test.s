.equ CLINT_BASE, 0x02000000

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
    lui   x21, 0x80001
    sw    x3, 0(x21)
    sb    x1, 4(x21)
    sh    x2, 6(x21)
    lw    x23, 0(x21)
    lb    x24, 4(x21)
    lbu   x25, 4(x21)
    lh    x26, 6(x21)
    lhu   x27, 6(x21)
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
    sb x10, 0(x21)
    lb x2, 0(x21)
    lbu x3, 0(x21)

    li x10, 0xC2
    sb x10, 1(x21)
    lb x4, 1(x21)
    lbu x5, 1(x21)

    li x10, 0xC3
    sb x10, 2(x21)
    lb x6, 2(x21)
    lbu x7, 2(x21)

    li x10, 0xC4
    sb x10, 3(x21)
    lb x8, 3(x21)
    lbu x9, 3(x21)

    li x10, 0x5678
    sh x10, 0(x21)
    lh x20, 0(x21)
    lhu x11, 0(x21)

    li x10, 0xABCD
    sh x10, 2(x21)
    lh x12, 2(x21)
    lhu x13, 2(x21)

    lw x14, 0(x21)

    li x10, 0x12345678
    sw x10, 4(x21)
    lw x15, 4(x21)

    lb x16, 4(x21)
    lb x17, 5(x21)
    lb x18, 6(x21)
    lb x19, 7(x21)

    li x10, 0x00FF
    sh x10, 8(x21)
    lb x22, 8(x21)
    lb x23, 9(x21)

    li x10, 0xFF00
    sh x10, 10(x21)
    lb x24, 10(x21)
    lb x25, 11(x21)

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

    la x10, trap_handler
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10
    li x10, 0x800
    csrw mie, x10

    csrw mscratch, x0

    addi x1, x0, 0
    ecall

    addi x1, x0, 1

    ebreak

    addi x1, x0, 2

    .word 0x0000007F

    addi  x1, x0, 3

    li    x5, 100
    li    x6, 7
    mul   x7, x5, x6
    sw    x7, 0x10(x21)

    li    x5, -1
    li    x6, -1
    mulh  x7, x5, x6
    sw    x7, 0x14(x21)

    mulhsu x7, x5, x6
    sw    x7, 0x18(x21)

    mulhu  x7, x5, x6
    sw    x7, 0x1C(x21)

    li    x5, 100
    li    x6, 7
    div   x7, x5, x6
    sw    x7, 0x20(x21)

    li    x5, -1
    divu  x7, x5, x6
    sw    x7, 0x24(x21)

    li    x5, 100
    rem   x7, x5, x6
    sw    x7, 0x28(x21)

    li    x5, -1
    remu  x7, x5, x6
    sw    x7, 0x2C(x21)

    li x10, 0x80
    csrw mstatus, x10
    li x10, 0x000
    csrw mie, x10

    la x10, timer_handler
    csrw mtvec, x10

    li x10, 0x88
    csrw mstatus, x10

    li x10, 0x080
    csrw mie, x10

    lui x10, 0x02000
    lw x11, 8(x10)
    lw x13, 12(x10)
    li x12, 100000
    mv x14, x11
    add x11, x11, x12
    sltu x14, x11, x14
    add x13, x13, x14
    sw x11, 0(x10)
    sw x13, 4(x10)

    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1

end_loop:
    j end_loop

trap_handler:
    csrrs x19, mcause, x0
    csrrs x20, mepc, x0
    addi x20, x20, 4
    csrw mepc, x20
    csrrs x21, mscratch, x0
    slli x21, x21, 2
    addi x22, x21, 72
    lui  x21, 0x80001
    add  x22, x22, x21
    sw x19, 0(x22)
    csrrs x21, mscratch, x0
    addi x21, x21, 1
    csrw mscratch, x21
    li x10, 0x80
    csrw mstatus, x10
    mret

timer_handler:
    csrrs x2, mcause, x0
    csrrs x3, mepc, x0
    addi x4, x0, 1

    lui x10, 0x02000
    sw x0, 0(x10)
    sw x0, 4(x10)

    li x10, 0x80
    csrw mstatus, x10
    mret
