# AXI 总线迁移 + chiplab 架构对齐 + MIG 仿真验证计划

> **日期**: 2026-06-09 | **状态**: 规划中 | **前置废弃**: 所有 AHB-Lite DDR3 计划已停止
> **目标 FPGA**: xc7a200t-fbg676-2 (与 chiplab 龙芯杯开发板一致)
> **参考项目**: ~/chiplab (LoongArch32 SoC, 成熟的 MIG+AXI 架构)

---

## 目标

1. **将系统总线从 AHB-Lite 换为 AXI4**，消除 AHB mux HREADY 传播死锁等根本性架构问题
2. **全面对齐 chiplab 的仿真/上板架构**，使 MIG 集成、时钟、复位、数据加载等关键路径与经过验证的成熟设计一致
3. **完成 MIG 加入和仿真验证**，实现 DDR3 读写正确、全系统仿真通过、FPGA 上板可用

---

## 大步骤（Phase）

### Phase 0: 清理与准备

**目标**: 清除旧 AHB-Lite DDR3 相关代码，建立新架构的基础设施

- 删除/归档 AHB-Lite DDR3 相关 RTL：`ddr3_bridge_wrapper.sv`、`ahb_sys_status.sv`、`ahb_bootrom_slave.sv`（AHB 版本）
- 删除 DDR3 相关 force workaround testbench：`tb_ddr3_system.sv`、`tb_ddr3_system_v2.sv`、`tb_ddr3_system_v3.sv`
- 保留可复用资产：`clk_wiz_0_passthrough.sv`、`Reference/ddr3_sim/`、MIG IP 配置 (`Reference/mig/`)
- 更新 `vivado_config.yaml`：确认 `device_part: xc7a200tfbg676-2`
- 创建 `soc_config.vh`（参照 chiplab）：`SIMU_USE_DDR`、`SIMU_USE_PLL` 宏定义

**约束**:
- 不删除非 DDR3 的 AHB-Lite 总线代码（Phase 1 会整体替换）
- 保留所有非 DDR3 testbench 的向后兼容性

---

### Phase 1: CPU 侧 AXI4 接口改造

**目标**: 将 CPU 核的总线接口从 AHB-Lite 输出改为 AXI4 输出

- 重写 `cpu_bus_bridge.sv`：输出 AXI4 信号（AW/AR/W/R/B 通道）而非 AHB-Lite 信号
- 修改 `core_top.sv`：端口声明从 AHB-Lite 改为 AXI4
- icache refill / dcache write-back：保持 INCR8 burst 语义，但走 AXI4 协议
- MMIO 访问（PLIC/CLINT/UART 等）：单拍 AXI4 事务

**约束**:
- CPU 核内部逻辑（fetch/decode/execute/mem/wb）**不修改**，仅改 `cpu_bus_bridge` 的输出协议
- AXI4 ID 宽度：4-bit（与 chiplab `core_top` 一致）
- AXI4 数据宽度：32-bit
- AXI4 地址宽度：32-bit
- 保持 cache line 大小不变（256-bit = 8×32bit）

---

### Phase 2: AXI4 互联 + 从设备适配

**目标**: 构建 AXI4 互联结构，替代 AHB-Lite bus + decoder + mux

- **AXI4 Crossbar**：使用 Xilinx `axi_interconnect` IP（2 主 × N 从，参照 chiplab 的 `axi_crossbar_2x3`）或自研 AXI4 crossbar
  - 主设备 0: CPU AXI4
  - 主设备 1: JTAG AXI master（上板用，仿真可接 BFM）
- **从设备适配**：
  - DDR3: 直连 MIG AXI4 接口（经 CDC，见 Phase 3）
  - Boot ROM: AXI4-Lite 从设备（只读 BRAM）
  - PLIC: AXI4-Lite 从设备
  - CLINT: AXI4-Lite 从设备
  - APB Bridge (UART/SPI/GPIO): AXI4-Lite → APB 桥
  - CONFREG (LED/数码管/开关): AXI4-Lite 从设备
  - Default slave: 错误响应

**约束**:
- 从设备地址映射与 chiplab 对齐：
  - DDR3: `0x8000_0000`（RISC-V DRAM 惯例，已决策）
  - Boot ROM: `0xFC00_0000`
  - PLIC: `0x0C00_0000`
  - CLINT: `0x0200_0000`
  - APB/UART: `0x1FE0_0000`
  - CONFREG: `0x1FD0_0000`
- AXI4 协议必须严格合规（无 HREADY 类似的组合环路风险）

---

### Phase 3: MIG + DDR3 集成（对齐 chiplab）

**目标**: 按照 chiplab 的 `axi_wrap_ddr.v` 架构集成 MIG

- **AXI CDC**：复用 chiplab 的 `Axi_CDC.v`（SpinalHDL 生成，1606 行），将 sys_clk 域 AXI4 请求安全传递到 MIG ui_clk 域
- **MIG 实例化**：
  - `sys_clk_i` ← 外部 100MHz（No Buffer）
  - `clk_ref_i` ← 200MHz DDR 参考时钟（No Buffer）
  - `sys_rst` ← 低电平有效复位
  - AXI4 接口：27-bit 地址，32-bit 数据，8-bit ID
  - 地址截断：`awaddr[26:0]`、`araddr[26:0]`
- **延迟展宽包装**（可选，Phase 5 再加）：初期先直连，验证基本功能
- **`ddr_aresetn` 处理**：`ddr_aresetn <= ~ui_clk_sync_rst && init_calib_complete`（与 chiplab 一致）
- **DDR3 引脚**：顶层输出，约束文件匹配 xc7a200t-fbg676

**约束**:
- MIG IP 参数：MT41J64M16XX-125, 16-bit, 800Mbps, 128MB（与 chiplab 一致）
- 仿真中使用 `_mig_sim.v`（SIM_BYPASS_INIT_CAL="FAST"），**绝不编译 `_mig.v`**
- MIG `sys_clk_i` 直接接外部时钟，不经过 clk_wiz（消除级联 MMCM 冲突）

---

### Phase 4: 时钟 + 复位架构（对齐 chiplab）

**目标**: 实现 chiplab 的 `generate` 三分支时钟架构和 `ddr_data_init` 门控

- **时钟架构** — `system_top.sv` 中 `generate` 三分支：
  ```
  if (SIMULATION && SIMU_USE_PLL==0):
      // 仿真模式：TB 直接生成时钟
      always #5.5 clk_91m = ~clk_91m;    // CPU 时钟
      always #2.5 clk_200m = ~clk_200m;  // DDR 参考时钟
      assign cpu_clk = clk_91m;
      assign sys_clk = clk;              // 100MHz 外部
      assign ddr_clk_ref = clk_200m;
  else if (SIMULATION && SIMU_USE_PLL==1):
      // 仿真+PLL：用 clk_pll IP（慢但更真实）
  else:
      // FPGA：用 clk_pll + clk_pll_ddr
  ```
- **`ddr_data_init` 门控**（关键！）：
  - `system_top` 新增 `ddr_data_init` 输入（或 wire）
  - 系统复位条件：`resetn & ddr_data_init`（DDR3 数据未加载时不释放 CPU）
  - 仿真 TB 中：`force ddr_data_init = 0` → 等 `init_calib_complete` → 写数据 → `force ddr_data_init = 1`
- **复位同步**：使用 `rst_sync` 模块（与 chiplab 一致），确保异步复位同步释放

**约束**:
- `SIMU_USE_PLL=0` 为默认仿真模式（最快）
- `SIMU_USE_DDR=0` 时用 SRAM 模型，`SIMU_USE_DDR=1` 时用 DDR3
- 仿真中不实例化任何 MMCM/PLL IP（`SIMU_USE_PLL=0` 时）
- FPGA 模式下 `ddr_data_init` 恒为 1（硬件上 CPU 从 Boot ROM 启动）

---

### Phase 5: 仿真基础设施

**目标**: 建立双路径仿真（SRAM 快速 + DDR3 验证），对齐 chiplab 的 TB 架构

- **SRAM 仿真路径**（`SIMU_USE_DDR=0`）：
  - AXI4 RAM 模型（行为级，零延迟或可配置延迟）
  - TB 直接 `$fread` 加载程序到 RAM
  - 用于日常开发、ISA 测试、性能测试
- **DDR3 仿真路径**（`SIMU_USE_DDR=1`）：
  - TB 实例化 `ddr3_model.sv` + `wiredly.v`（Micron 行为模型）
  - TB 等 `init_calib_complete` 后通过 MIG AXI 接口写程序到 DDR3
  - 写完后 toggle CDC 复位，释放 `ddr_data_init`
  - 用于 DDR3 通路验证、上板前确认
- **Vivado Orchestrator 适配**：
  - `tasks.yaml` 新增 `sim_mode: ddr3` / `sim_mode: sram` 区分
  - `operations.py` DDR3 仿真模型添加 + verilog defines 设置
  - `_mig_sim.v` 编译，移除 `_mig.v`

**约束**:
- SRAM 仿真路径必须**极快**（与当前无 DDR3 时相当）
- DDR3 仿真路径必须能完成 MIG 校准（使用 `_mig_sim.v` + FAST 模式）
- DDR3 仿真中 `ddr3_model` 的 `STOP_ON_ERROR` 设为 0（容错）
- TB 不使用任何 `force` workaround（这是对齐 chiplab 的核心目标）

---

### Phase 6: 延迟展宽 + 性能测试适配

**目标**: 移植 chiplab 的延迟展宽包装，使仿真接近真实硬件行为

- 移植 `axi_wrap_ddr.v` 的 R/B 通道延迟展宽逻辑
- 实现 `ram_random_mask` 延迟掩码（func 测试随机延迟 + perf 测试固定延迟倍增）
- `Delay_Multiple` 参数可配置（chiplab DDR3 用 5，SRAM 用 85/30）
- 性能测试时 R/B 通道延迟展宽使分数有意义

**约束**:
- 延迟展宽是**可选**的，初期可先跳过
- func 测试中随机延迟的种子必须可重现
- perf 测试分数必须与延迟倍增关闭时有明确对应关系

---

### Phase 7: FPGA 上板验证

**目标**: 在 xc7a200t-fbg676 开发板上完成综合、实现、上板

- **约束文件**：DDR3 引脚分配匹配开发板（参照 chiplab `soc_lite.xdc`）
- **时钟约束**：异步时钟组声明（cpu_clk/sys_clk/ddr_clk）
- **综合/实现**：Performance_Explore 策略，WNS ≥ 0
- **JTAG 下载**：JTAG AXI Master 写程序到 DDR3（参照 chiplab `jtag_axi_master.tcl`）
- **Boot 流程**：CPU 从 Boot ROM 启动 → DDR3 自检 → UART 加载 → 跳转

**约束**:
- WNS 不允许为负值
- 不修改综合/实现的优化参数
- DDR3 引脚 IOSTANDARD: SSTL15 / DIFF_SSTL15

---

## 全局约束

### 架构约束

| 约束 | 说明 |
|------|------|
| **总线协议** | 全程 AXI4，无 AHB-Lite |
| **MIG 集成** | 必须经过 AXI CDC（sys_clk → ui_clk），不允许直连 |
| **时钟架构** | `generate` 三分支（仿真/仿真+PLL/FPGA），不允许仿真中用 MMCM IP |
| **复位门控** | 系统复位必须等 `ddr_data_init`，不允许 CPU 在 DDR3 未就绪时启动 |
| **仿真模型** | DDR3 仿真必须用 `_mig_sim.v`，绝不编译 `_mig.v` |
| **无 force workaround** | 仿真中不使用任何 `force` 信号覆盖（chiplab 不需要，我们也不应该需要） |

### 兼容性约束

| 约束 | 说明 |
|------|------|
| **CPU 核内部不修改** | 仅改 `cpu_bus_bridge` 的输出协议，流水线逻辑不动 |
| **Cache 逻辑不修改** | icache/dcache 的 refill/write-back 语义不变，仅改总线协议 |
| **非 DDR3 外设不修改** | PLIC/CLINT/UART/SPI/GPIO 功能逻辑不变，仅改总线接口 |
| **向后兼容** | `SIMU_USE_DDR=0` 时行为与当前无 DDR3 时等价 |

### 参考约束

| 参考源 | 用途 |
|--------|------|
| `~/chiplab/chip/soc_demo/nscscc-team/soc_top.v` | 时钟三分支、DDR 条件编译、ddr_data_init 门控 |
| `~/chiplab/chip/soc_demo/nscscc-team/ram_wrap/axi_wrap_ddr.v` | DDR 包装层：CDC + 延迟展宽 + 地址重映射 |
| `~/chiplab/chip/soc_demo/nscscc-team/AMBA/Axi_CDC.v` | AXI4 跨时钟域桥（SpinalHDL 生成） |
| `~/chiplab/chip/soc_demo/nscscc-team/ram_wrap/axi_wrap_ram.v` | SRAM 仿真模型包装 |
| `~/chiplab/fpga/nscscc-team/testbench/mycpu_tb.sv` | 双路径 TB：SRAM 直接加载 / DDR3 AXI 写入 |
| `~/chiplab/chip/soc_demo/nscscc-team/soc_config.vh` | SIMU_USE_DDR / SIMU_USE_PLL 宏定义 |
| `~/chiplab/chip/soc_demo/nscscc-team/xilinx_ip/mig_axi_32/` | MIG IP 配置（XCI + mig_a.prj） |
| `~/chiplab/fpga/nscscc-team/constraints/soc_lite.xdc` | FPGA 约束（DDR3 引脚 + 异步时钟组） |
| `~/chiplab/fpga/nscscc-team/run_vivado/create_project.tcl` | Vivado 工程创建脚本 |
| `~/chiplab/IP/AMBA/axi3_to_axi4_bridge.v` | AXI3→AXI4 协议桥（若 CPU 输出 AXI3） |
| `~/chiplab/IP/AMBA/Axi_CDC.v` | AXI4 跨时钟域模块 |

---

## Phase 依赖关系

```
Phase 0 (清理)
  │
  ▼
Phase 1 (CPU AXI4 接口)
  │
  ▼
Phase 2 (AXI4 互联 + 从设备) ──→ Phase 3 (MIG + DDR3 集成)
  │                                      │
  └──────────────────────────────────────┘
                    │
                    ▼
              Phase 4 (时钟 + 复位)
                    │
                    ▼
              Phase 5 (仿真基础设施)
                    │
                    ▼
              Phase 6 (延迟展宽) ← 可选，初期可跳过
                    │
                    ▼
              Phase 7 (FPGA 上板)
```

Phase 2 和 Phase 3 可部分并行：Phase 2 先搭好 crossbar 和非 DDR3 从设备，Phase 3 独立开发 MIG 集成，最后合入。

---

## 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| AXI4 协议违规导致仿真死锁 | 高 | 使用 Xilinx AXI4 VIP 或协议检查器验证 |
| Axi_CDC 异步 FIFO 亚稳态 | 高 | 使用 chiplab 已验证的 SpinalHDL 生成模块，不自己写 |
| MIG 校准在完整系统中仍卡死 | 高 | 对齐 chiplab 的时钟架构（仿真直产时钟，无 MMCM），应可自然完成 |
| CPU AXI4 接口改造引入 bug | 中 | 逐步验证：先 SRAM 仿真通过，再 DDR3 仿真 |
| FPGA 引脚分配与开发板不匹配 | 中 | 直接参照 chiplab 的 soc_lite.xdc |
| 性能测试分数变化 | 低 | 延迟展宽参数与 chiplab 对齐 |

---

## 验收标准

| 验收项 | 标准 |
|--------|------|
| SRAM 仿真 (SIMU_USE_DDR=0) | ISA 测试全部通过，仿真速度与当前无 DDR3 时相当 |
| DDR3 仿真 (SIMU_USE_DDR=1) | MIG 校准自然完成（无 force），DDR3 读写正确 |
| DDR3 全系统仿真 | CPU 从 Boot ROM 启动 → DDR3 自检 → 执行测试程序 → PASS |
| FPGA 综合/实现 | WNS ≥ 0，bitstream 生成成功 |
| FPGA 上板 | DDR3 自检 LED 亮，程序加载执行正确 |

---

## 详细实施规格（Phase 0-7）

### Phase 0 详细步骤

#### 0.1 创建 `dev/rtl/soc_config.vh`
```verilog
// SoC 配置宏 — 参照 chiplab soc_config.vh
`define SIMU_USE_PLL 0   // 0=仿真直产时钟(快), 1=仿真用PLL(慢)
`define SIMU_USE_DDR 0   // 0=SRAM模型(快), 1=DDR3(真实)
```

#### 0.2 删除/归档文件
| 文件 | 操作 | 原因 |
|------|------|------|
| `dev/rtl/AHB-lite/ddr3_bridge_wrapper.sv` | 删除 | AHB→AXI4 bridge IP 不再需要，CPU 直出 AXI4 |
| `dev/rtl/AHB-lite/ahb_lite_bus.sv` | 归档到 `dev/rtl/_archived/ahb/` | 整个 AHB bus 被 AXI4 interconnect 替代 |
| `dev/rtl/AHB-lite/ahb_mux.sv` | 归档 | AHB 响应 mux 被 crossbar 替代 |
| `dev/rtl/AHB-lite/ahb_decoder.sv` | 归档 | 已未使用，crossbar 自带 decode |
| `dev/rtl/AHB-lite/ahb_def.svh` | 归档 | 被 `axi4_def.svh` 替代 |
| `dev/rtl/AHB-lite/ahb_sys_status.sv` | 重写为 AXI4-Lite | 保留功能，改接口 |
| `dev/rtl/AHB-lite/ahb_default_slave.sv` | 重写为 AXI4-Lite | 保留功能，改接口 |
| `dev/rtl/AHB-lite/ahb_bootrom_slave.sv` | 重写为 AXI4-Lite | 保留功能，改接口 |
| DDR3 workaround TBs (`tb_ddr3_system*.sv`) | 删除 | 不再需要 force workaround |

#### 0.3 创建 `dev/rtl/axi4_def.svh`
```systemverilog
// AXI4 常量定义 — 替代 ahb_def.svh
// Response
localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;
localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
localparam logic [1:0] AXI_RESP_DECERR = 2'b11;
// Burst
localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;
// Size
localparam logic [2:0] AXI_SIZE_1B  = 3'b000;
localparam logic [2:0] AXI_SIZE_2B  = 3'b001;
localparam logic [2:0] AXI_SIZE_4B  = 3'b010;
localparam logic [2:0] AXI_SIZE_8B  = 3'b011;
// Cache
localparam logic [3:0] AXI_CACHE_DEV_NONBUF = 4'b0000; // Device Non-bufferable
localparam logic [3:0] AXI_CACHE_NORM_BUF   = 4'b0011; // Normal Non-cacheable Bufferable
// Prot
localparam logic [2:0] AXI_PROT_DATA_PRIV   = 3'b000; // Data, Privileged, Secure
localparam logic [2:0] AXI_PROT_INST_PRIV   = 3'b010; // Instruction, Privileged, Secure
```

#### 0.4 确认 `vivado_config.yaml`
- `device_part: xc7a200tfbg676-2` ✓ (已正确)

---

### Phase 1 详细步骤

#### 1.1 重写 `dev/rtl/core/cpu_bus_bridge.sv`

**当前接口（AHB-Lite master，11 信号）：**
```
output [31:0] HADDR, output [1:0] HTRANS, output HWRITE, output [2:0] HSIZE,
output [2:0] HBURST, output [3:0] HPROT, output HMASTLOCK, output [31:0] HWDATA,
input [31:0] HRDATA, input HREADY, input HRESP
```

**新接口（AXI4 master，5 通道）：**
```systemverilog
// AW 通道 (Write Address)
output logic        awvalid,  input  logic        awready,
output logic [31:0] awaddr,   output logic [7:0]  awlen,
output logic [2:0]  awsize,   output logic [1:0]  awburst,
output logic        awlock,   output logic [3:0]  awcache,
output logic [2:0]  awprot,
// W 通道 (Write Data)
output logic        wvalid,   input  logic        wready,
output logic [31:0] wdata,    output logic [3:0]  wstrb,
output logic        wlast,
// B 通道 (Write Response)
input  logic        bvalid,   output logic        bready,
input  logic [1:0]  bresp,
// AR 通道 (Read Address)
output logic        arvalid,  input  logic        arready,
output logic [31:0] araddr,   output logic [7:0]  arlen,
output logic [2:0]  arsize,   output logic [1:0]  arburst,
output logic        arlock,   output logic [3:0]  arcache,
output logic [2:0]  arprot,
// R 通道 (Read Data)
input  logic        rvalid,   output logic        rready,
input  logic [31:0] rdata,    input  logic [1:0]  rresp,
input  logic        rlast
```

**FSM 改造要点：**
- AHB `HTRANS==NONSEQ` → AXI4 `awvalid=1`/`arvalid=1`
- AHB `HREADY` → AXI4 各通道独立 `awready`/`wready`/`arready`/`rready`
- AHB `HWDATA` 在 data phase → AXI4 W 通道 `wvalid`/`wdata`/`wstrb`/`wlast`
- AHB `HRDATA` → AXI4 R 通道 `rdata`/`rresp`/`rlast`
- AHB `HRESP` → AXI4 `bresp`（写）/ `rresp`（读）
- Burst: AHB `INCR8` → AXI4 `awlen=8'h07, awburst=AXI_BURST_INCR`
- 单拍 MMIO → AXI4 `awlen=8'h00, wlast=1'b1`
- **AW 和 W 通道可同拍发出**（AXI4 允许），简化 FSM
- **VALID 不可依赖 READY**（AXI4 握手规则），避免组合环路
- **AWID/ARID 恒为 4'b0000**（单 master，无需 ID 区分）
- **AWQOS/ARQOS = 4'b0, AWREGION/ARREGION = 4'b0**

#### 1.2 修改 `dev/rtl/core/core_top.sv`
- 移除 11 个 AHB-Lite 端口
- 添加 AXI4 master 5 通道端口（同上信号列表）
- 更新 `cpu_bus_bridge` 例化端口连接
- 添加 `include "axi4_def.svh"`

#### 1.3 chiplab 参考链路
chiplab 的完整链路：`core_top (AXI3, ID=4bit, len=4bit) → axi3_to_axi4_bridge → Axi_CDC → crossbar → DDR/RAM`

**我们的简化链路**：`core_top (AXI4, ID=4bit, len=8bit) → Axi_CDC → crossbar → DDR/RAM`

我们跳过 AXI3→AXI4 bridge（CPU 直出 AXI4，不需要 bridge）。CPU 内部 cache refill 用 INCR8 burst（len=7），MMIO 用单拍（len=0）。

---

### Phase 2 详细步骤

#### 2.1 创建 Xilinx AXI Crossbar IP
- **IP**: `axi_interconnect` (或 `axi_crossbar`)
- **配置**: 2 SI × 5 MI（参照 chiplab `axi_crossbar_2x3`，但我们有更多从设备）
- **参数**:
  - NUM_SI = 2 (CPU + JTAG)
  - NUM_MI = 5 (DDR3 + BootROM + PLIC+CLINT + APB + CONFREG)
  - PROTOCOL = AXI4
  - DATA_WIDTH = 32, ADDR_WIDTH = 32, ID_WIDTH = 4

#### 2.2 地址映射（从当前 ahb_lite_bus.sv 迁移）
| Crossbar MI | 从设备 | 地址范围 | Decode 条件 |
|-------------|--------|----------|-------------|
| M00_AXI | DDR3 (via CDC+MIG) | `0x8000_0000`–`0x8FFF_FFFF` | addr[31:28]==4'h8 |
| M01_AXI | Boot ROM | `0xFC00_0000`–`0xFCFF_FFFF` | addr[31:24]==8'hFC |
| M02_AXI | PLIC | `0x0C00_0000`–`0x0CFF_FFFF` | addr[31:24]==8'h0C |
| M03_AXI | CLINT | `0x0200_0000`–`0x02FF_FFFF` | addr[31:24]==8'h02 |
| M04_AXI | APB Bridge | `0x1000_0000`–`0x10FF_FFFF` | addr[31:24]==8'h10 |

**注意**: PLIC 和 CLINT 可以合并到同一 crossbar MI（共享地址空间不重叠），或分开。chiplab 用 3 MI (UART+RAM+CONFREG)，我们用 5 MI。如 crossbar 不支持 5 MI，可级联或用 `axi_interconnect`。

#### 2.3 从设备 AXI4-Lite 适配

**每个 AHB 从设备需要 AXI4-Lite wrapper**。通用 wrapper 模式：

```systemverilog
module axi4lite_to_ahb_wrapper (
    // AXI4-Lite slave input
    input  logic        s_axi_aclk,    input  logic        s_axi_aresetn,
    input  logic [31:0] s_axi_awaddr,  input  logic [2:0] s_axi_awprot,
    input  logic        s_axi_awvalid, output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,   input  logic [3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,  output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,   output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,  input  logic [2:0] s_axi_arprot,
    input  logic        s_axi_arvalid, output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,   output logic [1:0] s_axi_rresp,
    output logic        s_axi_rvalid,  input  logic        s_axi_rready,
    // AHB-like internal interface to existing slave logic
    output logic [31:0] ahb_addr,      output logic        ahb_write,
    output logic [31:0] ahb_wdata,     output logic [2:0]  ahb_size,
    output logic        ahb_req,       input  logic        ahb_ack,
    input  logic [31:0] ahb_rdata,     input  logic        ahb_resp
);
```

**需适配的从设备**:
| 从设备 | 当前文件 | 新文件 | 特点 |
|--------|----------|--------|------|
| PLIC | `ahb_plic.sv` | `axi4lite_plic.sv` | 中断逻辑不变，改接口 |
| CLINT | `ahb_clint.sv` | `axi4lite_clint.sv` | mtime/msip 逻辑不变 |
| Boot ROM | `ahb_bootrom_slave.sv` | `axi4lite_bootrom.sv` | 只读 BRAM |
| APB Bridge | `ahb_lite_to_apb.sv` | `axi4lite_to_apb.sv` | AXI4-Lite→APB 桥 |
| Default Slave | `ahb_default_slave.sv` | `axi4lite_default_slave.sv` | 返回 DECERR |
| Sys Status | `ahb_sys_status.sv` | `axi4lite_sys_status.sv` | 读 MIG/MMCM 状态 |

#### 2.4 APB 子系统
- APB 子系统（`apb_bus.sv`, `apb_decoder.sv`, `apb_perips.sv`）**不修改**
- 仅替换 `ahb_lite_to_apb.sv` 为 `axi4lite_to_apb.sv`
- APB 从设备（GPIO, UART, SPI, Timer）**不修改**

---

### Phase 3 详细步骤

#### 3.1 复制 Axi_CDC
- 从 `~/chiplab/chip/soc_demo/nscscc-team/AMBA/Axi_CDC.v` 复制到 `dev/rtl/AMBA/Axi_CDC.v`
- 1606 行 SpinalHDL 生成，**不修改**
- 注意：`awlock`/`arlock` 是 `[0:0]` 宽度（SpinalHDL artifact），连接时需匹配

#### 3.2 创建 `dev/rtl/ram_wrap/axi_wrap_ddr.sv`
参照 chiplab `axi_wrap_ddr.v`，关键组件：

**模块端口**（与 chiplab 一致）：
- `aclk`, `aresetn` — sys_clk 域
- `xtal_clk`, `button_resetn` — MIG 原始时钟/复位
- `ddr_clk_ref` — 200MHz DDR 参考时钟
- `ddr_aresetn` (output reg) — 反馈到 system_top 复位链
- AXI4 slave 端口：ID=4bit, addr=32bit, data=32bit, len=8bit
- `ram_random_mask[4:0]` — 延迟掩码（Phase 6 用，初期接 5'b0）
- DDR3 物理引脚

**内部结构**：
```
AXI4 slave (sys_clk域)
  → [地址重映射: 0x8000_xxxx → pass through, 其他 → remap]
  → Axi_CDC (sys_clk → ui_clk)
  → MIG AXI4 slave (ui_clk域)
  → DDR3 物理引脚
```

**ddr_aresetn 逻辑**（与 chiplab 完全一致）：
```verilog
always @(posedge ui_clk) begin
    ddr_aresetn <= ~ui_clk_sync_rst && init_calib_complete;
end
```

**MIG 例化**（参照 chiplab，关键连接）：
- `.sys_clk_i(xtal_clk)` — 直连外部 100MHz
- `.sys_rst(button_resetn)` — 直连外部复位
- `.clk_ref_i(ddr_clk_ref)` — 200MHz 参考时钟
- `.s_axi_awaddr(mig_awaddr[26:0])` — 地址截断到 27-bit
- `.s_axi_araddr(mig_araddr[26:0])` — 同上
- `.s_axi_awqos(4'b0)`, `.s_axi_arqos(4'b0)` — QoS 不用

#### 3.3 创建 `dev/rtl/ram_wrap/axi_wrap_ram.sv`
参照 chiplab `axi_wrap_ram.v`：
- AXI4 slave → 行为级 BRAM 模型
- 支持 INCR burst
- `ram_random_mask` 控制延迟（初期接 0，无延迟）
- 用于 `SIMU_USE_DDR=0` 快速仿真

#### 3.4 地址重映射
chiplab 的地址重映射将非 0/1/7 段地址映射到 0xF 段。我们的 DDR3 基地址是 `0x8000_0000`（addr[31:28]==4'h8），需要调整重映射逻辑：
```verilog
// AR 地址重映射
assign ram_araddr = (axi_araddr[31:28] == 4'h8) ? axi_araddr :  // DDR3 直通
                    {12'b0, 4'hf, axi_araddr[31:28], axi_araddr[11:0]};  // 其他 remap
```

---

### Phase 4 详细步骤

#### 4.1 system_top.sv 时钟 generate 三分支
参照 chiplab `soc_top.v` lines 147-226：

```systemverilog
generate
if (SIMULATION && `SIMU_USE_PLL==0) begin: sim_clk
    // 仿真：TB 直接产时钟，不实例化任何 PLL
    initial begin clk_91m = 0; clk_200m = 0; end
    always #5.5  clk_91m  = ~clk_91m;   // ~91MHz CPU
    always #2.5  clk_200m = ~clk_200m;  // 200MHz DDR ref
    assign cpu_clk     = clk_91m;
    assign sys_clk     = clk;            // 100MHz 外部
    assign ddr_clk_ref = clk_200m;
    rst_sync u_rst_sys(.clk(sys_clk), .rst_n_in(resetn & ddr_data_init), .rst_n_out(sys_resetn));
    rst_sync u_rst_cpu(.clk(cpu_clk), .rst_n_in(sys_resetn), .rst_n_out(cpu_resetn));
end
else if (SIMULATION && `SIMU_USE_PLL==1) begin: sim_pll_clk
    // 仿真+PLL：用 clk_pll IP（慢但更真实）
    clk_pll u_clk_pll(...);
    clk_pll_ddr u_clk_pll_ddr(...);
    rst_sync u_rst_sys(.clk(sys_clk), .rst_n_in(pll_locked & pll_locked_ddr & ddr_data_init), .rst_n_out(sys_resetn));
    rst_sync u_rst_cpu(.clk(cpu_clk), .rst_n_in(sys_resetn), .rst_n_out(cpu_resetn));
end
else begin: fpga_pll
    // FPGA：用 clk_pll + clk_pll_ddr
    clk_pll u_clk_pll(...);
    clk_pll_ddr u_clk_pll_ddr(...);
    rst_sync u_rst_sys(.clk(sys_clk), .rst_n_in(pll_locked & pll_locked_ddr & ddr_aresetn), .rst_n_out(sys_resetn));
    rst_sync u_rst_cpu(.clk(cpu_clk), .rst_n_in(core_rst_n), .rst_n_out(cpu_resetn));
end
endgenerate
```

**关键差异**：
| 分支 | sys_resetn 门控 | cpu_resetn 来源 |
|------|----------------|-----------------|
| sim_clk | `resetn & ddr_data_init` | `sys_resetn` |
| sim_pll_clk | `pll_locked & pll_locked_ddr & ddr_data_init` | `sys_resetn` |
| fpga_pll | `pll_locked & pll_locked_ddr & ddr_aresetn` | `core_rst_n` (JTAG) |

#### 4.2 ddr_data_init wire
```systemverilog
wire ddr_data_init;  // 仿真中由 TB force，FPGA 中恒为 1
```

#### 4.3 DDR/SRAM 条件编译
```systemverilog
generate
if (SIMULATION && `SIMU_USE_DDR==0) begin: sim_ram
    axi_wrap_ram u_axi_ram(.aclk(sys_clk), .aresetn(sys_resetn), ...);
end
else begin: ddr3
    axi_wrap_ddr u_axi_wrap_ddr(
        .aclk(sys_clk), .aresetn(sys_resetn),
        .xtal_clk(clk), .button_resetn(resetn),
        .ddr_clk_ref(ddr_clk_ref),
        .ddr_aresetn(ddr_aresetn), ...
    );
end
endgenerate
```

#### 4.4 rst_sync 模块
参照 chiplab，异步复位同步释放：
```systemverilog
module rst_sync(input clk, input rst_n_in, output reg rst_n_out);
    reg rst_n_d1;
    always @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) begin rst_n_d1 <= 0; rst_n_out <= 0; end
        else begin rst_n_d1 <= 1; rst_n_out <= rst_n_d1; end
    end
endmodule
```

---

### Phase 5 详细步骤

#### 5.1 创建 `dev/rtl/testbench/tb_soc.sv`
参照 chiplab `mycpu_tb.sv`，双路径 TB：

**公共部分**：
```systemverilog
initial begin clk = 0; resetn = 0; #2000; resetn = 1; end
always #5 clk = ~clk;  // 100MHz
```

**SRAM 路径** (`SIMU_USE_DDR==0`)：
```systemverilog
initial begin
    integer fd, i; reg [31:0] instr;
    fd = $fopen("inst_data.bin", "rb");
    for (i=0; i<262144; i=i+1) begin
        if ($fread(instr, fd))
            u_soc_top.sim_ram.u_axi_ram.BRAM[i] <= {instr[7:0],instr[15:8],instr[23:16],instr[31:24]}; // endian swap
        else
            u_soc_top.sim_ram.u_axi_ram.BRAM[i] <= 0;
    end
    $fclose(fd);
end
```

**DDR3 路径** (`SIMU_USE_DDR==1`)：
```systemverilog
`define MIG_AXI u_soc_top.ddr3.u_axi_wrap_ddr.mig_axi

initial begin
    force u_soc_top.ddr_data_init = 1'b0;                     // 1. 保持系统复位
    wait(`MIG_AXI.init_calib_complete);                        // 2. 等 MIG 校准完成
    write_file(32'h80000000, "inst_data.bin");                 // 3. 写程序到 DDR3 (基址 0x8000_0000)
    @(posedge `MIG_AXI.ui_clk);                                // 4. 等 1 个 MIG 时钟
    force u_soc_top.ddr3.u_axi_wrap_ddr.u_Axi_CDC.axiOutRst = 1'b0;  // 5. 复位 CDC 输出域
    @(posedge `MIG_AXI.ui_clk);
    force u_soc_top.ddr3.u_axi_wrap_ddr.u_Axi_CDC.axiOutRst = 1'b1;  // 6. 释放 CDC 复位
    force u_soc_top.ddr_data_init = 1'b1;                     // 7. 释放系统复位，CPU 开始执行
end
```

**DDR3 模型例化**：
```systemverilog
ddr3_model u_ddr3_model(
    .rst_n(resetn), .ck(ddr3_ck_p), .ck_n(ddr3_ck_n),
    .cke(ddr3_cke), .cs_n(1'b0), .ras_n(ddr3_ras_n), .cas_n(ddr3_cas_n),
    .we_n(ddr3_we_n), .dm_tdqs(ddr3_dm), .ba(ddr3_ba), .addr(ddr3_addr),
    .dq(ddr3_dq), .dqs(ddr3_dqs_p), .dqs_n(ddr3_dqs_n), .odt(ddr3_odt)
);
```

#### 5.2 axi4_write task
参照 chiplab `mycpu_tb.sv` lines 271-310，通过 MIG AXI4 slave 接口直接写 DDR3：
- force AW 通道 (awid=4'b0001, awaddr[26:0], awlen=0, awsize=2, awburst=INCR)
- force W 通道 (wdata, wstrb=4'b1111, wlast=1)
- force B 通道 (bready=1, 等 bvalid)
- 每次写 4 字节，endian swap

#### 5.3 Vivado Orchestrator 适配
- `tasks.yaml`: 新增 `sim_mode: sram` / `sim_mode: ddr3`
- `operations.py`: DDR3 模式添加 `ddr3_model.sv` + `ddr3_model_parameters.vh` 到 sim fileset
- 确保 `_mig_sim.v` 编译（非 `_mig.v`）
- 设置 verilog defines: `SIMULATION=1`, `SIMU_USE_DDR=0/1`

---

### Phase 6 详细步骤（可选，初期跳过）

- 移植 chiplab `axi_wrap_ddr.v` 的 R/B 通道延迟展宽逻辑
- `ram_random_mask` 接 CONFREG 寄存器输出
- func 测试：随机延迟（seed 可重现）
- perf 测试：固定延迟倍增（`Delay_Multiple` 参数）

---

### Phase 7 详细步骤

#### 7.1 FPGA 约束文件
参照 chiplab `soc_lite.xdc`：
- 主时钟：`AC19`, 10ns, BACKBONE route
- 复位：`Y3`
- DDR3 引脚：与 chiplab 完全相同（已确认 pin assignment 一致）
- 异步时钟组：`set_clock_groups -asynchronous -group [clk] -group [cpu_clk] -group [sys_clk] -group [ddr_clk]`

#### 7.2 Xilinx IP 列表
| IP | 用途 |
|----|------|
| `clk_pll` (clk_wiz:6.0) | 100MHz → cpu_clk(33MHz) + sys_clk(100MHz) |
| `clk_pll_ddr` (clk_wiz:6.0) | 100MHz → ddr_clk(200MHz) |
| `axi_crossbar_2x5` (axi_crossbar:2.1) | 2 master × 5 slave AXI4 crossbar |
| `jtag_axi` (jtag_axi:1.2) | JTAG → AXI4 master (上板用) |
| `mig_axi_32` (mig_7series:4.2) | DDR3 控制器 |

#### 7.3 综合/实现
- Synth strategy: `Flow_PerfOptimized_high`
- Impl strategy: `Performance_Explore`
- 验收：WNS ≥ 0

---

## 当前项目架构 → 目标架构对照

### 当前（AHB-Lite）
```
core_top (AHB-Lite master)
  → ahb_lite_bus (inline decode + mux)
    → ddr3_bridge_wrapper (AHB→AXI4 bridge IP → MIG → DDR3)
    → ahb_bootrom_slave
    → ahb_plic
    → ahb_clint
    → ahb_lite_to_apb → APB bus → GPIO/UART/SPI/Timer
    → ahb_sys_status
    → ahb_default_slave
```

### 目标（AXI4，对齐 chiplab）
```
core_top (AXI4 master, ID=4bit)
  → Axi_CDC (cpu_clk → sys_clk)
    → axi_crossbar_2x5 (Xilinx IP)
      → [M00] axi_wrap_ddr (Axi_CDC sys_clk→ui_clk → MIG → DDR3)
      → [M01] axi4lite_bootrom
      → [M02] axi4lite_plic
      → [M03] axi4lite_clint
      → [M04] axi4lite_to_apb → APB bus → GPIO/UART/SPI/Timer
  jtag_axi (AXI4 master, 上板用)
    → axi_crossbar_2x5 (S01)
```

**关键简化**：去掉 `ddr3_bridge_wrapper` 中的 AHB→AXI4 bridge IP，CPU 直出 AXI4 经 CDC 到 crossbar 到 MIG。
