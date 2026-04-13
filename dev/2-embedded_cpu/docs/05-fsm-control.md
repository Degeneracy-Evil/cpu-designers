# 05 - 多周期 FSM 控制

## 1. 设计原则

1. 明确区分取指、译码、执行、访存、写回等阶段
2. 主控制逻辑使用有限状态机描述
3. 不同指令类型在执行阶段分流到不同状态路径
4. 异常与中断有独立可识别的 trap 处理状态
5. 状态命名、转移条件、控制信号输出可文档化、可波形验证

## 2. FSM 状态定义

| 状态 | 描述 |
|------|------|
| FETCH | 取指：PC → iMem，读出指令 |
| DECODE | 译码：解析 opcode/funct3/funct7，生成控制信号与立即数 |
| EXECUTE | 执行：R-type/I-type 运算、分支判断、跳转目标计算 |
| EXECUTE_J | 跳转执行：JAL/JALR 计算目标地址，写返回地址 |
| EXECUTE_B | 分支执行：条件判断，决定是否跳转 |
| MEM_ADDR | 访存地址计算：rs1 + imm |
| MEM_READ | 读存储：dMem 读（Load 指令） |
| MEM_WRITE | 写存储：dMem 写（Store 指令） |
| MEM_READ_PERIPH | 读外设：MMIO 读（GPIO/UART） |
| MEM_WRITE_PERIPH | 写外设：MMIO 写（GPIO/UART） |
| WRITE_BACK | 写回：ALU 结果或存储器数据写入寄存器堆 |
| CSR_ACCESS | CSR 读写：执行 CSR 指令 |
| TRAP_ENTER | 进入 trap：保存 mepc/mcause/mstatus，跳转到 mtvec |
| TRAP_RETURN | 返回 trap：MRET，恢复 mstatus，跳转到 mepc |
| ERROR | 非法状态（调试用） |

## 3. 各指令类型的状态路径

### 3.1 R-Type 算术指令（ADD/SUB/SLL/...）

```
FETCH → DECODE → EXECUTE → WRITE_BACK
```

### 3.2 I-Type 立即数运算指令（ADDI/SLTI/...）

```
FETCH → DECODE → EXECUTE → WRITE_BACK
```

### 3.3 Load 指令（LB/LH/LW/LBU/LHU）

```
FETCH → DECODE → MEM_ADDR → MEM_READ → WRITE_BACK
```

> 若地址映射到外设空间：`MEM_ADDR → MEM_READ_PERIPH → WRITE_BACK`

### 3.4 Store 指令（SB/SH/SW）

```
FETCH → DECODE → MEM_ADDR → MEM_WRITE
```

> 若地址映射到外设空间：`MEM_ADDR → MEM_WRITE_PERIPH`

### 3.5 Branch 指令（BEQ/BNE/...）

```
FETCH → DECODE → EXECUTE_B
```

> 条件满足：PC ← PC + imm；条件不满足：PC ← PC + 4

### 3.6 JAL

```
FETCH → DECODE → EXECUTE_J
```

> rd ← PC + 4，PC ← PC + imm

### 3.7 JALR

```
FETCH → DECODE → EXECUTE_J
```

> rd ← PC + 4，PC ← (rs1 + imm) & ~1

### 3.8 LUI / AUIPC

```
FETCH → DECODE → EXECUTE → WRITE_BACK
```

### 3.9 CSR 指令

```
FETCH → DECODE → CSR_ACCESS → WRITE_BACK
```

### 3.10 ECALL / EBREAK

```
FETCH → DECODE → TRAP_ENTER
```

### 3.11 MRET

```
FETCH → DECODE → TRAP_RETURN
```

### 3.12 FENCE / FENCE.I

```
FETCH → DECODE → (NOP, 直接进入下一指令的 FETCH)
```

## 4. 控制信号清单

| 信号 | 描述 |
|------|------|
| pc_write | PC 写使能 |
| pc_source | PC 下一值来源：+4 / ALU结果 / mepc |
| ir_write | 指令寄存器写使能 |
| reg_write | 寄存器堆写使能 |
| reg_dst | 写目标寄存器选择：rd / 无 |
| alu_src_a | ALU A 输入选择：PC / rs1 / 0 |
| alu_src_b | ALU B 输入选择：rs2 / imm / 4 |
| mem_read | 数据存储器读使能 |
| mem_write | 数据存储器写使能 |
| mem_to_reg | 写回数据选择：ALU结果 / 存储器读出 / PC+4 |
| imm_type | 立即数类型选择：I/S/B/U/J |
| csr_write | CSR 写使能 |
| csr_to_reg | 写回数据来自 CSR |
| trap_enter | 进入 trap 信号 |
| trap_return | MRET 返回信号 |

> 具体信号值与 FSM 状态的对应关系在 RTL 实现阶段确定。
