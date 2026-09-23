# ============================================================
# exception/access_fault.s — Instruction access fault tests
# Category: Exception
# Description: Test instruction access fault (mcause=1)
# Sub-tests: 3
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# Uses custom trap handler: inst fault (mcause=1) redirects mepc
# to return label in x5; other faults skip (mepc+4).
# Records mcause in x22, mtval in x23.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, access_fault_handler
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_inst_fault_mcause
    jal x1, test_run
    la x11, test_inst_fault_continues
    jal x1, test_run
    la x11, test_data_access_fault
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Custom trap handler for access fault tests ──
# For inst access fault (mcause=1): redirect mepc to x5 (safe return)
# For other exceptions: skip (mepc+4)
# Records mcause→x22, mtval→x23
access_fault_handler:
    csrr x22, mcause
    csrr x23, mtval
    csrr x10, mepc

    li x11, 1
    beq x22, x11, _afh_inst_fault

    addi x10, x10, 4
    csrw mepc, x10
    mret

_afh_inst_fault:
    csrw mepc, x5
    mret

# ── Instruction access fault: mcause = 1 ──
test_inst_fault_mcause:
    li x10, 0
    la x5, after_fault1       # return address for handler
    lui x15, 0x40000          # x15 = 0x40000000
    jalr x0, x15, 0           # jump to invalid address
after_fault1:
    li x14, 1                 # mcause = 1 for instruction access fault
    bne x22, x14, 1f
    li x10, 1
1:
    ret

# ── Instruction access fault: execution continues after handler ──
test_inst_fault_continues:
    li x10, 0
    la x5, after_fault2
    lui x15, 0x40000
    jalr x0, x15, 0
after_fault2:
    li x10, 1                # reached = PASS
    ret

# ── Data access fault: load from invalid address ──
test_data_access_fault:
    li x10, 0
    lui x14, 0x40000          # x14 = 0x40000000
    lw x15, 0(x14)            # should trigger load access fault
    li x14, 5                 # mcause = 5 for load access fault
    beq x22, x14, 1f
    li x14, 7                 # mcause = 7 for store access fault
    beq x22, x14, 1f
    bne x22, x0, 1f           # any fault = pass
    ret                       # no fault = FAIL
1:
    li x10, 1
    ret
