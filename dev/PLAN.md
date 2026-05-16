# Verilog → SystemVerilog 迁移计划

## 1. 概述

将本项目从 Verilog (`*.v` / `*.vh`) 迁移至 SystemVerilog (`*.sv` / `*.svh`)，同时将仿真工具链从 `iverilog + mk.py` 切换至 Vivado TCL 仿真。

## 2. 迁移范围

### 2.1 RTL 源文件 (`dev/rtl/`)

| 子目录 | `.v` 文件数 | `.vh` 文件数 | 说明 |
|--------|------------|-------------|------|
| ALU/ | 10 | 0 | alu_32bit, alu_result_selector, cla_adder_*bit, logic_unit, lui, mux, shifter, subtractor |
| MU/ | 3 | 0 | booth_multiplier, mu_unit, non_restoring_divider |
| core/ | 21 | 0 | 含 icache.v / dcache.v（仿真时排除，但仍需改名） |
| AHB-lite/ | 5 | 1 | ahb_plic, ahb_lite_bus, ahb_decoder, ahb_mux, ahb_sram_slave + ahb_def.vh |
| AHB-lite/ip/ | 1 | 0 | sram_model |
| APB/ | 5 | 1 | apb_decoder, apb_bus, ahb_lite_to_apb, apb_master, apb_slave + apb_def.vh |
| APB/header/ | 0 | 2 | timer_define.vh, bus_define.vh |
| APB/perips/ | 7 | 0 | uart_tx, uart_top, uart_rx, timer, spi, gpio, apb_perips |
| 根目录 | 1 | 0 | system_top.v |
| **合计** | **53** | **4** | |

**操作：**
- 所有 `.v` → `.sv`，所有 `.vh` → `.svh`
- 文件内 `include 引用路径同步更新（`"xxx.vh"` → `"xxx.svh"`）
- 代码语法无需大改（Verilog 是 SystemVerilog 子集），但可逐步引入 SV 特性：
  - `logic` 替代 `reg` / `wire`
  - `always_ff` / `always_comb` 替代 `always @(...)`
  - `enum` / `struct` / `typedef` 等类型化改造（后续增量进行，本次不强制）

### 2.2 Testbench 文件 (`dev/tb/`)

| 路径 | 文件数 |
|------|--------|
| dev/tb/ (根) | 8 (tb_simple_cpu_top, tb_simple_cpu_compute, tb_simple_cpu_trap, tb_uart_hello, tb_led_marquee, tb_ahb_bus, tb_apb_perips, lcd_module_stub) |
| dev/tb/ALU/ | 3 (tb_non_restoring_divider, tb_mu_unit, tb_alu_cpu_integration) |
| **合计** | **11** |

**操作：**
- `.v` → `.sv`
- 测试模块命名保持 `tb_<module>` 不变

### 2.3 仿真工具链切换

| 项目 | 旧 | 新 |
|------|----|----|
| 编译仿真 | `python tools/mk.py --top <file>` | `vivado.bat -mode tcl` + TCL 脚本 |
| 仿真脚本 | `vivado_sim.tcl`（单文件固定流程） | 拆分为多个 TCL 脚本 + 参数化入口 |
| mk.py | 活跃使用 | **弃用**（保留文件，标记 deprecated） |

### 2.4 TCL 脚本重构

将现有 `vivado_sim.tcl` 拆分为：

```
vivado_sim.tcl          ← 主入口，解析参数，调用子脚本
tools/tcl/
  ├── create_proj.tcl   ← Step 1-3: 创建工程、添加源文件、设置 include
  ├── setup_ip.tcl      ← Step 4: 导入 IP、配置 COE
  ├── add_constrs.tcl   ← Step 5: 添加 DCP / XDC
  ├── add_tb.tcl        ← Step 6: 添加 testbench
  └── run_sim.tcl       ← Step 7-8: 启动仿真、读取日志
```

**参数化设计：**

```tcl
# vivado_sim.tcl 定义 proc vivado_sim，支持以下参数:
#   -tb <testbench_name>   指定 testbench（默认 tb_simple_cpu_top）
#   -step <step>           执行到哪一步: create|ip|constrs|tb|sim|all（默认 all）
#   -runtime <time>        仿真运行时间（默认按 tb_runtime_map 映射）
#   -clean                 删除已有工程目录后重建
```

**启动方式：**

```tcl
# 方式1: Vivado TCL Shell 交互
vivado.bat -mode tcl
source vivado_sim.tcl
vivado_sim -tb tb_simple_cpu_top -step all

# 方式2: 单步执行
vivado_sim -tb tb_ahb_bus -step create
vivado_sim -tb tb_ahb_bus -step ip
# ...

# 方式3: 通过 tcl-tunnel 远程执行（见 tools/tcl-tunnel/）
```

### 2.5 文档更新

| 文件 | 修改内容 |
|------|----------|
| `README.md` | 工具说明：mk.py → Vivado TCL 仿真 |
| `tools/README-mk.md` | 标记 deprecated，指向新的 TCL 方式 |
| `tools/tcl-tunnel/README.md` | 更新示例命令（.v → .sv 引用） |
| `dev/rtl/AHB-lite/AHB-lite.md` | 文件引用 .v → .sv |
| `dev/rtl/APB/APB.md` | 文件引用 .v → .sv |
| `dev/rtl/core/core.md` | 文件引用 .v → .sv |
| `.opencode/skills/coding-standards/SKILL.md` | 仿真命令更新 |

## 3. 执行顺序

1. **Phase 1 — 文件重命名**：批量 `.v` → `.sv`，`.vh` → `.svh`
2. **Phase 2 — 引用更新**：修改所有 `` `include ``、`add_files` glob、文档中的文件引用
3. **Phase 3 — TCL 重构**：拆分 vivado_sim.tcl，添加参数解析，适配 .sv 扩展名
4. **Phase 4 — mk.py 弃用**：标记 deprecated，更新文档
5. **Phase 5 — 验证**：逐个 testbench 跑通 Vivado 仿真

## 4. 风险与注意事项

- **`$readmemh` 路径**：Vivado xsim 工作目录与 iverilog 不同，相对路径需改为绝对路径（已在现有 TCL 中处理）
- **icache.v / dcache.v**：这两个文件在仿真中被排除（使用 IP 核替代），但文件仍需改名
- **`.vh` → `.svh`**：Vivado 对 `.svh` 的 include 行为与 iverilog 一致，但需确认 `include_dirs` 设置正确
- **Verilog → SV 语法兼容**：本次仅做文件扩展名迁移，不强制语法改造；Vivado 对 `.sv` 文件使用 SV 编译器，Verilog 语法完全兼容
- **tcl-tunnel 兼容**：tcl-tunnel 本身不涉及文件扩展名，但 README 示例需更新
