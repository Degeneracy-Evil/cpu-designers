---
name: coding-standards
description: |
  Coding standards and simulation guide for the embedded CPU project.
  Use this skill when writing SystemVerilog code, creating testbenches, or running
  simulations to ensure compliance with project conventions.
---

# 编码规范与仿真

## 编码规范要点

- 模块/信号：小写下划线分隔；参数/状态：大写下划线分隔
- 时序与组合逻辑分离；状态机三段式
- `timescale 1ns / 1ps`；上升沿 clk
- RTL 文件扩展名：`*.sv` / `*.svh`；测试平台：`tb_<module>.sv`；自动 PASS/FAIL 输出

## 复位信号规范（强制）

全项目统一使用 **active-LOW 异步复位**，禁止混用极性或同步复位模式。

### 命名约定

| 信号 | 命名 | 说明 |
|------|------|------|
| CPU core 复位 | `resetn` | 所有 core/FPU/MU 模块 |
| AHB 总线复位 | `HRESETn` | AHB-Lite 协议规定 |
| APB 外设复位 | `PRESETn` | APB 协议规定 |
| UART 子模块复位 | `rst_n` | uart_tx/uart_rx |
| FIFO 复位 | `rst_n` | sync_fifo |
| MIG AXI 复位 | `aresetn` | MIG 7 Series IP |

**禁止**：`reset`（无 `_n` 后缀的 active-HIGH 复位信号名）、`rst`（无 `_n` 后缀）。

### 编码模式

所有含状态的模块**必须**使用异步复位，模式如下：

```systemverilog
// CPU core 模块（resetn）
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        // 复位赋值
    end else begin
        // 正常逻辑
    end
end

// AHB 总线模块（HRESETn）
always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        // 复位赋值
    end else begin
        // 正常逻辑
    end
end

// APB 外设模块（PRESETn）
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        // 复位赋值
    end else begin
        // 正常逻辑
    end
end
```

### 禁止事项

- ❌ **同步复位**：`always_ff @(posedge clk)` + `if (resetn)` — 复位不在敏感列表中
- ❌ **active-HIGH 复位**：`posedge reset` / `if (reset)` — 极性反转
- ❌ **`initial` 块替代复位**：`initial begin ... end` — 仅仿真有效，FPGA 上电后无效
- ❌ **`foreach` 循环**：在 always 块中使用 `foreach` — 部分综合工具不支持，改用 `for (integer i = 0; i < N; i = i + 1)`
- ❌ **`always @`**：使用 `always_ff @` 代替（风格一致性）

### 复位同步器

跨时钟域或复位释放需同步化时，使用 `reset_sync` 模块（`dev/rtl/common/reset_sync.sv`）：

```systemverilog
reset_sync u_rst_sync (
    .rst_n_in (async_resetn),   // 异步 assert / 异步 deassert
    .clk      (domain_clk),     // 目标时钟域
    .rst_n_out(syncd_resetn)    // 异步 assert / 同步 deassert（2-stage FF）
);
```

每个时钟域实例化一个 `reset_sync`。**assert 保持异步**（立即响应），**deassert 经 2 级 FF 同步**（防 metastability）。

### 复位序列（system_top）

复位释放顺序为三级流水：

```
resetn deassert（板级）
    → Stage 1: mig_aresetn 释放（MIG 校准完成）
    → 2 cycles 延迟（MIG AXI 接口稳定）
    → Stage 2: ahb_hresetn 释放（AHB 总线就绪）
    → reset_sync 同步化
    → Stage 3: cpu_resetn 释放（CPU 开始取指）
```

新增模块时，根据其所属域连接对应复位信号，不得绕过序列直接连接板级 `resetn`。

## 仿真

```tcl
# 启动 Vivado TCL Shell
vivado.bat -mode tcl

# 加载脚本
source vivado_do.tcl

# 运行仿真 (全流程)
vivado_do -tb <testbench_name> -step all

# 单步执行
vivado_do -tb <testbench_name> -step create
vivado_do -tb <testbench_name> -step sim

# 可用参数: -tb <testbench> -step <create|ip|constrs|tb|sim|all> -runtime <time> -clean
```

## 编译产生coe文件

```bash
python3 tools/rv2coe.py \
  -i tools/examples/phase1_prog.S \
  -o dev/2-embedded_cpu/program_source/icache_init.coe
```

## 项目工作流与文档说明

- 项目脚本与工具位于 `tools/` 文件夹下。
- Vivado TCL 子脚本位于 `tools/tcl/` 目录。
- **所有修改都需要记录到 `dev/PROCESS.md` 中（如果没有该文件则创建）。**
