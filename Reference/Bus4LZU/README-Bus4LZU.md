# Vivado IP 分析报告: Asyncsys_bus_bus4LZU v1.0

---

## 1. IP 基本信息

| 属性 | 值 |
|------|-----|
| **IP 名称** | bus4LZU (显示名: simple_bus) |
| **Vendor** | Asyncsys |
| **Library** | bus |
| **版本** | 1.0 |
| **描述** | A bus ip written by Dump Cheung |
| **语言** | Verilog |
| **顶层模块** | `soc_top` |
| **Vivado 版本** | 2019.1 |
| **创建日期** | 2025-03-29 |
| **分类** | /UserIP |

---

## 2. 可配置参数

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| `CLK_FREQ` | 25 | 1~100 | 系统时钟频率 (MHz) |
| `GPIO_NUM` | 16 | 1~16 | GPIO 引脚数量 |

---

## 3. 接口与端口

### 3.1 总线接口

| 接口名 | 类型 | 角色 | 说明 |
|--------|------|------|------|
| `clk` | clock | Slave | 系统时钟输入 |
| `rstn` | reset | Slave | 异步复位，**低电平有效** |
| `spi_clk` | clock | Master | SPI 时钟输出 |

### 3.2 外部端口

| 端口 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `clk` | in | 1 | 系统时钟 |
| `rstn` | in | 1 | 异步复位 (低有效) |
| `rx` | in | 1 | UART 接收 |
| `tx` | out | 1 | UART 发送 |
| `timer_iqr` | out | 1 | 定时器中断 |
| `init_sig` | out | 1 | 初始化阶段指示信号 |
| `spi_miso` | in | 1 | SPI 主入从出 |
| `spi_mosi` | out | 1 | SPI 主出从入 |
| `spi_ss` | out | 1 | SPI 从设备片选 |
| `spi_clk` | out | 1 | SPI 时钟 |
| `gpio_io` | inout | GPIO_NUM | GPIO 双向引脚 |
| `instAddr_32` | in | 32 | 指令地址 (CPU ICache) |
| `instData_32` | out | 32 | 指令数据 (ICache 读出) |
| `dataWen_4` | in | 4 | 数据写使能 (字节级) |
| `dataAddr_32` | in | 32 | 数据地址 (CPU DCache) |
| `writeData_32` | in | 32 | 写入数据 |
| `readData_32` | out | 32 | 读出数据 |

---

## 4. 系统架构

### 4.1 顶层结构 (`soc_top`)

```
                    ┌─────────────────────────────────────────────┐
                    │                soc_top                       │
                    │                                              │
  instAddr_32 ──────►┐         ┌──────────────┐                   │
  instData_32 ◄──────┤         │ memory_slot  │                   │
                    │         │              │                   │
  dataAddr_32 ──────►┤  slot  │  ICache(Sram)│◄── init_sig=1    │
  writeData_32 ─────►┤ _data  │  DCache(Sram)│    时UART初始化   │
  dataWen_4 ────────►┤  ───►  │              │                   │
  readData_32 ◄──────┤         │  data_init   │──► init_tx/rx   │
                    │         └──────────────┘                   │
                    │                │                            │
                    │                ▼                            │
                    │         ┌──────────────┐                   │
                    │         │   bus_top    │                   │
                    │         │              │                   │
  rx ───────────────►┤         │ ┌──────────┐ │                   │
  tx ◄───────────────┤         │ │addr_dec  │ │                   │
  spi_miso ──────────►┤         │ └──────────┘ │                   │
  spi_mosi ◄──────────┤         │ ┌──────────┐ │                   │
  spi_ss ◄────────────┤         │ │slave_mux │ │                   │
  spi_clk ◄───────────┤         │ └──────────┘ │                   │
  gpio_io ◄───────────►┤         │              │                   │
  timer_iqr ◄─────────┤         │ UART|GPIO|   │                   │
                    │         │ Timer|SPI    │                   │
                    │         └──────────────┘                   │
                    └─────────────────────────────────────────────┘
```

### 4.2 三大子系统

| 模块 | 实例名 | 说明 |
|------|--------|------|
| `slot_data` | slot_data | 数据通路多路选择器，判断地址走内存还是总线 |
| `memory_slot` | memory | 存储子系统 (ICache + DCache + 初始化逻辑) |
| `bus_top` | bus | 总线顶层 (地址译码 + 从设备多路选择 + 外设) |

---

## 5. 总线架构 (`bus_top`)

### 5.1 总线协议

- **单主设备**总线 (CPU 侧)
- 信号: `addr[31:0]`, `as_` (地址选通, 低有效), `rw` (1=读, 0=写), `wrData[31:0]`, `rdData[31:0]`, `rdy_` (就绪, 低有效)
- 仲裁器已注释掉，当前为单主直连

### 5.2 地址映射

| 从设备 | 地址范围 | 大小 | 片选 |
|--------|----------|------|------|
| **UART** (Slave 1) | `0x00010000` ~ `0x0001FFFF` | 64 KB | `cs1_` |
| **GPIO** (Slave 2) | `0x00020000` ~ `0x0002FFFF` | 64 KB | `cs2_` |
| **Timer** (Slave 3) | `0x00040000` ~ `0x0004FFFF` | 64 KB | `cs3_` |
| **SPI** (Slave 4) | `0x00080000` ~ `0x0008FFFF` | 64 KB | `cs4_` |
| **内存** (地址 < `0x00010000`) | `0x00000000` ~ `0x0000FFFF` | 64 KB | 直接访问 SRAM |

### 5.3 地址译码器 (`bus_addr_decoder`)

根据地址高位判断目标从设备，生成片选信号 (低有效)。

### 5.4 从设备多路选择器 (`bus_slave_mux`)

根据片选信号选择对应从设备的读数据和就绪信号输出。

---

## 6. 数据通路 (`slot_data` / `data_mux`)

判断 CPU 数据访问地址是否 > `0xFFFF`：
- **地址 > 0xFFFF**: 走总线 (访问外设)，`busAs_=0` 有效，根据 `dataWen_4` 判断读/写
- **地址 <= 0xFFFF**: 走内存 (SRAM)，直接访问 DCache

读数据选择: 地址 > 0xFFFF 返回总线数据，否则返回内存数据。

---

## 7. 存储子系统 (`memory_slot`)

### 7.1 SRAM 配置 (Xilinx blk_mem_gen v8.4)

| 参数 | 值 |
|------|-----|
| 类型 | Single Port RAM |
| 深度 | 8192 |
| 位宽 | 32 bit |
| 容量 | 32 KB (每块) |
| BRAM 资源 | 8 x BRAM36K (每块) |
| 地址宽度 | 13 bit |
| 写使能 | 字节级 (4 bit WEA) |
| 读延迟 | 1 周期 |

- **ICache**: `Sram` 实例，地址取 `[14:2]` (字对齐)
- **DCache**: `Sram` 实例，地址取 `[14:2]` (字对齐)

### 7.2 初始化与正常模式切换

`init_sig` 信号控制：
- **init_sig = 1** (初始化阶段): UART 接收数据写入 ICache/DCache
- **init_sig = 0** (正常阶段): CPU 直接访问 ICache/DCache

---

## 8. 初始化模块 (`data_init`)

### 8.1 功能

通过 UART 串口接收数据包，写入 ICache 和 DCache，支持 CRC-16 校验。

### 8.2 协议

| 项目 | 说明 |
|------|------|
| 波特率 | 115200 |
| 数据包格式 | 序号(1B) + 数据(128B) + CRC(2B) = 131 Byte |
| CRC 算法 | CRC-16 (多项式 0xA001) |
| 应答 | ACK (0x06) / NAK (0x15) |

### 8.3 状态机

```
IDLE → NUM → DATA0 → DATA1 → DATA2 → DATA3 → SEND → CRC1 → CRC_START → CRC_CALC → CRC_END → SENDRSP → WAITSEND → NUM...
```

- `NUM`: 接收包序号，`0x00` 表示 ICache 数据，`0xFF` 表示 DCache 数据
- `DATA0~3`: 拼接 4 字节成 32bit 字
- `SEND`: 写入 ICache 或 DCache
- `CRC1/CRC_START/CRC_CALC`: CRC-16 校验计算
- `SENDRSP`: 发送 ACK/NAK

### 8.4 初始化完成条件

当 `first == size` 且 `number == 0xFF` 且状态为 `WAITSEND` 时，`init_sig` 拉低，进入正常工作模式。

---

## 9. 外设模块

### 9.1 UART (`uart_top`)

| 寄存器 | 偏移地址 | 说明 |
|--------|----------|------|
| `UART_CTRL` | `0x00` | bit[0]: TX 使能, bit[1]: RX 使能 |
| `UART_STATUS` | `0x04` | bit[0]: TX 忙, bit[1]: RX 数据就绪 |
| `UART_TXDATA` | `0x08` | 发送数据 [7:0] |
| `UART_RXDATA` | `0x0C` | 接收数据 [7:0] |

- 波特率: 115200 (固定)
- 全双工，内部例化 `uart_rx` + `uart_tx`
- 状态机: IDLE → START → REC/SEND_BYTE → STOP → DATA

### 9.2 GPIO (`gpio`)

| 寄存器 | 偏移地址 | 说明 |
|--------|----------|------|
| `GPIO_CTRL` | `0x0` | bit[i]=1: 输出模式, bit[i]=0: 输入模式 |
| `GPIO_DATA` | `0x4` | 数据寄存器 |

- 输出模式: `gpio_ctrl[i]=1` 时，`io_pin[i] = gpio_data[i]`
- 输入模式: `gpio_ctrl[i]=0` 时，`gpio_data[i] = io_pin[i]`
- 最多 16 个引脚 (可配置)

### 9.3 Timer (`timer`)

| 寄存器 | 偏移地址 | 说明 |
|--------|----------|------|
| `TIMER_CTRL` | `0x0` | bit[0]: 启动, bit[1]: 模式 (0=单次, 1=周期) |
| `TIMER_INTR` | `0x1` | bit[0]: 中断标志 |
| `TIMER_EXPR` | `0x2` | 比较值 (到期值) |
| `TIMER_COUNTER` | `0x3` | 当前计数值 |

- 单次模式: 计数到 `expr_val` 后停止，`start` 自动清零
- 周期模式: 计数到 `expr_val` 后归零重新计数
- 到期时产生中断 `irq`

### 9.4 SPI (`spi`)

| 寄存器 | 偏移地址 | 说明 |
|--------|----------|------|
| `SPI_CTRL` | `0x0` | bit[0]: 使能, bit[1]: CPOL, bit[2]: CPHA, bit[3]: 片选, bit[15:8]: 分频 |
| `SPI_DATA` | `0x4` | bit[7:0]: 发送/接收数据 |
| `SPI_STATUS` | `0x8` | bit[0]: 忙标志 |

- 支持 CPOL/CPHA 配置 (Mode 0/1/2/3)
- 可编程时钟分频: `div_cnt = spi_ctrl[15:8]`，分频系数 = (div_cnt+1)*2
- 片选: `spi_ss = ~spi_ctrl[3]`，低有效
- 8-bit 数据收发，MSB 优先

---

## 10. UART 收发底层模块

### `uart_rx`
- 检测起始位下降沿启动接收
- 状态机: IDLE → START → REC_BYTE → STOP → DATA
- 中点采样，8-bit 数据

### `uart_tx`
- 状态机: IDLE → START → SEND_BYTE → STOP
- 标准 UART 帧格式: 1 起始位 + 8 数据位 + 1 停止位

---

## 11. 文件清单

| 路径 | 类型 | 说明 |
|------|------|------|
| `sources_1/new/soc_core.v` | Verilog | 顶层模块 |
| `sources_1/new/slot/bus_top.v` | Verilog | 总线顶层 |
| `sources_1/new/slot/bus_addr_decoder.v` | Verilog | 地址译码器 |
| `sources_1/new/slot/bus_slave_mux.v` | Verilog | 从设备多路选择 |
| `sources_1/new/slot/data_mux.v` | Verilog | 数据通路多路选择 |
| `sources_1/new/slot/data_init.v` | Verilog | UART 初始化模块 |
| `sources_1/new/slot/memory_slot.v` | Verilog | 存储子系统 |
| `sources_1/new/perips/uart_top.v` | Verilog | UART 控制器 |
| `sources_1/new/perips/uart_rx.v` | Verilog | UART 接收 |
| `sources_1/new/perips/uart_tx.v` | Verilog | UART 发送 |
| `sources_1/new/perips/gpio.v` | Verilog | GPIO 控制器 |
| `sources_1/new/perips/timer.v` | Verilog | 定时器 |
| `sources_1/new/perips/spi.v` | Verilog | SPI 控制器 |
| `sources_1/new/header/bus_define.vh` | Header | 总线宏定义 |
| `sources_1/new/header/timer_define.vh` | Header | 定时器宏定义 |
| `sources_1/ip/Sram/Sram.xci` | XCI | Block Memory Generator (8Kx32) |
| `xgui/bus4LZU_v1_0.tcl` | TCL | IP GUI 配置脚本 |
| `sim_1/imports/.../soc_test_all_dc_behav.wcfg` | WCFG | 仿真波形配置 |

---

## 12. 支持 FPGA 系列

7 系列: Artix7, Kintex7, Virtex7, Zynq, Spartan7 及其变体
UltraScale: VirtexU, KintexU
UltraScale+: ZynqUltraScale+, VirtexUltraScale+, KintexUltraScale+, VirtexUltraScale+HBM 等

---

## 13. 使用方式

1. **作为 Vivado IP 集成**: 将此 IP 目录添加至 Vivado IP Repository，在 Block Design 或 RTL 中例化 `bus4LZU_v1_0`
2. **连接 CPU**: 将 CPU 的指令接口连接到 `instAddr_32`/`instData_32`，数据接口连接到 `dataAddr_32`/`writeData_32`/`readData_32`/`dataWen_4`
3. **初始化**: 上电后 `init_sig=1`，通过 UART (rx/tx) 发送带 CRC 校验的数据包加载指令和数据存储器；加载完成后 `init_sig=0`，CPU 开始正常执行
4. **外设访问**: CPU 通过数据接口访问地址 `0x10000+` 区域即可操作 UART/GPIO/Timer/SPI
5. **参数配置**: 在 Vivado IP Customization GUI 中设置时钟频率和 GPIO 数量
