---
name: rv32i
description: |
  RV32I + Zicsr instruction set implementation guide for the embedded CPU project.
  Use this skill when implementing, debugging, or verifying any RV32I instruction,
  CSR register, or instruction decoding logic.
---

# RV32I 指令实现指导

## opcode 译码

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

## 译码优先级

1. opcode → 指令大类
2. funct3 → 细分（Branch/Load/Store/OP-IMM/OP）
3. funct7 → 进一步区分（ADD/SUB, SRL/SRA, SLLI/SRLI/SRAI）
4. opcode=1110011 且 funct3=0 → SYSTEM（ECALL/EBREAK），funct3≠0 → CSR
5. opcode=0001111 → FENCE(funct3=0) / FENCE.I(funct3=1)

## 立即数生成

| 格式 | 构造 |
|------|------|
| I | `{{20{inst[31]}}, inst[31:20]}` |
| S | `{{20{inst[31]}}, inst[31:25], inst[11:7]}` |
| B | `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` |
| U | `{inst[31:12], 12'b0}` |
| J | `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` |

## 指令编码表（紧凑版）

**R-Type（opcode=0110011）**

| 指令 | funct7 | funct3 |
|------|--------|--------|
| ADD  | 0000000 | 000 |
| SUB  | 0100000 | 000 |
| SLL  | 0000000 | 001 |
| SLT  | 0000000 | 010 |
| SLTU | 0000000 | 011 |
| XOR  | 0000000 | 100 |
| SRL  | 0000000 | 101 |
| SRA  | 0100000 | 101 |
| OR   | 0000000 | 110 |
| AND  | 0000000 | 111 |

**I-Type 运算（opcode=0010011）**

| 指令 | funct7 | funct3 |
|------|--------|--------|
| ADDI  | - | 000 |
| SLTI  | - | 010 |
| SLTIU | - | 011 |
| XORI  | - | 100 |
| ORI   | - | 110 |
| ANDI  | - | 111 |
| SLLI  | 0000000 | 001 |
| SRLI  | 0000000 | 101 |
| SRAI  | 0100000 | 101 |

**Load（opcode=0000011）**：LB(000) LH(001) LW(010) LBU(100) LHU(101)
**Store（opcode=0100011）**：SB(000) SH(001) SW(010)
**Branch（opcode=1100011）**：BEQ(000) BNE(001) BLT(100) BGE(101) BLTU(110) BGEU(111)
**Jump**：JAL(1101111,J-type) JALR(1100111,I-type,funct3=000)
**Upper**：LUI(0110111,U-type) AUIPC(0010111,U-type)
**System**：ECALL / EBREAK（opcode=1110011, funct3=0）
**FENCE**：FENCE(0001111,funct3=000) FENCE.I(0001111,funct3=001) → 均为 NOP
**CSR（opcode=1110011）**：CSRRW(001) CSRRS(010) CSRRC(011) CSRRWI(101) CSRRSI(110) CSRRCI(111)

## CSR 寄存器

| 地址 | 名称 | 描述 |
|------|------|------|
| 0x300 | mstatus | MIE(bit3), MPIE(bit7), MPP(bits12:11) |
| 0x304 | mie | MSIE(bit3), MTIE(bit7), MEIE(bit11) |
| 0x305 | mtvec | BASE[31:2], MODE[1:0]（0=Direct） |
| 0x340 | mscratch | 暂存 |
| 0x341 | mepc | trap 指令地址 |
| 0x342 | mcause | bit31=Interrupt, bits30:0=Code |
| 0x343 | mtval | 附加信息 |
| 0x344 | mip | MSIP(bit3), MTIP(bit7), MEIP(bit11) |

## 异常编码

| Code | 名称 | 实现 |
|------|------|------|
| 0 | Instruction address misaligned | 是 |
| 2 | Illegal instruction | 是 |
| 3 | Breakpoint | 是 |
| 4 | Load address misaligned | 是 |
| 6 | Store/AMO address misaligned | 是 |
| 8 | ecall from U-mode | 是 |
| 11 | ecall from M-mode | 是 |

## 详细规格

完整指令语义与实现策略见 `docs/03-instruction-set.md`
