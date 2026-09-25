# 项目待办

更新：2026-09-25

## 当前状态

- RTL：时序收敛 @40MHz（WNS +0.459，44758 端点全过），bitstream 已生成（cf8b4e4）
- 仿真：52 程序 / 361 子测试全过；`kernel_boot_sram` / `kernel_boot_ddr3` 可复现 OpenSBI + 内核启动窗口
- 文档：整理完成（操作手册重写、设计报告大修、历史文档归档、第三方规范副本删除）

## 待办

- [ ] FPGA 上板：烧写 bitstream → `python3 -m tools.uart_console` 上传 `fw_payload.bin` → 验证 Linux 启动
- [ ] Linux 完整验证：仿真/上板跑到 init/shell（未达成前不能宣称 Linux 已完全验证）
- [ ] （可选）ILA 调试入口验证：确认普通构建不受影响

## 说明

历史调试/规划文档见 `docs/archive/`。旧版"大扫除"计划（vivado_cli 时代）已完成并废止，本文为现行唯一待办清单。
