#set title("求相反数")
#set page(header: align(right, [_技术文档 - 求相反数_]))
#set text(size: 18pt)
#show heading: it => {
  block([#sym.section *#it.body*], below: 0.8em)
}
#set par(first-line-indent: (amount: 2em, all: true))
#show strong: text.with(font: ("Microsoft YaHei"))
#show emph: text.with(font: ("Calibri","LiSu"))

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