# CPU 代码简化重构：CSR / Privileged Architecture

> 分支：`chp`  
> 前置阶段：Architecture Foundation、Unified Exception / Trap、A Extension Semantics、PMP + PMA 已完成。  
> 本文定义 Phase 9：CSR / Privileged Architecture 收口。目标是完成 M/S/U privileged semantics、消除 CSR 合法性重复定义，并把 trap entry / xRET / status / delegation / satp 等行为整理成稳定、明确的架构契约。

---

# 1. 本阶段定位

经过前面阶段后，core 的主要数据路径已经稳定：

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

异常路径也已经稳定：

```text
stage exception_t
      ↓
Trap manager
      ↓
Trap router
```

当前最后一个仍然明显包含重复知识和历史 glue 的核心区域是：

```text
cpu_decode.sv
cpu_csr_interface.sv
cpu_csr.sv
cpu_trap_router.sv
cpu_trap_csr.sv
```

主要问题：

- CSR 地址和合法性在 Decode 与 CSR 模块各维护一份；
- `mstatus` 仍允许一些当前硬件并不存在的 extension-state 字段被写入；
- `MPP=2'b10` reserved encoding 尚未 WARL sanitize；
- SRET 可以合法从 M-mode 执行，但当前 Trap Return path 仍用“当前 privilege”推断返回类型；
- `satp` 仍直接保存 raw write value；
- `mip/sip` 的软件 pending 与硬件 pending 通过一个镜像寄存器混在一起；
- `mcounteren/scounteren` 未限制到实际实现的 counter bits；
- Trap Router 的 status update 使用大段 bit concatenation，可读性较差；
- PTW non-leaf G inheritance 尚未补齐。

本阶段是最后一轮中等规模的 core semantic cleanup。

完成后，CSR/Privileged/Trap 结构应冻结。

---

# 2. 目标 privileged profile

本 core 明确实现：

```text
RV32
M-mode
S-mode
U-mode

Sv32
PMP
A-extension
Zicsr
Zifencei
```

不实现：

```text
H
N / user interrupts
Sstc
AIA
Smepmp
Smstateen
Smcdeleg
Smcntrpmf
Svinval
Svpbmt
vector / floating-point state
big-endian execution
```

`misa` 保持只读：

```text
RV32IMASU
```

Zicsr / Zifencei 不通过 `misa` 字母位表示。

---

# 3. CSR 定义必须只有一个 source of truth

新增：

```text
src/rtl/core/csr_defs.svh
src/rtl/core/csr_meta.sv
```

`csr_defs.svh` 只保存 CSR address 常量和少量固定 mask。

例如：

```text
CSR_SSTATUS
CSR_SIE
CSR_STVEC
...
CSR_MSTATUS
CSR_MISA
...
CSR_PMPCFG0
...
```

删除 `cpu_decode.sv` 和 `cpu_csr.sv` 中各自维护的一套 localparam CSR 地址。

---

# 4. csr_meta

新增小型 combinational module：

```systemverilog
module csr_meta(
    input  [11:0] addr,

    output        implemented,
    output priv_mode_t min_priv,
    output        read_only,

    output        is_counter_alias,
    output [1:0]  counter_index
);
```

它只描述静态 metadata。

例如：

```text
cycle/time/instret:
    implemented = 1
    min_priv = U
    read_only = 1
    counter_index = CY/TM/IR

mstatus:
    implemented = 1
    min_priv = M
    read_only = 0

misa:
    implemented = 1
    min_priv = M
    read_only = 1

satp:
    implemented = 1
    min_priv = S
    read_only = 0
```

runtime privilege policy 不放进 `csr_meta`。

---

# 5. CSR legality 只在 Decode 判定

Decode 对 CSR instruction 统一做：

```text
implemented?
current privilege >= min_priv?
read-only CSR is being written?
counter access allowed?
TVM special rule?
```

失败统一形成：

```text
illegal instruction
cause = 2
```

`cpu_csr` 不再承担一套重复的 `csr_addr_valid / csr_access_ok` policy。

删除：

```text
cpu_csr.csr_addr_valid
cpu_csr.csr_access_ok

cpu_csr_interface.csr_access_ok
cpu_trap_csr.csr_access_ok
core_top.csr_access_ok
```

CSR storage 模块只接受已经合法的 CSR operation。

---

# 6. privilege comparison

不要通过 raw 2-bit 数值随意比较 privilege。

统一显式语义：

```text
M can access M/S/U CSR
S can access S/U CSR
U can access U CSR
```

reserved privilege encoding `2'b10` 不参与正常运行。

可以在 `core_bus_types.svh` 提供一个小 helper：

```systemverilog
function automatic logic priv_at_least(
    input priv_mode_t current,
    input priv_mode_t required
);
```

只处理 U/S/M 三种合法值。

---

# 7. Counter CSR 权限

当前实现的 counter aliases：

```text
cycle / cycleh
time / timeh
instret / instreth
```

counter index：

```text
0 = cycle
1 = time
2 = instret
```

权限：

```text
M:
    always accessible

S:
    requires corresponding mcounteren bit

U:
    requires mcounteren AND scounteren
```

`mcounteren` 与 `scounteren` 只有 bits `[2:0]` 实现。

软件写入时：

```text
stored_value = write_data & 32'h0000_0007
```

bits `31:3` 读回 0。

不增加 HPM counter。

---

# 8. mcountinhibit

本 core 不实现 `mcountinhibit`。

行为视为：

```text
mcountinhibit = 0
```

即：

```text
mcycle always increments while cycle_en
minstret increments on architectural retirement
```

不要仅为了形式完整增加一个没有需求的 CSR。

---

# 9. mstatus：只实现真实存在的字段

当前 integer-only core 没有：

```text
F state
V state
other extension state
big-endian mode
hypervisor state
```

所以 `mstatus` 只保留以下可写字段：

```text
TSR   bit 22
TW    bit 21
TVM   bit 20
MXR   bit 19
SUM   bit 18
MPRV  bit 17

MPP   bits 12:11

SPP   bit 8
MPIE  bit 7
SPIE  bit 5
MIE   bit 3
SIE   bit 1
```

其余未实现字段读 0、写忽略。

---

# 10. FS / VS / XS / SD

当前不实现 F、V 或其他 stateful user extension。

因此选择最简单合法行为：

```text
FS = 00
VS = 00
XS = 00
SD = 0
```

全部 read-only zero。

删除当前通过 `mstatus/sstatus` 写 FS/XS 的逻辑。

这样软件不会误以为存在需要保存的 floating/vector/extension state。

---

# 11. Endianness fields

当前 CPU 全部 little-endian。

因此所有 endianness WARL field 选择固定为：

```text
little-endian
```

对应 field 读回 0，写 1 不生效。

`mstatush` 在当前实现中保持只读 0。

不引入 big-endian datapath。

---

# 12. MPP WARL

`MPP` 支持：

```text
00 U
01 S
11 M
```

`10` 为 reserved encoding。

软件写 `mstatus.MPP` 时统一 sanitize：

```text
00 -> U
01 -> S
11 -> M
10 -> U
```

选择 U 作为非法 encoding 的 deterministic WARL legalization。

不要让 `priv_mode_t'(2'b10)` 进入 core。

---

# 13. sstatus 是 mstatus 的受限 view

`sstatus` 不单独保存状态。

读回只暴露当前实现支持的 supervisor-visible fields：

```text
MXR
SUM
SPP
SPIE
SIE
```

其他字段：

```text
FS/VS/XS = 0
UBE = 0
SD = 0
```

写 `sstatus` 只能修改：

```text
MXR
SUM
SPP
SPIE
SIE
```

不能修改：

```text
MPRV
MPP
MPIE
MIE
TVM
TW
TSR
```

---

# 14. xIE / xPIE / xPP trap-entry rule

Trap 到 M：

```text
mepc   = exception/interrupt EPC
mcause = cause
mtval  = tval

MPP  = previous privilege
MPIE = MIE
MIE  = 0
```

Trap 到 S：

```text
sepc   = exception/interrupt EPC
scause = cause
stval  = tval

SPP  = previous privilege == S
SPIE = SIE
SIE  = 0
```

Trap 从 M-mode 发生时永远不会 delegation 到 S。

现有 Unified Trap 结构继续保留。

---

# 15. MRET

MRET 只允许在 M-mode 执行。

执行：

```text
new_priv = MPP
pc = mepc

MIE  = MPIE
MPIE = 1
MPP  = U
```

如果：

```text
new_priv != M
```

则：

```text
MPRV = 0
```

`mepc[1:0]` 当前 IALIGN=32，因此读写时 low 2 bits 保持 0。

---

# 16. SRET 可以从 S 或 M 执行

这是当前实现需要修正的明确语义。

SRET legal privilege：

```text
S-mode
M-mode
```

U-mode 执行 SRET：

```text
illegal instruction
```

如果：

```text
current privilege = S
AND mstatus.TSR = 1
```

则 SRET：

```text
illegal instruction
```

TSR 不阻止 M-mode 执行 SRET。

---

# 17. Trap Return 不能再根据 current privilege 猜类型

当前：

```text
STATE_TRAP_RETURN
```

只有一个状态，而后续逻辑通过 current privilege 猜这是 MRET 还是 SRET。

这种方式无法正确表示：

```text
M-mode executing SRET
```

因此新增：

```systemverilog
typedef enum logic [1:0] {
    RET_NONE = 2'd0,
    RET_M    = 2'd1,
    RET_S    = 2'd2
} trap_return_kind_t;
```

Controller 在 Decode 接受：

```text
MRET -> latch RET_M
SRET -> latch RET_S
```

进入 `STATE_TRAP_RETURN` 后继续保持该 kind。

---

# 18. Trap Router 显式接收 return kind

Trap Router 改为：

```text
trap_return_valid
trap_return_kind
```

不再使用：

```text
mret_req inferred from current M
sret_req inferred from current S
```

目标：

### RET_M

```text
trap_pc = mepc
target_priv = MPP
status update bank = M
```

### RET_S

```text
trap_pc = sepc
target_priv = SPP ? S : U
status update bank = S
```

这使：

```text
M-mode SRET
```

能够正确返回到 S/U。

---

# 19. target privilege 与 status bank 分开

当前 `hw_target_priv` 同时被当成：

```text
resulting privilege
which status stack to update
```

这两个概念在 M-mode SRET 时不同。

因此分离：

```text
target_priv
    trap/xRET 后实际 privilege

hw_status_priv
    本次 hardware CSR update 属于 M stack 还是 S stack
```

规则：

```text
trap to M:
    target_priv = M
    hw_status_priv = M

trap to S:
    target_priv = S
    hw_status_priv = S

MRET:
    target_priv = MPP
    hw_status_priv = M

SRET:
    target_priv = SPP ? S : U
    hw_status_priv = S
```

`core_top` 只使用 `target_priv` 更新当前 privilege。

`cpu_csr` 只使用 `hw_status_priv` 选择 M/S status update。

---

# 20. SRET state update

SRET：

```text
new_priv = SPP ? S : U
pc = sepc

SIE  = SPIE
SPIE = 1
SPP  = U
```

如果 SRET 是从 M-mode 执行，则它会离开 M-mode，因此：

```text
MPRV = 0
```

为了简单且 deterministic，本实现可以在所有 SRET 上清 MPRV。

这不会改变正常 S-mode software 的可见行为。

---

# 21. Trap Router status update 改成 named field logic

删除当前大段：

```systemverilog
{csr_mstatus[31:13], ... }
```

形式的 status concatenation。

改为：

```text
mstatus_on_trap_to_m
mstatus_on_trap_to_s
mstatus_on_mret
mstatus_on_sret
```

每个 combinational block：

1. 从当前 `csr_mstatus` 拷贝；
2. 只修改对应 named bit；
3. 输出新的 status。

这样可读性明显高于依赖 bit 拼接位置。

---

# 22. mtvec / stvec

当前实现继续选择：

```text
MODE = Direct only
```

软件写：

```text
MODE=0 -> 接受
MODE=1/其他 -> WARL legalize 为 MODE=0
```

保存：

```text
{write_data[31:2], 2'b00}
```

不实现 Vectored mode。

Trap target：

```text
M trap -> mtvec.BASE
S trap -> stvec.BASE
```

interrupt 与 synchronous exception 都使用同一 BASE。

这是本 core 的明确 WARL 实现选择，不属于功能缺失。

---

# 23. mepc / sepc

当前没有 C extension：

```text
IALIGN = 32
```

因此：

```text
mepc[1:0] = 00
sepc[1:0] = 00
```

软件写 xepc 时 low 2 bits 清零。

hardware trap entry 写入的 EPC 本身也应满足当前 instruction alignment contract。

---

# 24. mcause / scause

保持 32-bit可读写 register。

hardware trap entry：

```text
interrupt:
    bit31 = 1
    code = interrupt cause

exception:
    bit31 = 0
    code = exception cause
```

不增加 unsupported cause CSR logic。

software write 保持当前简单实现。

---

# 25. mtval / stval

hardware trap write继续由 unified `exception_t` 提供：

```text
illegal instruction -> instruction bits
address/page/access fault -> faulting VA
ecall/ebreak -> 0
interrupt -> 0
```

software write保持 full 32-bit。

physical PA 不进入 xTVAL。

---

# 26. medeleg

当前 core 实际可能产生的主要 synchronous exceptions：

```text
0   instruction address misaligned
1   instruction access fault
2   illegal instruction
3   breakpoint
4   load address misaligned
5   load access fault
6   store/AMO address misaligned
7   store/AMO access fault
8   U-mode ecall
9   S-mode ecall
11  M-mode ecall
12  instruction page fault
13  load page fault
15  store/AMO page fault
```

本实现继续选择 writable mask：

```text
0x0000_B1FF
```

即：

```text
0..8
12
13
15
```

可 delegated。

明确不允许：

```text
S-mode ECALL cause 9
M-mode ECALL cause 11
reserved cause 10/14
```

其中不 delegating S-mode ECALL 保持 SBI/OpenSBI 路径简单：

```text
S ECALL -> M
```

这属于 implementation-supported delegation subset。

---

# 27. mideleg

当前实现的 interrupt model：

```text
SSIP 1
MSIP 3
STIP 5
MTIP 7
SEIP 9
MEIP 11
```

只允许 supervisor-level interrupt delegation bits：

```text
mideleg writable mask = 0x0000_0222

SSIP
STIP
SEIP
```

Machine-level：

```text
MSIP
MTIP
MEIP
```

不通过当前 platform 的 `mideleg` 下放。

保持现有 PLIC dual-context + software-injected supervisor pending 设计。

---

# 28. mie / sie

`mie` 只实现：

```text
SSIE
MSIE
STIE
MTIE
SEIE
MEIE
```

mask：

```text
0x0000_0AAA
```

`sie` 继续是 `mie` 的 delegated view：

```text
sie = mie & mideleg & 0x0000_0222
```

S-mode 写 `sie` 只修改当前 delegated supervisor bits。

不增加独立 supervisor interrupt-enable bank。

---

# 29. mip / sip 清理

当前 `r_mip` 每 cycle 从硬件 pending + `r_sip` 重新构造，结构较绕。

删除 `r_mip` storage。

只保留软件可注入部分：

```text
r_sip_sw[9]   SEIP software portion
r_sip_sw[5]   STIP software portion
r_sip_sw[1]   SSIP software portion
```

组合生成：

```text
mip_value:
    MEIP = ext_meip
    SEIP = ext_seip OR r_sip_sw[9]
    MTIP = ext_mtip
    STIP = r_sip_sw[5]
    MSIP = ext_msip
    SSIP = r_sip_sw[1]
```

然后：

```text
csr_mip = mip_value
csr_sip = mip_value & mideleg & 0x222
```

这样 hardware pending 与 software injected pending 的所有权更清楚。

---

# 30. mip / sip software write

M-mode 写 `mip`：

```text
只允许修改 software portion:
    SEIP software portion
    STIP
    SSIP
```

硬件来源：

```text
MEIP
MTIP
MSIP
external SEIP
```

不可被 CSR write 直接覆盖。

S-mode 写 `sip`：

```text
只修改当前 mideleg 暴露的 supervisor software portion
```

保留当前平台行为，不引入 Sstc。

---

# 31. Interrupt arbitration

Trap Router 继续保持当前 supported interrupt priority。

M-target priority：

```text
MEI
MSI
MTI
SEI
SSI
STI
```

S-target priority：

```text
SEI
SSI
STI
```

higher-privilege target 优先于 lower-privilege target。

global enable rule 保持：

```text
target=M:
    current<M -> globally enabled
    current=M -> require MIE

target=S:
    current=U -> globally enabled
    current=S -> require SIE
    current=M -> cannot take S trap
```

不借本阶段重写 interrupt subsystem。

---

# 32. satp

RV32 `satp`：

```text
bit31      MODE
bits30:22  ASID
bits21:0   PPN
```

当前实现支持：

```text
MODE=0 Bare
MODE=1 Sv32
ASIDLEN=9
```

所有 9-bit ASID 保留。

---

# 33. satp WARL

为避免 Bare + nonzero fields 的 unspecified pattern，本实现采用 deterministic legalization：

```text
write MODE=0:
    satp = 0

write MODE=1:
    satp = write_data
```

因此 Bare 下：

```text
ASID = 0
PPN = 0
```

Sv32 下完整保存：

```text
ASID[8:0]
PPN[21:0]
```

---

# 34. satp 与 TVM

S-mode：

```text
mstatus.TVM = 1
```

时：

```text
任何 satp CSR access
SFENCE.VMA
```

产生 illegal instruction。

M-mode 不受 TVM 影响。

---

# 35. SFENCE.VMA privilege fix

SFENCE.VMA legal：

```text
M-mode
S-mode when TVM=0
```

U-mode 执行：

```text
illegal instruction
```

当前 Decode 需要补上 U-mode privilege violation。

---

# 36. SFENCE.VMA 的实现策略

当前 MMU/TLB 只有 16 entries，严格串行。

继续采用 conservative：

```text
ignore rs1
ignore rs2
always full TLB flush
```

包括：

```text
global entries
all ASIDs
all VPNs
```

这只降低性能，不改变 architecture correctness。

不为了 selective flush 增加 TLB search/invalidate complexity。

---

# 37. satp write 与 TLB

当前 MMU：

```text
satp changed
    -> conservative full flush
```

继续保留。

规范不要求 satp write 自动 flush，但 implementation 可以主动丢弃 translation cache entry。

因此当前行为是合法的 conservative implementation。

---

# 38. Sv32 non-leaf G inheritance

修正 PTW 的一个已知 completeness issue。

当前：

```text
walk_g = leaf pte.G
```

但 non-leaf PTE 的 G bit 应使其下所有映射都 global。

在 PTW 增加：

```systemverilog
logic global_seen_r;
```

每次 walk 开始：

```text
global_seen_r = 0
```

若 L1 non-leaf：

```text
global_seen_r |= pte.G
```

最终 leaf：

```text
walk_g = global_seen_r | leaf_pte.G
```

TLB 继续使用现有：

```text
G=1 -> ignore ASID on lookup
```

不修改 MMU state machine。

---

# 39. SUM / MXR

保持当前 Sv32 semantics。

`SUM`：

```text
S data access to U page:
    SUM=0 -> fault
    SUM=1 -> allowed if R/W permits

S instruction fetch from U page:
    always fault
```

`MXR`：

```text
load from X-only page:
    MXR=1 -> readable
    MXR=0 -> fault
```

U-mode不使用 SUM。

M-mode直接访问 physical memory时不受 Sv32 page permission。

MPRV 进入 S/U effective privilege 时继续通过现有 MMU path应用这些规则。

---

# 40. TVM / TW / TSR

保持并明确：

## TVM

只影响 S-mode：

```text
satp access
SFENCE.VMA
```

立即 illegal。

## TW

本 core WFI 实现为 legal NOP-like instruction。

当：

```text
TW=1
AND current privilege != M
```

WFI立即产生 illegal instruction。

当 TW=0：

```text
WFI retires like NOP
```

## TSR

只影响 S-mode SRET：

```text
TSR=1 -> illegal
```

M-mode SRET 不受 TSR 影响。

---

# 41. WFI

继续选择最简单合法实现：

```text
WFI = NOP-like
```

不增加：

- clock gating；
- sleep state；
- wakeup state machine。

当前 interrupt boundary 已在 Unified Trap 阶段补齐。

---

# 42. misa

`misa` 保持 read-only：

```text
0x4014_1101
```

即：

```text
MXL = RV32
A
I
M
S
U
```

软件写 `misa` 不改变任何 ISA feature。

Decode metadata 把它标记为 read-only CSR。

---

# 43. Machine identity CSR

继续保持：

```text
mvendorid   = 0
marchid     = 0
mimpid      = 0
mhartid     = 0
mconfigptr  = 0
```

均 read-only。

当前 single-hart platform：

```text
mhartid = 0
```

不额外引入 platform ID CSR。

---

# 44. Scratch / Cause / TVAL

以下保持普通 storage：

```text
mscratch
sscratch
mcause
scause
mtval
stval
```

不拆成独立 module。

`cpu_csr.sv` 即使仍有五六百行，只要职责已经变成：

```text
CSR storage
WARL sanitize
CSR aliases
hardware trap updates
counter state
PMP CSR state
```

就可以接受。

不要为了追求文件行数继续把每组 CSR 拆成 wrapper。

---

# 45. cpu_csr 最终职责

Phase 9 后，`cpu_csr.sv` 不再负责：

```text
instruction legality
current privilege legality
CSR instruction decoding
```

它只负责：

```text
storage
read mux
write semantics
WARL/WPRI
alias views
hardware trap update
counter update
PMP CSR storage
```

这是真正适合 CSR bank 的边界。

---

# 46. cpu_decode 最终职责

Decode：

```text
instruction decode
CSR metadata lookup
runtime CSR access legality
SYSTEM instruction legality
exception generation
```

但它不再保存一份独立 CSR address database。

静态 CSR knowledge 全部来自：

```text
csr_defs.svh
csr_meta.sv
```

---

# 47. Trap Router 最终职责

`cpu_trap_router.sv`：

```text
interrupt arbitration
delegation decision
trap target PC
trap/xRET target privilege
status-stack update values
trap CSR write values
```

不保存 CSR。

不识别具体 instruction encoding。

不处理 memory fault来源。

---

# 48. Controller 最终变化

Controller结构不重写。

仅为 Trap Return 增加：

```text
trap_return_kind latch
```

状态图仍然保持：

```text
DECODE
  -> TRAP_RETURN
  -> FETCH
```

不增加：

```text
STATE_MRET
STATE_SRET
```

保持朴素。

---

# 49. 主要代码变化

新增：

```text
src/rtl/core/csr_defs.svh
src/rtl/core/csr_meta.sv
```

修改：

```text
src/rtl/core/core_bus_types.svh
    trap_return_kind_t
    optional privilege helper

src/rtl/core/cpu_decode.sv
    remove duplicated CSR constants/functions
    use csr_meta
    SFENCE.VMA U-mode legality
    CSR legality single source

src/rtl/core/cpu_controller.sv
    latch MRET/SRET return kind

src/rtl/core/cpu_trap_router.sv
    explicit return kind
    explicit target_priv
    explicit status update bank
    named mstatus field updates

src/rtl/core/cpu_trap_manager.sv
src/rtl/core/cpu_trap_csr.sv
src/rtl/core/cpu_csr_interface.sv
src/rtl/core/core_top.sv
    propagate explicit return kind / status bank
    remove csr_access_ok glue

src/rtl/core/cpu_csr.sv
    mstatus/sstatus WARL cleanup
    MPP sanitize
    counter-enable masks
    satp sanitize
    mip/sip cleanup
    shared CSR address definitions

src/rtl/core/ptw.sv
    non-leaf G inheritance
```

---

# 50. 不在本阶段做

不要借 Privileged cleanup 扩大到：

- Cache/MMU/TLB state-machine redesign；
- PMP/PMA redesign；
- selective SFENCE.VMA；
- vectored mtvec/stvec；
- Sstc；
- AIA；
- H extension；
- big-endian support；
- F/V extension；
- power management；
- WFI sleep state；
- HPM counter；
- mcountinhibit；
- multi-hart；
- SoC decoder rewrite。

这些都不是当前目标。

---

# 51. Phase 9 完成后的 core

目标 core：

```text
                      cpu_decode
                  instruction legality
                         |
                      typed bus
                         |
                      execute
                         |
                       memory
                         |
                MMU -> PMP/PMA
                         |
                       cache

                 exception_t
                     |
               trap manager
                     |
               trap router
                     |
             explicit MRET/SRET
                     |
                  CSR bank
```

CSR 侧：

```text
csr_defs.svh
     |
 csr_meta.sv
     |
 cpu_decode
     |
 legal CSR op
     |
 cpu_csr_interface
     |
 cpu_csr
```

静态 CSR knowledge 只有一份。

---

# 52. 本阶段结束后的冻结边界

Phase 9 完成后应冻结：

```text
Controller
Decode/Execute/MEM contracts
MMU/TLB/PTW
PMP/PMA
Cache
Bus
Exception/Trap
A-extension
CSR/Privileged
```

之后不再规划新的 core architecture refactor。

剩余开发仅包括：

```text
SoC address-map cleanup
small completeness cleanup
stale debug/comment/naming cleanup
```

如果没有 concrete correctness issue，不再因为“还可以再拆模块”而主动重构 core。

---

# 53. 后续路线

下一阶段只剩平台层收口：

```text
SoC address-map cleanup
    |
    +-> exact decoder windows
    +-> remove broad aliases
    +-> align default DECERR behavior
    +-> synchronize platform constants
```

之后进行最后的小型 completeness cleanup。

到那时，代码目标不是继续变得“更抽象”，而是保持：

> 功能完整、微架构朴素、模块边界明确、行为可解释。
