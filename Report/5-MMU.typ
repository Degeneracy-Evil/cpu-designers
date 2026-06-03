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
  + 特权架构规范：#link("https://docs.riscv.org/reference/isa/_attachments/riscv-privileged.pdf")[riscv-privileged.pdf]
  + 平台级中断控制器：#link("https://docs.riscv.org/reference/plic/_attachments/riscv-plic.pdf")[riscv-plic.pdf]
  + tree-PLRU算法：#link("https://people.computing.clemson.edu/~mark/464/p_lru.txt")[p_lru.txt]
]