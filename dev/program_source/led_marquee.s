.equ GPIO_BASE, 0x10000000
.equ TIMER_BASE, 0x10004000
.equ TIMER_PERIOD, 1000

.section .text
.globl _start

_start:
    # Setup mtvec
    la t0, isr
    csrw mtvec, t0

    # Enable MTIE in mie (bit 7)
    li t0, 0x80
    csrw mie, t0

    # Enable MIE in mstatus (bit 3)
    li t0, 0x8
    csrw mstatus, t0

    # Initialize GPIO direction (all output)
    lui x10, 0x10000
    li x11, 0xFFFF
    sw x11, 0(x10)

    # Initialize LED state
    li x12, 0       # x12 will be our counter (0-15)
    li x11, 1
    xori x13, x11, -1
    sw x13, 4(x10)

    # Setup Timer
    lui x15, 0x10004
    li x16, TIMER_PERIOD
    sw x16, 0(x15)  # expr_val = TIMER_PERIOD
    li x16, 3
    sw x16, 4(x15)  # start = 1, mode = 1 (periodic)

loop:
    j loop

.align 4
isr:
    # We should preserve registers we use, but this is simple CPU, just save to mscratch
    csrrw sp, mscratch, sp
    addi sp, sp, -16
    sw x11, 0(sp)
    sw x13, 4(sp)
    sw x14, 8(sp)

    # Clear Timer IRQ
    lui x15, 0x10004
    sw x0, 8(x15)

    # Update LED state
    addi x12, x12, 1
    li x11, 16
    bne x12, x11, skip_reset
    li x12, 0
skip_reset:
    lui x10, 0x10000
    li x11, 1
    sll x13, x11, x12
    xori x13, x13, -1
    sw x13, 4(x10)

    lw x11, 0(sp)
    lw x13, 4(sp)
    lw x14, 8(sp)
    addi sp, sp, 16
    csrrw sp, mscratch, sp

    mret
