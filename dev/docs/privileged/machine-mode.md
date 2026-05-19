# Machine-Level ISA (M-Mode)

> 来源：The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Chapter 3, Version 1.13

## 概述

Machine-mode（M-mode）是 RISC-V hart 中最高特权级，也是唯一强制要求的特权级。M-mode 用于对硬件平台的低级访问，是复位后进入的第一个模式。M-mode 也可用于实现那些难以或过于昂贵而无法直接在硬件中实现的功能。

**特权级编码**：`11`（Level 3），缩写 **M**。

### 核心特性

- 唯一的**强制**特权级，所有硬件实现必须提供 M-mode
- 拥有对整台机器的完全访问权限
- 可选的物理内存保护（PMP）机制可在仅有 M-mode 时提供有限保护
- 支持最多 3 种特权模式：M（简单嵌入式）、M,U（安全嵌入式）、M,S,U（类 Unix 系统）
- 复位后 `pc` 跳转至实现定义的复位向量，特权模式为 M

---

## 3.1. Machine-Level CSRs

M-mode 代码可访问所有 CSR（包括更低特权级的 CSR）。以下是 M-mode 核心 CSR 列表：

| CSR 地址 | 名称 | 描述 |
|----------|------|------|
| `0x300` | `mstatus` | 机器状态寄存器 |
| `0x301` | `misa` | 机器 ISA 寄存器，报告 hart 支持的 ISA |
| `0x302` | `medeleg` | 机器异常委托寄存器 |
| `0x303` | `mideleg` | 机器中断委托寄存器 |
| `0x304` | `mie` | 机器中断使能寄存器 |
| `0x305` | `mtvec` | 机器陷阱向量基地址 |
| `0x306` | `mcounteren` | 机器计数器使能 |
| `0x310` | `mstatush` | 机器状态寄存器高32位（仅 RV32） |
| `0x320` | `mcountinhibit` | 机器计数器禁止寄存器 |
| `0x340` | `mscratch` | 机器暂存寄存器 |
| `0x341` | `mepc` | 机器异常程序计数器 |
| `0x342` | `mcause` | 机器陷阱原因 |
| `0x343` | `mtval` | 机器陷阱值 |
| `0x344` | `mip` | 机器中断挂起 |
| `0x34A` | `menvcfg` | 机器环境配置 |
| `0x3A0-0x3A3` | `pmpcfg0-3` | PMP 配置寄存器 |
| `0x3B0-0x3EF` | `pmpaddr0-63` | PMP 地址寄存器 |
| `0x747` | `mseccfg` | 机器安全配置 |
| `0x750-0x75F` | `mcyclecfg`, `minstretcfg` 等 | 计数器配置 |
| `0xF11` | `mvendorid` | 机器厂商 ID（只读） |
| `0xF12` | `marchid` | 机器架构 ID（只读） |
| `0xF13` | `mimpid` | 机器实现 ID（只读） |
| `0xF14` | `mhartid` | Hart ID（只读） |

### `mstatus` 寄存器关键字段

`mstatus` 跟踪处理器的当前运行状态，包含以下关键字段：

| 字段 | 描述 |
|------|------|
| **MIE / SIE** | M/S 模式全局中断使能 |
| **MPIE / SPIE** | 陷入之前的中断使能状态 |
| **MPP / SPP** | 陷入之前的特权模式 |
| **MPRV** | 修改有效特权模式（load/store 按 MPP 模式执行） |
| **MXR** | 使可执行页可读 |
| **SUM** | 允许 Supervisor 访问用户内存 |
| **TVM** | 陷阱虚拟内存（使 `satp` 写和 SFENCE.VMA 在 S-mode 下陷入 M-mode） |
| **TW** | 超时等待（使 WFI 在 S/U-mode 下陷入 M-mode） |
| **TSR** | 陷阱 SRET（使 SRET 在 S-mode 下陷入 M-mode） |
| **FS[1:0]** | 浮点扩展状态（Off/Initial/Clean/Dirty） |
| **XS[1:0]** | 附加用户扩展状态（Off/Initial/Clean/Dirty） |
| **SD** | 状态脏位（FS 或 XS 为 Dirty 时的只读摘要） |
| **SXL / UXL** | S/U 模式的 XLEN 设置（仅 RV64） |

#### 特权栈与中断

当从模式 *y* 陷入模式 *x* 时：

- *x*PIE ← *x*IE
- *x*IE ← 0
- *x*PP ← *y*

执行 MRET/SRET 返回时：

- *x*IE ← *x*PIE
- 特权模式 ← *x*PP
- *x*PIE ← 1
- *x*PP ← 最低支持模式（U 或 M）

### `misa` 寄存器

`misa` 是 WARL 读写寄存器，报告 hart 支持的 ISA。若 `misa` 非零，MXL 字段指示 M-mode 的有效 XLEN（MXLEN）。

**MXL 编码**：

| MXL | XLEN |
|-----|------|
| 1 | 32 |
| 2 | 64 |
| 3 | Reserved |

**Extensions 字段**（bit[25:0]）：每位对应一个字母扩展（bit 0 = A, bit 1 = B, ..., bit 25 = Z）。关键位：

- bit 8: "I" — RV32I/64I 基础 ISA
- bit 12: "M" — 整数乘除扩展
- bit 18: "S" — 支持 Supervisor 模式
- bit 20: "U" — 支持 User 模式
- bit 23: "X" — 存在非标准扩展

### `mcause` — 陷阱原因寄存器

**中断(Exception Code 最高位置 1)**：

| 异常码 | 描述 |
|--------|------|
| 1 | Supervisor 软件中断 |
| 3 | Machine 软件中断 |
| 5 | Supervisor 定时器中断 |
| 7 | Machine 定时器中断 |
| 9 | Supervisor 外部中断 |
| 11 | Machine 外部中断 |

**同步异常(Interrupt=0)**：

| 异常码 | 描述 |
|--------|------|
| 0 | 指令地址非对齐 |
| 1 | 指令访问错误 |
| 2 | 非法指令 |
| 3 | 断点 |
| 4 | Load 地址非对齐 |
| 5 | Load 访问错误 |
| 6 | Store/AMO 地址非对齐 |
| 7 | Store/AMO 访问错误 |
| 8 | 来自 U-mode 的环境调用 |
| 9 | 来自 S-mode 的环境调用 |
| 11 | 来自 M-mode 的环境调用 |
| 12 | 指令页错误 |
| 13 | Load 页错误 |
| 15 | Store/AMO 页错误 |
| 18 | 软件检查异常 |

---

## 3.3. Machine-Mode 特权指令

### ECALL（环境调用）

向执行环境发起请求。根据不同发起模式产生不同的异常：

- U-mode ECALL → Environment-call-from-U-mode exception
- S-mode ECALL → Environment-call-from-S-mode exception
- M-mode ECALL → Environment-call-from-M-mode exception

ECALL 将 `mepc` 设置为 ECALL 指令本身的地址（而非下一条指令），且不计入 `minstret`。

### MRET / SRET（陷阱返回）

- **MRET**：始终提供。从 M-mode 陷阱返回。
- **SRET**：若支持 Supervisor 模式则必须提供。从 S-mode 陷阱返回。
- 只能在对应特权级或更高特权级执行对应 RET 指令。
- 设置 `pc` 为 `xepc` 寄存器的值。
- 若支持 A 扩展，允许但不强制清除 LR 地址预留。

### WFI（等待中断）

通知实现当前 hart 可暂停直至可能需要处理中断。**所有特权模式均可使用**，可选择性开放给 U-mode。

- 若有已使能中断到来，中断将在 WFI 的下一条指令上被响应
- 实现允许无理由恢复执行（即可简单实现为 NOP）
- 操作不受 `mstatus` 中全局中断位或 `mideleg` 委托设置影响

### 自定义 SYSTEM 指令

`SYSTEM` 操作码的子空间保留供自定义使用，推荐使用 bit[29:28] 指定最低所需特权模式。

---

## 3.4. 复位

复位时：

- 特权模式设为 M
- `mstatus.MIE` 和 `mstatus.MPRV` 清零
- 小端模式下 `mstatus.MBE` 清零
- `misa` 复位为最大支持的扩展集
- 无可用的 LR 预留（若支持 A 扩展）
- `pc` 设为实现定义的复位向量
- `mcause` 设为指示复位原因的值
- 可写 PMP 寄存器的 A 和 L 字段清零
- 所有其他 hart 状态为 UNSPECIFIED

---

## 3.7. 物理内存保护 (PMP)

物理内存保护（PMP）单元提供**可选的** per-hart 机器模式控制寄存器，为每个物理内存区域指定访问权限（读、写、执行）。PMP 值在与 PMA 检查并行进行。

### PMP 检查适用范围

- S 或 U 模式的指令取指和数据访问
- MPRV=1 且 MPP=S 或 U 时的 M-mode 数据访问
- 虚拟地址翻译的页表访问（有效特权模式为 S）
- 可选地应用于 M-mode 访问（此时 PMP 本身被锁定）

### PMP 条目

- 最多支持 **64 个 PMP 条目**（实现 0、16 或 64 个均可，低编号优先实现）
- 每个条目由一个 8 位配置寄存器和一个 MXLEN 位地址寄存器描述
- 所有 PMP CSR 字段为 WARL，可能为只读零
- PMP CSR **仅 M-mode 可访问**

### PMP 配置格式

| 位 | 7 | 6-5 | 4-3 | 2 | 1 | 0 |
|----|---|------|------|---|---|---|
| | L | 0 | A[1:0] | X | W | R |

- **R/W/X**：读/写/执行权限
- **A[1:0]**：地址匹配模式
  - `00` OFF — 禁用（空区域）
  - `01` TOR — 范围顶部（Top of Range）
  - `10` NA4 — 自然对齐四字节区域
  - `11` NAPOT — 自然对齐 2 的幂区域（≥8 字节）
- **L**：锁定位。置位后忽略对配置/地址寄存器的写入，直至复位。同时还控制 M-mode 访问是否受 R/W/X 限制。

### PMP 优先级

PMP 条目为**静态优先级**：最低编号的匹配条目决定操作是否成功。匹配条目必须匹配内存操作的所有字节，否则操作失败。

- 若无条目匹配 M-mode 操作 → 成功
- 若无条目匹配 S/U-mode 操作，但至少实现了一个 PMP 条目 → 失败

### PMP 与分页

PMP 与基于页面的虚拟内存系统组合使用。当分页启用时，PMP 检查应用于所有物理内存访问（包括隐式页表引用）。修改 PMP 设置后，M-mode 软件必须执行 `SFENCE.VMA`（rs1=x0, rs2=x0）来同步 PMP 与虚拟机系统。
