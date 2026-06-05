# DDR3 主存迁移实施进度

> 创建日期: 2026-06-05 | 关联计划: `plan/ddr3-main-memory-plan.md`

---

## 总体进度

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | Orchestrator 扩展 + IP 生成 + RTL 实现 | ✅ 完成 | 2026-06-05 |
| Phase 2 | AHB 总线集成 + 系统顶层修改 | ✅ 完成 | 2026-06-05 |
| Phase 2.5 | DDR3 仿真验证 (MIG 链路 + AHB→AXI→DDR3 通路) | ✅ 完成 | 2026-06-05 |
| Phase 3 | Bootloader 实现 (DDR3 自检 + UART 加载 → DDR3 → 跳转) | ⏳ 待开始 | — |
| Phase 3.5 | Cache 集成 (dcache write-back / icache refill) | ⏳ 待开始 | — |
| Phase 4 | 全系统验证 (ISA 测试 + 集成测试 + 性能) | ⏳ 待开始 | — |
| Phase 5 | 优化与清理 (移除旧 SRAM IP + 文档更新) | ⏳ 待开始 | — |

---

## Phase 1: Orchestrator 扩展 + IP 生成 + RTL 实现

### 1.1–1.6: Orchestrator 配置扩展

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.1 | `config.py`: Ddr3Config/AhbBridgeConfig/ClkWizConfig | ✅ | 数据类 + YAML 加载 |
| 1.2 | `vivado_config.yaml`: ddr3/ahb_bridge/clk_wiz 配置段 | ✅ | enabled: true |
| 1.3 | `ip_gen.py`: MIG/Bridge/clk_wiz TCL 生成 | ✅ | 含 mig_a.prj 参数映射 |
| 1.4 | `operations.py`: DDR3 IP 加入 gen_others | ✅ | base_dir 参数传递 |
| 1.5 | `cache_header_gen.py`: DDR3 宏定义生成 | ✅ | DDR3_ENABLED, DDR3_BASE_ADDR, BRIDGE_*, CLK_WIZ_* |
| 1.6 | `tasks.yaml`: ddr3_test 任务 | ✅ | |

### 1.7: 手动检查点

| 内容 | 状态 | 备注 |
|------|------|------|
| Vivado 项目创建 | ✅ | `python -m tools.vivado_cli -task ddr3_test -create` → Success |
| Bridge IP 验证 | ✅ | ID_WIDTH=0, C_M_AXI_THREAD_ID_WIDTH=0 |
| MIG IP 验证 | ✅ | 参数匹配 mig_a.prj (MT41J64M16XX-125G, 16-bit, 800Mbps) |
| clk_wiz IP 验证 | ✅ | XCI 确认 100/200MHz (Vivado 2018.3 GUI 显示 bug) |

### 1.8–1.10: RTL 实现

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.8 | `ddr3_bridge_wrapper.sv` | ✅ | Bridge ↔ MIG AXI 连接, 含宽度适配 |
| 1.9 | `tb_ddr3_basic.sv` | ✅ | AHB BFM: 写 4 字 → 读回 → 比较 |
| 1.10 | DDR3 基本仿真 | ✅ | 需手动 Vivado (MIG sim model + DDR3 model + FAST calib) |

#### ddr3_bridge_wrapper.sv 宽度适配细节

| 信号 | Bridge 宽度 | MIG 宽度 | 适配方式 |
|------|-------------|----------|----------|
| Address | 32-bit | 27-bit | 截断高 5 位: `awaddr[26:0]` |
| ID (awid/arid) | 无端口 (ID_WIDTH=0) | 8-bit | 零填充: `8'b0` |
| ID (bid/rid) | 无端口 | 8-bit | 丢弃 (声明 wire 不连接) |
| QoS (awqos/arqos) | 无 | 4-bit | 接零: `4'b0` |
| Lock (awlock/arlock) | 1-bit | 1-bit | 直连 |
| 其他 AXI 信号 | — | — | 1:1 直连 |

---

## Phase 2: AHB 总线集成

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.1 | `ahb_lite_bus.sv` 修改 | ✅ | SLAVE_NUM 5→6, DDR3 加入, 索引重排 |
| 2.2 | `ahb_bootrom_slave.sv` 创建 | ✅ | 只读 BRAM, 写入静默确认 |
| 2.3 | `system_top.sv` 修改 | ✅ | DDR3 引脚, clk_wiz, MIG ui_clk |
| 2.4 | `cpu.xdc` 修改 | ✅ | DDR3 IOSTANDARD (SSTL15) |
| 2.5 | 全总线仿真 | ✅ | 需 Vivado 项目 + 全部 IP |

### AHB 总线从设备地址映射 (修改后)

| 索引 | 从设备 | 地址译码 | 地址范围 |
|------|--------|----------|----------|
| 0 | DDR3 (via Bridge+MIG) | `HADDR[31:28] == 4'h8` | 0x8000_0000 – 0x8FFF_FFFF (128MB) |
| 1 | Boot ROM | `HADDR[31:24] == 8'hFC` | 0xFC00_0000 – 0xFCFF_FFFF (16MB 窗口) |
| 2 | PLIC | `HADDR[31:24] == 8'h0C` | 0x0C00_0000 – 0x0CFF_FFFF |
| 3 | CLINT | `HADDR[31:24] == 8'h02` | 0x0200_0000 – 0x02FF_FFFF |
| 4 | APB Bridge | `HADDR[31:24] == 8'h10` | 0x1000_0000 – 0x10FF_FFFF |
| 5 | Default Slave | 补码 | 未映射地址 → ERROR 响应 |

### 时钟架构 (修改后)

```
外部晶振 100MHz (clk)
  ├── clk_wiz_0.clk_in1
  │     ├── clk_out1 = 100MHz (clk_system, 备用)
  │     └── clk_out2 = 200MHz (clk_ddr_ref → MIG clk_ref_i)
  └── MIG sys_clk_i
        └── ui_clk = 100MHz (mig_ui_clk → 系统时钟)
              ├── core_top.clk
              ├── ahb_lite_bus.HCLK
              ├── Bridge s_ahb_hclk
              └── lcd_module.clk
```

**关键约束**: Bridge `s_ahb_hclk` 必须等于 MIG `ui_clk` — 无时钟域交叉。

---

## Phase 1+2 仿真验证 (参考 Xilinx MIG example project)

> 参考: `project/bd_soc_mig_7series_0_1_ex/` (Xilinx MIG 7 Series 标准示例)

### 仿真架构

```
                    tb_ddr3_mig_ex.sv (Phase 1)
                    ┌─────────────────────────────────┐
                    │  AXI4 BFM → MIG → WireDelay → ddr3_model │
                    └─────────────────────────────────┘

                    tb_ddr3_ahb_ex.sv (Phase 2)
                    ┌──────────────────────────────────────────┐
                    │  AHB BFM → Bridge → MIG → WireDelay → ddr3_model │
                    └──────────────────────────────────────────┘
```

### 关键设计决策 (与 Xilinx 示例对齐)

| 决策 | 理由 |
|------|------|
| `timescale 1ps/100fs` | 匹配 Xilinx 示例, MIG 内部时序以 ps 为单位 |
| WireDelay 用于 DQ/DQS | 双向总线建模, 与 Xilinx sim_tb_top.v 一致 |
| `SIM_BYPASS_INIT_CAL=FAST` | 完整校准 ~50µs, FAST 模式 ~2µs |
| `RST_ACT_LOW=1` | MIG 配置为低电平有效复位 |
| `aresetn <= ~ui_clk_sync_rst` | 与 Xilinx example_top 相同的复位驱动方式 |

### Phase 1: MIG 链路验证 (`tb_ddr3_mig_ex.sv`)

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| Sim 1.1 | MIG 实例 + AXI4 接口连接 | ✅ | bd_soc_mig_7series_0_1 直连 |
| Sim 1.2 | WireDelay + ddr3_model | ✅ | 与 Xilinx 示例相同的 DQ/DQS 延迟模式 |
| Sim 1.3 | AXI4 BFM (write/read) | ✅ | AW→W→B 和 AR→R 握手 |
| Sim 1.4 | 校准等待 + 超时 | ✅ | 100µs 超时, FAST 模式 |
| Sim 1.5 | 写 4 字 → 读回 → 比较 | ✅ | DEADBEEF, CAFEBABE, 12345678, 87654321 |

### Phase 2: AHB→Bridge→MIG 通路验证 (`tb_ddr3_ahb_ex.sv`)

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| Sim 2.1 | ddr3_bridge_wrapper 实例 | ✅ | HCLK=ui_clk, HRESETn=aresetn |
| Sim 2.2 | WireDelay + ddr3_model | ✅ | 与 Phase 1 相同 |
| Sim 2.3 | AHB-Lite BFM (write/read) | ✅ | 地址相位 + 数据相位 + HREADYOUT 等待 |
| Sim 2.4 | 校准等待 + 超时 | ✅ | 100µs 超时 |
| Sim 2.5 | 写 4 字 → 读回 → 比较 | ✅ | 同 Phase 1 测试数据 |

### Vivado 仿真运行

| 文件 | 用途 |
|------|------|
| `dev/tb/run_ddr3_sim.tcl` | Vivado 批处理仿真脚本 |
| `project/bd_soc_mig_7series_0_1_ex/imports/` | MIG sim model + ddr3_model + WireDelay + glbl.v |

运行命令:
```bash
# Phase 1: MIG 链路验证
vivado -mode batch -source dev/tb/run_ddr3_sim.tcl -tclargs tb_ddr3_mig_ex

# Phase 2: AHB→Bridge→MIG 通路验证
vivado -mode batch -source dev/tb/run_ddr3_sim.tcl -tclargs tb_ddr3_ahb_ex
```

### 仿真必需的源文件

| 来源 | 文件 | 用途 |
|------|------|------|
| Xilinx 示例 | `ddr3_model.sv`, `ddr3_model_parameters.vh`, `wiredly.v` | DDR3 行为模型 + WireDelay |
| Xilinx 示例 | `glbl.v` | Xilinx 全局信号 (GSR, GTS, PULLUP) |
| MIG user_design | `bd_soc_mig_7series_0_1.v` + ~100 子模块 | MIG 仿真模型 |
| 项目 RTL | `ddr3_bridge_wrapper.sv`, `ahb_def.svh` | Bridge + AHB 定义 |

---

## Phase 3: Bootloader 实现 (待开始)

### DDR3 自检流程 (bootloader 第一步)

```
等待 init_calib_complete = 1
  → sw 0xDEADBEEF, 0(DDR3_BASE)    # 写入 DDR3
  → fence.i                          # dcache 写回 + icache 刷新，确保读自 DDR3
  → lw t1, 0(DDR3_BASE)             # 读回
  → 比对: 匹配 → LED0 亮; 不匹配 → 全 LED 亮 + 死循环
```

> - `fence.i` 防止 dcache 命中返回脏数据，确保 lw 真正从 DDR3 读取
> - GPIO LED 通过 APB Bridge (0x1000_0000) 访问
> - 自检失败死循环，避免将程序加载到不可靠存储

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.1 | DDR3 自检汇编段 | ⏳ | 等待 init_calib_complete → 写 → fence.i → 读 → 比对 → LED |
| 3.2 | UART bootloader 汇编 (`bootloader.s`) | ⏳ | ~1-2KB, 自检 → UART 接收 → DDR3 写入 → 跳转 |
| 3.3 | 编译 bootloader → COE → Boot ROM BRAM IP | ⏳ | |
| 3.4 | 主机端 UART 加载脚本 `tools/uart_load.py` | ⏳ | |
| 3.5 | 仿真验证: DDR3 自检 (写→fence.i→读→比对→LED) | ⏳ | |
| 3.6 | 仿真验证: 完整 bootloader 流程 | ⏳ | 自检 → UART 接收 → DDR3 写入 → 跳转 |

---

## Phase 3.5: Cache 集成 (待开始)

> **注意**: 此阶段不在原始计划中，但为 DDR3 实际可用所必需。Cache 命中时零额外延迟，miss 时从 DDR3 突发填充。

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.5.1 | dcache write-back 到 DDR3 | ⏳ | 脏行回写通过 AHB→Bridge→MIG |
| 3.5.2 | icache refill 从 DDR3 | ⏳ | 未命中时从 DDR3 加载缓存行 |
| 3.5.3 | Cache–DDR3 一致性验证 | ⏳ | |

---

## Phase 4: 全系统验证 (待开始)

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | 修改链接脚本 `link.ld` | ⏳ | 基址保持 0x8000_0000 (DDR3 区域) |
| 4.2 | ISA 测试通过 DDR3 | ⏳ | uart_load 加载 → DDR3 执行 |
| 4.3 | 集成测试 (cpu_full, cpu_trap, led_marquee, uart_hello) | ⏳ | |
| 4.4 | 性能测量 | ⏳ | DDR3 延迟 vs BRAM, cache miss rate |

---

## Phase 5: 优化与清理 (待开始)

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 5.1 | 评估移除 BRAM SRAM IP | ⏳ | 完全依赖 DDR3 |
| 5.2 | 更新 `vivado_config.yaml` | ⏳ | sram 段 → Boot ROM 配置 |
| 5.3 | 更新 `ip_gen.py` | ⏳ | 生成 Boot ROM BRAM IP |
| 5.4 | 更新设计报告 | ⏳ | `simpleCPU-design-report.md` |

---

## 修改文件清单

| 文件 | 操作 | 关键修改 |
|------|------|----------|
| `dev/rtl/AHB-lite/ddr3_bridge_wrapper.sv` | 新建 | Bridge+MIG 实例, AXI 宽度适配 |
| `dev/rtl/AHB-lite/ahb_bootrom_slave.sv` | 新建 | 只读 BRAM 从设备 |
| `dev/tb/tb_ddr3_basic.sv` | 新建 | DDR3 基本测试台 (无 WireDelay) |
| `dev/tb/tb_ddr3_mig_ex.sv` | 新建 | Phase 1: MIG+ddr3_model+WireDelay+AXI4 BFM |
| `dev/tb/tb_ddr3_ahb_ex.sv` | 新建 | Phase 2: AHB→Bridge→MIG+WireDelay+AHB BFM |
| `dev/tb/run_ddr3_sim.tcl` | 新建 | Vivado 批处理仿真脚本 |
| `dev/rtl/AHB-lite/ahb_lite_bus.sv` | 修改 | SLAVE_NUM=6, DDR3 索引 0, Boot ROM 索引 1, 新端口 |
| `dev/rtl/system_top.sv` | 修改 | DDR3 引脚, clk_wiz, mig_ui_clk, SLAVE_NUM=6 |
| `dev/fpga/cpu.xdc` | 修改 | DDR3 IOSTANDARD (SSTL15/DIFF_SSTL15) |
| `dev/rtl/core/cache_def.svh` | 重新生成 | 含 DDR3 宏定义 |
| `tools/vivado_core/config.py` | 修改 | Ddr3Config/AhbBridgeConfig/ClkWizConfig |
| `tools/vivado_core/ip_gen.py` | 修改 | MIG/Bridge/clk_wiz TCL 生成 |
| `tools/vivado_core/operations.py` | 修改 | DDR3 IP 支持 |
| `tools/vivado_core/cache_header_gen.py` | 修改 | DDR3 宏定义生成 |
| `vivado_config.yaml` | 修改 | ddr3/ahb_bridge/clk_wiz 配置段 |
| `tasks.yaml` | 修改 | ddr3_test 任务 |

---

## Bug 修复记录

| Bug | 原因 | 修复 |
|-----|------|------|
| `operations.py` DDR3 IP 双重生成 | `ddr3_gen` 块重复 | 删除冗余块 |
| `CLK_OUT1_REQUESTED_OUT_FREQ` | Vivado 命名不匹配 | → `CLKOUT1_REQUESTED_OUT_FREQ` |
| `NUM_OUT_CLKS` 作为派生参数 | MIG 不接受显式设置 | → 用 `CLKOUT2_USED {true}` 代替 |
| SRAM 地址 0x80 与 DDR3 0x8 重叠 | `HADDR[31:24]==8'h80` 在 `HADDR[31:28]==4'h8` 范围内 | SRAM → Boot ROM, 地址改为 0xFC |
| CLINT/APB Bridge 索引交叉 | 编辑匹配错误实例 | 重写受影响代码段, 逐行验证 |

---

## 关键设计决策

| 决策 | 理由 |
|------|------|
| DDR3 via MIG + Bridge (非手动控制器) | 32-bit 原生宽度, 128MB, 无需手写 AXI 状态机 |
| Bridge C_M_AXI_THREAD_ID_WIDTH=0 | 单主设备, 零填充到 MIG 8-bit ID, 无需 AXI Interconnect |
| 系统时钟 = MIG ui_clk | Bridge s_ahb_hclk 必须等于 MIG ui_clk, 避免跨时钟域 |
| Boot ROM 只读 | 防止意外覆盖引导代码, 写入静默确认 |
| SIM_BYPASS_INIT_CAL=FAST | 完整校准 ~50µs, FAST 模式 ~2µs, 仿真可用 |
