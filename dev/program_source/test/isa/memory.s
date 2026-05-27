# ============================================================
# isa/memory.s — Load/Store instruction tests
# Category: ISA
# Description: Test LW/SW/LB/SB/LH/LH/LBU/LHU
# Sub-tests: 20
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

    la x11, test_sw_lw
    jal x1, test_run
    la x11, test_sb_lb_sign
    jal x1, test_run
    la x11, test_sb_lbu_zero
    jal x1, test_run
    la x11, test_sh_lh_sign
    jal x1, test_run
    la x11, test_sh_lhu_zero
    jal x1, test_run
    la x11, test_sw_lw_offset
    jal x1, test_run
    la x11, test_lb_neg_byte
    jal x1, test_run
    la x11, test_lbu_pos_byte
    jal x1, test_run
    la x11, test_lh_neg_half
    jal x1, test_run
    la x11, test_lhu_pos_half
    jal x1, test_run
    la x11, test_sb_overwrite
    jal x1, test_run
    la x11, test_sh_overwrite
    jal x1, test_run
    la x11, test_sw_zero
    jal x1, test_run
    la x11, test_sb_all_pos
    jal x1, test_run
    la x11, test_sh_all_pos
    jal x1, test_run
    la x11, test_lw_max
    jal x1, test_run
    la x11, test_sw_lw_neg
    jal x1, test_run
    la x11, test_sb_lb_zero
    jal x1, test_run
    la x11, test_sh_lh_zero
    jal x1, test_run
    la x11, test_cross_halfword
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# Base address for test data: 0x80001000
.equ TEST_BASE, 0x80001000

# ── SW then LW: word aligned ──
test_sw_lw:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    lw x16, 0(x14)
    li x10, 0
    li x17, 0x12345678
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SB then LB: sign extension ──
test_sb_lb_sign:
    li x14, TEST_BASE
    li x15, 0x81          # store byte 0x81
    sb x15, 0(x14)
    lb x16, 0(x14)        # sign-extended: 0xFFFFFF81 = -127
    li x10, 0
    li x17, -127
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SB then LBU: zero extension ──
test_sb_lbu_zero:
    li x14, TEST_BASE
    li x15, 0x81
    sb x15, 0(x14)
    lbu x16, 0(x14)       # zero-extended: 0x00000081 = 129
    li x10, 0
    li x17, 129
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SH then LH: sign extension ──
test_sh_lh_sign:
    li x14, TEST_BASE
    li x15, 0xABCD
    sh x15, 0(x14)
    lh x16, 0(x14)        # sign-extended: 0xFFFFABCD = -21555
    li x10, 0
    li x17, -21555
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SH then LHU: zero extension ──
test_sh_lhu_zero:
    li x14, TEST_BASE
    li x15, 0xABCD
    sh x15, 0(x14)
    lhu x16, 0(x14)       # zero-extended: 0x0000ABCD = 43981
    li x10, 0
    li x17, 43981
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SW/LW at different offsets ──
test_sw_lw_offset:
    li x14, TEST_BASE
    li x15, 0xDEADBEEF
    sw x15, 12(x14)
    lw x16, 12(x14)
    li x10, 0
    li x17, 0xDEADBEEF
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LB negative byte: store 0xC1, LB = -63 ──
test_lb_neg_byte:
    li x14, TEST_BASE
    li x15, 0xC1
    sb x15, 0(x14)
    lb x16, 0(x14)        # sign-extend: 0xFFFFFFC1 = -63
    li x10, 0
    li x17, -63
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LBU positive byte: store 0xC1, LBU = 193 ──
test_lbu_pos_byte:
    li x14, TEST_BASE
    li x15, 0xC1
    sb x15, 0(x14)
    lbu x16, 0(x14)       # zero-extend: 0x000000C1 = 193
    li x10, 0
    li x17, 193
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LH negative half: store 0xF0F0, LH = -3856 ──
test_lh_neg_half:
    li x14, TEST_BASE
    li x15, 0xF0F0
    sh x15, 0(x14)
    lh x16, 0(x14)        # sign-extend: 0xFFFFF0F0 = -3856
    li x10, 0
    li x17, -3856
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LHU positive half: store 0xF0F0, LHU = 61680 ──
test_lhu_pos_half:
    li x14, TEST_BASE
    li x15, 0xF0F0
    sh x15, 0(x14)
    lhu x16, 0(x14)       # zero-extend: 0x0000F0F0 = 61680
    li x10, 0
    li x17, 61680
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SB overwrite: SW then SB overwrites low byte ──
test_sb_overwrite:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    li x15, 0xAB
    sb x15, 0(x14)        # overwrite byte 0: 0x123456AB
    lw x16, 0(x14)
    li x10, 0
    li x17, 0x123456AB
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SH overwrite: SW then SH overwrites low halfword ──
test_sh_overwrite:
    li x14, TEST_BASE
    li x15, 0x12345678
    sw x15, 0(x14)
    li x15, 0xABCD
    sh x15, 0(x14)        # overwrite halfword 0: 0x1234ABCD
    lw x16, 0(x14)
    li x10, 0
    li x17, 0x1234ABCD
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SW zero ──
test_sw_zero:
    li x14, TEST_BASE
    sw x0, 0(x14)
    lw x16, 0(x14)
    li x10, 0
    bne x16, x0, 1f
    li x10, 1
1:
    ret

# ── SB all positive bytes ──
test_sb_all_pos:
    li x14, TEST_BASE
    li x15, 0x7F          # positive byte
    sb x15, 0(x14)
    lb x16, 0(x14)        # sign-extend of 0x7F = 127
    li x10, 0
    li x17, 127
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SH all positive halfword ──
test_sh_all_pos:
    li x14, TEST_BASE
    li x15, 0x7FFF        # positive halfword
    sh x15, 0(x14)
    lh x16, 0(x14)        # sign-extend of 0x7FFF = 32767
    li x10, 0
    li x17, 32767
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LW max value ──
test_lw_max:
    li x14, TEST_BASE
    li x15, -1            # 0xFFFFFFFF
    sw x15, 0(x14)
    lw x16, 0(x14)
    li x10, 0
    li x17, -1
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SW/LW negative value ──
test_sw_lw_neg:
    li x14, TEST_BASE
    li x15, -123456
    sw x15, 0(x14)
    lw x16, 0(x14)
    li x10, 0
    li x17, -123456
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── SB/LB zero byte ──
test_sb_lb_zero:
    li x14, TEST_BASE
    sb x0, 0(x14)
    lb x16, 0(x14)
    li x10, 0
    bne x16, x0, 1f
    li x10, 1
1:
    ret

# ── SH/LH zero halfword ──
test_sh_lh_zero:
    li x14, TEST_BASE
    sh x0, 0(x14)
    lh x16, 0(x14)
    li x10, 0
    bne x16, x0, 1f
    li x10, 1
1:
    ret

# ── Cross-halfword: store byte at offset 1, then read halfword at offset 0 ──
test_cross_halfword:
    li x14, TEST_BASE
    sw x0, 0(x14)         # clear word
    li x15, 0xFF
    sb x15, 1(x14)        # write byte at offset 1 (bits [15:8] in little-endian)
    lhu x16, 0(x14)       # read halfword at offset 0
    li x10, 0
    li x17, 0xFF00        # byte 1 is bits [15:8] of halfword 0
    bne x16, x17, 1f
    li x10, 1
1:
    ret
