# 07 - 异常与中断机制

## 1. 设计原则

- 参考 RISC-V 特权架构，在课程实验范围内合理精简
- 仅实现 M-mode trap 处理（不实现 S-mode、delegation）
- 必须能区分：非法指令、ecall、地址未对齐、EBREAK、外部中断

## 2. Trap 进入流程

当异常或中断发生时：

1. **mepc** ← 触发 trap 的指令 PC（中断为当前指令，异常为该指令本身）
2. **mcause** ← trap 原因编码（Interrupt bit + Exception Code）
3. **mtval** ← 附加信息（非法指令→指令编码，地址未对齐→访存地址，其余→0）
4. **mstatus.MPIE** ← mstatus.MIE
5. **mstatus.MIE** ← 0（禁用中断）
6. **mstatus.MPP** ← 当前特权模式
7. **PC** ← mtvec.BASE（MODE=Direct）或 mtvec.BASE + 4×cause（MODE=Vectored）

## 3. MRET 返回流程

1. **PC** ← mepc
2. **mstatus.MIE** ← mstatus.MPIE
3. **mstatus.MPIE** ← 1
4. **特权模式** ← mstatus.MPP
5. **mstatus.MPP** ← U（最低特权模式）

## 4. 异常检测

### 4.1 非法指令（Exception Code = 2）

以下情况触发非法指令异常：
- opcode 未定义
- funct3/funct7 组合未定义
- 访问不存在的 CSR 地址
- 访问无权限的 CSR

### 4.2 ecall（Exception Code = 8 或 11）

- U-mode 执行 ecall → mcause = 8
- M-mode 执行 ecall → mcause = 11

### 4.3 EBREAK（Exception Code = 3）

- 触发断点异常，mcause = 3

### 4.4 地址未对齐（Exception Code = 0/4/6）

| 异常 | Code | 触发条件 |
|------|------|----------|
| Instruction address misaligned | 0 | JAL/JALR 目标地址未 4 字节对齐 |
| Load address misaligned | 4 | LH/LHU/LW 地址未对齐 |
| Store/AMO address misaligned | 6 | SH/SW 地址未对齐 |

## 5. 中断检测

### 5.1 中断判定条件

中断 i 被响应的条件（同时满足）：
1. mstatus.MIE = 1（全局中断使能）
2. mie[i] = 1（该中断使能）
3. mip[i] = 1（该中断等待中）

### 5.2 中断响应时机

- 在每条指令执行完毕后、下一条指令取指前检测
- 若有中断待响应，进入 TRAP_ENTER 状态
- 中断优先级：同时有多个中断时，按 cause 编号从小到大响应

### 5.3 UART 接收中断

- UART 接收缓冲区非空时，置 mip.MEIP = 1
- mie.MEIE = 1 且 mstatus.MIE = 1 时，CPU 响应中断
- 中断处理程序从 UART 数据寄存器读取数据
- 读取后 UART 清除 RX ready 标志，若缓冲区空则 mip.MEIP ← 0

## 6. CSR 寄存器

详见 `03-instruction-set.md` 第 5 节。
