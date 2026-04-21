#import "tbook.typ"

#show: doc => tbook.tbook([非恢复余数除法器], doc)

= 非恢复余数除法器

== 数学原理

设被除数为$N$，除数为$D$（$D != 0$），商为$Q$，余数为$R$，满足：

$ N = "DQ" + R, quad |R| < |D| $

非恢复余数（non-restoring）算法的核心是“按当前余数符号决定加减”，而不是“试减失败再恢复”。

对每一轮迭代，执行顺序为：

1. 组合左移：$R_s = {R[30:0], Q[31]}$。
2. 按当前余数符号选择运算：
	+ 若$R >= 0$，执行$R_n = R_s - D$。
	+ 若$R < 0$，执行$R_n = R_s + D$。
3. 按新余数符号写商位：
	+ 若$R_n >= 0$，则本位商为1。
	+ 若$R_n < 0$，则本位商为0。

迭代32轮后，若终态余数仍为负，则执行一次修正：$R = R + D$。

本实现在主循环中使用绝对值幅值运算，循环后再进行符号恢复与特殊修正。

== 状态机与数据通路

当前`rtl/non_restoring_divider.v`采用四态结构：

+ `IDLE`：等待`start`，锁存输入与符号信息。
+ `COMPUTE`：执行32轮 non-restoring 迭代。
+ `FIX`：终态余数修正（仅当`R[31]==1`时做`R=R+D`）。
+ `FINISH`：输出有效，下一拍回到`IDLE`。

关键组合信号：

+ `shifted_R = {R[30:0], Q[31]}`
+ `r_sub_d = shifted_R - D`
+ `r_add_d = shifted_R + D`
+ `r_next`由`R[31]`选择：`R>=0`选`r_sub_d`，`R<0`选`r_add_d`
+ `q_next_bit = ~r_next[31]`

这对应“按当前余数符号选加减，按新余数符号上商位”的标准 non-restoring 规则。

== 异常与边界处理

当前实现包含两类显式边界分支：

+ 除零：若`divisor == 0`，输出`quotient = 0`、`remainder = dividend`。
+ 溢出：若`dividend == 0x8000_0000`且`divisor == 0xFFFF_FFFF`（即$-2^31 / -1$），输出截断语义`quotient = 0x8000_0000`、`remainder = 0`。

其中$-2^31 / -1$在32位有符号整数下不可表示，模块采用“二补码截断”约定。

== 符号恢复与特殊修正

主循环结束后先做符号恢复：

+ 商符号：`sign_dividend ^ sign_divisor`
+ 余数符号：与被除数同号

随后做两类特殊修正（参考`docs/div.c`中的约定）：

+ 同号整除修正：若`final_remainder == divisor`，执行`quotient += 1`、`remainder -= divisor`。
+ 异号整除修正：若`final_remainder + divisor == 0`，执行`quotient -= 1`、`remainder = 0`。

这两类修正在除零与溢出场景下会被屏蔽，避免互相覆盖。

== 时序与完成信号

`done`定义为`state == FINISH`。

+ 常规路径：`IDLE -> COMPUTE(32轮) -> FIX -> FINISH`，最多33拍结束。
+ 除零与溢出路径：`IDLE -> FINISH`快速完成。

== 验证情况

除ALU顶层回归外，已增加模块级测试：`tb/tb_non_restoring_divider.v`。

该测试覆盖：

+ 常规有符号除法：`1000/7`、`-1000/7`、`1000/-7`、`-1000/-7`
+ INT_MIN边界：`INT_MIN/1`、`INT_MIN/-1`、`INT_MIN/2`、`INT_MIN/3`、`INT_MIN/-3`
+ 约定场景：`123/0`、`0/7`

当前构建命令：

`python tools/mk.py --top dev/1alu/tb/tb_non_restoring_divider.v`

当前结果：11/11全部通过。

