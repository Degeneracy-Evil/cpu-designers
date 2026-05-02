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
| tb_csr_test | 20 | 0 |
| tb_align_test | 23 | 0 |
| tb_timer_irq_test | 2 | 0 |
| tb_timer_seconds | 3 | 0 |

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
| tb_csr_test | PASS (20/20) |
| tb_align_test | PASS (23/23) |
| tb_timer_irq_test | PASS |
| tb_timer_seconds | PASS |
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
