> **[历史归档 2026-09-25]** 本文为 2026-06~08 的调试/规划快照：文中工具命令（`tools/vivado_cli`）、目录路径（`src/rtl`、`src/tb`、`src/program_source`）、时钟（cpu_clk 50MHz）及部分架构描述已被 2026-09 重构取代（现行工具链 `python3 -m tools.vivado`，RTL 位于 `src/{common,core,soc}`）。仅作历史记录，勿作操作依据。
>
> 本计划已被 Linux + OpenSBI 路线取代（`software/system/`），`src/os/` 从未建立。

# MicroOS 实现计划

> 生成日期: 2026-05-24 | 目标平台: SimpleCPU (RV32IM, Sv32, 32KB SRAM)
> 参考: xv6-riscv (docs/Reference/xv6) | RTL 设计报告: src/docs/simpleCPU-design-report.md

---

## 0. 设计约束与决策

### 0.1 硬件约束

| 项目 | 值 | 影响 |
|------|-----|------|
| ISA | RV32IM | 所有类型 32-bit，无原生 uint64 |
| 特权级 | M/S/U | 完整陷阱委托 |
| 页表 | Sv32 (2级) | VPN[1]/VPN[0] 各 10-bit，4KB 页 |
| RAM | 32KB (0x80000000~0x80007FFC) | 最多 ~4 个进程，内核极精简 |
| Cache | ICache/DCache 各 1KB | 缺失率较高，代码应紧凑 |
| 主 I/O | UART (TX/RX FIFO 各 16 字节) | 唯一控制台 I/O 通道 |
| CLINT | mtime 64-bit (高/低各 32-bit) | 必须同时使用高低 32 位，否则快速溢出 |
| PLIC | 8-source (Timer/UART/SPI/GPIO) | 中断路由已固定 |

### 0.2 架构决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 外设访问方式 | **全部通过 syscall** | 防止用户态资源竞争；接口简单统一 |
| 用户态直接 MMIO | **禁止** | 用户页表不映射设备寄存器，安全性+隔离 |
| 文件系统 | **暂不实现** | 无磁盘，32KB RAM 不支持；console I/O 优先 |
| ELF 加载 | **暂不实现** | 无 FS 则无 exec，进程通过内核内嵌代码启动 |
| GPIO/SPI 用户接口 | **通过 syscall 代理** | 未来扩展，初期仅实现 UART 相关 syscall |
| uint64 处理 | **仅 CLINT mtime 使用** | `types.h` 保留 `uint64` 定义，仅供 CLINT 时间戳 |

---

## 1. 目录结构

```
src/os/
├── PLAN-os-impl.md          ← 本文件
├── Makefile                 ← 构建系统
├── include/                 ← 头文件（内核与用户共享）
│   ├── types.h              ← 基础类型 (RV32 + uint64 for mtime)
│   ├── param.h              ← 系统参数 (32KB RAM 适配)
│   ├── memlayout.h          ← 物理地址映射 (匹配 RTL)
│   ├── riscv.h              ← RISC-V CSR + Sv32 页表 (RV32 重写)
│   ├── uart.h               ← UART 寄存器定义 (匹配 RTL §6.2.1)
│   ├── gpio.h               ← GPIO 寄存器定义 (匹配 RTL §6.2.2)
│   ├── spi.h                ← SPI 寄存器定义 (匹配 RTL §6.2.3)
│   ├── timer.h              ← APB Timer 寄存器定义
│   ├── plic.h               ← PLIC 寄存器定义 + 中断源映射
│   ├── clint.h              ← CLINT 寄存器定义 (mtime 高/低 32-bit)
│   ├── trap.h               ← 陷阱帧结构 (RV32)
│   ├── context.h            ← 上下文切换结构 (RV32 callee-saved)
│   ├── spinlock.h           ← 自旋锁
│   ├── sleeplock.h          ← 睡眠锁
│   ├── vm.h                 ← 虚拟内存常量
│   ├── proc.h               ← 进程控制块 (精简版)
│   ├── syscall.h            ← 系统调用号
│   ├── stat.h               ← 文件状态 (预留空壳)
│   ├── fcntl.h              ← 文件控制标志 (预留空壳)
│   ├── elf.h                ← ELF 格式 (RV32, 预留)
│   └── defs.h               ← 内核函数声明
├── kernel/                  ← 内核源码
│   ├── entry.S              ← M-mode 启动入口 (设置栈+跳 kernelvec)
│   ├── start.c              ← M-mode 初始化 (配置 medeleg/mideleg, 跳 main)
│   ├── main.c               ← S-mode 主入口 (初始化各子系统)
│   ├── kernel.ld            ← 内核链接脚本
│   ├── kernelvec.S          ← 内核陷阱向量
│   ├── trampoline.S         ← 用户/内核陷阱跳板页
│   ├── swtch.S              ← 上下文切换汇编
│   ├── kalloc.c             ← 物理页分配器
│   ├── vm.c                 ← 虚拟内存管理 (Sv32)
│   ├── trap.c               ← 陷阱处理 (S-mode)
│   ├── proc.c               ← 进程管理 + 调度器
│   ├── syscall.c            ← 系统调用分发
│   ├── sysproc.c            ← 进程相关 syscall 实现
│   ├── sysfile.c            ← 文件/IO 相关 syscall 实现 (UART console)
│   ├── uart.c               ← UART 驱动 (MMIO, 内核态)
│   ├── console.c            ← 控制台抽象 (read/write → UART)
│   ├── plic.c               ← PLIC 驱动
│   ├── printf.c             ← 内核 printf
│   ├── spinlock.c           ← 自旋锁实现
│   ├── sleeplock.c          ← 睡眠锁实现
│   ├── pipe.c               ← 管道实现
│   ├── file.c               ← 文件描述符管理
│   └── string.c             ← 内核字符串操作
├── user/                    ← 用户态源码
│   ├── user.h               ← 用户 API 声明 (仅 syscall + 库函数)
│   ├── usys.S               ← 系统调用桩 (ecall 汇编)
│   ├── ulib.c               ← 用户库 (start/strcpy/strcmp/strlen/...)
│   ├── umalloc.c            ← 用户态 malloc/free
│   ├── printf.c             ← 用户态 printf
│   ├── init.c               ← 用户态 init 进程 (未来)
│   └── sh.c                 ← 简易 shell (未来)
└── scripts/                 ← 构建脚本
    └── usys.pl              ← 自动生成 usys.S
```

---

## 2. 头文件详细规格

### 2.1 `include/types.h` — 基础类型

```c
#ifndef _TYPES_H
#define _TYPES_H

typedef unsigned int       uint;
typedef unsigned short     ushort;
typedef unsigned char      uchar;

typedef signed char        int8;
typedef short              int16;
typedef int                int32;
typedef unsigned char      uint8;
typedef unsigned short     uint16;
typedef unsigned int       uint32;

// uint64 仅用于 CLINT mtime (64-bit 计数器)
// RV32 无原生 64-bit，编译器用软件模拟
typedef unsigned long long uint64;

// 页目录项类型 (Sv32, 32-bit)
typedef uint32 pte_t;
typedef uint32 *pagetable_t;

#endif
```

**与 xv6 差异**: `uint64` 从 `unsigned long` 改为 `unsigned long long`（RV32 的 `long` 为 32-bit）；新增 `int8/int16/int32`；`pde_t` 改为 `uint32`。

---

### 2.2 `include/param.h` — 系统参数

```c
#ifndef _PARAM_H
#define _PARAM_H

#define NPROC       4       // 最大进程数 (32KB RAM)
#define NCPU        1       // 单核
#define NOFILE      8       // 每进程打开文件数
#define NFILE       16      // 系统总打开文件数
#define NINODE      8       // 最大活跃 inode 数 (预留)
#define NDEV        10      // 最大主设备号
#define MAXARG      8       // 最大 exec 参数 (预留)
#define MAXPATH     32      // 最大路径长度 (预留)
#define USERSTACK   1       // 用户栈页数

// 物理内存
#define SRAM_SIZE   32768   // 32KB
#define PGSIZE      4096    // 页大小 4KB
#define PGSHIFT     12      // 页偏移位数

// 内核可用页数: (32KB - 内核占用) / 4KB ≈ 6-7 页给用户
// 内核自身约需 2-3 页 (代码+数据+栈)

#endif
```

**与 xv6 差异**: `NPROC` 64→4, `NCPU` 8→1, `NOFILE` 16→8, `NFILE` 100→16, 删除 `FSSIZE/NBUF/MAXOPBLOCKS/LOGBLOCKS/ROOTDEV`，新增 `SRAM_SIZE`。

---

### 2.3 `include/memlayout.h` — 物理地址映射

```c
#ifndef _MEMLAYOUT_H
#define _MEMLAYOUT_H

#include "types.h"

// ============================================================
// 物理地址映射 (匹配 RTL 地址译码)
// addr[31:24] 译码:
//   0x80 → SRAM Slave (缓存映射, addr[31]==1)
//   0x02 → CLINT
//   0x0C → PLIC
//   0x10 → APB Bridge → UART/GPIO/Timer/SPI
// ============================================================

// --- SRAM 主存储器 (32KB) ---
#define KERNBASE    0x80000000U
#define PHYSTOP     (KERNBASE + 0x8000)  // 0x80008000

// --- CLINT (核心本地中断器) ---
#define CLINT           0x02000000U
#define CLINT_MTIMECMP  (CLINT + 0x0000)  // mtimecmp 低 32-bit
#define CLINT_MTIMECMP_H (CLINT + 0x0004) // mtimecmp 高 32-bit
#define CLINT_MTIME     (CLINT + 0x0008)  // mtime 低 32-bit
#define CLINT_MTIME_H   (CLINT + 0x000C)  // mtime 高 32-bit
#define CLINT_MSIP      (CLINT + 0x0010)  // msip (软件中断)

// --- PLIC (平台级中断控制器, 8-source) ---
#define PLIC            0x0C000000U
#define PLIC_PRIORITY   (PLIC + 0x000000)
#define PLIC_PENDING    (PLIC + 0x001000)
#define PLIC_SENABLE    (PLIC + 0x002080)  // S-mode enable (hart=0)
#define PLIC_SPRIORITY  (PLIC + 0x201000)  // S-mode priority (hart=0)
#define PLIC_SCLAIM     (PLIC + 0x201004)  // S-mode claim/complete (hart=0)

// --- APB 外设桥 ---
// 偏移需从 apb_decoder.sv 确认，以下为默认假设:
#define APB_BASE        0x10000000U
#define UART_BASE       (APB_BASE + 0x00000)
#define GPIO_BASE       (APB_BASE + 0x01000)
#define TIMER_BASE      (APB_BASE + 0x02000)
#define SPI_BASE        (APB_BASE + 0x03000)

// --- MMIO 判定 ---
// addr[31]==0 → MMIO (旁路缓存)
// addr[31]==1 → Cacheable (走 icache/dcache)
#define IS_MMIO(addr) (((uint32)(addr) >> 31) == 0)

// ============================================================
// Sv32 虚拟内存布局
// ============================================================
// MAXVA = 2^31 = 0x80000000 (Sv32 地址空间上限)
#define MAXVA       0x80000000U

// Trampoline 页映射到最高地址 (用户+内核共享)
#define TRAMPOLINE  (MAXVA - PGSIZE)

// Trapframe 页在 trampoline 下方
#define TRAPFRAME   (TRAMPOLINE - PGSIZE)

// 内核栈在 trampoline 下方，每个栈 1 页 + 1 页 guard
#define KSTACK(p)   (TRAMPOLINE - ((p) + 1) * 2 * PGSIZE)

#endif
```

**与 xv6 差异**: `MAXVA` 从 `2^38` 改为 `2^31`；CLINT 偏移增加 `_H` 高 32-bit 寄存器；新增 `IS_MMIO` 宏；APB 外设基地址全新；`PHYSTOP` 从 128MB 改为 32KB。

> ⚠️ **TODO**: 确认 APB 外设偏移（需读 `apb_decoder.sv`），确认 CLINT 寄存器间距（需读 `ahb_clint.sv`）。

---

### 2.4 `include/riscv.h` — RISC-V CSR + Sv32

```c
#ifndef _RISCV_H
#define _RISCV_H

#include "types.h"

#ifndef __ASSEMBLER__

// ============================================================
// CSR 读写内联函数 (RV32: 返回 uint32)
// ============================================================

static inline uint32 r_mhartid() {
    uint32 x; asm volatile("csrr %0, mhartid" : "=r"(x)); return x;
}

// --- mstatus ---
#define MSTATUS_MPP_MASK (3U << 11)
#define MSTATUS_MPP_M    (3U << 11)
#define MSTATUS_MPP_S    (1U << 11)
#define MSTATUS_MPP_U    (0U << 11)
#define MSTATUS_MPIE     (1U << 7)
#define MSTATUS_MIE      (1U << 3)
#define MSTATUS_SPP      (1U << 8)
#define MSTATUS_SPIE     (1U << 5)
#define MSTATUS_SIE      (1U << 1)

static inline uint32 r_mstatus() {
    uint32 x; asm volatile("csrr %0, mstatus" : "=r"(x)); return x;
}
static inline void w_mstatus(uint32 x) {
    asm volatile("csrw mstatus, %0" : : "r"(x));
}

// --- sstatus ---
#define SSTATUS_SPP  (1U << 8)
#define SSTATUS_SPIE (1U << 5)
#define SSTATUS_SIE  (1U << 1)

static inline uint32 r_sstatus() {
    uint32 x; asm volatile("csrr %0, sstatus" : "=r"(x)); return x;
}
static inline void w_sstatus(uint32 x) {
    asm volatile("csrw sstatus, %0" : : "r"(x));
}

// --- sie / sip ---
#define SIE_SEIE (1U << 9)  // 外部中断
#define SIE_STIE (1U << 5)  // 定时器中断
#define SIE_SSIE (1U << 1)  // 软件中断

static inline uint32 r_sie() {
    uint32 x; asm volatile("csrr %0, sie" : "=r"(x)); return x;
}
static inline void w_sie(uint32 x) {
    asm volatile("csrw sie, %0" : : "r"(x));
}
static inline uint32 r_sip() {
    uint32 x; asm volatile("csrr %0, sip" : "=r"(x)); return x;
}
static inline void w_sip(uint32 x) {
    asm volatile("csrw sip, %0" : : "r"(x));
}

// --- mie ---
#define MIE_MEIE (1U << 11)
#define MIE_MTIE (1U << 7)
#define MIE_MSIE (1U << 3)

static inline uint32 r_mie() {
    uint32 x; asm volatile("csrr %0, mie" : "=r"(x)); return x;
}
static inline void w_mie(uint32 x) {
    asm volatile("csrw mie, %0" : : "r"(x));
}

// --- mepc / sepc ---
static inline void w_mepc(uint32 x) {
    asm volatile("csrw mepc, %0" : : "r"(x));
}
static inline void w_sepc(uint32 x) {
    asm volatile("csrw sepc, %0" : : "r"(x));
}
static inline uint32 r_sepc() {
    uint32 x; asm volatile("csrr %0, sepc" : "=r"(x)); return x;
}

// --- medeleg / mideleg ---
static inline uint32 r_medeleg() {
    uint32 x; asm volatile("csrr %0, medeleg" : "=r"(x)); return x;
}
static inline void w_medeleg(uint32 x) {
    asm volatile("csrw medeleg, %0" : : "r"(x));
}
static inline uint32 r_mideleg() {
    uint32 x; asm volatile("csrr %0, mideleg" : "=r"(x)); return x;
}
static inline void w_mideleg(uint32 x) {
    asm volatile("csrw mideleg, %0" : : "r"(x));
}

// --- stvec / mtvec ---
static inline void w_stvec(uint32 x) {
    asm volatile("csrw stvec, %0" : : "r"(x));
}
static inline uint32 r_stvec() {
    uint32 x; asm volatile("csrr %0, stvec" : "=r"(x)); return x;
}
static inline void w_mtvec(uint32 x) {
    asm volatile("csrw mtvec, %0" : : "r"(x));
}

// --- scause / stval ---
static inline uint32 r_scause() {
    uint32 x; asm volatile("csrr %0, scause" : "=r"(x)); return x;
}
static inline uint32 r_stval() {
    uint32 x; asm volatile("csrr %0, stval" : "=r"(x)); return x;
}

// --- satp (Sv32) ---
#define SATP_SV32  (1U << 31)
#define MAKE_SATP(pagetable) (SATP_SV32 | (((uint32)(pagetable)) >> 12))

static inline void w_satp(uint32 x) {
    asm volatile("csrw satp, %0" : : "r"(x));
}
static inline uint32 r_satp() {
    uint32 x; asm volatile("csrr %0, satp" : "=r"(x)); return x;
}

// --- sscratch ---
static inline void w_sscratch(uint32 x) {
    asm volatile("csrw sscratch, %0" : : "r"(x));
}
static inline uint32 r_sscratch() {
    uint32 x; asm volatile("csrr %0, sscratch" : "=r"(x)); return x;
}

// --- mcounteren / scounteren ---
static inline void w_mcounteren(uint32 x) {
    asm volatile("csrw mcounteren, %0" : : "r"(x));
}
static inline void w_scounteren(uint32 x) {
    asm volatile("csrw scounteren, %0" : : "r"(x));
}

// --- 中断控制 ---
static inline void intr_on()  { w_sstatus(r_sstatus() | SSTATUS_SIE); }
static inline void intr_off() { w_sstatus(r_sstatus() & ~SSTATUS_SIE); }
static inline int  intr_get() { return (r_sstatus() & SSTATUS_SIE) != 0; }

// --- 通用寄存器读取 ---
static inline uint32 r_sp()  { uint32 x; asm volatile("mv %0, sp" : "=r"(x)); return x; }
static inline uint32 r_tp()  { uint32 x; asm volatile("mv %0, tp" : "=r"(x)); return x; }
static inline void   w_tp(uint32 x) { asm volatile("mv tp, %0" : : "r"(x)); }
static inline uint32 r_ra()  { uint32 x; asm volatile("mv %0, ra" : "=r"(x)); return x; }

// --- TLB 刷新 ---
static inline void sfence_vma() {
    asm volatile("sfence.vma zero, zero");
}

// --- fence.i (icache 失效 + dcache 写回) ---
static inline void fence_i() {
    asm volatile("fence.i");
}

#endif // __ASSEMBLER__

// ============================================================
// Sv32 页表定义 (常量部分，汇编和 C 共享)
// ============================================================
#define PGSIZE   4096    // 页大小 4KB
#define PGSHIFT  12      // 页内偏移位数

#define PGROUNDUP(sz)   (((sz) + PGSIZE - 1) & ~(PGSIZE - 1))
#define PGROUNDDOWN(a)  (((a)) & ~(PGSIZE - 1))

// 页表项标志位 (匹配 RTL PTE 格式)
#define PTE_V (1U << 0)  // 有效
#define PTE_R (1U << 1)  // 可读
#define PTE_W (1U << 2)  // 可写
#define PTE_X (1U << 3)  // 可执行
#define PTE_U (1U << 4)  // 用户可访问
#define PTE_G (1U << 5)  // 全局映射
#define PTE_A (1U << 6)  // 访问位
#define PTE_D (1U << 7)  // 脏位

// Sv32: PPN[21:10] 在 PTE[31:10]
#define PA2PTE(pa)      ((((uint32)(pa)) >> 12) << 10)
#define PTE2PA(pte)     (((pte) >> 10) << 12)
#define PTE_FLAGS(pte)  ((pte) & 0x3FF)

// Sv32: 2 级页表，每级 10-bit 索引 (1024 项)
#define PXMASK          0x3FF   // 10-bit
#define PXSHIFT(level)  (PGSHIFT + (10 * (level)))
#define PX(level, va)   ((((uint32)(va)) >> PXSHIFT(level)) & PXMASK)

#endif
```

**与 xv6 差异**: 全部 `uint64` → `uint32`；`SATP_SV39` → `SATP_SV32`；`PXMASK` 从 `0x1FF` (9-bit) 改为 `0x3FF` (10-bit)；`PXSHIFT` 从 `9*level` 改为 `10*level`；`MAXVA` 移入 `memlayout.h`；新增 `fence_i()` 内联；删除 `r_stimecmp/w_stimecmp`（改用 CLINT MMIO）；删除 PMP 相关（暂不使用）。

---

### 2.5 `include/uart.h` — UART 寄存器

```c
#ifndef _UART_H
#define _UART_H

#include "types.h"
#include "memlayout.h"

// ============================================================
// UART 寄存器偏移 (匹配 RTL §6.2.1)
// ============================================================
#define UART_CTRL      0x00  // [0]=TX_EN  [1]=RX_EN  [2]=TX_IE  [3]=RX_IE
#define UART_STATUS    0x04  // [0]=TX_BUSY [1]=RX_VALID [2]=TX_FIFO_FULL
                              // [3]=RX_FIFO_EMPTY [4]=TX_FIFO_EMPTY [5]=RX_FIFO_FULL
#define UART_TXDATA    0x08  // [7:0] 写入推入 TX FIFO
#define UART_RXDATA    0x0C  // [7:0] 读取弹出 RX FIFO
#define UART_BAUD      0x10  // [15:0] 波特率分频 (0=默认 115200)
#define UART_IRQ_STAT  0x14  // [0]=TX_DONE_IRQ [1]=RX_VALID_IRQ (写1清除)

// CTRL 位域
#define UART_TX_EN       (1U << 0)
#define UART_RX_EN       (1U << 1)
#define UART_TX_IE       (1U << 2)
#define UART_RX_IE       (1U << 3)

// STATUS 位域
#define UART_STS_TX_BUSY      (1U << 0)
#define UART_STS_RX_VALID     (1U << 1)
#define UART_STS_TX_FIFO_FULL (1U << 2)
#define UART_STS_RX_FIFO_EMPTY (1U << 3)
#define UART_STS_TX_FIFO_EMPTY (1U << 4)
#define UART_STS_RX_FIFO_FULL  (1U << 5)

// IRQ_STAT 位域
#define UART_IRQ_TX_DONE  (1U << 0)
#define UART_IRQ_RX_VALID (1U << 1)

// PLIC 中断源编号 (匹配 RTL §6.2.4)
#define UART_IRQ_ID      2    // PLIC src[2] = UART

// 寄存器读写辅助 (内核态 MMIO)
#define UART_REG(offset) (*(volatile uint32 *)(UART_BASE + (offset)))

static inline uint32 uart_read(uint32 offset) {
    return UART_REG(offset);
}
static inline void uart_write(uint32 offset, uint32 val) {
    UART_REG(offset) = val;
}

#endif
```

---

### 2.6 `include/gpio.h` — GPIO 寄存器

```c
#ifndef _GPIO_H
#define _GPIO_H

#include "types.h"
#include "memlayout.h"

#define GPIO_CTRL      0x00  // 方向控制 (1=输出, 0=输入), 16-bit
#define GPIO_DATA      0x04  // 数据寄存器, 16-bit
#define GPIO_IRQ_EN    0x08  // 逐引脚中断使能掩码, 16-bit
#define GPIO_IRQ_STAT  0x0C  // 逐引脚中断挂起 (写1清除), 16-bit

#define GPIO_IRQ_ID    4     // PLIC src[4] = GPIO
#define GPIO_PIN_COUNT 16    // 16-bit 双向 IO

#define GPIO_REG(offset) (*(volatile uint32 *)(GPIO_BASE + (offset)))

#endif
```

---

### 2.7 `include/spi.h` — SPI 寄存器

```c
#ifndef _SPI_H
#define _SPI_H

#include "types.h"
#include "memlayout.h"

#define SPI_CTRL       0x00  // [0]=EN [1]=CPOL [2]=CPHA [3]=CS [4]=IRQ_EN [15:8]=CLK_DIV
#define SPI_DATA       0x04  // [7:0] 数据寄存器
#define SPI_STATUS     0x08  // [0]=BUSY [1]=IRQ_PENDING

#define SPI_EN         (1U << 0)
#define SPI_CPOL       (1U << 1)
#define SPI_CPHA       (1U << 2)
#define SPI_CS         (1U << 3)
#define SPI_IRQ_EN     (1U << 4)
#define SPI_CLK_DIV_SHIFT  8

#define SPI_STS_BUSY   (1U << 0)
#define SPI_STS_IRQ    (1U << 1)

#define SPI_IRQ_ID     3     // PLIC src[3] = SPI

#define SPI_REG(offset) (*(volatile uint32 *)(SPI_BASE + (offset)))

#endif
```

---

### 2.8 `include/timer.h` — APB Timer 寄存器

```c
#ifndef _TIMER_H
#define _TIMER_H

#include "types.h"
#include "memlayout.h"

#define TIMER_CTRL     0x00  // [0]=EN [1]=MODE (0=单次, 1=周期)
#define TIMER_VALUE    0x04  // 当前计数值 (32-bit, 只读)
#define TIMER_COMPARE  0x08  // 比较匹配值 (32-bit, 读写)

#define TIMER_EN       (1U << 0)
#define TIMER_MODE_PERIODIC (1U << 1)

#define TIMER_IRQ_ID   1     // PLIC src[1] = Timer

#define TIMER_REG(offset) (*(volatile uint32 *)(TIMER_BASE + (offset)))

#endif
```

---

### 2.9 `include/plic.h` — PLIC 驱动接口

```c
#ifndef _PLIC_H
#define _PLIC_H

#include "types.h"

// PLIC 中断源映射 (匹配 RTL §6.2.4)
#define PLIC_SRC_TIMER   1   // APB Timer 比较匹配中断
#define PLIC_SRC_UART    2   // UART TX完成/RX有效中断
#define PLIC_SRC_SPI     3   // SPI 传输完成中断
#define PLIC_SRC_GPIO    4   // GPIO 引脚变化中断
#define PLIC_NUM_SOURCES 8   // 总中断源数 (src[0]保留, src[5:7]保留)

// 内核驱动接口
void plic_init(void);          // 初始化 PLIC
void plic_init_hart(void);     // 初始化当前 hart 的 S-mode 中断
uint32 plic_claim(void);       // 声明并获取最高优先级挂起中断
void plic_complete(uint32 irq); // 完成中断处理

#endif
```

---

### 2.10 `include/clint.h` — CLINT 驱动接口

```c
#ifndef _CLINT_H
#define _CLINT_H

#include "types.h"

// CLINT mtime 为 64-bit 计数器，RV32 下分为高/低 32-bit
// 必须同时使用高低 32 位，否则约 4.29 秒后低 32 位溢出归零

// 读取 mtime 64-bit 值 (原子: 先读低再读高，若高变化则重读)
uint64 clint_read_mtime(void);

// 写入 mtimecmp 64-bit 值 (先写高 32 位再写低 32 位，防止中间触发中断)
void clint_write_mtimecmp(uint64 val);

// 设置 msip (软件中断)
void clint_set_msip(uint32 hart, uint32 val);

// 便捷: 设置下一次定时器中断 (当前 mtime + interval)
void clint_set_timer_interval(uint64 interval);

#endif
```

**关键设计**: `clint_read_mtime` 必须处理低 32 位溢出导致的翻转问题——先读低再读高，若高 32 位在读低后发生变化则重读。`clint_write_mtimecmp` 必须先写高 32 位再写低 32 位，防止中间值意外触发中断。

---

### 2.11 `include/trap.h` — 陷阱帧

```c
#ifndef _TRAP_H
#define _TRAP_H

#include "types.h"

// 用户态陷阱帧 (RV32, 所有寄存器 32-bit)
// trampoline.S 保存/恢复用户寄存器到此结构
struct trapframe {
    /*   0 */ uint32 kernel_satp;     // 内核页表
    /*   4 */ uint32 kernel_sp;       // 进程内核栈顶
    /*   8 */ uint32 kernel_trap;     // usertrap() 地址
    /*  12 */ uint32 epc;             // 保存的用户 PC
    /*  16 */ uint32 kernel_hartid;   // 内核 tp (hartid)
    /*  20 */ uint32 ra;
    /*  24 */ uint32 sp;
    /*  28 */ uint32 gp;
    /*  32 */ uint32 tp;
    /*  36 */ uint32 t0;
    /*  40 */ uint32 t1;
    /*  44 */ uint32 t2;
    /*  48 */ uint32 s0;
    /*  52 */ uint32 s1;
    /*  56 */ uint32 a0;
    /*  60 */ uint32 a1;
    /*  64 */ uint32 a2;
    /*  68 */ uint32 a3;
    /*  72 */ uint32 a4;
    /*  76 */ uint32 a5;
    /*  80 */ uint32 a6;
    /*  84 */ uint32 a7;
    /*  88 */ uint32 s2;
    /*  92 */ uint32 s3;
    /*  96 */ uint32 s4;
    /* 100 */ uint32 s5;
    /* 104 */ uint32 s6;
    /* 108 */ uint32 s7;
    /* 112 */ uint32 s8;
    /* 116 */ uint32 s9;
    /* 120 */ uint32 s10;
    /* 124 */ uint32 s11;
    /* 128 */ uint32 t3;
    /* 132 */ uint32 t4;
    /* 136 */ uint32 t5;
    /* 140 */ uint32 t6;
};  // 总大小: 144 bytes (xv6 RV64 为 280 bytes)

#endif
```

---

### 2.12 `include/context.h` — 上下文切换

```c
#ifndef _CONTEXT_H
#define _CONTEXT_H

#include "types.h"

// 内核上下文切换保存的寄存器 (callee-saved only)
struct context {
    uint32 ra;    // 返回地址
    uint32 sp;    // 栈指针
    uint32 s0;
    uint32 s1;
    uint32 s2;
    uint32 s3;
    uint32 s4;
    uint32 s5;
    uint32 s6;
    uint32 s7;
    uint32 s8;
    uint32 s9;
    uint32 s10;
    uint32 s11;
};  // 总大小: 56 bytes (xv6 RV64 为 112 bytes)

#endif
```

---

### 2.13 `include/spinlock.h` — 自旋锁

```c
#ifndef _SPINLOCK_H
#define _SPINLOCK_H

#include "types.h"

struct spinlock {
    uint32 locked;    // 是否持锁
    // 调试信息:
    char *name;       // 锁名称
    struct cpu *cpu;  // 持锁 CPU
};

#endif
```

---

### 2.14 `include/sleeplock.h` — 睡眠锁

```c
#ifndef _SLEEPLOCK_H
#define _SLEEPLOCK_H

#include "types.h"

struct sleeplock {
    uint32 locked;           // 是否持锁
    struct spinlock lk;      // 保护此结构的自旋锁
    char *name;              // 锁名称
    int pid;                 // 持锁进程
};

#endif
```

---

### 2.15 `include/vm.h` — 虚拟内存常量

```c
#ifndef _VM_H
#define _VM_H

#define SBRK_EAGER 1
#define SBRK_LAZY  2

#endif
```

---

### 2.16 `include/proc.h` — 进程控制块

```c
#ifndef _PROC_H
#define _PROC_H

#include "types.h"
#include "context.h"
#include "spinlock.h"
#include "trap.h"
#include "param.h"
#include "riscv.h"

// 进程状态
enum procstate { UNUSED, USED, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };

// 进程控制块 (精简版)
struct proc {
    struct spinlock lock;

    // p->lock 保护:
    enum procstate state;   // 进程状态
    void *chan;             // 等待通道
    int killed;             // 是否被 kill
    int xstate;             // 退出状态码
    int pid;                // 进程 ID

    // wait_lock 保护:
    struct proc *parent;    // 父进程

    // 进程私有 (无需锁):
    uint32 kstack;          // 内核栈虚拟地址
    uint32 sz;              // 进程内存大小 (bytes)
    pagetable_t pagetable;  // 用户页表
    struct trapframe *trapframe;  // 陷阱帧
    struct context context;       // 上下文切换
    struct file *ofile[NOFILE];   // 打开的文件
    char name[16];          // 进程名 (调试)
    // 注: 无 cwd (无文件系统)
};

#endif
```

---

### 2.17 `include/syscall.h` — 系统调用号

```c
#ifndef _SYSCALL_H
#define _SYSCALL_H

// ============================================================
// 系统调用号 (精简版: 无 FS 相关, 外设通过 syscall 代理)
// ============================================================

// --- 进程管理 ---
#define SYS_fork    1
#define SYS_exit    2
#define SYS_wait    3
#define SYS_getpid  4
#define SYS_kill    5

// --- 内存管理 ---
#define SYS_sbrk    6

// --- 文件/IO (console + pipe, 无 FS) ---
#define SYS_read    7
#define SYS_write   8
#define SYS_close   9
#define SYS_dup     10
#define SYS_pipe    11

// --- 时间/调度 ---
#define SYS_pause   12   // sleep(ms)
#define SYS_uptime  13   // 获取 mtime

// --- 外设代理 (通过 syscall 防止资源竞争) ---
#define SYS_gpio_read    14   // int gpio_read(int pin)
#define SYS_gpio_write   15   // void gpio_write(int pin, int val)
#define SYS_spi_transfer 16   // int spi_transfer(unsigned char byte)

// --- 预留 ---
#define SYS_exec    17   // 预留: 加载并执行 (未来 FS)
#define SYS_open    18   // 预留: 打开文件 (未来 FS)
#define SYS_fstat   19   // 预留: 文件状态 (未来 FS)

#define NSYSCALL    19   // 系统调用总数

#endif
```

**与 xv6 差异**: 删除 `chdir/mknod/unlink/link/mkdir`；重新编号；新增 `gpio_read/gpio_write/spi_transfer`；`exec/open/fstat` 降为预留。

---

### 2.18 `include/stat.h` — 文件状态 (预留空壳)

```c
#ifndef _STAT_H
#define _STAT_H

#include "types.h"

// 预留: 文件系统未实现
#define T_DIR    1
#define T_FILE   2
#define T_DEVICE 3

struct stat {
    int dev;
    uint ino;
    short type;
    short nlink;
    uint32 size;
};

#endif
```

---

### 2.19 `include/fcntl.h` — 文件控制标志 (预留空壳)

```c
#ifndef _FCNTL_H
#define _FCNTL_H

#define O_RDONLY 0x000
#define O_WRONLY 0x001
#define O_RDWR   0x002
#define O_CREATE 0x200
#define O_TRUNC  0x400

#endif
```

---

### 2.20 `include/elf.h` — ELF 格式 (RV32 预留)

```c
#ifndef _ELF_H
#define _ELF_H

#include "types.h"

#define ELF_MAGIC 0x464C457FU

struct elfhdr {
    uint magic;
    uchar elf[12];
    ushort type;
    ushort machine;
    uint version;
    uint32 entry;    // RV32: 32-bit 入口点
    uint32 phoff;
    uint32 shoff;
    uint flags;
    ushort ehsize;
    ushort phentsize;
    ushort phnum;
    ushort shentsize;
    ushort shnum;
    ushort shstrndx;
};

struct proghdr {
    uint32 type;
    uint32 flags;
    uint32 off;
    uint32 vaddr;
    uint32 paddr;
    uint32 filesz;
    uint32 memsz;
    uint32 align;
};

#define ELF_PROG_LOAD      1
#define ELF_PROG_FLAG_EXEC  1
#define ELF_PROG_FLAG_WRITE 2
#define ELF_PROG_FLAG_READ  4

#endif
```

---

### 2.21 `include/defs.h` — 内核函数声明

```c
#ifndef _DEFS_H
#define _DEFS_H

struct spinlock;
struct sleeplock;
struct proc;
struct file;
struct pipe;
struct trapframe;

// --- kalloc.c ---
void *kalloc(void);
void  kfree(void *);
void  kinit(void);

// --- vm.c ---
void       kvminit(void);
void       kvminithart(void);
void       kvmmap(pagetable_t, uint32, uint32, uint32, int);
int        mappages(pagetable_t, uint32, uint32, uint32, int);
pagetable_t uvmcreate(void);
uint32     uvmalloc(pagetable_t, uint32, uint32, int);
uint32     uvmdealloc(pagetable_t, uint32, uint32);
int        uvmcopy(pagetable_t, pagetable_t, uint32);
void       uvmfree(pagetable_t, uint32);
void       uvmunmap(pagetable_t, uint32, uint32, int);
pte_t *    walk(pagetable_t, uint32, int);
uint32     walkaddr(pagetable_t, uint32);
int        copyout(pagetable_t, uint32, char *, uint32);
int        copyin(pagetable_t, char *, uint32, uint32);
int        copyinstr(pagetable_t, char *, uint32, uint32);

// --- proc.c ---
int         cpuid(void);
void        kexit(int) __attribute__((noreturn));
int         kfork(void);
int         growproc(int);
int         kkill(int);
int         killed(struct proc *);
void        setkilled(struct proc *);
struct proc *myproc(void);
void        procinit(void);
void        scheduler(void) __attribute__((noreturn));
void        sched(void);
void        sleep(void *, struct spinlock *);
void        userinit(void);
int         kwait(uint32);
void        wakeup(void *);
void        yield(void);
int         either_copyout(int, uint32, void *, uint32);
int         either_copyin(void *, int, uint32, uint32);

// --- swtch.S ---
void swtch(struct context *, struct context *);

// --- trap.c ---
extern uint ticks;
extern struct spinlock tickslock;
void trapinit(void);
void usertrap(void);
void usertrapret(void);
void kerneltrap(void);

// --- uart.c ---
void uartinit(void);
void uartintr(void);
void uartputc(int);
int  uartgetc(void);

// --- console.c ---
void consoleinit(void);
void consoleintr(int);
void consputc(int);

// --- plic.c ---
void   plic_init(void);
void   plic_init_hart(void);
uint32 plic_claim(void);
void   plic_complete(uint32);

// --- clint.c (新增) ---
uint64 clint_read_mtime(void);
void   clint_write_mtimecmp(uint64);
void   clint_set_msip(uint32, uint32);
void   clint_set_timer_interval(uint64);
void   timerinit(void);         // 设置第一次定时器中断
void   timer_intr_handler(void); // 定时器中断处理

// --- syscall.c ---
void argint(int, int *);
int  argstr(int, char *, int);
void argaddr(int, uint32 *);
void syscall(void);

// --- sysproc.c ---
// (syscall 实现，由 syscall.c 分发)

// --- sysfile.c ---
// (文件/IO syscall 实现)

// --- pipe.c ---
int  pipealloc(struct file **, struct file **);
void pipeclose(struct pipe *, int);
int  piperead(struct pipe *, uint32, int);
int  pipewrite(struct pipe *, uint32, int);

// --- file.c ---
struct file *filealloc(void);
void        fileclose(struct file *);
struct file *filedup(struct file *);
void        fileinit(void);
int         fileread(struct file *, uint32, int);
int         filewrite(struct file *, uint32, int);

// --- printf.c ---
int  printf(char *, ...) __attribute__((format(printf, 1, 2)));
void panic(char *) __attribute__((noreturn));

// --- spinlock.c ---
void acquire(struct spinlock *);
int  holding(struct spinlock *);
void initlock(struct spinlock *, char *);
void release(struct spinlock *);
void push_off(void);
void pop_off(void);

// --- sleeplock.c ---
void acquiresleep(struct sleeplock *);
void releasesleep(struct sleeplock *);
int  holdingsleep(struct sleeplock *);
void initsleeplock(struct sleeplock *, char *);

// --- string.c ---
int   memcmp(const void *, const void *, uint);
void *memmove(void *, const void *, uint);
void *memset(void *, int, uint);
char *safestrcpy(char *, const char *, int);
int   strlen(const char *);
int   strncmp(const char *, const char *, uint);
char *strncpy(char *, const char *, int);

// --- 数组元素数 ---
#define NELEM(x) (sizeof(x) / sizeof((x)[0]))

#endif
```

---

### 2.22 `user/user.h` — 用户态 API

```c
#ifndef _USER_H
#define _USER_H

#include "types.h"

struct stat;

// ============================================================
// 系统调用 (全部通过 ecall，内核代理执行)
// ============================================================

// 进程管理
int  fork(void);
int  exit(int) __attribute__((noreturn));
int  wait(int *);
int  getpid(void);
int  kill(int);

// 内存管理
char *sbrk(int);

// 文件/IO (console + pipe)
int  read(int, void *, int);
int  write(int, const void *, int);
int  close(int);
int  dup(int);
int  pipe(int *);

// 时间/调度
int  pause(int);      // sleep(ms)
uint64 uptime(void);  // 获取 mtime (64-bit)

// 外设代理 (通过 syscall，防止资源竞争)
int  gpio_read(int pin);           // 读取 GPIO 引脚
void gpio_write(int pin, int val); // 写入 GPIO 引脚
int  spi_transfer(unsigned char byte); // SPI 传输

// ============================================================
// 用户库 (ulib.c)
// ============================================================
int   strcmp(const char *, const char *);
char *strcpy(char *, const char *);
uint  strlen(const char *);
void *memset(void *, int, uint);
void *memmove(void *, const void *, int);
int   atoi(const char *);
char *gets(char *, int);

// printf (user/printf.c)
void printf(const char *, ...) __attribute__((format(printf, 1, 2)));

// malloc (user/umalloc.c)
void *malloc(uint);
void  free(void *);

#endif
```

---

## 3. 内核源码实现计划

### 3.1 实现阶段

| 阶段 | 目标 | 文件 | 依赖头文件 |
|------|------|------|-----------|
| **Phase 0: 启动** | M-mode → S-mode 跳转 | `entry.S`, `start.c`, `kernel.ld` | `riscv.h`, `memlayout.h` |
| **Phase 1: 内存** | 物理页分配 + Sv32 内核页表 | `kalloc.c`, `vm.c` | `types.h`, `param.h`, `memlayout.h`, `riscv.h`, `spinlock.h`, `defs.h` |
| **Phase 2: 陷阱** | S-mode 陷阱处理 + 定时器中断 | `trap.c`, `kernelvec.S`, `trampoline.S` | `trap.h`, `context.h`, `riscv.h`, `proc.h` |
| **Phase 3: 中断** | PLIC + CLINT + UART 中断 | `plic.c`, `clint.c`, `uart.c` | `plic.h`, `clint.h`, `uart.h`, `memlayout.h` |
| **Phase 4: 进程** | 进程管理 + 调度器 + 上下文切换 | `proc.c`, `swtch.S` | `proc.h`, `context.h`, `trap.h`, `spinlock.h` |
| **Phase 5: syscall** | 系统调用分发 + 实现 | `syscall.c`, `sysproc.c`, `sysfile.c` | `syscall.h`, `proc.h`, `defs.h` |
| **Phase 6: IO** | 控制台 + printf + 管道 | `console.c`, `printf.c`, `pipe.c`, `file.c` | `uart.h`, `spinlock.h`, `sleeplock.h` |
| **Phase 7: 用户** | 用户库 + init 进程 | `user.h`, `usys.S`, `ulib.c`, `umalloc.c`, `init.c` | `types.h`, `syscall.h`, `user.h` |

### 3.2 Phase 0: 启动 (entry.S + start.c)

**entry.S** (M-mode, 物理地址):
1. 设置栈指针 `sp = KSTACK(0)` 的物理地址
2. 跳转到 `start.c:start()`

**start.c** (M-mode 初始化):
1. `w_mstatus`: 将 MPP 设为 S-mode (return to S-mode after mret)
2. `w_mepc`: 设为 `main.c:main()` 的物理地址
3. `w_medeleg/mideleg`: 委托所有异常/中断到 S-mode (除 ECALL-from-M)
4. `w_satp`: 清零 (禁用 Sv32，物理地址直通)
5. `w_mtvec`: 设为 M-mode 陷阱向量 (临时)
6. `w_mie`: 禁用所有 M-mode 中断
7. `mret`: 跳转到 S-mode main()

**kernel.ld** (链接脚本):
- `.text` 从 `KERNBASE` 开始
- 定义 `etext`, `edata`, `end` 符号供 kalloc 使用
- 对齐到页边界

### 3.3 Phase 1: 内存管理 (kalloc.c + vm.c)

**kalloc.c**:
- 空闲页链表 (kmem.freelist)
- 可用页范围: `end` ~ `PHYSTOP` (约 32KB - 内核大小)
- `kinit()`: 将可用范围逐页加入空闲链表
- `kalloc()`: 取出空闲页，清零返回
- `kfree()`: 释放页，加入空闲链表

**vm.c** (Sv32 适配):
- `kvminit()`: 创建内核页表
  - 映射 SRAM (KERNBASE~PHYSTOP) 可读写
  - 映射 MMIO 区域 (CLINT/PLIC/APB) 可读写
  - 映射 trampoline 页 (TRAMPOLINE)
- `uvmcreate()`: 创建空用户页表 (仅 trampoline)
- `uvmalloc()`: 扩展用户内存 (分配页 + 映射)
- `uvmdealloc()`: 缩减用户内存 (解除映射 + 释放页)
- `mappages()`: Sv32 二级页表映射 (walk L1 → walk L0 → 设置 PTE)
- `walk()`: Sv32 页表漫游 (返回 L0 PTE 指针)
- `copyout/copyin/copyinstr`: 用户/内核空间数据拷贝

**Sv32 walk 逻辑** (与 xv6 Sv39 的关键差异):
```c
pte_t *walk(pagetable_t pagetable, uint32 va, int alloc) {
    if (va >= MAXVA) return 0;
    for (int level = 1; level >= 0; level--) {  // 2级: L1→L0
        pte_t *pte = &pagetable[PX(level, va)];  // PX 使用 10-bit 索引
        if (*pte & PTE_V) {
            pagetable = (pagetable_t)PTE2PA(*pte);
        } else {
            if (!alloc || (pagetable = kalloc()) == 0) return 0;
            memset(pagetable, 0, PGSIZE);
            *pte = PA2PTE((uint32)pagetable) | PTE_V;
        }
    }
    return &pagetable[PX(0, va)];
}
```

### 3.4 Phase 2: 陷阱处理 (trap.c + trampoline.S)

**kernelvec.S**: S-mode 内核陷阱向量
- 保存寄存器到内核栈
- 跳转到 `kerneltrap()` 或 `usertrap()`

**trampoline.S**: 用户↔内核切换跳板页
- `uservec`: 用户陷阱入口 → 保存寄存器到 trapframe → 切换内核栈/页表 → 跳转 usertrap()
- `userret`: 返回用户态 → 恢复 trapframe → 切换用户页表 → sret

**trap.c**:
- `usertrap()`: 处理用户态陷阱
  - 设 `p->trapframe->epc = r_sepc()`
  - 根据 `r_scause()` 分发:
    - 8 (ECALL from U): 系统调用 → `syscall()`
    - 13/15 (页错误): 处理缺页
    - 中断: 定时器 → `timer_intr_handler()`, 外部 → `dev_intr()`
  - `usertrapret()`: 设置返回用户态
- `kerneltrap()`: 处理内核态陷阱 (主要是中断)
  - 定时器中断: `timer_intr_handler()`
  - 外部中断: `dev_intr()`

### 3.5 Phase 3: 中断驱动 (plic.c + clint.c + uart.c)

**plic.c**:
- `plic_init()`: 禁用所有中断源，设置优先级
- `plic_init_hart()`: S-mode 使能所需中断源 (UART + Timer)
- `plic_claim()`: 读取 SCLAIM 寄存器
- `plic_complete()`: 写入 SCLAIM 完成中断

**clint.c** (mtime 高/低 32-bit 原子访问):
```c
uint64 clint_read_mtime(void) {
    uint32 lo, hi, hi2;
    do {
        hi  = *(volatile uint32 *)CLINT_MTIME_H;
        lo  = *(volatile uint32 *)CLINT_MTIME;
        hi2 = *(volatile uint32 *)CLINT_MTIME_H;  // 检测翻转
    } while (hi != hi2);
    return ((uint64)hi << 32) | lo;
}

void clint_write_mtimecmp(uint64 val) {
    *(volatile uint32 *)CLINT_MTIMECMP_H = (uint32)(val >> 32);  // 先写高
    *(volatile uint32 *)CLINT_MTIMECMP   = (uint32)(val);        // 再写低
}

void clint_set_timer_interval(uint64 interval) {
    uint64 now = clint_read_mtime();
    clint_write_mtimecmp(now + interval);
}
```

**uart.c** (内核态 MMIO 驱动):
- `uartinit()`: 使能 TX/RX，设置波特率，使能 RX 中断
- `uartputc(int c)`: 轮询方式发送 (等待 TX FIFO 非满)
- `uartgetc()`: 读取 RX FIFO (非阻塞，返回 -1 若空)
- `uartintr()`: UART 中断处理
  - 读取 IRQ_STAT，若 RX_VALID 则从 RXDATA 读取并推入 console 缓冲
  - 清除 IRQ_STAT (写 1 清除)

**timer_intr_handler()**:
1. 调用 `clint_set_timer_interval(next_interval)` 设置下次中断
2. `ticks++` (唤醒 sleep 的进程)

### 3.6 Phase 4: 进程管理 (proc.c + swtch.S)

**proc.c**:
- `procinit()`: 初始化进程表，分配内核栈
- `userinit()`: 创建第一个用户进程 (initcode 内嵌在内核中)
- `kfork()`: 创建子进程 (复制父进程内存+页表)
- `kexit()`: 进程退出，唤醒父进程
- `kwait()`: 等待子进程退出
- `scheduler()`: 简单轮转调度
  - 遍历 proc 表，找 RUNNABLE 进程
  - `swtch()` 切换到该进程上下文
- `sleep()/wakeup()`: 条件变量式等待/唤醒
- `myproc()`: 通过 tp 寄存器获取当前 CPU 的当前进程

**swtch.S** (RV32 callee-saved 切换):
- 保存 ra, sp, s0-s11 到旧 context
- 从新 context 恢复 ra, sp, s0-s11
- ret (跳转到新 context 的 ra)

### 3.7 Phase 5: 系统调用 (syscall.c + sysproc.c + sysfile.c)

**syscall.c**:
- `syscall()`: 从 trapframe->a7 获取调用号，查 `syscalls[]` 表分发
- `argint()/argaddr()/argstr()`: 从 trapframe 提取参数 a0-a5

**sysproc.c**:
- `sys_fork()`: 调用 `kfork()`
- `sys_exit()`: 调用 `kexit()`
- `sys_wait()`: 调用 `kwait()`
- `sys_getpid()`: 返回 `myproc()->pid`
- `sys_kill()`: 调用 `kkill()`
- `sys_sbrk()`: 调用 `growproc()`
- `sys_pause()`: 调用 `sleep()`
- `sys_uptime()`: 返回 `clint_read_mtime()`

**sysfile.c**:
- `sys_read()`: 调用 `fileread()`
- `sys_write()`: 调用 `filewrite()`
- `sys_close()`: 调用 `fileclose()`
- `sys_dup()`: 调用 `filedup()`
- `sys_pipe()`: 调用 `pipealloc()`
- `sys_gpio_read()`: 内核态读取 GPIO 寄存器 → 返回引脚值
- `sys_gpio_write()`: 内核态写入 GPIO 寄存器
- `sys_spi_transfer()`: 内核态执行 SPI 传输 → 返回接收字节

### 3.8 Phase 6: IO (console.c + printf.c + pipe.c + file.c)

**console.c**:
- 输入缓冲区 (cons.buf) + 读指针/写指针
- `consoleinit()`: 连接 UART 中断到 console
- `consoleintr()`: UART 中断调用，将字符放入输入缓冲，唤醒等待的 read
- `consputc()`: 输出字符到 UART

**printf.c**:
- 精简版 printf: 支持 %d, %x, %s, %c, %p
- `panic()`: 打印消息后死循环

**pipe.c**: 管道实现 (与 xv6 相同，仅类型适配)

**file.c**: 文件描述符管理 (与 xv6 相同，仅类型适配)

### 3.9 Phase 7: 用户态 (user.h + usys.S + ulib.c + umalloc.c)

**usys.S** (自动生成或手写):
```asm
# 每个 syscall 的桩:
.global fork
fork:
    li a7, 1      # SYS_fork
    ecall
    ret

.global exit
exit:
    li a7, 2      # SYS_exit
    ecall
    ret
# ... (共 NSYSCALL 个)
```

**ulib.c**: 用户库 (与 xv6 相同，仅类型适配)
- `start()`: 调用 main() 后 exit
- `strcpy/strcmp/strlen/memset/memmove/atoi/gets`

**umalloc.c**: 简易 malloc/free (基于 sbrk)

**init.c** (未来): 第一个用户进程，启动 shell

---

## 4. 构建系统

### 4.1 工具链

- **编译器**: RISC-V 32-bit GCC (`riscv32-unknown-elf-gcc` 或 `riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32`)
- **链接器**: `riscv32-unknown-elf-ld`
- **目标格式**: 通过 `tools/rv2coe.py` 生成 hex/coe 加载到 BRAM

### 4.2 编译标志

```makefile
CFLAGS = -march=rv32im -mabi=ilp32 -mcmodel=medany \
         -ffreestanding -fno-builtin -nostdinc \
         -I include -Wall -Werror -O2

# 内核: -DKERNEL
# 用户: 无额外定义
```

### 4.3 构建流程

```
kernel/*.c + kernel/*.S  →  kernel.elf  →  kernel.hex  →  BRAM
user/*.c + user/*.S      →  user code 嵌入内核 (初期)
```

初期无 exec，用户代码直接嵌入内核 (类似 xv6 的 initcode)。

---

## 5. 待确认事项

| # | 事项 | 需读取的文件 | 影响 |
|---|------|-------------|------|
| 1 | APB 外设地址偏移 (UART/GPIO/Timer/SPI 在 APB 空间中的偏移) | `src/rtl/APB/apb_decoder.sv` | `memlayout.h` 中 `UART_BASE/GPIO_BASE/TIMER_BASE/SPI_BASE` |
| 2 | CLINT 寄存器间距 (mtime/mtimecmp 高低 32-bit 偏移) | `src/rtl/axi/ahb_clint.sv` | `memlayout.h` 中 `CLINT_MTIMECMP_H/CLINT_MTIME_H` |
| 3 | PLIC 寄存器间距 (enable/pending 寄存器布局) | `src/rtl/axi/ahb_plic.sv` | `plic.h` 中 enable 寄存器地址计算 |
| 4 | APB Timer 寄存器布局确认 | `src/rtl/APB/perips/timer.sv` | `timer.h` 中寄存器偏移 |
| 5 | 内核代码大小估算 (32KB RAM 中内核占多少) | 编译后测量 | `param.h` 中可用页数 |

---

## 6. 验证计划

| 阶段 | 验证方式 | 预期结果 |
|------|---------|---------|
| Phase 0 | 仿真: entry.S 执行后进入 S-mode main() | UART 输出 "hello from kernel" |
| Phase 1 | 仿真: kalloc/vm 初始化成功 | 内核页表正确映射 |
| Phase 2 | 仿真: ecall 触发 S-mode 陷阱 | 陷阱处理正确返回 |
| Phase 3 | 仿真: 定时器中断周期触发 | ticks 计数递增 |
| Phase 4 | 仿真: fork + 调度切换 | 两个进程交替执行 |
| Phase 5 | 仿真: 用户态 syscall | fork/exit/wait 返回正确 |
| Phase 6 | 仿真: console read/write | UART 回显字符 |
| Phase 7 | 仿真: init 进程运行 | 简易 shell 可交互 |

每个阶段使用 Vivado XSim 仿真，通过 UART 输出和寄存器检查验证。
