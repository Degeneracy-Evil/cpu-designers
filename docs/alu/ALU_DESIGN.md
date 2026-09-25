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

减法器不包含独立加法器，而是与ALU顶层共享同一个`cla_adder_32bit`实例。
通过输入选择实现ADD/SUB复用：

- ADD模式：加法器计算 `src1 + src2 + 0`
- SUB/SLT/SLTU模式：加法器计算 `src1 + ~src2 + 1`

### 2.2 实现机制（集成于 alu_32bit 顶层）

```verilog
// b_neg = ~b, 送入共享加法器
// result = adder_sum  (当加法器配置为 a + ~b + 1 时)
// borrow = ~adder_cout
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

- A = 0 (33位，防有符号累加溢出)
- Q = multiplier (32位)
- Q₋₁ = 0 (1位)
- M = {multiplicand[31], multiplicand} (33位符号扩展)

对于每一位（共32次）：

1. 检查Q₀和Q₋₁的值
2. 根据以下规则操作：
   - 00或11：不操作
   - 01：A = A + M
   - 10：A = A - M
3. 算术右移{A, Q, Q₋₁}一位

结果：{A[31:0], Q}为64位乘积

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
    input         resetn,
    input  [31:0] multiplicand,
    input  [31:0] multiplier,
    input         start,
    output [63:0] product,
    output        done
);
    // 状态机
    // Booth算法实现
    // 32拍迭代完成
endmodule
```

## 7. 非恢复余数除法器

### 7.1 非恢复余数（Non-Restoring）算法

与恢复余数除法（R<0时回加恢复）不同：余数为负时不恢复，下一拍改做加法（R + D），加减交替进行，最后用一次修正（FIX）收尾，省去每拍的恢复加法。

### 7.2 算法步骤

初始化：

- R = 0 (32位余数)
- Q = |dividend| (被除数绝对值)
- D = |divisor| (除数绝对值)

对于每一位（共32次）：

1. 左移{R, Q}一位
2. 按当前R的符号选择操作：
   - R >= 0：R = R - D
   - R < 0：R = R + D
3. 上商：新R >= 0 则 Q[0] = 1，否则 Q[0] = 0

修正（FIX阶段）：

- 若终态R < 0：R = R + D

结果：

- Q为商（绝对值）
- R为余数（绝对值）

### 7.3 符号处理

1. 记录被除数和除数的符号
2. 使用绝对值进行计算
3. 商的符号 = 被除数符号 XOR 除数符号
4. 余数的符号 = 被除数的符号

### 7.4 状态机设计

```
IDLE -> COMPUTE -> FIX -> FINISH -> IDLE
```

- **IDLE**: 等待start信号，初始化；特殊情形直接出结果（除零、有符号溢出、无符号大除数）
- **COMPUTE**: 执行32次迭代
- **FIX**: 终态余数为负时修正 R = R + D
- **FINISH**: 商/余数按符号取补，输出结果

## 8. 顶层集成（当前架构）

当前为「组合 ALU + 独立多周期 MU」双单元架构，二者职责分离：

- `alu_32bit`：纯组合逻辑，无时钟、无握手，`result` 同拍直出，CPU EX 阶段同拍采样。接口见 `ALU_INTERFACE.md`。
- `mu_unit`：多周期乘除法单元，`mu_funct3` 直接对应 RV32M 指令 funct3。接口与时序见 `MU_INTERFACE.md`。

mu_unit 关键信号：

| 信号 | 方向 | 说明 |
|------|------|------|
| req_valid | 输入 | 请求有效，CPU 发起运算请求 |
| mu_ready | 输出 | MU 可接收新请求 |
| result_valid | 输出 | 当前 result 为有效结果 |
| result_got | 输入 | 下游已消费结果 |
| mu_busy | 输出 | 乘法或除法执行中 |
| flush | 输入 | 清空顶层请求状态 |
| div_by_zero | 输出 | 最近一次已接收 DIV 请求是否为除零 |

## 9. 性能与资源分析（按当前实现）

### 9.1 延迟/周期

| 运算类型 | 周期特性 |
|----------|----------|
| ADD/SUB/SLT/SLTU/AND/OR/XOR/NOR/SLL/SRL/SRA/LUI | 纯组合，同拍直出 |
| MUL | 33拍（1 IDLE + 32 COMPUTE + 1 FINISH） |
| DIV/REM | 34拍（1 IDLE + 32 COMPUTE + 1 FIX + 1 FINISH）；除零/溢出/大除数特殊路径 2 拍 |

### 9.2 关键优化点

1. 顶层移位器由3实例收敛为1实例复用，降低面积与扇出。
2. 减法器取消独立加法器，与ADD共享同一`cla_adder_32bit`实例，通过`is_sub`信号选择加法器输入（`b_neg`/`src2`）与进位（`1`/`0`），加法器实例数从2降至1。
3. `logic_unit`复用顶层减法结果，去除重复加减链。
4. 结果选择器由串行MUX链改为并行掩码与归约OR，缩短组合路径。

## 10. 边界行为与异常语义

### 10.1 除零（RV32M 语义）

除数为0时（有符号/无符号）：`quotient = 0xFFFFFFFF`，`remainder = dividend`。顶层同时置位`div_by_zero`。

### 10.2 整数溢出边界

有符号 `INT_MIN / -1`：`quotient = 0x80000000 (INT_MIN)`，`remainder = 0`（二补码截断语义）。

## 11. 测试与回归

- `isa_alu`：ALU 全部指令
- `isa_m_ext`：RV32M 全部乘除法指令（含除零、INT_MIN/-1 溢出边界）

```bash
python3 -m tools.vivado sim isa_alu
python3 -m tools.vivado sim isa_m_ext
```

## 12. 设计约束与后续改进

### 12.1 当前约束

1. 乘法器、除法器仍为迭代实现，吞吐率为“单发射、完成后再发射”。
2. `flush` 仅作用于 mu_unit 顶层，不下沉到乘除法子模块内部状态机（迟到完成脉冲由顶层活动标志过滤）。

### 12.2 后续建议

1. 为多周期请求增加`req_id`或序号，支持更严格的结果匹配。
2. 将`flush/kill`扩展到子模块以降低无效计算开销。
3. 增加`overflow/zero/negative`标志输出，减少CPU侧重复判断逻辑。
