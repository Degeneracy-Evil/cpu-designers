# 03 - 指令集实现定义

本文档定义本项目需要实现的全部指令，包括编码、语义与实现策略。所有编码数据严格依据 RISC-V 非特权手册（Volume I）与特权手册（Volume II）。

---

## 1. 实现范围

- **基础指令集**：RV32I（40 条）
- **CSR 扩展**：Zicsr（6 条）
- **指令缓存扩展**：Zifencei（1 条 FENCE.I，作为 NOP 处理）
- **总计**：47 条指令

不实现的扩展：RV32M、RV32A、RV32F、RV32D、RV32C。

---

## 2. 指令格式

所有指令均为 32 位，采用以下六种格式：

```
31        25 24   20 19  15 14  12 11    7 6      0
┌───────────┬──────┬──────┬─────┬───────┬───────┐
│  funct7   │  rs2 │  rs1 │funct3│   rd  │ opcode│  R-Type
├───────────┼──────┼──────┼─────┼───────┼───────┤
│  imm[11:0]│  rs1 │funct3│   rd  │ opcode│  I-Type
├───────────┼──────┼──────┼─────┼───────┼───────┤
│ imm[11:5] │  rs2 │  rs1 │funct3│imm[4:0]│ opcode│  S-Type
├───────────┼──────┼──────┼─────┼───────┼───────┤
│imm[12|10:5│  rs2 │  rs1 │funct3│imm[4:1|11]│opcode│  B-Type
├───────────┼──────┼──────┼─────┼───────┼───────┤
│    imm[31:12]     │   rd  │ opcode│  U-Type
├───────────┼──────┼──────┼─────┼───────┼───────┤
│imm[20|10:1|11|19:12]   │   rd  │ opcode│  J-Type
└───────────┴──────┴──────┴─────┴───────┴───────┘
```

### 立即数生成

| 格式 | 立即数位域构造 |
|------|---------------|
| I-Type | `imm = {{20{inst[31]}}, inst[31:20]}` |
| S-Type | `imm = {{20{inst[31]}}, inst[31:25], inst[11:7]}` |
| B-Type | `imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` |
| U-Type | `imm = {inst[31:12], 12'b0}` |
| J-Type | `imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` |

---

## 3. RV32I 基础指令集

### 3.1 R-Type 寄存器运算指令（opcode = 0110011）

| 指令 | funct7 | funct3 | 语义 | 实现策略 |
|------|--------|--------|------|----------|
| ADD  | 0000000 | 000 | `rd = rs1 + rs2` | ALU 加法 |
| SUB  | 0100000 | 000 | `rd = rs1 - rs2` | ALU 减法 |
| SLL  | 0000000 | 001 | `rd = rs1 << rs2[4:0]` | ALU 逻辑左移 |
| SLT  | 0000000 | 010 | `rd = (rs1 < rs2) ? 1 : 0`（有符号比较） | ALU SLT |
| SLTU | 0000000 | 011 | `rd = (rs1 < rs2) ? 1 : 0`（无符号比较） | ALU SLTU |
| XOR  | 0000000 | 100 | `rd = rs1 ^ rs2` | ALU 异或 |
| SRL  | 0000000 | 101 | `rd = rs1 >> rs2[4:0]`（逻辑右移） | ALU 逻辑右移 |
| SRA  | 0100000 | 101 | `rd = rs1 >>> rs2[4:0]`（算术右移） | ALU 算术右移 |
| OR   | 0000000 | 110 | `rd = rs1 \| rs2` | ALU 或 |
| AND  | 0000000 | 111 | `rd = rs1 & rs2` | ALU 与 |

### 3.2 I-Type 立即数运算指令（opcode = 0010011）

| 指令 | funct7 | funct3 | 语义 | 实现策略 |
|------|--------|--------|------|----------|
| ADDI  | - | 000 | `rd = rs1 + imm` | ALU 加法 |
| SLTI  | - | 010 | `rd = (rs1 < imm) ? 1 : 0`（有符号） | ALU SLT |
| SLTIU | - | 011 | `rd = (rs1 < imm) ? 1 : 0`（无符号，imm 先符号扩展再按无符号比较） | ALU SLTU |
| XORI  | - | 100 | `rd = rs1 ^ imm` | ALU 异或 |
| ORI   | - | 110 | `rd = rs1 \| imm` | ALU 或 |
| ANDI  | - | 111 | `rd = rs1 & imm` | ALU 与 |
| SLLI  | 0000000 | 001 | `rd = rs1 << shamt`（shamt = inst[24:20]） | ALU 逻辑左移 |
| SRLI  | 0000000 | 101 | `rd = rs1 >> shamt`（逻辑右移） | ALU 逻辑右移 |
| SRAI  | 0100000 | 101 | `rd = rs1 >>> shamt`（算术右移） | ALU 算术右移 |

> 注：SLLI/SRLI/SRAI 的 funct7 即 inst[31:25]，shamt = inst[24:20]（5 位，移位量 0~31）。

### 3.3 Load 指令（opcode = 0000011）

| 指令 | funct3 | 语义 | 实现策略 |
|------|--------|------|----------|
| LB  | 000 | `rd = SignExt(Mem[rs1 + imm][7:0])` | dMem 读，符号扩展 |
| LH  | 001 | `rd = SignExt(Mem[rs1 + imm][15:0])` | dMem 读，符号扩展，地址须半字对齐 |
| LW  | 010 | `rd = Mem[rs1 + imm][31:0]` | dMem 读，地址须字对齐 |
| LBU | 100 | `rd = ZeroExt(Mem[rs1 + imm][7:0])` | dMem 读，零扩展 |
| LHU | 101 | `rd = ZeroExt(Mem[rs1 + imm][15:0])` | dMem 读，零扩展，地址须半字对齐 |

> 访存地址 = rs1 + sign-extended imm。地址未对齐时触发 Load address misaligned 异常。

### 3.4 Store 指令（opcode = 0100011）

| 指令 | funct3 | 语义 | 实现策略 |
|------|--------|------|----------|
| SB | 000 | `Mem[rs1 + imm][7:0] = rs2[7:0]` | dMem 写，存 1 字节 |
| SH | 001 | `Mem[rs1 + imm][15:0] = rs2[15:0]` | dMem 写，存 2 字节，地址须半字对齐 |
| SW | 010 | `Mem[rs1 + imm][31:0] = rs2[31:0]` | dMem 写，存 4 字节，地址须字对齐 |

> 访存地址 = rs1 + sign-extended imm。地址未对齐时触发 Store/AMO address misaligned 异常。

### 3.5 Branch 指令（opcode = 1100011）

| 指令 | funct3 | 语义 | 实现策略 |
|------|--------|------|----------|
| BEQ  | 000 | `if (rs1 == rs2) PC += imm` | ALU 减法判零 |
| BNE  | 001 | `if (rs1 != rs2) PC += imm` | ALU 减法判零 |
| BLT  | 100 | `if (rs1 < rs2) PC += imm`（有符号） | ALU SLT |
| BGE  | 101 | `if (rs1 >= rs2) PC += imm`（有符号） | ALU SLT 取反 |
| BLTU | 110 | `if (rs1 < rs2) PC += imm`（无符号） | ALU SLTU |
| BGEU | 111 | `if (rs1 >= rs2) PC += imm`（无符号） | ALU SLTU 取反 |

> 跳转目标 = PC + imm（imm 由 B-Type 立即数生成，始终为偶数）。条件不满足时 PC += 4。

### 3.6 Jump 指令

| 指令 | opcode | 格式 | funct3 | 语义 | 实现策略 |
|------|--------|------|--------|------|----------|
| JAL  | 1101111 | J | - | `rd = PC + 4; PC = PC + imm` | 写返回地址，跳转 |
| JALR | 1100111 | I | 000 | `rd = PC + 4; PC = (rs1 + imm) & ~1` | 写返回地址，间接跳转，清最低位 |

> JAL 跳转目标 = PC + imm（imm 由 J-Type 立即数生成）。
> JALR 跳转目标 = (rs1 + sign-extended imm) & ~1，清除最低有效位。
> 若跳转目标未对齐到 4 字节边界，触发 Instruction address misaligned 异常。

### 3.7 Upper Immediate 指令

| 指令 | opcode | 格式 | 语义 | 实现策略 |
|------|--------|------|------|----------|
| LUI   | 0110111 | U | `rd = imm`（imm = inst[31:12] << 12） | ALU LUI |
| AUIPC | 0010111 | U | `rd = PC + imm`（imm = inst[31:12] << 12） | PC + 立即数 |

### 3.8 System 指令（opcode = 1110011）

| 指令 | 编码（inst[31:0]） | 语义 | 实现策略 |
|------|---------------------|------|----------|
| ECALL  | `0000000 00000 000 00000 1110011` | 触发 Environment call 异常 | 进入 trap，mcause = 8（U-mode）或 11（M-mode） |
| EBREAK | `0000000 00001 000 00000 1110011` | 触发 Breakpoint 异常 | 进入 trap，mcause = 3 |

### 3.9 FENCE 指令（opcode = 0001111）

| 指令 | funct3 | 语义 | 实现策略 |
|------|--------|------|----------|
| FENCE   | 000 | 内存序屏障 | **NOP**（单 hart，无乱序，无需排序） |
| FENCE.I | 001 | 指令缓存屏障 | **NOP**（Zifencei 扩展，无 I-Cache 一致性问题） |

---

## 4. Zicsr 扩展（CSR 指令）

opcode = 1110011，与 System 指令共享 opcode 空间，通过 funct3 区分。

| 指令 | funct3 | 语义 | 实现策略 |
|------|--------|------|----------|
| CSRRW  | 001 | `t = CSR[csr]; CSR[csr] = rs1; rd = t`（若 rd=x0 则不读） | CSR 读写 |
| CSRRS  | 010 | `t = CSR[csr]; CSR[csr] = t \| rs1; rd = t`（若 rs1=x0 则不写） | CSR 读置位 |
| CSRRC  | 011 | `t = CSR[csr]; CSR[csr] = t & ~rs1; rd = t`（若 rs1=x0 则不写） | CSR 读清除 |
| CSRRWI | 101 | `t = CSR[csr]; CSR[csr] = uimm; rd = t`（若 rd=x0 则不读） | CSR 立即数读写 |
| CSRRSI | 110 | `t = CSR[csr]; CSR[csr] = t \| uimm; rd = t`（若 uimm=0 则不写） | CSR 立即数读置位 |
| CSRRCI | 111 | `t = CSR[csr]; CSR[csr] = t & ~uimm; rd = t`（若 uimm=0 则不写） | CSR 立即数读清除 |

> - `csr` = inst[31:20]，即 12 位 CSR 地址。
> - `uimm` = inst[19:15]，即 rs1 字段被重解释为 5 位无符号立即数。
> - 访问不存在的 CSR 或无权限的 CSR 触发 Illegal instruction 异常。

---

## 5. CSR 寄存器定义

仅实现 Machine 模式下 trap 处理所需的最小 CSR 子集。

### 5.1 CSR 地址映射

| 地址 | 名称 | 读写 | 描述 |
|------|------|------|------|
| 0x300 | mstatus | MRW | Machine 状态寄存器 |
| 0x304 | mie | MRW | Machine 中断使能寄存器 |
| 0x305 | mtvec | MRW | Machine trap 向量基址 |
| 0x340 | mscratch | MRW | Machine 暂存寄存器 |
| 0x341 | mepc | MRW | Machine 异常程序计数器 |
| 0x342 | mcause | MRW | Machine 异常原因 |
| 0x343 | mtval | MRW | Machine trap 值 |
| 0x344 | mip | MRW | Machine 中断等待寄存器 |

> 访问上述范围以外的 CSR 地址视为非法指令异常。

### 5.2 mstatus（0x300）位域定义（RV32）

```
31          13 12 11 10 9 8 7 6 5 4 3 2 1 0
┌─────────────┬───┬───┬───┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   WPRI      │MPP│   │   │ │ │ │ │ │ │ │ │ │
│             │   │   │   │S│M│ │M│ │ │M│ │ │
│             │   │   │   │P│P│ │P│ │ │I│ │ │
│             │   │   │   │P│I│ │I│ │ │E│ │ │
│             │   │   │   │ │E│ │E│ │ │ │ │ │
└─────────────┴───┴───┴───┴─┴─┴─┴─┴─┴─┴─┴─┘
```

本项目仅使用以下位域（其余位保持为 0）：

| 位 | 名称 | 描述 |
|----|------|------|
| 3 | MIE | Machine 全局中断使能。1=使能，0=禁能 |
| 7 | MPIE | trap 前的 MIE 值 |
| 12:11 | MPP | trap 前的特权模式（本项目仅 M/U，故 00=U，11=M） |

**trap 进入时**：MPIE ← MIE，MIE ← 0，MPP ← 当前特权模式
**MRET 返回时**：MIE ← MPIE，MPIE ← 1，特权模式 ← MPP

### 5.3 mie（0x304）位域定义

```
15      12 11  8 7   4 3   0
┌─────────┬─────┬─────┬─────┐
│    0    │MEIE │  0  │MSIE │
│         │     │MTIE │     │
└─────────┴─────┴─────┴─────┘
```

| 位 | 名称 | 描述 |
|----|------|------|
| 3 | MSIE | Machine 软件中断使能 |
| 7 | MTIE | Machine 定时器中断使能 |
| 11 | MEIE | Machine 外部中断使能 |

> 其余位保留为 0。

### 5.4 mip（0x344）位域定义

| 位 | 名称 | 描述 |
|----|------|------|
| 3 | MSIP | Machine 软件中断等待 |
| 7 | MTIP | Machine 定时器中断等待 |
| 11 | MEIP | Machine 外部中断等待 |

> MEIP 由外部中断控制器（UART 等）写入，软件可读不可写。MSIP 可软件读写。

### 5.5 mtvec（0x305）位域定义

```
31          2 1 0
┌─────────────┬───┐
│   BASE      │MODE│
└─────────────┴───┘
```

| 位域 | 描述 |
|------|------|
| BASE [31:2] | trap 向量基址，4 字节对齐 |
| MODE [1:0] | 0=Direct（所有 trap 跳转到 BASE），1=Vectored（中断跳转到 BASE+4×cause） |

> 本项目优先实现 MODE=Direct。

### 5.6 mepc（0x341）

- 发生 trap 时，写入触发异常/中断的指令地址。
- MRET 返回时，PC ← mepc。
- mepc[1:0] 始终为 0（IALIGN=32）。

### 5.7 mcause（0x342）

```
31      30         0
┌───────┬──────────┐
│Interrupt│Exception │
│  bit   │  Code    │
└───────┴──────────┘
```

| 位 | 描述 |
|----|------|
| 31 | Interrupt：1=中断，0=同步异常 |
| 30:0 | Exception Code |

### 5.8 mtval（0x343）

- 异常时写入附加信息。
- 地址未对齐异常：写入触发异常的访存地址。
- 非法指令异常：写入该指令编码。
- 其余异常：写入 0。

### 5.9 mscratch（0x340）

- 通用暂存寄存器，供 trap handler 保存/恢复上下文使用。硬件不自动写入。

---

## 6. 异常与中断原因编码

### 6.1 同步异常编码（Interrupt bit = 0）

| Code | 名称 | 描述 | 本项目是否实现 |
|------|------|------|----------------|
| 0 | Instruction address misaligned | 取指地址未对齐 | 是 |
| 2 | Illegal instruction | 非法指令 | 是 |
| 3 | Breakpoint | 断点（EBREAK） | 是 |
| 4 | Load address misaligned | Load 地址未对齐 | 是 |
| 6 | Store/AMO address misaligned | Store 地址未对齐 | 是 |
| 8 | Environment call from U-mode | U-mode ecall | 是 |
| 11 | Environment call from M-mode | M-mode ecall | 是 |

> Code 1（Instruction access fault）、5（Load access fault）、7（Store/AMO access fault）在无 MMU 的实现中不会发生，不实现。

### 6.2 中断编码（Interrupt bit = 1）

| Code | 名称 | 描述 | 本项目是否实现 |
|------|------|------|----------------|
| 3 | Machine software interrupt | 软件中断 | 是 |
| 7 | Machine timer interrupt | 定时器中断 | 否（暂不实现定时器） |
| 11 | Machine external interrupt | 外部中断（UART等） | 是 |

---

## 7. 指令译码快速参考

### 7.1 opcode 译码表

| opcode[6:0] | 类型 | 用途 |
|-------------|------|------|
| 0110111 | U | LUI |
| 0010111 | U | AUIPC |
| 1101111 | J | JAL |
| 1100111 | I | JALR |
| 1100011 | B | Branch |
| 0000011 | I | Load |
| 0100011 | S | Store |
| 0010011 | I | OP-IMM |
| 0110011 | R | OP |
| 0001111 | I | FENCE / FENCE.I |
| 1110011 | I | SYSTEM / CSR |

### 7.2 译码优先级

1. 先按 opcode 确定指令大类
2. 按 funct3 细分（Branch、Load、Store、OP-IMM、OP）
3. 按 funct7 进一步区分（ADD/SUB、SRL/SRA、SLLI/SRLI/SRAI）
4. opcode=1110011 时：funct3=0 为 SYSTEM（ECALL/EBREAK 按 funct7/rs2 区分），funct3≠0 为 CSR 指令
5. opcode=0001111 时：funct3=0 为 FENCE，funct3=1 为 FENCE.I

---

## 8. 实现统计

| 类别 | 指令数 | 指令 |
|------|--------|------|
| R-Type 寄存器运算 | 10 | ADD SUB SLL SLT SLTU XOR SRL SRA OR AND |
| I-Type 立即数运算 | 9 | ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI |
| Load | 5 | LB LH LW LBU LHU |
| Store | 3 | SB SH SW |
| Branch | 6 | BEQ BNE BLT BGE BLTU BGEU |
| Jump | 2 | JAL JALR |
| Upper Immediate | 2 | LUI AUIPC |
| System | 4 | ECALL EBREAK FENCE FENCE.I |
| CSR (Zicsr) | 6 | CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI |
| **合计** | **47** | |
