# Trap-Loop Bug Analysis 3 — Store Page Fault on vmalloc Address

## 摘要

通过对 forensic buffer (128 周期 D-side 信号)、dmmu_fault_trace.log (116 行 D-side MMU 事件)、以及 TB 独立计算的 SV32 page table truth dump 的分析，将 trap #118 的定位边界从 "trap-loop/取指异常" 推进到了 "vmalloc 返回 a0021000 但对应 L0 PTE 在 PTW 可见的 SRAM 中仍为 0"：

**强证明的事实 (日志直接支撑):**

- **Trap 类型**: Store page fault (cause=0x0f = 15)
- **故障指令**: `sw s1, 20(a0)` @ PC=0xc01df3c8 (在 `gen_pool_add_owner` 中)
- **故障地址**: 0xa0021014 (vzalloc_node_noprof 返回的 vmalloc 地址 + 0x14)
- **直接原因**: SV32 page table walk 读取 L0 PTE @ 0x809b7084 = 0x00000000 (V=0)，PTW 按当前内存内容正确产生了 store page fault
- **本次 walk 序列正确**: 在最终 128-cycle forensic 窗口内，PTW 的 L1→L0 walk 序列、V=0 检测、cause=15 生成均符合 SV32 规范
- **本次窗口无 TLB collision**: 128-cycle forensic 窗口和 dmmu focused trace 内 coll_i=0, coll_d=0

**仅限本次窗口的结论 (不能外推):**

- "PTW 行为正确" 仅指本次 walk 在给定内存内容下正确产生 fault；不证明 PTW 全局无 bug，也不证明更早的页表建立期间没有 MMU/缓存交互问题
- "无 TLB collision" 仅指最终 forensic 窗口内；simulate.log 末尾之前仍有大量 Xilinx BRAM collision warning，更早时点的 collision 是否污染过页表建立过程尚不可知

**未定根因 (仍属推测):**

- L0 PTE @ 0x809b7084 = 0 的原因未定。日志只证明了 PTW 读取该 word 时 SRAM 中为 0。可能原因包括: (1) 页表建立代码未执行到 PTE store, (2) PTE store 写到了错误地址, (3) DCache write-back 未落到 SRAM, (4) 页表 flush/coherency 问题, (5) 更早的执行流已偏离

---

## 1. 证据链

### 1.1 Trap #118 确认数据

来源: `trap_deleg.log` (修复版，新增 HW_CAUSE/CSR_SCAUSE/CSR_STVAL/CSR_SEPC)

```
trap #118: cycle=2643788485000
  Event    = TRAP_IN
  PC       = c01df3cc  (trap 入口处 PC)
  Priv     = 1  (S-mode)
  TPriv    = 1  (trap target = S-mode)
  HW_CAUSE = 0x0000000f  (15 = store page fault)  ← 当前 trap 的真实 cause
  CSR_MCAUSE = 0x00000009  (上一个 M-mode ecall 的残留值)
  CSR_SCAUSE = 0x0000000c  (上一个 S-mode trap 的残留值，尚未更新)
  Deleg    = 1  (trap 委托到 S-mode)
  HW_EPC   = c01df3c8  (故障指令 PC)
  HW_TVAL  = a0021014  (故障地址)
  MEDELEG  = 0x0000b109  (bit15=1 → store page fault 委托到 S-mode)
```

**关键纠正**: 之前分析中误读 `csr_mcause=0x09` 为 cause=9 (ecall from S)。实际原因是 S-mode trap 不更新 mcause/mtval/mepc 寄存器（这些是 M-mode CSR），trap_deleg.log 打印的 mcause 值是上一个 M-mode ecall 的残留。`HW_CAUSE=0x0f` 才是当前 trap 的硬件 cause。

### 1.2 CSR_SCAUSE 残留值分析

```
trap #118 的 CSR_SCAUSE = 0x0000000c (12 = inst page fault)
```

这是上一个 S-mode trap (#116, #114, ...) 的残留值。在 trap_enter 阶段，硬件先读 HW_CAUSE 再写 CSR。trap_deleg.log 的采样点在 CSR 写入之前，所以看到的是旧值。当前 trap 的 S-mode cause 在 trap_enter 完成后才会写入 scause 寄存器。

### 1.3 MEDELEG 委托位分析

```
MEDELEG = 0x0000b109
  bit 0  = 1  (inst misaligned)
  bit 3  = 1  (breakpoint)
  bit 8  = 1  (ECALL from U)
  bit 12 = 1  (inst page fault)
  bit 13 = 1  (load page fault)
  bit 15 = 1  (store page fault)  ← 委托到 S-mode
  bit 9  = 0  (ECALL from S)      ← 不委托，留在 M-mode
```

cause=15 (store page fault) 的 MEDELEG bit15=1 → 委托到 S-mode (TPriv=1)。这与 trap_deleg.log 记录的 Deleg=1, TPriv=1 一致。

cause=9 (ecall from S) 的 MEDELEG bit9=0 → 不委托，留在 M-mode (TPriv=3)。但 trap #118 的 TPriv=1，如果 cause 真的是 9 则 Deleg 应该为 0、TPriv 应该为 3。**cause=9 + Deleg=1 + TPriv=1 是矛盾的**，进一步证明 cause=9 是误读。

---

## 2. 故障指令分析

### 2.1 反汇编

来源: `build/kernel/vmlinux` (riscv objdump)

```
c01df3b4 <gen_pool_add_owner+0x48>:
c01df3b4:  00060a93    mv    s5,a2
c01df3b8:  00068993    mv    s3,a3
c01df3bc:  00078a13    mv    s4,a5
c01df3c0:  fd5070ef    jal   c00e7394 <vzalloc_node_noprof>   ← 调用 vzalloc
c01df3c4:  08050a63    beqz  a0,c01df458                       ← 检查返回值是否为 NULL
c01df3c8:  00952a23    sw    s1,20(a0)                         ← 故障指令! store s1 to a0+20
c01df3cc:  fff48493    addi  s1,s1,-1
c01df3d0:  013484b3    add   s1,s1,s3
c01df3d4:  01552623    sw    s5,12(a0)
c01df3d8:  00952c23    sw    s1,24(a0)
c01df3dc:  01452823    sw    s4,16(a0)
```

### 2.2 执行流程

1. `c01df3c0`: `jal vzalloc_node_noprof` — 调用 vzalloc 分配 vmalloc 区域
2. `c01df3c4`: `beqz a0, c01df458` — 检查返回值 a0 是否为 NULL
3. `c01df3c8`: `sw s1, 20(a0)` — **a0 = 0xa0021000 (vzalloc 返回值), a0+20 = 0xa0021014**

a0 = vzalloc 返回值 = 0xa0021000 (非零，通过了 beqz 检查)
store 地址 = 0xa0021000 + 0x14 = 0xa0021014

---

## 3. SV32 Page Table Truth Dump

### 3.1 TB 独立计算的 SV32 walk

来源: `trap_forensics_dump.log` 头部。TB 通过 `sram_read_word()` 函数直接层次引用 `u_soc.sim_ram.u_axi_ram.BRAM[addr[26:2]]` 读取 SRAM (即 BRAM 阵列)，绕过 CPU MMU/DCache。`$fopen` 只用于打开日志文件，与数据读取无关。

```
SV32_TRUTH vaddr=a0021014 satp=800808fd root=808fd000

SV32_L1 addr=808fda00 pte=2026dc01 V=1 R=0 W=0 X=0 U=0 G=0 A=0 D=0 ppn=809b7 leaf=0
SV32_L0 addr=809b7084 pte=00000000 V=0 R=0 W=0 X=0 U=0 G=0 A=0 D=0 ppn=00000 expected_paddr=00000014
```

### 3.2 SV32 地址分解

```
vaddr  = 0xa0021014
satp   = 0x800808fd  (MODE=1 SV32, ASID=0, PPN=0x808fd)
root   = 0x808fd000  (satp.PPN << 12)

VPN[1] = (vaddr >> 22) & 0x3FF = 0x280
VPN[0] = (vaddr >> 12) & 0x3FF = 0x021
offset = vaddr & 0xFFF          = 0x014
```

### 3.3 L1 PTE 分析

```
L1 PTE 地址 = root + VPN[1] × 4 = 0x808fd000 + 0x280 × 4 = 0x808fd000 + 0xa00 = 0x808fda00

L1 PTE 值 = 0x2026dc01
  V = 1  (Valid)
  R = 0  (Not Readable)
  W = 0  (Not Writable)
  X = 0  (Not Executable)
  U = 0  (Not User)
  G = 0  (Not Global)
  A = 0  (Not Accessed)
  D = 0  (Not Dirty)
  PPN = 0x0809b7

→ V=1 且 R=W=X=0 → 非叶子 PTE，指向下一级页表
→ L0 页表基地址 = PPN << 12 = 0x0809b7 << 12 = 0x809b7000
```

### 3.4 L0 PTE 分析

```
L0 PTE 地址 = L0_table_base + VPN[0] × 4 = 0x809b7000 + 0x021 × 4 = 0x809b7000 + 0x84 = 0x809b7084

L0 PTE 值 = 0x00000000
  V = 0  (INVALID!)
  PPN = 0x000000

→ V=0 → 页表项不存在 → Page Fault!
→ 对于 store 操作 → cause = 15 (store page fault)
```

### 3.5 结论

**0xa0021014 的页表映射不存在。L0 PTE = 0x00000000, V=0。**

vzalloc_node_noprof 返回了 0xa0021000，但这个虚拟地址的 SV32 页表映射没有被建立。`sw s1, 20(a0)` 对 0xa0021014 的 store 触发了 store page fault。

---

## 4. DMMU Trace 分析

来源: `dmmu_fault_trace.log` (116 行，记录 D-side MMU 事件)

### 4.1 字段定义

```
cyc time event mem_pc mem_inst mem_en mem_we mem_vaddr mem_wdata
d_paddr d_ready d_miss d_pf d_pfc d_pfv d_state d_lat_vaddr d_atype
d_priv d_sum d_mxr d_tlb_v d_tlb_h d_tlb_perm d_tlb_miss d_ppn
d_r d_w d_x d_u d_a d_d d_g d_mega
ptw_done ptw_fault ptw_fc ptw_fv
fill fill_vpn fill_ppn fill_r fill_w fill_x fill_u fill_a fill_d
coll_i coll_d hwc hwe hwt scause stval sepc
```

### 4.2 关键事件时间线

所有 116 行 DMMU 事件按时间排列。a0021014 相关事件从第 83 行 (cycle 264378813) 开始。

#### Phase 1: 前序访问 (cycle 264307603 - 264307883)

```
cycle 264307603-264307681:  D-side load from c052c748 (kernel data)
  - d_tlb_v=1 d_tlb_miss=0 (TLB hit)
  - d_ppn=80923 (later 8092c, 80ffe, 80989)
  - 正常的 kernel 数据访问

cycle 264307883:  D-side access during jal vzalloc_node_noprof
  - mem_inst=fd5070ef (jal)
  - d_tlb_v=1 d_tlb_miss=0 (TLB hit for c052c748)
  - fill=0 (no TLB fill)
  - d_mega=1 (megapage mapping for kernel)
```

**大时间跳转**: cycle 264307883 → 264378812 (跳过 ~71000 周期，vzalloc_node_noprof 执行期间)

#### Phase 2: 首次访问 a0021014 (cycle 264378812-264378813)

```
cycle 264378812 (line 83):
  mem_pc=c01df3c8  mem_inst=00952a23 (sw s1,20(a0))
  mem_en=1  mem_we=1  mem_vaddr=a0021014  mem_wdata=a0000000
  d_paddr=c0589e18  d_ready=0  d_miss=0  d_pf=0
  d_state=1  (TLB lookup state)
  d_tlb_v=0  d_tlb_h=0  d_tlb_miss=0  (TLB miss, not yet reported)
  d_ppn=80441  (stale TLB entry from previous mapping, NOT used since d_tlb_v=0)
  ptw_done=0  ptw_fault=0

cycle 264378813 (line 84):
  d_paddr=a0021014  (vaddr passthrough, no translation yet)
  d_state=1  d_lat_vaddr=a0021014  (latched vaddr)
  d_tlb_v=0  d_tlb_miss=0
```

**注**: `d_ppn=80441` 是 TLB BRAM 中的残留数据 (stale entry)，但 `d_tlb_v=0` 表示该条目无效，不会被用于翻译。这是一个 red herring。

#### Phase 3: TLB miss 确认 + PTW walk 启动 (cycle 264378814-264378815)

```
cycle 264378814 (line 85):
  d_miss=1  (TLB miss reported)
  d_state=1  (still in lookup → transitioning to walk)
  d_tlb_v=1  d_tlb_miss=1  (TLB miss flag set)
  d_tlb_perm=0  (no permission fault)
  ptw_done=0  ptw_fault=0
  ptw_fc=15  (PTW fault cause pre-loaded? or residual)
  fill=0

cycle 264378815 (line 86):
  d_miss=1
  d_state=1
  d_tlb_v=1  d_tlb_miss=1
  ptw_fc=15  ptw_fv=c01df3c4  (residual from previous PTW)
  → PTW walk starting for a0021014
```

#### Phase 4: PTW walk 执行 (cycle 264378816 - 264378840)

```
cycle 264378816-264378829 (line 87-100):
  d_state=2  (PTW walk state)
  d_miss=0  d_pf=0  (walk in progress, no fault yet)
  d_tlb_v=0  d_tlb_miss=0  (TLB invalidated during walk)
  d_ppn=80441  (stale, not used)
  ptw_done=0  ptw_fault=0
  ptw_fc=15  ptw_fv=a0021014  (PTW working on this address)
  
  fill_ppn 从 805df → 809b7 变化:
    cycle 264378816-264378829: fill_ppn=805df (previous fill residual)
    cycle 264378830-264378840: fill_ppn=809b7 (L1 PTE PPN, walk progressed to L0)

cycle 264378840 (line 111, forensic idx 122):
  d_state=2  (PTW walk)
  PTW reads L0 PTE @ 0x809b7084 → data = 0x00000000 (V=0)
  ptw_fc=f (15)  ptwfv=a0021014
  fill_ppn=0809b7  (L1 PTE's PPN, used for L0 table base)
```

#### Phase 5: PTW fault 生成 (cycle 264378841-264378843)

```
cycle 264378841 (line 112, forensic idx 123):
  ptw_fault=0  (not yet)
  coll_d=0  (no TLB collision)

cycle 264378842 (line 113, forensic idx 124):
  ptw_fault starts:
  forensic idx 124: ptwfk=1  (PTW fault kill — PTW detected V=0, generating fault)
  ptw_fc=f (15)  ptwfv=a0021014
  fill_ppn=000000  (no fill, fault instead)
  coll_i=0  coll_d=0  ← 无 TLB collision

cycle 264378843 (line 114, forensic idx 125):
  d_pf=1  (D-side page fault asserted!)
  d_pfc=15  (cause = 15 = store page fault)
  d_pfv=a0021014  (fault virtual address)
  dpfptw=1  (page fault from PTW)
  d_state=2  (still in walk state, fault propagating)
  ptw_fault=0  (PTW fault already consumed)
  spf=0  lpf=0  saf=0  laf=0  (no other faults)
```

#### Phase 6: Exception 锁存 + Trap 进入 (cycle 264378844-264378845)

```
cycle 264378844 (line 115, forensic idx 126):
  d_pf=0  (page fault deasserted, latched into exception)
  d_ready=0  (data not ready, fault instead)
  d_state=1  (back to lookup state)
  
  Forensic idx 126:
    exv=1  (exception_valid_r asserted)
    excause=0x0000000f  (exception cause = 15)
    expc=c01df3c8  (exception PC = faulting instruction)
    exvr=1  (exception valid register)
    dtv=0  dtmiss=0  (TLB invalidated)
    spf=0  (not store page fault from TLB, it's from PTW)

cycle 264378845 (line 116, forensic idx 127):
  d_ready=1  (D-side "ready" with fault)
  
  Forensic idx 127:
    exv=1  excause=0x0000000f  expc=c01df3c8  exvr=1
    trap=1  (trap_enter state)
    hwc=0x0000000f  (hardware cause = 15)
    hwe=c01df3c8  (hardware EPC)
    hwt=a0021014  (hardware TVAL)
    tpc=c037fa58  (trap target PC = handle_exception)
    priv=1  tpriv=1  (S-mode → S-mode trap)
    dtv=1  dtmiss=1  (TLB miss, entry invalidated)
    dmiss=1  (D-side miss)
    spf=1  (store page fault flag set)
```

### 4.3 TLB Collision 检查 (仅限本次窗口)

整个 128 周期 forensic 窗口和 116 行 dmmu trace 中:

```
coll_i = 0  (全部行)
coll_d = 0  (全部行)
```

**本次 forensic 窗口内无 TLB BRAM collision。** 但这只是最终 trap 前 128 周期的局部结论。simulate.log 末尾之前仍存在大量 Xilinx BRAM collision warning，发生在 trap 之前的更早时点。更早的 collision 是否曾污染页表建立过程 (vzalloc 期间的 ~71K 周期) 尚不可知，不能全局排除 collision 对当前 bug 的贡献。

### 4.4 Stale TLB Entry 分析

```
d_ppn = 0x80441  (出现在所有 a0021014 相关行中)
d_tlb_v = 0  (TLB entry invalid, not used)
```

PPN 0x80441 是 TLB BRAM 中某个 way 的残留数据，对应一个之前的映射。由于 `d_tlb_v=0`，该条目不参与翻译。PTW walk 从 satp 指向的页表根开始独立遍历，不使用 TLB 中的 stale 数据。

**结论: stale TLB entry 是 red herring，不影响 PTW walk 结果。**

---

## 5. Forensic Buffer 关键数据

来源: `trap_forensics_dump.log` (128 周期，126 个信号)

### 5.1 PTW Walk 在 forensic 中的体现

forensic buffer 记录了 trap 前 128 周期的 CPU 内部信号。关键时间点:

| idx | cycle | 事件 | 关键信号 |
|-----|-------|------|---------|
| 110 | 264378828 | L1 PTE 读取 | mpa=808fda00 (i-side fetch addr), ptwfc=f, ptwfv=a0021014, fillppn=0805df→0809b7 |
| 114 | 264378832 | L0 PTE 地址计算 | mpa=809b7084, fillppn=0809b7 (L1 PTE's PPN) |
| 122 | 264378840 | L0 PTE=0 返回 | ptwfc=f, ptwfv=a0021014, fillppn=0809b7, data=00000000 |
| 124 | 264378842 | PTW fault 生成 | ptwfk=1 (PTW fault kill), fillppn=000000 |
| 125 | 264378843 | D-side page fault | dpf=1, dpfc=15, dpfv=a0021014, dpfptw=1 |
| 126 | 264378844 | Exception 锁存 | exv=1, excause=0x0f, expc=c01df3c8 |
| 127 | 264378845 | Trap enter | trap=1, hwc=0x0f, hwe=c01df3c8, hwt=a0021014, tpc=c037fa58 |

### 5.2 Trap 入口地址确认

```
tpc = 0xc037fa58
```

这是 `handle_exception` 的入口地址。trap_deleg.log 中 FPGA 观察到的 trap-loop PC 范围是 c037fa58-c037fa78，与 tpc=c037fa58 一致。

### 5.3 D-side TLB 状态变化

| idx | dtv | dtmiss | dtppn | dpfptw | spf | 说明 |
|-----|-----|--------|-------|--------|-----|------|
| 122 | 0 | 0 | 080441 | 0 | 0 | PTW walk 中, TLB invalid |
| 125 | 0 | 0 | 080441 | 1 | 0 | PTW fault 生成 |
| 126 | 0 | 0 | 080441 | 0 | 0 | Exception 锁存 |
| 127 | 1 | 1 | 080441 | 0 | 1 | Trap enter, TLB miss recorded, spf=1 |

**dtppn=080441 全程不变**: stale TLB entry 的 PPN，由于 dtv=0 (除 idx 127 外) 不参与翻译。idx 127 的 dtv=1 + dtmiss=1 表示 TLB miss 被记录 (trap 处理需要重新 walk)。

### 5.4 I-side 状态 (对比)

```
所有 128 周期:
  if_pc = c01df3cc  (trap 前一直停在 sw 的下一条指令)
  if_inst = 00952a23
  id_pc = c01df3c8
  id_inst = 00952a23  (sw s1,20(a0))
  mpa = 805df3cc  (i-side physical address, 正确翻译)
  mmiss = 0  (i-side fetch 正常)
  mpf = 0  (i-side 无 page fault)
```

I-side (取指) 全程正常。c01df3cc → 805df3cc 的翻译正确 (kernel linear mapping)。**取指路径无问题。**

---

## 6. vzalloc_node_noprof 调用链分析

### 6.1 调用路径

```
gen_pool_add_owner (c01df3b4)
  └─ vzalloc_node_noprof (c00e7394)
       └─ __vmalloc_node_noprof (c00e7248)
            ├─ __vmalloc_area_node  (分配 vmalloc 区域 + 物理页)
            │    ├─ alloc_vmap_area  (在 vmalloc 区域中分配虚拟地址范围)
            │    ├─ alloc_pages_node (分配物理页)
            │    └─ map_kernel_range (建立页表映射)
            │         └─ ... (set_pte / pte_set 等)
            └─ memset (清零分配的内存)
```

### 6.2 vzalloc_node_noprof 反汇编

```
c00e7394 <vzalloc_node_noprof>:
c00e7394:  ff010113    addi  sp,sp,-16
c00e7398:  00812423    sw    s0,8(sp)
c00e739c:  00112623    sw    ra,12(sp)
c00e73a0:  01010413    addi  s0,sp,16
c00e73a4:  00001637    lui   a2,0x1
c00e73a8:  00008713    mv    a4,ra
c00e73ac:  00058693    mv    a3,a1
c00e73b0:  dc060613    addi  a2,a2,-576    # a2 = 0xdc0 (GFP_KERNEL)
c00e73b4:  00100593    li    a1,1
c00e73b8:  e91ff0ef    jal   c00e7248 <__vmalloc_node_noprof>
c00e73bc:  00c12083    lw    ra,12(sp)
c00e73c0:  00812403    lw    s0,8(sp)
c00e73c4:  01010113    addi  sp,sp,16
c00e73c8:  00008067    ret
```

vzalloc_node_noprof 是 __vmalloc_node_noprof 的薄包装。__vmalloc_node_noprof 负责分配 vmalloc 区域、分配物理页、建立页表映射。

### 6.3 dmmu trace 中的时间跳转

```
cycle 264307883:  D-side access during jal vzalloc_node_noprof (c01df3c0)
cycle 264378812:  D-side access during sw s1,20(a0) (c01df3c8)
```

时间差: 264378812 - 264307883 = 70929 周期

vzalloc_node_noprof 执行了约 70929 周期 (~71K cycles)，在这期间建立了 (或应该建立) vmalloc 页表映射。但 dmmu trace 没有记录这期间的 D-side 事件 (trace 只在 a0021 相关事件或特定条件下触发)。

---

## 7. 根因分析

L0 PTE @ 0x809b7084 = 0x00000000 (V=0) 是直接原因。日志只证明了：PTW 读取 0x809b7084 时 SRAM (BRAM) 中该 word 为 0。**至于为什么为 0，目前仍属推测，日志不足以区分以下任何一种假设。**

### 当前 bug 的定位边界

- **已排除**: trap-loop 不是取指异常 (if_sanity.log + forensic 确认取指路径正确)；最终 trap 不是 ecall (cause=9 是 CSR 残留值)；最终 walk 序列在给定内存内容下正确。
- **已定位**: bug 边界推进到 "vmalloc 返回 a0021000，但对应 L0 PTE (0x809b7084) 在 PTW 可见的 SRAM 中仍为 0"。
- **未定位**: 0x809b7084 为 0 的原因。下一轮调查的焦点应是 vzalloc_node_noprof 执行的约 71K 周期内 PTE 写入路径，而不是最终 trap。

### 候选假设 (并列，无优先级)

#### 假设 1: 页表建立代码未执行到 PTE store

CPU 在 vzalloc_node_noprof 执行期间 (cycle 264307883 - 264378812, ~71K 周期) 的某条指令上出错，导致 map_kernel_range / set_pte 等页表建立代码被跳过，PTE store 从未发生。

**验证**: 在 TB 中监控 0x809b7000-0x809b7fff 地址范围的所有 AXI write，确认 vzalloc 期间是否有任何写入。

#### 假设 2: PTE store 写到了错误地址

CPU 执行了 set_pte，但地址计算出错，PTE 被写入了 0x809b7084 以外的位置。

**验证**: 监控 vzalloc 期间所有 D-side store 的物理地址，与 QEMU 执行的地址对比。

#### 假设 3: DCache write-back 未落到 SRAM

CPU 正确执行了 set_pte，PTE 进入 DCache (write-back)，但 DCache 没有将该 cache line 写回 SRAM。PTW walk 直接读 BRAM (绕过 DCache)，读到旧值 0。

**验证**: 
- 检查 DCache flush 指令 (CBO.FLUSH / dcache.flush) 是否在 vzalloc 期间被调用
- 监控 0x809b7084 对应 cache line 的 dirty 状态和 write-back 事件
- 确认 PTW 读路径是否绕过 DCache，以及绕过时 DCache 是否被提前 flush

#### 假设 4: 页表 flush/coherency 问题

PTE store 和后续 PTW walk 之间存在缓存一致性问题。kernel 可能在 store PTE 后执行了 sfence.vma 或 cache flush，但 CPU 对这些指令的实现有缺陷，导致 PTW 仍然看到旧值。

**验证**: 追踪 vzalloc 期间所有 sfence.vma / CBO 指令的执行，检查是否正确触发 DCache flush + TLB invalidate。

#### 假设 5: 更早的执行流已偏离

CPU 在 vzalloc_node_noprof 之前的某条指令上已经偏离了正确执行流，vzalloc 看到的输入数据 (如 page table 指针、alloc 状态) 已经错误，导致它建立了错误的页表或根本没有建立。

**验证**: 对比 QEMU 日志，在 vzalloc 入口处检查寄存器值和内存状态是否一致。

---

## 8. 下一步

**核心方向**: 不再追最终 trap (已充分定位)，转而追 vzalloc_node_noprof 执行的约 71K 周期内 (cycle 264307883 - 264378812)，L0 PTE 地址 0x809b7084 (或 L0 页表页 0x809b7000-0x809b7fff) 的写入路径。

### 8.1 PTE 写入监控

在 TB 中增加对 0x809b7000-0x809b7fff 地址范围的 AXI write 监控：
- 是否有任何 store 写入这个范围？
- 如果有，写入的物理地址、数据、时点是什么？
- 特别关注 0x809b7084 (L0 PTE 地址) 是否被写过

### 8.2 DCache 路径追踪

如果 PTE store 确实发生：
- store 是否进入 DCache (write-back)？
- 对应 cache line 是否曾经 dirty？
- 是否有 write-back 事件将该 cache line 写回 SRAM？
- PTW walk 读 BRAM 时，该 cache line 是否仍为 dirty？

同时检查：
- vzalloc 期间是否有 CBO.FLUSH / dcache.flush / sfence.vma 指令执行？
- 这些指令是否正确触发 DCache flush 到 BRAM？

### 8.3 PTW 读路径确认

确认 PTW walk 的读请求是否完全绕过 DCache，直接读 BRAM。如果是，则 DCache 中仍为 dirty 的 PTE store 不会被 PTW 看到——这正是假设 3 的核心。

### 8.4 更早执行流对比

对比 QEMU 日志，在 vzalloc_node_noprof 入口处 (c00e7394) 检查：
- 通用寄存器值是否一致
- satp、当前 priv 是否一致
- 关键内存状态 (如 vmap_area 列表、page 分配器状态) 是否一致

如果入口处已经偏离，bug 在更早的指令，需要向上追溯。

### 8.5 扩大 forensic 窗口 (可选)

当前 128 周期 forensic 只覆盖 PTW walk 和 trap，不覆盖 vzalloc 执行期间。考虑增加第二个 forensic buffer，在 vzalloc 入口 (c01df3c0 jal) 时触发，覆盖之后的 128 周期，观察 map_kernel_range / set_pte 的执行。

---

## 附录 A: 数据文件路径

```
仿真产物目录:
  project/kernel_boot_sram128_dtb16/simplecpu_soc.sim/sim_1/behav/xsim/

  trap_forensics_dump.log   — 128 周期 forensic buffer (126 信号)
  dmmu_fault_trace.log      — 116 行 D-side MMU 事件
  trap_deleg.log            — trap 委托日志 (修复版)
  if_sanity.log             — 取指健全性检查

RTL 文件:
  src/rtl/core/MMU.sv              — MMU + TLB + PTW
  src/rtl/core/tlb.sv              — TLB BRAM (READ_FIRST)
  src/rtl/core/cpu_trap_manager.sv — exception 锁存
  src/rtl/core/cpu_clint.sv        — hw_trap_cause/epc 生成
  src/tb/tb_kernel_boot.sv         — TB: forensic buffer, dmmu trace, SV32 truth

Kernel:
  build/kernel/vmlinux     — Linux kernel ELF
  build/qemu/boot_kernel2.log — QEMU 参考日志

文档:
  docs/trap-loop-bug-handoff.md  — 交接文档
  docs/trap-loop-analysis.md     — 分析 1 (初始)
  docs/trap-loop-analysis2.md    — 分析 2 (store page fault 确认)
  docs/trap-loop-analysis3.md    — 本文档
  docs/commands-cheatsheet.md    — 命令速查
```

## 附录 B: Forensic 字段定义

```
idx cyc time
if_pc if_inst ifd iv idv idd id_pc id_inst    (I-side fetch/decode)
de decill debrk                                 (decode stage)
exd exv excause expc exmt exvr excr expr extr  (execute/exception)
afv pfv msv exev decc dect                      (exception flags)
trap hwc hwe hwt tpend tpc priv tpriv satp      (trap control)
fva mpa mrdy mmiss mpf mpfc mpfv                (memory/i-side)
mis ws th tv wa pi ics                          (misc)
rr rv ra rd sw wo arv arr ara rvv rry rls rdt   (pipeline)
shadow mempc meminst memv memdone memen memwe msize mvaddr mwdata  (mem stage)
dpaddr drdy dmiss dpf dpfc dpfv ds              (D-side)
dlatv dlatatype dlatpriv dlatsatp dlatsum dlatmxr dinchg  (D-side latency)
dth dtv dtperm dtmiss dtppn dtr dtw dtx dtu dta dtd dtg dtmega  (D-side TLB)
dpfptw spf lpf saf laf                          (page fault flags)
ptwd ptwf ptwfc ptwfv ptwfk                     (PTW walk)
fill fillvpn fillppn fillasid fillr fillw fillx fillu filla filld fillg fillmega  (TLB fill)
coll_i coll_d                                   (TLB collision)
```

## 附录 C: DMMU Trace 字段定义

```
cyc time event
mem_pc mem_inst mem_en mem_we mem_vaddr mem_wdata  (memory stage)
d_paddr d_ready d_miss d_pf d_pfc d_pfv d_state    (D-side result)
d_lat_vaddr d_atype d_priv d_sum d_mxr             (D-side latency/config)
d_tlb_v d_tlb_h d_tlb_perm d_tlb_miss d_ppn        (D-side TLB)
d_r d_w d_x d_u d_a d_d d_g d_mega                 (TLB permissions)
ptw_done ptw_fault ptw_fc ptw_fv                   (PTW walk result)
fill fill_vpn fill_ppn fill_r fill_w fill_x fill_u fill_a fill_d  (TLB fill)
coll_i coll_d                                       (TLB collision)
hwc hwe hwt scause stval sepc                      (trap/CSR)
```
