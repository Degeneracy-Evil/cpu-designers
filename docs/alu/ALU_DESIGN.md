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

### 2.2 实现

```verilog
module subtractor(
    input  [31:0] b,
    output [31:0] b_neg,       // ~b, 送入共享加法器
    input  [31:0] adder_sum,   // 共享加法器的和输出
    input         adder_cout,  // 共享加法器的进位输出
    output [31:0] result,
    output        borrow
);
    // b_neg = ~b
    // result = adder_sum  (当加法器配置为 a + ~b + 1 时)
    // borrow = ~adder_cout
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

## 8. 顶层ALU模块（CPU集成版）

### 8.1 端口与职责

顶层ALU采用请求-响应握手协议，所有请求都需要显式驱动`req_valid`。

关键信号如下：

| 信号 | 方向 | 说明 |
|------|------|------|
| req_valid | 输入 | 请求有效。协议模式下由CPU发起请求。 |
| flush | 输入 | 取消当前顶层请求状态（例如分支冲刷）。 |
| result_ready | 输入 | CPU已消费结果。用于清除`result_valid`保持。 |
| alu_ready | 输出 | ALU可接收新请求。 |
| alu_busy | 输出 | 多周期单元（乘/除）执行中。 |
| result_valid | 输出 | 当前`result`有效。协议模式下应以此为准。 |
| illegal_op | 输出 | 非法操作编码（非one-hot或空操作）。 |
| div_by_zero | 输出 | 最近一次已接收除法请求是否为除零。 |

### 8.2 控制编码约束

`alu_control`保持16位one-hot编码（bit0保留未使用），合法操作要求：

1. `alu_control[15:1]`中恰有1位为1。
2. 在协议模式下，若请求有效但编码非法，`illegal_op=1`，请求不发射到多周期单元。

### 8.3 使用模式

#### 协议模式（唯一模式）

CPU侧推荐仅依据以下握手：

1. 发请求：`req_valid=1`且`alu_ready=1`。
2. 取结果：等待`result_valid=1`，读取`result`。
3. 消费确认：`result_ready=1`以释放保持状态。

### 8.4 请求接收与执行规则

#### 请求发射（req_fire）

满足以下条件时，顶层接收请求：

1. `req_valid=1`
2. `alu_ready=1`
3. `illegal_op=0`

其中`alu_ready`在以下情况为0：

1. 正在执行乘法/除法（`alu_busy=1`）
2. 前一请求仍在保持（`req_hold=1`）
3. 结果尚未被消费（`result_valid=1`且`result_ready=0`）

#### 多周期请求（MUL/DIV）

1. 仅在`req_fire`时产生单拍`start`脉冲。
2. 输入操作数在启动时锁存，执行期间外部`src1/src2`变化不影响本次运算。
3. 完成后锁存结果并拉高`result_valid`。

#### 组合请求（ADD/SUB/LOGIC/SHIFT/LUI）

1. 在请求拍采样组合结果并写入结果保持寄存器。
2. 对外通过`result_valid`发布一次结果有效。

### 8.5 flush语义

`flush=1`时，顶层执行以下动作：

1. 清除`mul_busy/div_busy`与活动标志。
2. 清除`result_valid`与请求保持状态。
3. 清除`div_by_zero`状态。

说明：当前`flush`仅作用于顶层状态，不强制中止乘除法子模块内部迭代。顶层通过活动标志过滤迟到完成脉冲，避免冲刷后旧结果回灌。

### 8.6 result与result_valid关系

1. `result`由寄存器保持，只有`result_valid=1`时才表示新结果可用。
2. `result_ready=1`后，下一拍清除`result_valid`。
3. 对于非法编码请求，CPU应检查`illegal_op`，且不会发布新的`result_valid`。

### 8.7 协议时序示意

#### 组合指令（协议模式）

```txt
cycle N   : req_valid=1, alu_ready=1, alu_control=ADD
cycle N+1 : result_valid=1, result稳定
cycle N+1 : 若result_ready=1，则下一拍释放result_valid
```

#### 多周期指令（MUL/DIV）

```txt
cycle N      : req_valid=1, alu_ready=1, 发射start脉冲
cycle N+1..K : alu_busy=1
cycle K+1    : result_valid=1, result输出锁存值
后续         : result_ready=1后清除result_valid
```

#### flush场景

```txt
执行中收到flush -> 顶层busy/result_valid清零
子模块若后续完成脉冲到达 -> 顶层不发布result_valid
```

## 9. 性能与资源分析（按当前实现）

### 9.1 延迟/周期

| 运算类型 | 周期特性 |
|----------|----------|
| ADD/SUB/SLT/SLTU/AND/OR/XOR/NOR/SLL/SRL/SRA/LUI | 组合计算 + 1拍结果发布（协议模式） |
| MUL | 32次迭代 + 完成发布 |
| DIV | 32次迭代 + 修正阶段 + 完成发布 |

### 9.2 关键优化点

1. 顶层移位器由3实例收敛为1实例复用，降低面积与扇出。
2. 减法器取消独立加法器，与ADD共享同一`cla_adder_32bit`实例，通过`is_sub`信号选择加法器输入（`b_neg`/`src2`）与进位（`1`/`0`），加法器实例数从2降至1。
3. `logic_unit`复用顶层减法结果，去除重复加减链。
4. 结果选择器由串行MUX链改为并行掩码与归约OR，缩短组合路径。

## 10. 边界行为与异常语义

### 10.1 除零

1. 除法器约定：除零时`quotient=0`，`remainder=dividend`。
2. 顶层在接收除零请求时置位`div_by_zero`。
3. `div_by_zero`在下一次合法请求或`flush/reset`后清除。

### 10.2 整数溢出边界

除法器内显式处理`INT_MIN / -1`，返回二补码截断语义结果。

### 10.3 非法操作编码

当请求有效但`alu_control`不是合法one-hot：

1. `illegal_op=1`
2. 不启动乘除法单元
3. 不发布新的`result_valid`

## 11. 测试与回归

### 11.1 既有功能回归

`tb_alu_cpu_integration.v`作为顶层回归入口，覆盖组合类运算与多周期请求在握手协议下的行为。

### 11.2 CPU集成回归

`tb_alu_cpu_integration.v`新增以下协议场景：

1. `req_valid`持续高电平时，多周期请求不重复触发。
2. 非法one-hot请求被拒绝且不产生执行。
3. 执行中`flush`后，不发布旧结果。
4. `div_by_zero`置位与清除路径验证。

## 12. CPU接入建议

### 12.1 EX阶段最小接线

1. 发射：`ex_valid && alu_ready`时驱动`req_valid=1`。
2. 停顿：`~alu_ready`时冻结发射级寄存器。
3. 写回：`result_valid && wb_ready`时采样`result`。
4. 冲刷：分支错误/异常时拉高`flush`一个周期。

### 12.2 推荐判定优先级

1. `flush`
2. `illegal_op`
3. `result_valid`

## 13. 设计约束与后续改进

### 13.1 当前约束

1. 乘法器、除法器仍为迭代实现，吞吐率为“单发射、完成后再发射”。
2. `flush`尚未下沉到乘除法子模块内部状态机。

### 13.2 后续建议

1. 为多周期请求增加`req_id`或序号，支持更严格的结果匹配。
2. 将`flush/kill`扩展到子模块以降低无效计算开销。
3. 增加`overflow/zero/negative`标志输出，减少CPU侧重复判断逻辑。
