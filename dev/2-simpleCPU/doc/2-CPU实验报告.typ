// 数字电路实验报告模板（Typst）
#set title("基础处理器设计实验报告")
#import "@local/cetz:0.5.0"
// 段落缩进
#set par(first-line-indent: (amount: 2em, all: true))
// 强调改进
#show strong: text.with(font: "Microsoft YaHei")
#show emph: text.with(font: ("Calibri", "LiSu"))

#set page(paper: "a4", margin: (top: 2cm, bottom: 2cm, left: 2.5cm, right: 2cm))
#set heading(numbering: "1.")
#show heading: it => {
  if it.level == 1 {
    block([*#it*], below: 1.2em)
  } else {
    block([#it], below: 1em)
  }
}
#set text(size: 24pt)
#align(horizon, {
  [#align(center)[2026 年春季学期\
    计算机组成原理课程]]
  v(2em)
  align(center)[32 位 RISC-V 多周期CPU 核]
  v(2em)
  align(center)[#text(40pt)[设\ 计\ 报\ 告]]

  v(4em)
  align(center)[#text(size: 18pt)[负责人：王之翼#h(1em)18996388318\    张潘妍    张之恒    陈海攀]]
  align(center)[#text(size: 18pt)[2024级计算机一班#h(1em)课序3第4组#h(1em)2026年4月21日]]
})
#pagebreak()
//普通文本
#set text(size: 16pt)
#set page(numbering: "1 / 1")

= 项目简述

== 项目环境与级别

设计语言：Verilog

仿真环境：Vivado~2018.3版本

== 设计目标

#move(dx: 2em)[
  + 支持`RISCV32-I`指令集除`fence`和中断相关指令
  + 采用多周期处理器
  + 哈佛架构（`iCache`和`dCache`），使用BLOCK RAM
  + 使用上一次实验的ALU
  + 交叉编译rv32I汇编为coe文件并导入执行
]

== 参考资料

#move(dx: 2em)[
  + RISC-V-Reader-Chinese-v2p12017.pdf
  + FPGA-A7-PRJ-UDB_V1.0-引脚坐标参考.pdf
  + 所有课程PPT（指导老师：何安平）
]

== 项目文件夹结构

= 实现细节

== 指令集选取

我们选取了`RISCV32-I`指令集除`fence`和中断相关指令，即

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
  text(blue)[auipc], [jal],
)

共37条指令，涉及到全部#text(orange)[`R`] #text(maroon)[`I`] #text(fuchsia)[`S`] #text(olive)[`B`] #text(blue)[`U`] `J`类别，能够实现基本CPU核。

== IP核使用

我们使用了BRAM IP核做为`iCache/dCache`，详细配置为：
#move(dx: 4em)[
  - 真双口(True Dual Port RAM)
  - 位宽：32
  - 位深：2048
  - Primitives Output Register：否
  - Core Output Register：否
  - iCache使用coe文件初始化
]
`iCache，dCache`分别实例化了一个BRAM IP核。

== 流水线设计

使用基础五级流水线：

#align(center)[#cetz.canvas({
  import cetz.draw: *
  let draw_line(x, y, w, h, d, alist) = {
    let px = x
    let count = 0
    for obj in alist {
      let id = obj.at(0)
      let text = obj.at(1)
      rect((px, y), (px + w, y + h), name: id)
      content(id, [#text])
      if count > 0 {
        line(alist.at(count - 1).at(0), id, mark: (end: "straight"))
      }
      px = px + w + d
      count = count + 1
    }
  }

  let water_line = (("if", "取指"), ("dc", "解码"), ("exe", "执行"), ("mem", "访存"), ("wb", "回写"))
  draw_line(0, 0, 2, 1.5, 1, water_line)
  line("wb", (rel: (0, -1.5), to: "wb"), (rel: (0, -1.5), to: "if"), "if", mark: (end: "straight"))
})]
