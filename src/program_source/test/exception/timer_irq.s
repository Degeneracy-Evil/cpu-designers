# ============================================================
# exception/timer_irq.s — Timer interrupt tests
# Category: Exception
# Description: Test CLINT timer interrupt (mcause=0x80000007)
# Sub-tests: 2
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# CLINT base: 0x02000000
#   +0x0000: msip
#   +0x4000: mtimecmp (low)
#   +0x4004: mtimecmp (high)
#   +0xBFF8: mtime (low)
#   +0xBFFC: mtime (high)
# ============================================================

.equ CLINT_BASE, 0x02000000
.equ MTIME_OFFSET, 0xBFF8
.equ MTIMECMP_OFFSET, 0x4000

.section .text.start
.globl _start

_start:
    la x10, m_trap_count
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_timer_irq_fires
    jal x1, test_run
    la x11, test_timer_irq_clear
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Timer interrupt fires: x23 (count) increments ──
test_timer_irq_fires:
    # Clear interrupt count
    addi x23, x0, 0

    # Disable interrupts during setup
    li x10, 0x1880
    csrw mstatus, x10

    # Read current mtime
    lui x14, 0x02000         # x14 = 0x02000000 (CLINT base)
    li x15, 0xBFF8           # mtime offset
    add x15, x14, x15        # x15 = mtime addr
    lw x16, 0(x15)           # mtime low
    li x15, 0xBFFC           # mtime+4 offset
    add x15, x14, x15        # x15 = mtime+4 addr
    lw x17, 0(x15)           # mtime high

    # Set mtimecmp = mtime + 100 (short delay)
    addi x16, x16, 100
    li x15, 0x4000           # mtimecmp offset
    add x15, x14, x15        # x15 = mtimecmp addr
    sw x16, 0(x15)           # mtimecmp low
    li x15, 0x4004           # mtimecmp+4 offset
    add x15, x14, x15        # x15 = mtimecmp+4 addr
    sw x17, 0(x15)           # mtimecmp high

    # Enable timer interrupt (MIE.MTIE=1)
    li x15, 0x080
    csrw mie, x15

    # Enable global interrupt (MSTATUS.MIE=1)
    li x15, 0x1888
    csrw mstatus, x15

    # Wait for interrupt (busy loop, ~300 cycles)
    li x15, 300
1:
    addi x15, x15, -1
    bnez x15, 1b

    # Disable interrupts before checking result
    li x10, 0x1880
    csrw mstatus, x10

    # Check: x23 should be > 0 (interrupt fired)
    li x10, 0
    bnez x23, 2f
    ret                      # x23=0 → FAIL
2:
    li x10, 1
    ret

# ── Timer interrupt clear: writing mtimecmp stops interrupts ──
test_timer_irq_clear:
    li x10, 0
    lui x14, 0x02000
    li x15, -1               # 0xFFFFFFFF
    li x16, 0x4000           # mtimecmp offset
    add x16, x14, x16        # mtimecmp addr
    sw x15, 0(x16)           # mtimecmp low = max
    li x16, 0x4004           # mtimecmp+4 offset
    add x16, x14, x16        # mtimecmp+4 addr
    sw x15, 0(x16)           # mtimecmp high = max

    # Save current count
    addi x22, x23, 0

    # Wait a bit
    li x15, 100
1:
    addi x15, x15, -1
    bnez x15, 1b

    # x23 should not have incremented (no new interrupts)
    beq x23, x22, 2f
    ret                      # x23 changed → FAIL
2:
    li x10, 1
    ret
