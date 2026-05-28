# ============================================================
# cache/icache_basic.s — I$ basic smoke tests
# Category: Cache
# Description: Verify icache doesn't corrupt instruction fetch
# Sub-tests: 3
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# Note: I$ hit/miss is not directly observable from software.
# These tests verify that instruction fetch works correctly through
# the icache, which implicitly tests refill, hit, and PLRU.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10

    jal x1, test_init

    la x11, test_icache_seq_fetch
    jal x1, test_run
    la x11, test_icache_branch_fetch
    jal x1, test_run
    la x11, test_icache_repeated_call
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop


# ── Sub-test 1: Sequential instruction fetch ──
# Execute a sequence of ALU operations — verifies icache refill works
test_icache_seq_fetch:
    li   x10, 10
    li   x11, 20
    add  x12, x10, x11        # 30
    sub  x13, x12, x10        # 20
    slli x14, x13, 2          # 80
    addi x15, x14, -2         # 78
    andi x16, x15, 0x3F       # 78 & 63 = 14

    li   x11, 14
    beq  x16, x11, 1f
    li   x10, 0
    ret
1:
    li   x10, 1
    ret


# ── Sub-test 2: Branch target fetch ──
# Branch to a different address — verifies icache handles branch targets
test_icache_branch_fetch:
    li   x10, 5
    li   x11, 10
    blt  x10, x11, _ibf_target  # taken branch
    li   x10, 0                 # should not reach here
    ret
_ibf_target:
    # We arrived via branch — icache fetched from new address
    li   x10, 1
    ret


# ── Sub-test 3: Repeated function call ──
# Call same function twice — second call should hit in icache
test_icache_repeated_call:
    # Save return address (x1 from test_run)
    add  x5, x1, x0            # save ra in t0 (caller-saved, not used by helper)

    # First call — likely icache miss → refill
    jal  x1, _irc_helper
    add  x12, x10, x0          # save first result

    # Second call — should hit in icache
    jal  x1, _irc_helper
    add  x13, x10, x0          # save second result

    # Restore original return address
    add  x1, x5, x0            # ra = original ra

    # Both should return same value (42)
    li   x11, 42
    bne  x12, x11, _irc_fail
    bne  x13, x11, _irc_fail
    li   x10, 1
    ret
_irc_fail:
    li   x10, 0
    ret

_irc_helper:
    li   x10, 42
    ret
