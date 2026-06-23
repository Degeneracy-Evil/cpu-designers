# ============================================================
# test_framework.s — 自检测试框架
# ============================================================
#
# 提供测试运行器和结果报告机制。每个子测试独立执行、独立报告，
# 失败时精确标识首个失败的子测试 ID。
#
# 寄存器约定 (框架专用，子测试不得修改):
#   x8  = pass_count        (通过数, s0)
#   x9  = total_count       (总测试数, s1)
#   x18 = first_fail_id     (首个失败 ID, 0=全过, s2)
#   x19 = current_test_id   (当前子测试 ID, 1-based, s3)
#
# 子测试约定:
#   - 输入: 无 (子测试自行设置状态)
#   - 输出: x10 = 1 (PASS) 或 0 (FAIL)
#   - 可自由使用: x10-x17 (caller-saved), x1 (ra)
#   - 不得修改: x8/x9/x18/x19 (框架寄存器)
#
# 内存结果区 (0x80007000):
#   +0:  total_count
#   +4:  pass_count
#   +8:  first_fail_id
#   +12: reserved
#   +16: test_1_result (1=PASS, 0=FAIL)
#   +20: test_2_result
#   ...
#   +4*(N+3): test_N_result  (最多 240 个子测试)
#
# NOTE: 使用 0x80007000 (SRAM 最后 4KB 页) 避免与页表/测试数据冲突
#       页表数据 .balign 4096 会被链接器放在 0x80001000 起始的区域
#
# ============================================================

.equ TEST_RESULT_BASE, 0x80007000

.section .text

# ── test_init: 初始化测试框架 ──
# 清零框架寄存器和结果区头部
.globl test_init
test_init:
    li   x8, 0               # pass_count = 0
    li   x9, 0               # total_count = 0
    li   x18, 0              # first_fail_id = 0
    li   x19, 0              # current_test_id = 0
    li   x28, 0              # compatibility mirror: pass_count
    li   x29, 0              # compatibility mirror: total_count
    li   x30, 0              # compatibility mirror: first_fail_id
    li   x31, 0              # compatibility mirror: current_test_id

    # 清零结果区头部 (16 字节)
    lui  x10, 0x80007         # x10 = 0x80007000
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
#   更新 x8/x9/x18/x19
#   写入结果区对应 slot
.globl test_run
test_run:
    # 递增计数器
    addi x9, x9, 1            # total_count++
    addi x19, x19, 1          # test_id++
    add  x20, x19, x0         # x20 = 保存当前 test_id

    # 保存返回地址 (子测试可能使用 jal/jalr)
    add  x21, x1, x0          # x21 = 保存 ra

    # 调用子测试: 结果在 x10 (1=PASS, 0=FAIL)
    jalr x1, x11, 0

    # ── 写入结果区 ──
    # addr = TEST_RESULT_BASE + (test_id + 3) * 4
    #      = 0x80007000 + test_id*4 + 12
    li   x5, 0x80007000       # x5 = 结果区基址
    addi x6, x20, 3           # x6 = test_id + 3
    slli x6, x6, 2            # x6 = (test_id + 3) * 4
    add  x5, x5, x6           # x5 = 结果区地址
    sw   x10, 0(x5)           # 写入 1(PASS) 或 0(FAIL)

    # ── 更新 pass_count ──
    li   x5, 1
    beq  x10, x5, _tr_pass
    j    _tr_check_first_fail

_tr_pass:
    addi x8, x8, 1            # pass_count++

_tr_check_first_fail:
    # 仅记录首个失败
    bnez x18, _tr_ret         # 已有失败记录，跳过
    bnez x10, _tr_ret         # 本次通过，跳过
    add  x18, x20, x0         # first_fail_id = test_id

_tr_ret:
    add  x1, x21, x0          # 恢复 ra
    ret


# ── test_report: 将汇总写入结果区头部 ──
# 在所有子测试运行完毕后调用
.globl test_report
test_report:
    lui  x10, 0x80007         # x10 = 0x80007000
    sw   x9, 0(x10)           # total_count
    sw   x8, 4(x10)           # pass_count
    sw   x18, 8(x10)          # first_fail_id
    add  x28, x8, x0          # compatibility mirror: pass_count
    add  x29, x9, x0          # compatibility mirror: total_count
    add  x30, x18, x0         # compatibility mirror: first_fail_id
    add  x31, x19, x0         # compatibility mirror: current_test_id
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
