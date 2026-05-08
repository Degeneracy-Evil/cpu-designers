# ALU 接口规范

## 1. 适用范围

本文档定义 `alu_32bit` 模块的对外接口。ALU 为纯组合逻辑模块，单周期直出结果，无时钟、无握手协议。

## 2. 模块端口

```verilog
module alu_32bit(
    input  [15:0] alu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    output [31:0] result
);
```

## 3. 信号语义

| 信号 | 方向 | 位宽 | 语义 |
|------|------|------|------|
| alu_control | 输入 | 16 | one-hot 操作选择编码，bit0 保留 |
| src1 | 输入 | 32 | 操作数 1（rs1） |
| src2 | 输入 | 32 | 操作数 2（rs2 或立即数） |
| result | 输出 | 32 | 组合运算结果，同拍有效 |

## 4. 控制编码

`alu_control` 使用 16 位 one-hot 编码：

| 位 | 操作 | 指令 |
|----|------|------|
| 0 | — | 保留 |
| 1 | ADD | ADD |
| 2 | SUB | SUB |
| 3 | SRL | SRL |
| 4 | SRA | SRA |
| 5 | SLL | SLL |
| 6 | AND | AND |
| 7 | OR | OR |
| 8 | NOT | — |
| 9 | XOR | XOR |
| 10 | SLT | SLT |
| 11 | SLTU | SLTU |
| 12 | NOR | — |
| 13 | LUI | LUI |
| 14 | — | 保留 |
| 15 | — | 保留 |

## 5. 时序特性

- 纯组合逻辑，无寄存器、无状态
- `result` 在 `alu_control`/`src1`/`src2` 变化后组合直出
- CPU EX 阶段可在同拍采样结果，无需握手等待

## 6. 调试入口

```bash
python3 tools/mk.py --top dev/tb/ALU/tb_alu_cpu_integration.v
```
