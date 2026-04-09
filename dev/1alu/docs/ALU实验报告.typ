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

输入数据经过所有模块的并行计算后通过`alu_result_selector`多选一模块选择输出。

对于多周期操作的同步问题，我们通过done信号线进行完成控制，且区分了组合操作和时序操作的done信号。

== 超前进位加法器（CLA）

对于一般的行波进位加法器中的每一个组件（全加器），我们有：

$cases(
  S_i=A plus.o B plus.o C_i,
  C_(i+1)=A_i circle.filled.tiny B_i + A_i circle.filled.tiny C_i + B_i circle.filled.tiny C_i
)$

令~$G_i=A_i circle.filled.tiny B_i, P_i=A_i+B_i$，则~$C_(i+1)=G_i+P_i circle.filled.tiny C_i$~。

可见，进位中的~$G_i$~和~$P_i$~不依赖前面的数据，仅依赖本位数据，于是，我们可以将行波进位加法器改为：

$cases(
  C_1&=G_0+P_0 circle.filled.tiny C_("in"),
  C_2&=G_1+P_1 circle.filled.tiny C_1, &=G_1+P_1 circle.filled.tiny G_0 + P_0 circle.filled.tiny P_1 circle.filled.tiny C_("in"),
  C_3&=G_2+P_2 circle.filled.tiny C_2,
  &=G_2+P_2 circle.filled.tiny G_1 + P_1 circle.filled.tiny P_2 circle.filled.tiny G_0+P_0 circle.filled.tiny P_1 circle.filled.tiny P_2 circle.filled.tiny C_("in"),
  C_4&=G_3+P_3 circle.filled.tiny C_3,
  &=G_3+P_3 circle.filled.tiny G_2+P_2 circle.filled.tiny P_3 circle.filled.tiny G_1+P_1 circle.filled.tiny P_2 circle.filled.tiny P_3 circle.filled.tiny G_0+P_0 circle.filled.tiny P_1 circle.filled.tiny P_2 circle.filled.tiny P_3 circle.filled.tiny C_("in"),
  C_("out")&=C_4
)$

可见，这个四位行波进位加法器其实不需要一个一个计算，每一个进位实际上都可以直接通过输入数据进行计算。

又由于$S_i=A plus.o B plus.o C_i$，我们可以构建一个四位超前进位加法器。

32位超前进位加法器虽然也可以直接构建（通过找规律），但是这样对于芯片面积的消耗太大，也不利于布线，所以我们加法模块采用 32 位层次化超前进位结构：4 位 CLA 组成 16 位 CLA，再由两个 16 位 CLA 构成 32 位加法器。其核心思想是提前并行计算进位，而不是像行波进位那样逐位传播。

对第 $i$ 位定义：

- 进位生成信号：$G_i = A_i dot B_i$
- 进位传递信号：$P_i = A_i plus.o B_i$
- 进位关系：$C_(i+1) = G_i + P_i C_i$
- 和位：$S_i = P_i plus.o C_i$

CLA 的优点是进位计算层次化并行，可显著降低长位宽加法延迟。顶层 ADD 直接取 CLA 输出。

== 桶形移位器

固定位的位移很简单，就是将输入输出线对应连接好就行，见`SHL_x.v`，问题在于不固定位数的位移器。

参考人民币币值的设计，不固定位数的位移器也可以使用多个固定位的位移完成。

在设计上来说，以~$2^n$~作为划分是一个很好的想法，一方面每个位移最多只需要一个就可以完成任意大小的位移，另一方面可以直接读取二进制位判断需不需要当前位数的位移。

具体来说，移位模块采用 5 级桶形位移结构，每一级对应一个二次幂移位量：1、2、4、8、16。通过 `shamt[4:0]` 控制各级是否生效，最终实现 0 到 31 位任意移位。

== 小于置位（SLT/SLTU）判断方法

SLT 与 SLTU 都输出 32 位，其中低位 `bit0` 为比较结果，其余位清零。

1. SLT（有符号小于）
先做减法 `a - b`，然后分情况判断：

- 若 `a` 与 `b` 符号不同，`a` 为负时必有 `a < b`；
- 若符号相同，则比较差值符号位。

代码等价表达为：

$"slt" = (a_(31) and overline(b_(31))) or (overline(a_(31) plus.o b_(31)) and "sub"_(31))$

2. SLTU（无符号小于）
无符号比较通过减法借位判断，而由于是补码表示，减法转化为加法，所以最终是比较进位。

令 $a + (~ b + 1)$ 的最终进位为 `cout`：

- `cout = 1` 表示无借位，即 $a >= b$；
- `cout = 0` 表示有借位，即 $a < b$。

因此 `sltu = ~cout`。

== 乘法算法（Booth）

Booth乘法器实际上是使用Booth编码的乘法器，布斯编码可以减少部分积的数目，用来计算有符号乘法，提高乘法运算的速度。

考虑一个由若干个0包围着若干个1的正的二进制乘数，比如00111110，与另一个乘数M的积可以表达为:$ M times [00111110]_B = M times (2^5+2^4+2^3+2^2+2^1)=M times 62 $

按照类手算算法需要至少5次乘法计算，而乘法而变形为下面的方式可以让计算次数减少为两次：$ M times [010000(-1)0]_B=M times (2^6-2^1)=M times 62 $

事实上，任何二进制数中连续的1可以被分解为两个二进制数之差：$ (dots 0overbrace(1 dots 1, n)0 dots)_B=(dots 1overbrace(0 dots 0, n)0 dots)_B-(dots 0overbrace(0 dots 1, n)0 dots)_B $

因此,我们可以用更简单的运算来替换原数中连续为1的数字的乘法，通过加上乘数，对部分积进行移位运算，最后再将之从乘数中减去。它利用了我们在针对为零的位做乘法时，不需要做其他运算，只需移位这一特点，这很像我们在做和99的乘法时利用99=100-1这一性质。这种模式可以扩展应用于任何一串数字中连续为1的部分(包括只有一个1的情况)。

布斯算法遵从这种模式，它在遇到一串数字中的第一组从0到1的变化时(即遇到01时)执行加法，在遇到这一串连续1的尾部时(即遇到10时)执行减法。这在乘数为负时同样有效。当乘数中的连续1比较多时(形成比较长的1串时)，布斯算法较一般的乘法算法执行的加减法运算少。

== 非恢复余数除法器

非恢复余数除法器是恢复余数除法器的优化版本，通过延迟恢复与后续操作合并的操作，节省了每一步的恢复步骤，并且数据通路更加连贯，复用性更高，使得其拥有更高的性能。

算法步骤（以 $n$ 位运算为例）

+ 初始化
  - 将除数存入寄存器 $Y$（$n$ 位补码）。
  - 将 $-Y$ 存入寄存器（取补码）。
  - 将被除数符号扩展后装入 $R$（高 $n$ 位）和 $Q$（低 $n$ 位）。

+ 循环迭代（共 $n-1$ 次）\
  对于 $i = 1$ 到 $n-1$：

  - 左移：将 $(R, Q)$ 组合左移一位，相当于 $R = 2R$ 并移入 $Q$ 的最高位，$Q$ 左移一位。
  - 运算选择：
    - 若当前 $R_i$ 与 $Y$ *同号*，则 $R_(i+1) = 2R_i - Y$（减法）；
    - 若当前 $R_i$ 与 $Y$ *异号*，则 $R_(i+1) = 2R_i + Y$（加法）。
  - 上商：
    - 若新余数 $R_(i+1)$ 与 $Y$ *同号*，则商位为 1；
    - 否则商位为 0。
  - 将商位移入 $Q$ 的最低位。

+ 第 $n$ 次操作
  - 完成第 $n$ 次左移和加减后，仅将商位写入 $Q$，不再对 $R$ 进行下一轮更新（因为已得到 $n$ 位商）。

+ 商修正
  - 若*被除数*与*除数*异号，则最终的商需要加 1（即对未修正的商求补码）。
  - 若同号，商不变。

+ 余数修正
  - 若最终*余数* $R$ 与*被除数*同号，则无需修正。
  - 若异号：
    - 若*被除数*与*除数**同号*，则余数*加*除数；
    - 若被除数与除数*异号*，则余数*减*除数。

+ 特殊情形修正
  - *同号相除且能整除*（如 $(-8) / (-8)$）：若余数等于除数，则余数减去除数，商加 1。
  - *异号相除且能整除*（如 $(-8) / 2$）：若余数加上除数为 0，则商减 1，余数置 0。

== 完成信号原理

`done` 信号分两类（高电平有效）：

- 非乘除法操作：`done = 1`（默认立即完成）。
- DIV：`done = div_done`。
- MUL：`done = mul_done`。

顶层通过多路选择结构根据`alu_control`码选择对应上述信号进行输出，实现统一时序语义。

= 功能实现

== 模块划分

`alu_32bit.v` 在结构上采用“并行计算 + 统一选择”的实现方式，主要由以下子模块组成（每一个都是独立的`.v`文件）：

- `cla_adder_32bit`：32位超前进位加法器顶层模块。
- `subtractor`：SUB 运算（内部调用ADD）。
- `logic_unit`：AND/OR/NOT/XOR/NOR/SLT/SLTU集成模块。
- `shifter`实现 SLL、SRL、SRA。
- `lui`：高位装载运算。
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

    line("in", "comb", mark: (end: "straight"))
    line("in", "seq", mark: (end: "straight"))
    line("comb", "sel", mark: (end: "straight"))
    line("seq", "sel", mark: (end: "straight"))
    line("sel", "out", mark: (end: "straight"))
    line("seq", "done", mark: (end: "straight"))
  }),
  kind: "graph",
  supplement: [图],
)

== 桶形移位器

移位模块采用 5 级桶形位移结构，每一级对应一个二次幂移位量：1、2、4、8、16。通过 `shamt[4:0]` 控制各级是否生效，最终实现 0 到 31 位任意移位。

具体实现方式如下：

- 第 1 级根据 `shamt[0]` 决定是否移 1 位。
- 第 2 级根据 `shamt[1]` 决定是否移 2 位。
- 第 3 级根据 `shamt[2]` 决定是否移 4 位。
- 第 4 级根据 `shamt[3]` 决定是否移 8 位。
- 第 5 级根据 `shamt[4]` 决定是否移 16 位。

需要注意的是，我们硬件上将SLL/SRL/SRA作为三条独立的部件进行实现，功能分别是：

- SLL：左移，低位补 0。
- SRL：右移，高位补 0。
- SRA：算术右移，高位补符号位。

最终使用一个 `mux_4to1` 部件由 `shift_type` 在三类结果中选择输出。

== 超前进位加法器（CLA）

4位超前进位加法器完全和原理部分列出的表达式相同，同时它们也输出内部的进位计算结果`G,P`，所以16位的CLA就可以基于其构建：

#figure(
  [```verilog
module cla_adder_16bit(
  input  [15:0] a,
  input  [15:0] b,
  input         cin,
  output [15:0] sum,
  output        cout
  );
  wire [3:0] g0, p0, g1, p1, g2, p2, g3, p3;
  wire c4, c8, c12;
  cla_adder_4bit cla0(.a(a[3:0]), .b(b[3:0]), .cin(cin),
  .sum(sum[3:0]), .cout(c4), .g(g0), .p(p0));
  cla_adder_4bit cla1(.a(a[7:4]), .b(b[7:4]), .cin(c4),
  .sum(sum[7:4]), .cout(c8), .g(g1), .p(p1));
  cla_adder_4bit cla2(.a(a[11:8]), .b(b[11:8]), .cin(c8),
  .sum(sum[11:8]), .cout(c12), .g(g2), .p(p2));
  cla_adder_4bit cla3(.a(a[15:12]), .b(b[15:12]), .cin(c12),
  .sum(sum[15:12]), .cout(cout), .g(g3), .p(p3));
endmodule```],
  caption: [16位超前进位加法器构建],
  kind: "code",
  supplement: [代码],
)

需要注意的是，32位我们没有使用进位生成器，而是使用了一种类似于串行的方法，因为这一层只需要2个16位超前进位加法器，时延问题并不明显。

== 多路选择器（MUX）

多路选择器的基础--二路选择器是由门构造的，更高层次的$2^n$选1选择器是由2-1选择器构造的。

并且，我们使用了Verilog-2001 标准引入的参数化模块定义语法（类似于模板函数），使得其拥有更强的适应性。

#figure(
  [```verilog
module mux_2to1 #(parameter WIDTH = 32)(
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input              sel,
    output [WIDTH-1:0] y
  );
  wire [WIDTH-1:0] a_masked;
  wire [WIDTH-1:0] b_masked;
  wire [WIDTH-1:0] not_sel_vec;

  // 对每一位独立实现: y[i] = (a[i] & ~sel) | (b[i] & sel)
  genvar i;
  generate
    for (i = 0; i < WIDTH; i = i + 1)
    begin : mux_bit
      not u_not_sel(not_sel_vec[i], sel);
      and u_and_a(a_masked[i], a[i], not_sel_vec[i]);
      and u_and_b(b_masked[i], b[i], sel);
      or  u_or_y(y[i], a_masked[i], b_masked[i]);
    end
  endgenerate
endmodule```],
  caption: [2-1选择器],
  kind: "code",
  supplement: [代码],
)

== Booth乘法器

乘法器采用 Booth 有符号乘法算法，状态机为 `IDLE -> COMPUTE -> FINISH`。寄存器含义如下：

- `A`：部分积累加器。
- `Q`：乘数寄存器。
- $Q_1$：扩展位。
- `M`：被乘数寄存器。

每个计算周期检查二位组合 $(Q[0], Q_1)$：

- `00` 或 `11`：不加减，仅算术右移。
- `01`：执行 `A = A + M`，再算术右移。
- `10`：执行 `A = A - M`，再算术右移。

共迭代 32 次后进入 FINISH，输出 `product = (A, Q)`，顶层取低 32 位作为 ALU 的 MUL 结果。

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

#figure(
  caption: [非恢复余数除法器数据通路与修正流程图],
  cetz.canvas({
    import cetz.draw: *

    set-style(stroke: (paint: black, thickness: 0.8pt), fill: rgb("fffaf3"))

    rect((0, 4), (3.5, 6.1), name: "abs")
    content("abs", [绝对值预处理\ dividend/divisor\ 除零与溢出判断])
    
    rect((rel: (0.3, -0.5), to: "abs.east"), (rel: (2.5, 1), to: "abs.east"), name: "d")
    content("d", [D寄存器\ 除数])

    rect((rel: (-1.1, -1.5), to: "d.south"), (rel: (1.1, -0.3), to: "d.south"), name: "r")
    content("r", [R寄存器\ 余数])

    rect((rel: (-1.1, -1.5), to: "r.south"), (rel: (1.1, -0.3), to: "r.south"), name: "q")
    content("q", [Q寄存器\ 商])

    rect((6.5, 4.0), (10.5, 5.5), name: "core")
    content("core", [非恢复余数主循环\ 左移 + 加/减选择])

    rect((rel: (-1.5, -1.5), to: "core.south"), (rel: (1.5, -0.3), to: "core.south"), name: "fix")
    content("fix", [FIX阶段\ R < 0 时恢复])

    rect((rel: (0.4, -0.7), to: "core.east"), (rel: (4, 0.7), to: "core.east"), name: "sign")
    content("sign", [符号恢复\ 商异或/余数同号])

    rect((rel: (-1.8, -2.5), to: "sign.south"), (rel: (1.8, -0.3), to: "sign.south"), name: "spec")
    content("spec", [特殊修正\ 同号进一位\ 异号退一位])

    rect((15, 3.0), (17.5, 5), name: "out")
    content("out", [quotient\ remainder\ done])

    line("abs.east", "d.west")
    line("abs.east", "r.west")
    line("abs.east", "q.west")
    line("d.east", "core.west")
    line("r.east", "core.west")
    line("q.east", "core.west")
    line("core", "fix")
    line("fix.east", "sign.west")
    line("sign.south", "spec.north")
    line("spec.east", "out.west")
  }),
  kind: "graph",
  supplement: [图],
)
