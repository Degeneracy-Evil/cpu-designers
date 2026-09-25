> **[历史归档 2026-09-25]** 本文为 2026-06~08 的调试/规划快照：文中工具命令（`tools/vivado_cli`）、目录路径（`src/rtl`、`src/tb`、`src/program_source`）、时钟（cpu_clk 50MHz）及部分架构描述已被 2026-09 重构取代（现行工具链 `python3 -m tools.vivado`，RTL 位于 `src/{common,core,soc}`）。仅作历史记录，勿作操作依据。

# Trap-Loop Bug 分析推导（第二轮·修正版）

> **日期**：2026-06-27 17:00
> **仿真配置**：#4 (128MB SRAM + 16MB DTB)，带 forensic buffer
> **Trap 发生 cycle**：~2643790000

---

## 一、核心结论

**trap #118 是 store page fault (cause=15)，不是 ecall (cause=9)。**

`vzalloc_node_noprof` 返回虚拟地址 0xa0021000，`gen_pool_add_owner` 中的 `sw s1,20(a0)` 对 0xa0021014 执行 store，触发 S-mode store page fault。随后 handle_exception 因栈/TP/上下文异常在 c037fa74 附近二次 trap-loop。

---

## 二、为什么之前认为 cause=9 是错误的

### 2.1 trap_deleg.log 的根本问题：打印了错误的 CSR

trap #118 的关键字段：

```
TPriv=1    → trap 到 S-mode
Deleg=1    → 异常被委托
HW_TPRIV=1 → 硬件写入 S-mode CSR
```

S-mode trap 更新的是 `scause`/`stval`/`sepc`，**不是** `mcause`/`mtval`/`mepc`。

但 `trap_deleg.log` 固定打印 `csr_mcause`：

```verilog
// tb_kernel_boot.sv line 57:
u_soc.cpu.csr_mcause    // ← M-mode cause 寄存器
```

对于 S-mode trap，`csr_mcause` 不会被更新，读到的是上一个 M-mode trap 的残留值。trap #116（合法 ecall，cause=9，M-mode 处理）写入了 `mcause=9`，trap #118 读到的就是这个旧值。

**这不是 posedge 时序问题，而是打印了错误的 CSR 寄存器。** 即使时序完全正确，`csr_mcause` 对 S-mode trap 也是无意义的。

### 2.2 验证：MEDELEG 委托位

```
MEDELEG = 0x0000b109 = 0b1011_0001_0000_1001

bit  0  inst access fault      = 1  → delegated
bit  3  breakpoint             = 1  → delegated
bit  8  ecall from U           = 1  → delegated
bit 12  inst page fault        = 1  → delegated
bit 13  load page fault        = 1  → delegated
bit 15  store page fault       = 1  → delegated  ← 关键
bit  7  store access fault     = 0  → NOT delegated
bit  9  ecall from S           = 0  → NOT delegated
```

trap #118 的 `Deleg=1`，说明真实 cause 必须是被 MEDELEG 委托的异常。ecall from S (bit 9) **不被委托**，所以 cause=9 + Deleg=1 本身就矛盾——这进一步证明 cause=9 是错误数据。

---

## 三、trap #118 是 store page fault 的证据链

### 3.1 EPC 处的指令是 store

```
EPC = c01df3c8
反汇编: c01df3c8:  00952a23  sw s1,20(a0)

这是 gen_pool_add_owner 函数中的 store 指令。
```

### 3.2 TVAL 等于 store 的目标地址

```
HW_TVAL = a0021014

sw s1,20(a0) 的目标地址 = a0 + 20 = 0xa0021014
→ a0 = 0xa0021000 (页对齐!)

TVAL 不是随机残留，正好等于这条 store 的目标地址。
0xa0021000 是 vmalloc 分配的虚拟地址。
```

### 3.3 反汇编上下文

```
c01df36c <gen_pool_add_owner>:
...
c01df3c0:  fd5070ef  jal  c00e7394 <vzalloc_node_noprof>  ← 分配虚拟内存
c01df3c4:  08050a63  beqz a0,c01df458                      ← 检查是否成功
c01df3c8:  00952a23  sw   s1,20(a0)                        ← ★ 写入 a0+20=0xa0021014, 触发 fault
c01df3cc:  fff48493  addi s1,s1,-1
```

a0 是 vzalloc_node_noprof 的返回值 = 0xa0021000（vmalloc 地址）。
对 0xa0021014 的 store 触发了 store page fault。

### 3.4 委托逻辑验证

```
store page fault = cause 15
MEDELEG bit 15 = 1 → 委托到 S-mode
→ Deleg=1, ToS=1, TPriv=1  ← 与 trap_deleg.log 记录一致

store access fault = cause 7
MEDELEG bit 7 = 0 → 不委托
→ 如果是 cause 7, Deleg 应该=0, TPriv=3 (M-mode)
→ 与 trap_deleg.log 记录不一致

→ 排除 store access fault, 确认 store page fault
```

### 3.5 排除 ecall

```
UNEXPECTED_ECALL_DECODE 未触发
ECALL_DECODE 事件仅出现在 c0010bbc（合法 ecall）
→ dec_is_ecall 从未在非 ecall 指令上置位
→ CPU 译码逻辑正确
→ trap #118 完全不是 ecall
```

---

## 四、真实事件序列

```
1. kernel 调用 dma_atomic_pool_init (0xc038af60)
2. dma_atomic_pool_init 调用 gen_pool_add_owner
3. gen_pool_add_owner 调用 vzalloc_node_noprof
4. vzalloc_node_noprof 返回 0xa0021000 (vmalloc 虚拟地址)
5. gen_pool_add_owner 执行 sw s1,20(a0) → store 到 0xa0021014
6. MMU 翻译 0xa0021014 时触发 store page fault (cause=15)
   - 可能原因: PTE 不存在 / PTE 的 W 位=0 / PTE 的 D 位=0
7. trap 委托到 S-mode (MEDELEG bit15=1)
8. 进入 handle_exception (c037fa58)
9. handle_exception 内部因栈/TP/上下文异常再次 trap → trap-loop
```

---

## 五、TLB BRAM collision 线索

### 5.1 collision 时间

```
trap #118 时间: 2643788485 ps
collision 时间范围 (near trap): 2630071042500 ~ 2638357749500 ps
```

大量 TLB BRAM same-address (A read addr=0, B write addr=0) collision 出现在 trap 前约 5.4~1.0 亿周期。虽然距离首次 fault 仍有间隔，但这些 collision 表明 TLB 的 flag/data BRAM 在频繁发生同地址读写碰撞。

### 5.2 READ_FIRST 下的 collision 行为

虽然 BRAM 已改为 READ_FIRST（Port A 读到旧数据），但 collision warning 仍被触发。READ_FIRST 保证返回有效旧数据，但如果 TLB fill 和 d-side lookup 在同一周期对同一 entry 操作，可能存在逻辑层面的竞态（数据正确但时序边界条件）。

### 5.3 DTLB 与 store page fault 的关联

store page fault 可能的硬件原因：
- DTLB 查找返回了错误的 PTE（W 位=0 或 D 位=0）
- DTLB miss 后 PTW walk 读到了错误的 page table entry
- PTE 本身正确但 DTLB flag BRAM collision 导致 permission 位被污染

---

## 六、下一轮仿真计划

### 6.1 修复 trap_deleg.log

```verilog
// 当前（错误）:
u_soc.cpu.csr_mcause           // M-mode cause, S-mode trap 时不更新

// 修复:
u_soc.cpu.hw_trap_cause        // 硬件组合逻辑输出的 cause（正确）
u_soc.cpu.csr_scause           // S-mode cause 寄存器
u_soc.cpu.csr_stval            // S-mode tval 寄存器
u_soc.cpu.csr_sepc             // S-mode epc 寄存器
```

### 6.2 修改 forensic trigger

去掉 cause==9 限制，捕获任何 EPC≠c0010bbc 的 trap：

```verilog
// 当前（不触发）:
if (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_cause == 32'd9) &&
    (u_soc.cpu.hw_trap_epc != 32'hc0010bbc))

// 修复:
if (u_soc.cpu.trap_enter_valid && (u_soc.cpu.hw_trap_epc != 32'hc0010bbc))
```

### 6.3 增加 D-side 信号到 forensic buffer

当前 forensic buffer 集中在 IF 路径，缺少 D-side 证据。下一轮应增加：

**D-side 访问信号：**
```
mem_pc, mem_valid, mem_done, mem_addr, mem_wen
mmu_data_pf_cause, mmu_data_pf_vaddr
store_page_fault, load_page_fault
```

**D-side TLB 信号：**
```
d_tlb_hit, d_tlb_valid, d_tlb_perm_fault
d_latched_vaddr, d_latched_sv32
d_input_changed
mmu_d_state, mmu_d_pf_from_ptw, mmu_d_tlb_miss
```

**D-side MMU 配置：**
```
access_type (load/store), priv, sum, mxr
```

**PTW 信号：**
```
ptw_bus_req, ptw_bus_addr, ptw_bus_rdata, ptw_bus_done
```

### 6.4 重点验证方向

1. **a0021000 页表项**：PTE 是否存在？V/R/W/X/U/A/D 位是什么？
2. **DTLB flag BRAM collision**：collision 是否导致 permission 位（W/D）被污染？
3. **PTW walk 数据**：walk 读取的 PTE 数据是否正确？
4. **vmalloc 页表映射**：0xa0021000 的映射是否被正确建立？

---

## 七、关键文件

```
project/kernel_boot_sram128_dtb16/simplecpu_soc.sim/sim_1/behav/xsim/
├── if_sanity.log              # IF 事件日志
├── trap_deleg.log             # trap 委托日志（cause 列对 S-mode trap 无效）
├── trap_forensics_dump.log    # forensic dump（0 字节，触发器未触发）
├── uart_tx.log                # UART 输出
└── simulate.log               # probe 日志

src/rtl/core/cpu_clint.sv         # hw_trap_cause/epc 生成, 委托逻辑
src/rtl/core/cpu_trap_manager.sv  # exception_valid_r 锁存, cause 优先级
src/rtl/core/cpu_csr.sv           # r_mcause/r_scause 寄存器
src/rtl/core/MMU.sv               # MMU/TLB, D-side page fault 生成
src/rtl/core/tlb.sv               # TLB BRAM (flag/data, READ_FIRST)
src/tb/tb_kernel_boot.sv          # TB (trap_deleg 记录 + forensic buffer)
```
