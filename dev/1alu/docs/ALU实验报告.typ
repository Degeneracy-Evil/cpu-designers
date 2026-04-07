// 数字电路实验报告模板（Typst）
#set title("算术逻辑单元ALU设计")
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
  [实验名称：算术逻辑单元ALU设计]
  v(4em)
  [专业班级：计算机科学与技术 一班]

  v(0.8em)
  [组#h(2em)员：王之翼#h(1em)张潘妍#h(1em)张之恒#h(1em)陈海攀]
  v(0.8em)
  [指导教师：--]
  v(0.8em)
  [实验日期：2026年3月28日]
  v(5.6em)
  align(center)[兰州大学信息科学与工程学院]
})
#pagebreak()

//普通文本
#set text(size: 14pt)

= 设计功能

本实验目标是完成一个 32 位算术逻辑单元（ALU）的模块化设计，采用 one-hot 控制编码，部分功能采用时序逻辑运算。

本实验项目不依赖 IP 核，使用接近于verilog原语的方法进行构建。

具体实现的功能如下：

- 32 位基本算术运算：ADD、SUB。
- 32 位逻辑运算：AND、OR、NOT、XOR、NOR。
- 比较运算：SLT（有符号小于）、SLTU（无符号小于）。
- 移位运算：SLL、SRL、SRA（左/右逻辑移位，右算数移位）。
- 立即数高位加载：LUI（将 `src2[15:0]` 装载到结果高 16 位）。
- 多周期乘除法：MUL（Booth 有符号乘法）与 DIV（恢复余数法有符号除法）。
- 完成标志 `done`：组合逻辑类操作单周期完成，乘除法在状态机结束时置位。

= 功能原理

== 顶层控制与数据通路

顶层模块输入为 `clk`、`reset`、`alu_control[15:0]`、`src1[31:0]`、`src2[31:0]`，输出为 `result[31:0]` 与 `done`。控制信号采用 one-hot 编码：

#box(height: 13em, columns(2, gutter: 0em)[#table(
    columns: (auto, auto),
    [码（左低右高）], [功能],
    [0000 0000 0000 000#text(orange)[x]], [---],
    [0000 0000 0000 00#text(orange)[1]0], [LUI],
    [0000 0000 0000 0#text(orange)[1]00], [SRA],
    [0000 0000 0000 #text(orange)[1]000], [SRL],
    [0000 0000 000#text(orange)[1] 0000], [SLL],
    [0000 0000 00#text(orange)[1]0 0000], [XOR],
    [0000 0000 0#text(orange)[1]00 0000], [OR],
    [0000 0000 #text(orange)[1]000 0000], [NOR],
  )
  #table(
    columns: (auto, auto),
    [码（左低右高）], [功能],
    [0000 000#text(orange)[1] 0000 0000], [AND],
    [0000 00#text(orange)[1]0 0000 0000], [SLTU],
    [0000 0#text(orange)[1]00 0000 0000], [STL],
    [0000 #text(orange)[1]000 0000 0000], [SUB],
    [000#text(orange)[1] 0000 0000 0000], [ADD],
    [00#text(orange)[1]0 0000 0000 0000], [NOT],
    [0#text(orange)[1]00 0000 0000 0000], [DIV],
    [#text(orange)[1]000 0000 0000 0000], [MUL],
  )])

输入数据经过所有模块的并行计算后通过`alu_result_selector`模块选择输出。

对于多周期操作的同步问题，我们通过done信号线进行完成控制，且区分了组合操作和时序操作的done信号。

== 超前进位加法器（CLA）

加法模块采用 32 位层次化超前进位结构：4 位 CLA 组成 16 位 CLA，再由两个 16 位 CLA 构成 32 位加法器。其核心思想是提前并行计算进位，而不是像行波进位那样逐位传播。

对第 $i$ 位定义：

- 进位生成信号：$G_i = A_i dot B_i$
- 进位传递信号：$P_i = A_i plus.o B_i$
- 进位关系：$C_(i+1) = G_i + P_i C_i$
- 和位：$S_i = P_i plus.o C_i$

CLA 的优点是进位计算层次化并行，可显著降低长位宽加法延迟。顶层 ADD 直接取 CLA 输出。

== 桶形移位器

移位模块采用 5 级桶形位移结构，每一级对应一个二次幂移位量：1、2、4、8、16。通过 `shamt[4:0]` 控制各级是否生效，最终实现 0 到 31 位任意移位。

具体实现方式如下：

- 第 1 级根据 `shamt[0]` 决定是否移 1 位。
- 第 2 级根据 `shamt[1]` 决定是否移 2 位。
- 第 3 级根据 `shamt[2]` 决定是否移 4 位。
- 第 4 级根据 `shamt[3]` 决定是否移 8 位。
- 第 5 级根据 `shamt[4]` 决定是否移 16 位。

同一套级联结构并行计算三类结果：

- SLL：左移，低位补 0。
- SRL：右移，高位补 0。
- SRA：算术右移，高位补符号位。

最终由 `shift_type` 在三类结果中选择输出。

== 小于置位（SLT/SLTU）判断方法

SLT 与 SLTU 都输出 32 位，其中低位 `bit0` 为比较结果，其余位清零。

1. SLT（有符号小于）
先做减法 `a - b`，然后分情况判断：

- 若 `a` 与 `b` 符号不同，`a` 为负时必有 `a < b`；
- 若符号相同，则比较差值符号位。

代码等价表达为：

$"slt" = (a_(31) dot overline(b_(31))) + (overline(a_(31) plus.o b_(31)) dot "sub"_(31))$

2. SLTU（无符号小于）
无符号比较通过减法进位判断。令 $a + (~ b + 1)$ 的最终进位为 `cout`：

- `cout = 1` 表示无借位，即 $a >= b$；
- `cout = 0` 表示有借位，即 $a < b$。

因此 `sltu = ~cout`。

== 乘法算法（Booth）

乘法器采用 Booth 有符号乘法算法，状态机为 `IDLE -> COMPUTE -> FINISH`。寄存器含义如下：

- `A`：部分积累加器。
- `Q`：乘数寄存器。
- `Q_1`：扩展位。
- `M`：被乘数寄存器。

每个计算周期检查二位组合 `(Q[0], Q_1)`：

- `00` 或 `11`：不加减，仅算术右移。
- `01`：执行 `A = A + M`，再算术右移。
- `10`：执行 `A = A - M`，再算术右移。

共迭代 32 次后进入 FINISH，输出 `product = (A, Q)`，顶层取低 32 位作为 ALU 的 MUL 结果。

== 非恢复余数除法器

除法器采用非恢复余数法（Non-Restoring Division），状态机分为 `IDLE -> COMPUTE -> FIX -> FINISH` 四个阶段。与恢复余数法相比，它在主循环中根据当前余数的符号决定执行加法或减法，避免每一步都显式恢复，因此更适合用统一的加减器数据通路实现。

1. 预处理
- 在 `IDLE` 状态接收 `start` 后，缓存原始被除数与除数；
- 记录二者符号位，随后将操作数转换为绝对值进入主循环；
- 若除数为 0，则直接进入 `FINISH`，约定商为 0，余数为被除数；
- 若出现 `INT_MIN / -1`，则直接进入 `FINISH`，按二补码截断语义输出商为 `0x8000_0000`、余数为 0。

2. 主循环（32 次）
- 组合寄存器采用 `{R, Q}` 形式，其中 `R` 为余数寄存器，`Q` 为商寄存器；
- 每一轮先整体左移一位，形成 `shifted_R = {R[30:0], Q[31]}`；
- 若当前 `R` 为非负，则执行 `shifted_R - D`；若当前 `R` 为负，则执行 `shifted_R + D`；
- 根据新余数的符号位决定本轮商位：新余数非负则 `Q[0] = 1`，否则 `Q[0] = 0`。

这一过程由 `cla_adder_32bit` 同时构造减法器和加法器完成，再通过 MUX 选择下一拍的余数结果。

3. 终态修正
- 32 次迭代结束后进入 `FIX` 阶段；
- 若最终余数为负，则执行 `R = R + D`，使余数回到非负范围；
- 随后进入 `FINISH`，完成基础非恢复余数运算。

4. 符号恢复与特殊修正
- 商的符号由被除数与除数符号异或得到；
- 余数的符号与被除数相同；
- 若同号除法出现 `remainder == divisor`，则说明结果可再进一位，模块执行 `quotient += 1`、`remainder -= divisor`；
- 若异号除法出现 `remainder + divisor == 0`，则执行 `quotient -= 1`、`remainder = 0`；
- 对除零和溢出情形，后级直接覆盖最终商和余数。

因此，该除法器并不是简单的“试减-恢复”结构，而是“非恢复余数主循环 + 终态修正 + 特殊商余数校正”的实现方式。最终 `quotient` 作为 ALU 的 DIV 输出，`remainder` 作为附加输出，`done` 在状态机进入 `FINISH` 后置位。

== 完成信号原理

`done` 信号分两类：

- 非乘除法操作：`done = 1`（默认立即完成）。
- DIV：`done = div_done`。
- MUL：`done = mul_done`。

顶层通过多路选择结构组合上述信号，实现统一时序语义。

= 功能实现

== 模块划分

`alu_32bit.v` 在结构上采用“并行计算 + 统一选择”的实现方式，主要由以下子模块组成：

- `cla_adder_32bit`：ADD 主运算通路。
- `subtractor`：SUB 运算通路。
- `logic_unit`：AND/OR/NOT/XOR/NOR/SLT/SLTU。
- `shifter`（3 次实例化）：分别实现 SLL、SRL、SRA。
- `lui`：LUI 运算。
- `booth_multiplier`：有符号乘法，多周期。
- `non_restoring_divider`：有符号除法，多周期。
- `alu_result_selector`：对 15 路候选结果进行选择输出。

== 顶层集成流程

实现流程如下：

1. 由 `alu_control` 解码得到各运算使能位。
2. 组合运算模块并行产生结果。
3. 对 MUL/DIV 在时钟上升沿锁存 `src1/src2` 到寄存器，启动对应状态机。
4. 乘法输出取 `product[31:0]` 参与最终选择；除法输出取 `quotient` 参与最终选择。
5. 由 `alu_result_selector` 按控制位输出最终 `result`。
6. 由 `mul_done/div_done` 与默认完成路径合成 `done`。

== 顶层模块架构图

#figure(
  caption: [ALU顶层模块架构图],
  cetz.canvas({
    import cetz.draw: *

    set-style(stroke: (paint: black, thickness: 0.8pt), fill: rgb("f7f7f7"))

    rect((0, 0), (5, 2.5), name: "in")
    content("in", [输入与控制\ clk/reset\ alu_control/src1/src2])

    rect((rel: (0.5, 0), to: "in.south-east"), (rel: (5.5, 2), to: "in.south-east"), name: "seq")
    content("seq", [多周期模块群\ Booth MUL / DIV FSM])

    rect((rel: (-3.5, 1), to: "in.north"), (rel: (3, 3), to: "in.north"), name: "comb")
    content("comb", [组合模块群\ ADD/SUB/LOGIC/SHIFT/LUI])

    rect((rel: (0.5, 0), to: "comb.south-east"), (rel: (4.5, 2), to: "comb.south-east"), name: "sel")
    content("sel", [结果选择器\ alu_result_selector])

    rect((rel: (1, 0), to: "seq.south-east"), (rel: (4.5, 2), to: "seq.south-east"), name: "done")
    content("done", [done合成\ default/div/mul])

    rect((rel: (1, 0), to: "sel.south-east"), (rel: (3, 2), to: "sel.south-east"), name: "out")
    content("out", [result])

    line("in", "comb")
    line("in", "seq")
    line("comb", "sel")
    line("seq", "sel")
    line("sel", "out")
    line("seq", "done")
  }),
  kind: "graph",
  supplement: [图],
)

== Booth乘法器架构图

#figure(
  caption: [Booth乘法器数据通路与状态机关系图],
  cetz.canvas({
    import cetz.draw: *

    set-style(stroke: (paint: black, thickness: 0.8pt), fill: rgb("f6fbff"))

    rect((0, 0), (2.5, 1), name: "q1")
    content("q1", [$Q_1$位])

    rect((rel: (-1.25, 0.5), to: "q1.north"), (rel: (1.25, 1.5), to: "q1.north"), name: "q")
    content("q", [Q寄存器])

    rect((rel: (-1.25, 0.5), to: "q.north"), (rel: (1.25, 1.5), to: "q.north"), name: "m")
    content("m", [M寄存器])

    rect((rel: (0.5, -0.8), to: "q.east"), (rel: (3.5, 0.8), to: "q.east"), name: "booth")
    content("booth", [$Q[0],Q_1$判定\ 00/01/10/11])

    rect((rel: (1, 0.5), to: "booth.east"), (rel: (4, 2), to: "booth.east"), name: "add")
    content("add", [A ± M\ CLA加法器])

    rect((rel: (-1.5, -0.5), to: "add.south"), (rel: (1.5, -2), to: "add.south"), name: "shift")
    content("shift", [算术右移\ $A,Q[0],Q_1$])

    rect((rel: (1, -1), to: "shift.east"), (rel: (5, 1), to: "shift.east"), name: "fsm")
    content("fsm", [FSM\ IDLE/COMPUTE\ /FINISH])

    rect((rel: (-2, 0.5), to: "fsm.north"), (rel: (2, 2), to: "fsm.north"), name: "outm")
    content("outm", [product=A,Q\ done])

    line("m", "add")
    line("q", "booth")
    line("q1", "booth")
    line("booth", "add")
    line("add", "shift")
    line("shift", "fsm")
    line("fsm", "outm")
  }),
  kind: "graph",
  supplement: [图],
)

== 非恢复余数除法器架构图

#figure(
  caption: [非恢复余数除法器数据通路与修正流程图],
  cetz.canvas({
    import cetz.draw: *

    set-style(stroke: (paint: black, thickness: 0.8pt), fill: rgb("fffaf3"))

    rect((0, 4.8), (2.8, 6.1), name: "abs")
    content("abs", [绝对值预处理\ dividend/divisor\ 除零与溢出判断])

    rect((3.6, 5.0), (6.1, 6.0), name: "d")
    content("d", [D寄存器\ |divisor|])

    rect((3.6, 3.4), (6.1, 4.4), name: "r")
    content("r", [R寄存器\ 余数])

    rect((3.6, 1.8), (6.1, 2.8), name: "q")
    content("q", [Q寄存器\ 商])

    rect((6.9, 4.0), (9.5, 5.2), name: "core")
    content("core", [非恢复余数主循环\ 左移 + 加/减选择])

    rect((6.9, 2.4), (9.5, 3.4), name: "fix")
    content("fix", [FIX阶段\ R < 0 时恢复])

    rect((10.2, 4.0), (12.8, 5.2), name: "sign")
    content("sign", [符号恢复\ 商异或/余数同号])

    rect((10.2, 2.2), (12.8, 3.4), name: "spec")
    content("spec", [特殊修正\ 同号进一位\ 异号退一位])

    rect((13.5, 3.0), (15.8, 4.3), name: "out")
    content("out", [quotient\ remainder\ done])

    line("abs.east", "d.west")
    line("abs.east", "r.west")
    line("abs.east", "q.west")
    line("d.east", "core.west")
    line("r.east", "core.west")
    line("q.east", "core.west")
    line("core.east", "fix.west")
    line("fix.east", "sign.west")
    line("sign.south", "spec.north")
    line("spec.east", "out.west")
  }),
  kind: "graph",
  supplement: [图],
)

== 关键实现特点

- 控制方式清晰：one-hot 编码减少译码复杂度，便于测试激励构造。
- 结构可综合：结果选择与完成信号均使用多路选择器结构，避免依赖高层语法推断特定 IP。
- 时序边界明确：组合运算与多周期运算在顶层通过寄存与握手机制解耦。
- 可扩展性好：新增运算时可沿用“新增子模块 + 扩展控制位 + 接入选择器”的模式。

综上，顶层 `alu_32bit.v` 实现了课程实验要求的 32 位 ALU 功能集合，并形成了可验证、可综合、可扩展的模块化实现。

