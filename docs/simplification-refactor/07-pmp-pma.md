# CPU 代码简化重构：PMP + PMA

> 分支：`chp`  
> 前置阶段：Architecture Foundation、Unified Exception / Trap、A Extension Semantics 已完成。  
> 本文定义 Phase 8：Physical Memory Protection（PMP）与 Physical Memory Attributes（PMA）。目标是在不引入复杂内存保护子系统的前提下，把当前已经存在但未真正执行的 PMP CSR、固定 SoC 物理属性、CPU 显式访问和 PTW 隐式访问统一到同一条 physical-access legality path。

---

# 1. 本阶段目标

当前 core 已经具备：

```text
VA
 ↓
MMU
 ↓
checked PA
 ↓
DCache / ICache
 ↓
AXI
```

但 MMU 完成 translation 后，PA 仍缺少真正的：

```text
PMP
PMA
```

检查。

当前代码还存在：

```systemverilog
assign pmp_data_violation = 1'b0;
```

与此同时，`cpu_csr.sv` 已经实现了 16 个 PMP entry 对应的：

```text
pmpcfg0..3
pmpaddr0..15
```

所以现状是：

> 软件可以配置 PMP，但配置并不影响实际 memory access。

本阶段要把这部分补完整。

完成后 physical path：

```text
                 virtual access
                      |
                     MMU
                      |
                 translated PA
                      |
             +--------+--------+
             |                 |
            PMP               PMA
             |                 |
             +--------+--------+
                      |
                 access allow
                      |
          +-----------+-----------+
          |                       |
       I/D access               PTW access
          |                       |
        Cache                   DCache
          |                       |
          +-----------+-----------+
                      |
                     AXI
```

---

# 2. 实现范围

实现基础 RISC-V PMP：

```text
16 PMP entries
4-byte PMP grain (G = 0)

A modes:
    OFF
    TOR
    NA4
    NAPOT

permissions:
    R
    W
    X

locking:
    L
```

不实现：

```text
Smepmp
mseccfg.MML
mseccfg.MMWP
mseccfg.RLB
64-entry PMP
configurable PMP grain
```

PMA 使用固定 SoC 属性，不增加可编程寄存器。

---

# 3. Physical access 的统一规则

任何真正访问 physical address 的 CPU operation 都必须同时满足：

```text
PMP allow
AND
PMA allow
```

PMP 和 PMA 职责不同：

```text
PMP
    programmable protection
    由 firmware 配置
    依赖 privilege mode
    可进一步限制某段物理地址

PMA
    fixed platform property
    由硬件拓扑决定
    与 privilege mode 无关
    描述某段地址本来支持什么
```

PMP 永远不能赋予 PMA 本来不支持的能力。

例如：

```text
BootROM PMA: write = no
```

即使 PMP 给了 W，也仍然不能写 BootROM。

---

# 4. PMA：SoC 的固定物理属性

扩展 `soc_addr_map.svh`，补齐真实 region size。

建议定义：

```text
DDR
    base = 0x8000_0000
    size = 0x0800_0000      // 128 MiB

BootROM
    base = 0xFC00_0000
    size = 0x0000_8000      // 32 KiB

CLINT
    base = 0x0200_0000
    size = 0x0001_0000      // 64 KiB

PLIC
    base = 0x0C00_0000
    size = 0x0100_0000      // 16 MiB

SysStatus
    base = 0x0400_0000
    size = 0x0000_1000      // 4 KiB

GPIO
    base = 0x1000_0000
    size = 0x0000_1000

UART
    base = 0x1000_8000
    size = 0x0000_1000

SPI
    base = 0x1000_C000
    size = 0x0000_1000
```

`0x1000_4000` 的旧 APB Timer slot 当前未实现，因此按 unmapped 处理。

---

# 5. PMA 属性表

平台属性固定为：

| Region | R | W | X | Cacheable | PTW R/W | LR/SC / AMO |
|---|---:|---:|---:|---:|---:|---:|
| DDR | yes | yes | yes | yes | yes | yes |
| BootROM | yes | no | yes | no | no | no |
| CLINT | yes | yes | no | no | no | no |
| PLIC | yes | yes | no | no | no | no |
| SysStatus | yes | no | no | no | no | no |
| GPIO | yes | yes | no | no | no | no |
| UART | yes | yes | no | no | no | no |
| SPI | yes | yes | no | no | no | no |
| Other / Unmapped | no | no | no | no | no | no |

这张表是本 SoC 的 architectural physical-memory contract。

后续 system_top address-decoder cleanup 应向它对齐，而不是反过来让 PMA 继续接受旧 broad decode alias。

---

# 6. PMA access width

当前 CPU architectural data access 只需要：

```text
1 byte
2 bytes
4 bytes
```

DDR 与已实现 MMIO region 允许上述自然访问宽度。

Instruction fetch：

```text
4 bytes
```

因为当前没有 C extension。

PTW：

```text
4-byte PTE read
4-byte A/D update write
```

Atomic：

```text
LR.W
SC.W
AMO*.W
```

只支持自然对齐 4-byte word，并且只允许 DDR。

Misalignment 仍由已有 stage exception path 处理，不在 PMA 内重新实现一套 alignment checker。

---

# 7. PMA checker

新增：

```text
src/rtl/core/pma_checker.sv
```

建议接口：

```systemverilog
module pma_checker(
    input  [31:0]       paddr,
    input  access_class_t access_type,
    input  [2:0]        access_size,

    input               is_atomic,
    input               is_ptw,

    output              allow
);
```

其中：

```text
access_type:
    ACCESS_FETCH
    ACCESS_LOAD
    ACCESS_STORE

is_atomic:
    MEM_LR / MEM_SC / MEM_AMO

is_ptw:
    implicit page-table access
```

PMA checker 先确定整个 access byte range 是否完全位于同一合法 region，再检查该 region 的属性。

禁止只检查起始地址。

---

# 8. PMA full-range rule

任何 access：

```text
[start, end)
```

必须完整落在同一 PMA region 内。

例如：

```text
last byte of valid region + 4-byte access crossing boundary
```

不能因为起始地址合法就放行。

建议内部使用 33-bit endpoint，避免：

```text
paddr + access_bytes
```

产生 32-bit wraparound。

---

# 9. PMA 与 Cache

当前只有 DDR 是 cacheable。

因此：

```text
DDR       -> cacheable
everything else -> uncached
```

ICache/DCache 当前已经使用 `SOC_DDR_BASE / SOC_DDR_SIZE` 判断 cacheability，这个策略继续保留。

本阶段不为了 PMA 再增加一套 cache-policy interface。

关键要求只有：

> cacheability 与 PMA 必须使用同一份 `soc_addr_map.svh` 平台常量。

这样不会出现“PMA 认为不是 DDR，但 Cache 认为是 DDR”的分裂定义。

---

# 10. PMP CSR 形态

保留当前：

```text
pmpcfg0
pmpcfg1
pmpcfg2
pmpcfg3

pmpaddr0
...
pmpaddr15
```

即 16 entries。

在 RV32 中：

```text
pmpcfg0 -> entries 0..3
pmpcfg1 -> entries 4..7
pmpcfg2 -> entries 8..11
pmpcfg3 -> entries 12..15
```

每个 config byte：

```text
bit 7    L
bit 6:5  reserved = 0
bit 4:3  A
bit 2    X
bit 1    W
bit 0    R
```

PMP grain 固定为：

```text
G = 0
```

因此支持 4-byte 最小 region，且 pmpaddr 的所有 32 bits 都实现。

---

# 11. PMP CSR 输出收口

当前 `cpu_csr -> cpu_trap_csr -> core_top` 传递 20 根独立 PMP register bus。

本阶段收成两个 packed bus：

```systemverilog
logic [127:0] pmpcfg_flat;
logic [511:0] pmpaddr_flat;
```

定义：

```text
pmpcfg_flat[8*i +: 8]   = PMP entry i config
pmpaddr_flat[32*i +:32] = pmpaddr[i]
```

内部 CSR register 仍可以保持当前独立寄存器实现，不要求改成 array。

目标只是消除 top-level 20 组重复 wiring。

---

# 12. PMP config WARL

支持全部基础 A mode：

```text
00 OFF
01 TOR
10 NA4
11 NAPOT
```

写 config byte 时：

1. reserved bits `[6:5]` 强制为 0；
2. `R=0, W=1` 是 reserved combination，本实现将 W 自动清零；
3. X 独立保留；
4. A 四种 encoding 全部支持；
5. L 正常写入并参与 lock。

建议实现统一：

```text
sanitize_pmpcfg_byte()
```

不要在四个 pmpcfg CSR write case 中复制逻辑。

---

# 13. 修正 locked pmpcfg write

当前代码的思路是：

```text
locked byte -> write mask = 0
```

然后整体覆盖整个 pmpcfg CSR。

这会把 locked byte 清零，而不是保持原值。

正确语义：

```text
new_byte =
    locked ? old_byte : sanitize(sw_byte)
```

即 locked config byte 在任何后续 write 中保持不变。

L 一旦置 1，只能 reset 清除。

即使 A=OFF，L=1 仍然锁住该 entry。

---

# 14. TOR predecessor locking

PMP lock 还必须处理 TOR 的特殊规则。

如果：

```text
entry i:
    L = 1
    A = TOR
```

则：

```text
pmpaddr[i]     locked
pmpaddr[i-1]   also locked
```

因为 `pmpaddr[i-1]` 是该 TOR region 的 lower bound。

所以 `pmpaddr[k]` 可写条件应为：

```text
not own_locked
AND
not (entry k+1 is locked TOR)
```

`pmpaddr15` 没有 next entry，只检查自己的 L。

---

# 15. PMP address modes

## OFF

```text
A = 00
```

不匹配任何地址。

## TOR

entry i：

```text
lower =
    i == 0 ? 0 : pmpaddr[i-1] << 2

upper =
    pmpaddr[i] << 2

region = [lower, upper)
```

如果：

```text
lower >= upper
```

region 为空。

## NA4

```text
base = pmpaddr[i] << 2
size = 4
```

## NAPOT

支持完整基础 NAPOT encoding。

根据 `pmpaddr` 低位连续 1 的数量推导 region size。

例如：

```text
...xxx0   -> 8 bytes
...xx01   -> 16 bytes
...x011   -> 32 bytes
...
```

实现时建议使用统一 trailing-ones helper，计算 35-bit：

```text
region_base
region_end
```

不要通过大量固定 size case 展开。

---

# 16. 为什么 PMP 内部需要 35-bit endpoint

RV32 PMP address register 实际描述：

```text
34-bit physical byte address / 4
```

而且 NAPOT 可以描述到整个 `2^(XLEN+3)` byte range。

当前 SoC AXI address 只有 32-bit，但 PMP CSR 本身仍应按 RV32 base PMP encoding 实现。

因此 checker 内部建议：

```text
35-bit range endpoint
```

用于：

```text
region_start
region_end
access_start
access_end
```

CPU 当前 32-bit PA 输入零扩展后参与比较。

这样不会因为 top-of-range overflow 破坏 NAPOT/TOR matching。

---

# 17. PMP matching priority

新增：

```text
src/rtl/core/pmp_checker.sv
```

建议接口：

```systemverilog
module pmp_checker(
    input  [31:0]        paddr,
    input  [2:0]         access_size,
    input  access_class_t access_type,
    input  priv_mode_t   effective_priv,

    input  [127:0]       pmpcfg_flat,
    input  [511:0]       pmpaddr_flat,

    output               allow
);
```

matching 必须遵守：

> 最低编号、且与该 memory operation 任意 byte 相交的 PMP entry 拥有最高优先级。

因此不是：

```text
find first entry that fully contains access
```

而是：

```text
find first entry that overlaps any byte
```

然后：

- 如果它只覆盖 access 的一部分：deny；
- 如果它完整覆盖：再检查 privilege 和 R/W/X。

---

# 18. PMP full-access matching

对于 physical operation：

```text
access = [access_start, access_end)
```

entry：

```text
region = [region_start, region_end)
```

定义：

```text
overlap =
    access_start < region_end
    AND
    access_end > region_start

full_match =
    access_start >= region_start
    AND
    access_end <= region_end
```

遍历 entry 0 → 15。

第一个 `overlap` entry：

```text
if !full_match:
    deny
else:
    evaluate permission
```

之后不再看低优先级 entry。

---

# 19. PMP permission rule

如果 first matching entry 完整覆盖 access：

## S/U effective privilege

必须检查对应 permission：

```text
FETCH -> X
LOAD  -> R
STORE -> W
```

## M effective privilege

如果：

```text
L = 0
```

则该 matching entry 对 M-mode 不限制，access allow。

如果：

```text
L = 1
```

则 M-mode 同样检查 R/W/X。

因此 locked entry 不只是“CSR 锁定”，也代表它的 permission 对 M-mode 生效。

---

# 20. PMP no-match rule

实现了 16 个 PMP entry，因此即使所有 A 都是 OFF，PMP facility 仍然存在。

如果没有 entry 匹配：

```text
effective privilege = M
    -> allow

effective privilege = S/U
    -> deny
```

这意味着 reset 后：

```text
all PMP entries OFF
```

时 S/U 默认不能访问 physical memory。

M-mode firmware 必须先配置 PMP，才能把允许的 physical regions 授权给 S/U。

这是完整 PMP 行为的一部分，不要为了保持旧“PMP 不生效”行为增加默认 bypass。

---

# 21. Effective privilege

PMP 使用的是 memory access 的 effective privilege。

## Instruction fetch

```text
pmp_priv = current priv_mode
```

MPRV 不影响 instruction fetch。

## Explicit data access

与 MMU 使用相同规则：

```text
if current mode == M && mstatus.MPRV == 1:
    pmp_priv = mstatus.MPP
else:
    pmp_priv = current mode
```

建议在 `core_bus_types.svh` 增加统一 helper：

```systemverilog
function automatic priv_mode_t effective_data_priv(...);
```

MMU 与 core_top/PMP 共用，不再各自复制。

## PTW implicit access

固定：

```text
effective privilege = S
```

page-table memory access 不使用原 instruction 的 U/S/M privilege 做 PMP check。

---

# 22. CPU Fetch physical protection

当前：

```text
Fetch VA
  -> MMU
  -> mmu_inst_paddr
  -> ICache
```

改为：

```text
Fetch VA
  -> MMU
  -> PA
  -> PMP(fetch, current priv)
  -> PMA(fetch)
  -> ICache
```

只有：

```text
mmu_inst_ready
AND pmp_allow
AND pma_allow
```

才向 ICache 发 request。

PMP/PMA deny：

```text
cause = 1   instruction access fault
epc   = fetch VA
tval  = fetch VA
```

不向 ICache/AXI 发 physical transaction。

---

# 23. CPU Data physical protection

Architecture Foundation 已经提供：

```text
mem_access_valid
mem_vaddr
mem_kind
mem_access_type
mem_access_paddr
```

本阶段增加：

```text
mem_access_size
```

用于 PMP/PMA full-range check。

路径：

```text
mem_vaddr
   |
  MMU
   |
mmu_data_paddr
   |
 +------+------+
 |             |
PMP           PMA
 |             |
 +------+------+
        |
 mem_access_ready
        |
      cpu_mem
        |
 latch checked PA
```

新的：

```text
mem_access_ready =
    mmu_data_ready
    AND data_pmp_allow
    AND data_pma_allow
```

如果 MMU ready 但 PMP/PMA deny：

```text
ACCESS_LOAD  -> cause 5
ACCESS_STORE -> cause 7

epc  = memory instruction PC
tval = mem_vaddr
```

不允许 cpu_mem 进入 physical request phase。

---

# 24. A-extension 与 PMA

`mem_kind` 用于 PMA atomic capability。

```text
MEM_LR
MEM_SC
MEM_AMO
    -> is_atomic = 1
```

当前平台：

```text
DDR:
    atomic allowed

BootROM / MMIO / unmapped:
    atomic denied
```

因此：

```text
LR on MMIO   -> load access fault, cause 5
SC on MMIO   -> store/AMO access fault, cause 7
AMO on MMIO  -> store/AMO access fault, cause 7
```

atomic deny 发生在任何 physical read/write 之前。

这完成 Phase 7 留给 PMA 的平台边界。

---

# 25. PTW 必须通过 PMP + PMA

当前 PTW：

```text
PTW
 ↓
DCache PTW port
 ↓
AXI
```

目前没有 PMP/PMA。

改为：

```text
PTW physical PTE request
        |
     +--+--+
     |     |
    PMP   PMA
     |     |
     +--+--+
        |
      DCache
```

PTW PMP：

```text
effective privilege = S

PTE read:
    ACCESS_LOAD

A/D update:
    ACCESS_STORE
```

PTW PMA：

```text
is_ptw = 1
```

当前只有 DDR 支持 hardware page-table read/write。

---

# 26. PTW protection failure 的异常类型

如果 PTW 访问 PTE 时违反 PMP 或 PMA：

```text
do not send DCache request

return:
    ptw_bus_done  = 1
    ptw_bus_error = 1
```

让现有 PTW fault machinery 将它转换成：

```text
access fault corresponding to original architectural access type
```

例如：

```text
instruction translation PTE denied
    -> instruction access fault, cause 1

load translation PTE denied
    -> load access fault, cause 5

store/AMO translation PTE denied
    -> store/AMO access fault, cause 7
```

不要把 PMP/PMA-denied page-table access 转换成 page fault。

---

# 27. PTW protection handshake

为避免把 denied PTW request 送进 DCache，core_top 将 PTW path 分为：

```text
ptw_bus_req           // from PTW/MMU

ptw_mem_req_valid     // only when protection allows
ptw_mem_done
ptw_mem_error         // raw DCache response
```

组合：

```text
if protection deny:
    DCache ptw_req_valid = 0
    MMU ptw_bus_done     = 1
    MMU ptw_bus_error    = 1

else:
    DCache ptw_req_valid = ptw_bus_req
    MMU ptw_bus_done     = dcache_ptw_done
    MMU ptw_bus_error    = dcache_ptw_error
```

现有 PTW held-request / drain 模型继续保留。

不增加 bus cancellation。

---

# 28. PMP / PMA fault 与 Unified Exception

Phase 6 已经统一 `exception_t`。

因此本阶段不新增：

```text
pmp_fault_pending
pma_fault_pending
```

之类的长期 sideband。

Fetch/data protection deny 直接在 core_top 形成现有：

```text
fetch_exception
mem_external_exception
```

对应的 access fault。

旧：

```text
pmp_data_violation
```

placeholder 删除。

---

# 29. Misalignment priority

当前 cpu_mem 在 architectural MMU/PMP/PMA access 前先检测：

```text
byte / half / word alignment
```

因此当前实现选择：

```text
misaligned exception
    before
page/access protection fault
```

对于普通 load/store/AMO，这属于实现允许选择的异常优先级。

本阶段不改变该行为。

---

# 30. Cache refill 与 PMP

PMP/PMA 检查发生在每次 architectural fetch/load/store/LR/SC/AMO 进入 Cache 之前。

因此即使某个 DDR line 已在 Cache 中：

```text
architectural access
    -> still passes PMP/PMA first
    -> then cache hit/miss
```

不能因为 cache hit 绕过 protection。

Cache line refill 可以继续按 32-byte DDR line 工作。

由于只有 DDR 是 cacheable，refill 不会对 MMIO 做 speculative over-read。

本阶段不引入 per-cache-line PMP metadata。

---

# 31. BootROM 与 read-only PMA

BootROM PMA：

```text
R = yes
X = yes
W = no
```

因此 CPU store 到：

```text
0xFC00_0000 .. 0xFC00_7FFF
```

会在进入 AXI 前产生 store access fault。

这取代当前 BootROM slave：

```text
write silently OKAY
```

对 CPU architectural behavior 的影响。

slave 本身可以暂时继续保持现状作为总线 robustness 行为。

---

# 32. Legacy broad decode 与 PMA

当前 system_top 仍有 broad decode，例如：

```text
BootROM: 0xFCxx_xxxx
CLINT:   0x02xx_xxxx
APB:     0x10xx_xxxx
SysStatus: 0x04xx_xxxx
```

PMA 不跟随这些历史 alias。

例如：

```text
0xFC01_0000
```

虽然当前 interconnect 可能仍路由到 BootROM slave，但 PMA 应判定为 unmapped 并产生 access fault。

这样：

> PMA 定义 architectural physical map；旧 interconnect alias 只是后续待清理实现细节。

后续 SoC address-map cleanup 再把 decoder 收紧到与 PMA 一致。

---

# 33. PMP checker 与 PMA checker 的组合位置

不要把 PMP/PMA 塞进 MMU 内部。

MMU 只负责：

```text
VA translation
page permission
A/D
translation faults
```

PMP/PMA 属于 translated physical address 之后的独立平台层。

目标：

```text
                     +-----------------+
VA ---------------->|       MMU       |
                     +--------+--------+
                              |
                              PA
                              |
                 +------------+------------+
                 |                         |
          +------+-------+          +------+-------+
          |     PMP      |          |     PMA      |
          +------+-------+          +------+-------+
                 |                         |
                 +------------+------------+
                              |
                           allowed
                              |
                           Cache/Bus
```

PTW 是例外：它自己产生 physical PTE address，所以直接进入同一 PMP/PMA 层。

---

# 34. 不实现 protection cache

PMP entries 只有 16 个，CPU 又是严格串行。

因此 checker 直接 combinational 遍历：

```text
entry 0 -> entry 15
```

即可。

不增加：

- PMP TLB；
- permission cache；
- region CAM；
- pipelined matcher。

当前 FPGA CPU 的目标是 correctness 和可调试性，不是 protection lookup 吞吐。

---

# 35. 不实现 Smepmp

本阶段只实现 base PMP semantics。

不添加：

```text
mseccfg
MML
MMWP
RLB
```

M-mode 行为保持 base PMP：

```text
unlocked matching rule -> M bypasses R/W/X
locked matching rule   -> M obeys R/W/X
no matching rule       -> M allow
```

S/U：

```text
matching rule -> obey R/W/X
no matching rule -> deny
```

---

# 36. 本阶段主要文件变化

新增：

```text
src/rtl/core/pmp_checker.sv
src/rtl/core/pma_checker.sv
```

修改：

```text
src/rtl/soc_addr_map.svh
    add exact region sizes

src/rtl/core/core_bus_types.svh
    shared effective_data_priv helper

src/rtl/core/cpu_csr.sv
    PMP WARL
    lock semantics
    TOR predecessor lock
    packed PMP outputs

src/rtl/core/cpu_csr_interface.sv
src/rtl/core/cpu_trap_csr.sv
src/rtl/core/core_top.sv
    collapse PMP CSR wiring to packed buses

src/rtl/core/MMU.sv
    reuse shared effective_data_priv helper

src/rtl/core/cpu_mem.sv
    expose mem_access_size

src/rtl/core/core_top.sv
    fetch PMP/PMA
    data PMP/PMA
    PTW PMP/PMA
    protection fault integration
```

ICache/DCache/MMU/PTW 的核心 FSM 不重写。

---

# 37. 本阶段不做

不要借 PMP/PMA 阶段扩大到：

- CSR 全面 WARL/WPRI cleanup；
- mtvec/stvec mode；
- trap delegation redesign；
- TLB/PTW algorithm redesign；
- Cache replacement/policy；
- Cache coherence；
- multi-hart；
- DMA；
- AXI atomic；
- SoC interconnect rewrite；
- PLIC/CLINT/UART/GPIO/SPI redesign；
- Svpbmt；
- misaligned atomicity granule；
- Smepmp。

这些不属于当前 physical-access legality 层。

---

# 38. Phase 8 完成后的 memory architecture

最终：

```text
                    architectural access
                           |
                          VA
                           |
                          MMU
                           |
                          PA
                           |
             +-------------+-------------+
             |                           |
            PMP                         PMA
    programmable protection      fixed platform attributes
             |                           |
             +-------------+-------------+
                           |
                        allowed
                           |
             +-------------+-------------+
             |                           |
          I/D Cache                    PTW path
             |                           |
             +-------------+-------------+
                           |
                          AXI
```

并形成以下不变量：

1. 所有 architectural physical access 都经过 PMP + PMA；
2. cache hit 不能绕过 PMP/PMA；
3. PTW PTE read/write 同样经过 PMP/PMA；
4. PMP 使用 translated PA，不使用 VA；
5. data PMP privilege 与 MPRV/MPP 一致；
6. PTW PMP privilege 固定为 S；
7. PMA 对所有 privilege 一视同仁；
8. PMP 不能覆盖 PMA 禁止的能力；
9. S/U 在无 PMP match 时默认 deny；
10. M-mode 只有 locked PMP rule 能限制；
11. LR/SC/AMO 只允许 PMA atomic-capable region；
12. BootROM/MMIO/unmapped 不再依赖 slave 的“静默响应”定义 architectural legality。

---

# 39. 后续路线

Phase 8 完成后，memory architecture 的大块功能应基本冻结。

下一阶段：

```text
CSR / Privileged Architecture
    |
    +-> mstatus / sstatus WARL
    +-> MPP / SPP
    +-> xRET
    +-> delegation
    +-> mtvec / stvec
    +-> counter permission
    +-> satp legality
    +-> remaining privileged semantics
```

之后再进行：

```text
SoC address-map cleanup
remaining completeness fixes
```

PMP/PMA 完成后，不应再通过 core_top 中的临时 violation wire 修补 physical memory permissions。
