# 06 - 存储与地址映射

## 1. 指令存储（iMem）

- 独立存储模块，仅读
- 按 32 bit 字对齐访问
- 地址空间由实现确定，仿真阶段通过 testbench 初始化

## 2. 数据存储（dMem）

- 独立存储模块，可读可写
- 支持 RV32I 所要求的数据访问类型（byte/halfword/word）
- 地址未对齐时触发对应异常

## 3. MMIO 地址映射

数据存储与外设共享地址空间，通过 `bus_decode` 模块按地址高位译码选择访问目标。

### 3.1 地址空间划分

| 地址范围 | 目标 | 描述 |
|----------|------|------|
| 0x0000_0000 ~ 0x0FFF_FFFF | dMem | 数据存储（256 MB） |
| 0x1000_0000 ~ 0x1000_FFFF | GPIO | GPIO 寄存器空间 |
| 0x1001_0000 ~ 0x1001_FFFF | UART | UART 寄存器空间 |

> 地址译码规则：地址 [31:28] = 0x0 → dMem；[31:16] = 0x1000 → GPIO；[31:16] = 0x1001 → UART。

### 3.2 GPIO 寄存器映射

| 偏移 | 名称 | 读写 | 描述 |
|------|------|------|------|
| 0x00 | gpio_in | RO | GPIO 输入数据（开关/按键） |
| 0x04 | gpio_out | RW | GPIO 输出数据（LED） |
| 0x08 | gpio_dir | RW | GPIO 方向控制（1=输出，0=输入） |

### 3.3 UART 寄存器映射

| 偏移 | 名称 | 读写 | 描述 |
|------|------|------|------|
| 0x00 | uart_tx | WO | 发送数据寄存器（写入触发发送） |
| 0x04 | uart_rx | RO | 接收数据寄存器 |
| 0x08 | uart_status | RO | 状态寄存器（bit0=TX busy, bit1=RX ready） |
| 0x0C | uart_ctrl | RW | 控制寄存器（bit0=RX interrupt enable） |

## 4. 访存对齐规则

| 指令 | 要求 | 违反时异常 |
|------|------|-----------|
| LB / LBU | 无对齐要求 | - |
| LH / LHU | 半字对齐（addr[0] = 0） | Load address misaligned |
| LW | 字对齐（addr[1:0] = 0） | Load address misaligned |
| SB | 无对齐要求 | - |
| SH | 半字对齐（addr[0] = 0） | Store/AMO address misaligned |
| SW | 字对齐（addr[1:0] = 0） | Store/AMO address misaligned |
