# AGENTS.md - 32位 RISC-V 多周期 CPU 开发指南

## 项目概述

实现一个 32 bit RISC-V 多周期 CPU，哈佛结构，基于已有 ALU，支持异常/中断与 GPIO/UART 外设。

## 文档

`docs/` 目录包含完整设计文档，供人类阅读以了解项目。

## Skills

按功能模块拆分的 AI 实现指导，开发具体功能时按需加载：

| Skill | 用途 |
|-------|------|
| `rv32i` | RV32I + Zicsr 指令实现（opcode 译码、编码表、立即数生成、CSR、异常编码） |
| `fsm` | 多周期 FSM 实现（状态定义、转移路径、控制信号） |
| `coding-standards` | 编码规范与仿真（命名约定、模板代码、iverilog 命令） |

## 文档索引

| 编号 | 文件 | 内容 |
|------|------|------|
| 01 | [overview](docs/01-overview.md) | 项目背景、目标、设计边界 |
| 02 | [architecture](docs/02-architecture.md) | 架构选型、微结构、存储结构 |
| 03 | [instruction-set](docs/03-instruction-set.md) | 完整指令表（编码+语义+实现策略）、CSR 定义 |
| 04 | [module-design](docs/04-module-design.md) | 模块划分、层次结构、接口约定 |
| 05 | [fsm-control](docs/05-fsm-control.md) | 多周期 FSM 状态定义、转移路径、控制信号 |
| 06 | [memory-mapping](docs/06-memory-mapping.md) | 存储组织、MMIO 地址映射、对齐规则 |
| 07 | [exception-interrupt](docs/07-exception-interrupt.md) | 异常与中断机制、trap 流程 |
| 08 | [peripherals](docs/08-peripherals.md) | GPIO、UART 设计 |
| 09 | [coding-standards](docs/09-coding-standards.md) | 代码规范、命名约定、模板 |
| 10 | [verification](docs/10-verification.md) | 仿真验证策略、工具链、Makefile |
| 11 | [development-phases](docs/11-development-phases.md) | 开发阶段、里程碑、当前状态 |

## 当前优先事项

1. 明确完整 RV32I 指令实现清单与分类 → `docs/03-instruction-set.md` ✅
2. 明确多周期 CPU 的总体数据通路与状态机框架 → `docs/05-fsm-control.md` ✅
3. 明确顶层模块划分、接口表与目录结构 → `docs/04-module-design.md` ✅

完成以上三项后，再正式进入 RTL 编写阶段。
