# FPGA测试指南

## 文件说明

- `alu_display.v` - FPGA顶层模块，调用ALU和触摸屏
- `alu.xdc` - FPGA约束文件
- `lcd_module.dcp` - 触摸屏IP核（需要从example复制）

## 使用步骤

### 1. 准备工作

在Vivado中创建项目，需要以下文件：

**RTL文件**（来自dev/1alu/rtl）：

- basic_gates.v
- mux.v
- cla_adder_4bit.v
- cla_adder_16bit.v
- cla_adder_32bit.v
- subtractor.v
- shifter.v
- logic_unit.v
- lui.v
- booth_multiplier.v
- non_restoring_divider.v
- alu_result_selector.v
- alu_32bit.v

**FPGA文件**（来自dev/1alu/fpga）：

- alu_display.v

**IP核**（来自example/1alu）：

- lcd_module.dcp

**约束文件**：

- alu.xdc

### 2. Vivado项目设置

1. 创建新项目，选择对应FPGA型号
2. 添加所有RTL源文件
3. 添加IP核：`lcd_module.dcp`
4. 添加约束文件：`alu.xdc`
5. 设置顶层模块：`alu_display`

### 3. 综合和实现

```tcl
# 综合设计
synth_design -top alu_display

# 实现设计
place_design
route_design

# 生成比特流
write_bitstream -force alu.bit
```

### 4. 下载和测试

1. 连接FPGA板
2. 下载比特流文件
3. 使用触摸屏输入测试数据

## 测试方法

### 输入选择（拨码开关）

| input_sel[1:0] | 输入类型 |
| -------------- | -------- |
| 00             | 控制信号 |
| 10             | 源操作数1 |
| 11             | 源操作数2 |

### 显示区域

| 编号 | 名称   | 说明 |
| ---- | ------ | ---- |
| 1    | SRC_1  | 源操作数1 |
| 2    | SRC_2  | 源操作数2 |
| 3    | CONTR  | 控制信号 |
| 4    | RESUL  | 运算结果 |
| 5    | DONE_  | 完成标志 |

### ALU控制信号（one-hot编码）

| 位  | 操作 | 说明 |
| ---- | ---- | ---- |
| 15   | MUL  | 乘法 |
| 14   | DIV  | 除法 |
| 13   | NOT  | 按位取反 |
| 12   | ADD  | 加法 |
| 11   | SUB  | 减法 |
| 10   | SLT  | 有符号比较 |
| 9    | SLTU | 无符号比较 |
| 8    | AND  | 按位与 |
| 7    | NOR  | 按位或非 |
| 6    | OR   | 按位或 |
| 5    | XOR  | 按位异或 |
| 4    | SLL  | 逻辑左移 |
| 3    | SRL  | 逻辑右移 |
| 2    | SRA  | 算术右移 |
| 1    | LUI  | 高位加载 |

### 测试示例

#### 1. 加法测试

```
控制信号: 0x1000 (bit 12 = 1, ADD)
源操作数1: 0x00003039 (12345)
源操作数2: 0x00010932 (67890)
预期结果: 0x0001396B (80235)
```

#### 2. 减法测试

```
控制信号: 0x0800 (bit 11 = 1, SUB)
源操作数1: 0x00000064 (100)
源操作数2: 0x00000032 (50)
预期结果: 0x00000032 (50)
```

#### 3. 乘法测试（需要等待done信号）

```
控制信号: 0x8000 (bit 15 = 1, MUL)
源操作数1: 0x0000007B (123)
源操作数2: 0x000001C8 (456)
预期结果: 0x0000DB18 (56088)
注意: 乘法需要32个时钟周期，等待DONE_=1
```

## 注意事项

1. **复位信号**: 低电平有效，按下Y3引脚对应的按钮复位
2. **时钟频率**: 100MHz
3. **乘除法延迟**: 乘法和除法各需要32个时钟周期
4. **done信号**: 观察显示区域5的DONE_信号，确认运算完成

## 与example的区别

1. **时钟和复位**: 我们的ALU需要时钟和复位信号（因为乘除法是多周期的）
2. **done信号**: 增加了完成标志，用于多周期运算
3. **控制信号位宽**: 使用16位one-hot编码（example使用32位）

## 故障排查

1. **结果不正确**: 检查控制信号是否为正确的one-hot编码
2. **结果一直为0**: 检查复位信号是否释放
3. **乘除法无结果**: 等待done信号，可能需要多个时钟周期
4. **触摸屏无响应**: 检查lcd_module.dcp是否正确添加
