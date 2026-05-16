# ~~Verilog 编译与仿真（mk.py）~~ [DEPRECATED]

> **此工具已弃用。** 项目已迁移至 SystemVerilog，仿真请使用 Vivado TCL 方式：
>
> ```tcl
> vivado.bat -mode tcl
> source vivado_do.tcl -notrace
> vivado_do -tb <testbench_name>
> ```
>
> 详见 `vivado_do.tcl` 头部注释。

---

仓库tools提供了 `tools/mk.py`，用于统一调用 `iverilog` 和 `vvp`。

特性：

- 通过命令行参数指定顶层文件。
- 自动递归搜索顶层文件实例化到的次级设计文件并参与编译。
- 所有编译与运行产物统一输出到 `build/` 目录。

## 基本用法

```bash
python tools/mk.py --top <顶层Verilog文件路径>
```

例如（当前 32 位 ALU 测试）：

```bash
python tools/mk.py --top dev/1-alu/tb/tb_alu_32bit.sv
```

## 常用参数

```bash
# 仅编译，不运行
python tools/mk.py --top dev/1-alu/tb/tb_alu_32bit.sv --compile-only

# 仅运行（使用已编译的 vvp 输出）
python tools/mk.py --top dev/1-alu/tb/tb_alu_32bit.sv --run-only

# 指定顶层模块名（传给 iverilog -s）
python tools/mk.py --top dev/1-alu/tb/tb_alu_32bit.sv --top-module tb_alu_32bit

# 指定输出目录（默认 build）
python tools/mk.py --top dev/1-alu/tb/tb_alu_32bit.sv --build-dir build
```
