# MMU构建计划

## 目标

建立页式虚拟内存。

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。

## 验收



## 参考资料

上一阶段完成后项目整体报告：dev\docs\simpleCPU-design-report.md
AHB-lite标准文件：dev\docs\AHB-lite\AMBA_AHB-Lite_Spec_Summary.md
APB标准文件：dev\docs\APB\AMBA_APB_Spec_Summary.md
M模式标准：dev\docs\privileged\machine-mode.md
S模式标准：dev\docs\privileged\supervisor-mode.md
U模式标准：dev\docs\privileged\user-mode.md
SV32标准：dev\docs\Mem\sv32-virtual-memory.md

## 工具

vivado_do.tcl：vivado tcl 脚本，使用其进行模拟
tools\rv2coe.py：rv汇编/C程序编译脚本，输出格式HEX/COE/...

## 开发约束

将更改和进度输出到dev\PROCESS-mmu.md中。
