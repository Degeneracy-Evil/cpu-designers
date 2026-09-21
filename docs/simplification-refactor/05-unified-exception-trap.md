# CPU 代码简化重构：Unified Exception / Trap

> 分支：`chp`  
> 前置阶段：Architecture Foundation 已完成。  
> 本文定义 Phase 6：统一同步异常与 Trap 控制路径。目标是在不改变严格串行 CPU 模型的前提下，消除现有异常路径的多套 pending/glue，并使所有同步异常都遵守同一 architectural contract。

---

# 1. 当前状态

Architecture Foundation 已经建立：

- `priv_mode_t`；
- `mem_kind_t`；
- `access_class_t`；
- `exception_t`；
- typed IF→ID、ID→EXE、EXE→MEM、WB bus；
- architectural memory access / physical request 分离；
- SoC address-map contract。

当前 `exception_t` 已存在：

```systemverilog
typedef struct packed {
    logic        valid;
    logic [31:0] cause;
    logic [31:0] epc;
    logic [31:0] tval;
} exception_t;
```

但 exception control path 仍然保留旧结构。

Controller 当前仍直接感知：

```text
exception_at_decode
fetch_fault_pending
data_fault_pending
trap_pending
```

Trap manager 仍维护多组独立寄存器：

```text
inst_access_fault_r
load_access_fault_r
store_access_fault_r

inst_page_fault_r
load_page_fault_r
store_page_fault_r
```

Execute 和 MEM 的 misalignment 也仍然通过独立 sideband 信号进入 Trap manager。

因此当前代码虽然已经有 `exception_t`，但还没有真正形成 unified exception architecture。

---

# 2. 本阶段目标

本阶段完成后：

```text
Fetch exception  ─┐
Decode exception ─┤
Execute exception ├──> exception_t ──> one exception latch ──> Trap router
Memory exception ─┘

Interrupt pending ────────────────────────────────> Trap router
```

Controller 只感知：

```text
sync_exception_pending
interrupt_pending
```

不再知道：

```text
page fault
access fault
illegal instruction
ecall
ebreak
misalignment
```

的具体类型。

同步异常必须在 faulting instruction 成功完成之前截断正常状态流。

---

# 3. Foundation 收尾清理

在正式重构 exception path 前，先完成几项只涉及 contract 命名的清理。

## 3.1 ID→EXE operand 命名

当前 `id_exe_bus_t` 中：

```text
csr_rs1_value
store_data
```

实际上分别被 Execute 当作通用：

```text
rs1_value
rs2_value
```

使用。

改为：

```systemverilog
logic [31:0] rs1_value;
logic [31:0] rs2_value;
```

进入 EXE→MEM 后，`rs2_value` 再被解释成 `store_data`。

不要让 typed contract 的 field name 暗示错误的生命周期语义。

## 3.2 删除无用 is_csr field

如果 `id_exe_bus_t.is_csr` 已无实际消费者，删除该字段。

CSR access 由：

```text
controller STATE_CSR_ACCESS
cpu_csr_interface
csr_addr / csr_funct3 / csr_uimm / rs1
```

表达，不需要在 typed bus 中额外保留 redundant boolean。

## 3.3 删除 result_ok

当前进入 EXE 的 instruction 已经由 Decode legality 和 Controller flow 保证有效。

如果确认 `exe_mem_bus_t.result_ok` 在所有合法 EXE completion 上恒为 1，则删除：

```text
result_ok
```

WB enable 直接由 instruction semantics 决定。

不要继续保留“理论上可能 invalid，但实际上不会进入 EXE”的历史保护位。

## 3.4 删除错误历史注释

删除 core_top 中已经与实际 wiring 不一致的旧：

```text
BUG-MMU-3 REVERTED ...
```

以及类似会误导后续维护者的 historical bug narrative。

代码注释只描述当前 contract，不保留已经失效的临时调试结论。

---

# 4. Stage Exception Contract

每个可能产生同步异常的 stage 都应向上层提供一个 `exception_t`。

目标接口：

```text
fetch_exception
decode_exception
exe_exception
mem_exception
```

严格串行 CPU 在任意时刻只有一个 stage 有效，因此正常情况下最多只有一个 exception candidate valid。

不设计复杂的多异常仲裁器。

---

# 5. Fetch Exception

Fetch exception 不要求由 `cpu_fetch` 自己产生，因为 translation 和 ICache error 位于外部。

在 core_top 根据当前 Fetch architectural request 形成：

```text
instruction access fault
instruction page fault
```

目标：

```systemverilog
exception_t fetch_exception;
```

语义：

### ICache / downstream access fault

```text
valid = 1
cause = 1
epc   = current fetch PC
tval  = faulting fetch VA
```

### MMU instruction access fault

```text
valid = 1
cause = 1
epc   = current fetch PC
tval  = MMU fault VA
```

### MMU instruction page fault

```text
valid = 1
cause = 12
epc   = current fetch PC
tval  = MMU fault VA
```

Fetch exception candidate 必须由 `if_valid` gate。

已经 redirect / trap 后到达的 stale ICache response 不得产生新的 architectural exception。

---

# 6. MMU Fault Interface 收口

当前 MMU 输出名称：

```text
i_page_fault
i_pf_cause
i_pf_vaddr

d_page_fault
d_pf_cause
d_pf_vaddr
```

实际 cause 同时可能是：

```text
1 / 5 / 7     access fault
12 / 13 / 15  page fault
```

因此 `*_page_fault` 这个名字已经不真实。

改为：

```text
i_fault
i_fault_cause
i_fault_vaddr

d_fault
d_fault_cause
d_fault_vaddr
```

MMU 只报告：

```text
fault valid
architectural cause
fault VA
```

core_top 不再通过多个 page/access boolean 重新解释 MMU 内部故障来源。

---

# 7. Decode Exception

Decode 直接生成：

```systemverilog
exception_t decode_exception;
```

不再把：

```text
dec_illegal
dec_is_ecall
dec_is_ebreak
```

单独送入 Trap manager。

Decode exception：

### Illegal instruction

```text
cause = 2
epc   = instruction PC
tval  = instruction bits
```

### EBREAK

```text
cause = 3
epc   = instruction PC
tval  = 0
```

### ECALL

```text
U-mode -> cause 8
S-mode -> cause 9
M-mode -> cause 11

epc  = instruction PC
tval = 0
```

所有当前 Decode legality 检查继续存在，包括：

```text
CSR legality
CSR privilege
read-only CSR write
MRET privilege
SRET privilege / TSR
WFI / TW
SFENCE.VMA / TVM
SATP / TVM
```

这些最终都统一表现为 illegal-instruction exception。

---

# 8. Execute Exception

`cpu_execute` 不再输出：

```text
exe_misalign_valid
exe_misalign_target
```

改为：

```systemverilog
output exception_t exe_exception;
```

当前唯一 Execute-stage synchronous exception 是 control-flow target misalignment：

```text
cause = 0
epc   = current instruction PC
tval  = branch/JAL/JALR target
```

JALR 仍先按 ISA 规则清除 bit 0，再判断 RV32 当前无 C extension 时的 4-byte alignment。

---

# 9. Memory Exception

`cpu_mem` 负责自己能够确定的 architectural exception：

```systemverilog
output exception_t mem_local_exception;
```

主要是 address misalignment。

### LOAD / LR misaligned

```text
cause = 4
epc   = memory instruction PC
tval  = effective VA
```

### STORE / SC / AMO misaligned

```text
cause = 6
epc   = memory instruction PC
tval  = effective VA
```

删除：

```text
mem_misalign_load
mem_misalign_store
mem_misalign_addr
```

这些 sideband 信号。

---

# 10. Memory External Exception

MMU / DCache 产生的异常在 core_top 转换为另一个 `exception_t`，再与 `mem_local_exception` 合并。

### MMU data fault

直接使用 MMU 的 architectural cause：

```text
cause = d_fault_cause
epc   = memory instruction PC
tval  = d_fault_vaddr
```

可能 cause：

```text
5   load access fault
7   store/AMO access fault
13  load page fault
15  store/AMO page fault
```

### DCache / downstream bus error

根据 stable architectural `mem_access_type` 分类：

```text
ACCESS_LOAD  -> cause 5
ACCESS_STORE -> cause 7

epc  = memory instruction PC
tval = architectural mem_vaddr
```

不得使用 DCache physical error PA 作为 `tval`。

DCache 可以继续保留 PA debug，但 architectural exception path 不消费它。

---

# 11. Memory Exception Priority

由于 cpu_mem 在 alignment check 失败时不会发起 architectural translation 或 physical request，正常情况下：

```text
local misalignment
MMU fault
DCache fault
```

不会同时有效。

仍建议明确 memory exception 合并顺序：

```text
mem_local_exception
    >
MMU fault
    >
DCache fault
```

这里只是 deterministic contract，不引入复杂 priority encoder。

---

# 12. Unified Synchronous Exception Candidate

core_top 最终形成：

```systemverilog
exception_t sync_exception_now;
```

来源：

```text
if_valid  -> fetch_exception
id_valid  -> decode_exception
exe_valid -> exe_exception
mem_valid -> mem_exception
```

由于 CPU 严格串行，当前 active stage 就是 exception ownership。

建议组合逻辑：

```text
default = invalid

if fetch active and fetch_exception.valid
    use fetch_exception
else if decode active and decode_exception.valid
    use decode_exception
else if execute active and exe_exception.valid
    use exe_exception
else if memory active and mem_exception.valid
    use mem_exception
```

不要依据 exception cause 做全局优先级。

---

# 13. One Exception Latch

`cpu_trap_manager` 删除所有独立 fault registers。

删除：

```text
inst_access_fault_r
load_access_fault_r
store_access_fault_r

inst_page_fault_r
load_page_fault_r
store_page_fault_r

对应 PC / address / vaddr registers
```

只保留：

```systemverilog
exception_t exception_r;
```

行为：

```text
if reset:
    exception_r = invalid

else if trap entry consumed:
    exception_r.valid = 0

else if sync_exception_now.valid and exception_r not valid:
    exception_r = sync_exception_now
```

不允许后来的 exception candidate 覆盖一个尚未处理的 exception。

严格串行架构下，这个 one-entry latch 足够。

---

# 14. Controller 接口

删除 Controller 输入：

```text
exception_at_decode
fetch_fault_pending
data_fault_pending
trap_pending
```

新增：

```text
sync_exception_pending
interrupt_pending
```

Controller 不解释 cause。

---

# 15. stage_done 的最终语义

从本阶段开始正式执行 Architecture Foundation 中定义的规则：

> `stage_done` 只表示 stage 成功完成。

同步异常和成功完成互斥。

## Fetch

已有：

```text
if_done = successful instruction fetch only
```

保持。

## Decode

修改为：

```text
decode exception:
    decode_exception.valid = 1
    id_done = 0

normal decode:
    id_done = 1
```

ECALL / EBREAK / illegal CSR 等都不再作为成功 Decode completion。

## Execute

control-flow misalignment：

```text
exe_exception.valid = 1
exe_done = 0
```

因此 core_top 不会执行错误 branch redirect。

## Memory

address misalignment：

```text
mem_local_exception.valid = 1
mem_done = 0
```

MMU / DCache fault 本来就不会形成正常 `mem_done`。

---

# 16. Controller 状态转换

## FETCH

```text
if sync_exception_pending:
    TRAP_ENTER
else if if_done:
    DECODE
else:
    FETCH
```

## DECODE

```text
if sync_exception_pending:
    TRAP_ENTER
else if !id_done:
    DECODE
else:
    normal instruction-class transition
```

## EXEC

```text
if sync_exception_pending:
    TRAP_ENTER
else if !exe_done:
    EXEC
else if branch:
    interrupt_pending ? TRAP_ENTER : FETCH
else if need_mem:
    MEM
else:
    WB
```

## MEM

```text
if sync_exception_pending:
    TRAP_ENTER
else if mem_done:
    WB
else:
    MEM
```

## WB

```text
if wb_done:
    interrupt_pending ? TRAP_ENTER : FETCH
```

---

# 17. Interrupt 只在 architectural boundary 接受

同步异常与 interrupt 的语义不同。

同步异常属于当前 faulting instruction，因此必须立即截断当前 instruction。

interrupt 是 instruction 之间的事件，因此只在一条 instruction 已成功完成后进入 Trap。

需要检查所有“不经过 WB”的 completion path。

### Branch

branch successful completion 后检查 `interrupt_pending`。

### NOP / FENCE

当前 Decode-only normal completion 也必须检查 `interrupt_pending`。

不能继续：

```text
NOP -> FETCH
```

而完全绕过 interrupt。

否则连续 NOP/FENCE 流可能无限推迟 interrupt。

目标：

```text
NOP/FENCE complete
    -> interrupt_pending ? TRAP_ENTER : FETCH
```

### FENCE.I

invalidate 完成后：

```text
interrupt_pending ? TRAP_ENTER : FETCH
```

### SFENCE.VMA

flush 完成后：

```text
interrupt_pending ? TRAP_ENTER : FETCH
```

### CSR / ALU / Load / Store / AMO

这些最终经过 WB，在 WB completion 后检查 interrupt。

### xRET

MRET/SRET 按当前 instruction semantics 先完成 Trap Return。

如果返回后的 privilege/status 允许某个 pending interrupt，下一 architectural boundary 再进入 interrupt trap。

---

# 18. Interrupt Pending 与 Exception Pending 分离

当前 `cpu_trap_manager.trap_pending` 实际主要表示 interrupt pending，但名字模糊。

改为明确：

```text
sync_exception_pending
interrupt_pending
```

`interrupt_pending` 由当前 interrupt enable / delegation / privilege 逻辑计算。

不要为了“当前已有 exception”把 interrupt pending 本身清零。

Controller 通过优先检查：

```text
sync exception
    >
normal stage completion
    >
interrupt at completion boundary
```

自然保证同步异常优先。

---

# 19. Trap Router

当前 `cpu_clint.sv` 实际并不是 memory-mapped CLINT device。

它负责：

```text
exception delegation
interrupt arbitration
trap target privilege
mtvec/stvec target
mepc/sepc
mcause/scause
mtval/stval
mstatus/sstatus trap-entry and xRET updates
```

而真正的平台 CLINT 已经是：

```text
axi4lite_clint.sv
```

因此建议将 `cpu_clint.sv` 重命名为：

```text
cpu_trap_router.sv
```

或等价清晰名称。

本阶段只改变命名和接口，不借机重写其 delegation/interrupt priority 算法。

具体 privileged correctness 仍留给后续 CSR / Privileged review。

---

# 20. Trap Router Exception Input

Trap router 不再接：

```text
exception_valid
exception_cause
exception_pc
exception_mtval
```

四个散乱信号。

直接接：

```systemverilog
input exception_t exception;
```

使用：

```text
exception.valid
exception.cause
exception.epc
exception.tval
```

生成 CSR trap write values。

---

# 21. Trap Manager 目标职责

完成后 `cpu_trap_manager` 只承担三件事：

1. latch 当前 synchronous exception；
2. 接收 Trap router 的 interrupt pending / target result；
3. 向 Controller 和 CSR subsystem 提供 trap control。

不再负责：

```text
识别 page fault
识别 access fault
识别 misalign
解析 ecall/ebreak
保存六套 pending flags
```

这些都已经在 exception source 处转换为 `exception_t`。

---

# 22. cpu_trap_csr 接口收口

`cpu_trap_csr` 不再接大量 fault-specific ports。

删除类似：

```text
dec_illegal
dec_is_ecall
dec_is_ebreak

mem_misalign_load
mem_misalign_store
mem_misalign_addr

exe_misalign_valid
exe_misalign_target

inst_access_fault
load_access_fault
store_access_fault

inst_page_fault
load_page_fault
store_page_fault
...
```

改为核心接口：

```text
sync_exception_now

trap_enter_valid
trap_return_valid

priv_mode
CSR state
interrupt sources

sync_exception_pending
interrupt_pending

trap_pc
target_priv
hardware CSR write values
```

这样 Trap/CSR wrapper 不再暴露 exception taxonomy。

---

# 23. PC / EPC / TVAL Contract

本阶段再次固定：

## Exception EPC

```text
epc = faulting instruction PC
```

## Interrupt EPC

```text
epc = next instruction PC
```

当前严格串行 core 中 `current_pc` 在 instruction completion 后已经指向 architectural next PC，因此 interrupt trap 可以继续使用它。

## TVAL

```text
instruction-address-misaligned -> bad target VA
instruction access/page fault  -> faulting instruction VA
illegal instruction           -> instruction bits
breakpoint/ecall              -> 0
load/store misaligned         -> effective VA
load/store access/page fault  -> effective VA
```

physical PA 永远不进入 architectural `tval`。

---

# 24. Trap Entry 清理行为

进入 `STATE_TRAP_ENTER` 时：

- 清除已消费的 `exception_r.valid`；
- cpu_mem 继续收到 `trap_enter`，取消当前未完成 architectural memory operation，并清除 LR reservation；
- ICache redirect/flush 行为保持；
- PC 更新到 Trap router 给出的 `trap_pc`；
- privilege 更新到 `target_priv`。

已经发出的 external bus transaction 仍按各 subsystem 当前规则安全 drain，不增加 bus cancellation。

---

# 25. Retire Contract

同步异常 instruction 不得计入 `minstret`。

由于本阶段将：

```text
fault -> stage_done = 0
```

现有 retirement points 可以自然收敛：

```text
WB success
branch success
decode-only normal instruction success
FENCE.I success
SFENCE.VMA success
xRET success
```

exception path 不产生 retire event。

---

# 26. 本阶段允许修改

主要：

- `core_bus_types.svh`
- `cpu_decode.sv`
- `cpu_execute.sv`
- `cpu_mem.sv`
- `cpu_controller.sv`
- `core_top.sv`
- `MMU.sv` fault port naming
- `cpu_trap_manager.sv`
- `cpu_trap_csr.sv`
- `cpu_clint.sv`，建议重命名为 `cpu_trap_router.sv`
- 直接受接口变化影响的 system wiring

---

# 27. 本阶段不要扩大范围

不要借本阶段修改：

- MMU/TLB/PTW translation algorithm；
- Cache policy；
- A-extension reservation/atomicity 细节；
- PMP implementation；
- PMA implementation；
- CSR WARL/WPRI 细节；
- interrupt priority policy；
- delegation policy；
- PLIC / CLINT platform device；
- system_top interconnect；
- SoC decode windows。

如果在开发过程中发现这些区域存在问题，记录到对应后续阶段，不在 Unified Exception 阶段顺手扩大修改。

---

# 28. 目标结构

最终 core control path：

```text
                    +-------------------+
Fetch  ------------>|                   |
Decode ------------>|   exception_t     |
Execute ----------->|   stage sources   |
Memory ------------>|                   |
                    +---------+---------+
                              |
                              v
                     sync_exception_now
                              |
                              v
                     +----------------+
                     | one exception  |
                     |     latch      |
                     +-------+--------+
                             |
              +--------------+--------------+
              |                             |
              v                             v
   sync_exception_pending            cpu_trap_router
              |                             |
              |                    interrupt_pending
              |                             |
              +--------------+--------------+
                             |
                             v
                       cpu_controller
                             |
                   STATE_TRAP_ENTER
                             |
                             v
                     Trap CSR update
```

Controller 的认知边界最终是：

```text
stage done
instruction class
sync exception pending
interrupt pending
fence completion
```

Controller 不再知道任何具体 exception cause。

---

# 29. 本阶段结束后的路线

完成 Unified Exception / Trap 后，异常控制路径应冻结。

后续开发顺序：

```text
A Extension semantics
        ↓
PMP + PMA
        ↓
CSR / Privileged architecture
        ↓
SoC address-map cleanup
        ↓
remaining completeness fixes
```

A Extension 阶段将在当前已经建立的：

```text
mem_kind
access_class
architectural address check
physical request
unified exception
```

基础上继续，不再为 LR/SC/AMO 增加特殊的跨模块 fault wiring。
