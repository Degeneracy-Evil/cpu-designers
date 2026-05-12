# simpleCPU 优化计划

## 项目概述

RISC-V RV32I + Zicsr 多周期处理器，5 级流水线 (IF→ID→EXE→MEM→WB)，
AHB-Lite + APB 两级总线架构，目标 Xilinx 7 系列 FPGA。

- ISA: 55 条指令 (RV32I 40 + M 8 + Zicsr 6 + Zifencei 1)
- 乘除法: Booth 乘法器 + 非恢复余数除法器，多周期握手
- 8 个 Machine 模式 CSR，异常/中断完整支持
- 外设: GPIO × 16, Timer + IRQ, UART (RX+TX), SPI
- 仿真: 116 项检查全部 PASS (CPU 综合/运算/异常, ALU/MU 专项, 总线/外设测试)

## 目录结构

```
dev/
├── rtl/                  # 所有 RTL 源文件
│   ├── ALU/              # ALU 模块 (12 文件)
│   ├── MU/               # 乘除法器 (3 文件)
│   ├── core/             # CPU 核心 (21 文件)
│   ├── AHB-lite/         # AHB-Lite 总线 (8 文件 + ip/)
│   ├── APB/              # APB 总线及外设 (10 文件 + header/ + perips/)
│   └── system_top.v      # 系统顶层
├── tb/                   # 所有 testbench
│   ├── ALU/              # ALU 专项测试
│   ├── tb_simple_cpu_top.v   # CPU 全功能测试 (34 PASS)
│   ├── tb_ahb_bus.v          # AHB 总线测试 (3 PASS)
│   ├── tb_apb_perips.v       # APB 外设测试 (10 PASS)
│   ├── tb_led_marquee.v      # LED 走马灯测试
│   ├── tb_uart_hello.v       # UART 发送测试
│   └── lcd_module_stub.v     # LCD 仿真 stub
├── fpga/                 # FPGA 约束与 IP
│   ├── cpu.xdc           # 引脚约束
│   ├── lcd_module.dcp    # LCD 预编译 IP
│   └── QUICK_REF.md      # ALU 控制信号速查
├── program_source/       # 测试程序 (.s / .hex / .coe)
├── docs/                 # 设计文档
│   ├── simpleCPU-design-report.md
│   ├── core/             # ISA, 异常中断, 项目描述
│   ├── alu/              # ALU 设计, 接口, 多周期握手
│   ├── AHB-lite/         # AHB-Lite 协议规范
│   └── APB/              # APB 协议规范
├── PLAN.md
└── PROCESS.md
```

## 优化目标

### P1 — PLIC (平台级中断控制器) 与 mtime 体系集成，及外设中断接入

**目标**: 实现符合 RISC-V 标准的 PLIC 模块（作为 AHB-Lite 从设备）及标准的 `mtime` 定时器体系。明确中断信号连线与总线 MMIO 访问的分离，将所有外设中断接入 PLIC。

**详细计划**:

1. **PLIC 核心逻辑设计与实现**
   - **中断网关 (Interrupt Gateway)**: 处理各个中断源的触发信号（电平/边沿），生成单一的挂起请求 (IP)。
   - **寄存器与内存映射**: 实现 32 位宽原子访问的寄存器，包括：优先级、挂起位、使能位、优先级阈值、Claim / Complete。

2. **总线接口与独立中断信号线**
   - **AHB-Lite 从设备封装**: 将 PLIC 封装为 **AHB-Lite 从设备**。PLIC 需要较大的地址空间，直接挂载在 AHB 总线上更为合理。总线仅用于 **MMIO 寄存器读写**。
   - **独立中断通知线**: PLIC 产生的全局外部中断通知 (`eip`) 通过**专用硬件信号线**直接连接到 CPU 核心的 `ext_meip` 引脚，不经过总线。

3. **外设中断接入与 MTIP 剥离**
   - **专用中断信号线**: 将外设 (UART, SPI, GPIO 等) 的中断请求信号通过**专用硬件连线**汇总到 PLIC 的全局中断输入端。
   - **Timer 中断分离**: 现有的外设 Timer 不再直接连接 CPU 的 MTIP。它的中断将作为普通的外部中断接入 PLIC。
   - **建立 mtime 体系 (CLINT)**: 根据 RISC-V 规范，实现专用的内存映射定时器 (`mtime` 和 `mtimecmp` 寄存器) 来生成真正的 `MTIP` (Machine Timer Interrupt) 和 `MSIP` (Machine Software Interrupt)，通常由 CLINT (Core Local Interruptor) 模块负责，并作为 AHB-Lite 从设备或映射在特定地址。

4. **CPU 核心侧修改**
   - **中断引脚对接**: 对接 PLIC 输出的 `eip` 到 `ext_meip`。对接 CLINT 输出的 `timer_irq` 到 `ext_mtip`，`soft_irq` 到 `ext_msip`。
   - **中断优先级与仲裁验证**: 确保 `cpu_clint` 中严格遵循规范 (`MEI > MSI > MTI`) 的降序优先级逻辑。

5. **仿真验证与系统测试**
   - 编写 PLIC 与 CLINT (mtime) 模块级 Testbench。
   - 更新系统级集成测试：验证 MMIO 读写配置 PLIC/CLINT，验证外设通过硬件线触发 PLIC 到 CPU 的外部中断，验证 mtime 到 MTIP 的中断触发，以及 MRET 退出流程。

### P2 — 远期

- [ ] **MMU 实现**: 当前 paddr=vaddr 直通，接口已预留，可扩展为简单 SV32 页表
- [ ] **中断优先级完善**: 当前 MEIP > MSIP，需补充完整优先级 MSIP > MTIP > MEIP
- [ ] **mtvec Vectored 模式**: 当前仅 Direct 模式，可扩展 Vectored 异常向量
- [ ] **Cache 容量扩展**: 4KB direct-mapped (12-bit index)，≥16KB 地址别名问题需解决
- [ ] **FPGA 构建自动化**: 当前 Vivado 项目需手动创建，可编写 TCL 脚本自动化综合/实现/比特流生成

## 已知限制

| 限制 | 说明 |
|------|------|
| MMU 直通 | paddr=vaddr，无虚拟内存 |
| 仅 Machine 模式 | 无 Supervisor 模式，无委托 |
| 无中断嵌套 | 单级中断控制，无可编程优先级 |
| FENCE/FENCE.I 为 NOP | 单 hart 无乱序，无需缓存一致性 |
| mtvec 仅 Direct | Vectored 模式未实现 |
| Cache 别名 | 4KB direct-mapped, ≥16KB 地址回绕别名 |
| 无 A/F/D/C 扩展 | 无原子/浮点/双精度/压缩指令 |

## 地址映射

| 地址范围 | 总线 | 从设备 |
|----------|------|--------|
| 0x00000000 - 0x7FFFFFFF | AHB-Lite | SRAM (1MB BRAM) |
| 0x80000000 - 0x8000FFFF | APB | GPIO (16-bit) |
| 0x80004000 - 0x80007FFF | APB | Timer (+IRQ) |
| 0x80008000 - 0x8000BFFF | APB | UART (RX+TX) |
| 0x8000C000 - 0x8000FFFF | APB | SPI |

> bit31=0 访问本地 BRAM Cache，bit31=1 绕过 Cache 直接到 AHB-Lite 总线 (MMIO)

## 参考资料

| 资料名称           | 内容简介                       | 路径                                      |
|--------------------|-------------------------------|-------------------------------------------|
| AHB-Lite 规范      | AMBA AHB-Lite 总线协议         | dev/docs/AHB-lite/AMBA_AHB-Lite_Spec_Summary.md |
| APB 规范           | AMBA APB 总线协议              | dev/docs/APB/AMBA_APB_Spec_Summary.md     |
| RISC-V 特权架构(M)    | RISC-V M特权级架构说明          | dev/docs/core/riscv-m-privilege-spec.typ  |
| RISC-V PLIC        | RISC-V 平台级中断控制器        | dev/docs/core/riscv-plic.md               |
| RISC-V 高级中断     | RISC-V 高级异常/中断机制       | dev/docs/core/exception-interrupt.md      |
| RISC-V 指令集      | 指令集定义/支持情况            | dev/docs/core/instruction-set.md          |
| RISC-V IOMMU       | RISC-V IOMMU 相关说明          | dev/docs/core/riscv-iommu.md              |
| RISC-V PLIC 参考   | PLIC 参考实现/寄存器           | dev/docs/core/riscv-plic-ref.md           |
| RISC-V M 扩展      | 乘除法扩展说明                 | dev/docs/core/rv32-m.md                   |
| ALU 接口           | ALU 接口定义                   | dev/docs/alu/ALU_INTERFACE.md             |
| MU 接口            | 乘除法单元接口                 | dev/docs/alu/MU_INTERFACE.md              |
| 设计报告           | 系统设计报告                    | dev/docs/simpleCPU-design-report.md        |
| 其它文档           | 其它相关设计/实现文档            | dev/docs/                                  |

## 工具链

| 工具 | 路径 | 用途 |
|------|------|------|
| mk.py | `tools/mk.py` | iverilog 编译 + vvp 仿真，自动依赖解析 |
| rv2coe.py | `tools/rv2coe.py` | RISC-V 源码编译为 COE/HEX/BIN |
| vivado_sim.tcl | `vivado_sim.tcl` | Vivado 仿真自动化 (创建工程/添加源/配置IP/启动仿真) |
| tcl-tunnel | `tools/tcl-tunnel/` | 远程 Vivado TCL 执行 (HTTP 服务) |
| Makefile | `dev/program_source/Makefile` | 测试程序编译 (.s → .hex) |

## 文档索引

| 文档 | 路径 |
|------|------|
| 系统设计报告 | `dev/docs/simpleCPU-design-report.md` |
| 指令集定义 | `dev/docs/core/instruction-set.md` |
| 异常/中断机制 | `dev/docs/core/exception-interrupt.md` |
| ALU 设计 | `dev/docs/alu/ALU_DESIGN.md` |
| ALU 接口 | `dev/docs/alu/ALU_INTERFACE.md` |
| MU 接口 | `dev/docs/alu/MU_INTERFACE.md` |
| AHB-Lite 规范 | `dev/docs/AHB-lite/AMBA_AHB-Lite_Spec_Summary.md` |
| APB 规范 | `dev/docs/APB/AMBA_APB_Spec_Summary.md` |
| FPGA 引脚速查 | `dev/fpga/QUICK_REF.md` |
| mk.py 使用说明 | `tools/README-mk.md` |
| rv2coe.py 使用说明 | `tools/program_source_usage.md` |
