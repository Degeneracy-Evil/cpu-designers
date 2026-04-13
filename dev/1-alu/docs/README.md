# 32位ALU设计文档

## 项目概述

本项目实现了一个完整的32位算术逻辑单元（ALU），完全使用Verilog门级设计，不使用任何IP核或高级运算符。

## 功能特性

### 已实现的功能

1. **超前进位加法器 (CLA Adder)**
   - 4位、16位、32位层级结构
   - O(log N)延迟时间

2. **减法器**
   - 使用补码实现：A - B = A + (~B + 1)
   - 基于CLA加法器

3. **移位器**
   - 逻辑左移 (SLL)
   - 逻辑右移 (SRL)
   - 算术右移 (SRA)
   - 桶形移位器结构，5级移位

4. **逻辑运算**
   - AND (按位与)
   - OR (按位或)
   - NOT (按位取反)
   - XOR (按位异或)
   - NOR (按位或非)
   - SLT (有符号小于比较)
   - SLTU (无符号小于比较)

5. **高位加载 (LUI)**
   - 将16位立即数加载到高16位

6. **Booth乘法器**
   - 支持32位有符号数乘法
   - 32个时钟周期完成
   - Booth算法实现

7. **非恢复余数除法器**
   - 支持32位有符号数除法
   - 32个时钟周期完成
   - Restoring Division算法

## 操作符号性质说明

### 有符号操作 (Signed Operations)

| 操作   | 说明                           | 示例                    |
|--------|--------------------------------|-------------------------|
| ADD    | 有符号加法                     | -1 + 1 = 0              |
| SUB    | 有符号减法                     | 50 - 100 = -50          |
| SLT    | 有符号比较                     | -1 < 1 → 1              |
| SRA    | 算术右移（保留符号位）         | -8 >>> 2 = -2           |
| MUL    | 有符号乘法（Booth算法）        | -123 × 456 = -56088     |
| DIV    | 有符号除法                     | -1000 ÷ 7 = -142        |

**注意事项：**

- 有符号数使用二进制补码表示
- 最高位（bit 31）为符号位：0表示正数，1表示负数
- 正数范围：0 ~ 2^31-1 (0 ~ 2147483647)
- 负数范围：-2^31 ~ -1 (-2147483648 ~ -1)

### 无符号操作 (Unsigned Operations)

| 操作   | 说明                           | 示例                    |
|--------|--------------------------------|-------------------------|
| SLTU   | 无符号比较                     | 0xFFFFFFFF < 1 → 0      |
| SLL    | 逻辑左移（低位补0）            | 0x0F << 4 = 0xF0        |
| SRL    | 逻辑右移（高位补0）            | 0xF0 >> 4 = 0x0F        |

**注意事项：**

- 无符号数所有位都表示数值
- 范围：0 ~ 2^32-1 (0 ~ 4294967295)

### 位运算操作 (Bitwise Operations)

| 操作   | 说明                           | 符号性质               |
|--------|--------------------------------|------------------------|
| AND    | 按位与                         | 无符号（位运算）       |
| OR     | 按位或                         | 无符号（位运算）       |
| NOT    | 按位取反                       | 无符号（位运算）       |
| XOR    | 按位异或                       | 无符号（位运算）       |
| NOR    | 按位或非                       | 无符号（位运算）       |
| LUI    | 高位加载                       | 无符号（位操作）       |

**注意事项：**

- 位运算对每一位独立操作，不关心符号
- 结果取决于操作数的位模式

### 关键设计决策

1. **为什么乘除法只支持有符号？**
   - Booth算法天然支持有符号数乘法
   - Restoring Division算法可以处理有符号数
   - MIPS指令集中乘除法通常是有符号的
   - 如需无符号乘除法，可扩展控制信号

2. **为什么移位操作区分有符号/无符号？**
   - SLL和SRL：移入0，不关心符号
   - SRA：移入符号位，保持负数的正确性
   - 例如：-8 (0xFFFFFFF8) >>> 2 = -2 (0xFFFFFFFE)

3. **比较操作为什么要区分SLT和SLTU？**
   - SLT：将操作数视为有符号数比较
   - SLTU：将操作数视为无符号数比较
   - 例如：0xFFFFFFFF 在SLT中是-1，在SLTU中是4294967295

## 文件结构

```
.
├── rtl/                        # RTL设计文件
│   ├── basic_gates.v           # 基础门电路
│   ├── cla_adder_4bit.v        # 4位超前进位加法器
│   ├── cla_adder_16bit.v       # 16位超前进位加法器
│   ├── cla_adder_32bit.v       # 32位超前进位加法器
│   ├── subtractor.v            # 减法器
│   ├── shifter.v               # 移位器
│   ├── logic_unit.v            # 逻辑运算单元
│   ├── lui.v                   # 高位加载
│   ├── booth_multiplier.v      # Booth乘法器
│   ├── non_restoring_divider.v # 非恢复余数除法器
│   └── alu_32bit.v             # 顶层ALU模块
├── tb/                         # 测试平台
│   └── tb_alu_cpu_integration.v # ALU握手集成测试平台
├── docs/                       # 文档
│   ├── README.md               # 本文档
│   ├── ALU_DESIGN.md           # 详细设计说明
│   └── ALU_INTERFACE.md        # 顶层接口规范
├── Makefile                    # 编译脚本
└── AGENTS.md                   # 开发指南
```

## 快速开始

### 编译和测试

```bash
# 显示帮助
make help

# 编译所有模块
make compile

# 运行测试
make test

# 清理
make clean

# 完整流程（默认）
make all

# 生成波形文件
make wave

# 查看波形（需要GTKWave）
make view

# 语法检查
make check

# 运行所有检查
make check-all

# 统计代码行数
make count
```

### Makefile主要目标

| 目标       | 说明                           |
|------------|--------------------------------|
| all        | 显示信息并运行测试（默认）     |
| compile    | 编译所有模块                   |
| run        | 运行测试（不重新编译）         |
| test       | 编译并运行测试                 |
| wave       | 生成波形文件                   |
| view       | 用GTKWave查看波形              |
| check      | 语法检查                       |
| lint       | Lint检查                       |
| clean      | 清理生成的文件                 |
| distclean  | 深度清理（包括备份文件）       |
| list       | 列出所有源文件                 |
| count      | 统计代码行数                   |
| check-all  | 运行所有检查                   |
| help       | 显示帮助信息                   |

### 测试结果

```
========================================
Test Summary
========================================
Total tests: 30
Passed:      30
Failed:      0
Pass rate:   100.0%
========================================
ALL TESTS PASSED!
```

## ALU控制信号

16位控制信号 `alu_control[15:0]`：

| Bit | 操作   | 说明                    | 符号性质       |
|-----|--------|-------------------------|----------------|
| 15  | MUL    | 乘法（Booth算法）       | 有符号         |
| 14  | DIV    | 除法（Restoring算法）   | 有符号         |
| 13  | NOT    | 按位取反                | 无符号（位运算）|
| 12  | ADD    | 加法                    | 有符号         |
| 11  | SUB    | 减法                    | 有符号         |
| 10  | SLT    | 有符号比较（小于置位）  | 有符号         |
| 9   | SLTU   | 无符号比较（小于置位）  | 无符号         |
| 8   | AND    | 按位与                  | 无符号（位运算）|
| 7   | NOR    | 按位或非                | 无符号（位运算）|
| 6   | OR     | 按位或                  | 无符号（位运算）|
| 5   | XOR    | 按位异或                | 无符号（位运算）|
| 4   | SLL    | 逻辑左移                | 无符号         |
| 3   | SRL    | 逻辑右移                | 无符号         |
| 2   | SRA    | 算术右移                | 有符号         |
| 1   | LUI    | 高位加载                | 无符号（位操作）|
| 0   | -      | 保留                    | -              |

**注意：** 控制信号为one-hot编码，同一时间只有一位为1。

## 模块接口

### 顶层ALU模块

```verilog
module alu_32bit(
    input         clk,           // 时钟信号
    input         reset,         // 复位信号（高电平有效）
    input  [15:0] alu_control,   // ALU控制信号（one-hot编码）
    input  [31:0] src1,          // 源操作数1
    input  [31:0] src2,          // 源操作数2
   input         req_valid,     // 请求有效
   input         flush,         // 冲刷当前顶层状态
   input         result_ready,  // 结果消费握手
    output [31:0] result,        // 运算结果
   output        alu_busy,      // 多周期执行中
   output        alu_ready,     // 可接收新请求
   output        result_valid,  // 结果有效
   output        illegal_op,    // 非法one-hot
   output        div_by_zero    // 最近一次除法是否为除零
);
```

### 使用示例

```verilog
// 加法示例
alu_control = 16'b0001_0000_0000_0000;  // ADD
src1 = 32'd12345;
src2 = 32'd67890;
req_valid = 1'b1;
// 当 alu_ready=1 时发射请求
// 下一拍可见 result_valid=1, result=80235

// 有符号比较示例
alu_control = 16'b0000_0100_0000_0000;  // SLT
src1 = 32'hffffffff;  // -1
src2 = 32'd1;
req_valid = 1'b1;
// result_valid=1 时读取 result=1

// 乘法示例（等待result_valid）
alu_control = 16'b1000_0000_0000_0000;  // MUL
src1 = 32'd123;
src2 = 32'd456;
req_valid = 1'b1;
// 等待若干拍后 result_valid = 1
// result = 56088
```

## 设计特点

### 1. 门级设计

所有模块完全使用门级设计，不使用以下运算符：

- 算术运算符: +, -, *, /
- 高级结构: always @(*) 用于算术运算

### 2. 模块化设计

每个功能独立封装，便于：

- 单独测试和验证
- 复用和替换
- 理解和维护

### 3. 性能优化

- CLA加法器：O(log N)延迟
- 桶形移位器：O(log N)延迟
- 乘法器：32周期
- 除法器：32周期

## 测试覆盖

测试平台包含30个测试用例，覆盖：

- 所有运算类型
- 正数和负数
- 边界值（0, 最大值, 最小值）
- 特殊情况（移位0位, 相同值相减等）

## FPGA迁移指南

### 1. 时钟和复位

**注意事项：**

- 本设计使用**高电平复位**（`reset`为1时复位）
- Vivado默认通常使用**低电平复位**，需要调整：

  ```verilog
  // 方案1：修改设计使用低电平复位
  always @(posedge clk or negedge reset_n) begin
      if (!reset_n) ...
  end
  
  // 方案2：在顶层添加复位反相器
  wire reset;
  assign reset = ~reset_n;
  ```

### 2. 时钟频率考虑

**乘除法延迟：**

- 乘法器需要32个时钟周期
- 除法器需要32个时钟周期
- 如果时钟频率为100MHz，则：
  - 乘法延迟 = 32 × 10ns = 320ns
  - 除法延迟 = 32 × 10ns = 320ns

**建议：**

- 根据FPGA时钟频率调整状态机周期数
- 或使用流水线设计提高吞吐量

### 3. 资源使用估算

| 模块         | LUT估算  | FF估算   | 说明               |
|--------------|----------|----------|--------------------|
| CLA加法器    | ~200     | 0        | 纯组合逻辑         |
| 减法器       | ~200     | 0        | 纯组合逻辑         |
| 移位器       | ~300     | 0        | 纯组合逻辑         |
| 逻辑单元     | ~150     | 0        | 纯组合逻辑         |
| 乘法器       | ~800     | ~100     | 32周期状态机       |
| 除法器       | ~600     | ~100     | 32周期状态机       |
| **总计**     | ~2250    | ~200     |                    |

### 4. 综合约束

**时序约束示例：**

```tcl
# 创建时钟
create_clock -period 10 -name sys_clk [get_ports clk]

# 设置输入延迟
set_input_delay -clock sys_clk 2 [get_ports {src1[*] src2[*] alu_control[*]}]

# 设置输出延迟
set_output_delay -clock sys_clk 2 [get_ports {result[*] result_valid alu_ready alu_busy illegal_op div_by_zero}]
```

### 5. 门级设计注意事项

**问题：** Vivado可能优化掉门级设计，使用DSP资源。

**解决方案：**

```tcl
# 禁用DSP推断（保持门级设计）
set_property USE_DSP48 none [get_cells -hierarchical *adder*]
set_property USE_DSP48 none [get_cells -hierarchical *multiplier*]

# 或在Verilog中使用综合属性
(* use_dsp48 = "no" *) module cla_adder_32bit(...);
```

### 6. 仿真和验证

**Vivado仿真步骤：**

1. 添加所有RTL文件到项目
2. 添加测试平台文件
3. 设置仿真时间：`set_property -name {xsim.simulate.runtime} -value {10us} [get_simulation_properties]`
4. 运行行为仿真
5. 检查波形和结果

### 7. 常见问题

**问题1：乘除法结果不正确**

- 检查复位信号极性
- 检查是否按`alu_ready/req_valid/result_valid`握手发射与取数
- 确认状态机状态转移

**问题2：时序违例**

- 降低时钟频率
- 添加流水线寄存器
- 使用时序优化指令

**问题3：资源使用过高**

- 检查是否使用了DSP资源
- 添加综合属性禁用DSP
- 优化状态机编码

### 8. XDC约束示例

```tcl
# 时钟约束
create_clock -period 10 -name sys_clk [get_ports clk]

# 复位约束
set_property PULLUP true [get_ports reset]

# 输入输出延迟
set_input_delay -clock sys_clk -max 2 [get_ports {src1[*] src2[*] alu_control[*]}]
set_input_delay -clock sys_clk -min 0 [get_ports {src1[*] src2[*] alu_control[*]}]
set_output_delay -clock sys_clk -max 2 [get_ports {result[*] result_valid alu_ready alu_busy illegal_op div_by_zero}]
set_output_delay -clock sys_clk -min 0 [get_ports {result[*] result_valid alu_ready alu_busy illegal_op div_by_zero}]

# 多周期路径（乘除法需要32周期）
set_multicycle_path -setup 32 -from [get_cells -hierarchical *multiplier*] -to [get_cells -hierarchical *multiplier*]
set_multicycle_path -setup 32 -from [get_cells -hierarchical *divider*] -to [get_cells -hierarchical *divider*]
```

## 开发环境

- **仿真器**: Icarus Verilog (iverilog)
- **编译**: iverilog
- **运行**: vvp
- **波形查看**: GTKWave (可选)

## 参考资料

- 计算机组成与设计：硬件/软件接口
- 数字逻辑与计算机组成
- Booth乘法算法
- Restoring Division算法
- 超前进位加法器原理

## 版本历史

- v1.0 (2026-03-28): 初始设计，完成所有模块，所有测试通过
