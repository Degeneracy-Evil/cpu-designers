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
  align(center)[#text(size: 18pt)[负责人：王之翼#h(1em)18996388318\    张潘妍    张之恒    陈海攀]]
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年5月18日]]
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

设计语言：SystemVerilog

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
  + 指令集：RV32I(40条) + M(8条) + Zicsr(6条) + Zifencei(1条) = 55条
  + 完整异常处理：非法指令、ECALL、EBREAK、地址未对齐
  + 三级中断响应：MEIP(外部,PLIC仲裁)、MTIP(Timer,CLINT直连)、MSIP(软件,预留)，电平触发
  + 18个有效CSR地址：mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip + mcycle/minstret/mcycleh/minstreth + 5个只读标识寄存器
  + AHB-Lite系统总线（4从设备: SRAM/PLIC/CLINT/Bridge）→ APB外设总线（4从设备）
  + ICache/DCache控制器 + BRAM IP，MMIO旁路（bit31=0时访问总线外设，bit31=1时访问Cache）
  + CLINT（mtime/mtimecmp）产生MTIP直连CPU；PLIC（8源）管理外部中断输出MEIP
  + 串口通信：UART+GPIO（连接到LED上）
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
  + 特权架构规范：#link("https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf")[riscv-privileged.pdf]
  + 平台级中断控制器：#link("https://docs.riscv.org/reference/plic/_attachments/riscv-plic.pdf")[riscv-plic.pdf]
]

== 项目文件夹结构

```text
dev/
├─rtl/
│  ├─core/                        CPU核心模块
│  │    core_top.sv               CPU顶层
│  │    cpu_controller.sv         FSM控制器
│  │    icache_ctrl.sv            ICache控制器
│  │    dcache_ctrl.sv            DCache控制器
│  │    MMU.sv                    内存管理单元 (直通, 预留)
│  │    cpu_fetch.sv              取指阶段
│  │    cpu_decode.sv             译码阶段
│  │    cpu_execute.sv            执行阶段
│  │    cpu_mem.sv                访存阶段
│  │    cpu_wb.sv                 回写阶段
│  │    cpu_regfile.sv            寄存器堆
│  │    cpu_trap_csr.sv           异常/CSR顶层封装
│  │    cpu_trap_manager.sv       异常检测与trap管理
│  │    cpu_clint.sv              中断控制逻辑
│  │    cpu_csr_interface.sv      CSR指令接口
│  │    cpu_csr.sv                CSR寄存器存储
│  │    cpu_bus_bridge.sv         CPU→AHB-Lite直接桥接
│  │    op_regroup.sv             指令字段拆分
│  │    branch_comparator.sv      分支比较器
│  │
│  ├─ALU/                         ALU模块
│  │    alu_32bit.sv              ALU顶层 (内联减法逻辑)
│  │    alu_result_selector.sv    ALU结果选择器
│  │    cla_adder_16bit.sv        16位超前进位加法器
│  │    cla_adder_32bit.sv        32位超前进位加法器
│  │    cla_adder_4bit.sv         4位超前进位加法器
│  │    logic_unit.sv             逻辑运算单元
│  │    lui.sv                    高位加载
│  │    mux.sv                    选择器 (行为级)
│  │    shifter.sv                位移器 (行为级对数移位)
│  │
│  ├─MU/                          乘除法单元
│  │    mu_unit.sv                乘除法调度
│  │    booth_multiplier.sv       Booth乘法器
│  │    non_restoring_divider.sv  非恢复余数除法器
│  │
│  ├─AHB-lite/                    AHB-Lite系统总线
│  │    ahb_lite_bus.sv           AHB外设总线顶层
│  │    ahb_decoder.sv            AHB地址译码 (未实例化)
│  │    ahb_mux.sv                AHB读数据MUX
│  │    ahb_sram_slave.sv         AHB SRAM从设备
│  │    ahb_clint.sv              AHB CLINT从设备
│  │    ahb_plic.sv               AHB PLIC从设备
│  │
│  ├─APB/                         APB外设总线
│  │    ahb_lite_to_apb.sv        AHB→APB桥
│  │    apb_slave.sv              APB通用从设备
│  │    apb_perips.sv             APB外设容器
│  │    perips/
│  │        gpio.sv               GPIO (16bit双向)
│  │        timer.sv              Timer (含IRQ)
│  │        uart_top.sv           UART顶层
│  │        spi.sv                SPI主机
│  │
│  └─system_top.sv                FPGA系统顶层
│
├─tb/                             测试台
├─program_source/                 测试程序
└─fpga/                           FPGA集成
    cpu.xdc                       引脚约束
    lcd_module.dcp                LCD预编译IP
```

= 实现细节

== 语言迁移

我们此次从Verilog语言迁移到了SystemVerilog语言，但是请不要担心，SystemVerilog是Verilog的超集，且我们当前几乎所有文件都按照Verilog语言语法构建，容易阅读，且使用我们的tcl脚本很容易完成项目构建以及仿真。

我们切换到SystemVerilog的原因是PLIC器件中一个接口如果不使用SV的数组语法则构建相当困难，为了构建方便且更加易读，切换到了SV，又为了文件统一，我们将所有文件的后缀都改为了`.sv`。

== 指令集扩展

在上一次实验实现的37条RV32I指令基础上，本次扩展至55条，新增M扩展8条、Zicsr扩展6条、Zifencei扩展1条，以及RV32I中此前未实现的3条（ECALL、EBREAK、FENCE）。

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

Zifencei扩展仅包含`FENCE.I`指令，用于指令缓存刷新，当前由于未使用主存，没有内存屏障限制，实现中为直接跳过。

此外，添加系统控制指令`ECALL`、`EBREAK`、`MRET`支持，分别触发异常进入和中断返回。详见"#link(<expact_exe>)[异常处理]"小节。

== CPU核优化

为了优化CPU核的结构以及CPI，我们对流水线、ALU和访存路径结构进行了重构。

=== 执行-回写数据链路

在之前实验的设计中，所有非分支指令执行后都必须经过MEM阶段（即使不需要访存），MEM阶段虽然做了直通，但还是占用了大量周期。为了优化CPI，我们优化了流水线路径，添加了exe->wb路径：

此优化使所有非分支非访存指令的执行周期下降2。完整状态机见#link(<c-ex>)[控制器扩展]小节。

=== ALU单周期化-MU扩展<MU>

由于从第一次实验继承来的ALU模块内部集成了Booth乘法器和非恢复余数除法器，使得其必须通过握手协议（`req_valid`/`result_valid`）与执行模块交互，但又没有M指令集，导致没有指令实际使用乘除法功能，平白为所有经过ALU计算的指令引入3周期额外开销（请求发射→结果锁存→读取`done_reg`）。

本次实验中我们将乘除法从ALU中分离为独立的`mu_unit`模块：

#move(dx: 2em)[
  - *ALU*：仅保留单周期组合逻辑运算（ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI/NOR/NOT），变为纯组合逻辑模块，移除握手协议，消除握手耗时。
]
#move(dx: 2em)[
  - *MU*：独立出来的乘除法单元，内部为从ALU中剥离出来的`booth_multiplier`和`non_restoring_divider`，通过`mu_req_valid`/`mu_result_valid`握手协议与执行模块交互，以支持M扩展指令。
]

ALU控制编码变化（one-hot，bit0保留）：

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

Cache控制器目前主要用于进行MMIO区分：当`is_mmio = ~cpu_req_addr[31]`，地址bit31=0时进行MMIO（访问外设区），bit31=1时访问Cache（DRAM区）。

控制器输出经过MUX选择：`cpu_req_data = is_mmio ? mmio_data : icache_dout`

MMIO地址空间：`0x00000000-0x7FFFFFFF`（bit31=0，访问总线外设），Cache地址空间：`0x80000000-0xFFFFFFFF`（bit31=1，访问DRAM），详细见#link(<mmap>)[内存映射模型]。

同时，我们升级了BRAM IP，现在cache来到了$32 times 4096=16"KB"$，并且支持了字节读写（`wea,web`变为四位，支持多种宽度读写），简化了访存的操作逻辑。

== 控制器扩展<c-ex>

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
  [指令未对齐], [0], [pc未4字节对齐],
  [非法指令], [2], [opcode/funct未定义，或CSR地址无效],
  [EBREAK], [3], [执行EBREAK指令],
  [Load地址未对齐], [4], [LH/LHU bit0≠0，LW bit\[1:0\]≠0],
  [Store地址未对齐], [6], [SH bit0≠0，SW bit\[1:0\]≠0],
  [ECALL (M-mode)], [11], [M模式下执行ECALL],
)

异常优先级：按照规范设置同步异常优先于中断（保证中断时指令点是清楚的）；同一指令边界上的同步异常先处理。

=== CSR寄存器

实现了18个有效地址的Machine模式CSR寄存器：

#table(
  columns: (auto, auto, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*地址*], [*名称*], [*读写*], [*说明*],
  [0x300], [mstatus], [MRW], [MIE\[3\], MPIE\[7\], MPP\[12:11\]],
  [0x301], [misa], [R], [固定为 0x40001100],
  [0x304], [mie], [MRW], [MSIE\[3\], MTIE\[7\], MEIE\[11\]],
  [0x305], [mtvec], [MRW], [trap基址（中断服务程序的基地址）],
  [0x310], [mstatush], [R], [固定为 0],
  [0x340], [mscratch], [MRW], [暂存寄存器],
  [0x341], [mepc], [MRW], [异常指令PC寄存器],
  [0x342], [mcause], [MRW], [异常原因],
  [0x343], [mtval], [MRW], [异常附加值],
  [0x344], [mip], [MR], [MEIP\[11\], MTIP\[7\], MSIP\[3\]由硬件驱动],
  [0xB00], [mcycle], [MRW], [64位周期计数器低32位],
  [0xB02], [minstret], [MRW], [64位提交计数器低32位],
  [0xB80], [mcycleh], [MRW], [64位周期计数器高32位],
  [0xB82], [minstreth], [MRW], [64位提交计数器高32位],
  [0xF11], [mvendorid], [R], [固定为 0],
  [0xF12], [marchid], [R], [固定为 0],
  [0xF13], [mimpid], [R], [固定为 0],
  [0xF14], [mhartid], [R], [固定为 0],
  [0xF15], [mconfigptr], [R], [固定为 0],
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

支持三级中断，电平触发（持续到软件ack）：

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

中断源连接：

总线上的PLIC设备连接到MEIP，总线上的CLINT设备连接到MTIP（设备描述见总线下的设备描述部分）。

目前来源于总线设备的中断有两个，均为定时器：
#move(dx: 3em)[
  - 规范中定义的`mtime`：`AHB CLINT`产生本地定时器中断`o_mtip`，直连CPU核心`timer_irq`（触发MTIP，Cause 7）
  - `APB Timer`产生外设定时器中断，连接到`AHB PLIC`的`src_irq[1]`，经PLIC仲裁后输出`o_eip`至CPU网络`ext_meip_in`（触发MEIP，Cause 11）。
]

中断和异常检测点在指令间隔，具体为EXEC完成（分支指令）和WB完成（其他）后。

== 系统总线

系统总线我们选择了ARM AMBA的AHB-Lite总线，原因是具有流水线传输机制，性能较好，同时较简单，且规范易于扩展。

=== AHB-Lite总线特性

AHB-Lite是AMBA总线族中的高性能系统总线，主要特性如下：

#move(dx: 2em)[
  + *流水线传输*：地址相位与数据相位重叠，前一笔传输的数据相位与后一笔传输的地址相位在同一周期进行，提高总线利用率
  + *单主设备*：AHB-Lite仅支持一个主设备（本系统中为CPU），无需仲裁
  + *多从设备*：通过地址译码器选择从设备，支持1/2/4/8个从设备
  + *突发传输*：支持SINGLE/INCR/WRAP4/WRAP8/WRAP16等突发类型（本系统仅使用SINGLE）
  + *传输宽度*：支持BYTE(8)/HWORD(16)/WORD(32)三种传输宽度
  + *错误响应*：从设备可通过HRESP返回ERROR/OKAY状态
]

=== AHB-Lite基本协议

AHB-Lite每次传输分为*地址相位*和*数据相位*两个阶段，各占一个HCLK周期：

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let w = 3.5
  let h = 0.8
  let y1 = 3.0
  let y2 = 1.8
  let y3 = 0.6

  for i in range(4) {
    let x = i * w
    line((x, 0), (x, 4), stroke: (dash: "dotted", paint: gray))
  }
  content((0.5 * w, 4.0), [#text(size: 10pt, "Cycle N")])
  content((1.5 * w, 4.0), [#text(size: 10pt, "Cycle N+1")])
  content((2.5 * w, 4.0), [#text(size: 10pt, "Cycle N+2")])
  content((3.5 * w, 4.0), [#text(size: 10pt, "Cycle N+3")])

  rect((0, y1), (w, y1 + h), fill: rgb("#4a90d9"), stroke: none)
  content((0.5 * w, y1 + 0.4), [#text(size: 9pt, fill: white, "Addr Phase 1")])

  rect((w, y1), (2 * w, y1 + h), fill: rgb("#d94a4a"), stroke: none)
  content((1.5 * w, y1 + 0.4), [#text(size: 9pt, fill: white, "Data Phase 1")])

  rect((w, y2), (2 * w, y2 + h), fill: rgb("#4a90d9"), stroke: none)
  content((1.5 * w, y2 + 0.4), [#text(size: 9pt, fill: white, "Addr Phase 2")])

  rect((2 * w, y2), (3 * w, y2 + h), fill: rgb("#d94a4a"), stroke: none)
  content((2.5 * w, y2 + 0.4), [#text(size: 9pt, fill: white, "Data Phase 2")])

  content((-0.3, y1 + 0.4), anchor: "east", [#text(size: 9pt, "Transfer 1")])
  content((-0.3, y2 + 0.4), anchor: "east", [#text(size: 9pt, "Transfer 2")])
})]

*关键信号*：

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*信号*], [*方向*], [*说明*],
  [`HCLK`], [—], [总线时钟，上升沿采样],
  [`HRESETn`], [—], [异步复位，低有效],
  [`HADDR[31:0]`], [M→S], [32位地址，地址相位有效],
  [`HTRANS[1:0]`], [M→S], [传输类型：IDLE(00)/BUSY(01)/NONSEQ(10)/SEQ(11)],
  [`HWRITE`], [M→S], [写使能：1=写，0=读],
  [`HSIZE[2:0]`], [M→S], [传输宽度：000=BYTE, 001=HWORD, 010=WORD],
  [`HBURST[2:0]`], [M→S], [突发类型：000=SINGLE, 其余INCR/WRAP等],
  [`HWDATA[31:0]`], [M→S], [写数据，数据相位有效],
  [`HRDATA[31:0]`], [S→M], [读数据，数据相位有效],
  [`HREADY`], [S→M], [从设备就绪：1=传输完成，0=插入等待状态],
  [`HRESP`], [S→M], [传输响应：0=OKAY, 1=ERROR],
  [`HSELx`], [Dec→S], [从设备选择信号，由地址译码器产生],
)

*传输交互流程*（以单笔读传输为例）：

#move(dx: 2em)[
  + 沿N（地址相位）：主设备驱动`HADDR`、`HTRANS=NONSEQ`、`HWRITE=0`、`HSIZE`，译码器产生`HSELx`
  + 沿N+1（数据相位）：从设备在`HSELx && HREADY`时采样地址，输出`HRDATA`，驱动`HREADY`
  + 若`HREADY=0`，从设备插入等待状态，主设备保持信号不变
  + `HREADY=1`时传输完成，主设备可发起下一笔传输
]

本系统中所有传输均为`HTRANS=NONSEQ`、`HBURST=SINGLE`的单笔传输，从设备零等待（`HREADY=1`），简化了协议实现。

=== 总线拓扑

#align(center)[#cetz.canvas({
  import cetz.draw: *

  rect((0, 2), (3, 3), name: "bridge")
  content("bridge", [#text(size: 10pt, "cpu_bus_bridge")])

  rect((5, 0), (10, 5), name: "bus")
  content("bus.north", anchor: "south", [#text(size: 10pt, "ahb_lite_bus")])

  rect((5.5, 3.5), (9.5, 4.5), name: "decoder")
  content("decoder", [#text(size: 10pt, "ahb_decoder")])

  rect((5.2, 1), (6.2, 2.5), name: "sram")
  content("sram", [#text(size: 9pt, "SRAM")])

  rect((6.4, 1), (7.4, 2.5), name: "plic")
  content("plic", [#text(size: 9pt, "PLIC")])

  rect((7.6, 1), (8.6, 2.5), name: "clint")
  content("clint", [#text(size: 9pt, "CLINT")])

  rect((8.8, 1), (9.8, 2.5), name: "apbb")
  content("apbb", [#text(size: 9pt, [AHB\ to\ APB])])

  line("bridge.east", "bus.west", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "AHB-Lite")])

  line("decoder.south", "sram.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_sram")
  line("decoder.south", "plic.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_plic")
  line("decoder.south", "clint.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_clint")
  line("decoder.south", "apbb.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_apb")

  content((name: "bus_sram", anchor: 50%), anchor: "east", [#text(size: 8pt, "HSEL0")])
  content((name: "bus_apb", anchor: 50%), anchor: "west", [#text(size: 8pt, "HSEL3")])
})]

AHB-Lite总线当前挂载4个从设备：

#table(
  columns: (auto, auto, auto, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*从设备*], [*选择条件*], [*模块*], [*说明*],
  [Slave 0], [HADDR\[31:24\]=0x00], [`ahb_sram_slave`], [主存Sram],
  [Slave 1], [HADDR\[31:24\]=0x0C], [`ahb_plic`], [PLIC 中断控制器 (16MB)],
  [Slave 2], [HADDR\[31:24\]=0x02], [`ahb_clint`], [CLINT 核心本地中断器 (16MB)],
  [Slave 3], [HADDR\[31:24\]=0x10], [`ahb_lite_to_apb`], [APB桥，连接外设（UART0/VirtIO等）],
)

以下是各个设备的介绍：

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

=== AHB CLINT从设备

CLINT（Core Local Interruptor）核心中断处理器，总线上的专门负责MTIP的执行，核心内部的则负责所有中断的顶层处理：
#move(dx: 2em)[
  - 64位`mtime`计数器：每个时钟周期自增1
  - 64位`mtimecmp`比较寄存器：通过总线写入
  - MTIP输出：`o_mtip = (mtime >= mtimecmp) && (mtimecmp != 0)`，直连CPU核心`timer_irq`
]

=== AHB PLIC从设备

PLIC（Platform-Level Interrupt Controller）平台控制器，工作是管理外设的中断信号，负责仲裁优先级以及通知CPU。

PLIC的输入是专用中断信号线，用于接收外设中断信号（目前只连接了Timer的中断信号，`Source ID=1`），输出是到CPU的MEIP（外设中断）的中断信号线，负责通知CPU有外设中断等待处理。

CPU通过MMIO访问外设，PLIC只负责中断信号传递，不负责数据传递。

=== SRAM从设备

主存，现阶段未使用，占位用。

== 内存映射模型<mmap>

在内存布局上，我们参考了QEMU riscv virt机器的内存映射模型：

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

比较遗憾的是我们当前的Cache逻辑上是互相独立的，要实现程序无感需要i/dcache均加载coe文件初始化，所以并没有完整实现此内存布局，预计下一个实验中会实现。

== 外设总线

外设总线我们选择了ARM AMBA的APB总线，原因是实现简单，功耗低，规范易于扩展，适合连接低速外设。

=== APB总线特性

APB是AMBA总线族中的低功耗外设总线，主要特性如下：

#move(dx: 2em)[
  + *非流水线传输*：每次传输需完整的SETUP+ACCESS两个周期，无地址/数据重叠
  + *单主设备*：由AHB-to-APB桥充当唯一主设备
  + *多从设备*：通过`PSELx`选择从设备，当前挂载4个
  + *无突发*：每次传输独立，不支持突发机制
  + *字节掩码*：通过`PSTRB[3:0]`支持字节级写使能
  + *低功耗*：所有信号在时钟上升沿变化，无复杂流水逻辑
]

=== APB基本协议

APB每次传输经历*IDLE → SETUP → ACCESS*三个状态，SETUP和ACCESS各占一个PCLK周期：

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let w = 3.0
  let h = 0.6
  let y = 0

  for i in range(3) {
    let x = i * w
    line((x, -0.5), (x, 3.5), stroke: (dash: "dotted", paint: gray))
  }
  content((0.5 * w, 3.2), [#text(size: 10pt, "Cycle N")])
  content((1.5 * w, 3.2), [#text(size: 10pt, "Cycle N+1")])
  content((2.5 * w, 3.2), [#text(size: 10pt, "Cycle N+2")])

  rect((0, 2.2), (w, 2.2 + h), fill: rgb("#999999"), stroke: none)
  content((0.5 * w, 2.2 + 0.3), [#text(size: 9pt, fill: white, "IDLE")])

  rect((w, 2.2), (2 * w, 2.2 + h), fill: rgb("#4a90d9"), stroke: none)
  content((1.5 * w, 2.2 + 0.3), [#text(size: 9pt, fill: white, "SETUP")])

  rect((2 * w, 2.2), (3 * w, 2.2 + h), fill: rgb("#d94a4a"), stroke: none)
  content((2.5 * w, 2.2 + 0.3), [#text(size: 9pt, fill: white, "ACCESS")])

  content((-0.3, 2.5), anchor: "east", [#text(size: 9pt, "状态")])

  rect((w, 1.2), (2 * w, 1.2 + h), fill: rgb("#4a90d9"), stroke: none)
  content((1.5 * w, 1.2 + 0.3), [#text(size: 9pt, "PSEL=1")])
  content((-0.3, 1.5), anchor: "east", [#text(size: 9pt, "PSELx")])

  rect((2 * w, 0.2), (3 * w, 0.2 + h), fill: rgb("#d94a4a"), stroke: none)
  content((2.5 * w, 0.2 + 0.3), [#text(size: 9pt, "PENABLE=1")])
  content((-0.3, 0.5), anchor: "east", [#text(size: 9pt, "PENABLE")])
})]

*关键信号*：

#table(
  columns: (1fr, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*信号*], [*方向*], [*说明*],
  [`PCLK`], [—], [总线时钟，上升沿采样],
  [`PRESETn`], [—], [异步复位，低有效],
  [`PSELx`], [M→S], [从设备选择，1=选中],
  [`PENABLE`], [M→S], [访问使能：SETUP阶段为0，ACCESS阶段为1],
  [`PWRITE`], [M→S], [写使能：1=写，0=读],
  [`PADDR[31:0]`], [M→S], [地址],
  [`PWDATA[31:0]`], [M→S], [写数据],
  [`PRDATA[31:0]`], [S→M], [读数据],
  [`PREADY`], [S→M], [从设备就绪：1=传输完成（本系统恒为1）],
  [`PSTRB[3:0]`], [M→S], [字节写掩码：0=不写，1=写],
  [`PSLVERR`], [S→M], [错误响应（本系统恒为0）],
)

*传输交互流程*（以写传输为例）：

#move(dx: 2em)[
  + *IDLE*：`PSELx=0`，`PENABLE=0`，总线空闲
  + *SETUP*（沿N）：桥驱动`PSELx=1`、`PWRITE=1`、`PADDR`、`PWDATA`、`PSTRB`，`PENABLE=0`
  + *ACCESS*（沿N+1）：`PENABLE=1`，从设备在`PCLK`上升沿采样写数据，`PREADY=1`时传输完成
  + 传输完成后回到IDLE或直接进入下一笔SETUP（背靠背传输）
]

读传输类似，ACCESS阶段从设备输出`PRDATA`，主设备在`PCLK`上升沿采样。本系统中所有从设备`PREADY`恒为1（零等待），`PSLVERR`恒为0（无错误响应）。

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

APB总线挂载4个从设备译码段，用以适配更新后的外设地址段位映射（包含向virt映射）：

#table(
  columns: (auto, auto, 1fr),
  align: (horizon, center),
  stroke: 0.5pt,
  inset: 6pt,
  [*从设备*], [*译码地址区间/匹配基准*], [*模块或映射说明*],
  [Slave 0], [0x1000_0000 区域], [UART0 (RX+TX, 兼容virt空间)],
  [Slave 1], [0x1000_1000 区域], [VirtIO0 MMIO (预留)],
  [Slave 2], [其它映射], [Timer (含IRQ) / GPIO等复用],
  [Slave 3], [其它映射], [SPI主机等扩展外设],
)

以下是各个设备的介绍：

=== AHB-to-APB桥

`ahb_lite_to_apb`实现将AHB-Lite传输转换为APB协议，连接外设总线和系统总线。

=== 外设

#table(
  columns: (auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*外设*], [*说明*],
  [GPIO], [16bit双向IO，方向控制+数据寄存器，当前连接LED作走马灯],
  [Timer], [32位计数器+阈值+使能，匹配时产生IRQ，连接PLIC源1产生ext\_meip\_in外部中断],
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

  line(
    "execute.south",
    (rel: (0, -0.5), to: "execute.south"),
    (rel: (0, -0.5), to: "wb.south"),
    "wb.south",
    mark: (end: "straight"),
    stroke: (dash: "dashed", paint: blue),
    name: "exe_wb",
  )
  content("exe_wb", anchor: "north", padding: .05, [#text(size: 9pt, fill: blue, "exe→wb")])

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

其中蓝色虚线为新增的*exe→wb路径*，R/I-type运算指令执行完成后跳过MEM阶段直接进入WB，减少2周期开销。

= 仿真验证

== 测试框架

#table(
  columns: (auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*Testbench*], [*测试内容*],
  [`tb_simple_cpu_top`], [CPU综合测试（ALU/访存/对齐/CSR/异常/中断）],
  [`tb_simple_cpu_compute`], [CPU运算指令测试（M扩展+算术）],
  [`tb_simple_cpu_trap`], [CPU异常/中断测试],
  [`tb_uart_hello`], [UART Hello World发送测试],
  [`tb_led_marquee`], [LED走马灯测试],
)

均在`dev/tb`目录下。

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
)

均在`dev/program_source`目录下，可以通过tools目录下的`rv2coe`工具编译为coe文件，要求有gcc交叉编译器（推荐在wsl中安装，脚本会自动检测）。

=== 综合测试程序

综合测试程序覆盖了CPU大多数功能的测试，以下是关键部分：

#box(height: 13em)[#columns(2, gutter: 5pt)[```asm
150    la x10, trap_handler
151    csrw mtvec, x10
152    li x10, 0x88
153    csrw mstatus, x10
154    li x10, 0x800
155    csrw mie, x10
157    csrw mscratch, x0
159    addi x1, x0, 0
160    ecall
162    addi x1, x0, 1
164    ebreak
166    addi x1, x0, 2
168    .word 0x0000007F
170    addi  x1, x0, 3
245 trap_handler:
246    csrrs x19, mcause, x0
247    csrrs x20, mepc, x0
248    addi x20, x20, 4
249    csrw mepc, x20
250    csrrs x21, mscratch, x0
251    slli x21, x21, 2
252    addi x22, x21, 72
```]]

```asm
253    sw x19, 0(x22)
254    csrrs x21, mscratch, x0
255    addi x21, x21, 1
256    csrw mscratch, x21
257    li x10, 0x80
258    csrw mstatus, x10
259    mret
```
这段代码展示了异常测试和异常服务程序，涵盖了自陷入和指令异常的情况。`cpu_test.s`中还有关于基础指令、M指令集、时钟中断的测试，内容较多，详细请查看源码。

=== LED跑马灯演示程序
#box(height: 42em)[#columns(2, gutter: 12pt)[
  ```asm
  .equ GPIO_BASE, 0x10000000
  .equ CLINT_BASE, 0x02000000
  .equ TIMER_PERIOD, 10000000
  .section .text
  .globl _start
  _start:
      la t0, isr
      csrw mtvec, t0
      # Enable MTIE in mie(bit7)
      li t0, 0x80
      csrw mie, t0
      # Enable MIE in mstatus(bit3)
      li t0, 0x8
      csrw mstatus, t0
      # Initialize GPIO direction (all output)
      lui x10, 0x10000
      li x11, 0xFFFF
      sw x11, 0(x10)
      # Initialize LED state
      li x12, 0
      li x11, 1
      xori x13, x11, -1
      sw x13, 4(x10)
      lui x15, 0x02000
      lw x16, 8(x15)
      lw x14, 12(x15)
      li x11, TIMER_PERIOD
      mv x13, x16
      add x16, x16, x11
      sltu x11, x16, x13
      add x14, x14, x11
      sw x16, 0(x15)
      sw x14, 4(x15)
  loop:
      j loop
  .align 4
  isr:
      csrrw sp, mscratch, sp
      addi sp, sp, -24
      sw x11, 0(sp)
      sw x13, 4(sp)
      sw x14, 8(sp)
      sw x15, 12(sp)
      sw x16, 16(sp)
      lui x15, 0x02000
      lw x16, 8(x15)
      lw x14, 12(x15)
      li x11, TIMER_PERIOD
      mv x13, x16
      add x16, x16, x11
      sltu x11, x16, x13
      add x14, x14, x11
      sw x16, 0(x15)
      sw x14, 4(x15)
      # Update LED state
      addi x12, x12, 1
      li x11, 16
      bne x12, x11, skip_reset
      li x12, 0
  skip_reset:
      lui x10, 0x10000
      li x11, 1
      sll x13, x11, x12
      xori x13, x13, -1
      sw x13, 4(x10)
      lw x11, 0(sp)
      lw x13, 4(sp)
      lw x14, 8(sp)
      lw x15, 12(sp)
      lw x16, 16(sp)
      addi sp, sp, 24
      csrrw sp, mscratch, sp
      mret
  ```]]

通过计时器中断服务程序`isr`定时修改GPIO（连接到LED）的输出状态来改变LED的状态，每一亿个时钟周期触发一次，每次输出数据都是循环右移一位，即LED亮灯位置0.1s循环右移一次。

=== UART测试程序

#box(height: 18em)[
  #columns(2, gutter: 12pt)[
    ```asm
    .equ UART_BASE, 0x80008000
    .equ UART_CTRL,   0x00
    .equ UART_STATUS, 0x04
    .equ UART_TXDATA, 0x08
    .section .text
    .globl _start
    _start:
        lui x10, 0x80008
        li x11, 0x01
        sw x11, UART_CTRL(x10)
        la x20, msg
        mv x21, x20
    send_loop:
        lb x12, 0(x21)
        beq x12, x0, done
    wait_tx:
        lw x13, UART_STATUS(x10)
        andi x13, x13, 1
        bne x13, x0, wait_tx

        sw x12, UART_TXDATA(x10)

        addi x21, x21, 1
        j send_loop
    done:
        mv x21, x20
        j send_loop
    msg:
        .byte 'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd', 0
    ```
  ]
]

此程序通过MMIO调用UART设备，循环发送`Hello World`字符串。

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
)

共74项测试全部通过模拟测试。重要测试结果以及上板结果见下。

=== 综合测试

模拟测试：
#image("media/cpu1-控制台.png", height: 80%)
#image("media/cpu1-波形.png")
上板结果：
#image("media/嵌入式cpu测试.jpg")

可见运行正常。

=== 走马灯测试

上板结果：
#image("media/走马灯.jpg")

视频见压缩包中`走马灯.mp4`文件。

=== UART测试

上板结果：
#image("media/uart.jpg")

通过tools中的`uart_reader.py`作为上位机读取串口数据截图：
#image("media/上位机读取1.png")
#image("media/上位机读取2.png")

可见所有测试均通过，上板验证均达到效果。

= 性能计算<PerformanceCalculation>

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
  + *exe\_to\_wb路径*：R/I-type跳过MEM（减少2周期）
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

= 结论

本项目在基础RV32I多周期CPU核之上，成功扩展和实现了一个32位RISC-V多周期嵌入式处理器，主要成果如下：

#move(dx: 2em)[
  + 指令集扩展：支持M扩展、Zicsr扩展、Zifencei扩展，以及ECALL/EBREAK/MRET系统控制指令
  + ALU，数据通路的CPI优化，性能大概提升了$51%$
  + 完整支持异常处理：实现非法指令、ECALL、EBREAK、地址未对齐异常
  + 支持三种中断响应，以及机器模式8个CSR寄存器完整实现
  + Cache控制器的MMIO旁路支持
  + 仿真验证通过
  + FPGA验证通过
]

本次实验，我们在上一次基础CPU设计的基础上，实现了CPU核的异常处理机制，扩展了外部设备，总的来说完成了实验目标。同时，通过流水线优化和结构优化显著提升了处理器性能。

在本次实验中，我们更加深入地了解了计算机硬件的组成部分以及相互间的交互，学习了riscv的中断、异常处理以及特权级架构，通过优化CPU流水线以及结构明白了一些微小设计对于CPU性能的巨大影响。同时，也学习了如何编写中断处理服务程序，以及如何进行完整的中断处理。



= 工具使用

== vivado_do.tcl
vivado_do.tcl — Vivado 仿真自动化脚本

用法:
#move(dx: 2em)[```cmd
$ vivado.bat -mode tcl
Vivado% source vivado_do.tcl -notrace -encoding utf-8
Vivado% vivado_do [-create] [-sim <tb>] [-runtime <t>] [-clear] [-bitstream] [-hw_connect] [-program]
```]

集合了项目创建、仿真、生成bit流等功能，详细命令见文件头部描述。

== tools/rv2coe.py

将riscv程序（汇编/c）编译为coe文件。

需要在本地或者wsl中有（Windows时会自动尝试查找本地以及wsl）：

#move(dx: 2em)[- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-objdump`（仅 `--check-isa` 时需要）]

详细用法见`tools\README-rv2coe.md`。

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
