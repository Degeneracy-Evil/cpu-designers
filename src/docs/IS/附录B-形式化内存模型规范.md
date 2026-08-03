## 附录B：形式化内存模型规范，版本0.1

为了促进RVWMO的形式化分析，本章介绍了一组使用不同工具和建模方法的形式化描述。任何差异都是无意的；期望是这些模型描述完全相同的合法行为集合。

本附录应视为评论；所有规范性材料在第18章和ISA规范主体的其余部分中提供。所有当前已知的差异列在第A.7节中。任何其他差异都是无意的。

## B.1. Alloy中的形式化公理规范

我们以Alloy（alloy.mit.edu）呈现RVWMO内存模型的形式化规范。此模型在线可用，网址为github.com/daniellustig/riscv-memory-model。

在线材料还包含一些litmus测试和一些示例，说明如何使用Alloy对A.5节中的一些映射进行模型检查。

```
// =RVWMO PPO=
// 保留的程序顺序（Preserved Program Order）
fun ppo : Event->Event {
// 相同地址排序
  po_loc :> Store
  + rdw
  + (AMO + StoreConditional) <: rfi
// 显式同步
  + ppo_fence
  + Acquire <: ^po :> MemoryEvent
  + MemoryEvent <: ^po :> Release
  + RCsc <: ^po :> RCsc
  + pair
// 语法依赖
  + addrdep
  + datadep
  + ctrldep :> Store
// 流水线依赖
  + (addrdep+datadep).rfi
  + addrdep.^po :> Store
}
// 全局内存序尊重保留的程序顺序
fact { ppo in ^gmo }
```

_清单19. 在Alloy中形式化的RVWMO内存模型（1/5: PPO）_

```
// =RVWMO公理=
```

```
// 加载值公理
fun candidates[r: MemoryEvent] : set MemoryEvent {
  (r.~^gmo & Store & same_addr[r]) // 在gmo中先于r的写入
  + (r.^~po & Store & same_addr[r]) // 在po中先于r的写入
}
fun latest_among[s: set Event] : Event { s - s.~^gmo }
pred LoadValue {
  all w: Store | all r: Load |
    w->r in rf <=> w = latest_among[candidates[r]]
}
// 原子性公理
pred Atomicity {
  all r: Store.~pair |            // 从lr开始，
    no x: Store & same_addr[r] |  // 没有到相同地址的存储x
      x not in same_hart[r]       // 使得x来自不同的hart，
      and x in r.~rf.^gmo         // x在gmo中跟随（r从中读取的存储），
      and r.pair in x.^gmo        // 且r在gmo中跟随x
}
// 进展公理是隐式的：Alloy只考虑有限执行
pred RISCV_mm { LoadValue and Atomicity /* and Progress */ }
```

_在Alloy中形式化的RVWMO内存模型（2/5: 公理）_

```
//内存的基本模型
sig Hart {  // 硬件线程
  start : one Event
}
sig Address {}
abstract sig Event {
  po: lone Event // 程序顺序
}
abstract sig MemoryEvent extends Event {
  address: one Address,
  acquireRCpc: lone MemoryEvent,
  acquireRCsc: lone MemoryEvent,
  releaseRCpc: lone MemoryEvent,
  releaseRCsc: lone MemoryEvent,
  addrdep: set MemoryEvent,
  ctrldep: set Event,
  datadep: set MemoryEvent,
```

```
  gmo: set MemoryEvent,  // 全局内存序
  rf: set MemoryEvent
}
sig LoadNormal extends MemoryEvent {} // l{b|h|w|d}
sig LoadReserve extends MemoryEvent { // lr
  pair: lone StoreConditional
}
sig StoreNormal extends MemoryEvent {}       // s{b|h|w|d}
// 模型中的所有StoreConditional假定为成功
sig StoreConditional extends MemoryEvent {}  // sc
sig AMO extends MemoryEvent {}               // amo
sig NOP extends Event {}
funLoad : Event { LoadNormal + LoadReserve + AMO }
funStore : Event { StoreNormal + StoreConditional + AMO }
sig Fence extends Event {
  pr: lone Fence, // 操作码位
  pw: lone Fence, // 操作码位
  sr: lone Fence, // 操作码位
  sw: lone Fence  // 操作码位
}
sig FenceTSO extends Fence {}
/* Alloy编码细节：操作码位要么设置（编码，例如
* 如f.pr在iden中）要么未设置（f.pr不在iden中）。这些位不能用于
* 其他任何东西 */
fact { pr + pw + sr + sw in iden }
// 对于排序注释同样如此
fact { acquireRCpc + acquireRCsc + releaseRCpc + releaseRCsc in iden }
// 不要试图通过pr/pw/sr/sw编码FenceTSO；就按原样使用它
fact { no FenceTSO.(pr + pw + sr + sw) }
```

_清单20. 在Alloy中形式化的RVWMO内存模型（3/5: 内存模型）_

```
// =基本模型规则=
```

```
// 排序注释组
fun Acquire:MemoryEvent { MemoryEvent.acquireRCpc+MemoryEvent.acquireRCsc }
funRelease:MemoryEvent { MemoryEvent.releaseRCpc+MemoryEvent.releaseRCsc }
funRCpc:MemoryEvent { MemoryEvent.acquireRCpc+MemoryEvent.releaseRCpc }
funRCsc:MemoryEvent { MemoryEvent.acquireRCsc+MemoryEvent.releaseRCsc }
```

```
// 没有存储获取或加载释放这回事，除非两者都是
fact { Load & Release in Acquire }
fact { Store & Acquire in Release }
```

```
// FENCE PPO
fun FencePRSR:Fence { Fence.(pr&sr) }
```

```
funFencePRSW:Fence { Fence.(pr&sw) }
funFencePWSR:Fence { Fence.(pw&sr) }
funFencePWSW:Fence { Fence.(pw&sw) }
funppo_fence:MemoryEvent->MemoryEvent {
    (Load<:^po:>FencePRSR).(^po:>Load)
+ (Load<:^po:>FencePRSW).(^po:>Store)
+ (Store<:^po:>FencePWSR).(^po:>Load)
+ (Store<:^po:>FencePWSW).(^po:>Store)
+ (Load<:^po:>FenceTSO) .(^po:>MemoryEvent)
+ (Store<:^po:>FenceTSO) .(^po:>Store)
}
```

```
// 辅助定义
fun po_loc :Event->Event { ^po&address.~address }
funsame_hart[e:Event] :setEvent { e+e.^~po+e.^po }
funsame_addr[e:Event] :setEvent { e.address.~address }
```

## `// 初始存储`

```
fun NonInit:setEvent { Hart.start.*po }
funInit:setEvent { Event-NonInit }
fact { InitinStoreNormal }
fact { Init->(MemoryEvent&NonInit) in^gmo }
fact { alle:NonInit|onee.*~po.~start }  // 每个事件恰好在
// 一个hart中
```

```
fact { all a:Address|oneInit&a.~address } // 每个地址一个初始存储
fact { no Init<: po and no po :> Init }
```

_清单21. 在Alloy中形式化的RVWMO内存模型（4/5: 基本模型规则）_

```
// po
fact { acyclic[po] }
// gmo
```

```
fact { total[^gmo, MemoryEvent] } // gmo是所有MemoryEvent上的全序
```

```
//rf
```

```
fact { rf.~rf in iden } // 每个读取只返回一个写入的值
fact { rf in Store <: address.~address :> Load }
fun rfi : MemoryEvent->MemoryEvent { rf & (*po + *~po) }
```

```
//dep
fact { no StoreNormal <: (addrdep + ctrldep + datadep) }
fact { addrdep + ctrldep + datadep + pair in ^po }
fact { datadep in datadep :> Store }
fact { ctrldep.*po in ctrldep }
fact { no pair & (^po :> (LoadReserve + StoreConditional)).^po }
fact { StoreConditional in LoadReserve.pair } // 假设所有SC成功
```

```
// rdw
```

```
fun rdw : Event->Event {
  (Load <: po_loc :> Load)  // 从所有相同地址加载-加载对开始，
  - (~rf.rf)                // 减去从同一存储读取的对，
  - (po_loc.rfi)            // 并减去"fri-rfi"模式
}
// 过滤掉冗余实例和/或可视化
fact { no gmo & gmo.gmo } // 保持可视化整洁
fact { all a: Address | some a.~address }
// =可选：操作码编码限制=
// 许可的栅栏列表
fact { Fence in
  Fence.pr.sr
  + Fence.pw.sw
  + Fence.pr.pw.sw
  + Fence.pr.sr.sw
  + FenceTSO
  + Fence.pr.pw.sr.sw
}
pred restrict_to_current_encodings {
  no (LoadNormal + StoreNormal) & (Acquire + Release)
}
// =Alloy快捷方式=
pred acyclic[rel: Event->Event] { no iden & ^rel }
pred total[rel: Event->Event, bag: Event] {
  all disj e, f: bag | e->f in rel + ~rel
  acyclic[rel]
}
```

_清单22. 在Alloy中形式化的RVWMO内存模型（5/5: 辅助）_

## B.2. Herd中的形式化公理规范

工具herd以内存模型和litmus测试作为输入，模拟该测试在内存模型之上的执行。内存模型用领域特定语言Cat编写。本节提供了两个RVWMO的Cat内存模型。第一个模型（清单24）尽可能遵循第18章的 _全局内存序_ 定义来编写RVWMO的Cat模型。第二个模型（清单25）是一个等价的、更高效的、基于偏序的RVWMO模型。

模拟器 `herd` 是 `diy` 工具套件的一部分——请参见diy.inria.fr获取软件和文档。这些模型及更多内容在线可用，网址为diy.inria.fr/cats7/riscv/。

```
(*************)
(* 工具     *)
(*************)
```

```
(* 所有栅栏关系 *)
let fence.r.r = [R];fencerel(Fence.r.r);[R]
let fence.r.w = [R];fencerel(Fence.r.w);[W]
let fence.r.rw = [R];fencerel(Fence.r.rw);[M]
let fence.w.r = [W];fencerel(Fence.w.r);[R]
let fence.w.w = [W];fencerel(Fence.w.w);[W]
let fence.w.rw = [W];fencerel(Fence.w.rw);[M]
let fence.rw.r = [M];fencerel(Fence.rw.r);[R]
let fence.rw.w = [M];fencerel(Fence.rw.w);[W]
let fence.rw.rw = [M];fencerel(Fence.rw.rw);[M]
let fence.tso =
  let f = fencerel(Fence.tso) in
  ([W];f;[W]) | ([R];f;[M])
let fence =
  fence.r.r | fence.r.w | fence.r.rw |
  fence.w.r | fence.w.w | fence.w.rw |
  fence.rw.r | fence.rw.w | fence.rw.rw |
  fence.tso
(* 相同地址，中间没有到相同地址的W *)
let po-loc-no-w = po-loc \ (po-loc?;[W];po-loc)
(* 读取相同写入 *)
let rsw = rf^-1;rf
(* 获取，或更强 *)
let AQ = Acq|AcqRel
(* 释放或更强 *)
and RL = RelAcqRel
(* 所有RCsc *)
let RCsc = Acq|Rel|AcqRel
(* Amo事件既是R也是W，关系rmw关联配对的lr/sc *)
let AMO = R & W
let StCond = range(rmw)
(*************)
(* ppo规则  *)
(*************)
(* 重叠地址排序 *)
let r1 = [M];po-loc;[W]
and r2 = ([R];po-loc-no-w;[R]) \ rsw
and r3 = [AMO|StCond];rfi;[R]
(* 显式同步 *)
and r4 = fence
and r5 = [AQ];po;[M]
and r6 = [M];po;[RL]
and r7 = [RCsc];po;[RCsc]
and r8 = rmw
(* 语法依赖 *)
and r9 = [M];addr;[M]
```

```
and r10 = [M];data;[W]
and r11 = [M];ctrl;[W]
(* 流水线依赖 *)
and r12 = [R];(addr|data);[W];rfi;[R]
and r13 = [R];addr;[M];po;[W]
```

```
let ppo = r1 | r2 | r3 | r4 | r5 | r6 | r7 | r8 | r9 | r10 | r11 | r12 | r13
```

_清单23. riscv-defs.cat，保留程序顺序的herd定义（1/3）_

```
Total
```

```
(* 请注意，herd已经定义了自己的rf关系 *)
```

```
(* 定义ppo *)
include "riscv-defs.cat"
(********************************)
(* 生成全局内存序             *)
(********************************)
let gmo0 = (* 前驱：即将gmo构建为包含gmo0的全序 *)
  loc & (W\FW) * FW | # 在相同位置的任何写入之后的最终写入
  ppo |               # ppo兼容
  rfe                 # 包含herd外部rf（优化）
(* 遍历gmo0的所有线性扩展 *)
with  gmo from linearizations(M\IW,gmo0)
```

```
(* 将初始写入放在前面——便于计算rfGMO *)
let gmo = gmo | loc & IW * (M\IW)
(**********)
(* 公理  *)
(**********)
```

```
(* 根据加载值公理计算rf，即rfGMO *)
let WR = loc & ([W];(gmo|po);[R])
let rfGMO = WR \ (loc&([W];gmo);WR)
```

```
(* 检查herd rf和rfGMO是否相等 *)
empty (rf\rfGMO)|(rfGMO\rf) as RfCons
```

```
(* 原子性公理 *)
let infloc = (gmo & loc)^-1
let inflocext = infloc & ext
let winside  = (infloc;rmw;inflocext) & (infloc;rf;rmw;inflocext) & [W]
empty winside as Atomic
```

_清单24. riscv.cat，RVWMO内存模型的herd版本（2/3）_

```
Partial
(***************)
(* 定义       *)
(***************)
(* 定义ppo *)
include "riscv-defs.cat"
(* 计算相干关系 *)
include "cos-opt.cat"
(**********)
(* 公理  *)
(**********)
(* 每位置顺序一致性 *)
acyclic co|rf|fr|po-loc as Coherence
(* 主要模型公理 *)
acyclic co|rfe|fr|ppo as Model
(* 原子性公理 *)
empty rmw & (fre;coe) as Atomic
```

_清单25. `riscv.cat`，RVWMO内存模型的替代herd表示（3/3）_

## B.3. 操作内存模型

这是RVWMO内存模型的操作风格的替代表示。它旨在承认与公理表示完全相同的扩展行为：对于任何给定程序，当且仅当公理表示允许时才承认一个执行。

公理表示被定义为完整候选执行上的谓词。相比之下，此操作表示具有抽象的微架构风格：它被表示为一个状态机，其状态是硬件机器状态的抽象表示，具有显式的乱序和推测执行（但抽象了更特定于实现的微架构细节，如寄存器重命名、存储缓冲区、缓存层次结构、缓存协议等）。因此，它可以提供有用的直觉。它还可以增量地构造执行，使得可以交互式和随机地探索更大示例的行为，而公理模型需要可以检查公理的完整候选执行。

操作表示涵盖混合大小执行，具有潜在重叠的不同2的幂字节大小的内存访问。未对齐访问被分解为单字节访问。

操作模型与RISC-V ISA语义（RV64I和A）的片段一起集成到 `rmem` 探索工具中（github.com/rems-project/rmem）。`rmem` 可以穷举地、伪随机地和交互式地探索litmus测试（参见A.2节）和小型ELF二进制文件。在 `rmem` 中，ISA语义用Sail显式表示（参见github.com/rems-project/sail了解Sail语言，github.com/rems-project/sail-riscv了解RISC-V ISA模型），并发语义用Lem表示（参见github.com/rems-project/lem了解Lem语言）。

`rmem` 具有命令行界面和Web界面。Web界面完全在客户端运行，并与litmus测试库一起在线提供：<www.cl.cam.ac.uk/>。命令行界面比Web界面更快，特别是在穷举模式下。

以下是模型状态和转换的非正式介绍。形式化模型的描述从下一小节开始。

术语：与公理表示相比，这里的每个内存操作要么是加载，要么是存储。因此，AMO产生两个不同的内存操作，一个加载和一个存储。当与 `指令` 结合使用时，术语 `加载` 和 `存储` 指的是产生此类内存操作的指令。因此，两者都包括AMO指令。术语 `获取` 指的是具有acquire-RCpc或acquire-RCsc注释的指令（或其内存操作）。术语 `释放` 指的是具有release-RCpc或release-RCsc注释的指令（或其内存操作）。

## 模型状态

模型状态：模型状态由共享内存和一个hart状态元组组成。

共享内存状态记录到目前为止已传播的所有内存存储操作，按它们传播的顺序记录（这可以做得更高效，但为了表示的简单性我们保持这种方式）。

每个hart状态主要由一个指令实例树组成，其中一些已经 _完成（finished）_，一些尚未完成。未完成的指令实例可能受到 _重启（restart）_，例如如果它们依赖于被证明不健全的乱序或推测加载。

条件分支和间接跳转指令可能在指令树中有多个后继。当此类指令完成时，任何未采用的分支将被丢弃。

指令树中的每个指令实例都有一个状态，包括指令内部语义（此指令的ISA伪代码）的执行状态。该模型使用Sail中指令内部语义的形式化。可以将指令的执行状态视为伪代码控制状态、伪代码调用栈和局部变量值的表示。指令实例状态还包括关于实例的内存和寄存器足迹、其寄存器读取和写入、其内存操作、是否完成等信息。

## 模型转换

该模型为任何模型状态定义了允许的转换集合，每个转换都是到新抽象机器状态的单一原子步骤。单条指令的执行通常涉及许多转换，它们可能在操作模型执行中与来自其他指令的转换交织。每个转换来自单个指令实例；它将改变该实例的状态，并且可能依赖或改变其hart状态和共享内存状态的其余部分，但它不依赖其他hart状态，也不会改变它们。转换在下面介绍并在第B.3.5节中定义，每个转换都有前提条件和转换后模型状态的构造。

所有指令的转换：

- **获取指令（Fetch instruction）**：此转换表示新指令实例的获取和解码，作为先前获取的指令实例（或初始获取地址）的程序顺序后继。该模型假设指令内存是固定的；它不描述自修改代码的行为。特别是，获取指令转换不生成内存加载操作，共享内存不参与该转换。相反，该模型依赖于在给定内存位置时提供操作码的外部预言机。
- **寄存器写入（Register write）**：寄存器值的写入。
- **寄存器读取（Register read）**：从最近写入该寄存器的程序顺序前驱指令实例读取寄存器值。
- **伪代码内部步骤（Pseudocode internal step）**：涵盖伪代码内部计算：算术、函数调用等。
- **完成指令（Finish instruction）**：此时指令伪代码已完成，指令不能被重启，内存访问不能被丢弃，所有内存效果已生效。对于条件分支和间接跳转指令，从非写入 _pc_ 寄存器的地址获取的任何程序顺序后继将被丢弃，连同它们下面的指令实例子树。

特定于加载指令的转换：

- **启动内存加载操作（Initiate memory load operations）**：此时加载指令的内存足迹已临时已知（如果早期指令被重启可能会改变），其各个内存加载操作可以开始被满足。
- **通过从未传播存储转发来满足内存加载操作（Satisfy memory load operation by forwarding from unpropagated stores）**：通过从程序顺序先前的内存存储操作转发，部分或全部满足单个内存加载操作。
- **从内存满足内存加载操作（Satisfy memory load operation from memory）**：完全满足单个内存加载操作的未满足切片，从内存。
- **完成加载操作（Complete load operations）**：此时指令的所有内存加载操作已被完全满足，指令伪代码可以继续执行。加载指令在此转换之前可能会被重启。但在某些条件下，模型可能将加载指令视为即使未完成也无法重启。

特定于存储指令的转换：

- **启动内存存储操作足迹（Initiate memory store operation footprints）**：此时存储的内存足迹已临时已知。
- **实例化内存存储操作值（Instantiate memory store operation values）**：此时内存存储操作有其值，程序顺序后继内存加载操作可以通过从它们转发来满足。
- **提交存储指令（Commit store instruction）**：此时存储操作保证会发生（指令不能再被重启或丢弃），它们可以开始被传播到内存。
- **传播存储操作（Propagate store operation）**：将单个内存存储操作传播到内存。
- **完成存储操作（Complete store operations）**：此时指令的所有内存存储操作已传播到内存，指令伪代码可以继续执行。

特定于 `sc` 指令的转换：

- **早期sc失败（Early sc fail）**：导致 `sc` 失败，要么是自发失败，要么因为它与程序顺序先前的 `lr` 未配对。
- **配对sc（Paired sc）**：此转换指示 `sc` 与 `lr` 配对，可能成功。
- **提交并传播sc的存储操作（Commit and propagate store operation of an sc）**：这是提交存储指令和传播存储操作转换的原子执行，它仅在 `lr` 从中读取的存储未被覆盖时才启用。
- **晚期sc失败（Late sc fail）**：导致 `sc` 失败，要么是自发失败，要么因为 `lr` 从中读取的存储已被覆盖。

特定于AMO指令的转换：

- **满足、提交并传播AMO的操作（Satisfy, commit and propagate operations of an AMO）**：这是满足加载操作、执行所需算术和传播存储操作所需的所有转换的原子执行。

特定于栅栏指令的转换：

- **提交栅栏（Commit fence）**

标记○的转换始终可以在前提条件满足时急切地采用，而不排除其他行为；标记∙的则不能。虽然获取指令标记为∙，但只要不被无限多次获取，它可以被急切地采用。

非AMO加载指令的实例，在被获取后，通常会按以下顺序经历以下转换：

1. 寄存器读取
2. 启动内存加载操作
3. 通过从未传播存储转发来满足内存加载操作和/或从内存满足内存加载操作（根据需要满足实例的所有加载操作）
4. 完成加载操作
5. 寄存器写入
6. 完成指令

在上述转换之前、之间和之后，可能出现任意数量的伪代码内部步骤转换。此外，获取下一个程序位置的指令的获取指令转换将可用，直到被采用。

这结束了操作模型的非正式描述。以下各节描述形式化操作模型。

## B.3.1. 指令内伪代码执行

每个指令实例的指令内语义被表示为一个状态机，本质上运行指令伪代码。给定一个伪代码执行状态，它计算下一个状态。大多数状态标识一个待处理的内存或寄存器操作，由伪代码请求，内存模型必须执行。状态如下（这是一个标记联合；标记用小写体表示）：

|Load_mem(_kind_,_address_,_size_,_load_continuation_)|- 内存加载操作|
|---|---|
|Early_sc_fail(_res_continuation_)|- 允许`sc`早期失败|
|Store_ea(_kind_,_address_,_size_,_next_state_)|- 内存存储有效地址|
|Store_memv(_mem_value_,_store_continuation_)|- 内存存储值|
|Fence(_kind_,_next_state_)|- 栅栏|
|Read_reg(_reg_name_,_read_continuation_)|- 寄存器读取|
|Write_reg(_reg_name_,_reg_value_,_next_state_)|- 寄存器写入|
|Internal(_next_state_)|- 伪代码内部步骤|
|Done|- 伪代码结束|

其中：

- _mem_value_ 和 _reg_value_ 是字节列表；
- _address_ 是XLEN位的整数；
- 对于加载/存储，_kind_ 标识它是否是 `lr/sc`、acquire-RCpc/release-RCpc、acquire-RCsc/release-RCsc、acquire-release-RCsc；对于栅栏，_kind_ 标识它是普通还是TSO，以及（对于普通栅栏）前驱和后继排序位；_reg_name_ 标识寄存器及其切片（起始和结束位索引）；continuation描述了对于周围内存模型可能提供的每个值，指令实例将如何继续（_load_continuation_ 和 _read_continuation_ 获取从内存加载的值和从前一个寄存器写入读取的值，_store_continuation_ 对失败的 `sc` 取 _false_，在所有其他情况下取 _true_，_res_continuation_ 在 `sc` 失败时取 _false_，否则取 _true_）。

_例如，给定加载指令 `lw x1,0(x2)`，执行通常如下进行。初始执行状态将从给定操作码的伪代码计算。可以预期为Read_reg(`x2`, read_continuation)。将寄存器 `x2` 最近写入的值（如果需要，指令语义将被阻塞直到寄存器值可用），比如 `0x4000`，提供给read_continuation，返回Load_mem(`plain_load`, `0x4000`, `4`, load_continuation)。将从内存位置 `0x4000` 加载的4字节值，比如 `0x42`，提供给load_continuation，返回Write_reg(`x1`, `0x42`, Done)。在上述状态之前和之间可能出现许多Internal(next_state)状态。_

请注意，写入内存被分为两个步骤，Store_ea和Store_memv：第一个临时使存储的内存足迹已知，第二个添加要存储的值。我们确保这些在伪代码中配对（Store_ea后跟Store_memv），但它们之间可能有其他步骤。

_可以观察到Store_ea可以在要存储的值确定之前发生。例如，为了使操作模型允许litmus测试LB+fence.r.rw+data-po（就像RVWMO允许的那样），Hart 1中的第一个存储必须在其值确定之前采取Store_ea步骤，以便第二个存储可以看到它是到非重叠的内存足迹，允许第二个存储被乱序提交而不违反相干性。_

每个指令的伪代码最多执行一次存储或一次加载，除了AMO执行恰好一次加载和一次存储。这些内存访问然后被hart语义分割为架构原子单元（见下面的启动内存加载操作和启动内存存储操作足迹）。

非正式地说，寄存器读取的每一位应从能写入该位的最近（程序顺序）指令实例（或hart的初始寄存器状态，如果没有这样的写入）的寄存器写入满足。因此，了解每个指令实例的寄存器写入足迹至关重要，我们在创建指令实例时计算这些足迹（见下面的获取指令操作）。我们在伪代码中确保每个指令最多对每个寄存器位执行一次寄存器写入，并且也不尝试读取它刚刚写入的寄存器值。

模型中的数据流依赖（地址和数据）源于每个寄存器读取必须等待适当的寄存器写入被执行（如上所述）。

## B.3.2. 指令实例状态

每个指令实例 __i_ 有一个状态包括：

- _program_loc_，从中获取指令的内存地址；
- _instruction_kind_，标识这是加载、存储、AMO、栅栏、分支/跳转还是"简单"指令（这还包括类似于为伪代码执行状态描述的 _kind_）；
- _src_regs_，源 _reg_name_ 的集合（包括系统寄存器），从指令的伪代码静态确定；
- _dst_regs_，目标 _reg_name_ 的集合（包括系统寄存器），从指令的伪代码静态确定；
- _pseudocode_state_（或有时简称为 `state`），以下之一（标记联合；标记用小写体）：

|_pseudocode_state_（或有时简称为`state`）|以下之一（标记联合；标记用小写体）：|
|---|---|
|Plain(_isa_state_)|- 准备进行伪代码转换|
|Pending_mem_loads(_load_continuation_)|- 请求内存加载操作|
|Pending_mem_stores(_store_continuation_)|- 请求内存存储操作|

- _reg_reads_，实例已执行的寄存器读取，包括每个读取的寄存器写入切片；
- _reg_writes_，实例已执行的寄存器写入；
- _mem_loads_，一组内存加载操作，对于每个操作，尚未满足的切片（尚未满足的字节索引），以及对于已满足的切片，满足它的存储切片（每个包含一个内存存储操作及其字节索引子集）。
- _mem_stores_，一组内存存储操作，对于每个操作，一个标志指示它是否已传播（传递给共享内存）或未传播。
- 记录实例是否已提交、已完成等的信息。

每个内存加载操作包括内存足迹（地址和大小）。每个内存存储操作包括内存足迹，以及在可用时的值。

具有非空 _mem_loads_ 的加载指令实例，其所有加载操作都已满足（即没有未满足的加载切片）被称为 _完全满足（entirely satisfied）_。

非正式地说，指令实例被称为具有 _完全确定的数据（fully determined data）_，如果向其源寄存器提供输入的加载（和 `sc`）指令已完成。类似地，它被称为具有 _完全确定的内存足迹（fully determined memory footprint）_，如果向其内存操作地址寄存器提供输入的加载（和 `sc`）指令已完成。正式地，我们首先定义 _完全确定的寄存器写入（fully determined register write）_ 的概念：如果满足以下条件之一，来自指令实例 _i_ 的 _reg_writes_ 的寄存器写入 _w_ 被称为 _完全确定的_：

1. _i_ 已完成；或
2. 由 _w_ 写入的值不受 _i_ 已进行的内存操作（即从内存加载的值或 `sc` 的结果）影响，并且对于 _i_ 已进行的每个影响 _w_ 的寄存器读取，_i_ 从中读取的寄存器写入是完全确定的（或 _i_ 从初始寄存器状态读取）。

现在，如果对于 _reg_reads_ 中的每个寄存器读取 _r_，_r_ 从中读取的寄存器写入是完全确定的，则指令实例 _i_ 被称为具有 _完全确定的数据_。如果对于 _reg_reads_ 中向 _i_ 的内存操作地址提供输入的每个寄存器读取 _r_，_r_ 从中读取的寄存器写入是完全确定的，则指令实例 _i_ 被称为具有 _完全确定的内存足迹_。

_`rmem` 工具为每个寄存器写入记录了在执行写入时此指令已读取的其他指令的寄存器写入集合。通过仔细安排工具涵盖的指令的伪代码，我们能够使其成为写入所依赖的寄存器写入的精确集合。_

## B.3.3. Hart状态

单个hart的模型状态包括：

- _hart_id_，hart的唯一标识符；
- _initial_register_state_，每个寄存器的初始寄存器值；
- _initial_fetch_address_，初始指令获取地址；
- _instruction_tree_，已获取（且未丢弃）的指令实例树，按程序顺序。

## B.3.4. 共享内存状态

共享内存的模型状态包括一个内存存储操作列表，按它们传播到共享内存的顺序排列。

当存储操作传播到共享内存时，它简单地添加到列表末尾。当加载操作从内存满足时，对于加载操作的每个字节，返回最近对应的存储切片。

_对于大多数目的，将共享内存看作一个数组更简单，即从内存位置到内存存储操作切片的映射，其中每个内存位置映射到对该位置的最近内存存储操作的单字节切片。然而，这种抽象不够详细，无法正确处理 `sc` 指令。RVWMO允许来自与 `sc` 同一hart的存储操作在 `sc` 的存储操作和配对 `lr` 从中读取的存储操作之间介入。为了允许此类存储操作介入并禁止其他操作，数组抽象必须扩展以记录更多信息。在这里，我们使用列表因为它非常简单，但更高效和可扩展的实现可能应该使用更好的东西。_

## B.3.5. 转换

以下每个段落描述了单一种类的系统转换。描述以当前系统状态的条件开始。仅当条件满足时，转换才能在当前状态中采用。条件后跟一个操作，当转换被采用时应用于该状态以生成新系统状态。

## B.3.5.1. 获取指令

如果满足以下条件，可以从地址 _loc_ 获取指令实例 _i_ 的可能程序顺序后继：

1. 它尚未被获取，即hart的 _instruction_tree_ 中 _i_ 的直接后继中没有来自 _loc_ 的；且
2. 如果 _i_ 的伪代码已向 _pc_ 写入地址，则 _loc_ 必须是该地址，否则 _loc_ 是：
   - 对于条件分支，后继地址或分支目标地址；
   - 对于（直接）跳转和链接指令（`jal`），目标地址；
   - 对于间接跳转指令（`jalr`），任何地址；且
   - 对于任何其他指令，_i.program_loc_ +4。

操作：为 _loc_ 处程序内存中的指令构造一个新鲜初始化的指令实例 _i'_，状态为Plain(_isa_state_)，从指令伪代码计算出，包括从伪代码可用的静态信息，如其 _instruction_kind_、_src_regs_ 和 _dst_regs_，并将 _i'_ 作为 _i_ 的后继添加到hart的 _instruction_tree_ 中。

可能的下一获取地址（_loc_）在获取 _i_ 后立即可用，模型不需要等待伪代码写入 _pc_；这允许乱序执行，以及推测通过条件分支和跳转。对于大多数指令，这些地址可以从指令伪代码轻松获得。唯一的例外是间接跳转指令（`jalr`），其地址取决于寄存器中保存的值。原则上，数学模型应允许在此处推测到任意地址。`rmem` 工具中的穷举搜索通过为每个间接跳转使用不断增长的可能的下一获取地址集合多次运行穷举搜索来处理这一点。初始搜索使用空集，因此在间接跳转指令之后没有获取，直到指令的伪代码写入 _pc_，然后我们使用该值获取下一条指令。在开始穷举搜索的下一迭代之前，我们为每个间接跳转（按代码位置分组）收集在前一次搜索迭代中所有执行中它写入 _pc_ 的值集合，并将其用作该指令的可能下一获取地址。当没有检测到新的获取地址时，此过程终止。

## B.3.5.2. 启动内存加载操作

状态为Plain(Load_mem(_kind_, _address_, _size_, _load_continuation_))的指令实例 _i_ 始终可以启动相应的内存加载操作。操作：

1. 构造适当的内存加载操作 _mlos_：
   - 如果 _address_ 对齐到 _size_，则 _mlos_ 是从 _address_ 开始的 _size_ 字节的单个内存加载操作；
   - 否则，_mlos_ 是 _size_ 个内存加载操作的集合，每个一个字节，来自地址 _address_ … _address_ + _size_ −1。
2. 将 _i_ 的 _mem_loads_ 设置为 _mlos_；且
3. 将 _i_ 的状态更新为 Pending_mem_loads(_load_continuation_)。

在第18.1.1节中，说了未对齐内存访问可以以任何粒度分解。在这里，我们将它们分解为单字节访问，因为此粒度包含所有其他粒度。

## B.3.5.3. 通过从未传播存储转发来满足内存加载操作

对于处于Pending_mem_loads(_load_continuation_)状态的非AMO加载指令实例 _i_，以及 _i.mem_loads_ 中具有未满足切片的内存加载操作 _mlo_，如果满足以下条件，内存加载操作可以通过从程序顺序先于 _i_ 的存储指令实例的未传播内存存储操作转发的部分或全部满足：

1. 所有设置了 `.sr` 和 `.pw` 的程序顺序先前 `fence` 指令已完成；
2. 对于每个设置了 `.sr` 和 `.pr` 且 `.pw` 未设置的程序顺序先前 `fence` 指令 _f_，如果 _f_ 未完成，则所有程序顺序先于 _f_ 的加载指令完全满足；
3. 对于每个未完成的程序顺序先前 `fence.tso` 指令 _f_，所有程序顺序先于 _f_ 的加载指令完全满足；
4. 如果 _i_ 是加载获取RCsc，所有程序顺序先前的存储释放RCsc已完成；
5. 如果 _i_ 是加载获取释放，所有程序顺序先前的指令已完成；
6. 所有未完成的程序顺序先前加载获取指令完全满足；且
7. 所有程序顺序先前的存储获取释放指令已完成；

令 _msoss_ 为来自程序顺序先于 _i_ 且已计算出要存储的值的非 `sc` 存储指令实例的所有未传播内存存储操作切片集合，这些切片与 _mlo_ 的未满足切片重叠，并且不被中间存储操作或被中间加载从中读取的存储操作取代。最后一个条件要求，对于 _msoss_ 中来自指令 _i'_ 的每个内存存储操作切片 _msos_：

- 在 _i_ 和 _i'_ 之间没有程序顺序存储指令具有与 _msos_ 重叠的内存存储操作；且
- 在 _i_ 和 _i'_ 之间没有程序顺序加载指令从来自不同hart的重叠内存存储操作切片中满足。

操作：

1. 更新 _i.mem_loads_ 以指示 _mlo_ 由 _msoss_ 满足；且
2. 重启因此导致违反相干性的任何推测指令，即对于作为 _i_ 的程序顺序后继的每个未完成指令 _i'_，以及 _i'_ 中从 _msoss'_ 满足的每个内存加载操作 _mlo'_，如果在 _msoss'_ 中存在一个内存存储操作切片 _msos'_，且在 _msoss_ 中存在来自不同内存存储操作的重叠内存存储操作切片，且 _msos'_ 不是来自是 _i_ 的程序顺序后继的指令，则重启 _i'_ 及其 _restart-dependents_。

其中，指令 _j_ 的 _restart-dependents_ 是：

- _j_ 的对 _j_ 的寄存器写入有数据流依赖的程序顺序后继；
- _j_ 的具有从 _j_ 的内存存储操作（通过转发）读取的内存加载操作的程序顺序后继；
- 如果 _j_ 是加载获取，_j_ 的所有程序顺序后继；
- 如果 _j_ 是加载，对于作为 _j_ 的程序顺序后继的每个设置了 `.sr` 和 `.pr` 且 `.pw` 未设置的 `fence` _f_，_f_ 的所有程序顺序后继中的加载指令；
- 如果 _j_ 是加载，对于作为 _j_ 的程序顺序后继的每个 `fence.tso` _f_，_f_ 的所有程序顺序后继中的加载指令；以及
- （递归地）上述所有指令实例的所有restart-dependents。

将内存存储操作转发到内存加载可能只满足加载的某些切片，其他切片保持未满足。

在采用上述转换时不可用的程序顺序先前存储操作，可能在它变得可用时使 _msoss_ 临时不健全（违反相干性）。该存储将阻止加载完成（见完成指令），并在该存储操作被传播时导致其重启（见传播存储操作）。

上述转换条件的一个后果是存储释放RCsc内存存储操作不能转发到加载获取RCsc指令：_msoss_ 不包括来自已完成存储的内存存储操作（因为这些必须是已传播的内存存储操作），并且上述条件要求当加载是获取RCsc时，所有程序顺序先前的存储释放RCsc已完成。

## B.3.5.4. 从内存满足内存加载操作

对于非AMO加载指令的指令实例 _i_ 或AMO指令在满足、提交和传播AMO操作的转换上下文中，如果满足满足内存加载操作通过从未传播存储转发的所有条件，_i.mem_loads_ 中具有未满足切片的任何内存加载操作 _mlo_ 可以从内存满足。操作：令 _msoss_ 为覆盖 _mlo_ 未满足切片的来自内存的内存存储操作切片，并应用满足内存操作通过从未传播存储转发的操作。

_请注意，满足内存操作通过从未传播存储转发可能使内存加载操作的某些切片未满足，这些将必须通过再次采取该转换或采取从内存满足内存加载操作来满足。另一方面，从内存满足内存加载操作将始终满足内存加载操作的所有未满足切片。_

## B.3.5.5. 完成加载操作

处于Pending_mem_loads(_load_continuation_)状态的加载指令实例 _i_ 可以完成（不要与已完成混淆），如果所有内存加载操作 _i.mem_loads_ 完全满足（即没有未满足的切片）。操作：将 _i_ 的状态更新为Plain(_load_continuation(mem_value)_)，其中 _mem_value_ 从满足 _i.mem_loads_ 的所有内存存储操作切片组装而成。

## B.3.5.6. 早期 `sc` 失败

处于Plain(Early_sc_fail(_res_continuation_))状态的 `sc` 指令实例 _i_ 始终可以被设置为失败。操作：将 _i_ 的状态更新为Plain(_res_continuation(false)_)。

## B.3.5.7. 配对 `sc`

处于Plain(Early_sc_fail(_res_continuation_))状态的 `sc` 指令实例 _i_ 如果 _i_ 与 `lr` 配对，可以继续其（潜在成功的）执行。操作：将 _i_ 的状态更新为Plain(_res_continuation(true)_)。

## B.3.5.8. 启动内存存储操作足迹

处于Plain(Store_ea(_kind_, _address_, _size_, _next_state_))状态的指令实例 _i_ 始终可以宣布其待处理的内存存储操作足迹。操作：

1. 构造适当的内存存储操作 _msos_（没有存储值）：
   - 如果 _address_ 对齐到 _size_，则 _msos_ 是到 _address_ 的 _size_ 字节的单个内存存储操作；
   - 否则，_msos_ 是 _size_ 个内存存储操作集合，每个一个字节大小，到地址 _address_ … _address_ + _size_ −1。
2. 将 _i.mem_stores_ 设置为 _msos_；且
3. 将 _i_ 的状态更新为Plain(_next_state_)。

请注意，在采用上述转换后，内存存储操作尚不具有其值。

将此转换与下面的转换分开的重要性在于，它允许其他程序顺序后继存储指令观察到此指令的内存足迹，如果它们不重叠，尽可能早地乱序传播（即在数据寄存器值变得可用之前）。

## B.3.5.9. 实例化内存存储操作值

处于Plain(Store_memv(_mem_value_, _store_continuation_))状态的指令实例 _i_ 始终可以实例化内存存储操作 _i.mem_stores_ 的值。操作：

1. 在内存存储操作 _i.mem_stores_ 之间分割 _mem_value_；且
2. 将 _i_ 的状态更新为Pending_mem_stores(_store_continuation_)。

## B.3.5.10. 提交存储指令

非 `sc` 存储指令或 `sc` 指令在提交和传播 `sc` 转换的存储操作上下文中的未提交指令实例 _i_，处于Pending_mem_stores(_store_continuation_)状态，如果满足以下条件可以被提交（不要与传播混淆）：

1. _i_ 具有完全确定的数据；
2. 所有程序顺序先前的条件分支和间接跳转指令已完成；
3. 所有设置了 `.sw` 的程序顺序先前 `fence` 指令已完成；
4. 所有程序顺序先前的 `fence.tso` 指令已完成；
5. 所有程序顺序先前的加载获取指令已完成；
6. 所有程序顺序先前的存储获取释放指令已完成；
7. 如果 _i_ 是存储释放，所有程序顺序先前的指令已完成；
8. 所有程序顺序先前的内存访问指令具有完全确定的内存足迹；
9. 除失败的 `sc` 外，所有程序顺序先前的存储指令已启动，因此具有非空 _mem_stores_；且
10. 所有程序顺序先前的加载指令已启动，因此具有非空 _mem_loads_。

操作：记录 _i_ 已提交。

_请注意，如果条件8满足，条件9和10也满足，或在采取某些急切转换后将满足。因此，要求它们不加强模型。通过要求它们，我们保证先前的内存访问指令已采取足够的转换，使其内存操作对条件检查可见，使该条件更简单。_

## B.3.5.11. 传播存储操作

对于处于Pending_mem_stores(_store_continuation_)状态的已提交指令实例 _i_，以及 _i.mem_stores_ 中的未传播内存存储操作 _mso_，如果满足以下条件，_mso_ 可以被传播：

1. 与 _mso_ 重叠的程序顺序先前存储指令的所有内存存储操作已传播；
2. 与 _mso_ 重叠的程序顺序先前加载指令的所有内存加载操作已满足，且（加载指令）是 _不可重启的（non-restartable）_（见下面的定义）；且
3. 通过转发 _mso_ 满足的所有内存加载操作完全满足。

其中，未完成的指令实例 _j_ 是 _不可重启的_，如果：

1. 不存在存储指令 _s_ 和 _s_ 的未传播内存存储操作 _mso_，使得对 _mso_ 应用传播存储操作转换的操作将导致 _j_ 的重启；且
2. 不存在未完成的加载指令 _l_ 和 _l_ 的内存加载操作 _mlo_，使得对 _mlo_ 应用满足内存加载操作通过从未传播存储转发/从内存满足内存加载操作转换（即使 _mlo_ 已满足）将导致 _j_ 的重启。

操作：

1. 用 _mso_ 更新共享内存状态；
2. 更新 _i.mem_stores_ 以指示 _mso_ 已传播；且
3. 重启因此导致违反相干性的任何推测指令，即对于 _i_ 之后的每个未完成指令 _i'_ 和 _i'_ 中从 _msoss'_ 满足的每个内存加载操作 _mlo'_，如果在 _msoss'_ 中存在与 _mso_ 重叠且不来自 _mso_ 的内存存储操作切片 _msos'_，且 _msos'_ 不是来自 _i_ 的程序顺序后继，则重启 _i'_ 及其 _restart-dependents_（见从未传播存储转发满足内存加载操作）。

## B.3.5.12. 提交并传播 `sc` 的存储操作

来自hart _h_ 的未提交 `sc` 指令实例 _i_，处于Pending_mem_stores(_store_continuation_)状态，具有已由某些存储切片 _msoss_ 满足的配对 `lr` _i'_，如果满足以下条件，可以同时被提交和传播：

1. _i'_ 已完成；
2. 已转发到 _i'_ 的每个内存存储操作已传播；
3. 提交存储指令的条件满足；
4. 传播存储指令的条件满足（请注意，`sc` 指令只能有一个内存存储操作）；且
5. 对于 _msoss_ 中的每个存储切片 _msos_，_msos_ 在共享内存中尚未被来自非 _h_ 的hart的任何存储覆盖，自 _msos_ 传播到内存以来的任何时间点。

操作：

1. 应用提交存储指令的操作；且
2. 应用传播存储指令的操作。

## B.3.5.13. 晚期 `sc` 失败

处于Pending_mem_stores(_store_continuation_)状态的 `sc` 指令实例 _i_，尚未传播其内存存储操作，始终可以被设置为失败。操作：

1. 清除 _i.mem_stores_；且
2. 将 _i_ 的状态更新为Plain(_store_continuation(false)_)。

为提高效率，`rmem` 工具仅当无法采取提交并传播 `sc` 转换的存储操作时才允许此转换。这不影响允许的最终状态集合，但在交互式探索时，如果 `sc` 应该失败，应使用早期 `sc` 失败转换而不是等待此转换。

## B.3.5.14. 完成存储操作

处于Pending_mem_stores(_store_continuation_)状态的存储指令实例 _i_，其 _i.mem_stores_ 中的所有内存存储操作已传播，始终可以完成（不要与已完成混淆）。操作：将 _i_ 的状态更新为Plain(_store_continuation(true)_)。

## B.3.5.15. 满足、提交并传播AMO的操作

处于Pending_mem_loads(_load_continuation_)状态的AMO指令实例 _i_ 可以执行其内存访问，如果可以在没有中间转换的情况下执行以下转换序列：

1. 从内存满足内存加载操作
2. 完成加载操作
3. 伪代码内部步骤（零次或多次）
4. 实例化内存存储操作值
5. 提交存储指令
6. 传播存储操作
7. 完成存储操作

此外，完成指令的条件（除了不要求 _i_ 处于Plain(Done)状态）在这些转换之后成立。操作：执行上述转换序列（这不包括完成指令），一个接一个，没有中间转换。

_请注意，程序顺序先前的存储不能转发到AMO的加载。这仅仅是因为上述转换序列不包括转发转换。但即使它包括，当尝试执行传播存储操作转换时序列将失败，因为此转换要求所有到重叠内存足迹的程序顺序先前存储操作已传播，而转发要求存储操作未传播。_

_此外，AMO的存储不能转发到程序顺序后继的加载。在采用上述转换之前，AMO的存储操作不具有其值，因此不能被转发；在采用上述转换之后，存储操作已传播，因此不能被转发。_

## B.3.5.16. 提交栅栏

处于Plain(Fence(_kind_, _next_state_))状态的栅栏指令实例 _i_ 如果满足以下条件可以被提交：

1. 如果 _i_ 是普通栅栏且设置了 `.pr`，所有程序顺序先前的加载指令已完成；
2. 如果 _i_ 是普通栅栏且设置了 `.pw`，所有程序顺序先前的存储指令已完成；且
3. 如果 _i_ 是 `fence.tso`，所有程序顺序先前的加载和存储指令已完成。

操作：

1. 记录 _i_ 已提交；且
2. 将 _i_ 的状态更新为Plain(_next_state_)。

## B.3.5.17. 寄存器读取

处于Plain(Read_reg(_reg_name_, _read_cont_))状态的指令实例 _i_ 可以执行 _reg_name_ 的寄存器读取，如果它需要从中读取的每个指令实例已执行预期的 _reg_name_ 寄存器写入。

令 _read_sources_ 包括，对于 _reg_name_ 的每一位，由能写入该位的最近（程序顺序）指令实例（如果有的话）写入该位的值。如果没有这样的指令，源是来自 _initial_register_state_ 的初始寄存器值。令 _reg_value_ 为从 _read_sources_ 组装的值。操作：

1. 将 _reg_name_ 添加到 _i.reg_reads_，带有 _read_sources_ 和 _reg_value_；且
2. 将 _i_ 的状态更新为Plain(_read_cont(reg_value)_)。

## B.3.5.18. 寄存器写入

处于Plain(Write_reg(_reg_name_, _reg_value_, _next_state_))状态的指令实例 _i_ 始终可以执行 _reg_name_ 寄存器写入。操作：

1. 将 _reg_name_ 添加到 _i.reg_writes_，带有 _deps_ 和 _reg_value_；且
2. 将 _i_ 的状态更新为Plain(_next_state_)。

其中 _deps_ 是来自 _i.reg_reads_ 的所有 _read_sources_ 集合与一个标志的对，该标志当且仅当 _i_ 是已完全满足的加载指令实例时为真。

## B.3.5.19. 伪代码内部步骤

处于Plain(Internal(_next_state_))状态的指令实例 _i_ 始终可以执行该伪代码内部步骤。操作：将 _i_ 的状态更新为Plain(_next_state_)。

## B.3.5.20. 完成指令

处于Plain(Done)状态的未完成指令实例 _i_ 如果满足以下条件可以被完成：

1. 如果 _i_ 是加载指令：
   - a. 所有程序顺序先前的加载获取指令已完成；
   - b. 所有设置了 `.sr` 的程序顺序先前 `fence` 指令已完成；
   - c. 对于每个未完成的程序顺序先前 `fence.tso` 指令 _f_，所有程序顺序先于 _f_ 的加载指令已完成；且
   - d. 保证由 _i_ 的内存加载操作读取的值不会导致相干性违规，即对于任何程序顺序先前的指令实例 _i'_，令 _cfp_ 为来自 _i_ 和 _i'_ 之间的存储指令（包括 _i'_）的已传播内存存储操作和被转发到 _i_ 的 _固定内存存储操作_ 的组合足迹，令 _/cfp_ 为 _cfp_ 在 _i_ 的内存足迹中的补集。如果 _/cfp_ 不为空：
     - i. _i'_ 具有完全确定的内存足迹；
     - ii. _i'_ 没有与 _/cfp_ 重叠的未传播内存存储操作；且
     - iii. 如果 _i'_ 是具有与 _/cfp_ 重叠的内存足迹的加载，则 _i'_ 中与 _/cfp_ 重叠的所有内存加载操作已满足，且 _i'_ 是 _不可重启的_（参见传播存储操作转换以了解如何确定指令是否不可重启）。

这里，如果存储指令具有完全确定的数据，内存存储操作被称为固定的。

2. _i_ 具有完全确定的数据；且
3. 如果 _i_ 不是栅栏，所有程序顺序先前的条件分支和间接跳转指令已完成。

操作：

1. 如果 _i_ 是条件分支或间接跳转指令，丢弃任何未采用的执行路径，即移除在 _instruction_tree_ 中通过所采用的分支/跳转不可达的所有指令实例；且
2. 记录指令已完成，即将 _finished_ 设置为 _true_。

## B.3.6. 局限性

- 该模型涵盖用户级RV64I和RV64A。特别是，它不支持未对齐原子性粒PMA或全序存储扩展"Ztso"。将模型适配到RV32I/A以及G、Q和C扩展应该是平凡的，但我们从未尝试过。这主要涉及为指令编写Sail代码，对并发模型的更改最小（如果有的话）。
- 该模型仅涵盖正常内存访问（它不处理I/O访问）。
- 该模型不涵盖TLB相关效应。
- 该模型假设指令内存是固定的。特别是，获取指令转换不生成内存加载操作，共享内存不参与该转换。相反，该模型依赖于在给定内存位置时提供操作码的外部预言机。
- 该模型不涵盖异常、陷阱和中断。
