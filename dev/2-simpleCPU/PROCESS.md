# PROCESS — dev/2-simpleCPU

## 2026-05-02 Vivado unpacked array port 兼容性修复

### 问题

Vivado xvlog 编译报错：

```
ERROR: [VRFC 10-3642] port 'slave_HRDATA' must not be declared to be an array [ahb_mux.v:9]
```

Vivado 的 Verilog 编译器不支持将 unpacked array 作为模块端口。
Iverilog 通过 `-g2005-sv` 支持，但 Vivado 不支持。

### 根因

`ahb_mux.v` 第 9 行声明了 unpacked array 端口：

```verilog
input wire [DATA_WIDTH-1:0] slave_HRDATA [0:SLAVE_NUM-1],
```

### 修复方案

将 unpacked array 端口展平为 packed vector，使用 `+:` 部分选择运算符索引。

#### 1. ahb_mux.v

| 项目 | 修改前 | 修改后 |
|------|--------|--------|
| 端口声明 | `[DATA_WIDTH-1:0] slave_HRDATA [0:SLAVE_NUM-1]` | `[DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA` |
| 内部访问 | `slave_HRDATA[i]` | `slave_HRDATA[i*DATA_WIDTH +: DATA_WIDTH]` |

#### 2. ahb_periph_bus.v

- 新增 `wire [DATA_WIDTH-1:0] sram_HRDATA;` 作为 SRAM slave HRDATA 输出中间线网
- `slave_HRDATA` 改为 packed vector：`wire [DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA;`
- 拼接赋值：`assign slave_HRDATA = {bridge_HRDATA, sram_HRDATA};`
- SRAM slave 端口连接：`.HRDATA(sram_HRDATA)` 替代 `.HRDATA(slave_HRDATA[0])`
- 删除 `assign slave_HRDATA[1] = bridge_HRDATA;`

#### 3. ahb_bus.v (deprecated)

- `slave_HRDATA` 改为 packed vector
- 新增 generate 块创建中间线网 `gen_hrdata[g].hrdata` 并赋值到对应 slice
- SRAM slave / default slave 端口连接改为 `gen_hrdata[g].hrdata`

### 回归验证

全部 8 个 testbench 通过（iverilog + `--exclude Reference`）：

| Testbench | Pass | Fail |
|-----------|------|------|
| tb_simple_cpu_top | 33 | 0 |
| tb_ahb_bus | 3 | 0 |
| tb_apb_perips | 10 | 0 |
| tb_cpu_bus_adapter | 6 | 0 |

## 2026-05-02 SLL/SRL/SRA 寄存器移位指令 Bug 修复

### 问题

LED marquee 程序写入 GPIO_DATA 的值始终为 `0xFFFFFFFF`，而非预期的 `~(1 << position)` 序列。

### 根因

`cpu_decode.v` 第 218 行，对寄存器移位指令（SLL/SRL/SRA），`alu_src1` 被错误赋值为 `{27'b0, rs2_value[4:0]}`（移位量），而非 `rs1_value`（被移位数据）。

ALU 移位器接口为 `shifter(.data(src1), .shamt(src2[4:0]), ...)`，因此 `src1` 必须是被移位的值，`src2[4:0]` 是移位量。

原代码将移位量同时放入 `src1` 和 `src2`，导致移位器对移位量本身进行移位，结果恒为 0。

### 修复

```verilog
// 修改前
assign alu_src1 = shift_op_r ? {27'b0, rs2_value[4:0]} :
       (shift_op_r | shift_op_i) ? rs1_value : ...

// 修改后
assign alu_src1 = (shift_op_r | shift_op_i) ? rs1_value :
       (inst_auipc | inst_jal | is_branch) ? pc : ...
```

### 回归验证

全部 testbench 通过：

| Testbench | 结果 |
|-----------|------|
| tb_simple_cpu_top | PASS (33/33) |
| tb_ahb_bus | PASS |
| tb_apb_perips | PASS (10/10) |
| tb_alu_cpu_integration | PASS (12/12) |
| tb_led_marquee | PASS (16/16) |

## 2026-05-02 LED marquee 仿真验证通过

### 测试内容

`tb_led_marquee.v` 验证 LED marquee 程序在 GPIO 上产生正确的逐位点亮序列：

| Step | gpio_io | 点亮 LED |
|------|---------|----------|
| 0 | 0xFFFE | LED1 |
| 1 | 0xFFFD | LED2 |
| 2 | 0xFFFB | LED3 |
| 3 | 0xFFF7 | LED4 |
| 4 | 0xFFEF | LED5 |
| 5 | 0xFFDF | LED6 |
| 6 | 0xFFBF | LED7 |
| 7 | 0xFF7F | LED8 |
| 8 | 0xFEFF | LED9 |
| 9 | 0xFDFF | LED10 |
| 10 | 0xFBFF | LED11 |
| 11 | 0xF7FF | LED12 |
| 12 | 0xEFFF | LED21 |
| 13 | 0xDFFF | LED22 |
| 14 | 0xBFFF | LED23 |
| 15 | 0x7FFF | LED24 |

16/16 PASS，每个步骤间隔 5186 时钟周期。

## 2026-05-02 GPIO 多驱动修复 (DRC MDRV-1)

### 问题

Vivado DRC 报错：
```
[DRC MDRV-1] Multiple Driver Nets: Net .../u_gpio/Q[0] has multiple drivers:
  .../gen_io_data[0].gpio_data_reg[0]/Q and .../gpio_data_reg[0]/Q
```

### 根因

`gpio.v` 中 `gpio_data` 寄存器被两个 always 块同时驱动：
1. 主 always 块：GPIO_DATA 写访问时写入整个 `gpio_data`
2. generate 块：按位写入 `gpio_data[i]`（输出模式写 PWDATA，输入模式采样引脚）

Verilog 中同一 reg 的同一位被多个 always 块驱动属于多驱动冲突，综合工具无法解析。

### 修复

将 `gpio_data` 拆分为两个独立寄存器，每个寄存器由唯一的 always 块驱动：

| 寄存器 | 位宽 | 驱动者 | 用途 |
|--------|------|--------|------|
| `gpio_data_lo` | GPIO_NUM | generate 块 | 引脚连接位，含输入/输出模式逻辑 |
| `gpio_data_hi` | APB_DATA_WIDTH-GPIO_NUM | 主 always 块 | 非引脚位，简单寄存器写入 |

组合输出：`wire gpio_data = {gpio_data_hi, gpio_data_lo}`

generate 块逻辑改为 `else if` 结构，消除同一时钟沿两个分支同时执行的可能：
- 输出模式 (`gpio_ctrl[i]=1`) 且写 GPIO_DATA → 写入 PWDATA[i]
- 输入模式 (`gpio_ctrl[i]=0`) → 采样 io_gpioPin[i]
- 输出模式且无写访问 → 保持原值

### 回归验证

全部 testbench 通过（同上表）。

### 注意事项

- Vivado 仿真需确保 xvlog 使用 SystemVerilog 模式（`.sv` 后缀或 `-sv` 标志）以支持 `+:` 运算符；
  或直接使用 Verilog-2001 模式（`+:` 属于 Verilog-2001 标准部分选择，Vivado 默认支持）
- `+:` 部分选择运算符属于 Verilog-2001 标准，无需 SystemVerilog 扩展

## 2026-05-04 全项目代码质量优化

### 概述

对 dev/1-alu/ 和 dev/2-simpleCPU/ 全部 RTL 文件进行代码质量审查，识别 56 项问题（2 个 Bug、14 项死代码、8 项冗余逻辑、5 项重复代码、若干冗余模式），逐一修复并通过仿真回归验证。

### Bug 修复

#### 1. csr_rs1_bus 字段提取错误 (simple_cpu_top.v)

CSRRS/CSRRC 指令判断是否写入 CSR 时需检查 `rs1==x0`，但原代码从指令的 `rd` 字段（inst[11:7]）提取而非 `rs1` 字段（inst[19:15]），导致所有 CSRRS/CSRRC 指令均执行写入。

```verilog
// 修改前
wire [4:0] csr_rs1_bus = inst_r[11:7];   // 错误：提取 rd 字段
// 修改后
wire [4:0] csr_rs1_bus = inst_r[19:15];  // 正确：提取 rs1 字段
```

#### 2. MIP 寄存器读取使用组合逻辑值 (cpu_csr.v)

CSR 读 `mip` 时原代码返回组合逻辑 `w_mip_hw`，软件读到的是当前周期的硬件中断状态而非寄存器锁存值，与硬件写入行为不一致。

```verilog
// 修改前
csr_mip: csr_rdata = w_mip_hw;
// 修改后
csr_mip: csr_rdata = r_mip;
```

### 死代码移除

| 文件 | 移除项 | 原因 |
|------|--------|------|
| simple_cpu_top.v | `exe_csr_wen/waddr/wdata/old_val` 4 根线网 | 声明并赋值但从未被引用 |
| simple_cpu_top.v | `instruction_complete` 线网 | 声明并赋值但从未被引用 |
| cpu_controller.v | `instruction_complete` 线网 | 同上 |
| MMU.v | `clk`/`reset` 端口 | 声明但模块内未使用 |
| alu_32bit.v | `mul_active`/`div_active` 寄存器 | 与 `mul_busy`/`div_busy` 完全相同 |
| alu_32bit.v | `flush_int`/`result_ready_int` 线网 | 直通赋值，无逻辑意义 |
| alu_32bit.v | `sll_result`/`srl_result`/`sra_result` 别名 | 直通赋值，改为直接传递 `shift_result` |
| non_restoring_divider.v | 8 根 `_cout` 线网 | 声明并赋值但从未被引用 |
| booth_multiplier.v | `sub_result`/`sub_cout`/`add_cout`/`count_inc_cout` | 声明并赋值但从未被引用 |
| cla_adder_16bit.v | `g0`/`p0`…`g3`/`p3` 8 根线网 | 声明并赋值但从未被引用 |
| ahb_lite_to_apb.v | `latch_addr`/`latch_write`/`latch_wdata`/`latch_prot` 4 个寄存器 | 声明并赋值但从未被引用 |
| gpio.v | `access_end` 线网 | 声明并赋值但从未被引用 |
| apb_slave.v | `access_end` 线网 | 同上 |
| ahb_master.v | `latch_addr`/`latch_write`/`latch_size`/`latch_burst`/`latch_prot`/`latch_lock` 6 个寄存器 | 声明并赋值但从未被引用 |

### 冗余逻辑简化

| 文件 | 修改 | 说明 |
|------|------|------|
| cpu_clint.v | `trap_enter` 简化为 `exception_valid \|\| interrupt_pending` | 原为 4 项 OR，其中 2 项被包含 |
| cpu_clint.v | `cur_mpp` 从 wire 改为 localparam | MPP 硬编码为 Machine 模式 (2'b11) |
| cpu_clint.v | 移除 `mpp_bits` 线网 | 仅赋值未被引用 |
| cpu_controller.v | 移除 STATE_DECODE 中 `dec_is_branch` 冗余分支 | 该条件下 state 不会改变 |
| cpu_decode.v | `alu_src1` 移位指令简化 | 移除 3 路穿透到 rs1_value 的冗余 |
| cpu_decode.v | `wb_we` 移除 `is_load` 条件 | load 指令的写使能已由 `is_load` 自身覆盖 |
| cpu_mem.v | 提取 `misalign_addr` 公共子表达式 | 消除重复的地址对齐判断 |
| cpu_mem.v | `alu_result[0] != 1'b0` → `alu_result[0]` | 语义等价，更简洁 |
| branch_comparator.v | 6 项 OR 链改为 case 语句 | 更清晰，综合等价 |
| cpu_bus_adapter.v | 9 路分支合并为 5 路 | 合并相同处理逻辑的 case 项 |
| simple_cpu_top.v | 合并 trap_enter/trap_return PC 赋值 | 消除重复的 PC 选择逻辑 |
| simple_cpu_top.v | 简化 `exception_valid_r` 自赋值 | 移除 `else exception_valid_r <= exception_valid_r` |
| logic_unit.v | `nor_result` 复用 `~or_result` | 消除重复的按位 OR 计算 |
| non_restoring_divider.v | `operand_same_sign` → `~result_sign` | 语义等价，减少冗余信号 |
| booth_multiplier.v | 提取 `no_op`/`shift_src` 组合逻辑 | 简化 COMPUTE 状态内的条件嵌套 |
| system_top.v | 移除 `cpu_clk` 直通线网 | 全部引用替换为 `clk` |

### UART/外设冗余模式清理

| 文件 | 修改 |
|------|------|
| uart_tx.v | 移除 `$unsigned()` 强制转换（5 处）、`== 1'b1` 冗余比较（2 处）、`bit_cnt <= bit_cnt` 自赋值 |
| uart_rx.v | 移除 `$unsigned()` 强制转换（4 处）、`bit_cnt <= bit_cnt` 自赋值、`rx_bits <= rx_bits` 自赋值 |
| uart_top.v | PREADY/PSLVERR 从寄存常量改为 assign |
| gpio.v | PREADY/PSLVERR 从寄存常量改为 assign |
| timer.v | PREADY/PSLVERR 从寄存常量改为 assign |
| spi.v | PREADY/PSLVERR 从寄存常量改为 assign |
| apb_decoder.v | 移除 `addr_region` 别名，直接使用 PADDR |

### AHB 总线冗余逻辑清理

| 文件 | 修改 |
|------|------|
| ahb_default_slave.v | 合并 IDLE/BUSY/!HSEL 三个相同分支为一个 else |
| ahb_sram_slave.v | 合并 IDLE/BUSY 与 !HSEL 两个相同分支 |
| ahb_decoder.v | 默认 slave 选择改为 `~(HSELx[0]\|HSELx[1]\|...)` 复用已有选择信号 |

### 回归验证

```
iverilog -g2012 编译通过，无 error/warning
vvp 仿真结果：pass=33 fail=0 — ALL TESTS PASSED
```
