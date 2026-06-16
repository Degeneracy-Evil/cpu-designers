# ============================================================
# isa/f_ext.s — F-extension (single-precision float) tests
# 类别:   ISA
# 描述:   测试 F 扩展指令 (FADD/FSUB/FMUL/FDIV/FSQRT/FMIN/FMAX/
#         FSGNJ/FSGNJN/FSGNJX/FEQ/FLT/FLE/FCLASS/FMV.W.X/FMV.X.W/
#         FCVT.S.W/FCVT.S.WU/FCVT.W.S/FCVT.WU.S/FLW/FSW/
#         FMADD.S/FMSUB.S/FNMSUB.S/FNMADD.S)
# 子测试: 30
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
#
# Float constants (IEEE 754 single-precision bit patterns loaded via FMV.W.X):
#   0.0   = 0x00000000    1.0   = 0x3F800000    2.0   = 0x40000000
#   3.0   = 0x40400000    4.0   = 0x40800000    6.0   = 0x40C00000
#   0.5   = 0x3F000000    0.25  = 0x3E800000    42.0  = 0x42280000
#  -1.0   = 0xBF800000   -2.0   = 0xC0000000
#  +inf   = 0x7F800000    NaN   = 0x7FC00000   -0.0   = 0x80000000
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
    la   x11, test_01_fadd
    jal  x1, test_run
    la   x11, test_02_fsub
    jal  x1, test_run
    la   x11, test_03_fmul
    jal  x1, test_run
    la   x11, test_04_fdiv
    jal  x1, test_run
    la   x11, test_05_fsqrt
    jal  x1, test_run
    la   x11, test_06_fmin
    jal  x1, test_run
    la   x11, test_07_fmax
    jal  x1, test_run
    la   x11, test_08_fsgnj
    jal  x1, test_run
    la   x11, test_09_fsgnjn
    jal  x1, test_run
    la   x11, test_10_fsgnjx
    jal  x1, test_run
    la   x11, test_11_feq
    jal  x1, test_run
    la   x11, test_12_flt
    jal  x1, test_run
    la   x11, test_13_fle
    jal  x1, test_run
    la   x11, test_14_fclass
    jal  x1, test_run
    la   x11, test_15_fmv_w_x
    jal  x1, test_run
    la   x11, test_16_fmv_x_w
    jal  x1, test_run
    la   x11, test_17_fcvt_s_w
    jal  x1, test_run
    la   x11, test_18_fcvt_s_wu
    jal  x1, test_run
    la   x11, test_19_fcvt_w_s
    jal  x1, test_run
    la   x11, test_20_fcvt_wu_s
    jal  x1, test_run
    la   x11, test_21_flw
    jal  x1, test_run
    la   x11, test_22_fsw
    jal  x1, test_run
    la   x11, test_23_fadd_neg
    jal  x1, test_run
    la   x11, test_24_fmul_frac
    jal  x1, test_run
    la   x11, test_25_fdiv_round
    jal  x1, test_run
    la   x11, test_26_fsqrt_zero
    jal  x1, test_run
    la   x11, test_27_fmadd
    jal  x1, test_run
    la   x11, test_28_fmsub
    jal  x1, test_run
    la   x11, test_29_fnmsub
    jal  x1, test_run
    la   x11, test_30_fnmadd
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 辅助宏: 加载 float 常数到浮点寄存器
#   用法: 将 IEEE 754 位模式加载到 x14, 然后 fmv.w.x
#   注意: 使用 x14/x15 作为临时整数寄存器, f10-f15 作为临时浮点寄存器
# ============================================================

# ============================================================
# 子测试
# ============================================================

# Test 1: FADD.S — 1.0 + 2.0 = 3.0
test_01_fadd:
    lui  x14, 0x3F800         # x14 = 0x3F800000 (1.0)
    fmv.w.x f10, x14
    lui  x14, 0x40000         # x14 = 0x40000000 (2.0)
    fmv.w.x f11, x14
    fadd.s f12, f10, f11, rne
    lui  x14, 0x40400         # x14 = 0x40400000 (3.0)
    fmv.w.x f13, x14
    feq.s x10, f12, f13       # x10 = (f12 == 3.0) ? 1 : 0
    ret

# Test 2: FSUB.S — 3.0 - 1.0 = 2.0
test_02_fsub:
    lui  x14, 0x40400         # 3.0
    fmv.w.x f10, x14
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f11, x14
    fsub.s f12, f10, f11, rne
    lui  x14, 0x40000         # 2.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 3: FMUL.S — 2.0 * 3.0 = 6.0
test_03_fmul:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    fmul.s f12, f10, f11, rne
    lui  x14, 0x40C00         # 6.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 4: FDIV.S — 6.0 / 2.0 = 3.0
test_04_fdiv:
    lui  x14, 0x40C00         # 6.0
    fmv.w.x f10, x14
    lui  x14, 0x40000         # 2.0
    fmv.w.x f11, x14
    fdiv.s f12, f10, f11, rne
    lui  x14, 0x40400         # 3.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 5: FSQRT.S — sqrt(4.0) = 2.0
test_05_fsqrt:
    lui  x14, 0x40800         # 4.0
    fmv.w.x f10, x14
    fsqrt.s f12, f10, rne
    lui  x14, 0x40000         # 2.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 6: FMIN.S — min(1.0, 2.0) = 1.0
test_06_fmin:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    lui  x14, 0x40000         # 2.0
    fmv.w.x f11, x14
    fmin.s f12, f10, f11
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 7: FMAX.S — max(1.0, 2.0) = 2.0
test_07_fmax:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    lui  x14, 0x40000         # 2.0
    fmv.w.x f11, x14
    fmax.s f12, f10, f11
    lui  x14, 0x40000         # 2.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 8: FSGNJ.S — sgnj(1.0, -2.0) = -1.0
#   FSGNJ: result = |fs1| with sign of fs2
test_08_fsgnj:
    lui  x14, 0x3F800         # 1.0 (positive)
    fmv.w.x f10, x14
    lui  x14, 0xC0000         # -2.0 (negative, 0xC0000000)
    fmv.w.x f11, x14
    fsgnj.s f12, f10, f11     # take sign from -2.0 → -1.0
    lui  x14, 0xBF800         # -1.0 (0xBF800000)
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 9: FSGNJN.S — sgnjn(1.0, -2.0) = 1.0
#   FSGNJN: result = |fs1| with INVERTED sign of fs2
test_09_fsgnjn:
    lui  x14, 0x3F800         # 1.0 (positive)
    fmv.w.x f10, x14
    lui  x14, 0xC0000         # -2.0 (negative)
    fmv.w.x f11, x14
    fsgnjn.s f12, f10, f11    # invert sign of -2.0 → positive → 1.0
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 10: FSGNJX.S — sgnjx(1.0, -2.0) = -1.0
#   FSGNJX: result = |fs1| with XOR of signs
test_10_fsgnjx:
    lui  x14, 0x3F800         # 1.0 (positive)
    fmv.w.x f10, x14
    lui  x14, 0xC0000         # -2.0 (negative)
    fmv.w.x f11, x14
    fsgnjx.s f12, f10, f11    # XOR signs: pos XOR neg = neg → -1.0
    lui  x14, 0xBF800         # -1.0
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 11: FEQ.S — eq(1.0, 1.0) = 1
test_11_feq:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    fmv.w.x f11, x14          # also 1.0
    feq.s x10, f10, f11       # x10 = 1 if equal
    ret

# Test 12: FLT.S — lt(1.0, 2.0) = 1
test_12_flt:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    lui  x14, 0x40000         # 2.0
    fmv.w.x f11, x14
    flt.s x10, f10, f11       # x10 = 1 if 1.0 < 2.0
    ret

# Test 13: FLE.S — le(2.0, 2.0) = 1
test_13_fle:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    fmv.w.x f11, x14          # also 2.0
    fle.s x10, f10, f11       # x10 = 1 if 2.0 <= 2.0
    ret

# Test 14: FCLASS.S — class(1.0) = bit 4 (positive normal)
#   FCLASS returns a 10-bit mask in rd:
#   bit 0: -inf, bit 1: -normal, bit 2: -subnormal, bit 3: -zero
#   bit 4: +zero, bit 5: +subnormal, bit 6: +normal, bit 7: +inf
#   bit 8: signaling NaN, bit 9: quiet NaN
#   Wait — let me check the standard encoding:
#   bit 0: -inf, bit 1: -normal, bit 2: -subnormal, bit 3: -zero
#   bit 4: +zero, bit 5: +subnormal, bit 6: +normal, bit 7: +inf
#   bit 8: sNaN, bit 9: qNaN
#   1.0 is positive normal → bit 6 → value = 0x040
test_14_fclass:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    fclass.s x12, f10         # x12 = class mask
    li   x13, 0x040           # bit 6 = positive normal
    li   x10, 1
    beq  x12, x13, _t14_end
    li   x10, 0
_t14_end:
    ret

# Test 15: FMV.W.X — move int 0x3F800000 to float = 1.0
test_15_fmv_w_x:
    lui  x14, 0x3F800         # x14 = 0x3F800000
    fmv.w.x f10, x14          # f10 = 1.0
    lui  x14, 0x3F800         # 1.0 for comparison
    fmv.w.x f11, x14
    feq.s x10, f10, f11       # should be equal
    ret

# Test 16: FMV.X.W — move float 1.0 to int = 0x3F800000
test_16_fmv_x_w:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    fmv.x.w x12, f10          # x12 = 0x3F800000
    lui  x13, 0x3F800         # expected
    li   x10, 1
    beq  x12, x13, _t16_end
    li   x10, 0
_t16_end:
    ret

# Test 17: FCVT.S.W — convert int 42 to float 42.0
#   Uses fmv.x.w for direct bit comparison to isolate FCVT vs FEQ bugs
test_17_fcvt_s_w:
    li   x14, 42
    fcvt.s.w f10, x14, rne      # RNE
    fmv.x.w x12, f10            # read back bit pattern
    lui  x13, 0x42280         # 42.0 = 0x42280000
    li   x10, 1
    beq  x12, x13, _t17_end
    li   x10, 0
_t17_end:
    ret

# Test 18: FCVT.S.WU — convert uint 42 to float 42.0
test_18_fcvt_s_wu:
    li   x14, 42
    fcvt.s.wu f10, x14, rne     # RNE
    lui  x14, 0x42280         # 42.0
    fmv.w.x f11, x14
    feq.s x10, f10, f11
    ret

# Test 19: FCVT.W.S — convert float 42.0 to int 42
test_19_fcvt_w_s:
    lui  x14, 0x42280         # 42.0
    fmv.w.x f10, x14
    fcvt.w.s x12, f10, rne      # RNE
    li   x13, 42
    li   x10, 1
    beq  x12, x13, _t19_end
    li   x10, 0
_t19_end:
    ret

# Test 20: FCVT.WU.S — convert float 42.0 to uint 42
test_20_fcvt_wu_s:
    lui  x14, 0x42280         # 42.0
    fmv.w.x f10, x14
    fcvt.wu.s x12, f10, rne     # RNE
    li   x13, 42
    li   x10, 1
    beq  x12, x13, _t20_end
    li   x10, 0
_t20_end:
    ret

# Test 21: FLW — load float from memory
#   Store 1.0 (0x3F800000) at scratch address, then FLW and verify
test_21_flw:
    lui  x14, 0x80006         # x14 = 0x80006000 (scratch area)
    lui  x15, 0x3F800         # x15 = 0x3F800000 (1.0)
    sw   x15, 0(x14)          # store bit pattern to memory
    flw  f10, 0(x14)          # load as float
    lui  x14, 0x3F800         # 1.0 for comparison
    fmv.w.x f11, x14
    feq.s x10, f10, f11       # should be 1.0
    ret

# Test 22: FSW — store float to memory and verify
#   Put 2.0 in f10, FSW to memory, then LW and compare bit pattern
test_22_fsw:
    lui  x14, 0x80006         # x14 = 0x80006000 (scratch area)
    lui  x15, 0x40000         # 2.0
    fmv.w.x f10, x15
    fsw  f10, 0(x14)          # store float to memory
    lw   x12, 0(x14)          # read back as integer
    lui  x13, 0x40000         # expected: 0x40000000
    li   x10, 1
    beq  x12, x13, _t22_end
    li   x10, 0
_t22_end:
    ret

# Test 23: FADD.S — -1.0 + 1.0 = 0.0 (signed zero)
test_23_fadd_neg:
    lui  x14, 0xBF800         # -1.0
    fmv.w.x f10, x14
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f11, x14
    fadd.s f12, f10, f11, rne
    # Result should be +0.0 (0x00000000)
    fmv.x.w x12, f12
    li   x10, 1
    beq  x12, x0, _t23_end   # x12 == 0 means +0.0
    li   x10, 0
_t23_end:
    ret

# Test 24: FMUL.S — 0.5 * 0.5 = 0.25
test_24_fmul_frac:
    lui  x14, 0x3F000         # 0.5 = 0x3F000000
    fmv.w.x f10, x14
    fmul.s f12, f10, f10, rne   # 0.5 * 0.5
    lui  x14, 0x3E800         # 0.25 = 0x3E800000
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 25: FDIV.S — 1.0 / 3.0 ≈ 0.333... (rounding test)
#   1.0/3.0 = 0.3333333432674408... → 0x3EAAAAAB (RNE)
test_25_fdiv_round:
    lui  x14, 0x3F800         # 1.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    fdiv.s f12, f10, f11, rne   # RNE
    # Expected: 0x3EAAAAAB — use li pseudo-instruction for full 32-bit constant
    li   x14, 0x3EAAAAAB
    fmv.w.x f13, x14
    feq.s x10, f12, f13
    ret

# Test 26: FSQRT.S — sqrt(0.0) = 0.0
test_26_fsqrt_zero:
    fmv.w.x f10, x0           # f10 = 0.0 (from x0 = 0)
    fsqrt.s f12, f10, rne
    feq.s x10, f12, f10       # sqrt(0.0) == 0.0
    ret

# Test 27: FMADD.S — (2.0 × 3.0) + 4.0 = 10.0
#   10.0 = 0x41200000
test_27_fmadd:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    lui  x14, 0x40800         # 4.0
    fmv.w.x f12, x14
    fmadd.s f13, f10, f11, f12, rne  # (2.0 * 3.0) + 4.0 = 10.0
    lui  x14, 0x41200         # 10.0 = 0x41200000
    fmv.w.x f15, x14
    feq.s x10, f13, f15
    ret

# Test 28: FMSUB.S — (2.0 × 3.0) - 4.0 = 2.0
test_28_fmsub:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    lui  x14, 0x40800         # 4.0
    fmv.w.x f12, x14
    fmsub.s f13, f10, f11, f12, rne  # (2.0 * 3.0) - 4.0 = 2.0
    lui  x14, 0x40000         # 2.0
    fmv.w.x f15, x14
    feq.s x10, f13, f15
    ret

# Test 29: FNMSUB.S — -(2.0 × 3.0) + 10.0 = 4.0
#   FNMSUB computes -(rs1×rs2) + rs3 = -6.0 + 10.0 = 4.0
test_29_fnmsub:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    lui  x14, 0x41200         # 10.0
    fmv.w.x f12, x14
    fnmsub.s f13, f10, f11, f12, rne  # -(2.0*3.0) + 10.0 = 4.0
    lui  x14, 0x40800         # 4.0
    fmv.w.x f15, x14
    feq.s x10, f13, f15
    ret

# Test 30: FNMADD.S — -(2.0 × 3.0) - 4.0 = -10.0
#   FNMADD computes -(rs1×rs2) - rs3 = -6.0 - 4.0 = -10.0
test_30_fnmadd:
    lui  x14, 0x40000         # 2.0
    fmv.w.x f10, x14
    lui  x14, 0x40400         # 3.0
    fmv.w.x f11, x14
    lui  x14, 0x40800         # 4.0
    fmv.w.x f12, x14
    fnmadd.s f13, f10, f11, f12, rne  # -(2.0*3.0) - 4.0 = -10.0
    lui  x14, 0xC1200         # -10.0 = 0xC1200000
    fmv.w.x f15, x14
    feq.s x10, f13, f15
    ret
