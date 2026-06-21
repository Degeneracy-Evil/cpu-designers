# Run Linux 调试进程：PC 卡死在 C0000098

> 日期: 2026-06-20
> 目标: Artix-7 xc7a200t, system_top, OpenSBI + Linux (fw_payload.elf)
> 状态: **全仿真验证通过** — 26/26 测试 PASS（12 MMU + 14 回归），待 FPGA 验证
> 固件: `/tmp/fws/firmware/fw_payload.elf` (ELF32, RISC-V, entry=0x80000000)
> 更新: 2026-06-21 — BUG-16 + 紧急补丁 + HIGH-2 + UART THRE + DCache error/fairness + AXI error injection + trap_enter/bridge fix + WB reissue holdoff + RAM error model + TLB死代码清理 + 总线/CDC审计 + mtime Gray编码CDC + core_top声明顺序修复 + PLIC/CLINT/UART AXI4-Lite修复 + 全回归通过

---

## 1. 问题描述

FPGA 运行 OpenSBI + Linux 时，LCD 显示 PC 卡死在 `C0000098`，CPU 进入 trap 死循环。
OpenSBI 正常启动并跳转到 Linux kernel payload (0x80400000)，Linux kernel 启用 Sv32 分页后触发 instruction page fault，trap 到 STVEC=C0000098，但 trap handler 自身也无法取指，形成无限循环。

---

## 2. LCD 完整输出与信号解读

### 2.1 Page 1 — IF/Trap 寄存器

| 信号 | 值 | 含义 |
|------|------|------|
| IF PC | `C0000098` | 取指 PC 卡死（= STVEC） |
| IF IN | `00098067` | 指令寄存器内容（可能是 stale 数据，I_RDY=0） |
| RSTN | `00000001` | 复位已释放 |
| STATE | `00000001` | 流水线状态 |
| T PC | `C0000098` | Trap PC |
| MCAUS | `00000002` | mcause = illegal instruction（上次 M-mode trap） |
| MTVEC | `80000418` | M-mode trap vector |
| MEPC | `80400000` | M-mode exception PC |
| STVEC | `C0000098` | S-mode trap vector = 当前 PC |
| SEPC | `80400098` | S-mode exception PC（Linux kernel payload 内） |
| SCAUS | `0000000C` | scause = 12 = instruction page fault |
| PRIV | `00000001` | S-mode (PRIV_S = 2'b01) |
| TPRIV | `00000001` | Target privilege = S-mode |
| TRAPF | `00000001` | Trap flag 置位 |
| CNT | `00000001` | Trap count = 1 |

### 2.2 Page 3 — S-origin Trap Monitor（关键）

| 信号 | 值 | 含义 |
|------|------|------|
| S VLD | `00000001` | S-origin trap 有效 |
| S EPC | `80400098` | S-mode exception PC |
| S CAU | `00000000` | S-origin cause（可能捕获的是不同 trap 事件） |
| S TVL | `80400098` | S-mode tval |
| S PVM | `00000005` | S-origin from→to privilege |
| S STT | `00000100` | S-origin sstatus |
| STVC | `C0000098` | S-origin stvec |
| S SCR | `00000000` | S-origin sscratch |
| **S SAT** | **`800808FC`** | **satp = Sv32 mode (bit31=1), PPN=0x808FC → 页表在物理 0x808FC000** |
| S CNT | `00000002` | S-mode trap count = 2（已发生 2 次 S-mode trap） |

### 2.3 Page 4 — icache/MMU 状态（关键）

| 信号 | 值 | 含义 |
|------|------|------|
| IC ST | `00000001` | icache 状态 = `S_TAG_READ`（等待 MMU 翻译完成） |
| IC RF | `00000000` | icache refill = 0（不在 refill） |
| I RDY | `00000000` | 指令未就绪（MMU 翻译未完成） |
| IFDON | `00000000` | IF done = 0 |
| I MIS | `00000000` | 无 instruction misalign |
| I PF | `00000000` | 无活跃 instruction page fault（已 latch 并 trap） |
| INVAL | `00000000` | 无 invalid |
| RFV | `00000000` | 无 refill valid |
| PTHAC | `00000000` | 无 path access |
| PIWLK | `00000000` | 无 pipeline walk |

---

## 3. 根因分析

### 3.1 启动流程反汇编

固件布局（`fw_payload.elf`）：

| Section | VMA | Size | 内容 |
|---------|-----|------|------|
| .text | 0x80000000 | 0x36448 | OpenSBI |
| .rodata | 0x80037000 | 0x9458 | OpenSBI rodata |
| .data | 0x80080000 | 0x2250 | OpenSBI data |
| .bss | 0x80083000 | 0x918 | OpenSBI bss |
| **.payload** | **0x80400000** | **0x4F9678** | **Linux kernel** |

Linux kernel 入口代码（`80400000`-`804000d4`）：

```assembly
80400000: j 804000d4              # 跳转到初始化
...
80400040: auipc a1,0x455          # 加载重定位偏移
80400044: addi a1,a1,-672
80400048: lw a1,0(a1)
8040004c: auipc a2,0x0
80400050: addi a2,a2,-76          # a2 = 80400000 (payload base)
80400054: sub a1,a1,a2            # a1 = relocation offset
80400058: add ra,ra,a1            # 重定位返回地址
8040005c: auipc a2,0x0
80400060: addi a2,a2,60           # a2 = 80400098
80400064: add a2,a2,a1            # a2 = 80400098 + reloc = C0000098
80400068: csrw stvec,a2           # ★ stvec = C0000098 (虚拟地址)
8040006c: srli a2,a0,0xc
80400070: auipc a1,0x455
80400074: addi a1,a1,-688
80400078: lw a1,0(a1)             # a1 = config from memory
8040007c: or a2,a2,a1
80400080: auipc a0,0x4fc
80400084: addi a0,a0,-128         # a0 = 0x808FC000 (页表物理地址)
80400088: srli a0,a0,0xc          # a0 = 0x808FC (PPN)
8040008c: or a0,a0,a1             # a0 = 0x808FC | mode = 0x800808FC
80400090: sfence.vma              # TLB flush
80400094: csrw satp,a0            # ★★★ 启用 Sv32 分页 (satp=0x800808FC)
80400098: auipc a0,0x0            # ★★★ SEPC=80400098 — 启用分页后第一条指令
8040009c: addi a0,a0,32           # a0 = 804000b8
804000a0: csrw stvec,a0           # 更新 stvec (未到达)
804000a4: auipc gp,0x4f9
804000a8: addi gp,gp,-2012        # gp = 808f88c8
804000ac: csrw satp,a2            # 切换到最终 kernel 页表 (未到达)
804000b0: sfence.vma              # (未到达)
804000b4: ret                     # (未到达)
804000b8: wfi                     # 临时 trap handler: wait for interrupt
804000bc: j 804000b8              # 循环
```

### 3.2 Trap 死循环机制

```
┌─────────────────────────────────────────────────────────┐
│  1. csrw satp, 0x800808FC  (80400094)                   │
│     → Sv32 分页启用，页表在物理 0x808FC000              │
│                                                         │
│  2. 取指 PC=80400098  (80400098)                        │
│     → MMU 翻译 VA 80400098                             │
│     → 页表中无 identity mapping for 804xxxxx            │
│     → instruction page fault (cause=12)                │
│     → SEPC=80400098, SCAUS=0xC                         │
│                                                         │
│  3. Trap 委托到 S-mode (medeleg[12]=1, priv=S)         │
│     → PC = STVEC = C0000098                             │
│                                                         │
│  4. 取指 PC=C0000098                                    │
│     → MMU 翻译 VA C0000098                             │
│     → icache 进入 S_TAG_READ，等待 mmu_ready            │
│     → TLB miss → PTW page table walk                    │
│     → PTW 读 L1 PTE at 0x808FCC00 (DDR3)               │
│     → 翻译失败/超时/错误 → page fault                   │
│     → Trap 到 STVEC = C0000098                          │
│                                                         │
│  5. 回到步骤 4 — 无限循环                                │
└─────────────────────────────────────────────────────────┘
```

### 3.3 关键 RTL 代码路径

```
icache_ctrl.sv:
  S_TAG_READ (IC_ST=1)
    → 等待 mmu_ready (i_ready)
    → mmu_ready=0 因为 TLB miss

MMU.sv:
  i_ready = (i_state == I_LOOKUP) && !i_input_changed
            && (!i_latched_sv32 || (i_tlb_hit && !i_tlb_perm_fault))
  → TLB miss → I_WALK_PENDING → 启动 PTW

ptw.sv:
  S_IDLE → S_L1_READ → S_L1_CHECK
    → 读 L1 PTE: {satp_ppn, 12'b0} + {vpn1, 2'b0}
    = 0x808FC000 + 0x300*4 = 0x808FCC00
    → 通过 cpu_bus_bridge 发起 AXI4 读

cpu_bus_bridge.sv:
  S_IDLE → S_PTW_AR → S_PTW_R
    → AXI4 AR channel: araddr=0x808FCC00
    → 路由到 slave 0 (DDR3, addr[31:27]==5'h10)

system_top.sv:
  AXI crossbar:
    ar_slave_sel = (cdc_araddr[31:27] == 5'h10) ? 3'd0 : ...
    → 0x808FCC00: addr[31:27]=0x10 → slave 0 (DDR3) ✓

PTW 结果:
  → 成功: TLB fill → i_ready=1 → icache 继续
  → 失败: S_FAULT → i_page_fault → trap_manager → trap to STVEC
  → 超时: 256 cycle timeout → S_FAULT → 同上
```

### 3.4 页表位置验证

| 项目 | 值 |
|------|------|
| satp | `0x800808FC` |
| Mode | Sv32 (bit31=1) |
| PPN | `0x808FC` |
| 页表物理基址 | `0x808FC000` |
| .payload 范围 | `0x80400000 - 0x808F9678` |
| 页表 vs .payload | 超出 .payload 末尾 10KB (0x2988) |
| **结论** | **页表由内核在运行时于 DDR3 中动态创建，不在固件二进制中** |

页表 L1 PTE 地址计算（VA C0000098）：
- VPN[1] = C0000098[31:22] = 0x300
- VPN[0] = C0000098[21:12] = 0x000
- L1 PTE 地址 = 0x808FC000 + 0x300 × 4 = **0x808FCC00**

---

## 4. 仿真复现方案

### 4.1 约束分析

| 约束 | 值 | 影响 |
|------|------|------|
| 固件大小 (fw_payload.bin) | 9.0 MB | 远超 SRAM 容量 |
| SRAM 容量 (axi_wrap_ram) | 1 MB (262144 × 4B) | 无法直接加载完整固件 |
| 页表 SRAM 偏移 | 0x8FC000 = 8.98 MB | 远超 1MB SRAM |
| DDR3 容量 | 128 MB | 足够，但仿真极慢 |
| OpenSBI only (fw_jump.bin) | 0.5 MB | 可放入 SRAM，但无 Linux |

### 4.2 方案 A：扩大 SRAM 模型（推荐用于完整验证）

修改 `dev/rtl/ram_wrap/axi_wrap_ram.sv`：

```systemverilog
// 从 256K words (1MB) 扩大到 4M words (16MB)
localparam MEM_DEPTH = 4194304;  // 16MB / 4B = 4M words
```

步骤：
1. 修改 SRAM 深度
2. 将 `fw_payload.bin` 转为 hex 格式
3. 创建 testbench 加载 hex 到 SRAM
4. 运行仿真：`python -m tools.vivado_cli -task linux_boot -create -sim --debug trace,trap,wave`

优点：完整复现 Linux 启动流程
缺点：仿真时间长（16MB SRAM + 9MB 固件），综合时间增加

### 4.3 方案 B：构造聚焦测试程序（推荐用于快速迭代）

编写小型汇编测试，复现相同 trap 场景：

```assembly
# test_linux_trap_loop.S
# 目标：验证 Sv32 启用后 trap handler 不可达时的行为

.section .text
.global _start

_start:
    # 1. 在 SRAM 内建立页表 (物理 0x80080000-0x80081000)
    #    L1 table at 0x80080000 (1KB = 256 entries)
    #    L0 table at 0x80081000 (4KB = 1024 entries)

    # 设置 L1 PTE for VPN1=0x300 (VA 0xC0000000-0xC03FFFFF)
    # → 指向 L0 table at 0x80081000
    la t0, 0x80080000
    li t1, 0x80081000       # L0 table physical address
    srli t1, t1, 12          # PPN
    slli t1, t1, 10          # PPN to PTE position
    ori t1, t1, 0x1          # V=1 (valid pointer)
    li t2, 0x300             # VPN1 index
    slli t2, t2, 2           # ×4
    add t3, t0, t2
    sw t1, 0(t3)             # L1[0x300] = pointer to L0

    # 设置 L0 PTE for VPN0=0x000 (VA 0xC0000000-0xC0000FFF)
    # → 映射到物理 0x80400000 (Linux kernel payload)
    la t0, 0x80081000
    li t1, 0x80400000        # target physical address
    srli t1, t1, 12          # PPN
    slli t1, t1, 10          # PPN to PTE position
    ori t1, t1, 0x1F         # V=1,R=1,W=1,X=1,A=1,D=1
    sw t1, 0(t0)             # L0[0x000] = leaf PTE

    # 2. 设置 stvec = C0000098 (虚拟地址)
    li t0, 0xC0000098
    csrw stvec, t0

    # 3. 启用 Sv32 分页
    li t0, 0x80080000        # L1 table physical address
    srli t0, t0, 12          # PPN
    li t1, 0x80000000        # Sv32 mode bit
    or t0, t0, t1            # satp = mode | PPN
    sfence.vma
    csrw satp, t0            # ★ 启用分页

    # 4. 下一条指令触发 page fault (无 identity mapping)
    #    → trap to STVEC = C0000098
    #    → 如果 C0000098 可翻译 → trap handler 执行
    #    → 如果 C0000098 不可翻译 → trap 死循环
    auipc a0, 0              # ← 此处应触发 page fault

    # 5. 如果 trap handler 成功执行，会到达这里
    li x28, 0xPASS           # 标记成功
    j done

trap_handler:
    # 位于 C0000098 对应的物理地址
    # 处理 page fault，恢复执行
    li x28, 0xTRAP           # 标记 trap 被处理
    j done

done:
    j done
```

构建与仿真：
```bash
# 添加到 build.yaml
python tools/test_builder.py --test regression/linux_trap_loop

# 仿真
python -m tools.vivado_cli -task reg_linux_trap_loop -create -sim --debug trace,trap,wave

# 分析
python -m tools.trace_analyzer parse instr_trace.log
python -m tools.trace_analyzer find-fail instr_trace.log
```

优点：快速（<1分钟仿真），可在 1MB SRAM 中运行
缺点：需要手动构造页表，不能验证完整 Linux 启动

### 4.4 方案 C：DDR3 仿真（最慢但最完整）

修改 `dev/rtl/soc_config.vh`：
```verilog
`define SIMU_USE_DDR 1   // 启用 DDR3 模型
```

步骤：
1. 修改配置
2. 创建 DDR3 仿真任务，加载 fw_payload
3. 运行仿真（预计数小时）

优点：完整复现 FPGA 行为
缺点：极慢（DDR3 MIG 初始化 + 9MB 程序加载 + 仿真运行）

### 4.5 方案对比

| 方案 | 耗时 | 完整性 | 适用场景 |
|------|------|--------|----------|
| A: 扩大 SRAM | ~30min | 高 | 完整验证 Linux 启动 |
| B: 聚焦测试 | ~5min | 中 | 快速验证 MMU/trap 逻辑 |
| C: DDR3 仿真 | ~数小时 | 最高 | 完整复现 FPGA 行为 |

**推荐顺序**：B → A → C

---

## 5. 调试步骤

### 5.1 第一步：聚焦测试验证硬件逻辑

1. 编写 `reg_linux_trap_loop.S`（方案 B）
2. 添加到 `dev/program_source/build.yaml`
3. 构建：`python tools/test_builder.py --test regression/linux_trap_loop`
4. 仿真：`python -m tools.vivado_cli -task reg_linux_trap_loop -create -sim --debug trace,trap,wave`
5. 分析 `trap_trace.log` 和 `instr_trace.log`

**验证目标**：
- Sv32 启用后，无 identity mapping 的地址是否正确触发 page fault
- STVEC 指向的虚拟地址无法翻译时，是否产生 trap 死循环
- PTW 超时/错误行为是否正确
- trap 委托逻辑（medeleg）是否正确

### 5.2 第二步：扩大 SRAM 完整验证

如果聚焦测试通过（硬件逻辑正确）：

1. 修改 `axi_wrap_ram.sv` MEM_DEPTH = 4194304 (16MB)
2. 转换固件：`riscv64-unknown-elf-objcopy -O binary fw_payload.elf fw_payload.bin`
3. 编写 hex 转换脚本：`python3 tools/bin2hex.py fw_payload.bin fw_payload.hex`
4. 创建 testbench 加载 hex
5. 仿真运行

**验证目标**：
- Linux kernel 是否正确建立页表
- 页表 at 0x808FC000 是否包含 C0000098 的有效映射
- PTW 是否能正确读取页表项

### 5.3 第三步：FPGA ILA 抓取

如果仿真无法复现（硬件逻辑正确，问题在 DDR3）：

1. 在 `system_top.sv` 中添加 ILA 探针：
   - PTW AXI 总线：`cpu_araddr`, `cpu_arvalid`, `cpu_rdata`, `cpu_rvalid`
   - MMU 状态：`i_state`, `walk_state`, `ptw state`
   - icache 状态：`icache state`
2. 触发条件：`cpu_araddr == 0x808FCC00`（页表 L1 PTE 地址）
3. 抓取 PTW 总线事务的完整 AXI 握手
4. 检查 DDR3 返回的 PTE 数据是否正确

### 5.4 第四步：对比 Spike

```bash
# Spike 仿真相同固件
spike --isa=rv32ima /tmp/fws/firmware/fw_payload.elf

# 对比 commit log
python -m tools.trace_analyzer diff instr_trace.log spike_commit.log
```

---

## 6. 关键文件索引

### 6.1 RTL 文件

| 文件 | 作用 |
|------|------|
| `dev/rtl/core/icache_ctrl.sv` | icache 控制器（S_TAG_READ 状态等待 mmu_ready） |
| `dev/rtl/core/MMU.sv` | MMU（TLB 查找 + PTW 仲裁 + page fault 生成） |
| `dev/rtl/core/ptw.sv` | Page Table Walker（Sv32 两级页表遍历 + 256 周期超时） |
| `dev/rtl/core/cpu_bus_bridge.sv` | AXI4 总线桥（PTW/icache/dcache 仲裁） |
| `dev/rtl/core/cpu_trap_manager.sv` | 异常检测 + cause 编码 + CLINT 实例化 |
| `dev/rtl/core/cpu_clint.sv` | Trap 派发（delegation + trap PC + CSR 写数据） |
| `dev/rtl/core/cpu_csr.sv` | CSR 寄存器文件（stvec/sepc/scause/satp 等） |
| `dev/rtl/core/cpu_controller.sv` | 流水线 FSM（TRAP_ENTER/TRAP_RETURN 状态） |
| `dev/rtl/core/core_top.sv` | Core 顶层（priv_mode 切换 + PC 更新） |
| `dev/rtl/system_top.sv` | SoC 顶层（AXI crossbar + DDR3/SRAM + LCD debug） |

### 6.2 关键信号

| 信号 | 路径 | 含义 |
|------|------|------|
| `state` | `icache_ctrl.dbg_state` | icache FSM 状态 (0=IDLE, 1=TAG_READ, 2=READ, 3=REFILL) |
| `i_ready` | `MMU.i_ready` | i-side 翻译完成 |
| `i_state` | `MMU.i_state` | i-side FSM (0=IDLE, 1=LOOKUP, 2=WALK_PENDING, 3=FILL_WAIT) |
| `walk_state` | `MMU.walk_state` | PTW 仲裁 (0=IDLE, 1=D_WALK, 2=I_WALK) |
| `state` | `ptw.state` | PTW FSM (0=IDLE, 1=L1_READ, 2=L1_CHECK, ...) |
| `i_page_fault` | `MMU.i_page_fault` | instruction page fault 脉冲 |
| `trap_enter_valid` | `core_top` | Trap 进入有效 |
| `priv_mode` | `core_top.priv_mode` | 当前特权级 (0=U, 1=S, 3=M) |

### 6.3 AXI 地址映射

| 地址范围 | Slave | 判定条件 |
|----------|-------|----------|
| 0x80000000-0x87FFFFFF | 0: DDR3/RAM (128MB) | `addr[31:27] == 5'h10` |
| 0xFC000000-0xFCFFFFFF | 1: Boot ROM | `addr[31:24] == 8'hFC` |
| 0x0C000000-0x0CFFFFFF | 2: PLIC | `addr[31:24] == 8'h0C` |
| 0x02000000-0x02FFFFFF | 3: CLINT | `addr[31:24] == 8'h02` |
| 0x10000000-0x10FFFFFF | 4: APB Bridge | `addr[31:24] == 8'h10` |
| 0x04000000-0x04FFFFFF | 5: Sys Status | `addr[31:24] == 8'h04` |
| 其他 | 6: Default (DECERR) | — |

页表地址 0x808FCC00 → `addr[31:27]=0x10` → **slave 0 (DDR3)** ✓

---

## 7. 相关 Bug 修复历史

以下已修复的 bug 与本问题相关（见 `process/near-linux-bug-fix.md`）：

| Bug | 描述 | 相关性 |
|-----|------|--------|
| Bug 1 | is_mmio 基于虚拟地址 → 改为物理地址 | 高：影响 MMU 地址判定 |
| Bug 2 | STIP 使用 ext_mtip 而非 csr_mip[5] | 中：S-mode timer interrupt |
| Bug 3 | sfence.vma 未 abort PTW | 高：页表切换时 PTW 残留 |
| Bug 4 | time/timeh CSR 未实现 | 低：timer 相关 |
| Bug 5 | PTW A/D 更新走 dcache 路径 | 高：PTW 总线访问 |
| Bug 6 | PMP 未实现 | 低：Linux 不依赖 PMP |
| Bug 7 | NS16550A UART 兼容性 | 低：UART 初始化 |
| Bug 9 | Vivado 工具 bug | 低：综合问题 |
| Bug 10 | FMADD.S 浮点 | 无 |
| Bug 11 | rodata section 加载 | 中：内核数据段 |

---

## 8. 待办事项

- [x] **修复 HIGH-1**：恢复 `ptw.sv` 中 `S_AD_UPDATE` 路径 — **已完成**，S_PERM_CHECK 检测 !pte_a → S_AD_UPDATE 写回 PTE|0x40 → S_AD_WAIT → S_DONE 填充 TLB
- [x] **修复 HIGH-2**：`ptw.sv` S_L1_CHECK 中 pre-issue L0 read，跳过 S_L0_READ 直接进 S_L0_CHECK，消除 bus_req_pending_r 1 周期空隙 — **已完成**
- [x] **修复 MEDIUM-3**：`MMU.sv` 中 `selected_d_walk` 逻辑包含 `pending_d_walk`，`active_d_walk` 正确选择 d-side 地址 — **已完成**（紧急补丁）
- [x] **紧急补丁**：PTW `walk_fault_kind` 区分 page fault / access fault；bus error 作为终止态不再等超时 — **已完成**
- [x] **仿真验证**：12/12 MMU 测试 PASS，8/10 回归测试 PASS — **已完成**
- [x] **修复 UART THRE**：`uart_regs_16550a.sv:347` `thre_set_en` 从 `1'b1` 改为 `(tstate == 3'd0)`，THRE 仅在移位寄存器空闲时置位 — **已完成**
- [x] **验证 DCache error 完成路径**：bridge error 时也置 `done=1`；dcache S_WB_SEND/S_REFILL 检查 `error` flag 后回 S_IDLE — **已修复**
- [x] **验证 flush error 完成路径**：S_FLUSH_WB_SD error 时记录 `flush_error_seen_r` 并继续推进，不 hang — **已修复**
- [x] **验证 write-back 公平性**：`wb_starve_cnt_r` 3 周期计数 → `wb_boost_r` 提升到最高优先级 — **已修复**
- [x] **修复 AXI error injection 回归测试**：`reg_dcache_wb_error` + `reg_dcache_refill_error` PASS — **已完成**
- [ ] **验证修复后 FPGA**：上 FPGA 确认 Linux 启动流程通过 STVEC=C0000098 处，且 UART 输出不再丢失
- [ ] 修复 `reg_bug16_tlb_valid_pulse` 测试程序（trap 嵌套处理不完善，非 CPU bug）
- [ ] 如果仿真无法复现 → FPGA ILA 抓取 PTW 总线
- [ ] 对比 Spike ISA simulator

---

## 9. 结论

**直接原因**：Linux kernel 在 `80400094` 启用 Sv32 分页后，下一条指令（`80400098`）作为虚拟地址在页表中无映射，触发 instruction page fault。Trap 委托到 S-mode，跳转到 STVEC=C0000098，但 C0000098 的页表翻译也无法完成，形成 trap 死循环。

**根本原因**（已定位并修复）：
1. **BUG-16**：BRAM TLB `i_lookup_valid_r` 是 1 周期脉冲，MMU `I_LOOKUP` 状态持续多周期，脉冲过期后 `valid=0, hit=1, ready=0, miss=0` → MMU 死锁。**已修复**：`i_tlb_lookup_req` 在 `I_LOOKUP` 期间保持高电平。
2. **HIGH-1**：PTW 在 PTE.A=0 时走 S_FAULT 不填 TLB → 下次 lookup 又 miss → 无限循环。**已修复**：恢复 S_AD_UPDATE 路径，硬件写回 PTE|0x40 后填充 TLB。
3. **HIGH-2**：PTW L1→L0 读取间 `bus_req_pending_r` 有 1 周期空隙，bus bridge PTW 优先级最低会被抢占。**已修复**：S_L1_CHECK 中 pre-issue L0 read，跳过 S_L0_READ。
4. **MEDIUM-3**：`active_d_walk` 在 `W_IDLE + pending_d_walk` 时为 0，PTW 用 i-side 地址做 d-walk。**已修复**：`selected_d_walk` 逻辑包含 `pending_d_walk`。
5. **UART THRE**：`thre_set_en = 1'b1` 导致 THRE 仅反映 TX FIFO 空，不反映移位寄存器正在发送。real 8250 driver 仅等 THRE → 全速写 THR → 16 字节 FIFO 溢出 → 后续输出全丢。**已修复**：`thre_set_en = (tstate == S_IDLE)`。
6. **DCache error 完成路径**：bridge 在 AXI error 时仅 pulse `dcache_error_r` 不置 `done`，dcache FSM 死等 `refill_valid`/`wb_valid` → 永久 stall。**已修复**：bridge error 时也置 `dcache_refill_done_r`/`dcache_wb_done_r`；dcache 检查 `error` flag 后回 S_IDLE。
7. **Flush error 完成路径**：S_FLUSH_WB_SD 仅在 `wb_valid` 成功时推进，无 error 路径 → fence.i/sfence.vma 死锁。**已修复**：error 时记录 `flush_error_seen_r` 并继续推进到下一 way/set，最终到达 `flush_done`。
8. **Write-back 公平性**：dcache_wb 优先级最低（icache_mmio > dcache_mmio > ptw > dcache_wb > ...），无公平机制 → 持续 PTW/MMIO 压力下饥饿。**已修复**：`wb_starve_cnt_r` 3 周期计数 → `wb_boost_r` 提升到最高优先级。

**仿真验证状态**：12/12 MMU 测试 PASS，8/10 回归测试 PASS。未引入新失败。

**推荐下一步**：上 FPGA 验证 Linux 启动是否通过 C0000098。

---

## 10. MMU-PTW 结构隐患检查（2026-06-20, 第二次硬件修改后）

### 10.1 当前修改摘要

> **BUG-16 修复**（`MMU.sv:170-177`）：`i_tlb_lookup_req` / `d_tlb_lookup_req` 从 `(state == I_IDLE)` 改为 `i_req_active = (i_state == I_LOOKUP) && !i_input_changed`。BRAM TLB valid 脉冲不再过期。
>
> **紧急补丁**：
> - PTW 新增 `walk_fault_kind` 输出，区分 page fault (cause 12/13/15) 与 access fault (cause 1/5/7)
> - PTW wait 状态将 `ptw_bus_error` 作为终止态，error-only 响应不再等超时
> - MMU `selected_d_walk` / `selected_i_walk` 简化 walk-start 选择逻辑（修复 MEDIUM-3）
> - MMU TLB lookup 请求收窄为 `i_req_active` / `d_req_active`（仅活跃 captured 请求）
>
> **HIGH-2 修复**（`ptw.sv:269-284`）：S_L1_CHECK 中 non-leaf PTE 分支 pre-issue L0 read，跳过 S_L0_READ 直接进 S_L0_CHECK。`bus_req_pending_r` 保持高电平，消除 1 周期空隙。
>
> **FPGA 效果**（BUG-16 修复后）：Linux 突破 C0000098 卡点，推进到 C0377xxx（kernel 虚拟空间 ~55MB），satp=0x800808FD。后续出现 load page fault at VA 0x00FEFFEC（demand paging），待 HIGH-2 + 紧急补丁上 FPGA 后进一步验证。

### 10.2 当前 FPGA 输出解读

| 信号 | 值 | 含义 |
|------|------|------|
| IF PC | `C0000098` | 取指 PC 不变（STVEC trap handler） |
| STATE | `00000001` | FETCH（等 if_done） |
| IFDON | `00000000` | if_done=0——指令未返回 |
| I RDY | `00000000` | mmu_inst_ready=0 |
| I MIS | `00000000` | mmu_inst_miss=0 |
| I PF | `00000000` | 无 page fault 脉冲 |
| IC ST | `00000001` | **icache 在 S_TAG_READ**（对比之前 S_IDLE，进步了） |
| IC RF | `00000000` | 不在 refill |
| PTHAC | `00000000` | PTW 无活动（即 walk 未进行或已结束） |
| PIWLK | `00000000` | pending_i_walk=0 |

**关键观察**：`I_RDY=0, I_MIS=0` 是不正常组合。如果 i_state 在 I_LOOKUP 并且 miss →`I_MIS` 应该=1 并且 i_state 去 I_WALK_PENDING。如果 i_state 在 I_WALK_PENDING 或 I_FILL_WAIT → `I_MIS=0, I_RDY=0`。`I_PF=0` 说明 page fault 也没有活跃。

→ **MMU 的 i_state 卡在 I_WALK_PENDING 或 I_FILL_WAIT**。PTW 已经走完或超时，`I_PF=0` 说明 PTW fault 信号没有被传递到 page fault 寄存器（`i_pf_r` 已经被 core_top latch 过了？还是在等新的 clock？）

实际上：`i_page_fault = i_pf_r`。i_pf_r 在 `i_state == I_LOOKUP && i_tlb_pf && !i_input_changed` 时以及 `ptw_fault_for_i` 时被置位 1 周期。在外面的 core_top 中，这个信号会被 `trap_manager` 捕获并锁存用于 trap 流程。如果 trap 流程还在进行中（controller 在 trap_enter 状态），`i_pf_r` 的下一周期脉冲可能被忽略。

### 10.3 PTW 结构隐患 — 按严重程度排序

#### ✅ HIGH-1：PTW fault 后 TLB 不填充 → 无限循环

**状态：已修复**。S_AD_UPDATE 路径已恢复。

**原机制**：
```
VA C0000098 → TLB miss → PTW walk (L1+L0) → 页表中 PTE.A=0
                                       ↓
新代码: !pte_a → S_FAULT（而不是原来的 S_AD_UPDATE）
                                       ↓
                              tlb_fill_req = ptw_walk_done && ...
                              ptw_walk_fault = 1 → tlb_fill_req = 0
                                       ↓
                              i_state: I_WALK_PENDING → I_IDLE (ptw_fault_for_i)
                                       ↓
                              I_IDLE → I_LOOKUP → TLB miss (未填充!)
                                       ↓
                              i_walk_req → PTW walk (PTE.A 还是 0!)
                                       ↓
                              S_FAULT → 回到起点
```

**修复**：`ptw.sv:313-326` S_PERM_CHECK 中 `!pte_a` → S_AD_UPDATE（写回 PTE|0x40）→ S_AD_WAIT → S_DONE（填充 TLB）。第二次 lookup 时 TLB 已填充，A=1。

#### ✅ HIGH-2：PTW bus 请求在 2 次连续读取间有漏洞周期

**状态：已修复**。S_L1_CHECK 中 pre-issue L0 read，跳过 S_L0_READ。

**原机制**：
```
S_L1_READ:  bus_req_r <= 1 (1周期脉冲), bus_req_pending_r <= 1
S_L1_CHECK: 等待 bus_resp_ok → 收到响应 → bus_req_pending_r 清 0 (顶层无条件清)
            → 判断非叶子 → 进入 S_L0_READ

S_L0_READ:  bus_req_r <= 1, bus_req_pending_r <= 1（重新置位）

问题：bus_req_pending_r 在 S_L1_CHECK 中清 0 后，
     到 S_L0_READ 的 posedge 之间，bus_req_pending_r=0 维持 1 周期。
     bus bridge 的 src_arbiter 在这 1 周期已离开 S_PTW 状态。
     下次重新仲裁 PTW 时，优先级最低，被 dcache/icache 抢占。
```

**修复**（`ptw.sv:269-284`）：S_L1_CHECK non-leaf 分支中直接预发 L0 读请求：
```systemverilog
bus_addr_r        <= next_l0_addr;    // 用 ptw_bus_rdata 计算 L0 地址
bus_req_pending_r <= 1'b1;            // 覆盖顶层清除（last NBA wins）
state             <= S_L0_CHECK;      // 跳过 S_L0_READ
```
`next_l0_addr = {bus_pte_ppn[19:0], 12'b0} + {20'b0, vpn0, 2'b0}`，其中 `bus_pte_ppn = {ptw_bus_rdata[31:20], ptw_bus_rdata[19:10]}`。bus bridge 在下一周期 S_IDLE 看到 `ptw_req=1`，立即接受 L0 读请求，无空隙。

#### ✅ MEDIUM-3：`active_d_walk` 在 W_IDLE 时选错地址

**状态：已修复**（紧急补丁）。`selected_d_walk` 逻辑包含 `pending_d_walk`。

**原问题**：`active_d_walk = (walk_state == W_D_WALK) || start_d_walk`，其中 `start_d_walk = (W_IDLE) && !pending_i && !pending_d && d_walk_req`。当 `pending_d_walk=1, walk_state=W_IDLE` 时 `start_d_walk=0`（因为 `!pending_d=0`），`active_d_walk=0`，PTW latch 了 `i_latched_vaddr` 做 d-walk → TLB 填充错误条目。

**修复**（`MMU.sv:559-636`）：
```systemverilog
wire selected_d_walk = pending_d_walk || (!pending_i_walk && d_walk_req);
wire selected_i_walk = pending_i_walk || (!selected_d_walk && i_walk_req);
wire start_d_walk = (walk_state == W_IDLE) && selected_d_walk;
wire active_d_walk = (walk_state == W_D_WALK) || start_d_walk;
```
当 `pending_d_walk=1, pending_i_walk=0` → `selected_d_walk=1` → `start_d_walk=1` → `active_d_walk=1` → `walk_vaddr = d_latched_vaddr` ✅

#### 🟢 LOW-4：sfence_vma 多周期脉冲的 MMU 死锁

**严重性：低**。取决于 core_top 的具体实现。如果 sfence_vma 是严格的单周期脉冲则无害。

#### 🟢 LOW-5：`perm_fault` 组合路径太长

**严重性：低**。纯组合逻辑，根据 priv_mode|access_type|pte_u|mstatus_sum/mxr 等信号计算 `perm_fault`。这些信号来自 latched register 的 output（`pte_r`, `vaddr_r` 等）。在 FPGA 上可能影响时序 closure 但不会导致功能错误。

### 10.4 结构隐患总结

| 优先级 | 隐患 | 文件 | 状态 | 修复方式 |
|--------|------|------|------|----------|
| ✅ HIGH-1 | PTW fault 后 TLB 不填充 → 无限循环 | `ptw.sv:313-326` | **已修复** | 恢复 S_AD_UPDATE 路径，A=0 时写回 PTE\|0x40 再填 TLB |
| ✅ HIGH-2 | PTW bus_req_pending 在两读间下降 → bus bridge 抢占 | `ptw.sv:269-284` | **已修复** | S_L1_CHECK pre-issue L0 read，跳过 S_L0_READ |
| ✅ MEDIUM-3 | active_d_walk 在 W_IDLE+pending_d 时选错地址 | `MMU.sv:559-636` | **已修复** | selected_d_walk 包含 pending_d_walk |
| 🟢 LOW-4 | sfence_vma 多周期脉冲死锁 | `MMU.sv:400-403` | 未修复 | 功能正确，依赖 core_top 脉冲行为 |
| 🟢 LOW-5 | perm_fault 组合路径长 | `ptw.sv:141-161` | 未修复 | 时序问题，不导致功能错误 |

### 10.5 仿真验证结果（2026-06-20）

**MMU 测试：12/12 PASS**

| 测试 | 结果 | 耗时 |
|------|------|------|
| mmu_sv32_basic | ✅ PASS | 39.6s |
| mmu_tlb_basic | ✅ PASS | 37.6s |
| mmu_tlb_replace | ✅ PASS | 35.1s |
| mmu_tlb_flush | ✅ PASS | 36.6s |
| mmu_tlb_asid | ✅ PASS | 36.4s |
| mmu_tlb_megapage | ✅ PASS | 39.3s |
| mmu_tlb_stress | ✅ PASS | 30.4s |
| mmu_ptw_walk | ✅ PASS | 41.8s |
| mmu_page_fault | ✅ PASS | 38.0s |
| mmu_permission | ✅ PASS | 40.0s |
| mmu_sv32_edge | ✅ PASS | 40.8s |
| mmu_unified_mmu | ✅ PASS | 62.4s |

**回归测试：8/10 PASS（排除 DDR3 + mmio_ready）**

| 测试 | 结果 | 备注 |
|------|------|------|
| reg_bare_no_miss | ✅ PASS | |
| reg_linux_field_values | ✅ PASS | |
| reg_linux_ptr_reload | ✅ PASS | |
| reg_pf_latch | ✅ PASS | |
| reg_ptw_fault_latch | ✅ PASS | |
| reg_sfence_during_walk | ✅ PASS | |
| reg_stale_paddr | ✅ PASS | |
| reg_tlb_fill_way | ✅ PASS | |
| reg_bug16_tlb_valid_pulse | ❌ FAIL | 测试程序 bug（trap 嵌套处理不完善），非 CPU bug |
| reg_linux_ptr_reload_ddr3 | ⏸️ 跳过 | DDR3 仿真太慢 |
| reg_mmio_ready | ❓ 无输出 | 仿真完成但无结果（pre-existing） |

**结论**：HIGH-2 修复未引入任何新失败。所有之前通过的测试仍然通过。

---

## 11. UART THRE Bug — Kernel 启动输出丢失

### 11.1 问题现象

FPGA 上 Linux 启动时，console handover 后大量 kernel 输出丢失。只有 handover 前 earlycon 的 ~4 行和 handover 后紧接的 ~200 字符能看到，之后全部丢失。

### 11.2 根因分析

**文件**：`dev/rtl/APB/perips/uart16550/uart_regs_16550a.sv:347`

```systemverilog
// 修复前：
assign thre_set_en = 1'b1;   // 恒为 1
assign lsr5 = (tf_count == 5'b0) && thre_set_en;   // THRE (LSR bit 5)
```

THRE 只反映 TX FIFO 是否为空，不反映移位寄存器是否正在发送。transmitter 在 `S_POP_BYTE` 状态 1 拍就将数据从 FIFO 弹入移位寄存器，FIFO 立刻空 → THRE 2 拍后重新置位，但字符才刚开始串行发送（还要 ~176 周期）。

**Kernel 两条输出路径**：

| 路径 | 等待条件 | 行为 |
|------|----------|------|
| earlycon (`8250_early.c`) | THRE && TEMT | TEMT 检查 `tstate==S_IDLE`，能正确门控 |
| real 8250 driver (`8250_port.c:3227`) | **仅等 THRE** | THRE 立刻置位 → 全速写 THR → FIFO 溢出 |

console handover 后 earlycon 被禁用，只剩 real driver。THRE 立刻置位 → 等待立即返回 → kernel 全速写 THR → 16 字节 TX FIFO 溢出 → 后续输出全部丢失。

只有 handover 那 4 行能看到，是因为 8250 driver probe 的 ~24ms 间隙让 FIFO 排空，紧接着的 ~200 字符刚好塞进 FIFO。之后 kernel 全速打印，FIFO 溢出，全丢。

### 11.3 修复

```systemverilog
// 修复后（uart_regs_16550a.sv:347）：
assign thre_set_en = (tstate == 3'd0);   // S_IDLE: THRE only when shift register idle
```

`thre_set_en` 的语义是「THRE 可以置位」。只有当移位寄存器也空闲（`tstate == S_IDLE`）时，THRE 才应该置位——否则前一个字符还在发送，THR 不能接受新数据。

修复后 `lsr5 = (tf_count == 0) && (tstate == S_IDLE)`：FIFO 空 **且** 移位寄存器空闲。

### 11.4 修复后时序

| 周期 | tstate | tf_count | lsr5 (THRE) | 说明 |
|------|--------|----------|-------------|------|
| 0 | S_IDLE | 1 | 0 | FIFO 有数据 |
| 1 | S_POP_BYTE | 0 | **0** | tstate≠S_IDLE → THRE 不置位 |
| 2~175 | S_SEND_* | 0 | **0** | 发送中 → THRE 保持低 |
| ~176 | S_IDLE | 0 | **1** | 发送完毕 → THRE 置位 |

real driver 等 THRE 时会被迫等到字符真正发完，earlycon 等 THRE+TEMT 同样被正确门控。两条路径都能被节流到波特率速度，输出不再丢失。

### 11.5 副作用分析

- **TEMT (lsr6) 不变**：`lsr6 = (tf_count==0) && thre_set_en && (tstate==0)`，修复前后都等价于 `(tf_count==0) && (tstate==0)`。
- **THRE 中断**：变保守——仅在 FIFO 空 **且** 移位寄存器空闲时触发。对 kernel 启动场景正确。
- **FIFO 利用率**：退化为 1 深度（写 1 字节 → 等发完 → 写下一个）。平均吞吐率不变（瓶颈是波特率），只是总线事务增多。对 kernel boot 输出无影响。

---

## 12. DCache / Bus Bridge 错误处理与公平性验证

### 12.1 Issue 1: refill/write-back 错误完成路径 — ✅ 已修复

**原问题**：bridge 仅在成功时置 `dcache_refill_valid_r`/`dcache_wb_valid_r`，error 时仅 pulse `dcache_error_r` 后回 S_IDLE。dcache FSM 无 error 输入，在 S_REFILL 死等 `refill_valid`，在 S_WB_SEND 死等 `wb_valid`。

**修复状态**：

**Bridge 侧** (`cpu_bus_bridge.sv`) — error 时也置 `done`：

S_DREFILL_R (line 656-662):
```systemverilog
if (r_error) begin
    dcache_refill_done_r  <= 1'b1;   // ← done 置位
    dcache_refill_error_r <= 1'b1;
end
```

S_WB_B (line 753-759):
```systemverilog
if (b_error) begin
    dcache_wb_done_r  <= 1'b1;       // ← done 置位
    dcache_wb_error_r <= 1'b1;
end
```

**Dcache 侧** (`dcache_ctrl.sv`) — 检查 error flag 后回 S_IDLE：

S_WB_SEND (line 633-634):
```systemverilog
if (wb_error) begin
    state <= S_IDLE;                 // ← error 退出
end
```

S_REFILL (line 652-653):
```systemverilog
if (refill_error) begin
    state <= S_IDLE;                 // ← error 退出
end
```

### 12.2 Issue 2: flush 路径 error 完成 — ✅ 已修复

**原问题**：S_FLUSH_WB_SD 仅在 `wb_valid` 成功时推进，无 error 完成路径。若 flush 中某 dirty line write-back 失败，维护序列 hang，阻塞指令退休。

**修复状态**：

S_FLUSH_WB_SD (line 720-751) — error 时记录并继续推进：
```systemverilog
if (wb_done) begin
    wb_req_r <= 1'b0;
    if (wb_error) begin
        flush_error_seen_r <= 1'b1;     // 记录错误
    end else begin
        // 清 dirty bit
    end
    // ← "Advance to next way/set" 在 if/else 之外，error 也执行
    if (latched_victim_way == NUM_WAYS - 1) begin
        if (latched_set == NUM_SETS - 1) begin
            state <= S_FLUSH_INVALIDATE;  // → 最终 flush_done_r
        end else begin
            state <= S_FLUSH_SCAN;        // → 继续下一个 set
        end
    end else begin
        state <= S_FLUSH_SCAN;            // → 继续下一个 way
    end
end
```

关键结构："Advance to next way/set" 在 `if (wb_error)` / `else` 之外（line 734），无论 error 与否都推进。flush 遇到 error 不会 hang，最终到达 `S_FLUSH_INVALIDATE` → `flush_done_r <= 1`。

### 12.3 Issue 3: write-back 公平性 — ✅ 已修复

**原问题**：dcache_wb 优先级最低（icache_mmio > dcache_mmio > ptw > dcache_wb > icache_refill > dcache_refill），无公平机制。dcache_ctrl 进入 S_WB_SEND 后无法前进直到 `wb_valid` 到达。持续 PTW/MMIO 压力下 dirty eviction 无限饥饿。

**修复状态**：

`cpu_bus_bridge.sv:346-362` — starvation counter + boost 机制：
```systemverilog
if (state == S_IDLE) begin
    if (dcache_wb_req) begin
        if ((icache_mmio_req || dcache_mmio_req || ptw_req) && !wb_boost_r) begin
            if (wb_starve_cnt_r == 3'd3) begin
                wb_boost_r      <= 1'b1;     // 3 周期后提升优先级
                wb_starve_cnt_r <= 3'd0;
            end else begin
                wb_starve_cnt_r <= wb_starve_cnt_r + 3'd1;
            end
        end else if (!(icache_mmio_req || dcache_mmio_req || ptw_req)) begin
            wb_starve_cnt_r <= 3'd0;         // 无竞争时重置
        end
    end
end
```

仲裁 (line 374) — `wb_boost_r` 时 dcache_wb 跳到最高优先级：
```systemverilog
if (dcache_wb_req && wb_boost_r && !dcache_wb_valid_r) begin
    state <= S_WB_AW;     // boost 时优先服务 write-back
    wb_boost_r      <= 1'b0;
    wb_starve_cnt_r <= 3'd0;
end
else if (icache_mmio_req && ...) begin   // 正常优先级链
```

dcache_wb 最多被饿死 3 周期，之后 `wb_boost_r` 强制提升到最高优先级。不会无限饥饿。

### 12.4 验证总结

| Issue | 描述 | 状态 | 修复方式 |
|-------|------|------|----------|
| 1 | refill/wb 无 error 完成路径 → 死等 | ✅ 已修复 | bridge error 时也置 `done=1`；dcache 检查 `error` flag 后回 S_IDLE |
| 2 | flush 路径无 error 完成 → hang | ✅ 已修复 | S_FLUSH_WB_SD error 时记录 `flush_error_seen_r` 并继续推进，最终到达 `flush_done` |
| 3 | write-back 无公平性 → 饥饿 | ✅ 已修复 | `wb_starve_cnt_r` 3 周期计数 → `wb_boost_r` 提升到最高优先级 |

---

## 13. AXI Error Injection 回归测试修复

### 13.1 问题

`reg_dcache_wb_error` 和 `reg_dcache_refill_error` 两个回归测试 FAIL。

### 13.2 根因分析

**reg_dcache_refill_error — CPU 卡死**：

1. Store 到 0x80004000 → dcache miss → refill → RRESP error → trap
2. `cpu_mem.sv` 的 `mem_en_reg` 在 trap_enter 时未清除 → dcache 看到 stale `cpu_req_valid=1` → 进入 S_REFILL 重试
3. `cpu_bus_bridge.sv` 在第一个 error beat 就回 S_IDLE → `rready=0` → RAM 卡在 R_BURST（burst 未消费完）
4. Dcache 卡在 S_REFILL（arready=0）→ 无法响应 `flush_req` → `fence.i` 永久卡死

**reg_dcache_wb_error — 无 trap**：

- LINE_A (0x80003000) 和 LINE_B (0x80013000) 映射到同一 set 0
- 4-way cache → 2 次访问不触发 eviction → 无 write-back → 无 error → 无 trap
- 测试程序未填满 4 个 way

### 13.3 修复

**RTL 修复 1：`cpu_mem.sv` — trap_enter 清除 mem_en_reg**

```systemverilog
if (trap_enter) begin
    lr_reservation_valid <= 1'b0;
    mem_en_reg           <= 1'b0;    // ← 新增
    mem_state            <= MEM_IDLE; // ← 新增
end
```

trap 时清除 `mem_en_reg` 并重置 `mem_state`，防止 dcache 看到过期请求重试。

**RTL 修复 2：`cpu_bus_bridge.sv` — error 时消费完整 burst**

S_DREFILL_R / S_IREFILL_R 中，error 响应不再立即回 S_IDLE，而是等 `rlast` 消费完所有 beat：

```systemverilog
if (r_error) begin
    if (rlast) begin          // ← 等到最后一个 beat
        state            <= S_IDLE;
        dcache_error_r   <= 1'b1;
        ...
    end
    // else: 继续消费 error beat，rready=1
end
```

防止 RAM 卡在 R_BURST（arready=0 阻塞后续 AXI 读）。

**测试程序修复 1：`reg_dcache_refill_error.s`**

移除 store + fence.i（store 的 refill 会消耗 RRESP 注入），改为直接读两次。TB 预加载数据到 BRAM。

**TB 修复 1：`tb_regression_reg_dcache_refill_error.sv`**

预加载数据到 BRAM，使用正确的索引 `(addr & 0xFFFFF) >> 2`（BRAM 按 addr[19:2] 索引）。

**测试程序修复 2：`reg_dcache_wb_error.s`**

填满 set 0 的 4 个 way（LINE_A/B/C/D），第 5 次访问（LINE_E）触发 PLRU 驱逐。TB 在 LINE_A 注入 BRESP error。

### 13.4 验证结果

| 测试 | 结果 | 关键信号 |
|------|------|----------|
| reg_dcache_wb_error | ✅ PASS | mcause=7, mtval=0x80003000 |
| reg_dcache_refill_error | ✅ PASS | mcause=5, mtval=0x80004000, data=0xA5A55A5A |
| reg_fencei_wb_error | ✅ PASS | |
| reg_sfence_wb_error | ✅ PASS | |
| reg_bare_no_miss | ✅ PASS | 无回归 |
| reg_pf_latch | ✅ PASS | 无回归 |
| reg_ptw_fault_latch | ✅ PASS | 无回归 |
| reg_stale_paddr | ✅ PASS | 无回归 |

**结论**：RTL 修复未引入任何回归。4 个 error injection 测试全部 PASS。

---

## 14. 全回归测试通过（2026-06-21）

### 14.1 修复的两个失败测试

**reg_bug16_tlb_valid_pulse — M-mode store 触发嵌套 trap**

- **根因**：s_trap_handler 执行 ecall → M-mode handler 写结果区 `sw x29, 0(x5)` 到 0x80000000（`lui x5, 0x8000` = 0x80000000，非注释所写 0x80007000）→ M-mode data store 触发嵌套 trap → handler 走 unexpected trap 路径 → FAIL
- **修复**：移除 M-mode handler 中不必要的内存写入。testbench 直接读 x28/x29/x30 寄存器，无需结果区。

**reg_mmio_ready — SIM_CYCLES 超过仿真运行时间**

- **根因**：testbench `SIM_CYCLES=15000000`（15M 周期 × 250ns = 3.75s），但仿真运行时间仅 60ms。CPU 在 ~188K 周期（47ms）完成全部 4 个子测试并进入 end_loop，但 testbench 的 `repeat(SIM_CYCLES) @(posedge clk)` 在 60ms 内无法完成 → 无输出。
- **修复**：`SIM_CYCLES` 从 15000000 改为 200000（200K × 250ns = 50ms < 60ms）。

### 14.2 全测试结果

| 类别 | 测试数 | PASS | FAIL |
|------|--------|------|------|
| MMU | 12 | 12 | 0 |
| Regression | 14 | 14 | 0 |
| **合计** | **26** | **26** | **0** |

### 14.3 各现象与对应测试

| 现象 | 对应测试 | 结果 |
|------|----------|------|
| BUG-16: TLB valid pulse 过期 → MMU 死锁 | reg_bug16_tlb_valid_pulse | ✅ PASS |
| HIGH-1: PTW fault 后 TLB 不填充 → 无限循环 | mmu_ptw_walk, mmu_page_fault | ✅ PASS |
| HIGH-2: PTW bus 请求间 1 周期空隙 | mmu_ptw_walk | ✅ PASS |
| MEDIUM-3: active_d_walk 选择错误地址 | mmu_unified_mmu | ✅ PASS |
| UART THRE: 移位寄存器状态未反映 | （FPGA 验证） | 待验证 |
| DCache error 完成路径 | reg_dcache_refill_error, reg_dcache_wb_error | ✅ PASS |
| Flush error 完成路径 | reg_fencei_wb_error, reg_sfence_wb_error | ✅ PASS |
| Write-back 公平性 | reg_dcache_wb_error | ✅ PASS |
| cpu_mem trap_enter 清除 mem_en_reg | reg_dcache_refill_error | ✅ PASS |
| cpu_bus_bridge error beat 消费 | reg_dcache_refill_error | ✅ PASS |
| MMIO mmu_ready gating (Bug 10) | reg_mmio_ready | ✅ PASS |
| SFENCE.VMA during PTW walk | reg_sfence_during_walk | ✅ PASS |
| TLB fill way replacement | reg_tlb_fill_way | ✅ PASS |
| Linux pointer reload | reg_linux_ptr_reload | ✅ PASS |
| Linux field values | reg_linux_field_values | ✅ PASS |

**结论**：所有可仿真验证的现象均已确认修复。剩余 UART THRE 和 FPGA Linux 启动需上板验证。

---

## 15. Write-back reissue holdoff + RAM error model 修复（2026-06-21）

### 15.1 问题

`reg_dcache_wb_error` / `reg_fencei_wb_error` / `reg_sfence_wb_error` 在初步修复后仍存在隐患：

- **根因**：maintenance write-back 在 BRESP error 时被正确 drop，但 `cpu_bus_bridge` 的 `dcache_wb_req` 是**电平敏感**信号。bridge 在 dcache 撤回 `dcache_wb_req` 之前的窗口期可以再次接受同一请求，导致 **stale line 被二次成功写回**——错误数据写入了 backing memory。
- **后果**：第二次写回成功后，RAM 中保存的是 stale 数据而非正确值。后续 reload 读到的是被污染的数据，测试虽 PASS 但实际未验证到真正的 error 路径。

### 15.2 修复

**`cpu_bus_bridge.sv` — write-back reissue holdoff**

在 bridge 接受 dcache write-back 请求后，加入 holdoff 窗口，阻止在同一 `dcache_wb_req` 电平期间重复接受请求。确保 dcache 必须先撤回 `dcache_wb_req`（拉低），bridge 才能接受下一次 write-back。

**`dcache_ctrl.sv` — maintenance fault 路径终止**

D-cache maintenance fault 路径在 invalidate stale victim 后正确终止，不再尝试重发 write-back。stale line 被丢弃而非重写。

**`axi_wrap_ram.sv` — BRESP fault 抑制 backing-memory commit**

SIM RAM write-error model 修改：注入的 BRESP fault 不仅返回 AXI 错误响应，还**抑制 backing-memory 的写入提交**。确保注入错误不污染 RAM 数据，后续 reload 读到的是原始正确值。

### 15.3 测试程序保持

- **`reg_bug16_tlb_valid_pulse.s`**：M-mode handler 不再 self-mask（移除了触发嵌套 trap 的 M-mode store 到 0x80000000）
- **`reg_dcache_wb_error.s` / `reg_dcache_refill_error.s`**：preload backing RAM，直接暴露 reload 值，验证 error 后 reload 读到的是原始数据而非 stale 写回值

### 15.4 验证结果

| 测试 | 结果 | 说明 |
|------|------|------|
| reg_bug16_tlb_valid_pulse | ✅ PASS | M-mode store 不再触发嵌套 trap |
| reg_fencei_wb_error | ✅ PASS | fence.i flush + WB error 正确终止 |
| reg_sfence_wb_error | ✅ PASS | sfence.vma flush + WB error 正确终止 |
| reg_dcache_wb_error | ✅ PASS | WB error 后 reload 读到原始数据 |
| reg_dcache_refill_error | ✅ PASS | refill error 后 reload 读到原始数据 |

**全回归**：26/26 PASS（12 MMU + 14 回归），未引入任何回归。

### 15.5 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/cpu_bus_bridge.sv` | WB reissue holdoff：接受 `dcache_wb_req` 后阻止重复接受直到信号撤回 |
| `dev/rtl/core/dcache_ctrl.sv` | Maintenance fault 路径在 invalidate stale victim 后终止 |
| `dev/rtl/ram_wrap/axi_wrap_ram.sv` | BRESP fault 抑制 backing-memory commit |
| `dev/program_source/test/regression/reg_bug16_tlb_valid_pulse.s` | 移除 M-mode store（不再 self-mask 嵌套 trap） |
| `dev/program_source/test/regression/reg_dcache_wb_error.s` | Preload backing RAM，暴露 reload 值 |
| `dev/program_source/test/regression/reg_dcache_refill_error.s` | Preload backing RAM，暴露 reload 值 |

---

## 16. 删除 TLB 非 BRAM 死代码路径（2026-06-21）

### 16.1 背景

`USE_TLB_BRAM` 宏控制 TLB 实现路径：
- **BRAM 路径**（`ifdef USE_TLB_BRAM`）：4-way × 4-set 组相联 BRAM TLB，双端口，1 周期读延迟
- **非 BRAM 路径**（`else`）：全相联寄存器阵列 TLB，组合查找，独立 FSM + 独立 PTW 实例

### 16.2 评估结论

| 检查项 | 结果 |
|--------|------|
| `USE_TLB_BRAM` 定义 | `cache_def.svh:114` 无条件 `` `define USE_TLB_BRAM 1 `` |
| `cache_header_gen.py` | 第 302 行硬编码输出，无配置开关可关闭 |
| `undef`/`ifndef USE_TLB_BRAM` | 全项目无匹配 |
| 非 BRAM 路径编译可行性 | **已损坏**：`MMU.sv:1098` 引用 `walk_state`，该寄存器仅在 BRAM 路径声明（第 109 行），非 BRAM 路径无法独立编译 |
| `core_top.sv` debug 端口 | 两路径都赋值同一组 debug 输出，删除非 BRAM 不破坏连接 |
| testbench 引用 | 无 — `dev/tb/` 下无任何 `nb_i_*`/`nb_d_*` 引用 |

**结论**：非 BRAM 路径是死代码，且已损坏（无法编译），安全删除。

### 16.3 删除内容

| 文件 | 删除范围 | 删除行数 | 内容 |
|------|----------|----------|------|
| `dev/rtl/core/tlb.sv` | 原 482-650 行（`else` 分支） | 168 行 | 全相联寄存器阵列 TLB：`entries[]` 数组、`rr_ptr` 轮转指针、i/d 侧 hit vector、组合查找逻辑、`pack_entry` 函数、fill/flush 逻辑 |
| `dev/rtl/core/MMU.sv` | 原 696-1099 行（`else` 分支） | 403 行 | 组合 TLB + latched input FSM（`nb_i_state`/`nb_d_state`）、独立 TLB 实例、独立 PTW 实例、walk 仲裁、page fault 逻辑 |
| **合计** | | **571 行** | |

### 16.4 验证

代表性回归 6/6 PASS（含 `mmu_unified_mmu`、`mmu_tlb_basic`、`mmu_tlb_replace`、`reg_bug16_tlb_valid_pulse`、`reg_dcache_wb_error`、`reg_bare_no_miss`），编译通过，功能无回归。

### 16.5 修改后文件结构

- `tlb.sv`：652 → 484 行，仅保留 BRAM 路径
- `MMU.sv`：1101 → 698 行，仅保留 BRAM 路径
- `ifdef USE_TLB_BRAM` / `endif` 保留（宏仍定义，BRAM 路径正常编译），`else` 分支已删除

---

## 17. 总线与时钟域子系统隐患审计（2026-06-21）

### 17.1 架构概览

```
CPU Pipeline (cpu_clk)
  ├─ icache/dcache/PTW → cpu_bus_bridge (单AXI4 master, 固定优先级FSM)
  │                         │
  │                    Axi_CDC (SpinalHDL Gray-code FIFO)
  │                         │
  ▼                    sys_clk domain
  AXI 地址解码器 → 7个从设备
    ├─ DDR3/RAM  (0x8000_0000, full AXI4)
    ├─ BootROM   (0xFC00_0000, AXI4-Lite)
    ├─ PLIC      (0x0C00_0000, AXI4-Lite)
    ├─ CLINT     (0x0200_0000, AXI4-Lite)
    ├─ APB Bridge(0x1000_0000, AXI4-Lite→APB→4外设)
    ├─ SysStatus (0x0400_0000, AXI4-Lite)
    └─ Default    (DECERR)
```

**时钟域**：

| 域 | 信号 | 频率 | 使用者 |
|----|------|------|--------|
| cpu_clk | cpu_clk | 50MHz(FPGA)/~91MHz(sim) | CPU core, bus bridge, trap latch, IRQ sync |
| sys_clk | sys_clk | 100MHz | AXI 互连, PLIC, CLINT, BootROM, APB, 所有外设, LCD |
| ddr_clk_ref | ddr_clk_ref | 200MHz | DDR3 MIG 参考时钟 |

**总线优先级**（`cpu_bus_bridge.sv`）：
```
1. dcache_wb (wb_boost_r 时)   ← 饿死3周期后提升
2. icache_mmio  (最高正常优先级)
3. dcache_mmio
4. ptw
5. dcache_wb (正常)
6. icache_refill
7. dcache_refill (最低)
```

### 17.2 CRITICAL — 必须修复

| # | 文件:行 | 隐患 | 说明 |
|---|---------|------|------|
| **C1** | `system_top.sv:374-375` | **64位 `clint_mtime` 多位 CDC** | `clint_mtime[63:0]` 从 `sys_clk` 通过2级移位寄存器同步到 `cpu_clk`。64位信号每位可能在不同时钟沿被采样，导致 CPU `rdtime` 读到撕裂值（如 `0x0000_FFFF` → `0x0001_0000` 可能被读为 `0x0001_FFFF`）。`r_mtime` 每 `sys_clk` 周期自增1，多位同时翻转概率高。 |

**修复方案**：同步 `mtime_tick` 脉冲在 `cpu_clk` 域重建计数器，或用 req/ack 握手，或用异步 FIFO。

### 17.3 HIGH — 应当修复

| # | 文件:行 | 隐患 | 说明 |
|---|---------|------|------|
| **H1** | `gpio.sv:78-88,61-67` | **GPIO 输入缺同步器** | `io_gpioPin[i]` 异步 FPGA 引脚直接采样到单级 `gpio_pin_prev[i]`，`gpio_pin_changed[i]` 组合逻辑使用可能亚稳态的值驱动 IRQ。 |
| **H2** | `uart_rx.sv:38-50` | **简单 UART RX 缺同步器** | `i_rxPin_1` 直接采入 `rx_d0`，`rx_negedge = rx_d1 && ~rx_d0` 使用仅1级同步的信号做组合边沿检测。 |
| **H3** | `apb_perips` 全体外设 | **PREADY 恒为1，无背压** | Timer/GPIO/SPI/UART 均 `PREADY=1'b1`。SPI 忙或 UART FIFO 满时写入静默成功丢数据，无 stall 机制。 |
| **H4** | `axi4lite_to_apb.sv:79-84` | **AW 等待 W 无超时** | AW 被 latch 后若 W 永不到达（CPU 异常或 CDC 丢拍），桥接器永久卡死在 `aw_latched=1`，无超时返回 IDLE。 |

### 17.4 MEDIUM — 建议修复

| # | 文件:行 | 隐患 | 说明 |
|---|---------|------|------|
| **M1** | `cpu_bus_bridge.sv:371` | **icache/dcache refill 无防饿死** | 仅 writeback 有 `wb_starve_cnt_r` 公平性。icache_refill 和 dcache_refill 为最低优先级，连续 MMIO/PTW 流量可无限阻塞 refill。 |
| **M2** | `axi4lite_plic.sv:266-274` | **PLIC 电平触发重挂起** | ISR 完成 claim/complete 后若外设 IRQ 线仍高，gateway 重开 → 中断立即重新挂起 → 伪二次中断。 |
| **M3** | 全体 APB 外设 | **PSLVERR 恒为0** | 访问外设窗口内未定义的寄存器偏移返回零数据+OKAY，软件无法感知错误。 |
| **M4** | `axi4lite_to_apb.sv:93` | **读可绕过半锁存写** | AW 已 latch 但 W 未到时，`arready` 仍可拉高（`!aw_latched` 为 false 但 `!w_latched` 也为 false 时才阻塞）。实际逻辑：`arready = IDLE && !aw_latched && !w_latched` — AW 先到时读被阻塞，但若 AW 和 AR 同周期到达且 W 未到，AR 被接受而 AW 被丢。需验证此边界。 |
| **M5** | `uart_regs_16550a.sv:528-538` | **UART 中断组合逻辑毛刺** | `int_o` 是 `lsr_mask`/`fifo_read` 等信号的组合输出，CPU 读 LSR 清中断与新错误同周期到达时可能毛刺或丢失。 |
| **M6** | `spi.sv:157-167` | **SPI done 脉冲与 IRQ 清除竞争** | `done` 为1周期脉冲，若 CPU 同周期读 STATUS 清 IRQ，clear 可能赢过 set，丢失中断。 |

### 17.5 LOW / 已正确处理 ✅

| 项 | 说明 |
|----|------|
| AXI CDC (cpu_clk↔sys_clk) | `Axi_CDC` 使用 SpinalHDL `StreamFifoCC`，Gray-code 指针同步 + 双口 RAM 存载荷，多位安全 ✅ |
| 单位 IRQ 同步 | `plic_eip`/`clint_mtip`/`clint_msip` 均2级同步器，单位信号安全 ✅ |
| 复位链 | `reset_sync` 每时钟域独立例示，async assert / sync deassert ✅ |
| UART 16550A RX 同步 | `uart_sync_flops` 2级同步器 ✅ |
| APB 译码器 | `PADDR[15:14]` 覆盖全部4种组合，无间隙 ✅ |
| 地址译码器 slave_sel 锁存 | `cpu_bus_bridge` 单在途（single-in-flight），`aw_slave_sel`/`ar_slave_sel` 不会被超前覆盖 ✅ |
| AXI 协议 | `rready`/`bready` 仅在期望响应的状态拉高，AW+W 独立握手跟踪 ✅ |
| Default slave | 正确返回 DECERR，AW/W/B 和 AR/R 均完整处理 ✅ |
| 波特率生成 | 单时钟域（PCLK）计数分频，无 CDC ✅ |

### 17.6 修复优先级建议

1. **C1 (mtime CDC)** — 对 Linux 启动影响最大，`rdtime` 是调度器核心 CSR。撕裂值可导致调度器误判时间跳变。
2. **H1/H2 (GPIO/UART 同步器)** — FPGA 上真实异步引脚，亚稳态概率随频率升高。仿真中不触发因为 testbench 驱动同步信号。
3. **H3 (PREADY=1)** — SPI 传输期间写入静默丢失是功能性 bug，不仅隐患。
4. **H4 (AW 等待 W 超时)** — 实际触发概率低（CPU bridge 总是配对发 AW+W），但属于防御性设计缺口。
5. **M1 (refill 饿死)** — 当前 Linux 负载下 MMIO 流量低，但高 I/O 负载场景可能触发。

### 17.7 审计方法

- 3个并行 explore agent：总线拓扑搜索、时钟域跨越搜索、APB/外设搜索
- 直接检查：`system_top.sv`（时钟/复位/CDC/地址译码）、`reset_sync.sv`、`Axi_CDC.v`、`axi4lite_to_apb.sv`、`apb_decoder.sv`、`axi4lite_default_slave.sv`、`axi4lite_clint.sv`
- 全项目 `USE_TLB_BRAM`/`cpu_clk`/`sys_clk`/`ext_mtime` 信号追踪

---

## 18. C1 修复：64位 `clint_mtime` Gray 编码 CDC（2026-06-21）

### 18.1 问题回顾

`clint_mtime[63:0]` 从 `sys_clk` 域通过2级移位寄存器同步到 `cpu_clk` 域，供 CPU `rdtime` CSR 读取。64位信号每位可能在不同时钟沿被采样，导致撕裂值。`r_mtime` 每 `sys_clk` 周期自增1，多位同时翻转概率高。

### 18.2 方案选型

| 方案 | 正确性 | 延迟 | 面积 | 适合 mtime? |
|------|--------|------|------|------------|
| **Gray 编码** ✅ | 正常操作完全安全；软件写有2~3周期瞬态误差 | 2周期 | 64×2 FF + 128 XOR | **推荐** |
| Tick 脉冲+本地重建 | 消除多位CDC，但 sys_clk > cpu_clk 时丢脉冲 | 0周期 | 1×2 FF + 64-bit 计数器 | ❌ 频率比>1丢脉冲 |
| Req/ack 握手 | 完全正确 | 4~6周期 | 2×2 FF + 控制逻辑 | 过度设计 |
| 异步 FIFO | 完全正确 | 取决于深度 | 64-bit FIFO + Gray 指针 | 杀鸡用牛刀 |

**选择 Gray 编码**：`clint_mtime` 每周期 +1，Gray 编码后仅1位翻转，2级逐位同步器要么捕获旧值要么新值，不会撕裂。`sys_clk`/`cpu_clk` = 2:1 时偏差 ±1~2 count，对 `rdtime` 可忽略。技术已在本项目 `Axi_CDC` 的 `StreamFifoCC` 中使用。

### 18.3 实现

**文件**：`dev/rtl/system_top.sv`

**修改前**（多位 CDC 隐患）：
```verilog
logic [63:0] clint_mtime_cpuclk_ff1, clint_mtime_cpuclk_ff2;
// in always_ff @(posedge cpu_clk):
clint_mtime_cpuclk_ff1 <= clint_mtime;        // 64位直接采样 → 撕裂风险
clint_mtime_cpuclk_ff2 <= clint_mtime_cpuclk_ff1;
```

**修改后**（Gray 编码 CDC）：
```verilog
// Gray 编码器 (sys_clk 域, 组合逻辑)
wire [63:0] clint_mtime_gray = clint_mtime ^ (clint_mtime >> 1);

// 2级逐位同步器 (cpu_clk 域)
logic [63:0] clint_mtime_gray_sync1, clint_mtime_gray_sync2;
// in always_ff @(posedge cpu_clk):
clint_mtime_gray_sync1 <= clint_mtime_gray;
clint_mtime_gray_sync2 <= clint_mtime_gray_sync1;

// Gray 解码器 (cpu_clk 域, 组合逻辑 — prefix-XOR 链)
wire [63:0] clint_mtime_cpuclk;
assign clint_mtime_cpuclk[63] = clint_mtime_gray_sync2[63];
generate for (ggi = 0; ggi < 63; ggi = ggi + 1)
    assign clint_mtime_cpuclk[ggi] = clint_mtime_gray_sync2[ggi] ^ clint_mtime_cpuclk[ggi+1];
endgenerate
```

**数据流**：
```
sys_clk: clint_mtime (binary) → XOR(>>1) → clint_mtime_gray (Gray code)
    ↓ 逐位2级同步器 (cpu_clk域)
cpu_clk: clint_mtime_gray_sync2 → prefix-XOR → clint_mtime_cpuclk (binary)
    → ext_mtime → CPU rdtime CSR
```

### 18.4 验证

| 测试 | 结果 |
|------|------|
| mmu_unified_mmu | ✅ PASS |
| reg_bug16_tlb_valid_pulse | ✅ PASS |
| reg_dcache_wb_error | ✅ PASS |
| reg_dcache_refill_error | ✅ PASS |
| reg_bare_no_miss | ✅ PASS |
| reg_mmio_ready | ✅ PASS |
| reg_fencei_wb_error | ✅ PASS |
| reg_sfence_wb_error | ✅ PASS |

编译通过，功能无回归。

### 18.5 边界分析

| 场景 | 行为 | 影响 |
|------|------|------|
| 正常自增 (每 sys_clk +1) | Gray 码仅1位翻转，同步器捕获旧或新值 | 完全正确 |
| sys_clk 2x cpu_clk (FPGA) | 一个 cpu_clk 周期内2次自增，Gray 码2位先后翻转 | 偏差 ±1~2 count，可忽略 |
| 软件写 mtime (罕见, 仅 boot) | 新旧值差大，Gray 码多位翻转，可能短暂撕裂 | 2~3周期瞬态误差，M-mode 可容忍 |

---

## 19. FPGA 第二轮验证 — Load Page Fault at C0377xxx（2026-06-21）

### 18.1 故障变化确认

**故障已显著变化**，前一轮修复（BUG-16 + HIGH-1 + HIGH-2 + MEDIUM-3 + UART THRE + DCache error + WB 公平性）生效：

| 项目 | 旧值（第一轮） | 新值（第二轮） | 变化 |
|------|----------------|----------------|------|
| IF PC | `C0000098`（卡死） | `C0377150`/`C0377160`（变化中） | ✅ PC 推进 ~55MB |
| SCAUS | `0xC`（inst page fault） | `0xD`（load page fault） | ⚠️ 故障类型变化 |
| SEPC | `80400098` | `C00ABBE4` | ✅ 内核虚拟空间 |
| S TVL | `80400098` | `00FEFFEC` | ⚠️ 用户空间地址 |
| S_SAT | `800808FC` | `800808FD` | ✅ 内核切换页表 |
| S_CNT | `2` | `0xF`（15） | ⚠️ trap 次数增加 |
| STVEC | `C0000098` | `C037FA88` | ✅ 内核更新 trap vector |
| IC_ST | `1`（S_TAG_READ） | `0`（IDLE） | ✅ icache 不再卡死 |
| I_RDY | `0` | `1` | ✅ **指令翻译完成** |
| MI_HI | — | `1` | ✅ **i-side TLB hit** |
| MI_SV | — | `1` | ✅ Sv32 已启用 |
| MI_VL | — | `1` | ✅ TLB entry valid |
| MI_PM | — | `0` | ✅ 无 i-side perm fault |
| STATE | `1`（FETCH） | `3` | ✅ 流水线推进 |
| MCAUS | `0x2`（illegal inst） | `0x9`（S-mode ecall） | ✅ SBI 调用正常 |
| MW_ST | — | `0`（W_IDLE） | ✅ PTW 空闲 |

**结论**：i-side MMU 完全工作。Linux 从 `80400000` 推进到 `C0377xxx`（~55MB kernel 虚拟空间），确认 BUG-16 修复有效。当前问题转移到 **d-side load page fault**。

### 18.2 新故障分析

#### 18.2.1 故障现场

```
SEPC = C00ABBE4    ← load 指令所在虚拟地址（kernel .text）
tval = 00FEFFEC    ← load 访问的目标虚拟地址（user space!）
scause = 13        ← load page fault
satp = 800808FD    ← Sv32, PPN=0x808FD, 页表在物理 0x808FD000
S_CNT = 15         ← 已发生 15 次 S-mode trap
MCAUS = 9          ← 同时有 S-mode ecall (SBI 调用)
```

#### 18.2.2 寄存器快照（Fault-time）

| 寄存器 | 值 | 推测含义 |
|--------|------|----------|
| F_S1 (x9) | `00FEFFEC` | **faulting pointer** — 被加载的用户空间地址 |
| F_S2 (x18) | `C045BC4E` | kernel 指针（可能是字符串/数据结构基址） |
| F_S3 (x19) | `00000002` | 可能是错误码或计数 |
| F_A4 (x14) | `00000038` | 56 decimal，可能是长度/偏移 |
| F_A5 (x15) | `00000000` | 清零 |

REG07 = `0x205B2D2D` → ASCII "]-[" （little-endian），REG06 = `0x2D` = '-'。内核正在处理字符串数据。

#### 18.2.3 地址分析

**faulting VA 0x00FEFFEC**（用户空间）：

```
0x00FEFFEC = 0000_0000_1111_1110_1111_1111_1110_1100

VPN[1] = [31:22] = 0b0000000011 = 0x003
VPN[0] = [21:12] = 0b1111011111 = 0x3EF  
offset = [11:0]  = 0xFEC

L1 PTE 地址 = 0x808FD000 + 0x003 × 4 = 0x808FD00C
L0 PTE 地址 = {L1_PTE.PPN, 12'b0} + 0x3EF × 4
```

**SEPC C00ABBE4**（内核虚拟空间）：

```
C00ABBE4 → VPN[1] = 0x300, VPN[0] = 0x0AB
L1 PTE 地址 = 0x808FD000 + 0x300 × 4 = 0x808FDC00
```

#### 18.2.4 可能原因

| # | 假说 | 证据 | 验证方法 |
|---|------|------|----------|
| **H1** | **d-side TLB 权限故障**：PTE 有 U=1，S-mode 无 SUM → perm fault | tval 在用户空间；perm 逻辑仿真 PASS | 检查 mstatus.SUM 位；添加 d-side debug 信号 |
| **H2** | **PTW walk 故障**：页表中无 0x00FEFFEC 的有效 PTE | S_CNT=15 可能是 demand paging 循环 | 检查 d_pf_from_ptw_r；ILA 抓取 PTE |
| **H3** | **指针腐败**：dcache/store bug 导致 s1 被写入错误值 | s1=0x00FEFFEC 是用户地址，kernel 不应主动访问 | Spike 对比；扩大 SRAM 仿真 |
| **H4** | **d-side TLB 条目错误**：MEDIUM-3 修复不完整，d-walk 用了 i-side 地址 | MEDIUM-3 曾导致 d-side 翻译错误 | 仿真波形检查 walk_vaddr |
| **H5** | **正常 demand paging**：内核合法访问用户页，fault handler 应处理但未完成 | S_CNT=15 持续增长 | Spike 对比确认是否正常 |

#### 18.2.5 权限检查逻辑验证

d-side 权限检查代码（`MMU.sv:260-266`）与 i-side 完全对称：

```systemverilog
assign d_tlb_perm_fault = (d_latched_priv_mode == 2'b00 && !d_tlb_u) ? 1'b1 :           // U-mode → non-U page
                          (d_latched_priv_mode == 2'b01 && d_tlb_u &&
                           (d_latched_access_type == ACCESS_FETCH || !d_latched_mstatus_sum)) ? 1'b1 :  // S-mode → U page without SUM
                          (d_latched_access_type == ACCESS_FETCH && !d_tlb_x) ? 1'b1 :   // no X
                          (d_latched_access_type == ACCESS_LOAD && !d_tlb_r && !(d_tlb_x && d_latched_mstatus_mxr)) ? 1'b1 :  // no R (unless MXR+X)
                          (d_latched_access_type == ACCESS_STORE && !d_tlb_w) ? 1'b1 :   // no W
                          1'b0;
```

`mmu/permission.s` 12/12 PASS 已验证此逻辑正确。**权限检查本身不是 bug**。

### 18.3 诊断缺口 — 缺少 d-side MMU debug 信号

**当前 LCD 只显示 i-side MMU 信号**（`system_top.sv:2183-2221`）：

| LCD 信号 | MMU.sv 输出 | 含义 |
|----------|-------------|------|
| MI_ST | `dbg_nb_i_state` | i-side FSM 状态 |
| MI_CH | `dbg_nb_i_input_changed` | i-side 输入变化 |
| MI_VA | `dbg_nb_i_latched_vaddr` | i-side latched VA |
| MI_SV | `dbg_nb_i_latched_sv32` | i-side Sv32 启用 |
| MI_HI | `dbg_i_tlb_hit` | i-side TLB hit |
| MI_VL | `dbg_i_tlb_valid` | i-side TLB valid |
| MI_PM | `dbg_i_tlb_perm_fault` | i-side perm fault |
| MW_ST | `dbg_walk_state` | PTW 仲裁状态 |

**缺少的 d-side 信号**（MMU.sv 未导出）：

| 需要的信号 | MMU.sv 内部名 | 诊断价值 |
|------------|---------------|----------|
| d_state | `d_state` | d-side FSM 状态（IDLE/LOOKUP/WALK_PENDING/FILL_WAIT） |
| d_tlb_hit | `d_tlb_hit` | d-side TLB 是否命中 |
| d_tlb_valid | `d_tlb_valid` | d-side TLB 条目是否有效 |
| d_tlb_perm_fault | `d_tlb_perm_fault` | d-side 权限故障 |
| d_input_changed | `d_input_changed` | d-side 输入变化 |
| d_latched_vaddr | `d_latched_vaddr` | d-side latched VA |
| d_latched_sv32 | `d_latched_sv32` | d-side Sv32 启用 |
| pending_d_walk | `pending_d_walk` | d-side PTW 排队 |
| d_pf_from_ptw_r | `d_pf_from_ptw_r` | **区分 TLB perm fault vs PTW walk fault** |
| d_tlb_miss | `d_tlb_miss` | d-side TLB miss |

**建议**：添加上述 d-side debug 信号到 MMU.sv → core_top.sv → system_top.sv LCD 显示，以便下次上板直接诊断。

### 18.4 仿真复现方案

#### 18.4.1 方案 A：扩大 SRAM 到 16MB（推荐）

**理由**：kernel 已推进到 C0377xxx，对应物理地址约 0x80377xxx（~3.5MB）+ 页表 0x808FD000（~9MB）。16MB SRAM 可覆盖全部。

**步骤**：

1. 修改 `dev/rtl/ram_wrap/axi_wrap_ram.sv`：
```systemverilog
localparam MEM_DEPTH = 4194304;  // 16MB / 4B = 4M words（从 262144 扩大）
```

2. 转换固件为 hex：
```bash
riscv64-unknown-elf-objcopy -O binary /tmp/fws/firmware/fw_payload.elf /tmp/fws/firmware/fw_payload.bin
python3 tools/bin2hex.py /tmp/fws/firmware/fw_payload.bin /tmp/fws/firmware/fw_payload.hex
```

3. 创建仿真任务（在 `tools/vivado_config.yaml` 或 tasks.yaml 中）：
```yaml
linux_boot:
  blhex: bootloader.hex
  phex: fw_payload.hex
  sim_cycles: 50000000   # 50M 周期
  debug: trace,trap,wave
```

4. 运行仿真：
```bash
python -m tools.vivado_cli -task linux_boot -create -sim --debug trace,trap,wave
```

5. 分析：
```bash
python -m tools.trace_analyzer parse instr_trace.log
python -m tools.trace_analyzer find-fail instr_trace.log
```

**预期耗时**：~30-60 分钟仿真

#### 18.4.2 方案 B：Spike 对比（快速定位硬件 vs 软件）

```bash
# Spike 仿真相同固件
spike --isa=rv32ima /tmp/fws/firmware/fw_payload.elf 2>&1 | tee spike.log

# 检查 Spike 是否在 C00ABBE4 处也触发 load page fault
# 如果 Spike 也 fault → 软件/固件问题
# 如果 Spike 不 fault → 硬件 bug
```

**预期耗时**：~5 分钟

#### 18.4.3 方案 C：聚焦 d-side MMU 测试（快速迭代）

编写测试验证 d-side MMU 在以下场景的行为：

```assembly
# test_d_side_load_fault.S
# 场景 1：S-mode load user page without SUM → expect load PF (cause 13)
# 场景 2：S-mode load user page with SUM=1 → expect OK
# 场景 3：S-mode load kernel page → expect OK
# 场景 4：d-side TLB miss → PTW walk → fill → retry → OK
# 场景 5：d-side PTW walk fault → load PF (cause 13)
```

**预期耗时**：~5 分钟仿真

#### 18.4.4 方案 D：添加 d-side debug 信号 + ILA（FPGA 诊断）

1. 在 `MMU.sv` 添加 d-side debug 输出端口
2. 在 `core_top.sv` 连接到顶层
3. 在 `system_top.sv` LCD 显示 d-side 信号
4. 可选：添加 ILA 探针在 d-side page fault 触发时抓取波形

### 18.5 推荐执行顺序

| 步骤 | 方案 | 耗时 | 目标 |
|------|------|------|------|
| 1 | **方案 B**（Spike 对比） | ~5min | 确定硬件 vs 软件 |
| 2 | **方案 D**（添加 d-side debug） | ~30min | 下次上板诊断 |
| 3 | **方案 A**（扩大 SRAM 仿真） | ~60min | 仿真复现 + 波形分析 |
| 4 | **方案 C**（聚焦测试） | ~5min | 快速验证修复 |

### 18.6 关键文件修改清单

| 文件 | 修改内容 | 优先级 |
|------|----------|--------|
| `dev/rtl/ram_wrap/axi_wrap_ram.sv` | MEM_DEPTH: 262144 → 4194304 | 高（方案 A） |
| `dev/rtl/core/MMU.sv` | 添加 d-side debug 输出端口 | 高（方案 D） |
| `dev/rtl/core/core_top.sv` | 连接 d-side debug 信号 | 高（方案 D） |
| `dev/rtl/system_top.sv` | LCD 显示 d-side MMU 信号 | 高（方案 D） |
| `tools/bin2hex.py` | 新建：bin → hex 转换脚本 | 中（方案 A） |
| `tools/vivado_config.yaml` | 添加 linux_boot 任务 | 中（方案 A） |

### 18.8 实施记录（2026-06-21）

#### 18.8.1 步骤 2：添加 d-side MMU debug 信号 — ✅ 完成

| 文件 | 修改 |
|------|------|
| `dev/rtl/core/MMU.sv` | 新增 10 个 d-side debug 输出端口：`dbg_nb_d_state`, `dbg_d_tlb_hit`, `dbg_d_tlb_valid`, `dbg_d_tlb_perm_fault`, `dbg_d_input_changed`, `dbg_d_latched_vaddr`, `dbg_d_latched_sv32`, `dbg_pending_d_walk`, `dbg_d_pf_from_ptw`, `dbg_d_tlb_miss` |
| `dev/rtl/core/core_top.sv` | 新增 10 个 wire + 端口声明 + MMU 实例连接 + assign 输出 |
| `dev/rtl/system_top.sv` | 新增 10 个 wire + core_top 实例连接 + LCD Page 4 显示 9 个 d-side 信号（索引 31-39） |

**LCD Page 4 新增信号**（sw[7:6]=11，索引 31-39）：

| LCD 信号 | 含义 | 诊断价值 |
|----------|------|----------|
| MD_ST | d_state (D_IDLE/D_LOOKUP/D_WALK_PENDING/D_FILL_WAIT) | d-side FSM 状态 |
| MD_HT | d_tlb_hit | d-side TLB 命中 |
| MD_VL | d_tlb_valid | d-side TLB 条目有效 |
| MD_PM | d_tlb_perm_fault | d-side 权限故障 |
| MD_CH | d_input_changed | d-side 输入变化 |
| MD_VA | d_latched_vaddr | d-side latched 虚拟地址 |
| MD_SV | d_latched_sv32 | d-side Sv32 启用 |
| MD_PW | d_pf_from_ptw | **区分 TLB perm fault (0) vs PTW walk fault (1)** |
| MD_MS | d_tlb_miss | d-side TLB miss |

#### 18.8.2 步骤 3：扩大 SRAM + 仿真基础设施 — ✅ 完成

| 文件 | 修改 |
|------|------|
| `dev/rtl/ram_wrap/axi_wrap_ram.sv` | MEM_DEPTH: 262144 → 4194304 (16MB); r_word_addr: [17:0] → [21:0]; 所有地址索引 [19:2] → [23:2] |
| `tools/bin2hex.py` | 新建：bin → $readmemh hex 转换工具 |
| `dev/program_source/firmware/fw_payload.hex` | 新建：9MB 固件 hex 文件（2352542 words） |
| `dev/tb/tb_simple_cpu_top.sv` | 新增 `LINUX_BOOT` 模式：200M 周期等待，跳过 cpu_full 寄存器检查 |
| `tasks.yaml` | 新增 `linux_boot` 任务：tb=tb_simple_cpu_top, phex=firmware/fw_payload.hex, runtime=60s, verilog_defines={LINUX_BOOT:TRUE} |

#### 18.8.3 步骤 4：仿真运行 — 进行中

```bash
python3 -m tools.vivado_cli -task linux_boot -create -sim --debug trace,trap,wave
```

**预期结果**：
- 仿真复现 load page fault at VA 0x00FEFFEC
- trap_trace.log 显示 SCAUS=0xD 循环
- instr_trace.log 显示 PC 到达 C0377xxx
- 波形文件可用于分析 d-side MMU 状态

**关键诊断信号**（波形中检查）：
- `dbg_mmu_d_state` — d-side FSM 是否卡在 D_WALK_PENDING
- `dbg_d_tlb_hit` / `dbg_d_tlb_miss` — TLB 命中/缺失
- `dbg_d_tlb_perm_fault` — 权限故障类型
- `dbg_d_pf_from_ptw` — 区分 TLB perm fault vs PTW walk fault
- `dbg_d_latched_vaddr` — d-side 正在翻译的虚拟地址

### 18.7 Explore Agent 发现 — d-side MMU 结构分析

#### 18.7.1 i-side vs d-side 不对称性（8 处）

| # | 不对称性 | i-side | d-side | 风险 |
|---|----------|--------|--------|------|
| 1 | IDLE 门控 | 总是 latch | 仅 `d_translate_en=1` 时 | ✅ 正确设计 |
| 2 | TLB fill 停顿 | 无（Port A 独占） | D_LOOKUP→D_IDLE on fill | ⚠️ 需 re-lookup |
| 3 | ready 额外条件 | `!i_input_changed` | `!d_input_changed && !d_lookup_stalled` | ⚠️ **d_ready 可在 fill 期间 glitch low** |
| 4 | page fault 脉冲 | 1 周期脉冲 | 1 周期脉冲 | ⚠️ mem_en 掉落时丢失 |
| 5 | PTW access_type | 硬编码 FETCH | 实际 LOAD/STORE | ✅ 正确 |
| 6 | VIPT set index | vaddr | vaddr | ✅ 正确（index ≤ 11） |
| 7 | TLB lookup during fill | 总是允许 | 被 fill 抑制 | ⚠️ d-side 必须 re-lookup |
| 8 | PTW A/D invalidation | 无 | dcache line invalidate | ✅ 正确 |

**关键风险 #3**：`d_ready = ... && !d_lookup_stalled`。当 TLB 正在 fill（`tlb_fill_req=1`），`d_lookup_stalled=1`，`d_ready=0`。如果 dcache 已经开始依赖 `mmu_ready` 的操作（如 tag BRAM 读），`d_ready` 突然拉低可能导致 dcache stall。

**关键风险 #4**：`d_pf_r` 每周期先清 0 再条件置 1。如果 `mem_en` 在 PTW walk 完成前掉落，`d_state` 回到 `D_IDLE`，page fault 脉冲不会被生成。但 `core_top.sv:1209` 注释说已移除 mem_en 门控。

#### 18.7.2 权限检查两阶段验证

**Stage A — PTW-level**（`ptw.sv:168-188`）：walk 时检查 R/W/X/U，**不检查 A/D**
- A=0 → `S_AD_UPDATE`（写回 PTE|0x40）→ `S_DONE`（填 TLB with A=1）
- **A=0 不触发 page fault**，触发的是 A/D 更新写回

**Stage B — TLB-level**（`MMU.sv:260-266`）：hit 时检查 R/W/X/U，**不检查 A/D**
- TLB 条目中 A=0 不会被发现（但 PTW fill 时 A 已被设为 1）

**结论**：权限检查逻辑结构正确，两阶段对称。A/D bit 处理正确。

#### 18.7.3 TLB 数据布局验证

```
TLB data entry: [31:10]=PPN, [9]=R, [8]=W, [7]=X, [6]=U, [5]=A, [4]=D, [3:0]=pad
Fill:  {fill_ppn, fill_r, fill_w, fill_x, fill_u, fill_a, fill_d, 4'b0}
Read:  d_hit_data[9]=R, [8]=W, [7]=X, [6]=U, [5]=A, [4]=D
```

**位位置匹配** ✅。无打包/解包错误。

#### 18.7.4 页表 walk 地址验证

faulting VA `0x00FEFFEC`：
- VPN[1] = 0x003, VPN[0] = 0x3EF
- satp PPN = 0x808FD → L1 表基址 = 0x808FD000
- L1 PTE 地址 = 0x808FD000 + 0x003 × 4 = **0x808FD00C**
- L0 PTE 地址 = {L1_PTE.PPN, 12'b0} + 0x3EF × 4

SEPC `C00ABBE4`（load 指令地址）：
- VPN[1] = 0x300, VPN[0] = 0x0AB
- L1 PTE 地址 = 0x808FD000 + 0x300 × 4 = **0x808FDC00**

#### 18.7.5 诊断结论

| 检查项 | 结果 |
|--------|------|
| 权限检查逻辑 | ✅ 正确（PTW + TLB 两阶段对称） |
| A/D bit 更新 | ✅ 正确（S_AD_UPDATE → S_DONE with A=1） |
| TLB 数据布局 | ✅ 正确（fill/read 位位置匹配） |
| d-side FSM | ✅ 正确（D_IDLE→D_LOOKUP→D_WALK_PENDING→D_FILL_WAIT） |
| walk 仲裁 | ✅ 正确（d-side 优先，pending 机制完整） |
| **d_ready glitch 风险** | ⚠️ `!d_lookup_stalled` 可导致 d_ready 在 TLB fill 期间拉低 |
| **d_page_fault 脉冲丢失** | ⚠️ mem_en 掉落时脉冲可能不被生成 |
| **d-side debug 信号缺失** | ❌ LCD 无 d_state/d_tlb_hit/d_tlb_perm_fault/d_pf_from_ptw_r |

**最终判断**：权限检查和 A/D 逻辑无 bug。load page fault 最可能原因：

1. **内核合法访问用户页**（demand paging 或 copy_from_user），fault handler 应处理但可能因其他 bug 循环
2. **指针腐败**（dcache/store bug 导致 s1=0x00FEFFEC）
3. **d_ready glitch** 导致 dcache 重发请求，时序异常

**下一步必须**：
- **Spike 对比**确定硬件 vs 软件
- **添加 d-side debug 信号**到 LCD/波形
- **扩大 SRAM 仿真**复现 + 波形分析

---

## 20. core_top.sv 声明顺序修复（2026-06-21）

### 20.1 问题

`log/full.log` 编译失败，`cpu_full` 任务报 7 个 `VRFC 10-2938` 重复声明错误：

```
ERROR: 'dbg_mu_active_w' is already implicitly declared on line 867 [core_top.sv:893]
ERROR: 'dbg_mu_req_valid_w' is already implicitly declared on line 868 [core_top.sv:894]
...（共7个）
ERROR: module 'core_top' ignored due to previous errors
```

**根因**：`dbg_mu_active_w` 等 7 个 wire 信号在 `cpu_execute u_execute(` 实例化（line 875-881）中作为端口连接使用，但 `wire` 声明位于实例化之后（line 901-907）。Vivado xvlog 先隐式声明为 wire（line 875-881 首次使用），遇到后续显式 `wire` 声明（line 901-907）时报重复声明错误。

### 20.2 修复

将 7 个 `wire` 声明移到 `cpu_execute u_execute(` 实例化之前：

```verilog
// dbg_mu wires must be declared before cpu_execute instantiation
wire        dbg_mu_active_w;
wire        dbg_mu_req_valid_w;
wire        dbg_mu_ready_w;
wire        dbg_mu_busy_w;
wire        dbg_mu_result_valid_w;
wire [2:0]  dbg_mu_funct3_w;
wire        dbg_exe_is_mu_w;

cpu_execute u_execute(
    ...
    .dbg_mu_active(dbg_mu_active_w),
    ...
);
```

### 20.3 验证

- `cpu_full` 编译通过（create OK 64.3s）
- `mmu_unified_mmu` + `reg_bare_no_miss` 回归 PASS

---

## 21. PLIC/CLINT/UART AXI4-Lite 修复（2026-06-21）

### 21.1 问题背景

总线/CDC 审计（§17）发现 AXI4-Lite 外设（PLIC、CLINT）的 AW/W 通道处理不正确：原实现假设 AW 和 W 总是同周期到达，但 AXI4-Lite 协议允许 AW 和 W 独立到达、任意顺序。UART 16550 wrapper 未检查 PSTRB，上半字节写会错误写入 8 位寄存器。

### 21.2 PLIC 修复 (`dev/rtl/axi/axi4lite_plic.sv`)

**AW/W 独立接收**：引入 `aw_latched`/`w_latched` 双锁存机制：

```verilog
wire aw_fire = (wr_state == WR_IDLE) && !aw_latched && s_axi_awvalid;
wire w_fire  = (wr_state == WR_IDLE) && !w_latched  && s_axi_wvalid;
wire wr_fire = (wr_state == WR_IDLE) && ((aw_latched || aw_fire) && (w_latched || w_fire));
```

- AW 先到 → 锁存 `wr_addr`，等 W
- W 先到 → 锁存 `wr_wdata`/`wr_wstrb`，等 AW
- 同周期 → 直接 fire
- 单 outstanding：`wr_fire` 后进 WR_RESP，等 `bready` 才回 WR_IDLE

**WSTRB 逐字节掩码**：priority/enable/threshold 寄存器写入时，每个 byte lane 按 `wr_wstrb_eff[i]` 选择新值或原值。

**等优先级偏向低 ID**：`find_highest` 函数用严格 `>` 比较，先找到的低 ID 不被等优先级后续源替换。SiFive 标准行为。

**锁存 claim 路径**：
- RD_IDLE：`rd_claim_id <= highest_id[ctx]`，原子清 pending + 关 gateway
- RD_WAIT：`r_rd_data <= {24'd0, rd_claim_id}` — 用锁存值，不依赖当前 `highest_id`
- RD_RESP：驱动 rvalid

第一次 claim 响应正确，即使 `highest_id` 在 claim 和 response 之间变化。

### 21.3 CLINT 修复 (`dev/rtl/axi/axi4lite_clint.sv`)

**AW/W 独立接收**：与 PLIC 相同的双锁存模式。

**WSTRB 逐字节掩码**：mtimecmp_lo/hi、mtime_lo/hi 四个半寄存器都有 WSTRB 掩码。

**mtime 自增暂停**：
```verilog
wire mtime_we = wr_fire && (wr_addr_timelo || wr_addr_timehi);
if (!mtime_we) r_mtime <= r_mtime + 64'd1;
```
写 mtime 任意半字时跳过自增，写入值不被立即覆盖。

**split 寄存器软件契约**：mtime/mtimecmp 暴露为 32 位半字，软件用 hi/lo 重试序列读、安全比较更新序列写。硬件保证写后 1 周期不自增。

### 21.4 UART 修复 (`dev/rtl/APB/perips/uart16550/uart_16550a.sv`)

**PSTRB[0] 门控**：
```verilog
wire we = PSEL & PENABLE & PWRITE & PSTRB[0];
```
仅 byte lane 0 写入。上半字节写（PSTRB=4'b1000）→ we=0，寄存器不修改。PREADY=1 常置，总线事务正常完成。

**timescale 指令**：添加 `` `timescale 1ns / 1ps ``。

### 21.5 测试覆盖

新增/更新 testbench：

| 测试 | 覆盖 | 结果 |
|------|------|------|
| `tb_axi4lite_plic_unit.sv` | AW/W 三种顺序、等优先级 claim、per-context enable/threshold、threshold 阻塞 | 8 pass, 0 fail |
| `tb_axi4lite_clint_unit.sv` | AW/W 三种顺序、msip/mtimecmp/mtime 读写、mtime 写保留+自增、MTIP/MSIP | Vivado task completed |
| `tb_uart_16550a_unit.sv` | SCR 读写、上半字节写忽略、LSR、RX+IRQ、TX | 6 pass, 0 fail |
| `tb_apb_perips.sv` (更新) | AXI 写顺序、UART 16550 活动路径 | 16 pass, 0 fail |

### 21.6 验证结果

```
tb_axi4lite_plic_unit:  pass=8 fail=0
tb_uart_16550a_unit:    pass=6 fail=0
apb_perips:             pass=16 fail=0
axi4lite_clint_unit:    Vivado task completed successfully
```

### 21.7 代码审查结论

| 模块 | 修复点 | 审查 |
|------|--------|------|
| PLIC | AW/W 独立接收 | ✅ 三种顺序 + 单 outstanding |
| PLIC | WSTRB 逐字节 | ✅ prio/enable/threshold 全覆盖 |
| PLIC | 等优先级偏向低 ID | ✅ 严格 `>` + 测试验证 |
| PLIC | 锁存 claim | ✅ RD_IDLE 锁存 → RD_WAIT 用锁存值 |
| PLIC | pending 写竞争 | ✅ claim 清除胜出，gateway 关闭阻止再 pending |
| CLINT | AW/W 独立接收 | ✅ 同 PLIC 模式 |
| CLINT | WSTRB 逐字节 | ✅ 四个半寄存器 |
| CLINT | mtime 自增暂停 | ✅ `mtime_we` 门控 |
| CLINT | split 寄存器契约 | ✅ 文档 + 硬件保证 |
| UART | PSTRB[0] 门控 | ✅ 上半字节写忽略 |
| UART | timescale | ✅ 已添加 |
