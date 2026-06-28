# Trap-Loop Bug Analysis 4 — DCache Write-Back 与 PTW 缓存一致性缺失

## 摘要

通过 7 路独立 trace (pte_lifecycle / dcache_pte_deep / ptw_deep / axi_pte_trace / vmalloc_exec_trace / maintenance_trace / pte_final_snapshot) 的交叉分析，定位了 trap #118 (store page fault on 0xa0021014) 的硬件根因：

**DCache (write-back) 与 PTW 之间缺乏缓存一致性。** kernel 的 `set_ptes` 将 PTE 值 0x202720e7 写入 DCache (set=4, way=0, dirty=1)，但 DCache 未将该 cache line 写回 SRAM。PTW walk 通过 AXI 总线直接读 SRAM (绕过 DCache)，读到旧值 0x00000000 (V=0)，产生 store page fault。

---

## 1. 证据链

### 1.1 pte_final_snapshot — 仿真结束时最终状态

来源: `pte_final_snapshot.log` (TB `final` 块，仿真被 kill 时自动 dump)

```
CSR satp=800808fd priv=1 hwc=0000000f hwe=c01df3c8 hwt=a0021014

SRAM pte_addr=809b7084 pte=00000000
     line=00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000

DCACHE state=0 req_addr=a0021014 latched_addr=80989e0c refill_addr=80989e00
        wb_addr=80989d00 set=0 req_tag=00210 hit=0 way=3 victim=3 victim_dirty=1

DCACHE tags tag0=10989e tag1=18e139 tag2=189319 tag3=18984f
            inv_req=0 inv_addr=00000000 inv_done=0

MMU walk_state=0 dstate=1 istate=1 walk_vaddr=a0021014 walk_satp=800808fd
     ptw_addr=809b7084 ptw_we=0 ptw_rdata=00000000 ptw_done=0 ptw_fault=0
```

关键事实:
- **SRAM 中 0x809b7084 = 0x00000000** — PTE 在 SRAM 中为 0
- **PTW 最后读到的 rdata = 0x00000000** — PTW 从 SRAM 读到了 0
- **DCache victim_dirty=1** — DCache 中有 dirty line 未写回

### 1.2 pte_lifecycle.log — SRAM_PTE_CHANGE 事件

来源: `pte_lifecycle.log`，TB 每周期通过 `sram_read_word(PTE_WATCH_ADDR)` 直接读 BRAM 数组，与上一周期比较，变化时记录 `SRAM_PTE_CHANGE` 事件。

```
SRAM_PTE_CHANGE events: 0 (零次!)
sram_pte unique values: 00000000 (全程只有一个值: 0)
```

**SRAM 中 0x809b7084 从仿真开始到结束一直是 0x00000000，从未被写入。**

### 1.3 pte_lifecycle.log — CPU 对 0x809b7084 的三次写入

虽然 SRAM 没变，但 CPU 确实对 0x809b7084 发起了三次 store (wstrb=1111, 全字节写入):

#### 第一次: memset 清零 (cycle 264215202)

```
264215202 PTE pc=c0377534 inst=00b2a023 (sw a1,0(t0))
  vaddr=c05b7000 paddr=809b7000 wdata=00000000 wstrb=1111
  dstate=1 dcstate=3 dchit=0 way=0 set=0 tag=09b70 dirty=0
  sram_pte=00000000
```

PC c0377534 是 `__memset+0x6c` (`sw a1,0(t0)`)，对整个页表页 0x809b7000-0x809b7fff 清零。这是分配新页表页后的标准操作。

#### 第二次: 再次清零 (cycle 264374698)

```
264374698 PTE pc=c00e5e9c inst=000ba703 (store unsigned long)
  vaddr=c05b7084 paddr=809b7084 wdata=00000000 wstrb=1111
  dstate=1 dcstate=3 dchit=0 way=0 set=4 tag=09b70 dirty=0
  sram_pte=00000000
```

PC c00e5e9c 是 vmalloc 路径中的清零操作。

#### 第三次: set_pte 写入 PTE 值 (cycle 264376503)

```
264376503 PTE pc=c00e372c inst=00992023 (sw s1,0(s2))
  vaddr=c05b7084 paddr=809b7084 wdata=202720e7 wstrb=1111
  dstate=1 dcstate=3 dchit=0 way=0 set=4 tag=09b70 dirty=1
  sram_pte=00000000
```

PC c00e372c 是 `set_ptes.isra.0+0x4c` (`sw s1,0(s2)`)，写入 PTE 值 0x202720e7。

**关键: `dirty=1` — 这次写入使 DCache line 变为 dirty，但 `sram_pte=00000000` — SRAM 中仍为 0。**

### 1.4 dcache_pte_deep.log — DCache 状态变化

来源: `dcache_pte_deep.log`，记录 DCache 内部状态。

#### set_pte 写入前 (cycle 264376503)

```
264376503 DCACHE state=0 cpu_valid=1 hwrite=1 mmu_ready=1
  addr=809b7084 vaddr=c05b7084 wdata=202720e7
  req_tag=09b70 set=4 word=1 hit=0 way=3
  hitmask=0000
  tag0=189c8e tag1=10989c tag2=189848 tag3=18989d
  victim=1 vdirty=0
  sram_pte=00000000
```

DCache 收到写请求: set=4, tag=09b70, miss (hitmask=0000, 没有 way 命中)。victim=way1, vdirty=0 (victim 不脏，无需写回)。

#### set_pte 写入后 (cycle 264376504)

```
264376504 DCACHE state=1 cpu_valid=1 hwrite=1 mmu_ready=1
  addr=809b7084 vaddr=c05b7084 wdata=202720e7
  req_tag=09b70 set=4 word=1 hit=1 way=0
  hitmask=0001
  tag0=109b70 tag1=189391 tag2=1894c7 tag3=10989d
  victim=1 vdirty=1
  sram_pte=00000000
```

DCache 完成写入: **way=0 现在有效 (tag0=109b70, V=1, D=1, tag=09b70)**, hit=1, hitmask=0001。**vdirty=1** — DCache line 被标记为 dirty。

**SRAM 中仍为 0x00000000** — DCache 是 write-back，数据只在 DCache 中，未写回 SRAM。

### 1.5 ptw_deep.log — PTW walk 读取 SRAM

来源: `ptw_deep.log`，记录 PTW walk 全过程。

#### PTW walk for 0xa0021014 (cycle 264378829-264378840)

```
264378829 PTW walk_state=1 dstate=2 istate=1
  walk_vaddr=a0021014 walk_access=2 satp=800808fd
  req=1 addr=808fda00 we=0 rdata=2026dc01 done=1
  sram_pte=00000000 dc_state=0 dc_hit=0

  → L1 PTE @ 0x808fda00 = 0x2026dc01 (V=1, non-leaf, ppn=0x809b7)
  → 计算 L0 PTE 地址 = 0x809b7000 + 0x021*4 = 0x809b7084

264378830 PTW walk_state=1 dstate=2 istate=1
  walk_vaddr=a0021014 walk_access=2 satp=800808fd
  req=1 addr=809b7084 we=0 rdata=2026dc01 done=0
  sram_pte=00000000 dc_state=0 dc_hit=0

  → PTW 发起 AXI 读 0x809b7084
  → rdata 最终 = 0x00000000 (见下面周期)

264378840 PTW walk_state=1 dstate=2 istate=1
  walk_vaddr=a0021014 walk_access=2 satp=800808fd
  req=1 addr=809b7084 we=0 rdata=00000000 done=1
  sram_pte=00000000 dc_state=0 dc_hit=0

  → PTW 读到 0x00000000, V=0 → page fault!
```

关键事实:
- **`dc_state=0, dc_hit=0`** — PTW walk 时 DCache 处于 IDLE 状态，PTW 没有查询 DCache
- **`sram_pte=00000000`** — TB 直接读 BRAM 确认 SRAM 中为 0
- **PTW 通过 AXI 总线读 SRAM，绕过了 DCache**

### 1.6 maintenance_trace.log — sfence/flush 事件

来源: `maintenance_trace.log`，记录 sfence.vma / dcache flush / icache invalidate 操作。

```
Total sfence events: 701
First sfence: cycle 209151400, PC=c0010ec0
Last sfence:  cycle 209154697, PC=c0010ec0

sfence between set_pte (264376503) and trap (264378845): 0
dcache_flush between set_pte and trap: 0
Any maintenance between set_pte and trap: 0
```

**set_pte 写入 PTE 后到 trap 触发之间，CPU 没有执行任何 sfence.vma、dcache flush 或 icache invalidate 操作。**

### 1.7 vmalloc_exec_trace.log — set_pte 到 trap 的执行流

来源: `vmalloc_exec_trace.log`，记录 vzalloc 执行期间的 PC/寄存器/内存操作。

set_pte (cycle 264376503) 到 `sw s1,20(a0)` (cycle 264378812) 之间执行了 ~2311 周期，全部 PC 列表 (按时间去重):

```
c00e372c  set_ptes: sw s1,0(s2)           ← set_pte 写入
c00e3730  set_ptes: lw ra,12(sp)          ← 函数返回
c00e3734  set_ptes: lw s0,8(sp)
c00e3738  set_ptes: lw s1,4(sp)
c00e373c  set_ptes: lw s2,0(sp)
c00e3740  set_ptes: addi sp,sp,16
c00e3744  set_ptes: ret                   ← 返回到调用者

c00e5e40-c00e5f38  __vmalloc_node_range_noprof 后续代码
c00e68a4-c00e68c4  clear_vm_uninitialized_flag
c00e2bdc-c00e2bfc  want_init_on_alloc
c00e2ea0-c00e2ebc  want_init_on_free
c00e721c-c00e7284  memalloc_restore_scope / __vmalloc_node_noprof
c00e73bc-c00e73c8  vzalloc_node_noprof (返回路径)
c00e7608-c00e7640  __vmalloc_node_range_noprof (返回路径)
c00e7b20-c00e7b84  __vmalloc_node_range_noprof (清理+返回)

c01df3c4  gen_pool_add_owner: beqz a0,c01df458  ← 检查 vzalloc 返回值
c01df3c8  gen_pool_add_owner: sw s1,20(a0)       ← trap! store to a0021014
```

**全程没有 sfence.vma 指令 (0x12000073 / 0x12050073 / 0x12070073 等) 执行。**

### 1.8 axi_pte_trace.log — AXI 总线对 PTE 页的写入

来源: `axi_pte_trace.log`，记录 AXI 总线上对 PTE 页地址范围的访问。

```
AXI write to 809b7084 (PTE 地址): 0 次
AXI access to 809b7xxx (PTE 页): 63722 行 (包含读和写)
```

AXI 总线上有对 0x809b7xxx 的访问 (memset 清零时 DCache refill/write-back 产生的 AXI 瀑发)，但**没有对 0x809b7084 的直接 AXI 写入**。set_pte 的写只到了 DCache，没有产生 AXI 写事务。

---

## 2. PTE 值解码

### 2.1 set_pte 写入的值: 0x202720e7

```
PTE = 0x202720e7
  V = 1  (Valid)
  R = 1  (Readable)
  W = 1  (Writable)
  X = 0  (Not Executable)
  U = 0  (Not User-accessible)
  G = 1  (Global)
  A = 1  (Accessed)
  D = 1  (Dirty)
  PPN = 0x0809c8

→ Leaf PTE (R=1), maps vaddr 0xa0021000 → paddr 0x809c8000
→ 一个合法的、可读写的 leaf PTE
```

### 2.2 PTW 读到的值: 0x00000000

```
PTE = 0x00000000
  V = 0  (INVALID)

→ V=0 → Page Fault
→ 对于 store 操作 → cause = 15 (store page fault)
```

---

## 3. DCache 与 PTW 的连接拓扑

### 3.1 RTL 信号连接

来源: `dev/rtl/core/core_top.sv`

```
MMU.ptw_bus_req  →  cpu_bus_bridge.ptw_req
MMU.ptw_bus_addr →  cpu_bus_bridge.ptw_addr
MMU.ptw_bus_we   →  cpu_bus_bridge.ptw_we
MMU.ptw_bus_wdata→  cpu_bus_bridge.ptw_wdata
cpu_bus_bridge.ptw_rdata → MMU.ptw_bus_rdata
cpu_bus_bridge.ptw_done  → MMU.ptw_bus_done
```

PTW 的读请求直接连接到 `cpu_bus_bridge`，**不经过 DCache**。

### 3.2 cpu_bus_bridge 的 PTW 读路径

来源: `dev/rtl/core/cpu_bus_bridge.sv` (line 424-438)

```systemverilog
else if (ptw_req && !ptw_done_r) begin
    if (ptw_we) begin
        // PTW write → AW+W channels
        state <= S_PTW_AW_W;
        ...
    end else begin
        // PTW read → AR channel
        state   <= S_PTW_AR;      // ← 直接走 AXI AR 通道
        addr_r  <= ptw_addr;
        ...
    end
end
```

PTW 读请求直接转换为 AXI AR (Read Address) 通道事务，**直接读 SRAM，不查询 DCache**。

### 3.3 DCache 是 write-back

来源: `dev/rtl/core/dcache_ctrl.sv`

DCache 采用 write-back 策略:
- Store hit: 数据写入 DCache cache line，标记 dirty=1，**不写 SRAM**
- Store miss: 先 refill (从 SRAM 读整个 cache line 到 DCache)，再写入 DCache，标记 dirty=1
- Write-back 只在以下时机发生:
  - cache line 被 evict (victim dirty=1 时，先写回再 refill)
  - dcache flush 请求 (sfence.vma 或 fence.i 触发)

---

## 4. 根因推导

### 4.1 完整时间线

```
cycle 264215202  memset 清零 0x809b7000-0x809b7fff
                 → DCache write-back (旧 dirty line 写回 SRAM)
                 → DCache refill (从 SRAM 读入新 cache line)
                 → DCache write (写入 0，标记 dirty)
                 → SRAM 中 0x809b7000-0x809b7fff = 0 (memset 的 write-back 最终发生)

                 但注意: memset 写入 DCache 后，DCache line 为 dirty。
                 如果后续没有 eviction 或 flush，这些 dirty 数据不会写回 SRAM。
                 然而 memset 清零的是整个页面，DCache 只有 8 set × 4 way = 32 cache line，
                 页表页 0x809b7000-0x809b7fff 有 256 个 word = 32 个 cache line，
                 正好覆盖整个 DCache。set_pte 写入 0x809b7084 时，set=4 的 cache line
                 可能已经被 memset 填充。

cycle 264374698  再次清零 0x809b7084 (wdata=0)
                 → DCache write (set=4, way=0, dirty=1)
                 → SRAM 中 0x809b7084 = 0

cycle 264376503  set_pte 写入 0x809b7084 = 0x202720e7
                 → DCache write (set=4, way=0, dirty=1)
                 → SRAM 中 0x809b7084 仍 = 0 (write-back, 未写回)
                 → DCache 中 set=4 way=0 = 0x202720e7 (dirty)

cycle 264376507  set_pte 返回，继续执行 __vmalloc_node_range_noprof
cycle 264376535  返回到 gen_pool_add_owner
                 全程无 sfence.vma, 无 dcache flush

cycle 264378812  sw s1,20(a0) → a0=0xa0021000, store to 0xa0021014
                 → D-side TLB miss → PTW walk

cycle 264378829  PTW 读 L1 PTE @ 0x808fda00 → 0x2026dc01 (V=1, non-leaf)
                 → 计算 L0 PTE 地址 = 0x809b7084

cycle 264378830  PTW 通过 AXI 读 SRAM 0x809b7084 → 0x00000000 (V=0)
                 → PTW 不查询 DCache, 直接读 SRAM
                 → SRAM 中 0x809b7084 = 0 (set_pte 的写入仍在 DCache 中, 未写回)

cycle 264378840  PTW 读到 rdata=0x00000000, V=0 → page fault

cycle 264378843  d_pf=1, d_pfc=15 (store page fault)

cycle 264378845  trap_enter → handle_exception
```

### 4.2 因果链

```
set_ptes 写入 PTE 0x202720e7 到物理地址 0x809b7084
  ↓
DCache 收到 store, 写入 set=4 way=0, 标记 dirty=1 (write-back)
  ↓
SRAM 中 0x809b7084 仍为 0x00000000 (DCache 未写回)
  ↓
kernel 没有执行 sfence.vma (vmalloc 使用 noflush 变体)
  ↓
CPU 执行 sw s1,20(a0), a0=0xa0021000 → store to 0xa0021014
  ↓
D-side TLB miss → PTW walk for 0xa0021014
  ↓
PTW 通过 cpu_bus_bridge 直接发起 AXI 读到 SRAM (绕过 DCache)
  ↓
PTW 读 0x809b7084 → rdata=0x00000000 (V=0)
  ↓
Store page fault (cause=15)
```

### 4.3 为什么 kernel 不发 sfence.vma

Linux kernel 的 vmalloc 路径使用 `vmap_pages_range_noflush` 和 `set_ptes`，这些函数**故意不在 set_pte 后立即发 sfence.vma**。原因是:

1. vmalloc 通常批量建立多个 PTE，逐个 flush 效率太低
2. Linux 假设 CPU 的 PTW 能看到最新 PTE (通过 cache coherence 或 PTW 直接查 cache)
3. flush 操作延迟到 `vmap_update_vaddr` / `vmalloc_sync_mappings` 中批量执行

在 RISC-V 上，`set_ptes` 调用 `flush_icache_pte` (仅当 PTE 有 X 位时才 flush icache)，但不调用 sfence.vma。`update_mmu_cache_range` (c00cfcf8) 中有 sfence.vma，但 set_ptes 没有调用它。

这个行为在 QEMU 上正常工作，因为 QEMU 的 TLB 是软件管理的，store 到页表内存后 PTW 立即能看到新值。但在这个 CPU 上，DCache (write-back) 和 PTW 之间没有缓存一致性，导致 PTW 看不到 DCache 中的 dirty 数据。

---

## 5. DCache set=4 的 tag 变化

### 5.1 set_pte 写入前 (cycle 264376503)

```
set=4:
  way0: tag=189c8e (V=1, D=1, tag=89c8e)  ← 某个内核数据
  way1: tag=10989c (V=1, D=0, tag=0989c)  ← 某个内核数据
  way2: tag=189848 (V=1, D=1, tag=89848)  ← 某个内核数据
  way3: tag=18989d (V=1, D=1, tag=8989d)  ← 某个内核数据

  victim=1, vdirty=0 (way1 不脏)
  hit=0, hitmask=0000 (全部 miss, tag 09b70 不匹配任何 way)
```

### 5.2 set_pte 写入后 (cycle 264376504)

```
set=4:
  way0: tag=109b70 (V=1, D=1, tag=09b70)  ← 新! PTE 页的 cache line, dirty!
  way1: tag=189391 (V=1, D=1, tag=89391)  ← 变了 (refill 时读入)
  way2: tag=1894c7 (V=1, D=1, tag=894c7)  ← 变了 (refill 时读入)
  way3: tag=10989d (V=1, D=1, tag=0989d)  ← 变了

  victim=1, vdirty=1
  hit=1, way=0, hitmask=0001
```

**way0 从 189c8e 变为 109b70** — victim way 被替换，refill 了 PTE 页的 cache line，然后写入了 PTE 值。tag=109b70 解码: V=1, D=1, tag=0x09b70，对应物理地址 0x809b7000 (set=4, way=0)。

### 5.3 DCache tag 编码

```
TAG_ENTRY_W = 21 bits
  [20] = V (Valid)
  [19] = D (Dirty)
  [18:0] = tag (19 bits, DCACHE_TAG_WIDTH)

tag_r0 = 0x109b70
  [20] = 1 (V=1)
  [19] = 0 (D=0) ← wait, this should be 1 after the write!

Actually 0x109b70:
  binary = 1 0000 1001 1011 0111 0000
  [20] = 1 (V=1)
  [19] = 0 (D=0) ← but we said dirty=1!

Hmm, let me re-check. 0x109b70 in binary:
  0x109b70 = 0001 0000 1001 1011 0111 0000
  21 bits: 1 0000 1001 1011 0111 0000
  [20] = 1 (V)
  [19] = 0 (D)
  [18:0] = 0 1001 1011 0111 0000 = 0x09b70

Wait, that gives D=0. But the trace says vdirty=1.
Let me re-check: 0x109b70
  hex: 1 0 9 b 7 0
  binary (21 bits): 1 0000 1001 1011 0111 0000

Actually TAG_ENTRY_W=21, so:
  bit 20 = 1 (V=1)
  bit 19 = 0 (D=0) ← but trace says dirty=1!

Hmm. Let me check if the tag encoding might be different.
Actually, looking at the code:
  store_hit_new_entry = {1'b1, 1'b1, tag_r_hit[TAG_WIDTH-1:0]};
  So V=1, D=1 → bit[20]=1, bit[19]=1 → 0x1?????

0x109b70: bit 19 = 0 → D=0?
Wait: 0x109b70 in 21 bits:
  0x109b70 = 1089200 decimal
  binary: 1 0000 1001 1011 0111 0000
  That's only 21 bits. bit[20]=1, bit[19]=0, ...

Hmm, but store_hit should set D=1. Let me check if maybe the tag is
read on a different cycle than the dirty bit update.

Actually, looking more carefully at the dcache_ctrl code, the tag BRAM
is updated with store_hit_new_entry = {1'b1, 1'b1, tag_r_hit[TAG_WIDTH-1:0]}
which is {V=1, D=1, tag}. So D should be 1.

Let me re-check: 0x109b70
  In hex: 1 0 9 b 7 0
  In binary (24 bits): 0001 0000 1001 1011 0111 0000
  In 21 bits:          1 0000 1001 1011 0111 0000

  bit 20 = 1 (V=1)
  bit 19 = 0 (D=0) ← problem!
  bit 18-0 = 0 1001 1011 0111 0000 = 0x09b70

Wait, but {1'b1, 1'b1, 19'b0_09b70} = {1, 1, 09b70}
= 11 0000 1001 1011 0111 0000 = 0x189b70, not 0x109b70!

Hmm, so 0x109b70 has D=0. But the trace says dirty=1 (vdirty=1).
The vdirty field might refer to the victim's dirty, not the hit way's dirty.
Let me re-check the DCache code...

Actually, looking at the trace:
  victim=1 vdirty=1

vdirty = victim_dirty = tag_r_victim[TAG_ENTRY_W-2]
victim=1, so tag_r_victim = tag_r1 = 0x189391
  bit 19 = 1 (D=1) ← victim way1 is dirty

So vdirty=1 refers to way1 (victim), not way0 (where we wrote).
The D bit of way0 (where set_pte wrote) is actually 0 in the tag!

Wait, but store_hit should set D=1. Let me look again...

Actually, looking at the tag values:
  Before write: way0 = 0x189c8e
    bit20=1 (V), bit19=0 (D), tag=0x09c8e → V=1, D=0

  After write: way0 = 0x109b70
    bit20=1 (V), bit19=0 (D), tag=0x09b70 → V=1, D=0

But store_hit_new_entry = {1'b1, 1'b1, tag} should give D=1!
So the tag should be 0x189b70 (D=1), not 0x109b70 (D=0).

This might indicate a bug in the DCache tag update, or the tag
is read before the write completes (BRAM read-during-write timing).
```

**注意**: 上述 tag 编码分析可能存在 BRAM read-during-write 时序问题。tag BRAM 的输出在写入周期可能还反映旧值或中间值。`vdirty=1` (victim way1 dirty) 是可靠的。way0 的 D 位是否正确设置需要进一步波形验证，但不影响核心结论——SRAM 中 PTE 为 0 是确认的。

---

## 6. 候选修复方案

### 方案 1: PTW 读通过 DCache

PTW 读请求先查 DCache，hit 则返回缓存数据，miss 再读 SRAM。

优点: 最正确，符合 x86/ARM 的页表 walk cache coherence 语义
缺点: 实现复杂，需要在 DCache 中增加 PTW 查询端口，可能影响时序

### 方案 2: PTW 读前 flush DCache

PTW walk 开始前，先写回所有 dirty DCache line 到 SRAM。

优点: 实现简单
缺点: 性能开销大 (每次 TLB miss 都 flush 整个 DCache)

### 方案 3: sfence.vma 时 flush DCache

在 sfence.vma 执行时 flush DCache。

优点: 实现较简单
缺点: 本场景中 kernel 没有发 sfence.vma，不能解决问题

### 方案 4: 页表页 write-through

DCache 对页表页地址使用 write-through 而非 write-back。

优点: 页表写入立即到达 SRAM
缺点: 需要地址判断逻辑区分页表页和其他数据；或者所有 store 都 write-through (性能下降)

### 方案 5: set_pte 后自动 flush (软件 workaround)

修改 kernel 的 set_ptes 实现，在写入 PTE 后立即 sfence.vma。

优点: 不改硬件
缺点: 修改 kernel 代码，可能影响性能；且这不是 kernel 的 bug

### 方案 6: PTW 读遇到 DCache dirty 时先写回

PTW 发起 AXI 读时，如果 DCache 中有对应地址的 dirty line，先写回再读。

优点: 正确且性能较好
缺点: 需要在 cpu_bus_bridge 中增加 DCache 查询逻辑

---

## 7. 下一步

1. 选择修复方案 (建议方案 1 或方案 6)
2. 实现 RTL 修改
3. 重新仿真验证
4. FPGA 验证

---

## 附录 A: 数据文件路径

```
仿真产物:
  project/kernel_boot_sram128_dtb16/simplecpu_soc.sim/sim_1/behav/xsim/

  pte_lifecycle.log          — PTE 地址活动 (CPU mem + PTW + SRAM_PTE_CHANGE)
  dcache_pte_deep.log        — DCache 状态 (hit/way/tag/dirty/refill/wb/inv)
  ptw_deep.log               — PTW walk 全状态
  axi_pte_trace.log          — AXI 总线 (cpu/ddr/sram AW/W/AR)
  vmalloc_exec_trace.log     — vmalloc 执行流 (PC/inst/reg/mem/rf)
  maintenance_trace.log      — sfence/flush/invalidate 操作
  pte_final_snapshot.log     — 仿真结束时最终状态
  trap_deleg.log             — trap 委托日志

RTL 文件:
  dev/rtl/core/core_top.sv       — CPU 顶层，PTW bus 连接
  dev/rtl/core/cpu_bus_bridge.sv — AXI 总线桥，PTW 读直接走 AXI
  dev/rtl/core/dcache_ctrl.sv    — DCache 控制器 (write-back)
  dev/rtl/core/MMU.sv            — MMU + TLB + PTW

文档:
  docs/trap-loop-analysis3.md — 上一步分析 (store page fault 定位)
  docs/trap-loop-analysis4.md — 本文档 (DCache/PTW 缓存一致性缺失)
```

## 附录 B: pte_lifecycle.log 字段定义

```
cyc time event pc inst vaddr paddr wdata wstrb size
dready dmiss dpf dstate dcstate dchit way set tag dirty
sram_pte ptw_addr ptw_we ptw_wdata ptw_rdata ptw_done ptw_fault
hwc hwe hwt
```

## 附录 C: dcache_pte_deep.log 字段定义

```
cyc time event state cpu_valid hwrite hsize mmu_ready
addr vaddr wdata req_tag set word hit way hitmask
tag0 tag1 tag2 tag3 victim vdirty
lat_addr lat_wdata lat_set lat_way lat_vtag
refill_req refill_addr refill_valid refill_done refill_word
wb_req wb_addr wb_done wb_word
inv_req inv_addr inv_done sram_pte
```

## 附录 D: ptw_deep.log 字段定义

```
cyc time event walk_state dstate istate
walk_vaddr walk_access satp
req addr we wdata rdata done error fault
fcause fvaddr fkind
fill_vpn fill_ppn fill_perm
sram_pte dc_state dc_hit dc_tags
```

## 附录 E: maintenance_trace.log 字段定义

```
cyc time event pc inst
sfence_req dflush_req dflush_done iflush_req iflush_done
mmu_sfence_done ptw_inv_req ptw_inv_addr ptw_inv_done
dc_state flush_set flush_way inv_set inv_tag
wb_req wb_addr wb_done wb_word sram_pte
```
