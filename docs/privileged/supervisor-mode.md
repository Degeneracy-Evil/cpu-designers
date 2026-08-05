# Supervisor-Level ISA (S-Mode)

> 来源：The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Chapter 12, Version 1.13

## 概述

Supervisor-mode（S-mode）被设计为运行操作系统内核的特权级。S-mode 有意限制与底层物理硬件（如物理内存和设备中断）的交互，以支持干净的虚拟化。

**特权级编码**：`01`（Level 1），缩写 **S**。

S-mode 提供：

- **页面虚拟内存系统**（Sv32, Sv39, Sv48, Sv57）
- 陷阱处理机制（中断和异常）
- 与更低特权级 U-mode 的隔离

---

## 12.1. Supervisor CSRs

S-mode CSR 是等效 M-mode CSR 的子集。S-mode 只能看到应对 supervisor 级操作系统可见的 CSR 状态。

| CSR 地址 | 名称 | 描述 |
|----------|------|------|
| `0x100` | `sstatus` | Supervisor 状态寄存器 |
| `0x104` | `sie` | Supervisor 中断使能寄存器 |
| `0x105` | `stvec` | Supervisor 陷阱向量基地址 |
| `0x106` | `scounteren` | Supervisor 计数器使能 |
| `0x10A` | `senvcfg` | Supervisor 环境配置寄存器 |
| `0x120` | `scountinhibit` | Supervisor 计数器禁止寄存器 |
| `0x140` | `sscratch` | Supervisor 暂存寄存器 |
| `0x141` | `sepc` | Supervisor 异常程序计数器 |
| `0x142` | `scause` | Supervisor 陷阱原因 |
| `0x143` | `stval` | Supervisor 陷阱值 |
| `0x144` | `sip` | Supervisor 中断挂起 |
| `0x180` | `satp` | Supervisor 地址翻译与保护 |
| `0x14D` | `stimecmp` | Supervisor 定时器比较（Sstc 扩展） |
| `0xDA0` | `scountovf` | Supervisor 计数器溢出（Sscofpmf 扩展） |

### `sstatus` 寄存器

`sstatus` 是 `mstatus` 的子集，跟踪处理器当前运行状态。

| 字段 | 位(SXLEN=32) | 描述 |
|------|-------------|------|
| **SIE** | 1 | S-mode 全局中断使能 |
| **SPIE** | 5 | 陷入之前 S-mode 中断使能状态 |
| **SPP** | 8 | 陷入之前的特权模式（0=U, 1=S） |
| **UBE** | 6 | U-mode 内存访问大小端控制 |
| **MXR** | 19 | 使可执行页可读 |
| **SUM** | 18 | 允许 Supervisor 访问用户内存 |
| **SDT** | 22 | Double-trap 控制（Smdbltrp 扩展） |
| **SPELP** | 23 | 上一个 ELP 状态（Zicfilp 扩展） |
| **UXL[1:0]** | 33-32 | U-mode XLEN 控制（仅 SXLEN=64） |
| **FS[1:0]** | 14-13 | 浮点扩展状态 |
| **XS[1:0]** | 16-15 | 附加用户扩展状态 |
| **SD** | 31/63 | 状态脏位（只读摘要） |

#### SPP / SPIE / SIE 陷阱机制

当陷入 S-mode 时：

- SPP ← 0（若来自 U-mode）或 1（否则）
- SPIE ← SIE
- SIE ← 0

执行 SRET 返回时：

- 特权模式 ← U（若 SPP=0）或 S（若 SPP=1）
- SIE ← SPIE
- SPIE ← 1
- SPP ← 0

#### MXR（Make eXecutable Readable）

- MXR=0：仅可从标记为可读（R=1）的页成功 load
- MXR=1：可从标记为可读或可执行（R=1 或 X=1）的页成功 load
- 仅在基于页面的虚拟内存生效时有作用

#### SUM（permit Supervisor User Memory access）

- SUM=0：S-mode 访问 U-mode 页（U=1）将发生错误
- SUM=1：允许此类访问
- S-mode **永远不能**在用户页上执行代码（与 SUM 无关）

#### UXL（U-mode XLEN 控制）

- SXLEN=32 时不存在，UXLEN=32
- SXLEN=64 时为 WARL 字段，编码与 MXL 相同
- 约束：UXLEN ≤ SXLEN

### `stvec` — 陷阱向量基地址

| 位 | 描述 |
|----|------|
| MODE[1:0] | 0=直接, 1=向量化 |
| BASE[SXLEN-1:2] | 陷阱处理函数基地址（4 字节对齐） |

- **直接模式(MODE=0)**： 所有陷阱跳转到 BASE 地址
- **向量化模式(MODE=1)**： 同步异常跳转到 BASE，中断跳转到 `BASE + 4 × cause`

### `sip` / `sie` — 中断挂起/使能

| 位 | 描述 |
|----|------|
| SSIP (1) | Supervisor 软件中断 |
| STIP (5) | Supervisor 定时器中断 |
| SEIP (9) | Supervisor 外部中断 |
| LCOFIP (13) | 计数器溢出中断（Sscofpmf 扩展） |

- `sip` 为只读（中断挂起状态），`sie` 为读写（中断使能）
- S-mode 可通过写 `sip` 设置 SSIP（其余位只读）

### `sscratch` — 暂存寄存器

临时数据交换寄存器，通常用于在陷阱处理时保存用户上下文。

### `sepc` — 异常程序计数器

- 陷阱发生时，写入触发陷阱的指令地址
- SRET 将 `pc` 恢复为 `sepc`

### `scause` — 陷阱原因

格式与 `mcause` 相同：

- 最高位为中断标志（1=中断，0=异常）
- 低有效位为异常码

### `stval` — 陷阱值

- 陷阱时写入异常特定信息（如错误地址）
- 格式与 `mtval` 相同

---

## 12.1.11. `satp` — 地址翻译与保护

`satp` 是 SXLEN 位读写寄存器，控制 supervisor 模式地址翻译与保护。

### RV32 格式（SXLEN=32）

| 31 | 30..22 | 21..0 |
|----|--------|-------|
| MODE (1 bit) | ASID (9 bits) | PPN (22 bits) |

### RV64 格式（SXLEN=64）

| 63..60 | 59..44 | 43..0 |
|--------|--------|-------|
| MODE (4 bits) | ASID (16 bits) | PPN (44 bits) |

### MODE 字段编码

| SXLEN | 值 | 名称 | 描述 |
|-------|-----|------|------|
| 32 | 0 | Bare | 无翻译或保护 |
| 32 | 1 | Sv32 | 32 位分页虚拟寻址 |
| 64 | 0 | Bare | 无翻译或保护 |
| 64 | 8 | Sv39 | 39 位分页虚拟寻址 |
| 64 | 9 | Sv48 | 48 位分页虚拟寻址 |
| 64 | 10 | Sv57 | 57 位分页虚拟寻址 |
| 64 | 11 | Sv64 | 保留用于 64 位分页虚拟寻址 |

- **ASID**（地址空间标识符）：便于按地址空间进行地址翻译 fence
- **PPN**：（根页表的物理页号）
- `satp` 在有效特权模式为 S-mode 或 U-mode 时被认为是**活跃的**
- 不支持写入不支持的 MODE 值（整个写入无效）

---

## 12.2. Supervisor 指令

S-mode 提供两条核心特权指令：

### SRET（Supervisor 陷阱返回）

- 从 S-mode 陷阱处理返回
- 将 `pc` 设为 `sepc` 的值
- 恢复 SPP/SPIE 中断栈
- 若 `mstatus.TSR=1` 则在 S-mode 下引发非法指令异常

### SFENCE.VMA（Supervisor 内存管理 Fence）

用于同步内存中内存管理数据结构的更新与当前执行。

| 操作数 | 行为 |
|--------|------|
| rs1=x0, rs2=x0 | 全局 fence：所有地址空间 |
| rs1=x0, rs2≠x0 | 指定 ASID 的所有地址（不含全局映射） |
| rs1≠x0, rs2=x0 | 指定虚拟地址的叶子 PTE（所有地址空间） |
| rs1≠x0, rs2≠x0 | 指定虚拟地址 + ASID 的叶子 PTE（不含全局映射） |

- SFENCE.VMA 仅对本地 hart 的隐式引用进行排序
- 若 rs1 不是有效虚拟地址，指令无效果（不引发异常）
- 实现允许过度 fence（如简单实现忽略 rs1 和 rs2 始终执行全局 fence）

**常见使用场景**：

- 回收 ASID 时：先改 `satp` 指向新页表，再执行 SFENCE.VMA
- 修改非叶子 PTE 后：执行 SFENCE.VMA(rs1=x0)
- 修改叶子 PTE 后：执行 SFENCE.VMA(rs1=页内虚拟地址)
- PMP 设置修改后：执行 SFENCE.VMA(rs1=x0, rs2=x0)

---

## 异常委托机制

S-mode 可以通过 `medeleg` 和 `mideleg` 寄存器接收由 M-mode 委托的陷阱：

- `medeleg`：委托同步异常（如环境调用、页错误）
- `mideleg`：委托中断（如定时器、软件、外部中断）
- 委托给 S-mode 的中断在 `sip`/`sie` 中可见，并通过 `stvec` 路由

---

## 虚拟内存系统

S-mode 支持以下虚拟内存方案（通过 `satp.MODE` 选择）：

| 方案 | SXLEN | 虚拟地址宽度 | 页表级数 | 支持页大小 |
|------|-------|------------|---------|-----------|
| Bare | 32/64 | 等同于物理地址 | 0 | — |
| Sv32 | 32 | 32 位 | 2 | 4 KiB, 4 MiB |
| Sv39 | 64 | 39 位 | 3 | 4 KiB, 2 MiB, 1 GiB |
| Sv48 | 64 | 48 位 | 4 | 4 KiB, 2 MiB, 1 GiB, 512 GiB |
| Sv57 | 64 | 57 位 | 5 | 4 KiB, 2 MiB, 1 GiB, 512 GiB, 256 TiB |

详见：

- Sv32：[`../Mem/sv32-virtual-memory.md`](../Mem/sv32-virtual-memory.md)
