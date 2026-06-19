.equ CLINT_BASE, 0x02000000

.section .text
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10
    li x10, 0x080
    csrw mie, x10

    csrw mscratch, x0

    # Set mtimecmp to far-future BEFORE enabling MTIE to prevent
    # premature timer interrupt (MTIP=1 at reset if mtimecmp=0)
    lui  x10, 0x02004        # mtimecmp base (0x02004000)
    li   x11, 0xFFFFFFFF
    sw   x11, 0(x10)         # mtimecmp_lo = 0xFFFFFFFF
    li   x11, 0xFFFFFFFF
    sw   x11, 4(x10)         # mtimecmp_hi = 0xFFFFFFFF

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

    addi x23, x0, 0

    li x10, 0x1888
    csrw mstatus, x10

    # Standard SiFive CLINT: mtimecmp@0x4000, mtime@0xBFF8
    lui x10, 0x0200B        # mtime base (0x0200B000)
    li x11, 0xFF8
    add x11, x10, x11       # mtime_lo addr
    lw x11, 0(x11)          # mtime_lo
    li x12, 0xFFC
    add x12, x10, x12       # mtime_hi addr
    lw x12, 0(x12)          # mtime_hi
    mv x13, x11
    addi x11, x11, 200
    sltu x13, x11, x13
    add x12, x12, x13
    lui x10, 0x02004        # mtimecmp base (0x02004000)
    sw x11, 0(x10)          # mtimecmp_lo
    sw x12, 4(x10)          # mtimecmp_hi

    li x25, 80
1:
    addi x25, x25, -1
    bnez x25, 1b

    li x10, 0x80001054
    sw x23, 0(x10)
    li x10, 0x80001058
    sw x19, 0(x10)
    fence.i                     # flush dcache so TB can read stores from BRAM

end_loop:
    j end_loop

trap_handler:
    csrrs x19, mcause, x0
    srli x24, x19, 31
    bnez x24, timer_int_handler

    csrrs x20, mepc, x0
    addi x20, x20, 4
    csrw mepc, x20
    csrrs x21, mscratch, x0
    slli x21, x21, 2
    addi x22, x21, 72
    lui  x21, 0x80001
    add  x22, x22, x21
    sw x19, 0(x22)
    csrrs x21, mscratch, x0
    addi x21, x21, 1
    csrw mscratch, x21
    li x10, 0x1880
    csrw mstatus, x10
    mret

timer_int_handler:
    addi x23, x23, 1
    # Set mtimecmp to far-future to prevent immediate re-fire
    # (old code set mtimecmp=0 which caused infinite re-trap)
    lui x10, 0x02004        # mtimecmp base (0x02004000)
    li  x11, 0xFFFFFFFF
    sw  x11, 0(x10)         # mtimecmp_lo = 0xFFFFFFFF
    sw  x11, 4(x10)         # mtimecmp_hi = 0xFFFFFFFF
    li x10, 0x1888
    csrw mstatus, x10
    mret
