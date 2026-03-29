#import "tbook.typ"

#show: doc => tbook.tbook([非恢复余数除法器], doc)

= 非恢复余数除法器

== 数学原理

设被除数为$N$，除数为$D$（$D != 0$），商为$Q$，余数为$R$，满足：

$ N = "DQ" + R, quad |R| < |D| $

二进制迭代除法的核心思想是“左移余数并试减除数”：

1. 先把余数与商寄存器做联合左移。
2. 计算$R' = R - D$。
3. 若$R' >= 0$，则本位商为1并保留$R'$；若$R' < 0$，则本位商为0并恢复为原左移后的$R$。

重复32轮后得到无符号幅值的商和余数，再依据输入符号做补码修正。

== 实现要点

`rtl/non_restoring_divider.v`同样采用`IDLE -> COMPUTE -> FINISH`三态结构。

+ `IDLE`：在`start`时锁存输入，记录`sign_dividend/sign_divisor`，并将被除数与除数转为绝对值幅值运算。
+ `COMPUTE`：执行32轮“左移 + 试减 + 判符号 + 写商位”。
+ `FINISH`：输出有效并返回空闲。

数据通路中的关键组合量：

+ `shifted_R = {R[30:0], Q[31]}`，表示联合左移后新的余数候选。
+ `sub_result = shifted_R + (~D) + 1`，用CLA实现$"shifted_R" - D$。

判定逻辑以`sub_result[31]`为符号位：

+ 若为1（负），说明试减失败：$R <= "shifted_R"$，`Q `$<=$` {Q[30:0], 1'b0}`。
+ 若为0（非负），说明试减成功：$R <= "sub_result"$，`Q `$<=$` {Q[30:0], 1'b1}`。

符号修正阶段：

+ 商符号为`sign_dividend ^ sign_divisor`，若为负则对`Q`取补码。
+ 余数符号与被除数一致，若被除数为负则对`R`取补码。

因此输出满足有符号除法常见约定：商按异号为负，余数同被除数符号。最终`done`在`FINISH`态拉高。

详细代码见`rtl/non_restoring_divider.v`。
