# CPU 代码简化重构：Final Platform & Completeness Cleanup

> 分支：`chp`  
> 前置阶段：Architecture Foundation、Unified Exception / Trap、A Extension Semantics、PMP + PMA、CSR / Privileged Architecture 已完成。  
> 本文定义最后一轮结构性开发：收口 Phase 9 剩余的 privileged correctness 尾巴、统一 SoC physical address map、清理平台层 legacy alias，并完成最后的明确 dead glue / stale comment 整理。完成后 core 与平台架构冻结。

---

# 1. 本阶段定位

当前 CPU core 的主要结构已经稳定：

```text
Decode
  ↓
Execute
  ↓
Memory
  ↓
MMU
  ↓
PMP / PMA
  ↓
Cache
  ↓
Bus
```

Trap / CSR 路径也已经稳定：

```text
exception_t
    ↓
Trap Manager
    ↓
Trap Router
    ↓
CSR Bank
```

本阶段不再进行新的 core architecture refactor。

只处理：

1. `mstatush` 最后的 CSR legality 尾巴；
2. xRET 后 interrupt 的 immediate reevaluation；
3. interconnect decoder 与 `soc_addr_map.svh` / PMA 的统一；
4. unmapped / read-only slave response 语义收口；
5. DTS 与 legacy address-map 描述清理；
6. 少量明确失效的注释、常量和 dead glue。

---

# 2. 结束目标

完成后：

```text
CPU architectural map
      =
PMA map
      =
system_top decoder
      =
platform description
```

并且：

```text
Core architecture       frozen
Memory architecture     frozen
Privileged architecture frozen
Platform address map    frozen
```

之后只允许针对 concrete correctness issue 做局部修复。

不再因为“文件较长”“还能拆模块”继续主动重构。

---

# 3. Phase 9 尾巴一：mstatush

当前 `csr_meta.sv` 把：

```text
mstatush
```

和：

```text
misa
mvendorid
marchid
mimpid
mhartid
mconfigptr
```

一起标记为 read-only。

这不符合当前选择的 CSR contract。

RV32 `mstatush` 是存在的 M-mode CSR。

本 core 不实现其中任何 writable capability，但：

> “字段固定为 0”不等于“CSR 本身是 read-only”。

---

# 4. mstatush 最终行为

`csr_meta.sv`：

```text
implemented = 1
min_priv    = M
read_only   = 0
```

`cpu_csr.sv`：

```text
read mstatush:
    return 0

write mstatush:
    accept instruction
    no state change
```

因此：

```text
CSRRW mstatush
CSRRS mstatush
CSRRC mstatush
immediate forms
```

只要 privilege 合法，都不能因为“写入 mstatush”而产生 illegal instruction。

不要新增 `r_mstatush`。

---

# 5. Phase 9 尾巴二：xRET 后 interrupt immediate reevaluation

当前：

```text
STATE_TRAP_RETURN
        ↓
      FETCH
        ↓
下一条 instruction
```

MRET / SRET 在 Trap Return cycle 更新：

```text
priv_mode
xIE / xPIE
xPP
MPRV
PC
```

因此 Trap Return 完成之后，interrupt eligibility 可能立即发生变化。

不能先开始执行返回地址上的一条新 instruction，再等它完成后处理已经 pending 的 interrupt。

---

# 6. 不在 FETCH 中直接动态 gate interrupt

不要简单改成：

```text
if_valid = STATE_FETCH && !interrupt_pending
```

原因：

`interrupt_pending` 可能在一个已经开始的 Fetch / translation / cache transaction 中途发生变化。

如果直接动态撤掉 `if_valid`，会把“architectural interrupt boundary”与“正在进行的 fetch transaction cancellation”混在一起。

当前设计没有必要引入这种耦合。

---

# 7. 新增显式 Return Boundary state

在 Controller 增加：

```text
STATE_RETURN_BOUNDARY
```

状态流：

```text
DECODE
  ↓
TRAP_RETURN
  ↓
RETURN_BOUNDARY
  ├─ interrupt_pending -> TRAP_ENTER
  └─ otherwise         -> FETCH
```

`STATE_RETURN_BOUNDARY`：

- 不发起 Fetch；
- 不发起 memory request；
- 不再次执行 xRET CSR update；
- 只在已经更新后的 `priv_mode + mstatus + mie/mip/mideleg` 上重新评估 `interrupt_pending`。

---

# 8. Trap Return 仍只退休一次

保持：

```text
trap_return_valid = STATE_TRAP_RETURN
```

只有这一 cycle：

- 更新 PC；
- 更新 privilege；
- 更新 mstatus；
- 计入 instruction retirement。

`STATE_RETURN_BOUNDARY` 不是一条 instruction，不产生 retire event。

---

# 9. CSR write 后 interrupt reevaluation

普通 CSR instruction 已经走：

```text
CSR_ACCESS
    ↓
WB
    ↓
interrupt boundary
```

因此 CSR 写入：

```text
mstatus
mie
mip
mideleg
```

后已经会在更新后的 CSR state 上重新评估 interrupt。

本阶段不为 CSR write 增加额外状态。

只补 xRET 这条绕过 WB 的路径。

---

# 10. 最终 SoC physical map

`soc_addr_map.svh` 是唯一 platform address source。

最终 implemented regions：

| Region | Base | Size |
|---|---:|---:|
| CLINT | `0x0200_0000` | `0x0001_0000` |
| SysStatus | `0x0400_0000` | `0x0000_1000` |
| PLIC | `0x0C00_0000` | `0x0100_0000` |
| GPIO | `0x1000_0000` | `0x0000_1000` |
| UART | `0x1000_8000` | `0x0000_1000` |
| SPI | `0x1000_C000` | `0x0000_1000` |
| DDR | `0x8000_0000` | `0x0800_0000` |
| BootROM | `0xFC00_0000` | `0x0000_8000` |

其他地址：

```text
unmapped
```

---

# 11. 删除 legacy address constants

删除：

```text
SOC_BOOTROM_LEGACY_MASK
SOC_BOOTROM_LEGACY_VALUE
```

如果没有实际消费者，同时删除：

```text
SOC_APB_RESERVED1_BASE
```

`SOC_APB_BASE` 如果只用于历史 broad decode，也删除。

平台 header 只描述真实 implemented region，不记录旧 alias。

---

# 12. system_top 使用 exact range decode

当前 decoder 包含：

```text
BootROM: top byte == FC
CLINT:   top byte == 02
APB:     top byte == 10
SysStatus: top byte == 04
```

这些必须删除。

新增一个简单本地 helper：

```systemverilog
function automatic logic addr_in_region(
    input logic [31:0] addr,
    input logic [31:0] base,
    input logic [31:0] size
);
```

语义：

```text
base <= addr < base + size
```

使用 33-bit endpoint，避免 `base + size` 溢出。

---

# 13. AW / AR decoder 共用同一逻辑

AW 与 AR 继续分别组合计算 slave select，但必须使用完全相同的 region predicate。

逻辑顺序建议固定：

```text
DDR
BootROM
PLIC
CLINT
GPIO/UART/SPI -> APB Bridge
SysStatus
Default
```

实际这些 window 不重叠，所以顺序不是 architectural priority。

保持当前 slave index：

```text
0 DDR
1 BootROM
2 PLIC
3 CLINT
4 APB
5 SysStatus
6 Default
```

不要为了最后 cleanup 重新编号整个 mux。

---

# 14. APB Bridge 顶层只接受真实 device window

APB Bridge 不再接受：

```text
0x1000_0000 .. 0x10FF_FFFF
```

只在以下任一 range 命中时选中 APB slave：

```text
GPIO
UART
SPI
```

即：

```text
is_apb_addr =
    in_gpio ||
    in_uart ||
    in_spi
```

因此：

```text
0x1000_4000
```

以及 APB 大窗口中的其他 hole 都直接进入 Default slave。

---

# 15. removed APB timer 不再是 architectural device

当前 `0x1000_4000` 的旧 Timer slot 已被移除。

最终行为：

```text
0x1000_4000 + ...
    -> not APB
    -> Default AXI slave
    -> DECERR
```

不再：

```text
APB slot1
    -> OKAY / zero
```

平台层不应该把不存在的设备伪装成成功访问。

---

# 16. APB slot1 作为 defensive unreachable path

`apb_perips.sv` 内部仍有四个 slot。

为了避免更大范围重排 UART/SPI slot 编号，继续保留 slot1 wiring。

但把 slot1 改成：

```text
PREADY  = 1
PSLVERR = 1
PRDATA  = 0
```

正常顶层 exact decoder 下不会到达它。

如果未来 wiring 错误或其他 master 绕过顶层 address filter，slot1 也不会静默返回 OKAY。

---

# 17. PLIC range

PLIC 当前 intended range：

```text
0x0C00_0000
+
16 MiB
```

也就是：

```text
0x0C00_0000 .. 0x0CFF_FFFF
```

因此当前 top-byte decode 在数值上碰巧等价。

但仍改成统一：

```text
addr_in_region(addr, SOC_PLIC_BASE, SOC_PLIC_SIZE)
```

不要保留例外式写法。

---

# 18. CLINT range

CLINT 只接受：

```text
0x0200_0000 .. 0x0200_FFFF
```

不是整个：

```text
0x02xx_xxxx
```

这与 DTS：

```text
reg = <0x02000000 0x00010000>
```

保持一致。

---

# 19. BootROM range

BootROM 实际：

```text
8192 × 32-bit word
= 32 KiB
```

因此只有：

```text
0xFC00_0000 .. 0xFC00_7FFF
```

进入 BootROM slave。

`0xFC00_8000` 及以上直接 Default / DECERR。

这与 PMA 已经采用的范围一致。

---

# 20. SysStatus range

SysStatus 只接受：

```text
0x0400_0000 .. 0x0400_0FFF
```

不再整个 `0x04xx_xxxx` 路由给该 slave。

当前 platform contract 保留一个 4 KiB MMIO page。

---

# 21. DDR range

DDR 保持：

```text
0x8000_0000 .. 0x87FF_FFFF
```

即 128 MiB。

继续使用：

```text
SOC_DDR_BASE
SOC_DDR_SIZE
```

不改变 MIG / AXI DDR wrapper。

---

# 22. Default slave

现有 `axi4lite_default_slave.sv` 已经具备正确职责：

```text
read  -> DECERR + zero data
write -> DECERR
```

保持不变。

所有 exact map 之外的 address 都必须落到它。

---

# 23. Read-only mapped slave 的 write response

两个 mapped slave 本身是 read-only：

```text
BootROM
SysStatus
```

当前它们会：

```text
write -> silently OKAY
```

虽然 CPU PMA 已经会提前阻止这些写操作，但 slave 本身的 protocol semantics 仍不应谎报成功。

改为：

```text
write to mapped read-only slave
    -> AXI SLVERR
```

不是 DECERR。

理由：

```text
address decode succeeded
but requested operation is unsupported
```

因此属于 slave error，而不是 decode error。

---

# 24. BootROM write behavior

`axi4lite_bootrom.sv`：

保留：

- AW / W independent handshake；
- B channel response；
- BRAM WE permanently 0。

只改：

```text
BRESP = SLVERR
```

以及对应注释。

不要删除 write channel，否则会破坏 AXI-Lite slave completeness。

---

# 25. SysStatus write behavior

`axi4lite_sys_status.sv`：

继续接受 AW + W 并完成 response。

改为：

```text
BRESP = SLVERR
```

SysStatus register bank保持 read-only。

---

# 26. SysStatus register decode

当前内部使用：

```text
s_axi_araddr[3:0]
```

判断 offset 0。

这会让：

```text
+0x00
+0x10
+0x20
...
```

都 alias 到 STATUS register。

改成真实 4 KiB page offset decode：

```text
offset = s_axi_araddr[11:0]

offset == 12'h000:
    STATUS
otherwise:
    zero
```

当前不需要为未知 register offset 返回 error。

mapped page 内 reserved offset：

```text
read -> zero / OKAY
```

即可。

只消除无意的 16-byte register mirroring。

---

# 27. APB peripheral address ownership

GPIO / UART / SPI 继续各自使用现有 register decode。

本阶段不重构 peripheral internals。

顶层 exact 4 KiB window已经保证：

```text
device cannot be reached through neighboring 16 KiB slot aliases
```

APB `PSELx` 的 slot decode继续保留。

---

# 28. PMA 与 interconnect 一致性

Phase 8 已经规定：

```text
PMA exact region
```

本阶段完成后：

```text
PMA says mapped
    <=> system_top routes to implemented slave

PMA says unmapped
    => system_top routes Default
```

对于 CPU master，大多数非法 access 会在 PMA 前置拦截。

但 interconnect仍必须独立拥有正确地址语义，不能依赖“CPU 应该不会发这种请求”。

---

# 29. DTS 清理

`linux/dts/simplecpu.dts` 当前主要真实节点已经与最终 map一致：

```text
memory
CLINT
PLIC
UART
GPIO
SPI
```

删除不存在的：

```text
apb_timer0: timer@10004000
```

即使它当前 `status = "disabled"`，也不应继续描述一个已经从 RTL 移除的设备。

---

# 30. DTS 保持不新增 SysStatus

SysStatus 是当前 FPGA/platform debug/status MMIO。

如果 software stack 没有 driver contract，本阶段不为了“地址表完整”新增 DTS node。

DTS只描述当前 OS 有意义的设备。

---

# 31. stale address-map comments

清理 `system_top.sv` 中类似：

```text
addr[31:24] == 8'hFC
addr[31:24] == 8'h02
addr[31:24] == 8'h10
```

的旧说明。

改为真实：

```text
base + size
```

描述。

不要保留“legacy decode” narrative。

---

# 32. 最后 hygiene 范围

只处理明确满足以下条件的内容：

```text
unused constant
unused wire
dead output
stale bug comment
stale module name comment
legacy address-map comment
removed peripheral description
```

不做：

```text
pure style rewrite
mass formatting
rename every signal
split large module
move code only for aesthetics
```

---

# 33. core_top / system_top 不再因行数拆分

`core_top.sv` 约九百多行。

`system_top.sv` 更长。

这本身不是重构理由。

它们当前主要承担：

```text
core_top:
    explicit module wiring

system_top:
    CDC
    explicit AXI channel routing
    slave mux
    platform wiring
```

在当前朴素架构中，显式 wiring 比增加多层 wrapper 更容易审计。

保持。

---

# 34. 不重写 interconnect

当前 system interconnect 的 contract：

```text
one outstanding write
one outstanding read
route captured at AW / AR handshake
response follows latched route
```

与 CPU single-outstanding memory system匹配。

本阶段只改 address selection predicate。

不要：

- 引入 AXI crossbar IP；
- 增加 arbitration layer；
- 改 transaction concurrency；
- 重写 CDC；
- 改 AW/W independent handling。

---

# 35. 不修改 PMA

`pma_checker.sv` 的 region table已经是最终 architectural map。

本阶段应让 system_top 向 PMA 对齐。

不要反过来扩大 PMA 来兼容 legacy decoder。

---

# 36. 不修改 PMP / MMU / Cache

本阶段不动：

```text
PMP matcher
PMP CSR semantics
MMU FSM
TLB
PTW
ICache policy
DCache policy
cpu_bus_bridge
```

除非接口因为删除明确 dead glue 必须发生机械变化。

---

# 37. Controller 唯一 semantic change

Controller只增加：

```text
STATE_RETURN_BOUNDARY
```

其他状态和 transition 不重新设计。

目标状态片段：

```text
STATE_TRAP_RETURN:
    next = STATE_RETURN_BOUNDARY

STATE_RETURN_BOUNDARY:
    next = interrupt_pending ? STATE_TRAP_ENTER : STATE_FETCH
```

`STATE_RETURN_BOUNDARY` 不产生任何 functional request signal。

---

# 38. CSR 唯一 semantic change

CSR 部分只补：

```text
mstatush:
    writable CSR encoding
    read zero
    write ignored
```

不重新打开 Phase 9 做第二轮 CSR redesign。

---

# 39. system_top exact decoder 建议形式

推荐：

```systemverilog
wire aw_is_ddr       = addr_in_region(cdc_awaddr, SOC_DDR_BASE, SOC_DDR_SIZE);
wire aw_is_bootrom   = addr_in_region(...);
wire aw_is_plic      = addr_in_region(...);
wire aw_is_clint     = addr_in_region(...);
wire aw_is_gpio      = addr_in_region(...);
wire aw_is_uart      = addr_in_region(...);
wire aw_is_spi       = addr_in_region(...);
wire aw_is_sysstatus = addr_in_region(...);
wire aw_is_apb       = aw_is_gpio || aw_is_uart || aw_is_spi;
```

AR 同样。

然后 slave select只引用这些 named predicate。

不要在 ternary chain 中重复硬编码 base/size arithmetic。

---

# 40. 不增加独立 address decoder module

当前只存在一个 system-level master decoder。

为这一次 cleanup 新增：

```text
soc_decoder.sv
```

收益很小，反而增加接口。

使用：

```text
soc_addr_map.svh
+
system_top local addr_in_region()
```

足够。

如果未来出现多个真正独立 master/crossbar，再考虑独立 decoder。

---

# 41. 最终 platform failure semantics

完成后：

```text
CPU violates privilege/page/PMP/PMA
    -> architectural access fault before AXI

mapped writable device
    -> normal AXI/APB transaction

mapped read-only device write
    -> AXI SLVERR

unmapped physical address
    -> AXI DECERR

removed APB slot
    -> unreachable from normal top decode
       defensive PSLVERR if reached
```

各层职责清楚，不再依赖“静默 OKAY”。

---

# 42. 最终 architecture freeze

本阶段结束后冻结：

```text
Instruction decode
Controller
Datapath
M-extension
A-extension
Exception / Trap
CSR / Privileged
MMU / TLB / PTW
PMP / PMA
ICache / DCache
CPU bus bridge
AXI CDC
System interconnect topology
SoC physical map
PLIC / CLINT / APB placement
```

之后不再规划新的 Phase 级架构重构。

---

# 43. 后续维护原则

后续只接受两类修改。

第一类：

```text
concrete correctness bug
```

例如某个 ISA / privileged / AXI 行为被明确证明错误。

第二类：

```text
局部实现清理
```

前提是：

- 不改变稳定 module boundary；
- 不引入新的 abstraction layer；
- 明显降低复杂度；
- 有明确现实收益。

不要再建立：

```text
Phase 11
Phase 12
...
```

去追求无限的“代码更漂亮”。

---

# 44. 本阶段主要文件

主要修改：

```text
src/rtl/core/csr_meta.sv
    mstatush legality

src/rtl/core/cpu_controller.sv
    RETURN_BOUNDARY

src/rtl/soc_addr_map.svh
    delete legacy constants

src/rtl/system_top.sv
    exact region decode
    remove broad aliases

src/rtl/apb/perips/apb_perips.sv
    reserved slot defensive error

src/rtl/axi/axi4lite_bootrom.sv
    read-only write -> SLVERR

src/rtl/axi/axi4lite_sys_status.sv
    read-only write -> SLVERR
    exact register offset decode

linux/dts/simplecpu.dts
    remove removed APB timer node
```

以及仅因上述变化产生的明确 dead glue/comment cleanup。

---

# 45. 明确不做

本阶段不做：

```text
RV64 migration
pipeline
superscalar
out-of-order
branch predictor
store buffer
non-blocking cache
cache coherence
multi-hart
DMA
new ISA extension
new privileged extension
selective SFENCE.VMA
vectored trap
new interconnect
new peripheral
power-management FSM
```

这些已经超出当前 CPU 的设计目标。

---

# 46. 最终设计原则

项目最终保持：

> **功能完整，微架构朴素。**

这里的“朴素”不是：

```text
删除 MMU
删除 TLB
删除 Cache
删除 PMP
删除 privilege
```

而是：

```text
每一层都存在
每一层职责明确
跨层特殊 glue 尽量少
同一语义只有一个 owner
没有为了形式美观增加不必要 abstraction
```

完成本阶段后，主动架构重构到此结束。
