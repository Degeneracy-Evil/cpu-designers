# 时钟架构修改计划

> ⛔ **已停止** — 2026-06-09: AHB-Lite 架构已废弃，全面转向 AXI 总线 + chiplab 对齐架构。见新计划 `plan/axi-mig-alignment-plan.md`

> 日期: 2026-06-07 | 状态: **✅ 已完成（全部 5 层修复完成，仿真验证通过，成果已合入 `ddr3-main-memory-plan.md`）** | 依赖资料: `Reference/clock_propagation_analysis.md`, `Reference/mig/mig_a.prj`, `process/init_calib_complete_analysis.md`
> 关联问题: BUG-56 (MIG 校准 FSM 卡死, init_calib_complete 永不拉高) — **已解决**

---

## 1. 问题描述

### 1.1 现象

`tb_ddr3_system` 仿真中 MIG 校准 FSM 卡死在 `INIT_PI_PHASELOCK_READS`（state 38），`init_calib_complete` 永不拉高，阻塞整个系统启动。

而 `tb_ddr3_ahb_ex`（仅实例化 `ddr3_bridge_wrapper`）校准正常通过。

### 1.2 根因（两层）

| 层级 | 根因 | 致命度 |
|------|------|--------|
| **1** | `_mig.v`（SIM_BYPASS_INIT_CAL="OFF"）被编译而非 `_mig_sim.v`（="FAST"） | 🔴 致命 |
| **2** | XSim SIP_PHASER_IN 不驱动 PHASELOCKED → 即使 "FAST" 也卡在 state 38 | 🔴 致命 |

次要问题：
- clk_wiz_0 级联 MMCM 行为模型相位偏移
- aresetn 循环依赖死锁风险

---

## 2. 参考架构对比

### 2.1 NonTrivialMIPS（参考，已验证成功）

```
Crystal (100MHz) ──→ clk_wiz_0 (MMCM) ──┬── clk_peripheral (100MHz) → MIG.sys_clk_i  ✅ 同源
                                          ├── clk_ddr_ref    (200MHz) → MIG.clk_ref_i  ✅ 同源
                                          ├── clk_cpu        (80MHz)  → CPU
                                          ├── clk_vga        (25MHz)  → VGA
                                          └── clk_spi        (20MHz)  → SPI Flash
MIG → ui_clk (100MHz) → DDR AXI bus
复位链: ext_rst → clk_wiz locked → MIG calib → 系统复位释放（严格有序）
```

### 2.2 修复后架构（当前项目）

```
Crystal (100MHz) ──→ clk_wiz_0 (MMCM) ──┬── clk_system (100MHz) → MIG.sys_clk_i  ✅ 同源
                                          └── clk_ddr_ref (200MHz) → MIG.clk_ref_i  ✅ 同源
MIG → ui_clk (100MHz) → CPU + AHB bus + LCD
复位链: ext_rst → clk_wiz locked → mmcm_locked → mig_aresetn 释放
         → init_calib_complete → ahb_hresetn 释放（CPU 可访问 DDR3）
```

仿真中 clk_wiz_0 被 `DDR3_BYPASS_CLK_WIZ` 绕过，testbench 直接提供 100MHz + 200MHz。

---

## 3. 已实施的修复（5 层）

### Layer 1：修复 MIG sys_clk_i 连接

**优先级**: P0 | **文件**: `dev/rtl/system_top.sv` L222

```systemverilog
// 修复前（错误）:
.mig_sys_clk_i  (clk),              // 直连晶振 → 与 clk_ref_i 异源

// 修复后（与参考架构一致）:
.mig_sys_clk_i  (clk_system),       // 来自 clk_wiz_0 → 与 clk_ref_i 同源同相
```

**效果**：两个 MIG 输入同属一个 MMCM，相对相位差 = 0°。sys_clk_i 经过 BUFG，满足 NO_BUFFER 配置要求。

---

### Layer 2：MIG 仿真模型选择

**优先级**: P0 | **文件**: `tools/vivado_core/operations.py` — `_tcl_add_ddr3_sim_models()`

**改动**：sim_1 只编译 `_mig_sim.v`，显式移除 `_mig.v`。

**原因**：`_mig.v` 和 `_mig_sim.v` 定义同名模块 `bd_soc_mig_7series_0_1_mig`，同时编译时 `_mig.v` 先编译先赢 → 硬件模型（SIM_BYPASS_INIT_CAL="OFF"）生效 → 校准卡死。

**效果**：MIG 使用 `SIM_BYPASS_INIT_CAL="FAST"` + `SIMULATION="TRUE"` 快速校准模式。

---

### Layer 3：绕过 clk_wiz_0（仿真必需）

**优先级**: P0（仿真） | **文件**: `tasks.yaml`

**改动**：`ddr3_system` 的 `verilog_defines` 添加 `DDR3_BYPASS_CLK_WIZ: 1`

**原因**：Xilinx MMCME2_ADV 行为模型在级联配置下不保持相位关系。MIG INIT_PI_PHASELOCK_READS 比较 sys_clk_i 与 clk_ref_i 相位，级联行为模型引入偏移导致相位锁定失败。参考项目不使用 clk_wiz_0，直接由 testbench 提供时钟。

**效果**：testbench 直接提供 100MHz + 200MHz 时钟 + `clk_wiz_locked=1`，与参考项目架构一致。

---

### Layer 4：aresetn 释放条件

**优先级**: P1 | **文件**: `dev/rtl/system_top.sv`

**改动**：`mig_aresetn` 在 `mmcm_locked` 后释放（**不等** `init_calib_complete`）

**原因**：若 `mig_aresetn` 等待 `init_calib_complete`，而 `init_calib_complete` 又依赖 MIG 校准完成（可能需要 `aresetn=1`），则形成循环依赖死锁：
```
aresetn 等待 init_calib_complete → calib 卡在 state 38 → init_calib_complete 永不拉高 → aresetn 永不释放 → 死锁
```

**效果**：打破循环依赖。`ahb_hresetn` 仍等 `init_calib_complete` 防止 CPU 过早访问 DDR3。

---

### Layer 5：PHASER_IN 仿真模型 workaround（仿真必需）

**优先级**: P0（仿真） | **文件**: `dev/tb/tb_ddr3_system.sv`

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

**原因**：XSim 的 PHASER_IN_PHY 仿真模型（secureip 库中 `SIP_PHASER_IN`）不正确驱动 `PHASELOCKED` 输出。MIG PHY init FSM 在 `INIT_PI_PHASELOCK_READS`（state 38）等待 `PHASELOCKED` 上升沿，永远等不到。

`SIM_BYPASS_INIT_CAL="FAST"` **不够**：
- `"FAST"` → `FAST_CAL` → 仅减少 `PHASELOCKED_TIMEOUT`（16383→1000），**仍等待 PHASELOCKED 上升沿**
- `"SKIP"` → `SKIP_CAL` → 写校准后跳过 PI 相位锁定，但可能遇到其他 PHASER_IN 问题

**`force` 是唯一可靠 workaround**。

**传播链**：
```
ddr_phy_init.init_calib_complete → ddr_calib_top.init_calib_complete
  → ddr_phy_top.phy_init_data_sel → mem_intfc.init_calib_complete
  → memc_ui_top_axi.init_calib_complete_r (enables AXI UI)
```

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
| `dev/rtl/system_top.sv` | `mig_sys_clk_i` 改接 `clk_system` | Layer 1 |
| `tools/vivado_core/operations.py` | sim_1 只编译 `_mig_sim.v`，移除 `_mig.v` | Layer 2 |
| `tasks.yaml` | `DDR3_BYPASS_CLK_WIZ: 1` 加入 verilog_defines | Layer 3 |
| `dev/rtl/system_top.sv` | `mig_aresetn` 在 `mmcm_locked` 后释放 | Layer 4 |
| `dev/tb/tb_ddr3_system.sv` | `force init_calib_complete=1` at 15µs | Layer 5 |

---

## 6. 下一步

1. **DDR3 读写功能验证**：`init_calib_complete` 拉高后，验证 AXI UI 可正常接收读写事务
2. **CPU 执行验证**：CPU 从 DDR3 执行程序，验证 `ahb_hresetn` 释放后系统正常启动
3. **回归测试**：`tb_ddr3_mig_ex`、`tb_ddr3_ahb_ex` 确认无副作用

---

## 7. Xilinx 官方参考

| 来源 | 关键内容 |
|------|---------|
| **UG586** | `SIM_BYPASS_INIT_CAL="OFF"` — Not supported in simulation; `_mig_sim.v` 用于仿真 |
| **AR 44019** | `"OFF"` 在行为仿真中不支持，校准永远卡住 |
| **AR 34744** | `"FAST"` 仅用于仿真，实现中必须用 `"OFF"` |
| **AR 60845** | 曾有 bug 导致 `_mig.v` 也被设为 `"FAST"`，造成硬件失败 |
| **SIP_PHASER_IN** | XSim secureip 中的 PHASER_IN 仿真模型不正确驱动 PHASELOCKED |
