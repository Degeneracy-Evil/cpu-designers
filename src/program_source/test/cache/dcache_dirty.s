# ============================================================
# cache/dcache_dirty.s — D$ write-through visibility compatibility tests
# Category: Cache
# Description: Test that completed stores remain visible across FENCE.I
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# D-cache is write-through: a store retires only after its backing AXI write
# completes. FENCE.I therefore only invalidates I-cache; these historical
# tests remain useful as architectural data-visibility regressions.
#
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

    la x11, test_dwb_flush_verify
    jal x1, test_run
    la x11, test_dwb_overwrite
    jal x1, test_run
    la x11, test_dwb_multi_dirty
    jal x1, test_run
    la x11, test_dwb_double_flush
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: Store + FENCE.I + load visibility ──
test_dwb_flush_verify:
    lui  x10, 0x80003         # 0x80003000
    li   x11, 0xCAFEBABE
    sw   x11, 0(x10)          # write-through store

    fence.i                    # instruction-side synchronization

    lw   x12, 0(x10)          # miss → refill from SRAM
    li   x11, 0xCAFEBABE
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 2: Overwrite — latest store wins ──
# Store A, then store B to same address, FENCE.I, load → B
test_dwb_overwrite:
    lui  x10, 0x80003         # 0x80003000
    li   x11, 0xAAAAAAAA
    sw   x11, 0(x10)          # store A
    li   x11, 0xBBBBBBBB
    sw   x11, 0(x10)          # store B (overwrites A in dcache)

    fence.i                    # flush → SRAM has B

    lw   x12, 0(x10)          # miss → refill from SRAM
    li   x11, 0xBBBBBBBB
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 3: Multiple stores + FENCE.I ──
# Store to 4 different addresses (potentially different cache lines),
# FENCE.I, load all 4 back — all should be correct
test_dwb_multi_dirty:
    lui  x10, 0x80003         # 0x80003000

    # Store to 4 different words in the same cache line
    li   x11, 0xAAAA0001
    sw   x11, 0(x10)          # word 0
    li   x11, 0xBBBB0002
    sw   x11, 4(x10)          # word 1
    li   x11, 0xCCCC0003
    sw   x11, 8(x10)          # word 2
    li   x11, 0xDDDD0004
    sw   x11, 12(x10)         # word 3

    fence.i                    # stores are already globally visible

    # Load all back
    lw   x12, 0(x10)
    li   x11, 0xAAAA0001
    bne  x12, x11, _dmd_fail

    lw   x12, 4(x10)
    li   x11, 0xBBBB0002
    bne  x12, x11, _dmd_fail

    lw   x12, 8(x10)
    li   x11, 0xCCCC0003
    bne  x12, x11, _dmd_fail

    lw   x12, 12(x10)
    li   x11, 0xDDDD0004
    bne  x12, x11, _dmd_fail

    li   x10, 1
    ret
_dmd_fail:
    li   x10, 0
    ret


# ── Sub-test 4: Double flush — store, FENCE.I, store, FENCE.I, load ──
# Verify that a second store after a first flush is correctly written back
test_dwb_double_flush:
    lui  x10, 0x80003         # 0x80003000

    # First store + flush
    li   x11, 0x11111111
    sw   x11, 0(x10)
    fence.i                    # first flush → SRAM has 0x11111111

    # Second store + flush
    li   x11, 0x22222222
    sw   x11, 0(x10)
    fence.i                    # second flush → SRAM has 0x22222222

    # Load — should get second value
    lw   x12, 0(x10)
    li   x11, 0x22222222
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret
