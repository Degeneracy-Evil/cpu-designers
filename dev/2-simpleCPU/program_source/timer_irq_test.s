.section .text
.globl _start

_start:
    addi x1, x0, 0

    la x10, handler
    csrw mtvec, x10

    li x10, 0x88
    csrw mstatus, x10

    li x10, 0x800
    csrw mie, x10

    lui x10, 0x10010
    li x11, 200
    sw x11, 0(x10)

    lui x10, 0x10010
    li x11, 1
    sw x11, 4(x10)

    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1
    addi x1, x1, 1

end_loop:
    j end_loop

handler:
    csrrs x2, mcause, x0
    csrrs x3, mepc, x0
    addi x4, x0, 1

    lui x10, 0x10010
    sw x0, 8(x10)

    li x10, 0x80
    csrw mstatus, x10
    mret
