# 测试程序体系重构计划

> 创建日期: 2026-05-26 | 状态: **规划中** | 关联: `dev/PLAN-nmmu.md` Phase 3-4

---

## 1. 目标与动机

### 1.1 核心目标

构建一套**结构化、自检、可扩展**的测试程序体系，使：

1. **全面覆盖** — 指令集、特权级、MMU/TLB、Cache、异常中断、MMIO 均有专项测试
2. **精确定位** — 测试失败时立即知道是哪个子测试、哪条指令/哪个场景出错
3. **隔离性** — 单个子测试失败不级联影响后续测试
4. **可扩展** — 新增测试只需按模板编写，自动纳入构建和回归
5. **服务当前与后续** — 覆盖 NMMU Phase 3-4 验证需求，并为后续功能扩展提供框架

### 1.2 当前问题分析

| 问题 | 表现 | 影响 |
|------|------|------|
| **单体测试** | `cpu_test.s` 270 行混合 ALU/分支/访存/CSR/M扩展/中断 | 失败时无法定位具体指令 |
| **无自检** | 程序不报告 pass/fail，靠 testbench 事后检查寄存器 | 寄存器值错但不知哪步出错 |
| **级联失败** | 前置指令写错寄存器 → 后续所有检查全错 | 一错全错，无法区分根因 |
| **时序依赖** | testbench 固定等 N 周期后检查 | BRAM 延迟变化导致采样点错 |
| **MMU 覆盖不足** | `cpu_test_priv.s` 仅测 M→S→U 基本切换，`cpu_test_mmu.s` 仅测 bare+Sv32 基本 | TLB 替换/刷新/ASID/并发 miss/页错误边角均未覆盖 |
| **无回归保障** | Phase 2 修了 11 个 bug，但无专项回归测试防止回退 | bug 可能随后续改动复现 |
| **testbench 重复** | 每个 tb 文件 80% 代码相同（DUT+总线+外设实例化） | 维护成本高，新增测试需复制大量模板 |

### 1.3 Phase 2 Bug 教训

Phase 2 修复的 11 个 bug 暴露了测试体系的根本缺陷：**每个 bug 都需要长时间仿真+人工波形排查才能定位**。若有专项测试，多数 bug 可在秒级定位：

| Bug | 本应存在的测试 | 定位时间对比 |
|-----|---------------|-------------|
| WEA 移位截断 | TLB fill 写入正确 way 验证 | 秒级 vs 小时级 |
| stale paddr 污染 | MMU ready 门控验证 | 秒级 vs 小时级 |
| bare 模式误报 miss | bare 模式 (satp=0) 专项 | 秒级 vs 小时级 |
| MMIO 未等 mmu_ready | CLINT 读偏移专项 | 秒级 vs 小时级 |

---

## 2. 体系架构

### 2.1 总体架构

```
┌─────────────────────────────────────────────────────┐
│                   测试程序体系                        │
├─────────────┬─────────────┬─────────────┬───────────┤
│  测试框架    │  测试程序    │  Testbench  │  构建/回归  │
│  framework   │  programs   │  templates  │  infra    │
├─────────────┼─────────────┼─────────────┼───────────┤
│ • 自检协议   │ • ISA       │ • 公共包含   │ • Makefile │
│ • 陷阱模板   │ • Exception │ • 参数化    │ • rv2coe   │
│ • 页表工具   │ • Privilege │ • 结果解析   │ • 回归脚本 │
│ • 结果报告   │ • MMU/TLB   │             │ • 覆盖追踪 │
│             │ • Cache     │             │           │
│             │ • MMIO      │             │           │
│             │ • Stress    │             │           │
└─────────────┴─────────────┴─────────────┴───────────┘
```

### 2.2 自检协议

**核心原则**：每个子测试独立执行、独立报告，失败时精确标识。

#### 寄存器约定

| 寄存器 | 用途 | 初始值 |
|--------|------|--------|
| `x28` | pass_count | 0 |
| `x29` | total_count | 0 |
| `x30` | first_fail_id (0=全过) | 0 |
| `x31` | 当前 test_id (1-based) | 0 |

#### 内存结果区

固定地址 `0x80001000`（SRAM 区域，非 MMIO）：

| 偏移 | 内容 | 说明 |
|------|------|------|
| +0 | total_count | 总测试数 |
| +4 | pass_count | 通过数 |
| +8 | first_fail_id | 首个失败 ID |
| +12 | first_fail_pc | 首个失败时的 PC |
| +16 | test_1_result | 1=PASS, 0=FAIL |
| +20 | test_2_result | ... |
| +4*(N+4) | test_N_result | 最多 240 个子测试 (1KB) |

#### 子测试编写模式

```asm
# ── 子测试模板 ──
# 每个 subtest 是一个函数：返回时 x10=1(pass) 或 0(fail)
# 子测试内部可自由使用 x10-x17 (caller-saved)，不污染 x28-x31

test_01_add:
    li   x10, 5
    li   x11, 7
    add  x12, x10, x11
    li   x13, 12
    li   x10, 1           # 假设 PASS
    beq  x12, x13, .L1
    li   x10, 0           # FAIL
.L1: ret
```

#### 测试运行器

```asm
# test_run: 运行一个子测试并记录结果
# 输入: x11 = 测试函数地址
# 使用: x28-x31 (框架寄存器), x12-x17 (临时)
test_run:
    addi x29, x29, 1          # total_count++
    addi x31, x31, 1          # test_id++
    add  x12, x31, x0         # 保存当前 test_id

    jalr x13, x11, 0          # 调用子测试, 结果在 x10

    # 写入结果区: offset = (test_id + 3) * 4 + 0x80001000
    lui  x14, 0x80001
    addi x15, x12, 3
    slli x15, x15, 2
    add  x14, x14, x15
    sw   x10, 0(x14)          # 存 1(PASS) 或 0(FAIL)

    # 更新 pass_count
    li   x15, 1
    beq  x10, x15, _tr_pass
    j    _tr_done
_tr_pass:
    addi x28, x28, 1
_tr_done:
    # 记录首个失败
    bnez x30, _tr_ret         # 已有失败记录
    bnez x10, _tr_ret         # 本次通过
    add  x30, x12, x0         # first_fail_id = test_id
_tr_ret:
    jr   x13                  # 返回 (x13 保存了返回地址)
```

#### Testbench 端结果解析

```systemverilog
// 读取结果区并逐项报告
task read_test_results;
    integer i, result, total, passed;
    begin
        // 读 total_count 和 pass_count (通过 SRAM 总线读取)
        // 逐项报告每个子测试结果
        for (i = 1; i <= total; i = i + 1) begin
            // result = mem[0x80001000 + (i+3)*4]
            if (result == 1)
                $display("  TEST[%0d]: PASS", i);
            else
                $display("  TEST[%0d]: FAIL <<<", i);
        end
    end
endtask
```

> **注意**：SRAM 内部为 BRAM IP，testbench 无法直接读取。替代方案：
> 1. **寄存器检查**：testbench 检查 x28==x29（全过）和 x30==0（无首败）
> 2. **UART 输出**：测试程序通过 UART 打印每个子测试结果（需 UART 驱动）
> 3. **GPIO 输出**：用 GPIO 引脚传递结果（适合硬件测试）
>
> **推荐**：仿真用方案 1（寄存器检查），硬件用方案 2/3。

### 2.3 目录结构

```
dev/program_source/
├── framework/                    # 测试框架
│   ├── test_framework.s          # 自检运行器 + 结果报告
│   ├── trap_handlers.s           # 通用陷阱处理器模板
│   └── page_table_utils.s       # 页表构建工具函数
├── test/                         # 测试程序
│   ├── tests.yaml                #   ★ 测试注册表 (声明式定义)
│   ├── isa/                      #   ISA 指令测试
│   │   ├── alu.s                 #     ALU 运算 (add/sub/sll/slt/...)
│   │   ├── branch.s              #     分支 (beq/bne/blt/bge/...)
│   │   ├── memory.s              #     访存 (lb/lh/lw/sb/sh/sw + 对齐)
│   │   ├── upper_imm.s           #     上立即数 (lui/auipc)
│   │   ├── jump.s                #     跳转 (jal/jalr)
│   │   ├── csr.s                 #     CSR 读写 (csrrw/csrrs/csrrc + *i)
│   │   └── m_ext.s               #     M 扩展 (mul/mulh/div/rem/...)
│   ├── exception/                #   异常/中断测试
│   │   ├── ecall.s               #     ECALL (M/S/U 各级)
│   │   ├── ebreak.s              #     EBREAK
│   │   ├── illegal_inst.s        #     非法指令
│   │   ├── access_fault.s        #     访问错误 (load/store/fetch)
│   │   ├── timer_irq.s           #     定时器中断
│   │   └── interrupt_basic.s     #     中断基本 (MIE/MSTATUS 配置)
│   ├── privilege/                #   特权级测试
│   │   ├── priv_transition.s     #     M↔S↔U 切换 (mret/sret)
│   │   ├── delegation.s          #     异常/中断委托 (medeleg/mideleg)
│   │   └── csr_access_priv.s     #     CSR 特权访问控制
│   ├── mmu/                      #   MMU/TLB 测试 ★ 当前重点
│   │   ├── tlb_basic.s           #     TLB 填充/命中/缺失
│   │   ├── tlb_replace.s         #     TLB 替换 (tree-PLRU 受害路选择)
│   │   ├── tlb_flush.s           #     SFENCE.VMA (全刷/ASID 刷)
│   │   ├── tlb_asid.s            #     ASID 匹配 + 全局页 (G 位)
│   │   ├── tlb_megapage.s        #     Megapage 翻译
│   │   ├── tlb_stress.s          #     TLB 压力 (超过 16 项的页切换)
│   │   ├── ptw_walk.s            #     页表漫游 (2 级, 无效 PTE, 未对齐)
│   │   ├── page_fault.s          #     页错误 (fetch/load/store PF)
│   │   ├── permission.s          #     权限检查 (R/W/X/U, SUM, MXR)
│   │   ├── sv32_basic.s          #     Sv32 基本翻译
│   │   ├── sv32_edge.s           #     Sv32 边角 (跨页边界, 零页, etc.)
│   │   └── unified_mmu.s         #     统一 MMU 并发访问 ★ Phase 3
│   ├── cache/                    #   Cache 测试
│   │   ├── icache_basic.s        #     I$ 命中/缺失/驱逐
│   │   ├── dcache_basic.s        #     D$ 命中/缺失/驱逐
│   │   ├── dcache_dirty.s        #     D$ 脏行写回
│   │   ├── fencei.s              #     FENCE.I 行为
│   │   └── cache_mmu_interact.s  #     Cache+MMU 交互
│   ├── mmio/                     #   MMIO 测试
│   │   ├── clint.s               #     CLINT (mtime/mtimecmp/msip)
│   │   └── plic.s                #     PLIC (中断优先级/阈值)
│   ├── regression/               #   回归测试 (防 Phase 2 bug 回退)
│   │   ├── reg_tlb_fill_way.s    #     Bug 1: TLB fill 写入正确 way
│   │   ├── reg_ptw_fault_latch.s #     Bug 2: PTW 页错误锁存
│   │   ├── reg_sfence_during_walk.s # Bug 3: SFENCE 期间 PTW
│   │   ├── reg_stale_paddr.s     #     Bug 8: stale paddr 不污染 data BRAM
│   │   ├── reg_bare_no_miss.s    #     Bug 9: bare 模式不产生 TLB miss
│   │   ├── reg_mmio_ready.s      #     Bug 10: MMIO 等待 mmu_ready
│   │   └── reg_pf_latch.s        #     Bug 11: 页错误锁存门控
│   ├── integration/              #   集成测试 (保留现有)
│   │   ├── cpu_full.s            #     全功能集成 (= 现有 cpu_test.s)
│   │   ├── cpu_compute.s         #     计算集成 (= 现有 cpu_test_compute.s)
│   │   └── cpu_trap.s            #     陷阱集成 (= 现有 cpu_test_trap.s)
│   └── [Makefile]                #   ❌ 废弃 (由 test_builder.py 替代)
├── app/                          # 应用程序 (不变)
├── lib/                          # 库 (不变)
├── link.ld                       # 链接脚本 (保留, 页表对齐需要)
├── link_harvard.ld               # Harvard 链接脚本 (保留)
└── [Makefile]                    # ❌ 废弃 (由 test_builder.py 替代)
                                    [verilog_to_words.py] ❌ 废弃 (由 rv2coe --hex 替代)

tools/
├── rv2coe.py                     # 编译器 (已有, WSL 回退)
├── test_builder.py               # ★ 测试构建管理 (新增)
├── run_regression.py             # ★ 回归运行器 (新增)
├── vivado_core/
│   ├── hash.py                   # ★ 需新增 src 层
│   ├── sync.py                   # ★ 需新增 src stale 自动重编译逻辑
│   └── ...
└── ...
```

---

## 3. 测试覆盖矩阵

### 3.1 ISA 指令覆盖

| 类别 | 指令 | 测试文件 | 子测试数 | 覆盖点 |
|------|------|----------|----------|--------|
| ALU-R | add, sub, sll, slt, sltu, xor, srl, sra, or, and | `isa/alu.s` | 20+ | 正/负/零/边界 |
| ALU-I | addi, slti, sltiu, xori, ori, andi, slli, srli, srai | `isa/alu.s` | 20+ | 正/负/零/最大移位 |
| 上立即数 | lui, auipc | `isa/upper_imm.s` | 6 | 全1/全0/典型值 |
| 跳转 | jal, jalr | `isa/jump.s` | 8 | 正向/反向/0偏移/链接寄存器 |
| 分支 | beq, bne, blt, bge, bltu, bgeu | `isa/branch.s` | 18 | taken/not-taken/相等/正负比较 |
| Load | lb, lh, lw, lbu, lhu | `isa/memory.s` | 15 | 对齐/非对齐/符号扩展/跨半字 |
| Store | sb, sh, sw | `isa/memory.s` | 12 | 对齐/非对齐/覆盖/部分写 |
| CSR | csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci | `isa/csr.s` | 18 | 读写/置位/清位/立即数 |
| M扩展 | mul, mulh, mulhsu, mulhu, div, divu, rem, remu | `isa/m_ext.s` | 16 | 正/负/零/溢出/除零 |
| 系统 | ecall, ebreak, mret, sret, sfence.vma | (在 exception/privilege/) | — | — |
| 缓存 | fence.i | `cache/fencei.s` | 6 | I$无效化+JIT |

### 3.2 特权架构覆盖

| 场景 | 测试文件 | 子测试数 | 关键验证 |
|------|----------|----------|----------|
| M→S 切换 (mret) | `privilege/priv_transition.s` | 4 | mstatus.MPP, mepc, 特权变更 |
| S→U 切换 (sret) | `privilege/priv_transition.s` | 4 | sstatus.SPP, sepc, 特权变更 |
| U→S trap (ecall) | `privilege/priv_transition.s` | 3 | scause=8, sepc, 特权提升 |
| S→M trap (ecall) | `privilege/priv_transition.s` | 3 | mcause=9, mepc, 特权提升 |
| 异常委托 | `privilege/delegation.s` | 6 | medeleg/mideleg, trap 入 S 非 M |
| CSR 特权访问 | `privilege/csr_access_priv.s` | 4 | U 读 S-CSR → 异常, S 写 M-CSR → 异常 |

### 3.3 MMU/TLB 覆盖 ★

| 场景 | 测试文件 | 子测试数 | 关键验证 | 对应 NMMU 阶段 |
|------|----------|----------|----------|----------------|
| TLB 填充 (首次访问) | `mmu/tlb_basic.s` | 4 | fill 后 hit, PPN 正确 | Phase 2 |
| TLB 命中 (重复访问) | `mmu/tlb_basic.s` | 4 | 连续访问同页, 无额外 walk | Phase 2 |
| TLB 缺失 (新页) | `mmu/tlb_basic.s` | 4 | miss → PTW → fill → hit | Phase 2 |
| tree-PLRU 替换 | `mmu/tlb_replace.s` | 6 | 4-way 全满后替换正确路 | Phase 2 |
| SFENCE.VMA 全刷 | `mmu/tlb_flush.s` | 4 | 刷后全部 miss, 重新 fill | Phase 2 |
| SFENCE.VMA + ASID | `mmu/tlb_flush.s` | 4 | 仅刷匹配 ASID, 全局页保留 | Phase 2 |
| ASID 匹配 | `mmu/tlb_asid.s` | 4 | 不同 ASID 不命中, 同 ASID 命中 | Phase 2 |
| 全局页 (G=1) | `mmu/tlb_asid.s` | 4 | G=1 忽略 ASID, 所有进程命中 | Phase 2 |
| Megapage 翻译 | `mmu/tlb_megapage.s` | 4 | VPN[9:0] 为页偏移, 仅比较 VPN[19:10] | Phase 2 |
| TLB 压力 (>16 页) | `mmu/tlb_stress.s` | 6 | 循环访问 20+ 页, 验证替换正确 | Phase 2 |
| 2 级页表漫游 | `mmu/ptw_walk.s` | 4 | L1→L0→PTE, 正确 PPN | Phase 2 |
| 无效 PTE (V=0) | `mmu/ptw_walk.s` | 4 | walk 遇无效 PTE → page fault | Phase 2 |
| Fetch 页错误 | `mmu/page_fault.s` | 4 | X=0 → fetch PF, mcause=12 | Phase 2 |
| Load 页错误 | `mmu/page_fault.s` | 4 | R=0 → load PF, mcause=13 | Phase 2 |
| Store 页错误 | `mmu/page_fault.s` | 4 | W=0 → store PF, mcause=15 | Phase 2 |
| U 访问 S 页 | `mmu/permission.s` | 4 | U=0 + S-mode → PF (除非 SUM=1) | Phase 2 |
| SUM 位 | `mmu/permission.s` | 4 | mstatus.SUM=1 → S 可访 U 页 | Phase 2 |
| MXR 位 | `mmu/permission.s` | 4 | mstatus.MXR=1 → load 可读 X 页 | Phase 2 |
| Sv32 基本翻译 | `mmu/sv32_basic.s` | 6 | VPN→PPN, 偏移保留, 对齐 | Phase 2 |
| Sv32 边角 | `mmu/sv32_edge.s` | 6 | 零页/全1页/跨页边界/对齐错 | Phase 2 |
| **统一 MMU 并发 i/d 查找** | `mmu/unified_mmu.s` | 6 | 同一 TLB 同时服务 i+d | **Phase 3** |
| **统一 MMU 并发 miss** | `mmu/unified_mmu.s` | 6 | i-miss + d-miss, d 优先 | **Phase 3** |
| **统一 MMU PTW 仲裁** | `mmu/unified_mmu.s` | 4 | PTW fill 暂停 d-lookup | **Phase 3** |
| **统一 MMU miss 排队** | `mmu/unified_mmu.s` | 4 | d-walk 中 i-miss 排队, 完成后处理 | **Phase 3** |

### 3.4 Cache 覆盖

| 场景 | 测试文件 | 子测试数 | 关键验证 |
|------|----------|----------|----------|
| I$ 命中 | `cache/icache_basic.s` | 4 | 重复取指命中, 无 refill |
| I$ 缺失+refill | `cache/icache_basic.s` | 4 | 新 set 访问触发 refill |
| I$ 驱逐 (8 set 填满) | `cache/icache_basic.s` | 4 | 9th set 驱逐 PLRU 路 |
| D$ load 命中 | `cache/dcache_basic.s` | 4 | 重复 load 命中 |
| D$ store 命中 | `cache/dcache_basic.s` | 4 | store 后 load 同地址 |
| D$ 缺失+refill | `cache/dcache_basic.s` | 4 | 新 set 触发 refill |
| D$ 脏行写回 | `cache/dcache_dirty.s` | 6 | store→evict→refill→验证写回 |
| FENCE.I | `cache/fencei.s` | 6 | I$ 全无效化, JIT 自修改 |
| Cache+MMU 交互 | `cache/cache_mmu_interact.s` | 6 | TLB miss 时 cache 暂停, TLB fill 后继续 |

### 3.5 回归测试覆盖 (防 Phase 2 bug 回退)

| Bug | 回归测试 | 验证 |
|-----|----------|------|
| #1 WEA 移位截断 | `regression/reg_tlb_fill_way.s` | TLB fill 写入后读回验证 PPN+权限 |
| #2 PTW fault 未锁存 | `regression/reg_ptw_fault_latch.s` | PTW walk 遇无效 PTE → 正确 cause+vaddr |
| #3 SFENCE 期间 PTW | `regression/reg_sfence_during_walk.s` | sfence.vma 不死锁, walk 可被中断 |
| #8 stale paddr 污染 | `regression/reg_stale_paddr.s` | mmu_ready=0 时不写 data BRAM |
| #9 bare 模式 miss | `regression/reg_bare_no_miss.s` | satp=0 → 直通, 无 TLB miss |
| #10 MMIO 未等 ready | `regression/reg_mmio_ready.s` | CLINT 读在 mmu_ready 后, 偏移正确 |
| #11 PF 锁存门控 | `regression/reg_pf_latch.s` | input_changed 时不锁存 stale PF |

---

## 4. 测试框架详细设计

### 4.1 framework/test_framework.s

```asm
# ============================================================
# test_framework.s — 自检测试框架
# ============================================================
# 寄存器约定:
#   x28 = pass_count
#   x29 = total_count
#   x30 = first_fail_id (0 = all pass)
#   x31 = current_test_id (1-based)
#
# 结果区: 0x80001000
#   +0:  total_count
#   +4:  pass_count
#   +8:  first_fail_id
#   +12: reserved
#   +16: test_1_result (1=PASS, 0=FAIL)
#   +20: test_2_result
#   ...

.equ TEST_RESULT_BASE, 0x80001000

.section .text

# ── test_init: 初始化框架 ──
.globl test_init
test_init:
    li   x28, 0
    li   x29, 0
    li   x30, 0
    li   x31, 0
    # 清零结果区 (前 16 字节)
    lui  x10, 0x80001
    sw   x0, 0(x10)
    sw   x0, 4(x10)
    sw   x0, 8(x10)
    sw   x0, 12(x10)
    ret

# ── test_run: 运行一个子测试 ──
# 输入: x11 = 测试函数地址
# 子测试返回: x10 = 1 (PASS) 或 0 (FAIL)
# 保存: x12-x17 (临时), x28-x31 (框架)
.globl test_run
test_run:
    addi x29, x29, 1          # total_count++
    addi x31, x31, 1          # test_id++
    add  x12, x31, x0         # 保存 test_id

    # 调用子测试
    add  x13, x1, x0          # 保存 ra
    jalr x1, x11, 0           # 调用, 结果在 x10

    # 写结果区: addr = TEST_RESULT_BASE + (test_id + 3) * 4
    lui  x14, 0x80001
    addi x15, x12, 3
    slli x15, x15, 2
    add  x14, x14, x15
    sw   x10, 0(x14)

    # 更新 pass_count
    li   x15, 1
    beq  x10, x15, _tr_pass
    j    _tr_check_first_fail
_tr_pass:
    addi x28, x28, 1
_tr_check_first_fail:
    bnez x30, _tr_ret         # 已记录首个失败
    bnez x10, _tr_ret         # 本次通过
    add  x30, x12, x0         # first_fail_id = test_id
_tr_ret:
    add  x1, x13, x0          # 恢复 ra
    ret

# ── test_report: 写汇总到结果区 ──
.globl test_report
test_report:
    lui  x10, 0x80001
    sw   x29, 0(x10)          # total_count
    sw   x28, 4(x10)          # pass_count
    sw   x30, 8(x10)          # first_fail_id
    ret
```

### 4.2 framework/trap_handlers.s

```asm
# ============================================================
# trap_handlers.s — 通用陷阱处理器
# ============================================================

# ── M-mode 陷阱处理器 (简单递增 mepc+4 并 mret) ──
.globl m_trap_handler_simple
m_trap_handler_simple:
    csrr x10, mepc
    addi x10, x10, 4
    csrw mepc, x10
    mret

# ── M-mode 陷阱处理器 (记录 cause 到 x19, epc 到 x20) ──
.globl m_trap_handler_record
m_trap_handler_record:
    csrr x19, mcause
    csrr x20, mepc
    addi x20, x20, 4
    csrw mepc, x20
    mret

# ── S-mode 陷阱处理器 (简单递增 sepc+4 并 sret) ──
.globl s_trap_handler_simple
s_trap_handler_simple:
    csrr x10, sepc
    addi x10, x10, 4
    csrw sepc, x10
    sret
```

### 4.3 framework/page_table_utils.s

```asm
# ============================================================
# page_table_utils.s — 页表构建工具
# ============================================================
# 提供: setup_identity_map, setup_user_map 等函数
# 输入: x15 = L1 表基址, x16 = L0 表基址
# 约定: 页表放在 .balign 4096 区域

.equ PTE_V, 0x001
.equ PTE_R, 0x002
.equ PTE_W, 0x004
.equ PTE_X, 0x008
.equ PTE_U, 0x010
.equ PTE_G, 0x020
.equ PTE_A, 0x040
.equ PTE_D, 0x080

# ── setup_identity_map: 恒等映射 0x80000000 ──
# L1[0] → L0, L0[0-3] → 0x80000000-0x80003FFF (RWX, supervisor)
.globl setup_identity_map
setup_identity_map:
    # L1[2] = (L0_base >> 12) << 10 | V
    la   x15, l1_page_table
    la   x16, l0_page_table
    srli x17, x16, 12
    slli x17, x17, 10
    ori  x17, x17, PTE_V
    sw   x17, 8(x15)            # L1[2] (VPN=2 → 0x80000000)

    # L0[0-3] = identity map, RWXAD
    li   x17, 0x80000           # PPN = 0x80000
    srli x17, x17, 12
    slli x17, x17, 10
    li   x18, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
    or   x17, x17, x18
    sw   x17, 0(x16)            # L0[0]
    addi x17, x17, 0x400        # next PPN
    sw   x17, 4(x16)            # L0[1]
    addi x17, x17, 0x400
    sw   x17, 8(x16)            # L0[2]
    addi x17, x17, 0x400
    sw   x17, 12(x16)           # L0[3]
    ret

# 页表数据区 (需 .balign 4096)
.balign 4096
l1_page_table:
    .fill 1024, 4, 0
.balign 4096
l0_page_table:
    .fill 1024, 4, 0
```

### 4.4 Testbench 公共包含

```systemverilog
// tb_common.svh — 公共 testbench 基础设施
// 使用: `include "tb_common.svh" 在 testbench 顶部

// 时钟生成
task auto_clock;
    input reg clk;
    begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
endtask

// 寄存器检查 (带 PASS/FAIL 计数)
task check_reg;
    input [4:0]  addr;
    input [31:0] expected;
    inout  integer pass_count;
    inout  integer fail_count;
    ref    [4:0]  rf_addr;
    ref    [31:0] rf_data;
    begin
        rf_addr = addr;
        #1;
        if (rf_data === expected) begin
            pass_count = pass_count + 1;
            $display("  PASS x%0d = 0x%08h", addr, rf_data);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL x%0d expected=0x%08h got=0x%08h", addr, expected, rf_data);
        end
    end
endtask

// 测试框架结果检查
task check_test_framework;
    input  [31:0] pass_count_val;   // x28
    input  [31:0] total_count_val;  // x29
    input  [31:0] first_fail_id;    // x30
    inout  integer pass_count;
    inout  integer fail_count;
    begin
        if (first_fail_id == 0 && pass_count_val == total_count_val) begin
            pass_count = pass_count + 1;
            $display("  PASS framework: %0d/%0d tests", pass_count_val, total_count_val);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL framework: first_fail_id=%0d, %0d/%0d passed",
                     first_fail_id, pass_count_val, total_count_val);
        end
    end
endtask

// 汇总报告
task test_summary;
    input string  test_name;
    input integer pass_count;
    input integer fail_count;
    begin
        $display("========================================");
        $display("%s test summary", test_name);
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
    end
endtask
```

---

## 5. 构建系统

### 5.1 环境约束

| 约束 | 说明 |
|------|------|
| **Windows 无 make** | 开发环境为 Windows，无 GNU Make |
| **工具链在 WSL** | `riscv64-unknown-elf-gcc/ld/objcopy` 仅在 WSL 中可用 |
| **rv2coe 已有 WSL 回退** | `rv2coe.py` 检测到工具不在 PATH 时自动通过 `wsl` 调用 |
| **rv2coe 支持多文件** | `-i` 可多次指定，自动编译每个源文件为 `.o` 后用 `ld` 链接 |

### 5.2 构建方案：Python 构建脚本 (`tools/test_builder.py`)

**不使用 Makefile**。改用 Python 脚本统一管理构建，直接调用 `rv2coe.py`。

#### 为什么不用 Makefile / WSL make

| 方案 | 问题 |
|------|------|
| Windows Makefile | Windows 无 make，需安装 MSYS2/MinGW make |
| WSL make | 路径映射复杂（`/mnt/e/` ↔ `E:\`），rv2coe 已封装 WSL 调用，重复封装增加维护 |
| Python 脚本 + rv2coe | ✅ 跨平台，rv2coe 已处理 WSL 回退，路径全用 Python Path 处理 |

#### 构建脚本设计

```python
#!/usr/bin/env python3
"""test_builder.py — 测试程序构建管理

用法:
    python tools/test_builder.py              # 构建全部
    python tools/test_builder.py --category mmu  # 仅构建 MMU 测试
    python tools/test_builder.py --test isa/alu  # 构建单个测试
    python tools/test_builder.py --clean       # 清理产物
    python tools/test_builder.py --list        # 列出所有测试
    python tools/test_builder.py --dry-run     # 仅打印命令不执行
"""

# 核心逻辑:
# 1. 扫描 test/ 目录下的 .s 文件，按子目录分类
# 2. 对每个测试，自动拼接 framework 文件 + 测试文件
# 3. 调用 rv2coe.py 编译为 .hex + .coe
# 4. 产物放在源文件同目录 (test/isa/alu.hex, test/isa/alu.coe)
```

#### 测试注册表 (`dev/program_source/test/tests.yaml`)

用 YAML 声明式定义所有测试，替代 Makefile 的变量列表：

```yaml
# 测试程序注册表
# 每个条目定义: 源文件、依赖的框架文件、链接脚本、架构、产物路径

framework:
  common:
    - framework/test_framework.s
    - framework/trap_handlers.s
  mmu_extra:              # MMU 测试额外需要页表工具
    - framework/page_table_utils.s

defaults:
  arch: rv32im_zicsr_zifencei
  abi: ilp32
  linker_script: link.ld
  depth: 8192

categories:
  isa:
    tests:
      - isa/alu
      - isa/branch
      - isa/memory
      - isa/upper_imm
      - isa/jump
      - isa/csr
      - isa/m_ext

  exception:
    tests:
      - exception/ecall
      - exception/ebreak
      - exception/illegal_inst
      - exception/access_fault
      - exception/timer_irq
      - exception/interrupt_basic

  privilege:
    tests:
      - privilege/priv_transition
      - privilege/delegation
      - privilege/csr_access_priv

  mmu:
    framework: common+mmu_extra    # 追加页表工具
    tests:
      - mmu/tlb_basic
      - mmu/tlb_replace
      - mmu/tlb_flush
      - mmu/tlb_asid
      - mmu/tlb_megapage
      - mmu/tlb_stress
      - mmu/ptw_walk
      - mmu/page_fault
      - mmu/permission
      - mmu/sv32_basic
      - mmu/sv32_edge
      - mmu/unified_mmu

  cache:
    tests:
      - cache/icache_basic
      - cache/dcache_basic
      - cache/dcache_dirty
      - cache/fencei
      - cache/cache_mmu_interact

  mmio:
    tests:
      - mmio/clint
      - mmio/plic

  regression:
    tests:
      - regression/reg_tlb_fill_way
      - regression/reg_ptw_fault_latch
      - regression/reg_sfence_during_walk
      - regression/reg_stale_paddr
      - regression/reg_bare_no_miss
      - regression/reg_mmio_ready
      - regression/reg_pf_latch

  integration:
    framework: []                  # 集成测试不用框架 (保持原有结构)
    tests:
      - integration/cpu_full
      - integration/cpu_compute
      - integration/cpu_trap
```

#### 构建流程

```
test_builder.py --test isa/alu
  │
  ├─ 读取 tests.yaml，解析 isa/alu 的配置
  ├─ 确定输入文件:
  │    - framework/test_framework.s
  │    - framework/trap_handlers.s
  │    - test/isa/alu.s
  ├─ 确定输出文件:
  │    - test/isa/alu.hex
  │    - test/isa/alu.coe
  ├─ 调用 rv2coe.py:
  │    python tools/rv2coe.py
  │      -i dev/program_source/framework/test_framework.s
  │      -i dev/program_source/framework/trap_handlers.s
  │      -i dev/program_source/test/isa/alu.s
  │      --linker-script dev/program_source/link.ld
  │      --march rv32im_zicsr_zifencei --abi ilp32
  │      --hex dev/program_source/test/isa/alu.hex
  │      --coe dev/program_source/test/isa/alu.coe
  │      --depth 8192
  └─ rv2coe 内部: gcc -c 每个 .s → .o → ld -T link.ld → ELF → hex+coe
      (工具链不在 PATH 时自动通过 wsl 调用)
```

### 5.3 Vivado Orchestrator 集成

#### 问题：源码变更检测盲区

当前 `hash.py` 的 `coe` 层仅监控 `.coe/.hex` 产物文件：

```python
"coe": [
    "dev/program_source/test/**/*.coe",
    "dev/program_source/test/**/*.hex",
    "dev/program_source/app/**/*.coe",
    "dev/program_source/app/**/*.hex",
],
```

**如果 `.s` 源文件改了但 `.coe/.hex` 未重新生成，Orchestrator 不会检测到变更，仿真跑的是旧程序。**

#### 解决方案：新增 `src` 层

在 `hash.py` 的 `LayeredHash` 中新增 `src` 层，监控所有测试源文件：

```python
LAYERS: tuple[str, ...] = ("rtl", "tb", "src", "coe", "fpga")

HASH_GLOBS: dict[str, list[str]] = {
    "rtl": [...],
    "tb": [...],
    "src": [   # ★ 新增
        "dev/program_source/**/*.s",
        "dev/program_source/**/*.S",
        "dev/program_source/**/*.c",
        "dev/program_source/**/*.ld",
        "dev/program_source/test/tests.yaml",
        "tools/test_builder.py",
        "tools/rv2coe.py",
    ],
    "coe": [...],
    "fpga": [...],
}
```

#### 集成流程：src stale → 自动重编译 → coe refresh

在 `operations.py` 的仿真前检查中，增加 `src` 层处理逻辑：

```
操作前检查:
  rtl stale  → 硬错误, 必须全量刷新
  tb stale   → 软警告, 可增量刷新
  src stale  → ★ 自动调用 test_builder.py 重编译
               → 重编译后 coe 层自动更新
               → 继续检查 coe stale
  coe stale  → 增量刷新 coe 配置
  fpga stale → 重加约束
  全部 fresh → 直接执行
```

具体实现：在 `sync.py` 的同步策略中，`src` 层 stale 时自动触发：

```python
# sync.py 中的新增逻辑
if staleness.get("src", False):
    logger.info("Source files changed, rebuilding test programs...")
    subprocess.run(
        [sys.executable, "tools/test_builder.py"],
        cwd=str(base_dir),
        check=True,
    )
    # 重编译后重新计算 coe 层哈希
    current_hashes = layered_hash.compute_current()
    staleness["coe"] = (
        current_hashes.get("coe", "") != session_hashes.get("coe", "")
    )
```

#### tasks.yaml 扩展

新增测试任务自动注册到 `tasks.yaml`：

```yaml
# 由 test_builder.py --gen-tasks 自动生成
# 不要手动编辑此段 (标记为 AUTO-GENERATED)

tasks:
  # ... 现有任务 ...

  # === AUTO-GENERATED test tasks (begin) ===
  isa_alu:
    tb: tb_isa_alu
    coe: test/isa/alu.coe
    runtime: 5ms
  mmu_tlb_basic:
    tb: tb_mmu_tlb_basic
    coe: test/mmu/tlb_basic.coe
    runtime: 20ms
  # ... etc ...
  # === AUTO-GENERATED test tasks (end) ===
```

### 5.4 废弃文件

| 文件 | 状态 | 原因 | 替代 |
|------|------|------|------|
| `dev/program_source/Makefile` | ❌ 废弃 | 调用裸 `as/ld/objcopy`（WSL 工具），Windows 不可用；`verilog_to_words.py` 与 rv2coe 重复 | `tools/test_builder.py` |
| `dev/program_source/verilog_to_words.py` | ❌ 废弃 | 功能已被 rv2coe 的 `--hex` 输出完全覆盖 | rv2coe `--hex` |
| `dev/program_source/link.ld` | ✅ 保留 | 页表 `.balign 4096` 需要链接脚本控制段布局；rv2coe `--linker-script` 使用 | — |
| `dev/program_source/link_harvard.ld` | ✅ 保留 | Harvard 架构分离指令/数据输出时需要 | — |

### 5.5 回归脚本

```python
#!/usr/bin/env python3
"""run_regression.py — 全测试回归运行器

用法:
    python tools/run_regression.py                 # 全回归
    python tools/run_regression.py --category mmu  # 仅 MMU
    python tools/run_regression.py --verbose       # 详细输出
"""

# 流程:
# 1. 调用 test_builder.py 构建指定类别
# 2. 读取 tests.yaml 获取 testbench 映射
# 3. 对每个测试调用 Vivado Orchestrator 运行仿真
#    python -m tools.vivado_cli -task <task_name> -sim
# 4. 解析仿真输出，收集 pass/fail
# 5. 输出汇总报告 (JSON + 表格)
```

---

## 6. 实施计划

### Phase T1: 框架搭建 (1-2 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T1.1 | 编写 `framework/test_framework.s` | 自检运行器 |
| T1.2 | 编写 `framework/trap_handlers.s` | 陷阱处理器 |
| T1.3 | 编写 `framework/page_table_utils.s` | 页表工具 |
| T1.4 | 编写 `test/tests.yaml` 测试注册表 | 声明式测试定义 |
| T1.5 | 编写 `tools/test_builder.py` Python 构建脚本 | 构建系统 (替代 Makefile) |
| T1.6 | 验证构建: `test_builder.py --test isa/alu` 成功生成 .hex/.coe | 构建可用 |
| T1.7 | 验证框架: 编写 1 个简单测试 (isa/alu.s 片段) 并仿真通过 | 框架可用 |

### Phase T2: ISA 测试拆分 (2-3 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T2.1 | 从 `cpu_test.s` 拆出 `isa/alu.s` (ALU-R + ALU-I) | ~40 子测试 |
| T2.2 | 从 `cpu_test.s` 拆出 `isa/branch.s` | ~18 子测试 |
| T2.3 | 从 `cpu_test.s` 拆出 `isa/memory.s` | ~27 子测试 |
| T2.4 | 从 `cpu_test.s` 拆出 `isa/upper_imm.s` + `isa/jump.s` | ~14 子测试 |
| T2.5 | 从 `cpu_test.s` 拆出 `isa/csr.s` | ~18 子测试 |
| T2.6 | 从 `cpu_test_compute.s` 拆出 `isa/m_ext.s` | ~16 子测试 |
| T2.7 | 每个拆出测试独立仿真验证 | 全部 PASS |

### Phase T3: 异常/特权测试 (1-2 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T3.1 | 编写 `exception/ecall.s` | M/S/U ECALL |
| T3.2 | 编写 `exception/ebreak.s` + `exception/illegal_inst.s` | 基本异常 |
| T3.3 | 重构 `cpu_test_trap.s` → `exception/access_fault.s` + `exception/timer_irq.s` | 陷阱测试 |
| T3.4 | 重构 `cpu_test_priv.s` → `privilege/priv_transition.s` + `privilege/delegation.s` | 特权测试 |
| T3.5 | 仿真验证 | 全部 PASS |

### Phase T4: MMU/TLB 测试 ★ (3-4 天, 与 NMMU Phase 3 并行)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T4.1 | 编写 `mmu/tlb_basic.s` (fill/hit/miss) | 12 子测试 |
| T4.2 | 编写 `mmu/tlb_replace.s` (tree-PLRU) | 6 子测试 |
| T4.3 | 编写 `mmu/tlb_flush.s` (SFENCE.VMA) | 8 子测试 |
| T4.4 | 编写 `mmu/tlb_asid.s` + `mmu/tlb_megapage.s` | 8 子测试 |
| T4.5 | 编写 `mmu/ptw_walk.s` + `mmu/page_fault.s` | 8 子测试 |
| T4.6 | 编写 `mmu/permission.s` (R/W/X/U/SUM/MXR) | 12 子测试 |
| T4.7 | 编写 `mmu/sv32_basic.s` + `mmu/sv32_edge.s` | 12 子测试 |
| T4.8 | 编写 `mmu/tlb_stress.s` | 6 子测试 |
| T4.9 | 仿真验证 (Phase 2 已完成, 应全部 PASS) | 全部 PASS |

### Phase T5: Cache + MMIO 测试 (1-2 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T5.1 | 重构 `cpu_test_fencei.s` → `cache/fencei.s` + `cache/icache_basic.s` | Cache 测试 |
| T5.2 | 编写 `cache/dcache_basic.s` + `cache/dcache_dirty.s` | D$ 测试 |
| T5.3 | 编写 `cache/cache_mmu_interact.s` | 交互测试 |
| T5.4 | 编写 `mmio/clint.s` + `mmio/plic.s` | MMIO 测试 |
| T5.5 | 仿真验证 | 全部 PASS |

### Phase T6: 回归测试 (1-2 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T6.1 | 编写 7 个回归测试 (对应 Phase 2 的 7 类 bug) | 回归套件 |
| T6.2 | 仿真验证 (Phase 2 已修复, 应全部 PASS) | 全部 PASS |

### Phase T7: 统一 MMU 测试 ★ (2-3 天, NMMU Phase 3 完成后)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T7.1 | 编写 `mmu/unified_mmu.s` (并发 i/d 查找) | 6 子测试 |
| T7.2 | 添加并发 miss + PTW 仲裁测试 | 10 子测试 |
| T7.3 | 添加 miss 排队测试 | 4 子测试 |
| T7.4 | 仿真验证 (需 Phase 3 RTL 完成) | 全部 PASS |

### Phase T8: 文档 + 集成 + Orchestrator 对接 (2-3 天)

| 步骤 | 任务 | 产出 |
|------|------|------|
| T8.1 | 编写测试体系文档 `dev/docs/test-system.md` | 规范文档 |
| T8.2 | 编写回归脚本 `tools/run_regression.py` | 自动化 |
| T8.3 | 修改 `tools/vivado_core/hash.py`: 新增 `src` 层监控 `.s/.S/.c/.ld` | 源码变更检测 |
| T8.4 | 修改 `tools/vivado_core/sync.py`: `src` stale 时自动调用 `test_builder.py` | 自动重编译 |
| T8.5 | 扩展 `tasks.yaml`: `test_builder.py --gen-tasks` 自动生成测试任务 | Orchestrator 任务注册 |
| T8.6 | 废弃 `dev/program_source/Makefile` 和 `verilog_to_words.py` (标记或删除) | 清理 |
| T8.7 | 全回归验证 | 全部 PASS |

---

## 7. 测试程序编写规范

### 7.1 文件头

每个测试文件必须包含：

```asm
# ============================================================
# 文件名: mmu/tlb_basic.s
# 类别:   MMU/TLB
# 描述:   TLB 基本操作测试 (fill, hit, miss)
# 子测试: 12
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# 前置:   Sv32 页表已设置, satp 已配置
# ============================================================
```

### 7.2 子测试命名

- 每个子测试函数名格式: `test_XX_描述` (XX 为两位数字)
- 数字从 01 开始，连续编号
- 描述用下划线分隔，简明扼要

```asm
test_01_fill_first_access:    # 首次访问触发 TLB fill
test_02_hit_after_fill:       # fill 后再次访问命中
test_03_miss_different_page:  # 不同页访问触发 miss
...
```

### 7.3 子测试结构

```asm
test_01_fill_first_access:
    # ── Setup ──
    # 设置该测试特有的状态 (不影响其他测试)

    # ── Exercise ──
    # 执行被测操作

    # ── Verify ──
    # 检查结果, 设置 x10 = 1(PASS) 或 0(FAIL)
    li   x10, 1           # 假设 PASS
    beq  x_actual, x_expected, .Lpass
    li   x10, 0           # FAIL
.Lpass:
    ret
```

### 7.4 主程序结构

```asm
.section .text
.globl _start

_start:
    # ── 全局 Setup ──
    la   x10, m_trap_handler
    csrw mtvec, x10
    li   x10, 0x1888
    csrw mstatus, x10

    # ── 框架初始化 ──
    jal  ra, test_init

    # ── 页表设置 (MMU 测试需要) ──
    jal  ra, setup_identity_map
    fence.i

    # ── 运行子测试 ──
    la   x11, test_01_fill_first_access
    jal  ra, test_run
    la   x11, test_02_hit_after_fill
    jal  ra, test_run
    ...

    # ── 报告结果 ──
    jal  ra, test_report

    # ── 结束 ──
end_loop:
    j    end_loop
```

### 7.5 Testbench 规范

每个新 testbench 应：

1. 实例化 `core_top` + `ahb_lite_bus` + 外设 (与现有一致)
2. 使用 `check_reg` 检查框架寄存器:
   - `x28` (pass_count) == `x29` (total_count) → 全过
   - `x30` (first_fail_id) == 0 → 无失败
3. 打印调试信息: `x30` 非零时报告首个失败 ID
4. 仿真时间: 根据测试复杂度设置, MMU 测试通常需 200000-500000 周期

---

## 8. 调试辅助设计

### 8.1 失败快速定位

当测试失败时，诊断路径：

```
testbench 报告: FAIL x30=5 (first_fail_id=5)
  → 查看源码: test_05_xxx 是第 5 个子测试
  → 该子测试只有 5-10 行有效代码
  → 直接定位到出错指令
```

对比当前:
```
testbench 报告: FAIL x5 expected=0x00000007 got=0x00000008
  → x5 在 270 行代码中被多次写入
  → 不知哪次写入出错
  → 需波形排查
```

### 8.2 陷阱调试

MMU 测试中页错误/异常频繁发生。框架提供：

- `m_trap_handler_record`: 记录 mcause→x19, mepc→x20
- 子测试可检查 x19/x20 验证异常是否正确触发
- 若异常意外触发 (x19 非预期值)，子测试返回 FAIL

### 8.3 分层调试

| 层级 | 方法 | 适用场景 |
|------|------|----------|
| L1: 子测试 ID | first_fail_id 直接定位 | 大多数失败 |
| L2: 陷阱记录 | x19(mcause) + x20(mepc) | 异常相关失败 |
| L3: PC 追踪 | testbench 中打印 wb_pc/wb_inst | 时序/流水线问题 |
| L4: 波形 | Vivado XSim WDB | 硬件级问题 |

---

## 9. 风险与缓解

| 风险 | 影响 | 概率 | 缓解 |
|------|------|------|------|
| 框架寄存器 (x28-x31) 与测试代码冲突 | 子测试结果错误 | 中 | 子测试仅用 x10-x17 (caller-saved), 框架用 x28-x31 (callee-saved) |
| 页表布局冲突 (多个 MMU 测试共用页表) | 翻译错误 | 低 | 每个测试程序有独立页表区 (.balign 4096) |
| 多文件链接 (framework + test) 增加构建复杂度 | 构建失败 | 中 | rv2coe.py 已支持多文件 `-i` + `--linker-script`，test_builder.py 封装调用 |
| 仿真时间增加 (更多测试程序) | 回归时间长 | 低 | 按类别并行, ISA 测试快 (<50K 周期), MMU 测试慢 (<500K 周期) |
| BRAM IP 内部无法 testbench 直接读 | 结果区不可读 | 中 | 用寄存器检查 (x28/x29/x30) 替代内存读取 |
| 统一 MMU 测试需 Phase 3 RTL 完成 | T7 阻塞 | 高 | T4-T6 可先行, T7 在 Phase 3 后执行 |
| rv2coe WSL 回退路径映射问题 | 构建失败 | 低 | rv2coe 已有 `to_wsl_path()` 处理 Windows→WSL 路径转换，经过现有测试验证 |
| test_builder.py 与 rv2coe 版本耦合 | 构建脚本需同步更新 | 低 | test_builder.py 通过 subprocess 调用 rv2coe，接口稳定；tests.yaml 声明式配置 |
| hash.py src 层误报 stale (如 .s 注释改动) | 不必要的重编译 | 低 | 重编译代价低 (每个测试 <1s)，可接受；极端情况可 `--no-rebuild` 跳过 |

---

## 10. 与 NMMU 计划的衔接

| NMMU 阶段 | 需要的测试体系阶段 | 说明 |
|-----------|-------------------|------|
| Phase 1 ✅ | T1-T2 (ISA 拆分) | Phase 1 已完成, ISA 拆分提供回归保障 |
| Phase 2 ✅ | T4 (MMU 测试) + T6 (回归) | Phase 2 已完成, 新测试验证不回退 |
| Phase 3 ⬜ | T4 + T7 (统一 MMU) | **T7 需 Phase 3 RTL, 可并行开发 T4-T6** |
| Phase 4 ⬜ | T8 (全回归) | Phase 4 用完整测试套件做集成验证 |

**建议执行顺序**：T1 → T2 → T3 → T4 → T5 → T6 (可与 Phase 3 并行) → T7 (Phase 3 后) → T8

---

## 附录 A: 现有测试到新体系的映射

| 现有文件 | 新位置 | 变化 |
|----------|--------|------|
| `cpu_test.s` | `integration/cpu_full.s` (保留) + 拆分到 `isa/*.s` | 拆分为 6 个专项测试 |
| `cpu_test_compute.s` | `integration/cpu_compute.s` (保留) + 拆分到 `isa/m_ext.s` | M 扩展独立 |
| `cpu_test_trap.s` | `integration/cpu_trap.s` (保留) + 拆分到 `exception/*.s` | 异常独立 |
| `cpu_test_priv.s` | `privilege/priv_transition.s` + `privilege/delegation.s` | 按功能拆分 |
| `cpu_test_mmu.s` | `mmu/sv32_basic.s` | 扩展为完整 MMU 套件 |
| `cpu_test_fencei.s` | `cache/fencei.s` | 归入 Cache 类别 |
| `cpu_test_access_fault.s` | `exception/access_fault.s` | 归入 Exception 类别 |

> **注意**：现有集成测试 (`integration/`) 保留不动，作为全功能回归基线。新测试是增量，不替代现有。

## 附录 B: 预计子测试总数

| 类别 | 测试文件数 | 预计子测试数 |
|------|-----------|-------------|
| ISA | 7 | ~133 |
| Exception | 6 | ~40 |
| Privilege | 3 | ~24 |
| MMU/TLB | 11 | ~82 |
| Cache | 5 | ~34 |
| MMIO | 2 | ~12 |
| Regression | 7 | ~28 |
| Integration | 3 | (现有, 不计) |
| **合计** | **44** | **~353** |

对比当前: 7 个测试程序, 无子测试计数, 失败无法定位。
