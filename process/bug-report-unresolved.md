# 未解决 Bug 汇总报告

> 生成日期: 2026-06-13
> 依据: `process/` 下全部 10 个文件的逐条审查
> 过滤规则: 排除已废弃 AHB-Lite 架构相关组件（ahb_lite_bus, ahb_mux, ahb_decoder, ahb_plic, ahb_clint, ahb_sram_slave, ahb_bootrom_slave, ahb_default_slave, ahb_sys_status, ddr3_bridge_wrapper, ahb_lite_to_apb, ahb_def.svh 均在 `_archived/ahb/`）

---

## 当前活跃架构确认

| 组件 | 状态 | 证据 |
|------|------|------|
| AHB-Lite 总线 (`ahb_lite_bus`, `ahb_mux`, `ahb_decoder`) | ❌ 已废弃 | 全部在 `_archived/ahb/` |
| AHB 从设备 (`ahb_plic`, `ahb_clint`, `ahb_bootrom_slave`, `ahb_sram_slave`, `ahb_default_slave`, `ahb_sys_status`) | ❌ 已废弃 | 全部在 `_archived/ahb/` |
| AHB-AXI Bridge (`ddr3_bridge_wrapper`) | ❌ 已废弃 | 仅在 `_archived/ahb/ahb_lite_bus.sv` 中引用 |
| AHB-to-APB 桥 (`ahb_lite_to_apb.sv`) | ❌ 死文件 | 存在于 `dev/rtl/APB/` 但无活跃模块实例化 |
| AHB 定义 (`ahb_def.svh`) | ❌ 已废弃 | 仅在 `_archived/` 中引用 |
| AXI4-Lite 从设备 (`axi4lite_plic/clint/bootrom/default/sys_status`) | ✅ 活跃 | `system_top.sv` 实例化 |
| AXI4-to-APB 桥 (`axi4lite_to_apb.sv`) | ✅ 活跃 | `system_top.sv` 实例化 |
| CPU 总线桥 (`cpu_bus_bridge.sv`) | ✅ AXI4 端口 | `awvalid/arvalid` 接口 |
| AXI CDC (`Axi_CDC.v`) | ✅ 活跃 | `system_top.sv` 实例化 |
| AXI RAM/DDR 包装 (`axi_wrap_ram.sv`, `axi_wrap_ddr.sv`) | ✅ 活跃 | `system_top.sv` 实例化 |

---

## 🔴 一、绕过未找根因（最危险）

| # | Bug | 文件 | 绕过方式 | 为何危险 |
|---|-----|------|---------|---------|
| 1 | **BUG-56: MIG 校准 FSM 卡死** | MIG 内部 `ddr_phy_init.v` | `force pi_phase_locked_all=1` + `force pi_dqs_found_all=1` | XSim SIP 模型不驱动 PHASELOCKED (AR#44019)。force 跳过校准部分状态 → DDR3 banks 未 precharge → model 报 refresh error。**硬件不存在此问题**，但仿真 DDR3 读通路初始化不完整 |
| 2 | **CPU 每条 lw/sw 触发两次 AXI4-Lite 事务** | `cpu_bus_bridge.sv` 或 AXI 互联 | UART RTL 添加 STATUS-read auto-arm 绕过 | **根因未查**。当前仅 UART 被 workaround，**PLIC claim 等有副作用寄存器仍受影响** |
| 3 | **XPM_FIFO_ASYNC xsim 仿真模型完全不工作** | `Axi_CDC.v`, Xilinx XPM | 仿真 `ifdef SIMULATION` 直连旁路 | **CDC 功能零仿真覆盖**，FPGA 上 CDC 正确性未验证 |

---

## 🟡 二、修复不彻底/回退

| # | Bug | 文件 | 遗留问题 |
|---|-----|------|---------|
| 4 | **Axi_CDC xpm_fifo_async 重写已回退** | `Axi_CDC.v` | 重写需单独验证后重新提交。当前仍用 SpinalHDL 原始实现 + 仿真旁路 |

---

## 🔴 三、HIGH 级未修复（当前架构相关）

| # | Bug | 描述 | 文件 | 备注 |
|---|-----|------|------|------|
| 5 | **BUG-1** | **PLIC Claim/Complete 握手完全失效** — 中断系统不可用 | `axi4lite_plic.sv` | 原 `ahb_plic.sv` 已废弃，但 AXI 版本是否有同一问题需确认。**PLIC claim 逻辑是协议核心，AXI 迁移时可能保留了同一时序缺陷** |
| 6 | **BUG-2** | FLW/FSW 非对齐异常未上报 — 静默数据损坏 | `cpu_mem.sv` | 核心管线 bug，与总线架构无关 |
| 7 | **BUG-5** | MMU Non-BRAM 路径 i_ready/d_ready 恒为 1 — TLB miss 使用错误物理地址 | `MMU.sv` | MMU bug，与总线架构无关 |
| 8 | **BUG-7** | FPU FCVT.W.S 左移截断 — 大浮点数转整数错误 | `fpu_cvt.sv` | FPU-bug-report 中 BUG 11 修复了 `f_abs_int` 位宽，但 rtl-bug-report 仍标记 BUG-7 未修复。**需确认：BUG 11 修复是否已覆盖 BUG-7** |
| 9 | **BUG-8** | FPU FCVT.W.S 右移截断 — 极小浮点数转整数错误 | `fpu_cvt.sv` | 同上，与 BUG-7 同源 |
| 10 | **BUG-4** | 全项目未使用 always_comb/always_ff — 锁存推断风险 | 全局 | 部分文件已迁移（UART BUG-64），但报告标记全局未完成 |
| 11 | **BUG-6** | FPU/MU Flush 后子模块死锁（当前 flush 硬连 0 故潜伏） | `fpu_unit.sv`, `mu_unit.sv` | 一旦实现 flush 必触发 |

---

## 🟡 四、MEDIUM 级未修复（当前架构相关）

| # | Bug | 描述 | 文件 |
|---|-----|------|------|
| 12 | **BUG-16** | MU/FPU flush 硬连为 0 — 长操作不可取消，中断延迟 | `cpu_execute.sv` |
| 13 | **BUG-14** | PTW 错误响应时 ptw_done 不置位 — MMU 永久挂起 | `cpu_bus_bridge.sv` |
| 14 | **BUG-15** | PTW 无总线响应超时 — 总线无响应则永久挂起 | `ptw.sv` |
| 15 | **BUG-9** | MMU 页故障 cause/vaddr 使用 PTW 实时输出而非锁存值 | `MMU.sv` |
| 16 | **BUG-10** | MMU Non-BRAM 同时 i_miss 和 d_miss 时 i-side 丢失 | `MMU.sv` |
| 17 | **BUG-22** | FPU DIV/SQRT 溢出忽略舍入模式 — 不符合 IEEE 754 | `fpu_divider.sv`, `fpu_sqrt.sv` |

---

## 🟡 五、AXI4-Lite / APB 协议合规（当前架构）

| # | 问题 | 严重度 | 文件 | 状态 |
|---|------|--------|------|------|
| 18 | **APB PPROT[0] 映射反转** — 特权访问被映射为非特权 | ❌ 严重 | `axi4lite_to_apb.sv` | ❌ 未修复（外设忽略 PPROT 故暂无功能影响） |
| 19 | **APB PSTRB 被所有外设忽略** — 子字写入覆盖整个寄存器 | ⚠️ 中等 | 所有 APB 外设 | ❌ 未修复 |
| 20 | **APB read_access 缺 PREADY 门控** | ⚠️ 中等 | 所有 APB 外设 | ❌ 未修复（零等待状态故暂无影响） |

---

## 🔴 六、FPGA 上板未验证

| # | 问题 | 来源 | 状态 |
|---|------|------|------|
| 21 | **FPGA MMIO 路径阻塞** — is_mmio 修复后 FPGA 仍无响应（PC=FC000000, IF_IN=00000000） | `fpga-boot-debug-process.md` §8 | ❌ 未解决。SRAM 仿真通过但 FPGA MMIO 路径未通 |
| 22 | **时序违规 WNS=-2.998ns** — MIG 内部 clk_pll_i 域 125 端点违规 | `axi-mig-alignment-process.md` §7.3 | ⚠️ MIG 已知问题，chiplab 同平台，未验证 |
| 23 | **sys_clk 域 WNS=-2.569ns** — 11 端点违规 | `axi-mig-alignment-process.md` §7.3 | ⚠️ 可能需 false_path 约束，未修复未验证 |

---

## 🟢 七、FPU 低优先级未修复

| # | 问题 | 文件 |
|---|------|------|
| 24 | fpu_multiply 极端下溢误报 OF | `fpu_multiplier.sv` |
| 25 | fpu_sqrt 次正规输入指数错误 | `fpu_sqrt.sv` |
| 26 | f0 硬连线零不符合 RISC-V 规范 | `fpu_regfile.sv` |

---

## ❌ 已排除的 Bug（关联已废弃 AHB-Lite 组件）

| Bug | 原描述 | 排除原因 |
|-----|--------|---------|
| BUG-11 | AHB-to-APB 桥 PPROT 未锁存 + 多驱动冲突 | `ahb_lite_to_apb.sv` 已废弃，活跃模块为 `axi4lite_to_apb.sv` |
| BUG-45 | DDR3 AHB Testbench aresetn 未初始化 | AHB 测试台已废弃，当前使用 AXI 仿真框架 |
| BUG-46 | Bridge C_M_AXI_THREAD_ID_WIDTH 配置不匹配 | `ddr3_bridge_wrapper` 已废弃 |
| BUG-47 | ahb_sys_status output wire 被 always_comb 驱动 | `ahb_sys_status.sv` 已废弃，AXI 版本 `axi4lite_sys_status.sv` 已修复 |
| BUG-48 | ddr3_bridge_wrapper 端口列表缺少逗号 | `ddr3_bridge_wrapper` 已废弃 |
| BUG-51 | ahb_bootrom_slave BRAM 无 mem 数组 | `ahb_bootrom_slave.sv` 已废弃，AXI 版本 `axi4lite_bootrom.sv` |
| BUG-60 | AHB SRAM byte_we 未连接到 BRAM | `ahb_sram_slave.sv` 已废弃 |
| ahb_apb_bug #1 | mux_HSELx 初始化死锁风险 | `ahb_lite_bus.sv` 已废弃 |
| ahb_apb_bug #2 | AHB 从设备接口不一致 | AHB 从设备已废弃 |
| ahb_apb_bug #3 | HMASTLOCK 始终为 0 | AHB 总线已废弃，AXI 无 HMASTLOCK |
| ahb_apb_bug #4 | INCR8 突发未检查 1KB 边界 | AHB 总线已废弃 |
| AHB phantom write 死锁 | AHB Bus Mux Phantom Write | AHB 架构已废弃 |
| DDR3-main-memory 大部分内容 | AHB-Lite 架构下的 DDR3 集成 | 整个 AHB 架构已废弃，转向 AXI |

---

## 📊 统计摘要

| 类别 | 数量 |
|------|------|
| 🔴 绕过未找根因 | **3** |
| 🟡 修复不彻底 | **1** |
| 🔴 HIGH 未修复 | **7** (BUG-1/2/5/7/8/4/6) |
| 🟡 MED 未修复 | **6** (BUG-16/14/15/9/10/22) |
| ⚠️ 协议合规 | **3** (PPROT反转, PSTRB忽略, read_access缺PREADY) |
| 🔴 FPGA 未验证 | **3** |
| 🟢 FPU 低优先级 | **3** |
| **总计未解决** | **26** |

---

## ⚠️ 最高风险项（建议优先处理）

1. **CPU 重复 AXI 事务 bug** — 根因未查，影响所有有副作用的 MMIO 寄存器（PLIC claim 等）
2. **BUG-1 PLIC Claim/Complete** — 需确认 AXI 版本 `axi4lite_plic.sv` 是否保留了同一时序缺陷
3. **FPGA MMIO 路径阻塞** — 上板核心阻塞点
4. **XPM_FIFO_ASYNC 仿真旁路** — CDC 零仿真覆盖
5. **BUG-7/8 FCVT 截断** — 需确认 FPU-bug-report 的 BUG 11 修复是否已覆盖
