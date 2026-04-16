# 06 - 存储与地址映射

## 1. 指令存储（iMem）

- 由 `instr_mem` 模块实现，内部使用 `bram` 作为 L1 iCache 存储体
- 独立于数据侧存储，仅用于取指
- 按 32 bit 字访问（字地址为 `pc[ADDR_WIDTH+1:2]`）
- 仿真阶段可通过 `INIT_FILE` 初始化指令镜像

## 2. 数据存储（dMem）

- 由 `data_mem` 模块实现，内部使用 `bram` 作为 L1 dCache 存储体
- 可读可写，CPU 主访问端口使用握手信号：`req/ready/rvalid/wdone`
- 支持 RV32I 所要求的数据访问类型（byte/halfword/word）
- 写掩码由 `wstrb[3:0]` 表示字节粒度写使能
- 额外提供显示/调试读端口（B 口）用于外部观测内存

### 2.1 dCache BRAM 端口映射

`data_mem` 内部 BRAM 端口与 CPU 信号映射关系如下：

| BRAM 端口 | 对应信号 | 说明 |
|-----------|----------|------|
| `clka` | `clk` | CPU 访问时钟 |
| `wea` | `req && write_en ? wstrb : 4'b0` | A 口写使能 |
| `addra` | `addr[ADDR_WIDTH+1:2]` | A 口字地址 |
| `dina` | `wdata` | A 口写数据 |
| `douta` | `rdata` 通路 | A 口读数据 |
| `clkb` | `clk` | 显示读端口时钟 |
| `web` | `4'b0` | B 口当前不写 |
| `addrb` | `mem_addr[ADDR_WIDTH+1:2]` | 显示读地址 |
| `dinb` | `32'b0` | B 口写数据固定 0 |
| `doutb` | `mem_data` | 显示读数据 |

## 3. MMIO 地址映射

数据侧地址空间最终将由 `bus_decode` 在 dCache 与外设 MMIO 间译码选择。
当前阶段尚未接入外设总线，CPU 访存默认落在 dCache。

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
