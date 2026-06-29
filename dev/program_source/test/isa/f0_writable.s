# ============================================================
# isa/f0_writable.s — f0 (ft0) writable register test
# 类别:   ISA-F
# 描述:   验证 f0 是普通可写寄存器（非硬连线 0）。
#         RISC-V F 扩展规范中 f0/ft0 是临时寄存器，无硬连线值。
#         复位后值为 0（实现选择，保证确定性）。
# 子测试: 5
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================
#
# 测试项:
#   1. f0 复位值为 0
#   2. 写 0x3F800000 (1.0) 到 f0，读回验证
#   3. 写 0x40000000 (2.0) 到 f0，读回验证
#   4. 写 0x00000000 到 f0，读回验证
#   5. f0 作为 FADD 源操作数 (f0 + f1)，验证使用 f0 的值
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
    la   x11, test_01_f0_reset_zero
    jal  x1, test_run
    la   x11, test_02_f0_write_1_0
    jal  x1, test_run
    la   x11, test_03_f0_write_2_0
    jal  x1, test_run
    la   x11, test_04_f0_write_zero
    jal  x1, test_run
    la   x11, test_05_f0_in_fadd
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试
# ============================================================

# Test 1: f0 复位值为 0
#   复位后未写 f0 前，读取 f0 应为 0x00000000
test_01_f0_reset_zero:
    fmv.x.w x12, f0            # x12 = f0 的位模式
    li   x13, 0                # 期望值 0
    li   x10, 1
    beq  x12, x13, _t01_end
    li   x10, 0
_t01_end:
    ret

# Test 2: 写 1.0 (0x3F800000) 到 f0，读回验证
test_02_f0_write_1_0:
    lui  x14, 0x3F800          # x14 = 0x3F800000 (1.0)
    fmv.w.x f0, x14            # 写 f0
    fmv.x.w x12, f0            # 读回 f0
    lui  x13, 0x3F800          # 期望 0x3F800000
    li   x10, 1
    beq  x12, x13, _t02_end
    li   x10, 0
_t02_end:
    ret

# Test 3: 写 2.0 (0x40000000) 到 f0，读回验证
test_03_f0_write_2_0:
    lui  x14, 0x40000          # x14 = 0x40000000 (2.0)
    fmv.w.x f0, x14            # 写 f0
    fmv.x.w x12, f0            # 读回 f0
    lui  x13, 0x40000          # 期望 0x40000000
    li   x10, 1
    beq  x12, x13, _t03_end
    li   x10, 0
_t03_end:
    ret

# Test 4: 写 0x00000000 到 f0，读回验证
test_04_f0_write_zero:
    fmv.w.x f0, x0             # 写 f0 = 0 (从 x0)
    fmv.x.w x12, f0            # 读回 f0
    li   x13, 0                # 期望 0
    li   x10, 1
    beq  x12, x13, _t04_end
    li   x10, 0
_t04_end:
    ret

# Test 5: f0 作为 FADD 源操作数
#   f0 = 1.0, f1 = 2.0, fadd.s f2, f0, f1 → f2 = 3.0
#   验证 f0 的值被正确使用（而非被强制为 0）
test_05_f0_in_fadd:
    lui  x14, 0x3F800          # 1.0
    fmv.w.x f0, x14            # f0 = 1.0
    lui  x14, 0x40000          # 2.0
    fmv.w.x f1, x14            # f1 = 2.0
    fadd.s f2, f0, f1, rne     # f2 = f0 + f1 = 3.0
    lui  x14, 0x40400          # 3.0 = 0x40400000
    fmv.w.x f3, x14
    feq.s x10, f2, f3          # x10 = (f2 == 3.0) ? 1 : 0
    ret
