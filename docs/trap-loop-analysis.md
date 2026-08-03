# Trap-Loop Bug 分析推导

> **日期**：2026-06-27 04:30
> **仿真配置**：#4 (128MB SRAM + 16MB DTB)
> **Trap 发生 cycle**：264378846

---

## 一、关键文件

### 仿真产物（本次 #4 仿真）

```
project/kernel_boot_sram128_dtb16/simplecpu_soc.sim/sim_1/behav/xsim/
├── if_sanity.log          # IF sanity checker 事件日志（640万行，最重要）
├── trap_deleg.log         # trap 委托日志（19861行）
├── trap_trace.log         # trap trace
├── uart_tx.log            # UART 输出（kernel printk）
├── simulate.log           # probe 日志（每1M周期一条）
└── prog.hex               # 加载的固件 hex
```

### RTL 源码

```
src/rtl/core/cpu_trap_manager.sv    # trap 生成逻辑（exception_valid, exception_cause）
src/rtl/core/cpu_clint.sv           # trap 委托 + cause 选择（hw_mcause_wdata）
src/rtl/core/cpu_decode.sv          # 译码（dec_is_ecall 生成）
src/rtl/core/cpu_fetch.sv           # 取指（if_inst = instData_32）
src/rtl/core/core_top.sv            # 顶层（if_id_bus_r 寄存器，id_inst_wire）
src/tb/tb_kernel_boot.sv            # TB（sanity checker 代码）
src/tb/tb_soc_includes.svh          # TB 共享（if_inst/id_inst 的 wire 定义）
```

### 参考

```
build/kernel/vmlinux               # kernel ELF（可反汇编）
build/qemu/boot_kernel2.log        # QEMU 参考日志
```

---

## 二、关键数据

### 数据 1：trap_deleg.log 过渡点（行 115-122）

```
# 格式: #  Cycle  Time  Event  PC  Priv  TPriv  Cause  Deleg  ToS  EPC  EMTVAL  IPF_VA  HW_EPC  HW_TVAL  HW_WEN  HW_TPRIV  MEDELEG

115  1737727925000  RET       800005a0  3  --  --  --  --  --  --  --  800005a0  00000000  --  --  0000b109
116  1737857205000  TRAP_IN   c0010bbc  1  3   00000009  0  0  c0010bbc  00000000  80400098  c0010bbc  00000000  1  3  0000b109
117  1737952335000  RET       800005a0  3  --  --  --  --  --  --  --  800005a0  00000000  --  --  0000b109
118  2643788485000  TRAP_IN   c01df3cc  1  1   00000009  1  1  c01df3c8  a0021014  80400098  c01df3c8  a0021014  1  1  0000b109
119  2643789895000  TRAP_IN   c037fa68  1  1   00000009  1  1  c01df3c8  a0021014  80400098  c01df3c8  a0021014  1  1  0000b109
120  2643790895000  TRAP_IN   c037fa78  1  1   00000009  1  1  c037fa74  ffffff74  80400098  c037fa74  ffffff74  1  1  0000b109
```

- trap #116：最后一次正常 ecall，EPC=c0010bbc（`__sbi_ecall` 中的 `ecall` 指令），cause=9，M-mode 处理（deleg=0）
- trap #117：mret 返回
- trap #118：**首次假 ecall**，EPC=c01df3c8，cause=9，S-mode 处理（deleg=1），EMTVAL=a0021014
- trap #119+：handle_exception 自身也触发 cause=9 → trap-loop

### 数据 2：if_sanity.log trap 前后事件（行 7178789-7178795）

```
# 格式: Cycle  Time  Event  PC  INST  PADDR  AUX0  AUX1  AUX2  AUX3

7178789: 264378807  2643788105000  IF_MAP      c01df3c8  00952a23  805df3c8  c01df3c8  800808fd  0  1
7178790: 264378816  2643788195000  PTW_START   c01df3cc  00952a23  805df3cc  c01df3cc  1  800808fd  1  1
7178791: 264378843  2643788465000  PTW_DONE    c01df3cc  00952a23  805df3cc  c01df3cc  c01df3cc  1  1
7178792: 264378846  2643788495000  PTW_START   c037fa58  00952a23  805df3cc  c01df3cc  1  800808fd  1  1
7178793: 264378850  2643788535000  I_MISS      c037fa58  00028067  c037fa58  c037fa58  1  800808fd  1  1
7178794: 264378875  2643788785000  PTW_DONE    c037fa58  00028067  c037fa58  c037fa58  c037fa58  0  0
7178795: 264378876  2643788795000  PTW_START   c037fa58  00028067  c037fa58  c037fa58  1  800808fd  2  2
```

- cycle 264378807：IF_MAP，PC=c01df3c8，inst=00952a23（`sw s1,20(a0)`），paddr=805df3c8 — 取指正确
- cycle 264378816：PTW walk 开始，为 c01df3cc 取指
- cycle 264378843：PTW walk 完成，TLB hit=1, valid=1
- cycle 264378846：**PC 突变为 c037fa58（handle_exception）** — trap 发生！但 inst 仍显示 00952a23
- cycle 264378850：I_MISS，PC=c037fa58，inst=00028067 — 开始取 handle_exception 的指令

### 数据 3：反汇编

```
c01df3c8:  00952a23  sw s1,20(a0)       # gen_pool_add_owner 中的 store
c0010bbc:  00000073  ecall              # __sbi_ecall 中的合法 ecall

c037fa58 <handle_exception>:
c037fa58:  14021273  csrrw tp,sscratch,tp
c037fa5c:  00021663  bnez tp,c037fa68
c037fa68:  00222623  sw sp,12(tp)
c037fa6c:  00822103  lw sp,8(tp)
c037fa70:  f7010113  addi sp,sp,-144
c037fa74:  00112223  sw ra,4(sp)
c037fa78:  00312623  sw gp,12(sp)
```

### 数据 4：sanity checker 触发结果

| 触发器 | 条件 | 结果 |
|--------|------|------|
| FETCH_TRUTH_MISMATCH | if_inst ≠ BRAM[paddr] | **未触发** |
| DECODE_ECALL_MISMATCH | dec_is_ecall=1 且 if_inst≠0x73 | **未触发** |
| SUSPICIOUS_ECALL_TRAP | cause=9 且 EPC≠c0010bbc | **未触发** |

### 数据 5：RTL 信号链

```
cpu_fetch.sv:
  if_inst = instData_32                          # 当前周期 IF 阶段指令

core_top.sv:
  if_id_bus = {pc_plus4, pc, instData_32}        # IF→ID 流水线总线
  if_id_bus_r <= if_id_bus (每周期锁存)           # ID 阶段寄存器
  id_inst_wire = if_id_bus_r[31:0]               # 上一周期的 if_inst

cpu_decode.sv:
  assign {pc_plus4, pc, inst} = if_id_bus_r;     # inst = id_inst = 上一周期的 if_inst
  is_ecall = (opcode==1110011) && (funct3==000) && (inst[31:20]==000)  # inst==0x00000073
  dec_is_ecall = id_valid && valid_inst && is_ecall

cpu_trap_manager.sv:
  exception_at_decode = (id_valid && id_done) && (dec_illegal || dec_is_ecall || dec_is_ebreak) && !inst_access_fault_r && !inst_page_fault_r
  decode_exception_cause = dec_is_ecall ? (priv==S ? 9 : ...) : ...
  exception_valid = access_fault_valid || pf_valid || exception_at_decode || misalign || exe
  exception_cause = access_fault ? ... : pf ? ... : exception_at_decode ? decode_exception_cause : ...
  // 时序: exception_valid_r 在下一周期锁存 exception_valid/cause/pc/mtval

cpu_clint.sv:
  trap_enter = exception_valid_r || m_interrupt || s_interrupt
  hw_mcause_wdata = exception_valid_r ? exception_cause_r : m_interrupt_cause
  // cause=9 且非中断(无0x80000000位) → 来自 exception_cause_r → 来自 decode_exception_cause → dec_is_ecall
```

---

## 三、推导过程

### 推导 1：trap cause=9 只能来自 dec_is_ecall

```
trap_deleg.log trap #118: cause=00000009 (无 0x80000000 位，不是中断)

cpu_clint.sv:
  hw_mcause_wdata = exception_valid_r ? exception_cause_r : m_interrupt_cause
  m_interrupt_cause = 0x8000000B / 0x80000007 / 0x80000003 (都有 bit31=1)
  → cause=0x00000009 没有 bit31 → 来自 exception_cause_r

cpu_trap_manager.sv:
  exception_cause = access_fault ? (1/5/7) : pf ? (12/13/15) : exception_at_decode ? decode_exception_cause : misalign ? (4/6) : 0
  → cause=9 只能来自 decode_exception_cause

  decode_exception_cause = dec_is_ecall ? (priv==S ? 9 : ...) : ...
  → cause=9 需要 dec_is_ecall=1 且 priv_mode==PRIV_S
```

**结论 1：trap #118 的 cause=9 要求 `dec_is_ecall` 在某个周期被置位。**

### 推导 2：dec_is_ecall 要求 id_inst=0x00000073

```
cpu_decode.sv:
  dec_is_ecall = id_valid && valid_inst && is_ecall
  is_ecall = (opcode==1110011) && (funct3==000) && (inst[31:20]==000)
  inst = if_id_bus_r[31:0] = id_inst

  → dec_is_ecall=1 要求 id_inst == 0x00000073
```

**结论 2：trap #118 要求 `id_inst` 在某个周期等于 `0x00000073`。**

### 推导 3：if_inst 和 id_inst 的时序关系

```
cpu_fetch.sv:
  if_inst = instData_32                          # cycle N 的 IF 阶段

core_top.sv:
  if_id_bus = {pc_plus4, pc, instData_32}        # cycle N
  if_id_bus_r <= if_id_bus                        # cycle N+1 锁存
  id_inst = if_id_bus_r[31:0]                     # cycle N+1 的 id_inst = cycle N 的 if_inst

  → id_inst[cycle N+1] = if_inst[cycle N]
  → id_inst 比 if_inst 晚一个周期
```

**结论 3：`id_inst` 是 `if_inst` 上一周期的值。**

### 推导 4：DECODE_ECALL_MISMATCH 有时序错位

```
TB sanity checker:
  DECODE_ECALL_MISMATCH 条件: dec_is_ecall && (if_inst !== 32'h00000073)

  dec_is_ecall 用的是 id_inst（上一周期的 if_inst）
  但检查的 if_inst 是当前周期的值

  → 如果 cycle N 的 id_inst=0x73 (dec_is_ecall=1)，
    此时 if_inst 是 cycle N 的新指令，不是 id_inst 对应的那条
  → 两者不是同一条指令，比较无意义
```

**结论 4：`DECODE_ECALL_MISMATCH` 不会触发，因为 `if_inst` 和 `dec_is_ecall` 引用的指令相差一个周期。这不是 bug 没被捕获的原因，而是检查条件本身有时序错位。**

### 推导 5：trap 发生时刻的指令不是 ecall

```
if_sanity.log:
  cycle 264378807: IF_MAP  PC=c01df3c8  inst=00952a23   ← 这是 if_inst
  cycle 264378816: PTW_START  PC=c01df3cc  inst=00952a23  ← if_inst 仍为 00952a23
  cycle 264378843: PTW_DONE   PC=c01df3cc  inst=00952a23  ← if_inst 仍为 00952a23
  cycle 264378846: PTW_START  PC=c037fa58  inst=00952a23  ← trap 发生！PC 已跳，但 if_inst 还没更新

  trap_deleg.log trap #118:
    EPC=c01df3c8  ← 这是 exception_pc_r，即 trap 发生时 id_pc 的值
    → id_pc=c01df3c8 意味着 id_inst 对应的指令是 c01df3c8 处的指令
    → c01df3c8 的真实指令是 00952a23 (sw s1,20(a0))
    → id_inst 应该是 00952a23，不是 0x00000073
```

**结论 5：trap 发生时 `id_inst` 应为 `00952a23`（`sw s1,20(a0)`），不是 ecall。但 `cause=9` 要求 `dec_is_ecall=1`，而 `dec_is_ecall` 要求 `id_inst=0x73`。矛盾。**

### 推导 6：EMTVAL=a0021014 是异常值

```
RISC-V 规范: ecall 的 mtval 应为 0
trap #118: EMTVAL=a0021014 (非零)

cpu_trap_manager.sv:
  decode_exception_mtval = dec_illegal ? id_inst : 32'b0
  → ecall 的 mtval 应该是 0

  但 trap #118 的 EMTVAL=a0021014 ≠ 0
  → 要么 mtval 生成逻辑有 bug
  → 要么 cause=9 不是来自正常的 decode_exception 路径
```

**结论 6：`EMTVAL=a0021014` 非零，不符合 ecall 的正常行为，进一步证明 trap #118 不是正常的 ecall trap。**

### 推导 7：FETCH_TRUTH_MISMATCH 未触发说明取指数据正确

```
TB sanity checker (SRAM 模式, cycle ≥ 200M):
  if (if_done && inst_valid_mux && mmu_inst_ready && !mmu_inst_page_fault &&
      is_sram_cacheable_addr(mmu_inst_paddr)) begin
      dbg_expected_inst = BRAM[mmu_inst_paddr[26:2]];
      if (if_inst !== dbg_expected_inst) → $finish

  → if_inst == BRAM[mmu_inst_paddr] 对所有 ≥200M 周期成立
  → 取指数据从内存到 if_inst 的路径是正确的
```

**结论 7：取指路径（MMU翻译 → icache → 总线 → SRAM）数据正确，`if_inst` 的值与内存一致。**

### 推导 8：IF_MAP 显示 MMU 翻译正确

```
if_sanity.log cycle 264378807:
  IF_MAP  PC=c01df3c8  inst=00952a23  PADDR=805df3c8  VADDR=c01df3c8

  vaddr=c01df3c8 → paddr=805df3c8

  BRAM shadow check 已经验证 if_inst == BRAM[paddr]
  → paddr 是正确的（至少 BRAM 里存的就是正确的指令）
```

**结论 8：MMU 翻译的 paddr 正确（至少对 c01df3c8 这条指令而言），因为 BRAM[paddr] 返回的指令与 if_inst 一致且是正确的 `00952a23`。**

---

## 四、核心矛盾

```
trap #118: cause=9, EPC=c01df3c8

cause=9 → dec_is_ecall=1 → id_inst=0x00000073
EPC=c01df3c8 → id_pc=c01df3c8 → 该地址的指令是 00952a23 (sw)

id_inst 不能同时是 0x00000073 (ecall) 和 00952a23 (sw)

且 EMTVAL=a0021014 ≠ 0 (ecall 的 mtval 应为 0)

且 FETCH_TRUTH_MISMATCH 未触发 (if_inst == BRAM[paddr], 取指正确)
且 IF_MAP 显示 vaddr→paddr 翻译正确
```

**矛盾总结：CPU 取到了正确的指令 `00952a23`，但 trap 生成逻辑输出了 `cause=9`（ecall）和 `EPC=c01df3c8`。这意味着要么 `dec_is_ecall` 在 `id_inst≠0x73` 时被错误置位，要么 `exception_cause_r` 被错误地锁存为 9。**

---

## 五、无法确定的部分（需要进一步验证）

1. **trap 前一个周期的 `id_inst` 实际值**：if_sanity.log 只记录事件边沿，没有每周期的 `id_inst`。需要确认 trap 前一个周期 `id_inst` 是否真的是 `0x00000073`。

2. **`exception_valid_r` 是否被错误锁存**：如果某个异常源（如 `inst_access_fault_r`）在 trap 前一个周期置位，但 `exception_cause` 被错误地选为 `decode_exception_cause`，就会产生错误的 cause=9。

3. **EMTVAL=a0021014 的来源**：这个值不符合任何正常的 mtval 生成逻辑。`decode_exception_mtval` 对 ecall 返回 0，对 illegal 返回 id_inst。`a0021014` 既不是 0 也不是 `00952a23`，可能是寄存器残留或组合逻辑 bug。

---

## 六、下一步验证方向

需要确认的核心问题：**trap 前一个周期（cycle 264378845），`id_inst` 的实际值是什么？`exception_valid` 和 `exception_cause` 的实际值是什么？**

### 方案 A：增加 id_inst 每周期监控

在 TB 的 sanity checker 中，当 `dec_is_ecall` 置位时，记录 `id_inst`（而非 `if_inst`）的值。修改 `DECODE_ECALL_MISMATCH` 的条件为 `dec_is_ecall && (id_inst !== 0x73)`，或者直接在 `ECALL_DECODE` 事件中输出 `id_inst`。

### 方案 B：增加 trap 前周期快照

在 TB 中增加一个深度 10 的环形缓冲区，每周期记录 `{id_inst, id_pc, dec_is_ecall, exception_valid, exception_cause, exception_valid_r, exception_cause_r}`。当 `trap_enter_valid && cause==9 && epc!=c0010bbc` 时 dump 缓冲区。

### 方案 C：直接分析 RTL

检查 `exception_valid_r` 和 `exception_cause_r` 的锁存条件，看是否存在以下场景：
- `exception_valid` 被 `access_fault_valid` 或 `pf_valid` 置位
- 但 `exception_cause` 选择了 `decode_exception_cause`（因为组合逻辑优先级问题）
- 导致 cause 被错误地设为 9
