.equ TIMER_BASE, 0x80004000

.section .text
.globl _start

_start:
    addi x1, x0, 0

    la x10, handler
    csrw mtvec, x10

    li x10, 0x08
    csrw mstatus, x10

    li x10, 0x080
    csrw mie, x10

    lui x10, 0x80004
    li x11, 500
    sw x11, 0(x10)

    li x11, 3
    sw x11, 4(x10)

loop:
    j loop

handler:
    addi x1, x1, 1

    lui x10, 0x80004
    sw x0, 8(x10)

    li x10, 0x08
    csrw mstatus, x10
    mret
