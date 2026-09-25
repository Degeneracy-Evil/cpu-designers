# 32位ALU设计文档

## 项目概述

本项目实现了一个完整的32位算术逻辑单元（ALU），完全使用Verilog门级设计，不使用任何IP核或高级运算符。

乘除法不在 `alu_32bit` 内——由独立的多周期单元 `mu_unit` 实现，见 `MU_INTERFACE.md`。

## 功能特性

### 已实现的功能

1. **超前进位加法器 (CLA Adder)**
   - 4位、16位、32位层级结构
   - O(log N)延迟时间

2. **减法器**
   - 使用补码实现：A - B = A + (~B + 1)
   - 与加法器共享同一CLA实例，通过输入选择复用

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

6. **Booth乘法器**（位于独立模块 `mu_unit`）
   - 实现 RV32M 乘法指令（有符号/无符号/混合）
   - 32个时钟周期完成
   - Booth算法实现

7. **非恢复余数除法器**（位于独立模块 `mu_unit`）
   - 实现 RV32M 除法指令（有符号/无符号）
   - 32个时钟周期完成
   - 非恢复余数（Non-Restoring）算法

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

1. **为什么乘除法放在独立的 mu_unit？**
   - 乘除法是 32 周期迭代状态机，与 ALU 单周期组合逻辑的时序特性完全不同
   - mu_unit 实现全部 8 条 RV32M 指令（有符号/无符号/混合，MUL/DIV/REM 系列）
   - 通过 `req_valid`/`mu_ready`/`result_valid` 握手与流水线交互，见 `MU_INTERFACE.md`

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
src/core/execution/alu/
├── top.sv                # alu_32bit 顶层（纯组合逻辑）
├── adder/                # CLA 加法器层级：cla_4bit → cla_16bit → cla_32bit
├── logic.sv              # logic_unit：逻辑运算与比较
├── shifter.sv            # 桶形移位器
├── immediate.sv          # lui：高位加载
├── mux.sv                # mux_2to1 / mux_4to1
├── result_selector.sv    # alu_result_selector：one-hot 结果选择
└── branch_comparator.sv  # 分支比较

src/core/execution/muldiv/    # mu_unit 乘除法单元（booth_multiplier + non_restoring_divider）
```

## 快速开始

ALU/MU 无独立单元仿真任务，由指令级测试覆盖：

```bash
python3 -m tools.vivado sim isa_alu    # ALU 全部指令
python3 -m tools.vivado sim isa_m_ext  # RV32M 全部乘除法指令
```

## ALU控制信号

16位控制信号 `alu_control[15:0]`（位定义见 `result_selector.sv`）：

| Bit | 操作   | 说明                    | 符号性质       |
|-----|--------|-------------------------|----------------|
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

**注意：**

- 控制信号为one-hot编码，同一时间只有一位为1
- bit 14/15（乘/除）不存在——乘除法由独立的 `mu_unit` 处理（`mu_funct3` 编码，见 `MU_INTERFACE.md`）
- CPU 译码（decode.sv）仅产生 bit 1-6、8-12；bit 7（NOR）、13（NOT）为模块保留能力，当前指令集不使用

## 模块接口

### alu_32bit — 纯组合逻辑 ALU

单周期直出结果，无时钟、无握手协议。仅处理加减移位逻辑比较等单周期运算。

```verilog
module alu_32bit(
    input  [15:0] alu_control,   // ALU控制信号（one-hot编码）
    input  [31:0] src1,          // 源操作数1
    input  [31:0] src2,          // 源操作数2
    output [31:0] result         // 运算结果，同拍有效
);
```

### mu_unit — 多周期乘除法单元

实现 RV32M 扩展全部 8 条乘除法指令，需要时钟和握手协议。详见 `MU_INTERFACE.md`。

```verilog
module mu_unit(
    input         clk,
    input         reset,
    input  [2:0]  mu_funct3,    // RISC-V funct3，直接映射M扩展操作码
    input  [31:0] src1,
    input  [31:0] src2,
    input         req_valid,    // 请求有效
    input         flush,        // 冲刷当前状态
    input         result_got,   // 结果消费握手
    output [31:0] result,       // 运算结果
    output        mu_busy,      // 多周期执行中
    output        mu_ready,     // 可接收新请求
    output        result_valid, // 结果有效
    output        div_by_zero   // 最近一次除法是否为除零
);
```

### 使用示例

```verilog
// alu_32bit: 加法示例（纯组合逻辑，同拍出结果）
alu_control = 16'b0001_0000_0000_0000;  // ADD
src1 = 32'd12345;
src2 = 32'd67890;
// result = 80235，同拍有效

// alu_32bit: 有符号比较示例
alu_control = 16'b0000_0100_0000_0000;  // SLT
src1 = 32'hffffffff;  // -1
src2 = 32'd1;
// result = 1，同拍有效

// mu_unit: 乘法示例（需等待result_valid）
mu_funct3 = 3'b000;  // MUL
src1 = 32'd123;
src2 = 32'd456;
req_valid = 1'b1;
// 等待若干拍后 result_valid = 1
// result = 56088

// mu_unit: 除法示例
mu_funct3 = 3'b100;  // DIV
src1 = 32'd1000;
src2 = 32'd7;
req_valid = 1'b1;
// 等待若干拍后 result_valid = 1
// result = 142
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

- `isa_alu`：ALU 全部指令（加/减/移位/逻辑/比较/LUI）
- `isa_m_ext`：RV32M 全部乘除法指令（含除零、溢出边界）

详见 `docs/testing/test-system.md`。

## 参考资料

- 计算机组成与设计：硬件/软件接口
- 数字逻辑与计算机组成
- Booth乘法算法
- 非恢复余数除法算法
- 超前进位加法器原理

## 版本历史

- v1.0 (2026-03-28): 独立 ALU 项目初始设计
- 2026-09-25: 对齐当前 RTL——乘除法归独立 mu_unit，修正控制信号表，删除独立项目时代的 Makefile/iverilog/FPGA 迁移内容
