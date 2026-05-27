# ============================================================
# page_table_utils.s — 页表构建工具
# ============================================================
#
# 提供 Sv32 页表设置工具函数，供 MMU/TLB/特权测试使用。
#
# PTE 位定义 (Sv32):
#   bit 0: V (Valid)
#   bit 1: R (Read)
#   bit 2: W (Write)
#   bit 3: X (Execute)
#   bit 4: U (User)
#   bit 5: G (Global)
#   bit 6: A (Accessed)
#   bit 7: D (Dirty)
#   bits [31:10]: PPN
#
# 约定:
#   页表数据区放在 .balign 4096 区域
#   L1 表: 1024 项 × 4 字节 = 4KB
#   L0 表: 1024 项 × 4 字节 = 4KB
#
# ============================================================

.equ PTE_V, 0x001
.equ PTE_R, 0x002
.equ PTE_W, 0x004
.equ PTE_X, 0x008
.equ PTE_U, 0x010
.equ PTE_G, 0x020
.equ PTE_A, 0x040
.equ PTE_D, 0x080

.section .text

# ── setup_identity_map: 恒等映射 0x80000000 区域 ──
#
# 创建 L1[2]→L0, L0[0-3]→0x80000000-0x80003FFF 的恒等映射
# 映射属性: Supervisor, RWXAD (非 User)
#
# 输入: 无 (使用全局 l1_page_table / l0_page_table 标签)
# 输出: 无
# 副作用: 写入页表内存
.globl setup_identity_map
setup_identity_map:
    # L1[2] = (L0_base >> 12) << 10 | V
    # VPN=2 对应虚拟地址 0x80000000 (VPN[19:10]=2)
    la   x15, l1_page_table
    la   x16, l0_page_table

    srli x17, x16, 12
    slli x17, x17, 10
    ori  x17, x17, PTE_V
    sw   x17, 8(x15)            # L1[2] (offset=2*4=8)

    # L0[0-3] = 恒等映射, RWXAD, Supervisor
    li   x17, 0x80000           # PPN = 0x80000 (0x80000000 >> 12)
    slli x17, x17, 10           # PPN << 10
    li   x18, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
    or   x17, x17, x18
    sw   x17, 0(x16)            # L0[0] → 0x80000000

    li   x17, 0x80001           # PPN = 0x80001
    slli x17, x17, 10
    or   x17, x17, x18
    sw   x17, 4(x16)            # L0[1] → 0x80001000

    li   x17, 0x80002           # PPN = 0x80002
    slli x17, x17, 10
    or   x17, x17, x18
    sw   x17, 8(x16)            # L0[2] → 0x80002000

    li   x17, 0x80003           # PPN = 0x80003
    slli x17, x17, 10
    or   x17, x17, x18
    sw   x17, 12(x16)           # L0[3] → 0x80003000

    ret


# ── setup_user_map: 恒等映射 + User 页 ──
#
# 在 setup_identity_map 基础上，将 L0[3] 设为 User 可访问
# 用于 U-mode 测试
#
.globl setup_user_map
setup_user_map:
    # 先做恒等映射
    jal  x1, setup_identity_map

    # 修改 L0[3] 为 User 页: URWXAD
    la   x16, l0_page_table
    li   x17, 0x80003
    slli x17, x17, 10
    li   x18, PTE_V|PTE_R|PTE_W|PTE_X|PTE_U|PTE_A|PTE_D
    or   x17, x17, x18
    sw   x17, 12(x16)           # L0[3] → User 页

    ret


# ── enable_sv32: 启用 Sv32 虚拟内存 ──
#
# 设置 satp 寄存器启用 Sv32 模式
# satp[31] = 1 (Sv32), satp[30:22] = ASID (0), satp[21:0] = L1_PPN
#
.globl enable_sv32
enable_sv32:
    la   x10, l1_page_table
    srli x10, x10, 12           # PPN = L1_base >> 12
    li   x11, 0x80000000        # Sv32 mode bit
    or   x10, x10, x11
    csrw satp, x10
    ret


# ── disable_sv32: 禁用 Sv32 (切换回 bare 模式) ──
#
.globl disable_sv32
disable_sv32:
    csrw satp, x0
    ret


# ── clear_page_tables: 清零页表 ──
#
# 将 L1 和 L0 页表全部清零
#
.globl clear_page_tables
clear_page_tables:
    la   x15, l1_page_table
    la   x16, l0_page_table

    # 清零 L1 (1024 项)
    li   x17, 1024
    add  x10, x15, x0          # x10 = current ptr
_cpt_l1:
    sw   x0, 0(x10)
    addi x10, x10, 4
    addi x17, x17, -1
    bnez x17, _cpt_l1

    # 清零 L0 (1024 项)
    li   x17, 1024
    add  x10, x16, x0          # x10 = current ptr
_cpt_l0:
    sw   x0, 0(x10)
    addi x10, x10, 4
    addi x17, x17, -1
    bnez x17, _cpt_l0

    ret


# ============================================================
# 页表数据区
# ============================================================
# 放在 .text 段末尾，.balign 4096 保证页对齐
# 每个测试程序链接时会包含这些区域

.balign 4096
l1_page_table:
    .fill 1024, 4, 0

.balign 4096
l0_page_table:
    .fill 1024, 4, 0
