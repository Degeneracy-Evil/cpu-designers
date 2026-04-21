.section .text
.globl _start

_start:
    addi x1, x0, 5
    addi x2, x0, 7
    add  x3, x1, x2
    lui  x4, 0x12345
    addi x5, x4, 1
    nop
    nop
    nop
