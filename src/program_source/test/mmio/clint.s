# ============================================================
# mmio/clint.s — CLINT register tests
# Category: MMIO
# Description: Test CLINT mtime, mtimecmp, msip registers
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# CLINT base: 0x02000000 (Standard SiFive CLINT layout)
# Register map (axi4lite_clint.sv uses addr[15:0]):
#   0x02000000: msip         (bit 0)
#   0x02004000: mtimecmp_lo  (32-bit)
#   0x02004004: mtimecmp_hi  (32-bit)
#   0x0200BFF8: mtime_lo     (32-bit)
#   0x0200BFFC: mtime_hi     (32-bit)
# ============================================================

.equ CLINT_BASE,  0x02000000
.equ MTIMECMP_LO, 0x02004000
.equ MTIMECMP_HI, 0x02004004
.equ MTIME_LO,    0x0200BFF8
.equ MTIME_HI,    0x0200BFFC

.section .text.start
.globl _start

_start:
    la x10, m_trap_count
    csrw mtvec, x10
    li x10, 0x1880
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_mtime_nonzero
    jal x1, test_run
    la x11, test_mtime_increments
    jal x1, test_run
    la x11, test_mtimecmp_rw
    jal x1, test_run
    la x11, test_timer_irq_fires
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: mtime reads non-zero after boot ──
test_mtime_nonzero:
    lui  x10, 0x0200B         # x10 = 0x0200B000
    li   x11, 0xFF8
    add  x11, x10, x11        # x11 = 0x0200BFF8 = mtime_lo
    lw   x12, 0(x11)          # x12 = mtime_lo

    li   x11, 0xFFC
    add  x11, x10, x11        # x11 = 0x0200BFFC = mtime_hi
    lw   x13, 0(x11)          # x13 = mtime_hi

    # mtime should be non-zero (some cycles have passed since reset)
    or   x14, x12, x13
    li   x10, 1
    bnez x14, 1f
    li   x10, 0
1:  ret


# ── Sub-test 2: mtime increments over time ──
test_mtime_increments:
    lui  x10, 0x0200B
    li   x11, 0xFF8
    add  x11, x10, x11        # x11 = mtime_lo addr
    lw   x12, 0(x11)          # x12 = mtime_lo (first read)

    # Small delay (50 iterations)
    li   x15, 50
1:
    addi x15, x15, -1
    bnez x15, 1b

    lw   x13, 0(x11)          # x13 = mtime_lo (second read)

    # Second read should be > first read (mtime always increments)
    li   x10, 1
    bgt  x13, x12, 2f
    li   x10, 0
2:  ret


# ── Sub-test 3: mtimecmp write/read roundtrip ──
test_mtimecmp_rw:
    # Disable interrupts during this test
    li   x10, 0x1880
    csrw mstatus, x10

    # Write a known value to mtimecmp
    lui  x10, 0x02004         # x10 = 0x02004000
    li   x11, 0x12345678
    sw   x11, 0(x10)          # mtimecmp_lo = 0x12345678
    li   x11, 0x9ABCDEF0
    sw   x11, 4(x10)          # mtimecmp_hi = 0x9ABCDEF0

    # Read back and verify
    lw   x12, 0(x10)          # read mtimecmp_lo
    li   x11, 0x12345678
    bne  x12, x11, _mcmp_fail

    lw   x12, 4(x10)          # read mtimecmp_hi
    li   x11, 0x9ABCDEF0
    bne  x12, x11, _mcmp_fail

    # Restore mtimecmp to far future (prevent spurious timer interrupt)
    li   x11, -1              # 0xFFFFFFFF
    sw   x11, 0(x10)          # mtimecmp_lo = max
    sw   x11, 4(x10)          # mtimecmp_hi = max

    li   x10, 1
    ret
_mcmp_fail:
    # Restore mtimecmp on failure too
    lui  x10, 0x02004
    li   x11, -1
    sw   x11, 0(x10)
    sw   x11, 4(x10)
    li   x10, 0
    ret


# ── Sub-test 4: Timer interrupt fires after mtimecmp set ──
test_timer_irq_fires:
    # Clear interrupt count
    addi x23, x0, 0

    # Disable interrupts during setup
    li   x10, 0x1880
    csrw mstatus, x10

    # Read current mtime
    lui  x14, 0x0200B
    li   x15, 0xFF8
    add  x15, x14, x15        # mtime_lo addr
    lw   x16, 0(x15)          # mtime_lo
    li   x15, 0xFFC
    add  x15, x14, x15        # mtime_hi addr
    lw   x17, 0(x15)          # mtime_hi

    # Set mtimecmp = mtime + 100 (short delay)
    addi x16, x16, 100
    lui  x15, 0x02004         # mtimecmp base
    sw   x16, 0(x15)          # mtimecmp_lo
    sw   x17, 4(x15)          # mtimecmp_hi

    # Enable timer interrupt (MIE.MTIE=1)
    li   x15, 0x080
    csrw mie, x15

    # Enable global interrupt (MSTATUS.MIE=1)
    li   x15, 0x1888
    csrw mstatus, x15

    # Wait for interrupt (busy loop)
    li   x15, 300
1:
    addi x15, x15, -1
    bnez x15, 1b

    # Disable interrupts before checking
    li   x10, 0x1880
    csrw mstatus, x10

    # Restore mtimecmp to far future
    lui  x10, 0x02004
    li   x11, -1
    sw   x11, 0(x10)
    sw   x11, 4(x10)

    # Check: x23 should be > 0 (interrupt fired)
    li   x10, 1
    bnez x23, 2f
    li   x10, 0
2:  ret
