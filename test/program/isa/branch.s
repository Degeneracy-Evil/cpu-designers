# ============================================================
# isa/branch.s — Branch instruction tests
# Category: ISA
# Description: Test all branch instructions (BEQ/BNE/BLT/BGE/BLTU/BGEU)
# Sub-tests: 17
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

    la x11, test_beq_taken
    jal x1, test_run
    la x11, test_beq_not_taken
    jal x1, test_run
    la x11, test_bne_taken
    jal x1, test_run
    la x11, test_bne_not_taken
    jal x1, test_run
    la x11, test_blt_pos
    jal x1, test_run
    la x11, test_blt_neg
    jal x1, test_run
    la x11, test_blt_not_taken
    jal x1, test_run
    la x11, test_bge_pos
    jal x1, test_run
    la x11, test_bge_equal
    jal x1, test_run
    la x11, test_bge_not_taken
    jal x1, test_run
    la x11, test_bltu_taken
    jal x1, test_run
    la x11, test_bltu_not_taken
    jal x1, test_run
    la x11, test_bgeu_taken
    jal x1, test_run
    la x11, test_bgeu_not_taken
    jal x1, test_run
    la x11, test_beq_zero
    jal x1, test_run
    la x11, test_bne_zero
    jal x1, test_run
    la x11, test_branch_backward
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── BEQ taken: 5 == 5 ──
test_beq_taken:
    li x10, 0
    li x14, 5
    li x15, 5
    beq x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BEQ not-taken: 5 != 7 ──
test_beq_not_taken:
    li x10, 1
    li x14, 5
    li x15, 7
    beq x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BNE taken: 5 != 7 ──
test_bne_taken:
    li x10, 0
    li x14, 5
    li x15, 7
    bne x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BNE not-taken: 5 == 5 ──
test_bne_not_taken:
    li x10, 1
    li x14, 5
    li x15, 5
    bne x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BLT positive: 3 < 5 ──
test_blt_pos:
    li x10, 0
    li x14, 3
    li x15, 5
    blt x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BLT negative: -5 < 3 ──
test_blt_neg:
    li x10, 0
    li x14, -5
    li x15, 3
    blt x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BLT not-taken: 5 < 3 is false ──
test_blt_not_taken:
    li x10, 1
    li x14, 5
    li x15, 3
    blt x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BGE positive: 5 >= 3 ──
test_bge_pos:
    li x10, 0
    li x14, 5
    li x15, 3
    bge x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BGE equal: 5 >= 5 ──
test_bge_equal:
    li x10, 0
    li x14, 5
    li x15, 5
    bge x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BGE not-taken: 3 >= 5 is false ──
test_bge_not_taken:
    li x10, 1
    li x14, 3
    li x15, 5
    bge x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BLTU taken: 3 <u 5 ──
test_bltu_taken:
    li x10, 0
    li x14, 3
    li x15, 5
    bltu x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BLTU not-taken: as signed -1 < 1, but unsigned 0xFFFFFFFF > 1 ──
test_bltu_not_taken:
    li x10, 1
    li x14, -1
    li x15, 1
    bltu x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BGEU taken: 0xFFFFFFFF >=u 1 ──
test_bgeu_taken:
    li x10, 0
    li x14, -1
    li x15, 1
    bgeu x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BGEU not-taken: 1 >=u 0xFFFFFFFF is false ──
test_bgeu_not_taken:
    li x10, 1
    li x14, 1
    li x15, -1
    bgeu x14, x15, 1f
    ret
1:
    li x10, 0
    ret

# ── BEQ with zero: 0 == 0 ──
test_beq_zero:
    li x10, 0
    li x14, 0
    li x15, 0
    beq x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── BNE with zero: 0 != 5 ──
test_bne_zero:
    li x10, 0
    li x14, 0
    li x15, 5
    bne x14, x15, 1f
    ret
1:
    li x10, 1
    ret

# ── Backward branch (loop pattern): sum 1..5 = 15 ──
test_branch_backward:
    li x14, 5          # counter
    li x15, 0          # accumulator
    li x16, 1          # decrement
1:
    add x15, x15, x14
    sub x14, x14, x16
    bne x14, x0, 1b   # backward branch
    # x15 should be 15
    li x10, 0
    li x17, 15
    bne x15, x17, 2f
    li x10, 1
2:
    ret
