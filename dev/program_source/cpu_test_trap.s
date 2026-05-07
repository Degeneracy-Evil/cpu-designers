.equ TIMER_BASE, 0x80004000

.section .text
.globl _start

_start:
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

    addi  x1, x1, 1
    addi  x1, x1, 1
    addi  x1, x1, 1
    addi  x1, x1, 1
    addi  x1, x1, 1

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
    sw x19, 0(x22)
    csrrs x21, mscratch, x0
    addi x21, x21, 1
    csrw mscratch, x21
    li x10, 0x80
    csrw mstatus, x10
    mret
