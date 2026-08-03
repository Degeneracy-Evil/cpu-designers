# ============================================================
# isa/a_ext.s — A extension (Atomic) instruction tests
# Category: ISA
# Description: Comprehensive test for LR.W/SC.W and all AMO operations
#              covering basic functionality, edge/boundary values,
#              LR/SC-AMO interactions, rd=x0 cases, and sequential chains
# Sub-tests: 52
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

    # ── Group 1: LR.W (Load Reserved) ──
    la x11, test_01_lr_w_basic
    jal x1, test_run
    la x11, test_02_lr_w_x0
    jal x1, test_run
    la x11, test_03_lr_w_multiple_same
    jal x1, test_run
    la x11, test_04_lr_w_different_addr
    jal x1, test_run

    # ── Group 2: SC.W (Store Conditional) ──
    la x11, test_05_sc_w_success
    jal x1, test_run
    la x11, test_06_sc_w_fail_no_lr
    jal x1, test_run
    la x11, test_07_sc_w_fail_after_store
    jal x1, test_run
    la x11, test_08_sc_w_fail_after_amo
    jal x1, test_run
    la x11, test_09_sc_w_fail_lr_different_addr
    jal x1, test_run
    la x11, test_10_sc_w_then_sc_fail
    jal x1, test_run
    la x11, test_11_sc_w_rs2_zero
    jal x1, test_run

    # ── Group 3: AMOSWAP.W ──
    la x11, test_12_amoswap_w_basic
    jal x1, test_run
    la x11, test_13_amoswap_w_twice
    jal x1, test_run
    la x11, test_14_amoswap_w_zero
    jal x1, test_run
    la x11, test_15_amoswap_w_all_ones
    jal x1, test_run

    # ── Group 4: AMOADD.W ──
    la x11, test_16_amoadd_w_basic
    jal x1, test_run
    la x11, test_17_amoadd_w_accumulate
    jal x1, test_run
    la x11, test_18_amoadd_w_zero
    jal x1, test_run
    la x11, test_19_amoadd_w_overflow
    jal x1, test_run
    la x11, test_20_amoadd_w_neg
    jal x1, test_run

    # ── Group 5: AMOAND.W ──
    la x11, test_21_amoand_w_basic
    jal x1, test_run
    la x11, test_22_amoand_w_all_ones
    jal x1, test_run
    la x11, test_23_amoand_w_zero
    jal x1, test_run
    la x11, test_24_amoand_w_self
    jal x1, test_run

    # ── Group 6: AMOOR.W ──
    la x11, test_25_amoor_w_basic
    jal x1, test_run
    la x11, test_26_amoor_w_zero
    jal x1, test_run
    la x11, test_27_amoor_w_all_ones
    jal x1, test_run
    la x11, test_28_amoor_w_self
    jal x1, test_run

    # ── Group 7: AMOXOR.W ──
    la x11, test_29_amoxor_w_basic
    jal x1, test_run
    la x11, test_30_amoxor_w_zero
    jal x1, test_run
    la x11, test_31_amoxor_w_self
    jal x1, test_run
    la x11, test_32_amoxor_w_double_restore
    jal x1, test_run

    # ── Group 8: AMOMIN.W (signed) ──
    la x11, test_33_amomin_w_basic
    jal x1, test_run
    la x11, test_34_amomin_w_both_neg
    jal x1, test_run
    la x11, test_35_amomin_w_equal
    jal x1, test_run
    la x11, test_36_amomin_w_boundary
    jal x1, test_run

    # ── Group 9: AMOMAX.W (signed) ──
    la x11, test_37_amomax_w_basic
    jal x1, test_run
    la x11, test_38_amomax_w_both_neg
    jal x1, test_run
    la x11, test_39_amomax_w_equal
    jal x1, test_run
    la x11, test_40_amomax_w_boundary
    jal x1, test_run

    # ── Group 10: AMOMINU.W (unsigned) ──
    la x11, test_41_amominu_w_basic
    jal x1, test_run
    la x11, test_42_amominu_w_both_large
    jal x1, test_run
    la x11, test_43_amominu_w_equal
    jal x1, test_run
    la x11, test_44_amominu_w_with_zero
    jal x1, test_run

    # ── Group 11: AMOMAXU.W (unsigned) ──
    la x11, test_45_amomaxu_w_basic
    jal x1, test_run
    la x11, test_46_amomaxu_w_both_large
    jal x1, test_run
    la x11, test_47_amomaxu_w_equal
    jal x1, test_run
    la x11, test_48_amomaxu_w_with_zero
    jal x1, test_run

    # ── Group 12: LR/SC interaction & mutex ──
    la x11, test_49_lr_sc_mutex
    jal x1, test_run
    la x11, test_50_lr_sc_amo_invalidate
    jal x1, test_run

    # ── Group 13: AMO rd=x0 (memory still updated) ──
    la x11, test_51_amoadd_w_rd_x0
    jal x1, test_run
    la x11, test_52_amoswap_w_rd_x0
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# Base addresses for test data
.equ TEST_BASE, 0x80001000
.equ TEST_BASE2, 0x80002000


# ============================================================
# Group 1: LR.W (Load Reserved)
# ============================================================

# ── Test 1: LR.W basic — load and verify value ──
test_01_lr_w_basic:
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

# ── Test 2: LR.W with rd=x0 — still sets reservation, value discarded ──
# Verify reservation was set by doing a subsequent SC that should succeed
test_02_lr_w_x0:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    lr.w x0, (x14)            # rd=x0, reservation still set
    li x22, 0xDEADBEEF
    sc.w x23, x22, (x14)      # Should succeed (return 0) since LR set reservation
    li x10, 0
    bne x23, x0, 1f           # SC should return 0
    lw x24, 0(x14)
    li x25, 0xDEADBEEF
    bne x24, x25, 1f          # Memory should be updated
    li x10, 1
1:
    ret

# ── Test 3: LR.W multiple at same address — each updates reservation ──
test_03_lr_w_multiple_same:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    lr.w x16, (x14)           # First LR
    lr.w x16, (x14)           # Second LR at same addr — refreshes reservation
    li x22, 0x22222222
    sc.w x23, x22, (x14)      # Should succeed (second LR refreshed reservation)
    li x10, 0
    bne x23, x0, 1f
    lw x24, 0(x14)
    li x25, 0x22222222
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 4: LR.W at different addresses — reservation moves ──
# LR at addr A, then LR at addr B, then SC at addr B should succeed
test_04_lr_w_different_addr:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x16, TEST_BASE2
    li x17, 0xBBBBBBBB
    sw x17, 0(x16)
    lr.w x22, (x14)           # LR at addr A
    lr.w x22, (x16)           # LR at addr B — reservation moves to B
    li x22, 0xCCCCCCCC
    sc.w x23, x22, (x16)      # SC at addr B — should succeed
    li x10, 0
    bne x23, x0, 1f
    lw x24, 0(x16)
    li x25, 0xCCCCCCCC
    bne x24, x25, 1f
    li x10, 1
1:
    ret


# ============================================================
# Group 2: SC.W (Store Conditional)
# ============================================================

# ── Test 5: SC.W success — LR then SC at same address ──
test_05_sc_w_success:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    lr.w x16, (x14)
    li x22, 0xDEADBEEF
    sc.w x23, x22, (x14)
    li x10, 0
    bne x23, x0, 1f
    lw x24, 0(x14)
    li x25, 0xDEADBEEF
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 6: SC.W fail — SC without preceding LR ──
test_06_sc_w_fail_no_lr:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    li x22, 0x22222222
    sc.w x23, x22, (x14)
    li x10, 0
    beq x23, x0, 1f           # SC should return non-zero (fail)
    lw x24, 0(x14)
    li x25, 0x11111111
    bne x24, x25, 1f          # Memory should NOT be updated
    li x10, 1
1:
    ret

# ── Test 7: SC.W fail — LR then SW then SC (store invalidates reservation) ──
test_07_sc_w_fail_after_store:
    li x14, TEST_BASE
    li x15, 0x33333333
    sw x15, 0(x14)
    lr.w x16, (x14)
    li x22, 0x44444444
    sw x22, 0(x14)            # Normal store invalidates reservation
    li x22, 0x55555555
    sc.w x23, x22, (x14)
    li x10, 0
    beq x23, x0, 1f           # SC should fail
    lw x24, 0(x14)
    li x25, 0x44444444
    bne x24, x25, 1f          # Memory should have the SW value
    li x10, 1
1:
    ret

# ── Test 8: SC.W fail — LR then AMO then SC (AMO invalidates reservation) ──
# RISC-V spec: AMO implicitly performs a store, invalidating the reservation
test_08_sc_w_fail_after_amo:
    li x14, TEST_BASE
    li x15, 0x100
    sw x15, 0(x14)
    lr.w x16, (x14)           # Set reservation
    li x22, 0x10
    amoadd.w x16, x22, (x14)  # AMO invalidates reservation (implicit store)
    li x22, 0x999
    sc.w x23, x22, (x14)      # SC should fail (reservation invalidated by AMO)
    li x10, 0
    beq x23, x0, 1f           # SC should return non-zero
    lw x24, 0(x14)
    li x25, 0x110             # AMOADD result: 0x100 + 0x10 = 0x110
    bne x24, x25, 1f          # Memory should have AMOADD result
    li x10, 1
1:
    ret

# ── Test 9: SC.W fail — LR at addr A, SC at addr B ──
test_09_sc_w_fail_lr_different_addr:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x16, TEST_BASE2
    li x17, 0xBBBBBBBB
    sw x17, 0(x16)
    lr.w x22, (x14)           # LR at addr A
    li x22, 0xCCCCCCCC
    sc.w x23, x22, (x16)      # SC at addr B — should fail (reservation is for A)
    li x10, 0
    beq x23, x0, 1f           # SC should return non-zero
    lw x24, 0(x16)
    li x25, 0xBBBBBBBB
    bne x24, x25, 1f          # Memory at B should be unchanged
    li x10, 1
1:
    ret

# ── Test 10: SC.W then SC fail — SC success, then SC again without LR ──
test_10_sc_w_then_sc_fail:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    lr.w x16, (x14)
    li x22, 0x22222222
    sc.w x23, x22, (x14)      # First SC — should succeed
    bne x23, x0, 2f           # If first SC failed, skip to fail
    li x22, 0x33333333
    sc.w x23, x22, (x14)      # Second SC — should fail (no LR between)
    li x10, 0
    beq x23, x0, 1f           # Second SC should return non-zero
    lw x24, 0(x14)
    li x25, 0x22222222
    bne x24, x25, 1f          # Memory should still have first SC value
    li x10, 1
    j 3f
1:
    li x10, 0
    j 3f
2:
    li x10, 0
3:
    ret

# ── Test 11: SC.W with rs2=x0 — write zero on success ──
test_11_sc_w_rs2_zero:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    lr.w x16, (x14)
    sc.w x23, x0, (x14)       # rs2=x0, write zero
    li x10, 0
    bne x23, x0, 1f           # SC should succeed
    lw x24, 0(x14)
    bne x24, x0, 1f           # Memory should be zero
    li x10, 1
1:
    ret


# ============================================================
# Group 3: AMOSWAP.W
# ============================================================

# ── Test 12: AMOSWAP.W basic ──
test_12_amoswap_w_basic:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x22, 0xBBBBBBBB
    amoswap.w x16, x22, (x14)
    li x10, 0
    li x17, 0xAAAAAAAA
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xBBBBBBBB
    bne x24, x25, 1f          # mem = new value
    li x10, 1
1:
    ret

# ── Test 13: AMOSWAP.W swap twice ──
test_13_amoswap_w_twice:
    li x14, TEST_BASE
    li x15, 0x11111111
    sw x15, 0(x14)
    li x22, 0x22222222
    amoswap.w x16, x22, (x14)  # x16=0x11111111, mem=0x22222222
    li x22, 0x33333333
    amoswap.w x17, x22, (x14)  # x17=0x22222222, mem=0x33333333
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

# ── Test 14: AMOSWAP.W with zero ──
test_14_amoswap_w_zero:
    li x14, TEST_BASE
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    amoswap.w x16, x0, (x14)   # Swap with zero
    li x10, 0
    li x17, 0xDEADBEEF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x0, 1f           # mem = 0
    li x10, 1
1:
    ret

# ── Test 15: AMOSWAP.W with all-ones ──
test_15_amoswap_w_all_ones:
    li x14, TEST_BASE
    sw x0, 0(x14)
    li x22, -1                 # 0xFFFFFFFF
    amoswap.w x16, x22, (x14)
    li x10, 0
    bne x16, x0, 1f           # rd = old value (0)
    lw x24, 0(x14)
    li x25, -1
    bne x24, x25, 1f          # mem = 0xFFFFFFFF
    li x10, 1
1:
    ret


# ============================================================
# Group 4: AMOADD.W
# ============================================================

# ── Test 16: AMOADD.W basic ──
test_16_amoadd_w_basic:
    li x14, TEST_BASE
    li x15, 100
    sw x15, 0(x14)
    li x22, 50
    amoadd.w x16, x22, (x14)
    li x10, 0
    li x17, 100
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 150
    bne x24, x25, 1f          # mem = 100 + 50
    li x10, 1
1:
    ret

# ── Test 17: AMOADD.W accumulate — multiple adds ──
test_17_amoadd_w_accumulate:
    li x14, TEST_BASE
    sw x0, 0(x14)
    li x22, 1
    amoadd.w x16, x22, (x14)   # counter = 1, x16 = 0
    amoadd.w x16, x22, (x14)   # counter = 2, x16 = 1
    amoadd.w x16, x22, (x14)   # counter = 3, x16 = 2
    lw x24, 0(x14)
    li x10, 0
    li x25, 3
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 18: AMOADD.W with zero (identity) ──
test_18_amoadd_w_zero:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    amoadd.w x16, x0, (x14)    # Add zero
    li x10, 0
    li x17, 0x12345678
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret

# ── Test 19: AMOADD.W overflow — 0x80000000 + 0x80000000 = 0x00000000 (wrap) ──
test_19_amoadd_w_overflow:
    li x14, TEST_BASE
    li x15, 0x80000000         # INT_MIN
    sw x15, 0(x14)
    li x22, 0x80000000
    amoadd.w x16, x22, (x14)   # INT_MIN + INT_MIN = 0x00000000 (overflow wraps)
    li x10, 0
    li x17, 0x80000000
    bne x16, x17, 1f          # rd = old value (0x80000000)
    lw x24, 0(x14)
    bne x24, x0, 1f           # mem = 0 (overflow wrapped)
    li x10, 1
1:
    ret

# ── Test 20: AMOADD.W negative — (-10) + 5 = -5 ──
test_20_amoadd_w_neg:
    li x14, TEST_BASE
    li x15, -10
    sw x15, 0(x14)
    li x22, 5
    amoadd.w x16, x22, (x14)
    li x10, 0
    li x17, -10
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, -5
    bne x24, x25, 1f          # mem = -5
    li x10, 1
1:
    ret


# ============================================================
# Group 5: AMOAND.W
# ============================================================

# ── Test 21: AMOAND.W basic ──
test_21_amoand_w_basic:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoand.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0x0F000F00        # 0xFF00FF00 & 0x0F0F0F0F
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 22: AMOAND.W with all-ones (identity) ──
test_22_amoand_w_all_ones:
    li x14, TEST_BASE
    li x15, 0xABCDEFFF
    sw x15, 0(x14)
    li x22, -1                 # 0xFFFFFFFF
    amoand.w x16, x22, (x14)   # x & 0xFFFFFFFF = x
    li x10, 0
    li x17, 0xABCDEFFF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret

# ── Test 23: AMOAND.W with zero (clears) ──
test_23_amoand_w_zero:
    li x14, TEST_BASE
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    amoand.w x16, x0, (x14)    # x & 0 = 0
    li x10, 0
    li x17, 0xDEADBEEF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x0, 1f           # mem = 0
    li x10, 1
1:
    ret

# ── Test 24: AMOAND.W self — x & x = x ──
test_24_amoand_w_self:
    li x14, TEST_BASE
    li x15, 0x55AA55AA
    sw x15, 0(x14)
    li x22, 0x55AA55AA
    amoand.w x16, x22, (x14)   # x & x = x
    li x10, 0
    li x17, 0x55AA55AA
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret


# ============================================================
# Group 6: AMOOR.W
# ============================================================

# ── Test 25: AMOOR.W basic ──
test_25_amoor_w_basic:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoor.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xFF0FFF0F        # 0xFF00FF00 | 0x0F0F0F0F
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 26: AMOOR.W with zero (identity) ──
test_26_amoor_w_zero:
    li x14, TEST_BASE
    li x15, 0xABCDEFFF
    sw x15, 0(x14)
    amoor.w x16, x0, (x14)     # x | 0 = x
    li x10, 0
    li x17, 0xABCDEFFF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret

# ── Test 27: AMOOR.W with all-ones ──
test_27_amoor_w_all_ones:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    li x22, -1                 # 0xFFFFFFFF
    amoor.w x16, x22, (x14)    # x | 0xFFFFFFFF = 0xFFFFFFFF
    li x10, 0
    li x17, 0x12345678
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, -1
    bne x24, x25, 1f          # mem = 0xFFFFFFFF
    li x10, 1
1:
    ret

# ── Test 28: AMOOR.W self — x | x = x ──
test_28_amoor_w_self:
    li x14, TEST_BASE
    li x15, 0x55AA55AA
    sw x15, 0(x14)
    li x22, 0x55AA55AA
    amoor.w x16, x22, (x14)    # x | x = x
    li x10, 0
    li x17, 0x55AA55AA
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret


# ============================================================
# Group 7: AMOXOR.W
# ============================================================

# ── Test 29: AMOXOR.W basic ──
test_29_amoxor_w_basic:
    li x14, TEST_BASE
    li x15, 0xFF00FF00
    sw x15, 0(x14)
    li x22, 0x0F0F0F0F
    amoxor.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFF00FF00
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xF00FF00F        # 0xFF00FF00 ^ 0x0F0F0F0F
    bne x24, x25, 1f
    li x10, 1
1:
    ret

# ── Test 30: AMOXOR.W with zero (identity) ──
test_30_amoxor_w_zero:
    li x14, TEST_BASE
    li x15, 0xABCDEFFF
    sw x15, 0(x14)
    amoxor.w x16, x0, (x14)    # x ^ 0 = x
    li x10, 0
    li x17, 0xABCDEFFF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged
    li x10, 1
1:
    ret

# ── Test 31: AMOXOR.W self — x ^ x = 0 ──
test_31_amoxor_w_self:
    li x14, TEST_BASE
    li x15, 0xDEADBEEF
    sw x15, 0(x14)
    li x22, 0xDEADBEEF
    amoxor.w x16, x22, (x14)   # x ^ x = 0
    li x10, 0
    li x17, 0xDEADBEEF
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x0, 1f           # mem = 0
    li x10, 1
1:
    ret

# ── Test 32: AMOXOR.W double XOR restores original ──
test_32_amoxor_w_double_restore:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x22, 0x55555555
    amoxor.w x16, x22, (x14)   # First XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
    amoxor.w x16, x22, (x14)   # Second XOR: 0xFFFFFFFF ^ 0x55555555 = 0xAAAAAAAA
    li x10, 0
    lw x24, 0(x14)
    li x25, 0xAAAAAAAA
    bne x24, x25, 1f          # mem restored to original
    li x10, 1
1:
    ret


# ============================================================
# Group 8: AMOMIN.W (signed minimum)
# ============================================================

# ── Test 33: AMOMIN.W basic — negative vs positive ──
test_33_amomin_w_basic:
    li x14, TEST_BASE
    li x15, -10
    sw x15, 0(x14)
    li x22, 5
    amomin.w x16, x22, (x14)
    li x10, 0
    li x17, -10
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, -10
    bne x24, x25, 1f          # mem = min(-10, 5) = -10
    li x10, 1
1:
    ret

# ── Test 34: AMOMIN.W both negative — more negative wins ──
test_34_amomin_w_both_neg:
    li x14, TEST_BASE
    li x15, -5
    sw x15, 0(x14)
    li x22, -100
    amomin.w x16, x22, (x14)
    li x10, 0
    li x17, -5
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, -100
    bne x24, x25, 1f          # mem = min(-5, -100) = -100
    li x10, 1
1:
    ret

# ── Test 35: AMOMIN.W equal values ──
test_35_amomin_w_equal:
    li x14, TEST_BASE
    li x15, 42
    sw x15, 0(x14)
    li x22, 42
    amomin.w x16, x22, (x14)
    li x10, 0
    li x17, 42
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem = 42 (equal)
    li x10, 1
1:
    ret

# ── Test 36: AMOMIN.W boundary — INT_MIN vs INT_MAX ──
test_36_amomin_w_boundary:
    li x14, TEST_BASE
    li x15, 0x7FFFFFFF         # INT_MAX = 2147483647
    sw x15, 0(x14)
    li x22, 0x80000000         # INT_MIN = -2147483648
    amomin.w x16, x22, (x14)
    li x10, 0
    li x17, 0x7FFFFFFF
    bne x16, x17, 1f          # rd = old value (INT_MAX)
    lw x24, 0(x14)
    li x25, 0x80000000
    bne x24, x25, 1f          # mem = INT_MIN (smaller signed)
    li x10, 1
1:
    ret


# ============================================================
# Group 9: AMOMAX.W (signed maximum)
# ============================================================

# ── Test 37: AMOMAX.W basic — negative vs positive ──
test_37_amomax_w_basic:
    li x14, TEST_BASE
    li x15, -10
    sw x15, 0(x14)
    li x22, 5
    amomax.w x16, x22, (x14)
    li x10, 0
    li x17, -10
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 5
    bne x24, x25, 1f          # mem = max(-10, 5) = 5
    li x10, 1
1:
    ret

# ── Test 38: AMOMAX.W both negative — less negative wins ──
test_38_amomax_w_both_neg:
    li x14, TEST_BASE
    li x15, -100
    sw x15, 0(x14)
    li x22, -5
    amomax.w x16, x22, (x14)
    li x10, 0
    li x17, -100
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, -5
    bne x24, x25, 1f          # mem = max(-100, -5) = -5
    li x10, 1
1:
    ret

# ── Test 39: AMOMAX.W equal values ──
test_39_amomax_w_equal:
    li x14, TEST_BASE
    li x15, -42
    sw x15, 0(x14)
    li x22, -42
    amomax.w x16, x22, (x14)
    li x10, 0
    li x17, -42
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem = -42 (equal)
    li x10, 1
1:
    ret

# ── Test 40: AMOMAX.W boundary — INT_MIN vs INT_MAX ──
test_40_amomax_w_boundary:
    li x14, TEST_BASE
    li x15, 0x80000000         # INT_MIN
    sw x15, 0(x14)
    li x22, 0x7FFFFFFF         # INT_MAX
    amomax.w x16, x22, (x14)
    li x10, 0
    li x17, 0x80000000
    bne x16, x17, 1f          # rd = old value (INT_MIN)
    lw x24, 0(x14)
    li x25, 0x7FFFFFFF
    bne x24, x25, 1f          # mem = INT_MAX (larger signed)
    li x10, 1
1:
    ret


# ============================================================
# Group 10: AMOMINU.W (unsigned minimum)
# ============================================================

# ── Test 41: AMOMINU.W basic ──
test_41_amominu_w_basic:
    li x14, TEST_BASE
    li x15, 0xFFFFFFFE         # unsigned: 4294967294
    sw x15, 0(x14)
    li x22, 5
    amominu.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFFFFFFFE
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 5
    bne x24, x25, 1f          # mem = minu(0xFFFFFFFE, 5) = 5
    li x10, 1
1:
    ret

# ── Test 42: AMOMINU.W both large unsigned ──
test_42_amominu_w_both_large:
    li x14, TEST_BASE
    li x15, 0xFFFFFFF0         # unsigned: 4294967280
    sw x15, 0(x14)
    li x22, 0xFFFFFFFE         # unsigned: 4294967294
    amominu.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFFFFFFF0
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xFFFFFFF0
    bne x24, x25, 1f          # mem = minu(0xFFFFFFF0, 0xFFFFFFFE) = 0xFFFFFFF0
    li x10, 1
1:
    ret

# ── Test 43: AMOMINU.W equal values ──
test_43_amominu_w_equal:
    li x14, TEST_BASE
    li x15, 0x80000000
    sw x15, 0(x14)
    li x22, 0x80000000
    amominu.w x16, x22, (x14)
    li x10, 0
    li x17, 0x80000000
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged (equal)
    li x10, 1
1:
    ret

# ── Test 44: AMOMINU.W with zero — zero is smallest unsigned ──
test_44_amominu_w_with_zero:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    amominu.w x16, x0, (x14)   # minu(0x12345678, 0) = 0
    li x10, 0
    li x17, 0x12345678
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x0, 1f           # mem = 0
    li x10, 1
1:
    ret


# ============================================================
# Group 11: AMOMAXU.W (unsigned maximum)
# ============================================================

# ── Test 45: AMOMAXU.W basic ──
test_45_amomaxu_w_basic:
    li x14, TEST_BASE
    li x15, 0xFFFFFFFE         # unsigned: 4294967294
    sw x15, 0(x14)
    li x22, 5
    amomaxu.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFFFFFFFE
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xFFFFFFFE
    bne x24, x25, 1f          # mem = maxu(0xFFFFFFFE, 5) = 0xFFFFFFFE
    li x10, 1
1:
    ret

# ── Test 46: AMOMAXU.W both large unsigned ──
test_46_amomaxu_w_both_large:
    li x14, TEST_BASE
    li x15, 0xFFFFFFF0         # unsigned: 4294967280
    sw x15, 0(x14)
    li x22, 0xFFFFFFFE         # unsigned: 4294967294
    amomaxu.w x16, x22, (x14)
    li x10, 0
    li x17, 0xFFFFFFF0
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    li x25, 0xFFFFFFFE
    bne x24, x25, 1f          # mem = maxu(0xFFFFFFF0, 0xFFFFFFFE) = 0xFFFFFFFE
    li x10, 1
1:
    ret

# ── Test 47: AMOMAXU.W equal values ──
test_47_amomaxu_w_equal:
    li x14, TEST_BASE
    li x15, 0x80000000
    sw x15, 0(x14)
    li x22, 0x80000000
    amomaxu.w x16, x22, (x14)
    li x10, 0
    li x17, 0x80000000
    bne x16, x17, 1f          # rd = old value
    lw x24, 0(x14)
    bne x24, x17, 1f          # mem unchanged (equal)
    li x10, 1
1:
    ret

# ── Test 48: AMOMAXU.W with zero ──
test_48_amomaxu_w_with_zero:
    li x14, TEST_BASE
    sw x0, 0(x14)
    li x22, 0x12345678
    amomaxu.w x16, x22, (x14)  # maxu(0, 0x12345678) = 0x12345678
    li x10, 0
    bne x16, x0, 1f           # rd = old value (0)
    lw x24, 0(x14)
    li x25, 0x12345678
    bne x24, x25, 1f          # mem = 0x12345678
    li x10, 1
1:
    ret


# ============================================================
# Group 12: LR/SC interaction & mutex
# ============================================================

# ── Test 49: LR/SC mutex — simple lock acquire/release ──
test_49_lr_sc_mutex:
    li x14, TEST_BASE
    sw x0, 0(x14)              # lock = 0 (unlocked)
1:
    lr.w x16, (x14)            # read lock
    bne x16, x0, 1b            # if locked, retry
    li x22, 1
    sc.w x23, x22, (x14)       # try to set lock
    bne x23, x0, 1b            # if SC failed, retry
    lw x24, 0(x14)
    li x10, 0
    li x25, 1
    bne x24, x25, 2f           # lock should be 1
    sw x0, 0(x14)              # release lock
    li x10, 1
2:
    ret

# ── Test 50: LR/SC + AMO invalidation — AMO after LR invalidates reservation ──
# This is a critical spec conformance test
test_50_lr_sc_amo_invalidate:
    li x14, TEST_BASE
    li x15, 100
    sw x15, 0(x14)
    lr.w x16, (x14)            # Set reservation
    li x22, 10
    amoadd.w x16, x22, (x14)   # AMO invalidates reservation
    li x22, 999
    sc.w x23, x22, (x14)       # SC should fail
    li x10, 0
    beq x23, x0, 1f            # SC should return non-zero (fail)
    lw x24, 0(x14)
    li x25, 110                # AMOADD result: 100 + 10 = 110
    bne x24, x25, 1f           # Memory should have AMOADD result, not SC value
    li x10, 1
1:
    ret


# ============================================================
# Group 13: AMO rd=x0 (memory still updated, result discarded)
# ============================================================

# ── Test 51: AMOADD.W rd=x0 — memory still updated ──
test_51_amoadd_w_rd_x0:
    li x14, TEST_BASE
    li x15, 100
    sw x15, 0(x14)
    li x22, 50
    amoadd.w x0, x22, (x14)    # rd=x0, result discarded but memory updated
    li x10, 0
    lw x24, 0(x14)
    li x25, 150
    bne x24, x25, 1f           # mem should be 100 + 50 = 150
    li x10, 1
1:
    ret

# ── Test 52: AMOSWAP.W rd=x0 — memory still updated ──
test_52_amoswap_w_rd_x0:
    li x14, TEST_BASE
    li x15, 0xAAAAAAAA
    sw x15, 0(x14)
    li x22, 0xBBBBBBBB
    amoswap.w x0, x22, (x14)   # rd=x0, result discarded but memory updated
    li x10, 0
    lw x24, 0(x14)
    li x25, 0xBBBBBBBB
    bne x24, x25, 1f           # mem should be 0xBBBBBBBB
    li x10, 1
1:
    ret
