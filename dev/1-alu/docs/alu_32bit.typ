#import "tbook.typ"

#show: doc => tbook.tbook([ALU顶层模块 alu_32bit], doc)

= ALU顶层模块 alu_32bit

== 模块组成

`rtl/alu_32bit.v`是整个32位ALU的顶层封装，内部主要由以下部件组成：

+ `cla_adder_32bit`：完成加法运算（ADD）。
+ `subtractor`：完成减法运算（SUB）。
+ `logic_unit`：完成AND/OR/NOT/XOR/NOR/SLT/SLTU。
+ `shifter`（3个实例）：分别实现SLL、SRL、SRA。
+ `lui`：实现LUI（高位加载）。
+ `booth_multiplier`：多周期有符号乘法（MUL）。
+ `non_restoring_divider`：多周期有符号除法（DIV）。

顶层负责：

+ 将`alu_control`拆分为各功能使能位。
+ 对乘法器和除法器产生`start`脉冲并锁存输入。
+ 在各子模块输出间进行结果选择，最终给出`result`与`done`。

== 输入输出含义

输入端口：

+ `clk`：时钟信号，驱动多周期模块与顶层控制寄存器。
+ `reset`：复位信号，高电平有效。
+ `alu_control[15:0]`：one-hot控制信号，每一位对应一种ALU操作。
+ `src1[31:0]`：操作数1。
+ `src2[31:0]`：操作数2。

输出端口：

+ `result[31:0]`：当前被选中操作的32位结果。
+ `done`：操作完成标志。

`done`语义：

+ 对单周期组合操作（加减、逻辑、移位、LUI）恒为1。
+ 对`MUL`和`DIV`，等待对应子模块`mul_done/div_done`后置1。

== 控制信号与结果选择

`alu_control`按位映射如下：

+ `[15] MUL`
+ `[14] DIV`
+ `[13] NOT`
+ `[12] ADD`
+ `[11] SUB`
+ `[10] SLT`
+ `[9]  SLTU`
+ `[8]  AND`
+ `[7]  NOR`
+ `[6]  OR`
+ `[5]  XOR`
+ `[4]  SLL`
+ `[3]  SRL`
+ `[2]  SRA`
+ `[1]  LUI`

顶层通过优先级条件选择输出：

+ 乘法返回`mul_result[31:0]`（低32位）。
+ 除法返回`div_quotient`（商）。
+ 其余操作返回对应子模块输出。
+ 若无控制位命中，输出`32'b0`。

详细实现见`rtl/alu_32bit.v`。
