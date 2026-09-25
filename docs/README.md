# 文档索引

## 操作与设计

| 文档 | 内容 |
|------|------|
| `../README.md` | 项目入口：结构、工具、仿真、上板 |
| `simpleCPU-design-report.md` | 设计报告：CPU/SoC 设计详述 |
| `commands-cheatsheet.md` | 常用命令速查 |
| `linux仿真手册.md` | Linux SRAM/DDR3 仿真步骤 |
| `testing/test-system.md` | 测试体系与新增测试方法 |
| `tools/README-vivado.md` | Vivado 工程/仿真/bitstream CLI |
| `tools/README-rv2coe.md` | RISC-V 程序编译为 COE/HEX |
| `todo.md` | 当前状态与待办 |

## 参考资料（项目内）

- `simplification-refactor/` — 设计简化重构记录 01-10（TLB/Cache/异常/特权/PMP 等）
- `alu/` — ALU/MU 设计与接口文档（README、ALU_DESIGN、ALU_INTERFACE、MU_INTERFACE）
- `privileged/`、`core/riscv-plic-ref.md`、`Mem/sv32-*.md` — RISC-V 规范摘要
- `Reference/` — 板级与构建参考（MIG、DDR3 模型、引脚约束、ILA 调试；含历史快照）
- `Report/` — 历史课程提交物，不代表当前设计
- `archive/` — 已归档历史文档，不再维护

## 官方规范（本地副本已删，需要时查原文）

- RISC-V ISA / Privileged / CLINT 等：<https://riscv.org/technical/specifications/>
- AMBA AXI / APB / AHB：<https://developer.arm.com/architecture/system-architecture/amba>
- PlantUML：<https://plantuml.com/>
