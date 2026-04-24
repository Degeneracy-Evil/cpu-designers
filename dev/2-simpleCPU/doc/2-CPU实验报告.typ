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
#set text(size: 18pt)
#align(horizon, {
  [#align(center)[#heading([计算机组成原理实验报告], numbering: none)]]
  v(4em)
  [实验名称：基础处理器设计]
  v(4em)
  [专业班级：计算机科学与技术 一班]

  v(0.8em)
  [组#h(2em)员：王之翼#h(1em)320240944621#h(1em)测试与修改\
    #h(7em)张潘妍#h(1em)320240944910#h(1em)文档\
    #h(7em)张之恒#h(1em)320240944971#h(1em)算法资料收集\
    #h(7em)陈海攀#h(1em)320230904051#h(1em)构建]
  v(4em)
  [实验日期：2026年4月21日]
  v(5.6em)
  align(center)[兰州大学信息科学与工程学院]
})
#pagebreak()
//普通文本
#set text(size: 14pt)

= 设计目标

+ 支持`RISCV32-I`指令集基础部分
+ 多周期处理器
+ 哈佛架构（`iCache`和`dCache`），使用BLOCK RAM
+ 使用之前的ALU
+ 交叉编译为coe文件并导入执行