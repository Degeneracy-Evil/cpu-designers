.section .text
.globl _start

_start:
    lui  x21, 0x80001
    lui  x22, 0x80002

    li   x10, 0xDEADBEEF
    sw   x10, 0(x21)
    fence.i
    lw   x11, 0(x21)

    li   x10, 0x02A00513
    sw   x10, 0(x22)
    li   x10, 0x00028067
    sw   x10, 4(x22)
    fence.i
    la   x5, jit_return1
    jalr x0, x22, 0
jit_return1:

    li   x10, 0x12345678
    sw   x10, 4(x21)
    li   x10, 0xABCDEF01
    sw   x10, 8(x21)
    fence.i
    lw   x12, 4(x21)
    lw   x13, 8(x21)

    fence.i
    lw   x14, 0(x21)

    li   x10, 0xCAFE
    sh   x10, 12(x21)
    li   x10, 0x42
    sb   x10, 14(x21)
    fence.i
    lhu  x15, 12(x21)
    lb   x16, 14(x21)

    li   x10, 0x0FF06513
    sw   x10, 0(x22)
    fence.i
    la   x5, jit_return2
    jalr x0, x22, 0
jit_return2:

end_loop:
    j    end_loop
