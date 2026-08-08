# ============================================================
# privilege/counter_access.s — counter-enable privilege tests
# Category: Privilege
# Sub-tests: 7
# ============================================================
# S-mode counter aliases are controlled by mcounteren. U-mode aliases require
# the corresponding bits in both mcounteren and scounteren.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, counter_trap_handler
    csrw mtvec, x10
    csrw medeleg, x0
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init
    la x11, test_01_m_time_always_allowed; jal x1, test_run
    la x11, test_02_s_time_denied_by_mcounteren; jal x1, test_run
    la x11, test_03_s_time_allowed_by_mcounteren; jal x1, test_run
    la x11, test_04_u_time_denied_by_mcounteren; jal x1, test_run
    la x11, test_05_u_time_denied_by_scounteren; jal x1, test_run
    la x11, test_06_u_time_allowed_by_both; jal x1, test_run
    la x11, test_07_minstret_counts_non_wb_instructions; jal x1, test_run
    jal x1, test_report

end_loop:
    j end_loop

test_01_m_time_always_allowed:
    csrw mcounteren, x0
    csrw scounteren, x0
    csrr x5, time
    li x10, 1
    ret

test_02_s_time_denied_by_mcounteren:
    csrw mcounteren, x0
    li x5, 2
    csrw scounteren, x5
    la x5, post_02
    jal x31, prepare_lower_test
    la x5, s_time_denied
    csrw mepc, x5
    li x5, 0x0880
    csrw mstatus, x5
    mret
s_time_denied:
    csrr x5, time
    j end_loop
post_02:
    jal x1, check_illegal
    jal x0, finish_lower_test

test_03_s_time_allowed_by_mcounteren:
    li x5, 2
    csrw mcounteren, x5
    csrw scounteren, x0       # must not restrict S-mode
    la x5, post_03
    jal x31, prepare_lower_test
    la x5, s_time_allowed
    csrw mepc, x5
    li x5, 0x0880
    csrw mstatus, x5
    mret
s_time_allowed:
    csrr x5, time
    li x5, 1
    la x6, counter_marker
    sw x5, 0(x6)
    ecall
post_03:
    li x5, 9
    jal x1, check_legal
    jal x0, finish_lower_test

test_04_u_time_denied_by_mcounteren:
    csrw mcounteren, x0
    li x5, 2
    csrw scounteren, x5
    la x5, post_04
    jal x31, prepare_lower_test
    la x5, u_time_denied_m
    csrw mepc, x5
    li x5, 0x0080
    csrw mstatus, x5
    mret
u_time_denied_m:
    csrr x5, time
    j end_loop
post_04:
    jal x1, check_illegal
    jal x0, finish_lower_test

test_05_u_time_denied_by_scounteren:
    li x5, 2
    csrw mcounteren, x5
    csrw scounteren, x0
    la x5, post_05
    jal x31, prepare_lower_test
    la x5, u_time_denied_s
    csrw mepc, x5
    li x5, 0x0080
    csrw mstatus, x5
    mret
u_time_denied_s:
    csrr x5, time
    j end_loop
post_05:
    jal x1, check_illegal
    jal x0, finish_lower_test

test_06_u_time_allowed_by_both:
    li x5, 2
    csrw mcounteren, x5
    csrw scounteren, x5
    la x5, post_06
    jal x31, prepare_lower_test
    la x5, u_time_allowed
    csrw mepc, x5
    li x5, 0x0080
    csrw mstatus, x5
    mret
u_time_allowed:
    csrr x5, time
    li x5, 1
    la x6, counter_marker
    sw x5, 0(x6)
    ecall
post_06:
    li x5, 8
    jal x1, check_legal
    jal x0, finish_lower_test

# The first CSR read itself retires after returning its old value.  Before the
# second read samples minstret, exactly five instructions must retire:
# first csrr, addi, taken branch, fence, and fence.i.
test_07_minstret_counts_non_wb_instructions:
    csrr x5, minstret
    addi x0, x0, 0
    beq x0, x0, 1f
    li x10, 0               # unreachable
1:  fence
    fence.i
    csrr x6, minstret
    sub x6, x6, x5
    li x10, 0
    li x7, 5
    bne x6, x7, 1f
    li x10, 1
1:  ret

# Input x5: M-mode resume address. Saves the framework return address and
# clears observations before entering a lower privilege mode.
prepare_lower_test:
    la x6, counter_saved_ra
    sw x1, 0(x6)
    la x6, counter_resume_pc
    sw x5, 0(x6)
    la x6, counter_cause
    sw x0, 0(x6)
    la x6, counter_marker
    sw x0, 0(x6)
    jalr x0, x31, 0

check_illegal:
    la x5, counter_cause
    lw x6, 0(x5)
    li x10, 0
    li x7, 2
    bne x6, x7, 1f
    li x10, 1
1:  ret

# Input x5: expected ECALL cause. A legal counter read stores marker=1 before
# trapping back to M-mode.
check_legal:
    la x6, counter_cause
    lw x7, 0(x6)
    li x10, 0
    bne x7, x5, 1f
    la x6, counter_marker
    lw x7, 0(x6)
    li x6, 1
    bne x7, x6, 1f
    li x10, 1
1:  ret

finish_lower_test:
    la x5, counter_saved_ra
    lw x1, 0(x5)
    ret

counter_trap_handler:
    csrr x5, mcause
    la x6, counter_cause
    sw x5, 0(x6)
    la x6, counter_resume_pc
    lw x5, 0(x6)
    csrw mepc, x5
    li x5, 0x1880
    csrw mstatus, x5
    mret

.section .data
.balign 4
counter_saved_ra:  .word 0
counter_resume_pc: .word 0
counter_cause:     .word 0
counter_marker:    .word 0
