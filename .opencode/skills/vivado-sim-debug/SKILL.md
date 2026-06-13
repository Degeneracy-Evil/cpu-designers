---
name: vivado-sim-debug
description: |
  Vivado simulation debugging with $fwrite trace logging and VCD/WDB waveform capture.
  Use this skill when debugging RISC-V CPU simulations, adding instruction trace logging,
  generating waveform files, analyzing simulation failures, or setting up debug probes.
  Trigger on: 'debug simulation', 'trace log', 'fwrite', 'VCD', 'waveform dump',
  'instruction trace', 'pipeline debug', 'simulation debugging', 'add debug probe',
  'generate VCD', 'WDB waveform', 'co-sim trace', 'Spike commit log'.
---

# Vivado 仿真调试使用指南

调试基础设施已实现在 `tb_soc_includes.svh` 中，通过 `--debug` CLI 开关启用。

---

## 1. 快速开始

```bash
# 启用指令追踪
python -m tools.vivado_cli -task isa_alu -sim --debug trace

# 启用指令追踪 + 异常追踪 + 波形
python -m tools.vivado_cli -task isa_alu -sim --debug trace,trap,wave

# 启用全部调试（追踪+流水线+异常+Spike+波形full）
python -m tools.vivado_cli -task isa_alu -sim --debug all

# 指定波形层级
python -m tools.vivado_cli -task isa_alu -sim --debug wave:full
```

---

## 2. 可用调试功能

| `--debug` 值 | Verilog Define | 生成文件 | 说明 |
|---|---|---|---|
| `trace` | `DEBUG_TRACE` | `instr_trace.log` | 指令追踪：Cycle/Time/PC/Inst/Event/RD/Value |
| `pipeline` | `DEBUG_PIPELINE` | `pipeline_dump.log` | 五级流水线状态转储 |
| `trap` | `DEBUG_TRAP` | `trap_trace.log` | 异常/中断事件追踪 |
| `spike` | `DEBUG_SPIKE` | `spike_commit.log` | Spike 兼容 commit log 格式 |
| `wave[:LEVEL]` | `DEBUG_WAVE` | WDB + 可选 VCD | 波形记录（LEVEL: minimal/normal/full） |
| `all` | 全部 | 全部 | 启用所有功能 + full 波形 |

### 波形层级

| LEVEL | 信号范围 | 速度影响 | 适用场景 |
|---|---|---|---|
| `minimal` | 顶层端口 + 关键控制 | ~2-5x | 正常调试 |
| `normal` (默认) | Core pipeline + regfile + 外设 | ~5-10x | 深度调试 |
| `full` | 全部信号 + VCD 导出 | ~10-30x | 协议验证 / GTKWave 分析 |

---

## 3. 日志文件位置

日志生成在 xsim 工作目录中：

```
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/instr_trace.log
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/pipeline_dump.log
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/trap_trace.log
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/spike_commit.log
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/sim_dump.vcd
```

---

## 4. 日志格式

### 4.1 指令追踪 (`instr_trace.log`)

```
# Cycle  Time    PC          Inst        Ev  RD    Value
1       5       80000000    00000297    N   ---   --------
2       15      80000004    00800313    N   x6    00000008
3       25      80000008    006283b3    N   x7    00000010
4       35      8000000c    00008067    BR  ---   --------
5       45      80000104    00000013    TR  ---   --------
```

事件类型：`N`=正常, `BR`=分支, `TR`=trap进入, `MR`=mret返回

### 4.2 流水线转储 (`pipeline_dump.log`)

```
# Cycle  Time  IF_PC  IF_Inst  ID_PC  ID_Inst  EX_PC  EX_Inst  MEM_PC  MEM_Inst  WB_PC  WB_Inst  FSM  Priv
```

### 4.3 异常追踪 (`trap_trace.log`)

```
# Cycle  Time  Event    PC          mstatus     mepc        mcause      Priv
1       45    TRAP_IN  80000104    00001880    80000104    8000000b    3
2       65    MRET     80000084    00001888    80000104    8000000b    0
```

### 4.4 Spike commit log (`spike_commit.log`)

```
3 0x80000000 (0x00000297)
3 0x80000004 (0x00800313) x6 0x00000008
3 0x80000008 (0x006283b3) x7 0x00000010
```

格式：`priv pc (inst) [rd val]`

---

## 5. 日志分析工具

```bash
# 解析并显示追踪日志
python -m tools.trace_analyzer parse instr_trace.log
python -m tools.trace_analyzer parse instr_trace.log --limit 50
python -m tools.trace_analyzer parse instr_trace.log --pc 80001000
python -m tools.trace_analyzer parse instr_trace.log --cycle-range 100:200

# 定位失败点（PC 不连续）
python -m tools.trace_analyzer find-fail instr_trace.log

# 与 Spike ISA Simulator 对比
python -m tools.trace_analyzer diff instr_trace.log spike_commit.log

# 生成统计摘要
python -m tools.trace_analyzer stats instr_trace.log
```

---

## 6. 双轨调试策略

**最佳实践：先用 $fwrite 日志定位失败周期，再用波形在对应时间点检查信号。**

```
1. 运行仿真，启用 --debug trace,wave
2. 分析 instr_trace.log → 找到错误 PC/寄存器值 → 记录 cycle/time
3. 在 Vivado 波形查看器中跳转到该时间点 → 检查信号过渡
4. 交叉引用：日志中的 cycle/time 对应波形中的时间轴位置
```

---

## 7. 运行时控制（无需重编译）

通过 XSim plusargs 在运行时调整：

```bash
# 禁用追踪（编译时启用了 DEBUG_TRACE，但运行时关闭）
xsim snap -R +trace_enable=0

# 自定义追踪文件名
xsim snap -R +trace_file=my_trace.log
```

---

## 8. 在 tasks.yaml 中永久启用

```yaml
tasks:
  isa_alu:
    tb: tb_isa_alu
    coe: test/isa/alu.coe
    verilog_defines:
      DEBUG_TRACE: 1    # 永久启用指令追踪
    runtime: 5ms
```

---

## 9. 直接编译启用（不通过 CLI）

```bash
# 手动 xvlog 编译时
xvlog -sv -d DEBUG_TRACE -d DEBUG_TRAP dev/tb/tb_isa_alu.sv

# 手动 xelab 时
xelab --debug typical -d DEBUG_TRACE -d DEBUG_WAVE ...
```

---

## 10. 手动波形 TCL

仿真启动后，可在 Vivado TCL 控制台手动执行：

```tcl
# 加载波形脚本
source tools/vivado_core/tcl/_debug_wave.tcl

# 按需选择层级
debug_wave_minimal   ;# 顶层端口 + 控制信号
debug_wave_normal    ;# Core pipeline + regfile + 外设
debug_wave_full      ;# 全部信号 + VCD 导出
```

---

## 11. 信号参考

### 端口级信号（无需层级路径）

| 信号 | 说明 | 来源 |
|---|---|---|
| `if_pc` / `if_inst` | IF 阶段 | system_top 端口 |
| `exe_pc` / `exe_inst` | EX 阶段 | system_top 端口 |
| `wb_pc` / `wb_inst` | WB 阶段 | system_top 端口 |
| `rf_data` | 寄存器读数据 | system_top 端口 |
| `display_state` | 显示状态 | system_top 端口 |

### 内部信号（层级路径 `u_soc.cpu.*`）

| 信号 | 路径 | 说明 |
|---|---|---|
| `if_done` | `u_soc.cpu.if_done` | IF 完成 |
| `exe_done` | `u_soc.cpu.exe_done` | EX 完成 |
| `wb_done` | `u_soc.cpu.wb_done` | WB 完成 |
| `exe_branch_taken` | `u_soc.cpu.exe_branch_taken` | 分支跳转 |
| `rf_wen` | `u_soc.cpu.rf_wen` | 寄存器写使能 |
| `rf_waddr` | `u_soc.cpu.rf_waddr` | 寄存器写地址 |
| `actual_rf_wdata` | `u_soc.cpu.actual_rf_wdata` | 寄存器写数据 |
| `trap_enter_valid` | `u_soc.cpu.trap_enter_valid` | Trap 进入 |
| `trap_return_valid` | `u_soc.cpu.trap_return_valid` | Trap 返回 |
| `priv_mode` | `u_soc.cpu.priv_mode` | 特权级 |
| `fsm_state` | `u_soc.cpu.fsm_state` | FSM 状态 |
| `csr_mstatus` | `u_soc.cpu.csr_mstatus` | CSR mstatus |
| `csr_mepc` | `u_soc.cpu.csr_mepc` | CSR mepc |

> 所有内部信号访问需要 `xsim.simulate.log_all_objects true`（已在 `_run_sim.tcl` 中设置）。
