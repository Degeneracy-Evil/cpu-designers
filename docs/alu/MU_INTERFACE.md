# MU 接口规范

## 1. 适用范围

本文档定义 `mu_unit` 顶层模块及其子模块（`booth_multiplier`、`non_restoring_divider`）的对外接口与握手时序。MU 单元实现 RV32M 扩展全部 8 条乘除法指令。

## 2. mu_unit 模块端口

```verilog
module mu_unit(
    input         clk,
    input         reset,
    input  [2:0]  mu_funct3,
    input  [31:0] src1,
    input  [31:0] src2,
    input         req_valid,
    input         flush,
    input         result_got,
    output [31:0] result,
    output        mu_busy,
    output        mu_ready,
    output        result_valid,
    output        div_by_zero
);
```

## 3. mu_unit 信号语义

| 信号 | 方向 | 语义 |
|------|------|------|
| mu_funct3 | 输入 | 指令 funct3，直接映射 RV32M 操作码 |
| req_valid | 输入 | 请求有效，CPU 发起运算请求 |
| mu_ready | 输出 | MU 可接收新请求 |
| result_valid | 输出 | 当前 result 为有效结果 |
| result_got | 输入 | 下游已消费结果 |
| mu_busy | 输出 | 乘法或除法执行中 |
| flush | 输入 | 清空顶层请求状态 |
| div_by_zero | 输出 | 最近一次已接收 DIV 请求是否为除零 |

## 4. mu_funct3 编码

`mu_funct3` 直接对应 RISC-V 指令 funct3 字段：

| funct3 | 操作 | 语义 |
|--------|------|------|
| 000 | MUL | src1 × src2，取低 32 位 |
| 001 | MULH | src1 × src2（有符号×有符号），取高 32 位 |
| 010 | MULHSU | src1 × src2（有符号×无符号），取高 32 位 |
| 011 | MULHU | src1 × src2（无符号×无符号），取高 32 位 |
| 100 | DIV | src1 ÷ src2（有符号），向零截断 |
| 101 | DIVU | src1 ÷ src2（无符号） |
| 110 | REM | src1 mod src2（有符号），余数与被除数同号 |
| 111 | REMU | src1 mod src2（无符号） |

指令格式：R-type，funct7=0000001，opcode=0110011。

## 5. 请求接收规则

定义：

- `req_fire = req_valid && mu_ready && (is_mul | is_div_rem)`

请求仅在 `req_fire=1` 的时钟上升沿被接收。

`mu_ready=0` 的条件：

1. 多周期单元在执行（`mu_busy=1`）
2. 请求保持标志未释放（`req_hold=1`）
3. 结果尚未消费（`result_valid=1` 且 `result_got=0`）

## 6. 结果选择逻辑

### 6.1 乘法结果

Booth 乘法器输出 64 位 `product`，按 `mu_funct3_reg` 选择：

| mu_funct3_reg | 输出 | 说明 |
|---------------|------|------|
| 000 (MUL) | product[31:0] | 低 32 位直接输出 |
| 001 (MULH) | product[63:32] | 有符号×有符号高 32 位直接输出 |
| 010 (MULHSU) | product[63:32] + (src2[31] ? src1 : 0) | 有符号×无符号修正 |
| 011 (MULHU) | product[63:32] + (src2[31] ? src1 : 0) + (src1[31] ? src2 : 0) | 无符号×无符号修正 |

MULHSU/MULHU 修正原理：Booth 乘法器执行有符号乘法，无符号操作数的高位为 0 而非符号扩展，需通过 CLA 加法器补偿差值。

### 6.2 除法结果

| mu_funct3_reg[1] | 输出 |
|-------------------|------|
| 0 | quotient（DIV/DIVU） |
| 1 | remainder（REM/REMU） |

## 7. 除零与边界语义

遵循 RISC-V M 扩展规范：

| 条件 | quotient | remainder |
|------|----------|-----------|
| divisor = 0（有符号/无符号） | 0xFFFFFFFF | dividend |
| dividend = INT_MIN, divisor = -1（有符号） | INT_MIN (0x80000000) | 0 |

## 8. flush 语义

`flush=1` 时顶层立即执行：

1. 清除 `mul_busy`/`div_busy` 与活动标志
2. 清除 `result_valid`
3. 清除 `div_by_zero`
4. 清除请求保持状态

`flush` 仅作用于顶层，不强制中止乘除法子模块内部迭代。顶层通过活动标志过滤迟到完成脉冲，避免旧结果回灌。

## 9. CPU 接入流程

1. 发射：`req_valid = exe_valid && is_mu && mu_ready`
2. 停顿：`!mu_ready` 时冻结发射级
3. 回写：`result_valid` 时采样 `result`
4. 消费确认：将 `result_got` 拉高一个周期
5. 冲刷：分支错误或异常时 `flush` 拉高一个周期

---

## 10. booth_multiplier 子模块

### 10.1 端口

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
```

### 10.2 信号语义

| 信号 | 方向 | 语义 |
|------|------|------|
| multiplicand | 输入 | 被乘数（32 位） |
| multiplier | 输入 | 乘数（32 位） |
| start | 输入 | 单拍启动脉冲 |
| product | 输出 | 64 位乘积（有符号×有符号） |
| done | 输出 | 计算完成标志，持续 1 拍 |

### 10.3 算法

Booth 编码乘法，33 位累加器（A[32:0]），32 拍迭代：

1. `M <= {multiplicand[31], multiplicand}`（33 位符号扩展）
2. 每拍检查 Booth 对 `{Q[0], Q_1}`：
   - 01：A += M
   - 10：A -= M
   - 00/11：无操作
3. 算术右移 `{A, Q, Q_1}` 一位
4. 32 拍后 `product = {A[31:0], Q}`

A/M 扩展至 33 位防止有符号乘法中累加器溢出（如 INT_MIN × 2 边界）。

### 10.4 时序

- 启动后 33 拍输出 `done=1`（1 拍 IDLE → 32 拍 COMPUTE → 1 拍 FINISH）
- `product` 在 `done=1` 当拍有效

---

## 11. non_restoring_divider 子模块

### 11.1 端口

```verilog
module non_restoring_divider(
    input         clk,
    input         resetn,
    input  [31:0] dividend,
    input  [31:0] divisor,
    input         start,
    input         is_unsigned,
    output [31:0] quotient,
    output [31:0] remainder,
    output        done
);
```

### 11.2 信号语义

| 信号 | 方向 | 语义 |
|------|------|------|
| dividend | 输入 | 被除数（32 位） |
| divisor | 输入 | 除数（32 位） |
| start | 输入 | 单拍启动脉冲 |
| is_unsigned | 输入 | 无符号除法模式（DIVU/REMU） |
| quotient | 输出 | 商 |
| remainder | 输出 | 余数 |
| done | 输出 | 计算完成标志，持续 1 拍 |

### 11.3 算法

非恢复余数除法，4 状态 FSM（IDLE → COMPUTE → FIX → FINISH）：

1. **IDLE**：接收操作数，处理特殊情形：
   - 除零：Q = 0xFFFFFFFF, R = dividend
   - 有符号溢出（INT_MIN / -1）：Q = 0x80000000, R = 0
   - 无符号大除数（`is_unsigned && divisor[31]`）：Q ∈ {0, 1}，直接比较计算
   - 正常：取绝对值进入 COMPUTE
2. **COMPUTE**：32 拍非恢复余数迭代，每拍左移并按 R 符号选择 R-D 或 R+D
3. **FIX**：终态余数为负时修正 R = R + D
4. **FINISH**：输出结果，商/余数按符号取补

`is_unsigned=1` 时：
- 绝对值 mux select 强制为 0（不取反）
- 跳过 INT_MIN / -1 溢出检查
- 大除数特殊路径直接计算 Q ∈ {0, 1}

### 11.4 时序

- 正常路径：34 拍（1 IDLE + 32 COMPUTE + 1 FIX + 1 FINISH → done 在第 35 拍）
- 特殊路径（除零/溢出/大除数）：2 拍（1 IDLE + 1 FINISH）

---

## 12. 调试入口

```bash
python3 -m tools.vivado sim isa_m_ext
```

重点观察信号：`req_valid`、`mu_ready`、`mu_busy`、`result_valid`、`div_by_zero`、`mu_funct3`。
