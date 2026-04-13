# ALU顶层接口规范（协议版）

## 1. 适用范围

本文档定义 `alu_32bit` 顶层模块的对外接口与握手时序。当前版本仅支持协议模式，不再支持 legacy 触发方式。

## 2. 模块端口

```verilog
module alu_32bit(
    input         clk,
    input         reset,
    input  [15:0] alu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    input         req_valid,
    input         flush,
    input         result_ready,
    output [31:0] result,
    output        alu_busy,
    output        alu_ready,
    output        result_valid,
    output        illegal_op,
    output        div_by_zero
);
```

## 3. 信号语义

| 信号 | 方向 | 语义 |
|------|------|------|
| req_valid | 输入 | 请求有效，CPU发起运算请求 |
| alu_ready | 输出 | ALU可接收新请求 |
| result_valid | 输出 | 当前result为有效结果 |
| result_ready | 输入 | 下游已消费结果 |
| alu_busy | 输出 | 乘法或除法执行中 |
| flush | 输入 | 清空顶层请求状态 |
| illegal_op | 输出 | `alu_control[15:1]`非法（非one-hot或全零） |
| div_by_zero | 输出 | 最近一次已接收DIV请求是否为除零 |

## 4. 请求接收规则

定义：

- `req_fire = req_valid && alu_ready && !illegal_op`

请求仅在 `req_fire=1` 的那个时钟上升沿被接收。

`alu_ready=0` 的条件：

1. 多周期单元在执行（`alu_busy=1`）
2. 请求保持标志未释放（`req_hold=1`）
3. 结果尚未消费（`result_valid=1` 且 `result_ready=0`）

## 5. 控制编码约束

`alu_control` 使用16位one-hot编码，bit0保留。

合法请求要求：

1. `alu_control[15:1]` 恰有一位为1
2. 若 `req_valid=1` 且编码非法，则 `illegal_op=1`
3. 非法请求不会启动乘除法单元，也不会发布新的 `result_valid`

## 6. 结果发布规则

### 6.1 组合类指令

ADD/SUB/SLT/SLTU/AND/OR/XOR/NOR/SLL/SRL/SRA/LUI：

1. 在 `req_fire` 当拍采样组合结果
2. 下一拍对外可见 `result_valid=1`
3. 若 `result_ready=1`，再下一拍清除 `result_valid`

### 6.2 多周期指令

MUL/DIV：

1. 在 `req_fire` 当拍发射单拍 `start`
2. 执行期间 `alu_busy=1`
3. 完成后锁存结果并拉高 `result_valid`
4. `result_ready=1` 后清除 `result_valid`

## 7. flush语义

`flush=1` 时顶层立即执行：

1. 清除 `mul_busy/div_busy` 与活动标志
2. 清除 `result_valid`
3. 清除 `div_by_zero`
4. 清除请求保持状态

说明：`flush` 仅作用于顶层，不强制中止乘除法子模块内部迭代。顶层通过活动标志过滤迟到完成脉冲，避免旧结果回灌。

## 8. 除零与边界语义

1. 除零约定：`quotient=0`，`remainder=dividend`
2. 顶层在接收除零DIV请求时置位 `div_by_zero`
3. `div_by_zero` 在下一次合法请求或 `flush/reset` 后清除
4. `INT_MIN / -1` 采用二补码截断语义

## 9. CPU接入最小流程

1. 发射：`req_valid = ex_valid && alu_ready`
2. 停顿：`!alu_ready` 时冻结发射级
3. 回写：`result_valid && wb_ready` 时采样 `result`
4. 消费确认：将 `result_ready` 拉高一个周期
5. 冲刷：分支错误或异常时 `flush` 拉高一个周期

## 10. 调试建议

推荐使用集成测试入口：

```powershell
python .\mk.py --top .\dev\1-alu\tb\tb_alu_cpu_integration.v
```

重点观察信号：`req_valid`、`alu_ready`、`alu_busy`、`result_valid`、`illegal_op`、`div_by_zero`。
