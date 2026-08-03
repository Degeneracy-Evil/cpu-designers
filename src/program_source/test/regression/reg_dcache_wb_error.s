# ============================================================
# regression/reg_dcache_wb_error.s — Dirty eviction write-back error regression
# Category: Regression (common) | Sub-tests: 1
#
# D-cache: 8 sets × 4 ways, 32-byte lines.
# Set index = addr[7:5]. All addresses below use bits[7:5]=000 (set 0)
# but different tags, filling all 4 ways. The 5th access triggers
# eviction of the PLRU victim. TB injects BRESP error at LINE_A
# (the first line written, which PLRU should evict first).
#
# Test verifies: (1) write-back error → store access fault (mcause=7),
#                (2) mtval = evicted line address,
#                (3) retry after trap succeeds.
# ============================================================

.equ LINE_A, 0x80003000   # set 0, tag 0x800030 — first dirty (PLRU victim)
.equ LINE_B, 0x80013000   # set 0, tag 0x800130
.equ LINE_C, 0x80023000   # set 0, tag 0x800230
.equ LINE_D, 0x80033000   # set 0, tag 0x800330
.equ LINE_E, 0x80043000   # set 0, tag 0x800430 — 5th access, triggers eviction

.section .text.start
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10

    jal x1, test_init
    la x11, test_wb_error_preserves_victim_and_allows_retry
    jal x1, test_run
    jal x1, test_report

end_loop:
    j end_loop

trap_handler:
    csrr x22, mcause
    csrr x23, mtval
    csrr x10, mepc
    addi x10, x10, 4
    csrw mepc, x10
    mret

test_wb_error_preserves_victim_and_allows_retry:
    li  x22, 0
    li  x23, 0

    # Fill all 4 ways of set 0 with dirty lines
    li  x14, LINE_A
    li  x15, 0x11223344
    sw  x15, 0(x14)

    li  x14, LINE_B
    li  x15, 0x22334455
    sw  x15, 0(x14)

    li  x14, LINE_C
    li  x15, 0x33445566
    sw  x15, 0(x14)

    li  x14, LINE_D
    li  x15, 0x44556677
    sw  x15, 0(x14)

    # 5th access to set 0 → eviction of PLRU victim (expected: LINE_A)
    # TB injects BRESP error at LINE_A → store access fault
    li  x14, LINE_E
    li  x15, 0x55667788
    sw  x15, 0(x14)

    # Verify trap: mcause=7 (store access fault), mtval=LINE_A
    li  x16, 7
    bne x22, x16, _fail
    li  x16, LINE_A
    bne x23, x16, _fail

    # Retry: write to LINE_E should now succeed (injection consumed)
    li  x14, LINE_E
    li  x15, 0x55667788
    sw  x15, 0(x14)

    fence.i

    # Verify LINE_A data is still accessible
    li  x14, LINE_A
    lw  x15, 0(x14)
    li  x16, 0x11223344
    bne x15, x16, _fail

    # Verify LINE_E data
    li  x14, LINE_E
    lw  x15, 0(x14)
    li  x16, 0x55667788
    bne x15, x16, _fail

    li  x10, 1
    ret

_fail:
    li  x10, 0
    ret
