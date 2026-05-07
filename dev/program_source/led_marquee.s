.equ GPIO_BASE, 0x80000000
.equ TIMER_BASE, 0x80004000

.section .text
.globl _start

_start:
    lui x10, 0x80000
    lui x15, 0x80004

    li x11, 0xFFFF
    sw x11, 0(x10)

    li x16, 100000000
    sw x16, 0(x15)
    li x16, 3
    sw x16, 4(x15)

    li x12, 0

loop:
    li x11, 1
    sll x13, x11, x12
    xori x13, x13, -1
    sw x13, 4(x10)

wait_timer:
    lw x14, 8(x15)
    beq x14, x0, wait_timer
    sw x0, 8(x15)

    addi x12, x12, 1
    li x11, 16
    bne x12, x11, loop
    li x12, 0
    j loop
