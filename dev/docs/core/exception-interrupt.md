# 异常与中断机制

## 1. 设计原则

- 参考 RISC-V 特权架构，实现 M-mode 和 S-mode trap 处理
- 支持异常委托（medeleg）和中断委托（mideleg），允许 trap 直接陷入 S-mode
- 必须能区分：非法指令、ecall、地址未对齐、EBREAK、外部中断
- 中断实现支持：MEIP（UART RX）、MTIP（定时器）、MSIP（软件中断），不实现中断嵌套与可编程优先级

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

## 3.5 SRET 返回流程

1. **PC** ← sepc
2. **sstatus.SIE** ← sstatus.SPIE
3. **sstatus.SPIE** ← 1
4. **特权模式** ← S（若 sstatus.SPP=1）或 U（若 sstatus.SPP=0）
5. **sstatus.SPP** ← 0

## 3.6 Trap 委托机制

通过 `medeleg` 和 `mideleg` CSR，M-mode 可以将特定异常和中断委托给 S-mode 处理，避免所有 trap 都陷入 M-mode。

### 异常委托（medeleg）

- `medeleg[i] = 1`：异常代码 i 委托给 S-mode
- 当异常发生时，若 `medeleg[cause] = 1` 且当前特权级 ≤ S-mode，则 trap 陷入 S-mode
- 否则陷入 M-mode
- 已实现的委托位：异常代码 0/2/3/4/6/8/11（对应本项目支持的异常类型）

### 中断委托（mideleg）

- `mideleg[i] = 1`：中断代码 i 委托给 S-mode
- 当中断发生时，若 `mideleg[cause] = 1` 且当前特权级 ≤ S-mode，则 trap 陷入 S-mode
- 否则陷入 M-mode
- 已实现的委托位：中断代码 3/7/11（MSIP/MTIP/MEIP）

### S-mode Trap 进入流程

当 trap 委托至 S-mode 时：

1. **sepc** ← 触发 trap 的指令 PC
2. **scause** ← trap 原因编码
3. **stval** ← 附加信息
4. **sstatus.SPIE** ← sstatus.SIE
5. **sstatus.SIE** ← 0
6. **sstatus.SPP** ← 当前特权模式（U=0, S=1）
7. **PC** ← stvec.BASE（MODE=Direct）或 stvec.BASE + 4×cause（MODE=Vectored）

## 4. 异常检测

### 4.1 非法指令（Exception Code = 2）

以下情况触发非法指令异常：
- opcode 未定义
- funct3/funct7 组合未定义
- 访问不存在的 CSR 地址
- 访问无权限的 CSR

### 4.2 ecall（Exception Code = 8 或 11）

- U-mode 执行 ecall → 若 medeleg[8]=1 则陷入 S-mode（scause=8），否则陷入 M-mode（mcause=8）
- S-mode 执行 ecall → mcause = 11（始终陷入 M-mode）

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

- 在每条指令执行完毕后、下一条指令取指前检测（即 FSM 的指令边界采样点）
- 若有中断待响应，进入 `TRAP_ENTER` 状态
- 对于可变延迟操作（ALU 多周期、访存等待、外设等待），在 `WAIT` 状态期间不抢占
- 若未来扩展多个中断源，使用固定硬编码优先顺序；不引入可编程优先级机制

### 5.3 UART 接收中断

- UART 接收缓冲区非空时，置 mip.MEIP = 1
- mie.MEIE = 1 且 mstatus.MIE = 1 时，CPU 响应中断
- 中断处理程序从 UART 数据寄存器读取数据
- 读取后 UART 清除 RX ready 标志，若缓冲区空则 mip.MEIP ← 0

### 5.4 精确 trap 边界约束

- 若当前指令尚未提交（例如仍在 `MEM_READ_WAIT`），不得提前写入 `mepc/mcause`
- `mepc` 始终记录“将被 trap 打断的那条指令地址”
- 异常优先于中断：同一条指令若触发同步异常，则先处理异常，不响应该边界上的中断

## 6. CSR 寄存器

详见 `instruction-set.md` 第 5 节。
