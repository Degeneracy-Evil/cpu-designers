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

| 位 | 十六进制 | 操作 | 指令 | 说明 |
|----|----------|------|------|------|
| 0 | — | — | 保留 | |
| 1 | 0x0002 | LUI | LUI | 高位加载 |
| 2 | 0x0004 | SRA | SRA/SRAI | 算术右移 |
| 3 | 0x0008 | SRL | SRL/SRLI | 逻辑右移 |
| 4 | 0x0010 | SLL | SLL/SLLI | 逻辑左移 |
| 5 | 0x0020 | XOR | XOR/XORI | 按位异或 |
| 6 | 0x0040 | OR | OR/ORI | 按位或 |
| 7 | 0x0080 | NOR | — | 按位或非 |
| 8 | 0x0100 | AND | AND/ANDI | 按位与 |
| 9 | 0x0200 | SLTU | SLTU/SLTIU | 无符号小于 |
| 10 | 0x0400 | SLT | SLT/SLTI | 有符号小于 |
| 11 | 0x0800 | SUB | SUB | 减法 |
| 12 | 0x1000 | ADD | ADD/ADDI/AUIPC/Load/Store/JAL/JALR/Branch | 加法 |
| 13 | 0x2000 | NOT | — | 按位取反 |
| 14 | 0x4000 | — | 保留（DIV 由 mu_unit 处理） | |
| 15 | 0x8000 | — | 保留（MUL 由 mu_unit 处理） | |

> 注：MUL(bit15) 和 DIV(bit14) 保留位仅用于 `QUICK_REF.md` 中的控制信号速查，
> 实际乘除法由 `mu_unit` 模块通过 `mu_funct3` 编码执行，不经过 `alu_32bit`。

## 5. 时序特性

- 纯组合逻辑，无寄存器、无状态
- `result` 在 `alu_control`/`src1`/`src2` 变化后组合直出
- CPU EX 阶段可在同拍采样结果，无需握手等待

## 6. 调试入口

```bash
python3 tools/mk.py --top src/tb/ALU/tb_alu_cpu_integration.v
```
