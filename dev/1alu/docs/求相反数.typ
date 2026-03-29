#import "tbook.typ"

#show: doc => tbook.tbook([求相反数], doc)

= 求相反数

== 数学方法

假设x位一个32位比特向量（补码表示），且从低位到高位的第一个1在第k位，则其相反数的补码表示就是将x中k位以上的部分逐位取反。

$ x+(-x)=0=2^(32) arrow.double -x=2^(32)-x $

从以上公式中易得以上方法。

== 实现

我们需要一个线性电路`inhibitory`记录传播为1的情况，当其低位曾经存在1时其就为1。其他部分：
+ `inhibitory`为0时放行原数据
+ `inhibitory`为1时方向求非结果

详细实现见`rtl/get_neg.v`
