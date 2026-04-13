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
iverilog -o cpu_tb rtl/*.v tb/tb_cpu_top.v && vvp cpu_tb
```

## 详细规格

- 完整命名规范与模板代码见 `docs/09-coding-standards.md`
- 验证策略与 Makefile 目标见 `docs/10-verification.md`
