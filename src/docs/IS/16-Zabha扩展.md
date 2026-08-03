## 第16章. "Zabha" 字节和半字原子内存操作扩展, 版本 1.0

A 扩展为 _字_、_双字_ 和 _四字_（仅 `AMOCAS`）提供了原子内存操作 (AMO) 指令。缺少子字数据类型的原子操作迫使需要模拟策略。对于按位操作，可以通过字大小的按位 AMO* 指令执行此模拟。对于非按位操作，可以使用字大小的 `LR` / `SC` 指令实现模拟。

此模拟方法存在若干局限：

1. 在大规模或非均匀内存访问 (NUMA) 配置的系统中，基于 `LR` / `SC` 的模拟引入了与可扩展性和公平性相关的问题，特别是在高竞争条件下。

2. 通过更宽的 AMO* 指令在非幂等 IO 内存区域上模拟较窄的 AMO 可能导致意外的副作用。

3. 利用更宽的 AMO* 指令模拟较窄的 AMO 存在激活多余断点或观察点的风险。

4. 在缺乏子字原子操作原生支持的情况下，编译器通常诉诸于内联代码序列来提供所需的模拟。这种做法导致代码体积增加，进而影响系统性能和内存利用率。

Zabha 扩展通过向 RISC-V Unprivileged ISA 添加对 _字节_ 和 _半字_ 原子内存操作的支持来解决这些局限。Zabha 扩展依赖于 Zaamo 标准扩展。

## 16.1. 字节和半字原子内存操作指令

Zabha 扩展提供 `AMO[ADD|AND|OR|XOR|SWAP|MIN[U]|MAX[U]].[B|H]` 指令。如果同时实现了 Zacas 扩展，Zabha 进一步提供 `AMOCAS.[B|H]` 指令。

|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|
|---|---|---|---|---|---|---|---|
|funct5|aq|rl|rs2|rs1|funct3|rd|opcode|
|AMO<br>AMO<br>AMO<br>AMO<br>AMO<br>AMO<br>AMO<br>AMO<br>dest<br>dest<br>dest<br>dest<br>dest<br>dest<br>dest<br>dest<br>width=0/1<br>width=0/1<br>width=0/1<br>width=0/1<br>width=0/1<br>width=0/1<br>width=0/1<br>width=0/1<br>addr<br>addr<br>addr<br>addr<br>addr<br>addr<br>addr<br>addr<br>src<br>src<br>src<br>src<br>src<br>src<br>src<br>src<br>ordering<br>ordering<br>ordering<br>ordering<br>ordering<br>ordering<br>ordering<br>ordering<br>AMOSWAP.B/H<br>AMOADD.B/H<br>AMOAND.B/H<br>AMOOR.B/H<br>AMOXOR.B/H<br>AMOMAX[U].B/H<br>AMOMIN[U].B/H<br>AMOCAS.B/H||||||||

字节和半字 AMO 始终将放入 `rd` 的值符号扩展，并忽略 `rs2` 中原始值的高位。`AMOCAS.[B|H]` 指令类似地忽略 `rd` 中原始值的高位。

与 A 扩展中指定的 AMO 类似，Zabha 扩展要求 `rs1` 寄存器中包含的地址必须自然对齐到操作数的大小。在地址未自然对齐的情况下，适用与 A 扩展中指定的相同的异常选项。

与 A 和 Zacas 扩展中指定的 AMO 类似，Zabha 扩展中的 AMO 可选地使用 `aq` 和 `rl` 位提供 release consistency 语义，以帮助实现多处理器同步。

**评论：** _Zabha 由于实用性较低而省略了对 `LR` 和 `SC` 的字节和半字支持。_
