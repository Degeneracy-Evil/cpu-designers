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
    addi  x5, x0, 0xC8
    jalr  x4, x5, 0
    addi  x2, x0, 88
    addi  x2, x0, 99
    addi  x2, x0, 111
    addi  x2, x0, 122
jalr_target:
    addi  x2, x0, 77
end_loop:
    j     end_loop
