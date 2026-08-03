## 第17章. "Zalasr" 原子 Load-Acquire 和 Store-Release 指令扩展, 版本 1.0

Zalasr（Load-Acquire 和 Store-Release）扩展在 RISC-V 中提供 load-acquire 和 store-release 指令。这对于高性能设计很重要，因为它通过提供单向屏障来实现比仅使用 fence 更细粒度的同步。Load-acquire 和 store-release 在语言级内存模型中广泛使用：Java 和 C++ 内存模型都使用 acquire-release 语义，而 C++ 的 `atomic` 提供旨在直接映射到 load-acquire 和 store-release 指令的原语。

Zalasr 扩展建立在 Zaamo（原子内存操作）、Zalrsc（Load-Reserved 和 Store-Conditional）以及 Zabha（字节和半字原子内存操作）扩展提供的原子支持之上，提供额外的原子操作（尽管它可以独立于它们实现）。Zaamo（和 Zabha）中的所有 AMO 操作都是既加载又存储的读-改-写操作。Zalrsc 扩展提供仅加载或仅存储的操作。然而，由于其设计目的是对单个内存字或双字执行原子操作，因此加载和存储被设计为成对使用。load-reserved 意味着后续将跟有 store-conditional，而 store-conditional 要求之前有 load-reserved 而没有其他介入的加载或存储。因此，Zalrsc 扩展不提供通用的原子和有序的加载或存储。

Zalasr 通过提供真正独立的原子和有序加载和存储来填补这一空白。Zalasr 指令是支持排序注解的原子加载和存储。结合 Zaamo、Zabha 和 Zalasr，所有 C++ 原子操作都可以用单条指令支持。

## 17.1. Load-Acquire 和 Store-Release 指令

Zalasr 指令始终将放入 _rd_ 的值符号扩展，并忽略 _rs2_ 值的较高位。Zalasr 扩展中的指令要求 _rs1_ 中保存的地址自然对齐到操作数以字节为单位的大小（2^[width]）。如果地址未自然对齐，将产生地址未对齐异常或访问故障异常。如果未对齐访问不应被模拟，那么即使未对齐情况下的内存访问本来可以完成，也会产生访问故障异常。

未对齐原子粒度 PMA 在 Volume II 中定义，可选地放宽此对齐要求。如果所有访问的字节位于同一个未对齐原子粒度内，指令不会因地址对齐原因引发异常，且对于 RVWMO 目的，指令将只产生一个内存操作——即它将原子地执行。

## 17.2. Load Acquire

## 概述

load-acquire 指令原子地从 _rs1_ 中的地址加载一个 2^[width] 字节的值，并将符号扩展的值放入寄存器 _rd_，受指令中指定的排序注解约束。

## 助记符

lb.{aq,aqrl} _rd_ , ( _rs1_ ) lh.{aq,aqrl} _rd_ , ( _rs1_ ) lw.{aq,aqrl} _rd_ , ( _rs1_ ) ld.{aq,aqrl} _rd_ , ( _rs1_ )

## 编码

|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|
|---|---|---|---|---|---|---|---|
|funct5|aq|rl|rs2|rs1|funct3|rd|opcode|
|7<br>AMO<br>5<br>dest<br>3<br>width<br>5<br>addr<br>5<br>0<br>1<br>ring<br>1<br>orde<br>1<br>5<br>Load Acquire<br>00110||||||||

## 描述

此指令从 rs1 原子地加载 2^[width] 字节的内存并将结果写入 rd。如果大小（2^[width+3]）小于 XLEN，则将其符号扩展以填充目标寄存器。此加载必须具有编码在指令中的排序注解 _aq_，并且可以具有排序注解 _rl_。该指令始终具有 "acquire-RCsc" 注解，如果位 _rl_ 被设置，则指令具有 "release-RCsc" 注解。

不设置 _aq_ 位的版本是保留的。LD.{AQ, AQRL} 仅 RV64。

**评论：** _aq 位是强制性的，因为产生的两种编码在目前看来没有用处。既不设置 aq 也不设置 rl 位的版本将对应一个保证原子执行但没有排序注解的加载。这可以通过普通加载指令并适当对齐指针来实现。仅设置 rl 位的版本将对应 load-release。Load-release 在 seqlocks 中有理论应用，但不受语言级内存模型支持，因此未包含。_

## 17.3. Store Release

## 概述

store-release 指令原子地将寄存器 _rs2_ 低位的 2^[width] 字节值存储到 _rs1_ 中的地址，受指令中指定的排序注解约束。

## 助记符

sb.{rl,aqrl} _rs2_ , ( _rs1_ ) sh.{rl,aqrl} _rs2_ , ( _rs1_ ) sw.{rl,aqrl} _rs2_ , ( _rs1_ ) sd.{rl,aqrl} _rs2_ , ( _rs1_ )

## 编码

|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>24<br>25<br>26<br>27<br>31|
|---|---|---|---|---|---|---|---|
|funct5|aq|rl|rs2|rs1|funct3|rd|opcode|
|7<br>AMO<br>5<br>0<br>3<br>width<br>5<br>addr<br>5<br>src<br>1<br>ring<br>1<br>1<br>orde<br>5<br>Store Release<br>00111||||||||

## 描述

此指令从 rs1 原子地存储 2^[width] 字节的内存。此存储必须具有编码在指令中的排序注解 _rl_，并且可以具有排序注解 _aq_。该指令始终具有 "release-RCsc" 注解，如果位 _aq_ 被设置，则指令具有 "acquire-RCsc" 注解。

不设置 _rl_ 位的版本是保留的。SD.{RL, AQRL} 仅 RV64。

**评论：** _rl 位是强制性的，因为产生的两种编码在目前看来没有用处。既不设置 aq 也不设置 rl 位的版本将对应一个保证原子执行但没有排序注解的存储。这可以通过普通存储指令并适当对齐指针来实现。仅设置 aq 位的版本将对应 store-acquire。Store-acquire 在 seqlocks 中有理论应用，但不受语言级内存模型支持，因此未包含。_
