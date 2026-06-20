# ============================================================
# regression/reg_dcache_refill_error.s — D-cache refill AXI error regression
# Category: Regression (common) | Sub-tests: 1
#
# TB pre-loads 0xA5A55A5A at 0x80004000 in SRAM before test starts,
# then injects RRESP error for the first refill at that address.
# Test verifies: (1) refill error → load access fault (mcause=5),
#                (2) retry after trap succeeds and returns correct data.
# ============================================================

.equ TEST_ADDR, 0x80004000
.equ TEST_DATA, 0xA5A55A5A

.section .text.start
.globl _start

_start:
    la x10, trap_handler
    csrw mtvec, x10

    jal x1, test_init
    la x11, test_refill_error_traps_and_recovers
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

test_refill_error_traps_and_recovers:
    li  x22, 0
    li  x23, 0

    # First read → cache miss → refill → RRESP error → trap
    li  x14, TEST_ADDR
    lw  x15, 0(x14)

    # Verify trap: mcause=5 (load access fault), mtval=TEST_ADDR
    li  x16, 5
    bne x22, x16, _fail
    li  x16, TEST_ADDR
    bne x23, x16, _fail

    # Second read → cache miss → refill → success (injection consumed)
    lw  x15, 0(x14)
    li  x16, TEST_DATA
    bne x15, x16, _fail

    li  x10, 1
    ret

_fail:
    li  x10, 0
    ret
