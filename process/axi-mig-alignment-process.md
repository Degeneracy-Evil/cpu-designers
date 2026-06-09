# AXI 总线迁移 + chiplab 架构对齐 进度

> **日期**: 2026-06-09 | **关联计划**: `plan/axi-mig-alignment-plan.md`
> **目标 FPGA**: xc7a200t-fbg676-2
> **状态**: Phase 5 完成，Phase 6/7 待开始

---

## Phase 进度总览

| Phase | 描述 | 状态 | 备注 |
|-------|------|------|------|
| 0 | 清理与准备 | ✅ 完成 | soc_config.vh, axi4_def.svh, 归档 AHB, 删除 DDR3 workaround |
| 1 | CPU AXI4 接口改造 | ✅ 完成 | cpu_bus_bridge.sv 16-state FSM, core_top.sv AXI4 ports |
| 2 | AXI4 互联 + 从设备适配 | ✅ 完成 | 手动地址解码器 + 6个 AXI4-Lite 适配器 + system_top.sv 重写 |
| 3 | MIG + DDR3 集成 | ✅ 完成 | Axi_CDC.v 复制 + axi_wrap_ddr.sv + axi_wrap_ram.sv |
| 4 | 时钟 + 复位架构 | ✅ 完成 | 3-branch generate + ddr_data_init + reset_sync |
| 5 | 仿真基础设施 | ✅ 完成 | tb_soc_includes.svh + 54 TB 重写 + orchestrator 适配 |
| 6 | 延迟展宽 | ⏳ 待开始 | 可选，初期跳过 |
| 7 | FPGA 上板 | ⏳ 待开始 | 约束 + 综合 + 上板 |

---

## Phase 0: 清理与准备

### 0.1 创建 soc_config.vh
- [x] 创建 `dev/rtl/soc_config.vh` (SIMU_USE_PLL=0, SIMU_USE_DDR=0)

### 0.2 创建 axi4_def.svh
- [x] 创建 `dev/rtl/axi4_def.svh` (AXI4 常量定义)

### 0.3 归档 AHB-Lite 文件
- [x] 创建 `dev/rtl/_archived/ahb/` 目录
- [x] 归档: ahb_lite_bus.sv, ahb_mux.sv, ahb_decoder.sv, ahb_def.svh
- [x] 删除: ddr3_bridge_wrapper.sv
- [x] 删除: DDR3 workaround testbenches

### 0.4 确认 vivado_config.yaml
- [x] 确认 device_part = xc7a200tfbg676-2

---

## Phase 1: CPU AXI4 接口改造

### 1.1 重写 cpu_bus_bridge.sv
- [x] 替换 AHB-Lite 端口为 AXI4 master 5 通道
- [x] FSM 改造: HTRANS→awvalid/arvalid, HREADY→per-channel ready
- [x] Burst 映射: INCR8→awlen=7, SINGLE→awlen=0
- [x] WLAST/RLAST 生成
- [x] AWID/ARID=4'b0000, AWQOS/ARQOS=0, AWREGION/ARREGION=0
- [x] VALID 不依赖 READY (无组合环路)

### 1.2 修改 core_top.sv
- [x] 移除 AHB-Lite 端口
- [x] 添加 AXI4 master 端口
- [x] 更新 cpu_bus_bridge 例化

### 1.3 验证
- [x] LSP diagnostics clean
- [ ] 编译通过 (SRAM 模式)

---

## Phase 2: AXI4 互联 + 从设备适配

### 2.1 创建 AXI4 Crossbar IP 配置
- [ ] 配置 axi_crossbar_2x5 (2 SI × 5 MI) — 待 Phase 7 FPGA 时添加 Xilinx IP
- [x] 地址映射设置 (手动地址解码器已实现)

### 2.2 从设备 AXI4-Lite 适配
- [x] axi4lite_plic.sv (从 ahb_plic.sv 适配)
- [x] axi4lite_clint.sv (从 ahb_clint.sv 适配)
- [x] axi4lite_bootrom.sv (从 ahb_bootrom_slave.sv 适配)
- [x] axi4lite_to_apb.sv (从 ahb_lite_to_apb.sv 适配)
- [x] axi4lite_default_slave.sv (从 ahb_default_slave.sv 适配)
- [x] axi4lite_sys_status.sv (从 ahb_sys_status.sv 适配)

### 2.3 重写 system_top.sv 互联
- [x] 手动地址解码器 + 从设备 mux (替代 Xilinx IP crossbar)
- [x] Axi_CDC 例化 (cpu_clk → sys_clk)
- [x] CPU AXI4 master → CDC → 地址解码器 → 各从设备
- [x] 移除 ahb_lite_bus 例化

### 2.4 验证
- [x] LSP diagnostics clean
- [ ] SRAM 仿真编译通过

---

## Phase 3: MIG + DDR3 集成

### 3.1 复制 Axi_CDC
- [x] 从 chiplab 复制 Axi_CDC.v 到 dev/rtl/AMBA/

### 3.2 创建 axi_wrap_ddr.sv
- [x] 模块端口 (与 chiplab 一致)
- [x] Axi_CDC 例化 (sys_clk → ui_clk)
- [x] MIG 例化 (参照 chiplab axi_wrap_ddr.v)
- [x] ddr_aresetn 逻辑
- [x] 地址重映射 (0x8000_xxxx 直通)

### 3.3 创建 axi_wrap_ram.sv
- [x] AXI4 行为级 BRAM 模型
- [x] 支持 INCR burst

### 3.4 验证
- [x] LSP diagnostics clean
- [ ] DDR3 仿真 MIG 校准完成

---

## Phase 4: 时钟 + 复位架构

### 4.1 时钟 generate 三分支
- [x] sim_clk 分支 (SIMU_USE_PLL=0)
- [x] sim_pll_clk 分支 (SIMU_USE_PLL=1)
- [x] fpga_pll 分支
- [x] ddr_data_init 门控

### 4.2 DDR/SRAM 条件编译
- [x] generate if (SIMU_USE_DDR==0) → axi_wrap_ram
- [x] else → axi_wrap_ddr

### 4.3 rst_sync 模块
- [x] 创建/确认 rst_sync (异步复位同步释放)

### 4.4 验证
- [ ] SRAM 仿真: 时钟/复位正确
- [ ] DDR3 仿真: init_calib_complete 正常拉高

---

## Phase 5: 仿真基础设施

### 5.1 创建 tb_soc_includes.svh (共享 TB 基础设施)
- [x] 创建 `dev/tb/tb_soc_includes.svh` — system_top 例化、时钟、复位、debug 信号、check_reg/check_mem_word/read_reg tasks
- [x] 54 个标准 TB 重写: core_top + ahb_lite_bus → `include "tb_soc_includes.svh"`
- [x] tb_ahb_bus.sv 重写: AHB-Lite BFM → AXI4-Lite BFM (force CPU AXI4 master wires)
- [x] tb_apb_perips.sv 重写: AHB-Lite BFM → AXI4-Lite BFM (same pattern)
- [x] tb_simple_cpu_top.sv 重写: system_top 例化 + check_reg/check_mem_word

### 5.2 Vivado Orchestrator 适配
- [x] operations.py: 移除 ahb_bridge IP 引用，MIG IP 名 bd_soc_mig_7series_0_1 → mig_axi_32 (config-driven)
- [x] vivado_config.yaml: 移除 ahb_bridge section，ddr3.ip_name → mig_axi_32
- [x] config.py: 移除 AhbBridgeConfig class，更新 Ddr3Config 默认 ip_name
- [x] ip_gen.py: 移除 generate_bridge_create_ip_tcl
- [x] cache_header_gen.py: 移除 BRIDGE_IP_NAME defines
- [x] Python 语法验证通过 (py_compile × 4 files)

### 5.3 验证
- [ ] SRAM 仿真: ISA 测试通过 (待 Vivado 编译验证)
- [ ] DDR3 仿真: 全系统启动 → PASS (待 Phase 7)

---

## Phase 6: 延迟展宽 (可选)

- [ ] 移植 R/B 通道延迟展宽
- [ ] ram_random_mask 接 CONFREG
- [ ] func 测试随机延迟
- [ ] perf 测试固定延迟

---

## Phase 7: FPGA 上板

### 7.1 约束文件
- [ ] DDR3 引脚 (参照 chiplab soc_lite.xdc)
- [ ] 时钟约束 + 异步时钟组

### 7.2 IP 配置
- [ ] clk_pll, clk_pll_ddr, axi_crossbar, jtag_axi, mig_axi_32

### 7.3 综合/实现
- [ ] Synth: Flow_PerfOptimized_high
- [ ] Impl: Performance_Explore
- [ ] WNS ≥ 0

### 7.4 上板验证
- [ ] DDR3 自检 LED 亮
- [ ] 程序加载执行正确
