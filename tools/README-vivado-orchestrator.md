# Vivado Orchestrator

Python 驱动的 Vivado 仿真/综合自动化系统，替代原有 `vivado_do.tcl`。核心改进：**项目隔离并行化**、**分层哈希增量刷新**、**双界面（CLI+TUI）**。

## 架构

```
vivado_core/          ← 核心库（无UI依赖）
├── hash.py           分层哈希（rtl/tb/coe/fpga 四层 SHA256）
├── tasks.py          任务配置（tasks.yaml 加载/查询）
├── session.py        会话管理（项目隔离 + Vivado 子进程）
├── sync.py           同步策略（预检 + 增量/全量刷新规划）
├── operations.py     高层操作（create/refresh/sim/bitstream/program/archive）
├── config.py         全局配置 + 内存/Cache 配置（vivado_config.yaml）
├── ip_gen.py         配置驱动的 BRAM create_ip TCL 生成
├── cache_header_gen.py  cache_def.svh 自动生成（地址切片推导）
├── exceptions.py     异常层次（13 个异常类）
└── tcl/              参数化 TCL 模板（10 个文件）

vivado_cli.py         ← CLI 前端（面向 agent/自动化）
vivado_tui.py         ← TUI 前端（面向人类，需 textual）
tasks.yaml            ← 任务定义（14 个任务）
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

### 分层哈希与增量刷新

源文件分为四层，各自独立计算 SHA256：

| 层 | 文件范围 | 刷新代价 |
|----|----------|----------|
| `rtl` | `dev/rtl/**/*.sv/.svh` + `Reference/**/*.xci` | 全量重建（分钟级） |
| `tb` | `dev/tb/**/*.sv` | 重加 testbench（秒级） |
| `coe` | `dev/program_source/**/*.coe/.hex` | 更新 COE 配置（秒级） |
| `fpga` | `dev/fpga/**/*.xdc/.dcp` + `tools/tcl/**/*.tcl` | 重加约束（秒级） |

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

# 清理旧会话
python -m tools.vivado_cli --cleanup
python -m tools.vivado_cli --cleanup-all

# 重新生成 cache_def.svh（修改 vivado_config.yaml 后）
python -m tools.vivado_cli --gen-config
```

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
| `-create` | 创建/打开工程 |
| `-sim` | 启动仿真 |
| `-runtime TIME` | 覆盖仿真时间 |
| `-refresh` | 刷新会话 |
| `--layers L1,L2` | 指定刷新层（rtl,tb,coe,fpga），默认全部 stale 层 |
| `-bitstream` | 生成 bitstream |
| `-hw-connect` | 连接硬件 |
| `-program` | 下载到 FPGA |
| `-archive` | 导出工程归档 |
| `--status` | 显示所有会话状态 |
| `--cleanup` | 清理旧会话 |
| `--cleanup-all` | 清理全部会话 |
| `--gen-config` | 从 vivado_config.yaml 重新生成 cache_def.svh |
| `--format text\|json` | 输出格式 |
| `--filter PATTERN` | 输出筛选（error/pass_fail/progress/正则） |
| `--config PATH` | 配置文件路径 |
| `--tasks PATH` | 任务定义文件路径 |
| `-v` | 详细输出 |

## 可用任务

| 任务名 | Testbench | COE | Runtime |
|--------|-----------|-----|---------|
| `cpu_full` | tb_simple_cpu_top | cpu_test.coe | 5ms |
| `cpu_compute` | tb_simple_cpu_compute | cpu_test_compute.coe | 5ms |
| `cpu_trap` | tb_simple_cpu_trap | cpu_test_trap.coe | 3ms |
| `cpu_fencei` | tb_cpu_test_fencei | cpu_test_fencei.coe | 5ms |
| `cpu_access_fault` | tb_cpu_test_access_fault | cpu_test_access_fault.coe | 3ms |
| `cpu_priv` | tb_simple_cpu_priv | cpu_test_priv.coe | 20ms |
| `uart_hello` | tb_uart_hello | uart_hello.coe | 40ms |
| `led_marquee` | tb_led_marquee | led_marquee.coe | 2s |
| `ahb_bus` | tb_ahb_bus | — | 5000ns |
| `apb_perips` | tb_apb_perips | — | 2000ns |
| `alu_integration` | tb_alu_cpu_integration | — | 5000ns |
| `mu_unit` | tb_mu_unit | — | 5000ns |
| `divider` | tb_non_restoring_divider | — | 5000ns |
| `fpga` | — | — | — (top: system_top) |

## 配置

### tasks.yaml

```yaml
tasks:
  cpu_full:
    tb: tb_simple_cpu_top
    coe: cpu_test.coe
    runtime: 5ms
  fpga:
    top: system_top
```

### vivado_config.yaml

```yaml
limits:
  max_sessions: 5       # 最大会话数
  max_concurrent: 3     # 最大并行 Vivado 进程
  max_disk_gb: 20       # project/ 总磁盘上限
  idle_timeout_min: 60  # 空闲进程自动关闭时间
vivado_path: vivado.bat
proj_name: simplecpu_bus
device_part: xc7a200tfbg676-2

# 内存/Cache 配置（修改后运行 --gen-config 同步 IP 和 RTL）
memory:
  sram:
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
```

## 配置驱动的 IP 生成

BRAM IP（Sram、icached、dcached）通过 `vivado_config.yaml` 的 `memory` 段动态生成 `create_ip` TCL，替代静态 XCI 文件导入。同时自动生成 `dev/rtl/core/cache_def.svh`（`` `define`` 宏），使 IP 几何与 RTL 常量始终同步。

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
