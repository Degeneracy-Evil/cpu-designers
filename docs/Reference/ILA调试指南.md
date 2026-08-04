# ILA (Integrated Logic Analyzer) 调试探针使用指南

## 1. 概述

本项目在 `system_top.sv` 中集成了两个 Vivado ILA 核，用于 FPGA 在片调试：

- **ILA #1 (`ila_reset_axi`)** — sys_clk 域，捕获复位信号与 CDC 侧 AXI 总线信号
- **ILA #2 (`ila_cpu_axi`)** — cpu_clk 域，捕获 CPU 侧 AXI 总线信号与 IF 阶段 PC

ILA 通过 `ENABLE_ILA` 宏条件编译：定义时实例化真实 ILA IP 核，未定义时实例化空壳 stub 模块，不影响仿真和普通构建。

---

## 2. 文件清单

| 文件 | 说明 |
|------|------|
| `src/rtl/system_top.sv` | 顶层模块，含 `ifdef ENABLE_ILA` 条件编译的 ILA 实例化 |
| `src/rtl/common/ila_stub.sv` | ILA stub 模块（空壳），仿真/无 ILA 构建时使用 |
| `tools/vivado_core/tcl/_add_ila.tcl` | 独立 TCL：在已打开的 Vivado 项目中创建 ILA IP 核 |
| `tools/vivado_core/tcl/build_with_ila.tcl` | 一键构建脚本：创建 ILA + 综合 + 实现 + 生成 bitstream |
| `system_top_ila.bit` | 带 ILA 的 bitstream（9.3 MB） |
| `system_top_ila.ltx` | ILA 探针定义文件（76 KB），Hardware Manager 必须加载 |

---

## 3. ILA 探针详细配置

### 3.1 ILA #1: `ila_reset_axi` (sys_clk 域)

**用途**：观察系统初始化阶段的复位序列与 AXI CDC 侧总线活动。

| 探针 | 宽度 | 信号 | 说明 |
|------|------|------|------|
| probe0 | 5-bit | `{resetn, clk_wiz_locked, ddr_aresetn, sys_resetn, cpu_resetn}` | 复位状态打包：外部复位、MMCM 锁定、MIG 校准完成、系统复位、CPU 复位 |
| probe1 | 32-bit | `cdc_awaddr` | CDC 侧 AXI 写地址 |
| probe2 | 8-bit | `{cdc_awvalid, cdc_awready, cdc_wvalid, cdc_wready, cdc_arvalid, cdc_arready, cdc_rvalid, cdc_rready}` | CDC 侧 AXI 四通道握手信号 |
| probe3 | 32-bit | `cdc_wdata` | CDC 侧 AXI 写数据 |
| probe4 | 32-bit | `cdc_araddr` | CDC 侧 AXI 读地址 |
| probe5 | 32-bit | `cdc_rdata` | CDC 侧 AXI 读返回数据 |
| probe6 | 4-bit | `{cdc_bvalid, cdc_bready, cdc_wlast, cdc_rlast}` | CDC 侧 B 通道响应 + W/R last 标志 |

**IP 配置**：7 探针，采样深度 4096，1 级输入流水线

### 3.2 ILA #2: `ila_cpu_axi` (cpu_clk 域)

**用途**：观察 CPU 侧 AXI 总线活动，关联指令位置 (PC)。

| 探针 | 宽度 | 信号 | 说明 |
|------|------|------|------|
| probe0 | 32-bit | `cpu_awaddr` | CPU 侧 AXI 写地址 |
| probe1 | 8-bit | `{cpu_awvalid, cpu_awready, cpu_wvalid, cpu_wready, cpu_arvalid, cpu_arready, cpu_rvalid, cpu_rready}` | CPU 侧 AXI 四通道握手信号 |
| probe2 | 32-bit | `cpu_wdata` | CPU 侧 AXI 写数据 |
| probe3 | 32-bit | `cpu_araddr` | CPU 侧 AXI 读地址 |
| probe4 | 32-bit | `cpu_rdata` | CPU 侧 AXI 读返回数据 |
| probe5 | 4-bit | `{cpu_bvalid, cpu_bready, cpu_wlast, cpu_rlast}` | CPU 侧 B 通道响应 + W/R last 标志 |
| probe6 | 32-bit | `if_pc` | CPU IF 阶段 PC，用于关联总线活动与指令位置 |

**IP 配置**：7 探针，采样深度 4096，1 级输入流水线

### 3.3 时钟域说明

| 时钟 | 频率 | 驱动 ILA | 信号域 |
|------|------|---------|--------|
| `sys_clk` | 100 MHz | ila_reset_axi | 复位链、CDC 输出、AXI 互连 |
| `cpu_clk` | 50 MHz | ila_cpu_axi | CPU 流水线、CPU 侧 AXI master |

> **重要**：ILA 探针必须在同一时钟域。跨域信号需使用独立 ILA 实例，否则会产生亚稳态。

---

## 4. 构建方法

### 4.1 一键构建（推荐）

```bash
vivado -mode batch -source tools/vivado_core/tcl/build_with_ila.tcl
```

此脚本自动完成：
1. 打开已有 FPGA 项目
2. 添加 `ila_stub.sv`
3. 创建 ILA IP 核 (`ila_reset_axi`, `ila_cpu_axi`)
4. 设置 `ENABLE_ILA` 宏
5. 综合 + 实现 + 生成 bitstream
6. 复制 `system_top_ila.bit` 和 `system_top_ila.ltx` 到项目根目录

### 4.2 手动步骤（Vivado TCL 交互模式）

```tcl
# 1. 打开项目
open_project project/fpga/simplecpu_soc.xpr

# 2. 添加 stub 文件
add_files -norecurse src/rtl/common/ila_stub.sv

# 3. 创建 ILA IP 核
source tools/vivado_core/tcl/_add_ila.tcl

# 4. 设置 ENABLE_ILA 宏
set_property verilog_define {ENABLE_ILA} [current_fileset]
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1

# 5. 综合与实现
reset_run synth_1
launch_runs synth_1 -jobs 14
wait_on_run synth_1
launch_runs impl_1 -jobs 14
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 14
wait_on_run impl_1

# 6. 复制输出
file copy -force project/fpga/simplecpu_soc.runs/impl_1/system_top.bit system_top_ila.bit
file copy -force project/fpga/simplecpu_soc.runs/impl_1/system_top.ltx system_top_ila.ltx
```

### 4.3 普通（无 ILA）构建

不设置 `ENABLE_ILA` 宏即可。此时 stub 模块被实例化（空壳），ILA IP 不消耗任何 FPGA 资源。

```bash
# 使用原有构建流程
vivado_do -bitstream
```

---

## 5. FPGA 下载与调试

### 5.1 前提条件

- FPGA 开发板已连接 JTAG 电缆并上电
- Vivado Hardware Server (`hw_server`) 已在远端运行
- SSH 反向隧道已建立（如需远程访问）

### 5.2 SSH 反向隧道设置

若 FPGA 连接在远端主机，需通过 SSH 反向隧道将远端 `hw_server` 端口转发到本地：

```bash
# 在远端 FPGA 主机上执行（将 3121 端口反向转发到本机）：
ssh -R 3121:localhost:3121 <user>@<this-server-ip>

# 验证隧道是否生效（在本机执行）：
ss -tlnp | grep 3121
# 应看到 127.0.0.1:3121 在监听
```

**验证 Vivado 连接**：连接时日志应显示 `Connecting to hw_server url TCP:localhost:3121`，**不应**出现 `Launching hw_server`（后者说明连到了本地新启动的 hw_server，而非远端）。

### 5.3 下载 bitstream + ILA 探针

#### 方法 A：TCL 脚本

```tcl
# 连接硬件
open_hw
connect_hw_server -url localhost:3121
open_hw_target [get_hw_targets */xilinx_tcf]

# 选择设备
set hw_device [lindex [get_hw_devices] 0]
current_hw_device $hw_device

# 设置 bitstream 和探针文件（两者都必须设置！）
set_property PROGRAM.FILE system_top_ila.bit  $hw_device
set_property PROBES.FILE  system_top_ila.ltx $hw_device   ;# ← 关键！缺少此文件 ILA 无法工作

# 下载
program_hw_devices $hw_device
refresh_hw_device $hw_device
```

#### 方法 B：Vivado GUI

1. 打开 Hardware Manager
2. 连接目标设备
3. 右键设备 → Program Device
4. **Bitstream file**: 选择 `system_top_ila.bit`
5. **Debug probes file**: 选择 `system_top_ila.ltx` ← **必须选择，否则 ILA 不可见**
6. 点击 Program

### 5.4 ILA 波形捕获

#### GUI 操作

1. 在 Hardware 面板中找到 `hw_ila_1` (ila_reset_axi) 和 `hw_ila_2` (ila_cpu_axi)
2. 右键 ILA → **Add Probes to Trigger** — 选择要触发/观察的探针
3. 在 Trigger Setup 中设置触发条件（见下方常用触发模式）
4. 点击 **Run Trigger** (▶) — 状态变为 "Waiting for Trigger"
5. 触发条件满足后，波形窗口自动弹出
6. 可点击 **Refresh** 重新武装 ILA（无需重新下载 bitstream）

#### TCL 操作

```tcl
# 获取 ILA 核
set ila1 [get_hw_ilas hw_ila_1]   ;# ila_reset_axi
set ila2 [get_hw_ilas hw_ila_2]   ;# ila_cpu_axi

# 设置触发条件：probe0 的 resetn (bit4) 上升沿
set_property TRIGGER_COMPARE_VALUE "eq 5'b1xxxx" [get_hw_probes probe0 -of $ila1]
set_property TRIGGER_MODE BASIC_ONLY $ila1

# 武装 ILA 并等待触发
run_hw_ila $ila1

# 立即捕获（不等待触发）
run_hw_ila $ila1 -trigger_now

# 上传捕获数据并导出
upload_hw_ila $ila1
write_hw_ila_data -force ila_capture1.wdb $ila1
```

---

## 6. 常用触发模式

### 6.1 观察初始化复位序列

在 `ila_reset_axi` 上设置触发，捕获系统从复位到正常运行的过程：

| 触发目标 | 触发条件 | 说明 |
|---------|---------|------|
| probe0[4] (`resetn`) | 上升沿 (re) | 外部复位释放时刻 |
| probe0[2] (`ddr_aresetn`) | 上升沿 (re) | DDR3 校准完成时刻 |
| probe0[3] (`sys_resetn`) | 上升沿 (re) | 系统复位释放时刻 |

### 6.2 观察 CPU 首次访存

在 `ila_cpu_axi` 上设置触发，捕获 CPU 发出第一个 AXI 请求：

| 触发目标 | 触发条件 | 说明 |
|---------|---------|------|
| probe1[4] (`cpu_arvalid`) | 上升沿 (re) | CPU 发出首个读请求 |
| probe1[0] (`cpu_awvalid`) | 上升沿 (re) | CPU 发出首个写请求 |
| probe0 (`cpu_awaddr`) | `eq 32'h80000000` | 写地址命中特定地址 |
| probe6 (`if_pc`) | `eq 32'h80000100` | PC 命中特定指令地址 |

### 6.3 观察 AXI 总线挂起

在 `ila_reset_axi` 上设置触发，检测 AXI 握手长时间未完成：

| 触发目标 | 触发条件 | 说明 |
|---------|---------|------|
| probe2[0] (`cdc_awvalid`) | `eq 1` 且 probe2[1] (`cdc_awready`) = `eq 0` | AW 通道 valid 但无 ready（需高级触发） |

### 6.4 触发条件语法速查

| 类型 | 语法 | 示例 |
|------|------|------|
| 等于 | `eq N'hVALUE` | `eq 32'h80000000` |
| 不等于 | `ne N'hVALUE` | `ne 32'h0` |
| 大于 | `gt N'hVALUE` | `gt 32'h100` |
| 小于 | `lt N'hVALUE` | `lt 32'hFF` |
| 位置位 | `bs N'hVALUE` | `bs 5'b10000` (resetn=1) |
| 位清除 | `bn N'hVALUE` | `bn 5'b00100` (ddr_aresetn=0) |
| 上升沿 | `re` | probe0 上升沿 |
| 下降沿 | `fe` | probe0 下降沿 |

---

## 7. 资源开销

| 资源 | ILA #1 (ila_reset_axi) | ILA #2 (ila_cpu_axi) | 合计 | Artix-7 A200T 总量 | 占比 |
|------|----------------------|----------------------|------|-------------------|------|
| LUTs | ~800 | ~800 | ~1600 | 53,650 | <3% |
| FFs | ~200 | ~200 | ~400 | 106,300 | <0.5% |
| BRAM36K | ~12 | ~12 | ~24 | 365 | ~7% |

> **注意**：BRAM 是主要瓶颈，由采样深度驱动。深度 4096 时两个 ILA 共消耗约 24 个 BRAM36K。如需减少开销，可将 `C_DATA_DEPTH` 从 4096 降至 1024。

---

## 8. 扩展指南

### 8.1 添加新探针

1. 在 `system_top.sv` 的 ILA 实例化块中添加新的 probe 端口连接
2. 在 `ila_stub.sv` 中对应添加新的 probe 端口（保持端口一致）
3. 在 `_add_ila.tcl` 中增加 `CONFIG.C_NUM_OF_PROBES` 和对应的 `CONFIG.C_PROBEn_WIDTH`
4. 重新运行 `build_with_ila.tcl`

### 8.2 添加新的 ILA 核

若需探针不同时钟域的信号（如 DDR3 MIG ui_clk 域）：

1. 在 `ila_stub.sv` 中添加新的 stub 模块
2. 在 `system_top.sv` 中添加新的 `ifdef ENABLE_ILA` 实例化块
3. 在 `_add_ila.tcl` 中添加新的 `create_ip` 块
4. 在 `build_with_ila.tcl` 中添加 IP 创建逻辑

### 8.3 调整采样深度

修改 `_add_ila.tcl` 和 `build_with_ila.tcl` 中的 `CONFIG.C_DATA_DEPTH`：

| 深度 | BRAM 开销 (每 ILA) | 适用场景 |
|------|-------------------|---------|
| 1024 | ~3 BRAM36K | 单指令触发，小窗口 |
| 4096 | ~12 BRAM36K | **当前默认**，初始化序列调试 |
| 8192 | ~24 BRAM36K | 长时间流水线观察 |
| 16384 | ~48 BRAM36K | 启动序列/Cache 行为分析 |

---

## 9. 故障排除

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| Hardware Manager 中看不到 ILA | 未加载 .ltx 文件 | 下载时设置 `PROBES.FILE = system_top_ila.ltx` |
| ILA 触发后无波形 | 采样深度不够或触发位置不对 | 增大 `C_DATA_DEPTH`，或调整触发前后采样比例 |
| 综合报 ILA 模块找不到 | 未创建 ILA IP 核 | 运行 `_add_ila.tcl` 或 `build_with_ila.tcl` |
| 仿真报 ILA 模块找不到 | 未添加 `ila_stub.sv` | 将 `ila_stub.sv` 加入仿真文件列表 |
| ILA 导致时序违例 | 探针路径过长 | 增大 `C_INPUT_PIPE_STAGES` 至 2 |
| 连接 hw_server 时显示 "Launching" | SSH 隧道未生效，Vivado 启动了本地 hw_server | 检查隧道：`ss -tlnp \| grep 3121`，确保远端 hw_server 已运行 |
