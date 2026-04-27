# SimpleCPU 设计与实现报告

> 生成日期：2026-04-26
> 项目路径：`dev/2-simpleCPU/`
> 当前分支：`busip`

---

## 1. 项目概述

SimpleCPU 是一个基于 RISC-V RV32I 指令集的**多周期处理器**实现，采用经典五级流水线结构（取指-译码-执行-访存-回写）但以**多周期串行**方式运行——每个时钟周期仅激活一个流水级，指令在多个周期内依次通过各阶段完成执行。

该项目已完成从内部 BRAM 直连模型到 **Bus4LZU 总线接口模型**的迁移，支持通过外部总线控制器访问存储器与外设（UART/SPI/GPIO/Timer），并实现了完整的 CSR 寄存器、异常处理与中断响应机制。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32I (40条) + Zicsr (6条) + Zifencei (1条) = 47条 |
| 架构 | 多周期五级流水（IF→ID→EXE→MEM→WB） |
| 数据宽度 | 32位地址、32位数据 |
| 存储器接口 | Bus4LZU 总线（4位字节写掩码、1周期读延迟） |
| 特权模式 | 仅 Machine 模式 |
| CSR | mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip (8个) |
| 异常 | 非法指令、ECALL、EBREAK、地址未对齐 |
| 中断 | Timer 外部中断 (MEIP)、软件中断 (MSIP) |
| FPGA | Xilinx 7系列，含 LCD 调试显示 |

---

## 2. 系统架构

### 2.1 顶层架构图

```
                    ┌─────────────────────────────────────────┐
                    │           simple_cpu_top                │
                    │                                         │
  clk ──────────────┤──┬────┬────┬────┬────┬────┬────┬────┐  │
  reset ────────────┤  │    │    │    │    │    │    │    │  │
                    │  │    │    │    │    │    │    │    │  │
  instData_32 ──────┤  │    │    │    │    │    │    │    │  │
  readData_32 ──────┤  │    │    │    │    │    │    │    │  │
  init_sig ─────────┤  │    │    │    │    │    │    │    │  │
  timer_irq ────────┤  │    │    │    │    │    │    │    │  │
                    │  F    D    E    M    W    C    L    R  │
  instAddr_32 ◄────┤  e    e    x    e    r    S    I    e  │
  dataWen_4 ◄──────┤  t    c    e    m    i    R    N    g  │
  dataAddr_32 ◄────┤  c    o    c    e    t    L    T    F  │
  writeData_32 ◄───┤  h    d    u    m    e    i    L    i  │
  data_req ◄───────┤       e    t    o         n    T    l  │
                    │            e              t    .    e  │
                    └─────────────────────────────────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    │           Bus4LZU 总线控制器           │
                    │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │
                    │  │ BRAM │ │ UART │ │ Timer│ │ SPI/ │ │
                    │  │(IMem │ │  RX/ │ │      │ │ GPIO │ │
                    │  │ DMem)│ │  TX) │ │      │ │      │ │
                    │  └──────┘ └──────┘ └──────┘ └──────┘ │
                    └───────────────────────────────────────┘
```

### 2.2 模块层次结构

```
simple_cpu_top
├── cpu_controller      # FSM 状态机控制器
├── cpu_fetch           # 取指阶段（1周期延迟）
├── cpu_decode          # 译码阶段
│   └── op_regroup      # 指令字段拆分与立即数生成
├── cpu_execute         # 执行阶段
│   ├── alu_32bit       # 32位ALU（外部共享模块）
│   └── branch_comparator  # 分支条件比较器
├── cpu_mem             # 访存阶段（字节掩码写入）
├── cpu_wb              # 回写阶段
├── cpu_regfile         # 32×32bit 寄存器堆
├── cpu_csr             # CSR 寄存器模块
└── cpu_clint           # 异常/中断控制逻辑
```

### 2.3 数据通路

模块间通过**总线寄存器**传递数据，级间设置触发器缓存以保证时序稳定：

| 总线名称 | 位宽 | 传递方向 | 主要字段 |
|----------|------|----------|----------|
| `if_id_bus` | 96位 | Fetch → Decode | pc_plus4[31:0], pc[31:0], inst[31:0] |
| `id_exe_bus` | 316位 | Decode → Execute | pc_plus4, 控制信号, ALU操作数, CSR信息, pc, inst |
| `exe_mem_bus` | 207位 | Execute → Mem | pc_plus4, ALU结果, 访存信息, CSR数据, pc, inst |
| `mem_wb_bus` | 168位 | Mem → Writeback | pc_plus4, 写回数据, CSR数据, pc, inst |

---

## 3. 各模块详细设计

### 3.1 cpu_controller — FSM 状态机控制器

**文件**：`rtl/cpu_controller.v`（135行）

**状态机设计**：9状态4位编码

| 状态 | 编码 | 说明 |
|------|------|------|
| STATE_IDLE | 0 | 空闲/复位 |
| STATE_FETCH | 1 | 取指 |
| STATE_DECODE | 2 | 译码 |
| STATE_EXEC | 3 | 执行 |
| STATE_MEM | 4 | 访存 |
| STATE_WB | 5 | 回写 |
| STATE_CSR_ACCESS | 6 | CSR 读写 |
| STATE_TRAP_ENTER | 7 | 异常/中断进入 |
| STATE_TRAP_RETURN | 8 | MRET 返回 |

**状态转移逻辑**：

```
IDLE → FETCH → DECODE → ┬→ EXEC → MEM → WB → FETCH (循环)
                          ├→ CSR_ACCESS → WB → FETCH
                          ├→ TRAP_ENTER → FETCH
                          ├→ TRAP_RETURN → FETCH
                          └→ FETCH (FENCE/NOP)
```

**init_sig 门控**：当 `init_sig=1` 时，所有状态转移强制到 IDLE，所有 `*_valid` 输出屏蔽，实现总线初始化期间的 CPU 冻结。

**中断检测点**：在 EXEC 完成（分支指令）和 WB 完成后检测 `trap_pending`，若有待响应中断则进入 TRAP_ENTER。

### 3.2 cpu_fetch — 取指阶段

**文件**：`rtl/cpu_fetch.v`（55行）

**设计要点**：
- 输出 `instAddr_32 = PC`（32位字节地址），替代原 11位字地址
- 输入 `instData_32` 来自总线，存在1周期读延迟
- 使用 `r_wait` 寄存器实现2周期取指：第1周期发地址，第2周期获取指令数据
- `init_sig=1` 时冻结 `r_wait=0`，`if_done` 永不为1

**时序**：
```
周期1: if_valid=1, r_wait=0 → if_done=0 (发地址)
周期2: if_valid=1, r_wait=1 → if_done=1 (得指令)
```

### 3.3 cpu_decode — 译码阶段

**文件**：`rtl/cpu_decode.v`（338行）

**功能**：
- 指令字段拆分（opcode/funct3/funct7/rs1/rs2/rd）
- 五种立即数生成（I/S/B/U/J型），均符号扩展
- 指令识别：RV32I 全部40条 + 6条CSR + ECALL/EBREAK/MRET/FENCE/FENCE.I
- ALU 操作数选择（源寄存器/立即数/PC）
- ALU 控制码生成（16位，区分 ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI）
- 分支类型与访存大小识别
- CSR 地址有效性检查（8个实现的CSR）

**非法指令判定**：`id_valid && !valid_inst`，其中 `valid_inst` 覆盖所有已实现指令。

### 3.4 cpu_execute — 执行阶段

**文件**：`rtl/cpu_execute.v`（231行）

**功能**：
- 调用 `alu_32bit` 执行算术逻辑运算
- 分支条件判断（通过 `branch_comparator`）
- 分支目标计算：JALR 结果清最低位 `(alu_result & ~3)`
- LUI 指令使用固定写回路径（`use_fixed_wb`），跳过 ALU
- CSR 新值计算（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI）
- CSR no-write 优化（rs1=0 或 uimm=0 时不写）

**握手协议**：使用 `req_valid`/`result_valid`/`result_ready` 与 ALU 交互，支持 ALU 多周期操作。

### 3.5 cpu_mem — 访存阶段

**文件**：`rtl/cpu_mem.v`（214行）

**状态机**：3状态

| 状态 | 说明 |
|------|------|
| MEM_IDLE | 等待访存请求 |
| MEM_READ | 等待读数据返回（1周期延迟） |
| MEM_WRITE | 写操作完成 |

**字节掩码写入逻辑**（`dataWen_4[3:0]`，0=写，1=不写）：

| 指令 | byte_offset | 掩码 | 说明 |
|------|-------------|------|------|
| SB | 00 | 1110 | 写byte0 |
| SB | 01 | 1101 | 写byte1 |
| SB | 10 | 1011 | 写byte2 |
| SB | 11 | 0111 | 写byte3 |
| SH | 00 | 1100 | 写半字低16位 |
| SH | 10 | 0011 | 写半字高16位 |
| SW | xx | 0000 | 写全部32位 |
| LOAD | xx | 1111 | 读操作标识 |

**读数据提取**：
- LB/LBU：按 `byte_offset` 选择对应字节，LB 符号扩展，LBU 零扩展
- LH/LHU：按 `byte_offset[1]` 选择高低半字，LH 符号扩展，LHU 零扩展
- LW：直接使用 `readData_32`

**未对齐检测**：LH/LHU 地址 bit0 非0、LW/SW 地址 bit[1:0] 非0 时触发异常。

### 3.6 cpu_wb — 回写阶段

**文件**：`rtl/cpu_wb.v`（41行）

**功能**：
- 通用寄存器写回：`rf_wen = wb_valid && wb_we`
- CSR 结果选择：`is_csr` 时使用 `csr_rdata`，否则使用 `wb_data`
- JAL/JALR 写回值：PC+4（在顶层通过 `wb_is_jal_like` 选择）

### 3.7 cpu_regfile — 寄存器堆

**文件**：`rtl/cpu_regfile.v`（34行）

- 32个32位寄存器 `rf[0:31]`
- x0 硬连线为0（读取返回0，写入忽略）
- 异步读、同步写
- 调试端口 `dbg_raddr`/`dbg_rdata` 供外部观察

### 3.8 cpu_csr — CSR 寄存器模块

**文件**：`rtl/cpu_csr.v`（118行）

**实现的 CSR 寄存器**：

| 地址 | 名称 | 读写 | 说明 |
|------|------|------|------|
| 0x300 | mstatus | MRW | MIE[3], MPIE[7], MPP[12:11] |
| 0x304 | mie | MRW | MSIE[3], MTIE[7], MEIE[11] |
| 0x305 | mtvec | MRW | trap 向量基址 |
| 0x340 | mscratch | MRW | 暂存寄存器 |
| 0x341 | mepc | MRW | 异常 PC |
| 0x342 | mcause | MRW | 异常原因 |
| 0x343 | mtval | MRW | 异常附加值 |
| 0x344 | mip | MR | MEIP[11], MSIP[3] 由硬件驱动 |

**双写端口**：
- 软件写（`sw_csr_wen`）：CSR 指令触发
- 硬件写（`hw_csr_wen`）：trap 进入/返回时自动更新 mepc/mcause/mtval/mstatus

**mip 硬件驱动**：`w_mip_hw = {20'b0, ext_meip, 3'b0, 1'b0, 3'b0, ext_msip, 3'b0}`，MEIP=bit11, MSIP=bit3。

### 3.9 cpu_clint — 异常/中断控制逻辑

**文件**：`rtl/cpu_clint.v`（68行）

**中断判定**：`mstatus.MIE && ((mie.MEIE && mip.MEIP) || (mie.MSIE && mip.MSIP))`

**trap 进入**：
- PC ← mtvec.BASE（Direct 模式）
- mepc ← 异常PC（异常）或当前PC（中断）
- mcause ← 异常/中断编码
- mstatus: MPIE←MIE, MIE←0, MPP←当前模式

**MRET 返回**：
- PC ← mepc
- mstatus: MIE←MPIE, MPIE←1, MPP←U

**异常优先级**：异常优先于中断；同一边界上的同步异常先处理。

### 3.10 辅助模块

#### op_regroup — 指令重组电路（`rtl/op_regroup.v`，50行）
- 拆分32位指令为 opcode/funct3/funct7/rs1/rs2/rd
- 生成五种立即数（I/S/B/U/J），均符号扩展

#### branch_comparator — 分支比较器（`rtl/branch_comparator.v`，25行）
- 支持 BEQ/BNE/BLT/BGE/BLTU/BGEU
- 有符号比较使用 `$signed`，无符号比较使用自然比较

---

## 4. 总线接口设计

### 4.1 Bus4LZU 接口信号

| 方向 | 信号 | 位宽 | 说明 |
|------|------|------|------|
| CPU→Bus | `instAddr_32` | 32 | 取指地址（字节地址=PC） |
| Bus→CPU | `instData_32` | 32 | 指令数据（1周期延迟） |
| CPU→Bus | `dataWen_4` | 4 | 字节写掩码（0=写，1=不写，1111=读） |
| CPU→Bus | `dataAddr_32` | 32 | 访存地址 |
| CPU→Bus | `writeData_32` | 32 | 写入数据 |
| Bus→CPU | `readData_32` | 32 | 读取数据（1周期延迟） |
| CPU→Bus | `data_req` | 1 | 数据请求使能 |
| Bus→CPU | `init_sig` | 1 | 初始化暂停信号 |
| Bus→CPU | `timer_irq` | 1 | Timer 中断信号 |

### 4.2 bus4lzu_mock — 仿真用总线代理

**文件**：`rtl/bus4lzu_mock.v`（107行）

仿真环境中替代真实 Bus4LZU IP 核，提供：

| 功能 | 实现 |
|------|------|
| 指令存储器 | 2KB BRAM (imem[0:2047])，$readmemh 初始化 |
| 数据存储器 | 2KB BRAM (dmem[0:2047])，支持4位字节写使能 |
| init_sig | 复位后100周期高电平，模拟 UART 加载 |
| Timer 外设 | 地址 0x10010000/4/8，含 counter/threshold/enable/ack |
| 地址过滤 | 0x1001xxxx 写入路由到 Timer，其余写入 dmem |
| 调试端口 | dbg_mem_addr/dbg_mem_data 供 testbench 观察 |

**Timer 地址映射**：

| 地址 | 功能 |
|------|------|
| 0x10010000 | timer_threshold（写） |
| 0x10010004 | timer_en（写，bit0） |
| 0x10010008 | timer_irq ack（写任意值清中断） |

---

## 5. 异常与中断机制

### 5.1 异常类型

| 异常 | mcause Code | 触发条件 |
|------|-------------|----------|
| 非法指令 | 2 | opcode/funct3/funct7 未定义，或 CSR 地址无效 |
| EBREAK | 3 | 执行 EBREAK 指令 |
| Load 地址未对齐 | 4 | LH/LHU bit0≠0，LW bit[1:0]≠0 |
| Store 地址未对齐 | 6 | SH bit0≠0，SW bit[1:0]≠0 |
| ECALL (M-mode) | 11 | M-mode 下执行 ECALL |

### 5.2 中断类型

| 中断 | mcause Code | 触发条件 |
|------|-------------|----------|
| Machine 软件中断 | 0x80000003 | mip.MSIP=1 && mie.MSIE=1 && mstatus.MIE=1 |
| Machine 外部中断 | 0x8000000B | mip.MEIP=1 && mie.MEIE=1 && mstatus.MIE=1 |

**中断源**：`ext_meip` 连接 `timer_irq`（来自 Bus4LZU 的 Timer 外设），电平触发（持续到软件 ack）。

### 5.3 异常检测点

- **Decode 阶段**：非法指令、ECALL、EBREAK
- **Mem 阶段**：Load/Store 地址未对齐
- **指令边界**：中断检测（在 EXEC 完成分支指令后、WB 完成后）

---

## 6. 测试验证

### 6.1 测试框架

| Testbench | 文件 | 测试内容 |
|-----------|------|----------|
| tb_simple_cpu_top | `tb/tb_simple_cpu_top.v` | 基础指令（33项） |
| tb_csr_test | `tb/tb_csr_test.v` | CSR + 异常（20项） |
| tb_timer_irq_test | `tb/tb_timer_irq_test.v` | Timer 中断（2项） |
| tb_align_test | `tb/tb_align_test.v` | 字节/半字对齐（23项） |

所有 testbench 统一结构：实例化 `simple_cpu_top` + `bus4lzu_mock`，通过 `check_reg`/`check_mem_word` 任务验证寄存器和存储器值。

### 6.2 测试程序

| 程序 | 文件 | 说明 |
|------|------|------|
| 基础测试 | `program_source/icache_init.s` | 算术/逻辑/分支/访存综合测试 |
| CSR 测试 | `program_source/csr_test.s` | CSR 读写 + ECALL/EBREAK/非法指令异常 |
| Timer 中断测试 | `program_source/timer_irq_test.s` | Timer 配置→等待中断→验证 mcause |
| 对齐测试 | `program_source/align_test.s` | sb/sh/lb/lh/lbu/lhu/sw/lw 全覆盖 |

### 6.3 验证结果

| 测试类别 | 检查项数 | 结果 |
|----------|----------|------|
| 基础指令 | 33 | ALL PASS |
| CSR + 异常 | 20 | ALL PASS |
| Timer 中断 | 2 | ALL PASS |
| 字节/半字对齐 | 23 | ALL PASS |
| **总计** | **78** | **ALL PASS** |

---

## 7. FPGA 集成

### 7.1 system_top — FPGA 顶层

**文件**：`fpga/system_top.v`（232行）

集成 CPU + Bus4LZU IP + LCD 显示模块：

```
system_top
├── bus4LZU_0          # Bus4LZU IP 核（Vivado IP）
├── simple_cpu_top     # CPU 核心
├── lcd_module         # LCD 触摸屏显示（.dcp 预编译）
└── BUFGCE             # 时钟门控（单步/连续切换）
```

**复位极性**：CPU 内部 `reset` 高有效，FPGA 板 `resetn` 低有效，顶层 `reset = ~resetn`。

**时钟控制**：`btn_clk` 按键实现单步调试，释放时连续运行。

### 7.2 LCD 显示项

| 编号 | 名称 | 内容 |
|------|------|------|
| 1 | IF_PC | 取指 PC |
| 2 | IF_IN | 取指指令 |
| 3 | ID_PC | 译码 PC |
| 4 | EXEPC | 执行 PC |
| 5 | MEMPC | 访存 PC |
| 6 | MEMIN | 访存指令 |
| 7 | WB_PC | 回写 PC |
| 8 | WB_IN | 回写指令 |
| 9 | DADDR | 总线数据地址 |
| 10 | DDATA | 总线读数据 |
| 11-42 | REGxx | 32个通用寄存器 |
| 43 | STATE | FSM 状态 |
| 44 | SW | 拨码开关 |

### 7.3 引脚约束

**文件**：`fpga/cpu.xdc`（139行）

约束覆盖：时钟(AC19)、复位(Y3)、单步按键(Y5)、8位拨码开关、LCD 触摸屏(16位数据+控制)、UART(RX:F23, TX:H19)、SPI(4线)、GPIO(16位扩展IO)。IO 标准均为 LVCMOS33。

---

## 8. 关键设计决策与演进

### 8.1 从 BRAM 直连到总线接口

| 方面 | 旧设计（BRAM 直连） | 新设计（Bus4LZU 总线） |
|------|---------------------|----------------------|
| 取指 | 组合逻辑，当周期完成 | 1周期延迟，2状态等待 |
| Store | read-modify-write (3周期) | 字节掩码直接写 (2周期) |
| Load | 当周期完成 (2状态) | 1周期读等待 (3状态) |
| 地址宽度 | 11位字地址 | 32位字节地址 |
| 写使能 | 1位字写使能 | 4位字节写掩码 |
| 外设 | 内部 UART 实例 | 总线统一编址 |
| 中断源 | UART RX → MEIP | Timer IRQ → MEIP |
| 初始化 | 直接 readmemh | init_sig 冻结100周期 |

### 8.2 已修复的关键 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| mip MEIP 位映射错误 | w_mip_hw 仅27位，零扩展后 MEIP 落在 bit6 | 扩展为32位，MEIP=bit11, MSIP=bit3 |
| interrupt_cause 编码错误 | {1'b1,27'd0,5'd11} = 33位，截断后 bit31=0 | 直接使用 32'h8000000B / 32'h80000003 |
| Timer IRQ 电平触发 | 原为单周期脉冲 | 改为持续高直到软件 ack (写0x10010008) |
| Store 误写寄存器 | MEM_WRITE 状态遗漏清除 wb_we_reg | 增加 wb_we_reg<=0; wb_data_reg<=0 |
| MRET 误判为非法指令 | inst_mret 匹配模式仅20位有效 | 扩展为完整25位匹配 |

---

## 9. 目录结构

```
dev/2-simpleCPU/
├── rtl/                          # RTL 源码
│   ├── simple_cpu_top.v          # 顶层模块 (468行)
│   ├── cpu_controller.v          # FSM 控制器 (135行)
│   ├── cpu_fetch.v               # 取指阶段 (55行)
│   ├── cpu_decode.v              # 译码阶段 (338行)
│   ├── cpu_execute.v             # 执行阶段 (231行)
│   ├── cpu_mem.v                 # 访存阶段 (214行)
│   ├── cpu_wb.v                  # 回写阶段 (41行)
│   ├── cpu_regfile.v             # 寄存器堆 (34行)
│   ├── cpu_csr.v                 # CSR 寄存器 (118行)
│   ├── cpu_clint.v               # 异常/中断控制 (68行)
│   ├── op_regroup.v              # 指令重组 (50行)
│   ├── branch_comparator.v       # 分支比较器 (25行)
│   ├── bus4lzu_mock.v            # 总线仿真代理 (107行)
│   ├── icache.v                  # iCache 行为模型 (45行, 不再实例化)
│   ├── dcache.v                  # dCache 行为模型 (41行, 不再实例化)
│   ├── uart_top.v                # UART 顶层 (130行, 不再实例化)
│   ├── simple_uart_rx.v          # UART 接收 (127行, 不再实例化)
│   └── simple_uart_tx.v          # UART 发送 (121行, 不再实例化)
├── tb/                           # 测试台
│   ├── tb_simple_cpu_top.v       # 基础指令测试 (175行)
│   ├── tb_csr_test.v             # CSR/异常测试 (178行)
│   ├── tb_timer_irq_test.v       # Timer 中断测试 (129行)
│   └── tb_align_test.v           # 对齐测试 (174行)
├── program_source/               # 测试程序
│   ├── icache_init.s/.hex/.coe   # 基础测试程序
│   ├── csr_test.s/.hex/.coe      # CSR 测试程序
│   ├── timer_irq_test.s/.hex     # Timer 中断测试程序
│   ├── align_test.s/.hex         # 对齐测试程序
│   └── comprehensive_test.*      # 综合测试程序
├── fpga/                         # FPGA 集成
│   ├── system_top.v              # FPGA 顶层 (232行)
│   ├── simple_cpu_display.v      # 显示模块 (253行, 旧版)
│   ├── cpu.xdc                   # 引脚约束 (139行)
│   ├── lcd_module.dcp            # LCD 预编译 IP
│   └── README.md
├── doc/                          # 文档
│   ├── instruction-set.md        # 指令集定义
│   ├── exception-interrupt.md    # 异常/中断机制
│   ├── 简单CPU项目描述.md         # 项目初始描述
│   └── simpleCPU-design-report.md # 本报告
├── PLAN.md                       # 总线接入计划
├── PROCESS.md                    # 开发进度记录
├── CODE_REVIEW_busip.md          # 代码审查报告
└── AGENTS.md                     # Agent 工作指引
```

---

## 10. 代码规模统计

| 类别 | 文件数 | 总行数 |
|------|--------|--------|
| RTL 核心模块 (活跃) | 12 | ~1,536 |
| RTL 保留模块 (不再实例化) | 5 | ~444 |
| Testbench | 4 | ~656 |
| FPGA | 3 | ~624 |
| 文档 | 5+ | ~1,200 |
| **合计** | **29** | **~4,460** |

---

## 11. 工具链

| 工具 | 用途 | 路径 |
|------|------|------|
| mk.py | 编译与仿真执行 | `tools/mk.py` |
| rv2coe.py | 汇编/C → HEX/COE/BIN | `tools/rv2coe.py` |
| Vivado | FPGA 综合/实现/Bitstream | 需独立安装 |

**仿真命令示例**：
```bash
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v
```

**程序编译命令示例**：
```bash
python3 tools/rv2coe.py -i dev/2-simpleCPU/program_source/test.S \
  -o dev/2-simpleCPU/program_source/icache_init.hex --depth 2048
```

---

## 12. 总结

SimpleCPU 是一个功能完整的 RV32I 多周期处理器，已实现：

1. **47条指令**：RV32I 基础40条 + Zicsr 6条 + Zifencei 1条
2. **完整异常处理**：非法指令、ECALL、EBREAK、地址未对齐，含 trap 进入/返回
3. **中断响应**：Timer 外部中断 (MEIP) + 软件中断 (MSIP)，电平触发
4. **总线接口**：Bus4LZU 4位字节掩码、1周期读延迟、init_sig 暂停控制
5. **78项测试全部通过**：基础33 + CSR/异常20 + Timer中断2 + 对齐23
6. **FPGA 验证就绪**：system_top + XDC 约束 + LCD 调试显示

该项目从简单的 BRAM 直连模型演进为总线接口模型，在保持功能正确性的同时获得了外设扩展能力，为后续接入更多 Bus4LZU 外设（SPI Flash、GPIO 扩展等）奠定了基础。
