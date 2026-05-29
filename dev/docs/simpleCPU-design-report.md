# SimpleCPU 设计报告

> 生成日期: 2026-05-29 | 项目路径: `dev/rtl/`

---

## 1. 项目概述

本项目实现了一个基于 RISC-V RV32IM 指令集的多周期 CPU，采用五级流水线结构（取指-译码-执行-访存-回写），通过有限状态机（FSM）控制器协调各级运行。CPU 通过 AHB-Lite 总线连接片上存储与外设，支持异常/中断陷阱处理、CSR 读写、M 扩展乘除法运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32IM（整数 + 乘除法） |
| 架构 | 多周期 FSM 控制，五级流水线数据通路 |
| 数据位宽 | 32-bit |
| 特权模式 | M/S/U 三级特权模式，支持陷阱委托（medeleg/mideleg） |
| 地址空间 | 32-bit，Sv32 页表虚拟内存（MMU + TLB + PTW） |
| 存储架构 | 哈佛结构（icache / dcache 分离），4 路组相联，Tree-PLRU 替换，VIPT |
| 缓存策略 | 写回（write-back）+ 写分配（write-allocate），脏行驱逐写回主存 |
| 标签存储 | BRAM IP（icachet 32-bit×8 / dcachet 36-bit×8），配置驱动 |
| TLB 架构 | 4 路 × 4 组组相联（16 项），BRAM IP（tlb_flag 128-bit×4 / tlb_data 128-bit×4），Tree-PLRU 替换 |
| 总线接口 | AHB-Lite Master，支持 INCR8 突发传输 |
| 中断/异常 | 支持 Trap 进入/返回（mret/sret）、CLINT 定时器中断、PLIC 外部中断 |
| 特权指令 | SRET、SFENCE.VMA 指令支持 |
| 乘法器 | Booth 编码，32 周期迭代 |
| 除法器 | 非恢复余数法，32 周期迭代 + 修正 |
| 加法器 | 超前进位加法器（CLA），16-bit 级联为 32-bit |
| 起始地址 | `0x8000_0000` |

### 1.2 支持的指令集

**RV32I 基础整数指令（40 条）：**

| 类别 | 指令 |
|------|------|
| LUI/AUIPC | `LUI`, `AUIPC` |
| JAL/JALR | `JAL`, `JALR` |
| 分支 | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Load | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Store | `SB`, `SH`, `SW` |
| 立即数算术 | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| 寄存器算术 | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| 系统 | `ECALL`, `EBREAK`, `MRET`, `SRET`, `SFENCE.VMA`, `FENCE`, `FENCE.I`, `WFI` |
| CSR | `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI` |

**RV32M 乘除法扩展（8 条）：**

| 指令 | 说明 |
|------|------|
| `MUL` | 乘法低 32 位 |
| `MULH` | 有符号×有符号高 32 位 |
| `MULHSU` | 有符号×无符号高 32 位 |
| `MULHU` | 无符号×无符号高 32 位 |
| `DIV` | 有符号除法 |
| `DIVU` | 无符号除法 |
| `REM` | 有符号取余 |
| `REMU` | 无符号取余 |

---

## 2. 系统架构

### 2.1 顶层结构

```
system_top
├── core_top              ← CPU 核心
│   ├── cpu_controller    ← FSM 状态机控制器
│   ├── cpu_fetch         ← 取指级
│   ├── cpu_decode        ← 译码级
│   ├── cpu_execute       ← 执行级（含 ALU + MU）
│   ├── cpu_mem           ← 访存级
│   ├── cpu_wb            ← 回写级
│   ├── cpu_regfile       ← 32×32bit 寄存器堆
│   ├── cpu_trap_csr      ← 陷阱/CSR 子系统
│   │   ├── cpu_trap_manager
│   │   │   └── cpu_clint
│   │   └── cpu_csr_interface
│   │       └── cpu_csr
│   ├── icache_ctrl       ← 指令缓存控制器（4路组相联，VIPT）
│   │   ├── icachet       ← ICache 标签 BRAM IP（32-bit×8，byte_size=8）
│   │   ├── icached       ← ICache 数据 BRAM IP（256-bit×32，byte_enable）
│   │   └── tree_plru     ← Tree-PLRU 替换策略
│   ├── dcache_ctrl       ← 数据缓存控制器（4路组相联，写回+写分配，VIPT）
│   │   ├── dcachet       ← DCache 标签 BRAM IP（36-bit×8，byte_size=9）
│   │   ├── dcached       ← DCache 数据 BRAM IP（256-bit×32，byte_enable）
│   │   └── tree_plru     ← Tree-PLRU 替换策略
│   ├── MMU (×2)          ← Sv32 虚拟内存（TLB + PTW 页表漫游）
│   │   ├── tlb           ← TLB（4路×4组=16项，BRAM存储，Tree-PLRU替换）
│   │   │   ├── tlb_flag  ← TLB 标志 BRAM IP（128-bit×4）
│   │   │   ├── tlb_data  ← TLB 数据 BRAM IP（128-bit×4）
│   │   │   └── tree_plru ← Tree-PLRU 替换策略（每组）
│   │   └── ptw           ← 页表漫游器（Sv32 二级页表）
│   └── cpu_bus_bridge    ← AHB-Lite 总线桥接（MMIO + INCR8 突发）
├── ahb_lite_bus          ← AHB-Lite 总线
│   ├── ahb_sram_slave    ← SRAM 从设备（32KB BRAM IP）
│   ├── ahb_default_slave ← 默认从设备（未映射地址返回 ERROR）
│   ├── ahb_clint         ← CLINT（mtime/mtimecmp/msip）
│   ├── ahb_plic          ← PLIC（8-source，src[1]=Timer, src[2]=UART, src[3]=SPI, src[4]=GPIO）
│   └── ahb_lite_to_apb → apb_bus → apb_perips
│       ├── GPIO          ← 16-bit 双向 IO，引脚变化中断（o_irq→PLIC src[4]）
│       ├── UART (TX/RX)  ← TX/RX FIFO（16字节），中断（o_irq→PLIC src[2]），可配波特率
│       ├── Timer          ← 32-bit 定时器，中断（o_irq→PLIC src[1]）
│       └── SPI            ← 主模式 SPI，传输完成中断（o_irq→PLIC src[3]）
└── lcd_module            ← LCD 调试显示
```

### 2.2 地址映射

| 地址高位 | 从设备 | 说明 |
|----------|--------|------|
| `0x80_xxxx_xxxx` | SRAM Slave | 主存储器（32KB，缓存映射区域） |
| `0x02_xxxx_xxxx` | CLINT | 核心本地中断器（mtime/mtimecmp/msip 可写） |
| `0x0C_xxxx_xxxx` | PLIC | 平台级中断控制器 |
| `0x10_xxxx_xxxx` | APB Bridge | 外设桥（GPIO/UART/Timer/SPI） |

Cache/MMIO 判定规则：地址最高位 `addr[31] == 0` 为 MMIO 区域（走 AHB 总线旁路缓存），`addr[31] == 1` 为 Cacheable 区域（走 icache/dcache）。SRAM 从设备地址由 `0x00` 迁移至 `0x80`，所有数据访问使用 `0x8000_0000` 基址。

---

## 3. CPU 核心设计详述

### 3.1 多周期 FSM 控制器 (`cpu_controller`)

控制器采用 9 状态 FSM 驱动整个数据通路：

```
STATE_IDLE (0) → STATE_FETCH (1) → STATE_DECODE (2)
    ├── dec_is_fence/fencei/wfi → STATE_FETCH
    ├── dec_is_mret → STATE_TRAP_RETURN (8)
    ├── exception_at_decode → STATE_TRAP_ENTER (7)
    ├── dec_is_csr → STATE_CSR_ACCESS (6) → STATE_WB (5)
    ├── !dec_need_exe → STATE_FETCH (跳过执行)
    └── dec_need_exe → STATE_EXEC (3)
        ├── exe_is_branch → STATE_FETCH (或 STATE_TRAP_ENTER)
        ├── exe_need_mem → STATE_MEM (4) → STATE_WB (5)
        └── !exe_need_mem → STATE_WB (5) → STATE_FETCH
```

各级使能信号由当前状态直接译码产生（`if_valid`, `id_valid`, `exe_valid`, `mem_valid`, `wb_valid`, `csr_valid`），确保每个时钟周期仅一级活跃。

### 3.2 取指级 (`cpu_fetch`)

- 输入：PC、指令数据（来自 icache 或 MMIO）
- 输出：`if_id_bus[95:0]` = `{pc_plus4, pc, inst}`
- 完成条件：`if_valid && inst_valid`
- PC 更新在 `core_top` 中统一管理

### 3.3 译码级 (`cpu_decode`)

**指令重组 (`op_regroup`)**：从 32-bit 指令中提取 opcode、funct3、funct7、rs1、rs2、rd 及五种立即数（I/S/B/U/J 型），均带符号扩展。

**指令识别**：通过 opcode + funct3 + funct7 组合译码，识别全部 48 条指令（含 M 扩展）。

**操作数选择**：

- `alu_src1`：AUIPC/JAL/分支使用 PC，其余使用 rs1
- `alu_src2`：LUI/AUIPC 使用 imm_u，JAL 使用 imm_j，JALR 使用 imm_i，分支使用 imm_b，立即数算术使用 imm_i，移位使用 shamt，Load 使用 imm_i，Store 使用 imm_s，其余使用 rs2

**ALU 控制码**（16-bit one-hot）：

| 位 | 操作 |
|----|------|
| [12] | ADD |
| [11] | SUB |
| [10] | SLT |
| [9] | SLTU |
| [8] | AND |
| [7] | NOR |
| [6] | OR |
| [5] | XOR |
| [4] | SLL |
| [3] | SRL |
| [2] | SRA |
| [1] | LUI |

**非法指令检测**：无效指令编码、CSR 地址无效、写只读 CSR 均触发非法指令异常。

**ID/EX 总线**（320-bit）：`{pc_plus4, valid_inst, is_alu, is_load, is_store, is_jal_like, is_branch, use_fixed_wb, wb_we, rd, wb_fixed_data, mem_size, mem_unsigned, alu_control[15:0], is_mu, mu_funct3, alu_src1, alu_src2, rs1_value, rs2_value, branch_funct3, is_csr, is_ecall, is_ebreak, is_mret, csr_addr, csr_funct3, csr_uimm, pc, inst}`

### 3.4 执行级 (`cpu_execute`)

**ALU 子系统**：

```
alu_32bit
├── cla_adder_32bit       ← 超前进位加法器
│   ├── cla_adder_16bit (低16位)
│   │   └── cla_adder_4bit × 4
│   └── cla_adder_16bit (高16位)
│       └── cla_adder_4bit × 4
├── logic_unit            ← 逻辑/比较运算
├── shifter               ← 桶形移位器（5级级联）
├── lui                   ← 立即数直通
└── alu_result_selector   ← 16-bit one-hot 结果选择
```

**分支比较器 (`branch_comparator`)**：支持 BEQ/BNE/BLT/BGE/BLTU/BGEU，使用 `$signed` 进行有符号比较。

**乘除法单元 (`mu_unit`)**：

- 乘法：Booth 编码迭代乘法器，32 周期完成，输出 64-bit 乘积
- 除法：非恢复余数法，32 周期迭代 + 1 周期余数修正，处理除零和溢出
- 握手协议：`req_valid` → `mu_ready` → `mu_busy` → `result_valid` → `result_got`
- MULHSU 修正：`upper + (src2[31] ? src1 : 0)`
- MULHU 修正：`mulhsu_upper + (src1[31] ? src2 : 0)`

**JALR 对齐**：结果与 `0xFFFF_FFFE` 按位与，清除最低位。

**分支/跳转目标**：

- 分支：条件成立时目标 = ALU 结果（pc + imm_b）
- JAL：目标 = ALU 结果（pc + imm_j）
- JALR：目标 = ALU 结果 & ~1（rs1 + imm_i）

**指令对齐异常检测**：跳转目标 `[1:0] != 00` 时触发指令地址对齐异常（Exception Code = 0）。

**EX/MEM 总线**（207-bit）：`{pc_plus4, result_ok, is_jal_like, is_load, is_store, is_csr, wb_we, wb_rd, result_reg, mem_size, mem_unsigned, rs2_value, csr_rdata, pc, inst}`

### 3.5 访存级 (`cpu_mem`)

内部状态机：

```
MEM_IDLE → MEM_READ  (Load)  → 等待 data_valid → MEM_IDLE
MEM_IDLE → MEM_WRITE (Store) → 等待 data_valid → MEM_IDLE
MEM_IDLE → MEM_IDLE   (非访存指令，直接完成)
```

**Load 数据处理**：

- Byte：按 byte_offset 选择字节，根据 mem_unsigned 决定零扩展/符号扩展
- Halfword：按 addr[1] 选择半字，根据 mem_unsigned 决定零扩展/符号扩展
- Word：直接使用 readData

**Store 数据处理**：

- Byte：将 store_data[7:0] 复制到 4 字节位置
- Halfword：根据 addr[1:0] 放置到低/高半字
- Word：直接写

**地址对齐异常**：

- Halfword 访问 `addr[0] != 0` → 对齐异常
- Word 访问 `addr[1:0] != 00` → 对齐异常

**MEM/WB 总线**（168-bit）：`{pc_plus4, is_jal_like, is_csr, wb_we, wb_rd, wb_data, csr_rdata, pc, inst}`

### 3.6 回写级 (`cpu_wb`)

- 寄存器写使能：`wb_valid && wb_we`
- 写数据选择：CSR 指令写回 CSR 读出值，其余写回 ALU/MU/Load 结果
- JAL/JALR 写回值：`pc + 4`（在 `core_top` 中通过 `wb_is_jal_like` 信号选择）
- 寄存器 x0 硬连线为 0（在 `cpu_regfile` 中实现）

### 3.7 寄存器堆 (`cpu_regfile`)

- 32 个 32-bit 寄存器
- x0 恒为 0（读返回 0，写忽略）
- 单写端口，双读端口
- 附加调试读端口（`dbg_raddr`/`dbg_rdata`）

---

## 4. 陷阱与 CSR 子系统

### 4.1 陷阱管理器 (`cpu_trap_manager`)

**异常检测**：

| 异常类型 | 检测位置 | Exception Code |
|----------|----------|----------------|
| 指令访问错误 | 取指级 | 1 |
| 非法指令 | 译码级 | 2 |
| EBREAK | 译码级 | 3 |
| Load 地址对齐 | 访存级 | 4 |
| Store 地址对齐 | 访存级 | 6 |
| ECALL (U-mode) | 译码级 | 8 |
| ECALL (S-mode) | 译码级 | 9 |
| ECALL (M-mode) | 译码级 | 11 |
| 指令页错误 | 取指级 | 12 |
| Load 页错误 | 访存级 | 13 |
| Store/AMO 页错误 | 访存级 | 15 |

**中断检测**（`cpu_clint`）：

| 中断源 | Interrupt Code | 优先级 |
|--------|----------------|--------|
| 外部中断（MEIE & MEIP） | 0x8000_000B | 最高 |
| 软件中断（MSIE & MSIP） | 0x8000_0003 | 中 |
| 定时器中断（MTIE & MTIP） | 0x8000_0007 | 低 |

中断使能条件：`mstatus.MIE == 1` 且对应 `mie` 位为 1 且 `mip` 位为 1。

**陷阱委托机制**：

通过 medeleg/mideleg CSR 实现异常/中断委托。对应位为 1 时，该异常/中断委托至 S-mode 处理：

- 委托判定：`delegated = medeleg[cause]`（异常）或 `mideleg[cause]`（中断）
- 委托位不可将 ECALL-from-M（code=11）设为委托（硬件强制 medeleg[11]=0）

**Trap 进入**：

1. 判断委托：若 `delegated=1`，进入 S-mode；否则进入 M-mode
2. S-mode 陷阱进入：
   - 保存 `sepc = exception_pc`（异常）或 `interrupt_pc`（中断）
   - 保存 `scause`、`stval`
   - 更新 `sstatus`：`SPP = 当前特权级`，`SPIE = SIE`，`SIE = 0`
   - 跳转到 `stvec`（仅支持 Direct 模式）
3. M-mode 陷阱进入：
   - 保存 `mepc = exception_pc`（异常）或 `interrupt_pc`（中断）
   - 保存 `mcause`、`mtval`
   - 更新 `mstatus`：`MPP = 当前特权级`，`MPIE = MIE`，`MIE = 0`
   - 跳转到 `mtvec`（仅支持 Direct 模式）

**Trap 返回**：

- **MRET**：恢复 `MIE = MPIE`，特权级恢复至 `MPP`，跳转到 `mepc`
- **SRET**：恢复 `SIE = SPIE`，特权级恢复至 `SPP`，跳转到 `sepc`

**ECALL 异常码**：根据调用者特权级区分，U-mode ECALL 产生 code=8，S-mode ECALL 产生 code=9，M-mode ECALL 产生 code=11。

**hw_trap_is_enter 信号**：该信号在陷阱进入时有效，用于门控 epc/cause/tval 的写入。仅当 `hw_trap_is_enter=1` 时才更新对应 CSR，防止非陷阱周期误写（Bug 12 修复）。

### 4.2 CSR 寄存器 (`cpu_csr`)

**M-mode CSR：**

| CSR 地址 | 名称 | 可写 | 说明 |
|----------|------|------|------|
| 0x300 | mstatus | 是 | MPP/MPIE/MIE/SPP/SPIE/SIE/UXS/FS/XS/SD |
| 0x301 | misa | 否 | 硬连线 `0x40001100`（RV32IM） |
| 0x302 | medeleg | 是 | 异常委托寄存器 |
| 0x303 | mideleg | 是 | 中断委托寄存器 |
| 0x304 | mie | 是 | MEIE/MTIE/MSIE/SEIE/STIE/SSIE |
| 0x305 | mtvec | 是 | M-mode Trap 向量基址 |
| 0x306 | mcounteren | 是 | 计数器使能寄存器 |
| 0x310 | mstatush | 否 | 硬连线 0 |
| 0x340 | mscratch | 是 | M-mode 临时寄存器 |
| 0x341 | mepc | 是 | M-mode 异常/中断返回 PC |
| 0x342 | mcause | 是 | M-mode 异常/中断原因 |
| 0x343 | mtval | 是 | M-mode 异常附加信息 |
| 0x344 | mip | 否 | MEIP/MTIP/MSIP/SEIP/STIP/SSIP（硬件写入） |
| 0xB00 | mcycle | 是 | 时钟周期计数器低 32 位 |
| 0xB02 | minstret | 是 | 指令退休计数器低 32 位 |
| 0xB80 | mcycleh | 是 | 时钟周期计数器高 32 位 |
| 0xB82 | minstreth | 是 | 指令退休计数器高 32 位 |
| 0xF11-0xF15 | mvendorid 等 | 否 | 硬连线 0 |

**S-mode CSR：**

| CSR 地址 | 名称 | 可写 | 说明 |
|----------|------|------|------|
| 0x100 | sstatus | 是 | mstatus 的 S-mode 视图（SIE/SPIE/SPP/UXS/FS/XS/SD） |
| 0x104 | sie | 是 | SEIE/STIE/SSIE |
| 0x105 | stvec | 是 | S-mode Trap 向量基址 |
| 0x106 | scounteren | 是 | S-mode 计数器使能寄存器 |
| 0x140 | sscratch | 是 | S-mode 临时寄存器 |
| 0x141 | sepc | 是 | S-mode 异常/中断返回 PC |
| 0x142 | scause | 是 | S-mode 异常/中断原因 |
| 0x143 | stval | 是 | S-mode 异常附加信息 |
| 0x144 | sip | 否 | SEIP/STIP/SSIP（硬件写入） |
| 0x180 | satp | 是 | S-mode 地址翻译与保护（ASID + PPN） |

**sstatus 与 mstatus 的关系**：sstatus 是 mstatus 的受限视图，仅暴露 SIE（位1）、SPIE（位5）、SPP（位8）、UXS（位18:17）、FS（位14:13）、XS（位16:15）、SD（位31）。对 sstatus 的写操作仅修改 mstatus 中对应位，其余位保持不变。

**CSR 访问控制**：

- U-mode：不可访问 S-mode 和 M-mode CSR，访问触发非法指令异常
- S-mode：不可访问 M-mode CSR，访问触发非法指令异常
- M-mode：可访问所有 CSR

CSR 写掩码：mstatus 仅允许写 MPP[12:11]、SPP[8]、MPIE[7]、SPIE[5]、MIE[3]、SIE[1]；mie 仅允许写 MEIE[11]、SEIE[9]、MTIE[7]、STIE[5]、MSIE[3]、SSIE[1]；mtvec/mepc/stvec/sepc 强制低 2 位为 0。

---

## 5. 存储子系统

### 5.1 缓存几何参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 相联度 | 4 路组相联 | 每组 4 个缓存行 |
| 组数 | 8 | set_idx = addr[7:5] |
| 标签位 | 7 | tag = addr[14:8] |
| 字偏移 | 3 位 | word_off = addr[4:2]，每行 8 字（32 字节） |
| 行大小 | 256-bit（8×32-bit） | 一次 INCR8 突发填充 |
| 总容量 | 8 组 × 4 路 × 32 字节 = 1KB | ICache 与 DCache 各 1KB |

地址分解：`| tag[14:8] | set[7:5] | word[4:2] | byte[1:0] |`

### 5.2 Tree-PLRU 替换策略 (`tree_plru`)

4 路 Tree-PLRU 使用 3-bit 状态编码，组织为二叉树：

```
       bit0
      /    \
   bit1    bit2
   / \     / \
  W0  W1  W2  W3
```

- `bit=0` 指向左子树，`bit=1` 指向右子树
- 访问 way N 时，从根到叶路径上所有节点指向 N 所在子树的反方向
- 替换时从根到叶按 bit 方向行走，定位受害路
- 优先选择无效路（invalid way first），仅当所有路有效时使用 PLRU

### 5.3 标签存储（BRAM IP）

标签使用 BRAM IP 存储（`use_tag_bram: true`），每组 4 路标签打包为一个 BRAM 字，通过 Port A 读取后在下一周期进行 4 路并行比较：

| 缓存 | 标签 BRAM | BRAM 配置 | 每路标签格式 | 说明 |
|------|-----------|-----------|-------------|------|
| ICache | `icachet` | 32-bit × 8，True Dual Port，Byte_Enable，Byte_Size=8 | `{V(1), tag[6:0]}` = 8-bit | 无脏位（指令缓存只读） |
| DCache | `dcachet` | 36-bit × 8，True Dual Port，Byte_Enable，Byte_Size=9 | `{V(1), D(1), tag[6:0]}` = 9-bit | dirty 位标识写回需求 |

- BRAM 地址 = set_idx（3-bit），每个地址包含一组 4 路标签
- ICache 标签 BRAM 字：`{Way3[7:0], Way2[7:0], Way1[7:0], Way0[7:0]}` = 32-bit
- DCache 标签 BRAM 字：`{Way3[8:0], Way2[8:0], Way1[8:0], Way0[8:0]}` = 36-bit
- Port A：CPU 读（S_IDLE 使能，S_TAG_READ 出结果）
- Port B：Refill 写 / Dirty 更新 / Invalidate 写
- 命中判定：`valid && (tag == paddr[14:8])`，4 路并行，BRAM 读延迟 1 周期
- Byte-write enable 支持单路标签更新（Refill/Dirty 置位时仅写目标路）

### 5.4 数据存储（BRAM IP）

| BRAM | 配置 | 端口 A | 端口 B |
|------|------|--------|--------|
| icached | 256-bit × 32，True Dual Port，WRITE_FIRST，Byte_Enable | CPU 读 | Refill 写 |
| dcached | 256-bit × 32，True Dual Port，WRITE_FIRST，Byte_Enable | CPU 读/写 | Refill 写 / Victim 读 |
| icachet | 32-bit × 8，True Dual Port，Byte_Enable，Byte_Size=8 | CPU 读 | Refill 写 / Invalidate 写 |
| dcachet | 36-bit × 8，True Dual Port，Byte_Enable，Byte_Size=9 | CPU 读 / Flush 扫描 | Refill 写 / Dirty 更新 / Invalidate 写 |
| tlb_flag | 128-bit × 4，True Dual Port，Byte_Enable，Byte_Size=8 | i-side 查找 | d-side 查找 / Fill 写 / Flush 写 |
| tlb_data | 128-bit × 4，True Dual Port，Byte_Enable，Byte_Size=8 | i-side 查找 | d-side 查找 / Fill 写 / Flush 写 |

数据 BRAM 地址映射：`bram_addr = {set_idx[2:0], way[1:0]}`，5-bit 寻址 32 项。
标签 BRAM 地址映射：`bram_addr = set_idx[2:0]`，3-bit 寻址 8 项（每组 4 路打包为 1 字）。
TLB BRAM 地址映射：`bram_addr = set_idx[1:0]`，2-bit 寻址 4 项（每组 4 路打包为 1 字）。

**BRAM 读延迟差异**：

- 仿真：BRAM 行为模型提供组合输出（0-cycle 延迟）
- 硬件：`READ_LATENCY=1`，寄存输出（1-cycle 延迟）
- 标签/TLB BRAM：ICache/DCache 控制器新增 `S_TAG_READ` 状态等待 BRAM 输出；TLB 查找结果延迟 1 周期有效
- 仿真通过不代表硬件时序正确，综合时需关注

### 5.5 指令缓存控制器 (`icache_ctrl`)

ICache 采用 VIPT（Virtually-Indexed Physically-Tagged）策略：使用虚拟地址的页内偏移位作为 set index（与物理地址相同），物理地址的 tag 位进行标签比较。这避免了 MMU 翻译延迟对缓存查找的影响。

ICache FSM 状态转换：

```
S_IDLE → S_TAG_READ (BRAM 使能，锁存请求，等待标签 BRAM 输出)
S_TAG_READ → hit:  使能数据 BRAM，进 S_READ
S_TAG_READ → miss: 锁存 set/addr/victim，发 refill_req，进 S_REFILL
S_READ:          返回数据 BRAM 输出，更新 PLRU，回 S_IDLE
S_REFILL:        保持 refill_req，等 refill_valid，写 BRAM PortB，
                 更新标签+PLRU，旁路返回数据，回 S_IDLE
S_INVALIDATE:    逐组写零标签 BRAM，完成后回 S_IDLE
```

- MMIO 旁路：`vaddr[31]==0` 时直接发 AHB 请求，不经过缓存（使用虚拟地址判断，因为物理地址可能在 MMU 未就绪时无效）
- 标签比较在 S_TAG_READ 完成（BRAM 1-cycle 延迟后），命中时进 S_READ 读数据 BRAM
- 缺失时向 `cpu_bus_bridge` 发 INCR8 读突发请求，8 拍填充整行
- 数据 BRAM 读使能门控 `mmu_ready`，避免使用过时物理地址

### 5.6 数据缓存控制器 (`dcache_ctrl`)

DCache 同样采用 VIPT 策略，使用虚拟地址的页内偏移位作为 set index，物理地址的 tag 位进行标签比较。

DCache FSM 状态转换：

```
S_IDLE → S_TAG_READ (标签 BRAM 使能，锁存请求，等待 BRAM 输出)
S_TAG_READ → store hit:  写数据 BRAM PortA，置 dirty（通过标签 BRAM PortB byte-write），更新 PLRU，ready=1
S_TAG_READ → load hit:   进 S_READ_HIT
S_TAG_READ → miss:       锁存请求，若 victim dirty → S_WB_READ，否则 → S_REFILL
S_READ_HIT:          返回数据 BRAM 输出，更新 PLRU，回 S_IDLE
S_WB_READ:           使能数据 BRAM PortB 读，重构 WB 地址，进 S_WB_SEND
S_WB_SEND:           保持 wb_req，等 wb_valid，清 dirty，发 refill_req，进 S_REFILL
S_REFILL:            保持 refill_req，等 refill_valid，写 BRAM PortB
                     （store miss 时合并写入数据），更新标签+PLRU，旁路返回，回 S_IDLE
S_FLUSH_SCAN:        逐组扫描标签 BRAM，检查脏行
S_FLUSH_CHECK:       检查当前组各路脏位，若有脏行 → S_FLUSH_WB_RD
S_FLUSH_WB_RD:       读出脏行数据 BRAM，进 S_FLUSH_WB_SD
S_FLUSH_WB_SD:       发写回请求，等 wb_valid，继续扫描下一脏行或下一组
S_FLUSH_INVALIDATE:  写零标签 BRAM，使所有路无效
```

**写策略**：

- 写回（write-back）：Store 命中时仅写 BRAM + 置 dirty，不立即写主存
- 写分配（write-allocate）：Store 缺失时先 Refill 读入整行，再合并写入

**Store 数据合并**：

- Byte Store：`wdata[7:0] << (addr[1:0] * 8)`
- Halfword/Word Store：直接使用 `cpu_req_wdata`（`cpu_mem` 已将数据放置到正确字节位置）
- Store 缺失合并：Refill 读回数据中，仅替换 store 目标字，其余保持 Refill 数据

**脏行驱逐（Writeback）**：

- 替换受害路时，若 dirty=1，先通过 BRAM PortB 读出整行 256-bit 数据
- 重构写回地址：`{tag, set_idx, 3'b000, 2'b00}`
- 通过 `cpu_bus_bridge` 发 INCR8 写突发，8 拍写回主存
- 写回完成后清 dirty，再发 Refill 读请求

### 5.7 总线桥接 (`cpu_bus_bridge`)

将 Cache Refill/Writeback 和 MMIO 请求转换为 AHB-Lite Master 协议：

```
S_IDLE: 仲裁请求（优先级: MMIO > WB > IRefill > DRefill）
S_MMIO_ADDR/S_MMIO_DATA:     单次 AHB 传输
S_IREFILL_ADDR/S_IREFILL_DATA: INCR8 读突发，累积 HRDATA 至 refill_shift_reg
S_DREFILL_ADDR/S_DREFILL_DATA: INCR8 读突发，同上
S_WB_ADDR/S_WB_DATA:          INCR8 写突发，每拍移出 wb_shift_reg[31:0]
```

**突发传输协议**：

- 地址拍：HTRANS=NONSEQ，HBURST=INCR8
- 数据拍 1-7：HTRANS=SEQ
- 数据拍 8（最后拍）：HTRANS=IDLE（提前指示突发结束）
- Refill 累积：`refill_shift_reg = {HRDATA, refill_shift_reg[255:32]}`，8 拍后得到完整 256-bit 行

**优先级防饿**：MMIO 最高优先（单拍完成），WB 次之（防止脏行堆积），IRefill 再次，DRefill 最低。

### 5.8 SRAM 从设备 (`ahb_sram_slave`)

- 容量：32KB（32-bit × 8192 字）
- 实现：Xilinx BRAM IP 核（True Dual Port，WRITE_FIRST）
- 写使能：1-bit（Sram IP 仅支持整字写，`byte_enable: false`）
- 基地址：`0x8000_0000`（地址译码 `HADDR[31:24] == 8'h80`）
- 支持 INCR8 突发读写，1 等待状态

### 5.9 AHB 默认从设备 (`ahb_default_slave`)

- 功能：响应未映射地址空间的 AHB 传输请求
- 行为：任何传输返回 ERROR 响应（`HRESP=1`），两拍完成（地址拍 + 错误拍）
- 用途：防止总线无响应挂死，符合 AHB-Lite 协议要求
- 状态机：`error_phase` 标记错误响应的第二拍

### 5.10 MMU（Sv32 虚拟内存）

CPU 包含两个 MMU 实例：指令 MMU（inst MMU）和数据 MMU（data MMU），各自拥有独立的 TLB 和 PTW。

**Sv32 页表格式**：

Sv32 采用二级页表结构，虚拟地址 32-bit 分解如下：

```
| VPN[1] (10-bit) | VPN[0] (10-bit) | page_offset (12-bit) |
```

- L1 页表：VPN[1] 索引，命中时为 megapage（4MB），PPN[0] 由虚拟地址 VPN[0] 直接传递
- L0 页表：VPN[0] 索引，命中时为普通页（4KB）

**页表项（PTE）格式**（32-bit）：

```
| PPN[31:10] (22-bit) | RSW[9:8] (2-bit) | D (1) | A (1) | G (1) | U (1) | X (1) | W (1) | R (1) | V (1) |
```

| 位域 | 说明 |
|------|------|
| PPN[31:10] | 物理页号 |
| RSW[9:8] | 保留供软件使用 |
| D | 脏位，该页曾被写入 |
| A | 访问位，该页曾被访问 |
| G | 全局映射，ASID 刷新时不驱逐 |
| U | 用户模式可访问 |
| X | 可执行 |
| W | 可写 |
| R | 可读 |
| V | 有效位 |

**TLB（`tlb.sv`）**：

TLB 采用 BRAM-based 4 路 × 4 组组相联结构（`use_tlb_bram: true`），共 16 项，使用 Tree-PLRU 替换策略：

- **双端口 BRAM**：Port A = i-side 查找，Port B = d-side 查找 / Fill 写
- **Flag BRAM（tlb_flag）**：128-bit × 4 deep，每路 32-bit 标志项
  - 标志项格式：`{V(1), G(1), ASID(9), VPN(20), mega(1)}`
- **Data BRAM（tlb_data）**：128-bit × 4 deep，每路 32-bit 数据项
  - 数据项格式：`{PPN(22), R(1), W(1), X(1), U(1), A(1), D(1), pad(4)}`
- **组索引**：`set_idx = VPN[SET_IDX_W+9:10]`（使用 VPN 高位，确保 megapage 的 VPN[9:0] 差异映射到同一组，无需复制）
- **ASID 感知**：每项存储 ASID，匹配时需 ASID 一致或 G=1（全局项）
- **查找**：BRAM 读延迟 1 周期，结果在 `lookup_valid` 信号有效时可用
- **命中**：`valid && vpn_match && (global || asid_match)`，4 路并行比较
- **Megapage 匹配**：仅比较 VPN[19:10]（高 10 位），VPN[9:0] 忽略
- **缺失**：触发 PTW 页表漫游
- **驱逐**：SFENCE.VMA 刷新全部项（逐组写零 BRAM，S_FLUSH 状态机）
- **Shadow valid bits**：寄存器阵列跟踪各路有效状态，用于 Fill 时选择受害路（无效路优先）
- **Fill 优先**：Port B 上 Fill 写优先于 d-side 查找，保证 TLB 填充不被阻塞

**PTW 状态机（`ptw.sv`）**：

页表漫游器按 Sv32 二级页表逐级查找，状态转换如下：

```
S_IDLE → S_L1_READ    ← 读取 L1 页表项（PTW 发起总线请求）
S_L1_READ → S_L1_CHECK ← 检查 L1 PTE：V=0 或 R=W=0 且 X=0 → fault
S_L1_CHECK → S_L0_READ ← L1 为非叶节点，计算 L0 PTE 地址，读取 L0 项
S_L1_CHECK → S_PERM_CHECK ← L1 为 megapage（叶节点），跳转权限检查
S_L0_READ → S_L0_CHECK  ← 检查 L0 PTE
S_L0_CHECK → S_PERM_CHECK ← L0 为叶节点，进入权限检查
S_PERM_CHECK → S_DONE   ← 权限通过，写入 TLB，输出物理地址
S_PERM_CHECK → S_FAULT  ← 权限违规，输出页错误
```

**A/D 位硬件管理**：

PTW 在页表漫游过程中自动管理访问位（A）和脏位（D）：

- 首次访问某页时，若 PTE.A=0，PTW 写回 PTE 并置 A=1
- 首次写入某页时，若 PTE.D=0，PTW 写回 PTE 并置 D=1
- 写回通过 PTW 总线请求完成，旁路 dcache 直接到 AHB→BRAM

**translate_en 输入**：

- 指令 MMU：translate_en 恒为 1（取指始终经过地址翻译）
- 数据 MMU：translate_en 由 mem_en 门控（Bug 14/15 修复），仅当访存使能时才激活 Sv32 翻译，消除组合信号竞争

**权限检查**：

| 访问类型 | 权限要求 |
|----------|----------|
| 取指（fetch） | PTE.X=1 |
| Load | PTE.R=1（或 PTE.X=1 且 mstatus.MXR=1） |
| Store/AMO | PTE.W=1 |
| U-mode 访问 | PTE.U=1 |
| S-mode 访问 | PTE.U=0（除非 mstatus.SUM=1 且为 Load） |

**SFENCE.VMA 指令**：

执行 SFENCE.VMA 时刷新两个 TLB 的全部项。若指定 rs1（ASID）或 rs2（VPN），可选择性刷新，当前实现为全刷新。

**FENCE.I 指令**：

执行 FENCE.I 时：
1. 刷新 dcache：写回所有脏行（writeback dirty lines）
2. 失效 icache：使所有标签 valid=0

### 5.11 总线桥接 PTW 路径 (`cpu_bus_bridge`)

`cpu_bus_bridge` 除了处理 Cache Refill/Writeback 和 MMIO 请求外，还负责 PTW 的读写请求。PTW 请求旁路 dcache，直接通过 AHB 总线访问 BRAM 中的页表数据。

**PTW 请求处理**：

- PTW 读请求：读取页表项（L1/L0 PTE），直接发 AHB 单拍读
- PTW 写请求：A/D 位写回，直接发 AHB 单拍写
- 旁路 dcache：PTW 请求不经过 dcache，避免缓存一致性问题和死锁

**仲裁优先级**（从高到低）：

```
icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill
```

PTW 优先级高于 Cache Writeback 和 Refill，确保页表漫游不会被缓存操作阻塞，但低于 MMIO 请求以保证外设访问的实时性。

**PTW 总线错误处理**（Bug 10/11 修复）：

当 PTW 发起的 AHB 请求收到错误响应（HRESP=ERROR）时：
1. 置 `ptw_error_r = 1`
2. PTW 状态机进入 S_FAULT
3. 产生页错误异常，由陷阱管理器处理

### 5.12 配置驱动的存储几何 (`cache_def.svh`)

所有 Cache/TLB 几何参数由 `vivado_config.yaml` 的 `memory` 段统一定义，通过自动生成链保持 IP 与 RTL 同步：

```
vivado_config.yaml
  ├─→ ip_gen.py           → create_ip TCL（BRAM 几何参数：Sram/icached/dcached/icachet/dcachet/tlb_flag/tlb_data）
  ├─→ cache_header_gen.py → cache_def.svh（`define 宏：地址切片、宽度常量、存储模式）
  └─→ operations.py       → _tcl_setup_ip() 在 create/refresh 时执行
```

**`cache_def.svh`** 为自动生成文件（勿手动编辑），包含：

- SRAM 参数：`SRAM_DATA_WIDTH`、`SRAM_DEPTH`、`SRAM_ADDR_WIDTH`
- ICache/DCache 参数：`NUM_SETS`、`NUM_WAYS`、`TAG_WIDTH`、`LINE_WORDS`、`LINE_WIDTH`、`DEPTH`、`ADDR_WIDTH`、`WEA_WIDTH`
- 地址切片：`WORD_OFF_LO/HI`、`SET_IDX_LO/HI`、`TAG_LO/HI`
- 标签 BRAM 参数：`TAG_ENTRY_WIDTH`、`TAG_BRAM_WIDTH/DEPTH/ADDR_WIDTH/WEA_WIDTH/BYTE_SIZE`
- TLB 参数：`TLB_NUM_WAYS`、`TLB_NUM_SETS`、`TLB_SET_IDX_WIDTH`、`TLB_WAY_WIDTH`
- TLB BRAM 参数：`TLB_FLAG/DATA_ENTRY_WIDTH`、`TLB_FLAG/DATA_BRAM_WIDTH/DEPTH/ADDR_WIDTH/WEA_WIDTH/BYTE_SIZE`
- 存储模式：`USE_TAG_BRAM`、`USE_TLB_BRAM`

修改 `vivado_config.yaml` 后运行 `python -m tools.vivado_cli --gen-config` 即可重新生成 `cache_def.svh`。

**可配置项**（`vivado_config.yaml` memory 段）：

| 参数 | 当前值 | 说明 |
|------|--------|------|
| `sram.data_width` | 32 | SRAM 字宽 |
| `sram.depth` | 8192 | SRAM 深度（32KB） |
| `sram.byte_enable` | false | SRAM 字节写使能（当前关闭） |
| `icache/dcache.num_sets` | 8 | 组数 |
| `icache/dcache.num_ways` | 4 | 相联度（⚠ tree_plru 硬编码，勿改） |
| `icache/dcache.tag_width` | 7 | 标签位宽（⚠ tree_plru 硬编码，勿改） |
| `icache/dcache.line_words` | 8 | 每行字数 |
| `icache/dcache.byte_enable` | true | 数据 BRAM 字节写使能 |
| `use_tag_bram` | true | 标签存储模式：true=BRAM IP，false=寄存器阵列 |
| `tlb.num_ways` | 4 | TLB 相联度（⚠ tree_plru 硬编码，勿改） |
| `tlb.num_sets` | 4 | TLB 组数（总项数 = ways × sets = 16） |
| `use_tlb_bram` | true | TLB 存储模式：true=BRAM IP，false=寄存器阵列 |

---

## 6. 总线与外设

### 6.1 AHB-Lite 总线 (`ahb_lite_bus`)

- 5 个从设备：SRAM、Default Slave、CLINT、PLIC、APB Bridge
- 地址译码：按 `HADDR[31:24]` 选择从设备
- Default Slave：未映射地址返回 ERROR 响应，防止总线挂死
- 多路复用器回读数据与响应
- 参数化：地址宽度、数据宽度、从设备数、SRAM 深度、等待状态数

### 6.2 APB 总线与外设

通过 AHB-Lite to APB 桥接访问：

| 外设 | 说明 |
|------|------|
| GPIO | 16-bit 双向 IO，引脚变化中断，中断使能/状态寄存器 |
| UART | TX/RX FIFO（16 字节），中断输出，运行时波特率配置 |
| Timer | 32-bit 定时器，产生中断，单次/周期模式 |
| SPI | 主模式 SPI 控制器，传输完成中断 |

#### 6.2.1 UART 寄存器映射

| 偏移 | 名称 | 位定义 | 说明 |
|------|------|--------|------|
| 0x00 | CTRL | [0]=TX_EN [1]=RX_EN [2]=TX_IE [3]=RX_IE | 控制/中断使能 |
| 0x04 | STATUS | [0]=TX_BUSY [1]=RX_VALID [2]=TX_FIFO_FULL [3]=RX_FIFO_EMPTY [4]=TX_FIFO_EMPTY [5]=RX_FIFO_FULL | FIFO 状态 |
| 0x08 | TXDATA | [7:0] | 写入推入 TX FIFO |
| 0x0C | RXDATA | [7:0] | 读取弹出 RX FIFO |
| 0x10 | BAUD | [15:0] | 波特率分频系数（0=默认 115200） |
| 0x14 | IRQ_STAT | [0]=TX_DONE_IRQ [1]=RX_VALID_IRQ | 中断挂起（写 1 清除） |

#### 6.2.2 GPIO 寄存器映射

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | CTRL | 方向控制（1=输出，0=输入） |
| 0x04 | DATA | 数据寄存器 |
| 0x08 | IRQ_EN | 逐引脚中断使能掩码 |
| 0x0C | IRQ_STAT | 逐引脚中断挂起（写 1 清除） |

#### 6.2.3 SPI 寄存器映射

| 偏移 | 名称 | 位定义 | 说明 |
|------|------|--------|------|
| 0x00 | CTRL | [0]=EN [1]=CPOL [2]=CPHA [3]=CS [4]=IRQ_EN [15:8]=CLK_DIV | 控制/中断使能 |
| 0x04 | DATA | [7:0] | 数据寄存器 |
| 0x08 | STATUS | [0]=BUSY [1]=IRQ_PENDING | 状态/中断挂起 |

#### 6.2.4 PLIC 中断路由

| PLIC src_irq | 来源 | 说明 |
|--------------|------|------|
| src[0] | — | 保留 |
| src[1] | Timer | APB Timer 比较匹配中断 |
| src[2] | UART | UART TX 完成 / RX 有效中断 |
| src[3] | SPI | SPI 传输完成中断 |
| src[4] | GPIO | GPIO 引脚变化中断 |
| src[5:7] | — | 保留 |

---

## 7. 模块间总线定义

| 总线名 | 位宽 | 传递内容 |
|--------|------|----------|
| `if_id_bus` | 96-bit | `{pc_plus4[31:0], pc[31:0], inst[31:0]}` |
| `id_exe_bus` | 320-bit | 完整译码结果（见 3.3 节） |
| `exe_mem_bus` | 207-bit | 执行结果 + 访存控制（见 3.4 节） |
| `mem_wb_bus` | 168-bit | 访存结果 + 回写控制（见 3.5 节） |

级间设置触发器（`if_id_bus_r`, `id_exe_bus_r`, `exe_mem_bus_r`, `mem_wb_bus_r`）作为流水线寄存器，在对应级完成时锁存。

---

## 8. 验证

### 8.1 测试平台

| Testbench | 程序 | 测试内容 | 仿真时间 | 结果 |
|-----------|------|----------|----------|------|
| `tb_simple_cpu_top` | `cpu_test.hex` | 完整指令集测试（ALU + 分支 + 跳转 + Load/Store + M 扩展 + CLINT + Trap） | 10ms | 42 PASS, 0 FAIL |
| `tb_simple_cpu_compute` | `cpu_test_compute.hex` | 算术/逻辑/移位/乘除法计算测试 | 10ms | 42 PASS, 0 FAIL |
| `tb_simple_cpu_trap` | `cpu_test_trap.hex` | 异常/中断陷阱处理测试 | 5ms | 14 PASS, 0 FAIL |
| `tb_simple_cpu_priv` | `cpu_test_priv.coe` | M/S/U 特权模式 + Sv32 虚拟内存测试 | 25ms | 3 PASS, 0 FAIL |
| `tb_led_marquee` | `led_marquee.hex` | LED 跑马灯 + GPIO + CLINT MTIP 测试 | 2s | 16 PASS, 0 FAIL |
| `tb_uart_hello` | `uart_hello.hex` | UART 输出 "Hello World" 测试 | 40ms | 12 PASS, 0 FAIL |
| `tb_ahb_bus` | — | AHB-Lite 总线功能测试 | 5000ns | — |
| `tb_apb_perips` | — | APB 外设功能测试 | 2000ns | — |
| `tb_non_restoring_divider` | — | 除法器单元测试 | — | — |
| `tb_mu_unit` | — | 乘除法单元测试 | — | — |
| `tb_alu_cpu_integration` | — | ALU 集成测试 | — | — |

### 8.2 验证方法

- 寄存器检查：通过 `rf_addr`/`rf_data` 端口直接读取寄存器堆，与期望值比对
- 存储器检查：BRAM IP 内部数组路径在仿真中不可直接访问，标记为 SKIP
- UART 检查：testbench 内嵌 UART RX 解码器，逐字符比对输出
- GPIO 检查：监测 GPIO 端口状态变化，验证 LED 跑马灯序列
- PASS/FAIL 计数汇总

### 8.3 仿真环境

- 仿真器：Vivado XSim（行为级仿真）
- 自动化工具：Vivado Orchestrator（Python 驱动，替代 `vivado_do.tcl`）
  - 会话隔离并行：不同任务可同时运行独立 Vivado 进程
  - 分层哈希增量刷新：RTL/TB/COE/FPGA 四层独立检测，仅 COE 变更时秒级刷新
  - 批处理模式：`-batch "isa_*"` 一条命令并行仿真多任务
  - 配置驱动 IP 生成：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL
- 程序加载：`$readmemh` 在 elaboration 阶段将 hex 文件加载至 Sram BRAM IP
- hex/coe 文件由 `tools/rv2coe.py` 从 RISC-V 汇编源码编译生成（`--base-addr 0x80000000`）
- BRAM 行为模型：0-cycle 读延迟，不精确模拟碰撞行为

### 8.4 已知限制

- **BRAM 读延迟**：仿真中 BRAM 行为模型为组合输出（0-cycle），硬件中为寄存输出（1-cycle），仿真通过不代表硬件时序正确。Cache/TLB 控制器已新增 S_TAG_READ 等状态处理 BRAM 延迟
- **SRAM 地址空间**：SRAM 从设备仅 32KB（8192 字），地址范围 `0x8000_0000` ~ `0x8000_7FFC`
- **Cache 容量**：ICache/DCache 各 1KB（8 组 × 4 路 × 32 字节），大工作集程序可能频繁缺失
- **TLB 容量**：4 路 × 4 组 = 16 项，大工作集或频繁上下文切换可能 TLB 抖动
- **SRAM 字节写**：当前 `byte_enable: false`，SRAM 仅支持整字写，不支持 SB/SH 直写（需经 DCache 写分配）

---

## 9. 文件清单

### 9.1 RTL 源文件

| 目录 | 文件 | 说明 |
|------|------|------|
| `dev/rtl/` | `system_top.sv` | 系统顶层（CPU + 总线 + LCD） |
| `dev/rtl/core/` | `core_top.sv` | CPU 核心顶层 |
| `dev/rtl/core/` | `cpu_controller.sv` | FSM 控制器 |
| `dev/rtl/core/` | `cpu_fetch.sv` | 取指级 |
| `dev/rtl/core/` | `cpu_decode.sv` | 译码级 |
| `dev/rtl/core/` | `cpu_execute.sv` | 执行级 |
| `dev/rtl/core/` | `cpu_mem.sv` | 访存级 |
| `dev/rtl/core/` | `cpu_wb.sv` | 回写级 |
| `dev/rtl/core/` | `cpu_regfile.sv` | 寄存器堆 |
| `dev/rtl/core/` | `op_regroup.sv` | 指令重组/立即数解码 |
| `dev/rtl/core/` | `branch_comparator.sv` | 分支条件比较器 |
| `dev/rtl/core/` | `cpu_trap_csr.sv` | 陷阱/CSR 顶层 |
| `dev/rtl/core/` | `cpu_trap_manager.sv` | 陷阱管理器 |
| `dev/rtl/core/` | `cpu_clint.sv` | 核心本地中断控制器 |
| `dev/rtl/core/` | `cpu_csr_interface.sv` | CSR 读写接口 |
| `dev/rtl/core/` | `cpu_csr.sv` | CSR 寄存器文件 |
| `dev/rtl/core/` | `cache_def.svh` | Cache/TLB 几何常量（**自动生成**，勿手动编辑） |
| `dev/rtl/core/` | `icache_ctrl.sv` | 指令缓存控制器（4路组相联，VIPT，Tree-PLRU） |
| `dev/rtl/core/` | `dcache_ctrl.sv` | 数据缓存控制器（4路组相联，写回+写分配，VIPT） |
| `dev/rtl/core/` | `tree_plru.sv` | Tree-PLRU 替换策略（4路，3-bit 状态） |
| `dev/rtl/core/` | `MMU.sv` | Sv32 虚拟内存（TLB + PTW） |
| `dev/rtl/core/` | `tlb.sv` | TLB（4路×4组=16项，BRAM存储，ASID感知，Tree-PLRU） |
| `dev/rtl/core/` | `ptw.sv` | Sv32 页表漫游器 |
| `dev/rtl/core/` | `cpu_bus_bridge.sv` | AHB-Lite 总线桥接（MMIO + INCR8 突发） |
| `dev/rtl/ALU/` | `alu_32bit.sv` | 32-bit ALU 顶层 |
| `dev/rtl/ALU/` | `cla_adder_4bit.sv` | 4-bit CLA |
| `dev/rtl/ALU/` | `cla_adder_16bit.sv` | 16-bit CLA |
| `dev/rtl/ALU/` | `cla_adder_32bit.sv` | 32-bit CLA |
| `dev/rtl/ALU/` | `logic_unit.sv` | 逻辑/比较单元 |
| `dev/rtl/ALU/` | `shifter.sv` | 桶形移位器 |
| `dev/rtl/ALU/` | `lui.sv` | LUI 直通 |
| `dev/rtl/ALU/` | `mux.sv` | 多路选择器 |
| `dev/rtl/ALU/` | `alu_result_selector.sv` | ALU 结果选择器 |
| `dev/rtl/MU/` | `mu_unit.sv` | 乘除法单元 |
| `dev/rtl/MU/` | `booth_multiplier.sv` | Booth 乘法器 |
| `dev/rtl/MU/` | `non_restoring_divider.sv` | 非恢复余数除法器 |
| `dev/rtl/AHB-lite/` | `ahb_lite_bus.sv` | AHB-Lite 总线 |
| `dev/rtl/AHB-lite/` | `ahb_decoder.sv` | 地址译码器 |
| `dev/rtl/AHB-lite/` | `ahb_mux.sv` | 数据多路复用 |
| `dev/rtl/AHB-lite/` | `ahb_sram_slave.sv` | SRAM 从设备（32KB，INCR8 突发） |
| `dev/rtl/AHB-lite/` | `ahb_default_slave.sv` | 默认从设备（未映射地址返回 ERROR） |
| `dev/rtl/AHB-lite/` | `ahb_clint.sv` | CLINT 从设备 |
| `dev/rtl/AHB-lite/` | `ahb_plic.sv` | PLIC 从设备 |
| `dev/rtl/APB/` | `ahb_lite_to_apb.sv` | AHB→APB 桥 |
| `dev/rtl/APB/` | `apb_bus.sv` | APB 总线 |
| `dev/rtl/APB/` | `apb_master.sv` | APB 主设备 |
| `dev/rtl/APB/` | `apb_slave.sv` | APB 从设备 |
| `dev/rtl/APB/` | `apb_decoder.sv` | APB 地址译码 |
| `dev/rtl/APB/perips/` | `apb_perips.sv` | 外设顶层 |
| `dev/rtl/APB/perips/` | `gpio.sv` | GPIO（16-bit 双向 IO，引脚变化中断） |
| `dev/rtl/APB/perips/` | `uart_top.sv` | UART（TX/RX FIFO，中断，可配波特率） |
| `dev/rtl/APB/perips/` | `uart_tx.sv` | UART 发送（可配波特率） |
| `dev/rtl/APB/perips/` | `uart_rx.sv` | UART 接收（可配波特率） |
| `dev/rtl/APB/perips/` | `timer.sv` | 定时器 |
| `dev/rtl/APB/perips/` | `spi.sv` | SPI（主模式，传输完成中断） |
| `dev/rtl/APB/perips/` | `sync_fifo.sv` | 参数化同步 FIFO |

**BRAM IP 核**（由 `vivado_config.yaml` 配置驱动，`ip_gen.py` 动态生成 create_ip TCL）：

| BRAM IP | 配置 | 用途 |
|---------|------|------|
| `Sram` | 32-bit × 8192，True Dual Port | SRAM 主存储器（32KB） |
| `icached` | 256-bit × 32，True Dual Port，Byte_Enable | ICache 数据存储 |
| `dcached` | 256-bit × 32，True Dual Port，Byte_Enable | DCache 数据存储 |
| `icachet` | 32-bit × 8，True Dual Port，Byte_Enable(Byte_Size=8) | ICache 标签存储 |
| `dcachet` | 36-bit × 8，True Dual Port，Byte_Enable(Byte_Size=9) | DCache 标签存储 |
| `tlb_flag` | 128-bit × 4，True Dual Port，Byte_Enable(Byte_Size=8) | TLB 标志存储 |
| `tlb_data` | 128-bit × 4，True Dual Port，Byte_Enable(Byte_Size=8) | TLB 数据存储 |

### 9.2 Testbench 文件

| 文件 | 说明 |
|------|------|
| `dev/tb/tb_simple_cpu_top.sv` | 完整指令集测试 |
| `dev/tb/tb_simple_cpu_compute.sv` | 计算密集测试 |
| `dev/tb/tb_simple_cpu_trap.sv` | 异常/中断测试 |
| `dev/tb/tb_simple_cpu_priv.sv` | M/S/U 特权模式测试 |
| `dev/tb/tb_ahb_bus.sv` | AHB 总线测试 |
| `dev/tb/tb_apb_perips.sv` | APB 外设测试 |
| `dev/tb/tb_uart_hello.sv` | UART 输出测试 |
| `dev/tb/tb_led_marquee.sv` | LED 跑马灯测试 |
| `dev/tb/ALU/tb_non_restoring_divider.sv` | 除法器单元测试 |
| `dev/tb/ALU/tb_mu_unit.sv` | 乘除法单元测试 |
| `dev/tb/ALU/tb_alu_cpu_integration.sv` | ALU 集成测试 |

---

## 10. 设计特点总结

1. **多周期 FSM 控制**：非传统流水线，由状态机逐级推进，每周期仅一级活跃，简化数据冒险处理
2. **级间总线打包**：使用位拼接传递控制信号与数据，减少端口数量，但牺牲可读性
3. **CLA 超前进位加法器**：4-bit → 16-bit → 32-bit 级联，降低进位延迟
4. **桶形移位器**：5 级级联（1/2/4/8/16），单周期完成任意移位
5. **Booth 乘法器**：Radix-2 Booth 编码，32 周期迭代，支持有符号/无符号
6. **非恢复余数除法器**：32 周期迭代 + 修正阶段，处理除零/溢出/符号
7. **完整陷阱处理**：支持 11 种异常 + 3 种中断，符合 RISC-V 特权规范
8. **M/S/U 三级特权模式**：支持陷阱委托（medeleg/mideleg），S-mode 独立陷阱向量与 CSR
9. **Sv32 二级页表虚拟内存**：硬件页表漫游（PTW），16 项 4 路×4 组组相联 TLB，ASID 感知
10. **SRET/SFENCE.VMA/fence.i 指令**：S-mode 陷阱返回、TLB 刷新、icache 失效 + dcache 写回
11. **硬件管理 A/D 位**：PTW 自动写回 PTE 的访问位和脏位
12. **4 路组相联缓存**：ICache/DCache 各 1KB（8 组 × 4 路 × 32B 行），BRAM 标签存储
13. **Tree-PLRU 替换**：3-bit 状态编码，无效路优先，近似 LRU 替换策略（Cache 和 TLB 均使用）
14. **写回 + 写分配**：Store 命中仅写 BRAM + 置 dirty，缺失先 Refill 再合并写入，脏行驱逐写回主存
15. **INCR8 突发传输**：Cache Refill/Writeback 使用 AHB INCR8 突发，8 拍传输整行 256-bit 数据
16. **MMIO 旁路**：`vaddr[31]==0` 直接走 AHB 总线，不经过缓存，保证外设访问强序
17. **VIPT（Virtually-Indexed Physically-Tagged）**：Cache 使用虚拟地址的页内偏移位索引，物理地址标签比较，避免 MMU 翻译延迟
18. **BRAM-based 标签存储**：Tag 使用 BRAM IP（icachet/dcachet），byte-write enable 支持单路更新，S_TAG_READ 状态处理 1-cycle 读延迟
19. **BRAM-based TLB**：4 路×4 组组相联，tlb_flag/tlb_data 双 BRAM，双端口（i-side/d-side），Tree-PLRU 替换
20. **AHB-Lite + APB 双总线**：高速设备挂 AHB，低速外设挂 APB，通过桥接互联
21. **AHB Default Slave**：未映射地址返回 ERROR 响应，防止总线挂死
22. **总线桥优先级**：MMIO > PTW > Writeback > IRefill > DRefill，防止饿死与脏行堆积
23. **数据 MMU translate_en 门控**：mem_en 同步控制 Sv32 翻译使能，消除组合信号竞争
24. **配置驱动存储几何**：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL，IP 与 RTL 常量自动同步
25. **外设中断路由**：UART/SPI/GPIO 中断输出经 PLIC 路由至 CPU（src[2]=UART, src[3]=SPI, src[4]=GPIO）
26. **UART TX/RX FIFO**：各 16 字节同步 FIFO 缓冲，支持连续收发不丢数据
27. **UART 可配波特率**：BAUD 寄存器运行时设置分频系数，0 回退默认 115200
28. **GPIO 引脚变化中断**：逐引脚中断使能掩码 + 写 1 清除挂起状态
29. **SPI 传输完成中断**：CTRL[4] 中断使能，传输完成置挂起，写 STATUS 清除
30. **CLINT 可写 msip**：msip 寄存器（偏移 0x10）支持软件中断，符合 RISC-V CLINT 规范
