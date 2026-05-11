// 计算机组成原理实验报告模板（Typst）
#set title("嵌入式处理器设计实验报告")
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
  align(center)[#text(size: 18pt)[负责人：]]
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年5月9日]]
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

设计语言：Verilog

仿真环境：Vivado~2018.3版本

== 设计目标

#move(dx: 2em)[
  + `RISCV32-IM_Zicsr_Zifencei`多周期嵌入式CPU（使用上次成果）
  + 具有异常处理机制
  + 实现（至少一级）中断机制
  + 实现接口通信机制（UART或GPIO）
  + 外设：UART、GPIO、Timer（含IRQ）、SPI
]

== 已实现的特性

#move(dx: 2em)[
  + 指令集：RV32I(41条) + M(8条) + Zicsr(6条) + Zifencei(1条) = 56条
  + 完整异常处理：非法指令、ECALL、EBREAK、地址未对齐
  + 三级中断响应：MEIP(外部)、MTIP(Timer)、MSIP(软件)，电平触发
  + 8个CSR寄存器：mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip
  + AHB-Lite系统总线（2从设备）→ APB外设总线（4从设备）
  + ICache/DCache控制器 + BRAM IP，MMIO旁路（addr[31]==1）
  + 串口通信：UART+GPIO（连接到LED上）
  + 执行-回写直通快速路径（R/I-type跳过MEM阶段）
  + ALU单周期化 + 独立MU乘除法单元
  + 四外设：GPIO(16bit)、Timer(含IRQ)、UART(RX+TX, 115200baud)、SPI
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
]

== 项目文件夹结构

```text
dev/
├─rtl/
│  ├─core/                        CPU核心模块
│  │    core_top.v                CPU顶层
│  │    cpu_controller.v          FSM控制器
│  │    icache_ctrl.v             ICache控制器
│  │    dcache_ctrl.v             DCache控制器
│  │    MMU.v                     内存管理单元 (直通, 预留)
│  │    cpu_fetch.v               取指阶段
│  │    cpu_decode.v              译码阶段
│  │    cpu_execute.v             执行阶段
│  │    cpu_mem.v                 访存阶段
│  │    cpu_wb.v                  回写阶段
│  │    cpu_regfile.v             寄存器堆
│  │    cpu_trap_csr.v            异常/CSR顶层封装
│  │    cpu_trap_manager.v        异常检测与trap管理
│  │    cpu_clint.v               中断控制逻辑
│  │    cpu_csr_interface.v       CSR指令接口
│  │    cpu_csr.v                 CSR寄存器存储
│  │    cpu_bus_bridge.v          CPU→AHB-Lite直接桥接
│  │    op_regroup.v              指令字段拆分
│  │    branch_comparator.v       分支比较器
│  │
│  ├─ALU/                         ALU模块
│  │    alu_32bit.v               ALU顶层
│  │    alu_result_selector.v     ALU结果选择器
│  │    cla_adder_16bit.v         16位超前进位加法器
│  │    cla_adder_32bit.v         32位超前进位加法器
│  │    cla_adder_4bit.v          4位超前进位加法器
│  │    logic_unit.v              逻辑运算单元
│  │    lui.v                     高位加载
│  │    mux.v                     选择器
│  │    shifter.v                 位移器
│  │    subtractor.v              减法器
│  │
│  ├─MU/                          乘除法单元
│  │    mu_unit.v                 乘除法调度
│  │    booth_multiplier.v        Booth乘法器
│  │    non_restoring_divider.v   非恢复余数除法器
│  │
│  ├─AHB-lite/                    AHB-Lite系统总线
│  │    ahb_lite_bus.v            AHB外设总线顶层
│  │    ahb_decoder.v             AHB地址译码
│  │    ahb_mux.v                 AHB读数据MUX
│  │    ahb_sram_slave.v          AHB SRAM从设备
│  │
│  ├─APB/                         APB外设总线
│  │    ahb_lite_to_apb.v         AHB→APB桥
│  │    apb_slave.v               APB通用从设备
│  │    apb_perips.v              APB外设容器
│  │    perips/
│  │        gpio.v                GPIO (16bit双向)
│  │        timer.v               Timer (含IRQ)
│  │        uart_top.v            UART顶层
│  │        spi.v                 SPI主机
│  │
│  └─system_top.v                 FPGA系统顶层
│
├─tb/                             测试台
├─program_source/                 测试程序
└─fpga/                           FPGA集成
    cpu.xdc                       引脚约束
    lcd_module.dcp                LCD预编译IP
```

= 实现细节

== 指令集扩展

在上一次实验实现的37条RV32I指令基础上，本次扩展至56条，新增M扩展8条、Zicsr扩展6条、Zifencei扩展1条，以及RV32I中此前未实现的3条（ECALL、EBREAK、FENCE）。

完整指令集如下：

#table(
  columns: (1fr, 1fr, 1fr, 1fr, 1fr),
  align: center,
  text(orange)[add], text(orange)[sub], text(orange)[sll], text(orange)[slt], text(orange)[sltu],
  text(orange)[xor], text(orange)[srl], text(orange)[sra], text(orange)[or], text(orange)[and],
  text(maroon)[jalr], text(maroon)[lb], text(maroon)[lh], text(maroon)[lw], text(maroon)[lbu],
  text(maroon)[lhu], text(maroon)[addi], text(maroon)[slti], text(maroon)[sltiu], text(maroon)[xori],
  text(maroon)[ori], text(maroon)[andi], text(maroon)[slli], text(maroon)[srli], text(maroon)[srai],
  text(fuchsia)[sb], text(fuchsia)[sh], text(fuchsia)[sw], text(olive)[beq], text(olive)[bne],
  text(olive)[blt], text(olive)[bge], text(olive)[bltu], text(olive)[bgeu], text(blue)[lui],
  text(blue)[auipc], [jal], [], [], [],
  text(teal)[mul], text(teal)[mulh], text(teal)[mulhsu], text(teal)[mulhu], text(teal)[div],
  text(teal)[divu], text(teal)[rem], text(teal)[remu], text(purple)[csrrw], text(purple)[csrrs],
  text(purple)[csrrc], text(purple)[csrrwi], text(purple)[csrrsi], text(purple)[csrrci], [ecall],
  [ebreak], [mret], [fence], [fence.i],
)

其中#text(orange)[`R`] #text(maroon)[`I`] #text(fuchsia)[`S`] #text(olive)[`B`] #text(blue)[`U`] `J`为上一次已实现，#text(teal)[`M`]为本次M扩展，#text(purple)[`Zicsr`]为CSR指令，其余为系统控制指令。

=== M指令集扩展

添加M扩展支持。新增8条乘除法指令，由独立的`mu_unit`模块处理：

#table(
  columns: (1fr, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令*], [*操作*], [*说明*],
  [MUL], [rs1 × rs2低32位], [有符号乘法],
  [MULH], [rs1 × rs2高32位], [有符号 × 有符号],
  [MULHSU], [rs1 × rs2高32位], [有符号 × 无符号],
  [MULHU], [rs1 × rs2高32位], [无符号 × 无符号],
  [DIV], [rs1 / rs2], [有符号除法（向零截断）],
  [DIVU], [rs1 / rs2], [无符号除法],
  [REM], [rs1 % rs2], [有符号取余],
  [REMU], [rs1 % rs2], [无符号取余],
)

乘法器、除法器均为原ALU内部模块，此次修改中独立出来为单独的MU模块，详细见#link(<MU>)[CPU核优化:ALU单周期化-MU扩展]。MU模块通过`mu_req_valid`/`mu_result_valid`握手协议与执行模块交互，支持`flush`中断。

=== Zicsr和Zifencei扩展

Zicsr扩展新增6条CSR指令，用于读写控制和状态寄存器：

#table(
  columns: (1fr, 2fr, 2fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令*], [*操作*], [*说明*],
  [CSRRW], [t=csr; csr=rs1; rd=t], [原子读改写],
  [CSRRS], [t=csr; csr=csr|rs1; rd=t], [原子读改置位],
  [CSRRC], [t=csr; csr=csr\&\~rs1; rd=t], [原子读改清位],
  [CSRRWI], [t=csr; csr=uimm; rd=t], [立即数读改写],
  [CSRRSI], [t=csr; csr=csr|uimm; rd=t], [立即数读改置位],
  [CSRRCI], [t=csr; csr=csr\&\~uimm; rd=t], [立即数读改清位],
)

CSR no-write优化：CSRRS/CSRRC且rs1=0时、CSRRSI/CSRRCI且uimm=0时不写CSR，仅读取。

Zifencei扩展仅包含`FENCE.I`指令，用于指令缓存刷新，当前由于未使用主存，没有内存屏障限制，实现中为NOP（直接跳过）。

此外，添加系统控制指令`ECALL`、`EBREAK`、`MRET`支持，分别触发异常进入和中断返回。详见"#link(<expact_exe>)[异常处理]"小节。

== CPU核优化

为了优化CPU核的结构以及CPI，我们对流水线、ALU和访存路径结构进行了重构。

=== 执行-回写数据链路

在之前实验的设计中，所有非分支指令执行后都必须经过MEM阶段（即使不需要访存），MEM阶段虽然做了直通，但还是占用了大量周期。为了优化CPI，我们优化了流水线路径，添加了exe->wb路径：

#move(dx: 2em)[
  - R/I-type运算指令：EXEC → WB（跳过MEM，减少2周期）
  - JAL/JALR指令：EXEC → WB（跳过MEM，减少2周期）
  - Load/Store指令：EXEC → MEM → WB（仍需访存）
  - Branch指令：EXEC → FETCH（跳过MEM和WB，与之前相同）
  - CSR指令：CSR\_ACCESS → WB
]

此优化使所有非分支非访存指令的执行周期下降2。

=== ALU单周期化-MU扩展<MU>

由于从第一次实验继承来的ALU模块内部集成了Booth乘法器和非恢复余数除法器，使得其必须通过握手协议（`req_valid`/`result_valid`）与执行模块交互，但又没有M指令集，导致没有指令实际使用乘除法功能，平白为所有经过ALU计算的指令引入3周期额外开销（请求发射→结果锁存→读取`done_reg`）。

本次实验中我们将乘除法从ALU中分离为独立的`mu_unit`模块：

#move(dx: 2em)[
  - *ALU*：仅保留单周期组合逻辑运算（ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI/NOR/NOT），变为纯组合逻辑模块，移除握手协议，消除握手耗时。
  - *MU*：独立出来的乘除法单元，内部为从ALU中剥离出来的`booth_multiplier`和`non_restoring_divider`，通过`mu_req_valid`/`mu_result_valid`握手协议与执行模块交互，以支持M扩展指令。
]

ALU控制编码（one-hot，bit0保留）：

#move(dx: 2em)[#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  align: center,
  stroke: 0.5pt,
  inset: 4pt,
  [*15*], [*14*], [*13*], [*12*], [*11*], [*10*], [*9*], [*8*],
  [—], [—], [NOT], [ADD], [SUB], [SLT], [SLTU], [AND],
  [*7*], [*6*], [*5*], [*4*], [*3*], [*2*], [*1*], [*0*],
  [NOR], [OR], [XOR], [SLL], [SRL], [SRA], [LUI], [—],
)]

注意MUL/DIV位已移除，乘除法由执行模块直接操作MU单元处理。

=== cache访存路径重构

此次实验中，由于需要支持MMIO进行外设访问，以及为了后续存储实验的进行，我们抛弃了之前的直接访问cache的方式，在访问路径上添加了MMU和cache控制器，即现在访问cache的路径为：fetch/mem->MMU->cache控制器->cache。

*MMU*：

占位用，当前地址直通`paddr = vaddr`，为后续虚拟内存扩展预留接口。CPU中两个cache访问路径对应两个MMU，分别用于取指地址和访存地址翻译。

*Cache控制器（i/dcache\_ctrl）*：

#move(dx: 2em)[
  - MMIO：`is_mmio = cpu_req_addr[31]`，选择访问外设或者访问cache
  - MMIO访问：转换信号，向总线发送`mmio_data`/`mmio_valid`信号
  - 输出选择：`cpu_req_data = is_mmio ? mmio_data : icache_dout`
  - dcache_ctrl与icache\_ctrl结构对称，额外支持写操作：
]

MMIO地址空间：`0x80000000-0xFFFFFFFF`，即地址最高位为1。

同时，我们升级了BRAM IP，现在cache来到了$32 times 4096=16"KB"$，并且支持了字节读写（`wea,web`变为四位，支持多种宽度读写），简化了访存的操作逻辑。

== 控制器扩展

此次添加中断和异常支持，控制器从6状态FSM扩展为9状态：

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*编码*], [*状态*], [*说明*],
  [4'd0], [`STATE_IDLE`], [复位后的初始状态，直接转入FETCH],
  [4'd1], [`STATE_FETCH`], [取指阶段],
  [4'd2], [`STATE_DECODE`], [译码阶段],
  [4'd3], [`STATE_EXEC`], [执行阶段],
  [4'd4], [`STATE_MEM`], [访存阶段],
  [4'd5], [`STATE_WB`], [回写阶段],
  [4'd6], [`STATE_CSR_ACCESS`], [CSR读写阶段，完成后进入WB],
  [4'd7], [`STATE_TRAP_ENTER`], [异常/中断进入，保存CSR后跳转mtvec],
  [4'd8], [`STATE_TRAP_RETURN`], [MRET返回，恢复CSR后跳转mepc],
)

FSM状态转移逻辑图：

#cetz.canvas({
  import cetz.draw: *
  set-style(content: (frame: "rect", stroke: none, fill: white, padding: .1))
  let w = 1.8
  let h = 1.0
  let dx = 3.5
  let y_top = 2.0
  let y_bot = 0

  rect((0, y_top), (w, y_top + h), name: "s0")
  content("s0", [#text(size: 11pt, "IDLE")])

  rect((dx, y_top), (dx + w, y_top + h), name: "s1")
  content("s1", [#text(size: 11pt, "FETCH")])

  rect((2 * dx, y_top), (2 * dx + w, y_top + h), name: "s2")
  content("s2", [#text(size: 11pt, "DECODE")])

  rect((3 * dx, y_top), (3 * dx + w, y_top + h), name: "s3")
  content("s3", [#text(size: 11pt, "EXEC")])

  rect((4 * dx, y_top), (4 * dx + w, y_top + h), name: "s4")
  content("s4", [#text(size: 11pt, "MEM")])

  rect((0, y_bot), (w, y_bot + h), name: "s7")
  content("s7", [#text(size: 11pt, "TRAP\nENTER")])

  rect((dx, y_bot), (dx + w, y_bot + h), name: "s8")
  content("s8", [#text(size: 11pt, "TRAP\nRET")])

  rect((2 * dx, y_bot), (2 * dx + w, y_bot + h), name: "s6")
  content("s6", [#text(size: 11pt, "CSR")])

  rect((4 * dx, y_bot), (4 * dx + w, y_bot + h), name: "s5")
  content("s5", [#text(size: 11pt, "WB")])

  line("s0.east", "s1.west", mark: (end: "straight"))
  line("s1.east", "s2.west", mark: (end: "straight"), name: "1t2")
  content((name: "1t2", anchor: 40%), anchor: "south", [#text(size: 10pt, "if_done")])
  line("s2.east", "s3.west", mark: (end: "straight"), name: "2t3")
  content((name: "2t3", anchor: 50%), anchor: "south", [#text(size: 10pt, "need_exe")])
  line("s3.east", "s4.west", mark: (end: "straight"), name: "3t4")
  content((name: "3t4", anchor: 50%), [#text(size: 10pt, "ld/st")])

  line("s2.south", "s7.north", bend: -25, mark: (end: "straight"), name: "2t7")
  content((name: "2t7", anchor: 75%), angle: ("2t7.start", 0%, "2t7.end"), [#text(size: 10pt, "trap")])
  line("s2.south", "s8.north", bend: -10, mark: (end: "straight"), name: "2t8")
  content((name: "2t8", anchor: 70%), angle: ("2t8.start", 0%, "2t8.end"), [#text(size: 10pt, "mret")])
  line("s2.south", "s6.north", mark: (end: "straight"), name: "2t6")
  content((name: "2t6", anchor: 50%), [#text(size: 10pt, "csr")])

  line("s3.south", "s5.north", bend: 15, mark: (end: "straight"), name: "3t5")
  content((name: "3t5", anchor: 50%), angle: ("3t5.start", 100%, "3t5.end"), [#text(size: 10pt, "R/I fast")])
  line("s4.south", "s5.north", mark: (end: "straight"), name: "4t5")
  content((name: "4t5", anchor: 50%), [#text(size: 10pt, "mem_done")])
  line("s6.east", "s5.west", mark: (end: "straight"))

  line("s5.north", "s1.south", bend: -15, mark: (end: "straight"), stroke: (dash: "dashed"), name: "5t1")
  content((name: "5t1", anchor: 30%), angle: ("5t1.start", 0%, "5t1.end"), [#text(size: 10pt, "next")])
  line("s7.north", "s1.south", mark: (end: "straight"), stroke: (dash: "dashed"))
  line("s8.north", "s1.south", mark: (end: "straight"), stroke: (dash: "dashed"))

  line(
    "s3.north",
    (rel: (0, 0.5), to: "s3.north"),
    (rel: (0, 0.5), to: "s1.north"),
    "s1.north",
    mark: (end: "straight"),
    name: "3t1",
  )
  content((name: "3t1", anchor: 50%), [#text(size: 10pt, "branch")])

  line("s3.south", (11.4, -0.5), (0.9, -0.5), "s7.south", mark: (end: "straight"), name: "3t7")
  content((name: "3t7", anchor: 50%), [#text(size: 10pt, "br+trap")])

  line("s5.south", (14.9, -0.3), (0.9, -0.3), "s7.south", mark: (end: "straight"), name: "5t7")
  content((name: "5t7", anchor: 20%), [#text(size: 10pt, "trap")])

  line("s2.north", "s1.north", bend: -30, mark: (end: "straight"), name: "2t1f")
  content((name: "2t1f", anchor: 50%), anchor: "south", [#text(size: 10pt, "fence")])
})

== 异常处理<expact_exe>

=== 异常类型

CPU支持以下异常，分别在Decode和Mem阶段检测：

#table(
  columns: (auto, auto, 1fr),
  align: (horizon, horizon + center, horizon),
  stroke: 0.5pt,
  inset: 6pt,
  [*异常*], [*mcause*], [*触发条件*],
  [非法指令], [2], [opcode/funct未定义，或CSR地址无效],
  [EBREAK], [3], [执行EBREAK指令],
  [Load地址未对齐], [4], [LH/LHU bit0≠0，LW bit\[1:0\]≠0],
  [Store地址未对齐], [6], [SH bit0≠0，SW bit\[1:0\]≠0],
  [ECALL (M-mode)], [11], [M模式下执行ECALL],
)

异常优先级：当前设置同步异常优先于中断；同一指令边界上的同步异常先处理。

=== CSR寄存器

实现了8个Machine模式CSR寄存器：

#table(
  columns: (auto, auto, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*地址*], [*名称*], [*读写*], [*说明*],
  [0x300], [mstatus], [MRW], [目前支持：MIE\[3\], MPIE\[7\], MPP\[12:11\]],
  [0x304], [mie], [MRW], [目前支持：MSIE\[3\], MTIE\[7\], MEIE\[11\]],
  [0x305], [mtvec], [MRW], [trap基址（中断服务程序的基地址）],
  [0x340], [mscratch], [MRW], [暂存寄存器],
  [0x341], [mepc], [MRW], [异常指令PC寄存器],
  [0x342], [mcause], [MRW], [异常原因],
  [0x343], [mtval], [MRW], [异常附加值],
  [0x344], [mip], [MR], [MEIP\[11\], MTIP\[7\], MSIP\[3\]由硬件驱动],
)

CSR模块支持*双写端口*：

#move(dx: 2em)[
  - 软件写（`sw_csr_wen`）：CSR指令触发
  - 硬件写（`hw_csr_wen`）：trap进入/返回时自动更新mepc/mcause/mtval/mstatus
]

`mip`寄存器由硬件驱动：`w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0}`。

=== Trap机制

*Trap进入（异常/中断响应）*：

#move(dx: 2em)[
  - PC ← mtvec.BASE（Direct模式）
  - mepc ← 异常PC（同步异常，即出错指令的pc）或当前PC（中断，即将要执行指令的pc）
  - mcause ← 异常/中断编码
  - mstatus: MPIE←MIE, MIE←0, MPP←当前模式
]

*MRET返回*：

#move(dx: 2em)[
  - PC ← mepc
  - mstatus: MIE←MPIE, MPIE←1, MPP←U
]

*模块化设计*：异常管理与CSR访问逻辑封装为`cpu_trap_csr`统一模块，内部实例化`cpu_trap_manager`（异常检测、中断判定、trap PC生成）和`cpu_csr_interface`（CSR指令新值计算、CSR写回总线生成），职责分离，便于维护与扩展。

=== 中断响应

支持三种中断，电平触发（持续到软件ack）：

#table(
  columns: (2fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*中断源*], [*mcause*], [*判定条件*],
  [软件中断(MSIP)], [0x80000003], [MSIE=1 && MSIP=1 && MIE=1],
  [Timer中断(MTIP)], [0x80000007], [MTIE=1 && MTIP=1 && MIE=1],
  [外部中断(MEIP)], [0x8000000B], [MEIE=1 && MEIP=1 && MIE=1],
)

中断源连接：`ext_mtip`连接`timer_irq`（来自APB 总线上的 Timer外设）。中断和异常检测点在指令间隔，具体为EXEC完成（分支指令）和WB完成后。

== 系统总线

系统总线我们选择了ARM AMBA的AHB-Lite总线，原因是具有突发机制，性能较好，同时较简单，且规范易于扩展。

=== 总线拓扑

#align(center)[#cetz.canvas({
  import cetz.draw: *

  rect((0, 2), (3, 3), name: "bridge")
  content("bridge", [#text(size: 10pt, "cpu_bus_bridge")])

  rect((5, 0), (10, 5), name: "bus")
  content("bus.north", anchor: "south", [#text(size: 10pt, "ahb_lite_bus")])

  rect((5.5, 3.5), (9.5, 4.5), name: "decoder")
  content("decoder", [#text(size: 10pt, "ahb_decoder")])

  rect((5.5, 1), (7.0, 2.5), name: "sram")
  content("sram", [#text(size: 10pt, "ahb_sram")])

  rect((7.5, 1), (9.5, 2.5), name: "apbb")
  content("apbb", [#text(size: 10pt, "AHB→APB")])

  line("bridge.east", "bus.west", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "AHB-Lite")])
  line("decoder.south", "sram.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_sram")
  line("decoder.south", "apbb.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_apb")

  content((name: "bus_sram", anchor: 50%), anchor: "east", [#text(size: 10pt, "HSEL0")])
  content((name: "bus_apb", anchor: 50%), anchor: "west", [#text(size: 10pt, "HSEL1")])
})]

AHB-Lite总线当前挂载2个从设备：

#table(
  columns: (auto, auto, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*从设备*], [*选择条件*], [*模块*], [*说明*],
  [Slave 0], [HADDR\[31\]=0], [`ahb_sram_slave`], [主存SRAM (1MB, Sram BRAM IP)],
  [Slave 1], [HADDR\[31\]=1], [`ahb_lite_to_apb`], [APB桥，连接外设总线],
)

=== cpu_bus_bridge

`cpu_bus_bridge`将CPU的ICache/DCache MMIO请求直接桥接为AHB-Lite主设备信号，CPU核心直接输出AHB-Lite信号（HADDR/HTRANS/HWRITE/HSIZE/HWDATA等）。

3状态FSM：

#table(
  columns: (auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*状态*], [*说明*],
  [`AHB_IDLE`], [空闲，等待icache_mmio_req或dcache_mmio_req],
  [`AHB_ADDR`], [地址相位，等待HREADY],
  [`AHB_DATA`], [数据相位，等待HREADY，锁存HRDATA],
)

优先级：ICache MMIO请求优先于DCache MMIO请求（同时到达时ICache先服务）。

AHB信号映射：

#table(
  columns: (2fr, 1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*CPU请求*], [*HTRANS*], [*HWRITE*], [*HSIZE*], [*HBURST*],
  [ICache取指], [NONSEQ], [0], [WORD], [SINGLE],
  [DCache读], [NONSEQ], [0], [hsize], [SINGLE],
  [DCache写], [NONSEQ], [1], [hsize], [SINGLE],
)

=== AHB SRAM从设备

`ahb_sram_slave`内部实例化Sram BRAM IP（Xilinx Block Memory Generator），参数化`MEM_DEPTH=262144`（1MB），支持字节/半字/字写使能，通过`byte_we`转换HSIZE+HADDR为BRAM字节掩码。等待状态计数器处理BRAM读延迟（1周期）。

== 外设总线

外设总线我们选择了ARM AMBA的APB总线，原因是实现简单，规范易于扩展。

=== APB总线拓扑

#align(center)[#cetz.canvas({
  import cetz.draw: *

  rect((0, 0.55), (2.5, 1.75), name: "bridge")
  content("bridge", [#text(size: 10pt, "AHB→APB")])

  rect((4, 0), (10.5, 2.3), name: "apb")
  content("apb.north", anchor: "south", padding: .1, [#text(size: 10pt, "APB总线")])

  rect((4.3, 0.3), (5.7, 1.5), name: "gpio")
  content("gpio", [#text(size: 10pt, "GPIO")])

  rect((6.0, 0.3), (7.4, 1.5), name: "timer")
  content("timer", [#text(size: 10pt, "Timer")])

  rect((7.7, 0.3), (9.1, 1.5), name: "uart")
  content("uart", [#text(size: 10pt, "UART")])

  rect((9.4, 0.3), (10.3, 1.5), name: "spi")
  content("spi", [#text(size: 10pt, "SPI")])

  line("bridge.east", "apb.west", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "APB")])

  content((5.0, 1.8), [#text(size: 10pt, "00")])
  content((6.7, 1.8), [#text(size: 10pt, "01")])
  content((8.4, 1.8), [#text(size: 10pt, "10")])
  content((9.85, 1.8), [#text(size: 10pt, "11")])
})]

APB总线挂载4个从设备，通过`PADDR[15:14]`译码：

#table(
  columns: (auto, 1fr, 2fr),
  align: (horizon, center),
  stroke: 0.5pt,
  inset: 6pt,
  [*从设备*], [*PADDR\[15:14\]*], [*模块*],
  [Slave 0], [00], [GPIO (16bit双向)],
  [Slave 1], [01], [Timer (含IRQ)],
  [Slave 2], [10], [UART (RX+TX)],
  [Slave 3], [11], [SPI主机],
)

=== AHB-to-APB桥

`ahb_lite_to_apb`实现3状态FSM（IDLE→SETUP→ACCESS），将AHB-Lite传输转换为APB协议（PSEL/PENABLE/PWRITE/PADDR/PWDATA/PSTRB）。支持PSLVERR错误响应回传、背靠背传输（ACCESS阶段检测新AHB请求直接进入SETUP）。

=== 外设

#table(
  columns: (auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*外设*], [*说明*],
  [GPIO], [16bit双向IO，方向控制+数据寄存器，当前连接LED做走马灯],
  [Timer], [32位计数器+阈值+使能，匹配时产生IRQ，连接CPU的ext\_mtip中断],
  [UART], [顶层封装含RX/TX子模块，可配置波特率（默认115200）],
  [SPI], [SPI主机，支持MOSI/MISO/SS/CLK四线],
)

== 结构总览

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let box_w = 1.8
  let box_h = 1.0
  let gap_x = 1.2
  let gap_y = 1.2

  let stages = (
    ("fetch", "Fetch"),
    ("decode", "Decode"),
    ("execute", "Execute"),
    ("mem", "Memory"),
    ("wb", "Writeback"),
  )
  for (i, s) in stages.enumerate() {
    let (id, label) = s
    let x_pos = i * (box_w + gap_x)
    rect((x_pos, 0), (x_pos + box_w, box_h), name: id)
    content(id, [#text(size: 10pt, label)])
  }

  rect((rel: (-1.0, -1.5), to: "execute"), (rel: (1.0, -2.5), to: "execute"), fill: gray, name: "regfile")
  content("regfile", [#text(size: 10pt, "RegFile")])

  rect((rel: (-1.25, -1.5), to: "fetch"), (rel: (1.25, -2.5), to: "fetch"), fill: gray, name: "icache")
  content("icache", [#text(size: 10pt, "iCache")])

  rect((rel: (-1.25, -1.5), to: "mem"), (rel: (1.25, -2.5), to: "mem"), fill: gray, name: "dcache")
  content("dcache", [#text(size: 10pt, "dCache")])

  rect((rel: (-1.25, 1.5), to: "fetch"), (rel: (1.25, 2.5), to: "fetch"), name: "ctrl")
  content("ctrl", [#text(size: 10pt, "Controller")])

  rect(
    (rel: (-4, -1.5), to: "regfile"),
    (rel: (-1.5, -2.5), to: "regfile"),
    name: "ahb",
  )
  content("ahb", [#text(size: 10pt, "AHB-Lite")])

  rect((rel: (-1.25, -1.5), to: "ahb"), (rel: (+1.25, -2.5), to: "ahb"), name: "apb")
  content("apb", [#text(size: 10pt, "APB+Perips")])

  rect((rel: (-1.0, 1.5), to: "mem"), (rel: (1.0, 2.5), to: "mem"), name: "csr")
  content("csr", [#text(size: 10pt, "Trap/CSR")])

  line("fetch.east", "decode.west", mark: (end: "straight"), name: "lfd")
  content("lfd", anchor: "south", padding: .1, text(size: 10pt, "96bit"))
  line("decode.east", "execute.west", mark: (end: "straight"), name: "lde")
  content("lde", anchor: "south", padding: .1, text(size: 10pt, "320bit"))
  line("execute.east", "mem.west", mark: (end: "straight"), name: "lem")
  content("lem", anchor: "south", padding: .1, text(size: 10pt, "207bit"))
  line("mem.east", "wb.west", mark: (end: "straight"), name: "lmw")
  content("lmw", anchor: "south", padding: .1, text(size: 10pt, "168bit"))

  line("icache.north", "fetch.south", mark: (end: "straight"))
  line("dcache.north", "mem.south", mark: (symbol: "straight"), bend: -20)
  line("ahb", "icache", mark: (symbol: "straight"))
  line("ahb", "dcache", mark: (symbol: "straight"))
  line("apb", "ahb", mark: (symbol: "straight"))

  line("ctrl.south", "fetch", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "decode.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "execute.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "mem.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "wb.north", stroke: (dash: "dashed"), mark: (end: "straight"))

  line("regfile.north", "decode.south", mark: (end: "straight"))
  line("wb.south", "regfile.north", mark: (end: "straight"))

  line("csr.south", "mem.north", mark: (start: "straight"))
  line("csr.west", "execute.north", mark: (start: "straight"))
})]

*模块间数据通路*：

#table(
  columns: (1fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*总线*], [*位宽*], [*主要内容*],
  [`if_id_bus`], [96], [`pc_plus4`(32) + `pc`(32) + `inst`(32)],
  [`id_exe_bus`], [320], [PC信息 + 控制标志 + ALU控制 + 操作数 + CSR信息 + 寄存器值 + 指令],
  [`exe_mem_bus`], [207], [PC信息 + ALU结果 + 访存信息 + CSR数据 + 指令],
  [`mem_wb_bus`], [168], [PC信息 + 写回数据 + CSR数据 + 指令],
)

= 仿真验证

== 测试框架

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*Testbench*], [*行数*], [*测试内容*],
  [`tb_simple_cpu_top`], [220], [CPU综合测试（ALU/访存/对齐/CSR/异常/中断）],
  [`tb_simple_cpu_compute`], [220], [CPU运算指令测试（M扩展+算术）],
  [`tb_simple_cpu_trap`], [191], [CPU异常/中断测试],
  [`tb_ahb_bus`], [175], [AHB-Lite总线功能测试],
  [`tb_apb_perips`], [202], [APB外设读写测试],
  [`tb_uart_hello`], [252], [UART Hello World发送测试],
  [`tb_led_marquee`], [189], [LED走马灯测试],
  [`tb_alu_cpu_integration`], [149], [ALU组合逻辑集成测试],
  [`tb_mu_unit`], [227], [乘除法单元测试],
  [`tb_non_restoring_divider`], [204], [非恢复余数除法器测试],
)

== 测试程序

#table(
  columns: (2fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*程序*], [*说明*],
  [`cpu_test.s`], [ALU/访存/对齐/CSR/异常/中断综合测试],
  [`cpu_test_compute.s`], [M扩展+算术运算测试],
  [`cpu_test_trap.s`], [异常/中断专项测试],
  [`led_marquee.s`], [LED跑马灯演示程序],
  [`uart_hello.s`], [UART Hello World发送程序],
  [`fib10.c`], [C语言Fibonacci数列计算],
)

== 测试结果

#table(
  columns: (2fr, 1fr, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*测试类别*], [*检查项数*], [*结果*],
  [CPU综合测试], [33], [ALL PASS],
  [CPU运算测试], [33], [ALL PASS],
  [CPU异常测试], [8], [ALL PASS],
  [AHB总线测试], [3], [ALL PASS],
  [APB外设测试], [10], [ALL PASS],
  [ALU集成测试], [11], [ALL PASS],
  [MU单元测试], [10], [ALL PASS],
  [除法器测试], [8], [ALL PASS],
)

共116项测试全部通过。

= 性能计算<PerformanceCalculation>

== 各阶段周期数分析

=== 取指阶段（FETCH）：2周期

与上一次设计相同，icache使用BRAM IP核具有1周期同步读延迟，需要2周期完成取指。

=== 译码阶段（DECODE）：1周期

纯组合逻辑，当拍完成。

=== 执行阶段（EXEC）

*LUI指令（`use_fixed_wb=1`，旁路ALU）：2周期*

#move(dx: 2em)[
  - 沿1：检测到`exe_valid`，直接锁存`wb_fixed_data`，`done_reg<=1`
  - 沿2：`exe_done=1`，FSM转移
]

*ALU指令（单周期，无握手）：2周期*

#move(dx: 2em)[
  - 沿1：`exe_valid=1`，ALU组合逻辑计算，结果可用，`done_reg<=1`
  - 沿2：`exe_done=1`，FSM转移
]

相比上一次设计的4周期（握手协议引入3周期额外开销），EXEC阶段从4周期降至2周期。

*M扩展指令（多周期握手）：约34周期*

#move(dx: 2em)[
  - 沿1：`mu_req_valid=1`，发起乘除法请求
  - 沿2-33：`mu_unit`执行运算（Booth乘法32周期 / 非恢复余数除法32周期+修正）
  - 沿34：`mu_result_valid=1`，采样结果，`done_reg<=1`
]

*CSR指令：1周期*

CSR读写为组合逻辑，在CSR\_ACCESS状态1周期完成。

=== 访存阶段（MEM）

*R/I-type ALU指令：0周期（快速路径跳过）*

exe\_to\_wb快速路径使R/I-type运算指令跳过MEM阶段，直接进入WB。

*Load指令：3周期*

#move(dx: 2em)[
  - 沿1：MEM\_IDLE→MEM\_READ，设置dcache使能和地址
  - 沿2：MEM\_READ，BRAM锁存地址并输出数据
  - 沿3：BRAM输出有效，采样数据，`done=1`
]

相比上一次设计的4周期（需要额外的MEM\_READ2状态），减少1周期。

*Store指令：2周期*

#move(dx: 2em)[
  - 沿1：MEM\_IDLE→MEM\_WRITE，使用字节掩码直接写入
  - 沿2：写入完成，`done=1`
]

相比上一次设计的5周期（需要读-改-写3步），字节掩码写入使Store从5周期降至2周期。

=== 回写阶段（WB）：1周期

纯组合逻辑，当拍完成。

== 各指令类型CPI与平均CPI

#table(
  columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令类型*], [*FETCH*], [*DECODE*], [*EXEC*], [*MEM*], [*WB*], [*CPI*],
  [R-type ALU], [2], [1], [2], [—], [1], [#text(red)[6]],
  [I-type ALU], [2], [1], [2], [—], [1], [#text(red)[6]],
  [AUIPC], [2], [1], [2], [—], [1], [#text(red)[6]],
  [LUI], [2], [1], [2], [—], [1], [#text(red)[6]],
  [JAL / JALR], [2], [1], [2], [—], [1], [#text(red)[6]],
  [Branch], [2], [1], [2], [—], [—], [#text(red)[5]],
  [Load], [2], [1], [2], [3], [1], [#text(red)[9]],
  [Store], [2], [1], [2], [2], [1], [#text(red)[8]],
  [CSR], [2], [1], [1\*], [—], [1], [#text(red)[5]],
  [MUL/DIV], [2], [1], [34], [—], [1], [#text(red)[38]],
)

与上一次设计对比：

#table(
  columns: (1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*指令类型*], [*旧CPI*], [*新CPI*], [*提升*],
  [R/I-type ALU], [10], [6], [#text(green)[-40\%]],
  [LUI], [8], [6], [#text(green)[-25\%]],
  [JAL/JALR], [10], [6], [#text(green)[-40\%]],
  [Branch], [7], [5], [#text(green)[-29\%]],
  [Load], [12], [9], [#text(green)[-25\%]],
  [Store], [13], [8], [#text(green)[-38\%]],
)

CPI改善来源：

#move(dx: 2em)[
  + *ALU单周期化*：EXEC从4周期降至2周期（所有指令受益）
  + *exe\_to\_wb快速路径*：R/I-type跳过MEM（减少2周期）
  + *字节掩码写入*：Store从读-改-写5周期降至直接写2周期
]

采用推算指令混合比例（此占比仅供参考，不含M扩展）：

#table(
  columns: (1fr, 1fr, 1fr, 1fr),
  align: center,
  stroke: 0.5pt,
  inset: 6pt,
  [*类别*], [*占比*], [*CPI*], [*加权*],
  [ALU], [40\%], [6], [2.4],
  [Load], [25\%], [9], [2.25],
  [Store], [10\%], [8], [0.8],
  [Branch], [20\%], [5], [1.0],
  [Jump], [5\%], [6], [0.3],
)

$ "平均CPI" = sum_i p_i dot "CPI"_i = 2.4 + 2.25 + 0.8 + 1.0 + 0.3 = #text(red)[6.75] $

$ "IPC" = 1 / "CPI" approx 0.148 $

== MIPS

系统时钟100MHz，每秒执行的百万条指令数：

$ "MIPS" = 10^8 / (6.75 times 10^6) approx #text(red)[14.8] $

相比上一次设计的MIPS=9.8，性能提升约#text(green)[51\%]。

= 遇到的问题以及解决

== mip MEIP位映射错误

*问题*：`w_mip_hw`仅27位，零扩展后MEIP落在bit6而非RISC-V规范要求的bit11。

*解决*：扩展为32位，MEIP=bit11, MTIP=bit7, MSIP=bit3。

== interrupt\_cause编码错误

*问题*：`{1'b1, 27'd0, 5'd11}`产生33位值，截断后bit31=0，中断编码失去最高位标识。

*解决*：直接使用32位常量`32'h8000000B`/`32'h80000007`/`32'h80000003`。

== Timer IRQ电平触发

*问题*：原设计Timer中断为单周期脉冲，CPU可能错过中断。

*解决*：改为电平触发，`timer_irq`持续高直到软件通过写Timer寄存器ack。

== Store误写寄存器

*问题*：MEM\_WRITE状态遗漏清除`wb_we_reg`，导致Store指令错误地写回通用寄存器。

*解决*：在MEM\_WRITE状态增加`wb_we_reg<=0; wb_data_reg<=0`。

== MRET误判为非法指令

*问题*：`inst_mret`匹配模式仅20位有效，部分位未参与比较，导致合法MRET被误判为非法指令。

*解决*：扩展为完整25位匹配。

== 从Bus4LZU Mock迁移到AHB-Lite

*问题*：旧设计使用自定义Bus4LZU仿真代理，不可综合，仅能仿真。

*解决*：迁移至AMBA AHB-Lite + APB标准协议，使用Xilinx BRAM IP，实现可综合设计。关键变更：

#table(
  columns: (1fr, 2fr, 2fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*方面*], [*旧设计*], [*新设计*],
  [总线协议], [自定义Bus4LZU仿真代理], [AMBA AHB-Lite + APB标准协议],
  [存储器], [内部BRAM数组 + \$readmemh], [Sram BRAM IP (Xilinx)],
  [外设], [内部Timer逻辑], [APB总线挂载GPIO/Timer/UART/SPI],
  [Cache], [行为模型], [BRAM IP + 控制器 + MMIO旁路],
  [CPU桥接], [直连mock], [cpu\_bus\_bridge (CPU→AHB direct)],
  [扩展性], [不可综合，仅仿真], [可综合，支持FPGA部署],
)

= 结论

本项目在基础RV32I多周期CPU之上，成功实现了一个32位RISC-V多周期嵌入式处理器，主要成果如下：

#move(dx: 2em)[
  + *指令集扩展*：从37条扩展至55条，新增M扩展8条乘除法指令、Zicsr扩展6条CSR指令、Zifencei扩展1条，以及ECALL/EBREAK/MRET系统控制指令
  + *CPI优化*：通过ALU单周期化（EXEC 4→2周期）、exe\_to\_wb快速路径（R/I-type跳过MEM）、字节掩码写入（Store 5→2周期），平均CPI从10.2降至6.75，MIPS从9.8提升至14.8，性能提升约51%
  + *完整异常处理*：实现非法指令、ECALL、EBREAK、地址未对齐异常，含trap进入/返回机制
  + *三级中断响应*：MEIP(外部)、MTIP(Timer)、MSIP(软件)，电平触发，8个CSR寄存器完整实现
  + *AMBA两级总线*：AHB-Lite系统总线（SRAM+APB桥）→ APB外设总线（GPIO/Timer/UART/SPI），标准化外设扩展
  + *Cache + MMIO旁路*：ICache/DCache BRAM IP + 控制器，bit31地址译码实现MMIO直连总线
  + *CPU总线直连*：cpu\_bus\_bridge直接驱动AHB-Lite信号，省去中间层，减少延迟
  + *CSR/Trap模块化*：cpu\_trap\_csr封装trap\_manager + csr\_interface，职责分离
  + *验证通过*：116项测试全部通过（CPU综合33 + CPU运算33 + CPU异常8 + AHB总线3 + APB外设10 + ALU集成11 + MU单元10 + 除法器8）
  + *FPGA验证就绪*：system\_top + XDC约束 + LCD调试显示，可综合部署
]

通过本次实验，我们在上一次基础CPU设计的基础上，深入实践了嵌入式处理器的完整设计流程：从指令集扩展（M/Zicsr）、特权架构实现（异常/中断/CSR）、到系统总线集成（AHB-Lite/APB）和外设接入（GPIO/Timer/UART/SPI）。同时，通过流水线优化（快速路径、ALU单周期化、字节掩码写入）显著提升了处理器性能。该项目从简单的BRAM直连模型演进为AMBA标准两级总线架构，为后续接入更多外设（SPI Flash存储、GPIO扩展、DMA等）奠定了基础。
