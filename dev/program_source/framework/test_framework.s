# ============================================================
# test_framework.s — 自检测试框架
# ============================================================
#
# 提供测试运行器和结果报告机制。每个子测试独立执行、独立报告，
# 失败时精确标识首个失败的子测试 ID。
#
# 寄存器约定 (框架专用，子测试不得修改):
#   x28 = pass_count        (通过数)
#   x29 = total_count       (总测试数)
#   x30 = first_fail_id     (首个失败 ID, 0=全过)
#   x31 = current_test_id   (当前子测试 ID, 1-based)
#
# 子测试约定:
#   - 输入: 无 (子测试自行设置状态)
#   - 输出: x10 = 1 (PASS) 或 0 (FAIL)
#   - 可自由使用: x10-x17 (caller-saved), x1 (ra)
#   - 不得修改: x28-x31 (框架寄存器)
#
# 内存结果区 (0x80001000):
#   +0:  total_count
#   +4:  pass_count
#   +8:  first_fail_id
#   +12: reserved
#   +16: test_1_result (1=PASS, 0=FAIL)
#   +20: test_2_result
#   ...
#   +4*(N+3): test_N_result  (最多 240 个子测试)
#
# ============================================================

.equ TEST_RESULT_BASE, 0x80001000

.section .text

# ── test_init: 初始化测试框架 ──
# 清零框架寄存器和结果区头部
.globl test_init
test_init:
    li   x28, 0              # pass_count = 0
    li   x29, 0              # total_count = 0
    li   x30, 0              # first_fail_id = 0
    li   x31, 0              # current_test_id = 0

    # 清零结果区头部 (16 字节)
    lui  x10, 0x80001        # x10 = 0x80001000
    sw   x0, 0(x10)          # total_count = 0
    sw   x0, 4(x10)          # pass_count = 0
    sw   x0, 8(x10)          # first_fail_id = 0
    sw   x0, 12(x10)         # reserved = 0
    ret


# ── test_run: 运行一个子测试并记录结果 ──
# 输入:
#   x11 = 子测试函数地址
# 输出:
#   x10 = 子测试返回值 (1=PASS, 0=FAIL)
# 副作用:
#   更新 x28 (pass_count), x29 (total_count),
#   x30 (first_fail_id), x31 (current_test_id)
#   写入结果区对应 slot
# 保存: x12-x14 (临时), x1 (ra)
.globl test_run
test_run:
    # 递增计数器
    addi x29, x29, 1          # total_count++
    addi x31, x31, 1          # test_id++
    add  x18, x31, x0         # x18 = 保存当前 test_id (callee-saved)

    # 保存返回地址 (子测试可能使用 jal/jalr)
    add  x19, x1, x0          # x19 = 保存 ra (callee-saved)

    # 调用子测试: 结果在 x10 (1=PASS, 0=FAIL)
    jalr x1, x11, 0

    # ── 写入结果区 ──
    # addr = TEST_RESULT_BASE + (test_id + 3) * 4
    #      = 0x80001000 + test_id*4 + 12
    # 使用 callee-saved x20/x21 避免被子测试 clobber
    lui  x20, 0x80001         # x20 = 0x80001000
    addi x21, x18, 3          # x21 = test_id + 3
    slli x21, x21, 2          # x21 = (test_id + 3) * 4
    add  x20, x20, x21        # x20 = 结果区地址
    sw   x10, 0(x20)          # 写入 1(PASS) 或 0(FAIL)

    # ── 更新 pass_count ──
    li   x21, 1
    beq  x10, x21, _tr_pass
    j    _tr_check_first_fail

_tr_pass:
    addi x28, x28, 1          # pass_count++

_tr_check_first_fail:
    # 仅记录首个失败
    bnez x30, _tr_ret         # 已有失败记录，跳过
    bnez x10, _tr_ret         # 本次通过，跳过
    add  x30, x18, x0         # first_fail_id = test_id

_tr_ret:
    add  x1, x19, x0          # 恢复 ra
    ret


# ── test_report: 将汇总写入结果区头部 ──
# 在所有子测试运行完毕后调用
.globl test_report
test_report:
    lui  x10, 0x80001         # x10 = 0x80001000
    sw   x29, 0(x10)          # total_count
    sw   x28, 4(x10)          # pass_count
    sw   x30, 8(x10)          # first_fail_id
    ret


# ── test_pass: 快速设置 PASS 结果 ──
# 供简单内联检查使用 (无需函数调用开销)
# 用法: beq actual, expected, 1f; jal ra, test_fail; 1: jal ra, test_pass
.globl test_pass
test_pass:
    li   x10, 1
    ret

# ── test_fail: 快速设置 FAIL 结果 ──
.globl test_fail
test_fail:
    li   x10, 0
    ret
