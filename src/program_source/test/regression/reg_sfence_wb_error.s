# ============================================================
# regression/reg_sfence_wb_error.s — SFENCE.VMA flush write-back error regression
# Category: Regression (common) | Sub-tests: 1
# ============================================================

.equ TEST_ADDR, 0x80003000

.section .text.start
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10

    jal x1, test_init
    la x11, test_sfence_wb_error_traps_and_drops_dirty_line
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

test_sfence_wb_error_traps_and_drops_dirty_line:
    li  x22, 0
    li  x23, 0

    li  x14, TEST_ADDR
    li  x15, 0x1234ABCD
    sw  x15, 0(x14)

    sfence.vma x0, x0

    li  x16, 7
    bne x22, x16, _fail
    li  x16, TEST_ADDR
    bne x23, x16, _fail

    lw  x15, 0(x14)
    mv  x24, x15
    li  x16, 0x13579BDF
    bne x15, x16, _fail

    li  x10, 1
    ret

_fail:
    li  x10, 0
    ret

.section .text
