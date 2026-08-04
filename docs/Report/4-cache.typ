// 计算机组成原理实验报告模板（Typst）
#set title("高速缓存设计实验报告")
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
  + 实现高速缓存（使用BRAM）到主存的映射
  + 实现缓存和主存之间的交换算法
]

== 当前实现的特性

#move(dx: 2em)[
  + i/d缓存、主存均使用BRAM IP
  + 缓存：四路组相连，8组，数据区行大小：256bit，总共1KB（每个cache）
  + 主存：32B一块，总共32KB（地址宽15bit，tag宽7bit）
  + 替换策略：Tree-PLRU （树基最近最少用算法）
  + 缓存数据区和标签区分离，icache有使能位，无脏位，dcache均有
  + 采用写回策略
]

详细参数见#link(<BRAM-yaml>)[BRAM IP和存储参数]小节。

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
  + 特权架构规范：#link("https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf")[riscv-privileged.pdf]
  + 平台级中断控制器：#link("https://docs.riscv.org/reference/plic/_attachments/riscv-plic.pdf")[riscv-plic.pdf]
  + tree-PLRU算法：#link("https://people.computing.clemson.edu/~mark/464/p_lru.txt")[p_lru.txt]
]

= 实现细节

备注：由于误判项目验收时间，我们实验4和5是同时进行的，没有单独的实验4的稳定版本，因此本实验的附件中代码是完整实验5完成后的代码。但是实验5本就是实验4的后续，因此当前代码中可以看见实验4的实现。

== 缓存存储参数<BRAM-yaml>

IP配置表如下：
```yaml
  i/dcache-d:             # 数据区
    num_sets: 8           # 8组
    num_ways: 4           # 4路
    line_words: 8         # 缓存行8B（以机器字32bit计算）
    tag_bram_byte_enable: true   # IP：字节写开启
    tag_bram_byte_size: 8        # 8宽字节

  icache-t:               # 标签区
    tag_width: 7          # 7宽tag
    v: true               # 使能位，有
    d: false              # 脏位，无
    ip_width: 32          # 4*8=32，即一行存储一组的标签位
    ip_depth: 8           # 共8行，对应8组
    tag_bram_byte_enable: true   # IP：字节写开启
    tag_bram_byte_size: 8        # 8宽字节

  dcache-t:               # 标签区
    tag_width: 7          # 7宽tag
    v: true               # 使能位，有
    d: true               # 脏位，有
    ip_width: 36          # 4*9=36，即一行存储一组的标签位
    ip_depth: 8           # 共8行，对应8组
    tag_bram_byte_enable: true   # IP：字节写开启
    tag_bram_byte_size: 9        # 9宽字节
```

如上，我们将数据和标签区分离，且标签区一行存储一组的标签，实现了快速存取标签，以满足缓存的tag比较速度。

== 内存映射模型<mmap>

在内存布局上，我们参考了QEMU riscv virt机器的内存映射模型，改造后完成了我们的模型：

#table(
  columns: (auto, auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*地址范围*], [*大小*], [*设备/区域*], [*说明*],
  [0x0200_0000 - 0x0200_FFFF], [64 KB], [CLINT], [核心本地中断器，提供mtime/Timer中断],
  [0x0C00_0000 - 0x0C2F_FFFF], [3 MB], [PLIC], [平台级中断控制器，管理外设全局中断],
  [0x1000_0000 - 0x1000_3FFF], [1 KB], [GPIO], [GPIO，连在LED],
  [0x1000_4000 - 0x1000_7FFF], [1 KB], [Timer], [外设计时器],
  [0x1000_8000 - 0x1000_BFFF], [1 KB], [UART], [UART],
  [0x1000_C000 - 0x1000_FFFF], [1 KB], [SPI], [未使用],
  [0x8000_0000 - 0xFFFF_FFFF], [2 GB], [DRAM (RAM)], [主内存区域],
)

== 回写策略和交换算法

回写策略上我们采用写回策略，即每次缓存未命中时会把目标内存块读取到缓存，以达到缓存加速的效果。

每次写回缓存时先选择无效路填充，若没有则使用tree-PLRU算法进行替换。

=== 树基最近最少用算法（tree-PLRU）

树基最近最少用算法是一种伪LRU算法，我们没有用LRU的原因是其需要的标志位太多，每组需要7位，而tree-PLRU每组只需要三位。

tree-PLRU算法的核心是通过二叉树指向每路，每标志位将路划分为两组，当此路被访存时则将指向逆转，指向对向路，通过标志位来保留使用的先后顺序。

示意图和转换表见下：
```txt
             bit_0 == 0?
              /       \
             y         n
            /           \
     bit_1 == 0?    bit_2 == 0?
       /    \          /    \
      y      n        y      n
     /        \      /        \
   line_0  line_1  line_2  line_3

   state | replace      ref to | next state
   ------+--------      -------+-----------
   00x   |  line_0      line_0 |    11_
   01x   |  line_1      line_1 |    10_
   1x0   |  line_2      line_2 |    0_1
   1x1   |  line_3      line_3 |    0_0
   ('x' means         ('_' means unchanged)
     don't care)
```

我们声明了一个模块来实现转换，以加强复用性，关键代码如下：

```v
    always @(*) begin
        case (access_way)
            2'd0: next_state_r = {1'b1, 1'b1, plru_state[2]};
            2'd1: next_state_r = {1'b1, 1'b0, plru_state[2]};
            2'd2: next_state_r = {1'b0, plru_state[1], 1'b1};
            2'd3: next_state_r = {1'b0, plru_state[1], 1'b0};
            default: next_state_r = plru_state;
        endcase
    end
```

我们的缓存控制器（`icache_ctrl.sv`和`dcache_ctrl.sv`）中实例化了两个`tree_plru`模块，一个面对cpu访存，一个面对内存回写，分离以简化控制逻辑和避免时序复杂度。

```v
    wire [WAY_W-1:0] plru_victim;
    wire [NUM_WAYS-2:0] plru_next;
    tree_plru u_plru(
        .plru_state (plru_state[set_idx]),
        .victim_way (plru_victim),
        .access_way (hit_way),
        .next_state (plru_next)
    );

    wire [WAY_W-1:0] victim_way = inv0 ? {WAY_W{1'b0}} :
                            inv1 ? {{(WAY_W-1){1'b0}}, 1'b1} :
                            inv2 ? {{(WAY_W-2){1'b0}}, 2'b10} :
                            inv3 ? {{(WAY_W-2){1'b0}}, 2'b11} :
                            plru_victim;
```

如上：通过tree-PLRU选择受害者路的关键代码片段。

```v
    wire [NUM_WAYS-2:0] plru_next_miss;
    tree_plru u_plru_miss(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (latched_victim_way),
        .next_state (plru_next_miss)
    );
```

如上，面向主存的回写的tree-PLRU硬件。

== 缓存控制器<dcache-ctrl>

dcache的缓存控制器（`dcache_ctrl.sv`）采用有限状态机实现，管理数据缓存的全部操作：命中判断、缺失处理（含脏行回写与行填充）、MMIO旁路、以及缓存冲刷（fence.i）。控制器共包含11个状态，可分为正常访存路径和冲刷路径两组。

=== 状态定义

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [S_IDLE], [空闲，等待CPU访存请求或冲刷请求],
  [S_TAG_READ], [标签BRAM读取，等待MMU就绪后进行tag比较],
  [S_READ_HIT], [读命中，从数据BRAM读出目标字，更新PLRU],
  [S_WB_READ], [缺失且受害者脏——从数据BRAM读出脏行],
  [S_WB_SEND], [将脏行发送至主存回写，等待`wb_valid`],
  [S_REFILL], [从主存填充新行到数据BRAM和标签BRAM，更新PLRU],
  [S_FLUSH_SCAN], [冲刷：发起标签BRAM读取（扫描当前组）],
  [S_FLUSH_CHECK], [冲刷：判断当前路是否有效且脏],
  [S_FLUSH_WB_RD], [冲刷回写：从数据BRAM读出脏行数据],
  [S_FLUSH_WB_SD], [冲刷回写：将脏行发送至主存],
  [S_FLUSH_INVALIDATE], [冲刷无效化：逐组写零清除所有有效位和PLRU状态],
)

=== 状态转移

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*源状态*], [*目标状态*], [*转移条件*],
  [S_IDLE], [S_TAG_READ], [`cpu_req_valid && !is_mmio`],
  [S_IDLE], [S_IDLE], [MMIO单周期旁路（`mmio_valid`）],
  [S_IDLE], [S_FLUSH_SCAN], [`flush_req`],
  [S_TAG_READ], [S_TAG_READ], [`!mmu_ready`（等待MMU）],
  [S_TAG_READ], [S_READ_HIT], [读命中（`cache_hit && !hwrite`）],
  [S_TAG_READ], [S_IDLE], [写命中（单周期完成）],
  [S_TAG_READ], [S_WB_READ], [缺失且受害者脏],
  [S_TAG_READ], [S_REFILL], [缺失且受害者干净],
  [S_READ_HIT], [S_IDLE], [数据读取完成],
  [S_WB_READ], [S_WB_SEND], [下一周期],
  [S_WB_SEND], [S_REFILL], [`wb_valid`（回写完成）],
  [S_REFILL], [S_IDLE], [`refill_valid`（填充完成）],
  [S_FLUSH_SCAN], [S_FLUSH_CHECK], [下一周期],
  [S_FLUSH_CHECK], [S_FLUSH_WB_RD], [当前路有效且脏],
  [S_FLUSH_CHECK], [S_FLUSH_CHECK], [不脏，同组下一路（BRAM输出仍有效）],
  [S_FLUSH_CHECK], [S_FLUSH_SCAN], [不脏，末路则推进下一组],
  [S_FLUSH_CHECK], [S_FLUSH_INVALIDATE], [所有组路扫描完毕],
  [S_FLUSH_WB_RD], [S_FLUSH_WB_SD], [下一周期],
  [S_FLUSH_WB_SD], [S_FLUSH_SCAN], [`wb_valid`，继续扫描],
  [S_FLUSH_WB_SD], [S_FLUSH_INVALIDATE], [`wb_valid`，全部处理完],
  [S_FLUSH_INVALIDATE], [S_IDLE], [无效化完成],
  [S_FLUSH_INVALIDATE], [S_FLUSH_INVALIDATE], [逐组写零（未完成）],
)

注：S\_TAG\_READ 的所有出口转移（除自环外）均需 `mmu_ready` 有效，以确保物理地址就绪后才进行tag比较。

=== FSM示意图<fsm-diagram>

图中缩写：TAG\_RD = S\_TAG\_READ，\RD\_HIT = S\_READ\_HIT，WB\_RD = S\_WB\_READ，WB\_SD = S\_WB\_SEND，F\_SCAN = S\_FLUSH\_SCAN，F\_CHK = S\_FLUSH\_CHECK，F\_WB\_RD = S\_FLUSH\_WB\_RD，F\_WB\_SD = S\_FLUSH\_WB\_SD，F\_INV = S\_FLUSH\_INVALIDATE。

图中左侧是正常访存路径右侧为冲刷路径。

#image("media/cache_ctrl_FSM.svg")

图中自环箭头分别表示：IDLE→IDLE（MMIO旁路）、TAG\_RD→TAG\_RD（等待`mmu_ready`）、F\_INV→F\_INV（逐组写零）。此外，F\_CHK在同组内推进下一路时亦保持本状态（BRAM输出仍有效），因视觉简洁未单独绘出。

=== 关键设计要点

#move(dx: 2em)[
  + *VIPT（虚拟索引物理标签）*：使用虚拟地址的页偏移内位作为组索引（VIPT），物理地址的高位作为tag。在S\_TAG\_READ状态需等待MMU就绪（`mmu_ready`）后才进行tag比较，避免使用过时的物理地址。

  + *MMIO旁路*：通过检测虚拟地址最高位`vaddr[31]==0`判断MMIO访问。MMIO请求在S\_IDLE状态直接旁路处理，不进入FSM主路径，单周期完成（等待`mmio_valid`）。

  + *双端口BRAM并行*：标签BRAM和数据BRAM均使用双端口——Port A面向CPU侧（正常读/写），Port B面向内存侧（回写/填充）。两端操作可并行，例如CPU读命中与回写可同时进行。

  + *写命中单周期完成*：dcache支持写命中时直接写入数据BRAM并置脏位，单周期从S\_TAG\_READ返回S\_IDLE。支持字节（BYTE）和半字（HWORD）写操作，通过字节写使能（WEA）实现部分写入。

  + *缺失处理流程*：缺失时优先选择无效路填充，若无无效路则使用tree-PLRU选择受害者。若受害者脏则先回写（S\_WB\_READ → S\_WB\_SEND），再填充（S\_REFILL）；若干净则直接填充。填充时若原请求为写，则将写数据合并到填充行中（merge逻辑）。

  + *冲刷（fence.i）*：冲刷时遍历所有8组×4路=32个缓存行，对脏行进行回写，最后逐组写零清除所有有效位和PLRU状态。冲刷路径与正常访存路径由FSM互斥保证。

  + *与icache控制器差异*：dcache比icache复杂，主要增加：脏位管理、写命中单周期写入、MMIO旁路、字节/半字写使能、冲刷路径中的脏行回写。icache为只读缓存，无脏位、无写命中、无MMIO旁路。
]


== AHB-Lite总线升级

由于Sram使用的IP配置位宽为32宽，要一次性传输256宽的内存块需要8次，为此我们优化了系统总线，增加了INCR8突发传输支持，使数据传输的速度加快。

根据AHB-lite的标准，突发地址递增是主设备负责计算，即当前的cpu到总线桥进行计算，而起始点地址由缓存控制器计算。

=== 总线桥状态机

`cpu_bus_bridge`是系统中唯一的AHB-Lite主设备，采用11状态FSM管理所有总线操作。每种操作均由地址相（ADDR）和数据相（DATA）配对组成；MMIO和PTW为单拍传输，缓存回写/填充为INCR8突发传输。

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [S_IDLE], [空闲，仲裁各请求源],
  [S_MMIO_ADDR], [MMIO单拍传输地址相：HTRANS=NONSEQ, HBURST=SINGLE],
  [S_MMIO_DATA], [MMIO单拍传输数据相：等待HREADY后返回S\_IDLE],
  [S_IREFILL_ADDR], [icache填充突发地址相：HTRANS=NONSEQ, HBURST=INCR8, HWRITE=0],
  [S_IREFILL_DATA], [icache填充突发数据相：逐拍收集HRDATA至refill\_shift\_reg],
  [S_DREFILL_ADDR], [dcache填充突发地址相：HTRANS=NONSEQ, HBURST=INCR8, HWRITE=0],
  [S_DREFILL_DATA], [dcache填充突发数据相：逐拍收集HRDATA至refill\_shift\_reg],
  [S_WB_ADDR], [dcache写回突发地址相：HTRANS=NONSEQ, HBURST=INCR8, HWRITE=1],
  [S_WB_DATA], [dcache写回突发数据相：逐拍发送wb\_shift\_reg至HWDATA],
  [S_PTW_ADDR], [页表漫步地址相：HTRANS=NONSEQ, HBURST=SINGLE],
  [S_PTW_DATA], [页表漫步数据相：等待HREADY后返回S\_IDLE],
)

#image("media/bus_bridge_fsm.svg")

=== INCR8突发传输机制

突发传输的关键硬件如下：

#move(dx: 2em)[
  + *节拍计数器* `beat_cnt`（3位）：从0计数至7，`last_beat = (beat_cnt == 7)`
  + *突发基址* `burst_base_addr`（32位）：在ADDR相锁存缓存控制器提供的起始地址
  + *地址递增*：后续拍地址 = `burst_base_addr + (beat_cnt + 1) * 4`，由主设备计算
  + *填充移位寄存器* `refill_shift_reg`（256位）：读突发时逐拍按`beat_cnt`索引写入`HRDATA[beat_cnt*32 +: 32]`
  + *写回移位寄存器* `wb_shift_reg`（256位）：写突发时在ADDR相加载`dcache_wb_data`，逐拍右移32位输出至`HWDATA`
]

icache填充突发的时序如下：

```txt
时间线 (每个 HCLK 上升沿):
─────────────────────────────────────────────────────────────

[icache_ctrl]  S_TAG_READ → miss → 发出 refill_req + refill_addr
                                    │
[cpu_bus_bridge]  S_IDLE 收到 icache_refill_req
                  │
                  ├─ S_IREFILL_ADDR ────────────────────────
                  │  • HADDR  = icache_refill_addr (cache line 起始地址)
                  │  • HTRANS = NONSEQ          ← 突发第一拍
                  │  • HBURST = INCR8
                  │  • HWRITE = 0 (读)
                  │  • HSIZE  = WORD (32-bit)
                  │  • beat_cnt = 0
                  │  等待 HREADY...
                  │
                  ├─ S_IREFILL_DATA (beat 0) ──────────────
                  │  • HTRANS = SEQ             ← 突发后续拍
                  │  • HADDR  = burst_base + 4  ← 地址自动递增
                  │  • HRDATA → refill_shift_reg[31:0]
                  │  • beat_cnt = 0 → 检查 last_beat? No
                  │
                  ├─ S_IREFILL_DATA (beat 7) ──────────────
                  │  • HTRANS = SEQ
                  │  • HADDR  = burst_base + 28
                  │  • HRDATA → refill_shift_reg[255:224]
                  │  • beat_cnt = 7 → last_beat = TRUE
                  │  • icache_refill_valid = 1  ← 通知 icache_ctrl
                  │  • HTRANS = IDLE            ← 突发结束
                  │
[icache_ctrl]  S_REFILL → refill_valid=1
               │  • 整行 256-bit refill_shift_reg 写入 Data BRAM
               │  • 更新 Tag BRAM (V=1, tag)
               │  • 返回请求 word 给 CPU
               └─ S_IDLE
```

dcache写回突发与填充类似，区别在于`HWRITE=1`，数据方向相反：`wb_shift_reg`在ADDR相加载整行256位脏数据，DATA相逐拍右移32位输出至`HWDATA`。

=== 请求仲裁优先级

S\_IDLE状态下按固定优先级链仲裁各请求源：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*优先级*], [*请求*], [*说明*],
  [1（最高）], [icache MMIO], [单拍外设访问，避免I/O被长突发阻塞],
  [2], [dcache MMIO], [同上，数据侧MMIO],
  [3], [PTW页表漫步], [必须在缓存缺失重试前完成],
  [4], [dcache写回], [脏行回写优先于填充（dcache\_ctrl需先回写再填充）],
  [5], [icache填充], [指令取指优先于数据取指，减少流水线停顿],
  [6（最低）], [dcache填充], [数据填充],
)

每个请求以`!xxx_valid_r`门控，防止重复服务已完成请求。突发一旦开始即运行至完成，不可抢占。

=== 总线互连

#image("media/bus_topology.svg")

`ahb_lite_bus`通过`HADDR[31:24]`地址解码将主设备请求分发至5个从设备，响应多路选择器`ahb_mux`在`HREADY=1`时锁存`HSELx`以正确处理流水线突发数据相。主存从设备`ahb_sram_slave`的BRAM读延迟为1周期。

== 中断和异常支持

本设计实现了RISC-V特权架构规范中的M陷阱机制，包括CLINT本地中断、PLIC外部中断、同步异常检测以及完整的CSR硬件更新。

=== 中断源架构

#image("media/interrupt_arch.svg")

系统中断源由CLINT和PLIC提供，均作为AHB-Lite从设备挂载在系统总线上，通过专用信号线将中断挂起标志传入CPU核心。

=== CLINT核心本地中断器

CLINT（`ahb_clint`）提供两种机器态中断：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*中断*], [*信号*], [*机制*],
  [软件中断], [`msip`], [对`msip`寄存器bit0写1触发，写0清除；输出`o_msip`],
  [计时器中断], [`mtip`], [`mtime`自由运行计数器每周期+1；当`mtime ≥ mtimecmp`且`mtimecmp ≠ 0`时置位`o_mtip`],
)

CLINT寄存器映射（基址`0x0200_0000`）：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*寄存器*], [*说明*],
  [`0x00`], [mtimecmp\_lo], [比较值低32位],
  [`0x04`], [mtimecmp\_hi], [比较值高32位],
  [`0x08`], [mtime\_lo], [计时器低32位（可读写）],
  [`0x0C`], [mtime\_hi], [计时器高32位（可读写）],
  [`0x10`], [msip], [软件中断挂起位（仅bit0有效）],
)

=== PLIC平台级中断控制器

PLIC（`ahb_plic`）管理8个外部中断源（源0保留），实现优先级仲裁和Claim/Complete握手协议。

*中断源分配*（在`ahb_lite_bus`中硬连线）：

#table(
  columns: (auto, auto),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*源ID*], [*设备*],
  [0], [保留],
  [1], [APB Timer],
  [2], [UART],
  [3], [SPI],
  [4], [GPIO],
  [5--7], [保留],
)

PLIC寄存器映射（基址`0x0C00_0000`）：

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*寄存器*],
  [`0x000000`--`0x00001C`], [优先级寄存器 `prio[1]`--`prio[7]`],
  [`0x000400`], [挂起位图 `pending`（32位）],
  [`0x000800`], [使能位图 `enable`（32位）],
  [`0x200000`], [优先级阈值 `threshold`],
  [`0x200004`], [Claim/Complete寄存器（读=认领，写=完成）],
)

*优先级仲裁*：`find_highest()`函数扫描所有挂起且使能的中断源，选择优先级值最大且超过阈值者；同优先级时高源ID优先。

*边触发网关*：每个源有网关使能位`gw_en`。`src_irq`上升沿且`gw_en=1`时置挂起位；`src_irq`归零后重门控（re-arm）`gw_en`，实现电平转边沿。

*Claim/Complete握手*：
#move(dx: 2em)[
  + *Claim*（读Claim寄存器）：返回最高优先级挂起中断ID，下一周期清除其挂起位并去门控`gw_en`
  + *Complete*（写中断ID至Claim寄存器）：重新门控`gw_en`，允许该源再次触发
]

=== 异常检测与优先级

`cpu_trap_manager`从流水线四级收集异常，按固定优先级排序：

#table(
  columns: (auto, auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*cause*], [*异常*], [*检测阶段*], [*mtval*],
  [0], [指令地址未对齐], [执行], [未对齐目标地址],
  [1], [指令访问错误], [取指], [错误指令地址],
  [2], [非法指令], [译码], [错误指令字],
  [3], [断点（EBREAK）], [译码], [0],
  [4], [加载地址未对齐], [访存], [未对齐加载地址],
  [5], [加载访问错误], [访存], [错误数据地址],
  [6], [存储地址未对齐], [访存], [未对齐存储地址],
  [7], [存储访问错误], [访存], [错误数据地址],
  [8], [ECALL from U], [译码], [0],
  [9], [ECALL from S], [译码], [0],
  [11], [ECALL from M], [译码], [0],
  [12], [指令页错误], [取指], [错误虚拟地址],
  [13], [加载页错误], [访存], [错误虚拟地址],
  [15], [存储页错误], [访存], [错误虚拟地址],
)

注：这里显示了另外两个模式的异常，这其实是实验5的进度。

异常优先级：访问错误 > 页错误 > 译码异常（非法 > ECALL > EBREAK）> 未对齐异常 > 执行未对齐。

*关键规则*：同步异常始终优先于异步中断（`trap_pending = clint_trap_enter && !exception_valid_r`）。

M态中断内部优先级：外部（MEIP）> 软件（MSIP）> 计时器（MTIP）。

=== 陷阱处理流程

#image("media/trap_pipeline.svg")

*陷阱入口*（`TRAP_ENTER`状态，原子操作）：

#move(dx: 2em)[
  + 委托判断：若`medeleg[cause]`或`mideleg[idx]`置位则陷入S态，否则陷入M态
  + CSR硬件写入（M态示例）：
    `mepc ← PC`，`mcause ← cause`（中断bit31=1），`mtval ← fault_val`
    `mstatus.MPP ← priv`，`mstatus.MPIE ← MIE`，`mstatus.MIE ← 0`
  + PC跳转：`PC ← mtvec[31:2]·00`（仅支持Direct模式），`priv ← target_priv`
]

*陷阱返回*（MRET/SRET）：

#move(dx: 2em)[
  + MRET：`MIE ← MPIE`，`MPIE ← 1`，`MPP ← U`；`PC ← mepc`，`priv ← MPP`
  + SRET：`SIE ← SPIE`，`SPIE ← 1`，`SPP ← 0`；`PC ← sepc`，`priv ← SPP`
]

=== 中断相关CSR寄存器

#table(
  columns: (auto, auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*CSR*], [*地址*], [*权限*], [*说明*],
  [mstatus], [`0x300`], [MRW], [MIE[3]/SIE[1]/MPIE[7]/SPIE[5]/MPP[12:11]/SPP[8]可写],
  [mie], [`0x304`], [MRW], [MEIE[11]/MTIE[7]/MSIE[3]可写],
  [mip], [`0x344`], [MRW], [纯硬件驱动：MEIP/MTIP/MSIP反映外部信号，软件不可写],
  [mtvec], [`0x305`], [MRW], [陷阱向量基址，低2位强制为0（仅Direct模式）],
  [mepc], [`0x341`], [MRW], [异常PC，低2位强制为0],
  [mcause], [`0x342`], [MRW], [异常/中断原因码],
  [mtval], [`0x343`], [MRW], [异常附加信息（错误地址/指令字/0）],
  [mscratch], [`0x340`], [MRW], [陷阱处理程序暂存寄存器],
  [medeleg], [`0x302`], [MRW], [异常委托位图，掩码`0xB3FF`],
  [mideleg], [`0x303`], [MRW], [中断委托位图，掩码`0x0AAA`],
  [sie], [`0x104`], [SRW], [SEIE[9]/STIE[5]/SSIE[1]可写],
  [sip], [`0x144`], [SRW], [仅SSIP[1]可软件写，其余硬件驱动],
  [stvec], [`0x105`], [SRW], [S态陷阱向量，低2位强制为0],
  [sepc], [`0x141`], [SRW], [S态异常PC],
  [scause], [`0x142`], [SRW], [S态原因码],
  [stval], [`0x143`], [SRW], [S态异常附加信息],
  [sscratch], [`0x140`], [SRW], [S态暂存寄存器],
  [satp], [`0x180`], [SRW], [S态页表基址],
)

CSR指令支持全部6种变体（CSRRW/CSRRS/CSRRC及立即数形式），CSRRS/CSRRC的rs1=0优化为纯读操作。

= 项目验证

== 仿真验证

在M模式层面我们写了四个个cache专项测试，仿真全部通过。

通过命令
```sh
python -m tools.vivado_cli -batch \
"cache_icache_basic,cache_dcache_basic, \
cache_dcache_dirty,cache_fencei,cache_mmu_interact" -create -sim
```
可以批量进行仿真，结果如图（`cache_mmu_interact`涉及到MMU和S特权级，忽略）：

#image("media/cache仿真结果.png")

详细测试如下：

=== cache_dcache_basic

dcache基础测试，包含

#table(columns: (auto,auto,1fr),
align: horizon,
[编号],[名称],[功能],
[1],[`test_dcache_store_load`],[测试基本存取指令],
[2],[`test_dcache_same_line`],[缓存行填充测试],
[3],[`test_dcache_cross_line`],[跨缓存行填充测试],
[4],[`test_dcache_byte_halfword`],[字、字节存取测试],
)

vivado测试：
#align(center)[#image("media/dcache_basic_控制台.png",width: 50%)]
#image("media/dcache_basic_波形图.png")

之后的测试都类似，省略测试结果，因为结果已经在工具输出中展示了。

=== cache_icache_basic

icache基础测试，包含

#table(columns: (auto,auto,1fr),
align: horizon,
[编号],[名称],[功能],
[1],[`test_icache_seq_fetch`],[连续取指令测试],
[2],[`test_icache_branch_fetch`],[分支指令测试],
[3],[`test_icache_repeated_call`],[缓存击中测试],
)

=== cache_fencei

缓存屏障测试，包含

#table(columns: (auto,auto,1fr),
align: horizon,
[编号],[名称],[功能],
[1],[`test_fencei_smc`],[指令自修改测试],
[2],[`test_fencei_dcache_flush`],[脏行回写测试],
[3],[`test_fencei_preserve_data`],[多脏行回写测试],
[4],[`test_dwb_double_flush`],[连续多次回写测试]
)

=== cache_dcache_dirty

dcache脏行测试

#table(columns: (auto,auto,1fr),
align: horizon,
[编号],[名称],[功能],
[1],[`test_dwb_flush_verify`],[写回验证],
[2],[`test_dwb_overwrite`],[覆盖型脏行回写测试],
[3],[`test_dwb_multi_dirty`],[多脏行回写测试],
[4],[`test_fencei_multi`],[写回覆盖性测试]
)

== 上板验证

#image("media/uart_echo_控制台.png")

如图，我们在FPGA上运行`uart_echo`程序，成功在串口上实现了输入什么就返回什么的功能。（无前缀的就是输入，带`[HEX]`和`[TXT]`的是接收到的数据和相应的解码）

= 总结

本次实验我们成功构建了cache+主存的硬件结构，摆脱了之前纯粹使用cache而不用主存的情况。我们成功构建了基于tree-PLRU的cache刷新，完成了`fence.i`指令，完善了异常（主要是错误内存地址这方面的异常）。

= 文件说明

提交的文件中除了本报告，`cpu-源码以及工具4.zip`是项目开发文件夹，`simplecpu_soc.xpr.zip`是vivado工程文件夹。其中项目开发文件夹中所有源代码均在`dev`下，测试程序和应用在`dev/program_source`下，硬件设计见`dev/rtl`；工具在`tools`下。

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
