# ============================================================
# isa/d_ext_special.s — D-extension special values & edge cases
# 类别:   ISA-D
# 描述:   浮点特殊值 (NaN/Inf/零/次正规数)、舍入模式、fflags/fcsr 边界测试
# 子测试: 28
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
#
# 本文件聚焦 d_ext.s 未覆盖的特殊值和边界情况:
#   - qNaN/sNaN 传播与 NV 标志区分
#   - Inf 算术 (Inf+Inf, Inf-Inf, Inf*0, Inf*finite)
#   - 有符号零算术规则
#   - D 次正规数运算
#   - 5 种舍入模式 (RNE/RTZ/RDN/RUP/RMM) 通过 FCVT.W.D 验证
#   - fflags 累积
#   - fcsr 读写验证
#   - NaN-box 违例 (FLW 后 D 运算)
#   - FCVT.S.D NaN 处理 (qNaN/sNaN)
#   - FCVT.D.S 次正规数→正规数
#   - FCVT.W.D / FCVT.WU.D 饱和与 NV 标志
#
# fflags 位定义 (CSR 0x001):
#   bit 4: NV (Invalid Operation)
#   bit 3: DZ (Divide by Zero)
#   bit 2: OF (Overflow)
#   bit 1: UF (Underflow)
#   bit 0: NX (Inexact)
#
# 舍入模式 (frm, CSR 0x002):
#   000: RNE   001: RTZ   010: RDN   011: RUP   100: RMM   111: DYN
#
# fcsr 格式 (CSR 0x003):
#   bits [4:0] = fflags, bits [7:5] = frm
#
# NOTE: 子测试内不得使用 JAL/JALR 调用辅助函数 (会覆盖 ra,
#       导致 ret 跳转错误)。CSR 访问和常量加载必须内联。
#
# Double-precision 特殊值常量:
#   qNaN   = 0x7FF8000000000000  (hi=0x7FF80000, lo=0x00000000)
#   sNaN   = 0x7FF0000000000001  (hi=0x7FF00000, lo=0x00000001)
#   +Inf   = 0x7FF0000000000000  (hi=0x7FF00000, lo=0x00000000)
#   -Inf   = 0xFFF0000000000000  (hi=0xFFF00000, lo=0x00000000)
#   +0.0   = 0x0000000000000000  (hi=0x00000000, lo=0x00000000)
#   -0.0   = 0x8000000000000000  (hi=0x80000000, lo=0x00000000)
#   0.5    = 0x3FE0000000000000  (hi=0x3FE00000, lo=0x00000000)
#   1.0    = 0x3FF0000000000000  (hi=0x3FF00000, lo=0x00000000)
#   1.5    = 0x3FF8000000000000  (hi=0x3FF80000, lo=0x00000000)
#   2.0    = 0x4000000000000000  (hi=0x40000000, lo=0x00000000)
#   2.5    = 0x4004000000000000  (hi=0x40040000, lo=0x00000000)
#   -1.5   = 0xBFF8000000000000  (hi=0xBFF80000, lo=0x00000000)
#   最小次正规 = 0x0000000000000001  (hi=0x00000000, lo=0x00000001)
#   2^31   = 0x41E0000000000000  (hi=0x41E00000, lo=0x00000000)
#   -2^32  = 0xC1F0000000000000  (hi=0xC1F00000, lo=0x00000000)
#   2^32   = 0x41F0000000000000  (hi=0x41F00000, lo=0x00000000)
#   S 次正规 0x1 → D: 0x36A0000000000000 (hi=0x36A00000, lo=0x00000000)
#
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
    la   x11, test_01_qnan_add_no_nv
    jal  x1, test_run
    la   x11, test_02_snan_add_nv
    jal  x1, test_run
    la   x11, test_03_inf_add_inf
    jal  x1, test_run
    la   x11, test_04_inf_minus_inf
    jal  x1, test_run
    la   x11, test_05_inf_mul_zero
    jal  x1, test_run
    la   x11, test_06_inf_mul_finite
    jal  x1, test_run
    la   x11, test_07_pos_zero_plus_neg_zero
    jal  x1, test_run
    la   x11, test_08_pos_zero_minus_neg_zero
    jal  x1, test_run
    la   x11, test_09_neg_zero_plus_neg_zero
    jal  x1, test_run
    la   x11, test_10_subnormal_add_zero
    jal  x1, test_run
    la   x11, test_11_subnormal_add_subnormal
    jal  x1, test_run
    la   x11, test_12_rne_tie_to_even
    jal  x1, test_run
    la   x11, test_13_rtz_truncate
    jal  x1, test_run
    la   x11, test_14_rdn_toward_neg
    jal  x1, test_run
    la   x11, test_15_rup_toward_pos
    jal  x1, test_run
    la   x11, test_16_rmm_tie_to_max
    jal  x1, test_run
    la   x11, test_17_fflags_accum
    jal  x1, test_run
    la   x11, test_18_fcsr_rw
    jal  x1, test_run
    la   x11, test_19_nanbox_violation
    jal  x1, test_run
    la   x11, test_20_fcvt_s_d_qnan
    jal  x1, test_run
    la   x11, test_21_fcvt_s_d_snan
    jal  x1, test_run
    la   x11, test_22_fcvt_d_s_subnormal
    jal  x1, test_run
    la   x11, test_23_fcvt_w_d_large_pos
    jal  x1, test_run
    la   x11, test_24_fcvt_w_d_large_neg
    jal  x1, test_run
    la   x11, test_25_fcvt_w_d_nan
    jal  x1, test_run
    la   x11, test_26_fcvt_wu_d_neg
    jal  x1, test_run
    la   x11, test_27_fcvt_wu_d_large_pos
    jal  x1, test_run
    la   x11, test_28_fcvt_wu_d_nan
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 辅助宏 (复用自 d_ext.s)
# ============================================================

# LOAD_D: 加载 double 常数到浮点寄存器
#   用法: LOAD_D fd, hi_val, lo_val
#   原理: 将 hi/lo 两个字通过 SW 写入 scratch (0x80006000),
#         然后 FLD 加载 64-bit double 到 fd。
#   副作用: 修改 x14, x15
.macro LOAD_D fd, hi_val, lo_val
    lui  x14, 0x80006          # x14 = 0x80006000 (scratch)
    li   x15, \hi_val
    sw   x15, 4(x14)           # store high word
    li   x15, \lo_val
    sw   x15, 0(x14)           # store low word
    fld  \fd, 0(x14)           # load 64-bit double
.endm

# VERIFY_D: 验证浮点寄存器中的 double 值
#   用法: VERIFY_D fd, hi_val, lo_val
#   原理: FSD 存储 fd 到 scratch, LW 读回两个字并比较。
#   输出: x10 = 1 (PASS) 或 0 (FAIL)
#   副作用: 修改 x12, x13, x14, x15
.macro VERIFY_D fd, hi_val, lo_val
    lui  x14, 0x80006          # x14 = 0x80006000 (scratch)
    fsd  \fd, 0(x14)           # store 64-bit double
    lw   x12, 0(x14)           # read low word
    lw   x13, 4(x14)           # read high word
    li   x10, 1                # assume PASS
    li   x15, \lo_val
    bne  x12, x15, 8f          # skip to fail
    li   x15, \hi_val
    bne  x13, x15, 8f          # skip to fail
    j    9f                    # skip to end
8:
    li   x10, 0                # FAIL
9:
.endm


# ============================================================
# 子测试 — NaN 传播
# ============================================================

# Test 1: qNaN + 1.0 = qNaN, NV 不置位
#   qNaN 是安静 NaN, 运算传播 qNaN 但不触发 NV。
test_01_qnan_add_no_nv:
    csrw fflags, x0
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    fadd.d f12, f10, f11, rne             # qNaN + 1.0 = qNaN
    csrr x16, fflags                      # 保存标志 (x16 不被 VERIFY_D 破坏)
    csrw fflags, x0
    fclass.d x12, f12                     # 分类结果
    li   x10, 1
    li   x13, 0x200                       # qNaN (bit 9)
    bne  x12, x13, _t01_fail
    andi x17, x16, 16                     # NV 位
    bnez x17, _t01_fail                   # qNaN 输入不应置 NV
    j    _t01_end
_t01_fail:
    li   x10, 0
_t01_end:
    ret

# Test 2: sNaN + 1.0 = qNaN, NV 置位
#   sNaN 是信号 NaN, 运算静默化为 qNaN 并触发 NV。
test_02_snan_add_nv:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000001    # sNaN
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    fadd.d f12, f10, f11, rne             # sNaN + 1.0 = qNaN, NV
    csrr x16, fflags
    csrw fflags, x0
    fclass.d x12, f12
    li   x10, 1
    li   x13, 0x200                       # qNaN (sNaN 被静默化)
    bne  x12, x13, _t02_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t02_fail                   # sNaN 输入应置 NV
    j    _t02_end
_t02_fail:
    li   x10, 0
_t02_end:
    ret


# ============================================================
# 子测试 — Inf 算术
# ============================================================

# Test 3: +Inf + +Inf = +Inf, 无标志
test_03_inf_add_inf:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    LOAD_D f11, 0x7FF00000, 0x00000000    # +Inf
    fadd.d f12, f10, f11, rne             # Inf + Inf = Inf
    csrr x16, fflags
    csrw fflags, x0
    VERIFY_D f12, 0x7FF00000, 0x00000000  # expect +Inf
    bnez x16, _t03_fail                   # 无标志
    j    _t03_end
_t03_fail:
    li   x10, 0
_t03_end:
    ret

# Test 4: +Inf + (-Inf) = qNaN, NV 置位 (Inf - Inf)
test_04_inf_minus_inf:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    LOAD_D f11, 0xFFF00000, 0x00000000    # -Inf
    fadd.d f12, f10, f11, rne             # Inf + (-Inf) = qNaN
    csrr x16, fflags
    csrw fflags, x0
    fclass.d x12, f12
    li   x10, 1
    li   x13, 0x200                       # qNaN
    bne  x12, x13, _t04_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t04_fail
    j    _t04_end
_t04_fail:
    li   x10, 0
_t04_end:
    ret

# Test 5: +Inf * +0 = qNaN, NV 置位
test_05_inf_mul_zero:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    LOAD_D f11, 0x00000000, 0x00000000    # +0
    fmul.d f12, f10, f11, rne             # Inf * 0 = qNaN
    csrr x16, fflags
    csrw fflags, x0
    fclass.d x12, f12
    li   x10, 1
    li   x13, 0x200                       # qNaN
    bne  x12, x13, _t05_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t05_fail
    j    _t05_end
_t05_fail:
    li   x10, 0
_t05_end:
    ret

# Test 6: +Inf * 2.0 = +Inf, 无标志
test_06_inf_mul_finite:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fmul.d f12, f10, f11, rne             # Inf * 2.0 = Inf
    csrr x16, fflags
    csrw fflags, x0
    VERIFY_D f12, 0x7FF00000, 0x00000000  # expect +Inf
    bnez x16, _t06_fail                   # 无标志
    j    _t06_end
_t06_fail:
    li   x10, 0
_t06_end:
    ret


# ============================================================
# 子测试 — 有符号零算术
# ============================================================

# Test 7: +0 + (-0) = +0 (RNE: 异号零相加结果为 +0)
test_07_pos_zero_plus_neg_zero:
    LOAD_D f10, 0x00000000, 0x00000000    # +0
    LOAD_D f11, 0x80000000, 0x00000000    # -0
    fadd.d f12, f10, f11, rne             # +0 + (-0) = +0 (RNE)
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0
    ret

# Test 8: +0 - (-0) = +0 (减去 -0 等于加 +0)
test_08_pos_zero_minus_neg_zero:
    LOAD_D f10, 0x00000000, 0x00000000    # +0
    LOAD_D f11, 0x80000000, 0x00000000    # -0
    fsub.d f12, f10, f11, rne             # +0 - (-0) = +0
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0
    ret

# Test 9: -0 + (-0) = -0 (同号零相加保持符号)
test_09_neg_zero_plus_neg_zero:
    LOAD_D f10, 0x80000000, 0x00000000    # -0
    LOAD_D f11, 0x80000000, 0x00000000    # -0
    fadd.d f12, f10, f11, rne             # -0 + (-0) = -0
    VERIFY_D f12, 0x80000000, 0x00000000  # expect -0
    ret


# ============================================================
# 子测试 — D 次正规数运算
# ============================================================

# Test 10: 最小次正规数 + 0 = 最小次正规数 (精确, 无标志)
test_10_subnormal_add_zero:
    csrw fflags, x0
    LOAD_D f10, 0x00000000, 0x00000001    # 最小次正规数 (2^-1074)
    LOAD_D f11, 0x00000000, 0x00000000    # +0
    fadd.d f12, f10, f11, rne             # 次正规 + 0 = 次正规
    csrr x16, fflags
    csrw fflags, x0
    VERIFY_D f12, 0x00000000, 0x00000001  # expect 最小次正规数
    bnez x16, _t10_fail                   # 精确运算, 无标志
    j    _t10_end
_t10_fail:
    li   x10, 0
_t10_end:
    ret

# Test 11: 最小次正规数 + 最小次正规数 = 2×最小次正规数 (精确, 仍为次正规)
test_11_subnormal_add_subnormal:
    csrw fflags, x0
    LOAD_D f10, 0x00000000, 0x00000001    # 最小次正规数
    LOAD_D f11, 0x00000000, 0x00000001    # 最小次正规数
    fadd.d f12, f10, f11, rne             # = 2×最小次正规数
    csrr x16, fflags
    csrw fflags, x0
    VERIFY_D f12, 0x00000000, 0x00000002  # expect 2×最小次正规数
    bnez x16, _t11_fail                   # 精确运算, 无标志
    j    _t11_end
_t11_fail:
    li   x10, 0
_t11_end:
    ret


# ============================================================
# 子测试 — 舍入模式 (通过 FCVT.W.D 验证)
# ============================================================

# Test 12: RNE — FCVT.W.D 2.5 = 2 (向偶数舍入)
#   2.5 在 2 和 3 之间, 偶数是 2。
test_12_rne_tie_to_even:
    LOAD_D f10, 0x40040000, 0x00000000    # 2.5
    fcvt.w.d x12, f10, rne                # 2.5 → 2 (ties to even)
    li   x13, 2
    li   x10, 1
    bne  x12, x13, _t12_fail
    j    _t12_end
_t12_fail:
    li   x10, 0
_t12_end:
    ret

# Test 13: RTZ — FCVT.W.D 1.5 = 1 (向零截断)
test_13_rtz_truncate:
    LOAD_D f10, 0x3FF80000, 0x00000000    # 1.5
    fcvt.w.d x12, f10, rtz                # 1.5 → 1 (truncate)
    li   x13, 1
    li   x10, 1
    bne  x12, x13, _t13_fail
    j    _t13_end
_t13_fail:
    li   x10, 0
_t13_end:
    ret

# Test 14: RDN — FCVT.W.D -1.5 = -2 (向负无穷)
test_14_rdn_toward_neg:
    LOAD_D f10, 0xBFF80000, 0x00000000    # -1.5
    fcvt.w.d x12, f10, rdn                # -1.5 → -2 (toward -Inf)
    li   x13, -2
    li   x10, 1
    bne  x12, x13, _t14_fail
    j    _t14_end
_t14_fail:
    li   x10, 0
_t14_end:
    ret

# Test 15: RUP — FCVT.W.D 1.5 = 2 (向正无穷)
test_15_rup_toward_pos:
    LOAD_D f10, 0x3FF80000, 0x00000000    # 1.5
    fcvt.w.d x12, f10, rup                # 1.5 → 2 (toward +Inf)
    li   x13, 2
    li   x10, 1
    bne  x12, x13, _t15_fail
    j    _t15_end
_t15_fail:
    li   x10, 0
_t15_end:
    ret

# Test 16: RMM — FCVT.W.D 0.5 = 1 (向最大幅度舍入)
#   0.5 在 0 和 1 之间, RMM 向远离零的方向舍入 → 1。
test_16_rmm_tie_to_max:
    LOAD_D f10, 0x3FE00000, 0x00000000    # 0.5
    fcvt.w.d x12, f10, rmm                # 0.5 → 1 (ties to max magnitude)
    li   x13, 1
    li   x10, 1
    bne  x12, x13, _t16_fail
    j    _t16_end
_t16_fail:
    li   x10, 0
_t16_end:
    ret


# ============================================================
# 子测试 — fflags 累积
# ============================================================

# Test 17: fflags 累积 — DZ 然后 NV → fflags = 0x18
#   1.0/0.0 触发 DZ (bit 3 = 8), sqrt(-1) 触发 NV (bit 4 = 16)。
#   累积结果: 8 | 16 = 0x18。
test_17_fflags_accum:
    csrw fflags, x0
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x00000000, 0x00000000    # +0
    fdiv.d f12, f10, f11, rne             # 1.0/0.0 = +Inf, DZ
    LOAD_D f10, 0xBFF00000, 0x00000000    # -1.0
    fsqrt.d f12, f10, rne                 # sqrt(-1) = qNaN, NV
    csrr x12, fflags
    csrw fflags, x0
    li   x13, 0x18                        # DZ(8) | NV(16)
    li   x10, 1
    bne  x12, x13, _t17_fail
    j    _t17_end
_t17_fail:
    li   x10, 0
_t17_end:
    ret


# ============================================================
# 子测试 — fcsr 读写
# ============================================================

# Test 18: fcsr 读写 — 写入 frm=RDN, 读回验证 bits [7:5] = 010
#   fcsr 格式: flags[4:0] | frm[7:5]
#   写入 0x40 = 010_00000 (frm=RDN, flags=0)
test_18_fcsr_rw:
    csrw fflags, x0                       # 先清零标志
    li   x14, 0x40                        # frm=RDN(010) 在 bits [7:5]
    csrw fcsr, x14                        # 写入 fcsr
    csrr x12, fcsr                        # 读回 fcsr
    csrw fcsr, x0                         # 恢复 (frm=RNE, flags=0)
    andi x13, x12, 0xE0                   # 提取 frm 位 [7:5]
    li   x10, 1
    li   x14, 0x40                        # 期望 010_00000
    bne  x13, x14, _t18_fail
    j    _t18_end
_t18_fail:
    li   x10, 0
_t18_end:
    ret


# ============================================================
# 子测试 — NaN-box 违例
# ============================================================

# Test 19: NaN-box 违例 — FLW 加载 1.0f, FADD.D 读取 → qNaN
#   FLW 写入 {0xFFFFFFFF, 0x3F800000} (NaN-boxed)。
#   作为 double 读取: exp=0x7FF, frac[51]=1 → qNaN。
#   FADD.D(qNaN, 1.0) = qNaN, 无 NV (qNaN 输入)。
test_19_nanbox_violation:
    csrw fflags, x0
    lui  x14, 0x80006                     # scratch = 0x80006000
    lui  x15, 0x3F800                     # 1.0f = 0x3F800000
    sw   x15, 0(x14)                      # 存储 1.0f 位模式
    flw  f10, 0(x14)                      # f10 = {0xFFFFFFFF, 0x3F800000}
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0 double
    fadd.d f12, f10, f11, rne             # NaN-boxed + 1.0 = qNaN
    csrr x16, fflags
    csrw fflags, x0
    fclass.d x12, f12                     # 分类结果
    li   x10, 1
    li   x13, 0x200                       # qNaN
    bne  x12, x13, _t19_fail
    andi x17, x16, 16                     # NV 位
    bnez x17, _t19_fail                   # qNaN 输入不应置 NV
    j    _t19_end
_t19_fail:
    li   x10, 0
_t19_end:
    ret


# ============================================================
# 子测试 — FCVT.S.D NaN 处理
# ============================================================

# Test 20: FCVT.S.D — D qNaN → S qNaN, 无 NV
#   qNaN 转换为单精度仍为 qNaN, 不触发 NV。
test_20_fcvt_s_d_qnan:
    csrw fflags, x0
    LOAD_D f10, 0x7FF80000, 0x00000000    # D qNaN
    fcvt.s.d f12, f10, rne                # → S qNaN (NaN-boxed)
    csrr x16, fflags
    csrw fflags, x0
    fclass.s x12, f12                     # 分类 S 结果
    li   x10, 1
    li   x13, 0x200                       # qNaN (bit 9)
    bne  x12, x13, _t20_fail
    andi x17, x16, 16                     # NV 位
    bnez x17, _t20_fail                   # qNaN 输入不应置 NV
    j    _t20_end
_t20_fail:
    li   x10, 0
_t20_end:
    ret

# Test 21: FCVT.S.D — D sNaN → S qNaN, NV 置位
#   sNaN 被静默化为 qNaN, 触发 NV。
test_21_fcvt_s_d_snan:
    csrw fflags, x0
    LOAD_D f10, 0x7FF00000, 0x00000001    # D sNaN
    fcvt.s.d f12, f10, rne                # → S qNaN (quieted)
    csrr x16, fflags
    csrw fflags, x0
    fclass.s x12, f12                     # 分类 S 结果
    li   x10, 1
    li   x13, 0x200                       # qNaN (sNaN 被静默化)
    bne  x12, x13, _t21_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t21_fail                   # sNaN 输入应置 NV
    j    _t21_end
_t21_fail:
    li   x10, 0
_t21_end:
    ret


# ============================================================
# 子测试 — FCVT.D.S 次正规数→正规数
# ============================================================

# Test 22: FCVT.D.S — S 次正规数 (0x00000001 = 2^-149) → D 正规数
#   单精度最小次正规数 2^-149 在双精度中是正规数 (指数 -149 ≥ -1022)。
#   D 表示: 0x36A0000000000000。转换精确, 无标志。
test_22_fcvt_d_s_subnormal:
    csrw fflags, x0
    li   x14, 1                           # S 次正规数 0x00000001
    fmv.w.x f10, x14                      # f10 = {0xFFFFFFFF, 0x00000001}
    fcvt.d.s f12, f10                     # → D 2^-149 (正规数)
    csrr x16, fflags
    csrw fflags, x0
    VERIFY_D f12, 0x36A00000, 0x00000000  # expect 2^-149
    bnez x16, _t22_fail                   # 精确转换, 无标志
    j    _t22_end
_t22_fail:
    li   x10, 0
_t22_end:
    ret


# ============================================================
# 子测试 — FCVT.W.D 饱和
# ============================================================

# Test 23: FCVT.W.D — 2^31 → 0x7FFFFFFF (饱和到 MAX_INT), NV 置位
#   2^31 = 2147483648.0 超出 int32 范围, 饱和到 0x7FFFFFFF。
test_23_fcvt_w_d_large_pos:
    csrw fflags, x0
    LOAD_D f10, 0x41E00000, 0x00000000    # 2^31
    fcvt.w.d x12, f10, rne                # → 0x7FFFFFFF (饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    li   x13, 0x7FFFFFFF
    bne  x12, x13, _t23_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t23_fail
    j    _t23_end
_t23_fail:
    li   x10, 0
_t23_end:
    ret

# Test 24: FCVT.W.D — -2^32 → 0x80000000 (饱和到 MIN_INT), NV 置位
#   -2^32 = -4294967296.0 超出 int32 范围, 饱和到 0x80000000。
test_24_fcvt_w_d_large_neg:
    csrw fflags, x0
    LOAD_D f10, 0xC1F00000, 0x00000000    # -2^32
    fcvt.w.d x12, f10, rne                # → 0x80000000 (饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    li   x13, 0x80000000
    bne  x12, x13, _t24_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t24_fail
    j    _t24_end
_t24_fail:
    li   x10, 0
_t24_end:
    ret

# Test 25: FCVT.W.D — NaN → 0x7FFFFFFF (饱和到 MAX_INT), NV 置位
test_25_fcvt_w_d_nan:
    csrw fflags, x0
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    fcvt.w.d x12, f10, rne                # → 0x7FFFFFFF (饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    li   x13, 0x7FFFFFFF
    bne  x12, x13, _t25_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t25_fail
    j    _t25_end
_t25_fail:
    li   x10, 0
_t25_end:
    ret


# ============================================================
# 子测试 — FCVT.WU.D 饱和
# ============================================================

# Test 26: FCVT.WU.D — -1.0 → 0 (负数饱和到 0), NV 置位
test_26_fcvt_wu_d_neg:
    csrw fflags, x0
    LOAD_D f10, 0xBFF00000, 0x00000000    # -1.0
    fcvt.wu.d x12, f10, rne               # → 0 (负数饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    beqz x12, _t26_check_nv
    li   x10, 0
    j    _t26_end
_t26_check_nv:
    andi x17, x16, 16                     # NV 位
    beqz x17, _t26_fail
    j    _t26_end
_t26_fail:
    li   x10, 0
_t26_end:
    ret

# Test 27: FCVT.WU.D — 2^32 → 0xFFFFFFFF (饱和到 MAX_UINT), NV 置位
#   2^32 = 4294967296.0 超出 uint32 范围, 饱和到 0xFFFFFFFF。
test_27_fcvt_wu_d_large_pos:
    csrw fflags, x0
    LOAD_D f10, 0x41F00000, 0x00000000    # 2^32
    fcvt.wu.d x12, f10, rne               # → 0xFFFFFFFF (饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    li   x13, 0xFFFFFFFF
    bne  x12, x13, _t27_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t27_fail
    j    _t27_end
_t27_fail:
    li   x10, 0
_t27_end:
    ret

# Test 28: FCVT.WU.D — NaN → 0xFFFFFFFF (饱和到 MAX_UINT), NV 置位
test_28_fcvt_wu_d_nan:
    csrw fflags, x0
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    fcvt.wu.d x12, f10, rne               # → 0xFFFFFFFF (饱和)
    csrr x16, fflags
    csrw fflags, x0
    li   x10, 1
    li   x13, 0xFFFFFFFF
    bne  x12, x13, _t28_fail
    andi x17, x16, 16                     # NV 位
    beqz x17, _t28_fail
    j    _t28_end
_t28_fail:
    li   x10, 0
_t28_end:
    ret
