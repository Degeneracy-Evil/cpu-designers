---
name: vivado-orchestrator
description: |
  Vivado simulation/build orchestration with session isolation and incremental refresh.
  Use this skill when running simulations, generating bitstreams, programming FPGAs,
  managing Vivado sessions, checking staleness, or refreshing projects.
  Replaces the old vivado_do.tcl with a Python-based system supporting parallel sessions,
  layered hash staleness detection, incremental (layer-specific) refresh, and batch
  execution for running multiple tasks in parallel from a single command.
---

# Vivado Orchestrator

Python 驱动的 Vivado 自动化系统，替代 `vivado_do.tcl`。支持**会话隔离并行**、**分层哈希增量刷新**、**批处理模式**、**IP 仿真模型自动注入**。

## 架构

```
vivado_core/
├── session.py    会话管理 + Semaphore 并发门控
├── operations.py 高层操作 (create/refresh/sim/bitstream/program/archive)
├── batch.py      批处理执行 (ThreadPoolExecutor + 进度追踪 + 失败策略)
├── sync.py       预检 + 增量/全量刷新规划
├── hash.py       分层哈希 (rtl/tb/src/coe/fpga)
├── tasks.py      任务配置 (tasks.yaml)
├── config.py     全局配置 + 内存/Cache/DDR3/Bridge/ClkWiz 配置
├── ip_gen.py     BRAM/MIG/Bridge/ClkWiz create_ip TCL 生成 + get_bram_ip_names()
├── cache_header_gen.py  cache_def.svh 自动生成
└── exceptions.py 异常层次

vivado_cli.py     CLI 前端 (含批处理)
vivado_tui.py     TUI 前端
```

## 核心命令

所有命令通过 CLI 执行：

```bash
python -m tools.vivado_cli <args>
```

### 会话管理

```bash
# 保留 (max_sessions - 1) 个最近使用的会话，仅清理最老的，腾出一个创建新会话的空间
# 不会清空全部空闲会话！如果批量运行(batch)后产生大量旧会话，需要用 --cleanup-all
python -m tools.vivado_cli --cleanup

# 彻底清理全部会话（包括空闲、报错的会话）
python -m tools.vivado_cli --cleanup-all

# 重新生成 cache_def.svh（修改 vivado_config.yaml 后）
python -m tools.vivado_cli --gen-config
```

### 仿真

```bash
# 首次：创建会话 + 仿真
python -m tools.vivado_cli -task cpu_full -create -sim

# 复用已有会话仿真
python -m tools.vivado_cli -task cpu_full -sim

# 覆盖仿真时间
python -m tools.vivado_cli -task cpu_full -sim -runtime 10ms

# 自定义会话名（同 task 多会话并行）
python -m tools.vivado_cli -task cpu_full -session cpu_v2 -sim
```

### 刷新

```bash
# 全量刷新（RTL 变更后）
python -m tools.vivado_cli -task cpu_full -refresh

# 增量刷新：仅 COE（改了程序后）
python -m tools.vivado_cli -task cpu_full -refresh --layers coe

# 增量刷新：仅 TB（改了 testbench 后）
python -m tools.vivado_cli -task cpu_full -refresh --layers tb

# 增量刷新：多层
python -m tools.vivado_cli -task cpu_full -refresh --layers coe,tb
```

### 综合/下载

```bash
# 生成 bitstream
python -m tools.vivado_cli -task fpga -bitstream

# 连接硬件
python -m tools.vivado_cli -task fpga -hw-connect

# 下载到 FPGA
python -m tools.vivado_cli -task fpga -program

# 导出工程归档
python -m tools.vivado_cli -task cpu_full -archive
```

## 可用任务

| 任务 | Testbench | 说明 |
|------|-----------|------|
| `cpu_full` | tb_simple_cpu_top | CPU 全功能测试 (5ms) |
| `cpu_compute` | tb_simple_cpu_compute | CPU 计算/访存测试 (5ms) |
| `cpu_trap` | tb_simple_cpu_trap | CPU 异常/陷阱测试 (3ms) |
| `cpu_fencei` | tb_cpu_test_fencei | fence.i JIT 测试 (5ms) |
| `cpu_access_fault` | tb_cpu_test_access_fault | 访问错误异常 (3ms) |
| `cpu_priv` | tb_simple_cpu_priv | 特权级测试 (20ms) |
| `isa_alu` | tb_isa_alu | ISA ALU 测试 (5ms) |
| `isa_branch` | tb_isa_branch | ISA 分支测试 (5ms) |
| `isa_memory` | tb_isa_memory | ISA 访存测试 (5ms) |
| `isa_upper_imm` | tb_isa_upper_imm | ISA 上立即数测试 (5ms) |
| `isa_jump` | tb_isa_jump | ISA 跳转测试 (5ms) |
| `isa_csr` | tb_isa_csr | ISA CSR 测试 (5ms) |
| `isa_m_ext` | tb_isa_m_ext | ISA 乘除扩展测试 (5ms) |
| `isa_f_ext` | tb_isa_f_ext | ISA 浮点扩展测试 (10ms) |
| `isa_f_ext_special` | tb_isa_f_ext_special | ISA 浮点特殊值测试 (10ms) |
| `exception_*` | (6 个) | 异常测试 (5-10ms) |
| `privilege_*` | (3 个) | 特权级测试 (10-20ms) |
| `mmu_*` | (11 个) | MMU/TLB 测试 (20-60ms) |
| `cache_*` | (5 个) | Cache 测试 (5-20ms) |
| `mmio_*` | (2 个) | MMIO 测试 (5-10ms) |
| `reg_*` | (7 个) | 回归测试 (10-20ms) |
| `fpu_adder` | tb_fpu_adder | FPU 加法器 (10us) |
| `fpu_multiplier` | tb_fpu_multiplier | FPU 乘法器 (10us) |
| `fpu_divider` | tb_fpu_divider | FPU 除法器 (50us) |
| `fpu_sqrt` | tb_fpu_sqrt | FPU 开方 (50us) |
| `fpu_cvt` | tb_fpu_cvt | FPU 转换 (10us) |
| `fpu_unit` | tb_fpu_unit | FPU 单元集成 (50us) |
| `uart_hello` | tb_uart_hello | UART 发送测试 (40ms) |
| `uart_echo` | tb_uart_echo | UART 回显测试 (100ms) |
| `led_marquee` | tb_led_marquee | LED 走马灯 (2s) |
| `calculator` | tb_calculator | 计算器应用 (100ms) |
| `ahb_bus` | tb_ahb_bus | AHB 总线测试 (5000ns) |
| `apb_perips` | tb_apb_perips | APB 外设测试 (2000ns) |
| `alu_integration` | tb_alu_cpu_integration | ALU 集成测试 (5000ns) |
| `mu_unit` | tb_mu_unit | 乘除法器测试 (5000ns) |
| `divider` | tb_non_restoring_divider | 除法器测试 (5000ns) |
| `fpga` | — | FPGA bitstream (top: system_top) |
| `ddr3_mig_ex` | tb_ddr3_mig_ex | MIG DDR3 控制器测试 (1000us) |
| `ddr3_ahb_ex` | tb_ddr3_ahb_ex | AHB+DDR3 测试 (1000us) |
| `ddr3_basic` | tb_ddr3_basic | DDR3 基础测试 (1000us) |
| `ddr3_system` | tb_ddr3_system | 全系统 DDR3 测试 (100ms) |
| `ddr3_system_v2` | tb_ddr3_system_v2 | DDR3 系统 v2 (100ms) |
| `ddr3_system_v3` | tb_ddr3_system_v3 | DDR3 系统 v3 (100ms) |

> 通配符速查：`isa_*`(9), `exception_*`(6), `privilege_*`(3), `mmu_*`(11), `cache_*`(5), `mmio_*`(2), `reg_*`(7), `fpu_*`(6), `cpu_*`(5), `ddr3_*`(7)

## IP 仿真策略（参照 chiplab）

### 核心问题

Xilinx IP（BRAM、MIG、Bridge、ClkWiz）由 `create_ip` 生成，但 XSim 的依赖解析器无法自动发现 IP 的行为仿真模型。若不手动添加仿真模型到 `sim_1`，XSim 在 elaborate 阶段报 "module <IP> not found"。

### 解决方案：三层策略

**1. 条件 generate 块（避免实例化不必要的 IP）**

`system_top.sv` 使用 `ifdef SIMULATION` + `SIMU_USE_PLL` / `SIMU_USE_DDR` 条件编译，参照 chiplab 的 `soc_top.v` + `soc_config.vh` 模式：

```systemverilog
// soc_config.vh — 用户控制仿真行为
`define SIMU_USE_PLL 0   // 0=直产时钟（快），1=PLL IP（慢）
`define SIMU_USE_DDR 0   // 0=SRAM 行为模型（快），1=MIG DDR3（慢）

// system_top.sv — 三分支时钟 + 双分支内存
`ifdef SIMULATION
    if (`SIMU_USE_PLL == 0) begin: sim_clk     // 直产时钟
    else begin: sim_pll_clk                      // PLL IP
`else
    begin: fpga_clk                              // FPGA: PLL IP
`endif

`ifdef SIMULATION
    if (`SIMU_USE_DDR == 0) begin: sim_ram      // SRAM 行为模型
    else begin: ddr3                             // MIG DDR3
`else
    begin: ddr3                                  // FPGA: DDR3
`endif
```

非 DDR3 仿真任务自动设置 `SIMULATION=TRUE` verilog define，激活 `soc_config.vh` 中的快速路径。

**2. BRAM 仿真模型自动注入（所有仿真任务）**

BRAM IP（ROM、icached、dcached、icachet、dcachet、tlb_flag、tlb_data）由 CPU 核心直接实例化，无法通过 generate 块绕过。orchestrator 自动为**所有仿真任务**添加 BRAM 行为仿真模型到 `sim_1`：

- `sim/<IP>.v` — IP 包装器（每个 IP 独有）
- `simulation/blk_mem_gen_v8_4.v` — 行为仿真模型（所有 BRAM IP 共享，仅添加一次）

BRAM IP 列表由 `ip_gen.get_bram_ip_names(mem_config)` 从 `MemoryConfig` 动态推导，而非硬编码。修改 `use_tag_bram` / `use_tlb_bram` 后列表自动更新。

**3. DDR3 仿真模型（仅 ddr3 任务）**

DDR3 仿真任务额外添加 MIG 仿真模型 + DDR3 SDRAM 行为模型 + verilog defines。

### IP gen 清理 + upgrade_ip（chiplab 模式）

参照 chiplab 的 `create_project.tcl`：

1. **IP gen 目录清理**：项目创建前删除所有 IP 的 `gen/` 子目录，强制 Vivado 从 `create_ip` 重新定制 IP，避免过期的输出产物导致仿真失败
2. **upgrade_ip**：所有 IP 创建后执行 `upgrade_ip -quiet [get_ips]`，处理 Vivado 版本差异导致的 IP 版本迁移

## 分层哈希与增量刷新

源文件分五层，独立哈希检测变更：

| 层 | 范围 | 刷新代价 |
|----|------|----------|
| `rtl` | dev/rtl/** + Reference/** + vivado_config.yaml + tools/vivado_core/**/*.py | 全量重建（分钟级） |
| `tb` | dev/tb/** | 重加 testbench（秒级） |
| `src` | dev/program_source/** (源码) | 需重新编译 COE |
| `coe` | dev/program_source/**/*.coe + .hex | 更新 COE 配置（秒级） |
| `fpga` | dev/fpga/** + tools/vivado_core/tcl/** | 重加约束（秒级） |

**同步策略**：
- RTL stale → 硬错误，必须全量刷新
- COE stale → 硬错误（否则仿真用旧固件）
- TB/FPGA stale → 软警告，可增量刷新
- 全部 fresh → 直接执行

## 输出筛选

```bash
# 仅错误
python -m tools.vivado_cli -task cpu_full -sim --filter error

# 仅 PASS/FAIL 结果
python -m tools.vivado_cli -task cpu_full -sim --filter pass_fail

# 自定义正则
python -m tools.vivado_cli -task cpu_full -sim --filter "PASS.*x1"
```

## 批处理参数

| 参数 | 说明 |
|------|------|
| `-batch TASKS` | 逗号分隔任务名或通配符（如 `isa_*`、`cpu_*,uart_hello`） |
| `-batch-plan FILE` | YAML 批处理计划文件 |
| `--max-parallel N` | 最大并行会话数（默认=min(任务数, max_concurrent)） |
| `--on-error STRATEGY` | `continue`（默认）/ `fail-fast`（首败即停）/ `stop-accepting`（停提交等完成） |

### 并发门控

`SessionManager` 使用 `threading.Semaphore(max_concurrent)` 原子控制 Vivado 进程并发数，`Session.start_vivado()` 时 acquire，`stop_vivado()` 时 release。批处理模式下 `ThreadPoolExecutor` 的 `max_workers` 由 `min(len(tasks), max_concurrent, --max-parallel)` 决定。

## TUI 界面

```bash
pip install textual
python tools/vivado_tui.py
```

提供：会话面板、任务下拉、操作按钮、TCL 命令输入、实时输出。

## 典型工作流

### 1. 首次仿真

```bash
python -m tools.vivado_cli -task cpu_full -create -sim
```

### 2. 改程序后重仿真

```bash
# 编译新程序
python3 tools/rv2coe.py -i my_prog.S -o dev/program_source/cpu_test.coe

# 增量刷新 COE 层（秒级，非全量重建）
python -m tools.vivado_cli -task cpu_full -refresh --layers coe

# 重仿真
python -m tools.vivado_cli -task cpu_full -sim
```

### 3. 改 RTL 后全量重建

```bash
python -m tools.vivado_cli -task cpu_full -refresh
python -m tools.vivado_cli -task cpu_full -sim
```

### 4. 并行仿真不同任务

```bash
# 终端 1
python -m tools.vivado_cli -task cpu_full -create -sim

# 终端 2（同时）
python -m tools.vivado_cli -task uart_hello -create -sim
```

### 4'. 批处理模式（一条命令并行多任务）

```bash
# 并行仿真所有 CPU 测试
python -m tools.vivado_cli -batch "cpu_full,cpu_compute,cpu_trap" -create -sim

# 用通配符匹配任务组
python -m tools.vivado_cli -batch "isa_*" -create -sim

# 混合精确名 + 通配符
python -m tools.vivado_cli -batch "cpu_*,uart_hello" -create -sim

# 控制并行度（最多 2 个 Vivado 进程）
python -m tools.vivado_cli -batch "isa_*" -create -sim --max-parallel 2

# 从 YAML 文件读取批处理计划
python -m tools.vivado_cli -batch-plan regression.yaml

# 失败策略：首败即停
python -m tools.vivado_cli -batch "cpu_*" -sim --on-error fail-fast

# 失败策略：不再提交新任务，但等待已运行的完成
python -m tools.vivado_cli -batch "cpu_*" -sim --on-error stop-accepting

# JSON 输出（CI/CD 友好）
python -m tools.vivado_cli -batch "isa_*" -create -sim --format json

# 并行增量刷新 + 重仿真
python -m tools.vivado_cli -batch "cpu_*" -refresh --layers coe
python -m tools.vivado_cli -batch "cpu_*" -sim
```

#### 批处理计划 YAML 格式

```yaml
# regression.yaml
max_parallel: 3
on_error: continue
operations: [create, sim]
tasks:
  - task: cpu_full
    runtime: 5ms
  - task: cpu_compute
  - task: cpu_trap
  - task: cpu_fencei
  - task: cpu_access_fault
  - task: cpu_priv
    runtime: 20ms
```

或用通配符：

```yaml
max_parallel: 3
operations: [create, sim]
task_pattern: "isa_*"
```

### 5. 生成 bitstream 并下载

```bash
python -m tools.vivado_cli -task fpga -create -bitstream
python -m tools.vivado_cli -task fpga -program
```

## 配置文件

- **tasks.yaml** — 任务定义（项目根目录）
- **vivado_config.yaml** — 全局配置：资源限制、Vivado 路径、器件型号、**内存/Cache/DDR3/Bridge/ClkWiz 参数**

## 配置驱动的 IP 生成

所有 IP 通过 `vivado_config.yaml` 动态生成，替代静态 XCI 导入。修改配置后，IP 和 RTL 常量自动同步。

### IP 类型

| IP | 类型 | 版本 | 配置来源 |
|----|------|------|----------|
| ROM | blk_mem_gen | v8.4 | memory.rom |
| icached / dcached | blk_mem_gen | v8.4 | memory.icache / memory.dcache |
| icachet / dcachet | blk_mem_gen | v8.4 | memory.icache / memory.dcache (use_tag_bram=true) |
| tlb_flag / tlb_data | blk_mem_gen | v8.4 | memory.tlb (use_tlb_bram=true) |
| clk_wiz_0 | clk_wiz | v6.0 | memory.clk_wiz (ddr3.enabled=true) |
| bd_soc_mig_7series_0_1 | mig_7series | v4.2 | memory.ddr3 (ddr3.enabled=true) |
| ahblite_axi_bridge_0 | ahblite_axi_bridge | v3.0 | memory.ahb_bridge (ddr3.enabled=true) |

### 重新生成配置

```bash
# 编辑 vivado_config.yaml 后，重新生成 cache_def.svh：
python -m tools.vivado_cli --gen-config

# 或在 Python 中：
from tools.vivado_core.operations import Operations
ops.gen_config()  # → 返回 cache_def.svh 路径
```

### 配置示例

```yaml
memory:
  rom:
    data_width: 32
    depth: 8192
  icache:
    num_sets: 8
    num_ways: 4
    tag_width: 7
    line_words: 8
  dcache:
    num_sets: 8
    num_ways: 4
    tag_width: 7
    line_words: 8
  use_tag_bram: true    # true = BRAM IPs (icachet/dcachet)
  tlb:
    num_ways: 4
    num_sets: 4
  use_tlb_bram: true    # true = BRAM IPs (tlb_flag/tlb_data)
  ddr3:
    enabled: true
    ip_name: bd_soc_mig_7series_0_1
    mig_prj_file: Reference/mig/mig_a.prj
  ahb_bridge:
    enabled: true
  clk_wiz:
    enabled: true
    clk_out2_freq: 200.0  # DDR ref clock
```

### 生成链

```
vivado_config.yaml
  ├─→ ip_gen.py        → create_ip TCL（所有 IP 几何） + get_bram_ip_names()
  ├─→ cache_header_gen.py → cache_def.svh（`define 宏：地址切片、宽度常量）
  └─→ operations.py    → _tcl_setup_ip() + _tcl_cleanup_ip_gen() + _tcl_upgrade_ip()
```

### 关键文件

| 文件 | 作用 |
|------|------|
| `tools/vivado_core/ip_gen.py` | BramConfig + create_ip TCL 生成 + `get_bram_ip_names()` |
| `tools/vivado_core/cache_header_gen.py` | `cache_def.svh` 生成（地址切片推导） |
| `tools/vivado_core/config.py` | `MemoryConfig` 数据类 + YAML 解析 |
| `dev/rtl/core/cache_def.svh` | **自动生成**，勿手动编辑 |
| `dev/rtl/soc_config.vh` | 仿真/FPGA 条件编译宏 |

## 与旧 vivado_do.tcl 的对照

| 旧 | 新 |
|----|-----|
| `vivado_do -create -sim tb_simple_cpu_top` | `-task cpu_full -create -sim` |
| `vivado_do -sim tb_ahb_bus` | `-task ahb_bus -sim` |
| `vivado_do -refresh` | `-task cpu_full -refresh`（支持增量） |
| `vivado_do -bitstream` | `-task fpga -bitstream` |
| `vivado_do -program` | `-task fpga -program` |

## DDR3 仿真

DDR3 仿真任务使用 `sim_mode: ddr3` 标记，自动添加 MIG 仿真模型、DDR3 行为模型、BRAM 仿真模型和 verilog defines。

```bash
# MIG DDR3 控制器测试
python -m tools.vivado_cli -task ddr3_mig_ex -create -sim

# AHB 总线 + DDR3 测试
python -m tools.vivado_cli -task ddr3_ahb_ex -create -sim

# 全系统 DDR3 测试（含 hex 程序加载）
python -m tools.vivado_cli -task ddr3_system -create -sim

# 批量 DDR3 仿真
python -m tools.vivado_cli -batch "ddr3_*" -create -sim
```

### DDR3 仿真任务

| 任务 | Testbench | 说明 | 仿真时间 |
|------|-----------|------|----------|
| `ddr3_mig_ex` | tb_ddr3_mig_ex | MIG DDR3 控制器测试 | 1000us |
| `ddr3_ahb_ex` | tb_ddr3_ahb_ex | AHB 总线 + DDR3 测试 | 1000us |
| `ddr3_basic` | tb_ddr3_basic | DDR3 基础测试 | 1000us |
| `ddr3_system` | tb_ddr3_system | 全系统 DDR3 测试 | 100ms |
| `ddr3_system_v2` | tb_ddr3_system_v2 | DDR3 系统 v2 | 100ms |
| `ddr3_system_v3` | tb_ddr3_system_v3 | DDR3 系统 v3 | 100ms |

### DDR3 仿真模型

仿真模型文件位于 `Reference/ddr3_sim/`：

| 文件 | 说明 |
|------|------|
| `ddr3_model.sv` | DDR3 SDRAM 行为模型 |
| `ddr3_model_parameters.vh` | DDR3 时序参数（⚠ 依赖 MIG 配置） |
| `wiredly.v` | Wire delay 模型 |

> ⚠ 若修改 MIG 配置（如更换 DDR3 芯片），需重新从 MIG example design 导出 `ddr3_model_parameters.vh`。

### MIG 配置文件

MIG IP 的核心配置由 `Reference/mig/mig_a.prj` 定义，包含引脚分配、时序参数、内存型号等。
修改此文件后需全量刷新（`-refresh`）。
