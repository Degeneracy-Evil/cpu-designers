# ============================================================
# privilege/wfi.s — WFI privilege and forward-progress tests
# Category: Privilege
# Sub-tests: 6
# ============================================================
# This CPU intentionally implements legal WFI instructions as immediately
# completing NOPs.  The privileged architecture permits this behavior.  TW=1
# is implemented by trapping WFI outside M-mode as an illegal instruction.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, wfi_trap_handler
    csrw mtvec, x10
    csrw medeleg, x0
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_m_wfi_tw0
    jal x1, test_run
    la x11, test_02_m_wfi_tw1
    jal x1, test_run
    la x11, test_03_s_wfi_tw0
    jal x1, test_run
    la x11, test_04_s_wfi_tw1_illegal
    jal x1, test_run
    la x11, test_05_u_wfi_tw1_illegal
    jal x1, test_run
    la x11, test_06_malformed_wfi_illegal
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

test_01_m_wfi_tw0:
    li x5, 0x200000
    csrc mstatus, x5
    wfi
    li x10, 1
    ret

test_02_m_wfi_tw1:
    li x5, 0x200000
    csrs mstatus, x5
    wfi                         # TW does not restrict M-mode
    csrc mstatus, x5
    li x10, 1
    ret

test_03_s_wfi_tw0:
    la x5, wfi_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    sw x0, 8(x5)
    la x5, post_03
    la x6, wfi_resume_pc
    sw x5, 0(x6)
    la x5, s_wfi_tw0
    csrw mepc, x5
    li x5, 0x0880              # MPP=S, MPIE=1, TW=0
    csrw mstatus, x5
    mret
s_wfi_tw0:
    wfi
    li x5, 1
    la x6, wfi_marker
    sw x5, 0(x6)
    ecall
post_03:
    la x5, wfi_marker
    lw x6, 0(x5)
    li x10, 0
    li x7, 1
    bne x6, x7, 1f
    la x5, wfi_cause
    lw x6, 0(x5)
    li x7, 9                   # environment call from S-mode
    bne x6, x7, 1f
    li x10, 1
1:  la x5, wfi_saved_ra
    lw x1, 0(x5)
    ret

test_04_s_wfi_tw1_illegal:
    la x5, wfi_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    sw x0, 8(x5)
    la x5, post_04
    la x6, wfi_resume_pc
    sw x5, 0(x6)
    la x5, s_wfi_tw1
    csrw mepc, x5
    li x5, 0x200880            # TW=1, MPP=S, MPIE=1
    csrw mstatus, x5
    mret
s_wfi_tw1:
    wfi                         # must trap as illegal instruction
    j end_loop
post_04:
    jal x1, check_illegal_wfi
    la x5, wfi_saved_ra
    lw x1, 0(x5)
    ret

test_05_u_wfi_tw1_illegal:
    la x5, wfi_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    sw x0, 8(x5)
    la x5, post_05
    la x6, wfi_resume_pc
    sw x5, 0(x6)
    la x5, u_wfi_tw1
    csrw mepc, x5
    li x5, 0x200080            # TW=1, MPP=U, MPIE=1
    csrw mstatus, x5
    mret
u_wfi_tw1:
    wfi                         # must trap as illegal instruction
    j end_loop
post_05:
    jal x1, check_illegal_wfi
    la x5, wfi_saved_ra
    lw x1, 0(x5)
    ret

test_06_malformed_wfi_illegal:
    la x5, wfi_saved_ra
    sw x1, 0(x5)
    sw x0, 4(x5)
    sw x0, 8(x5)
    la x5, post_06
    la x6, wfi_resume_pc
    sw x5, 0(x6)
    .word 0x105000f3           # WFI funct12 with rd=x1: reserved encoding
    j end_loop
post_06:
    la x5, wfi_cause
    lw x6, 0(x5)
    li x10, 0
    li x7, 2
    bne x6, x7, 1f
    la x5, wfi_tval
    lw x6, 0(x5)
    li x7, 0x105000f3
    bne x6, x7, 1f
    li x10, 1
1:  la x5, wfi_saved_ra
    lw x1, 0(x5)
    ret

check_illegal_wfi:
    la x5, wfi_cause
    lw x6, 0(x5)
    li x10, 0
    li x7, 2
    bne x6, x7, 1f
    la x5, wfi_tval
    lw x6, 0(x5)
    li x7, 0x10500073
    bne x6, x7, 1f
    li x10, 1
1:  ret

wfi_trap_handler:
    csrr x5, mcause
    la x6, wfi_cause
    sw x5, 0(x6)
    csrr x5, mtval
    la x6, wfi_tval
    sw x5, 0(x6)
    la x6, wfi_resume_pc
    lw x5, 0(x6)
    csrw mepc, x5
    li x5, 0x1880              # return to M-mode with TW cleared
    csrw mstatus, x5
    mret

.section .data
.balign 4
wfi_saved_ra:  .word 0
wfi_cause:     .word 0
wfi_tval:      .word 0
wfi_resume_pc: .word 0
wfi_marker:    .word 0
