# RISC-V RV32 CPU 启动 Linux 适配性检查报告

> 生成日期: 2026-06-15 | 参照文档: `dev/docs/simpleCPU-design-report.md` | 检查清单: `Reference/RV32-CPU启动Linux的最小必要条件检查清单.md`
>
> 本报告基于设计文档与 RTL 代码扫描，逐项标注当前 CPU/SoC 是否满足 Linux 启动最低硬件条件。**不涉及代码修改，仅扫描与标注。**
>
> **本次更新（2026-06-15）**：对全部检查项重新进行 RTL 扫描验证。相比上一版（2026-06-14），**11 项 ❌/⚠️ 已修复为 ✅**，包括：A 扩展、MMIO 判断、STIP 置位路径、time/timeh CSR、U-mode counter 别名、sfence.vma dcache flush、PTW-dcache 一致性、A/D 位写回一致性、M/S 中断优先级、UART ns16550a 兼容、misa A 位声明。

---

## 标记说明

| 标记 | 含义 |
|------|------|
| ✅ | 已达标，有设计文档/RTL 证据/测试支撑 |
| ⚠️ | 设计上可能达标，但缺少测试、存在风险、或部分实现 |
| ❌ | 未达标，Linux 暂时无法可靠启动 |
| N/A | 当前阶段不需要 |

---

## 1. CPU 指令集最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| RV32I 基础整数指令 | ✅ | 设计报告 §1.2 列出 40 条 RV32I 指令，ISA 测试（alu/branch/jump/memory/upper_imm）均通过 |
| M 扩展 | ✅ | 设计报告 §1.2 列出 8 条 M 指令，Booth 乘法器 + 非恢复余数除法器，m_ext ISA 测试通过 |
| A 扩展 | ✅ | **已实现。** `cpu_decode.sv` 译码 OPCODE_AMO（7'b0101111），LR.W/SC.W + 全部 9 条 AMO 指令（amoswap/amoadd/amoxor/amoand/amoor/amomin/amomax/amominu/amomaxu）在 `cpu_mem.sv` 两阶段 read-modify-write 执行。misa bit0=1 |
| AMO 指令完整性 | ✅ | 全部 9 条 AMO 在 `cpu_decode.sv:225-233` 译码，`cpu_mem.sv:155-170` amo_compute() 函数实现全部运算 |
| LR/SC 语义 | ✅ | `cpu_mem.sv:108-110` 实现 1-entry reservation set（`lr_reservation_addr` + `lr_reservation_valid`），SC.W 检查 reservation match 后写回（成功 rd=0，失败 rd=1）。trap entry 自动清除 reservation |
| `aq/rl` 位 | ✅ | `cpu_decode.sv:217-221` 提取 aq/rl 位，单核强顺序系统中作为有效指令接受（不触发 illegal instruction） |
| Zicsr | ✅ | CSRRW/CSRRS/CSRRC + 立即数版本实现，CSR ISA 测试通过 |
| Zifencei | ✅ | fence.i 实现：dcache writeback + icache invalidate（设计报告 §5.17），fencei 测试通过 |
| `fence` | ✅ | 设计报告 §1.2 列出 FENCE 指令，作为有效屏障 |
| `wfi` | ✅ | 设计报告 §1.2 列出 WFI，译码为 NOP 类指令 |
| 非对齐访问 | ✅ | 硬件不支持非对齐，但产生精确异常（cause 4/6），`cpu_mem.sv` 检测对齐违规 |
| `misa` | ✅ | 值为 `0x40141121` = RV32AIMFSU，bit0=1（A 扩展已声明）。MXL[31:30]=01（RV32） |

**最低建议 ISA 字符串**：当前为 `rv32aimf_zicsr_zifencei`，满足 Linux 要求 `rv32ima_zicsr_zifencei`。

---

## 2. 特权级最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| M-mode | ✅ | 复位后进入 M-mode，PC=0xFC00_0000 |
| S-mode | ✅ | 设计报告 §1.1 确认 M/S/U 三级特权模式 |
| U-mode | ✅ | 同上 |
| `mret` | ✅ | `cpu_clint.sv:160-162`：MIE←MPIE，MPP←priv_mode，特权级恢复至 MPP（`core_top.sv:316-322`） |
| `sret` | ✅ | `cpu_clint.sv:169-171`：SIE←SPIE，SPP←priv_mode[0]，特权级恢复至 SPP?S:U。TSR 位阻止 S-mode sret |
| `ecall` | ✅ | `cpu_trap_manager.sv:92-95`：cause 按 U/S/M 区分（8/9/11），ecall 异常测试通过 |
| `ebreak` | ✅ | cause=3，ebreak 异常测试通过 |
| 特权级非法访问检查 | ✅ | U-mode 不可访问 S/M CSR，S-mode 不可访问 M CSR，触发 illegal instruction |
| `mstatus` | ✅ | MPP/MPIE/MIE 字段实现，写掩码控制，trap enter/return 语义正确 |
| `sstatus` | ✅ | SPP/SPIE/SIE 为 mstatus 受限视图，SUM(bit18)/MXR(bit19) 在 MMU 权限检查中使用 |
| `medeleg` | ✅ | `cpu_csr.sv:424`：medeleg_wmask=0xB3FF，所有 Linux 需要的异常委托位可写（0-9,12,13,15），ecall-M(11)正确不可委托 |
| `mideleg` | ✅ | `cpu_csr.sv:427`：mideleg_wmask=0x0AAA，SSI(1)/MSI(3)/STI(5)/MTI(7)/SEI(9)/MEI(11) 全部可写 |
| `mtvec/stvec` | ✅ | Direct 模式支持（设计报告 §4.1），Vectored 未实现但非最低要求 |
| `mepc/sepc` | ✅ | 陷阱时保存 PC，返回时恢复 |
| `mcause/scause` | ✅ | 11 种异常 + 3 种中断 cause 编码正确 |
| `mtval/stval` | ✅ | page fault 保存 fault VA，非法指令保存指令编码，对齐异常保存地址 |
| `mscratch/sscratch` | ✅ | 可读写 CSR 实现 |

---

## 3. MMU / Sv32 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| Sv32 | ✅ | 二级页表实现，`MMU.sv` + `ptw.sv`，sv32_basic/edge/ptw_walk 测试通过 |
| `satp` | ✅ | MODE/ASID/PPN 字段实现，satp.MODE=0 关闭翻译 |
| MMU 开关 | ✅ | satp.MODE=0 时直通，=1 时启用 Sv32 |
| 虚拟地址翻译 | ✅ | PTW 两级页表漫游，TLB 缓存翻译结果 |
| 4KB page | ✅ | Sv32 L0 页表支持 4KB 普通页 |
| megapage | ✅ | L1 叶节点为 4MB megapage，PTW 支持，tlb_megapage 测试通过 |
| PTE 格式 | ✅ | V/R/W/X/U/G/A/D/RSW/PPN 字段解析正确 |
| leaf PTE 判断 | ✅ | PTW 检查 R/W/X 是否全零判断叶/非叶节点 |
| 权限检查 | ✅ | R/W/X/U + SUM/MXR 检查实现（`MMU.sv:234-247` + `ptw.sv:141-161`） |
| page fault | ✅ | cause 12/13/15 正确，page_fault 测试通过 |
| `stval` | ✅ | page fault 时保存 fault virtual address |
| A/D 位处理 | ✅ | 硬件自动管理：PTW 写回 PTE 置 A=1/D=1（`ptw.sv:290-316`），写回后触发 dcache 行无效化保持一致性 |
| `sfence.vma` | ✅ | **已修复。** 完整序列：dcache writeback+invalidate → icache invalidate → TLB flush（`core_top.sv:426-464`） |
| TLB | ✅ | 4路×4组=16项，BRAM 存储，ASID 感知，Tree-PLRU 替换，tlb_basic/flush/asid 测试通过 |
| ASID | ✅ | TLB 项存储 ASID，匹配时检查 ASID 一致或 G=1 |
| MMIO 翻译策略 | ✅ | **已修复。** `icache_ctrl.sv:71` / `dcache_ctrl.sv:92`：`is_mmio = ~cpu_req_addr[31] | cpu_req_addr[30]`，基于物理地址（`cpu_req_addr` 连接 MMU paddr 输出），非虚拟地址。BUG-FIX 注释已标注 |

---

## 4. Cache / 内存一致性最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| I-cache | ✅ | 4路组相联 1KB，VIPT，fencei 测试通过 |
| D-cache | ✅ | 4路组相联 1KB，写回+写分配，dcache_basic/dirty 测试通过 |
| cacheable 区域 | ✅ | DDR 区域走 cache |
| uncacheable/MMIO 区域 | ✅ | MMIO 旁路 cache 逻辑正确，判断基于物理地址 |
| MMIO 判断 | ✅ | **已修复。** 基于物理地址（`cpu_req_addr` = MMU paddr），`mmu_ready` 门控防止使用未完成翻译的 paddr |
| 写回策略 | ✅ | D-cache 写回+写分配，脏行驱逐写回主存 |
| 页表一致性 | ✅ | **已修复。** sfence.vma 时 dcache 全量 writeback+invalidate（`dcache_ctrl.sv:574-657` S_FLUSH_SCAN→S_FLUSH_INVALIDATE），确保 PTW 后续读到最新 PTE |
| PTW 访问路径 | ✅ | **已修复。** PTW 仍旁路 dcache 直接访问 AXI 总线，但 sfence.vma 时 dcache 全量写回保证一致性；A/D 位写回后触发 dcache 行无效化（`core_top.sv:490-497`） |
| A/D 位写回 | ✅ | **已修复。** PTW 写 A/D 位旁路 dcache，但完成后请求 dcache 单行无效化（V=0,D=0，不写回脏数据避免覆盖 PTW 更新），`dcache_ctrl.sv:659-708` S_INV_LINE 状态机 |
| `sfence.vma` 语义 | ✅ | **已修复。** dcache writeback+invalidate → icache invalidate → TLB flush，严格顺序执行 |
| `fence.i` 语义 | ✅ | dcache writeback + icache invalidate（设计报告 §5.17） |
| 总线顺序 | ✅ | AXI4 协议保序，MMIO 单拍传输 |

---

## 5. 异常与中断最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 同步异常 | ✅ | 11 种异常实现（illegal inst/ecall/ebreak/misaligned/access fault/page fault），cause 正确 |
| 异常优先级 | ⚠️ | 设计报告未明确多异常同时发生的优先级，但回归测试通过 |
| 中断入口 | ✅ | 保存 PC 和 cause，`hw_trap_is_enter` 门控防止误写 |
| 全局中断使能 | ✅ | `mstatus.MIE`/`sstatus.SIE` 行为正确 |
| 局部中断使能 | ✅ | `mie`/`sie` 寄存器实现 |
| pending 位 | ✅ | `mip`/`sip` 硬件写入 + 软件可写 STIP(5)/SSIP(1) |
| 中断委托 | ✅ | `mideleg` 实现，`cpu_clint.sv` 判断委托 |
| 异常委托 | ✅ | `medeleg` 实现，delegation 测试通过 |
| 嵌套/屏蔽 | ✅ | trap 进入时 MIE→MPIE/SIE→SPIE，返回时恢复 |
| precise trap | ✅ | 异常 PC 指向正确指令（`cpu_trap_manager.sv:243-247`），interrupt PC 保存当前指令 |

---

## 6. Timer / CLINT / Counter 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| `mtime` | ✅ | CLINT 实现 64-bit mtime（`r_mtime[63:0]`），每时钟周期递增（100 MHz） |
| `mtimecmp` | ✅ | 64-bit mtimecmp，`mtime>=mtimecmp` 触发 MTIP |
| timer 频率 | ✅ | `sys_clk = 100MHz`，固定可知。Device Tree `timebase-frequency = <0x5F5E100>` |
| MTIP | ✅ | `mtime>=mtimecmp` 时 MTIP=1，timer_irq 测试通过 |
| STIP | ✅ | **已修复。** `cpu_csr.sv:443`：`sip_wmask` 包含 `sw_csr_wdata[5]`（STIP 可写）；`cpu_csr.sv:509`：`r_mip` bit5 来自 `r_sip[5]`；`cpu_clint.sv:72`：S-mode timer pending 使用 `csr_mip[5]`（非 ext_mtip） |
| `time/timeh` CSR | ✅ | **已修复。** `cpu_csr.sv:648,651`：ADDR_TIME(0xC01)/ADDR_TIMEH(0xC81) 读路径返回 `ext_mtime`（CLINT mtime 经 2 级 CDC 同步）。`system_top.sv:271-272`：clint_mtime → ff1 → ff2 → core_top.ext_mtime |
| `cycle/cycleh` CSR | ✅ | `mcycle`/`mcycleh` 实现，64-bit 单调递增 |
| `instret/instreth` CSR | ✅ | `minstret`/`minstreth` 实现 |
| U-mode counter 别名 | ✅ | **已修复。** `cpu_csr.sv:244-253`：`is_u_csr` 函数包含 cycle(0xC00)/time(0xC01)/instret(0xC02)/cycleh(0xC80)/timeh(0xC81)/instreth(0xC82)。读路径返回 mcycle/minstret/ext_mtime 对应位 |
| `mcounteren` | ✅ | `cpu_csr.sv:543,635`：可读写 CSR（0x306），bit-indexed 权限控制（cycle=0, time=1, instret=2） |
| `scounteren` | ✅ | `cpu_csr.sv:568,619`：可读写 CSR（0x106），S-mode 需 mcounteren AND scounteren 均置位 |
| SBI set_timer | ⚠️ | 硬件支持 mtimecmp 写入 + STIP 注入，但 OpenSBI 尚未移植 |

**CLINT 寄存器布局**：

```
标准 SiFive CLINT 布局（已实现）：
  0x0200_0000: msip         (32-bit, bit 0 有效)
  0x0200_4000: mtimecmp_lo  (32-bit)
  0x0200_4004: mtimecmp_hi  (32-bit)
  0x0200_BFF8: mtime_lo     (32-bit)
  0x0200_BFFC: mtime_hi     (32-bit)

地址译码使用 addr[15:0]，覆盖 64KB CLINT 窗口。
Linux 标准 CLINT 驱动（sifive_clint）可直接使用。
```

### 6.1 STIP 修复验证（commit 51bd6ef）

| 修复项 | 修复前 | 修复后 | 验证 |
|--------|--------|--------|------|
| sip_wmask | `{31'd0, sw_csr_wdata[1]}` | `{26'd0, sw_csr_wdata[5], 4'd0, sw_csr_wdata[1], 1'b0}` | bit5 可写 |
| mip[5] 来源 | `w_mip_hw[5]`（恒 0） | `r_sip[5]` | 软件写入 STIP 可见 |
| S-mode timer pending | `stie_bit && mtip_bit`（用 ext_mtip） | `stie_bit && stip_bit`（用 csr_mip[5]） | STIP 注入可触发 S-mode timer |
| M/S 优先级 | `!m_int_delegated` | `!m_int_not_delegated` | M-mode 未委托时阻止 S-mode 抢占 |

---

## 7. PLIC / 外部中断最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 外部中断控制器 | ✅ | PLIC 8 源中断控制器（`axi4lite_plic.sv`），0x0C00_0000，SiFive 标准地址布局 |
| MEIP | ✅ | Context 0 (M-mode) EIP → ext_meip_in → mip[11] |
| SEIP | ✅ | Context 1 (S-mode) EIP → ext_seip_in → mip[9]，无需仅靠 mideleg 委托 |
| priority | ✅ | 每源 4 字节优先级寄存器，偏移 0x000000+S×4 |
| pending | ✅ | 只读挂起状态，偏移 0x001000 |
| enable | ✅ | 每上下文 32-bit 使能掩码，ctx N 偏移 0x002000+N×0x80 |
| threshold | ✅ | 每上下文优先级阈值，ctx N 偏移 0x200000+N×0x1000 |
| claim/complete | ✅ | claim 返回最高优先级中断号并原子清除 pending + 禁用 gateway；complete 重新使能 gateway。ctx N 偏移 0x200004+N×0x1000 |
| 双上下文 | ✅ | NUM_CTX=2：ctx0=M-mode (o_eip[0])，ctx1=S-mode (o_eip[1]) |
| Device Tree 描述 | ❌ | DTB 尚未创建 |

**PLIC 寄存器布局（SiFive 标准布局，已实现）**：

```
基地址：0x0C00_0000
  Priority[src]:    0x000000 + src*4   (src 0-7, src 0 保留)
  Pending:          0x001000
  Enable[ctx N]:    0x002000 + N*0x80  (ctx 0=M-mode, ctx 1=S-mode)
  Threshold[ctx N]: 0x200000 + N*0x1000
  Claim[ctx N]:     0x200004 + N*0x1000

地址译码使用 addr[23:0]（16MB PLIC 窗口）。
Linux 标准 PLIC 驱动（irq-sifive-plic.c）可直接使用。
```

**PLIC 中断源映射**：

| Source ID | 来源 |
|-----------|------|
| 0 | 保留（未使用） |
| 1 | APB Timer |
| 2 | UART |
| 3 | SPI |
| 4 | GPIO |
| 5-7 | 保留（未使用） |

**PLIC 双上下文 EIP 路由**：

```
u_plic.o_eip[0] → plic_eip[0] → 2-flop CDC → ext_meip_in → mip[11] (MEIP)
u_plic.o_eip[1] → plic_eip[1] → 2-flop CDC → ext_seip_in → mip[9]  (SEIP)
```

S-mode 外部中断使用 seip_bit (mip[9]) 而非 meip_bit (mip[11])，符合 RISC-V 特权规范。

---

## 8. UART / Console 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| UART TX | ✅ | TX FIFO（16 字节），可配波特率 |
| UART RX | ✅ | RX FIFO（16 字节） |
| 波特率 | ✅ | 可配，默认 115200，divisor latch 支持 |
| MMIO 地址 | ✅ | 0x1000_8000（APB PADDR[15:14]=01，UART 为 PSELx[2]） |
| Linux 驱动兼容性 | ✅ | **已修复。** `apb_perips.sv:86` 实例化 `uart_16550a`（ns16550a 兼容），替换原自定义 `uart_top`。标准 8 寄存器布局（THR/RBR, IER, IIR/FCR, LCR, MCR, LSR, MSR, SCR），Linux 8250 驱动可直接使用 |
| early console | ⚠️ | 可通过 `earlycon=uart8250,mmio32,0x10008000` 或 `earlycon=sbi` 实现，OpenSBI 未移植 |
| SBI console | ⚠️ | OpenSBI 未移植，无法提供 SBI console |
| 中断模式 | ✅ | TX/RX 中断支持（IER 寄存器），IRQ 路由到 PLIC src[2] |

**UART ns16550a 寄存器布局（uart_16550a.sv）**：

```
PADDR[4:2] → NS16550A byte offset：
  0x00: THR/RBR (DLAB=0) / DLL (DLAB=1)
  0x04: IER     (DLAB=0) / DLM (DLAB=1)
  0x08: IIR (read) / FCR (write)
  0x0C: LCR
  0x10: MCR
  0x14: LSR
  0x18: MSR
  0x1C: SCR
```

---

## 9. 物理内存 / DDR 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| DDR 可访问 | ✅ | DDR3 通过 MIG 访问，SRAM 仿真模型可用，bootloader DDR3 自检通过 |
| DDR 起始地址 | ✅ | 0x8000_0000 |
| DDR 大小 | ✅ | 128MB 窗口（0x8000_0000~0x87FF_FFFF），足够最小 BusyBox Linux |
| 地址连续性 | ✅ | 128MB 连续地址空间 |
| 内存对齐 | ✅ | 0x80400000 为 4MB 对齐 |
| 访问宽度 | ✅ | byte/halfword/word load/store 均支持 |
| AMO 到 DDR | ✅ | A 扩展已实现，AMO/LR/SC 可在 DDR 上正确工作 |
| MMIO 与 DDR 区分 | ✅ | 地址空间不重叠（DDR 0x80xx, MMIO 0x00-0x1F, 0xFC） |

---

## 10. Device Tree 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| `/cpus` | ❌ | DTB 未创建 |
| `riscv,isa` | ❌ | DTB 未创建（应为 `rv32ima_zicsr_zifencei`） |
| `mmu-type` | ❌ | DTB 未创建（应为 `riscv,sv32`） |
| `timebase-frequency` | ❌ | DTB 未创建（应为 `<0x5F5E100>` = 100000000） |
| `/memory` | ❌ | DTB 未创建 |
| `/chosen` | ❌ | DTB 未创建 |
| UART node | ❌ | DTB 未创建（compatible = "ns16550a"） |
| CLINT/timer node | ❌ | DTB 未创建（CLINT 寄存器布局已标准化，可用 compatible = "sifive,clint0"） |
| PLIC node | ❌ | DTB 未创建 |
| reserved-memory | ❌ | DTB 未创建 |
| initrd 信息 | ❌ | DTB 未创建 |

---

## 11. Boot Protocol 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| 入口特权级 | ✅ | Boot ROM 在 M-mode 启动（PC=0xFC00_0000） |
| kernel 装载地址 | ⚠️ | 地址空间支持 4MB 对齐（0x80400000），但未配置 Linux 启动流程 |
| `a0` | ⚠️ | 单核 hartid=0，但 OpenSBI 未移植 |
| `a1` | ⚠️ | DTB 地址传递依赖 OpenSBI，未移植 |
| `satp` | ✅ | 复位后 satp=0，MMU 关闭 |
| 中断状态 | ⚠️ | 复位后中断关闭，但未验证 Linux 入口条件 |
| cache 状态 | ✅ | fence.i/sfence.vma 可清理 cache，启动流程可使用 |
| 固件保留内存 | ❌ | 未规划 OpenSBI 常驻区域 |
| DTB 格式 | ❌ | DTB 未创建 |
| initramfs | ❌ | 未创建 |

---

## 12. OpenSBI 平台最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| M-mode firmware 入口 | ❌ | OpenSBI 未移植 |
| console putchar | ❌ | OpenSBI 未移植（UART ns16550a 已就绪，OpenSBI 可直接使用） |
| console getchar | ❌ | OpenSBI 未移植 |
| timer driver | ❌ | OpenSBI 未移植（mtimecmp + STIP 注入路径已就绪） |
| interrupt delegation | ❌ | OpenSBI 未移植（硬件 medeleg/mideleg 已支持） |
| hart start | ⚠️ | 单核，boot hart 可简化 |
| IPI | N/A | 单核不需要 |
| PMP | ⚠️ | PMP CSR（pmpaddr0-15/pmpcfg0-3 + lock bit）**已实现**，OpenSBI 不会因访问 PMP CSR 崩溃。但 PMP **无硬件强制执行**（输出端口在 core_top.sv 未连接），配置的保护无实际效果 |
| final jump | ❌ | OpenSBI 未移植 |
| platform config | ❌ | OpenSBI 未移植 |

**PMP 实现详情**：

| PMP 特性 | 状态 | 证据 |
|----------|------|------|
| pmpaddr0-15 CSR | ✅ | `cpu_csr.sv:189-204`，16 个 32-bit 寄存器，M-mode 可读写 |
| pmpcfg0-3 CSR | ✅ | `cpu_csr.sv:185-188`，4 个 32-bit 寄存器（每寄存器含 4 个 entry 配置字节） |
| Lock bit (L) | ✅ | `cpu_csr.sv:336-351`，16 个 lock wire 提取；写保护：locked entry 不可修改 |
| Reserved bits WARL | ✅ | `cpu_csr.sv:357-378`，pmpcfg 写掩码 `& 8'h9F` 强制 bits[6:5]=0 |
| A field WARL | ⚠️ | 注释说仅支持 OFF(00)/TOR(01)，但硬件未拒绝 NA4/NAI 编码 |
| **硬件强制执行** | **❌** | `core_top.sv:830-849`：所有 PMP 输出端口未连接（空括号）。无地址匹配、无权限检查、无 PMP violation trap。MMU.sv 无 PMP 输入 |

---

## 13. Rootfs / BusyBox 最低要求

| 项目 | 检查结果 | 证据/备注 |
|------|---------|-----------|
| initramfs | ❌ | 未创建 |
| `/init` | ❌ | 未创建 |
| BusyBox | ❌ | 未编译 |
| `/bin/sh` | ❌ | 未创建 |
| `/dev` | ❌ | 未创建 |
| `/proc` | ❌ | 未创建 |
| `/sys` | ❌ | 未创建 |
| bootargs | ❌ | 未配置 |

> 此部分属于软件阶段，非 CPU 硬件条件。

---

## 14. 最终检查表（逐项标注）

| 大类 | 项目 | 达标条件 | 检查结果 | 证据/备注 |
|------|------|---------|---------|-----------|
| ISA | RV32I | 基础整数指令全部正确 | ✅ | 40 条指令，ISA 测试通过 |
| ISA | M 扩展 | 乘除法指令正确 | ✅ | Booth + 非恢复余数 |
| ISA | A 扩展 | LR/SC + AMO 全部正确 | ✅ | **已实现**：LR.W/SC.W + 9 条 AMO，misa bit0=1 |
| ISA | Zicsr | CSR 指令正确 | ✅ | 6 条 CSR 指令 |
| ISA | Zifencei | `fence.i` 有效 | ✅ | dcache wb + icache inv |
| ISA | `wfi` | 至少作为 NOP | ✅ | NOP 类指令 |
| CSR | `misa` | 与真实硬件能力一致 | ✅ | 0x40141121 = RV32AIMFSU，A 位已声明 |
| 特权级 | M-mode | 复位进入 M-mode | ✅ | PC=0xFC00_0000 |
| 特权级 | S-mode | Linux 可运行在 S-mode | ✅ | M/S/U 三级特权 |
| 特权级 | U-mode | 用户程序可运行在 U-mode | ✅ | 同上 |
| 特权级 | `mret/sret` | 返回语义正确 | ✅ | 恢复 IE/PIE/特权级 |
| 异常 | `ecall` | U/S/M ecall cause 正确 | ✅ | cause 8/9/11 |
| 异常 | page fault | cause/stval 正确 | ✅ | cause 12/13/15 |
| 委托 | `medeleg` | S-mode 异常委托正常 | ✅ | 0xB3FF 掩码，所有 Linux 需要的位可写 |
| 委托 | `mideleg` | S-mode 中断委托正常 | ✅ | 0x0AAA 掩码，SSI/MSI/STI/MTI/SEI/MEI 可写 |
| MMU | `satp` | Sv32 MODE/ASID/PPN 正确 | ✅ | satp CSR 实现 |
| MMU | PTW | 两级页表遍历正确 | ✅ | ptw_walk 测试通过 |
| MMU | 权限检查 | R/W/X/U/SUM/MXR 正确 | ✅ | MMU.sv + ptw.sv |
| MMU | `sfence.vma` | TLB 和页表可见性正确 | ✅ | **已修复**：dcache wb+inv → icache inv → TLB flush |
| Cache | I-cache | `fence.i` 后取新指令 | ✅ | fencei 测试通过 |
| Cache | D-cache | 普通 load/store 正确 | ✅ | dcache 测试通过 |
| Cache | MMIO bypass | 基于物理地址判断 MMIO | ✅ | **已修复**：is_mmio 用 cpu_req_addr（paddr） |
| Cache | PTW 一致性 | PTW 能看到最新 PTE | ✅ | **已修复**：sfence.vma 时 dcache 全量写回；A/D 位写回触发行无效化 |
| Timer | `mtime` | 64-bit 单调递增 | ✅ | CLINT r_mtime[63:0]，100 MHz |
| Timer | `mtimecmp` | 能触发 timer interrupt | ✅ | MTIP 触发逻辑 |
| Timer | STIP | Linux 能收到 S-mode timer | ✅ | **已修复**：sip[5] 可写，mip[5]=r_sip[5]，pending 用 csr_mip[5] |
| Counter | `time/timeh` | S-mode 可读 | ✅ | **已修复**：CSR 0xC01/0xC81 读 ext_mtime（CLINT mtime 经 CDC） |
| Interrupt | PLIC | claim/complete/enable 可用 | ✅ | PLIC 8 源，SiFive 标准布局，双上下文（M+S） |
| UART | TX/RX | 能稳定输出和输入 | ✅ | FIFO + 可配波特率 |
| UART | Linux compatible | ns16550a 或 SBI console | ✅ | **已修复**：uart_16550a 实例化，ns16550a 兼容 |
| DDR | 基础读写 | CPU-DDR 通信稳定 | ✅ | MIG + DDR3 自检通过 |
| DDR | 地址空间 | memory map 与 DTB 一致 | ⚠️ | 硬件正确，DTB 未创建 |
| Boot | OpenSBI | 能打印 banner 并跳转 | ❌ | OpenSBI 未移植 |
| Boot | kernel 地址 | RV32 kernel 4MB 对齐 | ⚠️ | 地址空间支持，未配置 |
| Boot | `a0/a1` | hartid 和 DTB 地址正确 | ❌ | OpenSBI 未移植 |
| Boot | `satp=0` | 进入 kernel 前 MMU 关闭 | ✅ | 复位后 satp=0 |
| DTB | `/cpus` | ISA/MMU/timebase 正确 | ❌ | DTB 未创建 |
| DTB | `/memory` | DDR 地址和大小正确 | ❌ | DTB 未创建 |
| DTB | `/chosen` | console/bootargs 正确 | ❌ | DTB 未创建 |
| Rootfs | initramfs | kernel 能找到 rootfs | ❌ | 未创建 |
| Rootfs | `/init` | 能执行并进入 shell | ❌ | 未创建 |

---

## 15. 关键阻塞项汇总

### 致命级（Linux 完全无法启动）

**无。** 上一版的 3 项致命阻塞已全部修复：

| # | 原阻塞项 | 修复状态 | 修复 commit |
|---|---------|---------|------------|
| 1 | A 扩展未实现 | ✅ 已修复 | LR/SC + 9 AMO 完整实现，misa bit0=1 |
| 2 | MMIO 判断基于虚拟地址 | ✅ 已修复 | is_mmio 改用 cpu_req_addr（paddr） |
| 3 | STIP 无置位路径 | ✅ 已修复 | sip_wmask 含 bit5，mip[5]=r_sip[5]，pending 用 csr_mip[5]，M/S 优先级修复 |

### 高危级（Linux 可启动但运行不稳定或功能严重受限）

| # | 阻塞项 | 当前状态 | 影响范围 | 修复工作量估算 |
|---|--------|---------|---------|--------------|
| 4 | PMP 无硬件强制执行 | CSR 实现完整，但输出端口未连接，无地址匹配/权限检查/trap | Linux 依赖 PMP 保护 M-mode 内存不被 S-mode 访问；无强制执行时 S-mode 可直接访问 M-mode 区域 | 中（需实现 PMP checker 模块 + 接入 MMU/memory 路径） |
| 5 | ~~CLINT 寄存器布局非标准~~ | ~~mtimecmp@0x00, mtime@0x08, msip@0x10~~ | ~~标准 Linux CLINT 驱动无法直接使用~~ | **已修复**：axi4lite_clint.sv 地址译码已改为 SiFive 标准布局（msip@0x0, mtimecmp@0x4000, mtime@0xBFF8），addr[15:0] 译码 |

### 中危级（可通过软件绕过但需额外工作）

| # | 阻塞项 | 当前状态 | 影响范围 | 绕过方案 |
|---|--------|---------|---------|---------|
| 6 | PMP A field WARL 未强制 | NA4/NAI 编码不被硬件拒绝 | 非 TOR 模式 PMP entry 行为未定义 | 软件仅使用 OFF/TOR 模式（Linux 默认） |

### 待办级（软件阶段工作，硬件就绪后推进）

| # | 项目 | 状态 |
|---|------|------|
| 7 | OpenSBI 移植 | 未开始（硬件条件已就绪：UART ns16550a + mtimecmp + STIP 注入 + medeleg/mideleg + PMP CSR） |
| 8 | Device Tree (DTB) 创建 | 未开始 |
| 9 | initramfs / BusyBox 构建 | 未开始 |
| 10 | Linux kernel 配置与编译 | 未开始 |

---

## 16. 建议修复顺序

```
Phase 0 — 硬件高危修复（建议完成以提高 Linux 稳定性）
  ├─ [P0-1] PMP 硬件强制执行
  │         当前：CSR 存储完整，输出未连接
  │         方案 A：实现 PMP checker 模块（地址匹配 + 权限检查 + violation trap）
  │                 接入 MMU.sv 或 core_top.sv memory 路径
  │         方案 B：Linux 不依赖 PMP 强制执行也能启动（S-mode 不会主动访问
  │                 M-mode 区域），可延后实现
  │
  └─ [P0-2] ~~CLINT 寄存器布局标准化~~ → **已完成**
            已修改 axi4lite_clint.sv 地址译码匹配 SiFive 标准布局
            msip@0x0000, mtimecmp@0x4000, mtime@0xBFF8
            addr[15:0] 译码，Linux 标准 sifive_clint 驱动可直接使用

Phase 1 — 软件平台搭建（硬件已就绪）
  ├─ [P1-1] 创建 Device Tree (DTS → DTB)
  │         必须描述：CPU (rv32ima_zicsr_zifencei, sv32, 100MHz),
  │         memory (0x80000000, 128MB), UART (ns16550a@0x10008000),
  │         CLINT (0x02000000), PLIC (0x0C000000), chosen (bootargs)
  │
  ├─ [P1-2] 移植 OpenSBI（platform: 自定义 SoC）
  │         硬件就绪项：UART ns16550a, mtimecmp, STIP 注入, medeleg/mideleg, PMP CSR
  │         需适配：CLINT 非标准布局, UART 地址
         注：PLIC 已标准化为 SiFive 布局 + 双上下文，Linux irq-sifive-plic.c 可直接使用
  │
  └─ [P1-3] Linux kernel 配置与编译
             rv32ima, 自定义 platform, ns16550a console

Phase 2 — 用户态验证
  ├─ [P2-1] 构建 initramfs + BusyBox（riscv32, musl 静态链接）
  └─ [P2-2] 验证 Linux 启动到 /bin/sh
```

---

## 17. 当前硬件能力总结

| 能力维度 | 状态 | 说明 |
|---------|------|------|
| 指令集 | ✅ | RV32AIMF_Zicsr_Zifencei，A 扩展已实现 |
| 特权级 | ✅ | M/S/U 三级完整，委托机制正确 |
| 虚拟内存 | ✅ | Sv32 正确，MMIO 基于物理地址，PTW-dcache 一致性已保证 |
| 异常/中断 | ✅ | 11 种异常 + 3 种中断，委托正确，M/S 优先级已修复 |
| 定时器 | ✅ | CLINT mtime/mtimecmp 正确，**寄存器布局已标准化（SiFive 标准布局）**，STIP 可写可注入，time/timeh CSR 已实现 |
| 中断控制器 | ✅ | PLIC 8 源，SiFive 标准地址布局，双上下文（M+S），claim/complete 正确 |
| 外设 | ✅ | UART ns16550a 兼容，SPI/GPIO/Timer 功能正确 |
| 内存 | ✅ | DDR3 128MB @ 0x80000000，Boot ROM 32KB @ 0xFC000000 |
| 缓存 | ✅ | I$/D$ 各 1KB 写回+写分配，MMIO 基于物理地址，sfence.vma 保证一致性 |
| PMP | ⚠️ | CSR 完整实现（16 pmpaddr + 4 pmpcfg + lock bit），**无硬件强制执行** |

---

## 18. SoC 地址映射

| 基地址 | 大小 | 设备 | 译码条件 |
|--------|------|------|---------|
| 0x0200_0000 | 16MB | CLINT | addr[31:24] == 8'h02 |
| 0x0400_0000 | 16MB | Sys Status | addr[31:24] == 8'h04 |
| 0x0C00_0000 | 16MB | PLIC | addr[31:24] == 8'h0C |
| 0x1000_0000 | 16MB | APB Bridge | addr[31:24] == 8'h10 |
| 0x8000_0000 | 128MB | DDR3/RAM | addr[31:27] == 5'h10 |
| 0xFC00_0000 | 16MB | Boot ROM | addr[31:24] == 8'hFC |

**APB 子地址译码（PADDR[15:14]）**：

| APB 偏移 | 设备 | 完整地址 |
|----------|------|---------|
| 0x0000 | GPIO | 0x1000_0000 |
| 0x4000 | Timer | 0x1000_4000 |
| 0x8000 | UART (ns16550a) | 0x1000_8000 |
| 0xC000 | SPI | 0x1000_C000 |

---

## 19. 总体判定

**当前 CPU/SoC 硬件已基本具备启动 Linux 的最低条件。** 上一版的 3 项致命阻塞（A 扩展、MMIO 虚拟地址判断、STIP 无置位路径）已全部修复。CLINT 寄存器布局已标准化为 SiFive 标准布局，Linux sifive_clint 驱动可直接使用。剩余硬件问题为：

1. **PMP 无硬件强制执行**（⚠️ 中危）— CSR 存储完整但不产生实际保护效果。Linux 不依赖 PMP 强制执行也能启动（S-mode 不会主动访问 M-mode 区域），但长期安全性需要实现。

**下一步**：进入软件平台搭建阶段（OpenSBI 移植 → DTB 创建 → Linux kernel 配置 → initramfs 构建）。硬件侧建议同步推进 PMP 强制执行实现。
