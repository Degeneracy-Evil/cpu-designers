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
# 创建 L1[512]→L0, L0[0-7]→0x80000000-0x80007FFF 的恒等映射
# 映射属性: Supervisor, RWXAD (非 User)
# 覆盖 32KB SRAM 全部 (8 pages × 4KB)
#
# Sv32 VPN 索引:
#   VPN[1] = VA[31:22] (L1 index, 10 bits)
#   VPN[0] = VA[21:12] (L0 index, 10 bits)
#   对于 VA 0x80000000: VPN[1] = 0x200 = 512, VPN[0] = 0
#
# 输入: 无 (使用全局 l1_page_table / l0_page_table 标签)
# 输出: 无
# 副作用: 写入页表内存, 使用 caller-saved x5-x17 (不破坏 callee-saved)
.globl setup_identity_map
setup_identity_map:
    # L1[512] = (L0_base >> 12) << 10 | V
    # VPN[1]=512 对应虚拟地址 0x80000000 (VA[31:22]=0x200)
    la   x15, l1_page_table
    la   x16, l0_page_table

    srli x17, x16, 12
    slli x17, x17, 10
    ori  x17, x17, PTE_V
    # L1[512] offset=0x800 exceeds 12-bit imm, compute addr in register
    li   x14, 0x800
    add  x14, x15, x14         # x14 = &l1_page_table[512]
    sw   x17, 0(x14)           # L1[512]

    # L0[0-7] = 恒等映射, RWXAD, Supervisor (覆盖 32KB SRAM)
    li   x5, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D

    li   x17, 0x80000           # PPN = 0x80000 (0x80000000 >> 12)
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 0(x16)            # L0[0] → 0x80000000

    li   x17, 0x80001
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 4(x16)            # L0[1] → 0x80001000

    li   x17, 0x80002
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 8(x16)            # L0[2] → 0x80002000

    li   x17, 0x80003
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 12(x16)           # L0[3] → 0x80003000

    li   x17, 0x80004
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 16(x16)           # L0[4] → 0x80004000

    li   x17, 0x80005
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 20(x16)           # L0[5] → 0x80005000

    li   x17, 0x80006
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 24(x16)           # L0[6] → 0x80006000

    li   x17, 0x80007
    slli x17, x17, 10
    or   x17, x17, x5
    sw   x17, 28(x16)           # L0[7] → 0x80007000

    ret


# ── setup_user_map: 恒等映射 + User 页 ──
#
# 在 setup_identity_map 基础上，将 L0[7] 设为 User 可访问
# 用于 U-mode 测试 (L0[7] → 0x80007000)
#
.globl setup_user_map
setup_user_map:
    # 先做恒等映射
    jal  x1, setup_identity_map

    # 修改 L0[7] 为 User 页: URWXAD
    la   x16, l0_page_table
    li   x17, 0x80007
    slli x17, x17, 10
    li   x5, PTE_V|PTE_R|PTE_W|PTE_X|PTE_U|PTE_A|PTE_D
    or   x17, x17, x5
    sw   x17, 28(x16)           # L0[7] → User 页 (0x80007000)

    ret


# ── enable_sv32: 启用 Sv32 虚拟内存 ──
#
# 设置 satp 寄存器启用 Sv32 模式，并刷新 TLB
# satp[31] = 1 (Sv32), satp[30:22] = ASID (0), satp[21:0] = L1_PPN
# 注意: 切换 satp 后必须 sfence.vma 刷新 TLB，否则可能命中旧条目
# CRITICAL: dcache 是 write-back，页表写入可能还在 dcache 中未写回 SRAM。
# PTW 直接从 SRAM 读取（绕过 dcache），因此必须先 fence.i 刷新 dcache，
# 否则 PTW 会读到全零的陈旧页表 → 页表遍历失败 → CPU 挂死。
#
.globl enable_sv32
enable_sv32:
    fence.i                     # 刷新 dcache (写回脏行) + 无效化 icache
    la   x10, l1_page_table
    srli x10, x10, 12           # PPN = L1_base >> 12
    li   x11, 0x80000000        # Sv32 mode bit
    or   x10, x10, x11
    csrw satp, x10
    sfence.vma                  # 刷新 TLB (M-mode 下始终合法)
    ret


# ── disable_sv32: 禁用 Sv32 (切换回 bare 模式) ──
#
# 清除 satp 切换回 bare 模式。fence.i 确保后续 M-mode 访存
# 能看到 S-mode 期间可能缓存在 dcache 中的最新数据。
#
.globl disable_sv32
disable_sv32:
    csrw satp, x0
    fence.i                     # 刷新 dcache，确保 M-mode 可见最新数据
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
# 注意：页表位置随链接顺序浮动，通常在 0x80002000-0x80004000 附近
# 测试数据写入必须避开页表区域（见各测试文件的地址选择）

.balign 4096
.globl l1_page_table
l1_page_table:
    .fill 1024, 4, 0

.balign 4096
.globl l0_page_table
l0_page_table:
    .fill 1024, 4, 0
