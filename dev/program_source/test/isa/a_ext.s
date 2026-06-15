# ============================================================
# isa/a_ext.s — A extension (Atomic) instruction tests
# Category: ISA
# Description: Test LR.W/SC.W/AMOSWAP/AMOADD/AMOAND/AMOOR/AMOXOR/AMOMIN/AMOMAX/AMOMINU/AMOMAXU
# Sub-tests: 16
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_lr_w_basic
    jal x1, test_run
    la x11, test_sc_w_success
    jal x1, test_run
    la x11, test_sc_w_fail_no_lr
    jal x1, test_run
    la x11, test_sc_w_fail_after_store
    jal x1, test_run
    la x11, test_amoswap_w
    jal x1, test_run
    la x11, test_amoadd_w
    jal x1, test_run
    la x11, test_amoand_w
    jal x1, test_run
    la x11, test_amoor_w
    jal x1, test_run
    la x11, test_amoxor_w
    jal x1, test_run
    la x11, test_amomin_w
    jal x1, test_run
    la x11, test_amomax_w
    jal x1, test_run
    la x11, test_amominu_w
    jal x1, test_run
    la x11, test_amomaxu_w
    jal x1, test_run
    la x11, test_lr_sc_mutex
    jal x1, test_run
    la x11, test_amoadd_accumulate
    jal x1, test_run
    la x11, test_amoswap_swap_values
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# Base address for test data: 0x80001000
.equ TEST_BASE, 0x80001000

# ── LR.W basic: load and read value ──
test_lr_w_basic:
    li x14, TEST_BASE
    li x15, 0xAAAA5555
    sw x15, 0(x14)
    lr.w x16, (x14)
    li x10, 0
    li x17, 0xAAAA5555
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SC.W success: LR then SC at same address ──
test_sc_w_success:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    lr.w x16, (x14)
    li x22, 0xDEADBEEF
    sc.w x23, x22, (x14)
    # x23 should be 0 (success)
    li x10, 0
    bne x23, x0, 1f
    # verify memory was updated
    lw x24, 0(x14)
    li x25, 0xDEADBEEF
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── SC.W fail: SC without preceding LR ──
test_sc_w_fail_no_lr:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    # No LR before SC — reservation should be invalid
    li x22, 0x22222222
    sc.w x23, x22, (x14)
    # x23 should be non-zero (failure)
    li x10, 0
    beq x23, x0, 1f
    # verify memory was NOT updated
    lw x24, 0(x14)
    li x25, 0x11111111
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── SC.W fail: LR then SW then SC (store invalidates reservation) ──
test_sc_w_fail_after_store:
    li x14, TEST_BASE
    li x15, 0x33333333
    sw x15, 0(x14)
    lr.w x16, (x14)
    # A normal store to the same address invalidates the reservation
    li x22, 0x44444444
    sw x22, 0(x14)
    li x22, 0x55555555
    sc.w x23, x22, (x14)
    # x23 should be non-zero (failure)
    li x10, 0
    beq x23, x0, 1f
    # verify memory still has the SW value (0x44444444)
    lw x24, 0(x14)
    li x25, 0x44444444
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOSWAP.W: swap value ──
test_amoswap_w:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x22, 0xBBBBBBBB
    amoswap.w x16, x22, (x14)
    # x16 should be old value (0xAAAAAAAA)
    li x10, 0
    li x17, 0xAAAAAAAA
    bne x16, x17, 1f
    # memory should now be 0xBBBBBBBB
    lw x24, 0(x14)
    li x25, 0xBBBBBBBB
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOADD.W: add value ──
test_amoadd_w:
    li x14, TEST_BASE
    li x15, 100
    sw x15, 0(x14)
    li x22, 50
    amoadd.w x16, x22, (x14)
    # x16 should be old value (100)
    li x10, 0
    li x17, 100
    bne x16, x17, 1f
    # memory should now be 150
    lw x24, 0(x14)
    li x25, 150
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOAND.W: and value ──
test_amoand_w:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoand.w x16, x22, (x14)
    # x16 should be old value (0xFF00FF00)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f
    # memory should now be 0xFF00FF00 & 0x0F0F0F0F = 0x0F000F00
    lw x24, 0(x14)
    li x25, 0x0F000F00
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOOR.W: or value ──
test_amoor_w:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoor.w x16, x22, (x14)
    # x16 should be old value (0xFF00FF00)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f
    # memory should now be 0xFF00FF00 | 0x0F0F0F0F = 0xFF0FFF0F
    lw x24, 0(x14)
    li x25, 0xFF0FFF0F
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOXOR.W: xor value ──
test_amoxor_w:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoxor.w x16, x22, (x14)
    # x16 should be old value (0xFF00FF00)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f
    # memory should now be 0xFF00FF00 ^ 0x0F0F0F0F = 0xF00FF00F
    lw x24, 0(x14)
    li x25, 0xF00FF00F
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOMIN.W: signed minimum ──
test_amomin_w:
    li x14, TEST_BASE
    li x15, -10          # 0xFFFFFFF6
    sw x15, 0(x14)
    li x22, 5
    amomin.w x16, x22, (x14)
    # x16 should be old value (-10)
    li x10, 0
    li x17, -10
    bne x16, x17, 1f
    # memory should now be min(-10, 5) = -10
    lw x24, 0(x14)
    li x25, -10
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOMAX.W: signed maximum ──
test_amomax_w:
    li x14, TEST_BASE
    li x15, -10          # 0xFFFFFFF6
    sw x15, 0(x14)
    li x22, 5
    amomax.w x16, x22, (x14)
    # x16 should be old value (-10)
    li x10, 0
    li x17, -10
    bne x16, x17, 1f
    # memory should now be max(-10, 5) = 5
    lw x24, 0(x14)
    li x25, 5
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOMINU.W: unsigned minimum ──
test_amominu_w:
    li x14, TEST_BASE
    li x15, 0xFFFFFFFE  # unsigned: 4294967294
    sw x15, 0(x14)
    li x22, 5
    amominu.w x16, x22, (x14)
    # x16 should be old value (0xFFFFFFFE)
    li x10, 0
    li x17, 0xFFFFFFFE
    bne x16, x17, 1f
    # memory should now be minu(0xFFFFFFFE, 5) = 5
    lw x24, 0(x14)
    li x25, 5
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOMAXU.W: unsigned maximum ──
test_amomaxu_w:
    li x14, TEST_BASE
    li x15, 0xFFFFFFFE  # unsigned: 4294967294
    sw x15, 0(x14)
    li x22, 5
    amomaxu.w x16, x22, (x14)
    # x16 should be old value (0xFFFFFFFE)
    li x10, 0
    li x17, 0xFFFFFFFE
    bne x16, x17, 1f
    # memory should now be maxu(0xFFFFFFFE, 5) = 0xFFFFFFFE
    lw x24, 0(x14)
    li x25, 0xFFFFFFFE
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── LR/SC mutex: simple lock acquire/release ──
test_lr_sc_mutex:
    li x14, TEST_BASE
    sw x0, 0(x14)           # lock = 0 (unlocked)
    # Try to acquire lock
1:
    lr.w x16, (x14)         # read lock
    bne x16, x0, 1b         # if locked, retry
    li x22, 1               # locked value
    sc.w x23, x22, (x14)    # try to set lock
    bne x23, x0, 1b         # if SC failed, retry
    # Lock acquired — verify lock is 1
    lw x24, 0(x14)
    li x10, 0
    li x25, 1
    bne x24, x25, 2f
    # Release lock
    sw x0, 0(x14)
    li x10, 1
2:
    ret

# ── AMOADD.W accumulate: multiple adds ──
test_amoadd_accumulate:
    li x14, TEST_BASE
    sw x0, 0(x14)           # counter = 0
    li x22, 1
    amoadd.w x16, x22, (x14)   # counter = 1, x16 = 0
    amoadd.w x16, x22, (x14)   # counter = 2, x16 = 1
    amoadd.w x16, x22, (x14)   # counter = 3, x16 = 2
    # verify counter is 3
    lw x24, 0(x14)
    li x10, 0
    li x25, 3
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── AMOSWAP.W swap values twice ──
test_amoswap_swap_values:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    li x22, 0x22222222
    amoswap.w x16, x22, (x14)   # x16=0x11111111, mem=0x22222222
    li x22, 0x33333333
    amoswap.w x17, x22, (x14)   # x17=0x22222222, mem=0x33333333
    li x10, 0
    li x23, 0x11111111
    bne x16, x23, 1f
    li x23, 0x22222222
    bne x17, x23, 1f
    lw x24, 0(x14)
    li x25, 0x33333333
    bne x24, x25, 1f
    li x10, 1
1:
    ret
