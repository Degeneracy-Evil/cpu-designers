# Vivado Orchestrator DDR3 仿真升级计划

> 日期: 2026-06-06 | 状态: 待实施 | 目标: 使 `python -m tools.vivado_cli -task ddr3_ahb_ex -create -sim` 等价于 `vivado -mode batch -source dev/tb/run_ddr3_sim.tcl -tclargs tb_ddr3_ahb_ex`

---

## 1. 现状分析

### 1.1 已有基础设施（无需修改）

| 组件 | 文件 | 说明 |
|------|------|------|
| DDR3/Brige/ClkWiz 配置 | `config.py` | `Ddr3Config`/`AhbBridgeConfig`/`ClkWizConfig` 数据类完整 |
| YAML 配置 | `vivado_config.yaml` | `memory.ddr3.enabled: true`，bridge/clk_wiz 同样已启用 |
| IP 动态生成 | `ip_gen.py` | `generate_mig_create_ip_tcl()`、`generate_bridge_create_ip_tcl()`、`generate_clkwiz_create_ip_tcl()` 均已实现，`generate_all_ip_tcl()` 在 `ddr3.enabled` 时自动调用 |
| MIG 配置文件 | `Reference/mig/mig_a.prj` | 完整的 MIG 7 Series 引脚分配、时序参数、AXI 参数（149 行 XML） |
| 参考生成脚本 | `Reference/mig/gen_ddr_controller.tcl` | 独立的 MIG IP 生成 TCL（345 行），含 `create_ip` + `set_property` + `generate_target` |
| IP 配置报告 | `Reference/mig/ip_report.md` | MIG + Bridge + ClkWiz 完整 `create_ip` 命令、参数说明、连接方案 |
| DDR3 testbench | `dev/tb/tb_ddr3_*.sv` | 4 个：`tb_ddr3_mig_ex`、`tb_ddr3_ahb_ex`、`tb_ddr3_basic`、`tb_ddr3_system` |
| MIG example 项目 | `project/bd_soc_mig_7series_0_1_ex/` | 含 DDR3 仿真模型（`imports/ddr3_model.sv` 等） |

### 1.2 缺失功能（需实现）

| # | 缺失项 | 影响 | 涉及文件 |
|---|--------|------|----------|
| 1 | `TaskConfig` 无 `sim_mode`/`verilog_defines`/`hex_file` 字段 | 无法区分 DDR3 仿真与普通仿真 | `tasks.py` |
| 2 | `tasks.yaml` 无 DDR3 仿真任务定义 | CLI 无法识别 `-task ddr3_ahb_ex` | `tasks.yaml` |
| 3 | 无 DDR3 仿真模型导入（ddr3_model.sv、wiredly.v、glbl.v） | 仿真缺少 DDR3 行为模型和线延迟模型 | `operations.py` |
| 4 | 无 `verilog_define` 设置（`SIM_BYPASS_INIT_CAL=FAST`、`SIMULATION=TRUE`） | MIG 校准不跳过，仿真卡在初始化 | `operations.py` |
| 5 | 无 Bridge VHDL 库 workaround | `set_property library` 在 Vivado 2018.3 损坏 fileset | `operations.py` |
| 6 | 无 hex 文件拷贝支持 | `tb_ddr3_system` 的 `$readmemh` 找不到文件 | `operations.py` |
| 7 | DDR3 仿真模型文件分散在 `project/bd_soc_mig_7series_0_1_ex/imports/` | 无集中管理，变更检测缺失 | 新建 `Reference/ddr3_sim/` |
| 8 | `hash.py` 未覆盖 DDR3 仿真模型 | 模型变更不触发 staleness 检测 | `hash.py` |

---

## 2. 架构决策

### 2.1 IP 生成方式：`create_ip` 动态生成（维持现有方案）

当前 orchestrator 对所有 IP 均采用 `create_ip` 动态生成，不拷贝 XCI。DDR3 相关 IP 同样适用：

```
vivado_config.yaml (memory.ddr3.enabled=true)
  → ip_gen.py: generate_all_ip_tcl()
    → generate_clkwiz_create_ip_tcl()   # create_ip -name clk_wiz ...
    → generate_mig_create_ip_tcl()      # create_ip -name mig_7series ...
    → generate_bridge_create_ip_tcl()   # create_ip -name ahblite_axi_bridge ...
  → operations.py: _tcl_setup_ip()
    → session.execute(tcl)              # Vivado 执行 create_ip + generate_target
```

**MIG IP 的关键配置文件**：`Reference/mig/mig_a.prj`

此 XML 文件是 MIG 7 Series IP 的核心配置，包含：
- DDR3 引脚分配（`PinSelection`，110 行引脚映射）
- 时序参数（`TimingParameters`：tcke/tfaw/tras/trcd/trfc 等）
- 内存型号（`MT41J64M16XX-125G`，128MB）
- AXI 参数（地址宽度 27、数据宽度 32、ID 宽度 8）
- FPGA 器件和 Bank 选择

`ip_gen.py` 通过 `CONFIG.XML_INPUT_FILE` 引用此文件：

```tcl
# ip_gen.py 生成的 MIG create_ip 命令（与 Reference/mig/ip_report.md 一致）
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 \
    -module_name bd_soc_mig_7series_0_1 -dir {ip_dir}/bd_soc_mig_7series_0_1
set_property -dict [list \
    CONFIG.XML_INPUT_FILE        {base_dir/Reference/mig/mig_a.prj} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
] [get_ips bd_soc_mig_7series_0_1]
```

**参考 `create_ip` 命令**（来自 `Reference/mig/ip_report.md` §2）：

| IP | create_ip 命令 | 关键 set_property |
|----|----------------|-------------------|
| MIG 7 Series | `create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name bd_soc_mig_7series_0_1` | `CONFIG.XML_INPUT_FILE`, `CONFIG.RESET_BOARD_INTERFACE {Custom}`, `CONFIG.MIG_DONT_TOUCH_PARAM {Custom}` |
| AHB-AXI Bridge | `create_ip -name ahblite_axi_bridge -vendor xilinx.com -library ip -version 3.0 -module_name ahblite_axi_bridge_0` | `CONFIG.C_M_AXI_THREAD_ID_WIDTH {0}`, `CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {1}` |
| Clocking Wizard | `create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0` | `CONFIG.PRIM_IN_FREQ`, `CONFIG.MMCM_*`, `CONFIG.CLKOUT*_USED`, `CONFIG.RESET_TYPE` |

> ✅ `ip_gen.py` 已正确实现上述所有命令，与参考一致。

### 2.2 DDR3 仿真模型：overlay 方案

`create_ip` 生成 MIG IP 后，`generate_target all` 会生成 MIG 的仿真模型（wrapper + unisim）。
但仿真还需要 **外部 DDR3 行为模型**，这不是 MIG IP 的一部分：

| 文件 | 来源 | 用途 |
|------|------|------|
| `ddr3_model.sv` | MIG example design | DDR3 SDRAM 行为模型（仿真用） |
| `ddr3_model_parameters.vh` | MIG example design | DDR3 时序参数头文件（依赖 MIG 配置） |
| `wiredly.v` | MIG example design | Wire delay 模型（仿真信号延迟） |
| `glbl.v` | Vivado sim 或手动生成 | 全局 GSR/GTS/PRLD 信号 |

**方案**：将这些文件集中存储到 `Reference/ddr3_sim/`，由 orchestrator 在 `create` 阶段导入。

> ⚠ `ddr3_model_parameters.vh` 依赖 MIG 配置。若 MIG 参数变更（如更换 DDR3 芯片型号），需重新从 MIG example design 导出此文件。

---

## 3. 实施计划

### Phase 1: 基础设施 — TaskConfig 扩展 + DDR3 模型集中化

#### 1.1 `tasks.py` — 扩展 TaskConfig

**文件**: `tools/vivado_core/tasks.py`

**改动**: 在 `TaskConfig` 数据类中新增 3 个字段：

```python
@dataclass(frozen=True)
class TaskConfig:
    name: str
    tb: str = ""
    coe: str = ""
    runtime: str = ""
    top: str = ""
    # ↓ 新增
    sim_mode: str = ""                          # "ddr3" 触发 DDR3 仿真流程
    verilog_defines: dict[str, str] = field(default_factory=dict)  # 仿真 verilog defines
    hex_file: str = ""                          # 可选 hex 文件（相对 dev/program_source/）
```

**改动**: `TaskRegistry.load()` 解析新字段：

```python
self._tasks[name] = TaskConfig(
    name=name,
    tb=cfg.get("tb", ""),
    coe=cfg.get("coe", ""),
    runtime=cfg.get("runtime", ""),
    top=cfg.get("top", ""),
    sim_mode=cfg.get("sim_mode", ""),                          # 新增
    verilog_defines=cfg.get("verilog_defines", {}) or {},      # 新增
    hex_file=cfg.get("hex_file", ""),                          # 新增
)
```

**向后兼容**: 旧 `tasks.yaml` 无新字段时使用默认值（空字符串/空字典），不影响现有任务。

#### 1.2 `Reference/ddr3_sim/` — 集中存储 DDR3 仿真模型

**操作**: 从 `project/bd_soc_mig_7series_0_1_ex/imports/` 复制文件到 `Reference/ddr3_sim/`：

```
Reference/ddr3_sim/
├── ddr3_model.sv              # DDR3 内存行为模型
├── ddr3_model_parameters.vh   # DDR3 时序参数（⚠ MIG 配置依赖，变更时需重新导出）
└── wiredly.v                  # Wire delay 模型
```

**glbl.v 处理**: 不预存，在 TCL 中动态生成 stub（与 `run_ddr3_sim.tcl` 一致）：

```tcl
# 若 dev/tb/glbl.v 存在则导入，否则生成 stub
set glbl_path [file join $proj_dir glbl.v]
set glbl_fp [open $glbl_path w]
puts $glbl_fp "`timescale 1ps/1ps"
puts $glbl_fp "module glbl();"
puts $glbl_fp "  wire GSR = 1'b1;"
puts $glbl_fp "  wire GTS = 1'b0;"
puts $glbl_fp "  wire PRLD = 1'b1;"
puts $glbl_fp "  wire LOCK = 1'b1;"
puts $glbl_fp "endmodule"
close $glbl_fp
add_files -norecurse $glbl_path
```

#### 1.3 `tasks.yaml` — 添加 DDR3 仿真任务

**文件**: `tasks.yaml`

**改动**: 在文件末尾（`ddr3_test` 之后）追加：

```yaml
  # DDR3 simulation tasks (require sim_mode: ddr3)
  ddr3_mig_ex:
    tb: tb_ddr3_mig_ex
    sim_mode: ddr3
    verilog_defines:
      SIM_BYPASS_INIT_CAL: FAST
      SIMULATION: "TRUE"
    runtime: 1000us

  ddr3_ahb_ex:
    tb: tb_ddr3_ahb_ex
    sim_mode: ddr3
    verilog_defines:
      SIM_BYPASS_INIT_CAL: FAST
      SIMULATION: "TRUE"
    runtime: 1000us

  ddr3_basic:
    tb: tb_ddr3_basic
    sim_mode: ddr3
    verilog_defines:
      SIM_BYPASS_INIT_CAL: FAST
      SIMULATION: "TRUE"
    runtime: 1000us

  ddr3_system:
    tb: tb_ddr3_system
    sim_mode: ddr3
    verilog_defines:
      SIM_BYPASS_INIT_CAL: FAST
      SIMULATION: "TRUE"
    hex_file: app/ddr3_test.hex
    runtime: 10ms
```

---

### Phase 2: 核心逻辑 — operations.py DDR3 仿真支持

#### 2.1 新增 `_tcl_add_ddr3_sim_models()`

**文件**: `tools/vivado_core/operations.py`

**功能**: 添加 DDR3 仿真模型文件到 Vivado 项目

```python
def _tcl_add_ddr3_sim_models(base_dir: str, proj_dir: str) -> str:
    """添加 DDR3 仿真模型文件（ddr3_model.sv、wiredly.v、glbl.v）。

    Parameters
    ----------
    base_dir : str
        项目根目录（TCL 路径格式）。
    proj_dir : str
        Vivado 项目目录（TCL 路径格式），用于生成 glbl.v stub。
    """
```

**生成 TCL**：

```tcl
# --- DDR3 simulation model ---
add_files -norecurse "{base_dir}/Reference/ddr3_sim/ddr3_model.sv"
add_files -norecurse "{base_dir}/Reference/ddr3_sim/ddr3_model_parameters.vh"
set_property file_type "Verilog Header" [get_files ddr3_model_parameters.vh]
add_files -norecurse "{base_dir}/Reference/ddr3_sim/wiredly.v"

# --- glbl.v (global reset/set signals) ---
set glbl_v "{base_dir}/dev/tb/glbl.v"
if {[file exists $glbl_v]} {
    add_files -norecurse $glbl_v
} else {
    set glbl_path "{proj_dir}/glbl.v"
    set glbl_fp [open $glbl_path w]
    puts $glbl_fp "`timescale 1ps/1ps"
    puts $glbl_fp "module glbl();"
    puts $glbl_fp "  wire GSR = 1'b1;"
    puts $glbl_fp "  wire GTS = 1'b0;"
    puts $glbl_fp "  wire PRLD = 1'b1;"
    puts $glbl_fp "  wire LOCK = 1'b1;"
    puts $glbl_fp "endmodule"
    close $glbl_fp
    add_files -norecurse $glbl_path
}
```

#### 2.2 新增 `_tcl_set_verilog_defines()`

**功能**: 设置仿真 verilog defines

```python
def _tcl_set_verilog_defines(defines: dict[str, str]) -> str:
    """设置 verilog defines 用于仿真（如 SIM_BYPASS_INIT_CAL=FAST）。

    Parameters
    ----------
    defines : dict[str, str]
        定义名到值的映射，如 {"SIM_BYPASS_INIT_CAL": "FAST", "SIMULATION": "TRUE"}。
    """
```

**生成 TCL**：

```tcl
# --- verilog defines for simulation ---
set define_str "SIM_BYPASS_INIT_CAL=FAST SIMULATION=TRUE"
set_property verilog_define {$define_str} [get_filesets sim_1]
set_property verilog_define {$define_str} [current_fileset]
```

> 注意：TCL 中 `set_property verilog_define` 接受空格分隔的 `NAME=VALUE` 列表。

#### 2.3 新增 `_tcl_handle_bridge_vhdl()`

**功能**: Bridge VHDL 库 workaround

```python
def _tcl_handle_bridge_vhdl() -> str:
    """从项目中移除 Bridge VHDL 文件（避免 set_property library 损坏 fileset）。

    Vivado 2018.3 的 set_property library 会损坏 fileset。
    Bridge VHDL 需要编译到库 ahblite_axi_bridge_v3_0_13 中，
    但通过 create_ip 生成的 IP 已自动处理库映射，
    此 workaround 仅在从外部导入 VHDL 时需要。

    当使用 create_ip 方式时，Vivado 自动管理库映射，
    此函数作为安全措施移除可能冲突的文件。
    """
```

**生成 TCL**：

```tcl
# --- Bridge VHDL library workaround ---
# 移除可能冲突的 bridge VHDL 文件
set bridge_files [get_files -of_objects [get_filesets sources_1] -quiet "*ahblite_axi_bridge*"]
if {[llength $bridge_files] > 0} {
    remove_files $bridge_files
    puts "Removed [llength $bridge_files] bridge VHDL files from project"
}
```

> **重要说明**：当使用 `create_ip` 方式创建 Bridge IP 时，Vivado 自动将 VHDL 编译到正确的库。
> 此 workaround 主要防止用户手动导入 Bridge VHDL 文件时与 `create_ip` 生成的文件冲突。
> 若 `create_ip` 方式下仿真正常，此函数可简化为空操作。

#### 2.4 新增 `_tcl_copy_hex_file()`

**功能**: 拷贝 hex 文件到项目目录

```python
def _tcl_copy_hex_file(hex_src: str, proj_dir: str) -> str:
    """拷贝 hex 文件到项目目录以供 $readmemh 访问。

    Parameters
    ----------
    hex_src : str
        hex 文件绝对路径（TCL 路径格式）。
    proj_dir : str
        Vivado 项目目录（TCL 路径格式）。
    """
```

**生成 TCL**：

```tcl
# --- copy hex file for $readmemh ---
if {[file exists "{hex_src}"]} {
    file copy -force "{hex_src}" "{proj_dir}/prog.hex"
    puts "Copied {hex_src} -> {proj_dir}/prog.hex"
} else {
    puts "WARNING: HEX file not found: {hex_src}"
}
```

#### 2.5 修改 `Operations.create()` — 条件性添加 DDR3 仿真支持

**改动位置**: `Operations.create()` 方法，在 `tcl` 拼接处

```python
def create(self, session: Session, task: TaskConfig) -> ExecuteResult:
    ...
    tcl_parts = [
        _tcl_create_project(proj_name, device_part, proj_dir, dev, base),
        _tcl_setup_ip(proj_name, proj_dir, base, coe_file, mem_config),
        _tcl_add_constrs(base),
    ]

    # ↓ 新增：DDR3 仿真模式 — 添加仿真模型
    if task.sim_mode == "ddr3":
        tcl_parts.append(_tcl_add_ddr3_sim_models(base, proj_dir))
        tcl_parts.append(_tcl_handle_bridge_vhdl())

    tcl = "\n".join(tcl_parts)
    ...
```

#### 2.6 修改 `Operations.sim()` — 条件性设置 verilog defines + hex

**改动位置**: `Operations.sim()` 方法，在 `tcl` 拼接处

```python
def sim(self, session: Session, task: TaskConfig, runtime: str | None = None) -> ExecuteResult:
    ...
    tcl_parts = [
        _tcl_open_project(proj_dir, proj_name),
        _tcl_add_tb(dev, proj_dir, proj_name, task.tb, coe_file),
    ]

    # ↓ 新增：DDR3 仿真 defines
    if task.verilog_defines:
        tcl_parts.append(_tcl_set_verilog_defines(task.verilog_defines))

    # ↓ 新增：hex 文件拷贝
    if task.hex_file:
        hex_path = self._resolve_hex_path(task)
        tcl_parts.append(_tcl_copy_hex_file(hex_path, proj_dir))

    tcl_parts.append(_tcl_run_sim(task.tb, sim_runtime, proj_dir, proj_name))
    tcl = "\n".join(tcl_parts)
    ...
```

**新增辅助方法**：

```python
def _resolve_hex_path(self, task: TaskConfig) -> str:
    """Return the absolute hex file path for a task, or empty string."""
    if not task.hex_file:
        return ""
    return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.hex_file)
```

---

### Phase 3: 增量刷新 — hash.py 适配

#### 3.1 `hash.py` — DDR3 仿真模型纳入 `rtl` 层

**文件**: `tools/vivado_core/hash.py`

**改动**: 在 `HASH_GLOBS["rtl"]` 列表末尾追加 3 个 glob：

```python
HASH_GLOBS: dict[str, list[str]] = {
    "rtl": [
        "dev/rtl/**/*.sv",
        "dev/rtl/**/*.svh",
        "Reference/**/*.xci",
        "vivado_config.yaml",
        "tools/vivado_core/**/*.py",
        # ↓ 新增：DDR3 仿真模型
        "Reference/ddr3_sim/**/*.sv",
        "Reference/ddr3_sim/**/*.vh",
        "Reference/ddr3_sim/**/*.v",
    ],
    ...
}
```

**理由**：DDR3 仿真模型变更应触发全量重建（与 RTL 同级），因为模型直接影响仿真结果正确性。

#### 3.2 `sync.py` — 无需修改

DDR3 模型归入 `rtl` 层，变更时自动触发全量刷新，无需额外逻辑。

---

### Phase 4: 文档更新

#### 4.1 SKILL.md — 添加 DDR3 仿真文档

**文件**: `.opencode/skills/vivado-orchestrator/SKILL.md`

**新增章节**：

```markdown
### DDR3 仿真

DDR3 仿真任务使用 `sim_mode: ddr3` 标记，自动添加 MIG 仿真模型和 verilog defines。

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

#### DDR3 仿真任务

| 任务 | Testbench | 说明 | 仿真时间 |
|------|-----------|------|----------|
| `ddr3_mig_ex` | tb_ddr3_mig_ex | MIG DDR3 控制器测试 | 1000us |
| `ddr3_ahb_ex` | tb_ddr3_ahb_ex | AHB 总线 + DDR3 测试 | 1000us |
| `ddr3_basic` | tb_ddr3_basic | DDR3 基础测试 | 1000us |
| `ddr3_system` | tb_ddr3_system | 全系统 DDR3 测试 | 10ms |

#### DDR3 仿真模型

仿真模型文件位于 `Reference/ddr3_sim/`：

| 文件 | 说明 |
|------|------|
| `ddr3_model.sv` | DDR3 SDRAM 行为模型 |
| `ddr3_model_parameters.vh` | DDR3 时序参数（⚠ 依赖 MIG 配置） |
| `wiredly.v` | Wire delay 模型 |

> ⚠ 若修改 MIG 配置（如更换 DDR3 芯片），需重新从 MIG example design 导出 `ddr3_model_parameters.vh`。

#### MIG 配置文件

MIG IP 的核心配置由 `Reference/mig/mig_a.prj` 定义，包含引脚分配、时序参数、内存型号等。
修改此文件后需全量刷新（`-refresh`）。
```

#### 4.2 可用任务表 — 追加 DDR3 任务

在 SKILL.md 的可用任务表中追加 4 行 DDR3 任务。

---

## 4. 实施顺序与依赖关系

```
Phase 1.1 (TaskConfig 扩展)  ──┐
Phase 1.2 (DDR3 模型集中化)   │  可并行
Phase 1.3 (tasks.yaml)       ──┘
         │
         ▼
Phase 2 (operations.py 核心逻辑)
  2.1 _tcl_add_ddr3_sim_models()
  2.2 _tcl_set_verilog_defines()
  2.3 _tcl_handle_bridge_vhdl()
  2.4 _tcl_copy_hex_file()
  2.5 修改 create()
  2.6 修改 sim()
         │
         ▼
Phase 3 (hash.py 适配)
         │
         ▼
Phase 4 (文档更新)
```

---

## 5. 改动量与风险评估

| Phase | 文件 | 改动类型 | 改动量 | 风险 | 说明 |
|-------|------|----------|--------|------|------|
| 1.1 | `tools/vivado_core/tasks.py` | 修改 | 小（+3 字段 + 解析） | 低 | 向后兼容，默认值安全 |
| 1.2 | `Reference/ddr3_sim/` | 新建 | 小（3 文件复制） | 低 | 从现有 MIG example 复制 |
| 1.3 | `tasks.yaml` | 修改 | 小（+4 任务定义） | 低 | 纯数据追加 |
| 2.1 | `tools/vivado_core/operations.py` | 新增函数 | 中（~40 行） | 中 | 需验证 TCL 路径在 Windows/Linux 正确 |
| 2.2 | `tools/vivado_core/operations.py` | 新增函数 | 小（~15 行） | 低 | 标准 set_property |
| 2.3 | `tools/vivado_core/operations.py` | 新增函数 | 小（~10 行） | 中 | `create_ip` 方式下可能不需要，需实测 |
| 2.4 | `tools/vivado_core/operations.py` | 新增函数 | 小（~10 行） | 低 | 标准 file copy |
| 2.5 | `tools/vivado_core/operations.py` | 修改 | 小（+4 行条件分支） | 低 | 仅 `sim_mode == "ddr3"` 时触发 |
| 2.6 | `tools/vivado_core/operations.py` | 修改 | 小（+8 行条件分支） | 低 | 仅 `verilog_defines`/`hex_file` 非空时触发 |
| 3.1 | `tools/vivado_core/hash.py` | 修改 | 小（+3 glob） | 低 | 归入已有 `rtl` 层 |
| 4.1 | `.opencode/skills/.../SKILL.md` | 修改 | 小（+30 行文档） | 无 | 纯文档 |

---

## 6. 验证计划

### 6.1 Phase 1 验证

```bash
# TaskConfig 解析不报错
python -c "from tools.vivado_core.tasks import TaskRegistry; r = TaskRegistry('tasks.yaml'); r.load(); print(r.get('ddr3_ahb_ex'))"

# 输出应包含: TaskConfig(name='ddr3_ahb_ex', tb='tb_ddr3_ahb_ex', sim_mode='ddr3', ...)
```

### 6.2 Phase 2 验证

```bash
# DDR3 仿真 — 对比验证
# 方式 1: orchestrator
python -m tools.vivado_cli -task ddr3_ahb_ex -create -sim

# 方式 2: 原 TCL 脚本
vivado -mode batch -source dev/tb/run_ddr3_sim.tcl -tclargs tb_ddr3_ahb_ex

# 对比: 仿真结果应一致（PASS/FAIL 相同）
```

### 6.3 Phase 3 验证

```bash
# 修改 DDR3 模型文件后，staleness 检测
touch Reference/ddr3_sim/ddr3_model.sv
python -m tools.vivado_cli --status
# 应显示 rtl 层 stale
```

### 6.4 全量验证

| 测试 | 命令 | 预期 |
|------|------|------|
| MIG 测试 | `python -m tools.vivado_cli -task ddr3_mig_ex -create -sim` | 仿真完成，无 ERROR |
| AHB 测试 | `python -m tools.vivado_cli -task ddr3_ahb_ex -create -sim` | 仿真完成，无 ERROR |
| 基础测试 | `python -m tools.vivado_cli -task ddr3_basic -create -sim` | 仿真完成，无 ERROR |
| 系统测试 | `python -m tools.vivado_cli -task ddr3_system -create -sim` | 仿真完成，无 ERROR |
| 批量测试 | `python -m tools.vivado_cli -batch "ddr3_*" -create -sim` | 4 任务全部完成 |
| 旧任务不受影响 | `python -m tools.vivado_cli -task cpu_full -create -sim` | 行为与升级前一致 |

---

## 7. 与 `run_ddr3_sim.tcl` 的等价性对照

| `run_ddr3_sim.tcl` 步骤 | orchestrator 对应 | 等价性 |
|--------------------------|-------------------|--------|
| `create_project` | `_tcl_create_project()` | ✅ 等价 |
| 添加 MIG sim model（从 example project） | `create_ip` + `generate_target` 自动生成 | ✅ 等价（动态生成 vs 预生成） |
| 添加 DDR3 model + WireDelay | `_tcl_add_ddr3_sim_models()` | ✅ 等价（从 `Reference/ddr3_sim/` 导入） |
| 添加 Bridge VHDL + ClkWiz | `create_ip` + `generate_target` | ✅ 等价（动态生成） |
| 添加 glbl.v | `_tcl_add_ddr3_sim_models()` 内动态生成 | ✅ 等价 |
| 添加项目 RTL | `_tcl_create_project()` 内 glob 导入 | ✅ 等价 |
| 添加 testbench | `_tcl_add_tb()` | ✅ 等价 |
| `set_property verilog_define` | `_tcl_set_verilog_defines()` | ✅ 等价 |
| Bridge VHDL 库 workaround | `_tcl_handle_bridge_vhdl()` | ✅ 等价（`create_ip` 方式下可能不需要） |
| hex 文件拷贝 | `_tcl_copy_hex_file()` | ✅ 等价 |
| `set_property xsim.simulate.runtime` | `_tcl_run_sim()` 内设置 | ✅ 等价 |
| `launch_simulation` | `_tcl_run_sim()` 内调用 | ✅ 等价 |
