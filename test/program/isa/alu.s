# ============================================================
# isa/alu.s — ALU 运算测试
# 类别:   ISA
# 描述:   测试所有 ALU 指令 (R-type + I-type)
# 子测试: 20
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
    la   x11, test_01_add
    jal  x1, test_run
    la   x11, test_02_sub
    jal  x1, test_run
    la   x11, test_03_sll
    jal  x1, test_run
    la   x11, test_04_slt
    jal  x1, test_run
    la   x11, test_05_sltu
    jal  x1, test_run
    la   x11, test_06_xor
    jal  x1, test_run
    la   x11, test_07_srl
    jal  x1, test_run
    la   x11, test_08_sra
    jal  x1, test_run
    la   x11, test_09_or
    jal  x1, test_run
    la   x11, test_10_and
    jal  x1, test_run
    la   x11, test_11_addi
    jal  x1, test_run
    la   x11, test_12_slti
    jal  x1, test_run
    la   x11, test_13_sltiu
    jal  x1, test_run
    la   x11, test_14_xori
    jal  x1, test_run
    la   x11, test_15_ori
    jal  x1, test_run
    la   x11, test_16_andi
    jal  x1, test_run
    la   x11, test_17_slli
    jal  x1, test_run
    la   x11, test_18_srli
    jal  x1, test_run
    la   x11, test_19_srai
    jal  x1, test_run
    la   x11, test_20_addi_neg
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试: ALU R-type
# ============================================================

# Test 1: ADD — 正数加法
test_01_add:
    li   x10, 5
    li   x11, 7
    add  x12, x10, x11
    li   x13, 12
    li   x10, 1
    beq  x12, x13, _t01_end
    li   x10, 0
_t01_end:
    ret

# Test 2: SUB — 正数减法
test_02_sub:
    li   x10, 12
    li   x11, 5
    sub  x12, x10, x11
    li   x13, 7
    li   x10, 1
    beq  x12, x13, _t02_end
    li   x10, 0
_t02_end:
    ret

# Test 3: SLL — 逻辑左移
test_03_sll:
    li   x10, 5
    li   x11, 5
    sll  x12, x10, x11        # 5 << 5 = 160 = 0xA0
    li   x13, 0xA0
    li   x10, 1
    beq  x12, x13, _t03_end
    li   x10, 0
_t03_end:
    ret

# Test 4: SLT — 有符号小于 (正 < 正)
test_04_slt:
    li   x10, 5
    li   x11, 7
    slt  x12, x10, x11        # 5 < 7 = 1
    li   x13, 1
    li   x10, 1
    beq  x12, x13, _t04_end
    li   x10, 0
_t04_end:
    ret

# Test 5: SLTU — 无符号小于 (正 < 正)
test_05_sltu:
    li   x10, 7
    li   x11, 5
    sltu x12, x10, x11        # 7 <u 5 = 0
    li   x13, 0
    li   x10, 1
    beq  x12, x13, _t05_end
    li   x10, 0
_t05_end:
    ret

# Test 6: XOR — 异或
test_06_xor:
    li   x10, 5
    li   x11, 7
    xor  x12, x10, x11        # 5 ^ 7 = 2
    li   x13, 2
    li   x10, 1
    beq  x12, x13, _t06_end
    li   x10, 0
_t06_end:
    ret

# Test 7: SRL — 逻辑右移
test_07_srl:
    li   x10, 0x5555
    li   x11, 5
    srl  x12, x10, x11        # 0x5555 >> 5 = 0x2AA
    li   x13, 0x2AA
    li   x10, 1
    beq  x12, x13, _t07_end
    li   x10, 0
_t07_end:
    ret

# Test 8: SRA — 算术右移 (负数)
test_08_sra:
    li   x10, -1              # 0xFFFFFFFF
    li   x11, 5
    sra  x12, x10, x11        # -1 >>a 5 = -1
    li   x13, -1
    li   x10, 1
    beq  x12, x13, _t08_end
    li   x10, 0
_t08_end:
    ret

# Test 9: OR — 或
test_09_or:
    li   x10, 5
    li   x11, 7
    or   x12, x10, x11        # 5 | 7 = 7
    li   x13, 7
    li   x10, 1
    beq  x12, x13, _t09_end
    li   x10, 0
_t09_end:
    ret

# Test 10: AND — 与
test_10_and:
    li   x10, 5
    li   x11, 7
    and  x12, x10, x11        # 5 & 7 = 5
    li   x13, 5
    li   x10, 1
    beq  x12, x13, _t10_end
    li   x10, 0
_t10_end:
    ret


# ============================================================
# 子测试: ALU I-type
# ============================================================

# Test 11: ADDI — 立即数加法
test_11_addi:
    li   x10, 5
    addi x11, x10, 7          # 5 + 7 = 12
    li   x12, 12
    li   x10, 1
    beq  x11, x12, _t11_end
    li   x10, 0
_t11_end:
    ret

# Test 12: SLTI — 有符号小于立即数
test_12_slti:
    li   x10, 5
    slti x11, x10, 6          # 5 < 6 = 1
    li   x12, 1
    li   x10, 1
    beq  x11, x12, _t12_end
    li   x10, 0
_t12_end:
    ret

# Test 13: SLTIU — 无符号小于立即数
test_13_sltiu:
    li   x10, 5
    sltiu x11, x10, -1        # 5 <u 0xFFFFFFFF = 1
    li   x12, 1
    li   x10, 1
    beq  x11, x12, _t13_end
    li   x10, 0
_t13_end:
    ret

# Test 14: XORI — 异或立即数
test_14_xori:
    li   x10, 5
    xori x11, x10, 3          # 5 ^ 3 = 6
    li   x12, 6
    li   x10, 1
    beq  x11, x12, _t14_end
    li   x10, 0
_t14_end:
    ret

# Test 15: ORI — 或立即数
test_15_ori:
    li   x10, 5
    ori  x11, x10, 8          # 5 | 8 = 13
    li   x12, 13
    li   x10, 1
    beq  x11, x12, _t15_end
    li   x10, 0
_t15_end:
    ret

# Test 16: ANDI — 与立即数
test_16_andi:
    li   x10, 13
    andi x11, x10, 9          # 13 & 9 = 9
    li   x12, 9
    li   x10, 1
    beq  x11, x12, _t16_end
    li   x10, 0
_t16_end:
    ret

# Test 17: SLLI — 逻辑左移立即数
test_17_slli:
    li   x10, 5
    slli x11, x10, 3          # 5 << 3 = 40
    li   x12, 40
    li   x10, 1
    beq  x11, x12, _t17_end
    li   x10, 0
_t17_end:
    ret

# Test 18: SRLI — 逻辑右移立即数
test_18_srli:
    li   x10, 40
    srli x11, x10, 1          # 40 >> 1 = 20
    li   x12, 20
    li   x10, 1
    beq  x11, x12, _t18_end
    li   x10, 0
_t18_end:
    ret

# Test 19: SRAI — 算术右移立即数 (负数)
test_19_srai:
    li   x10, 40
    srai x11, x10, 2          # 40 >>a 2 = 10
    li   x12, 10
    li   x10, 1
    beq  x11, x12, _t19_end
    li   x10, 0
_t19_end:
    ret

# Test 20: ADDI — 负立即数
test_20_addi_neg:
    li   x10, 100
    addi x11, x10, -50        # 100 - 50 = 50
    li   x12, 50
    li   x10, 1
    beq  x11, x12, _t20_end
    li   x10, 0
_t20_end:
    ret
