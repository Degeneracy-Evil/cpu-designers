---
name: vivado-orchestrator
description: |
  Vivado simulation/build orchestration with session isolation and incremental refresh.
  Use this skill when running simulations, generating bitstreams, programming FPGAs,
  managing Vivado sessions, checking staleness, or refreshing projects.
  Replaces the old vivado_do.tcl with a Python-based system supporting parallel sessions,
  layered hash staleness detection, and incremental (layer-specific) refresh.
---

# Vivado Orchestrator

Python 驱动的 Vivado 自动化系统，替代 `vivado_do.tcl`。

## 核心命令

所有命令通过 CLI 执行：

```bash
python -m tools.vivado_cli <args>
```

### 会话管理

```bash
# 清理旧会话
python -m tools.vivado_cli --cleanup
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
| `uart_hello` | tb_uart_hello | UART 发送测试 (40ms) |
| `led_marquee` | tb_led_marquee | LED 走马灯 (2s) |
| `ahb_bus` | tb_ahb_bus | AHB 总线测试 (5000ns) |
| `apb_perips` | tb_apb_perips | APB 外设测试 (2000ns) |
| `alu_integration` | tb_alu_cpu_integration | ALU 集成测试 (5000ns) |
| `mu_unit` | tb_mu_unit | 乘除法器测试 (5000ns) |
| `divider` | tb_non_restoring_divider | 除法器测试 (5000ns) |
| `fpga` | — | FPGA bitstream (top: system_top) |

## 分层哈希与增量刷新

源文件分四层，独立哈希检测变更：

| 层 | 范围 | 刷新代价 |
|----|------|----------|
| `rtl` | dev/rtl/** + Reference/ips/** | 全量重建（分钟级） |
| `tb` | dev/tb/** | 重加 testbench（秒级） |
| `coe` | dev/program_source/** | 更新 COE 配置（秒级） |
| `fpga` | dev/fpga/** + tools/tcl/** | 重加约束（秒级） |

**同步策略**：
- RTL stale → 硬错误，必须全量刷新
- TB/COE stale → 软警告，可增量刷新
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

### 5. 生成 bitstream 并下载

```bash
python -m tools.vivado_cli -task fpga -create -bitstream
python -m tools.vivado_cli -task fpga -program
```

## 配置文件

- **tasks.yaml** — 任务定义（项目根目录）
- **vivado_config.yaml** — 全局配置：资源限制、Vivado 路径、器件型号、**内存/Cache 参数**

## 配置驱动的 IP 生成

BRAM IP（Sram、icached、dcached）通过 `vivado_config.yaml` 的 `memory` 段动态生成，替代静态 XCI 导入。修改配置后，IP 和 RTL 常量自动同步。

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
  sram:
    data_width: 32        # SRAM 字宽
    depth: 8192           # SRAM 深度（32KB）
  icache:
    num_sets: 8           # 组数
    num_ways: 4           # 相联度
    tag_width: 7          # 标记位宽
    line_words: 8         # 每行字数（line_width = line_words × 32）
  dcache:
    num_sets: 8
    num_ways: 4
    tag_width: 7
    line_words: 8
  use_tag_bram: false     # true = 用 BRAM 存 tag；false = 寄存器阵列
```

### 生成链

```
vivado_config.yaml
  ├─→ ip_gen.py        → create_ip TCL（Sram/icached/dcached BRAM 几何）
  ├─→ cache_header_gen.py → cache_def.svh（`define 宏：地址切片、宽度常量）
  └─→ operations.py    → _tcl_setup_ip() 在 create/refresh 时执行
```

### 关键文件

| 文件 | 作用 |
|------|------|
| `tools/vivado_core/ip_gen.py` | BramConfig 数据类 + `create_ip` TCL 生成 |
| `tools/vivado_core/cache_header_gen.py` | `cache_def.svh` 生成（地址切片推导） |
| `tools/vivado_core/config.py` | `MemoryConfig` 数据类 + YAML 解析 |
| `dev/rtl/core/cache_def.svh` | **自动生成**，勿手动编辑 |

## 与旧 vivado_do.tcl 的对照

| 旧 | 新 |
|----|-----|
| `vivado_do -create -sim tb_simple_cpu_top` | `-task cpu_full -create -sim` |
| `vivado_do -sim tb_ahb_bus` | `-task ahb_bus -sim` |
| `vivado_do -refresh` | `-task cpu_full -refresh`（支持增量） |
| `vivado_do -bitstream` | `-task fpga -bitstream` |
| `vivado_do -program` | `-task fpga -program` |
