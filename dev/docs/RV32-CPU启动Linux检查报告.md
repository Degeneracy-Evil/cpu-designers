# RV32-CPU 启动 Linux 最小必要条件检查报告

**检查对象**: `dev/rtl/` SystemVerilog RTL 设计
**检查阶段**: OpenSBI + Linux 启动阶段
**检查依据**: `Reference/RV32-CPU启动Linux的最小必要条件检查清单.md`
**检查日期**: 2026-06-21

---

## 总体结论

| 严重度 | 数量 | 说明 |
|--------|------|------|
| ❌ 硬性阻断 | **1** | TLB hit 绕过 D 位检查 |
| ⚠️ 高风险 | **2** | PTW access fault 丢失/cause 错误 |
| ⚠️ 中风险 | **2** | satp 写不刷 TLB；mtimecmp 复位值 |
| ✅ 通过 | **其余全部** | ISA/特权/MMU核心/Cache一致性/Timer/PLIC/UART/DTS |

**结论**: 6 项关键检查中，5 项通过，1 项（A/D 位处理）存在缺陷。Linux **可能能打印早期日志**，但**无法稳定进入用户态 shell**，因为 D 位丢失会导致脏页追踪错误。

---

## 第 19 节 6 项最重要结论逐项判定

### 1. ✅ 是否已支持完整 A 扩展

**通过。** 全部 11 条指令已实现：

| 指令 | funct5 | 位置 | 状态 |
|------|--------|------|------|
| lr.w | 00010 | cpu_decode.sv:236 | ✅ |
| sc.w | 00011 | cpu_decode.sv:237 | ✅ |
| amoswap.w | 00001 | cpu_decode.sv:238 | ✅ |
| amoadd.w | 00000 | cpu_decode.sv:239 | ✅ |
| amoxor.w | 00100 | cpu_decode.sv:242 | ✅ |
| amoand.w | 01100 | cpu_decode.sv:240 | ✅ |
| amoor.w | 01000 | cpu_decode.sv:241 | ✅ |
| amomin.w | 10000 | cpu_decode.sv:243 | ✅ |
| amomax.w | 10100 | cpu_decode.sv:244 | ✅ |
| amominu.w | 11000 | cpu_decode.sv:245 | ✅ |
| amomaxu.w | 11100 | cpu_decode.sv:246 | ✅ |

- **aq/rl 位**: 提取并传播到 cpu_mem.sv，但不产生任何功能效果。**不作为非法指令**。单核顺序 CPU 此处理正确。✅
- **LR/SC reservation**: 单地址 reservation，normal store 和 trap entry 时清除。语义正确。✅
- **AMO 原子性**: read-modify-write 状态机阻塞执行，单核无其他总线主设备干扰。✅

### 2. ✅ 是否已支持 M/S/U mode

**通过。**

- **三特权级**: PRIV_U=00, PRIV_S=01, PRIV_M=11，复位进入 M-mode ✅
- **mret/sret**: mret 恢复 MPP→priv_mode, MIE=MPIE, MPIE=1；sret 恢复 SPP→priv_mode, SIE=SPIE, SPIE=1。cpu_clint.sv:169-180 逻辑正确。✅
- **ecall cause**: U→8, S→9, M→11。cpu_decode.sv 正确。✅
- **mstatus 字段**: MPP[12:11], SPP[8], MPIE[7], SPIE[5], MIE[3], SIE[1] — 与 RISC-V spec v1.12 一致。✅
- **sstatus 视图**: 正确暴露 SPP/SPIE/SIE/MXR/SUM/MPRV/XS/FS，屏蔽 MPP/MPIE/MIE。✅
- **sstatus 写入**: cpu_csr.sv:566-577 逐位写入 mstatus，包括 SPIE(bit 5)。✅
- **misa**: 0x40141121 = RV32 IMAFSU。声明了 I/M/A/F/S/U。✅
- **PMP**: 16 个 PMP entry (pmpcfg0-3, pmpaddr0-15)，M-mode 可读写，lock-bit enforcement 已实现。输出在 core_top 中未连接（无硬件 enforcement），但 CSR 访问不会崩溃。OpenSBI 兼容。✅
- **medeleg**: wmask = 0xB3FF，允许委托 cause 0-9, 11-13, 15。page fault (12/13/15) 和 ecall from U (8) 可委托。✅
- **mideleg**: wmask = 0x0222，仅允许 SSI(1)/STI(5)/SEI(9)。M-mode 中断不可委托。✅
- **trap from M-mode**: `trap_to_s` 逻辑包含 `(priv_mode != PRIV_M)` 保护，M-mode trap 永远不委托。✅

### 3. ⚠️ 是否已支持 Sv32，并且 page fault / sfence.vma 正确

**部分通过，存在 1 个硬性缺陷 + 2 个高风险缺陷。**

**正确实现的部分：**
- **satp**: MODE=bit31, ASID=bits30:22, PPN=bits21:0。Sv32 在 S/U mode 且 satp[31]=1 时启用。✅
- **PTE 解析**: V/R/W/X/U/G/A/D/PPN 位定义正确。✅
- **Leaf PTE 判断**: R||X，W=1&&R=0 作为 reserved 编码在 leaf 判断之前捕获。✅
- **Megapage (4MB)**: L1 leaf PTE 检测为 megapage，PPN[9:0] 对齐检查存在。✅
- **权限检查**: U/S mode, SUM, MXR 全部正确实现 (MMU.sv:263-277, ptw.sv:168-188)。✅
- **Page fault cause**: 12=inst, 13=load, 15=store。编码正确。✅
- **Access fault cause**: 1=inst, 5=load, 7=store。PTW 中编码正确。✅
- **stval**: page fault 时写入 faulting VA。✅
- **sfence.vma**: D-cache flush(writeback+invalidate) → I-cache invalidate → TLB flush，三步串行完成。core_top.sv:699-752。✅
- **sfence.vma TVM trap**: S-mode 且 TVM=1 时 sfence.vma 触发 illegal instruction。✅
- **PTW walk abort**: sfence.vma 中止进行中的 PTW walk (ptw.sv:227)。✅
- **TLB ASID/Global**: 全局项无视 ASID 匹配，非全局项按 ASID 匹配。✅
- **TLB megapage VPN**: 填充时 VPN[9:0] 置零，查找时仅比较 VPN[19:10]。✅

**❌ 缺陷 1 (CRITICAL): TLB hit 绕过 D 位检查**

- **位置**: MMU.sv:263-277 (d_tlb_perm_fault), 299 (d_translation_ok)
- **描述**: TLB 命中时的权限检查只验证 R/W/X/U/SUM/MXR，**不检查 A/D 位**。当页面首次被读（PTW 设置 A=1, D=0，TLB 填充 A=1, D=0），之后同一页面被写，TLB 命中直接通过，**PTE 中的 D 位永远不会被置 1**。
- **影响**: Linux 依赖 D 位追踪脏页。如果 D 位未设置，Linux 可能将脏页误判为干净页，导致页面回收时数据丢失。Linux 启动时假设硬件 A/D 位设置工作（因为 PTW 确实设置了），但 TLB hit 路径绕过了 D 位更新。
- **修复方案**: 在 TLB 权限检查中增加 D 位检查。当 store 命中 D=0 的 TLB 项时：
  - 方案 A：使该 TLB 项无效，触发重新 walk（PTW 会设置 D=1）
  - 方案 B：直接触发 page fault（让软件处理）

**⚠️ 缺陷 2 (HIGH): PTW access fault 在 data 侧被静默丢弃**

- **位置**: core_top.sv:1301-1304
- **描述**: data 侧 page fault 信号按 cause 过滤：
  ```
  load_page_fault  = mmu_data_page_fault && (mmu_data_pf_cause == 4'd13)
  store_page_fault = mmu_data_page_fault && (mmu_data_pf_cause == 4'd15)
  ```
  PTW 遇到总线错误时报告 cause 5 (load access fault) 或 7 (store access fault)，不匹配 13/15，**fault 被丢弃**。
- **影响**: 如果页表位于总线错误区域（如未配置内存），CPU 会挂起。Linux 启动期间不太可能触发，但属于正确性缺陷。
- **修复方案**: 将 PTW access fault 通过 access fault 路径传递到 trap manager。

**⚠️ 缺陷 3 (HIGH): PTW access fault 在 instruction 侧 cause 编码错误**

- **位置**: cpu_trap_manager.sv:228
- **描述**: trap manager 硬编码 instruction page fault cause 为 12：
  ```
  pf_cause = inst_page_fault_r ? 32'd12 : ...
  ```
  PTW 报告 cause 1 (instruction access fault) 时，trap manager 错误地写入 cause 12。
- **影响**: 内核 fault handler 收到错误的 cause 编码，可能进入错误的处理路径。
- **修复方案**: 使用 MMU 提供的实际 cause 值，而非硬编码。

### 4. ✅ MMIO 判断是否基于物理地址

**通过。**

- **dcache_ctrl.sv:112 / icache_ctrl.sv:72**:
  ```
  wire is_mmio = ~cpu_req_addr[31] | cpu_req_addr[30];
  ```
  `cpu_req_addr` 是 **MMU 输出的物理地址**，不是虚拟地址。✅
- **地址映射**:
  - 0x00000000-0x7FFFFFFF (bit31=0): MMIO (PLIC/CLINT/APB) ✅
  - 0x80000000-0x87FFFFFF (bit31=1,bit30=0): 可缓存 DDR3 (128MB) ✅
  - 0xC0000000-0xFFFFFFFF (bit31=1,bit30=1): MMIO (Boot ROM) ✅
- **MMIO 绕过 D-cache**: is_mmio=1 时走 bypass 路径，不访问 tag/data BRAM。✅
- **DTS 地址匹配**: CLINT@0x02000000, PLIC@0x0C000000, UART@0x10008000, DDR@0x80000000 — 全部与 RTL 地址译码器一致。✅

### 5. ✅ PTW 读取页表是否与 dcache 保持一致

**通过。**

- **PTW 绕过 D-cache**: PTW 有独立总线接口 (ptw_bus_*)，通过 cpu_bus_bridge.sv 的 S_PTW_AR/R/AW_W/B 状态直接访问 AXI 总线。✅
- **sfence.vma 保证一致性**: sfence.vma 先执行 D-cache flush (writeback+invalidate)，再 flush TLB。Linux 修改页表后执行 sfence.vma，确保 PTW 重新 walk 时看到最新 PTE。✅
- **PTW A/D 写回一致性**: PTW 写 A/D 位后，core_top 触发 `inv_line_req` 使 D-cache 对应行无效化（不 writeback，因为 PTW 的 A/D 更新是权威版本）。dcache_ctrl.sv:804-813 注释正确解释了此逻辑。✅
- **fence.i 完整性**: D-cache flush → I-cache invalidate，两步完成。✅

### 6. ✅ Linux 是否能收到 S-mode timer interrupt

**通过。**

- **mtime**: 64-bit 自由运行计数器，axi4lite_clint.sv。✅
- **mtimecmp**: 64-bit，分为两个 32-bit 半字 (0x4000/0x4004)，RV32 标准访问。✅
- **MTIP**: `r_mtime >= mtimecmp_64`，64-bit 比较。✅
- **STIP 路径**: `stip_hw_pending = ext_mtip && r_mideleg[5]` → `mip[5]` → cpu_clint.sv S-mode timer interrupt。✅
- **mideleg[5]**: 可设置（wmask 0x222 包含 bit 5），OpenSBI 委托 timer interrupt 到 S-mode。✅
- **rdtime/rdtimeh**: TIME/TIMEH CSR 返回 ext_mtime，通过 Gray-code CDC 从 sys_clk 同步到 cpu_clk。✅
- **mcounteren/scounteren**: 已实现，OpenSBI 设置 mcounteren[1]=1 允许 U-mode 读 time/timeh。✅
- **PLIC**: 2 context (M+S), claim/complete 正确，S-mode context 1 enable/threshold/claim 地址正确。✅
- **SEIP/MEIP**: PLIC context 1→SEIP, context 0→MEIP，2-stage FF 同步。✅

---

## 其他检查项汇总

| 大类 | 项目 | 结果 | 证据/备注 |
|------|------|------|-----------|
| ISA | RV32I | ✅ | ALU/MU/branch/JAL 实现完整 |
| ISA | M 扩展 | ✅ | booth_multiplier + non_restoring_divider |
| ISA | A 扩展 | ✅ | 全部 11 条指令，见上 |
| ISA | Zicsr | ✅ | csrrw/csrrs/csrrc 及立即数版本 |
| ISA | Zifencei | ✅ | fence.i: dcache flush + icache inv |
| ISA | wfi | ✅ | 作为 NOP 处理 (cpu_decode.sv:265)，tw_bit 检查 |
| ISA | fence | ✅ | 作为 NOP-like 处理 |
| ISA | misalign | ✅ | load=cause4, store/AMO=cause6, branch misalign 检测 |
| CSR | misa | ✅ | 0x40141121 = RV32 IMAFSU |
| 特权 | M/S/U | ✅ | 三特权级，mret/sret 正确 |
| 异常 | ecall | ✅ | U=8, S=9, M=11 |
| 异常 | page fault | ✅ | cause 12/13/15, stval=faulting VA |
| 委托 | medeleg | ✅ | page fault/ecall 可委托 |
| 委托 | mideleg | ✅ | SSI/STI/SEI 可委托 |
| MMU | satp | ✅ | Sv32 MODE/ASID/PPN 正确 |
| MMU | PTW | ✅ | 两级页表遍历，megapage 支持 |
| MMU | 权限检查 | ✅ | R/W/X/U/SUM/MXR 正确 |
| MMU | A/D 位 | ❌ | **TLB hit 绕过 D 位检查（缺陷 1）** |
| MMU | sfence.vma | ✅ | dcache flush → icache inv → TLB flush |
| MMU | PTW access fault | ⚠️ | **data 侧丢失，inst 侧 cause 错误（缺陷 2/3）** |
| Cache | I-cache | ✅ | fence.i 后取新指令 |
| Cache | D-cache | ✅ | load/store 正确 |
| Cache | MMIO bypass | ✅ | 基于物理地址 |
| Cache | PTW 一致性 | ✅ | inv_line 机制 + sfence.vma flush |
| Timer | mtime | ✅ | 64-bit 单调递增 |
| Timer | mtimecmp | ⚠️ | 复位值为 0（应为 0xFFFFFFFF_FFFFFFFF），MTIP 立即触发但 MIE=0 阻止中断 |
| Timer | STIP | ✅ | mideleg[5] 委托路径正确 |
| Counter | time/timeh | ✅ | 返回 CLINT mtime via Gray-code CDC |
| Interrupt | PLIC | ✅ | claim/complete/enable/priority/threshold, 2 context |
| UART | TX/RX | ✅ | ns16550a 兼容 |
| UART | Linux compatible | ✅ | DTS 声明 ns16550a, earlycon=uart8250 |
| DDR | 基础读写 | ✅ | 128MB @ 0x80000000 |
| DDR | 地址空间 | ✅ | DTS 与 RTL 一致 |
| Boot | satp=0 | ✅ | MMU 在 M-mode 关闭翻译 |
| DTB | /cpus | ✅ | rv32ima_zicsr_zifencei, sv32, 100MHz |
| DTB | /memory | ✅ | 0x80000000, 128MB |
| DTB | /chosen | ✅ | stdout-path + bootargs |
| DTB | reserved-memory | ✅ | OpenSBI 0x80000000-0x803FFFFF |

---

## 缺陷修复优先级

| 优先级 | 缺陷 | 修复复杂度 | 阻断 Linux 启动？ |
|--------|------|-----------|-------------------|
| **P0** | 缺陷 1: TLB hit 绕过 D 位检查 | 中 — 在 d_tlb_perm_fault 增加 D 位检查，store 命中 D=0 时触发 TLB invalidate + re-walk | **是** — 脏页丢失导致数据损坏 |
| **P1** | 缺陷 2: PTW access fault data 侧丢失 | 低 — core_top.sv 增加 cause 5/7 的 access fault 路径 | 早期启动不太可能触发，但正确性缺陷 |
| **P1** | 缺陷 3: PTW access fault inst 侧 cause 错误 | 低 — trap manager 使用 MMU 提供的 cause 而非硬编码 | 早期启动不太可能触发，但正确性缺陷 |
| **P2** | mtimecmp 复位值 | 低 — CLINT 复位 mtimecmp 为 0xFFFFFFFF_FFFFFFFF | 否 — MIE=0 阻止中断 |
| **P2** | satp 写不刷 TLB | 低 — satp 写时触发 TLB flush | 否 — Linux 总是跟 sfence.vma |

---

## 建议的修复方案

### 缺陷 1 修复（P0 — 必须）

在 `MMU.sv` 的 `d_tlb_perm_fault` 中增加 D 位检查：

```systemverilog
// 现有代码 (MMU.sv:271-277)
assign d_tlb_perm_fault = ... (现有权限检查) ...

// 增加：store 到 D=0 页面时触发 re-walk 而非直接 fault
wire d_tlb_ad_fault = d_tlb_hit && (d_latched_access_type == ACCESS_STORE) && !d_tlb_d;
// 当 d_tlb_ad_fault 时，使该 TLB 项无效并触发 re-walk
// (具体实现取决于 TLB invalidate 接口)
```

或者更简单的方案：当 store 命中 D=0 的 TLB 项时，将其视为 TLB miss，触发 PTW re-walk，PTW 会设置 D=1 并重新填充 TLB。

### 缺陷 2/3 修复（P1）

在 `core_top.sv` 中增加 PTW access fault 路径：

```systemverilog
// 现有：只按 cause 13/15 过滤
// 修改：增加 cause 5/7 的 access fault 路径
wire load_access_fault_from_ptw  = mmu_data_page_fault && (mmu_data_pf_cause == 4'd5);
wire store_access_fault_from_ptw = mmu_data_page_fault && (mmu_data_pf_cause == 4'd7);
// 将这些连接到 trap manager 的 access fault 输入
```

在 `cpu_trap_manager.sv` 中使用 MMU 提供的 cause 而非硬编码：

```systemverilog
// 现有：pf_cause = inst_page_fault_r ? 32'd12 : ...
// 修改：pf_cause = inst_page_fault_r ? mmu_inst_pf_cause : ...
```

---

## DTS 配置审查

`boot/dts/simplecpu.dts` 与 RTL 一致性检查：

| 项目 | DTS 值 | RTL 值 | 一致？ |
|------|--------|--------|--------|
| riscv,isa | rv32ima_zicsr_zifencei | misa=0x40141121 (IMAFSU) | ✅ |
| mmu-type | riscv,sv32 | Sv32 实现 | ✅ |
| timebase-frequency | 100000000 | 100MHz 时钟 | ✅ |
| memory reg | 0x80000000, 128MB | DDR3 @ 0x80000000, 128MB | ✅ |
| CLINT reg | 0x02000000 | addr[31:24]==0x02 | ✅ |
| PLIC reg | 0x0c000000, 8 sources | addr[31:24]==0x0C, NUM_SRC=8 | ✅ |
| UART reg | 0x10008000 | APB bridge 0x10 + UART offset | ✅ |
| UART compatible | ns16550a | uart_16550a.sv | ✅ |
| UART reg-shift | 2 | PADDR[4:2] 选择寄存器 | ✅ |
| reserved-memory | 0x80000000, 4MB | OpenSBI 区域 | ✅ |
| bootargs | console=ttyS0,230400 earlycon=uart8250 | UART 支持 earlycon | ✅ |

**⚠️ 注意**: DTS 中 `riscv,isa` 声明不含 `f`（第一阶段 soft-float），但 `misa` 硬件值包含 F。如果 Linux 按 DTS 的 `rv32ima_zicsr_zifencei` 编译（无 F），而硬件 misa 报告有 F，**可能产生不一致**。建议：
- 如果 FPU 已验证通过，DTS 加上 `_f`
- 如果 FPU 未完全验证，硬件 misa 清除 F 位（bit 5）

---

## 检查方法说明

本次检查通过 5 个并行 explore agent 分别审计以下领域：

1. **A 扩展 AMO/LR/SC 实现** — 全部 11 条指令解码与执行逻辑
2. **MMU Sv32 / PTW / sfence.vma** — PTE 解析、权限检查、page fault、TLB、A/D 位
3. **MMIO/物理地址判断与 Cache 一致性** — is_mmio 逻辑、PTW-Dcache coherence、sfence.vma/fence.i 序列
4. **特权级与 trap/delegation** — M/S/U mode、mret/sret、CSR 实现、medeleg/mideleg、PMP
5. **Timer/CLINT/PLIC 与 S-mode timer interrupt** — mtime/mtimecmp、MTIP/STIP 路径、rdtime CSR、PLIC claim/complete

每个 agent 深入阅读相关 RTL 文件并逐行分析，主线程同步进行 DTS 审查和关键信号直接验证。

---

**检查完成。** 核心阻断项为**缺陷 1（TLB hit 绕过 D 位检查）**，建议优先修复后再进入 OpenSBI+Linux 联调。
