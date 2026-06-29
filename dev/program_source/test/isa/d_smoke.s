# ============================================================
# isa/d_smoke.s — D extension smoke test (minimal)
# 类别:   ISA-D
# 描述:   Minimal D extension smoke test: FADD.D + FLD/FSD.
#         Verifies D instructions decode correctly and reach
#         the FPU datapath (Tasks 24-26 integration check).
# 子测试: 2
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
#
# Double constants (IEEE 754 double-precision bit patterns):
#   1.0 = 0x3FF0000000000000  (high=0x3FF00000, low=0x00000000)
#   2.0 = 0x4000000000000000  (high=0x40000000, low=0x00000000)
#   3.0 = 0x4008000000000000  (high=0x40080000, low=0x00000000)
#
# RV32 D extension notes:
#   - FLD/FSD use two 32-bit transactions (lo word + hi word).
#   - No FMV.D.X/FMV.X.D in RV32 (XLEN>=64 only).
#   - Double constants are loaded via SW (two words) + FLD.
#   - Scratch area: 0x80006000 (same as f_ext.s, below result area).
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
    la   x11, test_01_fadd_d
    jal  x1, test_run
    la   x11, test_02_fld_fsd
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试
# ============================================================

# Test 1: FADD.D — 1.0 + 2.0 = 3.0
#   Load 1.0 and 2.0 via SW+FLD, add with FADD.D, store result
#   via FSD, read back via LW and verify bit pattern.
#   Expected: 3.0 = 0x4008000000000000 (low=0x00000000, high=0x40080000)
test_01_fadd_d:
    # Load 1.0 (0x3FF0000000000000) into f10 via memory
    lui  x14, 0x80006          # x14 = 0x80006000 (scratch)
    lui  x15, 0x3FF00          # x15 = 0x3FF00000
    sw   x15, 4(x14)           # high word = 0x3FF00000
    sw   x0, 0(x14)            # low word  = 0x00000000
    fld  f10, 0(x14)           # f10 = 1.0

    # Load 2.0 (0x4000000000000000) into f11 via memory
    lui  x15, 0x40000          # x15 = 0x40000000
    sw   x15, 4(x14)           # high word = 0x40000000
    sw   x0, 0(x14)            # low word  = 0x00000000
    fld  f11, 0(x14)           # f11 = 2.0

    # FADD.D — reaches fpu_adder_d via fpu_unit D dispatch (Task 23)
    fadd.d f12, f10, f11, rne  # f12 = 1.0 + 2.0 = 3.0

    # Store result via FSD (exercises FSD two-transaction path, Task 25)
    fsd  f12, 0(x14)           # store f12 (64-bit) to 0x80006000

    # Verify via LW (read back both words)
    lw   x12, 0(x14)           # low word
    lw   x13, 4(x14)           # high word
    li   x10, 1                # assume PASS
    bnez x12, _t01_fail        # low word must be 0x00000000
    lui  x15, 0x40080          # x15 = 0x40080000
    bne  x13, x15, _t01_fail   # high word must be 0x40080000
    j    _t01_end
_t01_fail:
    li   x10, 0
_t01_end:
    ret


# Test 2: FLD/FSD — load double from memory, store back, verify integrity
#   Store 0x4008000000000000 (3.0) via SW, FLD into f10,
#   FSD to another address, LW both words and compare.
#   Verifies FLD (Task 25 two-transaction load) and FSD roundtrip
#   preserve all 64 bits.
test_02_fld_fsd:
    # Store 3.0 (0x4008000000000000) at 0x80006000 via SW
    lui  x14, 0x80006          # x14 = 0x80006000
    sw   x0, 0(x14)            # low word  = 0x00000000
    lui  x15, 0x40080          # x15 = 0x40080000
    sw   x15, 4(x14)           # high word = 0x40080000

    # FLD from 0x80006000 (exercises FLD two-transaction load path, Task 25)
    fld  f10, 0(x14)           # f10 = 3.0

    # FSD to 0x80006008 (exercises FSD two-transaction store path, Task 25)
    addi x14, x14, 8           # x14 = 0x80006008
    fsd  f10, 0(x14)           # store f10 (64-bit) to 0x80006008

    # Verify: read back from 0x80006008 via LW
    lw   x12, 0(x14)           # low word
    lw   x13, 4(x14)           # high word
    li   x10, 1                # assume PASS
    bnez x12, _t02_fail        # low word must be 0x00000000
    lui  x15, 0x40080          # x15 = 0x40080000
    bne  x13, x15, _t02_fail   # high word must be 0x40080000
    j    _t02_end
_t02_fail:
    li   x10, 0
_t02_end:
    ret
