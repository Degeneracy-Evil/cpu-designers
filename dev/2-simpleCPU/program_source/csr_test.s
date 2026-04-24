.section .text
.globl _start

_start:
    addi x1, x0, 0

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

    la x10, handler
    csrrw x0, mtvec, x10
    li x10, 0x88
    csrrw x0, mstatus, x10
    li x10, 0x800
    csrrw x0, mie, x10

    csrw mscratch, x0

    addi x1, x0, 0
    ecall

    addi x1, x0, 1

    ebreak

    addi x1, x0, 2

    .word 0x0000007F

    addi x1, x0, 3

    li x10, 0x80
    csrrw x0, mstatus, x10
    li x10, 0x000
    csrrw x0, mie, x10

    sw x1, 0(x0)
    sw x2, 4(x0)
    sw x3, 8(x0)
    sw x4, 12(x0)
    sw x5, 16(x0)
    sw x6, 20(x0)
    sw x7, 24(x0)
    sw x8, 28(x0)
    sw x9, 32(x0)
    sw x10, 36(x0)
    sw x11, 40(x0)
    sw x12, 44(x0)
    sw x13, 48(x0)
    sw x14, 52(x0)
    sw x15, 56(x0)
    sw x16, 60(x0)
    sw x17, 64(x0)
    sw x18, 68(x0)

end_loop:
    j end_loop

handler:
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
