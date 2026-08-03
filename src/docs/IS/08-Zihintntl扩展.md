# 第8章 "Zihintntl" 非时间局部性提示扩展，版本 1.0

NTL 指令是 HINT，指示紧接其后的指令（以下称 "目标指令"）的显式内存访问表现出较差的时间引用局部性。NTL 指令不改变架构状态，也不改变目标指令的架构可见效果。提供了四种变体：

NTL.P1 指令指示目标指令在内存层次结构中最内层私有缓存的容量内不表现出时间局部性。NTL.P1 编码为 ADD _x0, x0, x2_。

NTL.PALL 指令指示目标指令在内存层次结构中任何级别的私有缓存的容量内都不表现出时间局部性。NTL.PALL 编码为 ADD _x0, x0, x3_。

NTL.S1 指令指示目标指令在内存层次结构中最内层共享缓存的容量内不表现出时间局部性。NTL.S1 编码为 ADD _x0, x0, x4_。

NTL.ALL 指令指示目标指令在内存层次结构中任何级别的缓存的容量内都不表现出时间局部性。NTL.ALL 编码为 ADD _x0, x0, x5_。

_NTL 指令可用于在流式传输数据或遍历大型数据结构时避免缓存污染，或用于减少生产者-消费者交互中的延迟。_

_微架构可以使用 NTL 指令来通知缓存替换策略，或决定分配到哪个缓存，或完全避免缓存分配。例如，NTL.P1 可能指示实现不应在私有 L1 缓存中分配缓存行，但应在 L2（无论是私有还是共享）中分配。在另一种实现中，NTL.P1 可能在 L1 中分配缓存行，但处于最近最少使用状态。_

_NTL.ALL 通常会指示实现不在缓存层次结构的任何位置分配。程序员应对没有可利用率的时间局部性的访问使用 NTL.ALL。_

_与任何 HINT 一样，这些指令可以被自由忽略。因此，尽管它们是根据基于缓存的内存层次结构来描述的，它们并不强制要求提供缓存。_

_某些实现可能对某些内存访问尊重这些 HINT 而对其他访问不尊重：例如，通过在 L1 中获取独占状态缓存行来实现 LR/SC 的实现可能忽略 LR 和 SC 上的 NTL 指令，但可能尊重 AMO 及常规加载和存储上的 NTL 指令。_

表 8 列出了若干软件用例以及 _可移植_ 软件（即未针对任何特定实现的内存层次结构调优的软件）在每种情况下应使用的推荐 NTL 变体。

_表 8. 可移植软件在各种场景下采用的推荐 NTL 变体。_

|Scenario|Recommended NTL variant|
|---|---|
|Access to a working set between and in size|NTL.P1|
|Access to a working set between and in size|NTL.PALL|
|Access to a working set greater than in size|NTL.S1|
|Access with no exploitable temporal locality (e.g., streaming)|NTL.ALL|

|Scenario|Recommended NTL variant|
|---|---|
|Access to a contended synchronization variable|NTL.PALL|

_表 8 中列出的工作集大小并不旨在约束实现者的缓存大小决策。各实现的缓存大小显然会有所不同，因此软件编写者只应将这些工作集大小视为粗略指南。_

表 9 列出了若干示例内存层次结构，并推荐了每个 NTL 变体如何映射到每个缓存级别。该表还推荐了实现调优软件应使用哪个 NTL 变体来避免在特定缓存级别中分配。例如，对于具有私有 L1 和共享 L2 的系统，推荐 NTL.P1 和 NTL.PALL 指示 L1 无法利用时间局部性，而 NTL.S1 和 NTL.ALL 指示 L2 无法利用时间局部性。此外，针对此类系统调优的软件应使用 NTL.P1 来指示 L1 缺乏可利用的时间局部性，或使用 NTL.ALL 来指示 L2 缺乏可利用的时间局部性。

如果提供了 C 或 Zca 扩展，还提供这些 HINT 的压缩变体：C.NTL.P1 编码为 C.ADD _x0, x2_；C.NTL.PALL 编码为 C.ADD _x0, x3_；C.NTL.S1 编码为 C.ADD _x0, x4_；C.NTL.ALL 编码为 C.ADD _x0, x5_。

NTL 指令影响除 Zicbom 扩展中的缓存管理指令之外的所有内存访问指令。

**==> picture [25 x 24] intentionally omitted <==**

**----- Start of picture text -----**<br>
<br>**----- End of picture text -----**<br>

_截至本文撰写时，此规则没有其他例外，因此 NTL 指令影响基础 ISA 和 A、F、D、Q、C 及 V 标准扩展中定义的所有内存访问指令，以及卷 II 中 hypervisor 扩展内定义的指令。_

_NTL 指令可以影响除 Zicbom 扩展中的那些操作之外的缓存管理操作。例如，NTL.PALL 后跟 CBO.ZERO 可能指示缓存行应在 L3 中分配并清零，但不在 L1 或 L2 中分配。_

_表 9. NTL 变体到各种内存层次结构的映射。_

|Memory hierarchy|Recommended mapping of NTL<br>variant to actual cache level|Recommended mapping of NTL<br>variant to actual cache level|Recommended mapping of NTL<br>variant to actual cache level|Recommended mapping of NTL<br>variant to actual cache level|Recommended NTL variant for<br>explicit cache management|Recommended NTL variant for<br>explicit cache management|Recommended NTL variant for<br>explicit cache management|Recommended NTL variant for<br>explicit cache management|
|---|---|---|---|---|---|---|---|
||P1|PALL|S1|ALL|L1|L2|L3|L4/L5|
|Common Scenarios|||||||||
|No caches|---||||none||||
|Private L1 only|L1|L1|L1|L1|ALL|---|---|---|
|Private L1; shared L2|L1|L1|L2|L2|P1|ALL|---|---|
|Private L1; shared L2/L3|L1|L1|L2|L3|P1|S1|ALL|---|
|Private L1/L2|L1|L2|L2|L2|P1|ALL|---|---|
|Private L1/L2; shared L3|L1|L2|L3|L3|P1|PALL|ALL|---|
|Private L1/L2; shared L3/L4|L1|L2|L3|L4|P1|PALL|S1|ALL|
|Uncommon Scenarios|||||||||
|Private L1/L2/L3; shared L4|L1|L3|L4|L4|P1|P1|PALL|ALL|
|Private L1; shared L2/L3/L4|L1|L1|L2|L4|P1|S1|ALL|ALL|
|Private L1/L2; shared L3/L4/L5|L1|L2|L3|L5|P1|PALL|S1|ALL|
|Private L1/L2/L3; shared L4/L5|L1|L3|L4|L5|P1|P1|PALL|ALL|

当 NTL 指令应用于 Zicbop 扩展中的预取提示时，它指示应将缓存行预取到比 NTL 指定的级别 _更外层_ 的缓存中。

_例如，在具有私有 L1 和共享 L2 的系统中，NTL.P1 后跟 PREFETCH.R 可能以读意图预取到 L2 中。_

_要预取到最内层缓存，不要在预取指令前加 NTL 指令前缀。_

_在某些系统中，NTL.ALL 后跟一条预取指令可能预取到内存控制器内部的缓存或预取缓冲区中。_

不鼓励软件在 NTL 指令后跟随不显式访问内存的指令。不遵守此建议可能会降低性能，但除此之外没有架构可见的影响。

如果目标指令发生陷入，不鼓励实现将 NTL 应用于陷入处理程序的第一条指令。相反，建议实现在这种情况下忽略该 HINT。

_如果在执行 NTL 指令与其目标指令之间发生中断，执行通常会从目标指令恢复。NTL 指令未被重新执行并不会改变程序的语义。_

_某些实现可能更倾向于在看到目标指令之前不处理 NTL 指令（例如，以便 NTL 可以与其修改的内存访问融合）。此类实现可能优先在 NTL 之前接受中断，而不是在 NTL 和内存访问之间。_

_由于 NTL 指令编码为 ADD，它们可以在 LR/SC 循环中使用而不会作废前向进度保证。但是，由于在 LR/SC 循环中使用其他加载和存储确实会作废前向进度保证，在此类循环中使用 NTL 的唯一理由就是修改 LR 或 SC。_
