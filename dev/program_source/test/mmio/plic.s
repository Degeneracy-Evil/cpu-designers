# ============================================================
# mmio/plic.s — PLIC register tests
# Category: MMIO
# Description: Test PLIC priority, threshold, enable, claim registers
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# PLIC base: 0x0C000000 (HADDR[31:24] == 0x0C)
# Register map — SiFive PLIC standard layout (dual-context):
#   Priority[src]:    0x0C000000 + src*4  (src 0-7, src 0 reserved)
#   Pending:          0x0C001000
#   Enable[ctx0 M]:   0x0C002000
#   Enable[ctx1 S]:   0x0C002080
#   Threshold[ctx0]:  0x0C200000
#   Claim[ctx0]:      0x0C200004
#   Threshold[ctx1]:  0x0C201000
#   Claim[ctx1]:      0x0C201004
# NUM_SRC = 8 (src 1=timer, 2=uart, 3=spi, 4=gpio)
# ============================================================

.equ PLIC_BASE,    0x0C000000
.equ PLIC_PRIO1,   0x0C000004   # Priority[1] (timer)
.equ PLIC_PRIO2,   0x0C000008   # Priority[2] (uart)
.equ PLIC_PENDING, 0x0C001000
.equ PLIC_ENABLE,  0x0C002000   # Enable context 0 (M-mode)
.equ PLIC_ENABLE_S,0x0C002080   # Enable context 1 (S-mode)
.equ PLIC_THRESH,  0x0C200000   # Threshold context 0 (M-mode)
.equ PLIC_CLAIM,   0x0C200004   # Claim context 0 (M-mode)
.equ PLIC_THRESH_S,0x0C201000   # Threshold context 1 (S-mode)
.equ PLIC_CLAIM_S, 0x0C201004   # Claim context 1 (S-mode)

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10

    jal x1, test_init

    la x11, test_plic_priority_rw
    jal x1, test_run
    la x11, test_plic_threshold_rw
    jal x1, test_run
    la x11, test_plic_enable_rw
    jal x1, test_run
    la x11, test_plic_claim_read
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: Priority register write/read ──
test_plic_priority_rw:
    # Write priority[1] = 5
    lui  x10, 0x0C000         # x10 = 0x0C000000
    li   x11, 5
    sw   x11, 4(x10)          # Priority[1] = 5 (offset 4)

    # Read back
    lw   x12, 4(x10)
    li   x11, 5
    bne  x12, x11, _prio_fail

    # Write priority[2] = 7
    li   x11, 7
    sw   x11, 8(x10)          # Priority[2] = 7 (offset 8)

    # Read back
    lw   x12, 8(x10)
    li   x11, 7
    bne  x12, x11, _prio_fail

    # Clean up: set priorities back to 0
    sw   x0, 4(x10)
    sw   x0, 8(x10)

    li   x10, 1
    ret
_prio_fail:
    # Clean up on failure
    lui  x10, 0x0C000
    sw   x0, 4(x10)
    sw   x0, 8(x10)
    li   x10, 0
    ret


# ── Sub-test 2: Threshold register write/read ──
test_plic_threshold_rw:
    # Write threshold = 3
    lui  x10, 0x0C200         # x10 = 0x0C200000
    li   x11, 3
    sw   x11, 0(x10)          # Threshold = 3

    # Read back
    lw   x12, 0(x10)
    li   x11, 3
    bne  x12, x11, _thresh_fail

    # Clean up: set threshold back to 0
    sw   x0, 0(x10)

    li   x10, 1
    ret
_thresh_fail:
    # Clean up on failure
    lui  x10, 0x0C200
    sw   x0, 0(x10)
    li   x10, 0
    ret


# ── Sub-test 3: Enable register write/read ──
test_plic_enable_rw:
    # Enable register at 0x0C002000 (SiFive standard: ctx0 M-mode)
    # offset 0x2000 exceeds 12-bit signed imm, use li+add
    lui  x10, 0x0C000         # x10 = 0x0C000000
    li   x13, 0x2000
    add  x13, x10, x13        # x13 = 0x0C002000 (Enable ctx0 addr)

    # Write enable = 0x0F (enable sources 0-3)
    li   x11, 0x0F
    sw   x11, 0(x13)

    # Read back
    lw   x12, 0(x13)
    li   x11, 0x0F
    bne  x12, x11, _en_fail

    # Clean up: disable all
    sw   x0, 0(x13)

    li   x10, 1
    ret
_en_fail:
    # Clean up on failure
    lui  x10, 0x0C000
    li   x13, 0x2000
    add  x13, x10, x13
    sw   x0, 0(x13)
    li   x10, 0
    ret


# ── Sub-test 4: Claim register read (no pending → returns 0) ──
test_plic_claim_read:
    # With no interrupts pending and threshold=0, claim should return 0
    # (or the highest pending ID if any; with no sources asserted, it's 0)

    # First ensure no sources are enabled (Enable at 0x0C002000, SiFive standard)
    lui  x10, 0x0C000
    li   x13, 0x2000
    add  x13, x10, x13        # x13 = 0x0C002000
    sw   x0, 0(x13)           # Enable = 0

    # Threshold at 0x0C200000
    lui  x10, 0x0C200
    sw   x0, 0(x10)           # Threshold = 0

    # Read claim register (0x0C200004, SiFive standard: offset 4 from ctx0 base)
    lw   x12, 4(x10)          # Claim (offset 0x4 from 0x0C200000)

    # With no pending interrupts, claim should return 0
    bnez x12, _claim_fail

    li   x10, 1
    ret
_claim_fail:
    li   x10, 0
    ret
