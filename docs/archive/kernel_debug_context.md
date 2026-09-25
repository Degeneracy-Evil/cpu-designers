> **[历史归档 2026-09-25]** 本文为 2026-06~08 的调试/规划快照：文中工具命令（`tools/vivado_cli`）、目录路径（`src/rtl`、`src/tb`、`src/program_source`）、时钟（cpu_clk 50MHz）及部分架构描述已被 2026-09 重构取代（现行工具链 `python3 -m tools.vivado`，RTL 位于 `src/{common,core,soc}`）。仅作历史记录，勿作操作依据。

# Kernel Boot 调试上下文交接

## 目标
修复 RISC-V 32位 CPU (RV32IMA) 上 Linux 7.1 kernel 零输出问题。OpenSBI v1.8.1 正常启动并打印 boot 信息，但跳转到 S-mode kernel 后 UART 无任何输出。

## CPU 与 SoC 基本信息
- **ISA**: RV32IMA (无 C 扩展, 无 Zicsr/Zifencei 单独扩展, M扩展已实现: Booth乘法器+非恢复除法器)
- **MMU**: SV32, 有 TLB (BRAM实现), 支持 sfence.vma
- **时钟**: CPU 50MHz, AXI/sys_clk 100MHz, UART 230400 baud
- **SoC地址映射**: DDR3@0x80000000, PLIC@0x0C000000, CLINT@0x02000000, APB@0x10000000, ROM@0xFC000000
- **UART**: 16550A 兼容, 基址 0x10008000, 寄存器间距 4 字节 (LSR@0x10008014, THR@0x10008000)
- **Kernel**: Linux 7.1, 加载到 0x80400000, PAGE_OFFSET=0xC0000000
- **OpenSBI**: fw_payload.bin, FW_PAYLOAD_OFFSET=0x400000, kernel at 0x80400000, DTB at 0x82200000
- **MEDELEG**: 0xb109 (delegated: 0,3,8,12,13,15; NOT delegated: 1,5,7,9,11)
- **MIDELEG**: 0x222 (SSIP, STIP, SEIP delegated)

## 之前的历史: 已修复的 RTL Bug (4个仿真全PASS)

### BUG-MMU-1: D bit check (已修复, 保留)
- 文件: `src/rtl/core/MMU.sv:278`
- 问题: store 到 D=0 的页不产生 page fault
- 修复: 添加 `(d_latched_access_type == ACCESS_STORE && !d_tlb_d)` 到 `d_tlb_perm_fault`

### BUG-CSR-5: MPIE writable (已修复, 保留)
- 文件: `src/rtl/core/cpu_csr.sv:409`
- 问题: mstatus 的 MPIE bit (bit 5) 不可写
- 修复: mstatus_wmask `3'b000` → `{1'b0, sw_csr_wdata[5], 1'b0}`

### BUG-CSR-3: sip ext_seip (已修复, 保留)
- 文件: `src/rtl/core/cpu_csr.sv:645`
- 问题: sip 读取不包含外部 SEIP
- 修复: `r_sip[9]` → `(ext_seip | r_sip[9])`

### BUG-MMU-3: PTW fault routing (已回退, 无效果)
- 文件: `src/rtl/core/core_top.sv:1285-1296`
- 问题: PTW access fault (cause 1/5/7) 被错误路由为 page fault (cause 12/13/15) 到 S-mode
- 修复尝试: 改为正确的 access fault 路由到 M-mode
- **回退原因**: MEDELEG 未委托 bit 1/5/7, access fault 去 M-mode 后 OpenSBI 不处理 → kernel 挂死
- **当前状态**: 已回退为原始行为 (access fault → page fault 到 S-mode), 但回退后 kernel 仍然零输出

## 当前最新修改 (待测试)

### 修改1: satp 写入触发 TLB flush (MMU.sv)
- **问题**: RISC-V spec 要求写 satp 时失效 TLB, 但 CPU 只更新 CSR 不刷 TLB
- **根因分析**: kernel 启动时 csrw satp 切换页表 (trampoline → final), TLB 中残留 stale 条目, 后续翻译可能用到错误物理地址
- **修复**: 在 MMU.sv 中添加 satp 变化检测:
  ```systemverilog
  reg [31:0] satp_prev;
  wire satp_changed = (satp != satp_prev) && (priv_mode != PRIV_M);
  wire mmu_flush_req = sfence_vma || satp_changed;
  ```
  所有 TLB flush 触发点 (FSM, flush_all, walk_abort) 从 `sfence_vma` 改为 `mmu_flush_req`
  `sfence_done` 追踪仍只用 `sfence_vma`

### 修改2: 移除 initcall_debug (simplecpu.dts)
- **问题**: bootargs 有 `initcall_debug`, 导致 do_one_initcall 调用 _printk/ktime_get
- **怀疑**: 这些调用可能损坏 s1 寄存器, 导致 jalr s1 跳到 BSS
- **修复**: 从 bootargs 移除 `initcall_debug`

### 修改3: Debug UART TX 模块 (新增)
- **目的**: 通过 UART 将 LCD 调试寄存器值发送到终端, 便于复制
- **文件**: `src/rtl/debug_uart_tx.sv` (新建)
- **集成**: `src/rtl/system_top.sv` 中 sw[5]=1 时 debug UART 接管 UART TX pin
- **格式**: `NAME=HHHHHHHH\r\n`, 自动循环发送当前 LCD 显示值

## FPGA LCD 调试结果 (原版 kernel, 无 initcall_debug)

### Page 2 (Trap Latch) — PC 在 0xCxxxxxxx 时的第一次 trap 快照
- **TRAP=1** (有 trap 被锁存)
- **CNT=0xE (14), 保持不变** (不再产生新 trap)
- **C_PRV=1** (当前 S-mode)
- **C_TRP=0** (不在进入 trap)
- **TPC=0xC04FA000** (trap 发生时 PC)
- **MCAUS=9** (mcause=9, ECALL from S-mode)
- **MEPC=0xC0010BC0** (mepc, ECALL 指令的下一条)
- **SEPC=0x80400098** (sepc, kernel 启动早期, MMU enable 后第一条指令的物理地址)
- **SCAUS=0xC** (scause=12, instruction page fault)

### Page 3 (S-origin Trap) — 第一次 S-mode trap
- **S_VLD=1** (有 S-mode trap)
- **R_VLD=0, R_CNT=0** (无递归 trap)
- **S_EPC=0xC04FA000** (sepc = BSS 地址!)
- **S_CAU=2** (scause=2, Illegal instruction)
- **S_TVL=0** (stval=0, CPU 未捕获指令编码)
- **S_SAT=0x800808FD** (satp: SV32 mode, PPN=0x808FD, page table at PA 0x808FD000)

### Page 4 (Pipeline + MMU)
- **IF_PC**: 一直在变化 (CPU 在运行, 不是死锁)
- **STATE**: 一直在变化
- **LM_V=1** (最后 MMIO 有效)
- **LM_AD=0x10008014** (UART LSR, 未变化)
- **LM_PC=0xC02917CC** (轮询代码在 serial8250_early_in)
- **LM_WE=0** (只读)
- **LM_RD=0x60** (LSR=0x60: bit5 THRE=1, bit6 TEMT=1 → THR 空闲!)
- **LM_CT=0x1083E77C** (2.7亿次 MMIO — 死循环轮询)

## 关键诊断链

1. **0xC04FA000 是 BSS 变量 `initcall_calltime`** — 不是代码地址
2. **CPU 支持 M 扩展** (mu_unit.sv: Booth乘法器 + 非恢复除法器) — 不是不支持的指令
3. **Initcall 表 (0xC03BB4F0-0xC03BB9CC) 所有函数指针都在 0xC03xxxxx** — 不含 0xC04FA000
4. **CPU 从 initcall 表读到错误数据 (0xC04FA000)** — `lw a0, 0(s1)` 应读 0xC03xxxxx, 实际读 0xC04FA000
5. **jalr s1 跳到 BSS → 0x00000000 (illegal instruction) → scause=2**
6. **Kernel 卡在 serial_putc 轮询循环** (0xC0291928): 读 LSR=0x60 (THR 空闲), beq 应该退出但不退出, 2.7亿次循环

## serial_putc 死循环分析

```assembly
serial_putc (0xC0291928):
  s2 = 0x60                    # THRE+TEMT mask
  serial8250_early_out(char)   # 写 THR (0x10008000)
loop:
  a0 = serial8250_early_in(5)  # 读 LSR (0x10008014) → LM_RD=0x60
  a0 = a0 & 0x60               # andi → a0 = 0x60
  beq a0, s2 → return          # 0x60 == 0x60 → 应该跳转但没跳!
  div a5, a5, zero             # 除零 (CPU 不 trap, 结果=全1)
  fence w
  j loop                       # 死循环
```

**LSR=0x60, beq 应该退出但没退出** — 可能原因:
- MMU 翻译错误: serial_putc 代码页 TLB 有 stale 条目, CPU 执行的不是正确的 beq 指令
- 寄存器损坏: s2 被 serial8250_early_in 调用损坏
- branch 单元 bug

## do_one_initcall 代码 (0xC0380D24)

```assembly
c0380d50: mv s1, a0           # s1 = init function pointer (从 initcall 表加载)
c0380d68: lui s4, 0xc04fa     # s4 = 0xC04FA000 (initcall_calltime 地址)
...
c0380d9c: sw a0, 0(a5)        # store ktime to initcall_calltime (a5=0xC04FA000)
c0380da0: sw a1, 4(a5)        # store ktime high bits
c0380da4: jalr s1             # call init function → 跳到 0xC04FA000 (BSS!)
```

**s4 = 0xC04FA000**, CPU 跳到的地址也是 0xC04FA000。s1 可能被损坏成了 s4 的值。

## Kernel 启动早期代码 (relocate_enable_mmu @ 0xC0000040)

```assembly
c0000094: csrw satp, a0       # 启用 trampoline 页表
c0000098: auipc a0, 0x0       # 第一条 MMU 翻译指令 (VA 0xC0000098)
...
c00000ac: csrw satp, a2       # 切换到 final 页表 (TLB 未刷新!)
c00000b0: sfence.vma          # 这里有 sfence, 但 satp 已切换
c00000b4: ret
```

**关键**: 0xC0000094 写 satp 启用 trampoline → TLB 开始填充 → 0xC00000AC 再写 satp 切换 final 页表 → **TLB 中 trampoline 的条目残留** → 后续翻译可能用错误物理地址

## RTL satp MODE 编码 (非标准但 kernel 匹配)

RTL 用 `satp[31]` (1位) 判断 SV32:
```systemverilog
wire i_sv32 = satp[31] && (priv_mode != PRIV_M) && i_translate_en;
```
Spec 要求 `satp[31:30] == 2'b01` (MODE=1), 但 kernel 也用 `(mode << 31)` = 0x80000000 (bit31=1), 所以两者匹配。**不是问题**。

## 尚未排除的可能性

1. **TLB stale 条目** (已修复, 待测试) — satp 写入不刷 TLB 是 spec 违规
2. **icache coherency** — kernel 有 `fence.i` 指令, CPU 是否正确处理?
3. **dcache coherency** — PTW 写 A/D bit 后 dcache 是否失效? (core_top.sv 有 PTW writeback → dcache invalidation 逻辑)
4. **寄存器堆 bug** — s1/s2 被意外损坏
5. **branch 单元 bug** — beq 比较器在特定条件下错误
6. **AXI bus 数据错误** — DDR3 返回错误数据 (不太可能, OpenSBI 正常)

## 关键文件

- `src/rtl/core/MMU.sv` — MMU + TLB + PTW (satp flush 修复)
- `src/rtl/core/core_top.sv` — CPU 顶层 (PTW fault routing, sfence sequencing)
- `src/rtl/core/cpu_csr.sv` — CSR 文件 (satp 写入, medeleg/mideleg)
- `src/rtl/core/cpu_execute.sv` — 执行单元 (MU/FPU handshake)
- `src/rtl/core/ptw.sv` — Page Table Walker
- `src/rtl/core/tlb.sv` — TLB (BRAM)
- `src/rtl/debug_uart_tx.sv` — 新建: debug UART TX 模块
- `src/rtl/system_top.sv` — SoC 顶层 (UART mux, LCD debug, ILA)
- `boot/dts/simplecpu.dts` — 设备树 (已移除 initcall_debug)
- `src/docs/scan.md` — 完整审计报告 + FPGA 调试结果
- `build/kernel/vmlinux` — kernel ELF (可反汇编)
- `tools/uart_console.py` — UART 捕获脚本

## Vivado 环境
- Vivado 2018.3: `/tools/Xilinx/Vivado/2018.3/bin`
- Python: `python3`
- 仿真: `python3 -m tools.vivado_cli -task <name> -create -sim` (必须 -create)
- 构建: `python3 tools/test_builder.py --test <name>`
- ILA 构建: `vivado -mode batch -source tools/vivado_core/tcl/build_with_ila.tcl`
- ILA 探针: `ila_cpu_axi` (probe6=if_pc), `ila_reset_axi`

## 下一步建议

1. **先测试当前修改**: 重新综合 + 重新编译 DTB/fw_payload → FPGA 测试
   - sw[5]=0: 看 kernel 是否有 UART 输出
   - sw[5]=1: 终端看 debug 寄存器值, 对比之前 LCD 结果
2. 如果仍然零输出, 检查 LCD/debug UART:
   - CNT 是否还在增长? (trap 是否还在发生)
   - S_EPC 是否还是 0xC04FA000? (illegal instruction 是否还在同一地址)
   - LM_RD 是否还是 0x60? (LSR 是否还是 THR ready)
3. 如果 satp flush 修复有效, kernel 应该能正确翻译 initcall 表, 不再跳到 BSS
4. 如果无效, 考虑:
   - ILA 抓取 if_pc 在 0xC0380DA4 (jalr s1) 附近的执行, 看 s1 的值
   - ILA 抓取 if_pc 在 0xC0291964 (beq) 附近的执行, 看 a0/s2 的值和 beq 是否跳转
   - 检查 icache 是否有 stale 条目 (fence.i 处理)
   - 检查 dcache PTW writeback invalidation 是否正确
