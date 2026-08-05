## 第18章 RVWMO内存一致性模型，版本2.0

本章定义了RISC-V内存一致性模型。内存一致性模型是一组规则，规定了内存加载操作可以返回的值。RISC-V使用一种称为"RVWMO"（RISC-V弱内存排序）的内存模型，该模型旨在为架构师提供灵活性，以构建高性能可扩展设计，同时支持易于处理的编程模型。

在RVWMO下，单个硬件线程（hart）上运行的代码从同一hart中其他内存指令的角度来看似乎是按顺序执行的，但来自另一个hart的内存指令可能观察到来自第一个hart的内存指令以不同顺序执行。因此，多线程代码可能需要显式同步来保证不同hart之间内存指令的排序。基础RISC-V ISA为此目的提供了FENCE指令（见第2.7节），而原子扩展"A"还定义了加载保留/条件存储和原子读-修改-写指令。

全存储排序标准ISA扩展"Ztso"（第19章）用特定于该扩展的附加规则增强了RVWMO。

本规范的附录提供了内存一致性模型的公理化形式化和操作形式化，以及附加的解释性材料。

_本章定义了常规主存操作的内存模型。内存模型与I/O内存、指令获取、FENCE.I、页表遍历和SFENCE.VMA之间的交互尚未（或尚未完全）形式化。上述部分或全部可能在未来的规范修订版中形式化。未来的ISA扩展（如V向量扩展和J JIT扩展）也需要纳入未来的修订版中。_

_支持不同宽度的重叠内存访问的内存一致性模型仍然是学术研究的活跃领域，尚未完全理解。不同大小的内存访问在RVWMO下如何交互的具体细节已尽我们当前能力指定，但如果发现新问题，可能会进行修订。_

## 18.1. RVWMO内存模型的定义

RVWMO内存模型通过_全局内存顺序_（global memory order）来定义，这是所有hart产生的内存操作的全排序。通常，一个多线程程序有许多不同的可能执行，每个执行都有其对应的全局内存顺序。

全局内存顺序定义在由内存指令产生的原始加载和存储操作之上，并受本章其余部分定义的约束。满足所有内存模型约束的任何执行都是合法执行（就内存模型而言）。

## 18.1.1. 内存模型原语

内存操作上的_程序顺序_（program order）反映了产生每个加载和存储的指令在该hart的动态指令流中逻辑排列的顺序；即，一个简单的顺序处理器执行该hart指令的顺序。

访问内存的指令产生_内存操作_（memory operation）。内存操作可以是_加载操作_（load operation）、_存储操作_（store operation）或两者同时。所有内存操作都是单拷贝原子的：它们永远不会被观察到处于部分完成状态。

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.1. Definition of the RVWMO Memory Model | Page 86

每个访问XLEN或更少位数的对齐内存指令恰好产生一个内存操作，除非另有规定。对齐的AMO产生一个同时是加载操作和存储操作的单一内存操作。

_在RV32GC和RV64GC的指令中，以下是对齐内存指令恰好产生一个内存操作规则的例外：_

- _不成功的SC指令不产生任何内存操作。_

## 

- _访问超过XLEN位的浮点加载和存储指令（例如，RV32中的FLD/FSD）可能各自产生多个内存操作。_

_诸如V（向量）和即将推出的P（SIMD）等ISA扩展可能产生多个内存操作。然而，这些扩展的内存模型尚未形式化。_

未对齐的加载或存储指令可以被分解为一组任意粒度的组件内存操作。超过XLEN位的浮点加载或存储也可以被分解为一组任意粒度的组件内存操作。由此类指令产生的内存操作在程序顺序中彼此之间不排序，但它们相对于程序顺序中前后指令产生的内存操作正常排序。原子扩展"A"根本不要求执行环境支持未对齐的原子指令。但是，如果通过未对齐原子性粒度PMA支持未对齐原子操作，则原子性粒度内的AMO不被分解，基础ISA中定义的加载和存储也不被分解，F、D和Q扩展中定义的不超过XLEN位的加载和存储也不被分解。

_将未对齐的内存操作分解到字节粒度有助于在不原生支持未对齐访问的实现上进行仿真。例如，此类实现可能简单地逐个迭代未对齐访问的字节。_

如果LR指令在程序顺序上先于SC指令，并且它们之间没有其他LR或SC指令，则称LR指令和SC指令是_配对的_（paired）；相应的内存操作也被称为配对的（除非SC失败，此时不产生存储操作）。决定SC是否必须成功、可能成功或必须失败的完整条件列表在第13.2节中定义。

加载和存储操作还可能携带来自以下集合的一个或多个排序注解："acquire-RCpc"、"acquire-RCsc"、"release-RCpc"和"release-RCsc"。设置了_aq_的AMO或LR指令具有"acquire-RCsc"注解。设置了_rl_的AMO或SC指令具有"release-RCsc"注解。同时设置了_aq_和_rl_的AMO、LR或SC指令同时具有"acquire-RCsc"和"release-RCsc"注解。

为方便起见，我们使用术语"获取注解"（acquire annotation）指代acquire-RCpc注解或acquire-RCsc注解。类似地，"释放注解"（release annotation）指代release-RCpc注解或release-RCsc注解。"RCpc注解"指代acquire-RCpc注解或release-RCpc注解。_RCsc注解_指代acquire-RCsc注解或release-RCsc注解。

**评论：**_在内存模型文献中，术语"RCpc"代表具有处理器一致性同步操作的释放一致性（release consistency with processor-consistent synchronization operations），术语"RCsc"代表具有顺序一致性同步操作的释放一致性（release consistency with sequentially consistent synchronization operations）。_

**评论：**_虽然文献中对获取和释放注解有许多不同的定义，但在RVWMO上下文中，这些术语由保留程序顺序规则5-7简洁且完整地定义。_

**评论：**_"RCpc"注解目前仅在标准扩展"Ztso"（第19章）隐式分配给每个内存访问时使用。此外，虽然ISA目前不包含原生加载-获取或存储-释放指令，也不包含它们的RCpc变体，但RVWMO模型本身被设计为向前兼容，允许将来在扩展中将上述任何或全部内容添加到ISA中。_

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.1. Definition of the RVWMO Memory Model | Page 87

## 18.1.2. 语法依赖

RVWMO内存模型的定义部分依赖于语法依赖（syntactic dependency）的概念，定义如下。

在定义依赖关系的上下文中，_寄存器_（register）指整个通用寄存器、CSR的某一部分或整个CSR。通过CSR跟踪依赖关系的粒度对每个CSR是特定的，在第18.2节中定义。

语法依赖根据指令的_源寄存器_（source register）、指令的_目标寄存器_（destination register）以及指令将_依赖关系传递_（carry a dependency）从其源寄存器到其目标寄存器的方式来定义。本节提供所有这些术语的一般定义；然而，第18.3节提供了每条指令具体情况的完整列表。

一般来说，如果满足以下任一条件，则寄存器_r_（非`x0`）是指令_i_的_源寄存器_：

- 在_i_的操作码中，_rs1_、_rs2_或_rs3_被设置为_r_

- _i_是CSR指令，在_i_的操作码中，_csr_被设置为_r_，除非_i_是CSRRW或CSRRWI且_rd_被设置为`x0`

- _r_是CSR并且是_i_的隐式源寄存器，如第18.3节定义

- _r_是与_i_的另一个源寄存器别名的CSR

内存指令还进一步指定哪些源寄存器是_地址源寄存器_（address source register）以及哪些是_数据源寄存器_（data source register）。

一般来说，如果满足以下任一条件，则寄存器_r_（非`x0`）是指令_i_的_目标寄存器_：

- 在_i_的操作码中，_rd_被设置为_r_

- _i_是CSR指令，在_i_的操作码中，_csr_被设置为_r_，除非_i_是CSRRS或CSRRC且_rs1_被设置为`x0`，或_i_是CSRRSI或CSRRCI且uimm[4:0]被设置为零。

- _r_是CSR并且是_i_的隐式目标寄存器，如第18.3节定义

- _r_是与_i_的另一个目标寄存器别名的CSR

大多数非内存指令将依赖关系从每个源寄存器_传递_到每个目标寄存器。然而，此规则有例外；见第18.3节。

如果满足以下任一条件，则指令_j_通过指令_i_的目标寄存器_s_和指令_j_的源寄存器_r_对指令_i_具有_语法依赖_：

- _s_与_r_相同，并且在程序顺序上位于_i_和_j_之间没有指令将_r_作为目标寄存器

- 在程序顺序上位于_i_和_j_之间存在一条指令_m_，使得以下所有条件成立：

   1. _j_通过目标寄存器_q_和源寄存器_r_对_m_具有语法依赖

   2. _m_通过目标寄存器_s_和源寄存器_p_对_i_具有语法依赖

   3. _m_将依赖关系从_p_传递到_q_

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.1. Definition of the RVWMO Memory Model | Page 88

最后，在以下定义中，设_a_和_b_为两个内存操作，设_i_和_j_分别为产生_a_和_b_的指令。

如果_r_是_j_的地址源寄存器，且_j_通过源寄存器_r_对_i_具有语法依赖，则_b_对_a_具有_语法地址依赖_（syntactic address dependency）。

如果_b_是存储操作，_r_是_j_的数据源寄存器，且_j_通过源寄存器_r_对_i_具有语法依赖，则_b_对_a_具有_语法数据依赖_（syntactic data dependency）。

如果在程序顺序上位于_i_和_j_之间存在一条指令_m_，使得_m_是分支或间接跳转指令，且_m_对_i_具有语法依赖，则_b_对_a_具有_语法控制依赖_（syntactic control dependency）。

## 

**评论：**_一般来说，非AMO加载指令没有数据源寄存器，无条件非AMO存储指令没有目标寄存器。但是，成功的SC指令被认为将rd中指定的寄存器作为目标寄存器，因此指令可能对在程序顺序上先于它的成功SC指令具有语法依赖。_

## 18.1.3. 保留程序顺序

程序任何给定执行的全局内存顺序尊重每个hart的某些（但不是全部）程序顺序。全局内存顺序必须尊重的程序顺序子集称为_保留程序顺序_（preserved program order）。

保留程序顺序的完整定义如下（注意AMO同时是加载和存储）：如果_a_在程序顺序上先于_b_，_a_和_b_都访问常规主存（而非I/O区域），并且满足以下任一条件，则内存操作_a_在保留程序顺序中先于内存操作_b_（因此在全局内存顺序中也先于）：

- 重叠地址排序：

   1. _b_是存储操作，且_a_和_b_访问重叠的内存地址

   2. _a_和_b_是加载操作，_x_是_a_和_b_都读取的一个字节，在_a_和_b_之间程序顺序上没有对_x_的存储，且_a_和_b_返回由不同内存操作写入的_x_的值

   3. _a_由AMO或SC指令产生，_b_是加载操作，且_b_返回由_a_写入的值

- 显式同步：

   1. 存在一条FENCE指令，将_a_排序在_b_之前

   2. _a_具有获取注解

   3. _b_具有释放注解

   4. _a_和_b_都具有RCsc注解

   5. _a_与_b_配对

- 语法依赖：

   1. _b_对_a_具有语法地址依赖

   2. _b_对_a_具有语法数据依赖

   3. _b_是存储操作，且_b_对_a_具有语法控制依赖

- 流水线依赖：

   1. _b_是加载操作，且存在某个存储操作_m_在程序顺序上位于_a_和_b_之间，使得_m_对_a_具有地址或数据依赖，且_b_返回由_m_写入的值

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.2. CSR Dependency Tracking Granularity | Page 89

1. _b_是存储操作，且存在某条指令_m_在程序顺序上位于_a_和_b_之间，使得_m_对_a_具有地址依赖

## 18.1.4. 内存模型公理

RISC-V程序的执行只有在存在符合保留程序顺序并满足_加载值公理_（load value axiom）、_原子性公理_（atomicity axiom）和_进展公理_（progress axiom）的全局内存顺序时，才符合RVWMO内存一致性模型。

## 18.1.4.1. 加载值公理

每个加载_i_的每个字节返回该字节由以下存储中在全局内存顺序中最晚的那个写入的值：

1. 写入该字节且在全局内存顺序中先于_i_的存储

2. 写入该字节且在程序顺序中先于_i_的存储

## 18.1.4.2. 原子性公理

如果_r_和_w_是由hart _h_中对齐的LR和SC指令产生的配对加载和存储操作，_s_是对字节_x_的存储，且_r_返回由_s_写入的值，则_s_必须在全局内存顺序中先于_w_，并且在全局内存顺序中，在_s_之后且_w_之前不能有来自_h_以外的hart的对字节_x_的存储。

**==> picture [25 x 24] intentionally omitted <==**

**----- Start of picture text -----**<br>
<br>**----- End of picture text -----**<br>

**评论：**_原子性公理在理论上支持不同宽度和不对齐地址的LR/SC对，因为实现被允许在此类情况下让SC操作成功。然而，在实践中，我们预计此类模式很少见，不鼓励使用。_

## 18.1.4.3. 进展公理

没有任何内存操作可以在全局内存顺序中被无限序列的其他内存操作所先于。

## 18.2. CSR依赖跟踪粒度

_表12. 通过CSR跟踪语法依赖的粒度_

|名称|作为独立单元跟踪的部分|别名|
|---|---|---|
|_fflags_|位4, 3, 2, 1, 0|_fcsr_|
|_frm_|整个CSR|_fcsr_|
|_fcsr_|位7-5, 4, 3, 2, 1, 0|_fflags_,_frm_|

注意：只读CSR未列出，因为它们不参与语法依赖的定义。

## 18.3. 源寄存器和目标寄存器列表

本节提供每条指令的源寄存器和目标寄存器的具体列表。这些列表用于第18.1.2节中语法依赖的定义。

术语"累积CSR"（accumulating CSR）用于描述既是源寄存器又是目标寄存器的CSR，但

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 90

它仅将依赖关系从自身传递到自身。

除非另有注释，指令将依赖关系从"源寄存器"列中的每个源寄存器传递到"目标寄存器"列中的每个目标寄存器，从"源寄存器"列中的每个源寄存器传递到"累积CSR"列中的每个CSR，以及从"累积CSR"列中的每个CSR传递到自身。

图例：

- A 地址源寄存器

- D 数据源寄存器

- † 该指令不从任何源寄存器向任何目标寄存器传递依赖关系

- ‡ 该指令按指定方式从源寄存器向目标寄存器传递依赖关系

_表13. RV32I基础整数指令集_

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|LUI||_rd_|||
|AUIPC||_rd_|||
|JAL||_rd_|||
|JALR†|_rs1_|_rd_|||
|BEQ|_rs1_,_rs2_||||
|BNE|_rs1_,_rs2_||||
|BLT|_rs1_,_rs2_||||
|BGE|_rs1_,_rs2_||||
|BLTU|_rs1_,_rs2_||||
|BGEU|_rs1_,_rs2_||||
|LB †|_rs1_ A|_rd_|||
|LH †|_rs1_ A|_rd_|||
|LW †|_rs1_ A|_rd_|||
|LBU †|_rs1_ A|_rd_|||
|LHU †|_rs1_ A|_rd_|||
|SB|_rs1_ A,_rs2_ D||||
|SH|_rs1_ A,_rs2_ D||||
|SW|_rs1_ A,_rs2_ D||||
|ADDI|_rs1_|_rd_|||
|SLTI|_rs1_|_rd_|||
|SLTIU|_rs1_|_rd_|||
|XORI|_rs1_|_rd_|||
|ORI|_rs1_|_rd_|||
|ANDI|_rs1_|_rd_|||
|SLLI|_rs1_|_rd_|||
|SRLI|_rs1_|_rd_|||
|SRAI|_rs1_|_rd_|||

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 91

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|ADD|_rs1_,_rs2_|_rd_|||
|SUB|_rs1_,_rs2_|_rd_|||
|SLL|_rs1_,_rs2_|_rd_|||
|SLT|_rs1_,_rs2_|_rd_|||
|SLTU|_rs1_,_rs2_|_rd_|||
|XOR|_rs1_,_rs2_|_rd_|||
|SRL|_rs1_,_rs2_|_rd_|||
|SRA|_rs1_,_rs2_|_rd_|||
|OR|_rs1_,_rs2_|_rd_|||
|AND|_rs1_,_rs2_|_rd_|||
|FENCE|||||
|FENCE.I|||||
|ECALL|||||
|EBREAK|||||
|CSRRW‡|_rs1_,_csr_*|_rd_,_csr_||*除非_rd_=`x0`|
|‡ 将依赖关系从_rs1_传递到_csr_，从_csr_传递到_rd_|||||
|CSRRS‡|_rs1_,_csr_|_rd_,_csr_*||*除非_rs1_=`x0`|
|CSRRC‡|_rs1_,_csr_|_rd_,_csr_*||*除非_rs1_=`x0`|
|‡ 将依赖关系从_csr_和_rs1_传递到_csr_，从_csr_传递到_rd_|||||
|CSRRWI ‡|_csr_ *|_rd_,_csr_||*除非_rd_=_x0_|
|‡ 将依赖关系从_csr_传递到_rd_|||||
|CSRRSI ‡|_csr_|_rd_,_csr_*||*除非 uimm[4:0]=0|
|CSRRCI ‡|_csr_|_rd_,_csr_*||*除非 uimm[4:0]=0|
|‡ 将依赖关系从_csr_传递到_rd_和_csr_|||||

_表14. RV64I基础整数指令集_

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|_LWU_†|_rs1_ A|_rd_|||
|_LD_†|_rs1_ A|_rd_|||
|SD|_rs1_ A,_rs2_ D||||
|SLLI|_rs1_|_rd_|||
|SRLI|_rs1_|_rd_|||
|SRAI|_rs1_|_rd_|||
|ADDIW|_rs1_|_rd_|||
|SLLIW|_rs1_|_rd_|||
|SRLIW|_rs1_|_rd_|||
|SRAIW|_rs1_|_rd_|||
|ADDW|_rs1_,_rs2_|_rd_|||
|SUBW|_rs1_,_rs2_|_rd_|||
|SLLW|_rs1_,_rs2_|_rd_|||

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 92

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|SRLW|_rs1_,_rs2_|_rd_|||
|SRAW|_rs1_,_rs2_|_rd_|||

## _表15. RV32M标准扩展_

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|MUL|_rs1_,_rs2_|_rd_|||
|MULH|_rs1_,_rs2_|_rd_|||
|MULHSU|_rs1_,_rs2_|_rd_|||
|MULHU|_rs1_,_rs2_|_rd_|||
|DIV|_rs1_,_rs2_|_rd_|||
|DIVU|_rs1_,_rs2_|_rd_|||
|REM|_rs1_,_rs2_|_rd_|||
|REMU|_rs1_,_rs2_|_rd_|||

## _表16. RV64M标准扩展_

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|MULW|_rs1_,_rs2_|_rd_|||
|DIVW|_rs1_,_rs2_|_rd_|||
|DIVUW|_rs1_,_rs2_|_rd_|||
|REMW|_rs1_,_rs2_|_rd_|||
|REMUW|_rs1_,_rs2_|_rd_|||

## _表17. RV32A标准扩展_

||源寄存器<br>|目标寄存器|累积CSR||
|---|---|---|---|---|
|LR.W†|_rs1_ A<br>|_rd_|||
|SC.W†|_rs1_ A,_rs2_ D<br>|_rd_ *||*如果成功|
|AMOSWAP.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOADD.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOXOR.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOAND.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOOR.W†|_rs1_ A,_rs2_D<br>|_rd_|||
|AMOMIN.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOMAX.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOMINU.W†|_rs1_ A,_rs2_ D<br>|_rd_|||
|AMOMAXU.W†|_rs1_ A,_rs2_ D<br>|_rd_|||

## _表18. RV64A标准扩展_

||源寄存器<br>|目标寄存器|累积CSR||
|---|---|---|---|---|
|LR.D†|_rs1_ A<br>|_rd_|||
|SC.D†|_rs1_ A,_rs2_ D<br>|_rd_ *||*如果成功|
|AMOSWAP.D†|_rs1_ A,_rs2_ D<br>|_rd_|||

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 93

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|AMOADD.D†|_rs1_ A,_rs2_ D|_rd_|||
|AMOXOR.D†|_rs1_ A,_rs2_ D|_rd_|||
|AMOAND.D†|_rs1_ A,_rs2_D|_rd_|||
|AMOOR.D†|_rs1_ A,_rs2_D|_rd_|||
|AMOMIN.D†|_rs1_ A,_rs2_D|_rd_|||
|AMOMAX.D†|_rs1_ A,_rs2_D|_rd_|||
|AMOMINU.D†|_rs1_ A,_rs2_D|_rd_|||
|AMOMAXU.D†|_rs1_ A,_rs2_D|_rd_|||

## _表19. RV32F标准扩展_

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|FLW†|_rs1_ A|_rd_|||
|FSW|_rs1_ A,_rs2_D||||
|FMADD.S|_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FMSUB.S|_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FNMSUB.S|_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FNMADD.S|_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FADD.S|_rs1_,_rs2_, frm*|_rd_|NV, OF, NX|*如果 rm=111|
|FSUB.S|_rs1_,_rs2_, frm*|_rd_|NV, OF, NX|*如果 rm=111|
|FMUL.S|_rs1_,_rs2_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FDIV.S|_rs1_,_rs2_, frm*|_rd_|NV, DZ, OF, UF, NX|*如果 rm=111|
|FSQRT.S|_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FSGNJ.S|_rs1_,_rs2_|_rd_|||
|FSGNJN.S|_rs1_,_rs2_|_rd_|||
|FSGNJX.S|_rs1_,_rs2_|_rd_|||
|FMIN.S|_rs1_,_rs2_|_rd_|NV||
|FMAX.S|_rs1_,_rs2_|_rd_|NV||
|FCVT.W.S|_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FCVT.WU.S|_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FMV.X.W|_rs1_|_rd_|||
|FEQ.S|_rs1_,_rs2_|_rd_|NV||
|FLT.S|_rs1_,_rs2_|_rd_|NV||
|FLE.S|_rs1_,_rs2_|_rd_|NV||
|FCLASS.S|_rs1_|_rd_|||
|FCVT.S.W|_rs1_, frm*|_rd_|NX|*如果 rm=111|
|FCVT.S.WU|_rs1_, frm*|_rd_|NX|*如果 rm=111|
|FMV.W.X|_rs1_|_rd_|||

_表20. RV64F标准扩展_

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 94

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|FCVT.L.S|_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FCVT.LU.S|_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FCVT.S.L|_rs1_, frm*|_rd_|NX|*如果 rm=111|
|FCVT.S.LU|_rs1_, frm*|_rd_|NX|*如果 rm=111|

## _表21. RV32D标准扩展_

|||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|---|
|FLD†||_rs1_ A|_rd_|||
|FSD||_rs1_ A,_rs2_D||||
|FMADD.D||_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FMSUB.D||_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FNMSUB.D||_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FNMADD.D||_rs1_,_rs2_,_rs3_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FADD.D||_rs1_,_rs2_, frm*|_rd_|NV, OF, NX|*如果 rm=111|
|FSUB.D||_rs1_,_rs2_, frm*|_rd_|NV, OF, NX|*如果 rm=111|
|FMUL.D||_rs1_,_rs2_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FDIV.D||_rs1_,_rs2_, frm*|_rd_|NV, DZ, OF, UF, NX|*如果 rm=111|
|FSQRT.D||_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FSGNJ.D||_rs1_,_rs2_|_rd_|||
|FSGNJN.D||_rs1_,_rs2_|_rd_|||
|FSGNJX.D||_rs1_,_rs2_|_rd_|||
|FMIN.D||_rs1_,_rs2_|_rd_|NV||
|FMAX.D||_rs1_,_rs2_|_rd_|NV||
|FCVT.S.D||_rs1_, frm*|_rd_|NV, OF, UF, NX|*如果 rm=111|
|FCVT.D.S||_rs1_|_rd_|NV||
|FEQ.D||_rs1_,_rs2_|_rd_|NV||
|FLT.D||_rs1_,_rs2_|_rd_|NV||
|FLE.D||_rs1_,_rs2_|_rd_|NV||
|FCLASS.D||_rs1_|_rd_|||
|FCVT.W.D||_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FCVT.WU.D||_rs1_, frm*|_rd_|NV, NX|*如果 rm=111|
|FCVT.D.W||_rs1_|_rd_|||
|FCVT.D.WU||_rs1_|_rd_|||
|_表22. RV64D标准扩展_||||||
||源寄存器||目标寄存器|累积CSR||
|FCVT.L.D|_rs1_, frm*||_rd_|NV, NX|*如果 rm=111|
|FCVT.LU.D|_rs1_, frm*||_rd_|NV, NX|*如果 rm=111|
|FMV.X.D|_rs1_||_rd_|||
|FCVT.D.L|_rs1_, frm*||_rd_|NX|*如果 rm=111|

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

18.3. Source and Destination Register Listings | Page 95

||源寄存器|目标寄存器|累积CSR||
|---|---|---|---|---|
|FCVT.D.LU|_rs1_, frm*|_rd_|NX|*如果 rm=111|
|FMV.D.X|_rs1_|_rd_|||

The RISC-V Instruction Set Manual, Volume I | © RISC-V International

Chapter 19. "Ztso" Extension for Total Store Ordering, Version 1.0 | Page 96
