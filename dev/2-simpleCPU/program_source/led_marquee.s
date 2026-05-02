.equ GPIO_BASE, 0x80000000

.section .text
.globl _start

_start:
    lui x10, 0x80000

    li x11, 0xFFFF
    sw x11, 0(x10)

    li x12, 0

loop:
    li x11, 1
    sll x13, x11, x12
    xori x13, x13, -1
    sw x13, 4(x10)

    li x14, 300
delay:
    addi x14, x14, -1
    bne x14, x0, delay

    addi x12, x12, 1
    li x11, 16
    bne x12, x11, loop
    li x12, 0
    j loop
