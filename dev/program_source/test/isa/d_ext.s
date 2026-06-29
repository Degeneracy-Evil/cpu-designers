# ============================================================
# isa/d_ext.s — D-extension (double-precision float) tests
# 类别:   ISA-D
# 描述:   测试 D 扩展指令 (FADD.D/FSUB.D/FMUL.D/FDIV.D/FSQRT.D/
#         FLD/FSD/FCVT.W.D/FCVT.WU.D/FCVT.D.W/FCVT.D.WU/
#         FCVT.S.D/FCVT.D.S/FSGNJ.D/FSGNJN.D/FSGNJX.D/
#         FEQ.D/FLT.D/FLE.D/FCLASS.D/FMIN.D/FMAX.D)
# 子测试: 51
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
#
# Double constants (IEEE 754 double-precision bit patterns):
#   1.0   = 0x3FF0000000000000  (hi=0x3FF00000, lo=0x00000000)
#   2.0   = 0x4000000000000000  (hi=0x40000000, lo=0x00000000)
#   3.0   = 0x4008000000000000  (hi=0x40080000, lo=0x00000000)
#   4.0   = 0x4010000000000000  (hi=0x40100000, lo=0x00000000)
#   6.0   = 0x4018000000000000  (hi=0x40180000, lo=0x00000000)
#  42.0   = 0x4045000000000000  (hi=0x40450000, lo=0x00000000)
#  -1.0   = 0xBFF0000000000000  (hi=0xBFF00000, lo=0x00000000)
#  -2.0   = 0xC000000000000000  (hi=0xC0000000, lo=0x00000000)
#  +0.0   = 0x0000000000000000  (hi=0x00000000, lo=0x00000000)
#  -0.0   = 0x8000000000000000  (hi=0x80000000, lo=0x00000000)
#  +Inf   = 0x7FF0000000000000  (hi=0x7FF00000, lo=0x00000000)
#  -Inf   = 0xFFF0000000000000  (hi=0xFFF00000, lo=0x00000000)
#  qNaN   = 0x7FF8000000000000  (hi=0x7FF80000, lo=0x00000000)
#  sNaN   = 0x7FF0000000000001  (hi=0x7FF00000, lo=0x00000001)
#  MaxN   = 0x7FEFFFFFFFFFFFFF  (hi=0x7FEFFFFF, lo=0xFFFFFFFF)
#  MinN   = 0x0010000000000000  (hi=0x00100000, lo=0x00000000)
#  1/3.D  = 0x3FD5555555555555  (hi=0x3FD55555, lo=0x55555555)
#  2^-149 = 0x36A0000000000000  (hi=0x36A00000, lo=0x00000000)
#
# RV32 D extension notes:
#   - FLD/FSD use two 32-bit transactions (lo word + hi word).
#   - No FMV.D.X/FMV.X.D in RV32 (XLEN>=64 only).
#   - Double constants loaded via SW (two words) + FLD.
#   - Scratch area: 0x80006000 (below result area at 0x80007000).
#   - D results verified via FSD + LW (both words).
#   - Integer results (FCVT.W.D, FEQ.D, FCLASS.D, etc.) write to
#     integer registers directly (rd_is_int=1).
#   - FCVT.S.D result is NaN-boxed F value; use FMV.X.W to read
#     lower 32 bits for verification.
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
    la   x11, test_01_fadd_d_pp
    jal  x1, test_run
    la   x11, test_02_fadd_d_pn
    jal  x1, test_run
    la   x11, test_03_fadd_d_overflow
    jal  x1, test_run
    la   x11, test_04_fadd_d_nan
    jal  x1, test_run
    la   x11, test_05_fsub_d_pp
    jal  x1, test_run
    la   x11, test_06_fsub_d_pn
    jal  x1, test_run
    la   x11, test_07_fsub_d_zero
    jal  x1, test_run
    la   x11, test_08_fmul_d_pp
    jal  x1, test_run
    la   x11, test_09_fmul_d_zero_inf
    jal  x1, test_run
    la   x11, test_10_fmul_d_overflow
    jal  x1, test_run
    la   x11, test_11_fdiv_d_pp
    jal  x1, test_run
    la   x11, test_12_fdiv_d_dz
    jal  x1, test_run
    la   x11, test_13_fdiv_d_inf_inf
    jal  x1, test_run
    la   x11, test_14_fsqrt_d_4
    jal  x1, test_run
    la   x11, test_15_fsqrt_d_neg
    jal  x1, test_run
    la   x11, test_16_fsqrt_d_zero
    jal  x1, test_run
    la   x11, test_17_fld_fsd_consistency
    jal  x1, test_run
    la   x11, test_18_fld_fsd_integrity
    jal  x1, test_run
    la   x11, test_19_fcvt_w_d_normal
    jal  x1, test_run
    la   x11, test_20_fcvt_w_d_nan
    jal  x1, test_run
    la   x11, test_21_fcvt_w_d_inf
    jal  x1, test_run
    la   x11, test_22_fcvt_w_d_neg
    jal  x1, test_run
    la   x11, test_23_fcvt_wu_d_normal
    jal  x1, test_run
    la   x11, test_24_fcvt_wu_d_neg
    jal  x1, test_run
    la   x11, test_25_fcvt_wu_d_nan
    jal  x1, test_run
    la   x11, test_26_fcvt_d_w_42
    jal  x1, test_run
    la   x11, test_27_fcvt_d_w_zero
    jal  x1, test_run
    la   x11, test_28_fcvt_d_w_neg1
    jal  x1, test_run
    la   x11, test_29_fcvt_d_wu_42
    jal  x1, test_run
    la   x11, test_30_fcvt_d_wu_zero
    jal  x1, test_run
    la   x11, test_31_fcvt_s_d_exact
    jal  x1, test_run
    la   x11, test_32_fcvt_s_d_precision
    jal  x1, test_run
    la   x11, test_33_fcvt_d_s_exact
    jal  x1, test_run
    la   x11, test_34_fcvt_d_s_subnormal
    jal  x1, test_run
    la   x11, test_35_fsgnj_d
    jal  x1, test_run
    la   x11, test_36_fsgnjn_d
    jal  x1, test_run
    la   x11, test_37_fsgnjx_d
    jal  x1, test_run
    la   x11, test_38_feq_d_eq
    jal  x1, test_run
    la   x11, test_39_feq_d_nan
    jal  x1, test_run
    la   x11, test_40_flt_d_lt
    jal  x1, test_run
    la   x11, test_41_flt_d_nan
    jal  x1, test_run
    la   x11, test_42_fle_d_eq
    jal  x1, test_run
    la   x11, test_43_fle_d_nan
    jal  x1, test_run
    la   x11, test_44_fclass_d_normal
    jal  x1, test_run
    la   x11, test_45_fclass_d_inf
    jal  x1, test_run
    la   x11, test_46_fclass_d_qnan
    jal  x1, test_run
    la   x11, test_47_fmin_d
    jal  x1, test_run
    la   x11, test_48_fmin_d_neg0_pos0
    jal  x1, test_run
    la   x11, test_49_fmax_d
    jal  x1, test_run
    la   x11, test_50_fmax_d_neg0_pos0
    jal  x1, test_run
    la   x11, test_51_nanbox_flw_d
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 辅助宏
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
# 子测试
# ============================================================

# Test 1: FADD.D — 1.0 + 2.0 = 3.0
test_01_fadd_d_pp:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fadd.d f12, f10, f11, rne             # 1.0 + 2.0 = 3.0
    VERIFY_D f12, 0x40080000, 0x00000000  # expect 3.0
    ret

# Test 2: FADD.D — 1.0 + (-1.0) = +0.0 (signed zero cancellation)
test_02_fadd_d_pn:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0xBFF00000, 0x00000000    # -1.0
    fadd.d f12, f10, f11, rne             # 1.0 + (-1.0) = +0.0
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0.0
    ret

# Test 3: FADD.D — MaxNormal + MaxNormal = +Inf (overflow)
test_03_fadd_d_overflow:
    LOAD_D f10, 0x7FEFFFFF, 0xFFFFFFFF    # max normal
    LOAD_D f11, 0x7FEFFFFF, 0xFFFFFFFF    # max normal
    fadd.d f12, f10, f11, rne             # overflow → +Inf
    VERIFY_D f12, 0x7FF00000, 0x00000000  # expect +Inf
    ret

# Test 4: FADD.D — qNaN + 1.0 = qNaN (NaN propagation)
test_04_fadd_d_nan:
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    fadd.d f12, f10, f11, rne             # qNaN + 1.0 = qNaN
    VERIFY_D f12, 0x7FF80000, 0x00000000  # expect canonical qNaN
    ret

# Test 5: FSUB.D — 3.0 - 1.0 = 2.0
test_05_fsub_d_pp:
    LOAD_D f10, 0x40080000, 0x00000000    # 3.0
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    fsub.d f12, f10, f11, rne             # 3.0 - 1.0 = 2.0
    VERIFY_D f12, 0x40000000, 0x00000000  # expect 2.0
    ret

# Test 6: FSUB.D — 1.0 - (-2.0) = 3.0
test_06_fsub_d_pn:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0xC0000000, 0x00000000    # -2.0
    fsub.d f12, f10, f11, rne             # 1.0 - (-2.0) = 3.0
    VERIFY_D f12, 0x40080000, 0x00000000  # expect 3.0
    ret

# Test 7: FSUB.D — 1.0 - 1.0 = +0.0 (underflow to zero)
test_07_fsub_d_zero:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    fsub.d f12, f10, f11, rne             # 1.0 - 1.0 = +0.0
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0.0
    ret

# Test 8: FMUL.D — 2.0 * 3.0 = 6.0
test_08_fmul_d_pp:
    LOAD_D f10, 0x40000000, 0x00000000    # 2.0
    LOAD_D f11, 0x40080000, 0x00000000    # 3.0
    fmul.d f12, f10, f11, rne             # 2.0 * 3.0 = 6.0
    VERIFY_D f12, 0x40180000, 0x00000000  # expect 6.0
    ret

# Test 9: FMUL.D — 0.0 * +Inf = qNaN (invalid operation)
test_09_fmul_d_zero_inf:
    LOAD_D f10, 0x00000000, 0x00000000    # +0.0
    LOAD_D f11, 0x7FF00000, 0x00000000    # +Inf
    fmul.d f12, f10, f11, rne             # 0.0 * Inf = qNaN
    VERIFY_D f12, 0x7FF80000, 0x00000000  # expect canonical qNaN
    ret

# Test 10: FMUL.D — MaxNormal * MaxNormal = +Inf (overflow)
test_10_fmul_d_overflow:
    LOAD_D f10, 0x7FEFFFFF, 0xFFFFFFFF    # max normal
    LOAD_D f11, 0x7FEFFFFF, 0xFFFFFFFF    # max normal
    fmul.d f12, f10, f11, rne             # overflow → +Inf
    VERIFY_D f12, 0x7FF00000, 0x00000000  # expect +Inf
    ret

# Test 11: FDIV.D — 6.0 / 2.0 = 3.0
test_11_fdiv_d_pp:
    LOAD_D f10, 0x40180000, 0x00000000    # 6.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fdiv.d f12, f10, f11, rne             # 6.0 / 2.0 = 3.0
    VERIFY_D f12, 0x40080000, 0x00000000  # expect 3.0
    ret

# Test 12: FDIV.D — 1.0 / 0.0 = +Inf (divide by zero)
test_12_fdiv_d_dz:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x00000000, 0x00000000    # +0.0
    fdiv.d f12, f10, f11, rne             # 1.0 / 0.0 = +Inf
    VERIFY_D f12, 0x7FF00000, 0x00000000  # expect +Inf
    ret

# Test 13: FDIV.D — +Inf / +Inf = qNaN (invalid operation)
test_13_fdiv_d_inf_inf:
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    LOAD_D f11, 0x7FF00000, 0x00000000    # +Inf
    fdiv.d f12, f10, f11, rne             # Inf / Inf = qNaN
    VERIFY_D f12, 0x7FF80000, 0x00000000  # expect canonical qNaN
    ret

# Test 14: FSQRT.D — sqrt(4.0) = 2.0
test_14_fsqrt_d_4:
    LOAD_D f10, 0x40100000, 0x00000000    # 4.0
    fsqrt.d f12, f10, rne                 # sqrt(4.0) = 2.0
    VERIFY_D f12, 0x40000000, 0x00000000  # expect 2.0
    ret

# Test 15: FSQRT.D — sqrt(-1.0) = qNaN (invalid operation)
test_15_fsqrt_d_neg:
    LOAD_D f10, 0xBFF00000, 0x00000000    # -1.0
    fsqrt.d f12, f10, rne                 # sqrt(-1.0) = qNaN
    VERIFY_D f12, 0x7FF80000, 0x00000000  # expect canonical qNaN
    ret

# Test 16: FSQRT.D — sqrt(0.0) = 0.0
test_16_fsqrt_d_zero:
    LOAD_D f10, 0x00000000, 0x00000000    # +0.0
    fsqrt.d f12, f10, rne                 # sqrt(0.0) = 0.0
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0.0
    ret

# Test 17: FLD/FSD — store 3.0 via SW, FLD, FSD to another addr, verify
test_17_fld_fsd_consistency:
    lui  x14, 0x80006                     # x14 = 0x80006000
    sw   x0, 0(x14)                       # low word = 0
    lui  x15, 0x40080                     # x15 = 0x40080000
    sw   x15, 4(x14)                      # high word = 0x40080000
    fld  f10, 0(x14)                      # f10 = 3.0
    addi x14, x14, 8                      # x14 = 0x80006008
    fsd  f10, 0(x14)                      # store to 0x80006008
    lw   x12, 0(x14)                      # low word
    lw   x13, 4(x14)                      # high word
    li   x10, 1
    bnez x12, _t17_fail                   # low must be 0
    lui  x15, 0x40080
    bne  x13, x15, _t17_fail              # high must be 0x40080000
    j    _t17_end
_t17_fail:
    li   x10, 0
_t17_end:
    ret

# Test 18: FLD/FSD — 64-bit data integrity (non-zero low word: 1/3 double)
test_18_fld_fsd_integrity:
    lui  x14, 0x80006                     # x14 = 0x80006000
    li   x15, 0x55555555
    sw   x15, 0(x14)                      # low word = 0x55555555
    li   x15, 0x3FD55555
    sw   x15, 4(x14)                      # high word = 0x3FD55555
    fld  f10, 0(x14)                      # f10 = 1/3 double
    addi x14, x14, 8                      # x14 = 0x80006008
    fsd  f10, 0(x14)                      # store to 0x80006008
    lw   x12, 0(x14)                      # low word
    lw   x13, 4(x14)                      # high word
    li   x10, 1
    li   x15, 0x55555555
    bne  x12, x15, _t18_fail
    li   x15, 0x3FD55555
    bne  x13, x15, _t18_fail
    j    _t18_end
_t18_fail:
    li   x10, 0
_t18_end:
    ret

# Test 19: FCVT.W.D — 42.0 → 42 (signed int)
test_19_fcvt_w_d_normal:
    LOAD_D f10, 0x40450000, 0x00000000    # 42.0
    fcvt.w.d x12, f10, rne                # x12 = 42
    li   x13, 42
    li   x10, 1
    bne  x12, x13, _t19_fail
    j    _t19_end
_t19_fail:
    li   x10, 0
_t19_end:
    ret

# Test 20: FCVT.W.D — NaN → 0x7FFFFFFF (saturate to max positive)
test_20_fcvt_w_d_nan:
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    fcvt.w.d x12, f10, rne                # x12 = 0x7FFFFFFF (saturate)
    li   x13, 0x7FFFFFFF
    li   x10, 1
    bne  x12, x13, _t20_fail
    j    _t20_end
_t20_fail:
    li   x10, 0
_t20_end:
    ret

# Test 21: FCVT.W.D — +Inf → 0x7FFFFFFF (saturate to max positive)
test_21_fcvt_w_d_inf:
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    fcvt.w.d x12, f10, rne                # x12 = 0x7FFFFFFF (saturate)
    li   x13, 0x7FFFFFFF
    li   x10, 1
    bne  x12, x13, _t21_fail
    j    _t21_end
_t21_fail:
    li   x10, 0
_t21_end:
    ret

# Test 22: FCVT.W.D — -1.0 → -1 (0xFFFFFFFF, signed)
test_22_fcvt_w_d_neg:
    LOAD_D f10, 0xBFF00000, 0x00000000    # -1.0
    fcvt.w.d x12, f10, rne                # x12 = -1 = 0xFFFFFFFF
    li   x13, 0xFFFFFFFF
    li   x10, 1
    bne  x12, x13, _t22_fail
    j    _t22_end
_t22_fail:
    li   x10, 0
_t22_end:
    ret

# Test 23: FCVT.WU.D — 42.0 → 42 (unsigned int)
test_23_fcvt_wu_d_normal:
    LOAD_D f10, 0x40450000, 0x00000000    # 42.0
    fcvt.wu.d x12, f10, rne               # x12 = 42
    li   x13, 42
    li   x10, 1
    bne  x12, x13, _t23_fail
    j    _t23_end
_t23_fail:
    li   x10, 0
_t23_end:
    ret

# Test 24: FCVT.WU.D — -1.0 → 0 (saturate, negative to unsigned)
test_24_fcvt_wu_d_neg:
    LOAD_D f10, 0xBFF00000, 0x00000000    # -1.0
    fcvt.wu.d x12, f10, rne               # x12 = 0 (saturate)
    li   x13, 0
    li   x10, 1
    bne  x12, x13, _t24_fail
    j    _t24_end
_t24_fail:
    li   x10, 0
_t24_end:
    ret

# Test 25: FCVT.WU.D — NaN → 0xFFFFFFFF (saturate to max unsigned)
test_25_fcvt_wu_d_nan:
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    fcvt.wu.d x12, f10, rne               # x12 = 0xFFFFFFFF (saturate)
    li   x13, 0xFFFFFFFF
    li   x10, 1
    bne  x12, x13, _t25_fail
    j    _t25_end
_t25_fail:
    li   x10, 0
_t25_end:
    ret

# Test 26: FCVT.D.W — 42 → 42.0
test_26_fcvt_d_w_42:
    li   x14, 42
    fcvt.d.w f10, x14                     # f10 = 42.0 (int→double always exact, no rm)
    VERIFY_D f10, 0x40450000, 0x00000000  # expect 42.0
    ret

# Test 27: FCVT.D.W — 0 → 0.0
test_27_fcvt_d_w_zero:
    li   x14, 0
    fcvt.d.w f10, x14                     # f10 = 0.0
    VERIFY_D f10, 0x00000000, 0x00000000  # expect 0.0
    ret

# Test 28: FCVT.D.W — -1 → -1.0
test_28_fcvt_d_w_neg1:
    li   x14, -1
    fcvt.d.w f10, x14                     # f10 = -1.0
    VERIFY_D f10, 0xBFF00000, 0x00000000  # expect -1.0
    ret

# Test 29: FCVT.D.WU — 42 → 42.0
test_29_fcvt_d_wu_42:
    li   x14, 42
    fcvt.d.wu f10, x14                    # f10 = 42.0
    VERIFY_D f10, 0x40450000, 0x00000000  # expect 42.0
    ret

# Test 30: FCVT.D.WU — 0 → 0.0
test_30_fcvt_d_wu_zero:
    li   x14, 0
    fcvt.d.wu f10, x14                    # f10 = 0.0
    VERIFY_D f10, 0x00000000, 0x00000000  # expect 0.0
    ret

# Test 31: FCVT.S.D — 1.0 double → 1.0f (0x3F800000, exact)
#   Result is NaN-boxed F value; use FMV.X.W to read lower 32 bits.
test_31_fcvt_s_d_exact:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0 double
    fcvt.s.d f12, f10, rne                # f12 = 1.0f (NaN-boxed)
    fmv.x.w x12, f12                      # x12 = lower 32 bits = 0x3F800000
    lui  x13, 0x3F800                     # x13 = 0x3F800000
    li   x10, 1
    bne  x12, x13, _t31_fail
    j    _t31_end
_t31_fail:
    li   x10, 0
_t31_end:
    ret

# Test 32: FCVT.S.D — 1/3 double → 1/3 float (0x3EAAAAAB, precision loss)
#   1/3 double = 0x3FD5555555555555, 1/3 float = 0x3EAAAAAB (RNE)
test_32_fcvt_s_d_precision:
    LOAD_D f10, 0x3FD55555, 0x55555555    # 1/3 double
    fcvt.s.d f12, f10, rne                # f12 = 1/3 float (NaN-boxed)
    fmv.x.w x12, f12                      # x12 = 0x3EAAAAAB
    li   x13, 0x3EAAAAAB
    li   x10, 1
    bne  x12, x13, _t32_fail
    j    _t32_end
_t32_fail:
    li   x10, 0
_t32_end:
    ret

# Test 33: FCVT.D.S — 1.0f → 1.0 double (exact conversion)
#   Load 1.0f via FMV.W.X (NaN-boxed), then FCVT.D.S.
test_33_fcvt_d_s_exact:
    lui  x14, 0x3F800                     # 0x3F800000 = 1.0f
    fmv.w.x f10, x14                      # f10 = {0xFFFFFFFF, 0x3F800000}
    fcvt.d.s f12, f10                     # f12 = 1.0 double (single→double always exact)
    VERIFY_D f12, 0x3FF00000, 0x00000000  # expect 1.0 double
    ret

# Test 34: FCVT.D.S — subnormal float (0x00000001) → 2^-149 double
#   Smallest subnormal float = 2^-149, in double = 0x36A0000000000000.
test_34_fcvt_d_s_subnormal:
    li   x14, 1
    fmv.w.x f10, x14                      # f10 = {0xFFFFFFFF, 0x00000001}
    fcvt.d.s f12, f10                     # f12 = 2^-149 double
    VERIFY_D f12, 0x36A00000, 0x00000000  # expect 2^-149
    ret

# Test 35: FSGNJ.D — sgnj(1.0, -2.0) = -1.0
#   FSGNJ: result = |fs1| with sign of fs2
test_35_fsgnj_d:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0 (positive)
    LOAD_D f11, 0xC0000000, 0x00000000    # -2.0 (negative)
    fsgnj.d f12, f10, f11                 # take sign from -2.0 → -1.0
    VERIFY_D f12, 0xBFF00000, 0x00000000  # expect -1.0
    ret

# Test 36: FSGNJN.D — sgnjn(1.0, -2.0) = 1.0
#   FSGNJN: result = |fs1| with INVERTED sign of fs2
test_36_fsgnjn_d:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0 (positive)
    LOAD_D f11, 0xC0000000, 0x00000000    # -2.0 (negative)
    fsgnjn.d f12, f10, f11                # invert sign of -2.0 → positive → 1.0
    VERIFY_D f12, 0x3FF00000, 0x00000000  # expect 1.0
    ret

# Test 37: FSGNJX.D — sgnjx(1.0, -2.0) = -1.0
#   FSGNJX: result = |fs1| with XOR of signs
test_37_fsgnjx_d:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0 (positive)
    LOAD_D f11, 0xC0000000, 0x00000000    # -2.0 (negative)
    fsgnjx.d f12, f10, f11                # XOR signs: pos XOR neg = neg → -1.0
    VERIFY_D f12, 0xBFF00000, 0x00000000  # expect -1.0
    ret

# Test 38: FEQ.D — eq(1.0, 1.0) = 1
test_38_feq_d_eq:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x3FF00000, 0x00000000    # 1.0
    feq.d x12, f10, f11                   # x12 = 1 (equal)
    li   x13, 1
    li   x10, 1
    bne  x12, x13, _t38_fail
    j    _t38_end
_t38_fail:
    li   x10, 0
_t38_end:
    ret

# Test 39: FEQ.D — eq(1.0, qNaN) = 0 (NaN never equal)
test_39_feq_d_nan:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x7FF80000, 0x00000000    # qNaN
    feq.d x12, f10, f11                   # x12 = 0 (NaN → false)
    li   x13, 0
    li   x10, 1
    bne  x12, x13, _t39_fail
    j    _t39_end
_t39_fail:
    li   x10, 0
_t39_end:
    ret

# Test 40: FLT.D — lt(1.0, 2.0) = 1
test_40_flt_d_lt:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    flt.d x12, f10, f11                   # x12 = 1 (1.0 < 2.0)
    li   x13, 1
    li   x10, 1
    bne  x12, x13, _t40_fail
    j    _t40_end
_t40_fail:
    li   x10, 0
_t40_end:
    ret

# Test 41: FLT.D — lt(1.0, qNaN) = 0 (NaN → false)
test_41_flt_d_nan:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x7FF80000, 0x00000000    # qNaN
    flt.d x12, f10, f11                   # x12 = 0 (NaN → false)
    li   x13, 0
    li   x10, 1
    bne  x12, x13, _t41_fail
    j    _t41_end
_t41_fail:
    li   x10, 0
_t41_end:
    ret

# Test 42: FLE.D — le(2.0, 2.0) = 1
test_42_fle_d_eq:
    LOAD_D f10, 0x40000000, 0x00000000    # 2.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fle.d x12, f10, f11                   # x12 = 1 (2.0 <= 2.0)
    li   x13, 1
    li   x10, 1
    bne  x12, x13, _t42_fail
    j    _t42_end
_t42_fail:
    li   x10, 0
_t42_end:
    ret

# Test 43: FLE.D — le(1.0, qNaN) = 0 (NaN → false)
test_43_fle_d_nan:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x7FF80000, 0x00000000    # qNaN
    fle.d x12, f10, f11                   # x12 = 0 (NaN → false)
    li   x13, 0
    li   x10, 1
    bne  x12, x13, _t43_fail
    j    _t43_end
_t43_fail:
    li   x10, 0
_t43_end:
    ret

# Test 44: FCLASS.D — class(1.0) = bit 6 (positive normal, 0x040)
#   FCLASS.D 10-bit mask: bit0=-Inf, bit1=-normal, bit2=-subnormal,
#   bit3=-0, bit4=+0, bit5=+subnormal, bit6=+normal, bit7=+Inf,
#   bit8=sNaN, bit9=qNaN
test_44_fclass_d_normal:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    fclass.d x12, f10                     # x12 = 0x040 (bit 6)
    li   x13, 0x040
    li   x10, 1
    bne  x12, x13, _t44_fail
    j    _t44_end
_t44_fail:
    li   x10, 0
_t44_end:
    ret

# Test 45: FCLASS.D — class(+Inf) = bit 7 (0x080)
test_45_fclass_d_inf:
    LOAD_D f10, 0x7FF00000, 0x00000000    # +Inf
    fclass.d x12, f10                     # x12 = 0x080 (bit 7)
    li   x13, 0x080
    li   x10, 1
    bne  x12, x13, _t45_fail
    j    _t45_end
_t45_fail:
    li   x10, 0
_t45_end:
    ret

# Test 46: FCLASS.D — class(qNaN) = bit 9 (0x200)
test_46_fclass_d_qnan:
    LOAD_D f10, 0x7FF80000, 0x00000000    # qNaN
    fclass.d x12, f10                     # x12 = 0x200 (bit 9)
    li   x13, 0x200
    li   x10, 1
    bne  x12, x13, _t46_fail
    j    _t46_end
_t46_fail:
    li   x10, 0
_t46_end:
    ret

# Test 47: FMIN.D — min(1.0, 2.0) = 1.0
test_47_fmin_d:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fmin.d f12, f10, f11                  # min(1.0, 2.0) = 1.0
    VERIFY_D f12, 0x3FF00000, 0x00000000  # expect 1.0
    ret

# Test 48: FMIN.D — min(-0, +0) = -0 (strict total ordering)
test_48_fmin_d_neg0_pos0:
    LOAD_D f10, 0x80000000, 0x00000000    # -0.0
    LOAD_D f11, 0x00000000, 0x00000000    # +0.0
    fmin.d f12, f10, f11                  # min(-0, +0) = -0
    VERIFY_D f12, 0x80000000, 0x00000000  # expect -0.0
    ret

# Test 49: FMAX.D — max(1.0, 2.0) = 2.0
test_49_fmax_d:
    LOAD_D f10, 0x3FF00000, 0x00000000    # 1.0
    LOAD_D f11, 0x40000000, 0x00000000    # 2.0
    fmax.d f12, f10, f11                  # max(1.0, 2.0) = 2.0
    VERIFY_D f12, 0x40000000, 0x00000000  # expect 2.0
    ret

# Test 50: FMAX.D — max(-0, +0) = +0 (strict total ordering)
test_50_fmax_d_neg0_pos0:
    LOAD_D f10, 0x80000000, 0x00000000    # -0.0
    LOAD_D f11, 0x00000000, 0x00000000    # +0.0
    fmax.d f12, f10, f11                  # max(-0, +0) = +0
    VERIFY_D f12, 0x00000000, 0x00000000  # expect +0.0
    ret

# Test 51: NaN-box test — FLW 1.0f then FCLASS.D → qNaN (bit 9 = 0x200)
#   FLW writes {0xFFFFFFFF, 0x3F800000} to 64-bit regfile (NaN-boxed).
#   Reading as double: exp=0x7FF, frac[51]=1 → qNaN.
#   FCLASS.D should return 0x200 (bit 9, qNaN).
test_51_nanbox_flw_d:
    lui  x14, 0x80006                     # x14 = 0x80006000 (scratch)
    lui  x15, 0x3F800                     # x15 = 0x3F800000 (1.0f)
    sw   x15, 0(x14)                      # store 1.0f bit pattern
    flw  f10, 0(x14)                      # f10 = {0xFFFFFFFF, 0x3F800000}
    fclass.d x12, f10                     # classify as double → qNaN
    li   x13, 0x200                       # bit 9 = qNaN
    li   x10, 1
    bne  x12, x13, _t51_fail
    j    _t51_end
_t51_fail:
    li   x10, 0
_t51_end:
    ret
