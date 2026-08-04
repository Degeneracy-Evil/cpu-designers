// 计算机组成原理实验报告模板（Typst）
#set title("存储控制单元设计实验报告")
#import "@local/cetz:0.5.0"
// 段落缩进
#set par(first-line-indent: (amount: 2em, all: true))
// 强调改进
#show strong: text.with(font: "Microsoft YaHei")
#show emph: text.with(font: ("Calibri", "LiSu"))

#set page(paper: "a4", margin: (top: 2cm, bottom: 2cm, left: 2.5cm, right: 2cm))
#set heading(numbering: "1.")
#show heading: it => {
  block([*#it*], below: 1em)
}
#set text(size: 24pt)
#align(horizon, {
  [#align(center)[2026 年春季学期\
    计算机组成原理课程]]
  v(2em)
  align(center)[32 位 RISC-V 多周期嵌入式CPU]
  v(2em)
  align(center)[#text(40pt)[设\ 计\ 报\ 告]]

  v(4em)
  align(center)[#text(size: 18pt)[负责人：王之翼#h(1em)18996388318\    张潘妍    张之恒    陈海攀]]
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年5月30日]]
})
#pagebreak()
//普通文本
#set text(size: 14pt)
#set page(numbering: "1 / 1")
#show link: underline

#outline(title: "目录", indent: auto, depth: 2)
#pagebreak()

= 项目简述

== 项目环境与语言

设计语言：SystemVerilog（除数组语法外基本和Verilog兼容）

仿真环境：Vivado~2018.3版本

== 设计目标

#move(dx: 2em)[
  + `RISCV32-IM_Zicsr_Zifencei`多周期CPU（使用上次成果）
  + 实现虚拟内存
  + 实现TLB
]

== 当前实现的特性

#move(dx: 2em)[
  + 实现Sv32页式虚拟内存体系
  + 实现统一TLB
]

== 参考资料

#move(dx: 2em)[
  + RISC-V-Reader-Chinese-v2p12017.pdf
  + FPGA-A7-PRJ-UDB_V1.0-引脚坐标参考.pdf
  + 所有课程PPT（指导老师：何安平）
  + #link(
      "https://documentation-service.arm.com/static/64258237314e245d086bc8c6?token=",
    )[IHI0033a_AMBA_AHB-Lite_Protocol.pdf]
  + #link(
      "https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3?token=",
    )[IHI0024E_amba_apb_architecture_spec.pdf]
  + #link("https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb?token=")[IHI0022L_amba_axi_protocol_spec.pdf]
  + 特权架构规范：#link("https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf")[riscv-privileged.pdf]
  + 平台级中断控制器：#link("https://docs.riscv.org/reference/plic/_attachments/riscv-plic.pdf")[riscv-plic.pdf]
  + tree-PLRU算法：#link("https://people.computing.clemson.edu/~mark/464/p_lru.txt")[p_lru.txt]
]

= 实现细节

== Sv32 页式虚拟内存体系

我们按照riscv的标准，实现了Sv32虚存。Sv32是RISC-V 32位架构定义的页式虚拟内存方案，采用二级页表结构将32位虚拟地址翻译为物理地址。

=== 虚拟地址分解

32位虚拟地址被分解为三个字段：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*字段*], [*位宽*], [*说明*],
  [VPN\[1\]], [10 bit], [一级页表索引，`vaddr[31:22]`],
  [VPN\[0\]], [10 bit], [二级页表索引，`vaddr[21:12]`],
  [page\_offset], [12 bit], [页内偏移，`vaddr[11:0]`],
)

=== 二级页表结构

页表漫游从`satp.PPN`指向的L1页表开始：

#move(dx: 2em)[
  + *L1页表*：以VPN\[1\]为索引查找L1 PTE。若L1 PTE为叶节点（R/W/X不全为0），则命中*megapage*（4MB大页），物理页号的高位来自PTE.PPN，低10位来自虚拟地址的VPN\[0\]
  + *L0页表*：若L1 PTE为非叶节点（指向下一级页表），则以VPN\[0\]为索引查找L0 PTE。L0 PTE必须为叶节点，命中*normal page*（4KB普通页）
  + *错误*：L0 PTE为非叶节点，或PTE.V=0，或保留位编码（R=0且W=1），均产生页错误
]

=== PTE格式

32位页表项（PTE）的位域定义如下：

#table(
  columns: (auto, auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*位域*], [*位宽*], [*位位置*], [*说明*],
  [PPN], [22], [31:10], [物理页号，拼接page\_offset得到完整物理地址],
  [RSW], [2], [9:8], [保留给软件使用，硬件忽略],
  [D], [1], [7], [脏位，该页曾被写入],
  [A], [1], [6], [访问位，该页曾被访问],
  [G], [1], [5], [全局映射，ASID不参与匹配],
  [U], [1], [4], [用户模式可访问],
  [X], [1], [3], [可执行],
  [W], [1], [2], [可写],
  [R], [1], [1], [可读],
  [V], [1], [0], [有效位],
)

叶节点判定：`V=1 && !(R=0 && W=1)`，且R/W/X不全为0。

=== Sv32使能条件

Sv32地址翻译的使能条件为：

```v
sv32_enabled = satp[31] && (priv_mode != M_MODE) && translate_en
```

M模式始终绕过地址翻译，直接使用物理地址作为虚拟地址（bare模式）。`translate_en`为MMU模块的顶层使能信号，由CPU核心在取指和访存阶段分别控制。

=== MMU整体架构

MMU模块（`mmu.sv`）的组成结构如下：

/*```plantuml
@startuml MMU_Architecture
skinparam componentStyle rectangle
skinparam defaultFontSize 12

package "MMU" {
  component "i-side FSM\nI_IDLE → I_LOOKUP\nI_WALK_PENDING\nI_FILL_WAIT\nI_FLUSH" as iFSM
  component "d-side FSM\nD_IDLE → D_LOOKUP\nD_WALK_PENDING\nD_FILL_WAIT\nD_FLUSH" as dFSM

  component "TLB\n(dual-port BRAM)\n4-way × 4-set = 16 entries\nTree-PLRU" as TLB {
    note right of TLB
      Port A: i-side lookup
      Port B: d-side lookup / PTW fill
    end note
  }

  component "Walk Arbiter FSM\nW_IDLE → W_D_WALK\n          → W_I_WALK" as ARB
  component "PTW\n(Page Table Walker)\n10-state FSM" as PTW
  component "Permission Check\n(combinational)" as PERM

  iFSM -down-> TLB : i_lookup_vpn/asid
  dFSM -down-> TLB : d_lookup_vpn/asid
  TLB -down-> ARB : miss
  ARB -down-> PTW : walk_req
  PTW -up-> TLB : fill (Port B write)
  PTW -right-> PERM : PTE R/W/X/U
}

component "cpu_bus_bridge\n→ AXI4 Bus" as BUS

PTW -down-> BUS : ptw_bus_req/addr/we/wdata

@enduml
```*/

#image("media/MMU架构.png",height: 80%)

PTW的总线请求通过`cpu_bus_bridge`的S\_PTW\_ADDR/S\_PTW\_DATA状态以单拍传输方式访问主存，优先级高于缓存回写和填充（详见4-cache报告中的总线桥仲裁优先级）。

=== Sv32页表漫游序列图

// ```plantuml
// @startuml Sv32_Walk_Sequence
// autonumber
// skinparam defaultFontSize 11

// participant "MMU\n(i/d-side FSM)" as MMU
// participant "Walk Arbiter" as ARB
// participant PTW
// participant "cpu_bus_bridge" as BUS
// participant "主存 (BRAM)" as MEM

// MMU -> ARB : TLB miss → walk_req
// ARB -> PTW : start walk (walk_vaddr, satp, priv)

// PTW -> BUS : ptw_bus_req (L1 PTE addr, read)
// BUS -> MEM : AXI4 AR channel
// MEM --> BUS : AXI4 R channel (L1 PTE data)
// BUS --> PTW : ptw_bus_done + rdata

// alt L1 PTE 为叶节点 (megapage)
//   PTW -> PTW : 权限检查 + A/D位检查
//   PTW --> ARB : walk_done (PPN, R/W/X/U/A/D/G)
//   ARB -> MMU : ptw_done + fill info
//   MMU -> MMU : TLB fill (Port B write)
// else L1 PTE 为非叶节点
//   PTW -> BUS : ptw_bus_req (L0 PTE addr, read)
//   BUS -> MEM : AXI4 AR channel
//   MEM --> BUS : AXI4 R channel (L0 PTE data)
//   BUS --> PTW : ptw_bus_done + rdata
//   PTW -> PTW : 权限检查 + A/D位检查
//   PTW --> ARB : walk_done
//   ARB -> MMU : ptw_done + fill info
//   MMU -> MMU : TLB fill (Port B write)
// end

// note over PTW
//   若需更新 A/D 位：
//   PTW → BUS → MEM : 写回 PTE (A=1, D=1)
//   然后才 walk_done
// end note

// @enduml
// ```

#image("media/Sv32页表漫游序列图.png")

== 统一TLB设计

TLB（Translation Lookaside Buffer）缓存最近使用的虚拟地址到物理地址的翻译结果，避免每次访存都进行页表漫游。本设计使用统一的TLB同时服务取指侧（i-side）和数据侧（d-side）。

=== BRAM组相联TLB（USE\_TLB\_BRAM=1）

当前默认配置使用BRAM实现的组相联结构，参数为4路×4组=16个表项，替换策略为Tree-PLRU。

==== 双端口BRAM结构

TLB使用两块双端口BRAM分别存储标志位和数据位：

*标志BRAM（tlb\_flag）*：128位×4深度，每路32位标志项：

```v
// flag entry packing (32-bit per way)
// [31]    : V     (valid)
// [30]    : G     (global)
// [29:21] : ASID  (9-bit)
// [20:1]  : VPN   (20-bit)
// [0]     : mega  (megapage flag)
```

*数据BRAM（tlb\_data）*：128位×4深度，每路32位数据项：

```v
// data entry packing (32-bit per way)
// [31:10] : PPN   (22-bit)
// [9]     : R
// [8]     : W
// [7]     : X
// [6]     : U
// [5]     : A
// [4]     : D
// [3:0]   : pad   (reserved)
```

端口分配：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*端口*], [*用途*], [*说明*],
  [Port A], [i-side lookup], [取指侧虚拟地址翻译，每周期查询],
  [Port B], [d-side lookup / PTW fill], [数据侧查询与PTW填充复用，PTW fill优先抢占],
)

TLB内部结构如下：

```plantuml
@startuml TLB_Structure
skinparam componentStyle rectangle
skinparam defaultFontSize 11

package "TLB (4-way × 4-set)" {
  component "tlb_flag BRAM\n128-bit × 4 deep\nTrue Dual Port" as FLAG {
    note right of FLAG
      每路 32-bit flag entry:
      {V, G, ASID[9], VPN[20], mega}
    end note
  }
  component "tlb_data BRAM\n128-bit × 4 deep\nTrue Dual Port" as DATA {
    note right of DATA
      每路 32-bit data entry:
      {PPN[22], R, W, X, U, A, D, pad[4]}
    end note
  }
  component "tree_plru\n(×2, i-side/d-side)" as PLRU
  component "shadow_valid\n[4-set][4-way]" as SHADOW

  FLAG -[hidden]- DATA
  PLRU -[hidden]- SHADOW
}

component "i-side\n(MMU Port A)" as ISIDE
component "d-side / PTW fill\n(MMU Port B)" as DSIDE

ISIDE -down-> FLAG : Port A: addra=set_idx\n→ 4路并行比较
ISIDE -down-> DATA : Port A: addra=set_idx
DSIDE -down-> FLAG : Port B: addrb=set_idx\n(web: fill写 / flush写零)
DSIDE -down-> DATA : Port B: addrb=set_idx

PLRU ..> FLAG : victim way 选择
SHADOW ..> PLRU : 无效路优先判定

@enduml
```

==== 组索引与匹配逻辑

组索引取VPN的高位，确保megapage的VPN\[9:0\]差异映射到同一组：

```v
// SET_IDX_W = 2 (4 sets)
// set_idx = VPN[SET_IDX_W + 9 : 10]  即 VPN[11:10]
```

4路并行匹配逻辑如下：

```v
// Per-way match (combinational)
wire vpn_match = mega ? (flag_vpn[19:10] == vpn[19:10])
                      : (flag_vpn == vpn);
wire way_hit[i] = flag_valid[i]
               && vpn_match[i]
               && (flag_global[i] || flag_asid[i] == current_asid);
```

megapage匹配时仅比较VPN的高10位（VPN\[19:10\]），低10位（VPN\[9:0\]）被忽略，因为megapage的PPN\[9:0\]直接来自虚拟地址。

==== 影子有效位与替换选择

BRAM的读延迟为1周期，MMU FSM管理时序。为在0周期内判断某组是否存在无效路（用于优先填充），TLB维护一组寄存器阵列`shadow_valid[way][set]`跟踪每路每组的有效状态。替换选择逻辑：

```v
// Priority: invalid way first, then Tree-PLRU victim
wire [WAY_W-1:0] fill_way = ~shadow_valid[0] ? 2'd0 :
                            ~shadow_valid[1] ? 2'd1 :
                            ~shadow_valid[2] ? 2'd2 :
                            ~shadow_valid[3] ? 2'd3 :
                            plru_victim;
```

==== 刷新（Flush）

SFENCE.VMA指令触发TLB刷新。TLB进入S\_FLUSH状态，逐组向BRAM写入零，同时清除shadow\_valid和PLRU状态。刷新完成后置`tlb_flush_done`通知MMU FSM。

=== 寄存器全相联TLB（USE\_TLB\_BRAM=0）

非BRAM回退模式使用16项全相联寄存器阵列，轮转（round-robin）替换。查找为组合逻辑，0周期延迟。结构简单但不反映真实硬件时序，主要用于早期功能验证。

== 页表漫游器（PTW）

PTW（Page Table Walker）是MMU中执行页表漫游的硬件模块（`ptw.sv`），通过总线接口直接访问主存中的页表。PTW为10状态有限状态机，完成从L1到L0的二级页表查找、权限检查和A/D位硬件管理。

=== 状态定义

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [S\_IDLE], [空闲，等待walk\_req],
  [S\_L1\_READ], [发起L1 PTE读请求，计算地址并置ptw\_bus\_req],
  [S\_L1\_CHECK], [检查L1 PTE：V=0或保留编码→S\_FAULT；叶节点→megapage→S\_PERM\_CHECK；非叶→S\_L0\_READ],
  [S\_L0\_READ], [发起L0 PTE读请求，计算地址并置ptw\_bus\_req],
  [S\_L0\_CHECK], [检查L0 PTE：V=0或保留编码→S\_FAULT；叶节点→S\_PERM\_CHECK；非叶→S\_FAULT（L0非叶为错误）],
  [S\_PERM\_CHECK], [权限检查，通过则检查A/D位],
  [S\_AD\_UPDATE], [若PTE.A=0或（store且PTE.D=0），写回PTE置A/D位],
  [S\_AD\_WAIT], [等待总线写回响应],
  [S\_DONE], [漫游完成，输出PPN+权限位],
  [S\_FAULT], [漫游失败，输出fault\_cause+vaddr],
)

=== 状态转移

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*源状态*], [*目标状态*], [*转移条件*],
  [S\_IDLE], [S\_L1\_READ], [`walk_req`有效],
  [S\_L1\_READ], [S\_L1\_CHECK], [`ptw_bus_done`（总线返回PTE数据）],
  [S\_L1\_CHECK], [S\_PERM\_CHECK], [L1 PTE为叶节点（megapage）],
  [S\_L1\_CHECK], [S\_L0\_READ], [L1 PTE为非叶节点（指向L0页表）],
  [S\_L1\_CHECK], [S\_FAULT], [L1 PTE无效或保留编码],
  [S\_L0\_READ], [S\_L0\_CHECK], [`ptw_bus_done`],
  [S\_L0\_CHECK], [S\_PERM\_CHECK], [L0 PTE为叶节点],
  [S\_L0\_CHECK], [S\_FAULT], [L0 PTE无效、保留编码或非叶节点],
  [S\_PERM\_CHECK], [S\_AD\_UPDATE], [权限通过且需更新A/D位],
  [S\_PERM\_CHECK], [S\_DONE], [权限通过且A/D位已正确],
  [S\_PERM\_CHECK], [S\_FAULT], [权限检查失败],
  [S\_AD\_UPDATE], [S\_AD\_WAIT], [下一周期（发起总线写请求）],
  [S\_AD\_WAIT], [S\_DONE], [`ptw_bus_done`（写回完成）],
  [S\_AD\_WAIT], [S\_FAULT], [`ptw_bus_error`（总线错误）],
  [S\_DONE], [S\_IDLE], [输出完成，返回空闲],
  [S\_FAULT], [S\_IDLE], [输出错误，返回空闲],
)

注：任意状态下收到`walk_abort`（sfence\_vma）均强制回到S\_IDLE。总线错误（`ptw_bus_error`）在任何等待总线响应的状态均触发S\_FAULT。

=== PTW状态机图

```plantuml
@startuml PTW_StateDiagram
skinparam defaultFontSize 11

[*] --> S_IDLE

S_IDLE --> S_L1_READ : walk_req

S_L1_READ --> S_L1_CHECK : ptw_bus_done

S_L1_CHECK --> S_PERM_CHECK : L1 PTE为叶节点\n(megapage)
S_L1_CHECK --> S_L0_READ : L1 PTE为非叶节点
S_L1_CHECK --> S_FAULT : V=0 或保留编码\n或 ptw_bus_error

S_L0_READ --> S_L0_CHECK : ptw_bus_done

S_L0_CHECK --> S_PERM_CHECK : L0 PTE为叶节点
S_L0_CHECK --> S_FAULT : V=0 / 保留 / 非叶\n或 ptw_bus_error

S_PERM_CHECK --> S_AD_UPDATE : 权限通过\n且需更新A/D位
S_PERM_CHECK --> S_DONE : 权限通过\nA/D位已正确
S_PERM_CHECK --> S_FAULT : 权限检查失败

S_AD_UPDATE --> S_AD_WAIT : 发起总线写

S_AD_WAIT --> S_DONE : ptw_bus_done
S_AD_WAIT --> S_FAULT : ptw_bus_error

S_DONE --> S_IDLE
S_FAULT --> S_IDLE

note right of S_FAULT
  任意状态收到 walk_abort
  (sfence_vma) 均强制回 S_IDLE
end note

@enduml
```

=== PTE地址计算

页表基址来自`satp.PPN`，PTE按字对齐（4字节），地址计算如下：

```v
// L1 PTE address: satp.PPN points to L1 page table base
l1_pte_addr = {satp_ppn[19:0], 12'b0}    // 页表基址（4KB对齐）
            + {20'b0, vpn1, 2'b0};        // + VPN[1] * 4

// L0 PTE address: L1 PTE's PPN points to L0 page table base
l0_pte_addr = {pte_ppn[19:0], 12'b0}     // L0页表基址
            + {20'b0, vpn0, 2'b0};        // + VPN[0] * 4
```

=== A/D位硬件管理

RISC-V规范要求硬件在首次访问时置A位、首次写入时置D位。PTW在S\_PERM\_CHECK状态检查A/D位，若需更新则进入S\_AD\_UPDATE写回：

```v
// A/D bit update logic
wire need_ad_update = (~pte_access)                       // A=0: 首次访问
                   || (is_store && ~pte_dirty);            // D=0: 首次写入

// Write-back PTE value
ptw_wdata = {pte_ppn, pte_rsw, 2'b00,                     // 保持G/U/X/W/R/V
             (pte_dirty | is_store),                       // D = D | store
             1'b1,                                         // A = 1 (always set)
             pte_g, pte_u, pte_x, pte_w, pte_r, 1'b1};    // V = 1
```

A/D位写回通过PTW总线请求完成，绕过dcache直接访问主存，避免缓存一致性问题。

== 权限检查机制

权限检查在PTW的S\_PERM\_CHECK状态以组合逻辑完成，依据PTE的R/W/X/U位、当前特权级和mstatus的MXR/SUM位判定访问是否合法。

=== 访问权限规则

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*访问类型*], [*权限要求*],
  [Fetch（取指）], [PTE.X = 1],
  [Load（读）], [PTE.R = 1，或（PTE.X = 1 且 mstatus.MXR = 1）],
  [Store/AMO（写）], [PTE.W = 1],
  [U模式访问], [PTE.U = 1],
  [S模式访问], [PTE.U = 0，除非（mstatus.SUM = 1 且为Load访问）],
)

MXR（Make eXecutable Readable）位允许S模式将可执行页也视为可读。SUM（Supervisor User Memory access）位允许S模式访问U模式页面（仅限Load，Store/AMO仍禁止）。

=== Megapage对齐检查

megapage要求PPN\[9:0\]全为0，即PPN必须4MB对齐。若megapage的PPN\[9:0\]非零，产生权限错误（permission fault），防止物理地址空间出现重叠映射。

=== 页错误原因映射

权限检查失败时，根据访问类型映射到不同的异常cause码：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*访问类型*], [*cause*], [*异常名称*],
  [Fetch], [12], [指令页错误（instruction page fault）],
  [Load], [13], [加载页错误（load page fault）],
  [Store/AMO], [15], [存储页错误（store/AMO page fault）],
)

页错误信息（fault\_cause和fault\_vaddr）由PTW传递给MMU，再由MMU传递给CPU的trap manager，最终写入mcause/scause和mtval/stval。

== 漫游仲裁器（Walk Arbiter）

MMU中只有一个PTW实例，由取指侧和数据侧共享。漫游仲裁器（Walk Arbiter）管理两侧对PTW的访问，避免并发冲突。

=== 仲裁器状态机

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [W\_IDLE], [空闲，检查挂起请求：d\_walk\_req优先，其次i\_walk\_req],
  [W\_D\_WALK], [d-side漫游进行中；若i-side缺失到达，置pending\_i\_walk],
  [W\_I\_WALK], [i-side漫游进行中；若d-side缺失到达，置pending\_d\_walk],
)

=== 仲裁策略

#move(dx: 2em)[
  + *d-side优先*：W\_IDLE状态下若两侧同时请求，d-side先获得PTW使用权。数据访存的正确性优先于取指，因为取指侧可以停顿流水线等待
  + *挂起队列*：当一侧正在漫游时，另一侧的缺失请求通过`pending_i_walk`/`pending_d_walk`标志排队。当前漫游完成后，W\_IDLE检查挂起标志再接受新请求
  + *SFENCE.VMA清除*：sfence\_vma清除所有挂起标志并强制仲裁器回到W\_IDLE，正在进行的漫游被PTW的walk\_abort信号中止
]

=== i-side与d-side FSM

取指侧和数据侧各自维护独立的FSM管理TLB查找和漫游等待：

*i-side FSM*：

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [I\_IDLE], [空闲，等待取指请求],
  [I\_LOOKUP], [TLB查找（BRAM读1周期），判断命中/缺失],
  [I\_WALK\_PENDING], [TLB缺失，等待仲裁器分配PTW],
  [I\_FILL\_WAIT], [PTW漫游完成，等待TLB填充],
  [I\_FLUSH], [SFENCE.VMA刷新TLB，等待tlb\_flush\_done],
)

*d-side FSM*：

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [D\_IDLE], [空闲，等待访存请求],
  [D\_LOOKUP], [TLB查找（BRAM读1周期），判断命中/缺失],
  [D\_WALK\_PENDING], [TLB缺失，等待仲裁器分配PTW],
  [D\_FILL\_WAIT], [PTW漫游完成，等待TLB填充],
  [D\_FLUSH], [SFENCE.VMA刷新TLB，等待tlb\_flush\_done],
)

=== 输入变化检测

当虚拟地址、特权级或satp在查找过程中发生变化时，必须重新发起TLB查找。MMU通过`i_input_changed`/`d_input_changed`信号检测输入变化，在LOOKUP或WALK\_PENDING状态触发回退到IDLE重新查找。

d-side的`d_translate_en`门控确保仅在`mem_en=1`时锁存输入并推进FSM，防止无访存请求时输入信号振荡导致误触发（BUG-13修复）。

=== 漫游仲裁器状态图

```plantuml
@startuml Walk_Arbiter_StateDiagram
skinparam defaultFontSize 11

[*] --> W_IDLE

W_IDLE --> W_D_WALK : pending_d_walk\n或 d_walk_req（优先）
W_IDLE --> W_I_WALK : pending_i_walk\n或 i_walk_req

W_D_WALK --> W_IDLE : ptw_walk_done\n或 ptw_walk_fault
W_I_WALK --> W_IDLE : ptw_walk_done\n或 ptw_walk_fault

note right of W_D_WALK
  若 i-side miss 到达：
  置 pending_i_walk = 1
end note

note left of W_I_WALK
  若 d-side miss 到达：
  置 pending_d_walk = 1
end note

note bottom of W_IDLE
  sfence_vma：清除所有
  pending 标志
end note

@enduml
```

=== i-side与d-side FSM状态图

```plantuml
@startuml Side_FSM_StateDiagram
skinparam defaultFontSize 11

title i-side / d-side FSM（结构对称，以 i-side 为例）

[*] --> I_IDLE

I_IDLE --> I_LOOKUP : 锁存 vaddr/priv/satp
I_LOOKUP --> I_WALK_PENDING : sv32 && !tlb_hit\n(TLB 缺失)
I_LOOKUP --> I_IDLE : input_changed\n(输入变化，重新查找)
I_WALK_PENDING --> I_FILL_WAIT : ptw_done_for_i\n(PTW 漫游完成)
I_WALK_PENDING --> I_IDLE : ptw_fault_for_i\n(页错误)
I_FILL_WAIT --> I_IDLE : TLB 填充完成\n(重新发起查找)

I_IDLE --> I_FLUSH : sfence_vma
I_LOOKUP --> I_FLUSH : sfence_vma
I_WALK_PENDING --> I_FLUSH : sfence_vma
I_FLUSH --> I_IDLE : tlb_flush_done

note right of I_LOOKUP
  i_ready 有效条件：
  sv32=0 (bare) 或
  (tlb_hit && !perm_fault)
end note

@enduml
```

== MMU与缓存的交互

MMU与icache\_ctrl和dcache\_ctrl通过物理地址和就绪信号交互，缓存控制器的设计细节（FSM状态、VIPT、替换策略等）已在4-cache报告中详述，此处仅描述MMU与缓存的接口关系。

=== 接口信号

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*信号*], [*方向*], [*说明*],
  [`i_paddr`], [MMU→icache], [取指侧翻译后的物理地址],
  [`i_ready`], [MMU→icache], [取指侧翻译就绪（命中或漫游完成）],
  [`i_page_fault`], [MMU→icache], [取指侧页错误标志],
  [`d_paddr`], [MMU→dcache], [数据侧翻译后的物理地址],
  [`d_ready`], [MMU→dcache], [数据侧翻译就绪],
  [`d_page_fault`], [MMU→dcache], [数据侧页错误标志],
)

=== 交互流程

```plantuml
@startuml MMU_Cache_Interaction
skinparam defaultFontSize 11
skinparam componentStyle rectangle

package "icache_ctrl" {
  component "S_TAG_READ\n等待 i_ready" as ICACHE
}
package "dcache_ctrl" {
  component "S_TAG_READ\n等待 d_ready" as DCACHE
}
package "MMU" {
  component "i-side FSM" as IMMU
  component "d-side FSM" as DMMU
  component "TLB" as TLB
  component "PTW" as PTW
}
component "trap_manager" as TRAP

ICACHE -down-> IMMU : i_vaddr
IMMU --> ICACHE : i_paddr (命中)\ni_ready / i_page_fault

DCACHE -down-> DMMU : d_vaddr, d_access_type
DMMU --> DCACHE : d_paddr (命中)\nd_ready / d_page_fault

IMMU -down-> TLB : i-side lookup (Port A)
DMMU -down-> TLB : d-side lookup (Port B)
TLB -down-> PTW : miss → walk_req

IMMU -down-> TRAP : i_page_fault\ni_pf_cause, i_pf_vaddr
DMMU -down-> TRAP : d_page_fault\nd_pf_cause, d_pf_vaddr

note right of TLB
  MMIO 旁路：
  vaddr[31]==0 → 不经过 MMU
  直接使用虚拟地址
end note

@enduml
```

#move(dx: 2em)[
  + *正常命中*：icache\_ctrl/dcache\_ctrl在S\_TAG\_READ状态等待`i_ready`/`d_ready`有效后使用`i_paddr`/`d_paddr`进行tag比较
  + *TLB缺失*：MMU发起PTW漫游，缓存控制器停留在S\_TAG\_READ等待`mmu_ready`。漫游期间流水线停顿
  + *页错误*：`i_page_fault`/`d_page_fault`传递给CPU的trap manager，触发陷阱处理，缓存控制器回到S\_IDLE
  + *MMIO访问*：MMU不参与MMIO地址翻译（MMIO地址使用虚拟地址最高位判断，直接旁路）
]

== SFENCE.VMA与FENCE.I指令

=== SFENCE.VMA

SFENCE.VMA是RISC-V特权指令，用于刷新TLB和同步页表修改。本设计的处理流程：

#move(dx: 2em)[
  + CPU执行SFENCE.VMA后向MMU发送`sfence_vma`信号
  + MMU的i-side和d-side FSM分别进入I\_FLUSH和D\_FLUSH状态
  + TLB执行全表刷新：逐组写零清除BRAM，清除shadow\_valid和PLRU状态
  + PTW若正在漫游，收到`walk_abort`信号强制回到S\_IDLE
  + 漫游仲裁器清除`pending_i_walk`和`pending_d_walk`标志，回到W\_IDLE
  + 刷新完成后`tlb_flush_done`有效，MMU FSM回到IDLE
  + 同时触发icache无效化（所有tag清零），确保取指使用刷新后的翻译结果
]

=== FENCE.I

FENCE.I指令确保指令存储一致性，用于自修改代码场景。处理流程：

#move(dx: 2em)[
  + *dcache冲刷*：dcache\_ctrl进入冲刷路径（S\_FLUSH\_SCAN → S\_FLUSH\_CHECK → S\_FLUSH\_WB\_RD → S\_FLUSH\_WB\_SD → S\_FLUSH\_INVALIDATE），写回所有脏行后无效化全部缓存行
  + *icache无效化*：icache\_ctrl进入S\_INVALIDATE状态，逐组向tag BRAM写零清除所有有效位
  + 冲刷完成后，新的取指将从主存重新加载指令，保证看到之前写入的修改
]

= 项目验证

== 仿真验证

我们编写了12个MMU专项测试和3个特权级测试，仿真全部通过。

通过命令

```sh
python -m tools.vivado_cli -batch \
"mmu_sv32_basic,mmu_sv32_edge,mmu_ptw_walk,\
mmu_tlb_basic,mmu_tlb_flush,mmu_tlb_asid,\
mmu_tlb_megapage,mmu_tlb_replace,mmu_tlb_stress,\
mmu_permission,mmu_page_fault,mmu_unified_mmu" -create -sim
```

可以批量进行MMU仿真。

详细测试如下：

=== mmu\_sv32\_basic

Sv32基本翻译测试，验证4KB普通页和4MB大页的地址翻译正确性。

=== mmu\_sv32\_edge

Sv32边界条件测试，验证页表首尾项、地址空间边界、全零/全一PTE等极端情况。

=== mmu\_ptw\_walk

PTW页表漫游测试，验证二级页表遍历、非叶节点跳转、PTE无效/保留编码检测、总线错误处理。

=== mmu\_tlb\_basic

TLB基本功能测试，验证翻译结果缓存、命中/缺失判定、物理地址输出正确性。

=== mmu\_tlb\_flush

TLB刷新测试（SFENCE.VMA），验证刷新后所有表项无效、后续访问重新触发漫游。

=== mmu\_tlb\_asid

TLB ASID感知测试，验证不同ASID的同VPN映射独立、ASID切换后旧映射不命中。

=== mmu\_tlb\_megapage

TLB大页匹配测试，验证megapage的VPN\[9:0\]忽略匹配、PPN拼接正确性、对齐检查。

=== mmu\_tlb\_replace

TLB替换策略测试，验证4路填满后Tree-PLRU替换、无效路优先填充。

=== mmu\_tlb\_stress

TLB压力测试，大量不同VPN连续访问，验证替换正确性和无死锁。

=== mmu\_permission

页表权限检查测试，验证R/W/X/U位、MXR/SUM位、S/U模式访问控制、megapage对齐检查。

=== mmu\_page\_fault

页错误测试，验证各种权限违反场景下正确的fault\_cause和fault\_vaddr输出。

=== mmu\_unified\_mmu

统一MMU测试，验证i-side和d-side并发访问、漫游仲裁器优先级、挂起队列正确性。

=== 特权级测试

此外还有3个特权级相关测试：

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*测试名*], [*功能*],
  [privilege\_csr\_access\_priv], [CSR特权访问测试，验证M/S/U模式对CSR的读写权限],
  [privilege\_delegation], [陷阱委托测试，验证medeleg/mideleg的异常/中断委托到S模式],
  [privilege\_priv\_transition], [特权级转换测试，验证M↔S↔U模式切换和mret/sret返回],
)

=== 回归测试

针对调试过程中发现的时序问题，我们编写了6个回归测试：

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*测试名*], [*功能*],
  [reg\_bare\_no\_miss], [裸机无缺失回归，验证bare模式下TLB不产生缺失],
  [reg\_mmio\_ready], [MMIO ready时序回归，验证MMIO旁路时ready信号时序],
  [reg\_pf\_latch], [页错误锁存回归，验证页错误信号正确锁存不被覆盖],
  [reg\_ptw\_fault\_latch], [PTW错误锁存回归，验证PTW fault信号在FSM中正确保持],
  [reg\_sfence\_during\_walk], [漫游中SFENCE回归，验证漫游进行中收到sfence\_vma时正确中止],
  [reg\_stale\_paddr], [过期物理地址回归，验证输入变化检测防止使用过期翻译结果],
  [reg\_tlb\_fill\_way], [TLB填充路选择回归，验证PTW填充时正确选择替换路],
)

== 上板验证

我们在FPGA上运行`privilege`测试程序和`uart_echo`程序进行上板验证。privilege测试覆盖了M/S/U三级特权模式切换、CSR访问权限、陷阱委托和页错误处理。uart_echo测试验证了在Sv32虚拟内存使能的情况下，用户程序通过系统调用访问UART外设的完整流程。

= 总结

本次实验我们成功实现了完整的Sv32页式虚拟内存体系，主要成果包括：

#move(dx: 2em)[
  + *Sv32二级页表虚拟内存*：支持4KB普通页和4MB大页，M模式bare模式直通
  + *统一TLB*：BRAM实现4路×4组组相联结构，双端口服务i-side和d-side，Tree-PLRU替换
  + *硬件页表漫游器*：10状态FSM完成二级页表遍历，含A/D位硬件管理
  + *M/S/U三级特权*：支持陷阱委托（medeleg/mideleg），S模式独立页表（satp）
  + *权限检查*：完整实现R/W/X/U位检查，支持MXR和SUM扩展
  + *漫游仲裁器*：单PTW实例共享，d-side优先，挂起队列保证公平性
  + *SFENCE.VMA与FENCE.I*：TLB刷新、PTW中止、缓存一致性维护
]

= 文件说明

提交的文件中除了本报告，`cpu-源码以及工具5.zip`是项目开发文件夹，`simplecpu_soc.xpr.zip`是vivado工程文件夹。其中项目开发文件夹中所有源代码均在`dev`下，测试程序和应用在`dev/program_source`下，硬件设计见`dev/rtl`；工具在`tools`下。

= 组员以及分工

#table(
  columns: (1fr, 2fr, 2fr),
  align: horizon,
  [*姓名*], [*学号*], [*分工*],
  [王之翼], [320240944621], [构建],
  [陈海攀], [320230904051], [测试、DEBUG],
  [张潘妍], [320240944910], [c程序、riscv汇编交叉编译],
  [张之恒], [320240944971], [资料查找、文档整理],
)
