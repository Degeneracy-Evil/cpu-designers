# SimpleCPU 设计报告

> 生成日期: 2026-05-20 | 项目路径: `dev/rtl/`

---

## 1. 项目概述

本项目实现了一个基于 RISC-V RV32IM 指令集的多周期 CPU，采用五级流水线结构（取指-译码-执行-访存-回写），通过有限状态机（FSM）控制器协调各级运行。CPU 通过 AHB-Lite 总线连接片上存储与外设，支持异常/中断陷阱处理、CSR 读写、M 扩展乘除法运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32IM（整数 + 乘除法） |
| 架构 | 多周期 FSM 控制，五级流水线数据通路 |
| 数据位宽 | 32-bit |
| 地址空间 | 32-bit，虚拟地址直通（MMU 恒等映射） |
| 存储架构 | 哈佛结构（icache / dcache 分离），4 路组相联，Tree-PLRU 替换 |
| 缓存策略 | 写回（write-back）+ 写分配（write-allocate），脏行驱逐写回主存 |
| 总线接口 | AHB-Lite Master，支持 INCR8 突发传输 |
| 中断/异常 | 支持 Trap 进入/返回（mret）、CLINT 定时器中断、PLIC 外部中断 |
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
| 系统 | `ECALL`, `EBREAK`, `MRET`, `FENCE`, `FENCE.I`, `WFI` |
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
│   ├── icache_ctrl       ← 指令缓存控制器（4路组相联）
│   │   ├── tree_plru     ← Tree-PLRU 替换策略
│   │   └── icached       ← ICache 数据 BRAM IP（256bit×32）
│   ├── dcache_ctrl       ← 数据缓存控制器（4路组相联，写回+写分配）
│   │   ├── tree_plru     ← Tree-PLRU 替换策略
│   │   ├── dcached       ← DCache 数据 BRAM IP（256bit×32）
│   │   └── dtag          ← DCache 标签 BRAM IP（9bit×32）
│   ├── MMU (×2)          ← 地址映射（恒等）
│   └── cpu_bus_bridge    ← AHB-Lite 总线桥接（MMIO + INCR8 突发）
├── ahb_lite_bus          ← AHB-Lite 总线
│   ├── ahb_sram_slave    ← SRAM 从设备（32KB BRAM IP）
│   ├── ahb_clint         ← CLINT
│   ├── ahb_plic          ← PLIC
│   └── ahb_lite_to_apb → apb_bus → apb_perips
│       ├── GPIO
│       ├── UART (TX/RX)
│       ├── Timer
│       └── SPI
└── lcd_module            ← LCD 调试显示
```

### 2.2 地址映射

| 地址高位 | 从设备 | 说明 |
|----------|--------|------|
| `0x80_xxxx_xxxx` | SRAM Slave | 主存储器（32KB，缓存映射区域） |
| `0x02_xxxx_xxxx` | CLINT | 核心本地中断器 |
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
| 非法指令 | 译码级 | 2 |
| ECALL | 译码级 | 11 |
| EBREAK | 译码级 | 3 |
| 指令地址对齐 | 执行级 | 0 |
| Load 地址对齐 | 访存级 | 4 |
| Store 地址对齐 | 访存级 | 6 |

**中断检测**（`cpu_clint`）：

| 中断源 | Interrupt Code | 优先级 |
|--------|----------------|--------|
| 外部中断（MEIE & MEIP） | 0x8000_000B | 最高 |
| 软件中断（MSIE & MSIP） | 0x8000_0003 | 中 |
| 定时器中断（MTIE & MTIP） | 0x8000_0007 | 低 |

中断使能条件：`mstatus.MIE == 1` 且对应 `mie` 位为 1 且 `mip` 位为 1。

**Trap 进入**：

1. 保存 `mepc = exception_pc`（异常）或 `interrupt_pc`（中断）
2. 保存 `mcause`
3. 保存 `mtval`
4. 更新 `mstatus`：`MPP = 11`（Machine），`MPIE = MIE`，`MIE = 0`
5. 跳转到 `mtvec`（仅支持 Direct 模式）

**Trap 返回（MRET）**：

1. 恢复 `MIE = MPIE`
2. 跳转到 `mepc`

### 4.2 CSR 寄存器 (`cpu_csr`)

| CSR 地址 | 名称 | 可写 | 说明 |
|----------|------|------|------|
| 0x300 | mstatus | 是 | MPP/MPIE/MIE |
| 0x301 | misa | 否 | 硬连线 `0x40001100`（RV32IM） |
| 0x304 | mie | 是 | MEIE/MTIE/MSIE |
| 0x305 | mtvec | 是 | Trap 向量基址 |
| 0x310 | mstatush | 否 | 硬连线 0 |
| 0x340 | mscratch | 是 | 临时寄存器 |
| 0x341 | mepc | 是 | 异常/中断返回 PC |
| 0x342 | mcause | 是 | 异常/中断原因 |
| 0x343 | mtval | 是 | 异常附加信息 |
| 0x344 | mip | 否 | MEIP/MTIP/MSIP（硬件写入） |
| 0xB00 | mcycle | 是 | 时钟周期计数器低 32 位 |
| 0xB02 | minstret | 是 | 指令退休计数器低 32 位 |
| 0xB80 | mcycleh | 是 | 时钟周期计数器高 32 位 |
| 0xB82 | minstreth | 是 | 指令退休计数器高 32 位 |
| 0xF11-0xF15 | mvendorid 等 | 否 | 硬连线 0 |

CSR 写掩码：mstatus 仅允许写 MPP[12:11]、MIE[3]、MPIE[7]；mie 仅允许写 MEIE[11]、MTIE[7]、MSIE[3]；mtvec/mepc 强制低 2 位为 0。

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

### 5.3 标签存储

标签使用寄存器数组（非 BRAM），实现单周期 4 路并行比较：

| 缓存 | 标签格式 | 位宽 | 说明 |
|------|----------|------|------|
| ICache | `{valid, tag[6:0]}` | 8-bit | 无脏位（指令缓存只读） |
| DCache | `{valid, dirty, tag[6:0]}` | 9-bit | dirty 位标识写回需求 |

- 每组 4 路标签寄存器，共 8 组 × 4 路 = 32 个标签项
- 命中判定：`valid && (tag == addr[14:8])`，4 路并行，1 周期出结果

### 5.4 数据存储（BRAM IP）

| BRAM | 配置 | 端口 A | 端口 B |
|------|------|--------|--------|
| icached | 256-bit × 32，True Dual Port，WRITE_FIRST | CPU 读 | Refill 写 |
| dcached | 256-bit × 32，True Dual Port，WRITE_FIRST | CPU 读/写 | Refill 写 / Victim 读 |
| dtag | 9-bit × 32，True Dual Port，WRITE_FIRST | CPU 读/写 | Refill 写 |

BRAM 地址映射：`bram_addr = {set_idx[2:0], way[1:0]}`，5-bit 寻址 32 项。

**BRAM 读延迟差异**：
- 仿真：BRAM 行为模型提供组合输出（0-cycle 延迟）
- 硬件：`READ_LATENCY=1`，寄存输出（1-cycle 延迟）
- 仿真通过不代表硬件时序正确，综合时需关注

### 5.5 指令缓存控制器 (`icache_ctrl`)

ICache FSM 状态转换：

```
S_IDLE → S_READ (BRAM 使能，锁存请求)
S_READ → hit:  返回数据，更新 PLRU，回 S_IDLE
S_READ → miss: 锁存 set/addr/victim，发 refill_req，进 S_REFILL
S_REFILL:      保持 refill_req，等 refill_valid，写 BRAM PortB，
               更新标签+PLRU，旁路返回数据，回 S_IDLE
```

- MMIO 旁路：`addr[31]==0` 时直接发 AHB 请求，不经过缓存
- 标签比较在 S_READ 完成，命中时 1 周期返回（仿真）或 2 周期（硬件）
- 缺失时向 `cpu_bus_bridge` 发 INCR8 读突发请求，8 拍填充整行

### 5.6 数据缓存控制器 (`dcache_ctrl`)

DCache FSM 状态转换：

```
S_IDLE → store hit:  写 BRAM PortA，置 dirty，更新 PLRU，ready=1
S_IDLE → load hit:   进 S_READ_HIT
S_IDLE → miss:       锁存请求，若 victim dirty → S_WB_READ，否则 → S_REFILL
S_READ_HIT:          返回 BRAM 数据，更新 PLRU，回 S_IDLE
S_WB_READ:           使能 BRAM PortB 读，重构 WB 地址，进 S_WB_SEND
S_WB_SEND:           保持 wb_req，等 wb_valid，清 dirty，发 refill_req，进 S_REFILL
S_REFILL:            保持 refill_req，等 refill_valid，写 BRAM PortB
                     （store miss 时合并写入数据），更新标签+PLRU，旁路返回，回 S_IDLE
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
- 写使能：1-bit（Sram IP 仅支持整字写）
- 基地址：`0x8000_0000`（地址译码 `HADDR[31:24] == 8'h80`）
- 支持 INCR8 突发读写，1 等待状态

### 5.9 MMU

当前为恒等映射（`paddr = vaddr`），为未来虚拟地址扩展预留接口。

---

## 6. 总线与外设

### 6.1 AHB-Lite 总线 (`ahb_lite_bus`)

- 4 个从设备：SRAM、CLINT、PLIC、APB Bridge
- 地址译码：按 `HADDR[31:24]` 选择从设备
- 多路复用器回读数据与响应
- 参数化：地址宽度、数据宽度、从设备数、SRAM 深度、等待状态数

### 6.2 APB 总线与外设

通过 AHB-Lite to APB 桥接访问：

| 外设 | 说明 |
|------|------|
| GPIO | 16-bit 双向 IO |
| UART | 发送/接收，参数化频率 |
| Timer | 32-bit 定时器，产生中断 |
| SPI | 主模式 SPI 控制器 |

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

- 仿真器：Vivado XSim 2018.3（行为级仿真）
- 自动化脚本：`vivado_do.tcl`（工程创建/刷新/仿真/综合/实现/下载一体化）
- 程序加载：`$readmemh` 在 elaboration 阶段将 hex 文件加载至 Sram BRAM IP
- hex 文件由 `tools/rv2coe.py` 从 RISC-V 汇编源码编译生成（`--base-addr 0x80000000`）
- BRAM 行为模型：0-cycle 读延迟，不精确模拟碰撞行为

### 8.4 已知限制

- **BRAM 读延迟**：仿真中 BRAM 行为模型为组合输出（0-cycle），硬件中为寄存输出（1-cycle），仿真通过不代表硬件时序正确
- **SRAM 地址空间**：SRAM 从设备仅 32KB（8192 字），地址范围 `0x8000_0000` ~ `0x8000_7FFC`
- **Cache 容量**：ICache/DCache 各 1KB（8 组 × 4 路 × 32 字节），大工作集程序可能频繁缺失

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
| `dev/rtl/core/` | `icache_ctrl.sv` | 指令缓存控制器（4路组相联，Tree-PLRU） |
| `dev/rtl/core/` | `dcache_ctrl.sv` | 数据缓存控制器（4路组相联，写回+写分配） |
| `dev/rtl/core/` | `tree_plru.sv` | Tree-PLRU 替换策略（4路，3-bit 状态） |
| `dev/rtl/core/` | `MMU.sv` | 地址映射（恒等） |
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
| `dev/rtl/AHB-lite/` | `ahb_clint.sv` | CLINT 从设备 |
| `dev/rtl/AHB-lite/` | `ahb_plic.sv` | PLIC 从设备 |
| `dev/rtl/APB/` | `ahb_lite_to_apb.sv` | AHB→APB 桥 |
| `dev/rtl/APB/` | `apb_bus.sv` | APB 总线 |
| `dev/rtl/APB/` | `apb_master.sv` | APB 主设备 |
| `dev/rtl/APB/` | `apb_slave.sv` | APB 从设备 |
| `dev/rtl/APB/` | `apb_decoder.sv` | APB 地址译码 |
| `dev/rtl/APB/perips/` | `apb_perips.sv` | 外设顶层 |
| `dev/rtl/APB/perips/` | `gpio.sv` | GPIO |
| `dev/rtl/APB/perips/` | `uart_top.sv` | UART |
| `dev/rtl/APB/perips/` | `uart_tx.sv` | UART 发送 |
| `dev/rtl/APB/perips/` | `uart_rx.sv` | UART 接收 |
| `dev/rtl/APB/perips/` | `timer.sv` | 定时器 |
| `dev/rtl/APB/perips/` | `spi.sv` | SPI |

### 9.2 Testbench 文件

| 文件 | 说明 |
|------|------|
| `dev/tb/tb_simple_cpu_top.sv` | 完整指令集测试 |
| `dev/tb/tb_simple_cpu_compute.sv` | 计算密集测试 |
| `dev/tb/tb_simple_cpu_trap.sv` | 异常/中断测试 |
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
7. **完整陷阱处理**：支持 6 种异常 + 3 种中断，符合 RISC-V 特权规范
8. **4 路组相联缓存**：ICache/DCache 各 1KB（8 组 × 4 路 × 32B 行），寄存器标签并行比较
9. **Tree-PLRU 替换**：3-bit 状态编码，无效路优先，近似 LRU 替换策略
10. **写回 + 写分配**：Store 命中仅写 BRAM + 置 dirty，缺失先 Refill 再合并写入，脏行驱逐写回主存
11. **INCR8 突发传输**：Cache Refill/Writeback 使用 AHB INCR8 突发，8 拍传输整行 256-bit 数据
12. **MMIO 旁路**：`addr[31]==0` 直接走 AHB 总线，不经过缓存，保证外设访问强序
13. **AHB-Lite + APB 双总线**：高速设备挂 AHB，低速外设挂 APB，通过桥接互联
14. **总线桥优先级**：MMIO > Writeback > IRefill > DRefill，防止饿死与脏行堆积
