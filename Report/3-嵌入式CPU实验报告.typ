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
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年4月21日]]
  align(center)[#text(size: 14pt)[（分工表见最后）]]
})
#pagebreak()
//普通文本
#set text(size: 14pt)
#set page(numbering: "1 / 1")

= 项目简述

== 项目环境与级别

设计语言：Verilog

仿真环境：Vivado~2018.3版本

== 设计目标

#move(dx: 2em)[
  + `RISCV32-IM_zicsr_zifencei`多周期嵌入式CPU
  + 支持异常
  + 支持单级中断
  + 支持UART和GPIO
]

== 已实现的特性

#move(dx: 2em)[
  + `RISCV32-IM_zicsr_zifencei`多周期嵌入式CPU
  + 支持单级中断、异常（`ebreak,`指令）
  + AHB系统总线,APB外设总线
  + MMIO
  + 外设：UART、GPIO（目前连在LED上做走马灯）、timer（含IRQ中断）、SPI
]

== 参考资料

#move(dx: 2em)[
  + RISC-V-Reader-Chinese-v2p12017.pdf
  + FPGA-A7-PRJ-UDB_V1.0-引脚坐标参考.pdf
  + 所有课程PPT（指导老师：何安平）
  + IHI0033a_AMBA_AHB-Lite_Protocol.pdf
  + IHI0024E_amba_apb_architecture_spec.pdf
]

== 项目文件夹结构

= 实现细节

== 指令集扩展

=== M指令集扩展

=== zicsr和zifencei扩展指令

== CPU核更改

为了优化CPU核的结构以及CPI，我们修改了流水线以及ALU结构

//