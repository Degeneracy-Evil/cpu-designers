#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2cm),
  numbering: "1",
)
#set text(
  size: 10.5pt,
)
#set par(justify: true, leading: 0.6em)
#set heading(numbering: "1.1")

#set document(title: [RISC-V M 特权级规范速查手册])

#align(center)[
  #text(size: 18pt, weight: "bold")[
    RISC-V Machine (M) 特权级规范速查手册
  ]
  #v(0.4em)
  #text(size: 10pt)[
    基于 RISC-V Privileged Architecture Version 20260120 (Machine ISA Version 1.13)\
    仅涵盖 M 特权级，适用于 SimpleCPU 开发参考\
    整理日期：#datetime.today().display()
  ]
]

#v(1.2em)

= 概述

本文档从 RISC-V 特权规范中提取 Machine (M) 特权级相关内容，整理为开发速查手册。所有内容仅涉及 M 级，S/U/H 级相关内容不纳入。

*适用范围：*仅实现 M 特权级的嵌入式系统（SimpleCPU 属于此类别）。

= 特权级定义

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*级别*], [*编码*], [*缩写*], [*说明*],
  [0], [`00`], [U], [用户/应用模式（本系统未实现）],
  [1], [`01`], [S], [监管者模式（本系统未实现）],
  [3], [`11`], [M], [机器模式（*必须实现*）],
)

M 模式是唯一必须实现的特权级，拥有对硬件的完全访问权限。

= CSR 地址映射规则

CSR 地址 12 位，高 4 位 `csr[11:8]` 编码访问权限：

- `csr[11:10]`：`00`/`01`/`10` = 读/写，`11` = 只读
- `csr[9:8]`：最低可访问特权级（`11` = M 级）

*关键地址范围：*

#table(
  columns: (auto, 1fr, auto),
  align: (center, left, center),
  inset: 6pt,
  [*地址范围*], [*用途*], [*权限*],
  [`0x300-0x3FF`], [M 级标准读/写 CSR], [MRW],
  [`0x700-0x77F`], [M 级标准读/写 CSR], [MRW],
  [`0xB00-0xB7F`], [M 级标准读/写 CSR（计数器）], [MRW],
  [`0xB80-0xBBF`], [M 级标准读/写 CSR（计数器高半）], [MRW],
  [`0xF00-0xF7F`], [M 级标准只读 CSR], [MRO],
  [`0xF80-0xFBF`], [M 级标准只读 CSR], [MRO],
)

*访问违规：*访问不存在的 CSR → 非法指令异常；写只读 CSR → 非法指令异常。

= CSR 字段规范

== WPRI（保留写保留值，读忽略值）
保留字段。软件应忽略读出值，写时应保留原值。未提供这些字段的实现必须使其只读为零。

== WLRL（只写/读合法值）
仅对部分编码定义行为。软件不应写非法值，也不应假设读回合法值（除非上次写的是合法值）。实现*可以*（但不要求）在写非法值时触发非法指令异常。

== WARL（写任意值，读合法值）
允许写任意值，但保证读回合法值。实现*不会*因写非法值触发异常。可通过"写入后读回"确定支持值范围。

= M 级 CSR 完整列表

== 机器信息寄存器（只读）

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*地址*], [*名称*], [*属性*], [*说明*],
  [`0xF11`], [`mvendorid`], [MRO], [供应商 JEDEC ID，非商业实现返回 0],
  [`0xF12`], [`marchid`], [MRO], [微架构 ID，开源项目 MSB=0],
  [`0xF13`], [`mimpid`], [MRO], [实现版本 ID，未实现返回 0],
  [`0xF14`], [`mhartid`], [MRO], [硬件线程 ID，单核返回 0],
  [`0xF15`], [`mconfigptr`], [MRO], [配置数据结构指针，无则返回 0],
)

== 机器陷阱设置寄存器

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*地址*], [*名称*], [*属性*], [*说明*],
  [`0x300`], [`mstatus`], [MRW], [机器状态寄存器（详见下文）],
  [`0x301`], [`misa`], [MRW], [ISA 扩展报告寄存器（WARL）],
  [`0x304`], [`mie`], [MRW], [机器中断使能寄存器],
  [`0x305`], [`mtvec`], [MRW], [机器陷阱向量基址寄存器],
  [`0x310`], [`mstatush`], [MRW], [mstatus 高 32 位（仅 RV32）],
)

*注意：* `medeleg`(0x302) 和 `mideleg`(0x303) 在无 S 模式系统中*不应存在*。`mcounteren`(0x306) 在无 U 模式系统中*不应存在*。

== 机器陷阱处理寄存器

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*地址*], [*名称*], [*属性*], [*说明*],
  [`0x340`], [`mscratch`], [MRW], [机器暂存寄存器],
  [`0x341`], [`mepc`], [MRW], [机器异常程序计数器],
  [`0x342`], [`mcause`], [MRW], [机器陷阱原因寄存器],
  [`0x343`], [`mtval`], [MRW], [机器陷阱值寄存器],
  [`0x344`], [`mip`], [MRW], [机器中断挂起寄存器],
)

== 机器计数器/定时器寄存器

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*地址*], [*名称*], [*属性*], [*说明*],
  [`0xB00`], [`mcycle`], [MRW], [时钟周期计数器（低 32 位）],
  [`0xB02`], [`minstret`], [MRW], [指令完成计数器（低 32 位）],
  [`0xB80`], [`mcycleh`], [MRW], [mcycle 高 32 位（仅 RV32）],
  [`0xB82`], [`minstreth`], [MRW], [minstret 高 32 位（仅 RV32）],
)

= `misa` 寄存器详解

WARL 读/写寄存器，报告 hart 支持的 ISA。MXLEN 位宽。

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*字段*], [*位*], [*说明*],
  [MXL], [MXLEN-1 : MXLEN-2], [机器 XLEN：1=RV32, 2=RV64。*只读*],
  [Extensions], [25:0], [每比特对应一个字母扩展（WARL）],
)

*扩展位编码（常用）：*

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*位*], [*字母*], [*扩展*],
  [0], [A], [原子扩展],
  [2], [C], [压缩指令扩展],
  [8], [I], [RV32I/RV64I 基础 ISA],
  [12], [M], [整数乘/除扩展],
  [18], [S], [监管者模式],
  [20], [U], [用户模式],
  [23], [X], [非标准扩展],
)

*仅 M 级系统典型值（RV32I）：* MXL=1, I=1 → `0x40000100`

*E 位为 I 的补码（只读）。*若设置 F=0 且 D=1，则 F 和 D 均被清除。若设置 U=0 且 S=1，则 U 和 S 均被清除。

= `mstatus` 寄存器详解

MXLEN 位读/写寄存器，跟踪和控制 hart 当前运行状态。

== RV32 位布局

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 5pt,
  [*位*], [*字段*], [*属性*], [*说明*],
  [31], [SD], [只读], [FS/XS/VS 任一 Dirty 时为 1],
  [22], [TSR], [WARL], [Trap SRET，无 S 模式时只读 0],
  [21], [TW], [WARL], [Timeout Wait，无更低特权级时只读 0],
  [20], [TVM], [WARL], [Trap Virtual Memory，无 S 模式时只读 0],
  [19], [MXR], [WARL], [Make eXecutable Readable，无 S 模式时只读 0],
  [18], [SUM], [WARL], [Supervisor User Memory，无 S 模式时只读 0],
  [17], [MPRV], [WARL], [Modify PRiVilege，无 U 模式时只读 0],
  [16:15], [XS], [只读], [扩展状态摘要，无扩展时只读 0],
  [14:13], [FS], [WARL], [浮点状态，无 F 扩展且无 S 模式时只读 0],
  [12:11], [MPP], [WARL], [先前特权级：可保存 M 及更低已实现模式],
  [10:9], [VS], [WARL], [向量状态，无 V 扩展且无 S 模式时只读 0],
  [8], [SPP], [WARL], [先前 S 特权级，无 S 模式时只读 0],
  [7], [MPIE], [WARL], [M 模式中断使能保存位],
  [6], [UBE], [WARL], [U 模式大端使能，无 U 模式时只读 0],
  [5], [SPIE], [WARL], [S 模式中断使能保存位，无 S 模式时只读 0],
  [4], [WPRI], [-], [保留],
  [3], [MIE], [WARL], [M 模式全局中断使能],
  [2], [WPRI], [-], [保留],
  [1], [SIE], [WARL], [S 模式全局中断使能，无 S 模式时只读 0],
  [0], [WPRI], [-], [保留],
)

== 仅 M 级系统的 mstatus 简化

当系统仅实现 M 模式时，大量字段只读为 0：

*可写字段：*仅 MIE（bit 3）和 MPIE（bit 7）

*WARL 约束：* MPP 只能保存 `2'b11`（M 模式）

*只读 0 字段：* SIE, SPIE, SPP, UBE, VS, FS, XS, MPRV, SUM, MXR, TVM, TW, TSR, SD

= 中断使能与挂起寄存器

== `mie` 寄存器（0x304）

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*位*], [*字段*], [*属性*], [*说明*],
  [11], [MEIE], [WARL], [M 级外部中断使能],
  [9], [SEIE], [WARL], [S 级外部中断使能（无 S 模式时只读 0）],
  [7], [MTIE], [WARL], [M 级定时器中断使能],
  [5], [STIE], [WARL], [S 级定时器中断使能（无 S 模式时只读 0）],
  [3], [MSIE], [WARL], [M 级软件中断使能],
  [1], [SSIE], [WARL], [S 级软件中断使能（无 S 模式时只读 0）],
)

*仅 M 级系统可写字段：* MEIE(11), MTIE(7), MSIE(3)

== `mip` 寄存器（0x344）

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 6pt,
  [*位*], [*字段*], [*属性*], [*说明*],
  [11], [MEIP], [只读], [M 级外部中断挂起（由中断控制器设置）],
  [9], [SEIP], [WARL], [S 级外部中断挂起（无 S 模式时只读 0）],
  [7], [MTIP], [只读], [M 级定时器中断挂起（由 mtimecmp 清除）],
  [5], [STIP], [WARL], [S 级定时器中断挂起（无 S 模式时只读 0）],
  [3], [MSIP], [只读], [M 级软件中断挂起（由内存映射寄存器设置）],
  [1], [SSIP], [WARL], [S 级软件中断挂起（无 S 模式时只读 0）],
)

*仅 M 级系统：* MEIP、MTIP、MSIP 由硬件/中断控制器驱动，软件不可直接写。

== 中断优先级（Section 3.1.9）

多个 M 级中断同时挂起时，按以下*降序优先级*处理：

#text(fill: red, weight: "bold")[*MEI > MSI > MTI > SEI > SSI > STI > LCOFI*]

即：外部中断 > 软件中断 > 定时器中断

= `mtvec` 寄存器详解（0x305）

WARL 读/写寄存器，MXLEN 位宽。

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*字段*], [*位*], [*说明*],
  [BASE], [MXLEN-1 : 2], [陷阱向量基址，*必须 4 字节对齐*（WARL）],
  [MODE], [1:0], [向量模式（WARL）],
)

*MODE 编码：*

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*值*], [*名称*], [*行为*],
  [0], [Direct], [所有陷阱：`pc ← BASE`],
  [1], [Vectored], [同步异常：`pc ← BASE`；中断：`pc ← BASE + 4×cause`],
  [≥2], [-], [保留],
)

= `mepc` 寄存器详解（0x341）

MXLEN 位 WARL 读/写寄存器。

- `mepc[0]` 始终为 0
- 当 IALIGN=32 时，`mepc[1:0]` 始终为 0（WARL：写时屏蔽低 2 位）
- 陷阱进入 M 模式时，`mepc` 写入被中断/异常指令的虚拟地址

= `mcause` 寄存器详解（0x342）

MXLEN 位读/写寄存器。

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*字段*], [*位*], [*说明*],
  [Interrupt], [MXLEN-1], [1=中断，0=同步异常],
  [Exception Code], [MXLEN-2 : 0], [异常/中断编号（WLRL）],
)

== 中断编码（Interrupt=1）

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 5pt,
  [*Code*], [*名称*], [*说明*],
  [0], [-], [保留],
  [3], [MSI], [机器软件中断],
  [7], [MTI], [机器定时器中断],
  [11], [MEI], [机器外部中断],
  [≥16], [-], [平台自定义],
)

== 异常编码（Interrupt=0）

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 5pt,
  [*Code*], [*名称*], [*说明*],
  [0], [指令地址不对齐], [控制流指令目标未对齐],
  [1], [指令访问故障], [取指访问错误],
  [2], [非法指令], [未定义或特权级不足的指令],
  [3], [断点], [EBREAK 或 C.EBREAK 触发],
  [4], [加载地址不对齐], [加载地址未对齐],
  [5], [加载访问故障], [加载访问错误],
  [6], [Store/AMO 地址不对齐], [Store/AMO 地址未对齐],
  [7], [Store/AMO 访问故障], [Store/AMO 访问错误],
  [8], [ECALL from U], [U 模式环境调用],
  [11], [ECALL from M], [M 模式环境调用],
  [12], [指令页故障], [取指页故障],
  [13], [加载页故障], [加载页故障],
  [15], [Store/AMO 页故障], [Store/AMO 页故障],
)

== 同步异常优先级（降序）

#table(
  columns: (auto, 1fr),
  align: (center, left),
  inset: 5pt,
  [*优先级*], [*异常码*],
  [最高], [3 — 指令地址断点],
  [], [12, 1 — 取指页故障/访问故障],
  [], [1 — 指令访问故障（物理地址）],
  [], [2 — 非法指令],
  [], [0 — 指令地址不对齐],
  [], [8, 9, 11 — ECALL],
  [], [3 — EBREAK],
  [], [4, 6 — 加载/Store 地址不对齐（可选更高优先级）],
  [], [13, 15, 5, 7 — 数据页故障/访问故障],
  [最低], [4, 6 — 加载/Store 地址不对齐（若非更高优先级）],
)

= `mtval` 寄存器详解（0x343）

MXLEN 位 WARL 读/写寄存器。

- 断点/不对齐/访问故障/页故障：写入出错虚拟地址
- EBREAK 异常：写入 0 或指令虚拟地址
- 非法指令异常：可选写入出错指令编码（右对齐，高位清零）
- 其他陷阱：写入 0

= `mscratch` 寄存器详解（0x340）

MXLEN 位读/写寄存器，专供 M 模式使用。典型用途：保存 M 模式陷阱处理上下文指针，进入陷阱处理时与通用寄存器交换。

= 陷阱进入行为

当陷阱进入 M 模式时，硬件自动执行：

#table(
  columns: (auto, 1fr),
  align: (center, left),
  inset: 6pt,
  [*操作*], [*说明*],
  [`mepc ← pc`], [写入被中断/异常指令地址],
  [`mcause ← cause`], [写入陷阱原因编码],
  [`mtval ← val`], [写入异常相关信息],
  [`MPIE ← MIE`], [保存当前 MIE 到 MPIE],
  [`MIE ← 0`], [禁用 M 级中断],
  [`MPP ← 当前特权级`], [保存当前特权级到 MPP],
  [`pc ← mtvec.BASE`], [跳转到陷阱向量（Direct 模式）],
)

*Vectored 模式：*若 `mtvec.MODE=1`，同步异常跳转 BASE，中断跳转 `BASE + 4×cause`。

= MRET 指令行为

从 M 模式陷阱返回时，硬件自动执行：

#table(
  columns: (auto, 1fr),
  align: (center, left),
  inset: 6pt,
  [*操作*], [*说明*],
  [`MIE ← MPIE`], [从 MPIE 恢复 MIE],
  [`MPIE ← 1`], [MPIE 设为 1],
  [`MPP ← 最低已实现特权级`], [仅 M 模式时设为 M（`2'b11`）；有 U 模式时设为 U（`2'b00`）],
  [`MPRV ← 0`], [若新特权级 ≠ M，则 MPRV 清零],
  [`pc ← mepc`], [返回到陷阱前的指令],
)

#block(fill: rgb(255, 240, 240), inset: 8pt, radius: 4pt)[
  *重要提醒：* MRET 中 MIE 和 MPIE 是*交换恢复*关系，不是简单置位！
  - `MIE ← MPIE`（从保存值恢复，不是硬编码 1）
  - `MPIE ← 1`（置 1，不是保留原值）
  - MPP 设为*最低已实现特权级*（仅 M 级系统为 `2'b11`）
]

= WFI 指令

Wait For Interrupt。告知实现当前 hart 可暂停直到中断需要服务。

- 合法实现：将 WFI 作为 *NOP* 执行
- 若中断使能且挂起，在 `pc+4` 处取中断陷阱
- 在 M 模式中，TW=0 时 WFI 正常执行；TW=1 时在更低特权级触发非法指令异常
- WFI 操作不受 `mstatus.MIE` 和 `mideleg` 影响，但应遵守各独立中断使能位

= ECALL / EBREAK

- *ECALL*：在 M 模式中执行 → 触发异常码 11（Environment call from M-mode）
- *EBREAK*：触发异常码 3（Breakpoint）
- 两者均将 `mepc` 设为*自身指令地址*（非 pc+4），不增加 `minstret`

= 复位行为

复位时 hart 状态：

#table(
  columns: (auto, 1fr),
  align: (center, left),
  inset: 6pt,
  [*项目*], [*复位值*],
  [特权模式], [M],
  [`mstatus.MIE`], [0],
  [`mstatus.MPRV`], [0],
  [`mstatus.MBE`], [0（若支持小端）],
  [`misa`], [最大支持扩展集],
  [`pc`], [实现定义的复位向量],
  [`mcause`], [复位原因（不区分时返回 0）],
  [PMP A/L 字段], [0（除非平台另有规定）],
  [其他状态], [UNSPECIFIED],
  [WARL 字段], [不含非法值],
)

= 定时器寄存器（内存映射）

== `mtime`
64 位内存映射读/写寄存器，以恒定频率递增。所有 harts 共享。

== `mtimecmp`
64 位内存映射读/写寄存器。当 `mtime ≥ mtimecmp`（无符号比较）时，MTIP 置 1。写 `mtimecmp` 为更大值可清除 MTIP。

*注意：* `mtime` 改变后保证最终反映到 MTIP，但不一定立即反映。

= `mstatush` 寄存器（仅 RV32，0x310）

RV32 专用 32 位读/写寄存器，包含 RV64 `mstatus` 高 32 位中的部分字段：

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 6pt,
  [*位*], [*字段*], [*说明*],
  [30], [MDT], [M 级禁用陷阱（Smdbltrp 扩展）],
  [29], [MPELP], [M 级先前 ELP（Zicfilp 扩展）],
  [7], [MPV], [修改特权虚拟化（H 扩展）],
  [6], [GVA], [Guest 虚拟地址（H 扩展）],
  [5], [MBE], [M 模式大端使能],
  [4], [SBE], [S 模式大端使能],
)

*仅 M 级系统：* MBE 可读写，SBE 只读 0，其余字段视扩展实现而定。

= CSR 字段调制规则

若写一个 CSR 改变了另一个 CSR 字段的合法值集合，则第二个 CSR 的字段*立即*获得新合法值集合中的一个 `UNSPECIFIED` 值——即使原值仍合法也可能改变。此变化不是对 CSR 的写操作，不触发副作用。

= 仅 M 级系统设计要点总结

#table(
  columns: (auto, 1fr),
  align: (center, left),
  inset: 6pt,
  [*项目*], [*要求*],
  [必须实现的 CSR], [`mstatus`, `misa`, `mie`, `mtvec`, `mstatush`(RV32), `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mconfigptr`, `mcycle`, `minstret`, `mcycleh`(RV32), `minstreth`(RV32)],
  [不应存在的 CSR], [`medeleg`, `mideleg`, `mcounteren`, `sstatus`, `sie`, `stvec`, `sscratch`, `sepc`, `scause`, `stval`, `sip`, `satp`],
  [`mstatus` 可写位], [仅 MIE(bit3) 和 MPIE(bit7)],
  [`mstatus` MPP], [WARL，仅接受 `2'b11`],
  [`mie` 可写位], [仅 MEIE(bit11), MTIE(bit7), MSIE(bit3)],
  [`mip` 可写位], [无（MEIP/MTIP/MSIP 均由硬件驱动）],
  [`mtvec` MODE], [至少支持 Direct(0)；Vectored(1) 可选],
  [`mtvec` BASE], [必须 4 字节对齐],
  [`mepc` 低 2 位], [IALIGN=32 时始终为 0],
  [中断优先级], [MEI > MSI > MTI],
  [MRET], [`MIE←MPIE`, `MPIE←1`, `MPP←M`, `pc←mepc`],
  [陷阱进入], [`MPIE←MIE`, `MIE←0`, `MPP←当前模式`, `pc←mtvec.BASE`],
  [WFI], [至少作为 NOP 实现],
  [复位], [M 模式，MIE=0，MPRV=0，pc=复位向量],
)
