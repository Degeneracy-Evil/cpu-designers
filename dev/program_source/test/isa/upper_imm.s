# ============================================================
# isa/upper_imm.s — Upper immediate instruction tests
# Category: ISA
# Description: Test LUI and AUIPC instructions
# Sub-tests: 8
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_simple
    csrw mtvec, x10
    li x10, 0x88
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_lui_typical
    jal x1, test_run
    la x11, test_lui_max
    jal x1, test_run
    la x11, test_lui_zero
    jal x1, test_run
    la x11, test_auipc_zero
    jal x1, test_run
    la x11, test_auipc_nonzero
    jal x1, test_run
    la x11, test_lui_addi_combo
    jal x1, test_run
    la x11, test_lui_address
    jal x1, test_run
    la x11, test_lui_addi_neg
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── LUI with typical value: 0x12345 << 12 = 0x12345000 ──
test_lui_typical:
    li x10, 0
    lui x14, 0x12345
    li x17, 0x12345000
    bne x14, x17, 1f
    li x10, 1
1:
    ret

# ── LUI with max immediate: 0xFFFFF << 12 = 0xFFFFF000 ──
test_lui_max:
    li x10, 0
    lui x14, 0xFFFFF
    li x17, 0xFFFFF000
    bne x14, x17, 1f
    li x10, 1
1:
    ret

# ── LUI with zero: 0x0 << 12 = 0 ──
test_lui_zero:
    li x10, 0
    lui x14, 0x0
    bne x14, x0, 1f
    li x10, 1
1:
    ret

# ── AUIPC with 0: two consecutive auipc differ by 4 ──
test_auipc_zero:
    li x10, 0
    auipc x14, 0          # x14 = PC of this instruction
    auipc x15, 0          # x15 = PC of next instruction (x14 + 4)
    sub x16, x15, x14
    li x17, 4             # should differ by exactly 4
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── AUIPC with non-zero: result = PC + (imm << 12) ──
test_auipc_nonzero:
    li x10, 0
    auipc x14, 0          # x14 = PC of this instruction
    auipc x15, 1          # x15 = PC of this instruction + 0x1000
    # x15 - x14 should be 0x1004 (0x1000 from imm, +4 from 1 instruction gap)
    sub x16, x15, x14
    li x17, 0x1004
    bne x16, x17, 1f
    li x10, 1
1:
    ret

# ── LUI + ADDI combination: build 0x12345678 ──
test_lui_addi_combo:
    li x10, 0
    lui x14, 0x12345      # x14 = 0x12345000
    addi x14, x14, 0x678  # x14 = 0x12345678
    li x17, 0x12345678
    bne x14, x17, 1f
    li x10, 1
1:
    ret

# ── LUI for address construction: 0x80001 ──
test_lui_address:
    li x10, 0
    lui x14, 0x80001      # x14 = 0x80001000
    li x17, 0x80001000
    bne x14, x17, 1f
    li x10, 1
1:
    ret

# ── LUI + ADDI with negative offset: build 0xFFFFF000 + 0xFFF = 0xFFFFFFFF ──
test_lui_addi_neg:
    li x10, 0
    lui x14, 0xFFFFF      # x14 = 0xFFFFF000
    addi x14, x14, -1     # x14 = 0xFFFFEFFF
    li x17, 0xFFFFEFFF
    bne x14, x17, 1f
    li x10, 1
1:
    ret
