# nontrivial-mips vs ddr3_system — DDR3/MIG 架构对比分析

**日期**: 2026-06-07  
**目的**: 对比两个项目的时钟/DDR3/MIG 架构，确认 `init_calib_complete` 仿真失败的根因是否一致

---

## 1. 核心结论

**两个项目的 MIG 仿真参数根因完全一致**：MIG wrapper 均实例化 `_mig.v`（硬件模型），而非 `_mig_sim.v`（仿真模型），导致 `SIM_BYPASS_INIT_CAL="OFF"` 和 `SIMULATION="FALSE"`，行为仿真中校准永远无法完成。

---

## 2. MIG 参数对比

### 2.1 Wrapper 实例化选择

| 属性 | nontrivial-mips | ddr3_system |
|------|----------------|-------------|
| **Wrapper 文件** | `bd_soc_mig_7series_0_1.v` | `bd_soc_mig_7series_0_1.v` |
| **实例化的模块** | `bd_soc_mig_7series_0_1_mig` (**_mig**) | `bd_soc_mig_7series_0_1_mig` (**_mig**) |
| **_mig_sim.v 存在？** | ✅ 存在但未使用 | ✅ 存在但未使用 |

两个项目的 wrapper 代码完全相同：
```verilog
bd_soc_mig_7series_0_1_mig u_bd_soc_mig_7series_0_1_mig (  // ← 硬件模型
```

### 2.2 关键仿真参数

| 参数 | `_mig.v` (当前使用) | `_mig_sim.v` (未使用) |
|------|--------------------|--------------------|
| `SIM_BYPASS_INIT_CAL` | **"OFF"** | **"FAST"** |
| `SIMULATION` | **"FALSE"** | **"TRUE"** |
| `CLKOUT4_PHASE` (infrastructure) | 168.75° (硬件值) | 22.5° (仿真优化) |

**两个项目的 `_mig.v` 和 `_mig_sim.v` 参数值完全一致。**

### 2.3 参数影响机制

- `SIM_BYPASS_INIT_CAL = "OFF"` → MIG 执行完整校准序列（IODELAY 校准、读写均衡、相位锁定）。行为仿真中 IODELAY 无真实延迟，校准 FSM 卡死。
- `SIMULATION = "FALSE"` → infrastructure 使用 `CLKOUT4_PHASE = 168.75°`（硬件值），仿真中 MMCM 相位行为不可预测。
- `SIM_BYPASS_INIT_CAL = "FAST"` → 跳过耗时校准，只做初始化 + 简化校准，~107ns 完成。

---

## 3. 时钟架构对比

### 3.1 nontrivial-mips

```
外部 clk (AC19, 100MHz, LVCMOS33)
  │
  └─→ bd_soc_clk_wiz_0_0 (MMCM, VCO=1000MHz)
        ├─→ clk_cpu        (80MHz)   → CPU
        ├─→ clk_ddr_ref    (200MHz)  → MIG.clk_ref_i
        ├─→ clk_vga        (25MHz)   → VGA
        ├─→ clk_spi        (20MHz)   → SPI Flash
        └─→ clk_peripheral (100MHz)  → MIG.sys_clk_i + 外设
```

**特点**：
- 使用 Vivado Block Design (`bd_soc`) 管理整个时钟和 MIG 连接
- BD 内包含 `bd_soc_clk_wiz_0_0` IP (MMCM)，从 100MHz 生成 5 路时钟
- **MIG.sys_clk_i** 来自 clk_wiz 的 100MHz 输出 (clk_peripheral)
- **MIG.clk_ref_i** 来自 clk_wiz 的 200MHz 输出 (clk_ddr_ref)
- BD wrapper 是 Vivado 自动生成的，不在 git 仓库中
- 无独立的 `sim_1` 源集 — 没有自定义 testbench
- 仅使用 MIG 自带的 `example_design/sim/sim_tb_top.v` 做仿真

### 3.2 ddr3_system

```
外部 ext_clk (AC19, 100MHz, LVCMOS33)
  │
  └─→ clk_wiz_0 (MMCME2_ADV)
        ├─→ clk_system  (100MHz) ──→ MIG.sys_clk_i
        ├─→ clk_ddr_ref (200MHz) ──→ MIG.clk_ref_i
        └─→ clk_wiz_locked
```

**特点**：
- 使用独立的 `clk_wiz_0` IP (MMCME2_ADV) 生成 MIG 所需时钟
- `clk_wiz_0` 使用真实 MMCME2_ADV 原语，行为仿真中锁定时间可能很长
- 有自定义 testbench (`tb_ddr3_system.sv`)，包含 `DDR3_BYPASS_CLK_WIZ` 诊断选项
- MIG 层级：`system_top → u_ahb_lite_bus → u_ddr3_bridge_wrapper → u_mig → u_bd_soc_mig_7series_0_1_mig`

### 3.3 关键差异

| 方面 | nontrivial-mips | ddr3_system |
|------|----------------|-------------|
| **时钟管理** | BD 内 clk_wiz_0_0 (5路输出) | 独立 clk_wiz_0 (2路输出) |
| **MMCM 风险** | BD 内 clk_wiz + MIG 内 PLLE2+MMCM | clk_wiz_0 MMCM + MIG 内 PLLE2+MMCM |
| **时钟链深度** | ext→IBUF→MMCM→BUFG→PLLE2→MMCM→BUFG (4级) | ext→IBUF→MMCM→BUFG→PLLE2→MMCM→BUFG (4级) |
| **仿真支持** | 仅 MIG example testbench | 自定义 testbench + 诊断选项 |
| **时钟绕过选项** | 无 | `DDR3_BYPASS_CLK_WIZ` 宏 |
| **外部时钟引脚** | AC19 (100MHz) | AC19 (100MHz) — **相同** |
| **clk_wiz 输出** | 80/200/25/20/100MHz | 100/200MHz |
| **ui_clk_sync_rst** | MIG example 中使用 | **未连接** (ddr3_bridge_wrapper.sv:140) |

---

## 4. XDC 约束对比

### 4.1 共同点

- **FPGA**: Artix-7 A200T FBG676 (同一块板)
- **外部时钟**: Pin AC19, 100MHz, LVCMOS33
- **复位**: Pin Y3, LVCMOS33
- **DDR3 引脚**: 均由 MIG IP 的 XDC 自动生成（不在顶层 XDC 中）
- **配置**: CFGBVS=VCCO, CONFIG_VOLTAGE=3.3

### 4.2 差异

| 方面 | nontrivial-mips | ddr3_system |
|------|----------------|-------------|
| **时钟约束** | `CLOCK_DEDICATED_ROUTE BACKBONE` | `create_clock -period 10.000` |
| **DDR3 IOSTANDARD** | 仅在 MIG IP XDC 中 | cpu.xdc 中显式声明 SSTL15/DIFF_SSTL15 |
| **外设引脚** | 完整 (UART/SPI/NAND/VGA/PS2/Ethernet/LCD/USB/EJTAG) | 精简 (UART/SPI/LCD/GPIO) |
| **io_timings.xdc** | 有（额外时序约束） | 无 |

---

## 5. 复位/初始化序列对比

### 5.1 nontrivial-mips

- 复位由 BD 内部管理，具体逻辑在自动生成的 BD wrapper 中
- MIG 的 `sys_rst` 和 `aresetn` 由 BD 的处理器系统复位 (PRS) IP 驱动
- `init_calib_complete` 连接到 BD 内部，用于解锁 AXI 互联

### 5.2 ddr3_system

- `aresetn` 由 `clk_wiz_locked` 门控：MMCM 未锁定时 MIG 保持复位
- `init_calib_complete` 用于解锁 DDR3 bridge wrapper 的命令通道
- 复位链：`ext_rst_n → clk_wiz_0 (等待锁定) → MIG.aresetn → init_calib_complete → bridge 解锁`

### 5.3 仿真影响

- **ddr3_system 的复位链更脆弱**：如果 `clk_wiz_0` 的 MMCM 在仿真中不锁定，`aresetn` 永远不释放，校准无法开始
- **nontrivial-mips 的复位链由 BD 管理**：BD 内部可能使用 MIG 自己的 MMCM 锁定信号，减少了外部依赖

### 5.4 ddr3_system 特有架构隐患

1. **双重 MMCM 链**：`clk_wiz_0` MMCM (VCO=1000MHz) → MIG 内 PLLE2_ADV (VCO=800MHz) → MIG 内 MMCME2_ADV → 4 级时钟修改原语串联，每级增加抖动和相位不确定性
2. **ui_clk_sync_rst 未连接**：MIG 的同步复位输出在 `ddr3_bridge_wrapper.sv:140` 悬空，系统使用自定义复位逻辑
3. **CPU 复位未由 calib 门控**：CPU 直接使用 `reset`（来自 ext resetn），不受 `init_calib_complete` 门控。CPU 可能在校准完成前尝试 DDR3 访问
4. **clk_wiz_locked 未参与复位门控**：`mig_aresetn` 和 `ahb_hresetn` 仅检查 `mig_init_calib_complete && mig_mmcm_locked`，不检查 `clk_wiz_locked`
5. **MIG XDC 时钟约束被注释**：`sys_clk_i` 和 `clk_ref_i` 的 period 约束是 `#create_clock`（注释掉），时序依赖 clk_wiz_0 的 XDC 传播

---

## 5.5 MIG IP 配置对比（完全一致）

| 参数 | nontrivial-mips | ddr3_system |
|------|----------------|-------------|
| **FPGA** | XC7A200T-FBG676, -2 | XC7A200T-FBG676, -2 |
| **Memory** | MT41J64M16XX-125G | MT41J64M16XX-125G |
| **DDR 频率** | 400 MHz (tCK=2500ps) | 400 MHz (tCK=2500ps) |
| **数据宽度** | 16-bit | 16-bit |
| **nCK_PER_CLK** | 4 (quarter-rate) | 4 (quarter-rate) |
| **SYSCLK_TYPE** | NO_BUFFER | NO_BUFFER |
| **REFCLK_TYPE** | NO_BUFFER | NO_BUFFER |
| **RST_ACT_LOW** | 1 | 1 |
| **REFCLK_FREQ** | 200.0 | 200.0 |
| **CLKFBOUT_MULT** | 8 (PLL VCO=800MHz) | 8 (PLL VCO=800MHz) |
| **MMCM_VCO** | 800 | 800 |
| **UI_EXTRA_CLOCKS** | FALSE | FALSE |

**结论**：两个项目的 MIG IP 配置参数完全一致，根因和修复方案可以通用。

---

## 5.6 仿真特定要求对比

| 要求 | nontrivial-mips (example testbench) | ddr3_system (自定义 testbench) |
|------|-------------------------------------|-------------------------------|
| **glbl.v 包含** | ✅ (从 $XILINX_VIVADO/data/verilog/src/glbl.v) | ❓ 需确认 |
| **+notimingchecks** | ✅ (sim.do 中 vsim 参数) | ❓ 需确认 |
| **ddr3_model 定义** | ✅ `-d x1Gb -d sg125 -d x16` | ❓ 需确认 |
| **SIMULATION="TRUE" 传递** | ✅ (testbench 通过参数端口) | ❌ (仅本地参数，未传递) |
| **SIM_BYPASS_INIT_CAL="FAST"** | ✅ (testbench 通过参数端口) | ❌ (仅本地参数，未传递) |
| **TEMP_MON_EN** | "OFF" (SIMULATION="TRUE" 时自动) | "ON" (SIMULATION="FALSE" 时自动) |

**重要**：`glbl.v` 是 Xilinx 仿真必需模块（提供 GSR 等全局信号），缺失可能导致仿真异常。`+notimingchecks` 对 MIG 仿真也很关键。

---

## 6. 仿真现状对比

| 方面 | nontrivial-mips | ddr3_system |
|------|----------------|-------------|
| **自定义 testbench** | ❌ 无 | ✅ `tb_ddr3_system.sv` |
| **MIG example testbench** | ✅ `sim_tb_top.v` | ✅ 存在但未使用 |
| **MIG example 使用 _mig_sim** | ✅ example 的 xsim_files.prj 使用 `_mig_sim.v` | ✅ 参考项目 (`_ex`) 使用 `_mig_sim.v` |
| **主设计使用 _mig_sim** | ❌ 使用 `_mig.v` | ❌ 使用 `_mig.v` |
| **init_calib_complete 结果** | 仿真中不拉高（推断） | 仿真中不拉高（已确认） |

**关键发现**：MIG 自带的 example_design 仿真正确使用了 `_mig_sim.v`，但主设计均未使用。这是 Xilinx MIG IP 的通用问题 — Vivado 生成的 user_design 默认使用硬件模型。

---

## 7. 修复方案对比

### 7.1 通用修复（两个项目均适用）

#### 方案 A（推荐）：testbench 中 defparam 覆盖

**nontrivial-mips** — 需要先创建自定义 testbench：
```systemverilog
// 需要确定 BD wrapper 的 MIG 层级路径
// 推测: bd_soc_inst → bd_soc_mig_7series_0_1_0 → u_bd_soc_mig_7series_0_1_mig
initial begin
    defparam <hier_path>.u_bd_soc_mig_7series_0_1_mig.SIM_BYPASS_INIT_CAL = "FAST";
    defparam <hier_path>.u_bd_soc_mig_7series_0_1_mig.SIMULATION = "TRUE";
end
```

**ddr3_system** — 层级路径已确认：
```systemverilog
initial begin
    defparam u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig
            .u_bd_soc_mig_7series_0_1_mig.SIM_BYPASS_INIT_CAL = "FAST";
    defparam u_dut.u_ahb_lite_bus.u_ddr3_bridge_wrapper.u_mig
            .u_bd_soc_mig_7series_0_1_mig.SIMULATION = "TRUE";
end
```

#### 方案 B：MIG wrapper 条件编译

两个项目的 `bd_soc_mig_7series_0_1.v` 修改方式完全相同：
```verilog
`ifdef SIMULATION_MIG
  bd_soc_mig_7series_0_1_mig_sim u_bd_soc_mig_7series_0_1_mig (
`else
  bd_soc_mig_7series_0_1_mig u_bd_soc_mig_7series_0_1_mig (
`endif
```

### 7.2 ddr3_system 特有修复

#### 方案 C：绕过 clk_wiz_0

仅 ddr3_system 需要（nontrivial-mips 的 BD 内部处理时钟）：
```tcl
vlog +define+DDR3_BYPASS_CLK_WIZ ...
```

---

## 8. 推荐实施顺序

### ddr3_system（当前项目）
1. ✅ 已有完整分析 (`init_calib_complete_analysis.md`)
2. **实施方案 A**（defparam 覆盖）— 层级路径已确认
3. 如仍不拉高，**加上方案 C**（绕过 clk_wiz_0）
4. 长期迁移到**方案 B**（条件编译）

### nontrivial-mips（参考项目）
1. **确认 MIG 层级路径**（需要生成 BD wrapper 或从 Vivado 中查看）
2. **创建自定义 testbench**（当前无 sim_1 源集）
3. **实施方案 A 或 B**（与 ddr3_system 相同的修复逻辑）
4. 无需方案 C（BD 内部管理时钟）

---

## 9. 附录：关键文件路径

### nontrivial-mips

| 文件 | 路径 |
|------|------|
| MIG wrapper | `NonTrivialMIPS.srcs/sources_1/bd/bd_soc/ip/bd_soc_mig_7series_0_1/.../user_design/rtl/bd_soc_mig_7series_0_1.v` |
| MIG 硬件模型 | `.../bd_soc_mig_7series_0_1_mig.v` (SIM_BYPASS="OFF", SIMULATION="FALSE") |
| MIG 仿真模型 | `.../bd_soc_mig_7series_0_1_mig_sim.v` (SIM_BYPASS="FAST", SIMULATION="TRUE") |
| MIG example testbench | `.../example_design/sim/sim_tb_top.v` |
| MIG example top | `.../example_design/rtl/example_top.v` |
| XDC (FPGA pins) | `NonTrivialMIPS.srcs/constrs_1/new/fpga_pins.xdc` |
| XDC (IO timings) | `NonTrivialMIPS.srcs/constrs_1/new/io_timings.xdc` |

### ddr3_system

| 文件 | 路径 |
|------|------|
| Testbench | `simplecpu_soc.srcs/sim_1/imports/tb/tb_ddr3_system.sv` |
| MIG wrapper | `simplecpu_soc.srcs/sources_1/ip/bd_soc_mig_7series_0_1/.../user_design/rtl/bd_soc_mig_7series_0_1.v` |
| MIG 硬件模型 | `.../bd_soc_mig_7series_0_1_mig.v` (SIM_BYPASS="OFF", SIMULATION="FALSE") |
| MIG 仿真模型 | `.../bd_soc_mig_7series_0_1_mig_sim.v` (SIM_BYPASS="FAST", SIMULATION="TRUE") |
| clk_wiz_0 | `simplecpu_soc.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0/clk_wiz_0_clk_wiz.v` |
| system_top | `simplecpu_soc.srcs/sources_1/imports/rtl/system_top.sv` |
| XDC | `simplecpu_soc.srcs/constrs_1/imports/fpga/cpu.xdc` |
| 根因分析 | `init_calib_complete_analysis.md` |
