# SimpleOS — RISC-V M/S/U 特权级 + sv32 分页操作系统

SimpleOS 是运行在自研 RISC-V CPU 上的最小化操作系统演示。它在约 1500 行 C/汇编代码内完整展示了：

- **M → S → U 三级特权转换**（mret / sret / ecall）
- **Sv32 分页**（L1 + 2×L0 三级页表，内核恒等映射 + 用户映射）
- **系统调用**（SYS_write / SYS_read / SYS_report / SYS_exit，ecall 陷入分发）
- **U-mode 浮点计算器**（RV32IMF，递归下降解析器，5 项自检测试）

整个系统单核单进程，没有调度器、文件系统、IPC 或中断，但足以验证 CPU 的 MMU、PTW、CSR、特权切换、FPU 全栈功能。

---

## 目录

1. [系统概述](#1-系统概述)
2. [架构设计](#2-架构设计)
3. [内存布局](#3-内存布局)
4. [特权级转换](#4-特权级转换)
5. [sv32 页表设计](#5-sv32-页表设计)
6. [系统调用接口](#6-系统调用接口)
7. [目录结构](#7-目录结构)
8. [编译命令](#8-编译命令)
9. [仿真命令](#9-仿真命令)
10. [预期输出](#10-预期输出)
11. [自检协议](#11-自检协议)
12. [调试技巧](#12-调试技巧)
13. [设计约束](#13-设计约束)
14. [关键设计决策](#14-关键设计决策)
15. [FPGA 上板](#15-fpga-上板)

---

## 1. 系统概述

SimpleOS 是一个教学/验证用操作系统，目标是验证自研 RISC-V CPU 的特权级与分页机制。它不是 Linux，也不是 xv6，而是一个"刚好够用"的微型 OS：

- **M-mode**：`entry.S` → `m_init.c`。建页表、配委托、开分页、`mret` 进 S-mode。
- **S-mode**：`s_main.c` → `trap.S`/`trap.c`/`syscall.c`。装 stvec、开 FPU、打印 banner、`sret` 进 U-mode，之后作为 syscall 服务器。
- **U-mode**：`user_start.S` → `calculator.c`。浮点计算器先跑 5 项自检，通过 `SYS_report` 把成绩写回内存（不停机），然后进入交互模式，用户可通过 UART 输入表达式实时计算，输入 `exit` 退出。

启动流程一图概览：

```
  reset (PC=0x80000000)
     │
     ▼  bootloader_phase1 跳转到 0x80004000
  _start (entry.S, M-mode)
     │  sp = 0x80004000
     ▼
  m_init (m_init.c, M-mode)
     │  1. 清零 3 张页表
     │  2. 建 L1 + L0_kernel + L0_user
     │  3. medeleg = 0xB100 (委托 U-ecall/PF 给 S)
     │  4. mstatus.MPP = S, mstatus.FS = 01
     │  5. mepc = s_mode_entry
     │  6. satp = Sv32 | L1 base
     │  7. sfence.vma + fence.i
     └── mret ──▶ s_mode_entry (S-mode)
                    │  stvec = trap_handler
                    │  sstatus.FS = 01 (开 FPU)
                    │  uart_puts("SimpleOS booted\n")
                    │  sstatus.SPP = 0, sepc = 0x0
                    └── sret ──▶ _start (U-mode, VA=0x0)
                                  │  sp = 0x9000
                                  │  清 bss
                                  │  call main
                                  │    └─ run_tests()
                                  │         ├─ sys_write("1+2 = 3.000000\n")
                                  │         ├─ ... (5 项测试)
                                  │         └─ sys_report(5, 5, 0)
                                  │              └─ ecall ▶ S-mode
                                  │                   写 0x80007000（不停机，返回 U-mode）
                                  │
                                  │  ── 交互模式 ──
                                  │    printf("=== RISC-V FPU Calculator ===\n")
                                  │    for (;;) {
                                  │      printf("> ")
                                  │      gets(input)           ← sys_read 阻塞等待 UART
                                  │      if "exit": sys_exit() ← 停机
                                  │      parse_expr() → print result
                                  │    }
                                  ▼
                            （仿真：等 200M 周期后 TB $finish）
                            （上板：用户交互，输入 exit 停机）
```

---

## 2. 架构设计

### 2.1 特权模型

SimpleOS 使用 RISC-V 标准的 M/S/U 三级特权模型：

| 特权级 | 值 | 执行者 | 入口 | 出口 |
|--------|----|--------|------|------|
| M-mode | 3 | `entry.S` + `m_init.c` | reset | `mret` |
| S-mode | 1 | `s_main.c` + `trap.S/.c` + `syscall.c` | `mret` / `ecall` 陷入 | `sret` |
| U-mode | 0 | `user_start.S` + `calculator.c` | `sret` | `ecall` |

特权级值与 RTL `MMU.sv` 一致：`PRIV_U=0, PRIV_S=1, PRIV_M=3`。

### 2.2 单页表设计

SimpleOS **全程使用同一张页表**，陷入和返回时不切换 `satp`。这是关键简化：

- L1 页表同时包含内核映射（VA 0x80000000+ 恒等映射）和用户映射（VA 0x0 → PA 0x80008000）。
- S-mode 和 U-mode 共用 `satp`，区别仅在 PTE 的 U 位：内核页 U=0，用户页 U=1。
- 陷入时无需保存/恢复 `satp`，trap handler 只需保存 GPR + sepc/sstatus。

### 2.3 陷入流

```
U-mode ecall
   │
   ▼  硬件：sepc←PC, scause←8, sstatus.SPP←0, 切到 S-mode, PC←stvec
trap_handler (trap.S)
   │  sscratch ← user_sp
   │  sp ← _kernel_stack_top (0x80004000)
   │  保存 x1-x31 + sepc/sstatus/scause/stval 到栈帧 (144 字节)
   ▼
trap_dispatch (trap.c)
   │  scause == 8 (ECALL_U)?
   │    → sepc += 4
   │    → syscall_handle(tf)
   │       ├─ a7=8: SYS_write, VA 转换后 uart_putc 循环
   │       ├─ a7=7: SYS_read, uart_getc 循环
   │       └─ a7=2: SYS_exit, 写 0x80007000, 打印, wfi 停机
   ▼
trap_handler 恢复
   │  恢复 sepc, sstatus
   │  恢复 x1, x3-x31
   │  sp ← user_sp (lw sp, 4(sp))
   └── sret ──▶ U-mode (sepc 处继续)
```

---

## 3. 内存布局

### 3.1 物理内存映射（DDR3 @ 0x80000000）

所有物理地址落在 128 MB DDR3 窗口内，SimpleOS 仅用低 68 KB：

```
PA              大小      用途                        来源
──────────────────────────────────────────────────────────────
0x80000000      4 KB     L1 页表 (1024 项)           memlayout.h: PA_L1_PT
0x80001000      4 KB     L0 内核页表 (1024 项)        memlayout.h: PA_L0_KERNEL_PT
0x80002000      4 KB     L0 用户页表 (1024 项)        memlayout.h: PA_L0_USER_PT
0x80003000      4 KB     内核栈 (向下生长)            memlayout.h: PA_KERNEL_STACK
0x80004000      12 KB    内核代码 (.text/.rodata/.data) os.ld: KERNEL ORIGIN
0x80007000      4 KB     自检结果区                   memlayout.h: PA_SELF_CHECK
0x80008000      32 KB    用户程序镜像 (.incbin 嵌入)  memlayout.h: PA_USER_PROG
0x80010000      4 KB     用户栈顶                     memlayout.h: PA_USER_STACK
──────────────────────────────────────────────────────────────
0x80011000               (SimpleOS 不再使用更高地址)
```

> 注意：`0x80000000-0x80004000` 这 16 KB 在 hex 文件里是零填充 + 跳转指令，运行时被 `m_init` 覆盖为页表。

### 3.2 虚拟内存映射（Sv32）

```
VA              →  PA              权限          说明
─────────────────────────────────────────────────────────────
0x00000000-0x00007FFF → 0x80008000-0x8000FFFF  RWXU AD   用户代码+数据 (8 页)
0x00008000-0x00008FFF → 0x80010000-0x80010FFF  RWU AD    用户栈 (1 页, 无 X)
0x10000000-0x103FFFFF → 0x10000000 (恒等)      RW AD     UART 设备 (L1 megapage, 无 U 无 X)
0x80000000-0x80010FFF → 0x80000000 (恒等)      见下表     内核全区间 (L0 恒等映射)
```

内核恒等映射的 L0 页表项权限（VA == PA）：

```
PA 区间                       PTE flags          说明
0x80000000-0x80002FFF        V R W A D          页表本身 (3 页, 无 X 无 U)
0x80003000-0x80003FFF        V R W A D          内核栈 (1 页, 无 X 无 U)
0x80004000-0x80006FFF        V R W X A D        内核代码 (3 页, 无 U)
0x80007000-0x80007FFF        V R W A D          自检区 (1 页, 无 X 无 U)
0x80008000-0x8000FFFF        V R W X A D        用户镜像 (8 页, 无 U! 见 §14)
0x80010000-0x80010FFF        V R W A D          用户栈 (1 页, 无 U! 见 §14)
```

### 3.3 MMIO

| 设备 | 基地址 | 说明 |
|------|--------|------|
| UART | 0x10008000 | NS16550A，与 `sys.h` 一致 |
| DDR3 | 0x80000000 | 128 MB 主存 |

---

## 4. 特权级转换

### 4.1 M → S（mret）

发生在 `m_init.c` 末尾。CSR 写入序列（与 RTL `page_table_utils.s` 参考一致）：

```c
// 1. 委托：U-ecall(8) + 指令页错误(12) + load页错误(13) + store页错误(15) → S-mode
csrw(medeleg, (1U << 8) | (1U << 12) | (1U << 13) | (1U << 15));  // = 0xB100

// 2. mideleg（RTL wmask=0x0888，此值被硬件屏蔽为 0，无害）
csrw(mideleg, (1U << 9) | (1U << 5) | (1U << 1));  // = 0x222

// 3. mstatus: MPP=S (bit11=1,bit12=0), FS=01 (bit13=1)
csrr(mstatus, val);
val = (val & ~MSTATUS_MPP_M) | MSTATUS_MPP_S | (1U << 13);
csrw(mstatus, val);

// 4. mepc = S-mode 入口
csrw(mepc, (uint32_t)(uintptr_t)s_mode_entry);

// 5. satp = Sv32 | ASID=0 | L1 base
csrw(satp, satp_make(SATP_MODE_SV32, 0, PA_L1_PT));  // = 0x80000000

// 6. sfence.vma（写 satp 不自动刷 TLB！）
sfence_vma();

// 7. fence.i（dcache 写回 + icache 失效，确保 PTW 读到新页表）
fence_i();

// 8. mret → 跳到 mepc，特权级 ← MPP = S
__asm__ volatile("mret");
```

> **medeleg 掩码**：RTL `medeleg_wmask = 0xB1FF`，bit 9（S-ecall）硬连线 0，bit 8（U-ecall）可写。我们写 0xB100 落在掩码内。

### 4.2 S → U（sret）

发生在 `s_main.c`：

```c
// 1. stvec = trap_handler（DIRECT 模式，低 2 位 = 00）
csrw(stvec, (uint32_t)(uintptr_t)trap_handler);

// 2. 开 FPU：sstatus.FS = 01（bit 13）
csrr(sstatus, val);
val |= (1U << 13);
csrw(sstatus, val);

// 3. sscratch = 0（trap.S 每次陷入会覆盖它）
csrw(sscratch, 0);

// 4. 打印 banner
uart_puts("SimpleOS booted\n");

// 5. SPP = 0（bit 8 清零 → sret 回 U-mode）
csrr(sstatus, val);
val &= ~(1U << 8);
csrw(sstatus, val);

// 6. sepc = 用户入口（VA 0x0）
csrw(sepc, VA_USER_BASE);  // = 0x00000000

// 7. sret → 跳到 sepc，特权级 ← SPP = U
__asm__ volatile("sret");
```

### 4.3 U → S（ecall 陷入）

用户执行 `ecall` 时硬件自动完成：

1. `sepc` ← ecall 指令的 PC
2. `scause` ← 8（ECALL_U）
3. `sstatus.SPP` ← 0（来自 U-mode）
4. `sstatus.SPIE` ← `sstatus.SIE`
5. `sstatus.SIE` ← 0（关 S-mode 中断）
6. PC ← `stvec`（即 `trap_handler`）
7. 特权级 ← S

`trap_dispatch` 处理后 `sepc += 4`（ecall 是 4 字节，无 C 扩展），`sret` 回到 ecall 的下一条指令。

---

## 5. sv32 页表设计

### 5.1 三张页表

| 页表 | 物理地址 | 项数 | 作用 |
|------|----------|------|------|
| L1 | 0x80000000 | 1024 | 顶级表，3 个有效项 |
| L0_kernel | 0x80001000 | 1024 | 内核恒等映射（VA 0x80000000-0x803FFFFF） |
| L0_user | 0x80002000 | 1024 | 用户映射（VA 0x00000000-0x003FFFFF） |

### 5.2 L1 页表项

```
L1[0]    (VPN1=0x000)   → L0_user   @ 0x80002000   flags=V        (用户低 4 MB)
L1[64]   (VPN1=0x040)   → megapage  @ 0x10000000   flags=V R W A D (UART 4 MB, 叶子)
L1[512]  (VPN1=0x200)   → L0_kernel @ 0x80001000   flags=V        (内核 4 MB)
其余 1021 项 = 0 (无效)
```

> `VPN1(0x80000000) = 0x80000000 >> 22 = 0x200 = 512`，不是 2。这是 Sv32 的标准索引。

### 5.3 PTE 格式（Sv32）

```
 31                  20 19                  10 9    8 7 6 5 4 3 2 1 0
┌──────────────────────┬──────────────────────┬──────┬─┬─┬─┬─┬─┬─┬─┬─┐
│      PPN[1] (10b)    │      PPN[0] (10b)    │ RSW  │D│A│G│U│X│W│R│V│
└──────────────────────┴──────────────────────┴──────┴─┴─┴─┴─┴─┴─┴─┴─┘
```

PTE 位定义（`riscv.h`，与 RTL `ptw.sv` 行 129-137 完全一致）：

| 位 | 名称 | 值 | 说明 |
|----|------|----|------|
| 0 | V | 0x001 | Valid |
| 1 | R | 0x002 | Readable |
| 2 | W | 0x004 | Writable |
| 3 | X | 0x008 | Executable |
| 4 | U | 0x010 | User-accessible |
| 5 | G | 0x020 | Global |
| 6 | A | 0x040 | Accessed |
| 7 | D | 0x080 | Dirty |

PPN = `pte[31:10]`（22 位），PA = `PPN << 12`。

### 5.4 pte_make 公式

```c
static inline uint32_t pte_make(uint32_t pa, uint32_t flags) {
    return ((pa >> 12) << 10) | (flags & PTE_FLAGS_MASK);
}
```

即 `PTE = (PA >> 12) << 10 | flags`。这与参考实现 `page_table_utils.s` 的 `srli x17,x16,12; slli x17,x17,10; ori x17,x17,flags` 完全一致。

**关键**：早期版本曾误用 `(pa >> 10) << 10`，导致 PTW 解析出错误 PA。正确做法是先 `>> 12`（去掉页内偏移）再 `<< 10`（对齐到 PPN 字段）。

### 5.5 A/D 位预置

自研 CPU 的 PTW **不会自动置位 A/D**。若叶子 PTE 的 A=0 或 D=0，PTW 会触发页错误。因此 SimpleOS 在建表时就把所有叶子 PTE 的 A=1、D=1 预置好：

| 组合 | 值 | 用途 |
|------|----|------|
| `PTE_RWXAD` | 0xCF | 内核代码页 |
| `PTE_RWAD` | 0xC7 | 内核数据/栈/页表/自检页 |
| `PTE_RWXUAD` | 0xDF | 用户代码页 |
| `PTE_RWUAD` | 0xD7 | 用户栈页 |
| `PTE_V` | 0x01 | 非叶子中间表项（无需 A/D） |

### 5.6 satp 布局

```
 31   30        22 21                   0
┌────┬────────────┬──────────────────────┐
│MODE│   ASID(9b) │      PPN(22b)        │
└────┴────────────┴──────────────────────┘
```

`satp_make(SV32, 0, 0x80000000)` = `(1<<31) | (0<<22) | (0x80000000>>12 & 0x3FFFFF)` = `0x80000000`。

写完 satp **必须** `sfence.vma`，否则 TLB 残留旧表项。

---

## 6. 系统调用接口

### 6.1 系统调用号（`syscall.h`）

| 名称 | 编号 | 说明 |
|------|------|------|
| `SYS_exit` | 2 | 退出并写自检结果，停机 |
| `SYS_read` | 7 | 从 fd 读 |
| `SYS_write` | 8 | 向 fd 写 |
| `SYS_report` | 9 | 写自检结果到内存，不停机（返回调用者） |

### 6.2 调用约定

```
a7 (x17) = 系统调用号
a0 (x10) = arg0 / 返回值
a1 (x11) = arg1
a2 (x12) = arg2
```

用户侧封装在 `user_syscall.S`：`sys_write`/`sys_read`/`sys_exit` 都是叶子函数，只设 a7 然后 `ecall`，无需栈帧。通用 `syscall(num,a0,a1,a2)` 需要把第一个参数（num）从 a0 移到 a7，其余参数从 a1/a2/a3 平移到 a0/a1/a2。

### 6.3 各调用语义

**SYS_write(fd, buf, len) → 写入字节数**

- `fd == 1`（stdout）：VA 转换后逐字节 `uart_putc`，返回 `len`。
- 其他 fd：返回 -1。
- **VA 转换**：用户缓冲区在 VA 0x0+（U 页，S-mode 不可直接访问）。内核用 `kernel_va = user_va + PA_USER_PROG`（0x80008000）走恒等映射访问同一物理内存。详见 §14。

**SYS_read(fd, buf, len) → 读取字节数**

- `fd == 0`（stdin）：逐字节 `uart_getc`，返回读取数。
- 其他 fd：返回 -1。

**SYS_exit(pass, total, first_fail) → 不返回**

- 写自检结果到 `PA_SELF_CHECK`（0x80007000）：
  - `sc[0] = total`
  - `sc[1] = pass`
  - `sc[2] = first_fail`
- 打印 `Calculator exited: <pass>/<total> tests passed`
- `wfi` 死循环停机

**SYS_report(pass, total, first_fail) → 无返回值（但继续执行）**

- 写自检结果到 `PA_SELF_CHECK`（0x80007000），格式与 `SYS_exit` 相同。
- **不停机**：写完内存后直接返回到 ecall 的下一条指令，U-mode 继续执行。
- 用途：自检完成后需要继续运行（如进入交互模式）时使用。

### 6.4 陷入分发（`trap.c`）

```
scause == 8  (ECALL_U)   → sepc += 4, syscall_handle(tf)
scause == 12/13/15 (PF)  → 打印 "Page fault! scause=.. stval=..", halt
scause == 3  (ebreak)    → sepc += 4 (跳过)
其他                      → 打印 "Unexpected trap: scause=.. stval=..", halt
```

---

## 7. 目录结构

```
dev/os/
├── Makefile                  两阶段构建（user → kernel 嵌入 user.bin → os.hex）
├── bin2hex.py                flat binary → $readmemh hex（含 --pad-start / --boot-jump）
├── os.ld                     内核链接脚本（ORIGIN=0x80004000, LENGTH=48K）
├── user.ld                   用户链接脚本（VA 0x0，无 MEMORY 命令）
├── README.md                 本文件
├── PLAN-os-impl.md           实现计划（历史文档）
│
├── include/                  OS 公共头
│   ├── types.h               定宽类型（uint32_t 等，freestanding）
│   ├── riscv.h               CSR 地址、PTE 位、satp/pte_make 辅助函数
│   ├── memlayout.h           物理地址常量（PA_L1_PT 等）
│   ├── syscall.h             系统调用号 + 封装声明
│   └── trap.h                trapframe_t 结构 + scause 常量
│
├── kernel/                   S/M-mode 内核
│   ├── entry.S               M-mode 入口：设 sp，call m_init
│   ├── m_init.c              M-mode 初始化：建页表、委托、mret
│   ├── m_init.h              m_init / s_mode_entry 声明
│   ├── s_main.c              S-mode 入口：stvec、FPU、banner、sret
│   ├── trap.S                陷入入口：保存 x1-x31 + CSR，call dispatch，恢复，sret
│   ├── trap.c                陷入分发：ecall→syscall, PF→halt
│   ├── syscall.c             系统调用实现（含 VA 转换）
│   ├── uart.c                内核 UART 驱动（NS16550A，轮询）
│   └── uart.h                UART 寄存器结构 + API
│
└── user/                     U-mode 用户库 + 应用
    ├── user_start.S          U-mode 入口：sp=0x9000，清 bss，call main，ecall exit
    ├── user_syscall.S        ecall 封装：syscall / sys_write / sys_read / sys_exit
    ├── user.h                用户库 API（user_printf 等）
    ├── user_printf.c         printf 实现（基于 sys_write，含 ftoa）
    ├── user_gets.c           gets 实现（基于 sys_read）
    ├── calculator.c          浮点计算器 + run_tests() 自检
    ├── atof.c                字符串→float（从 lib/ 原样复制）
    ├── ftoa.c                float→字符串（从 lib/ 原样复制）
    ├── math.c                sqrtf/fabsf（从 lib/ 原样复制）
    └── math.h                math API
```

---

## 8. 编译命令

### 8.1 工具链

```bash
# 已安装的工具链（riscv32 未装，用 rv64 + -march=rv32 等价替代）
riscv64-unknown-elf-gcc -march=rv32imaf_zicsr_zifencei -mabi=ilp32
```

### 8.2 一键编译

```bash
# 编译 OS（清理 + 全量构建 + 安装到 program_source）
make -C dev/os clean all
```

该命令依次完成：

1. **Stage 1（用户）**：编译 `user/*.S` + `user/*.c` → `build/user.elf` → `build/user.bin`（裸二进制）
2. **Stage 2（内核）**：生成 `build/user_bin_wrap.S`（`.incbin "user.bin"`）→ 汇编 → 编译 `kernel/*` → 链接 `build/os.elf` → `build/os.bin` → `build/os.hex`（$readmemh 格式）
3. **安装**：`cp build/os.hex ../program_source/app/os.hex`

### 8.3 编译产物

```
dev/os/build/user.bin      用户程序裸二进制（约 5 KB）
dev/os/build/user.elf      用户 ELF（带调试符号）
dev/os/build/os.elf        内核 ELF（含嵌入的 user.bin）
dev/os/build/os.bin        内核裸二进制（约 21 KB）
dev/os/build/os.hex        $readmemh hex（9472 行，每行 8 hex 字符）
dev/program_source/app/os.hex   安装到仿真目录的 hex
```

### 8.4 单独编译某一阶段

```bash
make -C dev/os user     # 仅编译用户程序
make -C dev/os kernel   # 仅编译内核（依赖 user.bin）
make -C dev/os install  # 仅安装 hex
make -C dev/os clean    # 清理 build/ 和已安装的 hex
```

### 8.5 验证编译

```bash
# 检查 hex 格式：每行必须正好 8 个 hex 字符
awk 'length($0) != 8 {print NR": "$0; bad++} END {print "bad lines: "bad+0}' dev/os/build/os.hex
# 期望输出：bad lines: 0

# 检查首行是 boot jump（lui t0,0x80004 → 0x80004000）
head -1 dev/os/build/os.hex
# 期望：800042b7 (lui t0,0x80004)
sed -n '2p' dev/os/build/os.hex
# 期望：00028067 (jr t0)

# 检查第 4097 行是内核 _start（auipc sp,0x0）
sed -n '4097p' dev/os/build/os.hex
# 期望：00000117
```

---

## 9. 仿真命令

### 9.1 首次仿真（创建会话）

```bash
python -m tools.vivado_cli -task os_boot -create -sim --debug trace,trap,uart_tx
```

- `-task os_boot`：对应 `tasks.yaml` 中的 `os_boot` 条目（`tb_simple_cpu_top` + `blhex: boot/bootloader_phase1.hex` + `phex: app/os.hex` + `LINUX_BOOT: TRUE`）
- `-create`：创建新的 Vivado 会话
- `-sim`：运行仿真
- `--debug trace,trap,uart_tx`：启用指令追踪 + 异常追踪 + UART TX 捕获

### 9.2 复用会话重新仿真

```bash
python -m tools.vivado_cli -task os_boot -sim --debug trace,trap,uart_tx
```

不重建工程，直接在已有会话上重新跑仿真。

### 9.3 修改代码后增量刷新

```bash
# 仅刷新 COE/hex 层（改了 OS 代码后用这个，秒级）
python -m tools.vivado_cli -task os_boot -refresh --layers coe

# 全量刷新（改了 RTL 后用这个）
python -m tools.vivado_cli -task os_boot -refresh
```

典型迭代循环：

```bash
make -C dev/os clean all                                    # 重新编译
python -m tools.vivado_cli -task os_boot -refresh --layers coe   # 刷新 hex
python -m tools.vivado_cli -task os_boot -sim --debug trap,uart_tx  # 仿真
```

### 9.4 仿真时长

`os_boot` 任务在 `LINUX_BOOT=TRUE` 模式下，TB 硬编码等待 200M 周期。OS 实际在约 11.5 ms 仿真时间后 `wfi` 停机，剩余时间都是 wfi。仿真实际墙钟时间取决于主机性能，通常数分钟。

---

## 10. 预期输出

### 10.1 UART TX 输出

仿真结束后查看 `.omo/evidence/task-9-uart-tx.log`（或 `--debug uart_tx` 生成的日志）：

```
SimpleOS booted
1+2 = 3.000000
3*4 = 12.000000
10-3 = 7.000000
8/2 = 4.000000
sqrt(4) = 2.000000
Tests: 5/5 passed

=== RISC-V FPU Calculator ===
Supports: + - * / () sqrt() neg()
Type 'exit' to quit.

>
```

逐行来源：

| 行 | 产生者 | 系统调用 |
|----|--------|----------|
| `SimpleOS booted` | `s_main.c` 的 `uart_puts` | 直接 MMIO（内核态） |
| `1+2 = 3.000000` ... `sqrt(4) = 2.000000` | `calculator.c` 的 `run_tests` | `SYS_write` via `user_printf` |
| `Tests: 5/5 passed` | `calculator.c` 的 `run_tests` | `SYS_write` |
| `=== RISC-V FPU Calculator ===` ... `Type 'exit' to quit.` | `calculator.c` 的 `main` | `SYS_write` via `user_printf` |
| `> ` | `calculator.c` 的 `main` 交互循环 | `SYS_write`，之后阻塞在 `SYS_read` 等待输入 |

### 10.2 陷入追踪

`--debug trap` 日志共 149 个事件（取自 `.omo/evidence/task-9-trap-trace.log`）：

```
#1   MRET    PC=0x80004324  priv=3→1   (M→S via mret)
#2   MRET    PC=0x80004380  priv=1→0   (S→U via sret)
#3   TRAP_IN PC=0x00000054  priv=0→1   (U→S ecall, sys_write)
#4   MRET    PC=0x80004160  priv=1→0   (S→U sret)
...  (ecall/sret 交替，中间穿插 sys_write 调用)
#149 TRAP_IN PC=0x0000006c  priv=0→1   (sys_report ecall, sret 返回 U-mode)
```

> 注意：自检阶段约 149 个 trap 事件。进入交互模式后，程序阻塞在 `SYS_read`（S-mode `uart_getc` 轮询），仿真无 UART 输入，直到 200M 周期超时 `$finish`。

### 10.3 自检结果

仿真结束后 TB 读取 `PA_SELF_CHECK`（0x80007000）：

| 偏移 | 字段 | 期望值 |
|------|------|--------|
| +0 | total_count | 5 |
| +1 | pass_count | 5 |
| +2 | first_fail_id | 0 |

寄存器自检（若 TB 检查）：

| 寄存器 | 含义 | 期望值 |
|--------|------|--------|
| x28 | pass_count | 5 |
| x29 | total_count | 5 |
| x30 | first_fail_id | 0 |

---

## 11. 自检协议

SimpleOS 沿用项目的自检协议，但通过 `SYS_report` 系统调用把结果写入内存，而非直接写寄存器。`SYS_report` 写完内存后返回调用者继续执行（不停机），`SYS_exit` 仅在用户输入 `exit` 命令时调用，用于停机。

### 11.1 测试用例

`calculator.c:run_tests()` 跑 5 项浮点测试：

| ID | 表达式 | 期望 | 容差 |
|----|--------|------|------|
| 1 | `1+2` | 3.0 | 0.0001 |
| 2 | `3*4` | 12.0 | 0.0001 |
| 3 | `10-3` | 7.0 | 0.0001 |
| 4 | `8/2` | 4.0 | 0.0001 |
| 5 | `sqrt(4)` | 2.0 | 0.0001 |

每项测试调用 `eval_str(expr)` → `parse_expr()`（递归下降解析器），结果用 `fabsf(result - expected) < 0.0001f` 判定。

### 11.2 结果传递

```c
// calculator.c
sys_report(pass, total, first_fail);  // a0=pass, a1=total, a2=first_fail

// syscall.c (SYS_report handler)
volatile uint32_t *sc = (volatile uint32_t *)PA_SELF_CHECK;  // 0x80007000
sc[0] = total_count;
sc[1] = pass_count;
sc[2] = first_fail_id;
// 写完即返回，U-mode 继续执行（进入交互模式）
```

`SYS_report` 与 `SYS_exit` 的区别：`SYS_report` 写完内存后返回调用者继续执行，`SYS_exit` 写完后 `wfi` 停机。交互模式下用户输入 `exit` 时才调用 `SYS_exit`。

### 11.3 TB 校验

仿真结束后 TB 检查：

- 内存 `0x80007000` 处的 3 个字（total/pass/first_fail）
- （可选）寄存器 x28/x29/x30

全部通过的条件：`pass == total && first_fail == 0`。

---

## 12. 调试技巧

### 12.1 启动即卡死（PC=0x80000000，illegal instruction）

**原因**：bootloader 跳到 0x80000000，但内核链接在 0x80004000，中间是零填充。执行 `0x00000000`（全零）= illegal instruction。

**排查**：看 trap 日志，mcause=2（illegal instruction），PC=0x80000000。

**修复**：确认 `bin2hex.py --boot-jump 0x80004000` 生效。hex 文件第 1 行应是 `lui t0,0x80004` 的编码，第 2 行是 `jr t0`。

### 12.2 mret 后立即页错误（mcause=0，exe_misalign）

**原因**：`pte_make()` 公式错误，PTW 解析出错误 PA，取指拿到乱码指令。

**排查**：看 trap 日志，mcause=0（RTL 里 exe_exception_cause 硬编码 0，实际是 exe_misalign）。检查 PTE 值：`pte_make(0x80004000, 0xCF)` 应得 `0x200010CF`，不是 `0x800040CF`。

**修复**：`pte_make` 必须用 `((pa >> 12) << 10) | flags`，不是 `((pa >> 10) << 10) | flags`。

### 12.3 sys_write 触发 load page fault（scause=13）

**原因**：内核页表里用户页带了 PTE_U 位，S-mode 访问 U 页（无 SUM）触发页错误。

**排查**：trap 日志显示 `Page fault! scause=0x0000000D stval=0x80010F5F`。stval 落在用户区。

**修复**：内核 L0 页表里用户镜像和用户栈的 PTE **不要**带 U 位。用户访问走 L0_user（带 U），内核访问走 L0_kernel（不带 U），同一物理页，不同 PTE。

### 12.4 sys_exit 显示 "5/36703 tests passed"

**原因**：`register int a1 asm("a1") = total` 在函数调用（`sys_exit(pass)`）后被覆盖，a1 变成垃圾值。

**修复**：`sys_exit` 改成 3 参数：`void sys_exit(int pass, int total, int first_fail)`。C ABI 自然把 a0/a1/a2 放好，`ecall` 不破坏它们。

### 12.5 FPU 指令触发 illegal instruction

**原因**：`sstatus.FS == 0`（Off），任何 FPU 指令都陷阱。

**排查**：trap 日志显示 scause=2（illegal instruction），PC 指向 `fsqrt.s` 或 `fmv.x.w`。

**修复**：`s_main.c` 里 `sstatus.FS = 01`（`val |= (1U << 13)`）。M-mode 也要设 `mstatus.FS = 01`（`m_init.c` 已做）。

### 12.6 ecall 后无限循环

**原因**：`trap_dispatch` 没有把 `sepc += 4`，sret 回到 ecall 本身，再次陷入。

**排查**：trap 日志显示同一个 PC 反复 TRAP_IN。

**修复**：确认 `trap.c` 里 `CAUSE_ECALL_U` 分支有 `tf->sepc += 4`（ecall 是 4 字节，无 C 扩展）。

### 12.7 通用调试命令

```bash
# 启用全部调试
python -m tools.vivado_cli -task os_boot -sim --debug all

# 解析指令追踪
python -m tools.trace_analyzer parse .omo/evidence/os_boot/instr_trace.log

# 定位失败点
python -m tools.trace_analyzer find-fail .omo/evidence/os_boot/instr_trace.log

# 与 Spike 对比
python -m tools.trace_analyzer diff instr_trace.log spike.log
```

---

## 13. 设计约束

SimpleOS 是最小化演示，**不包含**：

| 功能 | 有无 | 说明 |
|------|------|------|
| 进程调度器 | 无 | 单进程，无 fork/exec |
| 文件系统 | 无 | 无 VFS、无 inode、无 open/read/write 文件 |
| IPC | 无 | 无 pipe、shm、msg |
| 中断 | 无 | 全程轮询，`sstatus.SIE = 0`，无 PLIC 驱动 |
| 多核 | 无 | 单核单线程 |
| 用户态隔离 | 弱 | 单页表，内核可访问用户内存（通过 VA 转换） |
| 动态加载 | 无 | user.bin 在编译期 `.incbin` 嵌入内核镜像 |
| 时钟 | 无 | 无 mtime 驱动，无调度 tick |
| 信号 | 无 | 无 signal/kill |
| 内存分配 | 无 | 无 malloc，所有内存静态分配 |

这些限制是刻意的：SimpleOS 的目标是验证 CPU 的特权级 + 分页 + 陷入机制，不是做一个能用的 OS。

---

## 14. 关键设计决策

### 14.1 单页表（不切换 satp）

**决策**：S-mode 和 U-mode 全程共用同一张页表，陷入/返回时不保存/恢复 `satp`。

**原因**：
- 简化 trap handler：无需保存/恢复 satp，少 2 条 CSR 指令。
- 避免 TLB 刷新：切换 satp 需要 `sfence.vma`，单页表不需要。
- 单进程场景下没有隔离需求，一张表覆盖所有 VA 空间即可。

**代价**：用户 VA 空间被限制在 L1[0] 指向的 4 MB 内（实际只用 36 KB）。多进程需要每进程一张表 + satp 切换。

### 14.2 VA 转换代替 SUM

**决策**：S-mode 访问用户内存时，用 `kernel_va = user_va + PA_USER_PROG` 走内核恒等映射，而不是置 `sstatus.SUM = 1`。

**原因**：
- SUM 位允许 S-mode 直接访问 U 页，但语义混乱（容易意外访问用户数据）。
- VA 转换显式、可控：内核必须主动计算地址才能访问用户内存。
- 内核 L0 页表里用户页不带 U 位，S-mode 走恒等映射访问同一物理页，干净利落。

**实现**（`syscall.c`）：
```c
const char *kbuf = (const char *)(uintptr_t)(buf_va + PA_USER_PROG);
// 用户 VA 0x1234 → 内核 VA 0x80009234 → PA 0x80009234（恒等映射）
```

### 14.3 A/D 位预置

**决策**：建表时把所有叶子 PTE 的 A=1、D=1 预置好。

**原因**：自研 CPU 的 PTW 不实现 A/D 位自动置位。若 PTE.A=0 或 PTE.D=0，PTW 触发页错误。标准 RISC-V 要求硬件在首次访问时自动置 A/D，但我们的硬件没做，软件补偿。

**代价**：无法用 A/D 位做页面置换（但 SimpleOS 没有换页，无所谓）。

### 14.4 .incbin 嵌入用户镜像

**决策**：用户程序先编译成 `user.bin`（裸二进制），再通过 `.incbin` 嵌入内核 ELF 的 `.user_bin` 段（VMA=0x80008000）。

**原因**：
- 单一 hex 文件：最终只产出一个 `os.hex`，包含内核 + 用户，TB 只需加载一个文件。
- 无需文件系统：用户镜像在编译期固化进内核，运行时无需加载器。
- 链接器限制：`ld` 不支持 SECTIONS 内的 `.incbin`，所以用 `user_bin_wrap.S` 包装。

**实现**（Makefile）：
```makefile
$(BUILD_DIR)/user_bin_wrap.S: $(USER_BIN)
	@printf '.section .user_bin, "a", "progbits"\n\t.incbin "user.bin"\n' > $@
```

> `"a"` 标志让段可分配（ALLOC），否则 `objcopy -O binary` 会跳过它。

### 14.5 boot-jump 填充

**决策**：hex 文件首字放一条 `lui t0,0x80004; jr t0` 跳转指令，跳到 0x80004000。

**原因**：phase-1 bootloader 跳到 SRAM 基址 0x80000000，但内核链接在 0x80004000。中间 16 KB 是零填充（运行时被页表覆盖）。不填跳转指令的话，CPU 执行全零（illegal instruction）立即陷阱。

**实现**（`bin2hex.py --boot-jump 0x80004000`）。

### 14.6 内核页表用户页不带 U 位

**决策**：内核 L0 页表里，用户镜像和用户栈的 PTE **不带** PTE_U。

**原因**：S-mode 访问带 U 位的页会触发页错误（除非 SUM=1）。内核需要通过 VA 转换访问用户内存（§14.2），所以内核页表里的用户页必须不带 U。用户访问走另一张 L0_user（带 U），两张表映射同一物理页，权限不同。

这是 Task 9 调试中发现的第 3 个 bug，详见 `learnings.md`。

---

## 15. FPGA 上板

SimpleOS 已具备 FPGA 上板运行能力。上板流程：

### 15.1 前提条件

- FPGA 已烧录 bitstream（`python3 -m tools.vivado_cli -task fpga -create -bitstream`）
- UART 串口终端已连接（波特率 230400，8N1）
- `dev/os/build/os.bin` 已编译

### 15.2 加载流程

1. FPGA 上电后，bootloader（`bootloader.coe`）运行：
   - 等待 DDR3 MIG 校准完成
   - DDR3 自检（写 0xDEADBEEF + 0xCAFEBABE 回读验证）
   - 初始化 UART（230400 baud，8N1，FIFO）
   - 等待 UART 接收程序镜像
2. 使用 `tools/uart_load.py` 发送 `os.bin`：
   ```bash
   python3 tools/uart_load.py --port /dev/ttyUSB0 --file dev/os/build/os.bin \
       --load-addr 0x80000000 --entry-addr 0x80000000
   ```
3. Bootloader 接收完毕后 `fence.i` + 跳转到 0x80000000
4. SimpleOS 启动：M-mode 建页表 → S-mode 初始化 → U-mode 计算器

### 15.3 交互使用

启动后终端显示：

```
SimpleOS booted
1+2 = 3.000000
3*4 = 12.000000
10-3 = 7.000000
8/2 = 4.000000
sqrt(4) = 2.000000
Tests: 5/5 passed

=== RISC-V FPU Calculator ===
Supports: + - * / () sqrt() neg()
Type 'exit' to quit.

> 
```

在 `> ` 提示符后输入表达式（如 `(1+2)*3.5`），回车后显示结果。输入 `exit` 退出。

### 15.4 UART 波特率

UART 接在 `sys_clk`（100MHz）域，分频系数 = 100MHz / (16 × 230400) ≈ 27。内核 `s_main.c` 在启动时调用 `uart_init(UART_BAUD_230400)` 初始化 UART。

---

## 附：快速验证清单

```bash
# 1. 编译
make -C dev/os clean all
# 期望：[INSTALL] ../program_source/app/os.hex

# 2. 仿真
python -m tools.vivado_cli -task os_boot -create -sim --debug trap,uart_tx

# 3. 检查 UART 输出
cat .omo/evidence/task-9-uart-tx.log
# 期望：5 项测试结果 + "Tests: 5/5 passed" + 交互模式 banner + "> " 提示符

# 4. 检查自检内存
# TB 自动检查 0x80007000 处的 total/pass/first_fail
```
