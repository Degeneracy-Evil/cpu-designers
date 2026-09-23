# ============================================================
# cache/fencei.s — FENCE.I behavior tests
# Category: Cache
# Description: Test FENCE.I instruction/data stream synchronization
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# Completed write-through stores are already visible in memory. FENCE.I clears
# I-cache valid bits so later fetches observe self-modifying-code stores.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10

    jal x1, test_init

    la x11, test_fencei_smc
    jal x1, test_run
    la x11, test_fencei_dcache_flush
    jal x1, test_run
    la x11, test_fencei_preserve_data
    jal x1, test_run
    la x11, test_fencei_multi
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: FENCE.I enables self-modifying code ──
# Write new instruction to smc_fn, FENCE.I, call smc_fn, verify new behavior
test_fencei_smc:
    # Save original return address (x1 from test_run)
    add  x5, x1, x0            # save ra in t0

    # Overwrite smc_fn's first instruction: addi x10, x0, 1 (0x00100513)
    la   x11, smc_fn
    li   x12, 0x00100513
    sw   x12, 0(x11)

    # FENCE.I: invalidate I-cache after the completed write-through store
    fence.i

    # Call smc_fn — icache miss, fetch from SRAM, gets new instruction
    jal  x1, smc_fn           # x10 = return value from smc_fn

    # Restore original return address
    add  x1, x5, x0            # ra = original ra

    # Check: x10 should be 1 (new instruction)
    li   x11, 1
    beq  x10, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 2: FENCE.I preserves completed store visibility ──
test_fencei_dcache_flush:
    lui  x10, 0x80003         # x10 = 0x80003000 (test_data_area)
    li   x11, 0xDEADBEEF
    sw   x11, 0(x10)          # write-through store

    fence.i                    # invalidate I-cache

    # Load from same address — cache hit or refill must see the store
    lw   x12, 0(x10)          # x12 should be 0xDEADBEEF

    li   x11, 0xDEADBEEF
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 3: FENCE.I preserves multiple stores ──
# Store to 4 different addresses, FENCE.I, load all back
test_fencei_preserve_data:
    lui  x10, 0x80003         # base = 0x80003000

    li   x11, 0xAAAA1111
    sw   x11, 0(x10)          # addr+0
    li   x11, 0xBBBB2222
    sw   x11, 4(x10)          # addr+4
    li   x11, 0xCCCC3333
    sw   x11, 8(x10)          # addr+8
    li   x11, 0xDDDD4444
    sw   x11, 12(x10)         # addr+12

    fence.i                    # synchronize instruction fetch

    # Load all back and verify
    lw   x11, 0(x10)
    li   x12, 0xAAAA1111
    bne  x11, x12, _fpd_fail

    lw   x11, 4(x10)
    li   x12, 0xBBBB2222
    bne  x11, x12, _fpd_fail

    lw   x11, 8(x10)
    li   x12, 0xCCCC3333
    bne  x11, x12, _fpd_fail

    lw   x11, 12(x10)
    li   x12, 0xDDDD4444
    bne  x11, x12, _fpd_fail

    li   x10, 1
    ret
_fpd_fail:
    li   x10, 0
    ret


# ── Sub-test 4: Multiple FENCE.I in sequence ──
# Store, FENCE.I, FENCE.I, load — should still be correct
test_fencei_multi:
    lui  x10, 0x80003         # 0x80003000
    li   x11, 0x12345678
    sw   x11, 16(x10)         # store to offset 16

    fence.i                    # first flush
    fence.i                    # second flush (no-op on clean cache)

    lw   x12, 16(x10)         # load back
    li   x11, 0x12345678
    beq  x12, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Self-modifying code target ──
# Aligned to cache line boundary (32 bytes) to avoid corrupting adjacent code
    .balign 32
smc_fn:
    addi x10, x0, 0           # 0x00000513 — initially returns 0
    ret                        # 0x00008067
