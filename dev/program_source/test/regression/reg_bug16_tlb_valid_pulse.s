# ============================================================
# regression/reg_bug16_tlb_valid_pulse.s — BUG-16 regression
# Category: Regression | Sub-tests: 1
# ============================================================
# Scenario: Enable Sv32 with kernel-only megapage mapping (no identity).
# After csrw satp, the next instruction page-faults (no identity map).
# CPU traps to STVEC=0xC0000098 → MMU translates via megapage →
# PA 0x80000098 → trap handler executes.
#
# Without BUG-16 fix: TLB i_lookup_valid_r pulse expires during
# I_LOOKUP → MMU deadlocks (valid=0, hit=1, ready=0, miss=0).
# With BUG-16 fix: TLB lookup req stays active → valid stays 1 →
# trap handler executes → PASS.
# ============================================================

.section .text.start
.globl _start

_start:
    # ── M-mode setup ──
    la   x10, m_trap_handler
    csrw mtvec, x10
    li   x10, 0x1888
    csrw mstatus, x10

    # Delegate page faults to S-mode: inst pf(12), load pf(13), store pf(15)
    li   x10, 0xB000
    csrw medeleg, x10

    # Set up L1[0x300] = megapage: VA 0xC0000000 → PA 0x80000000, 4MB, RWXADG
    la   x15, l1_page_table
    li   x16, 0xC00           # offset = 0x300 * 4
    add  x14, x15, x16
    li   x17, 0x200000EF      # PTE: V=1,R=1,W=1,X=1,G=1,A=1,D=1, PPN=0x80000
    sw   x17, 0(x14)

    # Set stvec = 0xC0000098 (kernel virtual trap vector)
    lui  x10, 0xC0000
    addi x10, x10, 0x98
    csrw stvec, x10

    # mret to S-mode at s_entry
    la   x10, s_entry
    csrw mepc, x10
    li   x10, 0x880           # MPP=S(01), MPIE=1
    csrw mstatus, x10
    mret

# ── S-mode entry (after mret) ──
s_entry:
    sfence.vma
    la   x10, l1_page_table
    srli x10, x10, 12         # PPN = l1_page_table >> 12
    li   x11, 0x80000000      # Sv32 mode bit
    or   x10, x10, x11
    csrw satp, x10
    # ← PAGE FAULT: next inst at ~0x8000004C, no identity mapping
    # → trap to STVEC=0xC0000098 → MMU megapage → PA 0x80000098
    j    .

# ── Pad to offset 0x98 — trap handler MUST be at PA 0x80000098 ──
.balign 4
.org 0x98
s_trap_handler:
    # Arrived via megapage translation of VA 0xC0000098 → PA 0x80000098
    # BUG-16 fix confirmed: TLB valid stayed high, MMU returned ready
    li   x28, 1               # pass_count = 1
    li   x29, 1               # total_count = 1
    li   x30, 0               # first_fail_id = 0 (all pass)
    ecall                    # → M-mode trap handler

# ── M-mode trap handler ──
m_trap_handler:
    csrr x22, mcause
    li   x5, 9                # ECALL from S-mode
    beq  x22, x5, _m_ecall
    li   x5, 8                # ECALL from U-mode
    beq  x22, x5, _m_ecall
    # Unexpected trap — fail
    li   x28, 0
    li   x29, 1
    li   x30, 1               # first_fail_id = 1
    j    _m_done
_m_ecall:
    # x28/x29/x30 already hold the result. Avoid an M-mode data store here:
    # this regression is about post-satp trap delivery, and an extra store can
    # re-enter the trap path and mask the original BUG-16 behavior.
_m_done:
    j    _m_done
