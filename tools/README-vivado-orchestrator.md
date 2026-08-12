# Vivado Orchestrator

Python 驱动的 Vivado 仿真/综合自动化系统，替代原有 `vivado_do.tcl`。核心改进：**项目隔离并行化**、**分层哈希增量刷新**、**批处理模式**、**双界面（CLI+TUI）**。

## 架构

```
vivado_core/          ← 核心库（无UI依赖）
├── hash.py           分层哈希（rtl/tb/coe/fpga 四层 SHA256）
├── tasks.py          任务配置（tasks.yaml 加载/查询）
├── session.py        会话管理（项目隔离 + Vivado 子进程 + Semaphore 并发门控）
├── sync.py           同步策略（预检 + 增量/全量刷新规划）
├── operations.py     高层操作（create/refresh/sim/bitstream/program/archive）
├── batch.py          批处理执行（ThreadPoolExecutor + 进度追踪 + 失败策略）
├── config.py         全局配置 + 内存/Cache/RtlPaths 配置（vivado_config.yaml）
├── ip_gen.py         配置驱动的 BRAM create_ip TCL 生成
├── cache_header_gen.py  cache_def.svh 自动生成（地址切片推导）
├── exceptions.py     异常层次（13 个异常类）
└── tcl/              参数化 TCL 模板（10 个文件）

vivado_cli.py         ← CLI 前端（面向 agent/自动化，含批处理支持）
vivado_tui.py         ← TUI 前端（面向人类，需 textual）
tasks.yaml            ← 任务定义（40+ 个任务）
vivado_config.yaml    ← 全局配置（资源限制 + 路径 + 内存/Cache 参数）
```

## 核心概念

### 会话 = 项目目录

每个会话对应 `project/` 下的一个独立 Vivado 工程目录，天然持久化：

```
project/
├── cpu_full/                  ← 会话: cpu_full
│   ├── simplecpu_bus.xpr      ← Vivado 工程
│   └── .session.yaml          ← 会话元数据（哈希、状态、PID）
├── uart_hello/                ← 会话: uart_hello
└── fpga_build/                ← 会话: fpga_build
```

多个会话可并行运行各自的 Vivado 进程，互不干扰。

### 并发门控（Semaphore）

`SessionManager` 使用 `threading.Semaphore(max_concurrent)` 原子控制同时运行的 Vivado 进程数，替代了原先基于文件系统扫描的 `running_count()`（存在竞态条件）。`Session.start_vivado()` 时 acquire，`Session.stop_vivado()` 时 release，确保并发数严格不超过 `max_concurrent`。

### 分层哈希与增量刷新

源文件分为四层，各自独立计算 SHA256：

| 层 | 文件范围 | 刷新代价 |
|----|----------|----------|
| `rtl` | `src/rtl/**/*.sv/.svh` + `docs/Reference/**/*.xci` | 全量重建（分钟级） |
| `tb` | `src/tb/**/*.sv` | 重加 testbench（秒级） |
| `coe` | `src/program_source/**/*.coe/.hex` | 更新 COE 配置（秒级） |
| `fpga` | `src/fpga/**/*.xdc/.dcp` + `tools/tcl/**/*.tcl` | 重加约束（秒级） |

对比原 `vivado_do.tcl -refresh`（永远全量重建），增量刷新在仅 COE/TB 变更时快 **10x+**。

### 同步策略

每次操作前自动检测 staleness：

- **RTL stale** → 硬错误，必须全量刷新
- **TB/COE stale** → 软警告，可增量刷新或跳过
- **全部 fresh** → 直接执行

## 快速开始

### CLI（面向 agent/脚本）

```bash
# 查看所有会话状态
python -m tools.vivado_cli --status

# 创建会话并仿真
python -m tools.vivado_cli -task cpu_full -create -sim

> **⚠ `-create` 行为详述**：
> - **会话层**（`SessionManager.get_or_create()`）：未指定 `-session` 时永远新建（`<task>_<timestamp>` 不重复）；指定 `-session` 且同名 session 已存在时复用
> - **工程层**（TCL `create_project -force`）：强制覆盖目标目录已有工程，旧的波形数据、IP 缓存、elaborate 结果会被删除
> - **推荐做法**：首次用 `-create`，改 RTL 后 `-refresh -sim` 复用已有工程，工程损坏时再重复 `-create`

# 仅仿真（复用已有会话）
python -m tools.vivado_cli -task cpu_full -sim

# 增量刷新（仅 COE 层）
python -m tools.vivado_cli -task cpu_full -refresh --layers coe

# 全量刷新
python -m tools.vivado_cli -task cpu_full -refresh

# 生成 bitstream
python -m tools.vivado_cli -task fpga -bitstream

# 下载到 FPGA
python -m tools.vivado_cli -task fpga -program

# 自定义会话名
python -m tools.vivado_cli -task cpu_full -session cpu_v2 -sim

# JSON 输出（agent 可解析）
python -m tools.vivado_cli --status --format json

# 输出筛选
python -m tools.vivado_cli -task cpu_full -sim --filter pass_fail

# 清理旧会话：保留 (max_sessions - 1) 个最近使用的会话，仅清理最老的，为新会话腾出 1 个空间
python -m tools.vivado_cli --cleanup

# 彻底清理全部会话：删除所有存在的会话（batch后大量积压时尤其有用）
python -m tools.vivado_cli --cleanup-all

# 重新生成 cache_def.svh（修改 vivado_config.yaml 后）
python -m tools.vivado_cli --gen-config
```

### 批处理模式（一条命令并行多任务）

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

# 自定义日志目录（默认自动写入 log/ 目录）
python -m tools.vivado_cli -batch "isa_*" -create -sim --log /custom/log/dir
```

#### 分轮执行

当 batch 任务数超过 `max_sessions` 时，自动分轮执行：

- 每轮运行最多 `max_sessions` 个任务
- 前一轮完成后，销毁该轮所有 session（释放目录和并发信号量）
- 下一轮创建新 session 替代前轮
- 错误策略跨轮传播：`fail-fast` 跳过所有后续轮，`stop-accepting` 跳过未开始的轮
- 最后一轮不销毁 session（保留结果供查看）

示例：`max_sessions=5`，batch 20 个任务 → 4 轮，每轮 5 个。

#### 自动日志

Batch 模式**自动为每个 session 开启日志**，无需手动指定 `--log`：

- 日志目录默认为 `{project_root}/log/`
- 每个 session 生成独立日志文件：`log/{session_name}.log`
- 每行输出带时间戳 `[HH:MM:SS.mmm]`
- 若指定 `--log FILE`，则该文件父目录作为日志目录
- YAML 批处理计划支持 `log_dir` 字段自定义目录

#### 批处理计划 YAML 格式

```yaml
# regression.yaml
max_parallel: 3
on_error: continue
operations: [create, sim]
log_dir: log                   # 可选：日志目录（默认 log/）
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

#### 批处理输出示例

Text 模式：

```
============================================================
BATCH RESULT
============================================================
Total    : 6
Succeeded: 5
Failed   : 1
Skipped  : 0
Duration : 67.3s
------------------------------------------------------------
  cpu_full            PASS   8.2s  session=cpu_full_batch_20260529_...
  cpu_compute         PASS   12.1s  session=cpu_compute_batch_20260529_...
  cpu_trap            FAIL   5.2s  session=cpu_trap_batch_20260529_...
    Error: One or more operations failed
  cpu_fencei          PASS   6.8s  session=cpu_fencei_batch_20260529_...
  cpu_access_fault    PASS   4.1s  session=cpu_access_fault_batch_20260529_...
  cpu_priv            PASS   18.3s  session=cpu_priv_batch_20260529_...
============================================================
```

JSON 模式（`--format json`）：结构化输出，含每个任务的逐操作结果，适合 CI/CD 解析。

### TUI（面向人类）

```bash
pip install textual
python tools/vivado_tui.py
```

提供：会话面板、任务下拉选择、操作按钮、TCL 命令输入、实时输出查看。

## CLI 参数

| 参数 | 说明 |
|------|------|
| `-task NAME` | 指定任务（来自 tasks.yaml） |
| `-session NAME` | 覆盖会话名（默认=任务名） |
| `-create` | 创建/打开工程（同名 session 复用，工程 `-force` 覆盖） |
| `-sim` | 启动仿真 |
| `-runtime TIME` | 覆盖仿真时间 |
| `-refresh` | 刷新会话 |
| `--layers L1,L2` | 指定刷新层（rtl,tb,coe,fpga），默认全部 stale 层 |
| `-bitstream` | 生成 bitstream |
| `-hw-connect` | 连接硬件 |
| `-program` | 下载到 FPGA |
| `-archive` | 导出工程归档 |
| `-batch TASKS` | 批处理：逗号分隔任务名或通配符（如 `isa_*`） |
| `-batch-plan FILE` | 批处理：从 YAML 文件读取执行计划 |
| `--max-parallel N` | 批处理最大并行会话数（默认=min(任务数, max_concurrent)） |
| `--on-error STRATEGY` | 批处理失败策略：`continue`/`fail-fast`/`stop-accepting` |
| `--log FILE` | 日志输出文件（batch 模式自动启用，默认写入 `log/` 目录） |
| `--status` | 显示所有会话状态 |
| `--cleanup` | 清理最旧的会话（保留 `max_sessions - 1` 个），腾出一个配额 |
| `--cleanup-all` | 彻底覆盖清理全部会话 |
| `--gen-config` | 从 vivado_config.yaml 重新生成 cache_def.svh |
| `--format text\|json` | 输出格式 |
| `--filter PATTERN` | 输出筛选（error/pass_fail/progress/正则） |
| `--config PATH` | 配置文件路径 |
| `--tasks PATH` | 任务定义文件路径 |
| `-v` | 详细输出 |

## 可用任务

| 任务名 | Testbench | blcoe / blhex + phex | Runtime |
|--------|-----------|----------------------|---------|
| `cpu_full` | tb_simple_cpu_top | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test.hex | 5ms |
| `cpu_compute` | tb_simple_cpu_compute | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test_compute.hex | 5ms |
| `cpu_trap` | tb_simple_cpu_trap | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test_trap.hex | 3ms |
| `cpu_fencei` | tb_cpu_test_fencei | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test_fencei.hex | 5ms |
| `cpu_access_fault` | tb_cpu_test_access_fault | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test_access_fault.hex | 3ms |
| `cpu_priv` | tb_simple_cpu_priv | blhex: boot/bootloader_phase1.hex, phex: test/cpu_test_priv.hex | 20ms |
| `isa_alu` | tb_isa_alu | blhex: boot/bootloader_phase1.hex, phex: test/isa/alu.hex | 5ms |
| `isa_branch` | tb_isa_branch | blhex: boot/bootloader_phase1.hex, phex: test/isa/branch.hex | 5ms |
| `isa_memory` | tb_isa_memory | blhex: boot/bootloader_phase1.hex, phex: test/isa/memory.hex | 5ms |
| `isa_upper_imm` | tb_isa_upper_imm | blhex: boot/bootloader_phase1.hex, phex: test/isa/upper_imm.hex | 5ms |
| `isa_jump` | tb_isa_jump | blhex: boot/bootloader_phase1.hex, phex: test/isa/jump.hex | 5ms |
| `isa_csr` | tb_isa_csr | blhex: boot/bootloader_phase1.hex, phex: test/isa/csr.hex | 5ms |
| `isa_m_ext` | tb_isa_m_ext | blhex: boot/bootloader_phase1.hex, phex: test/isa/m_ext.hex | 5ms |
| `exception_*` | (5 个异常测试) | blhex: boot/bootloader_phase1.hex, phex: test/exception/*.hex | 5-10ms |
| `mmu_*` | (10 个 MMU/TLB 测试) | blhex: boot/bootloader_phase1.hex, phex: test/mmu/*.hex | 20ms |
| `cache_*` | (5 个 Cache 测试) | blhex: boot/bootloader_phase1.hex, phex: test/cache/*.hex | 5-20ms |
| `mmio_*` | (2 个 MMIO 测试) | blhex: boot/bootloader_phase1.hex, phex: test/mmio/*.hex | 5-10ms |
| `reg_*` | (7 个回归测试) | blhex: boot/bootloader_phase1.hex, phex: test/regression/*.hex | 10-20ms |
| `uart_hello` | tb_uart_hello | blcoe: app/uart_hello.coe | 40ms |
| `uart_echo` | tb_uart_echo | blcoe: app/uart_echo.coe | 100ms |
| `led_marquee` | tb_led_marquee | blcoe: app/led_marquee.coe | 2s |
| `ahb_bus` | tb_ahb_bus | — | 5000ns |
| `apb_perips` | tb_apb_perips | — | 2000ns |
| `alu_integration` | tb_alu_cpu_integration | — | 5000ns |
| `mu_unit` | tb_mu_unit | — | 5000ns |
| `divider` | tb_non_restoring_divider | — | 5000ns |
| `fpga` | — | — | — (top: system_top) |

> 通配符速查：`isa_*`(7), `exception_*`(5), `mmu_*`(11), `cache_*`(5), `mmio_*`(2), `reg_*`(7), `cpu_*`(6)
>
> **字段互斥规则**：`blcoe` 和 `blhex` 互斥。正常仿真任务使用 `blhex` + `phex`（SRAM 模式，bootROM 通过 `$readmemh` 加载 bootloader，SRAM 通过 `$readmemh` 加载程序）。DDR3/FPGA 任务使用 `blcoe`（COE 文件初始化 BRAM IP）。

## 配置

### tasks.yaml

任务字段说明：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `name` | str | (key) | 任务标识符（YAML 键名） |
| `tb` | str | `""` | Testbench 模块名 |
| `blcoe` | str | `""` | Bootloader COE 文件，用于 FPGA bitstream 和 DDR3 仿真。初始化 BRAM IP。与 `blhex` 互斥。 |
| `blhex` | str | `""` | Bootloader HEX 文件，用于 SRAM 模式仿真。bootROM 通过 `$readmemh` 加载。与 `blcoe` 互斥。 |
| `phex` | str | `""` | 程序 HEX 文件，用于 SRAM 模式仿真。SRAM 通过 `$readmemh` 加载。 |
| `runtime` | str | `""` | 仿真时间字符串 |
| `top` | str | `""` | 顶层模块名（bitstream 用） |
| `sim_mode` | str | `""` | 仿真模式标记（如 `"ddr3"`） |
| `verilog_defines` | dict | `{}` | Verilog defines（仿真时注入） |
| `mig_param_overrides` | dict | `{}` | MIG 参数覆盖（传递给 xelab 的 `-g` 标志） |

示例：

```yaml
tasks:
  cpu_full:
    tb: tb_simple_cpu_top
    blhex: boot/bootloader_phase1.hex
    phex: test/cpu_test.hex
    runtime: 5ms
  ddr3_system:
    tb: tb_ddr3_system
    blhex: boot/bootloader.hex
    phex: test/ddr3_system.hex
    runtime: 100ms
  fpga:
    top: system_top
    blcoe: app/led_marquee.coe
```

### vivado_config.yaml

```yaml
limits:
  max_sessions: 5       # 最大会话数
  max_concurrent: 3     # 最大并行 Vivado 进程
  max_disk_gb: 20       # project/ 总磁盘上限
  idle_timeout_min: 60  # 空闲进程自动关闭时间
vivado_path: vivado        # Linux/macOS; Windows 用户改为 vivado.bat
proj_name: simplecpu_bus
device_part: xc7a200tfbg676-2

# 内存/Cache 配置（修改后运行 --gen-config 同步 IP 和 RTL）
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
  use_tag_bram: false

# RTL 子目录路径配置（相对于 src/rtl/）
# 修改后影响项目创建和 testbench 导入的源文件搜索路径
rtl_path:
  alu: alu
  mu: mu
  cpu_core: core
  common: common
  ahb: axi
  ahb_ip: axi/ip
  amba: AMBA
  ram_wrap: ram_wrap
  apb: APB
  apb_header: APB/header
  apb_perips: APB/perips
  apb_uart16550: APB/perips/uart16550
  sys_rtl: ""                   # src/rtl 根目录
  tb: ""                        # src/tb（相对于 src/ 而非 src/rtl/）
```

## 配置驱动的 IP 生成

BRAM IP（ROM、icached、dcached）通过 `vivado_config.yaml` 的 `memory` 段动态生成 `create_ip` TCL，替代静态 XCI 文件导入。同时自动生成 `src/rtl/core/cache_def.svh`（`` `define`` 宏），使 IP 几何与 RTL 常量始终同步。

### 工作流

```bash
# 1. 编辑 vivado_config.yaml（如将 icache num_sets 改为 16）
# 2. 重新生成 cache_def.svh
python -m tools.vivado_cli --gen-config
# 3. 下次 -create 时，create_ip TCL 会使用新配置生成 BRAM IP
```

### 生成链

```
vivado_config.yaml
  ├─→ ip_gen.py           → create_ip TCL（BRAM 几何参数）
  ├─→ cache_header_gen.py → cache_def.svh（地址切片、宽度常量）
  └─→ operations.py       → _tcl_setup_ip() 在 create/refresh 时执行
```

### 关键属性

动态 `create_ip` 设置的 BRAM 属性（与原始 XCI 对齐）：

| 属性 | 说明 |
|------|------|
| `Memory_Type` | True_Dual_Port_RAM |
| `Write_Width_A/B`, `Read_Width_A/B` | 数据宽度 |
| `Write_Depth_A` | 深度 |
| `Operating_Mode_A/B` | WRITE_FIRST |
| `Interface_Type` | Native |
| `PRIM_type_to_Implement` | BRAM |
| `Use_Byte_Write_Enable` | 按配置 |
| `Byte_Size` | 8（仅 byte_enable=true 时） |

## 与旧 vivado_do.tcl 的关系

新系统与旧脚本并行存在，不修改原文件。迁移对照：

| 旧命令 | 新命令 |
|--------|--------|
| `vivado_do -create -sim tb_simple_cpu_top` | `python -m tools.vivado_cli -task cpu_full -create -sim` |
| `vivado_do -sim tb_ahb_bus` | `python -m tools.vivado_cli -task ahb_bus -sim` |
| `vivado_do -refresh` | `python -m tools.vivado_cli -task cpu_full -refresh` |
| `vivado_do -bitstream` | `python -m tools.vivado_cli -task fpga -bitstream` |
| `vivado_do -program` | `python -m tools.vivado_cli -task fpga -program` |

**关键改进**：
- `-refresh` 支持增量（`--layers coe`），不再永远全量重建
- `-task` 与 `-sim` 解耦：先选目标，再执行操作
- 多会话并行：不同任务可同时运行
- 跨调用持久化：会话状态天然保存在项目目录
- **批处理模式**：`-batch` 一条命令并行操作多个任务，支持通配符、YAML 计划、失败策略、分轮执行（任务超限时自动分批）、自动日志
- **Semaphore 并发门控**：原子控制 Vivado 进程数，消除竞态条件
