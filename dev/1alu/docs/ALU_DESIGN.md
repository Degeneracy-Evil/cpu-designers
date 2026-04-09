# 32位ALU详细设计说明

## 1. 超前进位加法器 (CLA Adder)

### 1.1 设计原理

传统的行波进位加法器（Ripple Carry Adder）延迟为O(N)，对于32位加法器来说延迟太大。超前进位加法器通过并行计算进位信号，将延迟降低到O(log N)。

### 1.2 基本概念

对于每一位i，定义：

- **生成信号 (Generate)**: G[i] = A[i] AND B[i]
- **传播信号 (Propagate)**: P[i] = A[i] XOR B[i]
- **进位信号**: C[i+1] = G[i] OR (P[i] AND C[i])
- **和**: S[i] = P[i] XOR C[i]

### 1.3 层次化设计

```txt
32位CLA
├── 16位CLA (高16位)
│   ├── 4位CLA (位12-15)
│   ├── 4位CLA (位8-11)
│   ├── 4位CLA (位4-7)
│   └── 4位CLA (位0-3)
└── 16位CLA (低16位)
    ├── 4位CLA (位12-15)
    ├── 4位CLA (位8-11)
    ├── 4位CLA (位4-7)
    └── 4位CLA (位0-3)
```

### 1.4 实现

**4位CLA模块**:

```verilog
module cla_adder_4bit(
    input  [3:0] a,
    input  [3:0] b,
    input         cin,
    output [3:0] sum,
    output        cout,
    output [3:0] g,    // 生成信号
    output [3:0] p     // 传播信号
);
    // P[i] = a[i] XOR b[i]
    // G[i] = a[i] AND b[i]
    // S[i] = P[i] XOR C[i]
    // C[i+1] = G[i] OR (P[i] AND C[i])
endmodule
```

## 2. 减法器

### 2.1 设计原理

使用补码表示法实现减法：

```
A - B = A + (-B)
      = A + (~B + 1)
```

### 2.2 实现

```verilog
module subtractor(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result,
    output        borrow
);
    // result = a + (~b + 1)
    // borrow = ~cout
endmodule
```

## 3. 移位器

### 3.1 桶形移位器 (Barrel Shifter)

桶形移位器使用对数级移位实现任意位移，延迟为O(log N)。

### 3.2 5级移位结构

对于32位数据，移位量可以是0-31，需要5位表示。桶形移位器使用5级：

```
第1级: 移0位或1位   (根据shamt[0])
第2级: 移0位或2位   (根据shamt[1])
第3级: 移0位或4位   (根据shamt[2])
第4级: 移0位或8位   (根据shamt[3])
第5级: 移0位或16位  (根据shamt[4])
```

### 3.3 三种移位类型

**逻辑左移 (SLL)**:

- 低位补0
- `result = data << shamt`

**逻辑右移 (SRL)**:

- 高位补0
- `result = data >> shamt`

**算术右移 (SRA)**:

- 高位补符号位
- `result = data >>> shamt`

## 4. 逻辑运算单元

### 4.1 基本逻辑运算

```verilog
and_result = a & b
or_result  = a | b
not_result = ~a
xor_result = a ^ b
nor_result = ~(a | b)
```

### 4.2 比较运算

**有符号小于 (SLT)**:

```verilog
// 如果a和b符号不同，a为负则a<b
// 如果a和b符号相同，看a-b的符号
slt_result = (a[31] & ~b[31]) | (~(a[31]^b[31]) & (a-b)[31])
```

**无符号小于 (SLTU)**:

```verilog
// 使用33位比较：{1'b0, a} < {1'b0, b}
// 等价于检查a-b的借位
sltu_result = ~(a >= b) = borrow_of(a-b)
```

## 5. 高位加载 (LUI)

### 5.1 功能

将16位立即数加载到结果的高16位，低16位补0。

### 5.2 实现

```verilog
result = {imm[15:0], 16'b0}
```

## 6. Booth乘法器

### 6.1 Booth算法原理

Booth算法是一种用于有符号数乘法的高效算法，通过检查乘数相邻位的模式来决定操作。

### 6.2 算法步骤

初始化：

- A = 0 (32位)
- Q = multiplier (32位)
- Q₋₁ = 0 (1位)
- M = multiplicand (32位)

对于每一位（共32次）：

1. 检查Q₀和Q₋₁的值
2. 根据以下规则操作：
   - 00或11：不操作
   - 01：A = A + M
   - 10：A = A - M
3. 算术右移{A, Q, Q₋₁}一位

结果：{A, Q}为64位乘积

### 6.3 状态机设计

```
IDLE -> COMPUTE -> FINISH -> IDLE
```

- **IDLE**: 等待start信号
- **COMPUTE**: 执行32次迭代
- **FINISH**: 输出结果

### 6.4 实现

```verilog
module booth_multiplier(
    input         clk,
    input         reset,
    input  [31:0] multiplicand,
    input  [31:0] multiplier,
    input         start,
    output [63:0] product,
    output        done
);
    // 状态机
    // Booth算法实现
    // 32个周期完成
endmodule
```

## 7. 非恢复余数除法器

### 7.1 Restoring Division算法

Restoring Division是一种用于整数除法的算法，通过移位和加减操作实现。

### 7.2 算法步骤

初始化：

- R = 0 (32位余数)
- Q = dividend (32位被除数)
- D = divisor (32位除数)

对于每一位（共32次）：

1. 左移{R, Q}一位
2. R = R - D
3. 如果R < 0：
   - 恢复：R = R + D
   - Q[0] = 0
4. 如果R >= 0：
   - Q[0] = 1

结果：

- Q为商
- R为余数

### 7.3 符号处理

1. 记录被除数和除数的符号
2. 使用绝对值进行计算
3. 商的符号 = 被除数符号 XOR 除数符号
4. 余数的符号 = 被除数的符号

### 7.4 状态机设计

```
IDLE -> COMPUTE -> FINISH -> IDLE
```

- **IDLE**: 等待start信号，初始化
- **COMPUTE**: 执行32次迭代
- **FINISH**: 调整符号，输出结果

## 8. 顶层ALU模块

### 8.1 模块集成

顶层ALU模块集成所有子模块，根据控制信号选择相应的运算结果。

### 8.2 控制逻辑

```verilog
assign result = alu_mul  ? mul_result_low :
                alu_div  ? div_quotient :
                alu_not  ? not_result :
                alu_add  ? add_result :
                alu_sub  ? sub_result :
                alu_slt  ? slt_result :
                alu_sltu ? sltu_result :
                alu_and  ? and_result :
                alu_nor  ? nor_result :
                alu_or   ? or_result :
                alu_xor  ? xor_result :
                alu_sll  ? sll_result :
                alu_srl  ? srl_result :
                alu_sra  ? sra_result :
                alu_lui  ? lui_result :
                32'b0;
```

### 8.3 完成信号

对于组合逻辑运算，done信号始终为1。
对于乘法和除法，done信号表示运算完成。

## 9. 性能分析

### 9.1 延迟分析

| 运算   | 延迟/周期      |
|--------|----------------|
| 加法   | O(log N)       |
| 减法   | O(log N)       |
| 移位   | O(log N)       |
| 逻辑   | O(1)           |
| 乘法   | 32周期         |
| 除法   | 32周期         |

### 9.2 面积估算

- CLA加法器：约32个全加器 + 超前进位逻辑
- 移位器：约5级多路选择器
- 乘法器：约32个加法器 + 寄存器
- 除法器：约2个加法器 + 寄存器

## 10. 测试策略

### 10.1 单元测试

每个模块独立测试，确保功能正确。

### 10.2 集成测试

顶层ALU测试，覆盖所有运算类型和边界情况。

### 10.3 测试用例

- 正常值测试
- 边界值测试（0, 最大值, 最小值）
- 负数测试
- 特殊情况测试

## 11. 设计约束

### 11.1 门级设计约束

- 不使用算术运算符 +, -, *, /
- 不使用关系运算符 <, >, <=, >= (比较逻辑除外)
- 所有算术运算基于加法器

### 11.2 时序约束

- 乘法器和除法器需要32个周期
- 其他运算为组合逻辑

## 12. 未来改进

### 12.1 性能优化

- 使用Wallace树乘法器减少延迟
- 使用SRT除法器减少延迟
- 流水线设计提高吞吐量

### 12.2 功能扩展

- 支持无符号乘除法
- 添加溢出检测
- 添加异常处理
