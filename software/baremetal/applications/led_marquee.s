.equ GPIO_BASE, 0x10000000
.equ CLINT_BASE, 0x02000000
#ifndef LED_TIMER_PERIOD
#define LED_TIMER_PERIOD 100000000
#endif
.equ TIMER_PERIOD, LED_TIMER_PERIOD
.equ STACK_TOP, 0x80008000

.section .text
.globl _start

_start:
    # Initialize main stack and interrupt scratch stack before enabling IRQs.
    li sp, STACK_TOP
    csrw mscratch, sp

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
    li x12, 0
    li x11, 1
    xori x13, x11, -1
    sw x13, 4(x10)

    # Setup CLINT Timer: mtimecmp = mtime + TIMER_PERIOD (64-bit safe)
    # Standard SiFive CLINT: mtimecmp@0x4000, mtime@0xBFF8
    lui x15, 0x0200B        # mtime base (0x0200B000)
    li x11, 0xFF8
    add x11, x15, x11       # mtime_lo addr
    lw x16, 0(x11)          # mtime_lo
    li x11, 0xFFC
    add x11, x15, x11       # mtime_hi addr
    lw x14, 0(x11)          # mtime_hi
    li x11, TIMER_PERIOD
    mv x13, x16
    add x16, x16, x11
    sltu x11, x16, x13
    add x14, x14, x11
    lui x15, 0x02004        # mtimecmp base (0x02004000)
    sw x16, 0(x15)          # mtimecmp_lo
    sw x14, 4(x15)          # mtimecmp_hi

loop:
    j loop

.align 4
isr:
    csrrw sp, mscratch, sp
    addi sp, sp, -24
    sw x11, 0(sp)
    sw x13, 4(sp)
    sw x14, 8(sp)
    sw x15, 12(sp)
    sw x16, 16(sp)

    # Update mtimecmp for next interrupt (64-bit safe)
    # Standard SiFive CLINT: mtimecmp@0x4000, mtime@0xBFF8
    lui x15, 0x0200B        # mtime base (0x0200B000)
    li x11, 0xFF8
    add x11, x15, x11       # mtime_lo addr
    lw x16, 0(x11)          # mtime_lo
    li x11, 0xFFC
    add x11, x15, x11       # mtime_hi addr
    lw x14, 0(x11)          # mtime_hi
    li x11, TIMER_PERIOD
    mv x13, x16
    add x16, x16, x11
    sltu x11, x16, x13
    add x14, x14, x11
    lui x15, 0x02004        # mtimecmp base (0x02004000)
    sw x16, 0(x15)          # mtimecmp_lo
    sw x14, 4(x15)          # mtimecmp_hi

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
    lw x15, 12(sp)
    lw x16, 16(sp)
    addi sp, sp, 24
    csrrw sp, mscratch, sp

    mret
