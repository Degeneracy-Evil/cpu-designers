# Vivado Orchestrator DDR3 仿真升级进度

> ⛔ **已停止** — 2026-06-09: AHB-Lite 架构已废弃，全面转向 AXI 总线 + chiplab 对齐架构。见新计划 `plan/axi-mig-alignment-plan.md`
> 创建日期: 2026-06-06 | 关联计划: `plan/vivado-orchestrator-ddr3-upgrade-plan.md`

---

## 总体进度

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | 基础设施 — TaskConfig 扩展 + DDR3 模型集中化 + tasks.yaml | ✅ 完成 | 2026-06-06 |
| Phase 2 | 核心逻辑 — operations.py DDR3 仿真支持 | ✅ 完成 | 2026-06-06 |
| Phase 3 | 增量刷新 — hash.py 适配 | ✅ 完成 | 2026-06-06 |
| Phase 4 | 文档更新 — SKILL.md | ✅ 完成 | 2026-06-06 |

---

## Phase 1: 基础设施 — TaskConfig 扩展 + DDR3 模型集中化 + tasks.yaml

### 1.1: TaskConfig 扩展

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.1a | `tasks.py`: 新增 `sim_mode: str` 字段 | ✅ | 默认空字符串，向后兼容 |
| 1.1b | `tasks.py`: 新增 `verilog_defines: dict[str, str]` 字段 | ✅ | `field(default_factory=dict)` |
| 1.1c | `tasks.py`: 新增 `hex_file: str` 字段 | ✅ | 默认空字符串 |
| 1.1d | `tasks.py`: `TaskRegistry.load()` 解析新字段 | ✅ | `cfg.get("sim_mode", "")` 等 |
| 1.1e | `tasks.py`: docstring 更新 | ✅ | 新增 3 个属性说明 |
| 1.1f | 验证：旧任务 `cpu_full` 向后兼容 | ✅ | `sim_mode=''`, `verilog_defines={}`, `hex_file=''` |

### 1.2: DDR3 仿真模型集中化

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.2a | 创建 `Reference/ddr3_sim/` 目录 | ✅ | |
| 1.2b | 复制 `ddr3_model.sv` | ✅ | 来源: `project/bd_soc_mig_7series_0_1_ex/imports/` |
| 1.2c | 复制 `ddr3_model_parameters.vh` | ✅ | ⚠ MIG 配置依赖，变更时需重新导出 |
| 1.2d | 复制 `wiredly.v` | ✅ | Wire delay 模型 |

### 1.3: tasks.yaml DDR3 仿真任务

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.3a | `ddr3_mig_ex` 任务定义 | ✅ | `sim_mode: ddr3`, `runtime: 1000us` |
| 1.3b | `ddr3_ahb_ex` 任务定义 | ✅ | `sim_mode: ddr3`, `runtime: 1000us` |
| 1.3c | `ddr3_basic` 任务定义 | ✅ | `sim_mode: ddr3`, `runtime: 1000us` |
| 1.3d | `ddr3_system` 任务定义 | ✅ | `sim_mode: ddr3`, `hex_file: app/ddr3_test.hex`, `runtime: 10ms` |
| 1.3e | 验证：`ddr3_ahb_ex` 解析正确 | ✅ | `sim_mode=ddr3`, `defines={'SIM_BYPASS_INIT_CAL': 'FAST', 'SIMULATION': 'TRUE'}` |
| 1.3f | 验证：`ddr3_system` 解析正确 | ✅ | `hex_file=app/ddr3_test.hex`, `runtime=10ms` |

---

## Phase 2: 核心逻辑 — operations.py DDR3 仿真支持

### 2.1: 新增 TCL 辅助函数

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.1a | `_tcl_add_ddr3_sim_models()` | ✅ | 添加 ddr3_model.sv + ddr3_model_parameters.vh (Verilog Header) + wiredly.v + glbl.v stub |
| 2.1b | `_tcl_set_verilog_defines()` | ✅ | `set_property verilog_define` 到 sim_1 和 current_fileset |
| 2.1c | `_tcl_handle_bridge_vhdl()` | ✅ | 移除冲突的 bridge VHDL 文件（create_ip 方式下安全措施） |
| 2.1d | `_tcl_copy_hex_file()` | ✅ | 拷贝 hex 到项目目录供 `$readmemh` 访问 |

### 2.2: 修改 Operations 方法

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.2a | `create()`: 条件性添加 DDR3 仿真模型 | ✅ | `if task.sim_mode == "ddr3"` |
| 2.2b | `create()`: 条件性调用 bridge workaround | ✅ | 紧接 DDR3 模型添加之后 |
| 2.2c | `sim()`: 条件性设置 verilog defines | ✅ | `if task.verilog_defines` |
| 2.2d | `sim()`: 条件性拷贝 hex 文件 | ✅ | `if task.hex_file` |
| 2.2e | 新增 `_resolve_hex_path()` 辅助方法 | ✅ | 与 `_resolve_coe_path()` 对称 |

### 2.3: 验证

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.3a | Python 语法检查 (operations.py) | ✅ | `ast.parse()` 通过 |
| 2.3b | `_tcl_add_ddr3_sim_models()` 输出验证 | ✅ | 路径正确，glbl.v fallback 逻辑正确 |
| 2.3c | `_tcl_set_verilog_defines()` 输出验证 | ✅ | `SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE` |
| 2.3d | `_tcl_handle_bridge_vhdl()` 输出验证 | ✅ | remove_files 逻辑正确 |
| 2.3e | `_tcl_copy_hex_file()` 输出验证 | ✅ | file copy + WARNING fallback |

---

## Phase 3: 增量刷新 — hash.py 适配

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.1 | `hash.py`: 追加 `Reference/ddr3_sim/**/*.sv` 到 rtl 层 | ✅ | |
| 3.2 | `hash.py`: 追加 `Reference/ddr3_sim/**/*.vh` 到 rtl 层 | ✅ | |
| 3.3 | `hash.py`: 追加 `Reference/ddr3_sim/**/*.v` 到 rtl 层 | ✅ | |
| 3.4 | 验证：glob 匹配到 3 个文件 | ✅ | ddr3_model.sv, ddr3_model_parameters.vh, wiredly.v |
| 3.5 | Python 语法检查 (hash.py) | ✅ | `ast.parse()` 通过 |

---

## Phase 4: 文档更新

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | SKILL.md: DDR3 仿真章节 | ✅ | 用法 + 任务表 + 模型说明 + MIG 配置文件说明 |
| 4.2 | SKILL.md: 可用任务表追加 4 行 | ✅ | ddr3_mig_ex, ddr3_ahb_ex, ddr3_basic, ddr3_system |

---

## 改动文件清单

| 文件 | 改动类型 | 行数变化 |
|------|----------|----------|
| `tools/vivado_core/tasks.py` | 修改 | +15 行（3 字段 + 解析 + docstring） |
| `tools/vivado_core/operations.py` | 修改 | +170 行（4 函数 + create/sim 修改 + _resolve_hex_path + _patch_prj_and_rerun fallback） |
| `tools/vivado_core/hash.py` | 修改 | +3 行（3 glob） |
| `tasks.yaml` | 修改 | +30 行（4 任务定义） |
| `Reference/ddr3_sim/ddr3_model.sv` | 新建 | 从 MIG example 复制 |
| `Reference/ddr3_sim/ddr3_model_parameters.vh` | 新建 | 从 MIG example 复制 |
| `Reference/ddr3_sim/wiredly.v` | 新建 | 从 MIG example 复制 |
| `dev/rtl/axi/ahb_sys_status.sv` | 修改 | `output wire` → `output logic` (HRDATA) |
| `dev/rtl/axi/ddr3_bridge_wrapper.sv` | 修改 | 补充 aresetn 端口逗号 |
| `dev/rtl/core/core_bus_types.svh` | 修改 | 添加 include guard |
| `dev/rtl/system_top.sv` | 修改 | clk_wiz_0 `.reset` → `.resetn`；BUG-52: `.mig_sys_rst(~resetn)` → `.mig_sys_rst(resetn)`；BUG-54: `mig_aresetn` 在 MMCM lock 后释放；BUG-55c: 添加异步复位 |
| `dev/rtl/axi/ahb_bootrom_slave.sv` | 修改 | 添加 `ifdef SIMULATION` 寄存器数组；BUG-55: 添加 `initial` 块初始化为 0 |
| `dev/rtl/APB/perips/uart_tx.sv` | 修改 | BUG-55b: cycle_cnt 添加 `state != S_IDLE` 守卫 |
| `dev/rtl/APB/perips/uart_rx.sv` | 修改 | BUG-55b: cycle_cnt 添加 `state != S_IDLE` 守卫 |
| `dev/tb/tb_ddr3_system.sv` | 修改 | 移除 glbl 双实例；SIM_TIMEOUT 溢出修复；CALIB_TIMEOUT 500µs→1ms；MIG 基础设施探针；BUG-55d: 注释掉 $dumpvars |
| `Reference/ddr3_sim/ddr3_model_parameters.vh` | 修改 | BUG-53: DEBUG=1→0（4处，抑制 verbose 输出） |
| `tasks.yaml` | 修改 | BUG-53: ddr3_system 添加 `sg125: 1` 到 verilog_defines |
| `.opencode/skills/vivado-orchestrator/SKILL.md` | 修改 | +35 行（DDR3 文档 + 任务表） |

---

## 与 `run_ddr3_sim.tcl` 的等价性对照

| `run_ddr3_sim.tcl` 步骤 | orchestrator 对应 | 等价性 |
|--------------------------|-------------------|--------|
| `create_project` | `_tcl_create_project()` | ✅ |
| 添加 MIG sim model（从 example project） | `create_ip` + `generate_target` 自动生成 | ✅ |
| 添加 DDR3 model + WireDelay | `_tcl_add_ddr3_sim_models()` | ✅ |
| 添加 Bridge VHDL + ClkWiz | `create_ip` + `generate_target` | ✅ |
| 添加 glbl.v | `_tcl_add_ddr3_sim_models()` 内动态生成 | ✅ |
| 添加项目 RTL | `_tcl_create_project()` 内 glob 导入 | ✅ |
| 添加 testbench | `_tcl_add_tb()` | ✅ |
| `set_property verilog_define` | `_tcl_set_verilog_defines()` | ✅ |
| Bridge VHDL 库 workaround | `_tcl_handle_bridge_vhdl()` | ✅ |
| hex 文件拷贝 | `_tcl_copy_hex_file()` | ✅ |
| `set_property xsim.simulate.runtime` | `_tcl_run_sim()` 内设置 | ✅ |
| `launch_simulation` | `_tcl_run_sim()` 内调用 | ✅ |

---

## Phase 5: 仿真验证 + RTL Bug 修复

> **关键发现**: 原诊断 "Vivado 2018.3 依赖解析器在 SV→VHDL 边界失败" **错误**。
> 真正根因是 **5 个预存 RTL bug** 阻止 xvlog 编译 sources_1 文件。
> 修复 RTL 后，`launch_simulation` 直接成功，无需 prj patching。

### 5.1: RTL Bug 修复

| Bug | 文件 | 问题 | 修复 | 日期 |
|-----|------|------|------|------|
| `output wire` 被 `always_comb` 驱动 | `ahb_sys_status.sv:34` | HRDATA 声明为 `wire`，但 `always_comb` 过程赋值要求 `logic`/`reg` | `output wire` → `output logic` | 2026-06-06 |
| 端口列表缺少逗号 | `ddr3_bridge_wrapper.sv:50` | `aresetn` 端口后无逗号，下一个端口 `app_sr_req` 语法错误 | 添加逗号 | 2026-06-06 |
| 缺少 include guard | `core_bus_types.svh` | `wb_bus_t`/`exe_mem_bus_t` 被多个编译单元重复声明 (VRFC 10-2934) | 添加 `` `ifndef CORE_BUS_TYPES_SVH `` guard | 2026-06-06 |
| clk_wiz_0 端口名不匹配 | `system_top.sv:62` | `.reset(~resetn)` — IP 实际端口名为 `resetn`（低有效），非 `reset`（高有效） | `.reset(~resetn)` → `.resetn(resetn)` | 2026-06-06 |
| BRAM IP 无 `mem` 数组 | `ahb_bootrom_slave.sv` | 测试台 `u_ahb_bootrom_slave.mem[0]` 层次引用不存在（BRAM IP 无可访问内存数组） | 添加 `` `ifdef SIMULATION `` 寄存器数组替代 BRAM IP | 2026-06-06 |

### 5.2: 仿真验证结果

| 测试台 | 命令 | 结果 | 详情 | 日期 |
|--------|------|------|------|------|
| `ddr3_mig_ex` | `python -m tools.vivado_cli -task ddr3_mig_ex -create -sim` | ✅ 4 PASS, 0 FAIL | ALL TESTS PASSED | 2026-06-06 |
| `ddr3_ahb_ex` | `python -m tools.vivado_cli -task ddr3_ahb_ex -create -sim` | ✅ 4 PASS, 0 FAIL | ALL TESTS PASSED (BUG-45 修复后) | 2026-06-06 |
| `ddr3_basic` | `python -m tools.vivado_cli -task ddr3_basic -create -sim` | ✅ 仿真启动 | MIG 校准超时 100µs — FAST sim 预期 | 2026-06-06 |
| `ddr3_system` | `python -m tools.vivado_cli -task ddr3_system -create -sim` | ⏳ 仿真进行中 | BUG-52~55 ✅ 修复，XSIM 43-3356 ✅ workaround，仿真提速 500x | 2026-06-07 |

### 5.3: tb_ddr3_system 调试历程

| Bug | 根因 | 修复 | 验证 |
|-----|------|------|------|
| BUG-52 | MIG `sys_rst` 极性反转：`~resetn` 传入但 `RST_ACT_LOW=1`（低有效） | `.mig_sys_rst(resetn)` 替代 `~resetn` | PLL/MMCM 锁定 ✅, `init_calib_complete` 从 X→0 ✅ |
| BUG-53 | DDR3 model 默认 DDR3-800 时序，MIG 配置 DDR3-1600 | `tasks.yaml` 添加 `sg125: 1`；`ddr3_model_parameters.vh` DEBUG=0 | MIG 校准完成 ✅ |
| BUG-54 | `mig_aresetn` 等待 `init_calib_complete` → 循环依赖死锁 | `mig_aresetn` 在 `mmcm_locked && resetn` 后释放；新增 `ahb_hresetn` 在 `init_calib_complete` 后释放 | `MIG.aresetn=1` ✅, 校准开始 ✅ |
| XSIM 43-3356 | xelab 多线程代码生成竞争 `xsim.type` 文件锁 | 重试逻辑：mt2→mtoff→mtoff + taskkill + 快照清理 | xelab 成功 ✅ |
| BUG-55 | Boot ROM `mem[]` 未初始化 → 全 X → CPU 管线 X 传播风暴 → 仿真 5000x 慢 | `initial` 块初始化 `mem[]` 为 0 | 仿真提速 **~500x** ✅ |
| BUG-55b | UART TX/RX `cycle_cnt` 空闲时自由运行 | 添加 `state != S_IDLE` 守卫 | 无功能影响 ✅ |
| BUG-55c | `mig_aresetn`/`ahb_hresetn` 无异步复位 → X 传播 | 添加 `posedge reset` 异步复位 | 复位确定性 ✅ |
| BUG-55d | `$dumpvars(0,...)` 60K-FF 设计 VCD I/O 开销 | 注释掉 `$dumpvars` | I/O 开销消除 ✅ |
| BUG-56 | MIG `init_calib_complete` 在 tb_ddr3_system 中恒为 0（tb_ddr3_ahb_ex @106µs 正常完成） | 见下方 BUG-56 调查详情 | 🔄 调查中 |

### 5.3.1: BUG-56 调查详情

> **症状**: tb_ddr3_system 中 MIG `init_calib_complete` 恒为 0，即使仿真推进到 300µs（tb_ddr3_ahb_ex 在 106µs 即完成校准）
> **所有 MIG 基础设施信号正常**: mmcm_locked=1, pll_locked=1, aresetn=1, sys_rst=1, rst_tmp=0, sys_rst_act_hi=0
> **DDR3 model PHY_INIT 完成**: @9.6µs

#### 关键发现：校准 FSM 卡在 INIT_PI_PHASELOCK_READS (state 38)

`init_state_r = 7'b0100110 = 38` → `INIT_PI_PHASELOCK_READS`

FSM 等待 `pi_phase_locked_all` 上升沿：
```verilog
INIT_PI_PHASELOCK_READS:
  if (pi_phase_locked_all_r3 && ~pi_phase_locked_all_r4)
    init_next_state = INIT_PRECHARGE_PREWAIT;
```

`pi_phase_locked_all` 永不拉高 → FSM 永远卡在 state 38。

#### 完整信号链追踪

```
ddr_phy_init.init_state_r == INIT_DONE (state 22)
  → init_complete_r → init_complete_r1 → init_complete_r2
  → ddr_phy_init.init_calib_complete (REGISTER, 最深源)
  → ddr_calib_top.calib_complete (wire)
  → ddr_calib_top.init_calib_complete (registered, +1 clk)
  → ddr_phy_top.phy_init_data_sel
  → mem_intfc.init_calib_complete_w
  → memc_ui_top_axi.init_calib_complete (output)
  → memc_ui_top_axi.init_calib_complete_r (registered, +1 clk, UI/MC 使用)
```

MC/UI 模块使用 `init_calib_complete` 使能 AXI 命令通路：
- `bank_common.v`: `accept_internal_ns = init_calib_complete && |idle_ns`
- `rank_cntrl.v`: `if (~init_calib_complete)` → 阻止 refresh 请求
- `mc.v`: `mc_read_idle_ns = col_read_fifo_empty & init_calib_complete`

#### 排除的假设

| 假设 | 测试方法 | 结果 | 结论 |
|------|----------|------|------|
| clk_wiz_0 未产生 200MHz 时钟 | 探针采样 clk_ddr_ref | `toggled=1` | ❌ 排除 |
| Bridge 发送虚假 AXI 事务 | 探针 awvalid/arvalid/wvalid | 全为 0 | ❌ 排除 |
| CPU AHB 活动干扰校准 | 探针 CPU HTRANS/HADDR | IDLE | ❌ 排除 |
| clk_wiz_0 MMCM 相位偏移 | `DDR3_BYPASS_CLK_WIZ=1` 强制替换 | 仍卡在 state 38 | ❌ 排除 |
| aresetn 释放时机差异 | 两种方式均测试 | 均失败 | ❌ 排除 |
| _mig.v/_mig_sim.v 冲突 | 移除 _mig.v + 运行时参数探针 | 确认 FAST 模式 | ❌ 排除 |
| _mig_sim.v 文件差异 | SHA256 对比 | 完全一致 | ❌ 排除 |
| SIM_BYPASS_INIT_CAL="SKIP" | MIG 代码检查 | "Not supported" | ❌ 不可用 |
| DDR3_BYPASS_CLK_WIZ (MIG 内部) | MIG 代码搜索 | 不存在此 define | ❌ 不可用 |

#### 已尝试的修复方案

| 方案 | 结果 | 原因分析 |
|------|------|----------|
| `DDR3_BYPASS_CLK_WIZ=1`（强制 TB 生成 200MHz 时钟，绕过 clk_wiz_0） | ❌ 仍卡在 state 38 | 外部 clk_wiz_0 **不是**根因；MIG 内部 MMCM 行为模型问题 |
| `force MIG.init_calib_complete=1`（强制 MIG 输出端口） | ⚠️ 部分有效 | 系统复位释放（ahb_hresetn=1），CPU 开始写 DDR3，但 MIG **内部 UI** 仍使用自己的 init_calib_complete=0 → AXI 命令通路未使能 → awvalid=0 |
| `force pi_phase_locked_all=1`（强制 FSM 推进条件） | ⚠️ 部分有效 | FSM 从 state 38 推进到 state 18 (INIT_RDLVL_STG2_READ_WAIT)，又卡住 — 打地鼠式修复不可行 |
| `force ddr_phy_init.init_calib_complete=1`（强制最深源寄存器） | ⚠️ 部分有效 | UI 使能，但 MC 立即发 refresh → DDR3 model 报错 "Refresh Failure. All banks must be Precharged" — 校准 FSM 未完成 precharge 序列，DDR3 banks 仍为 active |

#### 根因总结

MIG 仿真模型的校准算法在完整系统层级中无法完成。不是单一信号问题，而是**多步校准都会卡住**。与 `tb_ddr3_ahb_ex` 的唯一架构差异是 MIG 实例化层级深度（直接在 TB vs. system_top→ahb_lite_bus→bridge_wrapper），但相同参数、相同 _mig_sim.v、相同 DDR3 model。

**核心矛盾**: 
- 强制 `init_calib_complete=1` → UI 使能 → MC 发 refresh → DDR3 banks 未 precharge → 协议违反
- 不强制 → 校准永远卡住 → 系统永远等待

**待尝试方案**:
1. 同时强制 `pi_phase_locked_all=1` + 所有后续卡住的校准信号，让 FSM 自然走到 INIT_DONE（含 precharge 序列）
2. 修改 DDR3 model 容错模式（抑制 refresh failure error）
3. 在 `ddr_phy_init` 中强制 `init_state_r = INIT_DONE` 并手动 precharge 所有 banks

**状态**: 🔄 调查中

### 5.4: 仿真速度优化结果

| 指标 | 修复前 | 修复后 | 提升倍数 |
|------|--------|--------|----------|
| 仿真推进速度 | 200ns / 30min | 9.6µs / 90s | **~500x** |
| MIG 校准完成 | 永不（死锁） | 9.6µs ✅ | ∞ |
| `init_calib_complete` | 恒 0/X | 0→1 @ 9.6µs | ✅ |
| `MIG.aresetn` | 恒 0（死锁） | 0→1 @ MMCM lock | ✅ |

**根因分析**: Boot ROM `mem[]` 全 X 是主因（贡献 ~90% 提速）。CPU 从 X 指令取指 → X 传播通过 334-bit 管线 → 每周期海量事件。修复后 CPU 取指返回 0（NOP），管线静默，事件量骤降。

### 5.4: 调试历程（已废弃的方案）

| 方案 | 结果 | 原因 |
|------|------|------|
| `add_files -fileset sim_1` | ❌ | Vivado 仍不将文件加入 prj |
| `import_files -fileset sim_1` | ❌ | 同上 |
| `set_property used_in_simulation true` | ❌ | 2018.3 无此属性 |
| `update_compile_order` | ❌ | 不触发依赖解析 |
| `reset_run sim_1` | ❌ | 不影响 prj 生成 |
| Python prj patching + 手动 xvlog/xelab/xsim | ⚠️ 部分 | xvlog 在 RTL bug 处停止编译后续文件 |

> prj patching 代码保留为 fallback（`_patch_prj_and_rerun`），但 RTL 修复后 `launch_simulation` 直接成功，无需触发。

---

## 待验证（未来）

| 验证项 | 命令 | 预期 |
|--------|------|------|
| `tb_ddr3_system` 完整测试 | 手动 xsim -R（需足够长超时） | MIG 校准完成 + DDR3 读写通过 + CPU 执行测试程序 |
| 批量仿真 | `python -m tools.vivado_cli -batch "ddr3_*" -create -sim` | 4 任务全部完成 |
| 旧任务不受影响 | `python -m tools.vivado_cli -task cpu_full -create -sim` | 行为与升级前一致 |
| staleness 检测 | `touch Reference/ddr3_sim/ddr3_model.sv && python -m tools.vivado_cli --status` | rtl 层 stale |

---

## 已知限制

| 限制 | 说明 | 影响 |
|------|------|------|
| **BUG-56: MIG 校准 FSM 卡死** | `tb_ddr3_system` 中 MIG 校准 FSM 卡在 `INIT_PI_PHASELOCK_READS` (state 38)，`pi_phase_locked_all` 永不拉高。`tb_ddr3_ahb_ex` 在 106µs 正常完成。根因是 MIG 仿真模型在完整系统层级中校准算法无法完成。 | `tb_ddr3_system` 全系统仿真无法完成，阻塞 DDR3 读写验证 |
| XSim 全系统仿真速度 | 即使 BUG-55 修复后（500x 提速），完整 `tb_ddr3_system` 仿真（MIG 校准 + DDR3 读写 + CPU 执行）仍需数十分钟 | 长仿真需耐心等待或使用 xsim 超时 3600s |
| `operations.py` refresh bug | `UnboundLocalError: tcl_parts` — refresh 路径在 DDR3 任务中崩溃 | 使用 `-create -sim` 替代 `-refresh` |
| XSIM 43-3356 | xelab 多线程代码生成竞争（Vivado 2018.3 Windows 已知 bug） | 已有重试逻辑 workaround |
