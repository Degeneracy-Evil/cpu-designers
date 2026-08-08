# ============================================================
# regression/reg_dcache_store_error.s
# Write-through DCache store-response error regression
# Category: Regression (common) | Sub-tests: 1
#
# The testbench returns an AXI BRESP error for the first store to TEST_ADDR.
# The store must raise a precise store access fault. Because an errored store
# is not committed to the cache, a later retry must issue a new bus write and
# the reloaded value must come from that successful retry.
# ============================================================

.equ TEST_ADDR, 0x80003000
.equ TEST_DATA, 0x11223344

.section .text.start
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10

    jal x1, test_init
    la x11, test_store_error_is_precise_and_retryable
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

test_store_error_is_precise_and_retryable:
    li x22, 0
    li x23, 0

    li x14, TEST_ADDR
    li x15, TEST_DATA
    sw x15, 0(x14)

    li x16, 7
    bne x22, x16, _fail
    li x16, TEST_ADDR
    bne x23, x16, _fail

    # The one-shot error has been consumed. Retry and verify visibility.
    sw x15, 0(x14)
    lw x17, 0(x14)
    bne x17, x15, _fail

    li x10, 1
    ret

_fail:
    li x10, 0
    ret
