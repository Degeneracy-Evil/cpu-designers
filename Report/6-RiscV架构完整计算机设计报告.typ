// 计算机组成原理实验报告模板（Typst）
#set title("RiscV架构完整计算机设计报告")
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
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年7月4日]]
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
  + `RISCV32-IMAFD_Zicsr_Zifencei`多周期CPU（含双精度浮点扩展D）
  + 构建完整计算机系统：CPU + 总线 + 主存 + 外设
  + 系统总线升级为AXI4，支持突发传输和时钟域穿越
  + 引入DDR3主存（FPGA）或SRAM仿真模型
  + 引入Boot ROM，支持从ROM启动
  + 浮点扩展F（单精度）+ D（双精度，非FMA部分）
  + 运行SimpleOS微型操作系统（M/S/U特权 + Sv32分页）
  + 成功进入Linux内核态（OpenSBI + Linux内核启动，内核panic阶段）
]

== 已实现的特性

#move(dx: 2em)[
  + 指令集：RV32I(40条) + M(8条) + A(11条) + F(22条) + D(22条非FMA) + Zicsr(6条) + Zifencei(1条) = 110条
  + 完整Sv32虚拟内存：MMU统一翻译FSM(11状态) + TLB(4路×4组) + PTW(8状态FSM)
  + 四路组相联Cache（i/d各1KB），写回策略，Tree-PLRU替换，*PIPT*（物理索引物理标签）
  + AXI4系统总线（单主7从）→ APB4外设总线（4从）
  + AXI4时钟域穿越（cpu\_clk→sys\_clk），SpinalHDL生成
  + DDR3主存（FPGA，Xilinx MIG）或BRAM仿真模型
  + Boot ROM（8K条目，0xFC000000）
  + CLINT（mtime/mtimecmp）+ PLIC（8源，M/S双上下文）
  + 四外设：GPIO(16bit)、Timer(含IRQ)、UART 16550A(含FIFO)、SPI
  + FPU：单精度+双精度浮点运算单元（加/减/乘/除/开方/FMA/转换/比较/分类/符号注入），5状态显式FSM + 超时看门狗
  + M/S/U三级特权，陷阱委托（medeleg/mideleg）
  + 64位浮点寄存器堆（32×64-bit），NaN-boxing支持
  + SimpleOS微型操作系统：M→S→U三级特权转换 + Sv32分页 + ecall系统调用
  + Linux内核启动：OpenSBI固件 + Linux内核进入S-mode分页，推进至内核虚拟空间C0377xxx
]

== 参考资料

#move(dx: 2em)[
  + RISC-V-Reader-Chinese-v2p12017.pdf
  + RISC-V特权架构规范：#link("https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf")[riscv-privileged.pdf]
  + RISC-V外部中断规范：#link("https://docs.riscv.org/reference/plic/_attachments/riscv-plic.pdf")[riscv-plic.pdf]
  + AXI4协议规范：#link("https://developer.arm.com/documentation/ihi0022/latest")[IHI0022G_amba_axi_protocol_spec.pdf]
  + APB4协议规范：#link("https://developer.arm.com/documentation/ihi0024/latest")[IHI0024E_amba_apb_architecture_spec.pdf]
  + FPGA引脚参考：FPGA-A7-PRJ-UDB_V1.0-引脚坐标参考.pdf
  + 所有课程PPT（指导老师：何安平）
  + tree-PLRU算法：#link("https://people.computing.clemson.edu/~mark/464/p_lru.txt")[p_lru.txt]
]

== 项目文件夹结构

#text(size: 10pt)[
  ```text
  dev/rtl/
  ├── system_top.sv                  # SoC顶层
  ├── soc_config.vh                  # SoC配置宏
  ├── axi4_def.svh                   # AXI4总线定义
  ├── clk_wiz_0_passthrough.sv       # 时钟直通（仿真用）
  │
  ├── core/                          # CPU核心
  │   ├── core_top.sv                #   核心顶层
  │   ├── cpu_controller.sv          #   流水线控制器（11状态FSM）
  │   ├── cpu_fetch.sv               #   取指
  │   ├── cpu_decode.sv              #   译码
  │   ├── cpu_execute.sv             #   执行
  │   ├── cpu_mem.sv                 #   访存
  │   ├── cpu_wb.sv                  #   回写
  │   ├── cpu_regfile.sv             #   整数寄存器堆
  │   ├── cpu_trap_csr.sv            #   异常/CSR处理
  │   ├── cpu_trap_manager.sv        #   异常检测与优先级仲裁
  │   ├── cpu_clint.sv               #   中断判定逻辑
  │   ├── cpu_bus_bridge.sv          #   AXI4主设备桥（16状态FSM）
  │   ├── icache_ctrl.sv             #   ICache控制器（5状态FSM）
  │   ├── dcache_ctrl.sv             #   DCache控制器（13状态FSM）
  │   ├── tree_plru.sv               #   Tree-PLRU替换策略
  │   ├── MMU.sv                     #   内存管理单元（统一翻译FSM 11状态）
  │   ├── tlb.sv                     #   TLB（4路×4组）
  │   ├── ptw.sv                     #   页表漫游器（8状态FSM）
  │   ├── branch_comparator.sv       #   分支比较器
  │   └── op_regroup.sv              #   指令字段拆分
  │
  ├── ALU/                           # 算术逻辑单元
  ├── MU/                            # 乘除法单元
  ├── FPU/                           # 浮点运算单元
  ├── AMBA/Axi_CDC.v                 # AXI4时钟域穿越
  ├── axi/                           # AXI4-Lite从设备
  │   ├── axi4lite_plic.sv           #   PLIC
  │   ├── axi4lite_clint.sv          #   CLINT
  │   ├── axi4lite_bootrom.sv        #   Boot ROM
  │   ├── axi4lite_default_slave.sv  #   默认从设备
  │   └── axi4lite_sys_status.sv     #   系统状态寄存器
  ├── ram_wrap/                      # 存储器封装
  │   ├── axi_wrap_ram.sv            #   BRAM仿真模型
  │   └── axi_wrap_ddr.sv            #   DDR3封装（MIG）
  ├── APB/                           # APB子系统
  │   ├── axi4lite_to_apb.sv         #   AXI4-Lite→APB4桥
  │   ├── apb_decoder.sv             #   APB地址译码
  │   └── perips/                    #   外设
  │       ├── gpio.sv, timer.sv, spi.sv
  │       └── uart16550/             #   UART 16550A
  └── common/                        # 公共模块
      ├── reset_sync.sv              #   复位同步器
      └── ila_stub.sv                #   ILA调试探针
  ```
]
= 实现细节

== 总体架构

本系统是一个基于RISC-V 32位多周期CPU的完整计算机，采用层次化总线架构，系统总线为AXI4，外设总线为APB4。系统使用两个时钟域降低时序风险：CPU核心运行在`cpu_clk`（50MHz），总线及外设运行在`sys_clk`（100MHz），通过AXI4时钟域穿越模块（Axi\_CDC）安全跨越。

=== 总架构图

以下文件描述了系统的整体架构，包括CPU内部部件、总线层次、时钟域和中断连接：

// ```plantuml
// @startuml System_Architecture
// skinparam componentStyle rectangle
// skinparam defaultFontSize 11
// skinparam packageStyle rectangle

// package "cpu_clk 域" #LightBlue {
//   package "core_top (RISC-V CPU)" as CPU {
//     package "五级流水线" {
//       component "Fetch" as IF
//       component "Decode" as ID
//       component "Execute" as EXE
//       component "Memory" as MEM
//       component "Writeback" as WB
//     }
//     component "Controller\n(11-state FSM)" as CTRL
//     component "RegFile\nx0-x31" as RF
//     component "FPU RegFile\nf0-f31" as FRF
//     component "ALU" as ALU
//     component "MU\n(Booth/NonRestoring)" as MU
//     component "FPU" as FPU
//     component "Trap/CSR" as TRAP
//     component "MMU\n(Unified FSM 11-state)" as MMU
//     component "TLB\n(4way×4set)" as TLB
//     component "PTW\n(8-state FSM)" as PTW
//     component "ICache Ctrl\n(5-state FSM)" as IC
//     component "DCache Ctrl\n(13-state FSM)" as DC
//     component "cpu_bus_bridge\n(16-state FSM)" as BRIDGE
//   }
// }

// component "Axi_CDC\n(cpu_clk→sys_clk)" as CDC #LightGray

// package "sys_clk 域" #LightYellow {
//   package "AXI4 系统总线 (手动地址译码)" as AXI_BUS {
//     component "DDR3/RAM\n(Full AXI4)\n0x8000_0000" as DDR3 #Pink
//     component "Boot ROM\n0xFC00_0000" as BOOTROM
//     component "PLIC\n0x0C00_0000" as PLIC
//     component "CLINT\n0x0200_0000" as CLINT
//     component "Sys Status\n0x0400_0000" as SYSSTAT
//     component "Default Slave\n(DECERR)" as DEFSLV
//   }
//   package "APB4 外设总线" as APB_BUS {
//     component "AXI4-Lite\n→APB4 Bridge" as APB_BRIDGE
//     component "GPIO\n0x1000_0000" as GPIO
//     component "Timer\n0x1000_4000" as TIMER
//     component "UART 16550A\n0x1000_8000" as UART
//     component "SPI\n0x1000_C000" as SPI
//   }
// }

// ' CPU internal connections
// CTRL ..> IF : valid
// CTRL ..> ID : valid
// CTRL ..> EXE : valid
// CTRL ..> MEM : valid
// CTRL ..> WB : valid
// IF -right-> ID : if_id_bus\n(96bit)
// ID -right-> EXE : id_exe_bus\n(349bit)
// EXE -right-> MEM : exe_mem_bus
// MEM -right-> WB : mem_wb_bus
// WB -left-> RF : write
// EXE -down-> ALU
// EXE -down-> MU
// EXE -down-> FPU
// FPU -down-> FRF
// IF -down-> IC
// MEM -down-> DC
// IC -down-> MMU : i_vaddr→i_paddr
// DC -down-> MMU : d_vaddr→d_paddr
// MMU -down-> TLB
// TLB -down-> PTW : miss→walk

// ' Bus connections
// BRIDGE -down-> CDC : AXI4 Master\n(cpu_clk)
// CDC -down-> AXI_BUS : AXI Master\n(sys_clk)

// ' APB hierarchy
// APB_BRIDGE -down-> GPIO : PSEL[0]
// APB_BRIDGE -down-> TIMER : PSEL[1]
// APB_BRIDGE -down-> UART : PSEL[2]
// APB_BRIDGE -down-> SPI : PSEL[3]

// ' Interrupt connections
// CLINT -up-> TRAP : MTIP, MSIP\n(直连)
// PLIC -up-> TRAP : MEIP, SEIP\n(2级同步)
// TIMER -up-> PLIC : src_irq[1]
// UART -up-> PLIC : src_irq[2]
// SPI -up-> PLIC : src_irq[3]
// GPIO -up-> PLIC : src_irq[4]

// note right of CDC
//   SpinalHDL生成
//   5个异步FIFO
//   (AW/W/B/AR/R)
// end note

// note bottom of DDR3
//   FPGA: Xilinx MIG DDR3
//   SIM: BRAM模型
//   128MB地址空间
// end note

// @enduml
// ```

（此图只是截图，表明SOC层面的架构，要看其他子系统和内存映射的架构，请转到原图——HTML文件：`架构图.html`）

#align(center, image("media/架构图-缩略.png"))

=== 时钟域

#table(
  columns: (auto, auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*时钟域*], [*信号*], [*频率*], [*用途*],
  [CPU域], [`cpu_clk`], [50MHz], [CPU核心、Cache、MMU、cpu\_bus\_bridge],
  [系统域], [`sys_clk`], [100MHz], [AXI互连、所有AXI4-Lite从设备、APB桥、外设],
  [DDR参考], [`ddr_clk_ref`], [200MHz], [DDR3 MIG参考时钟],
)

仿真和上FPGA使用两套配置：
#move(dx: 2em)[
  + 仿真：使用主存行为模型（内部是reg数组）、绕过`Axi_CDC`，CPU域时钟~91 MHz（5.5ns 半周期），tb直接驱动时钟
  + `fpga_clk`（FPGA）：DDR3（MIG IP）、`Axi_CDC`以及标准时钟配置
]
使用这种配置的主要是为了加快仿真速度，避免DDR、PLL、CDC严重拖慢时钟速度。

=== 复位链

// ```plantuml
// @startuml Reset_Chain
// skinparam defaultFontSize 11

// rectangle "resetn\n(板载按钮，低有效)" as BTN
// rectangle "clk_wiz_locked\n(MMCM锁定)" as LOCK
// rectangle "ddr_aresetn\n(MIG init_calib)" as DDR
// rectangle "reset_sync\nu_rst_sys" as RST_SYS
// rectangle "reset_sync\nu_rst_cpu" as RST_CPU
// rectangle "sys_resetn\n(sys_clk域)" as SYS_RST
// rectangle "cpu_resetn\n(cpu_clk域)" as CPU_RST

// BTN -down-> RST_SYS : AND
// LOCK -down-> RST_SYS : AND
// DDR -down-> RST_SYS : AND
// RST_SYS -down-> SYS_RST : 异步断言\n同步解除断言
// RST_SYS -down-> RST_CPU
// RST_CPU -down-> CPU_RST : 异步断言\n同步解除断言

// @enduml
// ```

#align(center, image("media/复位链.svg"))

=== 内存映射

#table(
  columns: (auto, auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*地址范围*], [*大小*], [*设备*], [*说明*],
  [0x0200\_0000 - 0x02FF\_FFFF], [16 MB], [CLINT], [核心本地中断器的mtime/msip/mtip],
  [0x0400\_0000 - 0x04FF\_FFFF], [16 MB], [Sys Status], [MIG/MMCM状态寄存器],
  [0x0C00\_0000 - 0x0CFF\_FFFF], [16 MB], [PLIC], [平台级中断控制器，8源双上下文],
  [0x1000\_0000 - 0x1000\_3FFF], [16 KB], [GPIO], [GPIO，16bit双向],
  [0x1000\_4000 - 0x1000\_7FFF], [16 KB], [Timer], [外设计时器，含IRQ],
  [0x1000\_8000 - 0x1000\_BFFF], [16 KB], [UART], [UART 16550A，含FIFO],
  [0x1000\_C000 - 0x1000\_FFFF], [16 KB], [SPI], [SPI主机],
  [0x8000\_0000 - 0x87FF\_FFFF], [128 MB], [DDR3/RAM], [主内存区域],
  [0xFC00\_0000 - 0xFCFF\_FFFF], [16 MB], [Boot ROM], [启动ROM，8K条目],
  [其他], [—], [Default Slave], [返回DECERR],
)

== CPU核心

CPU核心（`core_top`）采用五级多周期流水线架构（没有流水线填充），由11状态FSM控制器驱动。支持RV32IMAFD\_Zicsr\_Zifencei指令集（110条指令，D扩展的FMA指令不支持），包含完整的异常/中断处理机制和Sv32虚拟内存支持。

=== 流水线控制器

控制器（`cpu_controller`）采用11状态FSM，状态编码如下：

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*编码*], [*状态*], [*说明*],
  [4'd0], [`STATE_IDLE`], [复位后的初始状态，直接转入FETCH],
  [4'd1], [`STATE_FETCH`], [取指阶段，等待icache和MMU就绪],
  [4'd2], [`STATE_DECODE`], [译码阶段，根据指令类型分发],
  [4'd3], [`STATE_EXEC`], [执行阶段，ALU/MU/FPU运算和分支判断],
  [4'd4], [`STATE_MEM`], [访存阶段，等待dcache和MMU就绪],
  [4'd5], [`STATE_WB`], [回写阶段，写寄存器堆],
  [4'd6], [`STATE_CSR_ACCESS`], [CSR读写阶段，完成后进入WB],
  [4'd7], [`STATE_TRAP_ENTER`], [异常/中断进入，保存CSR后跳转trap向量],
  [4'd8], [`STATE_TRAP_RETURN`], [MRET/SRET返回，恢复CSR后跳转mepc/sepc],
  [4'd9], [`STATE_FENCEI`], [fence.i执行，dcache冲刷→icache无效化],
  [4'd10], [`STATE_SFENCE_VMA`], [sfence.vma执行，dcache冲刷→icache无效化→TLB刷新],
)

控制器FSM状态转移图：

// ```plantuml
// @startuml Controller_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> IDLE

// IDLE --> FETCH : reset完成
// FETCH --> DECODE : if_done
// DECODE --> EXEC : need_exe
// DECODE --> CSR : csr指令
// DECODE --> TRAP_ENTER : trap/中断
// DECODE --> TRAP_RETURN : mret/sret
// DECODE --> FENCEI : fence.i
// DECODE --> SFENCE_VMA : sfence.vma

// EXEC --> FETCH : branch跳转
// EXEC --> MEM : ld/st
// EXEC --> WB : R/I快速路径
// EXEC --> TRAP_ENTER : 分支+trap

// MEM --> WB : mem_done
// MEM --> TRAP_ENTER : trap

// WB --> FETCH : next
// CSR --> WB : csr_done

// TRAP_ENTER --> FETCH : 跳转mtvec/stvec
// TRAP_RETURN --> FETCH : 跳转mepc/sepc
// FENCEI --> FETCH : 冲刷完成
// SFENCE_VMA --> FETCH : 刷新完成

// @enduml
// ```

#align(center, image("media/CPU_CTRL_FSM.svg"))

关键设计：
#move(dx: 2em)[
  + *完全步进化*：CPU严格步进化，各个模块只有被调用才能执行，且调用模块阻塞等待，避免时序错误。
  + *exe→wb快速路径*：细化R/I-type运算指令执行路径，跳过MEM阶段直接进入WB，减少2周期。
  + *分层状态机和握手处理*：有可能出现多周期才能完成执行的阶段通过握手协议确定完成时间点，通过内部状态机完成执行，主要包含FETCH,EXEC,MEM阶段和异常处理。
  + *页错误检测*：MMU检测到页错误时，重定向到TRAP\_ENTER。
]

=== 取指模块

取指模块（`cpu_fetch`）为纯组合逻辑，负责将当前PC与取回的指令打包传递给译码级。MMU地址翻译和icache查找在`core_top`顶层完成，不在本模块内。

*接口信号：*

#table(
  columns: (auto, 1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*方向*], [*信号*], [*说明*],
  [输入], [`pc`], [当前程序计数器（虚拟地址），32位],
  [输入], [`instData_32`], [icache取回的指令字（由core\_top从icache获取）],
  [输入], [`inst_valid`], [icache指令有效信号],
  [输入], [`if_valid`], [取指级有效（流水线控制器驱动）],
  [输出], [`instAddr_32`], [输出PC给icache（通过core\_top连线），32位],
  [输出], [`if_done`], [取指完成标志 = `if_valid && inst_valid`],
  [输出], [`if_id_bus`], [取指→译码总线，96位 = `{pc+4, pc, inst}`],
  [输出], [`if_pc`], [当前PC（调试用）],
  [输出], [`if_inst`], [当前指令（调试用）],
)

*地址翻译与取指流程（core\_top层面）：*

`cpu_fetch`输出虚拟地址PC → `core_top`将其送入MMU的`translate_vaddr` → MMU统一翻译FSM输出物理地址`translate_paddr` → `core_top`将其作为`mmu_inst_paddr`送入`icache_ctrl`的`cpu_req_addr`端口 → icache用物理地址做PIPT命中判断/缺失填充/MMIO旁路 → 取回指令通过`instData_32`回传给`cpu_fetch`。

=== 译码模块

译码模块从32位指令中提取所有控制信号和操作数，包括五种立即数生成（I/S/B/U/J型）、指令识别和分类、ALU操作数选择等。译码为纯组合逻辑，1周期完成。

指令集覆盖：RV32I(40条) + M(8条) + A(11条) + F(22条) + D(22条非FMA) + Zicsr(6条) + Zifencei(1条) = 110条。

*浮点指令译码（F + D扩展）：*

#table(
  columns: (auto, 1fr, 2fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*opcode*], [*名称*], [*指令*],
  [0x07], [LOAD-FP], [`FLW`(funct3=010) / `FLD`(funct3=011)],
  [0x27], [STORE-FP], [`FSW`(funct3=010) / `FSD`(funct3=011)],
  [0x43/47/4B/4F], [MADD/MSUB/NMSUB/NMADD], [`FMADD.S`/`FMSUB.S`/`FNMSUB.S`/`FNMADD.S`（R4格式）],
  [0x53],
  [OP-FP],
  [FADD/FSUB/FMUL/FDIV/FSQRT/FMIN/FMAX/FSGNJ\*/FCVT/FEQ/FLT/FLE/FCLASS/FMV.X.W/FMV.W.X 及D扩展对应指令],
)

*浮点控制信号（ID/EX总线新增）：*

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*信号*], [*位宽*], [*说明*],
  [`is_fpu`], [1], [当前指令为浮点运算指令],
  [`is_flw`/`is_fsw`], [1+1], [FLW/FSW（单精度加载/存储）],
  [`is_fld`/`is_fsd`], [1+1], [FLD/FSD（D扩展双精度加载/存储）],
  [`fpu_funct`], [7], [浮点操作码（46种：F 0-23 + D 24-45）],
  [`fpu_rm`], [3], [舍入模式（来自funct3，DYN=111在执行级用CSR frm替换）],
  [`fpu_rd_is_int`], [1], [结果写整数寄存器（FEQ/FLT/FLE/FCLASS/FMV.X.W/FCVT.W.\*及D扩展对应）],
  [`frs3_value`], [32], [FMA第三操作数（R4格式rs3）],
)

浮点操作数选择：浮点计算指令读取浮点寄存器frs1/frs2（FMA额外读取frs3）；整数→浮点指令（`FMV.W.X`/`FCVT.S.W`/`FCVT.D.W`等）读取整数寄存器rs1；浮点→整数指令（`FMV.X.W`/`FCVT.W.S`/`FCVT.W.D`等）结果写整数寄存器。

=== 执行模块

执行模块调用ALU/MU/FPU完成运算，并处理分支和跳转指令。

*运算单元选择：*

#table(
  columns: (1fr, 4fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*单元*], [*负责指令*],
  [ALU], [ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI/NOR/NOT等单周期运算],
  [MU], [MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU（多周期握手）],
  [FPU], [FADD/FSUB/FMUL/FDIV/FSQRT/FMADD/FMSUB及D扩展双精度运算等（5状态FSM + 超时看门狗，多周期握手）],
)

分支比较器（`branch_comparator`）为独立组合逻辑模块，协处理分支命令的比较运算，根据`funct3`判断beq/bne/blt/bge/bltu/bgeu条件。

=== 访存模块

访存模块负责与dcache交互，支持字节/半字/字的读写操作。通过MMU翻译虚拟地址后，dcache控制器进行命中判断和数据访问。内部状态机（`mem_state` 4-bit）管理单字访存和D扩展双事务访存：

```
// 单字访存（LB/LH/LW/SB/SH/SW/FLW/FSW）
MEM_IDLE → MEM_READ  (Load)  → 等待 data_valid → MEM_IDLE
MEM_IDLE → MEM_WRITE (Store) → 等待 data_valid → MEM_IDLE

// D扩展 FLD/FSD 双事务（两个32-bit字拼合为64-bit）
MEM_IDLE → MEM_FLD_LO  (FLD 读低字 addr)   → MEM_FLD_GAP → MEM_FLD_HI (读高字 addr+4) → MEM_IDLE
MEM_IDLE → MEM_FSD_LO  (FSD 写低字 addr)   → MEM_FSD_GAP → MEM_FSD_HI (写高字 addr+4) → MEM_IDLE
```

*FLD/FSD双事务与GAP状态：* D扩展的FLD/FSD需访问两个连续的32-bit字（addr和addr+4）拼合为64-bit浮点数据。由于两次访问地址不同，MMU需重新翻译第二个字的地址。GAP状态（`MEM_FLD_GAP`/`MEM_FSD_GAP`）在两次访问间脉冲`mem_en=0`一个周期，强制MMU重新翻译。

MMIO旁路：当物理地址最高位`bit[31]=0`或`bit[30]=1`时，不经过Cache，直接通过总线访问外设（使用MMU翻译后的物理地址判断）。

*对齐异常检测：* Byte访问`addr[0]!=0`不触发；Halfword访问`addr[0]!=0`→对齐异常；Word访问`addr[1:0]!=00`→对齐异常；FLD/FSD双精度访问`addr[2:0]!=000`→对齐异常（8字节对齐）。

=== 回写模块

回写模块为纯组合逻辑，将访存/执行结果写回寄存器堆。JAL/JALR指令写回PC+4（返回地址）。

*整数寄存器写回：* 写使能`wb_valid && wb_we && !is_fpu && !is_flw && !is_fld`（FLW/FLD/FPU结果不写整数寄存器）。写数据选择：CSR指令写回CSR读出值，其余写回ALU/MU/Load结果。

*浮点寄存器写回（64-bit数据通路）：*

#table(
  columns: (auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*写回来源*], [*64-bit写数据*],
  [F/D计算指令], [`fpu_result_64`（F结果已NaN-box为`{32'hFFFFFFFF, result[31:0]}`，D结果为完整64位）],
  [FLD（双精度加载）], [`fp_wdata64`（由访存级双事务拼合的64-bit数据）],
  [FLW（单精度加载）], [`{32'hFFFFFFFF, wb_data[31:0]}`（NaN-box 32-bit加载数据）],
)

浮点寄存器写使能：`wb_valid && (is_fpu || is_flw || is_fld)`。

*fflags累积：* `wb_valid && (fpu_fflags != 0)`时，OR累积至CSR fflags（`fflags_wen`需`wb_valid`门控，防止残留总线数据误写）。

=== 寄存器堆

#move(dx: 2em)[
  + *整数寄存器堆*（`cpu_regfile`）：32个32位寄存器，x0硬连线为0，组合读同步写，支持WB同周期写穿透（read forwarding）
  + *浮点寄存器堆*（`fpu_regfile`）：32个*64位*寄存器，f0-f31，支持单精度（NaN-boxing：高32位填充`0xFFFFFFFF`）和双精度浮点存储。f0为正常可写寄存器（RISC-V规范不要求f0=0）。单写端口（64-bit），三读端口（64-bit，含FMA rs3第三读端口）
]

== 运算单元

=== ALU

ALU为纯组合逻辑模块，支持14种单周期运算（ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI/NOR/NOT等）。使用超前进位加法器（CLA）和桶形移位器。

控制编码（one-hot）：

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

=== MU（乘除法单元）

独立的乘除法单元，通过`mu_req_valid`/`mu_result_valid`握手协议与执行模块交互：
#move(dx: 2em)[
  + *Booth乘法器*：Booth编码，支持MUL/MULH/MULHSU/MULHU
  + *非恢复余数除法器*：支持DIV/DIVU/REM/REMU
  + 支持`flush`中断（异常/中断发生时中止当前运算）
]

=== FPU（浮点运算单元）

单精度+双精度浮点运算单元，支持RISC-V F扩展的22条指令和D扩展的22条非FMA指令。浮点寄存器堆为32×64-bit，支持NaN-boxing（F单精度结果高32位填充`0xFFFFFFFF`）。

*F扩展子模块（单精度）：*

#table(
  columns: (1fr, 3fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*子模块*], [*功能*],
  [`fpu_adder`], [浮点加法/减法],
  [`fpu_multiplier`], [浮点乘法],
  [`fpu_divider`], [浮点除法],
  [`fpu_sqrt`], [浮点开方],
  [`fpu_fma`], [融合乘加（FMADD/FMSUB/FNMADD/FNMSUB）],
  [`fpu_cvt`], [浮点↔整数转换（FCVT）],
  [`fpu_compare`], [浮点比较（FEQ/FLT/FLE）],
  [`fpu_minmax`], [浮点极值（FMIN/FMAX）],
  [`fpu_classify`], [浮点分类（FCLASS）],
  [`fpu_sign_inject`], [符号注入（FSGNJ/FSGNJN/FSGNJX）],
  [`fpu_round`], [舍入单元],
  [`fpu_special`], [特殊值处理（NaN/Inf/零）],
)

*D扩展子模块（双精度，独立实现非参数化F模块）：*

#table(
  columns: (auto, 5fr, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*子模块*], [*功能*], [*周期数*],
  [`fpu_adder_d`], [双精度加法/减法（FSM: 对齐→加法→规格化→舍入）], [4-6],
  [`fpu_multiplier_d`], [双精度乘法（53×53尾数乘）], [2-3],
  [`fpu_divider_d`], [双精度除法（非恢复余数迭代55-bit商）], [~56],
  [`fpu_sqrt_d`], [双精度开方（非恢复余数法57-bit根）], [~57],
  [`fpu_cvt_d`], [双精度↔整数/单精度转换（FCVT.S.D/FCVT.D.S等6条）], [2-3],
  [`fpu_compare_d`], [双精度比较（FEQ.D/FLT.D/FLE.D）], [单周期],
  [`fpu_minmax_d`], [双精度极值（FMIN.D/FMAX.D）], [单周期],
  [`fpu_classify_d`], [双精度分类（FCLASS.D）], [单周期],
  [`fpu_sign_inject_d`], [双精度符号注入（FSGNJ.D/FSGNJN.D/FSGNJX.D）], [单周期],
)

*FPU内部状态机（5状态显式FSM）：*

// ```plantuml
// @startuml FPU_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> F_IDLE

// F_IDLE --> F_DISPATCH : req_valid
// F_DISPATCH --> F_DONE : 组合运算（比较/分类等）
// F_DISPATCH --> F_WAIT : 时序运算（加/乘/除/开方/转换）

// F_WAIT --> F_DONE : sub_module_done
// F_WAIT --> F_IDLE : flush
// F_WAIT --> F_DONE : timeout(1000周期)\nfpu_error=1

// F_DONE --> F_COMPLETE : 下一周期
// F_COMPLETE --> F_IDLE : result_got

// note right of F_WAIT
//   超时看门狗：1000周期
//   未收到done则fpu_error=1
//   抑制写回（结果标记无效）
// end note

// @enduml
// ```

#align(center, image("media/FPU_FSM.svg"))

FPU通过`fpu_req_valid`/`fpu_result_valid`握手协议与执行模块交互，支持`flush`中断。数据位宽为64-bit：F运算取低32位并NaN-box，D运算使用完整64位。`fpu_active`信号与`mu_busy`互斥，确保同一时刻仅一个多周期运算单元活跃。

*FLD/FSD双事务加载/存储：* 见访存模块章节。D扩展的FLD/FSD通过访存级三状态FSM（`MEM_FLD_LO→MEM_FLD_GAP→MEM_FLD_HI`）完成双事务，GAP状态强制MMU重新翻译第二个字的地址。

*D扩展未实现部分：* D-FMA（FMADD.D/FMSUB.D/FNMSUB.D/FNMADD.D）暂不实现。FMV.X.D/FMV.D.X需要XLEN≥64，RV32下不实现。

== 存储子系统

=== ICache控制器

icache控制器（`icache_ctrl`）采用5状态FSM，管理指令缓存的命中判断、缺失填充和无效化。

*Cache参数：**4路组相联，8组*，256bit行大小（8字），共1KB。*PIPT*（物理索引物理标签），Tree-PLRU替换。无脏位（只读缓存）。set\_idx和tag均来自MMU翻译后的物理地址（paddr），消除了VIPT的别名问题。

*状态定义：*

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [S\_IDLE], [空闲，等待CPU请求；MMIO单周期旁路],
  [S\_TAG\_READ], [标签BRAM读取，直接进行tag比较（paddr在S\_IDLE已锁存，无需等待MMU）],
  [S\_READ], [读命中，从数据BRAM读出目标字],
  [S\_REFILL], [缺失填充：请求总线行填充，写入数据+标签BRAM],
  [S\_INVALIDATE], [全无效化（fence.i）：逐组写零清除有效位],
)

*ICache FSM状态图：*

// ```plantuml
// @startuml ICache_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> S_IDLE

// S_IDLE --> S_TAG_READ : cpu_req && !is_mmio && mmu_ready
// S_IDLE --> S_IDLE : MMIO旁路（单周期）
// S_IDLE --> S_IDLE : !mmu_ready（等待MMU翻译物理地址）

// S_TAG_READ --> S_READ : 读命中
// S_TAG_READ --> S_IDLE : 写命中（icache只读，不应发生）
// S_TAG_READ --> S_REFILL : 缺失

// S_READ --> S_IDLE : 数据读取完成

// S_REFILL --> S_IDLE : refill_valid（填充完成）

// S_IDLE --> S_INVALIDATE : flush_req (fence.i)
// S_INVALIDATE --> S_IDLE : 8组全部写零完成
// S_INVALIDATE --> S_INVALIDATE : invalidate_set < NUM_SETS-1\n（逐组写零，每周期1组）

// @enduml
// ```

#align(center, image("media/icache_fsm.svg"))

=== DCache控制器

dcache控制器（`dcache_ctrl`）采用13状态FSM，管理数据缓存的全部操作：命中判断、写命中单周期写入、缺失处理（含脏行回写与行填充）、MMIO旁路、缓存冲刷和单行无效化。

*Cache参数：*4路组相联，8组，256bit行大小（8字），共1KB。写回策略，*PIPT*（物理索引物理标签），Tree-PLRU替换。有脏位。set\_idx和tag均来自MMU翻译后的物理地址（paddr）。

*状态定义：*

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [S\_IDLE], [空闲，等待CPU请求或冲刷请求],
  [S\_TAG\_READ], [标签BRAM读取；写命中单周期完成，读命中→S\_READ\_HIT，缺失→回写/填充],
  [S\_READ\_HIT], [读命中，从数据BRAM读出目标字],
  [S\_WB\_READ], [缺失且受害者脏——从数据BRAM读出脏行],
  [S\_WB\_SEND], [将脏行发送至总线回写，等待`wb_valid`],
  [S\_REFILL], [从总线填充新行到数据+标签BRAM，合并待写数据],
  [S\_FLUSH\_SCAN], [冲刷：发起标签BRAM读取],
  [S\_FLUSH\_CHECK], [冲刷：判断当前路是否有效且脏],
  [S\_FLUSH\_WB\_RD], [冲刷回写：从数据BRAM读出脏行],
  [S\_FLUSH\_WB\_SD], [冲刷回写：将脏行发送至总线],
  [S\_FLUSH\_INVALIDATE], [冲刷无效化：逐组写零清除所有有效位],
  [S\_INV\_LINE], [单行无效化：标签BRAM读取],
  [S\_INV\_LINE\_WRITE], [单行无效化：清除匹配路的V位],
)

*DCache FSM状态图：*

// ```plantuml
// @startuml DCache_FSM
// skinparam defaultFontSize 10
// hide empty description

// [*] --> S_IDLE

// state "正常访存路径" as NORMAL {
//   S_IDLE --> S_TAG_READ : cpu_req && !is_mmio
//   S_IDLE --> S_IDLE : MMIO旁路
//   S_TAG_READ --> S_READ_HIT : 读命中
//   S_TAG_READ --> S_IDLE : 写命中（单周期）
//   S_TAG_READ --> S_WB_READ : 缺失且脏
//   S_TAG_READ --> S_REFILL : 缺失且干净
//   S_READ_HIT --> S_IDLE : 完成
//   S_WB_READ --> S_WB_SEND : 下一周期
//   S_WB_SEND --> S_REFILL : wb_valid
//   S_REFILL --> S_IDLE : refill_valid
// }

// state "冲刷路径" as FLUSH {
//   S_IDLE --> S_FLUSH_SCAN : flush_req
//   S_FLUSH_SCAN --> S_FLUSH_CHECK : 下一周期
//   S_FLUSH_CHECK --> S_FLUSH_WB_RD : 有效且脏
//   S_FLUSH_CHECK --> S_FLUSH_SCAN : 不脏，下一组
//   S_FLUSH_WB_RD --> S_FLUSH_WB_SD : 下一周期
//   S_FLUSH_WB_SD --> S_FLUSH_SCAN : wb_valid
//   S_FLUSH_WB_SD --> S_FLUSH_INVALIDATE : 全部处理完
//   S_FLUSH_INVALIDATE --> S_IDLE : 无效化完成
// }

// state "单行无效化" as INV {
//   S_IDLE --> S_INV_LINE : inv_line_req
//   S_INV_LINE --> S_INV_LINE_WRITE : tag读取完成
//   S_INV_LINE_WRITE --> S_IDLE : V位清除完成
// }

// @enduml
// ```

#align(center, image("media/dcache_FSM.svg", width: 100%))

关键设计要点：
#move(dx: 2em)[
  + *写命中单周期完成*：dcache支持写命中时直接写入数据BRAM并置脏位，单周期从S\_TAG\_READ返回S\_IDLE
  + *字节写使能*：通过BRAM的WEA端口支持BYTE/HWORD/WORD写入
  + *单行无效化接口*：`inv_line_req/addr/done`端口支持外部（如sfence.vma后）对dcache中特定行进行无效化，清除匹配路的V位（不写回脏数据）
  + *MMIO旁路*：物理地址`bit[31]=0`或`bit[30]=1`时旁路Cache
  + *error完成路径*：AXI总线错误时bridge也置`done=1`，dcache检查error flag后回S\_IDLE，避免死等
  + *write-back公平性*：`wb_starve_cnt_r` 3周期计数后`wb_boost_r`提升到最高优先级，防止写回饥饿
]

=== MMU

MMU模块（`MMU.sv`）实现Sv32页式虚拟内存。经过精简优化后，采用*统一翻译FSM*（11状态）替代早期分离的i-side/d-side FSM + 仲裁器结构，CPU通过`translate_req`/`translate_done`握手驱动单次翻译流程。

*Sv32地址分解：*

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

*Sv32使能条件：*`sv32_enabled = satp[31] && (priv_mode != M_MODE) && translate_en`。M模式始终使用bare模式（物理地址直通）。

*统一翻译FSM（11状态）：*

// ```plantuml
// @startuml MMU_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> T_IDLE

// T_IDLE --> T_LOOKUP : translate_req
// T_LOOKUP --> T_CHECK : 下一周期(BRAM读延迟)

// T_CHECK --> T_DONE : bare模式 或 TLB命中
// T_CHECK --> T_FAULT : TLB命中+权限故障
// T_CHECK --> T_WALK : TLB缺失

// T_WALK --> T_FILL : ptw_walk_done
// T_WALK --> T_FAULT : ptw_walk_fault

// T_FILL --> T_RELOOKUP : 下一周期
// T_RELOOKUP --> T_RECHECK : 下一周期
// T_RECHECK --> T_DONE : 命中
// T_RECHECK --> T_FAULT : 权限故障

// T_DONE --> T_COMPLETE : 下一周期
// T_FAULT --> T_COMPLETE : 下一周期
// T_COMPLETE --> T_IDLE : !translate_req
// T_COMPLETE --> T_IDLE : translate_req && vaddr变化

// T_IDLE --> T_FLUSH : sfence_vma
// T_FLUSH --> T_IDLE : 刷新完成

// note right of T_COMPLETE
//   translate_done 为电平信号
//   (在T_COMPLETE中保持高电平)
//   而非1周期脉冲
//   防止重复翻译
// end note

// @enduml
// ```

#align(center, image("media/MMU_FSM.svg", height: 80%))

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*状态*], [*功能描述*],
  [T\_IDLE], [空闲，锁存vaddr/satp/priv，等待translate\_req],
  [T\_LOOKUP], [TLB BRAM读请求（1周期延迟）],
  [T\_CHECK], [TLB输出有效，判定hit/miss/fault；bare模式直接T\_DONE],
  [T\_WALK], [TLB缺失，PTW页表漫游],
  [T\_FILL], [PTW完成，写TLB Port B（1周期）],
  [T\_RELOOKUP], [重新读TLB确认fill提交],
  [T\_RECHECK], [检查re-lookup结果],
  [T\_DONE], [翻译成功，置translate\_done + paddr],
  [T\_FAULT], [翻译失败，置translate\_done + fault],
  [T\_COMPLETE], [保持translate\_done为电平信号，等待translate\_req撤除后回T\_IDLE],
  [T\_FLUSH], [sfence.vma刷新TLB，逐组写零BRAM],
)

*T\_COMPLETE状态（关键简化）*：`translate_done`现为电平信号（在T\_COMPLETE中保持高电平），而非早期的1周期脉冲。防止`translate_req`保持高电平时触发重复翻译，消除T\_DONE与T\_COMPLETE之间的1周期gap，避免dcache数据BRAM使能被mmu\_ready间隙抑制导致的store hit数据丢失问题。

*与流水线的交互*：icache和dcache各自通过独立的`translate_req`请求驱动MMU翻译。MMU为单例实例，两种请求分时复用同一翻译FSM。sfence.vma通过`mmu_flush_req`中断任意状态进入T\_FLUSH。

=== TLB

TLB使用双端口BRAM实现4路×4组=16表项的组相联结构，Tree-PLRU替换。

*BRAM结构：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*BRAM*], [*规格*], [*内容*],
  [tlb\_flag], [128bit × 4深], [每路32bit：{V(1), G(1), ASID(9), VPN(20), mega(1)}],
  [tlb\_data], [128bit × 4深], [每路32bit：{PPN(22), R, W, X, U, A, D, pad(4)}],
)

端口分配：Port A = i-side查找，Port B = d-side查找 / PTW填充（填充优先抢占）。

Megapage匹配：仅比较VPN\[19:10\]，低10位由虚拟地址直接提供。全局页（G=1）跳过ASID比较。

=== PTW（页表漫游器）

PTW为8状态FSM，完成Sv32二级页表遍历和权限检查。*A/D位采用软件管理*：当PTE.A=0或（store且PTE.D=0）时，PTW直接触发页错误（cause 12/13/15），由软件（OS）负责设置A/D位，而非硬件自动写回。这简化了PTW状态机并消除了PTW写回与dcache的一致性问题。

*PTW FSM状态图：*

// ```plantuml
// @startuml PTW_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> S_IDLE

// S_IDLE --> S_L1_READ : walk_req

// S_L1_READ --> S_L1_CHECK : ptw_bus_done

// S_L1_CHECK --> S_PERM_CHECK : L1 PTE为叶节点\n(megapage)
// S_L1_CHECK --> S_L0_READ : L1 PTE为非叶节点
// S_L1_CHECK --> S_FAULT : V=0 或保留编码

// S_L0_READ --> S_L0_CHECK : ptw_bus_done

// S_L0_CHECK --> S_PERM_CHECK : L0 PTE为叶节点
// S_L0_CHECK --> S_FAULT : V=0 / 保留 / 非叶

// S_PERM_CHECK --> S_DONE : 权限通过 且 A=1 且 (非store 或 D=1)
// S_PERM_CHECK --> S_FAULT : 权限检查失败
// S_PERM_CHECK --> S_FAULT : A=0 或 (store且D=0)\n→ 页错误(软件管理A/D)

// S_DONE --> S_IDLE
// S_FAULT --> S_IDLE

// note right of S_FAULT
//   任意状态收到 walk_abort
//   (sfence_vma) 均强制回 S_IDLE
// end note

// @enduml
// ```

#align(center, image("media/PTW_FSM.svg", height: 70%))

*A/D位软件管理*：此实现较为普遍（香山处理器也是软件管理A/D位），当PTE.A=0或（store且PTE.D=0）时，PTW在S\_PERM\_CHECK状态直接进入S\_FAULT，触发page fault（cause 12/13/15）。操作系统在page fault handler中手动设置PTE的A/D位后重新执行。这消除了早期的S\_AD\_UPDATE/S\_AD\_WAIT状态及其相关的PTW写回总线操作和dcache一致性维护需求。SimpleOS等操作系统在建页表时预置A=1、D=1避免页错误。

== 总线系统

系统采用层次化总线架构：AXI4系统总线→AXI4-Lite→APB4外设总线。从之前的AHB-Lite总线全面升级为AXI4，支持突发传输和更完善的协议机制，解决了AHB-Lite总线连不上MIG的AXI接口的问题。

=== AXI4总线协议

AXI4是ARM AMBA总线族中的高性能系统总线，本系统使用单主设备（CPU）多从设备拓扑。

*AXI4主要特性：*

#move(dx: 2em)[
  + *五通道独立握手*：写地址（AW）、写数据（W）、写响应（B）、读地址（AR）、读数据（R），各通道独立VALID/READY握手
  + *突发传输*：支持NONSEQ/SEQ等突发类型，INCR8突发用于Cache行填充/回写
  + *单主设备*：CPU为唯一AXI4主设备，无需仲裁
  + *多从设备*：通过手动地址译码器选择7个从设备
  + *时钟域穿越*：Axi\_CDC使用5个异步FIFO安全跨越cpu\_clk→sys\_clk
  + *响应码*：OKAY(00)/EXOKAY(01)/SLVERR(10)/DECERR(11)
]

*AXI4关键信号：*

#table(
  columns: (auto, auto, 1fr),
  align: horizon,
  stroke: 0.5pt,
  inset: 6pt,
  [*信号*], [*方向*], [*说明*],
  [`AWADDR[31:0]`], [M→S], [写地址],
  [`AWVALID/AWREADY`], [M→S/S→M], [写地址握手],
  [`AWBURST[1:0]`], [M→S], [突发类型：00=FIXED, 01=INCR, 10=WRAP],
  [`AWLEN[7:0]`], [M→S], [突发长度-1（INCR8时为7）],
  [`AWSIZE[2:0]`], [M→S], [传输宽度：011=32bit],
  [`WDATA[31:0]`], [M→S], [写数据],
  [`WVALID/WREADY`], [M→S/S→M], [写数据握手],
  [`WSTRB[3:0]`], [M→S], [字节写使能],
  [`WLAST`], [M→S], [最后一拍标志],
  [`BRESP[1:0]`], [S→M], [写响应],
  [`BVALID/BREADY`], [S→M/M→S], [写响应握手],
  [`ARADDR[31:0]`], [M→S], [读地址],
  [`ARVALID/ARREADY`], [M→S/S→M], [读地址握手],
  [`RDATA[31:0]`], [S→M], [读数据],
  [`RRESP[1:0]`], [S→M], [读响应],
  [`RLAST`], [S→M], [最后一拍标志],
)

*AXI4读/INCR8突发读传输时序图：*

（左侧AXI4读单拍MMIO读，右侧INCR8读Cache行填充）
// ```plantuml
// @startuml AXI4_Read_Timing
// robust "ARVALID" as ARV
// robust "ARREADY" as ARR
// robust "RVALID" as RV
// robust "RREADY" as RR
// concise "ARADDR" as ARA
// concise "RDATA" as RD

// @0
// ARV is low
// ARR is low
// RV is low
// RR is low

// @50
// ARV is high
// ARA is "addr"

// @100
// ARR is high

// @150
// ARV is low
// RV is high
// RD is "data"
// ARR is low

// @200
// RR is high

// @250
// RV is low
// RR is low

// @enduml
// ```

// *AXI4 INCR8突发读时序（Cache行填充）：*

// ```plantuml
// @startuml AXI4_Burst_Read_Timing
// robust "CLOCK" as CLK
// robust "ARVALID" as ARV
// robust "ARREADY" as ARR
// robust "RVALID" as RV
// robust "RREADY" as RR
// concise "ARADDR" as ARA
// concise "RDATA" as RD
// robust "RLAST" as RL

// @0
// CLK is low
// ARV is low
// RV is low
// RL is low

// @50
// CLK is high
// ARV is high
// ARA is "base_addr"

// @100
// CLK is low
// ARR is high

// @150
// CLK is high
// ARV is low
// RV is high
// RD is "word0"
// ARR is low

// @200
// CLK is low
// RR is high

// @250
// CLK is high
// RD is "word1"

// @300
// CLK is low
// RD is "word2"

// @350
// CLK is high
// RD is "word3"

// @400
// CLK is low
// RD is "word4"

// @450
// CLK is high
// RD is "word5"

// @500
// CLK is low
// RD is "word6"

// @550
// CLK is high
// RD is "word7"
// RL is high

// @600
// CLK is low
// RV is low
// RL is low

// @enduml
// ```

#grid(
  columns: (2fr, 3fr),
  gutter: 0em,
  [#image("media/AXI4_Read_Timing.svg", height: 16em)], [#image("media/AXI4_Burst_Read_Timing.svg", height: 16em)],
)
=== AXI4总线网络结构

// ```plantuml
// @startuml AXI4_Network_Topology
// skinparam componentStyle rectangle
// skinparam defaultFontSize 11

// component "core_top\n(RISC-V CPU)" as CPU #LightBlue
// component "cpu_bus_bridge\n(16-state FSM)" as BRIDGE
// component "Axi_CDC\n(cpu_clk→sys_clk)" as CDC #LightGray

// rectangle "AXI4 地址译码器 + 从设备MUX" as DECODER #LightYellow {
//   component "DDR3/RAM\n(Full AXI4)\nSlave 0\n0x8000_0000" as DDR3 #Pink
//   component "Boot ROM\nSlave 1\n0xFC00_0000" as BOOTROM
//   component "PLIC\nSlave 2\n0x0C00_0000" as PLIC
//   component "CLINT\nSlave 3\n0x0200_0000" as CLINT
//   component "AXI4-Lite→APB\nSlave 4\n0x1000_0000" as APB_BR
//   component "Sys Status\nSlave 5\n0x0400_0000" as SYSSTAT
//   component "Default\nSlave 6\n(DECERR)" as DEF
// }

// CPU -down-> BRIDGE : 内部请求
// BRIDGE -down-> CDC : AXI4 Master\n(cpu_clk域)
// CDC -down-> DECODER : AXI Master\n(sys_clk域)

// note right of DECODER
//   地址译码：
//   addr[31:27]==5'h10 → DDR3
//   addr[31:24]==8'hFC → BootROM
//   addr[31:24]==8'h0C → PLIC
//   addr[31:24]==8'h02 → CLINT
//   addr[31:24]==8'h10 → APB Bridge
//   addr[31:24]==8'h04 → SysStatus
//   其他 → Default (DECERR)
// end note

// @enduml
// ```

#align(center, image("media/AXI4_Network_Topology.svg", width: 60%))

=== cpu\_bus\_bridge

`cpu_bus_bridge`是系统中唯一的AXI4主设备，采用16状态FSM管理所有总线操作。仲裁6种请求源：

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*优先级*], [*请求*], [*说明*],
  [1（最高）], [icache MMIO], [单拍外设访问，避免I/O被长突发阻塞],
  [2], [dcache MMIO], [数据侧MMIO],
  [3], [PTW], [页表漫步，必须在缓存缺失重试前完成],
  [4], [dcache写回], [脏行回写优先于填充],
  [5], [icache填充], [指令取指优先于数据取指],
  [6（最低）], [dcache填充], [数据填充],
)

事务类型：
#move(dx: 2em)[
  + *MMIO读*：AR→R（单拍，DEV\_NONBUF缓存属性）
  + *MMIO写*：AW+W同时→B（单拍，支持子字存储）
  + *icache填充*：AR(burst 8)→R(8拍，NORM\_BUF缓存属性)
  + *dcache填充*：AR(burst 8)→R(8拍)
  + *dcache写回*：AW(burst 8)+W(beat 0)→W(beats 1-7)→B
  + *PTW读/写*：AR→R / AW+W→B（单拍）
]

=== APB4总线协议

APB4是AMBA总线族中的低功耗外设总线，本系统通过AXI4-Lite→APB4桥连接低速外设。

*APB4主要特性：*

#move(dx: 2em)[
  + *非流水线传输*：每次传输需完整的SETUP+ACCESS两个周期
  + *单主设备*：由AXI4-Lite→APB4桥充当唯一主设备
  + *多从设备*：通过`PSELx`选择4个从设备
  + *字节掩码*：通过`PSTRB[3:0]`支持字节级写使能
  + *低功耗*：所有信号在时钟上升沿变化
]

*APB4关键信号：*

#table(
  columns: (1fr, auto, 3fr),
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
  [`PREADY`], [S→M], [从设备就绪（本系统恒为1）],
  [`PSTRB[3:0]`], [M→S], [字节写掩码],
  [`PSLVERR`], [S→M], [错误响应（本系统恒为0）],
)

*APB4写/读传输时序图：*

// ```plantuml
// @startuml APB4_Write_Timing
// robust "PSEL" as SEL
// robust "PENABLE" as EN
// robust "PWRITE" as WR
// concise "PADDR" as ADDR
// concise "PWDATA" as WDATA

// @0
// SEL is low
// EN is low
// WR is low

// @50
// SEL is high
// WR is high
// ADDR is "addr"
// WDATA is "wdata"

// @100
// EN is high

// @150
// SEL is low
// EN is low
// WR is low

// @enduml
// ```

// *APB4读传输时序图：*

// ```plantuml
// @startuml APB4_Read_Timing
// robust "PSEL" as SEL
// robust "PENABLE" as EN
// robust "PWRITE" as WR
// concise "PADDR" as ADDR
// concise "PRDATA" as RDATA

// @0
// SEL is low
// EN is low
// WR is low

// @50
// SEL is high
// WR is low
// ADDR is "addr"

// @100
// EN is high
// RDATA is "rdata"

// @150
// SEL is low
// EN is low

// @enduml
// ```

#grid(
  columns: (2fr, 3fr),
  gutter: 0em,
  [#image("media/APB4_Write_Timing.svg", height: 16em)], [#image("media/APB4_Read_Timing.svg", height: 16em)],
)

=== APB4总线网络结构

// ```plantuml
// @startuml APB4_Network_Topology
// skinparam componentStyle rectangle
// skinparam defaultFontSize 11

// component "AXI4-Lite\n→APB4 Bridge\n(7-state FSM)" as BRIDGE
// rectangle "APB4 地址译码器\n(PADDR[15:14])" as DECODER {
//   component "GPIO\nPSEL[0]\n0x1000_0000" as GPIO
//   component "Timer\nPSEL[1]\n0x1000_4000" as TIMER
//   component "UART 16550A\nPSEL[2]\n0x1000_8000" as UART
//   component "SPI\nPSEL[3]\n0x1000_C000" as SPI
// }

// BRIDGE -down-> DECODER : APB4 Master

// note right of DECODER
//   PADDR[15:14] 译码：
//   2'b00 → GPIO
//   2'b01 → Timer
//   2'b10 → UART
//   2'b11 → SPI
// end note

// @enduml
// ```

#align(center, image("media/APB4_Network_Topology.svg", width: 60%))

=== AXI4-Lite→APB4桥

`axi4lite_to_apb`实现AXI4-Lite到APB4的协议转换，采用7状态FSM：

// ```plantuml
// @startuml AXI4Lite_to_APB4_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> ST_IDLE

// ST_IDLE --> ST_READ_SETUP : AR valid
// ST_IDLE --> ST_WRITE_SETUP : AW+W latched

// ST_READ_SETUP --> ST_READ_ACCESS : 下一周期
// ST_READ_ACCESS --> ST_READ_RESP : PREADY
// ST_READ_RESP --> ST_IDLE : RREADY

// ST_WRITE_SETUP --> ST_WRITE_ACCESS : 下一周期
// ST_WRITE_ACCESS --> ST_WRITE_RESP : PREADY
// ST_WRITE_RESP --> ST_IDLE : BREADY

// @enduml
// ```

#align(center, image("media/AXI4Lite_to_APB4_FSM.svg"))

关键设计：
#move(dx: 2em)[
  + AW和W通道独立锁存（pending\_awaddr, pending\_wdata）
  + 读优先（当无写通道部分锁存时）
  + PPROT极性反转：AXI4 AxPROT\[0\]（0=特权）vs APB4 PPROT\[0\]（0=非特权），bit 0取反
]

== 中断控制器

=== CLINT

CLINT（`axi4lite_clint`）为核心本地中断器，作为AXI4-Lite从设备挂载在系统总线上。

*寄存器映射（基址0x0200\_0000）：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*寄存器*], [*说明*],
  [`0x0000`], [msip], [软件中断挂起位（仅bit0有效）],
  [`0x4000`], [mtimecmp\_lo], [比较值低32位],
  [`0x4004`], [mtimecmp\_hi], [比较值高32位],
  [`0xBFF8`], [mtime\_lo], [计时器低32位（每周期自增1）],
  [`0xBFFC`], [mtime\_hi], [计时器高32位],
)

*中断输出：*
#move(dx: 2em)[
  + `o_mtip = (mtime >= mtimecmp)`：电平触发，持续到软件更新mtimecmp
  + `o_msip = r_msip`：软件控制，通过msip寄存器置位/清除
]

CLINT的MTIP直连CPU核心`timer_irq`，MSIP直连CPU核心`sw_irq`。

=== PLIC

PLIC（`axi4lite_plic`）为平台级中断控制器，管理8个外部中断源（源0保留），支持M/S双上下文。采用SiFive标准地址布局。

*中断源分配：*

#align(center)[#table(
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
)]

*寄存器映射（基址0x0C00\_0000）：*

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*寄存器*],
  [`0x000000`--`0x00001C`], [优先级寄存器 `prio[1]`--`prio[7]`],
  [`0x001000`], [挂起位图 `pending`（32位）],
  [`0x002000`+N×0x80], [使能位图 `enable[N]`（每上下文）],
  [`0x200000`+N×0x1000], [优先级阈值 `threshold[N]`],
  [`0x200000`+N×0x1000+4], [Claim/Complete寄存器（读=认领，写=完成）],
)

*仲裁机制*：`find_highest()`扫描所有挂起且使能的中断源，选择优先级值最大且超过阈值者。电平触发网关：`src_irq`上升沿且`gw_en=1`时置挂起位；Claim清除挂起位并去门控；Complete重新门控允许再次触发。

*AXI4-Lite接口FSM*：
#move(dx: 2em)[
  + 写FSM（3状态）：WR\_IDLE → WR\_DATA → WR\_RESP
  + 读FSM（2状态）：RD\_IDLE → RD\_RESP
]

*PLIC输出*：`o_eip[0]`（M模式MEIP）和`o_eip[1]`（S模式SEIP），通过2级触发器同步器从sys\_clk域穿越到cpu\_clk域。

== 外设

所有外设挂载在APB4总线上，零等待状态响应（PREADY=1, PSLVERR=0）。

=== GPIO

16bit双向可编程I/O，连接到FPGA LED。

*寄存器映射：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*名称*], [*说明*],
  [`0x00`], [GPIO\_CTRL], [方向控制：bit\[i\]=1输出，0输入],
  [`0x04`], [GPIO\_DATA], [输出数据（写）/引脚值（读）],
  [`0x08`], [GPIO\_IRQ\_EN], [引脚变化中断使能],
  [`0x0C`], [GPIO\_IRQ\_STAT], [引脚变化挂起状态（W1C清除）],
)

IRQ检测：输入引脚边沿变化时置位`gpio_irq_stat`，`o_irq = |(gpio_irq_stat & gpio_irq_en)`。

=== Timer

32位计时器，支持单次和周期模式，匹配时产生IRQ。

*寄存器映射：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*名称*], [*说明*],
  [`0x00`], [EXPR\_VAL], [过期值（32位）],
  [`0x04`], [CTRL], [\[0\]=启动, \[1\]=模式(0=单次, 1=周期)],
  [`0x08`], [IRQ], [\[0\]=o\_irq（写0清除）],
  [`0x0C`], [COUNTER], [当前计数值（32位）],
)

行为：计数器在`start=1`时自增；单次模式过期后自动停止；周期模式过期后归零继续。IRQ连接到PLIC源1。

=== UART 16550A

NS16550A兼容UART，含16深度TX/RX FIFO，可配置波特率（默认115200），产生TX完成和RX有效中断。

*寄存器映射：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*名称*], [*说明*],
  [`0x00`], [THR/RBR], [发送保持（W）/接收缓冲（R）],
  [`0x04`], [IER], [中断使能 \[RDA, THRE, RLS, MS\]],
  [`0x08`], [IIR/FCR], [中断ID（R）/FIFO控制（W）],
  [`0x0C`], [LCR], [线路控制 \[数据位, 停止位, 校验, DLAB\]],
  [`0x10`], [MCR], [Modem控制],
  [`0x14`], [LSR], [线路状态 \[DR, OE, PE, FE, BI, THRE, TE\]],
  [`0x18`], [MSR], [Modem状态],
  [`0x1C`], [SCR], [暂存寄存器],
)

*TX FSM（6状态）：*

// ```plantuml
// @startuml UART_TX_FSM
// skinparam defaultFontSize 11
// hide empty description

// [*] --> S_IDLE

// S_IDLE --> S_POP_BYTE : FIFO非空
// S_POP_BYTE --> S_SEND_START : 下一周期
// S_SEND_START --> S_SEND_BYTE : start bit发送完成
// S_SEND_BYTE --> S_SEND_PARITY : 所有数据位发送完\n且校验使能
// S_SEND_BYTE --> S_SEND_STOP : 所有数据位发送完\n且无校验
// S_SEND_PARITY --> S_SEND_STOP : 校验位发送完
// S_SEND_STOP --> S_IDLE : stop bit发送完

// @enduml
// ```

#align(center, image("media/UART_TX_FSM.svg", height: 53%))

*RX FSM（11状态）：*支持完整的帧错误、校验错误、间断中断和溢出检测。

IRQ连接到PLIC源2。

=== SPI

SPI主机，支持CPOL/CPHA四种模式，可编程时钟分频。

*寄存器映射：*

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*偏移*], [*名称*], [*说明*],
  [`0x00`], [SPI\_CTRL], [\[0\]=启动, \[1\]=CPOL, \[2\]=CPHA, \[3\]=SS, \[4\]=IRQ\_EN, \[15:8\]=时钟分频],
  [`0x04`], [SPI\_DATA], [\[7:0\]=TX数据（写）/RX数据（读）],
  [`0x08`], [SPI\_STATUS], [\[0\]=busy, \[1\]=irq\_pending（W1C清除）],
)

传输机制：基于时钟边沿计数器（17个边沿），CPHA=0时奇数边沿移位偶数边沿采样，CPHA=1时反之。传输完成后置`done`，IRQ连接到PLIC源3。

= 系统软件验证

本项目在硬件验证通过后，进一步在CPU上运行了两个系统软件以验证完整的特权级和分页机制：

== SimpleOS微型操作系统

SimpleOS是运行在自研RISC-V CPU上的最小化操作系统演示（约1500行C/汇编），完整展示了M→S→U三级特权转换 + Sv32分页 + ecall系统调用。

*启动流程：*

// ```plantuml
// @startuml SimpleOS_Boot
// skinparam defaultFontSize 11

// rectangle "M-mode" #LightBlue {
//   rectangle "entry.S" as ENTRY
//   rectangle "m_init.c\n建3张Sv32页表\n配medeleg委托\nmret→S-mode" as MINIT
// }

// rectangle "S-mode" #LightGreen {
//   rectangle "s_main.c\n装stvec\n开FPU\n打印banner\nsret→U-mode" as SMAIN
//   rectangle "trap.S/.c\necall陷入分发\nsyscall服务器" as TRAP
// }

// rectangle "U-mode" #LightYellow {
//   rectangle "user_start.S\nsp=0x9000\ncall main" as USTART
//   rectangle "calculator.c\n5项浮点自检\n交互计算器" as CALC
// }

// ENTRY -down-> MINIT : call
// MINIT -right-> SMAIN : mret
// SMAIN -right-> USTART : sret
// USTART -down-> CALC : call main
// CALC -up-> TRAP : ecall (SYS_write/read/report/exit)
// TRAP -down-> CALC : sret (返回U-mode)

// @enduml
// ```

#align(center, image("media/SimpleOS_Boot.svg", width: 80%))

*验证内容：*

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*特性*], [*验证结果*],
  [M→S特权转换], [mret从M-mode进入S-mode，CSR序列：medeleg/mstatus.MPP=S/satp/sfence.vma ✓],
  [S→U特权转换], [sret从S-mode进入U-mode，sstatus.SPP=0, sepc=0x0 ✓],
  [Sv32分页], [L1+2×L0三级页表，内核恒等映射+用户映射，单页表设计 ✓],
  [ecall系统调用], [SYS_write/read/report/exit 4个系统调用，sepc+=4后sret返回 ✓],
  [U-mode浮点计算], [RV32IMF浮点计算器，5项自检全部通过（1+2, 3\*4, 10-3, 8/2, sqrt(4)） ✓],
  [陷阱委托], [medeleg=0xB100，U-ecall和页错误委托至S-mode ✓],
  [UART交互], [通过ecall SYS_read阻塞等待UART输入，实现交互式计算器 ✓],
)

*仿真结果：* UART输出"SimpleOS booted" + 5项测试结果 + "Tests: 5/5 passed" + 交互模式banner + "> "提示符。自检结果写入PA_SELF_CHECK（0x80007000），TB自动校验。149个trap事件（ecall/sret交替）均正确处理。

== Linux内核启动

在SimpleOS验证基础上，进一步尝试启动Linux内核（OpenSBI + Linux内核payload），验证CPU对完整OS的兼容性。

*启动配置：*

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*项目*], [*配置*],
  [固件], [OpenSBI fw\_payload.elf（OpenSBI + Linux内核一体）],
  [DTS], [`boot/dts/simplecpu.dts`：rv32ima\_zicsr\_zifencei, sv32, 128MB DDR3],
  [内核入口], [0x80400000（OpenSBI跳转至Linux payload）],
  [UART], [ns16550a, 230400 baud, earlycon=uart8250],
  [bootargs], [console=ttyS0,230400 earlycon ignore\_loglevel loglevel=8],
)

*启动进度：*

// ```plantuml
// @startuml Linux_Boot
// skinparam defaultFontSize 11

// rectangle "OpenSBI (M-mode)\n0x80000000-0x80083FFF" as OPENSBI #LightBlue
// rectangle "Linux kernel payload\n0x80400000" as KERNEL #LightGreen
// rectangle "启用Sv32分页\n0x80400094: csrw satp" as ENABLE_PG #LightYellow
// rectangle "内核虚拟空间\nC0000098-C0377xxx (~55MB)" as KVSPACE #LightCoral
// rectangle "Load Page Fault\nVA=0x00FEFFEC (user space)\nscause=0xD" as PANIC #Red

// OPENSBI -right-> KERNEL : mret跳转
// KERNEL -down-> ENABLE_PG : 初始化序列
// ENABLE_PG -right-> KVSPACE : Sv32翻译工作
// KVSPACE -down-> PANIC : demand paging\n内核panic

// note right of KVSPACE
//   i-side MMU完全工作
//   TLB hit, Sv32启用
//   PC推进~55MB内核虚拟空间
//   SBI调用正常(MCAUS=9)
// end note

// @enduml
// ```

#align(center, image("media/Linux_Boot.svg"))

*达成状态：*

#move(dx: 2em)[
  + OpenSBI正常启动，完成M-mode初始化，跳转至Linux内核payload
  + Linux内核在S-mode启用Sv32分页（satp=0x800808FC），i-side MMU翻译工作正常
  + 内核从物理地址0x80400000推进至虚拟地址C0377xxx（约55MB内核虚拟空间）
  + TLB命中、SBI调用（MCAUS=9, S-mode ecall）、内核页表切换均正常
  + 最终在demand paging阶段触发load page fault（VA=0x00FEFFEC, scause=0xD），进入内核panic
  + *结论*：CPU成功运行Linux内核，验证了M/S特权、Sv32分页、CLINT/PLIC中断等核心功能对Linux的兼容性，后续用户态panic阶段不清楚是软件还是硬件问题。
]

*为Linux适配修复的关键RTL bug：*

#table(
  columns: (auto, 2fr, 3fr),
  stroke: 0.5pt,
  inset: 6pt,
  align: horizon,
  [*Bug*], [*文件*], [*修复内容*],
  [MMIO判定], [icache/dcache\_ctrl.sv], [is\_mmio改用物理地址（TLB翻译后）而非虚拟地址],
  [sfence.vma一致性], [cpu\_controller.sv], [新增STATE\_SFENCE\_VMA：dcache flush→icache inv→TLB flush三步串行],
  [STIP中断委托], [cpu\_csr.sv/cpu\_clint.sv], [S-mode定时器中断改用csr\_mip\[5\]；M/S优先级修复],
  [time/timeh CSR], [cpu\_csr.sv], [实现rdtime CSR，CLINT mtime经Gray编码CDC同步到cpu\_clk],
  [PMP寄存器], [cpu\_csr.sv], [实现16个PMP条目CSR（pmpcfg0-3, pmpaddr0-15），锁定位强制],
  [UART NS16550A], [uart\_16550a.sv], [替换自定义UART为NS16550A兼容实现，PSTRB\[0\]门控],
  [TLB valid脉冲], [MMU.sv], [BRAM TLB lookup请求在LOOKUP期间保持高电平（BUG-16修复）],
  [PTW bus空隙], [ptw.sv], [S\_L1\_CHECK预发L0 read，消除bus\_req\_pending 1周期空隙],
  [UART THRE], [uart\_regs\_16550a.sv], [THRE仅在移位寄存器空闲时置位，防止kernel输出FIFO溢出],
  [DCache error路径], [cpu\_bus\_bridge.sv/dcache\_ctrl.sv], [AXI error时也置done，防止dcache死等],
  [流水线冲刷], [core\_top.sv], [trap/redirect时清零IF/ID和ID/EXE流水线寄存器],
  [GPR写穿透], [cpu\_regfile.sv], [WB同周期读优先返回WB数据（write-through）],
  [CSR权限隔离], [cpu\_decode.sv], [csr\_priv\_violation接入illegal\_inst],
  [AMO预留集失效], [cpu\_mem.sv], [AMO操作清除LR/SC预留集],
  [mtime Gray CDC], [system\_top.sv], [64位mtime改用Gray编码跨时钟域同步],
)

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
  [MMU专项测试×12], [Sv32翻译/TLB/PTW/权限/页错误/统一FSM],
  [Cache专项测试×5], [icache/dcache基础/脏行/fence.i/MMU交互],
  [特权级测试×3], [CSR访问/委托/特权级转换],
  [D扩展测试×3], [d\_ext(51子测试)/d\_ext\_special(28子测试)/d\_smoke冒烟测试],
  [F扩展测试×3], [f\_ext(30子测试)/f\_ext\_special(24子测试)/f0\_writable(5子测试)],
  [FPU FSM测试], [fpu\_fsm边界测试(15子测试，含超时/flush)],
  [A扩展测试], [a\_ext(52子测试，含LR/SC/AMO预留集失效)],
  [回归测试×14], [BUG-16/HIGH-1/HIGH-2/MEDIUM-3/error注入/公平性等],
  [SimpleOS启动], [os\_boot任务：M→S→U启动 + 5项浮点自检 + 交互模式],
  [Linux启动], [linux\_boot任务：OpenSBI + Linux内核进入Sv32分页（内核panic）],
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
  [`uart_echo.s`], [UART回显程序],
)

均在`dev/program_source`目录下，可通过`tools/rv2coe.py`编译为coe文件。

== 测试结果

所有仿真测试均通过，包括CPU综合测试、运算测试、异常测试、Cache专项测试、MMU专项测试（12/12）、特权级测试、D扩展测试（51+28+2子测试）、A扩展测试（52子测试）、回归测试（14/14，含BUG-16/HIGH-1/HIGH-2/MEDIUM-3/error注入等）。SimpleOS成功运行（5/5自检通过）。Linux内核成功进入Sv32分页模式，推进至内核虚拟空间C0377xxx后demand paging触发内核panic。上板验证中走马灯、UART回显、SimpleOS交互计算器等功能均达到预期效果。

= 性能计算

== 各指令类型CPI

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
  [FP运算], [2], [1], [N], [—], [1], [#text(red)[N+4]],
)

== 平均CPI估算

采用推算指令混合比例（不含M/F扩展）：

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

CPU时钟50MHz（FPGA上板频率）：

$ "MIPS" = (5 times 10^7) / (6.75 times 10^6) approx #text(red)[7.4] $

= 遇到的问题以及解决

== 总线从AHB-Lite升级到AXI4

在实验3中系统使用AHB-Lite总线，但AHB-Lite的地址/数据相位重叠机制在跨时钟域时实现复杂。升级到AXI4后，五通道独立握手协议天然适合异步FIFO穿越，使用SpinalHDL生成的Axi\_CDC模块安全可靠地完成了cpu\_clk→sys\_clk的跨越。

== DDR3集成

FPGA上使用Xilinx MIG IP核驱动DDR3内存，需要200MHz参考时钟和初始化校准。通过`axi_wrap_ddr`封装MIG为AXI4从设备，仿真时切换为`axi_wrap_ram`（BRAM模型），通过`SIMU_USE_DDR`宏编译时选择。

== PTW A/D位软件管理简化

原PTW实现包含S\_AD\_UPDATE和S\_AD\_WAIT两个状态用于硬件自动写回PTE的A/D位。这引入了PTW写回与dcache的一致性问题（dcache可能缓存过期PTE副本），需要单行无效化机制维护一致性。简化后，PTW在A=0或D=0时直接触发page fault，由软件（OS）负责管理A/D位。这消除了PTW写回总线操作、dcache一致性维护需求，将PTW从10状态精简为8状态FSM。SimpleOS等操作系统在建页表时预置A=1、D=1避免页错误。

== MMU统一翻译FSM精简

原MMU包含分离的i-side FSM（5状态）、d-side FSM（5状态）和漫游仲裁器FSM（3状态），共13个状态。精简为统一翻译FSM（11状态），CPU通过`translate_req`/`translate_done`握手驱动单次翻译。新增T\_COMPLETE状态将`translate_done`从1周期脉冲改为电平信号，消除了重复翻译和dcache数据BRAM使能间隙问题。非BRAM全相联TLB路径作为死代码删除（571行）。

== UART RX双事务问题

CPU读取UART状态和RX数据需要两次总线事务，但APB协议每次传输独立。解决方案：RX采用"arm on STATUS read, pop on RXDATA read"机制——读STATUS寄存器时"武装"pop操作，读RXDATA时实际弹出FIFO。

= 结论

本项目成功构建了一个完整的RISC-V计算机系统，主要成果如下：

#move(dx: 2em)[
  + *完整SoC*：CPU + AXI4系统总线 + DDR3主存 + Boot ROM + APB4外设总线 + 4外设
  + *指令集*：RV32IMAFD\_Zicsr\_Zifencei，110条指令，含单精度+双精度浮点
  + *AXI4总线*：单主7从拓扑，支持INCR8突发传输，Axi\_CDC时钟域穿越
  + *虚拟内存*：Sv32二级页表，MMU统一翻译FSM(11状态) + TLB(4路×4组) + PTW(8状态FSM)，A/D位软件管理
  + *Cache*：i/d各1KB，4路组相联，写回策略，Tree-PLRU替换，PIPT
  + *中断*：CLINT(MTIP/MSIP, Gray编码CDC) + PLIC(8源，M/S双上下文)，M/S/U三级特权
  + *外设*：GPIO(16bit)、Timer(含IRQ)、UART 16550A(含FIFO, NS16550A兼容)、SPI
  + *DDR3主存*：FPGA上128MB DDR3，仿真时BRAM模型
  + *FPU*：单精度F扩展(22条) + 双精度D扩展(22条非FMA)，5状态显式FSM + 超时看门狗，64-bit浮点寄存器堆 + NaN-boxing
  + *SimpleOS*：M→S→U三级特权转换 + Sv32分页 + ecall系统调用，5项浮点自检通过
  + *Linux内核*：成功进入Linux内核态（OpenSBI + Linux Sv32分页），推进至内核虚拟空间C0377xxx
  + *验证通过*：仿真全部通过（26+回归 + D扩展 + A扩展 + SimpleOS），FPGA上板验证达到预期效果
]

通过本次实验，我们完成了从单个CPU核到完整计算机系统的构建，并成功运行SimpleOS微型操作系统和Linux内核（进入内核态），深入理解了SoC层次化设计、总线协议（AXI4/APB4）、时钟域穿越、存储器层次（DDR3→Cache→MMU→TLB）、中断架构、特权级与分页机制等计算机系统核心概念。

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
