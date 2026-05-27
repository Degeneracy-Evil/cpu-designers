# ============================================================
# isa/m_ext.s — M-extension (multiply/divide) tests
# 类别:   ISA
# 描述:   测试 M 扩展指令 (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
# 子测试: 16
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================

.section .text.start
.globl _start

_start:
    # ── 全局 Setup ──
    la   x10, m_trap_simple
    csrw mtvec, x10
    li   x10, 0x88             # MSTATUS: MPP=M, MPIE=1, MIE=1
    csrw mstatus, x10

    # ── 框架初始化 ──
    jal  x1, test_init

    # ── 运行子测试 ──
    la   x11, test_01_mul
    jal  x1, test_run
    la   x11, test_02_mulh
    jal  x1, test_run
    la   x11, test_03_mulhsu
    jal  x1, test_run
    la   x11, test_04_mulhu
    jal  x1, test_run
    la   x11, test_05_div
    jal  x1, test_run
    la   x11, test_06_divu
    jal  x1, test_run
    la   x11, test_07_rem
    jal  x1, test_run
    la   x11, test_08_remu
    jal  x1, test_run
    la   x11, test_09_mul_zero
    jal  x1, test_run
    la   x11, test_10_div_zero
    jal  x1, test_run
    la   x11, test_11_divu_zero
    jal  x1, test_run
    la   x11, test_12_mul_identity
    jal  x1, test_run
    la   x11, test_13_div_identity
    jal  x1, test_run
    la   x11, test_14_mul_neg
    jal  x1, test_run
    la   x11, test_15_div_neg
    jal  x1, test_run
    la   x11, test_16_rem_neg
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试
# ============================================================

# Test 1: MUL — 100 * 7 = 700
test_01_mul:
    li   x10, 100
    li   x11, 7
    mul  x12, x10, x11
    li   x13, 700
    li   x10, 1
    beq  x12, x13, _t01_end
    li   x10, 0
_t01_end:
    ret

# Test 2: MULH — (-1) * (-1) signed, high 32 bits
#   (-1) * (-1) = 1 → 64-bit = 0x0000000000000001 → high = 0x00000000
test_02_mulh:
    li   x10, -1
    li   x11, -1
    mulh x12, x10, x11
    li   x13, 0
    li   x10, 1
    beq  x12, x13, _t02_end
    li   x10, 0
_t02_end:
    ret

# Test 3: MULHSU — (-1) signed * (-1) unsigned, high 32 bits
#   (-1) * 0xFFFFFFFF = -4294967295 → 64-bit = 0xFFFFFFFF00000001 → high = 0xFFFFFFFF
test_03_mulhsu:
    li   x10, -1
    li   x11, -1
    mulhsu x12, x10, x11
    li   x13, -1               # 0xFFFFFFFF
    li   x10, 1
    beq  x12, x13, _t03_end
    li   x10, 0
_t03_end:
    ret

# Test 4: MULHU — (-1) unsigned * (-1) unsigned, high 32 bits
#   0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001 → high = 0xFFFFFFFE
test_04_mulhu:
    li   x10, -1
    li   x11, -1
    mulhu x12, x10, x11
    li   x13, -2               # 0xFFFFFFFE
    li   x10, 1
    beq  x12, x13, _t04_end
    li   x10, 0
_t04_end:
    ret

# Test 5: DIV — 100 / 7 = 14 (truncate toward zero)
test_05_div:
    li   x10, 100
    li   x11, 7
    div  x12, x10, x11
    li   x13, 14
    li   x10, 1
    beq  x12, x13, _t05_end
    li   x10, 0
_t05_end:
    ret

# Test 6: DIVU — 0xFFFFFFFF / 7 unsigned = 613566756 (0x24924924)
test_06_divu:
    li   x10, -1               # 0xFFFFFFFF
    li   x11, 7
    divu x12, x10, x11
    li   x13, 0x24924924
    li   x10, 1
    beq  x12, x13, _t06_end
    li   x10, 0
_t06_end:
    ret

# Test 7: REM — 100 % 7 = 2
test_07_rem:
    li   x10, 100
    li   x11, 7
    rem  x12, x10, x11
    li   x13, 2
    li   x10, 1
    beq  x12, x13, _t07_end
    li   x10, 0
_t07_end:
    ret

# Test 8: REMU — 0xFFFFFFFF % 7 unsigned = 3
test_08_remu:
    li   x10, -1               # 0xFFFFFFFF
    li   x11, 7
    remu x12, x10, x11
    li   x13, 3
    li   x10, 1
    beq  x12, x13, _t08_end
    li   x10, 0
_t08_end:
    ret

# Test 9: MUL by zero — 0 * 42 = 0
test_09_mul_zero:
    li   x10, 0
    li   x11, 42
    mul  x12, x10, x11
    li   x10, 1
    beq  x12, x0, _t09_end
    li   x10, 0
_t09_end:
    ret

# Test 10: DIV by zero — 42 / 0 = -1 (RISC-V spec)
test_10_div_zero:
    li   x10, 42
    li   x11, 0
    div  x12, x10, x11
    li   x13, -1
    li   x10, 1
    beq  x12, x13, _t10_end
    li   x10, 0
_t10_end:
    ret

# Test 11: DIVU by zero — 42 /u 0 = 0xFFFFFFFF (RISC-V spec)
test_11_divu_zero:
    li   x10, 42
    li   x11, 0
    divu x12, x10, x11
    li   x13, -1               # 0xFFFFFFFF
    li   x10, 1
    beq  x12, x13, _t11_end
    li   x10, 0
_t11_end:
    ret

# Test 12: MUL identity — x * 1 = x
test_12_mul_identity:
    li   x10, 12345
    li   x11, 1
    mul  x12, x10, x11
    li   x13, 12345
    li   x10, 1
    beq  x12, x13, _t12_end
    li   x10, 0
_t12_end:
    ret

# Test 13: DIV identity — x / 1 = x
test_13_div_identity:
    li   x10, 12345
    li   x11, 1
    div  x12, x10, x11
    li   x13, 12345
    li   x10, 1
    beq  x12, x13, _t13_end
    li   x10, 0
_t13_end:
    ret

# Test 14: MUL negative — (-5) * 7 = -35
test_14_mul_neg:
    li   x10, -5
    li   x11, 7
    mul  x12, x10, x11
    li   x13, -35
    li   x10, 1
    beq  x12, x13, _t14_end
    li   x10, 0
_t14_end:
    ret

# Test 15: DIV negative — (-100) / 7 = -14 (RISC-V truncates toward zero)
test_15_div_neg:
    li   x10, -100
    li   x11, 7
    div  x12, x10, x11
    li   x13, -14
    li   x10, 1
    beq  x12, x13, _t15_end
    li   x10, 0
_t15_end:
    ret

# Test 16: REM negative — (-100) % 7 = -2 (RISC-V: remainder same sign as dividend)
test_16_rem_neg:
    li   x10, -100
    li   x11, 7
    rem  x12, x10, x11
    li   x13, -2
    li   x10, 1
    beq  x12, x13, _t16_end
    li   x10, 0
_t16_end:
    ret
