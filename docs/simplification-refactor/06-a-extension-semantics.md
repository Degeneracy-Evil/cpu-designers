# CPU 代码简化重构：A Extension Semantics

> 分支：`chp`  
> 前置阶段：Architecture Foundation、Unified Exception / Trap 已完成。  
> 本文定义 Phase 7：RV32A（Zaamo + Zalrsc）语义收口。目标不是增加复杂原子子系统，而是在当前单 hart、严格串行、single-outstanding memory system 上，把 LR/SC/AMO 的架构语义实现完整并明确平台边界。

---

# 1. 范围

当前 `misa.A` 表示处理器支持 RV32A。

本阶段继续支持：

```text
Zalrsc
    LR.W
    SC.W

Zaamo
    AMOSWAP.W
    AMOADD.W
    AMOXOR.W
    AMOAND.W
    AMOOR.W
    AMOMIN.W
    AMOMAX.W
    AMOMINU.W
    AMOMAXU.W
```

不实现：

```text
Zacas
Zabha
Zawrs
RV64 LR.D / SC.D / AMO*.D
misaligned atomicity granule
```

A-extension instruction address必须自然 word-aligned。

---

# 2. 当前平台假设

当前 SoC：

```text
single hart
strictly serial CPU
one architectural memory instruction at a time
blocking DCache
single-outstanding CPU bus bridge
no DMA
no second coherent hart
no other writable main-memory bus master
```

因此在当前平台中，CPU 可以通过：

```text
READ old value
compute
WRITE new value
```

实现 AMO，而不需要额外 AXI lock/coherence protocol。

关键原因不是“两个 AXI transaction 天生原子”，而是：

> 当前系统不存在能够插入这两个 transaction 之间、并对同一主存位置进行可观察写入的竞争 master。

这是当前 A-extension 正确性的明确平台前提。

如果未来增加：

```text
second hart
DMA
GPU/NPU master
debug memory writer
其他可写 DDR master
```

则必须重新设计：

- reservation invalidation；
- AMO RMW exclusion；
- cache coherence / shared atomic point。

当前阶段不为未来不存在的 master 增加复杂协议。

---

# 3. 核心原则：Reservation 必须绑定物理位置

当前 reservation 保存 effective address：

```text
reservation_addr_r = VA
```

这不足够严格。

例如：

```text
LR.W VA X -> PA A
page mapping changes
SFENCE.VMA
SC.W VA X -> PA B
```

如果只比较 VA，SC 可能错误成功到不同物理位置。

因此本阶段改为：

```text
reservation set = translated physical word
```

最简单实现：

```systemverilog
logic        reservation_valid_r;
logic [29:0] reservation_word_r;   // PA[31:2]
```

reservation set 精确为 4-byte word。

这是合法且最容易理解的 reservation granule。

---

# 4. Address Check 必须返回并锁存 checked PA

Architecture Foundation 已经拆分：

```text
architectural access
        ↓
       MMU
        ↓
physical request
```

但当前 cpu_mem 仍通过 core_top 直接使用 live `mmu_data_paddr` 发 physical request。

本阶段进一步完成这个 contract：

```text
mem_access_valid
mem_vaddr
mem_kind
        ↓
       MMU
        ↓
mem_access_ready
mem_access_paddr
        ↓
      cpu_mem latch
        ↓
     checked_paddr_r
        ↓
physical request
```

新增 cpu_mem 输入：

```systemverilog
input [31:0] mem_access_paddr;
```

在 `mem_access_ready` 时：

```systemverilog
checked_paddr_r <= mem_access_paddr;
```

之后该 instruction 的所有 physical phase 都只使用 `checked_paddr_r`。

---

# 5. Physical Request 必须显式携带 PA

cpu_mem 输出增加：

```text
phys_req_paddr
phys_req_valid
phys_req_write
phys_req_size
phys_req_wdata
```

core_top：

```text
cpu_mem.phys_req_paddr
        ↓
      DCache
```

不再：

```text
DCache <- live MMU response PA
```

这样一条 AMO：

```text
translation / permission check once
             ↓
         latch PA
             ↓
        READ same PA
             ↓
        WRITE same PA
```

物理地址在整个 RMW 生命周期内不可变化。

普通 LOAD/STORE/LR/SC 同样使用这一接口。

---

# 6. LR.W

LR.W 流程：

```text
LR.W
  |
  +-> alignment check
  |
  +-> ACCESS_LOAD translation / protection
  |
  +-> latch checked PA
  |
  +-> physical READ
  |
  +-> if read succeeds:
        rd = loaded word
        reservation_valid = 1
        reservation_word = checked PA[31:2]
```

如果 alignment/MMU/PMP/PMA/downstream access fault：

```text
no reservation is established
no register result retires
```

新 LR 成功时直接替换旧 reservation。

系统只保存一个 reservation。

---

# 7. SC.W

SC 必须先通过 store-class address/permission check，再检查 reservation。

流程：

```text
SC.W
  |
  +-> word alignment check
  |
  +-> ACCESS_STORE translation / protection
  |
  +-> latch checked PA
  |
  +-> compare reservation_word with checked PA[31:2]
        |
        +-> mismatch
        |     reservation_valid = 0
        |     rd = 1
        |     no physical write
        |
        +-> match
              reservation_valid = 0
              physical WRITE checked PA
              if write succeeds:
                  rd = 0
```

SC failure code固定：

```text
1
```

这是标准允许的 unspecified failure code。

任何 SC attempt 都清除当前 reservation，无论：

- success；
- normal reservation failure；
- 最终进入 trap。

---

# 8. SC permission-first rule

不能优化成：

```text
if reservation invalid:
    rd = 1
    skip MMU/PMP/PMA
```

正确顺序始终是：

```text
architectural STORE permission
        ↓
reservation check
```

因此 failed SC 仍可以：

- 触发 store page fault；
- 触发 store/AMO access fault；
- 产生合法的页表 A/D side effect。

---

# 9. Reservation alias 行为

使用 physical word 比较后：

```text
LR VA1 -> PA X
SC VA2 -> PA X
```

允许成功。

这是标准允许的行为。

不同 VA alias 不需要被人为强制失败。

反过来：

```text
LR VA -> PA X
SC same VA -> PA Y
```

必须失败，因为 physical reservation 不匹配。

---

# 10. Reservation invalidation policy

当前简单实现采用保守失效策略。

以下事件清除 reservation：

```text
any SC attempt
normal STORE completion
AMO completion
trap entry
reset
```

新 LR 成功会覆盖旧 reservation。

对普通同 hart store，无论是否命中 reservation word，都允许保守地清除 reservation。

这可能使 unconstrained LR/SC sequence 更容易失败，但不会破坏架构正确性。

不要为了更少 SC failure 引入 reservation snoop complexity。

---

# 11. Constrained LR/SC forward progress

当前单 hart平台不主动制造随机 SC failure。

对于满足 constrained LR/SC 条件的典型循环：

```text
LR.W
integer computation / forward control
SC.W same address
retry on failure
```

如果：

- 没有 trap；
- 没有 access fault；
- 没有平台外部 writer；

reservation 会保持到 SC，因此 SC 可以成功。

所以当前简单 reservation 实现天然满足本平台需要的 forward-progress 行为，不需要 retry counter、timeout 或复杂 reservation FSM。

---

# 12. AMO architectural class

所有 AMO 都是：

```text
mem_kind = MEM_AMO
access_class = ACCESS_STORE
```

即使第一 physical phase 是 READ，也不能变成 load-class fault。

因此：

```text
AMO page fault        -> cause 15
AMO access fault      -> cause 7
AMO address misalign  -> cause 6
```

保持 Unified Exception 当前 contract。

---

# 13. AMO execution

所有 RV32 AMO 使用同一 FSM：

```text
AMO
 |
 +-> word alignment check
 |
 +-> ACCESS_STORE translation / PMP / PMA
 |
 +-> latch checked PA
 |
 +-> physical READ
 |
 +-> old = read data
 |
 +-> new = amo_compute(old, rs2)
 |
 +-> physical WRITE same checked PA
 |
 +-> rd = old
```

只有 WRITE 成功后 instruction 才完成并退休。

如果 READ 或 WRITE 任一 physical phase 出现 downstream error：

```text
store/AMO access fault
no WB
```

---

# 14. AMO operation table

继续保留当前统一 `amo_compute`：

```text
AMOSWAP.W  new = rs2
AMOADD.W   new = old + rs2
AMOXOR.W   new = old ^ rs2
AMOAND.W   new = old & rs2
AMOOR.W    new = old | rs2

AMOMIN.W   new = signed_min(old, rs2)
AMOMAX.W   new = signed_max(old, rs2)
AMOMINU.W  new = unsigned_min(old, rs2)
AMOMAXU.W  new = unsigned_max(old, rs2)
```

RV32 下 writeback 即完整 32-bit old value，不涉及 RV64 的 word sign-extension规则。

---

# 15. DCache 与 AMO

继续使用现有 DCache policy：

```text
load/read:
    cacheable DDR hit/miss/refill

store/write:
    write-through
    no-write-allocate
    cache hit after successful backing write -> update cached word
```

AMO READ 可以：

- hit existing DCache line；
- miss 后 refill。

AMO WRITE：

- 必须先成功写 backing memory；
- 如果对应 line 已在 cache 中，再更新 cached copy。

因此当前 write-through DCache 不需要增加专用 atomic cache state。

---

# 16. aq / rl

当前 cpu_mem 使用：

```text
amo_aq || amo_rl
    -> MEM_AMO_FENCE
```

但 `MEM_AMO_FENCE` 只是额外等待一个 cycle，没有改变任何 memory visibility 或 ordering。

它不是实际 fence。

当前 CPU 已经天然执行：

```text
instruction N 完整结束
    before
instruction N+1 开始

memory transaction 完整 response
    before
memory instruction retires

one outstanding memory operation
```

因此当前实现比 RVWMO 对普通操作要求的顺序更强。

在这个微架构上：

> aq/rl 不需要额外硬件动作即可满足要求。

所以本阶段删除：

```text
MEM_AMO_FENCE
amo_ordered_r
id_exe_bus_t.amo_aq
id_exe_bus_t.amo_rl
exe_mem_bus_t.amo_aq
exe_mem_bus_t.amo_rl
```

Decode 仍然合法接受 aq/rl 任意编码。

不需要把 aq/rl bit 向后传播。

---

# 17. 不实现“假 fence”

不要用：

```text
one-cycle bubble
```

表示 acquire/release。

如果未来 CPU 引入：

- store buffer；
- non-blocking cache；
- multiple outstanding；
- speculative load；
- 多 hart；

则必须重新实现 aq/rl ordering。

在当前严格串行 CPU 中，不增加状态反而更准确。

---

# 18. Interrupt / Trap 与 atomic instruction

Controller 已经只在 architectural boundary 接受 interrupt。

因此：

```text
AMO READ
AMO compute
AMO WRITE
```

过程中不会插入普通 interrupt trap。

AMO 成功完成并进入 WB 后，才可能接受 interrupt。

同步 fault 仍可终止当前 atomic instruction。

Trap entry 清除 reservation。

这足以保证当前 single-hart LR/SC 的上下文切换安全性。

---

# 19. Physical bus atomicity 的边界

本阶段明确：

> AMO 的 READ+WRITE 原子性是当前 SoC 拓扑属性，不是 cpu_bus_bridge 提供的 AXI atomic transaction。

因此不要：

- 使用 AXI lock；
- 增加 cache lock line；
- 增加 bus semaphore；
- 增加 global atomic controller。

这些对当前单-master平台没有收益，只增加复杂度。

如果以后出现第二个 writable master，本假设立即失效，必须重新设计。

---

# 20. PMA 边界

A-extension 是否允许访问某个 physical region，不应在 cpu_mem 里硬编码。

后续 PMA 阶段负责定义：

```text
DDR
    atomic-capable = yes

BootROM
    atomic-capable = no

MMIO
    atomic-capable = no

unmapped
    atomic-capable = no
```

因此本阶段不要在 cpu_mem 复制 address map 做：

```text
if DDR then AMO allowed
else fault
```

A-extension 只提供正确的：

```text
mem_kind
access_class
checked PA
```

PMA 下一阶段根据这些信息决定 region legality。

在 PMA 完成前，“AMO 对 MMIO 的最终平台合法性”仍属于未完成平台功能，而不是 A-extension 本地逻辑。

---

# 21. PMP 边界

LR：

```text
ACCESS_LOAD
```

SC / AMO：

```text
ACCESS_STORE
```

PMP 后续直接使用统一 `access_class_t`。

cpu_mem 不解析 PMP config，也不增加 A-extension 专用 PMP 判断。

---

# 22. Misalignment

当前不支持 misaligned atomicity granule。

因此：

```text
LR.W / SC.W / AMO*.W
address[1:0] != 00
    -> synchronous exception
```

异常分类：

```text
LR.W      -> load address misaligned, cause 4
SC.W      -> store/AMO address misaligned, cause 6
AMO*.W    -> store/AMO address misaligned, cause 6
```

不做 misaligned atomic emulation。

---

# 23. Decode 语义

继续保持：

```text
opcode = AMO
funct3 = 010
```

LR.W 额外要求：

```text
rs2 = x0
```

否则按 illegal instruction 处理。

支持的 funct5 保持当前列表。

未知 funct5 不应进入 `MEM_AMO`。

aq/rl 位不参与 instruction identity，只作为 ordering annotation，因此任何合法组合都应 decode 成对应 A instruction。

---

# 24. Reservation Debug / State

reservation 保持 cpu_mem 内部微架构状态。

不新增 CSR。

也不需要把 reservation 暴露成跨模块 protocol。

如果保留 debug，最多提供：

```text
reservation_valid
reservation_paddr
```

但不是功能接口。

---

# 25. 建议的 cpu_mem 状态

删除 `MEM_AMO_FENCE` 后，状态可保持：

```text
MEM_IDLE
MEM_ACCESS
MEM_READ
MEM_WRITE
MEM_AMO_READ
MEM_AMO_WRITE
```

其中：

```text
MEM_READ
    normal LOAD

MEM_WRITE
    normal STORE

MEM_AMO_READ
    LR or AMO read phase

MEM_AMO_WRITE
    SC or AMO write phase
```

不用为每个 AMO funct5 单独增加 FSM state。

---

# 26. 典型时序

## LR.W

```text
MEM_IDLE
  -> MEM_ACCESS
  -> latch PA
  -> MEM_AMO_READ
  -> response
  -> set reservation(PA)
  -> WB(old)
```

## SC.W success

```text
MEM_IDLE
  -> MEM_ACCESS
  -> latch PA
  -> reservation match
  -> clear reservation
  -> MEM_AMO_WRITE
  -> response
  -> WB(0)
```

## SC.W failure

```text
MEM_IDLE
  -> MEM_ACCESS
  -> latch PA
  -> reservation mismatch
  -> clear reservation
  -> WB(1)
```

没有 physical read，也没有 physical write。

## AMO

```text
MEM_IDLE
  -> MEM_ACCESS
  -> latch PA
  -> MEM_AMO_READ
  -> compute
  -> MEM_AMO_WRITE same PA
  -> WB(old)
```

---

# 27. 需要修改的主要区域

主要：

- `core_bus_types.svh`
  - 删除 aq/rl stage fields；
- `cpu_decode.sv`
  - 保持 A decode；
  - 不再向后传播 aq/rl；
- `cpu_execute.sv`
  - 删除 aq/rl passthrough；
- `cpu_mem.sv`
  - latch checked PA；
  - reservation 改为 physical word；
  - 增加 phys_req_paddr；
  - 删除 MEM_AMO_FENCE；
  - 删除 amo_ordered；
- `core_top.sv`
  - MMU checked PA 接入 cpu_mem；
  - DCache PA 改接 cpu_mem.phys_req_paddr。

DCache、MMU、Controller、Trap 的核心结构不重写。

---

# 28. 不在本阶段修改

不要借 A-extension 收口扩大到：

- PMP matcher；
- PMA checker；
- MMIO atomic policy；
- Cache coherence；
- multi-hart；
- DMA；
- AXI atomic/lock；
- memory model优化；
- store buffer；
- non-blocking cache；
- CSR/Privilege cleanup；
- SoC address decoder。

这些不是当前 A-extension 本地职责。

---

# 29. Phase 7 完成后的 A-extension contract

最终：

```text
                    Architectural instruction
                            |
          +-----------------+-----------------+
          |                 |                 |
         LR                SC                AMO
          |                 |                 |
      LOAD-class        STORE-class       STORE-class
          |                 |                 |
          +-----------------+-----------------+
                            |
                        MMU/PMP/PMA
                            |
                       checked PA
                            |
              +-------------+-------------+
              |                           |
        reservation                  physical R/W
        physical word                     |
              |                           |
              +-------------+-------------+
                            |
                          DCache
                            |
                           AXI
```

关键不变量：

1. reservation 绑定 physical word；
2. SC 先 permission check，再 reservation check；
3. SC 任意 attempt 都使 reservation 失效；
4. AMO READ/WRITE 使用同一 checked PA；
5. AMO fault 始终是 store/AMO class；
6. aq/rl 由严格串行执行天然满足，不做假 fence；
7. 当前 AMO 原子性依赖 single writable master 平台假设；
8. atomic-capable region 由下一阶段 PMA 决定。

---

# 30. 后续路线

Phase 7 完成后，A-extension 本地语义应冻结。

下一阶段：

```text
PMP + PMA
    |
    +-> physical region attributes
    +-> R/W/X legality
    +-> atomic-capable
    +-> PTW PMP/PMA
    +-> MPRV / effective privilege
```

完成 PMP/PMA 后，RV32A 才拥有完整的平台访问边界。
