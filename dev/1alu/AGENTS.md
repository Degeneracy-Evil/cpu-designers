# AGENTS.md - 32位ALU开发指南

## 项目概述

本项目设计并实现一个32位算术逻辑单元（ALU），完全使用Verilog门级设计，不使用任何IP核。

## 开发环境

### 工具链
- **仿真器**: Icarus Verilog (iverilog)
- **波形查看**: GTKWave (暂不使用)
- **编译**: iverilog
- **运行**: vvp

### 安装iverilog
```bash
# Ubuntu/Debian
sudo apt-get install iverilog

# 验证安装
iverilog -V
```

## 项目结构

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
│   └── tb_alu_32bit.v          # ALU测试平台
├── docs/                       # 文档
│   ├── README.md               # 设计文档
│   └── ALU_DESIGN.md           # 详细设计说明
├── Makefile                    # 编译脚本
└── AGENTS.md                   # 本文档
```

## 编译和仿真

### 使用Makefile（推荐）

```bash
# 编译所有模块
make compile

# 运行测试
make test

# 清理
make clean

# 完整流程（编译+测试）
make all
```

### 手动编译和仿真

```bash
# 编译所有RTL文件和测试平台
iverilog -o alu_tb \
    rtl/basic_gates.v \
    rtl/cla_adder_4bit.v \
    rtl/cla_adder_16bit.v \
    rtl/cla_adder_32bit.v \
    rtl/subtractor.v \
    rtl/shifter.v \
    rtl/logic_unit.v \
    rtl/lui.v \
    rtl/booth_multiplier.v \
    rtl/non_restoring_divider.v \
    rtl/alu_32bit.v \
    tb/tb_alu_32bit.v

# 运行仿真
vvp alu_tb

# 查看输出（测试结果会直接打印到终端）
```

### 单模块测试

```bash
# 测试单个模块（例如CLA加法器）
iverilog -o cla_test rtl/cla_adder_32bit.v tb/tb_cla.v
vvp cla_test
```

## 设计规范

### 1. 代码风格

- **时间精度**: 统一使用 `timescale 1ns / 1ps
- **模块命名**: 小写字母，下划线分隔（例如：cla_adder_32bit）
- **信号命名**: 
  - 输入信号：小写，有意义（例如：multiplicand, multiplier）
  - 输出信号：小写，有意义（例如：product, quotient）
  - 内部信号：使用wire或reg，命名清晰
- **参数命名**: 大写字母，下划线分隔（例如：DATA_WIDTH）

### 2. 门级设计原则

**禁止使用**:
- 算术运算符: +, -, *, /
- 关系运算符: <, >, <=, >= (用于比较逻辑除外)
- 直接的位拼接运算用于算术目的

**允许使用**:
- 位运算符: &, |, ^, ~, ~&, ~|, ~^
- 位拼接: {a, b}
- 位选择: a[i], a[i:j]
- 条件运算符: ? :
- 移位运算符: <<, >> (仅用于常数移位，如 {a[30:0], 1'b0})
- 关系运算符: ==, != (用于控制逻辑)

### 3. 模块接口规范

#### 组合逻辑模块
```verilog
module module_name(
    input  [N-1:0] input1,
    input  [M-1:0] input2,
    output [K-1:0] output1
);
```

#### 时序逻辑模块（状态机）
```verilog
module module_name(
    input         clk,
    input         reset,
    input  [N-1:0] data_in,
    input         start,
    output [M-1:0] data_out,
    output        done
);
```

### 4. 状态机设计规范

使用三段式状态机：

```verilog
// 状态定义
localparam IDLE   = 2'b00;
localparam COMPUTE = 2'b01;
localparam DONE   = 2'b10;

reg [1:0] state, next_state;

// 状态转移（时序逻辑）
always @(posedge clk or posedge reset) begin
    if (reset)
        state <= IDLE;
    else
        state <= next_state;
end

// 下一状态逻辑（组合逻辑）
always @(*) begin
    case (state)
        IDLE: next_state = ...;
        COMPUTE: next_state = ...;
        DONE: next_state = ...;
        default: next_state = IDLE;
    endcase
end

// 输出逻辑
always @(*) begin
    // 根据状态产生输出
end
```

## ALU控制信号定义

16位控制信号 `alu_control[15:0]`：

| Bit | 操作 | 说明 |
|-----|------|------|
| 15  | MUL  | 乘法（Booth算法） |
| 14  | DIV  | 除法（非恢复余数法） |
| 13  | NOT  | 按位取反 |
| 12  | ADD  | 加法 |
| 11  | SUB  | 减法 |
| 10  | SLT  | 有符号比较（小于置位） |
| 9   | SLTU | 无符号比较（小于置位） |
| 8   | AND  | 按位与 |
| 7   | NOR  | 按位或非 |
| 6   | OR   | 按位或 |
| 5   | XOR  | 按位异或 |
| 4   | SLL  | 逻辑左移 |
| 3   | SRL  | 逻辑右移 |
| 2   | SRA  | 算术右移 |
| 1   | LUI  | 高位加载 |
| 0   | -    | 保留 |

**注意**: 控制信号为one-hot编码，同一时间只有一位为1。

## 测试规范

### 测试平台结构

```verilog
module tb_module_name;

    // 信号声明
    reg clk;
    reg reset;
    // ... 其他输入信号
    wire [31:0] result;
    wire done;

    // 实例化被测模块
    module_name uut (
        .clk(clk),
        .reset(reset),
        // ...
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 测试用例
    initial begin
        // 初始化
        reset = 1;
        #10 reset = 0;
        
        // 测试用例1
        // ...
        
        // 检查结果
        if (result == expected)
            $display("PASS: Test case 1");
        else
            $display("FAIL: Test case 1, expected=%h, got=%h", expected, result);
        
        // 完成测试
        $finish;
    end

endmodule
```

### 测试用例要求

- 至少10组测试实例
- 覆盖所有操作类型
- 包含边界值测试（0, 最大值, 最小值）
- 包含正数和负数测试
- 自动输出PASS/FAIL结果
- 统计通过率

### 测试报告格式

```
========================================
ALU Test Report
========================================
Test 1: ADD Operation
  Input: 12345 + 67890
  Expected: 80235
  Result: 80235
  Status: PASS

Test 2: SUB Operation
  Input: 100 - 50
  Expected: 50
  Result: 50
  Status: PASS

...

========================================
Summary: 15/15 tests passed
========================================
```

## 调试技巧

### 1. 查看信号值

在测试平台中添加：
```verilog
initial begin
    $monitor("Time=%0t, state=%b, result=%h", $time, state, result);
end
```

### 2. 分模块测试

先测试基础模块（如CLA加法器），确保正确后再集成到顶层。

### 3. 错误定位

如果测试失败：
1. 检查输入信号是否正确
2. 检查控制信号是否正确
3. 检查中间结果（使用$display打印）
4. 检查时序关系

## 开发流程

### 阶段1: 基础模块开发
1. 实现基础门电路 (`basic_gates.v`)
2. 实现CLA加法器 (`cla_adder_*.v`)
3. 测试CLA加法器

### 阶段2: 算术运算模块
4. 实现减法器 (`subtractor.v`)
5. 实现移位器 (`shifter.v`)
6. 测试算术模块

### 阶段3: 逻辑运算模块
7. 实现逻辑单元 (`logic_unit.v`)
8. 实现高位加载 (`lui.v`)
9. 测试逻辑模块

### 阶段4: 复杂运算模块
10. 实现Booth乘法器 (`booth_multiplier.v`)
11. 测试乘法器
12. 实现非恢复余数除法器 (`non_restoring_divider.v`)
13. 测试除法器

### 阶段5: 集成测试
14. 实现顶层ALU (`alu_32bit.v`)
15. 编写完整测试平台 (`tb_alu_32bit.v`)
16. 运行所有测试用例
17. 验证测试结果

### 阶段6: 文档完善
18. 编写README.md
19. 编写ALU_DESIGN.md
20. 更新AGENTS.md

## 常见问题

### Q1: 编译错误 "Cannot find module"
**A**: 检查文件是否在编译命令中列出，检查模块名是否正确。

### Q2: 仿真结果不正确
**A**: 
- 检查是否使用了禁止的运算符
- 检查状态机状态转移逻辑
- 检查信号位宽是否匹配

### Q3: 乘法器/除法器一直不结束
**A**: 
- 检查状态机是否正确转移到DONE状态
- 检查计数器是否正确递增
- 检查done信号是否正确产生

### Q4: 时序逻辑不工作
**A**: 
- 检查时钟是否正确生成
- 检查复位信号是否正确
- 检查always块敏感列表

## 性能指标

### 面积优化
- 尽量复用模块
- 减少冗余逻辑

### 时序优化
- CLA加法器：O(log N) 延迟
- 移位器：O(log N) 延迟
- 乘法器：32个时钟周期
- 除法器：32个时钟周期

## 参考资料

- 计算机组成与设计：硬件/软件接口
- 数字逻辑与计算机组成
- Booth乘法算法
- 非恢复余数除法算法
- 超前进位加法器原理

## 版本历史

- v1.0 (2026-03-28): 初始设计，完成所有模块