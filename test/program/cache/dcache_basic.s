# ============================================================
# cache/dcache_basic.s — D$ basic operation tests
# Category: Cache
# Description: Test dcache load/store hit, same-line, cross-line
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# D-cache: 8 sets × 2 ways, 32-byte lines, write-through/no-write-allocate
# Address layout: tag[14:8] | set[7:5] | word_off[4:2] | byte[1:0]
# test_data_area = 0x80003000 (tag=3, set=0)
# ============================================================

.equ TEST_DATA, 0x80003000

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10

    jal x1, test_init

    la x11, test_dcache_store_load
    jal x1, test_run
    la x11, test_dcache_same_line
    jal x1, test_run
    la x11, test_dcache_cross_line
    jal x1, test_run
    la x11, test_dcache_byte_halfword
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: Store-load roundtrip ──
test_dcache_store_load:
    lui  x10, 0x80003         # 0x80003000
    li   x11, 0xDEADBEEF
    sw   x11, 0(x10)
    lw   x12, 0(x10)
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 2: Multiple stores to same cache line ──
# A cache line is 32 bytes (8 words). Store 8 words, load all back.
test_dcache_same_line:
    lui  x10, 0x80003         # 0x80003000

    li   x11, 0x11111111
    sw   x11, 0(x10)
    li   x11, 0x22222222
    sw   x11, 4(x10)
    li   x11, 0x33333333
    sw   x11, 8(x10)
    li   x11, 0x44444444
    sw   x11, 12(x10)
    li   x11, 0x55555555
    sw   x11, 16(x10)
    li   x11, 0x66666666
    sw   x11, 20(x10)
    li   x11, 0x77777777
    sw   x11, 24(x10)
    li   x11, 0x88888888
    sw   x11, 28(x10)

    # Load all back and verify
    lw   x12, 0(x10)
    li   x11, 0x11111111
    bne  x12, x11, _dsl_fail

    lw   x12, 4(x10)
    li   x11, 0x22222222
    bne  x12, x11, _dsl_fail

    lw   x12, 8(x10)
    li   x11, 0x33333333
    bne  x12, x11, _dsl_fail

    lw   x12, 12(x10)
    li   x11, 0x44444444
    bne  x12, x11, _dsl_fail

    lw   x12, 16(x10)
    li   x11, 0x55555555
    bne  x12, x11, _dsl_fail

    lw   x12, 20(x10)
    li   x11, 0x66666666
    bne  x12, x11, _dsl_fail

    lw   x12, 24(x10)
    li   x11, 0x77777777
    bne  x12, x11, _dsl_fail

    lw   x12, 28(x10)
    li   x11, 0x88888888
    bne  x12, x11, _dsl_fail

    li   x10, 1
    ret
_dsl_fail:
    li   x10, 0
    ret


# ── Sub-test 3: Cross-line stores ──
# Store to two different cache lines (different sets), load back
# 0x80003000: set 0, tag 3
# 0x80003020: set 1, tag 3  (same tag, different set)
test_dcache_cross_line:
    lui  x10, 0x80003         # 0x80003000

    # Store to set 0
    li   x11, 0xAA55AA55
    sw   x11, 0(x10)          # 0x80003000: set 0

    # Store to set 1 (offset 0x20 = next set in same tag)
    li   x11, 0x55AA55AA
    sw   x11, 0x20(x10)       # 0x80003020: set 1

    # Load back
    lw   x12, 0(x10)
    li   x11, 0xAA55AA55
    bne  x12, x11, _dcl_fail

    lw   x12, 0x20(x10)
    li   x11, 0x55AA55AA
    bne  x12, x11, _dcl_fail

    li   x10, 1
    ret
_dcl_fail:
    li   x10, 0
    ret


# ── Sub-test 4: Byte and halfword store-load ──
test_dcache_byte_halfword:
    lui  x10, 0x80003         # 0x80003000

    # Byte store + load
    li   x11, 0xAB
    sb   x11, 0(x10)
    lbu  x12, 0(x10)
    bne  x12, x11, _dbw_fail

    # Halfword store + load
    li   x11, 0x1234
    sh   x11, 4(x10)
    lhu  x12, 4(x10)
    bne  x12, x11, _dbw_fail

    # Signed byte load
    li   x11, 0xFF            # -1 as byte
    sb   x11, 8(x10)
    lb   x12, 8(x10)          # sign-extended: 0xFFFFFFFF
    li   x11, -1
    bne  x12, x11, _dbw_fail

    # Signed halfword load
    li   x11, 0xF800          # -2048 as halfword
    sh   x11, 12(x10)
    lh   x12, 12(x10)         # sign-extended: 0xFFFFF800
    li   x11, -2048
    bne  x12, x11, _dbw_fail

    li   x10, 1
    ret
_dbw_fail:
    li   x10, 0
    ret
