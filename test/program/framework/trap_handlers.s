# ============================================================
# trap_handlers.s — 通用陷阱处理器模板
# ============================================================
#
# 提供多种 M-mode 和 S-mode 陷阱处理器，供不同测试场景选择。
# 测试程序通过 csrw mtvec/stvec 设置所需处理器。
#
# ============================================================

.section .text

# ────────────────────────────────────────────
# M-mode 陷阱处理器
# ────────────────────────────────────────────

# m_trap_simple: 简单递增 mepc+4 并 mret
# 适用: 异常不需要特殊处理，只需跳过当前指令
.globl m_trap_simple
m_trap_simple:
    csrr x10, mepc
    addi x10, x10, 4
    csrw mepc, x10
    mret


# m_trap_record: 记录 mcause→x22, mepc→x23, 然后跳过并 mret
# 适用: 需要验证异常类型和触发地址的测试
# 注意: x22/x23 被 overwrite，子测试应在 trap 前保存
# 输出寄存器选择 x22-x27 避免与 test_run (x18-x21) 冲突
.globl m_trap_record
m_trap_record:
    csrr x22, mcause
    csrr x23, mepc
    addi x23, x23, 4
    csrw mepc, x23
    mret


# m_trap_count: 递增 x23；中断返回原 mepc，同步异常跳过指令
# 定时器中断是电平触发，返回前屏蔽 MTIE，避免反复进入处理器。
.globl m_trap_count
m_trap_count:
    csrr x10, mcause
    blt  x10, x0, 1f
    csrr x10, mepc
    addi x10, x10, 4
    csrw mepc, x10
    j    2f
1:
    li   x10, 0x80
    csrc mie, x10
2:
    addi x23, x23, 1
    mret


# m_trap_save_cause: 记录 mcause→x22, mtval→x23, mepc→x24
# 适用: 需要完整异常信息的测试 (access fault, page fault)
.globl m_trap_save_cause
m_trap_save_cause:
    csrr x22, mcause
    csrr x23, mtval
    csrr x24, mepc
    addi x24, x24, 4
    csrw mepc, x24
    mret


# m_trap_ebreak_handler: 处理 ebreak (mcause=3)
# 记录 mcause→x22, 跳过 ebreak 指令，继续执行
.globl m_trap_ebreak_handler
m_trap_ebreak_handler:
    csrr x22, mcause
    csrr x10, mepc
    addi x10, x10, 4
    csrw mepc, x10
    mret


# ────────────────────────────────────────────
# S-mode 陷阱处理器
# ────────────────────────────────────────────

# s_trap_simple: 简单递增 sepc+4 并 sret
.globl s_trap_simple
s_trap_simple:
    csrr x10, sepc
    addi x10, x10, 4
    csrw sepc, x10
    sret


# s_trap_record: 记录 scause→x22, sepc→x23, 然后跳过并 sret
.globl s_trap_record
s_trap_record:
    csrr x22, scause
    csrr x23, sepc
    addi x23, x23, 4
    csrw sepc, x23
    sret


# s_trap_dispatch: 根据 scause 分发处理
# scause=8  (ecall U→S) → 跳过
# scause=2  (illegal)    → 跳过
# scause=12/13/15 (PF)  → 跳过
# 其他                   → 跳过
# 输出: scause→x22, sepc→x23
.globl s_trap_dispatch
s_trap_dispatch:
    csrr x22, scause
    csrr x23, sepc

    # ecall from U
    li   x10, 8
    beq  x22, x10, _std_skip

    # illegal instruction
    li   x10, 2
    beq  x22, x10, _std_skip

    # instruction page fault
    li   x10, 12
    beq  x22, x10, _std_skip

    # load page fault
    li   x10, 13
    beq  x22, x10, _std_skip

    # store page fault
    li   x10, 15
    beq  x22, x10, _std_skip

_std_skip:
    addi x23, x23, 4
    csrw sepc, x23
    sret
