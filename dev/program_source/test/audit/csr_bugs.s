# ============================================================
# audit/csr_bugs.s — CSR bug verification + discovery
# Category: Audit | Sub-tests: 8
# ============================================================
# Tests:
#   1. BUG-CSR-5: mstatus SPIE write cleared (bit 5)
#   2. mstatus SPP write/read (bit 8)
#   3. mstatus MPP write/read (bits 12:11)
#   4. mip/sip SEIP software write path (bit 9)
#   5. mip/sip SSIP software write path (bit 1)
#   6. BUG-CSR-3: sip read after mip write (r_sip path)
#   7. mstatus MPIE write/read (bit 7)
# (test 8 removed: scounteren is SRW — S-mode write is legal per spec)
# ============================================================

.equ PLIC_BASE,    0x0C000000
.equ PLIC_PRIO2,   0x0C000008   # Priority[2] (UART)
.equ PLIC_ENABLE0, 0x0C002000   # Enable context 0 (M-mode)
.equ PLIC_ENABLE1, 0x0C002080   # Enable context 1 (S-mode)
.equ PLIC_THRESH0, 0x0C200000   # Threshold context 0
.equ PLIC_THRESH1, 0x0C201000   # Threshold context 1

.section .text.start
.globl _start

_start:
    la   x10, audit_trap_handler
    csrw mtvec, x10
    li   x10, 0x1888             # MPP=M, MPIE=1, MIE=1, SPIE=1
    csrw mstatus, x10

    jal  x1, test_init

    la   x11, test_01_mstatus_spie_write
    jal  x1, test_run
    la   x11, test_02_mstatus_spp_write
    jal  x1, test_run
    la   x11, test_03_mstatus_mpp_write
    jal  x1, test_run
    la   x11, test_04_mip_seip_sw_write
    jal  x1, test_run
    la   x11, test_05_mip_ssip_sw_write
    jal  x1, test_run
    la   x11, test_06_sip_read_after_mip_write
    jal  x1, test_run
    la   x11, test_07_mstatus_mpie_write
    jal  x1, test_run

    jal  x1, test_report
    fence.i

end_loop:
    j    end_loop

# ── Sub-test 1: mstatus SPIE write (BUG-CSR-5) ──
# Write SPIE=1 (bit 5), read back, check bit 5
# Bug: mstatus_wmask bits[6:4]=0 → SPIE forced to 0
test_01_mstatus_spie_write:
    li   x10, 0x8A0              # MPP=M(0x800) | MPIE=1(0x80) | SPIE=1(0x20)
    csrw mstatus, x10
    csrr x11, mstatus
    andi x12, x11, 0x20          # extract SPIE (bit 5)
    li   x10, 1
    bnez x12, 1f
    li   x10, 0                  # FAIL: SPIE cleared
1:  ret

# ── Sub-test 2: mstatus SPP write/read (bit 8) ──
# SPP is 1 bit (bit 8). Write SPP=1, read back.
test_02_mstatus_spp_write:
    li   x10, 0x900              # MPP=M(0x800) | SPP=1(0x100)
    csrw mstatus, x10
    csrr x11, mstatus
    andi x12, x11, 0x100         # extract SPP (bit 8)
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  ret

# ── Sub-test 3: mstatus MPP write/read (bits 12:11) ──
# MPP is 2 bits (bits 12:11). Write MPP=01 (S-mode), read back.
test_03_mstatus_mpp_write:
    li   x10, 0x800              # MPP=00 (M-mode) as baseline
    csrw mstatus, x10
    li   x10, 0x880              # MPP=01 (S-mode, 0x800) | MPIE=1
    csrw mstatus, x10
    csrr x11, mstatus
    li   x13, 0x1800
    and  x12, x11, x13           # extract MPP+SPP (bits 12:8)
    li   x13, 0x800              # expect MPP=01, SPP=0
    li   x10, 1
    beq  x12, x13, 1f
    li   x10, 0
1:  ret

# ── Sub-test 4: mip SEIP software write (bit 9) ──
# Write mip[9]=1, read mip, check bit 9
test_04_mip_seip_sw_write:
    csrw mip, x0                 # clear all pending
    li   x10, 0x200              # SEIP (bit 9)
    csrw mip, x10
    csrr x11, mip
    andi x12, x11, 0x200         # extract SEIP
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  csrw mip, x0                 # cleanup
    ret

# ── Sub-test 5: mip SSIP software write (bit 1) ──
# Write mip[1]=1, read mip, check bit 1
test_05_mip_ssip_sw_write:
    csrw mip, x0
    li   x10, 0x2                # SSIP (bit 1)
    csrw mip, x10
    csrr x11, mip
    andi x12, x11, 0x2           # extract SSIP
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  csrw mip, x0
    ret

# ── Sub-test 6: sip read after mip write (BUG-CSR-3 r_sip path) ──
# Write mip[9]=1 (sets r_sip[9]), read sip, check bit 9
# Bug: sip read may not include r_sip[9]
test_06_sip_read_after_mip_write:
    csrw mip, x0
    li   x10, 0x200              # SEIP (bit 9)
    csrw mip, x10
    csrr x11, sip                # read S-mode interrupt pending
    andi x12, x11, 0x200         # extract SEIP from sip
    li   x10, 1
    bnez x12, 1f
    li   x10, 0                  # FAIL: sip doesn't reflect mip write
1:  csrw mip, x0
    ret

# ── Sub-test 7: mstatus MPIE write/read (bit 7) ──
# MPIE is bit 7. Write MPIE=1, read back.
test_07_mstatus_mpie_write:
    li   x10, 0x880              # MPP=M(0x800) | MPIE=1(0x80)
    csrw mstatus, x10
    csrr x11, mstatus
    andi x12, x11, 0x80          # extract MPIE (bit 7)
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  ret

# ── Sub-test 8: scounteren S-mode write traps ──
test_08_scounteren_smode_write:
    la   x5, audit_saved_ra; sw  x1, 0(x5)
    la   x5, post_scounteren; la x6, audit_return_pc; sw x5, 0(x6)
    sw   x0, 8(x6)               # clear got_fault
    jal  x1, setup_identity_map
    jal  x1, enable_sv32
    la   x5, s_scounteren_test; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_scounteren_test:
    li   x10, 0x7
    csrw scounteren, x10         # S-mode write — should trap
    li   x10, 0                  # if we reach here → no trap → FAIL
    ecall

post_scounteren:
    la   x5, audit_got_fault; lw  x5, 0(x5)
    beqz x5, 1f                  # no fault → FAIL
    la   x5, audit_fault_cause; lw x5, 0(x5)
    li   x6, 2; beq  x5, x6, 2f  # illegal instruction → PASS
1:  li   x10, 0; j 3f
2:  li   x10, 1
3:  la   x5, audit_saved_ra; lw  x1, 0(x5); ret

# ============================================================
# Trap Handler
# ============================================================
audit_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    li   x5, 9; beq  x22, x5, _ath_ecall
    li   x5, 8; beq  x22, x5, _ath_ecall
    li   x5, 11; beq x22, x5, _ath_ecall
    la   x5, audit_fault_cause; sw x22, 0(x5)
    la   x5, audit_fault_val;   sw x24, 0(x5)
    li   x5, 1; la x6, audit_got_fault; sw x5, 0(x6)
    la   x5, audit_return_pc; lw x5, 0(x5)
    beqz x5, _ath_fatal
    csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5
    la   x5, audit_return_pc; sw x0, 0(x5); mret
_ath_fatal:
    la   x5, audit_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li   x10, 0; li x5, 0x1888; csrw mstatus, x5; mret
_ath_ecall:
    la   x5, audit_result; lw x10, 0(x5)
    la   x5, audit_return_pc; lw x5, 0(x5)
    bnez x5, _ath_ecall_post
    la   x5, audit_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li   x5, 0x1888; csrw mstatus, x5; mret
_ath_ecall_post:
    csrw mepc, x5; la x5, audit_return_pc; sw x0, 0(x5)
    li   x5, 0x1888; csrw mstatus, x5; mret

# ============================================================
# Data
# ============================================================
.section .text
.balign 4
audit_saved_ra:    .word 0
audit_return_pc:   .word 0
audit_result:      .word 0
audit_got_fault:   .word 0
audit_fault_cause: .word 0
audit_fault_val:   .word 0
