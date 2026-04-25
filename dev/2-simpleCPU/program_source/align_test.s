.section .text
.globl _start

_start:
    addi x1, x0, 0

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

    addi x1, x0, 1

end_loop:
    j end_loop
