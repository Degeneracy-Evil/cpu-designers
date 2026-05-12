---
name: coding-standards
description: |
  Coding standards and simulation guide for the embedded CPU project.
  Use this skill when writing Verilog code, creating testbenches, or running
  simulations to ensure compliance with project conventions.
---

# 编码规范与仿真

## 编码规范要点

- 模块/信号：小写下划线分隔；参数/状态：大写下划线分隔
- 时序与组合逻辑分离；状态机三段式
- `timescale 1ns / 1ps`；上升沿 clk；高电平异步 reset
- 测试平台：`tb_<module>.v`；自动 PASS/FAIL 输出

## 仿真

```bash
python tools/mk.py --top <顶层Verilog文件路径>
```

## 编译产生coe文件

```bash
python3 tools/rv2coe.py \
  -i tools/examples/phase1_prog.S \
  -o dev/2-embedded_cpu/program_source/icache_init.coe
```

## 项目工作流与文档说明

- 项目脚本与工具位于 `tools/` 文件夹下。
- **所有修改都需要记录到 `dev/PROCESS.md` 中（如果没有该文件则创建）。**
