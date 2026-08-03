# ============================================================
# isa/f_ext_special.s — F-extension exception/rounding edge cases
# 类别:   ISA
# 描述:   浮点异常标志 (fflags) 和舍入模式 (frm) 边界测试
# 子测试: 24
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
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
# NOTE: 子测试内不得使用 JAL/JALR 调用辅助函数 (会覆盖 ra,
#       导致 ret 跳转错误)。CSR 访问必须内联。
#
# ============================================================

.section .text.start
.globl _start

_start:
    la   x10, m_trap_simple
    csrw mtvec, x10
    li   x10, 0x88
    csrw mstatus, x10

    jal  ra, test_init

    la   x11, test_1_nx_add
    jal  ra, test_run
    la   x11, test_2_nx_sub
    jal  ra, test_run
    la   x11, test_3_nx_mul
    jal  ra, test_run
    la   x11, test_4_dz_div
    jal  ra, test_run
    la   x11, test_5_of_add
    jal  ra, test_run
    la   x11, test_6_uf_mul
    jal  ra, test_run
    la   x11, test_7_nv_sqrt_neg
    jal  ra, test_run
    la   x11, test_8_nv_0_div_0
    jal  ra, test_run
    la   x11, test_9_nv_inf_minus_inf
    jal  ra, test_run
    la   x11, test_10_rtz_pos
    jal  ra, test_run
    la   x11, test_11_rtz_neg
    jal  ra, test_run
    la   x11, test_12_rdn_pos
    jal  ra, test_run
    la   x11, test_13_rdn_neg
    jal  ra, test_run
    la   x11, test_14_rup_pos
    jal  ra, test_run
    la   x11, test_15_rup_neg
    jal  ra, test_run
    la   x11, test_16_rmm_tie
    jal  ra, test_run
    la   x11, test_17_dyn_round
    jal  ra, test_run
    la   x11, test_18_fflags_accum
    jal  ra, test_run
    la   x11, test_19_fcvt_w_s_overflow
    jal  ra, test_run
    la   x11, test_20_fcvt_s_wu_max
    jal  ra, test_run
    la   x11, test_21_fadd_signed_zero
    jal  ra, test_run
    la   x11, test_22_fmul_zero_inf
    jal  ra, test_run
    la   x11, test_23_fsqrt_zero
    jal  ra, test_run
    la   x11, test_24_fcvt_w_s_nan
    jal  ra, test_run

    jal  ra, test_report

1:  wfi
    j    1b

# ============================================================
# Test 1: NX — FADD 1.0 + 2^-24 (inexact, bit beyond precision)
#   2^-24 = 0x33800000, shifts to bit -24, rounds away → NX=1
# ============================================================
test_1_nx_add:
    lui  x14, 0x3F800
    fmv.w.x f10, x14
    lui  x14, 0x33800           # 2^-24
    fmv.w.x f11, x14
    fadd.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 1
    ret

# ============================================================
# Test 2: No NX — FSUB 1.5 - 1.0 = 0.5 (exact)
# ============================================================
test_2_nx_sub:
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    lui  x14, 0x3F800
    fmv.w.x f11, x14
    fsub.s f12, f10, f11, rne
    csrr x12, fflags
    csrw fflags, x0
    li   x10, 1
    beqz x12, _t2_end
    li   x10, 0
_t2_end:
    ret

# ============================================================
# Test 3: No NX — FMUL 1.0 * 1.5 = 1.5 (exact)
# ============================================================
test_3_nx_mul:
    lui  x14, 0x3F800
    fmv.w.x f10, x14
    lui  x14, 0x3FC00
    fmv.w.x f11, x14
    fmul.s f12, f10, f11, rne
    csrr x12, fflags
    csrw fflags, x0
    li   x10, 1
    beqz x12, _t3_end
    li   x10, 0
_t3_end:
    ret

# ============================================================
# Test 4: DZ — FDIV 1.0 / 0.0 = +Inf
# ============================================================
test_4_dz_div:
    lui  x14, 0x3F800
    fmv.w.x f10, x14
    fmv.w.x f11, x0
    fdiv.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 8
    snez x10, x10
    ret

# ============================================================
# Test 5: OF — FADD max + max overflows
# ============================================================
test_5_of_add:
    lui  x14, 0x7F7F0
    fmv.w.x f10, x14
    fmv.w.x f11, x14
    fadd.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 4
    snez x10, x10
    ret

# ============================================================
# Test 6: UF — FMUL smallest_normal * smallest_normal (2^-252, flushed to zero)
# ============================================================
test_6_uf_mul:
    lui  x14, 0x00800
    fmv.w.x f10, x14
    lui  x14, 0x00800
    fmv.w.x f11, x14
    fmul.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 2
    snez x10, x10
    ret

# ============================================================
# Test 7: NV — FSQRT(-1.0)
# ============================================================
test_7_nv_sqrt_neg:
    lui  x14, 0xBF800
    fmv.w.x f10, x14
    fsqrt.s f12, f10, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 16
    snez x10, x10
    ret

# ============================================================
# Test 8: NV — 0.0 / 0.0 = NaN
# ============================================================
test_8_nv_0_div_0:
    fmv.w.x f10, x0
    fmv.w.x f11, x0
    fdiv.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 16
    snez x10, x10
    ret

# ============================================================
# Test 9: NV — +Inf + -Inf = NaN
# ============================================================
test_9_nv_inf_minus_inf:
    lui  x14, 0x7F800
    fmv.w.x f10, x14
    lui  x14, 0xFF800
    fmv.w.x f11, x14
    fadd.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 16
    snez x10, x10
    ret

# ============================================================
# Test 10: RTZ — FCVT.W.S 1.5 = 1
# ============================================================
test_10_rtz_pos:
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rtz
    li   x10, 1
    li   x13, 1
    beq  x12, x13, _t10_end
    li   x10, 0
_t10_end:
    ret

# ============================================================
# Test 11: RTZ — FCVT.W.S -1.5 = -1
# ============================================================
test_11_rtz_neg:
    lui  x14, 0xBFC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rtz
    li   x10, 1
    li   x13, -1
    beq  x12, x13, _t11_end
    li   x10, 0
_t11_end:
    ret

# ============================================================
# Test 12: RDN — FCVT.W.S 1.5 = 1
# ============================================================
test_12_rdn_pos:
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rdn
    li   x10, 1
    li   x13, 1
    beq  x12, x13, _t12_end
    li   x10, 0
_t12_end:
    ret

# ============================================================
# Test 13: RDN — FCVT.W.S -1.5 = -2
# ============================================================
test_13_rdn_neg:
    lui  x14, 0xBFC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rdn
    li   x10, 1
    li   x13, -2
    beq  x12, x13, _t13_end
    li   x10, 0
_t13_end:
    ret

# ============================================================
# Test 14: RUP — FCVT.W.S 1.5 = 2
# ============================================================
test_14_rup_pos:
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rup
    li   x10, 1
    li   x13, 2
    beq  x12, x13, _t14_end
    li   x10, 0
_t14_end:
    ret

# ============================================================
# Test 15: RUP — FCVT.W.S -1.5 = -1
# ============================================================
test_15_rup_neg:
    lui  x14, 0xBFC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rup
    li   x10, 1
    li   x13, -1
    beq  x12, x13, _t15_end
    li   x10, 0
_t15_end:
    ret

# ============================================================
# Test 16: RMM — FCVT.W.S 1.5 = 2
# ============================================================
test_16_rmm_tie:
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rmm
    li   x10, 1
    li   x13, 2
    beq  x12, x13, _t16_end
    li   x10, 0
_t16_end:
    ret

# ============================================================
# Test 17: DYN — frm=RDN, FCVT.W.S 1.5 = 1
# ============================================================
test_17_dyn_round:
    li   x14, 2
    csrw frm, x14
    lui  x14, 0x3FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, dyn
    csrw frm, x0
    li   x10, 1
    li   x13, 1
    beq  x12, x13, _t17_end
    li   x10, 0
_t17_end:
    ret

# ============================================================
# Test 18: fflags accumulation — DZ then NV
# ============================================================
test_18_fflags_accum:
    csrw fflags, x0
    lui  x14, 0x3F800
    fmv.w.x f10, x14
    fmv.w.x f11, x0
    fdiv.s f12, f10, f11, rne
    lui  x14, 0xBF800
    fmv.w.x f10, x14
    fsqrt.s f12, f10, rne
    csrr x12, fflags
    csrw fflags, x0
    li   x13, 0x18
    li   x10, 1
    beq  x12, x13, _t18_end
    li   x10, 0
_t18_end:
    ret

# ============================================================
# Test 19: FCVT.W.S overflow → INT_MAX, NV
# ============================================================
test_19_fcvt_w_s_overflow:
    lui  x14, 0x4F000
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rne
    csrr x13, fflags
    csrw fflags, x0
    li   x10, 1
    li   x14, 0x7FFFFFFF
    bne  x12, x14, _t19_fail
    andi x14, x13, 16
    beqz x14, _t19_fail
    j    _t19_end
_t19_fail:
    li   x10, 0
_t19_end:
    ret

# ============================================================
# Test 20: FCVT.S.WU 0xFFFFFFFF → 4294967296.0 (RNE)
# ============================================================
test_20_fcvt_s_wu_max:
    li   x14, -1
    fcvt.s.wu f10, x14, rne
    fmv.x.w x12, f10
    lui  x13, 0x4F800
    li   x10, 1
    beq  x12, x13, _t20_end
    li   x10, 0
_t20_end:
    ret

# ============================================================
# Test 21: FADD -0.0 + 0.0 = +0.0
# ============================================================
test_21_fadd_signed_zero:
    lui  x14, 0x80000
    fmv.w.x f10, x14
    fmv.w.x f11, x0
    fadd.s f12, f10, f11, rne
    fmv.x.w x12, f12
    li   x10, 1
    beqz x12, _t21_end
    li   x10, 0
_t21_end:
    ret

# ============================================================
# Test 22: FMUL 0.0 * Inf = NaN, NV
# ============================================================
test_22_fmul_zero_inf:
    fmv.w.x f10, x0
    lui  x14, 0x7F800
    fmv.w.x f11, x14
    fmul.s f12, f10, f11, rne
    csrr x10, fflags
    csrw fflags, x0
    andi x10, x10, 16
    snez x10, x10
    ret

# ============================================================
# Test 23: FSQRT(+0.0) = +0.0, no exception
# ============================================================
test_23_fsqrt_zero:
    fmv.w.x f10, x0
    fsqrt.s f12, f10, rne
    csrr x13, fflags
    csrw fflags, x0
    fmv.x.w x12, f12
    li   x10, 1
    bnez x13, _t23_fail
    bnez x12, _t23_fail
    j    _t23_end
_t23_fail:
    li   x10, 0
_t23_end:
    ret

# ============================================================
# Test 24: FCVT.W.S NaN → INT_MAX, NV
# ============================================================
test_24_fcvt_w_s_nan:
    lui  x14, 0x7FC00
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rne
    csrr x13, fflags
    csrw fflags, x0
    li   x10, 1
    li   x14, 0x7FFFFFFF
    bne  x12, x14, _t24_fail
    andi x14, x13, 16
    beqz x14, _t24_fail
    j    _t24_end
_t24_fail:
    li   x10, 0
_t24_end:
    ret
