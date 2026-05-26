# NMMU 存储改造计划

> 创建日期: 2026-05-25 | 状态: **实施中** | 关联进度: `dev/PROCESS-nmmu.md`

---

## 1. 项目目标

将 Cache 标志段和 TLB 从寄存器阵列（reg array）迁移至 BRAM 存储，统一 i/d MMU 为单一实例，替换算法统一为 tree-PLRU。

**核心收益**：
- 减少 FF 占用（D$ 标志 288 FF + I$ 标志 256 FF + 2×TLB 960 FF ≈ 1504 FF → BRAM）
- 双口 BRAM 天然支持并发读写（CPU 查找 Port A / Refill 填充 Port B）
- 统一 MMU 减少硬件冗余（2 TLB + 2 PTW → 1 TLB + 1 PTW）
- tree-PLRU 替换优于 FIFO，降低 TLB 颠簸率

**约束**：
- BRAM IP 采用配置驱动现场生成（`vivado_config.yaml` → `ip_gen.py` → TCL），不使用静态 XCI
- **tree_plru 位宽/路数当前不可参数化**（硬编码 4-way / 3-bit 状态），配置文件和文档中已标记此限制
- BRAM 支持 `Byte_Size=9` 字节写使能，D$ tag BRAM 利用此特性实现 per-way 写入

---

## 2. 现状分析

### 2.1 Cache 标志段现状

| 项目 | I-Cache | D-Cache |
|------|---------|---------|
| 标志存储 | `reg [7:0] tag_ram[0:7][0:3]` | `reg [8:0] tag_ram[0:7][0:3]` |
| 条目格式 | `{V(1), tag(7)}` = 8 bit | `{V(1), D(1), tag(7)}` = 9 bit |
| 总 FF 数 | 8×4×8 = 256 | 8×4×9 = 288 |
| PLRU 存储 | `reg [2:0] plru_state[0:7]` = 24 FF | 同左 |
| 查找方式 | 组合逻辑并行 4 路比较 | 同左 |
| 数据 BRAM | `icached` 256bit×32 TDP | `dcached` 256bit×32 TDP |
| BRAM 寻址 | `{set_idx[2:0], way[1:0]}` = 5 bit | 同左 |

**关键代码位置**：

- `dev/rtl/core/icache_ctrl.sv` L54: `tag_ram` 声明, L57-65: 组合比较
- `dev/rtl/core/dcache_ctrl.sv` L71: `tag_ram` 声明, L74-83: 组合比较
- `dev/rtl/core/cache_def.svh` L61: `USE_TAG_BRAM 0`（已预留开关）
- `vivado_config.yaml` L42: `use_tag_bram: false`

### 2.2 TLB 现状

| 项目 | 值 |
|------|-----|
| 实例数 | 2（inst TLB + data TLB，各自独立） |
| 相联度 | 16 项全相联 |
| 条目宽度 | 60 bit = {V(1), G(1), ASID(9), VPN(20), PPN(22), R,W,X,U,A,D(6), mega(1)} |
| 存储 | `reg [59:0] entries[0:15]`（寄存器阵列） |
| 替换算法 | Round-Robin (FIFO)，`rr_ptr` 循环递增 |
| 总 FF 数 | 2 × 16 × 60 = 1920 FF |
| ASID 感知 | 是（匹配 ASID 或 G=1） |
| Megapage | VPN[0] 归零，仅比较 VPN[1] |

**关键代码位置**：

- `dev/rtl/core/tlb.sv` L39: `ENTRY_W` 计算, L41: `entries` 声明, L42: `rr_ptr` FIFO 指针
- `dev/rtl/core/MMU.sv` L66: TLB 实例化, L130-142: walk 控制逻辑
- `dev/rtl/core/ptw.sv`: 10 状态 FSM 页表漫游器
- `dev/rtl/core/core_top.sv` L644-698: 两个 MMU 实例化

### 2.3 I-MMU vs D-MMU 差异

| 方面 | I-MMU | D-MMU |
|------|-------|-------|
| `access_type` | `2'b00` (FETCH) | `mem_hwrite ? 2'b10 : 2'b01` |
| `translate_en` | `1'b1`（始终翻译） | `mem_en`（仅访存时） |
| PTW 总线 | `ptw_i_bus_*`（独立） | `ptw_d_bus_*`（独立） |
| `satp` / `priv_mode` | 共享 | 共享 |
| `sfence_vma` | 共享脉冲 | 共享脉冲 |

### 2.4 BRAM IP 现有配置

| IP 名 | 类型 | 宽度 | 深度 | 写模式 | BRAM 数量 |
|--------|------|------|------|--------|-----------|
| icached | TDP | 256 bit | 32 | WRITE_FIRST | 8 × BRAM36 |
| dcached | TDP | 256 bit | 32 | WRITE_FIRST | 8 × BRAM36 |
| Sram | TDP | 32 bit | 8192 | WRITE_FIRST | 8 × BRAM36 |

> **注意**：设计报告提及 `dtag` (9bit×32) BRAM IP，但实际未创建 XCI 文件，RTL 中也未实例化。

---

## 3. Cache 标志段 BRAM 改造方案

### 3.1 设计概述

将每个 Cache 的 `{V, D, tag}` 标志位从 `reg` 阵列改为 **1 个 True Dual Port BRAM**。每个 BRAM 地址对应一个 Set 的全部 4 个 Way，实现单次 BRAM 读取即可获得 4 路标志，支持并行比较。

**PLRU 状态位保持 reg 不变**（8 sets × 3 bits = 24 bits，极小，不值得 BRAM）。

### 3.2 BRAM 配置

#### D-Cache 标志 BRAM (`dcachet`)

| 参数 | 值 | 说明 |
|------|-----|------|
| 类型 | True Dual Port RAM | |
| 数据宽度 | **36 bit** | 4 way × (V1 + D1 + tag7) = 4 × 9 |
| 深度 | **8** | 8 sets |
| 地址宽度 | **3 bit** | set_idx[2:0] |
| 写模式 | WRITE_FIRST | 与现有 BRAM IP 一致 |
| 字节写使能 | **是，Byte_Size=9** | 4-bit WEA，每 bit 控制 1 way 的 9-bit 段 |

**数据布局**（每个 BRAM 地址 = 1 个 Set）：

```
dout[35:27] = Way3: {V, D, tag[6:0]}   (9 bit)
dout[26:18] = Way2: {V, D, tag[6:0]}   (9 bit)
dout[17:9]  = Way1: {V, D, tag[6:0]}   (9 bit)
dout[8:0]   = Way0: {V, D, tag[6:0]}   (9 bit)
```

#### I-Cache 标志 BRAM (`icachet`)

| 参数 | 值 | 说明 |
|------|-----|------|
| 类型 | True Dual Port RAM | |
| 数据宽度 | **32 bit** | 4 way × (V1 + tag7) = 4 × 8 |
| 深度 | **8** | 8 sets |
| 地址宽度 | **3 bit** | set_idx[2:0] |
| 写模式 | WRITE_FIRST | |
| 字节写使能 | **是，Byte_Size=8** | 4-bit WEA，每 bit 控制 1 way 的 8-bit 段 |

**数据布局**：

```
dout[31:24] = Way3: {V, tag[6:0]}   (8 bit)
dout[23:16] = Way2: {V, tag[6:0]}   (8 bit)
dout[15:8]  = Way1: {V, tag[6:0]}   (8 bit)
dout[7:0]   = Way0: {V, tag[6:0]}   (8 bit)
```

### 3.3 BRAM 资源估算

| BRAM | 宽×深 | 总比特 | 实际使用 | BRAM18/36 |
|------|--------|--------|----------|-----------|
| dcachet | 36×8 | 288 | 288 | 1 × BRAM36（36bit 模式，深度 1024，利用率 0.8%） |
| icachet | 32×8 | 256 | 256 | 1 × BRAM36（36bit 模式，深度 1024，利用率 0.7%） |

> **注**：BRAM36 最小深度在 36bit 宽度下为 1024，利用率低但无法避免。替代方案是用 LUT 分布式 RAM，但丧失双口优势。对于 FPGA 设计，1 个 BRAM36 的开销可接受。

### 3.4 端口分配

| 端口 | D-Cache (`dcachet`) | I-Cache (`icachet`) |
|------|---------------------|---------------------|
| Port A 地址 | `set_idx`（CPU 请求的 set） | `set_idx` |
| Port A 操作 | 读：获取 4 路标志 → 并行比较 | 读：获取 4 路标志 → 并行比较 |
| Port A 使能 | `state == S_IDLE && cpu_req_valid && !is_mmio` | 同左 |
| Port B 地址 | `latched_set`（refill 目标 set） | `latched_set` |
| Port B 操作 | 写：refill 更新某 way 的标志 | 写：refill 更新某 way 的标志 |
| Port B 使能 | `refill_valid && state == S_REFILL` | 同左 |

**Port B 写策略**：仅更新 1 个 way 的标志位。利用 Xilinx BRAM 的 **Byte_Size=9** 字节写使能支持，每个 way 恰好对应 1 个 9-bit 字节段，无需 Read-Modify-Write。

> **关键决策**：Xilinx 7-series BRAM 支持 `CONFIG.Byte_Size {9}`，使字节写使能粒度为 9 bit。
> - D$ tag BRAM：36 bit 宽 / Byte_Size=9 → 4-bit WEA，每 bit 控制 1 个 way 的 9-bit 段
> - I$ tag BRAM：32 bit 宽 / Byte_Size=8 → 4-bit WEA，每 bit 控制 1 个 way 的 8-bit 段
>
> **写单个 way**：仅置位对应 way 的 WEA 位，写入该 way 的 8/9-bit 数据，其余 way 保持不变。
>
> **写整 set（invalidate）**：WEA 全 1，写入全零行。

### 3.5 FSM 修改 — BRAM 读延迟处理

**核心问题**：BRAM 输出是寄存输出（1-cycle 延迟），当前 reg 阵列是组合输出（0-cycle 延迟）。

#### I-Cache FSM 修改

**当前流程**（0-cycle tag 延迟）：

```
S_IDLE → S_READ: tag 比较（组合逻辑，同周期出结果）
  hit → 返回数据
  miss → 发起 refill
```

**改造后流程**（1-cycle tag 延迟）：

```
S_IDLE: 使能 tag BRAM (addra=set_idx)，转入 S_TAG_READ
S_TAG_READ: tag BRAM 输出有效，4 路并行比较
  hit → 使能 data BRAM (addra={set_idx, hit_way})，转入 S_READ_HIT
  miss → 锁存 victim，发起 refill，转入 S_REFILL
S_READ_HIT: data BRAM 输出有效，返回数据
S_REFILL: (不变)
```

**延迟影响**：命中路径从 2 周期（S_IDLE→S_READ）变为 3 周期（S_IDLE→S_TAG_READ→S_READ_HIT）。缺失路径不变。

#### D-Cache FSM 修改

**当前流程**：

```
S_IDLE: tag 比较（组合逻辑）
  store hit → 写 data BRAM，置 dirty，完成
  load hit → 转入 S_READ_HIT
  miss → 锁存，检查 victim dirty
```

**改造后流程**：

```
S_IDLE: 使能 tag BRAM，转入 S_TAG_READ
S_TAG_READ: tag BRAM 输出有效，4 路比较
  store hit → 写 data BRAM，置 dirty（需 RMW tag BRAM 更新 dirty），完成
  load hit → 使能 data BRAM，转入 S_READ_HIT
  miss → 锁存 victim，检查 victim dirty
S_READ_HIT: data BRAM 输出有效，返回数据
S_WB_READ / S_WB_SEND / S_REFILL: (基本不变，tag 更新改用 BRAM 写)
```

**Store Hit 的 Dirty 更新**：需要 Read-Modify-Write tag BRAM（读出 36-bit，修改目标 way 的 D 位，写回）。

### 3.6 Invalidate / Flush 处理

**I-Cache Invalidate**（FENCE.I）：

- 当前：循环清零所有 `tag_ram[s][w]`
- 改造后：逐 set 写入全零行（8 次_BRAM 写，8 周期），或引入 `S_INVALIDATE` 状态逐 set 清零

**D-Cache Flush**（FENCE.I 的 writeback+invalidate）：

- 当前：`S_FLUSH_SCAN` 遍历所有 set/way 检查 dirty
- 改造后：`S_FLUSH_SCAN` 需从 tag BRAM 读取标志判断 dirty，逐 set 读取 → 检查 → 写回

### 3.7 需修改的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/icache_ctrl.sv` | 删除 `tag_ram` reg 阵列，实例化 `icachet` BRAM，新增 `S_TAG_READ` 状态，修改 invalidate 逻辑 |
| `dev/rtl/core/dcache_ctrl.sv` | 删除 `tag_ram` reg 阵列，实例化 `dcachet` BRAM，新增 `S_TAG_READ` 状态，修改 flush/dirty 更新逻辑 |
| `dev/rtl/core/cache_def.svh` | 新增 `ICACHE_TAG_BRAM_WIDTH=32`、`DCACHE_TAG_BRAM_WIDTH=36` 等定义，`USE_TAG_BRAM` 改为 1 |
| `vivado_config.yaml` | `use_tag_bram: true`，新增 tag BRAM 宽度/深度配置 |
| `tools/vivado_core/cache_header_gen.py` | 新增 tag BRAM 参数生成逻辑 |
| BRAM XCI | 新建 `icachet.xci` (32bit×8 TDP) 和 `dcachet.xci` (36bit×8 TDP) |

---

## 4. TLB BRAM 改造方案

### 4.1 设计概述

将 TLB 从 16 项全相联寄存器阵列改为 **4 路 4 组组相联 BRAM 结构**，分为标志段（Flag BRAM）和数据段（Data BRAM），替换算法从 FIFO 改为 tree-PLRU。

**从全相联改为组相联的原因**：BRAM 每端口每周期只能读 1 个地址，无法实现 16 路并行比较。组相联（4 路 × 4 组）每次读 1 组的 4 路，并行比较 4 路，是 BRAM 下最实用的 TLB 结构。

### 4.2 TLB 几何参数

| 参数 | 当前值 | 改造后值 | 说明 |
|------|--------|----------|------|
| 相联度 | 16 路全相联 | 4 路组相联 | BRAM 限制 |
| 组数 | 1 | 4 | 16 entries / 4 ways |
| 总项数 | 16 | 16 | 容量不变 |
| 组索引 | 无 | VPN[1:0] 或 hash(VPN) | 2 bit |
| 替换算法 | Round-Robin (FIFO) | tree-PLRU (3 bit/set) | 与 cache 一致 |

### 4.3 组索引策略

**选项 A**：`set_idx = VPN[1:0]`（简单，用 VPN 最低 2 位）

- 优点：零逻辑开销
- 缺点：Megapage 的 VPN[9:0] 为页偏移，VPN[1:0] 通常为 0 → megapage 集中在 set 0

**选项 B**：`set_idx = VPN[1:0] ^ VPN[11:10]`（XOR hash）

- 优点：分散 megapage，更好的均匀性
- 缺点：额外 XOR 门

**推荐**：选项 B（XOR hash）。Megapage 数量少（通常 < 4），即使集中在 set 0 也仅占 4 way 中的少数，但 XOR hash 提供更好的最坏情况保证。

### 4.4 标志段 BRAM（Flag BRAM, `tlb_flag`）

存储 VPN、ASID、V、G、is_megapage — 用于查找匹配。

| 参数 | 值 | 说明 |
|------|-----|------|
| 类型 | True Dual Port RAM | |
| 每 way 宽度 | 32 bit | {V(1), G(1), ASID(9), VPN(20), mega(1)} |
| 每 set 宽度 | **128 bit** | 4 way × 32 bit |
| 深度 | **4** | 4 sets |
| 地址宽度 | **2 bit** | set_idx |
| 写模式 | WRITE_FIRST | |

**数据布局**（每个 BRAM 地址 = 1 个 Set）：

```
dout[127:96] = Way3: {V, G, ASID[8:0], VPN[19:0], mega}   (32 bit)
dout[95:64]  = Way2: {V, G, ASID[8:0], VPN[19:0], mega}   (32 bit)
dout[63:32]  = Way1: {V, G, ASID[8:0], VPN[19:0], mega}   (32 bit)
dout[31:0]   = Way0: {V, G, ASID[8:0], VPN[19:0], mega}   (32 bit)
```

### 4.5 数据段 BRAM（Data BRAM, `tlb_data`）

存储 PPN、R、W、X、U、A、D — 命中后输出翻译结果和权限位。

| 参数 | 值 | 说明 |
|------|-----|------|
| 类型 | True Dual Port RAM | |
| 每 way 宽度 | 28 bit | {PPN(22), R, W, X, U, A, D} |
| 每 set 宽度 | **112 bit** | 4 way × 28 bit |
| 深度 | **4** | 4 sets |
| 地址宽度 | **2 bit** | set_idx |
| 写模式 | WRITE_FIRST | |

**数据布局**：

```
dout[111:84] = Way3: {PPN[21:0], R, W, X, U, A, D}   (28 bit)
dout[83:56]  = Way2: {PPN[21:0], R, W, X, U, A, D}   (28 bit)
dout[55:28]  = Way1: {PPN[21:0], R, W, X, U, A, D}   (28 bit)
dout[27:0]   = Way0: {PPN[21:0], R, W, X, U, A, D}   (28 bit)
```

### 4.6 BRAM 资源估算

| BRAM | 宽×深 | 总比特 | BRAM36 数量 |
|------|--------|--------|-------------|
| tlb_flag | 128×4 | 512 | 1 × BRAM36（128bit 模式，深度 512，利用率 0.8%） |
| tlb_data | 112×4 | 448 | 1 × BRAM36（112bit 需 144bit 模式，利用率 0.6%） |

### 4.7 tree-PLRU 替换

复用现有 `tree_plru.sv` 模块（4 way, 3 bit 状态），每组 1 个实例：

```systemverilog
reg [2:0] plru_state [0:3];  // 4 sets × 3 bits = 12 bits (reg)
```

**替换逻辑**（与 cache 完全一致）：

1. 优先选择无效路（V=0）
2. 全部有效时选择 tree-PLRU 受害路

### 4.8 TLB 查找流程

**当前**（全相联，组合逻辑）：

```
VPN → 同时比较 16 项 → 命中/缺失（0-cycle）
```

**改造后**（组相联，BRAM 1-cycle 延迟）：

```
S_IDLE: 计算 set_idx, 使能 flag BRAM + data BRAM (addra=set_idx)
S_LOOKUP: flag BRAM 输出有效 → 4 路并行匹配
  hit → 从 data BRAM 输出提取 PPN+权限（data BRAM 同周期有效）
  miss → 发起 PTW walk
```

> **关键**：flag BRAM 和 data BRAM 同时使能、同地址，因此输出同时有效（均在 1 cycle 后）。命中时无需额外等待 data BRAM。

### 4.9 Megapage 匹配处理

Megapage 仅比较 VPN[1]（高 10 位 VPN[19:10]），VPN[0] 为页偏移。组相联下：

- 查找时：仍按 `hash(VPN)` 选择 set，在该 set 内 4 路并行匹配
- Megapage way 的匹配条件：`valid && (vpn_stored[19:10] == lookup_vpn[19:10]) && (global || asid_match)`
- 与当前全相联逻辑一致，仅比较范围从 16 路缩小为 4 路

### 4.10 SFENCE.VMA 刷新

- 当前：`flush_all` 清零所有 16 项的 V 位
- 改造后：逐 set 写入全零行到 flag BRAM（4 次写，4 周期），或引入 `S_FLUSH` 状态逐 set 清零 V 位

### 4.11 需修改的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/tlb.sv` | 重写为组相联 BRAM 结构，删除 `entries` reg 阵列和 `rr_ptr`，实例化 `tlb_flag` + `tlb_data` BRAM，集成 `tree_plru`，新增 `S_LOOKUP` 状态 |
| `dev/rtl/core/cache_def.svh` | 新增 TLB BRAM 参数定义（`TLB_NUM_SETS`, `TLB_NUM_WAYS`, `TLB_FLAG_BRAM_WIDTH`, `TLB_DATA_BRAM_WIDTH` 等） |
| BRAM XCI | 新建 `tlb_flag.xci` (128bit×4 TDP) 和 `tlb_data.xci` (112bit×4 TDP) |

---

## 5. 统一 MMU 方案

### 5.1 设计概述

将 `core_top` 中的两个 MMU 实例（`u_mmu_inst` + `u_mmu_data`）合并为 **1 个统一 MMU 实例**，共享 1 个 TLB 和 1 个 PTW。

### 5.2 统一 MMU 接口

```systemverilog
module MMU_unified #(
    parameter TLB_ENTRIES = 16
)(
    input              clk, reset,

    // --- 指令侧接口 ---
    input       [31:0] i_vaddr,
    input              i_translate_en,     // 始终为 1
    output      [31:0] i_paddr,
    output             i_miss,
    output             i_page_fault,
    output      [3:0]  i_pf_cause,
    output      [31:0] i_pf_vaddr,

    // --- 数据侧接口 ---
    input       [31:0] d_vaddr,
    input       [1:0]  d_access_type,     // LOAD/STORE
    input              d_translate_en,     // mem_en
    output      [31:0] d_paddr,
    output             d_miss,
    output             d_page_fault,
    output      [3:0]  d_pf_cause,
    output      [31:0] d_pf_vaddr,

    // --- 共享输入 ---
    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_sum,
    input              mstatus_mxr,

    // --- PTW 总线（单一） ---
    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error,

    input              sfence_vma
);
```

### 5.3 双口 TLB 并发查找

利用 BRAM 的 True Dual Port 特性：

| BRAM 端口 | 用途 | 地址 |
|-----------|------|------|
| Port A | 指令侧查找 | `hash(i_vaddr[31:12])` → i_set_idx |
| Port B | 数据侧查找 | `hash(d_vaddr[31:12])` → d_set_idx |

**并发场景**：

- i-lookup 和 d-lookup 访问**不同 set**：完全并发，无冲突
- i-lookup 和 d-lookup 访问**同一 set**：TDP BRAM 支持同时读同一地址，无冲突
- i-lookup / d-lookup 与 PTW fill **同时**：需要仲裁

### 5.4 PTW 填充仲裁

PTW fill 需要写 BRAM（占用一个端口）。仲裁策略：

| 场景 | 处理 |
|------|------|
| 仅 i-lookup 或 d-lookup | 正常读 |
| i-lookup + d-lookup | 双口并发读 |
| lookup + PTW fill | PTW 优先，暂停 lookup 1 周期（fill 是低频操作） |
| 双 lookup + PTW fill | PTW 使用 Port B，暂停 d-lookup 1 周期，i-lookup 不受影响 |

**推荐**：PTW fill 使用 Port B 写，期间暂停数据侧 lookup（stall dcache 1 周期），指令侧 lookup 使用 Port A 不受影响。这保证了取指不被 PTW 阻塞。

### 5.5 共享 PTW

**当前**：2 个 PTW 实例，可同时 walk（i-PTW 和 d-PTW 并发通过 AHB 总线）。

**统一后**：1 个 PTW 实例，同一时刻仅处理 1 次 walk。

**并发 miss 处理**：

- 若 i-miss 和 d-miss 同时发生，需排队处理
- 优先级：**d-miss 优先**（数据访存通常在取指之后，且 d-miss 阻塞流水线 MEM 级）
- 实现：引入 `pending_walk_type` 寄存器（IDLE / I_WALK / D_WALK / I_PENDING）
  - D_WALK 进行中 → i-miss 记录为 I_PENDING
  - D_WALK 完成 → 检查 I_PENDING → 启动 I_WALK

**总线简化**：`cpu_bus_bridge` 从 2 个 PTW 总线接口（`ptw_i_bus_*` + `ptw_d_bus_*`）简化为 1 个（`ptw_bus_*`），仲裁逻辑简化。

### 5.6 权限检查

统一 TLB 中，每项存储完整的 R/W/X/U 权限位。查找时根据 `access_type` 检查：

| access_type | 权限要求 |
|-------------|----------|
| FETCH (i-side) | X=1 |
| LOAD (d-side) | R=1 或 (X=1 且 MXR=1) |
| STORE (d-side) | W=1 |

统一 MMU 分别对 i-side 和 d-side 独立做权限检查，逻辑与当前两个 MMU 实例内部一致。

### 5.7 需修改的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/MMU.sv` | 重写为 `MMU_unified`，双查找接口，单 PTW，并发 miss 排队 |
| `dev/rtl/core/tlb.sv` | 已在 §4 改造为组相联 BRAM |
| `dev/rtl/core/ptw.sv` | 接口不变，仅被单一实例化 |
| `dev/rtl/core/core_top.sv` | 删除 `u_mmu_inst` + `u_mmu_data`，改为 1 个 `u_mmu_unified`，重新连线 |
| `dev/rtl/core/cpu_bus_bridge.sv` | 合并 `ptw_i_bus_*` + `ptw_d_bus_*` 为单一 `ptw_bus_*`，简化仲裁 |
| `dev/rtl/core/cpu_controller.sv` | `mmu_inst_miss` / `mmu_data_miss` 信号来源改为统一 MMU 输出 |

---

## 6. 实施阶段与依赖关系

```
Phase 1: Cache 标志段 BRAM     ──→ Phase 2: TLB BRAM + tree-PLRU
   (独立，可先行)                      (依赖 Phase 1 的 BRAM 经验)
                                       │
                                       ↓
                                 Phase 3: 统一 MMU
                                  (依赖 Phase 2 的 TLB)
                                       │
                                       ↓
                                 Phase 4: 集成验证
                                  (依赖全部)
```

### Phase 1: Cache 标志段 BRAM（预计 3-5 天）

| 步骤 | 任务 | 产出 |
|------|------|------|
| 1.1 | 创建 BRAM XCI：`icachet.xci` (32bit×8 TDP), `dcachet.xci` (36bit×8 TDP) | IP 文件 |
| 1.2 | 更新 `cache_def.svh`：新增 tag BRAM 宏定义，`USE_TAG_BRAM=1` | 头文件 |
| 1.3 | 更新 `vivado_config.yaml` + `cache_header_gen.py` | 配置/脚本 |
| 1.4 | 改造 `icache_ctrl.sv`：删除 `tag_ram`，实例化 `icachet`，新增 `S_TAG_READ`，修改 invalidate | RTL |
| 1.5 | 改造 `dcache_ctrl.sv`：删除 `tag_ram`，实例化 `dcachet`，新增 `S_TAG_READ`，修改 flush/dirty | RTL |
| 1.6 | 仿真验证：`tb_simple_cpu_top`, `tb_simple_cpu_trap`, `tb_simple_cpu_priv` | 测试通过 |

### Phase 2: TLB BRAM + tree-PLRU（预计 3-5 天）

| 步骤 | 任务 | 产出 |
|------|------|------|
| 2.1 | 创建 BRAM XCI：`tlb_flag.xci` (128bit×4 TDP), `tlb_data.xci` (112bit×4 TDP) | IP 文件 |
| 2.2 | 更新 `cache_def.svh`：新增 TLB BRAM 宏定义 | 头文件 |
| 2.3 | 重写 `tlb.sv`：组相联 BRAM 结构，集成 `tree_plru`，新增 `S_LOOKUP` | RTL |
| 2.4 | 修改 `MMU.sv`：适配新 TLB 接口（BRAM 延迟） | RTL |
| 2.5 | 仿真验证：`tb_simple_cpu_priv`（Sv32 虚拟内存测试） | 测试通过 |

### Phase 3: 统一 MMU（预计 3-5 天）

| 步骤 | 任务 | 产出 |
|------|------|------|
| 3.1 | 重写 `MMU.sv` → `MMU_unified`：双查找接口，单 PTW，并发 miss 排队 | RTL |
| 3.2 | 修改 `core_top.sv`：单一 MMU 实例化，重新连线 | RTL |
| 3.3 | 修改 `cpu_bus_bridge.sv`：合并 PTW 总线，简化仲裁 | RTL |
| 3.4 | 修改 `cpu_controller.sv`：适配统一 MMU 信号 | RTL |
| 3.5 | 仿真验证：全部 testbench | 测试通过 |

### Phase 4: 集成验证（预计 2-3 天）

| 步骤 | 任务 | 产出 |
|------|------|------|
| 4.1 | 全 testbench 回归：`tb_simple_cpu_top`, `tb_simple_cpu_compute`, `tb_simple_cpu_trap`, `tb_simple_cpu_priv`, `tb_led_marquee`, `tb_uart_hello` | 全部 PASS |
| 4.2 | Vivado 综合验证：检查时序收敛、BRAM 利用率 | 综合报告 |
| 4.3 | 硬件 BRAM 延迟验证：确认仿真行为与硬件一致（READ_LATENCY=1） | 验证记录 |
| 4.4 | 更新设计报告 `dev/docs/simpleCPU-design-report.md` | 文档 |

---

## 7. 风险与缓解措施

| 风险 | 影响 | 概率 | 缓解 |
|------|------|------|------|
| BRAM 1-cycle 读延迟导致 FSM 时序错误 | 功能失败 | 高 | 严格按 S_IDLE→S_TAG_READ→S_READ_HIT 流程改造，仿真中启用 BRAM 寄存输出模型验证 |
| 组相联 TLB 缺失率上升（16-way→4-way） | 性能下降 | 中 | 保留 16 项总容量；如实测 miss rate 过高，可扩展为 8-way×8-set=32 项 |
| 统一 MMU 并发 miss 处理死锁 | 功能失败 | 低 | PTW 单线程化 + pending 队列，优先级明确（d-miss > i-miss） |
| Megapage 集中在 set 0 导致不均衡 | 性能下降 | 低 | XOR hash 分散；megapage 通常 < 4 个，4-way 足够 |
| Read-Modify-Write tag BRAM 增加周期 | 性能下降 | 低 | 仅 refill 时需 RMW（低频），命中路径无 RMW |
| 现有 testbench 未覆盖 BRAM 延迟场景 | 隐藏 bug | 中 | 修改 testbench 使用寄存输出 BRAM 模型，或增加仿真时间容限 |
| Vivado 工程 RTL/IP 同步问题 | 仿真跑旧代码 | 高 | 每次修改后执行 `update_compile_order`，或使用 vivado-orchestrator 自动刷新 |

---

## 8. 验证策略

### 8.1 仿真验证

| Testbench | 验证重点 | 预期结果 |
|-----------|----------|----------|
| `tb_simple_cpu_top` | 完整指令集 + Cache 命中/缺失 | 42 PASS, 0 FAIL |
| `tb_simple_cpu_trap` | 异常/中断 + TLB 权限错误 | 14 PASS, 0 FAIL |
| `tb_simple_cpu_priv` | M/S/U 特权 + Sv32 虚拟内存 + TLB miss/refill | 3 PASS, 0 FAIL |
| `tb_led_marquee` | 长时间运行 + Cache 驱逐 + TLB 压力 | 16 PASS, 0 FAIL |
| `tb_uart_hello` | MMIO 旁路 + DCache store | 12 PASS, 0 FAIL |

### 8.2 BRAM 延迟验证

- **仿真环境**：Vivado XSim 行为模型默认 0-cycle 延迟
- **硬件验证**：综合后 BRAM 为 1-cycle 寄存输出
- **建议**：在 testbench 中增加时钟周期容限，或在仿真中使用 `-relax` 模式检查时序

### 8.3 性能对比

| 指标 | 改造前 | 改造后 | 说明 |
|------|--------|--------|------|
| I$ 命中延迟 | 2 cycle (sim) | 3 cycle | +1 cycle (tag BRAM) |
| D$ load 命中延迟 | 2 cycle (sim) | 3 cycle | +1 cycle (tag BRAM) |
| D$ store 命中延迟 | 1 cycle (sim) | 2 cycle | +1 cycle (tag BRAM) |
| TLB 查找延迟 | 0 cycle (组合) | 1 cycle | BRAM 寄存输出 |
| TLB 替换质量 | FIFO | tree-PLRU | 更优，降低 miss rate |
| FF 节省 | — | ~1504 FF | tag_ram + TLB entries |
| BRAM 新增 | — | +4 BRAM36 | icachet + dcachet + tlb_flag + tlb_data |

---

## 9. 设计决策待确认项

| # | 决策项 | 选项 | 推荐 | 状态 |
|---|--------|------|------|------|
| D1 | TLB 组索引策略 | A: VPN[1:0] / B: XOR hash | B | ✅ 确认：XOR hash |
| D2 | Tag BRAM 写策略 | A: 字节写使能 / B: Read-Modify-Write | B | ✅ 确认：字节写使能（Byte_Size=9/8），无需 RMW |
| D3 | 统一 MMU 并发 miss 优先级 | A: i-miss 优先 / B: d-miss 优先 | B | ✅ 确认：d-miss 优先（默认） |
| D4 | TLB 容量 | A: 16 项 / B: 32 项 (8way×4set) | A | ✅ 确认：16 项（默认） |
| D5 | PLRU 是否参数化 | A: 保持 4-way 硬编码 / B: 参数化 N-way | A | ✅ 确认：不参数化，配置/文档标记位宽路数不可动 |
| D6 | Invalidate/Flush 实现 | A: 逐 set BRAM 写 / B: 引入专用状态机 | A | ✅ 确认：逐 set BRAM 写（默认） |

---

## 附录 A: BRAM 宽度-深度对照表（Xilinx 7-series BRAM36）

| 端口宽度 | 最大深度 | 适用场景 |
|----------|----------|----------|
| 1 | 32768 | — |
| 9 | 4096 | — |
| 18 | 2048 | — |
| 36 | 1024 | dcachet (36bit×8) |
| 72 | 512 | — |
| 128 | 256 | tlb_flag (128bit×4) |
| 144 | 256 | tlb_data (112bit→144bit 对齐) |
| 256 | 128 | icached/dcached (256bit×32) |
| 288 | 128 | — |

## 附录 B: 信号位宽变更汇总

| 信号 | 当前 | 改造后 | 说明 |
|------|------|--------|------|
| icache tag_ram | `reg[7:0] [0:7][0:3]` | BRAM 32bit×8 | 4 way 打包 |
| dcache tag_ram | `reg[8:0] [0:7][0:3]` | BRAM 36bit×8 | 4 way 打包 |
| tlb entries | `reg[59:0] [0:15]` | flag BRAM 128bit×4 + data BRAM 112bit×4 | 拆分标志/数据 |
| tlb rr_ptr | `reg[3:0]` | 删除 | 改用 tree_plru |
| tlb plru_state | 无 | `reg[2:0] [0:3]` | 新增，4 sets × 3 bits |
| MMU 实例数 | 2 | 1 | 统一 |
| PTW 实例数 | 2 | 1 | 共享 |
| PTW 总线数 | 2 (ptw_i + ptw_d) | 1 | 简化 |
