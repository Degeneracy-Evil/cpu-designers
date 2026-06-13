# VCD/WDB 波形生成与查看工作流

## 目录

1. [Vivado XSim 波形架构](#1-vivado-xsim-波形架构)
2. [TCL 命令参考](#2-tcl-命令参考)
3. [批处理仿真脚本](#3-批处理仿真脚本)
4. [选择性信号记录策略](#4-选择性信号记录策略)
5. [时间门控波形转储](#5-时间门控波形转储)
6. [波形查看工作流](#6-波形查看工作流)
7. [VCD 文件大小管理](#7-vcd-文件大小管理)
8. [与 $fwrite 日志关联](#8-与-fwrite-日志关联)

---

## 1. Vivado XSim 波形架构

### 编译/展开/仿真流程

```
xvlog -sv source.sv          # 编译
xelab -debug typical top     # 展开（-debug 必须指定！）
xsim top -gui                # GUI 仿真
xsim top -R                  # 批处理仿真
```

**关键**：`xelab` 必须指定 `-debug typical` 或 `-debug all`，否则**不记录波形数据**。

| -debug 选项 | 能力 | 速度影响 |
|-------------|------|---------|
| `off` | 无调试信息 | 最快（基线） |
| `typical` | 行断点 + 波形生成 | ~2-5x 慢 |
| `all` | 全部调试能力 | ~5-10x 慢 |

### VCD vs WDB

| 特性 | VCD | WDB |
|------|-----|-----|
| 格式 | IEEE 1364 标准文本 | Xilinx 专有二进制 |
| 可互操作 | GTKWave 等均可读 | 仅 Vivado 可读 |
| Vivado 可读？ | **否**（仅输出） | **是** |
| Vivado 可写？ | **是** | **是** |
| 文件大小 | 较大 | 较小 |
| 层级保留 | 可能扁平化 | 保留完整层级 |

**策略**：Vivado 内部调试用 WDB，外部工具（GTKWave）分析用 VCD。

---

## 2. TCL 命令参考

### VCD 控制

| TCL 命令 | Verilog 等价 | 说明 |
|----------|-------------|------|
| `open_vcd <file>` | `$dumpfile` | 打开 VCD 文件 |
| `log_vcd <scope>` | `$dumpvars` | 记录 scope 内信号 |
| `log_vcd -ports * <scope>` | — | 仅记录端口 |
| `start_vcd` | `$dumpon` | 恢复 VCD 输出 |
| `stop_vcd` | `$dumpoff` | 暂停 VCD 输出 |
| `checkpoint_vcd` | `$dumpall` | 强制输出所有值 |
| `flush_vcd` | `$dumpflush` | 刷新 VCD 缓冲 |
| `limit_vcd <n>` | `$dumplimit` | 限制 VCD 文件大小 |
| `close_vcd` | — | 关闭 VCD 文件 |

### WDB 控制

| TCL 命令 | 说明 |
|----------|------|
| `log_wave <signal>` | 记录信号到 WDB |
| `log_wave -r <scope>` | 递归记录 scope 内所有信号 |
| `add_wave <signal>` | 添加信号到波形查看器（同时记录） |
| `add_wave -radix hex <signal>` | 十六进制显示 |
| `add_wave -recursive <scope>` | 递归添加 |
| `add_wave_group <name>` | 创建信号组 |
| `save_wave_config <file>` | 保存波形配置 |
| `get_objects -filter {type == signal} <scope>` | 获取内部信号 |
| `get_objects -filter {type == in_port \|\| type == out_port} <scope>` | 获取端口 |

### 仿真控制

| TCL 命令 | 说明 |
|----------|------|
| `run <time>` | 运行指定时间 |
| `run -all` | 运行到结束 |
| `restart` | 重启仿真 |
| `current_time` | 获取当前仿真时间 |
| `add_marker <time>` | 在指定时间添加标记 |

---

## 3. 批处理仿真脚本

详见 `scripts/xsim_debug.tcl`，支持三级调试深度：

- **minimal**：仅顶层端口和关键控制信号
- **normal**：Core pipeline + register file + 外设
- **full**：全部信号 + VCD 导出

运行方式：
```bash
# Tier 1: 最小调试
xsim snap_name -tclbatch xsim_debug.tcl -wdb sim_minimal.wdb

# Tier 2: 正常调试
set log_level normal
xsim snap_name -tclbatch xsim_debug.tcl -wdb sim_normal.wdb

# Tier 3: 完整调试（含 VCD）
set log_level full
xsim snap_name -tclbatch xsim_debug.tcl -wdb sim_full.wdb
```

---

## 4. 选择性信号记录策略

### Tier 1：最小信号集（快速定位）

```tcl
# 顶层时钟和复位
log_wave /tb/clk /tb/resetn

# CPU 核心关键信号
log_wave /tb/u_soc/cpu/if_pc /tb/u_soc/cpu/if_inst
log_wave /tb/u_soc/cpu/exe_pc /tb/u_soc/cpu/exe_inst
log_wave /tb/u_soc/cpu/wb_pc /tb/u_soc/cpu/wb_inst

# 控制信号
log_wave /tb/u_soc/cpu/if_done /tb/u_soc/cpu/exe_done /tb/u_soc/cpu/wb_done
log_wave /tb/u_soc/cpu/exe_branch_taken
```

### Tier 2：正常信号集（流水线调试）

```tcl
# Tier 1 信号
log_wave /tb/clk /tb/resetn
log_wave /tb/u_soc/cpu/if_pc /tb/u_soc/cpu/if_inst
log_wave /tb/u_soc/cpu/exe_pc /tb/u_soc/cpu/exe_inst

# 寄存器文件
log_wave /tb/u_soc/cpu/u_regfile/*

# ALU 和乘除法
log_wave /tb/u_soc/cpu/u_alu/*
log_wave /tb/u_soc/cpu/u_mul_div/*

# 总线接口
log_wave /tb/u_soc/cpu/u_bus_bridge/*
```

### Tier 3：完整信号集（深度调试）

```tcl
# 递归记录全部信号
log_wave -r /tb/u_soc/*

# 同时生成 VCD 供外部工具
open_vcd sim_debug.vcd
log_vcd /tb/u_soc/cpu/*
```

---

## 5. 时间门控波形转储

仅在可疑区域前后转储波形，大幅减小文件大小：

```tcl
# 仅在 5000ns 到 6000ns 之间转储 VCD
open_vcd targeted.vcd
log_vcd /tb/u_soc/cpu/*

run 5000ns

start_vcd       # 开始 VCD 转储
run 1000ns
stop_vcd        # 停止 VCD 转储

run 1000ns      # 继续运行但不转储

close_vcd
quit
```

### 结合 $fwrite 日志定位时间窗口

```bash
# 1. 先运行带 $fwrite 日志的仿真（快速）
# 2. 在日志中找到失败点
grep "FAIL" instr_trace.log
# 输出: 5000000  500000ns  80001040  00000013  N

# 3. 用失败时间 ±1000ns 作为 VCD 转储窗口
# 修改 TCL: run 499000ns; start_vcd; run 2000ns; stop_vcd
```

---

## 6. 波形查看工作流

### Vivado GUI 查看

```bash
# 打开已有 WDB 文件
xsim -gui sim_output.wdb

# 或在 Vivado GUI 中
# 1. 打开仿真：Flow → Run Simulation → Run Behavioral Simulation
# 2. 添加信号：右键 → Add to Wave Window
# 3. 使用波形配置：File → Load Wave Configuration → debug.wcfg
```

### GTKWave 查看 VCD

```bash
# 生成 VCD 后用 GTKWave 查看
gtkwave sim_debug.vcd &

# GTKWave 快捷键
# + 放大 / - 缩小 / 鼠标滚轮 缩放
# 左键点击信号值查看详细信息
# Search → Wave → 跳转到指定时间
# File → Read Save File → 加载信号配置
```

### 保存常用波形配置

```tcl
# 创建信号组
set pipe_grp [add_wave_group "Pipeline"]
add_wave -into $pipe_grp -radix hex /tb/u_soc/cpu/if_pc
add_wave -into $pipe_grp -radix hex /tb/u_soc/cpu/if_inst
add_wave -into $pipe_grp -radix hex /tb/u_soc/cpu/exe_pc

set reg_grp [add_wave_group "Register File"]
add_wave -into $reg_grp -radix hex /tb/u_soc/cpu/u_regfile/rf[0]
add_wave -into $reg_grp -radix hex /tb/u_soc/cpu/u_regfile/rf[1]
# ... 或递归
add_wave -into $reg_grp -recursive -radix hex /tb/u_soc/cpu/u_regfile/*

# 保存配置
save_wave_config cpu_debug.wcfg
```

---

## 7. VCD 文件大小管理

| 策略 | 效果 | 实现方式 |
|------|------|---------|
| 选择性信号记录 | 10-100x 减小 | `log_vcd /tb/dut/core/*` 替代 `log_vcd -r /` |
| 时间门控 | 仅转储可疑区域 | `start_vcd` / `stop_vcd` |
| `limit_vcd` | 限制最大值变化数 | `limit_vcd 1000000` |
| 仅端口 | 大幅减小 | `log_vcd -ports * /tb/dut/*` |
| 压缩 | 2-5x 减小 | `gzip sim_debug.vcd` |

### 典型文件大小参考

| 信号范围 | 10ms 仿真 VCD 大小 | WDB 大小 |
|----------|-------------------|---------|
| 顶层端口 | ~1 MB | ~500 KB |
| Core pipeline | ~10 MB | ~3 MB |
| Core + regfile | ~50 MB | ~15 MB |
| 全部信号 (`-r /`) | ~500 MB+ | ~100 MB+ |

---

## 8. 与 $fwrite 日志关联

### 时间戳关联方法

1. **在 $fwrite 日志中包含 `$time`**：
   ```systemverilog
   $fwrite(fd, "%0t\t%0d\t%08h\t%08h\n", $time, cycle, pc, instr);
   ```

2. **在波形查看器中跳转到对应时间**：
   - Vivado: `add_marker <time>` 或在时间轴上点击
   - GTKWave: Search → Jump to Time

3. **使用 cycle 计数器关联**：
   - 在日志中找到失败的 cycle
   - 在波形中找到对应 cycle 的时钟上升沿

### 完整调试流程

```
1. 运行仿真（$fwrite 日志 + WDB 波形）
   └─ python -m tools.vivado_cli -task cpu_full -sim

2. 分析日志定位失败
   └─ grep "FAIL" instr_trace.log
   └─ 输出: 5000000  500000ns  80001040  00000013

3. 打开波形，跳转到失败时间
   └─ xsim -gui sim.wdb
   └─ add_marker 500000ns

4. 在波形中检查信号过渡
   └─ 检查 if_pc, exe_pc, regfile 写使能等
   └─ 确认根因

5. 修复 RTL，重新仿真验证
```
