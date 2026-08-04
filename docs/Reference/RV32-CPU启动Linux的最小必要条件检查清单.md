# RISC-V RV32 CPU 启动 Linux 的最小必要条件检查报告

## 1. 检查目标

本报告用于检查当前自研 RV32 CPU / SoC 是否已经具备启动 Linux 的最低硬件与平台条件。

这里的“启动 Linux”分为两个目标：

1. **最低目标 A：Linux kernel 能启动并打印日志**

   * 能从 OpenSBI 跳入 Linux kernel。
   * 能看到 `Linux version ...`、early console、内存初始化等日志。
   * 即使最后因为没有 rootfs 而 panic，也算完成最低 kernel 启动验证。

2. **最低目标 B：Linux 能进入 BusyBox shell**

   * kernel 能完成初始化。
   * 能挂载 initramfs。
   * 能执行 `/init`。
   * 能进入 `/bin/sh`。

本报告优先检查 CPU/SoC 设计本身是否达标。BusyBox、rootfs、应用程序属于后续软件阶段，不是 CPU 最小硬件能力的核心检查项。

---

## 2. 总体判定原则

只要下面任意“硬性必需项”不达标，就不建议直接进入 Linux 移植阶段。

硬性必需项包括：

* RV32IMA_Zicsr_Zifencei 指令集能力
* M/S/U 特权级
* Sv32 MMU
* 异常、中断、委托机制
* 可用 timer
* 可用 UART 或 SBI console
* 正确的物理内存与 MMIO 区分
* 页表访问与 cache 一致性
* 可用的 Device Tree
* 正确的 boot protocol

检查结果建议使用以下标记：

| 标记  | 含义                 |
| --- | ------------------ |
| ✅   | 已达标，有测试证据          |
| ⚠️  | 设计上可能达标，但缺少测试或存在风险 |
| ❌   | 未达标，Linux 暂时无法可靠启动 |
| N/A | 当前阶段不需要            |

---

# 3. CPU 指令集最低要求

| 项目           | 判断是否达标的条件                                                                                                 | 备注信息                                              |
| ------------ | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| RV32I 基础整数指令 | 所有 RV32I 指令功能正确，通过基础指令测试                                                                                  | Linux kernel、OpenSBI、编译器生成代码都依赖 RV32I             |
| M 扩展         | `mul/div/rem` 等 RV32M 指令正确实现                                                                              | 理论上可用软件除法，但实际移植中建议必须支持 RV32M                      |
| A 扩展         | 支持 `lr.w/sc.w` 和所有 RV32 AMO 指令                                                                            | **硬性必需项**。Linux 内核原子操作、锁、调度、futex 都依赖原子语义         |
| AMO 指令完整性    | 至少支持 `amoswap.w`、`amoadd.w`、`amoxor.w`、`amoand.w`、`amoor.w`、`amomin.w`、`amomax.w`、`amominu.w`、`amomaxu.w` | 不能只实现部分 AMO，否则 kernel 运行中可能触发 illegal instruction |
| LR/SC 语义     | `lr.w` 建立 reservation，`sc.w` 根据 reservation 成功或失败返回 0/1                                                   | 单核可以简化实现，但必须满足软件锁的基本语义                            |
| `aq/rl` 位    | AMO/LR/SC 的 `aq`、`rl` 位不能被当成非法指令                                                                          | 单核强顺序系统中可以简化处理，但必须接受这些编码                          |
| Zicsr        | CSR 读写指令正确实现                                                                                              | `csrrw/csrrs/csrrc` 及立即数版本必须正确                    |
| Zifencei     | `fence.i` 正确实现                                                                                            | Linux 或 bootloader 修改指令内存后需要刷新 I-cache            |
| `fence`      | 至少实现为有效的内存顺序屏障                                                                                            | 单核可简化，但不能 illegal                                 |
| `wfi`        | 至少实现为 NOP                                                                                                 | Linux idle 和 OpenSBI 可能执行 `wfi`，不能触发非法指令          |
| 非对齐访问        | 要么硬件支持，要么产生精确异常                                                                                           | Linux 可以处理部分 misaligned trap，但异常原因和地址必须准确         |
| `misa`       | 正确声明已实现 ISA，例如 `RV32IMA_Zicsr_Zifencei`，并正确反映 S/U 特权能力                                                    | `misa` 与真实硬件不一致会误导 OpenSBI/Linux                  |
| 可选扩展探测   | 除 C/F/D/V 外，还需确认 Zicbom/Zicboz/Zba/Zbb/Zbs/Zicond/Zihintpause/Zawrs/Zacas 等未被 kernel 生成代码使用或 DTB 宣称 | 之前 `wrs.nto` 就是此类问题。不能假设"不实现就没事"，未实现扩展的指令必须产生 illegal instruction |

最低建议 ISA 字符串：

```text
rv32ima_zicsr_zifencei
```

不要求：

```text
F / D / C / V
```

其中：

* `C` 压缩指令不是启动 Linux 的硬性要求。
* `F/D` 浮点不是硬性要求，可以先关闭 FPU。
* `V` 向量扩展完全不需要。

---

# 4. 特权级最低要求

| 项目                  | 判断是否达标的条件                             | 备注信息                                                |
| ------------------- | ------------------------------------- | --------------------------------------------------- |
| M-mode              | 支持 Machine mode，复位后进入 M-mode          | OpenSBI 通常运行在 M-mode                                |
| S-mode              | 支持 Supervisor mode                    | Linux kernel 通常运行在 S-mode                           |
| U-mode              | 支持 User mode                          | BusyBox、shell、用户程序运行在 U-mode                        |
| `mret`              | 从 M-mode 正确返回到目标特权级                   | OpenSBI 进入 Linux 时依赖                                |
| `sret`              | 从 S-mode 正确返回到 S/U-mode               | Linux 系统调用、异常返回依赖                                   |
| `ecall`             | U/S/M mode 下 `ecall` 能产生正确 cause      | 用户态 syscall、SBI call 都依赖                            |
| `ebreak`            | 能产生正确断点异常                             | 调试功能需要，最低启动可不重点依赖                                   |
| 特权级非法访问检查           | 低特权级访问高特权 CSR 时产生 illegal instruction | Linux 的隔离能力依赖                                       |
| `mstatus`           | `MPP/MPIE/MIE` 等字段行为正确                | M-mode trap/return 依赖                               |
| `sstatus`           | `SPP/SPIE/SIE/SUM/MXR` 等字段行为正确        | Linux 异常返回、用户态访问、copy_to_user/copy_from_user 依赖     |
| `medeleg`           | 能把指定同步异常委托给 S-mode                    | Linux 需要在 S-mode 处理 page fault、syscall 等异常          |
| `mideleg`           | 能把指定中断委托给 S-mode                      | Linux 需要处理 S-mode timer/external/software interrupt |
| `mtvec/stvec`       | 支持 trap vector 设置                     | Direct 模式够用，Vectored 模式不是最低要求                       |
| `mepc/sepc`         | trap 时保存正确 PC，return 时恢复正确 PC         | 异常和中断返回必须依赖                                         |
| `mcause/scause`     | trap cause 编码正确                       | Linux 根据 cause 分发异常处理                               |
| `mtval/stval`       | page fault、非法指令、访问异常时提供有效辅助信息         | Linux page fault 处理和调试依赖                            |
| `mscratch/sscratch` | CSR 可读写，trap entry 可使用                | OpenSBI/Linux trap handler 常用                       |
| `xRET` 语义    | `mret/sret` 必须精确更新 `xIE/xPIE/xPP`：`xIE←xPIE`, `xPIE←1`, `priv←xPP` | 不是只改 PC。错误会导致返回后中断永远不开、特权级错误、递归 trap |
| `sepc/mepc` 保存 | 同步异常保存当前指令 PC；中断保存被打断指令 PC；`ecall` 不自动 +4 | Linux trap handler 自己决定是否递增 `sepc`。硬件提前 +4 会破坏 syscall/异常返回 |
| `mstatus.TVM` | TVM=1 时 S-mode `sfence.vma` 或写 `satp` 产生 illegal instruction | 控制 S-mode MMU 操作权限，Linux 期望 TVM=0 |
| `mstatus.TSR` | TSR=1 时 S-mode `sret` 产生 illegal instruction | Linux 期望 TSR=0，否则无法从 trap 返回 |
| `mstatus.TW`  | TW=1 时 S-mode `wfi` 产生 illegal instruction | Linux idle 用 `wfi`，期望 TW=0 |
| CSR 探测行为   | 未实现 CSR 的访问要么产生 illegal instruction 被 OpenSBI/Linux fixup 捕获，要么不要让代码访问到 | OpenSBI probe PMP/可选 CSR；Linux 也可能 probe。不能假设"不实现就没事" |

最低要求：

```text
M-mode + S-mode + U-mode
```

只有 M-mode 或只有 M/U mode 不足以运行标准 MMU Linux。

---

# 5. MMU / Sv32 最低要求

| 项目           | 判断是否达标的条件                                     | 备注信息                                   |
| ------------ | --------------------------------------------- | -------------------------------------- |
| Sv32         | 支持 RV32 的 Sv32 两级页表                           | 标准 RV32 Linux MMU 模式需要                 |
| `satp`       | `MODE/ASID/PPN` 字段符合 Sv32 定义                  | Linux 通过写 `satp` 开启分页                  |
| MMU 开关       | `satp.MODE=0` 时地址翻译关闭，`satp.MODE=Sv32` 时启用翻译  | 进入 Linux 前要求 `satp=0`                  |
| 虚拟地址翻译       | VA → VPN[1:0] → 页表 → PA 流程正确                  | 必须通过多级页表测试                             |
| 4KB page     | 支持普通 4KB 页                                    | Linux 基础内存管理依赖                         |
| megapage     | 建议支持 4MB megapage                             | Linux 早期映射常用大页；若不支持可能需要修改 kernel 配置或代码 |
| PTE 格式       | `V/R/W/X/U/G/A/D/RSW/PPN` 字段解析正确              | 位定义不能自定义                               |
| leaf PTE 判断  | 正确区分 leaf PTE 和 non-leaf PTE                  | 页表遍历核心逻辑                               |
| 权限检查         | 根据当前特权级、PTE 权限、`SUM/MXR` 做访问检查                | Linux 用户态隔离依赖                          |
| page fault   | 指令、读、写 page fault cause 分别正确                  | cause 12/13/15 必须准确                    |
| `stval`      | page fault 时保存 fault virtual address          | Linux 缺页处理依赖                           |
| A/D 位处理      | 硬件自动设置 A/D 位，或在 A/D 位不满足时产生 page fault 交给软件处理 | 二选一即可，但行为必须一致                          |
| `sfence.vma` | 能刷新 TLB，并保证后续地址翻译看到最新页表                       | 只清 TLB 不一定够，还要考虑页表与 dcache 一致性         |
| TLB          | 命中、缺失、刷新、权限缓存逻辑正确                             | TLB 错误会导致随机 page fault 或错误访问           |
| ASID         | 可以先简单实现 ASID=0                                | 单进程/早期启动可简化，但不能破坏 `satp` 格式            |
| MMIO 翻译策略    | 先完成虚拟地址到物理地址翻译，再根据物理地址判断 RAM/MMIO             | **不能用虚拟地址最高位判断 MMIO**                  |

特别注意：

```text
错误做法：
  if vaddr[31] == 0:
      当作 MMIO
  else:
      当作 DDR

正确做法：
  vaddr → MMU → paddr
  if paddr in DDR:
      走内存/cache
  else if paddr in MMIO:
      走外设/bypass
```

Linux 开启虚拟内存后，用户程序通常使用低虚拟地址。低虚拟地址不等于 MMIO。

---

# 6. Cache / 内存一致性最低要求

| 项目                  | 判断是否达标的条件                                                             | 备注信息                                                 |
| ------------------- | --------------------------------------------------------------------- | ---------------------------------------------------- |
| I-cache             | 取指正确，`fence.i` 后能看到最新指令内容                                             | kernel 解压、自修改/加载代码场景需要                               |
| D-cache             | load/store 功能正确                                                       | Linux 普通内存访问依赖                                       |
| cacheable 区域        | DDR 可 cache                                                           | 允许先做简单 cache 策略                                      |
| uncacheable/MMIO 区域 | MMIO 不能被 D-cache 缓存                                                   | 外设寄存器必须每次真实访问                                        |
| MMIO 判断             | 基于物理地址/PMA 判断是否 cacheable                                             | 不能基于虚拟地址判断                                           |
| 写回策略                | 如果 D-cache 是 write-back，必须处理页表、DMA、外设一致性问题                            | Linux 下风险很大                                          |
| 页表一致性               | CPU 写 PTE 后，PTW 必须能看到最新 PTE                                           | **硬性必需项**                                            |
| PTW 访问路径            | PTW 走 coherent dcache，或 `sfence.vma` 时 writeback/flush 相关 dcache line | 如果 PTW 绕过 dcache，而 dcache 是写回，会读到旧页表                 |
| A/D 位写回             | PTW/硬件写 A/D 位时不能和 dcache 中的 PTE 副本冲突                                  | 否则会出现页表位丢失                                           |
| `sfence.vma` 语义     | 至少保证 TLB 和页表内存视图同步                                                    | 课程项目可采用粗暴方案：`sfence.vma` 时 flush/writeback 整个 dcache |
| `fence.i` 语义        | 数据写入指令内存后，后续取指能看到新指令                                                  | 最简单方案：`fence.i` 时 flush I-cache                      |
| 总线顺序                | 对 MMIO 访问保持顺序，不乱序合并                                                   | UART/PLIC/CLINT 寄存器访问依赖                              |

最低推荐实现策略：

```text
1. DDR: cacheable
2. MMIO: uncacheable
3. MMIO 判断基于物理地址
4. sfence.vma: flush TLB + writeback/flush D-cache
5. fence.i: flush I-cache
```

这不是性能最优方案，但最容易保证 Linux 能先跑起来。

---

# 7. 异常与中断最低要求

| 项目           | 判断是否达标的条件                                                                        | 备注信息                                 |
| ------------ | -------------------------------------------------------------------------------- | ------------------------------------ |
| 同步异常         | illegal instruction、ecall、breakpoint、misaligned、access fault、page fault cause 正确 | Linux trap handler 依赖                |
| 异常优先级        | 多个异常同时发生时优先级合理                                                                   | 不必一开始完全优化，但不能明显错误                    |
| 中断入口         | 中断发生时保存正确 PC 和 cause                                                             | 定时器、外设中断依赖                           |
| 全局中断使能       | `mstatus.MIE`、`sstatus.SIE` 行为正确                                                 | 中断开关依赖                               |
| 局部中断使能       | `mie/sie` 对应 bit 行为正确                                                            | timer/external/software interrupt 依赖 |
| pending 位    | `mip/sip` 能反映 pending 中断                                                         | Linux 判断中断来源依赖                       |
| 中断委托         | `mideleg` 能把 S-mode 需要的中断委托到 S-mode                                              | Linux 通常不直接处理 M-mode 中断              |
| 异常委托         | `medeleg` 能把 page fault、ecall from U、breakpoint 等委托给 S-mode                      | Linux 必须处理这些异常                       |
| ecall 委托规则    | U-mode ecall (cause 8) 委托给 S-mode；S-mode ecall (cause 9) **不得**委托，必须进 M-mode/OpenSBI | Linux 发 SBI call 是 S-mode `ecall`，若 `medeleg[9]` 错误置位，SBI call 会进 Linux 自己的 trap，极易卡死 |
| 嵌套/屏蔽        | trap 进入时正确更新 IE/PIE 字段                                                           | 异常返回正确性依赖                            |
| precise trap | 异常 PC 指向正确指令                                                                     | page fault、syscall、非法指令处理依赖          |
| `sie/sip` 视图 | `sie/sip` 不能是独立假寄存器，必须是 S-mode 对 `mie/mip` 对应位的视图 | Linux 写 `sie.STIE/SEIE` 后，硬件中断判定必须真的生效 |

必须重点测试的 cause：

```text
Instruction address misaligned
Instruction access fault
Illegal instruction
Breakpoint
Load address misaligned
Load access fault
Store/AMO address misaligned
Store/AMO access fault
Environment call from U-mode
Environment call from S-mode
Instruction page fault
Load page fault
Store/AMO page fault
Supervisor software interrupt
Supervisor timer interrupt
Supervisor external interrupt
Machine timer interrupt
Machine external interrupt
```

---

# 8. Timer / CLINT / Counter 最低要求

| 项目                     | 判断是否达标的条件                                       | 备注信息                                                |
| ---------------------- | ----------------------------------------------- | --------------------------------------------------- |
| `mtime`                | 提供单调递增的 64-bit 计时器                              | OpenSBI timer、Linux clocksource 依赖                  |
| `mtimecmp`             | 写入后能在指定时间触发 timer interrupt                     | Linux 调度器依赖周期性/单次 timer event                       |
| timer 频率               | 固定、可知，并在 Device Tree 中正确描述                      | `timebase-frequency` 必须准确                           |
| MTIP                   | `mtime >= mtimecmp` 时产生 Machine timer interrupt | OpenSBI 通常先接收 MTIP                                  |
| STIP                   | Linux 能收到 Supervisor timer interrupt            | OpenSBI 需要能把 timer event 转化为 S-mode timer interrupt |
| STIP 注入              | M-mode 必须能写 `mip.STIP`，S-mode 必须能通过 `sip.STIP` 看到 pending | OpenSBI 传统 timer 路径依赖 M-mode 注入 S-mode timer interrupt。只检查 `mideleg[5]` 不够 |
| STIP 清除              | STIP 必须能被 OpenSBI 或硬件正确清除                      | 否则会 timer interrupt storm。表现：`scause=0x80000005` 快速增长，`sepc` 基本不动 |
| `time/timeh` CSR       | `rdtime/rdtimeh` 可读，反映 `mtime`                  | Linux clocksource 常直接读 time CSR，只实现 MMIO `mtime` 不够 |
| `cycle/cycleh` CSR     | 可读，单调递增                                         | 非绝对硬性，但建议实现                                         |
| `instret/instreth` CSR | 可读或至少有合理行为                                      | 非绝对硬性，但建议实现                                         |
| `mcounteren`           | M-mode 可允许 S-mode 读取 time/cycle/instret，`mcounteren.TM` 必须置位 | Linux S-mode 读 `rdtime` 需要 `mcounteren.TM=1`，否则产生 illegal instruction |
| `scounteren`           | S-mode 可允许 U-mode 读取 counter                    | 用户态性能计数/时间读取需要                                      |
| 64-bit `mtimecmp` 写入  | RV32 下 `mtimecmp` 的两个 32-bit 写入顺序不能产生永久 MTIP 或永久不触发 | OpenSBI 写 64-bit `mtimecmp` 时通常拆成高低 32 位。实现不严谨会导致 timer storm 或 timer 永远不来 |
| SBI set_timer          | OpenSBI 调用平台 timer 驱动后，下一次 timer interrupt 正常触发 | Linux 不直接写 `mtimecmp`，通常通过 SBI                      |

最小测试建议：

```text
1. M-mode 设置 mtimecmp，确认 MTIP 触发。
2. OpenSBI 或自写 M-mode firmware 设置下一次 timer。
3. 委托/注入 S-mode timer interrupt。
4. S-mode 开启 sie.STIE 和 sstatus.SIE。
5. 确认进入 stvec，并且 scause 为 supervisor timer interrupt。
```

如果 S-mode timer interrupt 不可用，Linux 可能能打印早期日志，但调度器无法正常工作。

---

# 9. PLIC / 外部中断最低要求

| 项目             | 判断是否达标的条件                              | 备注信息                   |
| -------------- | -------------------------------------- | ---------------------- |
| 外部中断控制器        | 至少能把 UART 等外设中断送到 CPU                  | 早期只用轮询 UART 时可暂时不依赖    |
| MEIP           | Machine external interrupt 可触发         | OpenSBI/M-mode 可能使用    |
| SEIP           | Supervisor external interrupt 可触发或可被委托 | Linux 外设驱动依赖           |
| priority       | 中断优先级寄存器可工作                            | 简化实现可以所有优先级固定          |
| pending        | pending 状态可读                           | Linux PLIC driver 依赖   |
| enable         | 每个中断源可 enable/disable                  | Linux PLIC driver 依赖   |
| threshold      | threshold 机制可工作或简化但兼容                  | PLIC 标准驱动会访问           |
| claim/complete | claim 返回中断号，complete 正确清除/结束中断         | Linux PLIC driver 必须依赖 |
| source 0      | claim 无中断时必须返回 0，source ID 0 保留              | Linux PLIC driver 依赖此语义 |
| context 布局   | M/S context 布局、enable/threshold/claim/complete 偏移必须与 DTB 一致 | context 错一个，Linux 可能 enable 了错误 context |
| level IRQ 语义 | UART 这类 level interrupt 需要设备条件清除后 pending 才消失 | complete 本身不应无条件清 pending。否则可能丢中断或中断风暴 |
| Device Tree 描述 | PLIC 地址、中断源数量、interrupt-parent 正确      | Linux 需要通过 DTB 识别 PLIC |

第一阶段可以暂时不启用复杂外设中断，但如果要使用标准 Linux PLIC driver，就必须兼容 PLIC 寄存器模型。

---

# 10. UART / Console 最低要求

| 项目            | 判断是否达标的条件                                   | 备注信息                             |
| ------------- | ------------------------------------------- | -------------------------------- |
| UART TX       | 能稳定输出字符                                     | 最小调试能力                           |
| UART RX       | 能接收输入字符                                     | 进入 shell 后需要                     |
| 波特率           | 与终端一致，例如 115200                             | Device Tree 和 bootargs 需要一致      |
| MMIO 地址       | UART 寄存器物理地址固定                              | Device Tree 需要描述                 |
| Linux 驱动兼容性   | 最好兼容 `ns16550a` / `uart8250`                | 这样不需要自己写 Linux driver            |
| 8250 寄存器精确兼容 | IER/IIR/FCR/LCR/LSR/DLL/DLM/MCR/MSR 语义必须正确，THRE/TEMT/DR 位精确 | earlycon 只需 TX，正式 8250 driver 会访问全部寄存器。console handoff 后高度相关 |
| early console | 支持 `earlycon=sbi` 或 `earlycon=uart8250,...` | 没有 early console 时 debug 难度很高    |
| SBI console   | OpenSBI 能通过 UART 输出字符                       | 可以先让 Linux 使用 SBI console 打印早期日志 |
| MMIO 访问宽度    | 必须支持 Linux 实际发出的 8/16/32-bit MMIO 访问 | `reg-io-width=<4>`、`reg-shift=<2>` 时 8250 按 32-bit stride 访问 |
| 中断模式          | 见下方详细说明                                      | 不能简单写"可选"                          |

UART interrupt 详细要求：

```text
- 若 DTS 中 UART node 没有 interrupts，且 Linux 使用 polling console，则 UART IRQ 可暂时不实现。
- 若 DTS 中 UART node 写了 interrupts，标准 8250 driver 可能启用 UART IRQ。
- 此时必须保证 UART IRQ、PLIC source ID、PLIC enable、claim/complete、IIR/IER/LSR 清中断语义全部正确。
```

最低建议：

```text
优先让 UART 兼容 ns16550a。
如果做不到，先通过 OpenSBI 实现 SBI console。
```

---

# 11. 物理内存 / DDR 最低要求

| 项目            | 判断是否达标的条件                                | 备注信息                       |
| ------------- | ---------------------------------------- | -------------------------- |
| DDR 可访问       | CPU 能稳定读写完整 DDR 地址范围                     | 已通过裸机测试后还需长时间压力测试          |
| DDR 起始地址      | 建议固定为 `0x80000000`                       | RISC-V Linux 常见平台约定        |
| DDR 大小        | 至少能容纳 OpenSBI、kernel、DTB、initramfs、运行时内存 | 128MB 对最小 BusyBox Linux 足够 |
| 地址连续性         | Linux 可用内存区域应连续或在 DTB 中准确描述              | 简化阶段建议只给 Linux 一段连续内存      |
| 内存对齐          | RV32 Linux kernel 装载地址需要 4MB 对齐          | 建议 kernel 放在 `0x80400000`  |
| 保留区域          | OpenSBI、DTB、initramfs 等区域不能被 kernel 覆盖   | 需要在 boot plan 和 DTB 中规划    |
| 访问宽度          | byte/halfword/word load/store 都正确        | Linux 编译代码会使用各种访问宽度        |
| AMO 到 DDR     | AMO/LR/SC 对 DDR 正确工作                     | 内核锁和原子变量依赖                 |
| MMIO 与 DDR 区分 | DDR 和外设地址空间不能重叠                          | 需要统一 SoC memory map        |
| 非法 MMIO 响应   | 非法/未实现 MMIO 地址不能让总线挂死，必须返回 access fault 或安全响应 | Linux driver 可能 probe 寄存器，总线 hang 会表现为 kernel 无任何后续输出 |

建议初始内存布局：

```text
0x80000000  OpenSBI / firmware
0x80400000  Linux kernel Image
0x87E00000  initramfs，可选
0x87F00000  DTB
```

具体地址可以调整，但必须保证：

```text
1. kernel 4MB 对齐
2. DTB 不被 kernel 解压或 BSS 覆盖
3. initramfs 不被覆盖
4. OpenSBI 常驻区域不被 Linux 当作普通内存使用
```

---

# 12. Device Tree 最低要求

| 项目                   | 判断是否达标的条件                                           | 备注信息                        |
| -------------------- | --------------------------------------------------- | --------------------------- |
| `/cpus`              | 描述 CPU hart、ISA、MMU 类型、timebase                     | Linux 识别 CPU 依赖             |
| `riscv,isa`          | 至少描述 `rv32ima_zicsr_zifencei`                       | 必须与真实硬件一致                   |
| `mmu-type`           | 写 `riscv,sv32`                                      | Linux 判断 MMU 能力             |
| `timebase-frequency` | 与硬件 timer 频率一致                                      | timer/clocksource 依赖        |
| `/memory`            | 描述 DDR 起始地址和大小                                      | Linux 内存管理依赖                |
| `/chosen`            | 包含 `stdout-path` 和 `bootargs`                       | console 和启动参数依赖             |
| UART node            | 描述 UART compatible、reg、clock、interrupts             | 使用标准驱动时必须                   |
| CLINT/timer node     | 描述 timer/ipi 相关中断                                   | OpenSBI 或 Linux 识别 timer 需要 |
| PLIC node            | 描述 PLIC 地址、interrupt-controller、interrupts-extended | Linux 外部中断需要                |
| CPU intc 子节点       | 每个 CPU 节点下必须有 `interrupt-controller` 子节点（`riscv,cpu-intc`） | PLIC 和 timer 的 `interrupts-extended` 要引用它，只写 CPU 本身不够 |
| reserved-memory      | 保留 OpenSBI、特殊内存、不可用区域，建议加 `no-map`，并确认 Linux memblock 没有分配这段区域 | 只保留地址范围但未被 Linux 识别，仍可能被覆盖 |
| initrd 信息            | 如果使用 initramfs/initrd，需要在 chosen 中提供 `linux,initrd-start/end`，或直接编进 kernel | 只写 rootfs 内容不够，kernel 必须能知道 initramfs 在哪里 |

最小 DTS 必须至少描述：

```text
CPU
memory
chosen
UART
timer/interrupt controller
```

---

# 13. Boot Protocol 最低要求

| 项目          | 判断是否达标的条件                                         | 备注信息                           |
| ----------- | ------------------------------------------------- | ------------------------------ |
| 入口特权级       | 推荐 OpenSBI 在 M-mode 启动，Linux 在 S-mode 启动          | 标准 RISC-V Linux 路线             |
| kernel 装载地址 | RV32 kernel 放在 4MB 对齐地址                           | 例如 `0x80400000`                |
| `a0`        | 跳入 Linux 时 `a0 = hartid`                          | 单核通常为 0                        |
| `a1`        | 跳入 Linux 时 `a1 = DTB 物理地址`                        | DTB 必须在内存中且未被覆盖                |
| `satp`      | 跳入 Linux 前 `satp = 0`                             | 进入 kernel 前 MMU 必须关闭           |
| 中断状态        | 跳入 kernel 前中断状态合理，通常关闭全局中断                        | 避免 kernel 初始化前收到异常中断           |
| cache 状态    | I-cache/D-cache 不应包含会破坏 kernel 启动的脏状态             | 最简单方案：跳转前 flush 必要 cache       |
| 固件保留内存      | OpenSBI 常驻区域不能被 Linux 分配覆盖                        | 通过 DTB reserved-memory 或内存范围规避 |
| DTB 格式      | DTB 是合法 flattened device tree binary              | 不能传 DTS 文本                     |
| initramfs   | 若需要进入 shell，initramfs 地址和大小必须传给 kernel，或编进 kernel | kernel 只打印日志时可暂时没有 rootfs      |

推荐第一阶段 boot chain：

```text
Reset / loader
  ↓
OpenSBI, M-mode
  ↓
Linux kernel, S-mode
  ↓
initramfs / BusyBox, U-mode
```

---

# 14. OpenSBI 平台最低要求

| 项目                   | 判断是否达标的条件                                 | 备注信息                         |
| -------------------- | ----------------------------------------- | ---------------------------- |
| M-mode firmware 入口   | OpenSBI 能从指定地址运行                          | 第一目标是看到 OpenSBI banner       |
| console putchar      | OpenSBI 能通过 UART 输出字符                     | Linux earlycon=sbi 依赖        |
| console getchar      | 可选，但进入交互 shell 后有帮助                       | 最小 kernel 日志不强制              |
| timer driver         | OpenSBI 能设置下一次 timer event                | Linux 调度依赖                   |
| interrupt delegation | OpenSBI 能配置 `medeleg/mideleg`             | Linux S-mode trap 依赖         |
| hart start           | 单核只需 boot hart                            | SMP 可后续再做                    |
| IPI                  | 单核不需要                                     | 多核 Linux 才需要                 |
| PMP                  | 见下方详细说明                                      | PMP 配置错误会导致 S/U 访问 DDR/MMIO 直接 fault |
| final jump           | OpenSBI 能正确跳到 Linux，设置 `a0/a1`，关闭 MMU     | boot protocol 核心             |
| platform config      | OpenSBI 平台代码中的 UART、timer、PLIC 地址与 SoC 一致 | 地址错误会导致无输出或无 timer           |

PMP 详细要求：

```text
- 如果完全不实现 PMP entry，则确认 S/U mode 对 DDR/MMIO 没有被 PMP 阻断。
- 如果实现任意 PMP entry，则必须由 OpenSBI 配置出允许 S-mode 访问的 DDR/MMIO 区域。
- Linux 所需区域至少包括 DDR、UART、CLINT/ACLINT、PLIC。
- PMP probe illegal 可以被 OpenSBI 处理，但 probe 能处理不代表权限配置正确。
```

最低验证顺序：

```text
1. 只运行 OpenSBI。
2. 确认 UART 打印 OpenSBI banner。
3. 确认 OpenSBI 能识别 hart、timer、console。
4. 再把 Linux 作为 payload 或 next stage。
```

---

# 15. Rootfs / BusyBox 最低要求

这一部分不是 CPU 硬件条件，但如果目标是进入 shell，则必须满足。

| 项目        | 判断是否达标的条件                               | 备注信息                              |
| --------- | --------------------------------------- | --------------------------------- |
| initramfs | kernel 能找到 initramfs                    | 最简单 rootfs 方案                     |
| `/init`   | initramfs 根目录存在可执行 `/init`              | kernel 默认找 `/init`、`/sbin/init` 等 |
| BusyBox   | 静态编译，适配 `riscv32`                       | 建议用 musl 静态链接                     |
| `/bin/sh` | `/bin/sh` 指向 BusyBox ash                | 进入 shell 需要                       |
| `/dev`    | 能提供 console/null/tty 等基础设备，或挂载 devtmpfs | 没有 console 会影响 shell              |
| `/proc`   | `/init` 中挂载 procfs                      | 方便调试                              |
| `/sys`    | `/init` 中挂载 sysfs                       | 方便调试                              |
| bootargs  | 包含 `console=... init=/init`             | 指定 console 和 init                 |

最小 `/init`：

```sh
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "Hello from RV32 Linux"
exec /bin/sh
```

---

# 16. 第一阶段不强制要求的项目

以下项目不是最小 Linux 启动的硬性条件，可以后续再做：

| 项目                | 是否必须 | 备注                 |
| ----------------- | ---- | ------------------ |
| 网卡驱动              | 否    | 进入 shell 后再移植      |
| NAND Flash rootfs | 否    | 第一阶段建议使用 initramfs |
| SPI Flash boot    | 否    | 可以先 JTAG/loader 加载 |
| 文件系统 ext4         | 否    | initramfs 阶段不需要    |
| 多核 SMP            | 否    | 单核 Linux 先跑通       |
| 用户态动态链接           | 否    | BusyBox 静态链接即可     |
| bash              | 否    | BusyBox ash 足够     |
| FPU               | 否    | 可先禁用               |
| 压缩指令 C            | 否    | 不是 Linux 启动硬要求     |
| 高性能 cache 策略      | 否    | 正确性优先              |
| DMA 一致性           | 否    | 没有使用 DMA 外设时可后续处理  |

---

# 17. 建议检查顺序

建议小组按以下顺序逐项确认：

```text
1. ISA
   - RV32I/M/A/Zicsr/Zifencei
   - misa 正确
   - riscv-tests 通过

2. 特权级
   - M/S/U mode
   - mret/sret/ecall
   - CSR 行为
   - 异常委托/中断委托

3. MMU
   - satp
   - Sv32 page table walk
   - TLB
   - page fault
   - sfence.vma

4. cache / memory consistency
   - MMIO 不 cache
   - PTW 与 dcache 一致
   - fence.i 有效
   - sfence.vma 后页表更新可见

5. timer / interrupt
   - mtime/mtimecmp
   - MTIP
   - STIP
   - mideleg
   - S-mode timer interrupt

6. SoC 外设
   - UART
   - CLINT/timer
   - PLIC
   - DDR memory map

7. boot protocol
   - OpenSBI 能启动
   - kernel 4MB 对齐
   - a0/a1 正确
   - satp=0
   - DTB 正确

8. Linux kernel
   - 能打印 early log
   - 能完成内存初始化
   - 能 panic 到 no init

9. initramfs / BusyBox
   - 能执行 /init
   - 能进入 /bin/sh
```

---

# 18. 最终检查表

| 大类        | 项目               | 达标条件                      | 检查结果 | 证据/备注 |
| --------- | ---------------- | ------------------------- | ---- | ----- |
| ISA       | RV32I            | 基础整数指令全部正确                |      |       |
| ISA       | M 扩展             | 乘除法指令正确                   |      |       |
| ISA       | A 扩展             | LR/SC + AMO 全部正确          |      |       |
| ISA       | Zicsr            | CSR 指令正确                  |      |       |
| ISA       | Zifencei         | `fence.i` 有效              |      |       |
| ISA       | `wfi`            | 至少作为 NOP                  |      |       |
| ISA       | 可选扩展探测           | 未实现扩展指令产生 illegal instr   |      |       |
| CSR       | `misa`           | 与真实硬件能力一致                 |      |       |
| 特权级       | M-mode           | 复位进入 M-mode               |      |       |
| 特权级       | S-mode           | Linux 可运行在 S-mode         |      |       |
| 特权级       | U-mode           | 用户程序可运行在 U-mode           |      |       |
| 特权级       | `mret/sret`      | 精确更新 xIE/xPIE/xPP，返回语义正确  |      |       |
| 特权级       | `sepc/mepc`      | 同步异常保存当前PC，中断保存被打断PC，ecall不+4 |      |       |
| 特权级       | `mstatus.TVM/TSR/TW` | S-mode 下 sfence.vma/sret/wfi 受控 | |       |
| 特权级       | CSR 探测行为         | 未实现 CSR 访问产生 illegal instr |      |       |
| 异常        | `ecall`          | U/S/M ecall cause 正确      |      |       |
| 异常        | page fault       | cause/stval 正确            |      |       |
| 委托        | `medeleg`        | S-mode 异常委托正常             |      |       |
| 委托        | `mideleg`        | S-mode 中断委托正常             |      |       |
| 委托        | S-mode ecall 不委托 | `medeleg[9]=0`，SBI call 进 M-mode |  |       |
| 委托        | `sie/sip` 视图    | sie/sip 是 mie/mip 的 S-mode 视图 |   |       |
| MMU       | `satp`           | Sv32 MODE/ASID/PPN 正确     |      |       |
| MMU       | PTW              | 两级页表遍历正确                  |      |       |
| MMU       | 权限检查             | R/W/X/U/SUM/MXR 正确        |      |       |
| MMU       | `sfence.vma`     | TLB 和页表可见性正确              |      |       |
| Cache     | I-cache          | `fence.i` 后取新指令           |      |       |
| Cache     | D-cache          | 普通 load/store 正确          |      |       |
| Cache     | MMIO bypass      | 基于物理地址判断 MMIO             |      |       |
| Cache     | PTW 一致性          | PTW 能看到最新 PTE             |      |       |
| Timer     | `mtime`          | 64-bit 单调递增               |      |       |
| Timer     | `mtimecmp`       | 能触发 timer interrupt       |      |       |
| Timer     | 64-bit mtimecmp 写入 | RV32 高低32位写入顺序不产生永久MTIP |   |       |
| Timer     | STIP             | Linux 能收到 S-mode timer    |      |       |
| Timer     | STIP 注入          | M-mode 可写 mip.STIP，S-mode 可见 sip.STIP | |   |
| Timer     | STIP 清除          | STIP 能正确清除，不会 storm       |      |       |
| Counter   | `time/timeh`     | S-mode 可读或通过 counteren 开放 |      |       |
| Counter   | `mcounteren.TM`  | 置位，允许 S-mode 读 rdtime     |      |       |
| Interrupt | PLIC             | claim/complete/enable 可用  |      |       |
| Interrupt | PLIC source 0    | claim 无中断返回 0，source 0 保留  |      |       |
| Interrupt | PLIC context     | M/S context 布局与 DTB 一致     |      |       |
| Interrupt | level IRQ 语义    | level interrupt 设备条件清除后 pending 消失 | |    |
| UART      | TX/RX            | 能稳定输出和输入                  |      |       |
| UART      | Linux compatible | ns16550a 或 SBI console 可用 |      |       |
| UART      | 8250 寄存器兼容       | IER/IIR/FCR/LCR/LSR/DLL/DLM 语义正确 | |       |
| UART      | MMIO 访问宽度        | 支持 8/16/32-bit MMIO stride |      |       |
| UART      | 中断模式             | 有 interrupts 则 IRQ 必须完整实现  |      |       |
| DDR       | 基础读写             | CPU-DDR 通信稳定              |      |       |
| DDR       | 地址空间             | memory map 与 DTB 一致       |      |       |
| DDR       | 非法 MMIO 响应       | 未实现地址返回 access fault 不挂死  |      |       |
| PMP       | PMP 配置           | 若实现 PMP，S-mode 可访问 DDR/MMIO |   |       |
| Boot      | OpenSBI          | 能打印 banner 并跳转            |      |       |
| Boot      | kernel 地址        | RV32 kernel 4MB 对齐        |      |       |
| Boot      | `a0/a1`          | hartid 和 DTB 地址正确         |      |       |
| Boot      | `satp=0`         | 进入 kernel 前 MMU 关闭        |      |       |
| DTB       | `/cpus`          | ISA/MMU/timebase 正确       |      |       |
| DTB       | CPU intc 子节点     | riscv,cpu-intc 存在且被引用      |      |       |
| DTB       | `/memory`        | DDR 地址和大小正确               |      |       |
| DTB       | `/chosen`        | console/bootargs 正确       |      |       |
| DTB       | initrd 地址        | linux,initrd-start/end 正确  |      |       |
| DTB       | reserved-memory  | no-map 且 Linux memblock 不分配 |    |       |
| Rootfs    | initramfs        | kernel 能找到 rootfs         |      |       |
| Rootfs    | `/init`          | 能执行并进入 shell              |      |       |

---

# 19. 当前阶段最重要的结论

在正式开始 OpenSBI/Linux 移植之前，必须优先确认以下 6 件事：

```text
1. 是否已经支持完整 A 扩展。
2. 是否已经支持 M/S/U mode。
3. 是否已经支持 Sv32，并且 page fault / sfence.vma 正确。
4. MMIO 判断是否基于物理地址，而不是虚拟地址。
5. PTW 读取页表是否与 dcache 保持一致。
6. Linux 是否能收到 S-mode timer interrupt。
```

如果这 6 项中任意一项不达标，Linux 即使能打印早期日志，也很可能无法稳定进入用户态 shell。

## 当前卡死最相关的 8 项补充检查

在 OpenSBI 已通过、kernel 一进入就卡死的情况下，以下 8 项最可能导致问题：

```text
1. S-mode ecall 不得委托，必须进入 OpenSBI。
2. M-mode 可写 mip.STIP，S-mode 可见 sip.STIP。
3. STIP 必须能正确清除，不能 storm。
4. sie/sip 必须是 mie/mip 的正确 S-mode 视图。
5. PLIC claim/complete/context/source ID 必须严格匹配 DTB。
6. UART 8250 IER/IIR/FCR/LCR/LSR/DLAB/THRE/TEMT/DR 语义必须正确。
7. 若 UART interrupts 存在，UART IRQ 不能再当作可选。
8. 若实现 PMP，必须确认 S-mode 访问 DDR/MMIO 没被 PMP 拦截。
```

**关键认识**：对课程 CPU 来说，Linux 启动失败往往不是因为漏了大类，而是某个 CSR bit、IRQ pending 清除、PLIC context、8250 寄存器语义不精确。
