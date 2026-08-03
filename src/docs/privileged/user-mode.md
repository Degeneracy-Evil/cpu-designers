# User-Level (U-Mode)

> 来源：The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Section 1.2 & 2.2.1

## 概述

User-mode（U-mode）是 RISC-V 中最低特权级，用于运行应用程序代码。U-mode 提供与更高特权级之间的保护隔离——运行在 U-mode 的代码不能直接访问特权 CSR 或执行特权指令。

**特权级编码**：`00`（Level 0），缩写 **U**。

### 核心特性

- 最低特权级，为应用程序提供受限的执行环境
- U-mode 代码通过 **ECALL** 请求更高特权级的服务
- U-mode 不能直接访问任何特权 CSR
- 硬件实现至少支持 M-mode，可选择性支持 U-mode（M,U）或完整三级（M,S,U）

### 运行模式

Hart 通常在 U-mode 运行应用程序代码，直到发生陷阱（如 supervisor 调用或定时器中断）强制切换到陷阱处理程序，处理程序通常在更高特权模式下运行。陷阱处理完成后，最终在 U-mode 中恢复执行。

**垂直陷阱**（Vertical Trap）：陷阱导致特权级提升（如 U→S, U→M）

---

## U-mode 可访问的 CSR

U-mode 仅可访问非特权 CSR：

### 浮点 CSRs

| 地址 | 名称 | 描述 |
|------|------|------|
| `0x001` | `fflags` | 浮点累积异常 |
| `0x002` | `frm` | 浮点动态舍入模式 |
| `0x003` | `fcsr` | 浮点控制与状态寄存器（`frm` + `fflags`） |

### 向量 CSRs

| 地址 | 名称 | 描述 |
|------|------|------|
| `0x008` | `vstart` | 向量起始位置 |
| `0x009` | `vxsat` | 定点累积饱和标志 |
| `0x00A` | `vxrm` | 定点舍入模式 |
| `0x00F` | `vcsr` | 向量控制与状态寄存器 |
| `0xC20` | `vl` | 向量长度（只读） |
| `0xC21` | `vtype` | 向量数据类型（只读） |
| `0xC22` | `vlenb` | 向量寄存器长度（字节）（只读） |

### Zicfiss 扩展

| 地址 | 名称 | 描述 |
|------|------|------|
| `0x011` | `ssp` | Shadow Stack Pointer |

### 熵源扩展

| 地址 | 名称 | 描述 |
|------|------|------|
| `0x015` | `seed` | 加密随机位生成器种子 |

### Zcmt 扩展

| 地址 | 名称 | 描述 |
|------|------|------|
| `0x017` | `jvt` | 表跳转基向量与控制寄存器 |

### 计数器/定时器

| 地址 | 名称 | 描述 |
|------|------|------|
| `0xC00` | `cycle` | 周期计数器（RDCYCLE） |
| `0xC01` | `time` | 定时器（RDTIME） |
| `0xC02` | `instret` | 已退休指令计数器（RDINSTRET） |
| `0xC03`-`0xC1F` | `hpmcounter3`-`hpmcounter31` | 性能监视计数器 |
| `0xC80`-`0xC9F` | `cycleh`-`hpmcounter31h` | 计数器高 32 位（仅 RV32） |

---

## U-mode 特权指令

U-mode 没有专用的特权指令，但可以使用以下跨特权级的指令：

### ECALL（环境调用）

在 U-mode 执行 ECALL 会生成 **Environment-call-from-U-mode exception**，引发陷阱进入更高特权模式进行处理。`sepc` 或 `mepc` 被设为 ECALL 指令本身的地址。

ECALL 的典型用途是系统调用——用户程序通过 ECALL 请求操作系统服务。

### WFI（等待中断）

WFI 在所有特权模式可用，可选地向 U-mode 开放。若 `mstatus.TW=1` 且在低特权模式执行，则引发非法指令异常。

### EBREAK（断点）

由调试器使用，将控制转移到调试环境。U-mode 下的 EBREAK 引发断点异常。

---

## 内存保护

- U-mode 代码只能访问 **U 位 = 1** 的虚拟页
- MXR 和 SUM 位在 U-mode 下不适用（仅影响 S-mode 访问行为）
- 物理内存保护（PMP）默认拒绝 U-mode 的所有访问，除非 PMP 条目显式授予权限
- 通过 `scounteren` 寄存器，S-mode 可控制 U-mode 对硬件性能计数器的访问

---

## 模式支持配置

系统可以使用不同的特权模式组合（表 2）：

| 级数 | 支持模式 | 典型用途 |
|------|---------|---------|
| 1 | M | 简单嵌入式系统 |
| 2 | M, U | 安全嵌入式系统 |
| 3 | M, S, U | 运行类 Unix 操作系统 |

当实现 U-mode 时，`misa.U` 位设为 1。

---

## 与 S-mode 的交互

在完整三级（M,S,U）系统中：

- U-mode 应用程序通过 **ABI**（应用程序二进制接口）与操作系统交互
- 系统调用通过 ECALL 触发 S-mode 陷阱
- S-mode 可通过 SUM 位临时获得对 U-mode 内存的访问权限
- S-mode **永远不得**在 U-mode 页（U=1）上执行指令
- U-mode 大小端可通过 `sstatus.UBE` 独立于 S-mode 控制
