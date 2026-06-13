# 未解决 Bug 汇总报告

> 生成日期: 2026-06-13
> 依据: `process/` 下全部 10 个文件的逐条审查 + 当前 RTL 代码逐条验证
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
| 2 | **XPM_FIFO_ASYNC xsim 仿真模型完全不工作** | `Axi_CDC.v`, Xilinx XPM | 仿真 `ifdef SIMULATION` 直连旁路 | **CDC 功能零仿真覆盖**，FPGA 上 CDC 正确性未验证 |

> **注**: 原"CPU 每条 lw/sw 触发两次 AXI4-Lite 事务"已确认为 **BUG-91**，见下方第三段。

---

## 🟡 二、修复不彻底/回退

| # | Bug | 文件 | 遗留问题 |
|---|-----|------|---------|
| 3 | **Axi_CDC xpm_fifo_async 重写已回退** | `Axi_CDC.v` | 重写需单独验证后重新提交。当前仍用 SpinalHDL 原始实现 + 仿真旁路 |

---

## 🔴 三、BUG-91: MMIO 请求接口为电平协议（原"CPU 重复 AXI 事务"根因）

**状态**: ✅ **已修复并验证通过** (2026-06-13)

**文件**: `icache_ctrl.sv`, `dcache_ctrl.sv`, `cpu_bus_bridge.sv`

**原报告描述**: "CPU 每条 lw/sw 触发两次 AXI4-Lite 事务"

**实际根因**: `icache/dcache → cpu_bus_bridge` 的 MMIO 请求使用 level-sensitive `mmio_req`，而不是 `valid/accept` 握手。总线桥在 `S_IDLE` 无法区分"请求 still high"与"新请求 arrived"。

**修复方案** (已实施):
1. 将 MMIO 接口改为 `req + accept + resp_valid` 三段式握手
2. `cpu_bus_bridge` 在 `S_IDLE` 仲裁选中请求源时发出单周期 `*_mmio_accept`
3. `icache_ctrl/dcache_ctrl` 内部增加 pending 位 + 锁存 `mmio_addr_r`/`mmio_wdata_r`，请求被 accept 后立刻撤销 `mmio_req`
4. 删除 `mmio_inst_served/mmio_data_served` 补丁逻辑

**验证结果**:
- `reg_mmio_ready`: 191,397 条指令退休，MMIO 握手无重复事务、无 stale 响应丢弃
- `mmio_plic`: PLIC claim/complete 中断测试完整执行 ✅
- `mmio_clint`: CLINT 定时器中断测试完整执行 ✅

**UART STATUS-read auto-arm workaround 仍保留**（作为防御层），但根因已消除。

---

## ✅ 四、原 HIGH/MEDIUM 级 Bug — 经代码审查全部已修复

### HIGH 级（原 7 项 → 0 项未修复）

| Bug | 描述 | 文件 | 审查结果 |
|-----|------|------|---------|
| **BUG-1** | PLIC Claim/Complete 握手失效 | `axi4lite_plic.sv` | ✅ AXI 版本通过 `rd_fire`/`wr_fire` 门控 + `r_claim_id` 锁存正确实现原子 claim（返回 highest_id + 清 pending + 关 gateway） |
| **BUG-2** | FLW/FSW 非对齐异常未上报 | `cpu_mem.sv` | ✅ 当前代码 `(is_load \| is_flw) && misalign_addr`（line 263-264），已包含 is_flw/is_fsw |
| **BUG-5** | MMU Non-BRAM i_ready/d_ready 恒为 1 | `MMU.sv` | ✅ Non-BRAM 路径 `i_ready = !i_miss`（含 pending_i_walk），TLB miss 时 ready=0 正确阻止使用错误物理地址 |
| **BUG-7** | FPU FCVT.W.S 左移截断 | `fpu_cvt.sv` | ✅ `f_lshift_of = f_large && (f_lshift >= 10'd32)` 检测溢出（line 144），`f_ovf_w/f_ovf_wu` 包含 `f_lshift_of`（line 191-195） |
| **BUG-8** | FPU FCVT.W.S 右移截断 | `fpu_cvt.sv` | ✅ 56 位扩展 + `f_rshift_zero = !f_large && (f_shift >= 10'd56)` 检测全移出归零（line 149-151） |
| **BUG-4** | 全项目未使用 always_comb/always_ff | 全局 | ✅ 仅 `axi4lite_bootrom.sv` 残留 1 处 `always @`（`ifdef SIMULATION` 内调试，与 `initial` 混合驱动需保留）。综合路径零 `always @`，锁存推断风险消除 |
| **BUG-6** | FPU/MU Flush 后子模块死锁 | `fpu_unit.sv`, `mu_unit.sv` | ✅ 子模块已有 flush 输入（state→IDLE），`cpu_execute.sv` 计算 `exe_flush = trap_pending && (mu_active \|\| fpu_active)` |

### MEDIUM 级（原 6 项 → 0 项未修复）

| Bug | 描述 | 文件 | 审查结果 |
|-----|------|------|---------|
| **BUG-16** | MU/FPU flush 硬连为 0 | `cpu_execute.sv` | ✅ `exe_flush = trap_pending && (mu_active \|\| fpu_active)` 连接到 flush 端口 |
| **BUG-14** | PTW 错误响应时 ptw_done 不置位 | `cpu_bus_bridge.sv` | ✅ 错误路径中 `ptw_done_r <= 1'b1`（line 724, 776） |
| **BUG-15** | PTW 无总线响应超时 | `ptw.sv` | ✅ 添加 16 位 `timeout_cnt`，阈值 256 周期，超时进 S_FAULT（line 239, 270, 312） |
| **BUG-9** | MMU 页故障 cause/vaddr 用 PTW 实时输出 | `MMU.sv` | ✅ 4 处输出 assign 改为使用锁存值 `i_pf_cause_r`/`i_pf_vaddr_r`（line 330-331, 367-368, 831-832, 867-868） |
| **BUG-10** | MMU 同时 i_miss/d_miss 时 i-side 丢失 | `MMU.sv` | ✅ `pending_i_walk`/`pending_d_walk` 捕获同时 miss（line 752-797） |
| **BUG-22** | FPU DIV/SQRT 溢出忽略舍入模式 | `fpu_divider.sv`, `fpu_sqrt.sv` | ✅ 添加 `ovf_to_inf` 逻辑，按 IEEE 754 舍入模式决定返回 ±Infinity 或 ±Max（line 190-196, 182-189） |

### 第七轮新增 Bug（BUG-91/92/93/94/95）

| Bug | 描述 | 状态 |
|-----|------|------|
| **BUG-91** | MMIO 请求接口为电平协议 → 重复 AXI 事务 | ✅ 已修复（见第三节） |
| **BUG-92** | sys_clk 域中断直接进入 cpu_clk 域（CDC 风险） | ✅ 已修复 — `system_top.sv` 添加 2 级同步器 `*_cpuclk_ff1/ff2`（line 245-266） |
| **BUG-93** | FPU Multiplier 单拍大组合路径（时序热点） | ❌ **未修复** — `mant1 * mant2` 仍为单周期组合乘法 + 后处理串接 |
| **BUG-94** | AXI BFM 在错误时钟域驱动 | ✅ 已修复 — `axi_mst_clk = u_soc.cpu_clk` 替换 `clk` |
| **BUG-95** | UART_STATUS 期望值错误 | ✅ 已修复 — `4'b0100` → `4'b0110` |

### APB 协议合规（原 3 项 → 0 项未修复）

| 问题 | 状态 | 证据 |
|------|------|------|
| PPROT[0] 映射反转 | ✅ 已修复 | `PPROT = {latch_prot[2], latch_prot[1], ~latch_prot[0]}`（`axi4lite_to_apb.sv` line 117），注释说明 AXI AxPROT[0] 与 APB PPROT[0] 极性相反 |
| PSTRB 被所有外设忽略 | ✅ 已修复 | GPIO/UART/SPI/Timer 均添加 PSTRB 字节掩码写入（如 `if (PSTRB[0]) reg[7:0] <= PWDATA[7:0]`） |
| read_access 缺 PREADY 门控 | ✅ 已修复 | `read_access = PSEL & PENABLE & !PWRITE & PREADY`（gpio.sv line 54, uart_top.sv line 46 等） |

---

## 🔴 五、FPGA 上板未验证

| # | 问题 | 来源 | 状态 |
|---|------|------|------|
| 4 | **FPGA MMIO 路径阻塞** — is_mmio 修复后 FPGA 仍无响应（PC=FC000000, IF_IN=00000000） | `fpga-boot-debug-process.md` §8 | ❌ 未解决。SRAM 仿真通过但 FPGA MMIO 路径未通 |
| 5 | **时序违规 WNS=-2.998ns** — MIG 内部 clk_pll_i 域 125 端点违规 | `axi-mig-alignment-process.md` §7.3 | ⚠️ MIG 已知问题，chiplab 同平台，未验证 |
| 6 | **sys_clk 域 WNS=-2.569ns** — 11 端点违规 | `axi-mig-alignment-process.md` §7.3 | ⚠️ 可能需 false_path 约束，未修复未验证 |

---

## 🟡 六、MEDIUM 级未修复

| # | Bug | 描述 | 文件 | 状态 |
|---|-----|------|------|------|
| 7 | **BUG-93** | FPU Multiplier 单拍大组合路径（24×24 乘法 + 规格化 + 舍入串接），时序热点 | `fpu_multiplier.sv` | ❌ 未修复。修复方案：拆为至少 2 拍 `MUL → NORM/ROUND` |

---

## 🟢 七、FPU 低优先级未修复

| # | 问题 | 文件 |
|---|------|------|
| 8 | fpu_multiply 极端下溢误报 OF | `fpu_multiplier.sv` |
| 9 | fpu_sqrt 次正规输入指数错误 | `fpu_sqrt.sv` |
| 10 | f0 硬连线零不符合 RISC-V 规范（设计选择） | `fpu_regfile.sv` |

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
| 🔴 绕过未找根因 | **2** (BUG-56 MIG force, XPM_FIFO_ASYNC 旁路) |
| 🟡 修复不彻底 | **1** (Axi_CDC xpm 回退) |
| ✅ 原标未修复实际已修复 | **16** (BUG-1/2/5/7/8/4/6/16/14/15/9/10/22/91/92 + APB 协议 3 项) |
| 🔴 FPGA 未验证 | **3** |
| 🟡 MEDIUM 未修复 | **1** (BUG-93 FPU 乘法器时序) |
| 🟢 FPU 低优先级 | **3** |
| **总计未解决** | **10** |

---

## ⚠️ 最高风险项（建议优先处理）

1. **FPGA MMIO 路径阻塞** — 上板核心阻塞点，SRAM 仿真无法覆盖
2. **XPM_FIFO_ASYNC 仿真旁路** — CDC 零仿真覆盖，FPGA 上 CDC 是跨时钟域关键路径
3. **BUG-56 MIG 校准 force workaround** — 仿真 DDR3 读通路初始化不完整（硬件不存在此问题）
4. **BUG-93 FPU 乘法器时序热点** — 单周期 24×24 组合乘法，高频率下可能成关键路径
