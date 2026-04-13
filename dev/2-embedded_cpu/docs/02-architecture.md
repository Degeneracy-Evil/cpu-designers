# 02 - 架构选型

## 1. ISA

- **基础指令集**：RISC-V RV32I
- **CSR 扩展**：Zicsr
- **指令缓存扩展**：Zifencei（FENCE.I 作为 NOP）
- 普通指令行为参考 RISC-V 非特权手册
- 异常、中断、trap 机制参考 RISC-V 特权手册（精简子集）

## 2. 微结构

- **结构**：哈佛结构，指令存储与数据存储分离
- **控制方式**：多周期 FSM
- **数据位宽**：32 bit
- **特权模式**：M-mode + U-mode（不实现 S-mode）

## 3. 存储结构

- 两块独立存储模块：
  - `iMem`：指令存储
  - `dMem`：数据存储
- 均按 32 bit 字对齐访问
- dMem 地址空间通过地址译码区分内存与外设（MMIO）

## 4. ALU

- 复用 `dev/1-alu` 中自研 32 bit ALU
- ALU 控制信号为 16 bit one-hot 编码（详见 `dev/1-alu/AGENTS.md`）
- 通过 `alu_wrapper` 模块对接 ALU 接口与 CPU 数据通路

## 5. 外设与中断

- 外设：GPIO + UART
- 中断：一级外部中断，优先 UART RX 中断
- 外设接入方式：Memory-Mapped I/O（MMIO）
