# 第6章 "Zicsr" 控制与状态寄存器（CSR）指令扩展，版本 2.0

RISC-V 定义了每个硬件线程关联的、独立的 4096 个控制与状态寄存器地址空间。本章定义了操作这些 CSR 的完整 CSR 指令集。

_虽然 CSR 主要由特权架构使用，但在非特权代码中也有若干用途，包括用于计数器和定时器，以及用于浮点状态。_

_计数器和定时器不再被视为标准基础 ISA 的强制组成部分，因此访问它们所需的 CSR 指令已从第 2 章移出，放入此独立章节。_

## 6.1. CSR 指令

所有 CSR 指令原子地读取-修改-写入单个 CSR，其 CSR 标识符编码在指令位 31-20 的 12 位 _csr_ 字段中。立即数形式使用编码在 _rs1_ 字段中的 5 位零扩展立即数。

|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>31|0<br>6<br>7<br>11<br>12<br>14<br>15<br>19<br>20<br>31|
|---|---|---|---|---|
|csr|rs1|funct3|rd|opcode|
|7<br>SYSTEM<br>SYSTEM<br>SYSTEM<br>SYSTEM<br>SYSTEM<br>SYSTEM<br>5<br>dest<br>dest<br>dest<br>dest<br>dest<br>dest<br>3<br>CSRRW<br>CSRRS<br>CSRRC<br>CSRRWI<br>CSRRSI<br>CSRRCI<br>5<br>source<br>source<br>source<br>uimm[4:0]<br>uimm[4:0]<br>uimm[4:0]<br>12<br>source/dest<br>source/dest<br>source/dest<br>source/dest<br>source/dest<br>source/dest|||||

CSRRW（原子读/写 CSR）指令原子地交换 CSR 和整数寄存器中的值。CSRRW 读取 CSR 的旧值，将其零扩展至 XLEN 位，然后写入整数寄存器 _rd_ 中。_rs1_ 中的初始值被写入 CSR。如果 _rd_ = `x0`，则该指令不应读取 CSR，也不应引起 CSR 读取可能产生的任何副作用。

CSRRS（原子读取并置位 CSR 中的位）指令读取 CSR 的值，将其零扩展至 XLEN 位，并写入整数寄存器 _rd_ 中。整数寄存器 _rs1_ 中的初始值被视为位掩码，指定 CSR 中要置位的位位置。_rs1_ 中为高的任何位将导致 CSR 中相应的位被置位（如果该 CSR 位可写）。

CSRRC（原子读取并清除 CSR 中的位）指令读取 CSR 的值，将其零扩展至 XLEN 位，并写入整数寄存器 _rd_ 中。整数寄存器 _rs1_ 中的初始值被视为位掩码，指定 CSR 中要清除的位位置。_rs1_ 中为高的任何位将导致 CSR 中相应的位被清除（如果该 CSR 位可写）。

_由于 CSRRS 和 CSRRC 执行读取-修改-写入操作，因此即使 _rs1_ 中对应的位未被置位，读取值与底层值不同的任何位也可能被这些指令修改。例如，pmpaddrn[G-1] 的底层值可能为 1 但读取为 0。执行 CSRRC 或 CSRRS 来修改不同的位将导致从 pmpaddrn[G-1] 读取 0，然后回写，将底层值更新为 0。_

对于 CSRRS 和 CSRRC，如果 _rs1_ = `x0`，则该指令根本不会写入 CSR，因此不应引起 CSR 写入可能产生的任何副作用，也不会在访问只读 CSR 时引发非法指令异常。CSRRS 和 CSRRC 始终读取所寻址的 CSR 并引起任何读取副作用，无论 _rs1_ 和 _rd_ 字段为何值。请注意，如果 _rs1_ 指定了 `x0` 以外的寄存器，且该寄存器保存零值，则该指令不会触发任何伴随的逐字段副作用，但会触发写入整个 CSR 所产生的任何副作用。

CSRRW 在 _rs1_ = `x0` 时将尝试向目标 CSR 写入零。

CSRRWI、CSRRSI 和 CSRRCI 变体分别类似于 CSRRW、CSRRS 和 CSRRC，不同之处在于它们使用由编码在 _rs1_ 字段中的 5 位无符号立即数（uimm[4:0]）零扩展得到的 XLEN 位值来更新 CSR，而非使用整数寄存器中的值。对于 CSRRSI 和 CSRRCI，如果 uimm[4:0] 字段为零，则这些指令不会写入 CSR，且不应引起 CSR 写入可能产生的任何副作用，也不会在访问只读 CSR 时引发非法指令异常。对于 CSRRWI，如果 _rd_ = `x0`，则该指令不应读取 CSR，也不应引起 CSR 读取可能产生的任何副作用。CSRRSI 和 CSRRCI 始终读取 CSR 并引起任何读取副作用，无论 _rd_ 和 _rs1_ 字段为何值。

_表 7. 确定 CSR 指令是否读取或写入指定 CSR 的条件。_

|Register operand|Register operand|Register operand|Register operand|Register operand|
|---|---|---|---|---|
|Instruction|_rd_is`x0`|_rs1_is`x0`|Reads CSR|Writes CSR|
|CSRRW|Yes|-|No|Yes|
|CSRRW|No|-|Yes|Yes|
|CSRRS/CSRRC|-|Yes|Yes|No|
|CSRRS/CSRRC|-|No|Yes|Yes|
|Immediate operand|||||
|Instruction|_rd_is`x0`|_uimm_=0|Reads CSR|Writes CSR|
|CSRRWI|Yes|-|No|Yes|
|CSRRWI|No|-|Yes|Yes|
|CSRRSI/CSRRCI|-|Yes|Yes|No|
|CSRRSI/CSRRCI|-|No|Yes|Yes|

表 7 总结了 CSR 指令在是否读取和/或写入 CSR 方面的行为。

除了因读取或写入 CSR 而产生的副作用之外，CSR 中的个别字段在写入时也可能有副作用。CSRRW[I] 指令会触发被写入 CSR 中所有此类字段的副作用。CSRRS[I] 和 CSRRC[I] 指令仅触发 _rs1_ 或 _uimm_ 参数中至少有一个置位位与该字段对应的那些字段的副作用。

_截至本文撰写时，尚无标准 CSR 在字段写入时有副作用。因此，标准 CSR 访问是否产生副作用可以仅通过操作码来确定。_

_不推荐定义在字段写入时有副作用的 CSR。_

对于因 CSR 具有特定值而发生的任何事件或后果，如果对 CSR 的写入使其具有该值，则由此产生的事件或后果被称为该写入的 _间接效应_。RISC-V ISA 不将 CSR 写入的间接效应视为该写入的副作用。

_一个 CSR 访问副作用的例子：假设读取特定 CSR 导致灯泡亮起，而向同一 CSR 写入奇数值导致灯熄灭。假设写入偶数值无效。在这种情况下，读取和写入都有控制灯是否亮起的副作用，因为此条件并非仅由 CSR 值决定。（请注意，在向 CSR 写入奇数值关闭灯后，然后读取以打开灯，再次写入相同的奇数值会导致灯再次熄灭。因此，在最后一次写入中，关灯并非由 CSR 值的变化引起。）_

_另一方面，如果灯泡被设置为每当特定 CSR 的值为奇数时就亮起，那么开关灯就不被视为写入 CSR 的副作用，而仅仅是此类写入的间接效应。_

_更具体地，卷 II 中定义的 RISC-V 特权架构规定，CSR 值的某些组合会导致陷入发生。当对 CSR 的显式写入创造了触发陷入的条件时，该陷入不被视为写入的副作用，而仅仅是间接效应。_

_标准 CSR 在读取时没有任何副作用。标准 CSR 在写入时可能有副作用。自定义扩展可能添加访问时在读取或写入上有副作用的 CSR。_

某些 CSR，如已退休指令计数器 `instret`，可能作为指令执行的副作用而被修改。在这些情况下，如果一条 CSR 访问指令读取一个 CSR，它读取的是该指令执行之前的值。如果一条 CSR 访问指令写入这样的 CSR，则显式写入会替代副作用产生的更新。特别是，一条指令写入 `instret` 的值将成为下一条指令读取的值。

汇编器伪指令读取 CSR（CSRR _rd, csr_）编码为 CSRRS _rd, csr, x0_。汇编器伪指令写入 CSR（CSRW _csr, rs1_）编码为 CSRRW _x0, csr, rs1_，而 CSRWI _csr, uimm_ 编码为 CSRRWI _x0, csr, uimm_。

还定义了进一步的汇编器伪指令，用于在不需要旧值时置位和清除 CSR 中的位：CSRS/CSRC _csr, rs1_；CSRSI/CSRCI _csr, uimm_。

## 6.1.1. CSR 访问排序

每个 RISC-V 硬件线程通常观察其自身的 CSR 访问（包括其隐式 CSR 访问）为按程序顺序执行。特别地，除非另有规定，否则 CSR 访问在程序顺序中位于其行为修改 CSR 状态或受 CSR 状态修改的任何先前指令执行之后执行，并在程序顺序中位于其行为修改 CSR 状态或受 CSR 状态修改的任何后续指令执行之前执行。此外，显式 CSR 读取返回指令执行前的 CSR 状态，而显式 CSR 写入则抑制并覆盖同一指令对同一 CSR 的任何隐式写入或修改。

同样，显式 CSR 访问的任何副作用通常被观察为按程序顺序同步发生。除非另有规定，否则任何此类副作用的全部后果对于紧随的下一条指令是可观察的，并且没有后果可能被先前的指令乱序观察到。（请注意前面所述的 CSR 写入的副作用与间接效应之间的区别。）

对于 RVWMO 内存一致性模型（第 18 章），CSR 访问默认是弱排序的，因此其他硬件线程或设备可能以不同于程序顺序的顺序观察到 CSR 访问。此外，CSR 访问与显式内存访问之间不排序，除非 CSR 访问修改了执行显式内存访问的指令的执行行为，或者除非 CSR 访问和显式内存访问通过内存模型定义的句法依赖或本手册卷 II 中内存排序 PMA 部分定义的排序要求进行排序。要在所有其他情况下强制排序，软件应在相关访问之间执行一条 FENCE 指令。对于 FENCE 指令的目的，CSR 读取访问被分类为设备输入（I），CSR 写入访问被分类为设备输出（O）。

_非正式地说，CSR 地址空间表现为一个弱排序的内存映射 I/O 区域，如本手册卷 II 中内存排序 PMA 部分所定义。因此，CSR 访问相对于所有其他访问的顺序受到与约束内存映射 I/O 访问到此类区域的顺序相同的机制的约束。_

_这些 CSR 排序约束的施加是为了支持主存和内存映射 I/O 访问与设备或其他硬件线程可见或受其影响的 CSR 访问之间的排序。例子包括_ `time`、`cycle` 和 `mcycle` CSR，以及反映待处理中断的 CSR，如 `mip` 和 `sip`。请注意，对此类 CSR 的隐式读取（例如，因 `mip` 变化而接受中断）也被排序为设备输入。_

_大多数 CSR（包括例如 `fcsr`）对其他硬件线程不可见；它们相对于 FENCE 指令的访问可以在全局内存顺序中自由重排序而不违反本规范。_

硬件平台可以定义对某些 CSR 的访问是强排序的，如本手册卷 II 中内存排序 PMA 部分所定义。对强排序 CSR 的访问相对于弱排序 CSR 的访问以及内存映射 I/O 区域的访问具有更强的排序约束。

**==> picture [25 x 24] intentionally omitted <==**

**----- Start of picture text -----**<br>
<br>**----- End of picture text -----**<br>

_关于 CSR 访问在全局内存顺序中重排序的规则或许应移至关于 RVWMO 内存一致性模型的第 18 章。_
