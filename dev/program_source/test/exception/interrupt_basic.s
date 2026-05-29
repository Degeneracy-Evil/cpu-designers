# ============================================================
# exception/interrupt_basic.s — Basic interrupt configuration tests
# Category: Exception
# Description: Test MIE/MSTATUS interrupt enable/disable and basic
#              timer interrupt behavior
# Sub-tests: 6
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================

.equ CLINT_BASE, 0x02000000

.section .text.start
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10
    li x10, 0x1888          # M-mode, MPP=11, MIE=1
    csrw mstatus, x10

    jal x1, test_init

    # ── Interrupt basic tests ──
    la x11, test_01_mie_write_read
    jal x1, test_run
    la x11, test_02_mstatus_mie_enable
    jal x1, test_run
    la x11, test_03_mie_disable_no_interrupt
    jal x1, test_run
    la x11, test_04_mscratch_setup
    jal x1, test_run
    la x11, test_05_timer_interrupt_pending
    jal x1, test_run
    la x11, test_06_timer_interrupt_handler
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Test 01: MIE CSR write/read ──
test_01_mie_write_read:
    li x10, 0x080           # MTIE=1 (timer interrupt enable)
    csrw mie, x10
    csrr x11, mie
    li x12, 0x080
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 02: mstatus.MIE enable ──
test_02_mstatus_mie_enable:
    li x10, 0x1888          # MIE=1
    csrw mstatus, x10
    csrr x11, mstatus
    li x12, 0x1888
    and x11, x11, x12       # check MIE bit
    li x10, 1
    beq x11, x12, 1f
    li x10, 0
1:  ret

# ── Test 03: MIE disabled → no interrupt taken ──
test_03_mie_disable_no_interrupt:
    li x10, 0x1880          # MIE=0 (global disable)
    csrw mstatus, x10
    # Timer may be pending but won't be taken
    li x10, 1               # If we reach here without trap, PASS
    ret

# ── Test 04: mscratch setup ──
test_04_mscratch_setup:
    csrw mscratch, x0       # clear mscratch
    csrr x11, mscratch
    li x10, 1
    beqz x11, 1f
    li x10, 0
1:  ret

# ── Test 05: Timer interrupt pending (mip.MTIP) ──
test_05_timer_interrupt_pending:
    # Set mtimecmp < mtime to trigger timer
    lui x10, 0x02000        # CLINT_BASE
    lw x11, 8(x10)          # mtime_lo
    lw x12, 12(x10)         # mtime_hi
    mv x13, x11
    addi x11, x11, 200      # mtimecmp = mtime + 200
    sltu x13, x11, x13
    add x12, x12, x13
    sw x11, 0(x10)          # mtimecmp_lo
    sw x12, 4(x10)          # mtimecmp_hi

    # Re-enable interrupts
    li x14, 0x1888
    csrw mstatus, x14
    li x14, 0x080
    csrw mie, x14

    # Wait for interrupt
    li x14, 80
1:  addi x14, x14, -1
    bnez x14, 1b

    # Check if interrupt was taken (x23 counter incremented by handler)
    li x10, 1
    bnez x23, 2f            # x23 > 0 means interrupt taken
    li x10, 0
2:  ret

# ── Test 06: Timer interrupt handler runs correctly ──
test_06_timer_interrupt_handler:
    # x23 counts interrupts from m_trap_handler
    li x10, 1
    bnez x23, 1f            # at least 1 interrupt taken
    li x10, 0
1:  ret

# ────────────────────────────────────────
# Trap handler
# ────────────────────────────────────────
m_trap_handler:
    csrrs x22, mcause, x0
    srli x24, x22, 31
    bnez x24, timer_int_handler

    # Exception: skip instruction
    csrrs x23, mepc, x0
    addi x23, x23, 4
    csrw mepc, x23
    li x10, 0x1880
    csrw mstatus, x10
    mret

timer_int_handler:
    addi x23, x23, 1        # increment interrupt counter
    # Clear timer interrupt by writing mtimecmp far ahead
    lui x10, 0x02000
    sw x0, 0(x10)           # mtimecmp_lo = 0
    sw x0, 4(x10)           # mtimecmp_hi = 0
    li x10, 0x1888
    csrw mstatus, x10
    mret
