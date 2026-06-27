# ============================================================
# regression/reg_wb_error_multi_dirty.s — Multi dirty-line wb_error during flush
# Category: Regression (common) | Sub-tests: 1
#
# Validates ISSUE-1 fix: when wb_error occurs during dcache flush with
# multiple dirty lines, the remaining dirty lines are still written back
# to memory (not silently lost).
#
# D-cache: 8 sets × 4 ways, 32-byte lines. Set index = addr[7:5].
# The three addresses below all map to set 0 (addr[7:5]=000) but have
# different tags, allocating to way 0, 1, 2 in write order.
#
# Flush scans set 0 way 0 → way 1 → way 2. The TB injects BRESP error
# at LINE_2 (way 1, the middle dirty line). With the ISSUE-1 fix, the
# flush continues and writes back LINE_3 (way 2) after the error.
#
# Test verifies:
#   (1) Trap occurred: mcause=7 (store access fault), mtval=LINE_2
#   (2) LINE_1 memory = NEW_1 (writeback BEFORE error succeeded)
#   (3) LINE_2 memory = OLD_2 (writeback DROPPED due to error)
#   (4) LINE_3 memory = NEW_3 (writeback AFTER error succeeded — ISSUE-1 fix)
# ============================================================

.equ LINE_1, 0x80003000   # set 0, way 0 — flushed 1st (before error)
.equ LINE_2, 0x80004000   # set 0, way 1 — flushed 2nd (MIDDLE — error injected)
.equ LINE_3, 0x80005000   # set 0, way 2 — flushed 3rd (AFTER error — must still write back)

.equ OLD_2, 0x13579BDF    # preloaded by TB into LINE_2 memory (retained after error)
.equ NEW_1, 0x1234ABCD    # written to LINE_1 (writeback succeeds)
.equ NEW_3, 0xCAFEBABE    # written to LINE_3 (writeback must succeed after error)

.section .text.start
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10

    jal x1, test_init
    la x11, test_multi_dirty_wb_error_continues_flush
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

test_multi_dirty_wb_error_continues_flush:
    li  x22, 0
    li  x23, 0

    # Create 3 dirty lines in dcache (set 0, ways 0/1/2)
    li  x14, LINE_1
    li  x15, NEW_1
    sw  x15, 0(x14)

    li  x14, LINE_2
    li  x15, 0x87654321        # value doesn't matter (writeback will be dropped)
    sw  x15, 0(x14)

    li  x14, LINE_3
    li  x15, NEW_3
    sw  x15, 0(x14)

    # Trigger dcache flush — LINE_2 writeback gets wb_error (TB-injected)
    sfence.vma x0, x0

    # (1) Verify trap: mcause=7 (store access fault), mtval=LINE_2
    li  x16, 7
    bne x22, x16, _fail
    li  x16, LINE_2
    bne x23, x16, _fail

    # (2) LINE_1: memory has NEW_1 (writeback succeeded BEFORE error)
    li  x14, LINE_1
    lw  x15, 0(x14)
    li  x16, NEW_1
    bne x15, x16, _fail

    # (3) LINE_2: memory has OLD_2 (writeback DROPPED due to error)
    li  x14, LINE_2
    lw  x15, 0(x14)
    li  x16, OLD_2
    bne x15, x16, _fail

    # (4) LINE_3: memory has NEW_3 (writeback succeeded AFTER error — ISSUE-1 fix)
    li  x14, LINE_3
    lw  x15, 0(x14)
    li  x16, NEW_3
    bne x15, x16, _fail

    li  x10, 1
    ret

_fail:
    li  x10, 0
    ret

.section .text
