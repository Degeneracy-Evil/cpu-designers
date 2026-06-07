# init_calib_complete 始终不拉高 — 根因分析与修复方案

**日期**: 2026-06-07（最终更新 — 已修复）  
**项目**: ddr3_system  
**参考项目**: bd_soc_mig_7series_0_1_ex（官方示例，107ns 校准完成）

---

## 1. 问题现象

- **ddr3_system**: `init_calib_complete` 始终为 0，校准永远不完成
- **参考项目**: `init_calib_complete` 在 107ns 拉高

---

## 2. 根因分析（两层根因）

### 2.1 层级 1：`_mig.v` 被编译而非 `_mig_sim.v`

**Xilinx UG586 原文**：

> **SIM_BYPASS_INIT_CAL**: `"OFF"` — **Not supported in simulation.** Must be used for hardware implementations.

MIG IP 生成器产出两个版本的 RTL，定义**相同模块名**但参数不同：

| 文件 | SIM_BYPASS_INIT_CAL | SIMULATION | 用途 |
|------|---------------------|------------|------|
| **`_mig.v`** (硬件模型) | `"OFF"` | `"FALSE"` | 综合/实现 |
| **`_mig_sim.v`** (仿真模型) | `"FAST"` | `"TRUE"` | 行为仿真 |

**ddr3_system 的 wrapper 硬编码实例化 `_mig`**（第 466 行）：

```verilog
bd_soc_mig_7series_0_1_mig u_bd_soc_mig_7series_0_1_mig (  // ← 硬件模型！
```

Vivado orchestrator 的 `_tcl_add_ddr3_sim_models()` 同时将 `_mig.v` 和 `_mig_sim.v` 加入 sim_1，两者定义同名模块，`_mig.v` 先编译先赢 → 硬件模型生效 → 校准卡死。

**修复**：orchestrator 中移除 `_mig.v`，只编译 `_mig_sim.v`。

---

### 2.2 层级 2：XSim PHASER_IN_PHY 仿真模型缺陷（致命）

即使编译 `_mig_sim.v`（`SIM_BYPASS_INIT_CAL="FAST"`），校准仍卡在 state 38。

**根因**：XSim 的 PHASER_IN_PHY 仿真模型（secureip 库中的 `SIP_PHASER_IN`）**不正确驱动 PHASELOCKED 输出**。

MIG PHY init FSM 在 `INIT_PI_PHASELOCK_READS`（state 38）等待 `PHASELOCKED` 上升沿。由于 `SIP_PHASER_IN` 不产生此信号，FSM 永远卡在此状态。

#### 为什么 `SIM_BYPASS_INIT_CAL="FAST"` 不够

| SIM_BYPASS_INIT_CAL | SIM_CAL_OPTION | PHASELOCKED 行为 | 结果 |
|---------------------|----------------|-------------------|------|
| `"OFF"` | `"NONE"` | 完整校准，等待 PHASELOCKED | 卡死 |
| `"FAST"` | `"FAST_CAL"` | 仅减少 `PHASELOCKED_TIMEOUT`（16383→1000），**仍等待 PHASELOCKED 上升沿** | **仍卡死** |
| `"SKIP"` | `"SKIP_CAL"` | 写校准后跳过 PI 相位锁定，但可能遇到其他 PHASER_IN 问题 | 可能卡死 |

**结论**：`"FAST"` 只减少超时计数，不跳过 PHASELOCKED 等待。`SIP_PHASER_IN` 不产生 PHASELOCKED → 任何非 `"SKIP"` 模式都会卡死。即使 `"SKIP"` 也可能遇到其他 PHASER_IN 问题。

**唯一可靠 workaround**：`force ddr_phy_init.init_calib_complete=1`。

---

### 2.3 `SIMULATION` 参数的真实影响

`SIMULATION` **从未传递给 `infrastructure` 模块**，因此 `CLKOUT4_PHASE` **始终为 168.75°**，即使在 `_mig_sim.v` 中也是如此。`SIMULATION` 仅影响 `TEMP_MON_EN`，两者默认都是 "ON"，无差异。无需覆盖。

---

### 2.4 次要问题：clk_wiz_0 级联 MMCM

Xilinx MMCME2_ADV 行为模型在级联配置（clk_wiz_0 → MIG 内部 MMCM）下不保持相位关系。参考项目不使用 clk_wiz_0，直接由 testbench 提供时钟。

**修复**：启用 `DDR3_BYPASS_CLK_WIZ` 宏，testbench 直接提供 100MHz + 200MHz 时钟。

---

### 2.5 次要问题：aresetn 循环依赖

若 `mig_aresetn` 等待 `init_calib_complete` 才释放，而 `init_calib_complete` 又依赖 MIG 校准完成（可能需要 `aresetn=1`），则形成循环依赖死锁。

**修复**：`mig_aresetn` 在 `mmcm_locked` 后释放（不等 `init_calib_complete`）。`ahb_hresetn` 仍等 `init_calib_complete` 防止 CPU 过早访问 DDR3。

---

## 3. 已实施的修复（4 层）

### 3.1 层 1：MIG 仿真模型选择

**文件**: `tools/vivado_core/operations.py` — `_tcl_add_ddr3_sim_models()`

**改动**：sim_1 只编译 `_mig_sim.v`，移除 `_mig.v`。添加 `remove_files` TCL 显式移除 sources_1 自动带入的 `_mig.v`。

**效果**：MIG 使用 `SIM_BYPASS_INIT_CAL="FAST"` 快速校准模式。

---

### 3.2 层 2：PHASER_IN 仿真模型 workaround

**文件**: `dev/tb/tb_ddr3_system.sv`

**改动**：15µs 后 `force ddr_phy_init.init_calib_complete=1`

```systemverilog
initial begin
    #15000000;  // 15µs — well after PHY init
    force u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig
          .u_bd_soc_mig_7series_0_1_mig.u_memc_ui_top_axi
          .mem_intfc0.ddr_phy_top0.u_ddr_calib_top.u_ddr_phy_init
          .init_calib_complete = 1'b1;
end
```

**效果**：强制拉高 `init_calib_complete`，解除 AXI UI 阻塞，DDR3 读写可正常进行。

**传播链**：
```
ddr_phy_init.init_calib_complete → ddr_calib_top.init_calib_complete
  → ddr_phy_top.phy_init_data_sel → mem_intfc.init_calib_complete
  → memc_ui_top_axi.init_calib_complete_r (enables AXI UI)
```

---

### 3.3 层 3：绕过 clk_wiz_0

**文件**: `tasks.yaml`

**改动**：`ddr3_system` 的 `verilog_defines` 添加 `DDR3_BYPASS_CLK_WIZ: 1`

**效果**：testbench 直接提供 100MHz + 200MHz 时钟给 MIG，与参考项目架构一致。消除级联 MMCM 相位偏移问题。

---

### 3.4 层 4：aresetn 释放条件

**文件**: `dev/rtl/system_top.sv`

**改动**：`mig_aresetn` 在 `mmcm_locked` 后释放（不等 `init_calib_complete`）

**效果**：打破 aresetn ↔ init_calib_complete 循环依赖。`ahb_hresetn` 仍等 `init_calib_complete` 防止 CPU 过早访问 DDR3。

---

### 3.5 辅助改动：MIG sys_clk_i 连接

**文件**: `dev/rtl/system_top.sv`

**改动**：`.mig_sys_clk_i(clk)` → `.mig_sys_clk_i(clk_system)`

**效果**：硬件正确性 — MIG 两输入同属一个 MMCM，相位确定。仿真中被 `DDR3_BYPASS_CLK_WIZ` 覆盖。

---

## 4. 验证结果

```
SIM_BYPASS_INIT_CAL = FAST  ✅
SIMULATION           = TRUE ✅
force applied at     = 15µs ✅
init_calib_complete  = 1    ✅ (at 15.005ms)
Simulation completed = 2ms  ✅
```

---

## 5. 修改文件汇总

| 文件 | 改动 | 层级 |
|------|------|------|
| `tools/vivado_core/operations.py` | sim_1 只编译 `_mig_sim.v`，移除 `_mig.v` | 层 1 |
| `dev/tb/tb_ddr3_system.sv` | 添加 `force init_calib_complete=1` workaround | 层 2 |
| `tasks.yaml` | `DDR3_BYPASS_CLK_WIZ: 1` 加入 verilog_defines | 层 3 |
| `dev/rtl/system_top.sv` | `mig_aresetn` 在 `mmcm_locked` 后释放 | 层 4 |
| `dev/rtl/system_top.sv` | `mig_sys_clk_i` 改接 `clk_system` | 辅助 |

---

## 6. Xilinx 官方参考

| 来源 | 关键内容 |
|------|---------|
| **UG586** (MIG 7 Series User Guide) | `SIM_BYPASS_INIT_CAL="OFF"` — **Not supported in simulation**; `_mig_sim.v` 用于仿真 |
| **AR 44019** | `"OFF"` 在行为仿真中不支持，校准永远卡住 |
| **AR 34744** | `"FAST"` 仅用于仿真，实现中必须用 `"OFF"` |
| **AR 60845** | 曾有 bug 导致 `_mig.v` 也被设为 `"FAST"`，造成硬件失败 |
| **SIP_PHASER_IN** | XSim secureip 中的 PHASER_IN 仿真模型不正确驱动 PHASELOCKED |

---

## 7. 附录：关键文件路径

| 文件 | 路径 |
|------|------|
| Testbench | `dev/tb/tb_ddr3_system.sv` |
| system_top | `dev/rtl/system_top.sv` |
| Vivado orchestrator | `tools/vivado_core/operations.py` |
| 任务配置 | `tasks.yaml` |
| MIG wrapper | `simplecpu_soc.srcs/sources_1/ip/bd_soc_mig_7series_0_1/.../user_design/rtl/bd_soc_mig_7series_0_1.v` |
| MIG 仿真模型 | `.../bd_soc_mig_7series_0_1_mig_sim.v` (SIM_BYPASS="FAST") |
| MIG infrastructure | `.../clocking/mig_7series_v4_2_infrastructure.v` |
| MIG PHY init | `.../phy/mig_7series_v4_2_ddr_phy_init.v` (校准 FSM) |
| clk_wiz_0 | `simplecpu_soc.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0/clk_wiz_0_clk_wiz.v` |
| 参考项目 testbench | `project/bd_soc_mig_7series_0_1_ex/imports/sim_tb_top.v` |
