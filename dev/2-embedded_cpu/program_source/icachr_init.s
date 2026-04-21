.section .text
.globl _start

_start:
    addi x1, x0, 5          # x1 = 0 + 5
    addi x2, x0, 7          # x2 = 0 + 7
    add x3, x1, x2          # x3 = x1 + x2
    lui x4, 0x12345         # x4 = 0x12345 << 12
    addi x5, x4, 1          # x5 = x4 + 1
    add x6, x3, x5          # x6 = x3 + x5
    addi x10, x0, 0         # x10 = 0
    sw x1, 0(x10)           # 将 x1 存入地址 x10 + 0
    sw x2, 4(x10)           # 将 x2 存入地址 x10 + 4
    sw x3, 8(x10)           # 将 x3 存入地址 x10 + 8
    sw x4, 12(x10)          # 将 x4 存入地址 x10 + 12
    addi x10, x0, 12        # x10 = 12

end_loop:
    j end_loop
