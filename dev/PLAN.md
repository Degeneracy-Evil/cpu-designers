# simpleCPU 优化计划

## 项目概述

RISC-V RV32I + Zicsr 多周期处理器，5 级流水线 (IF→ID→EXE→MEM→WB)，
AHB-Lite + APB 两级总线架构，目标 Xilinx 7 系列 FPGA。

- ISA: 47 条指令 (RV32I 40 + Zicsr 6 + Zifencei 1)
- 8 个 Machine 模式 CSR，异常/中断完整支持
- 外设: GPIO × 16, Timer + IRQ, UART (RX+TX), SPI
- 仿真: 52 项检查全部 PASS

## 目录结构

```
dev/
├── rtl/                  # 所有 RTL 源文件
│   ├── ALU/              # ALU 模块 (12 文件)
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

### P0 — 已完成

- [x] **文件夹重构**: 从 `dev/1-alu/` + `dev/2-simpleCPU/` 扁平化为 `dev/rtl/`, `dev/tb/`, `dev/fpga/`, `dev/program_source/`, `dev/docs/`
- [x] **AHB-Lite + APB 总线架构**: 替换 Bus4LZU mock，实现完整 AMBA 两级总线
- [x] **外设集成**: GPIO, Timer, UART, SPI 通过 APB 总线接入
- [x] **异常/中断处理**: Illegal inst, ECALL, EBREAK, 地址不对齐, MEIP/MTIP/MSIP
- [x] **FPGA 集成**: system_top, XDC 约束, LCD 调试显示, BRAM IP

### P1 — 已完成

- [x] **完全去除 Bus4LZU 风格接口**
  - 删除 `cpu_bus_adapter`，CPU 核心直接输出 AHB-Lite master 信号
  - 3 状态主 FSM（AHB_IDLE→AHB_ADDR→AHB_DATA）替代原 9 状态两级桥接
  - 收益: 减少一级适配延迟，简化数据通路，消除冗余 FSM 状态

- [x] **AHB-Lite 主 FSM 模块化**
  - 从 `simple_cpu_top.v` 提取 AHB-Lite 主设备 FSM 到独立模块 `cpu_bus_bridge.v`
  - `simple_cpu_top.v` 仅实例化 `cpu_bus_bridge`，不再内联总线协议逻辑
  - 收益: 降低 `simple_cpu_top` 复杂度，总线逻辑可独立验证和复用

- [x] **CSR 与 异常/Trap 重构**
  - 从 `simple_cpu_top.v` 提取 CSR 写解码 + 异常检测/注册 + `cpu_csr` + `cpu_clint` 到独立模块 `cpu_trap_csr.v`
  - `simple_cpu_top.v` 仅实例化 `cpu_trap_csr`，移除所有 CSR/异常内联逻辑
  - 收益: `simple_cpu_top` 从 573 行缩减至 439 行，CSR/异常路径可独立验证

- [x] **CSR 与 异常/Trap 进一步拆分**
  - 将 `cpu_trap_csr.v` 拆分为 `cpu_trap_manager`（异常捕获/注册 + `cpu_clint` + trap 决策）和 `cpu_csr_interface`（CSR 读写解码 + 写回总线 + `cpu_csr`）
  - `cpu_trap_csr` 退化为薄包装层，仅做信号连线
  - 收益: CSR 写逻辑与 trap 决策可独立测试，为 vectored mtvec、可编程中断优先级等扩展留出清晰边界

### P1 — 计划中

(暂无)

### P2 — 优化与扩展

- [ ] **ALU 乘除法器独立**
  - 现状: `booth_multiplier` 和 `non_restoring_divider` 嵌入在 `alu_32bit` 内部
  - 目标: 乘法器/除法器作为独立模块（放在MU文件夹下），ALU 变为单周期模块并排除握手逻辑，mem不经过握手逻辑直接调用
  - 收益: 流水线时序优化，加减法等单周期运算CPI更低。
  
- [ ] **RV32M 扩展**:
  - 现状：硬件乘除法器已就绪，
  - 目标：实现M指令集扩展，需在 decode/execute 中添加 M 扩展指令识别

### P2 — 远期

- [ ] **双发射**：将CPU升级为双发射CPU，进一步提升性能 
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
| 无 RV32M | 乘除硬件存在但未接入 ISA 解码 |
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
| AHB-Lite 规范 | `dev/docs/AHB-lite/AMBA_AHB-Lite_Spec_Summary.md` |
| APB 规范 | `dev/docs/APB/AMBA_APB_Spec_Summary.md` |
| FPGA 引脚速查 | `dev/fpga/QUICK_REF.md` |
| mk.py 使用说明 | `tools/README-mk.md` |
| rv2coe.py 使用说明 | `tools/program_source_usage.md` |
