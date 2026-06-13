# 仿真调试体系实现计划

## 目标

为 RISC-V CPU 项目建立完善、强大、易用的仿真调试体系，包括：
- $fwrite 文本追踪日志（指令追踪、流水线状态、Cache 日志、异常追踪）
- VCD/WDB 波形生成（选择性信号记录、时间门控）
- Python 日志分析工具（解析、对比 Spike、定位失败点）
- Vivado CLI 集成（`--debug` 开关）
- SKILL 使用指南（指导如何使用已实现的调试体系）

## 设计原则

1. **零侵入**：所有调试代码用 `ifdef` 保护，不影响综合
2. **即插即用**：改一个 define 或传一个 plusarg 即可启用，无需改 testbench 代码
3. **分层可选**：指令追踪 / 流水线转储 / Cache 日志 / 波形 各自独立开关
4. **性能可控**：$fwrite ~1-5% 开销；波形按层级选择，不影响无波形仿真
5. **与现有基础设施兼容**：基于 `tb_soc_includes.svh` 扩展，不破坏现有 testbench

---

## 已验证的信号层级

所有信号路径已通过代码库验证：

| 类别 | 信号 | 层级路径 | 来源 |
|------|------|---------|------|
| IF 阶段 PC/Inst | `if_pc`, `if_inst` | `u_soc.if_pc` (端口) | system_top.sv:228-229 |
| ID 阶段 PC/Inst | `id_pc`, `id_inst` | `u_soc.cpu.id_pc` (内部) | core_top.sv:13-14 |
| EX 阶段 PC/Inst | `exe_pc`, `exe_inst` | `u_soc.exe_pc` (端口) | system_top.sv:232-233 |
| MEM 阶段 PC/Inst | `mem_pc`, `mem_inst` | `u_soc.cpu.mem_pc` (内部) | core_top.sv:17-18 |
| WB 阶段 PC/Inst | `wb_pc`, `wb_inst` | `u_soc.wb_pc` (端口) | system_top.sv:236-237 |
| IF 完成 | `if_done` | `u_soc.cpu.if_done` | core_top.sv:83 |
| EX 完成 | `exe_done` | `u_soc.cpu.exe_done` | core_top.sv:85 |
| WB 完成 | `wb_done` | `u_soc.cpu.wb_done` | core_top.sv:87 |
| 分支跳转 | `exe_branch_taken` | `u_soc.cpu.exe_branch_taken` | core_top.sv:120 |
| 分支目标 | `exe_branch_target` | `u_soc.cpu.exe_branch_target` | core_top.sv:121 |
| RF 写使能 | `rf_wen` | `u_soc.cpu.rf_wen` | core_top.sv:173 |
| RF 写地址 | `rf_waddr` | `u_soc.cpu.rf_waddr` | core_top.sv:174 |
| RF 写数据 | `actual_rf_wdata` | `u_soc.cpu.actual_rf_wdata` | core_top.sv:200 |
| Trap 挂起 | `trap_pending` | `u_soc.cpu.trap_pending` | core_top.sv:229 |
| Trap 进入 | `trap_enter_valid` | `u_soc.cpu.trap_enter_valid` | core_top.sv:95 |
| Trap 返回 | `trap_return_valid` | `u_soc.cpu.trap_return_valid` | core_top.sv:96 |
| MRET 检测 | `dec_is_mret` | `u_soc.cpu.dec_is_mret` | core_top.sv:109 |
| 特权级 | `priv_mode` | `u_soc.cpu.priv_mode` | core_top.sv:81 |
| CSR mstatus | `csr_mstatus` | `u_soc.cpu.csr_mstatus` | core_top.sv:246 |
| CSR mepc | `csr_mepc` | `u_soc.cpu.csr_mepc` | core_top.sv:249 |
| FSM 状态 | `fsm_state` | `u_soc.cpu.fsm_state` | core_top.sv:98 |
| 指令退休 | `inst_retire` | `u_soc.cpu.inst_retire` | core_top.sv:243 |

---

## 实现步骤

### Step 1: RTL — 在 `tb_soc_includes.svh` 添加调试追踪基础设施

**文件**: `dev/tb/tb_soc_includes.svh`

在文件末尾（`read_reg` task 之后）添加条件编译的调试基础设施块：

```systemverilog
// ============================================================================
// 调试追踪基础设施（条件编译，各模块独立开关）
// ============================================================================

// ── 1.1 指令追踪日志 (DEBUG_TRACE) ──
`ifdef DEBUG_TRACE
    integer dbg_trace_fd;
    integer dbg_trace_cycle;
    logic   dbg_trace_enable;
    string  dbg_trace_file;

    initial begin
        dbg_trace_enable = 1'b1;
        dbg_trace_file = "instr_trace.log";
        void'($value$plusargs("trace_enable=%b", dbg_trace_enable));
        void'($value$plusargs("trace_file=%s", dbg_trace_file));
        if (dbg_trace_enable) begin
            dbg_trace_fd = $fopen(dbg_trace_file, "w");
            $fwrite(dbg_trace_fd, "# Instruction Trace Log\n");
            $fwrite(dbg_trace_fd, "# Cycle  Time  PC         Instr     Ev  RD   Value\n");
        end
        dbg_trace_cycle = 0;
    end

    always @(posedge clk) begin
        if (resetn && dbg_trace_enable && u_soc.cpu.if_done) begin
            dbg_trace_cycle = dbg_trace_cycle + 1;
            $fwrite(dbg_trace_fd, "%0d\t%0t\t%08h\t%08h",
                    dbg_trace_cycle, $time, if_pc, if_inst);
            // 事件分类
            if (u_soc.cpu.exe_branch_taken)
                $fwrite(dbg_trace_fd, "\tBR");
            else if (u_soc.cpu.trap_enter_valid)
                $fwrite(dbg_trace_fd, "\tTR");
            else if (u_soc.cpu.trap_return_valid)
                $fwrite(dbg_trace_fd, "\tMR");
            else
                $fwrite(dbg_trace_fd, "\tN ");
            // WB 寄存器写回
            if (u_soc.cpu.rf_wen && u_soc.cpu.rf_waddr != 0)
                $fwrite(dbg_trace_fd, "\tx%0d\t%08h", u_soc.cpu.rf_waddr, u_soc.cpu.actual_rf_wdata);
            else
                $fwrite(dbg_trace_fd, "\t---\t--------");
            $fwrite(dbg_trace_fd, "\n");
            if (dbg_trace_cycle % 10000 == 0) $fflush(dbg_trace_fd);
        end
    end

    final begin
        if (dbg_trace_fd != 0) begin
            $fflush(dbg_trace_fd);
            $fclose(dbg_trace_fd);
        end
    end
`endif

// ── 1.2 流水线状态转储 (DEBUG_PIPELINE) ──
`ifdef DEBUG_PIPELINE
    // ... (每周期转储五级流水线 PC/Inst)
`endif

// ── 1.3 异常/中断追踪 (DEBUG_TRAP) ──
`ifdef DEBUG_TRAP
    // ... (trap_enter/trap_return/mret 事件)
`endif

// ── 1.4 Spike 兼容 commit log (DEBUG_SPIKE) ──
`ifdef DEBUG_SPIKE
    // ... (priv pc (inst) rd value 格式)
`endif

// ── 1.5 VCD 波形生成 (DEBUG_WAVE) ──
`ifdef DEBUG_WAVE
    initial begin
        $dumpfile("sim_dump.vcd");
        $dumpvars(0, u_soc);
    end
`endif
```

**关键设计**：
- 每个 debug 功能独立 `ifdef`，可组合启用
- 所有信号路径已验证（见上表）
- `rf_waddr`/`actual_rf_wdata` 通过层级路径 `u_soc.cpu.*` 访问（XSim 支持）
- plusargs 运行时控制（`trace_enable`、`trace_file`）
- `final` 块确保 `$fflush` + `$fclose`

**编译启用方式**：
```bash
# 单独启用指令追踪
xvlog -sv -d DEBUG_TRACE dev/tb/tb_simple_cpu_top.sv

# 组合启用
xvlog -sv -d DEBUG_TRACE -d DEBUG_TRAP -d DEBUG_WAVE dev/tb/tb_simple_cpu_top.sv
```

---

### Step 2: RTL — 在 `core_top.sv` 暴露更多调试输出端口（可选）

**文件**: `dev/rtl/core/core_top.sv`, `dev/rtl/system_top.sv`

当前 `core_top` 仅暴露 `if_pc`/`if_inst`/`exe_pc`/`exe_inst`/`wb_pc`/`wb_inst`/`rf_data`/`display_state`。
`if_done`、`rf_wen`、`rf_waddr`、`rf_wdata`、`trap_pending`、`priv_mode` 等是内部 wire。

**方案 A（推荐）**：保持现状，testbench 通过层级路径 `u_soc.cpu.*` 访问。
- 优势：零 RTL 改动，不影响综合
- 劣势：层级路径依赖实现细节（但 XSim 行为仿真支持）

**方案 B**：将关键信号添加为 `core_top` 输出端口 + `system_top` wire。
- 优势：更干净的接口，也适用于 FPGA ILA
- 劣势：需改 RTL，需确保新端口不影响综合

**建议**：先用方案 A 实现，验证功能。如果后续需要 FPGA ILA 调试，再升级为方案 B。

---

### Step 3: 工具 — Python 追踪日志分析器

**文件**: `tools/trace_analyzer.py`

功能：
1. **解析指令追踪日志**：读取 `instr_trace.log`，提取 PC/Inst/Cycle/Event/RD/Value
2. **定位失败点**：
   - PC 不连续检测（跳转到意外地址）
   - 特定 PC 搜索
   - 特定周期范围提取
3. **与 Spike ISA Simulator 对比**：
   - 解析 Spike commit log
   - 逐指令对比 PC + Inst + RD + Value
   - 报告首个不匹配点
4. **统计摘要**：
   - 总指令数、分支数、异常数
   - Cache 命中率（如果有 Cache 日志）
   - 执行时间分布
5. **输出格式**：JSON + 人类可读文本

```bash
# 使用示例
python -m tools.trace_analyzer parse instr_trace.log
python -m tools.trace_analyzer diff instr_trace.log spike_commit.log
python -m tools.trace_analyzer find-fail instr_trace.log
python -m tools.trace_analyzer stats instr_trace.log
```

---

### Step 4: 工具 — 扩展 Vivado Orchestrator CLI

**文件**: `tools/vivado_core/operations.py`, `tools/vivado_cli.py`

添加 `--debug` 参数：

```bash
# 启用指令追踪
python -m tools.vivado_cli -task cpu_full -sim --debug trace

# 启用指令追踪 + 异常追踪 + 波形
python -m tools.vivado_cli -task cpu_full -sim --debug trace,trap,wave

# 启用全部调试
python -m tools.vivado_cli -task cpu_full -sim --debug all

# 指定波形层级
python -m tools.vivado_cli -task cpu_full -sim --debug wave=core
```

**实现**：
- `--debug trace` → 添加 `verilog_defines: {DEBUG_TRACE: 1}`
- `--debug trap` → 添加 `DEBUG_TRAP: 1`
- `--debug wave` → 在 `_run_sim.tcl` 中添加 `log_wave` 命令
- `--debug all` → 启用所有 DEBUG_* defines + full waveform

---

### Step 5: 工具 — 批处理波形生成 TCL 脚本

**文件**: `tools/vivado_core/tcl/_debug_wave.tcl`

三级调试深度的波形配置脚本（已创建在 skill 的 scripts/ 中，需移到 tools/）：

- **minimal**: 顶层端口 + 关键控制信号
- **normal**: Core pipeline + regfile + 外设
- **full**: 全部信号 + VCD 导出

---

### Step 6: SKILL — 重写为使用指南

**文件**: `.opencode/skills/vivado-sim-debug/SKILL.md`

将 SKILL 从"实现计划"重写为"使用指南"：

1. **快速开始**：如何启用调试（一行命令）
2. **指令追踪**：如何读 instr_trace.log，如何用 trace_analyzer 分析
3. **波形调试**：如何生成 WDB/VCD，如何查看
4. **双轨调试**：如何结合日志 + 波形定位问题
5. **与 Spike 对比**：如何运行 co-simulation 验证
6. **配置参考**：所有 DEBUG_* defines 和 plusargs

---

## 实现顺序与依赖

```
Step 1 (RTL 追踪基础设施)
  ↓
Step 3 (Python 分析器) ── 可并行 ── Step 5 (TCL 波形脚本)
  ↓                                    ↓
Step 4 (CLI 集成) ←──── 依赖 Step 1 + Step 5
  ↓
Step 6 (SKILL 使用指南) ←── 依赖全部完成
```

Step 2 (暴露端口) 为可选，不影响其他步骤。

---

## Vivado Orchestrator 兼容性分析

### 架构概览

```
vivado_cli.py (argparse CLI)
    ↓ 调用
Operations.sim(session, task, runtime)
    ↓ 生成 TCL
_tcl_add_tb() + _tcl_set_verilog_defines() + _tcl_copy_hex_file() + _tcl_run_sim()
    ↓ 执行
Session.execute(tcl_string) → Vivado TCL shell
```

### 兼容性要点

#### 1. verilog_defines 传递机制 ✅ 已有

`Operations.sim()` 已有完整的 verilog_defines 传递链：

```python
# operations.py L996-1009
if task.verilog_defines:
    defines = dict(task.verilog_defines)
else:
    defines = {}
if task.sim_mode != "ddr3" and "SIMULATION" not in defines:
    defines["SIMULATION"] = "TRUE"
if defines:
    tcl_parts.append(_tcl_set_verilog_defines(defines))
```

`_tcl_set_verilog_defines()` 生成 `set_property verilog_define {K1=V1 K2=V2} [get_filesets sim_1]`。

**调试体系集成方式**：`--debug trace` → 向 `defines` 字典追加 `{"DEBUG_TRACE": "1"}`，走已有传递链。**零改动 Operations 核心逻辑**。

#### 2. TaskConfig.verilog_defines 字段 ✅ 已有

`TaskConfig` dataclass 已有 `verilog_defines: dict[str, str]` 字段（tasks.py L61），tasks.yaml 中已有使用先例：

```yaml
# tasks.yaml — cpu_full_ddr3 任务
verilog_defines:
  SIM_BYPASS_INIT_CAL: FAST
  SIMULATION: "TRUE"
  SIMU_USE_DDR: 1
```

**调试体系集成方式**：可在 tasks.yaml 中为特定任务添加 `DEBUG_TRACE: 1`，也可通过 CLI `--debug` 动态追加。

#### 3. prj 补丁机制 ⚠️ 需注意

`Operations._patch_prj_and_rerun()` 在 prj 不完整时会直接调用 `xelab`：

```python
# operations.py L1178
exec xelab --incr --debug typical --relax -mt 8 -d SIMULATION=TRUE ...
```

**问题**：prj 补丁路径的 xelab 命令硬编码了 `-d SIMULATION=TRUE`，不会传递 `--debug` 新增的 DEBUG_* defines。

**解决方案**：修改 `_patch_prj_and_rerun()`，将当前 task 的 `verilog_defines` 传入 xelab 的 `-d` 参数。具体改动：

```python
# 修改前
exec xelab ... -d SIMULATION=TRUE ...

# 修改后：将所有 verilog_defines 作为 -d 参数传递
define_args = " ".join(f"-d {k}={v}" for k, v in defines.items())
exec xelab ... {define_args} ...
```

#### 4. _tcl_run_sim() 波形配置 ⚠️ 需扩展

当前 `_tcl_run_sim()` 仅设置 runtime 和 log_all_objects，不配置波形信号：

```python
# operations.py L575-576
set_property xsim.simulate.runtime {runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]
```

**调试体系需要**：在 `launch_simulation` 后添加 `log_wave`/`add_wave`/`open_vcd`/`log_vcd` 命令。

**解决方案**：新增 `_tcl_debug_wave()` 函数，根据 `--debug` 的 wave 级别生成波形配置 TCL，在 `_tcl_run_sim()` 的 `launch_simulation` 之后插入。

#### 5. $fwrite 日志文件输出位置 ⚠️ 需明确

`$fopen("instr_trace.log", "w")` 的文件生成在 **xsim 工作目录**：
```
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/instr_trace.log
```

**问题**：用户可能不知道日志在哪里，且 Orchestrator 不收集这些文件。

**解决方案**：
- 在 `_tcl_run_sim()` 末尾添加日志文件路径打印
- 在 `Operations.sim()` 返回结果中包含日志路径信息
- 可选：在仿真结束后将日志复制到项目根目录的 `debug_logs/` 下

#### 6. 增量刷新与 DEBUG defines ⚠️ 需处理

`Operations.refresh()` 的增量刷新逻辑不处理 verilog_defines 变更。如果用户先不带 `--debug` 运行仿真，再带 `--debug trace` 运行，需要重新 elaborate（因为 define 改变导致编译结果不同）。

**解决方案**：`--debug` 参数改变时，强制重新 elaborate。实现方式：
- 在 `sync.py` 的 staleness 检测中，将 verilog_defines 纳入 hash 计算
- 或更简单：`--debug` 存在时，在 `_tcl_run_sim()` 前添加 `reset_run sim_1` 强制重新编译

#### 7. 批处理模式兼容性 ✅ 无问题

`batch.py` 使用 `ThreadPoolExecutor` 并行执行多个 task，每个 task 独立调用 `Operations.sim()`。`--debug` 参数可在批处理中传递：

```bash
python -m tools.vivado_cli -batch "isa_*" -sim --debug trace
```

每个并行 session 独立生成 `instr_trace.log`，互不干扰。但需注意：
- 每个 session 的 xsim 目录不同，日志文件不会冲突
- 但日志文件名相同（`instr_trace.log`），需在分析时区分来自哪个 task
- **改进**：可通过 plusarg 传递日志文件名，包含 task 名：`trace_file=isa_alu_trace.log`

#### 8. JSON 输出格式 ✅ 需扩展

CLI 的 `--format json` 输出结果。调试信息（日志路径、波形路径）应纳入 JSON 输出：

```json
{
  "operation": "sim",
  "task": "isa_alu",
  "success": true,
  "debug": {
    "trace_log": "/path/to/instr_trace.log",
    "wave_wdb": "/path/to/sim.wdb",
    "wave_vcd": "/path/to/sim.vcd"
  }
}
```

### 兼容性改动汇总

| 组件 | 改动 | 影响 |
|------|------|------|
| `vivado_cli.py` | 添加 `--debug` 参数 | 新增 ~30 行 |
| `operations.py` | `sim()` 方法追加 debug defines + 波形 TCL | 修改 ~20 行 |
| `operations.py` | `_patch_prj_and_rerun()` 传递 defines 到 xelab | 修改 ~5 行 |
| `operations.py` | 新增 `_tcl_debug_wave()` 函数 | 新增 ~50 行 |
| `tasks.py` | 无改动（已有 verilog_defines 字段） | 0 |
| `sync.py` | 可选：defines 纳入 staleness 检测 | 可选 ~10 行 |
| `tb_soc_includes.svh` | 添加 ifdef 调试基础设施 | 新增 ~100 行 |
| `tasks.yaml` | 可选：特定任务添加 debug defines | 可选 |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 层级路径 `u_soc.cpu.*` 在 XSim 中访问失败 | 已有 testbench 使用此模式（tb_simple_cpu_top.sv），XSim 支持 |
| `rf_wen`/`rf_waddr` 访问需要 XSim `log_all_objects` | 已在 `_run_sim.tcl` 中设置 `xsim.simulate.log_all_objects true` |
| $fwrite 性能影响 | 门控写入 + 条件编译，无 define 时零开销 |
| VCD 文件过大 | 选择性信号记录 + 时间门控 + limit_vcd |
| Spike 对比格式不匹配 | 使用 DEBUG_SPIKE define 生成 Spike 兼容格式 |
| prj 补丁路径不传递 DEBUG defines | 修改 `_patch_prj_and_rerun()` 将 defines 传入 xelab |
| 增量刷新不检测 defines 变更 | `--debug` 时强制重新 elaborate |
| 批处理模式日志文件名冲突 | plusarg 传递 task-specific 日志名 |
| $fwrite 日志在 xsim 深层目录 | 仿真后打印路径，可选复制到项目根 |

---

## 验证计划

1. **Step 1 验证**：编译 `tb_isa_alu` 带 `DEBUG_TRACE`，运行仿真，检查 `instr_trace.log` 生成且内容合理
2. **Step 3 验证**：用 Step 1 生成的日志运行 `trace_analyzer parse`，确认解析正确
3. **Step 4 验证**：`python -m tools.vivado_cli -task isa_alu -sim --debug trace`，确认 define 传递正确
4. **Step 5 验证**：运行带波形的仿真，确认 WDB 文件生成且信号可查看
5. **端到端验证**：故意制造一个 bug（如修改 ALU 结果），用调试体系定位失败点
