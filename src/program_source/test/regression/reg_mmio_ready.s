# ============================================================
# regression/reg_mmio_ready.s — Bug 10 regression: MMIO mmu_ready gating
# Category: Regression
# Description: Verify CLINT reads return correct data, no offset corruption
# Sub-tests: 4
# ============================================================
# Bug 10: CLINT read happened before mmu_ready, getting wrong offset/data.
# Fix: MMIO access waits for mmu_ready signal. Verify CLINT reads work.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10
    li x10, 0x1880
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_mtime_read_consistent
    jal x1, test_run
    la x11, test_mtimecmp_rw_verify
    jal x1, test_run
    la x11, test_mtime_hi_lo_consistency
    jal x1, test_run
    la x11, test_repeated_mtime_reads
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: mtime reads return consistent values ──
test_mtime_read_consistent:
    # Read mtime_lo twice with short delay
    lui x14, 0x0200B
    li x15, 0xFF8
    add x15, x14, x15          # mtime_lo addr
    lw x16, 0(x15)             # first read

    # Short delay
    li x17, 20
1:  addi x17, x17, -1
    bnez x17, 1b

    lw x17, 0(x15)             # second read

    # Second read should be >= first (monotonically increasing)
    li x10, 1
    bge x17, x16, 2f
    li x10, 0
2:  ret


# ── Sub-test 2: mtimecmp write/read roundtrip ──
test_mtimecmp_rw_verify:
    # Disable interrupts
    li x10, 0x1880
    csrw mstatus, x10

    # Write known values to mtimecmp
    lui x14, 0x02004
    li x15, 0xABCD1234
    sw x15, 0(x14)             # mtimecmp_lo
    li x15, 0x5678FEDC
    sw x15, 4(x14)             # mtimecmp_hi

    # Read back
    lw x16, 0(x14)
    li x15, 0xABCD1234
    bne x16, x15, _clint_fail

    lw x16, 4(x14)
    li x15, 0x5678FEDC
    bne x16, x15, _clint_fail

    # Restore mtimecmp to far future
    li x15, -1
    sw x15, 0(x14)
    sw x15, 4(x14)

    li x10, 1
    ret
_clint_fail:
    lui x14, 0x02004
    li x15, -1
    sw x15, 0(x14)
    sw x15, 4(x14)
    li x10, 0
    ret


# ── Sub-test 3: mtime hi/lo consistency check ──
test_mtime_hi_lo_consistency:
    # Read mtime_lo, then mtime_hi, then mtime_lo again
    # If lo overflowed between reads, the second lo should be much smaller
    lui x14, 0x0200B
    li x15, 0xFF8
    add x15, x14, x15
    lw x16, 0(x15)             # mtime_lo first

    li x15, 0xFFC
    add x15, x14, x15
    lw x17, 0(x15)             # mtime_hi

    li x15, 0xFF8
    add x15, x14, x15
    # x18 is owned by test_framework as first_fail_id; keep sub-tests from
    # clobbering it even though this routine is otherwise leaf-only.
    lw x7, 0(x15)              # mtime_lo second

    # mtime_hi should be 0 (not enough cycles to overflow)
    # Second lo >= first lo (unless overflow happened)
    bnez x17, _mtime_overflow_ok

    # No overflow: second >= first
    li x10, 1
    bge x7, x16, 2f
    li x10, 0
2:  ret

_mtime_overflow_ok:
    # If hi is non-zero, lo could have wrapped
    li x10, 1
    ret


# ── Sub-test 4: Repeated mtime reads show increment ──
test_repeated_mtime_reads:
    lui x14, 0x0200B
    li x15, 0xFF8
    add x15, x14, x15

    lw x16, 0(x15)             # first

    # Longer delay
    li x17, 100
1:  addi x17, x17, -1
    bnez x17, 1b

    lw x17, 0(x15)             # second

    li x10, 1
    bgt x17, x16, 2f
    li x10, 0
2:  ret
