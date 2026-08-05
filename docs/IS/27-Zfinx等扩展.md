## 第27章. "Zfinx"、"Zdinx"、"Zhinx"、"Zhinxmin" 扩展：整数寄存器中的浮点，版本 1.0

本章定义了 "Zfinx" 扩展（读作 "z-f-in-x"），提供与标准浮点 F 扩展中类似的单精度浮点指令，但这些指令在 `x` 寄存器上操作而非 `f` 寄存器。本章还定义了 "Zdinx"、"Zhinx" 和 "Zhinxmin" 扩展，为其他浮点精度提供类似的指令。

**评论：**_F 扩展使用单独的_ `f` _寄存器进行浮点计算，以减少寄存器压力并简化宽超标量的寄存器文件端口供应。然而，额外的架构状态增加了最小实现成本。通过消除_ `f` _寄存器，Zfinx 扩展显著降低了支持浮点指令集的简单 RISC-V 实现的成本。Zfinx 还减少了上下文切换成本。_

**评论：**_一般来说，假定存在 F 扩展的软件与假定存在 Zfinx 扩展的软件不兼容，反之亦然。_

Zfinx 扩展添加了 F 扩展添加的所有指令，_除了_ 传输指令 FLW、FSW、FMV.W.X、FMV.X.W、C.FLW[SP] 和 C.FSW[SP]。

**评论：**_Zfinx 软件使用整数加载和存储将浮点值从内存传输到寄存器。寄存器之间的传输使用整数算术或浮点符号注入指令。_

这些 F 扩展指令的 Zfinx 变体具有相同的语义，不同之处在于每当此类指令访问 `f` 寄存器时，它改为访问相同编号的 `x` 寄存器。

Zfinx 扩展依赖于 "Zicsr" 扩展以访问控制与状态寄存器。

## 27.1. 较窄值的处理

宽度 _w_ < XLEN 位的浮点操作数占据 `x` 寄存器的位 _w_-1:0。_w_ 位操作数上的浮点操作忽略操作数位 XLEN-1:_w_。

产生 _w_ < XLEN 位结果的浮点操作用位 _w_-1（符号位）的副本填充位 XLEN-1:_w_。

**评论：**_在_ `f` _寄存器中使用的 NaN-boxing 方案旨在高效支持重编码浮点格式。然而，重编码对 Zfinx 不太实用，因为相同的寄存器同时保存浮点和整数操作数。因此，对 NaN-boxing 的需求减少了。_

**评论：**_在 RV64_ `x` _寄存器中符号扩展 32 位浮点数与现有的 RV64 调用约定兼容，后者在将 32 位浮点值传递到_ `x` _寄存器时保持位 63-32 未定义。为了保持架构更规则，我们将此模式扩展到 RV32 和 RV64 中的 16 位浮点数。_

## 27.2. Zdinx

Zdinx 扩展提供类似的双精度浮点指令。Zdinx 扩展依赖于 Zfinx 扩展。

Zdinx 扩展添加了 D 扩展添加的所有指令，_除了_ 传输指令

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

27.3. Processing of Wider Values | Page 150

FLD、FSD、FMV.D.X、FMV.X.D、C.FLD[SP] 和 C.FSD[SP]。

这些 D 扩展指令的 Zdinx 变体具有相同的语义，不同之处在于每当此类指令访问 `f` 寄存器时，它改为访问相同编号的 `x` 寄存器。

## 27.3. 较宽值的处理

RV32Zdinx 中的双精度操作数保存在对齐的 `x` 寄存器对中，即寄存器编号必须是偶数。使用未对齐的（奇数编号）寄存器作为双宽浮点操作数属于 _reserved_。

无论字节序如何，编号较小的寄存器保存低位，编号较大的寄存器保存高位：例如，RV32Zdinx 中双精度操作数的位 31:0 可以保存在寄存器 `x14` 中，该操作数的位 63:32 保存在 `x15` 中。

当双宽浮点结果写入 `x0` 时，整个写入不产生效果：例如，对于 RV32Zdinx，将双精度结果写入 `x0` 不会导致 `x1` 被写入。

当 `x0` 用作双宽浮点操作数时，整个操作数为零——即不访问 `x1`。

**评论：**_加载对和存储对指令包含在单独的扩展中（参见 RV32 加载/存储对扩展部分）。如果不可用，在 RV32Zdinx 中从内存传输双精度操作数需要两次加载或存储。然而，寄存器移动只需一条 FSGNJ.D 指令。_

## 27.4. Zhinx

Zhinx 扩展提供类似的半精度浮点指令。Zhinx 扩展依赖于 Zfinx 扩展。

Zhinx 扩展添加了 Zfh 扩展添加的所有指令，_除了_ 传输指令 FLH、FSH、FMV.H.X 和 FMV.X.H。

这些 Zfh 扩展指令的 Zhinx 变体具有相同的语义，不同之处在于每当此类指令访问 `f` 寄存器时，它改为访问相同编号的 `x` 寄存器。

## 27.5. Zhinxmin

Zhinxmin 扩展为在 `x` 寄存器上操作的 16 位半精度浮点指令提供最小支持。Zhinxmin 扩展依赖于 Zfinx 扩展。

Zhinxmin 扩展包括 Zhinx 扩展中的以下指令：FCVT.S.H 和 FCVT.H.S。如果存在 Zdinx 扩展，则还包括 FCVT.D.H 和 FCVT.H.D 指令。

**评论：**_将来，可以类似 RV32Zdinx 定义 RV64Zqinx 四精度扩展。也可以定义 RV32Zqinx 扩展，但需要四寄存器组。_

## 27.6. 特权架构含义

在 Volume II 中定义的标准特权架构中，如果实现了 Zfinx 扩展，`mstatus` 字段 FS 硬连线为 0，

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

27.6. Privileged Architecture Implications | Page 151

并且 FS 不再影响浮点指令或 `fcsr` 访问的陷阱行为。

当实现了 Zfinx 扩展时，`misa` 位 F、D 和 Q 硬连线为 0。

**==> picture [25 x 24] intentionally omitted <==**

**----- Start of picture text -----**<br>
<br>**----- End of picture text -----**<br>

**评论：**_将来可能使用一种发现机制来探测 Zfinx、Zhinx 和 Zdinx 扩展的存在。_

The RISC-V Instruction Set Manual, Volume I | © RISC-V International
