# Simple CPU FPGA 调试使用说明

## 概述

`simple_cpu_display.v` 是简单CPU的FPGA调试显示模块，通过触摸屏展示CPU运行状态，并支持查询dcache任意地址的数据。

## 硬件连接

| 外设 | 引脚 | 信号 | 说明 |
|------|------|------|------|
| 100MHz时钟 | AC19 | clk | 系统主时钟 |
| 复位按键 | Y3 | resetn | 低电平复位 |
| 断点调试按键 | Y5 | btn_clk | 单步时钟脉冲 |
| SW0 | AC21 | sw[0] | 拨码开关 |
| SW1 | AD24 | sw[1] | 拨码开关 |
| SW2 | AC22 | sw[2] | 拨码开关 |
| SW3 | AC23 | sw[3] | 拨码开关 |
| SW4 | AB6 | sw[4] | 拨码开关 |
| SW5 | W6 | sw[5] | 拨码开关 |
| SW6 | AA7 | sw[6] | 拨码开关 |
| SW7 | Y6 | sw[7] | 拨码开关 |
| 触摸屏 | - | lcd_* / ct_* | LCD显示与触摸输入 |

## 操作方式

### 单步执行

按下 `btn_clk`（SW_STEP0按键）产生一个时钟脉冲，CPU执行一步。每次按下只推进一个CPU时钟周期，便于逐条指令调试。

### 复位

按下复位按键（低电平有效），CPU复位到初始状态，PC归零，所有寄存器清零，流水线总线清空。

### 查询dcache数据

在触摸屏上输入一个32位地址值，该地址会写入 `mem_addr`，dcache端口B会读出该地址对应的数据并在触摸屏的 `MDATA` 区域显示。地址按字对齐，实际访问dcache的 `addrb = mem_addr[12:2]`。

### 拨码开关

8位拨码开关 SW0-SW7 的状态实时显示在触摸屏第44号区域（SW），值为8位无符号数，高24位补零。拨码开关当前仅用于状态展示，不影响CPU运行逻辑。

## 触摸屏显示布局

触摸屏共有44块显示区域，编号1~44，内容如下：

| 编号 | 名称 | 含义 |
|------|------|------|
| 1 | IF_PC | 取指阶段PC |
| 2 | IF_IN | 取指阶段指令 |
| 3 | ID_PC | 译码阶段PC |
| 4 | EXEPC | 执行阶段PC |
| 5 | MEMPC | 访存阶段PC |
| 6 | MEMIN | 访存阶段指令 |
| 7 | WB_PC | 回写阶段PC |
| 8 | WB_IN | 回写阶段指令 |
| 9 | MADDR | 当前观察的内存地址（由触摸屏输入） |
| 10 | MDATA | MADDR对应的dcache数据 |
| 11 | REG00 | 寄存器x0（恒为0） |
| 12 | REG01 | 寄存器x1（ra） |
| ... | ... | ... |
| 42 | REG31 | 寄存器x31 |
| 43 | STATE | CPU FSM当前状态 |
| 44 | SW | 拨码开关SW[7:0]状态 |

### FSM状态编码（STATE字段）

| 值 | 状态 |
|----|------|
| 0 | IDLE |
| 1 | FETCH |
| 2 | DECODE |
| 3 | EXEC |
| 4 | MEM |
| 5 | WB |

## Vivado工程配置

1. 顶层模块设为 `simple_cpu_display`
2. 添加约束文件 `cpu.xdc`
3. 添加 `lcd_module.dcp` 作为IP核
4. 添加 `rtl/` 下所有 `.v` 文件（`simple_cpu_top.v` 及各子模块）
5. 添加 `fpga/simple_cpu_display.v`

## 文件清单

```
fpga/
├── simple_cpu_display.v   # 显示顶层模块
├── cpu.xdc                # FPGA引脚约束
└── lcd_module.dcp         # 触摸屏IP核
```
