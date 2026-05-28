# ============================================================
# regression/reg_bare_no_miss.s — Bug 9 regression: bare mode TLB miss
# Category: Regression
# Description: Verify satp=0 (bare mode) never triggers TLB miss
# Sub-tests: 3
# ============================================================
# Bug 9: When satp=0 (bare mode), TLB miss was incorrectly reported.
# Fix: MMU.sv checks i_sv32 = satp[31] && priv_mode!=M, so bare mode
# always bypasses TLB. Verify no spurious page faults in bare mode.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_count
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_bare_no_miss
    jal x1, test_run
    la x11, test_bare_after_sv32
    jal x1, test_run
    la x11, test_bare_multi_access
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: Bare mode accesses don't trigger trap ──
test_bare_no_miss:
    li x10, 0x1880             # disable MIE
    csrw mstatus, x10
    csrw satp, x0               # ensure bare mode
    addi x23, x0, 0             # clear trap counter

    # Do several loads in bare mode
    la x14, test_data
    lw x15, 0(x14)              # simple load
    lw x16, 4(x14)              # another load
    la x14, test_data2
    lw x17, 0(x14)              # different address

    # No trap should have occurred
    bnez x23, 1f                # trap counter should be 0
    li x10, 1
    ret
1:  li x10, 0
    ret


# ── Sub-test 2: Bare mode after Sv32 disable works ──
test_bare_after_sv32:
    # Save return address (use x6 — setup_identity_map uses x5)
    add  x6, x1, x0             # save ra

    # Enable then disable Sv32, verify bare mode works after
    jal x1, setup_identity_map
    jal x1, enable_sv32
    csrw satp, x0               # disable Sv32
    fence.i                      # flush caches

    # Restore return address
    add  x1, x6, x0             # restore ra

    addi x23, x0, 0             # clear trap counter

    # Access data in bare mode
    la x14, test_data
    lw x15, 0(x14)
    li x16, 0xDEADBEEF
    bne x15, x16, 1f

    # Verify no traps
    bnez x23, 1f
    li x10, 1
    ret
1:  li x10, 0
    ret


# ── Sub-test 3: Multiple bare mode accesses across different addresses ──
test_bare_multi_access:
    li x10, 0x1880             # disable MIE
    csrw mstatus, x10
    csrw satp, x0
    addi x23, x0, 0

    # Access multiple addresses
    lui x14, 0x80000            # page 0 (code area)
    lw x15, 0(x14)
    lui x14, 0x80003            # page 3 (data area)
    lw x15, 0(x14)
    lui x14, 0x80007            # page 7 (result area)
    lw x15, 0(x14)

    bnez x23, 1f
    li x10, 1
    ret
1:  li x10, 0
    ret


# ── Data ──
.section .text
.balign 4
test_data:
    .word 0xDEADBEEF
    .word 0xCAFEBABE
test_data2:
    .word 0x12345678
