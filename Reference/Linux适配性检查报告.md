# RISC-V RV32 CPU 启动 Linux 适配性检查报告

> 生成日期: 2026-06-14 | 参照文档: `dev/docs/simpleCPU-design-report.md` | 检查清单: `Reference/RISC-V RV32-CPU启动Linux的最小必要条件检查清单.md`
>
> 本报告基于设计文档与 RTL 代码扫描，逐项标注当前 CPU/SoC 是否满足 Linux 启动最低硬件条件。**不涉及代码修改，仅扫描与标注。**

---

## 标记说明

| 标记 | 含义 |
|------|------|
| ✅ | 已达标，有设计文档/测试证据支撑 |
| ⚠️ | 设计上可能达标，但缺少测试、存在风险、或部分实现 |
| ❌ | 未达标，Linux 暂时无法可靠启动 |
| N/A | 当前阶段不需要 |

---

## 1. CPU 指令集最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| RV32I 基础整数指令 | ✅ | 设计报告 §1.2 列出 40 条 RV32I 指令，ISA 测试（alu/branch/jump/memory/upper_imm）均通过 |
| M 扩展 | ✅ | 设计报告 §1.2 列出 8 条 M 指令，Booth 乘法器 + 非恢复余数除法器，m_ext ISA 测试通过 |
| **A 扩展** | **❌** | **硬性阻塞项。** `misa=0x40141120`（RV32IMFSU），bit0=0。RTL 中无 `OPCODE_AMO`（7'b0101111）译码、无 LR/SC reservation set、无 AMO 执行路径。任何 AMO 指令触发 illegal instruction 异常 |
| AMO 指令完整性 | ❌ | 全部 9 条 AMO（amoswap/amoadd/amoxor/amoand/amoor/amomin/amomax/amominu/amomaxu）均未实现 |
| LR/SC 语义 | ❌ | 无 reservation set 寄存器/逻辑（无 `lr_sc`、`resv`、`load_reserve` 信号） |
| `aq/rl` 位 | ❌ | 无 AMO 译码，aq/rl 编码视为非法指令 |
| Zicsr | ✅ | CSRRW/CSRRS/CSRRC + 立即数版本实现，CSR ISA 测试通过 |
| Zifencei | ✅ | fence.i 实现：dcache writeback + icache invalidate（设计报告 §5.17），fencei 测试通过 |
| `fence` | ✅ | 设计报告 §1.2 列出 FENCE 指令，作为有效屏障 |
| `wfi` | ✅ | 设计报告 §1.2 列出 WFI，译码为 NOP 类指令 |
| 非对齐访问 | ✅ | 硬件不支持非对齐，但产生精确异常（cause 4/6），`cpu_mem.sv` 检测对齐违规 |
| `misa` | ⚠️ | 值为 `0x40141120` = RV32IMFSU，**缺 A 位**。实现 A 扩展后需改为 `0x40141121` |

**最低建议 ISA 字符串**：当前为 `rv32imf_zicsr_zifencei`，Linux 要求 `rv32ima_zicsr_zifencei`。

---

## 2. 特权级最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| M-mode | ✅ | 复位后进入 M-mode，PC=0xFC00_0000 |
| S-mode | ✅ | 设计报告 §1.1 确认 M/S/U 三级特权模式 |
| U-mode | ✅ | 同上 |
| `mret` | ✅ | 设计报告 §4.1，恢复 MIE=MPIE，特权级恢复至 MPP |
| `sret` | ✅ | 设计报告 §4.1，恢复 SIE=SPIE，特权级恢复至 SPP |
| `ecall` | ✅ | cause 按 U/S/M 区分（8/9/11），ecall 异常测试通过 |
| `ebreak` | ✅ | cause=3，ebreak 异常测试通过 |
| 特权级非法访问检查 | ✅ | U-mode 不可访问 S/M CSR，S-mode 不可访问 M CSR，触发 illegal instruction |
| `mstatus` | ✅ | MPP/MPIE/MIE 字段实现，写掩码控制 |
| `sstatus` | ✅ | SPP/SPIE/SIE 为 mstatus 受限视图，SUM(bit18)/MXR(bit19) 已在 MMU 权限检查中使用 |
| `medeleg` | ✅ | 异常委托寄存器实现，delegation 测试通过 |
| `mideleg` | ✅ | 中断委托寄存器实现，`cpu_clint.sv` 使用 mideleg 判断委托 |
| `mtvec/stvec` | ✅ | Direct 模式支持（设计报告 §4.1），Vectored 未实现但非最低要求 |
| `mepc/sepc` | ✅ | 陷阱时保存 PC，返回时恢复 |
| `mcause/scause` | ✅ | 11 种异常 + 3 种中断 cause 编码正确 |
| `mtval/stval` | ✅ | page fault 保存 fault VA，非法指令保存指令编码，对齐异常保存地址 |
| `mscratch/sscratch` | ✅ | 可读写 CSR 实现 |

---

## 3. MMU / Sv32 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| Sv32 | ✅ | 二级页表实现，`MMU.sv` + `ptw.sv`，sv32_basic/edge/ptw_walk 测试通过 |
| `satp` | ✅ | MODE/ASID/PPN 字段实现，satp.MODE=0 关闭翻译 |
| MMU 开关 | ✅ | satp.MODE=0 时直通，=1 时启用 Sv32 |
| 虚拟地址翻译 | ✅ | PTW 两级页表漫游，TLB 缓存翻译结果 |
| 4KB page | ✅ | Sv32 L0 页表支持 4KB 普通页 |
| megapage | ✅ | L1 叶节点为 4MB megapage，PTW 支持，tlb_megapage 测试通过 |
| PTE 格式 | ✅ | V/R/W/X/U/G/A/D/RSW/PPN 字段解析正确 |
| leaf PTE 判断 | ✅ | PTW 检查 R/W/X 是否全零判断叶/非叶节点 |
| 权限检查 | ✅ | R/W/X/U + SUM/MXR 检查实现（`MMU.sv` + `ptw.sv`） |
| page fault | ✅ | cause 12/13/15 正确，page_fault 测试通过 |
| `stval` | ✅ | page fault 时保存 fault virtual address |
| A/D 位处理 | ✅ | **硬件自动管理**：PTW 写回 PTE 置 A=1/D=1（设计报告 §5.17） |
| `sfence.vma` | ✅ | 刷新两个 TLB 全部项（S_FLUSH 状态机），sfence_during_walk 回归测试通过 |
| TLB | ✅ | 4路×4组=16项，BRAM 存储，ASID 感知，Tree-PLRU 替换，tlb_basic/flush/asid 测试通过 |
| ASID | ✅ | TLB 项存储 ASID，匹配时检查 ASID 一致或 G=1 |
| **MMIO 翻译策略** | **❌** | **硬性阻塞项。** `icache_ctrl.sv:64` / `dcache_ctrl.sv:80`: `wire is_mmio = ~cpu_req_vaddr[31] | cpu_req_vaddr[30];` — 基于虚拟地址判断 MMIO，而非物理地址。Linux 开启 Sv32 后，用户程序使用低虚拟地址会被误判为 MMIO |

**MMIO 判断问题详述**：

```
当前实现（错误）：
  is_mmio = ~vaddr[31] | vaddr[30]
  → 虚拟地址 0x00000000~0x3FFFFFFF 和 0x40000000~0x7FFFFFFF 被判为 MMIO
  → Linux 用户空间（低虚拟地址）所有访问被旁路 cache，走 MMIO 路径

正确做法：
  vaddr → MMU → paddr
  is_mmio = (paddr 在 MMIO 地址范围内)
  → 仅物理地址 0x00000000~0x1FFFFFFF (CLINT/PLIC/APB/SysStatus) 走 MMIO
  → 物理地址 0x80000000+ (DDR) 走 cache
```

---

## 4. Cache / 内存一致性最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| I-cache | ✅ | 4路组相联 1KB，VIPT，fencei 测试通过 |
| D-cache | ✅ | 4路组相联 1KB，写回+写分配，dcache_basic/dirty 测试通过 |
| cacheable 区域 | ✅ | DDR 区域走 cache |
| uncacheable/MMIO 区域 | ⚠️ | MMIO 旁路 cache 逻辑正确，但判断基于虚拟地址（见 §3 ❌） |
| **MMIO 判断** | **❌** | 基于虚拟地址（`vaddr[31]`/`vaddr[30]`），应基于物理地址。Linux 启动后用户空间访问被误路由 |
| 写回策略 | ✅ | D-cache 写回+写分配，脏行驱逐写回主存 |
| **页表一致性** | **⚠️** | PTW 绕过 dcache 直接访问 AXI 总线（`cpu_bus_bridge.sv` 有独立 `ptw_req` 路径）。当 dcache 为写回策略时，若 CPU 写 PTE 后数据仍在 dcache 脏行中未写回，PTW 会从主存读到旧 PTE |
| **PTW 访问路径** | **⚠️** | PTW 旁路 dcache → 可能读到旧页表。需 `sfence.vma` 时额外 writeback/flush dcache，或让 PTW 走 dcache coherent 路径 |
| **A/D 位写回** | **⚠️** | PTW 直接写 A/D 位到主存（旁路 dcache），若 dcache 中有该 PTE 的脏行副本，后续 dcache 写回会覆盖 PTW 的 A/D 位更新 |
| `sfence.vma` 语义 | ⚠️ | 仅刷 TLB，**未 flush/writeback dcache**。Linux 修改页表后需 `sfence.vma` + 额外缓存操作才能保证一致性 |
| `fence.i` 语义 | ✅ | dcache writeback + icache invalidate（设计报告 §5.17） |
| 总线顺序 | ✅ | AXI4 协议保序，MMIO 单拍传输 |

**PTW-dcache 一致性问题详述**：

```
场景：Linux 修改页表项
  1. CPU 执行 SW 写 PTE → 数据进入 dcache 脏行，未写回主存
  2. CPU 执行 SFENCE.VMA → 仅刷新 TLB，未 flush dcache
  3. 后续访存触发 TLB miss → PTW 从主存读 PTE → 读到旧值！
  4. 使用旧 PTE 翻译地址 → 可能产生错误 page fault 或访问错误物理页

修复方案（按复杂度排序）：
  A. sfence.vma 时 flush+writeback 整个 dcache（最简单，性能损失大）
  B. sfence.vma 时仅 writeback dcache（不 invalidate，保留有效数据）
  C. PTW 走 dcache coherent 路径（最正确，改动最大）
```

---

## 5. 异常与中断最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 同步异常 | ✅ | 11 种异常实现（illegal inst/ecall/ebreak/misaligned/access fault/page fault），cause 正确 |
| 异常优先级 | ⚠️ | 设计报告未明确多异常同时发生的优先级，但回归测试通过 |
| 中断入口 | ✅ | 保存 PC 和 cause，`hw_trap_is_enter` 门控防止误写 |
| 全局中断使能 | ✅ | `mstatus.MIE`/`sstatus.SIE` 行为正确 |
| 局部中断使能 | ✅ | `mie`/`sie` 寄存器实现 |
| pending 位 | ✅ | `mip`/`sip` 硬件写入 |
| 中断委托 | ✅ | `mideleg` 实现，`cpu_clint.sv` 判断委托 |
| 异常委托 | ✅ | `medeleg` 实现，delegation 测试通过 |
| 嵌套/屏蔽 | ✅ | trap 进入时 MIE→MPIE/SIE→SPIE，返回时恢复 |
| precise trap | ✅ | 异常 PC 指向正确指令，interrupt PC 保存当前指令 |

---

## 6. Timer / CLINT / Counter 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| `mtime` | ✅ | CLINT 实现 64-bit mtime（`r_mtime[63:0]`），单调递增 |
| `mtimecmp` | ✅ | 64-bit mtimecmp，`mtime>=mtimecmp` 触发 MTIP |
| timer 频率 | ✅ | `cpu_clk = 50MHz`，固定可知 |
| MTIP | ✅ | `mtime>=mtimecmp` 时 MTIP=1，timer_irq 测试通过 |
| STIP | **❌** | **见下方详述。** `mideleg[5]` 仅是委托开关，但 STIP（sip[5]）无硬件/软件置位路径，M-mode 无法注入 S-mode timer interrupt |
| **`time/timeh` CSR** | **❌** | RTL 中无 `ADDR_TIME`（0xC01）/ `ADDR_TIMEH`（0xC81）CSR 实现。`rdtime` 指令将触发 illegal instruction。Linux clocksource 依赖此 CSR |
| `cycle/cycleh` CSR | ✅ | `mcycle`/`mcycleh` 实现，64-bit 单调递增 |
| `instret/instreth` CSR | ✅ | `minstret`/`minstreth` 实现 |
| **U-mode counter 别名** | **⚠️** | U-mode 只读别名 CSR `cycle`（0xC00）/ `instret`（0xC02）未实现。`rdcycle`/`rdinstret` 将 trap。可通过 SBI 仿真或 mcounteren=0 陷阱处理绕过 |
| `mcounteren` | ✅ | 可读写 CSR（0x306），控制 S-mode 读 counter 权限 |
| `scounteren` | ✅ | 可读写 CSR（0x106），控制 U-mode 读 counter 权限 |
| SBI set_timer | ⚠️ | 硬件支持 mtimecmp 写入，但 OpenSBI 尚未移植 |

**time CSR 问题详述**：

```
当前状态：
  - CLINT 有内存映射的 mtime（0x0200_BFF8），可被 M-mode 软件直接读写
  - 但 RISC-V 规范要求 time/timeh 为 unprivileged counter CSR（0xC01/0xC81）
  - Linux 使用 rdtime 指令读取时间，该指令访问 CSR 0xC01
  - 当前 CSR 地址映射中无 0xC01 → rdtime 触发 illegal instruction

修复方案：
  A. 在 cpu_csr.sv 中添加 time/timeh CSR 读路径，返回 CLINT mtime 值
     （需从 CLINT 模块路由 mtime 值到 CSR 读 mux，跨模块信号）
  B. 依赖 SBI 仿真：OpenSBI 拦截 rdtime trap，从 CLINT mtime 读取返回
     （性能较差，每次 rdtime 需 trap + mret，但无需改 RTL）
```

### 6.1 STIP 置位路径专项分析

> **结论：STIP（sip[5]）无硬件置位路径，M-mode 软件（OpenSBI）无法注入 S-mode timer interrupt。这是 Linux 启动的硬性阻塞项。**

#### RTL 证据链

**1. mip 硬件写入（cpu_csr.sv:133,297）**

```verilog
// 硬件 pending 位：仅 MEIP/MTIP/MSIP
assign w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};
//                                                          bit7=MTIP        bit3=MSIP

// mip 寄存器构建：bit5 恒为 0
r_mip <= {w_mip_hw[31:2], r_sip[1], w_mip_hw[0]};
//                       ↑只有SSIP来自sip   ↑bit0=0
```

→ **mip[5]（STIP）恒为 0**，无任何硬件信号可置位。

**2. sip 软件写入掩码（cpu_csr.sv:256-257）**

```verilog
assign sip_wmask = {31'd0, sw_csr_wdata[1]};
//                       ↑仅 bit1（SSIP）可写
```

→ **sip[5]（STIP）不可由软件写入**。M-mode 执行 `csrs sip, t0`（t0[5]=1）无法置位 STIP。

**3. S-mode timer pending 检查（cpu_clint.sv:77）**

```verilog
wire s_interrupt_pending = sie_bit && ((ssie_bit && (csr_sip[1] | msip_bit)) ||
                                       (stie_bit && mtip_bit) ||     // ← 直接用 MTIP！
                                       (seie_bit && meip_bit));
```

→ S-mode timer interrupt pending 判定使用 `mtip_bit = ext_mtip`（CLINT 硬件信号），**而非 `csr_sip[5]`（STIP）**。

**4. S-mode timer cause 编码（cpu_clint.sv:89）**

```verilog
assign s_interrupt_cause = ... (stie_bit && mtip_bit) ? 32'h80000005 : ...;
//                                              ↑MTIP 直接触发 scause=5
```

→ 当 MTIP=1 且 sie.STIE=1 时，产生 scause=5（Supervisor timer interrupt）。

#### 三种可能的中断流向分析

| 流向 | 条件 | 是否可行 | 问题 |
|------|------|---------|------|
| **A. 直接委托** | mideleg[7]=1, MTIP 触发 | ⚠️ 部分可行 | MTIP 直接触发 S-mode trap，scause=5。**但 OpenSBI 无法在 M-mode 先处理 timer 再注入**，Linux 直接收到原始 MTIP，无法执行 SBI timer 逻辑 |
| **B. 软件注入** | mideleg[7]=0, OpenSBI 处理 MTIP 后写 sip[5]=1 | ❌ 不可行 | **sip[5] 不可写**，OpenSBI 无法注入 STIP |
| **C. MTIP 旁路** | mie[7]=0, sie[5]=1, MTIP 直接触发 S-mode | ⚠️ 部分可行 | M-mode 禁用自身 timer 中断，MTIP 直接走 S-mode。**但 OpenSBI 无法接收 timer 中断，无法实现 SBI set_timer** |

#### 中断优先级 Bug

当 MTIP 触发且 mideleg[7]=0 时：

```verilog
wire m_int_delegated = m_interrupt_pending && csr_mideleg[m_int_idx];
// m_int_idx=7, mideleg[7]=0 → m_int_delegated=false

wire s_int_taken = s_interrupt_pending && !m_int_delegated;
// s_interrupt_pending=true (stie_bit && mtip_bit), !false=true → s_int_taken=true

assign trap_to_s = ... || (!exception_valid && s_int_taken);
// → trap_to_s=true → 中断进入 S-mode！
```

→ **M-mode 中断未委托时，S-mode 中断却抢占了优先级**。违反 RISC-V 特权规范：M-mode 中断应始终优先于 S-mode 中断。

#### 标准 Linux timer 流程（当前无法实现）

```
正确流程（RISC-V 标准）：
  1. Linux 调用 SBI set_timer(next_timeout)
  2. OpenSBI（M-mode）编程 mtimecmp = next_timeout
  3. mtime >= mtimecmp → CLINT 置 MTIP
  4. OpenSBI 在 M-mode 接收 timer 中断（mcause=7）
  5. OpenSBI 执行 timer 回调，置 sip[5]=1（STIP）← 当前不可行！
  6. S-mode 收到 supervisor timer interrupt（scause=5）
  7. Linux 处理 timer 中断，重新调用 SBI set_timer

当前实现的最接近流程：
  - 设置 mideleg[7]=1（委托 MTI 到 S-mode）
  - MTIP 触发时直接进入 S-mode，scause=5
  - Linux 直接处理，跳过 OpenSBI timer 逻辑
  - 但这绕过了 SBI 层，Linux 需要直接写 mtimecmp（S-mode 无权写 M-mode CLINT）
```

#### 修复方案

| 方案 | 改动 | 复杂度 | 说明 |
|------|------|--------|------|
| **A. 使 sip[5] 可写 + 用 sip[5] 判定 pending** | cpu_csr.sv: sip_wmask 扩展 bit5; cpu_clint.sv: STIP pending 改用 csr_sip[5] | 中 | 标准方案，OpenSBI 可正常注入 STIP |
| **B. mideleg[7]=1 直接委托 + S-mode 可写 mtimecmp** | 需 CLINT 地址权限调整 | 中 | Linux 直接处理 timer，绕过 OpenSBI |
| **C. 硬件自动 MTIP→STIP 映射** | MTIP 置位时自动置 mip[5] | 小 | 非标准但实用，需同时修复优先级 bug |

**必须同时修复**：S-mode timer pending 检查应使用 `csr_sip[5]`（或 `csr_mip[5]`）而非 `ext_mtip`，否则当 M-mode 和 S-mode timer 同时 pending 时优先级判断错误。

#### 专项测试建议

```asm
# STIP 置位路径验证测试
# 前置：M-mode, mideleg=0, mie=0, sie=0

1. # 验证 sip[5] 不可写（当前行为）
   li t0, (1 << 5)
   csrs sip, t0          # 尝试置位 STIP
   csrr t1, sip          # 读回 sip
   # 期望：t1[5] = 0（STIP 未被置位）

2. # 验证 MTIP 直接触发 S-mode timer（当前行为）
   # 设置 mideleg[7]=1（委托 MTI）
   li t0, (1 << 7)
   csrs mideleg, t0
   # 设置 S-mode timer 使能
   li t0, (1 << 5)       # STIE
   csrs sie, t0
   csrs sstatus, (1 << 1) # SIE
   # 编程 mtimecmp 使其立即触发
   li t0, 0x02004000     # mtimecmp 地址
   lw t1, 0x0200BFF8     # 读 mtime
   sw t1, 0(t0)          # mtimecmp = mtime → MTIP=1
   # 期望：trap 到 stvec，scause = 0x80000005

3. # 验证 M-mode 优先级（当前有 bug）
   # 设置 mie[7]=1（M-mode timer 使能）+ mideleg[7]=0
   li t0, (1 << 7)
   csrs mie, t0
   csrc mideleg, t0      # 不委托
   # 同时 sie[5]=1（S-mode timer 使能）
   li t0, (1 << 5)
   csrs sie, t0
   # 触发 MTIP
   # 期望：trap 到 mtvec（M-mode），mcause = 0x80000007
   # 实际：可能 trap 到 stvec（S-mode）← BUG

4. # 验证修复后 sip[5] 可写
   # （修复后执行）
   li t0, (1 << 5)
   csrs sip, t0          # M-mode 置位 STIP
   csrr t1, sip
   # 期望：t1[5] = 1
   # S-mode 应收到 scause = 0x80000005
```

---

## 7. PLIC / 外部中断最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 外部中断控制器 | ✅ | PLIC 8 源中断控制器，0x0C00_0000 |
| MEIP | ✅ | Machine external interrupt 可触发 |
| SEIP | ✅ | 通过 mideleg 委托 |
| priority | ✅ | 每源 4 字节优先级寄存器 |
| pending | ✅ | 只读挂起状态 |
| enable | ✅ | 32-bit 使能掩码 |
| threshold | ✅ | 优先级阈值寄存器 |
| claim/complete | ✅ | claim 返回中断号，complete 完成处理 |
| Device Tree 描述 | ❌ | DTB 尚未创建 |

---

## 8. UART / Console 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| UART TX | ✅ | TX FIFO（16 字节），可配波特率，uart_hello/echo 测试通过 |
| UART RX | ✅ | RX FIFO（16 字节），peek + auto-arm 机制 |
| 波特率 | ✅ | 可配，默认 115200 |
| MMIO 地址 | ✅ | 0x1000_8000 |
| **Linux 驱动兼容性** | **❌** | 自定义 UART（`uart_top.sv`），**不兼容 ns16550a/uart8250 寄存器模型**。需：① 编写自定义 Linux 驱动，或 ② 修改 UART RTL 兼容 ns16550a，或 ③ 使用 SBI console 绕过 |
| early console | ⚠️ | 可通过 SBI console（`earlycon=sbi`）实现，但 OpenSBI 未移植 |
| SBI console | ⚠️ | OpenSBI 未移植，无法提供 SBI console |
| 中断模式 | ✅ | TX/RX 中断支持（IRQ_STAT 寄存器） |

**UART 兼容性问题详述**：

```
当前 UART 寄存器布局（自定义）：
  0x00 CTRL   [0]=TX_EN [1]=RX_EN [2]=TX_IE [3]=RX_IE
  0x04 STATUS [0]=TX_BUSY [1]=RX_VALID [2]=TX_FIFO_FULL ...
  0x08 TXDATA [7:0]
  0x0C RXDATA [7:0]  （peek + auto-arm 语义）
  0x10 BAUD   [15:0]
  0x14 IRQ_STAT
  0x18 RXPOP

ns16550a 标准寄存器布局：
  0x00 THR/RBR  [7:0]  （发送/接收保持寄存器）
  0x01 IER      [3:0]  （中断使能）
  0x02 FCR/IIR  [7:0]  （FIFO 控制/中断标识）
  0x03 LCR      [7:0]  （线路控制）
  0x04 MCR      [4:0]  （MODEM 控制）
  0x05 LSR      [7:0]  （线路状态）
  0x06 MSR      [7:0]  （MODEM 状态）
  0x07 SCR      [7:0]  （暂存）

→ 寄存器布局完全不兼容，Linux 标准 8250 驱动无法直接使用
```

---

## 9. 物理内存 / DDR 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| DDR 可访问 | ✅ | DDR3 通过 MIG 访问，SRAM 仿真模型可用，bootloader DDR3 自检通过 |
| DDR 起始地址 | ✅ | 0x8000_0000 |
| DDR 大小 | ✅ | 128MB 窗口（0x8000_0000~0x87FF_FFFF），足够最小 BusyBox Linux |
| 地址连续性 | ✅ | 128MB 连续地址空间 |
| 内存对齐 | ✅ | 0x80400000 为 4MB 对齐 |
| 访问宽度 | ✅ | byte/halfword/word load/store 均支持 |
| **AMO 到 DDR** | **❌** | A 扩展未实现，AMO/LR/SC 无法在 DDR 上工作 |
| MMIO 与 DDR 区分 | ✅ | 地址空间不重叠（DDR 0x80xx, MMIO 0x00-0x1F, 0xFC） |

---

## 10. Device Tree 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| `/cpus` | ❌ | DTB 未创建 |
| `riscv,isa` | ❌ | DTB 未创建 |
| `mmu-type` | ❌ | DTB 未创建 |
| `timebase-frequency` | ❌ | DTB 未创建 |
| `/memory` | ❌ | DTB 未创建 |
| `/chosen` | ❌ | DTB 未创建 |
| UART node | ❌ | DTB 未创建 |
| CLINT/timer node | ❌ | DTB 未创建 |
| PLIC node | ❌ | DTB 未创建 |
| reserved-memory | ❌ | DTB 未创建 |
| initrd 信息 | ❌ | DTB 未创建 |

---

## 11. Boot Protocol 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 入口特权级 | ✅ | Boot ROM 在 M-mode 启动（PC=0xFC00_0000） |
| kernel 装载地址 | ⚠️ | 地址空间支持 4MB 对齐（0x80400000），但未配置 Linux 启动流程 |
| `a0` | ⚠️ | 单核 hartid=0，但 OpenSBI 未移植 |
| `a1` | ⚠️ | DTB 地址传递依赖 OpenSBI，未移植 |
| `satp` | ✅ | 复位后 satp=0，MMU 关闭 |
| 中断状态 | ⚠️ | 复位后中断关闭，但未验证 Linux 入口条件 |
| cache 状态 | ⚠️ | fence.i 可清理 cache，但启动流程未针对 Linux 配置 |
| 固件保留内存 | ❌ | 未规划 OpenSBI 常驻区域 |
| DTB 格式 | ❌ | DTB 未创建 |
| initramfs | ❌ | 未创建 |

---

## 12. OpenSBI 平台最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| M-mode firmware 入口 | ❌ | OpenSBI 未移植 |
| console putchar | ❌ | OpenSBI 未移植 |
| console getchar | ❌ | OpenSBI 未移植 |
| timer driver | ❌ | OpenSBI 未移植 |
| interrupt delegation | ❌ | OpenSBI 未移植（硬件 medeleg/mideleg 已支持） |
| hart start | ⚠️ | 单核，boot hart 可简化 |
| IPI | N/A | 单核不需要 |
| **PMP** | **⚠️** | PMP CSR（`pmpaddr0-15`/`pmpcfg0-3`）**完全未实现**。OpenSBI 默认平台代码会访问 PMP CSR，触发 illegal instruction 崩溃。需：① 实现最小 PMP（至少 `pmpaddr0`+`pmpcfg0`），或 ② 修改 OpenSBI 平台代码跳过 PMP 初始化 |
| final jump | ❌ | OpenSBI 未移植 |
| platform config | ❌ | OpenSBI 未移植 |

---

## 13. Rootfs / BusyBox 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| initramfs | ❌ | 未创建 |
| `/init` | ❌ | 未创建 |
| BusyBox | ❌ | 未编译 |
| `/bin/sh` | ❌ | 未创建 |
| `/dev` | ❌ | 未创建 |
| `/proc` | ❌ | 未创建 |
| `/sys` | ❌ | 未创建 |
| bootargs | ❌ | 未配置 |

> 此部分属于软件阶段，非 CPU 硬件条件。

---

## 14. 最终检查表（逐项标注）

| 大类 | 项目 | 达标条件 | 检查结果 | 证据/备注 |
|------|------|---------|---------|-----------|
| ISA | RV32I | 基础整数指令全部正确 | ✅ | 40 条指令，ISA 测试通过 |
| ISA | M 扩展 | 乘除法指令正确 | ✅ | Booth + 非恢复余数 |
| **ISA** | **A 扩展** | **LR/SC + AMO 全部正确** | **❌** | **完全未实现，misa 无 A 位** |
| ISA | Zicsr | CSR 指令正确 | ✅ | 6 条 CSR 指令 |
| ISA | Zifencei | `fence.i` 有效 | ✅ | dcache wb + icache inv |
| ISA | `wfi` | 至少作为 NOP | ✅ | NOP 类指令 |
| CSR | `misa` | 与真实硬件能力一致 | ⚠️ | 缺 A 位声明 |
| 特权级 | M-mode | 复位进入 M-mode | ✅ | PC=0xFC00_0000 |
| 特权级 | S-mode | Linux 可运行在 S-mode | ✅ | M/S/U 三级特权 |
| 特权级 | U-mode | 用户程序可运行在 U-mode | ✅ | 同上 |
| 特权级 | `mret/sret` | 返回语义正确 | ✅ | 恢复 IE/PIE/特权级 |
| 异常 | `ecall` | U/S/M ecall cause 正确 | ✅ | cause 8/9/11 |
| 异常 | page fault | cause/stval 正确 | ✅ | cause 12/13/15 |
| 委托 | `medeleg` | S-mode 异常委托正常 | ✅ | delegation 测试通过 |
| 委托 | `mideleg` | S-mode 中断委托正常 | ✅ | cpu_clint 委托逻辑 |
| MMU | `satp` | Sv32 MODE/ASID/PPN 正确 | ✅ | satp CSR 实现 |
| MMU | PTW | 两级页表遍历正确 | ✅ | ptw_walk 测试通过 |
| MMU | 权限检查 | R/W/X/U/SUM/MXR 正确 | ✅ | MMU.sv + ptw.sv |
| MMU | `sfence.vma` | TLB 和页表可见性正确 | ⚠️ | 仅刷 TLB，**未 flush dcache** |
| Cache | I-cache | `fence.i` 后取新指令 | ✅ | fencei 测试通过 |
| Cache | D-cache | 普通 load/store 正确 | ✅ | dcache 测试通过 |
| **Cache** | **MMIO bypass** | **基于物理地址判断 MMIO** | **❌** | **基于虚拟地址 vaddr[31]/vaddr[30]** |
| **Cache** | **PTW 一致性** | **PTW 能看到最新 PTE** | **⚠️** | **PTW 旁路 dcache，写回策略下读到旧 PTE** |
| Timer | `mtime` | 64-bit 单调递增 | ✅ | CLINT r_mtime[63:0] |
| Timer | `mtimecmp` | 能触发 timer interrupt | ✅ | MTIP 触发逻辑 |
| **Timer** | **STIP** | **Linux 能收到 S-mode timer** | **❌** | **sip[5] 不可写，mip[5] 恒为 0，M-mode 无法注入 STIP；M/S 优先级 bug（见 §6.1）** |
| **Counter** | **`time/timeh`** | **S-mode 可读** | **❌** | **CSR 未实现，rdtime 触发 illegal inst** |
| Interrupt | PLIC | claim/complete/enable 可用 | ✅ | PLIC 8 源 |
| UART | TX/RX | 能稳定输出和输入 | ✅ | FIFO + 可配波特率 |
| **UART** | **Linux compatible** | **ns16550a 或 SBI console** | **❌** | **自定义 UART，不兼容 ns16550a** |
| DDR | 基础读写 | CPU-DDR 通信稳定 | ✅ | MIG + DDR3 自检通过 |
| DDR | 地址空间 | memory map 与 DTB 一致 | ⚠️ | 硬件正确，DTB 未创建 |
| Boot | OpenSBI | 能打印 banner 并跳转 | ❌ | OpenSBI 未移植 |
| Boot | kernel 地址 | RV32 kernel 4MB 对齐 | ⚠️ | 地址空间支持，未配置 |
| Boot | `a0/a1` | hartid 和 DTB 地址正确 | ❌ | OpenSBI 未移植 |
| Boot | `satp=0` | 进入 kernel 前 MMU 关闭 | ✅ | 复位后 satp=0 |
| DTB | `/cpus` | ISA/MMU/timebase 正确 | ❌ | DTB 未创建 |
| DTB | `/memory` | DDR 地址和大小正确 | ❌ | DTB 未创建 |
| DTB | `/chosen` | console/bootargs 正确 | ❌ | DTB 未创建 |
| Rootfs | initramfs | kernel 能找到 rootfs | ❌ | 未创建 |
| Rootfs | `/init` | 能执行并进入 shell | ❌ | 未创建 |

---

## 15. 关键阻塞项汇总

### 致命级（Linux 完全无法启动）

| # | 阻塞项 | 当前状态 | 影响范围 | 修复工作量估算 |
|---|--------|---------|---------|--------------|
| 1 | **A 扩展未实现** | misa 无 A 位，无 AMO/LR/SC 译码与执行 | Linux 内核所有原子操作/锁/调度/futex 触发 illegal instruction | 中（单核可简化实现，约 2-3 周） |
| 2 | **MMIO 判断基于虚拟地址** | `is_mmio = ~vaddr[31] \| vaddr[30]` | Linux 开启 Sv32 后，用户空间低虚拟地址被误路由为 MMIO，所有用户态访存失败 | 小（改 2 行 RTL，用 paddr 替代 vaddr 判断） |
| 3 | **STIP 无置位路径** | sip[5] 不可写，mip[5] 恒为 0，S-mode timer pending 直接用 MTIP | OpenSBI 无法注入 S-mode timer interrupt；同时存在 M/S 优先级 bug（mideleg[7]=0 时 S-mode 抢占 M-mode） | 中（扩展 sip_wmask + 改 pending 判定逻辑 + 修优先级） |

### 高危级（Linux 可启动但运行不稳定或功能严重受限）

| # | 阻塞项 | 当前状态 | 影响范围 | 修复工作量估算 |
|---|--------|---------|---------|--------------|
| 4 | **PTW-dcache 一致性** | PTW 旁路 dcache，写回策略下读到旧 PTE | Linux 修改页表后可能产生错误 page fault 或访问错误物理页 | 中（sfence.vma 时 flush dcache，或 PTW 走 coherent 路径） |
| 5 | **time/timeh CSR 未实现** | CSR 地址 0xC01/0xC81 不存在 | `rdtime` 触发 illegal instruction，Linux clocksource 不可用 | 小（添加 CSR 读路径映射到 CLINT mtime，或依赖 SBI 仿真） |
| 6 | **UART 不兼容 ns16550a** | 自定义寄存器布局 | Linux 标准 8250 驱动无法使用，需自定义驱动或 SBI console | 中（改 RTL 兼容 ns16550a，或写自定义驱动） |

### 中危级（可通过软件绕过但需额外工作）

| # | 阻塞项 | 当前状态 | 影响范围 | 绕过方案 |
|---|--------|---------|---------|---------|
| 7 | **PMP CSR 未实现** | 无 pmpaddr/pmpcfg | OpenSBI 访问 PMP CSR 崩溃 | 修改 OpenSBI 平台代码跳过 PMP 初始化 |
| 8 | **sfence.vma 未 flush dcache** | 仅刷 TLB | 页表更新后 TLB 填充可能用旧 PTE | Linux 可在 sfence.vma 后额外执行 cache flush 操作 |
| 9 | **U-mode counter 别名未实现** | 无 cycle(0xC00)/instret(0xC02) | rdcycle/rdinstret trap | mcounteren=0 让所有 counter 访问 trap 到 M-mode 由 SBI 仿真 |

### 待办级（软件阶段工作，硬件就绪后推进）

| # | 项目 | 状态 |
|---|------|------|
| 10 | OpenSBI 移植 | 未开始 |
| 11 | Device Tree (DTB) 创建 | 未开始 |
| 12 | initramfs / BusyBox 构建 | 未开始 |
| 13 | Linux kernel 配置与编译 | 未开始 |

---

## 16. 建议修复顺序

```
Phase 0 — 硬件致命阻塞修复（必须完成才能启动 Linux）
  ├─ [P0-1] 实现 A 扩展（LR.W/SC.W + 9 条 AMO）
  │         单核简化：1-entry reservation set，aq/rl 作为 NOP
  │         修改：cpu_decode.sv, cpu_execute.sv, cpu_mem.sv, cpu_csr.sv(misa)
  │
  ├─ [P0-2] MMIO 判断改为基于物理地址
  │         修改：icache_ctrl.sv:64, dcache_ctrl.sv:80
  │         is_mmio = ~paddr[31] | paddr[30]  （或更精确的 MMIO 地址范围判断）
  │
  └─ [P0-3] 修复 STIP 置位路径 + 中断优先级
            修改：cpu_csr.sv（sip_wmask 扩展 bit5，mip 构建加入 sip[5]）
                  cpu_clint.sv（S-mode timer pending 改用 csr_sip[5]/csr_mip[5]）
                  cpu_clint.sv（M-mode 中断未委托时，S-mode 不可抢占）
            验证：专项测试（见 §6.1 测试代码）

Phase 1 — 硬件高危修复（Linux 可启动但功能受限）
  ├─ [P1-1] 修复 PTW-dcache 一致性
  │         最简方案：sfence.vma 时 writeback+invalidate 整个 dcache
  │         修改：core_top.sv(sfence 信号扩展), dcache_ctrl.sv(新增 flush 状态)
  │
  ├─ [P1-2] 实现 time/timeh CSR
  │         方案 A：cpu_csr.sv 添加 0xC01/0xC81 读路径（需路由 CLINT mtime）
  │         方案 B：依赖 SBI 仿真（不改 RTL，性能差）
  │
  └─ [P1-3] UART 兼容性
            方案 A：修改 UART RTL 兼容 ns16550a 寄存器布局
            方案 B：编写自定义 Linux UART 驱动
            方案 C：仅使用 SBI console（earlycon=sbi）

Phase 2 — 软件平台搭建
  ├─ [P2-1] 修改 OpenSBI 平台代码（跳过 PMP / 适配自定义 UART 地址）
  ├─ [P2-2] 创建 Device Tree (DTS → DTB)
  ├─ [P2-3] 移植 OpenSBI（platform: 自定义 SoC）
  └─ [P2-4] Linux kernel 配置与编译（rv32ima, 自定义 platform）

Phase 3 — 用户态验证
  ├─ [P3-1] 构建 initramfs + BusyBox（riscv32, musl 静态链接）
  └─ [P3-2] 验证 Linux 启动到 /bin/sh
```

---

## 17. 当前硬件能力总结

| 能力维度 | 状态 | 说明 |
|---------|------|------|
| 指令集 | ⚠️ | RV32IMF_Zicsr_Zifencei，**缺 A 扩展** |
| 特权级 | ✅ | M/S/U 三级完整，委托机制正确 |
| 虚拟内存 | ⚠️ | Sv32 基本正确，**MMIO 判断错误** + **PTW-dcache 一致性风险** |
| 异常/中断 | ✅ | 11 种异常 + 3 种中断，委托正确 |
| 定时器 | ❌ | CLINT mtime/mtimecmp 正确，**但 STIP 无置位路径（sip[5] 不可写），M-mode 无法注入 S-mode timer interrupt；存在 M/S 中断优先级 bug** |
| 中断控制器 | ✅ | PLIC 8 源，claim/complete 正确 |
| 外设 | ⚠️ | UART/SPI/GPIO/Timer 功能正确，**UART 不兼容 ns16550a** |
| 内存 | ✅ | DDR3 128MB @ 0x80000000，Boot ROM 32KB @ 0xFC000000 |
| 缓存 | ⚠️ | I$/D$ 各 1KB 写回+写分配，**MMIO 判断基于虚拟地址** |
| PMP | ❌ | 完全未实现 |

**总体判定**：当前 CPU/SoC **不具备** 启动 Linux 的最低硬件条件。主要阻塞为：① A 扩展未实现、② MMIO 判断基于虚拟地址、③ STIP 无置位路径（M-mode 无法注入 S-mode timer interrupt）。修复此三项后，还需解决 PTW-dcache 一致性和 time CSR 缺失问题，方可进入 OpenSBI/Linux 移植阶段。
