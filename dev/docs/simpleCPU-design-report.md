# SimpleCPU 设计与实现报告

> 生成日期：2026-05-08
> 项目路径：`dev/`
> 当前分支：`wood-dev`

---

## 1. 项目概述

SimpleCPU 是一个基于 RISC-V RV32IM 指令集的**多周期处理器**实现，采用经典五级流水线结构（取指-译码-执行-访存-回写）但以**多周期串行**方式运行——每个时钟周期仅激活一个流水级，指令在多个周期内依次通过各阶段完成执行。

该项目已完成从内部 BRAM 直连模型到 **AHB-Lite + APB 两级总线架构**的迁移。CPU 通过 `cpu_bus_bridge` 直接驱动 AHB-Lite 总线信号，AHB-Lite 下挂 SRAM 从设备与 AHB-to-APB 桥，APB 总线下挂 GPIO/Timer/UART/SPI 四个外设。ICache/DCache 控制器支持 MMIO 旁路（地址 bit31=1 时直接访问总线），并实现了完整的 CSR 寄存器、异常处理与中断响应机制。M 扩展（乘除法）通过 Booth 乘法器与非恢复余数除法器实现，支持多周期运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32I (40条) + M (8条) + Zicsr (6条) + Zifencei (1条) = 55条 |
| 架构 | 多周期五级流水（IF→ID→EXE→MEM→WB） |
| 数据宽度 | 32位地址、32位数据 |
| 总线架构 | AHB-Lite (2从设备) → APB (4从设备) |
| Cache | ICache/DCache 控制器 + BRAM IP，MMIO 旁路 |
| 乘除法 | Booth 乘法器 + 非恢复余数除法器，多周期握手 |
| 特权模式 | 仅 Machine 模式 |
| CSR | mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip (8个) |
| 异常 | 非法指令、ECALL、EBREAK、地址未对齐 |
| 中断 | MEIP(外部)/MTIP(Timer)/MSIP(软件)，电平触发 |
| 系统时钟 | 100 MHz |
| 外设 | GPIO(16bit)/Timer/UART(RX+TX, 115200 baud)/SPI，APB 总线挂载 |
| FPGA | Xilinx 7系列，含 LCD 调试显示 |

---

## 2. 系统架构

### 2.1 顶层架构图

```
                        ┌──────────────────────────────────────────────┐
                        │              system_top                      │
                        │                                              │
  clk ──────────────────┤──┐                                           │
  resetn ───────────────┤  │                                           │
                        │  │  ┌─────────────────┐                      │
  sw[7:0] ──────────────┤  │  │ core_top   │                      │
  uart_rx/tx ───────────┤  │  │  IF→ID→EXE→MEM→WB│                      │
  spi_miso/mosi/ss/clk ─┤  │  │  CSR + CLINT     │                      │
  gpio_io[15:0] ────────┤  │  │  icache_ctrl     │                      │
                        │  │  │  dcache_ctrl     │                      │
                        │  │  │  MMU ×2          │                      │
                        │  │  └────────┬────────┘                      │
                        │  │           │ AHB-Lite (direct)              │
                        │  │  ┌────────┴────────┐                      │
                        │  │  │ cpu_bus_bridge   │                      │
                        │  │  │ (CPU→AHB direct) │                      │
                        │  │  └────────┬────────┘                      │
                        │  │           │ AHB-Lite                      │
                        │  │  ┌────────┴────────────────────────┐      │
                         │  │  │       ahb_lite_bus            │      │
                         │  │  │  ┌──────────────┐              │      │
                         │  │  │  │ahb_decoder   │              │      │
                         │  │  │  └──────┬───────┘              │      │
                         │  │  │         │ HSELx                │      │
                         │  │  │  ┌──────┴─────┐ ┌─────────────┐│      │
                         │  │  │  │ahb_sram  │ │ahb_lite_to  ││      │
                         │  │  │  │_slave    │ │_apb bridge  ││      │
                         │  │  │  │(SRAM IP) │ │             ││      │
                         │  │  │  └──────────┘ └──────┬──────┘│      │
                         │  │  └──────────────────────┼────────┘      │
                        │  │                          │ APB            │
                        │  │  ┌───────────────────────┴───────────┐    │
                        │  │  │          apb_perips               │    │
                        │  │  │  ┌────┐┌─────┐┌────┐┌─────┐    │    │
                        │  │  │  │GPIO││Timer││UART││ SPI  │    │    │
                        │  │  │  └────┘└─────┘└────┘└─────┘    │    │
                        │  │  └──────────────────────────────────┘    │
                        │  │                                           │
                        │  │  ┌─────────────────┐                      │
                        │  │  │ lcd_module (DCP) │                      │
                        │  │  └─────────────────┘                      │
                        │  └───────────────────────────────────────────┘
```

### 2.2 模块层次结构

```
system_top
├── core_top              # CPU 核心
│   ├── cpu_controller          # FSM 状态机控制器
│   ├── icache_ctrl             # ICache 控制器 (BRAM IP + MMIO 旁路)
│   │   └── icache              # ICache BRAM IP (Xilinx)
│   ├── cpu_fetch               # 取指阶段
│   ├── cpu_decode              # 译码阶段
│   │   └── op_regroup          # 指令字段拆分与立即数生成
│   ├── cpu_execute             # 执行阶段
│   │   ├── alu_32bit           # 32位ALU（外部共享模块）
│   │   ├── mu_unit             # 乘除法单元（M扩展）
│   │   │   ├── booth_multiplier  # Booth 乘法器
│   │   │   └── non_restoring_divider  # 非恢复余数除法器
│   │   └── branch_comparator   # 分支条件比较器
│   ├── dcache_ctrl             # DCache 控制器 (BRAM IP + MMIO 旁路)
│   │   └── dcache              # DCache BRAM IP (Xilinx)
│   ├── cpu_mem                 # 访存阶段（字节掩码写入）
│   ├── cpu_wb                  # 回写阶段
│   ├── cpu_regfile             # 32×32bit 寄存器堆
│   ├── cpu_trap_csr            # 异常/CSR 顶层封装
│   │   ├── cpu_trap_manager    # 异常检测与 trap 管理
│   │   │   └── cpu_clint       # 中断检测与 trap PC/mstatus 更新
│   │   └── cpu_csr_interface   # CSR 指令接口与新值计算
│   │       └── cpu_csr         # CSR 寄存器存储
│   ├── cpu_bus_bridge          # CPU→AHB-Lite 直接桥接
│   └── MMU ×2                  # 地址翻译 (当前直通)
├── ahb_lite_bus              # AHB-Lite 外设总线
│   ├── ahb_decoder             # AHB 地址译码 (2从设备)
│   ├── ahb_mux                 # AHB 读数据多路选择
│   ├── ahb_sram_slave          # AHB SRAM 从设备 (Sram IP)
│   │   └── Sram                # SRAM BRAM IP (Xilinx)
│   ├── ahb_lite_to_apb         # AHB-to-APB 桥
│   ├── apb_decoder             # APB 地址译码 (4从设备)
│   └── apb_perips              # APB 外设容器
│       ├── gpio                # GPIO (16bit 双向)
│       ├── timer               # 定时器 (含 IRQ)
│       ├── uart_top            # UART 顶层
│       │   ├── uart_rx         # UART 接收
│       │   └── uart_tx         # UART 发送
│       └── spi                 # SPI 主机
└── lcd_module                  # LCD 触摸屏显示 (DCP 预编译)
```

### 2.3 数据通路

模块间通过**总线寄存器**传递数据，级间设置触发器缓存以保证时序稳定：

| 总线名称 | 位宽 | 传递方向 | 主要字段 |
|----------|------|----------|----------|
| `if_id_bus` | 96位 | Fetch → Decode | pc_plus4[31:0], pc[31:0], inst[31:0] |
| `id_exe_bus` | 320位 | Decode → Execute | pc_plus4, 控制信号, ALU操作数, CSR信息, pc, inst |
| `exe_mem_bus` | 207位 | Execute → Mem | pc_plus4, ALU结果, 访存信息, CSR数据, pc, inst |
| `mem_wb_bus` | 168位 | Mem → Writeback | pc_plus4, 写回数据, CSR数据, pc, inst |

---

## 3. 各模块详细设计

### 3.1 cpu_controller — FSM 状态机控制器

**文件**：`rtl/core/cpu_controller.v`（133行）

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
                        ├→ EXEC → WB → FETCH (R/I-type 快速路径)
                        ├→ CSR_ACCESS → WB → FETCH
                        ├→ TRAP_ENTER → FETCH
                        ├→ TRAP_RETURN → FETCH
                        └→ FETCH (FENCE/NOP)
```

**init_sig 门控**：当 `init_sig=1` 时，所有状态转移强制到 IDLE，所有 `*_valid` 输出屏蔽，实现总线初始化期间的 CPU 冻结。

**中断检测点**：在 EXEC 完成（分支指令）和 WB 完成后检测 `trap_pending`，若有待响应中断则进入 TRAP_ENTER。

**exe_to_wb 快速路径**：R/I-type 运算指令跳过 MEM 阶段，EXEC 完成后直接写入 WB 总线，减少一个时钟周期。

### 3.2 icache_ctrl — ICache 控制器

**文件**：`rtl/core/icache_ctrl.v`（60行）

**设计要点**：

- 参数化深度 `DEPTH=4096`，12位索引 → 4KB 直接映射
- MMIO 旁路：`is_mmio = cpu_req_addr[31]`，地址 bit31=1 时绕过 Cache 直连总线
- Cache 命中：组合逻辑读 BRAM IP，下一周期 `icache_valid_r=1` 返回数据
- MMIO 访问：透传 `mmio_data`/`mmio_valid` 信号
- 输出 MUX：`cpu_req_data = is_mmio ? mmio_data : icache_dout`

### 3.3 dcache_ctrl — DCache 控制器

**文件**：`rtl/core/dcache_ctrl.v`（76行）

**设计要点**：

- 与 icache_ctrl 结构对称，额外支持写操作
- 字节写使能生成：根据 `cpu_req_hsize`（BYTE/HWORD/WORD）和地址低位生成 BRAM 字节掩码
- MMIO 旁路时透传 `mmio_wdata`/`mmio_hwrite`/`mmio_hsize`
- 非 MMIO 写操作时 `mmio_req=0`（不向总线发写请求）

### 3.4 MMU — 内存管理单元

**文件**：`rtl/core/MMU.v`（10行）

当前为直通模式 `paddr = vaddr`，为后续虚拟内存扩展预留接口。CPU 中实例化两个 MMU，分别用于取指地址和访存地址翻译。

### 3.5 cpu_fetch — 取指阶段

**文件**：`rtl/core/cpu_fetch.v`（30行）

**设计要点**：

- 输出 `instAddr_32 = PC`（32位字节地址）
- 输入 `instData_32` 来自 icache_ctrl，`inst_valid` 标识数据有效
- `if_done = if_valid && inst_valid`，当 icache 返回有效数据时完成取指
- 无内部等待状态，时序由 icache_ctrl 的 BRAM 延迟保证

### 3.6 cpu_decode — 译码阶段

**文件**：`rtl/core/cpu_decode.v`（360行）

**功能**：

- 指令字段拆分（opcode/funct3/funct7/rs1/rs2/rd）
- 五种立即数生成（I/S/B/U/J型），均符号扩展
- 指令识别：RV32I 全部40条 + M扩展8条 + 6条CSR + ECALL/EBREAK/MRET/FENCE/FENCE.I
- ALU 操作数选择（源寄存器/立即数/PC）
- ALU 控制码生成（16位，区分 ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI）
- M 扩展操作识别（MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU）
- 分支类型与访存大小识别
- CSR 地址有效性检查（8个实现的CSR）

**非法指令判定**：`id_valid && !valid_inst`，其中 `valid_inst` 覆盖所有已实现指令。

### 3.7 cpu_execute — 执行阶段

**文件**：`rtl/core/cpu_execute.v`（249行）

**功能**：

- 调用 `alu_32bit` 执行算术逻辑运算
- 调用 `mu_unit` 执行乘除法运算（M扩展）
- 分支条件判断（通过 `branch_comparator`）
- 分支目标计算：JALR 结果清最低位 `(alu_result & ~1)`
- LUI 指令使用固定写回路径（`use_fixed_wb`），跳过 ALU
- CSR 新值计算（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI）
- CSR no-write 优化（rs1=0 或 uimm=0 时不写）

**M 扩展多周期握手**：使用 `mu_req_valid`/`mu_result_valid` 与 `mu_unit` 交互，EX 阶段在 `mu_req_valid && !mu_result_valid` 时保持等待，直到乘除法器返回结果。

### 3.8 cpu_mem — 访存阶段

**文件**：`rtl/core/cpu_mem.v`（242行）

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

### 3.9 cpu_wb — 回写阶段

**文件**：`rtl/core/cpu_wb.v`（41行）

**功能**：

- 通用寄存器写回：`rf_wen = wb_valid && wb_we`
- CSR 结果选择：`is_csr` 时使用 `csr_rdata`，否则使用 `wb_data`
- JAL/JALR 写回值：PC+4（在顶层通过 `wb_is_jal_like` 选择）

### 3.10 cpu_regfile — 寄存器堆

**文件**：`rtl/core/cpu_regfile.v`（34行）

- 32个32位寄存器 `rf[0:31]`
- x0 硬连线为0（读取返回0，写入忽略）
- 异步读、同步写
- 调试端口 `dbg_raddr`/`dbg_rdata` 供外部观察

### 3.11 cpu_trap_csr — 异常/CSR 顶层封装

**文件**：`rtl/core/cpu_trap_csr.v`（109行）

将异常管理与 CSR 访问逻辑封装为统一模块，内部实例化：

- `cpu_trap_manager`：异常检测、中断判定、trap PC 生成、CSR 硬件写触发
- `cpu_csr_interface`：CSR 指令新值计算、CSR 写回总线生成

### 3.12 cpu_trap_manager — 异常检测与 trap 管理

**文件**：`rtl/core/cpu_trap_manager.v`（130行）

**功能**：

- Decode 阶段异常检测：非法指令(mcause=2)、ECALL(mcause=11)、EBREAK(mcause=3)
- Mem 阶段异常检测：Load 未对齐(mcause=4)、Store 未对齐(mcause=6)
- 异常寄存器锁存：`exception_valid_r`/`exception_cause_r`/`exception_pc_r`/`exception_mtval_r`
- `trap_pending` 判定：中断待响应且无更高优先级同步异常
- 内部实例化 `cpu_clint` 完成中断判定与 CSR 硬件写

**异常优先级**：同步异常优先于中断；同一边界上的同步异常先处理。

### 3.13 cpu_csr_interface — CSR 指令接口

**文件**：`rtl/core/cpu_csr_interface.v`（103行）

**功能**：

- 从 `id_exe_bus_r` 提取 CSR 相关字段（funct3/uimm/rs1/rs1_val/rd/pc/inst）
- CSR 新值计算：CSRRW(rs1_val)、CSRRS(csr|rs1_val)、CSRRC(csr&~rs1_val)、CSRRWI(uimm)、CSRRSI(csr|uimm)、CSRRCI(csr&~uimm)
- CSR no-write 优化：CSRRS/CSRRC 且 rs1=0 时、CSRRSI/CSRRCI 且 uimm=0 时不写
- CSR 写回总线生成：`csr_wb_bus = {pc_plus4, 0, 1, 1, rd, csr_rdata, csr_rdata, pc, inst}`
- 内部实例化 `cpu_csr` 完成寄存器读写

### 3.14 cpu_csr — CSR 寄存器模块

**文件**：`rtl/core/cpu_csr.v`（119行）

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
| 0x344 | mip | MR | MEIP[11], MTIP[7], MSIP[3] 由硬件驱动 |

**双写端口**：

- 软件写（`sw_csr_wen`）：CSR 指令触发
- 硬件写（`hw_csr_wen`）：trap 进入/返回时自动更新 mepc/mcause/mtval/mstatus

**mip 硬件驱动**：`w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0}`，MEIP=bit11, MTIP=bit7, MSIP=bit3。

### 3.15 cpu_clint — 异常/中断控制逻辑

**文件**：`rtl/core/cpu_clint.v`（77行）

**中断判定**：`mstatus.MIE && ((mie.MEIE && mip.MEIP) || (mie.MTIE && mip.MTIP) || (mie.MSIE && mip.MSIP))`

**中断编码**：

| 中断源 | mcause Code | 条件 |
|--------|-------------|------|
| 软件中断 (MSIP) | 0x80000003 | MSIE=1 && MSIP=1 |
| Timer 中断 (MTIP) | 0x80000007 | MTIE=1 && MTIP=1 |
| 外部中断 (MEIP) | 0x8000000B | MEIE=1 && MEIP=1 |

**trap 进入**：

- PC ← mtvec.BASE（Direct 模式）
- mepc ← 异常PC（异常）或当前PC（中断）
- mcause ← 异常/中断编码
- mstatus: MPIE←MIE, MIE←0, MPP←当前模式

**MRET 返回**：

- PC ← mepc
- mstatus: MIE←MPIE, MPIE←1, MPP←U

### 3.16 cpu_bus_bridge — CPU 总线桥接器

**文件**：`rtl/core/cpu_bus_bridge.v`（157行）

将 CPU 的 ICache/DCache MMIO 请求直接桥接为 AHB-Lite 主设备信号（HADDR/HTRANS/HWRITE/HSIZE/HWDATA 等），CPU 核心直接输出 AHB-Lite 信号。

**状态机**：3状态

| 状态 | 说明 |
|------|------|
| AHB_IDLE | 空闲，等待 icache_mmio_req 或 dcache_mmio_req |
| AHB_ADDR | 地址相位，等待 HREADY |
| AHB_DATA | 数据相位，等待 HREADY，锁存 HRDATA |

**优先级**：ICache MMIO 请求优先于 DCache MMIO 请求（同时到达时 ICache 先服务）。

**AHB 信号映射**：

| CPU 请求 | HTRANS | HWRITE | HSIZE | HBURST |
|----------|--------|--------|-------|--------|
| ICache 取指 | NONSEQ | 0 | WORD | SINGLE |
| DCache 读 | NONSEQ | 0 | hsize | SINGLE |
| DCache 写 | NONSEQ | 1 | hsize | SINGLE |

**与旧版 cpu_bus_adapter 的区别**：旧版使用 req/resp 握手协议经 `ahb_master` 转换；新版直接驱动 AHB-Lite 信号，省去 `ahb_master` 中间层，减少延迟。

### 3.17 mu_unit — 乘除法单元

**文件**：`rtl/MU/mu_unit.v`（197行）

**M 扩展指令支持**：

| 指令 | 操作 | 说明 |
|------|------|------|
| MUL | rs1 × rs2 低32位 | 有符号乘法 |
| MULH | rs1 × rs2 高32位 | 有符号×有符号 |
| MULHSU | rs1 × rs2 高32位 | 有符号×无符号 |
| MULHU | rs1 × rs2 高32位 | 无符号×无符号 |
| DIV | rs1 / rs2 | 有符号除法（向零截断） |
| DIVU | rs1 / rs2 | 无符号除法 |
| REM | rs1 % rs2 | 有符号取余 |
| REMU | rs1 % rs2 | 无符号取余 |

**握手协议**：`mu_req_valid` → `mu_result_valid`，支持 flush 中断。

**内部实例化**：

- `booth_multiplier`：Booth 乘法器
- `non_restoring_divider`：非恢复余数除法器

### 3.18 booth_multiplier — Booth 乘法器

**文件**：`rtl/MU/booth_multiplier.v`（129行）

- 基2 Booth 算法，32周期迭代
- 3状态 FSM（IDLE/COMPUTE/FINISH）
- 65位 A:Q:Q_1 寄存器，根据 Q[0]/Q_1 位对决定加/减被乘数
- 每周期算术右移1位
- 输出64位乘积

### 3.19 non_restoring_divider — 非恢复余数除法器

**文件**：`rtl/MU/non_restoring_divider.v`（397行）

- 非恢复余数除法算法，32周期迭代
- 4状态 FSM（IDLE/COMPUTE/FIX/FINISH）
- 特殊情况处理：除零（商=0xFFFFFFFF, 余=被除数）、溢出（INT_MIN / -1 → 商=INT_MIN, 余=0）
- 无符号大除数快速路径
- 绝对值转换 + 32周期迭代 + 余数修正 + 符号应用
- C 语言风格向零截断修正（同符号/异符号边界情况）

### 3.20 辅助模块

#### op_regroup — 指令重组电路（`rtl/core/op_regroup.v`，50行）

- 拆分32位指令为 opcode/funct3/funct7/rs1/rs2/rd
- 生成五种立即数（I/S/B/U/J），均符号扩展

#### branch_comparator — 分支比较器（`rtl/core/branch_comparator.v`，33行）

- 支持 BEQ/BNE/BLT/BGE/BLTU/BGEU
- 有符号比较使用 `$signed`，无符号比较使用自然比较

---

## 4. AHB-Lite 总线设计

### 4.1 总线拓扑

```
cpu_bus_bridge (AHB Master, direct drive)
         │
    ┌────┴─────────────────────┐
    │    ahb_lite_bus         │
   │                           │
   │  ahb_decoder (2 slaves)   │
   │  ┌─────────────────────┐  │
   │  │ Slave 0: SRAM       │  │  HADDR[31]=0
   │  │ (ahb_sram_slave)    │  │
   │  └─────────────────────┘  │
   │  ┌─────────────────────┐  │
   │  │ Slave 1: APB Bridge │  │  HADDR[31]=1
   │  │ (ahb_lite_to_apb)   │  │
   │  └─────────────────────┘  │
   └───────────────────────────┘
```

### 4.2 ahb_decoder — AHB 地址译码器

**文件**：`rtl/AHB-lite/ahb_decoder.v`（37行）

参数化 `SLAVE_NUM`，通过 generate 支持 1/2/4/8 从设备配置。当前系统使用 2 从设备模式：`HSELx[0]=~HADDR[31]`（SRAM），`HSELx[1]=HADDR[31]`（APB Bridge）。

### 4.3 ahb_mux — AHB 读数据多路选择器

**文件**：`rtl/AHB-lite/ahb_mux.v`（32行）

根据 `HSELx` 选择对应从设备的 HRDATA/HREADY/HRESP。

### 4.4 ahb_sram_slave — AHB SRAM 从设备

**文件**：`rtl/AHB-lite/ahb_sram_slave.v`（121行）

- 参数化 `MEM_DEPTH=262144`（1MB），`WAIT_STATES=0`
- 内部实例化 Sram BRAM IP（Xilinx Block Memory Generator）
- 支持字节/半字/字写使能，通过 `byte_we` 转换 HSIZE+HADDR 为 BRAM 字节掩码
- 等待状态计数器处理 BRAM 读延迟（1周期）

### 4.5 ahb_lite_bus — AHB 外设总线顶层

**文件**：`rtl/AHB-lite/ahb_lite_bus.v`（215行）

集成 ahb_decoder + ahb_mux + ahb_sram_slave + ahb_lite_to_apb + apb_decoder + apb_perips。对外暴露 AHB-Lite 主设备接口及外设 IO（GPIO/UART/SPI/Timer IRQ）。

---

## 5. APB 总线与外设设计

### 5.1 APB 总线拓扑

```
ahb_lite_to_apb (Bridge)
        │
   ┌────┴─────────────────────┐
   │    apb_decoder (4 slaves) │
   │  ┌──────────┐             │
   │  │ Slave 0  │  PADDR[15:14]=00  GPIO
   │  ├──────────┤             │
   │  │ Slave 1  │  PADDR[15:14]=01  Timer
   │  ├──────────┤             │
   │  │ Slave 2  │  PADDR[15:14]=10  UART
   │  ├──────────┤             │
   │  │ Slave 3  │  PADDR[15:14]=11  SPI
   │  └──────────┘             │
   └───────────────────────────┘
```

### 5.2 ahb_lite_to_apb — AHB-to-APB 桥

**文件**：`rtl/APB/ahb_lite_to_apb.v`（150行）

3状态 FSM（IDLE→SETUP→ACCESS），将 AHB-Lite 传输转换为 APB 协议（PSEL/PENABLE/PWRITE/PADDR/PWDATA/PSTRB）。支持 PSLVERR 错误响应回传、背靠背传输（ACCESS 阶段检测新 AHB 请求直接进入 SETUP）。

### 5.3 apb_master — APB 主设备

**文件**：`rtl/APB/apb_master.v`（101行）

3状态 FSM（IDLE→SETUP→ACCESS），将 req/resp 握手转换为 APB 协议信号。

### 5.4 apb_slave — APB 通用从设备

**文件**：`rtl/APB/apb_slave.v`（66行）

参数化 `REG_NUM=4`，内部维护 `regs[0:REG_NUM-1]` 寄存器数组。支持 PSTRB 字节掩码写入，零等待周期（PREADY=1），无错误响应（PSLVERR=0）。

### 5.5 apb_perips — APB 外设容器

**文件**：`rtl/APB/perips/apb_perips.v`（119行）

实例化 GPIO/Timer/UART/SPI 四个外设，根据 `PSELx[3:0]` 选择对应从设备。输出各从设备的 PREADY/PRDATA/PSLVERR 供桥接逻辑使用。

### 5.6 外设模块

| 外设 | 文件 | 行数 | 说明 |
|------|------|------|------|
| GPIO | `perips/gpio.v` | 104 | 16bit 双向 IO，方向控制+数据寄存器 |
| Timer | `perips/timer.v` | 85 | 32位计数器+阈值+使能，匹配时产生 IRQ |
| UART | `perips/uart_top.v` | 153 | 顶层封装，含 RX/TX 子模块 |
| UART RX | `perips/uart_rx.v` | 142 | 接收状态机，可配置波特率 |
| UART TX | `perips/uart_tx.v` | 133 | 发送状态机，可配置波特率 |
| SPI | `perips/spi.v` | 194 | SPI 主机，支持 MOSI/MISO/SS/CLK |

---

## 6. ALU 与乘除法单元设计

### 6.1 ALU 模块层次

```
alu_32bit
├── cla_adder_32bit
│   └── cla_adder_16bit ×2
│       └── cla_adder_4bit ×4
├── subtractor
├── logic_unit
├── shifter
│   └── mux_2to1 / mux_4to1
├── lui
└── alu_result_selector
```

### 6.2 ALU 模块明细

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| alu_32bit | `rtl/ALU/alu_32bit.v` | 104 | 顶层 ALU，路由控制码到各子模块 |
| alu_result_selector | `rtl/ALU/alu_result_selector.v` | 51 | 13路 one-hot 结果选择 |
| cla_adder_32bit | `rtl/ALU/cla_adder_32bit.v` | 27 | 32位超前进位加法器 |
| cla_adder_16bit | `rtl/ALU/cla_adder_16bit.v` | 51 | 16位超前进位加法器 |
| cla_adder_4bit | `rtl/ALU/cla_adder_4bit.v` | 32 | 4位超前进位加法器（叶节点） |
| logic_unit | `rtl/ALU/logic_unit.v` | 27 | AND/OR/XOR/NOR/NOT/SLT/SLTU |
| shifter | `rtl/ALU/shifter.v` | 138 | 桶形移位器，5级对数移位 |
| lui | `rtl/ALU/lui.v` | 8 | LUI 单元 |
| subtractor | `rtl/ALU/subtractor.v` | 14 | 减法器（取补+加法） |
| mux | `rtl/ALU/mux.v` | 178 | 参数化多路选择器库（2/4/8/16:1） |

### 6.3 乘除法单元层次

```
mu_unit
├── booth_multiplier
└── non_restoring_divider
```

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| mu_unit | `rtl/MU/mu_unit.v` | 197 | 乘除法调度，MULHSU/MULHU 修正 |
| booth_multiplier | `rtl/MU/booth_multiplier.v` | 129 | 基2 Booth 乘法，32周期 |
| non_restoring_divider | `rtl/MU/non_restoring_divider.v` | 397 | 非恢复余数除法，32周期+修正 |

---

## 7. CPU 总线接口设计

### 7.1 CPU 侧接口信号

| 方向 | 信号 | 位宽 | 说明 |
|------|------|------|------|
| CPU→Cache | `instAddr_32` | 32 | 取指地址（字节地址=PC） |
| Cache→CPU | `instData_32` | 32 | 指令数据 |
| Cache→CPU | `inst_valid` | 1 | 指令数据有效 |
| CPU→Cache | `dataWen_4` | 4 | 字节写掩码（0=写，1=不写，1111=读） |
| CPU→Cache | `dataAddr_32` | 32 | 访存地址 |
| CPU→Cache | `writeData_32` | 32 | 写入数据 |
| Cache→CPU | `readData_32` | 32 | 读取数据 |
| Cache→CPU | `data_valid` | 1 | 读数据有效 |
| CPU→Bus | `data_req` | 1 | 数据请求使能 |
| Bus→CPU | `init_sig` | 1 | 初始化暂停信号 |
| Bus→CPU | `timer_irq` | 1 | Timer 中断信号 |

### 7.2 Cache MMIO 旁路机制

ICache/DCache 控制器通过地址最高位判断访问类型：

| 地址范围 | is_mmio | 路径 | 说明 |
|----------|---------|------|------|
| 0x00000000-0x7FFFFFFF | 0 | BRAM IP | Cache 本地 SRAM，零延迟读 |
| 0x80000000-0xFFFFFFFF | 1 | 总线 MMIO | 透传到 AHB-Lite 总线 |

ICache MMIO 时 `mmio_req=cpu_req_valid`，DCache MMIO 时透传 `cpu_req_wen`/`cpu_req_wdata`/`cpu_req_hwrite`/`cpu_req_hsize`。

---

## 8. 异常与中断机制

### 8.1 异常类型

| 异常 | mcause Code | 触发条件 |
|------|-------------|----------|
| 非法指令 | 2 | opcode/funct3/funct7 未定义，或 CSR 地址无效 |
| EBREAK | 3 | 执行 EBREAK 指令 |
| Load 地址未对齐 | 4 | LH/LHU bit0≠0，LW bit[1:0]≠0 |
| Store 地址未对齐 | 6 | SH bit0≠0，SW bit[1:0]≠0 |
| ECALL (M-mode) | 11 | M-mode 下执行 ECALL |

### 8.2 中断类型

| 中断 | mcause Code | 触发条件 |
|------|-------------|----------|
| Machine 软件中断 | 0x80000003 | mip.MSIP=1 && mie.MSIE=1 && mstatus.MIE=1 |
| Machine Timer 中断 | 0x80000007 | mip.MTIP=1 && mie.MTIE=1 && mstatus.MIE=1 |
| Machine 外部中断 | 0x8000000B | mip.MEIP=1 && mie.MEIE=1 && mstatus.MIE=1 |

**中断源**：`ext_mtip` 连接 `timer_irq`（来自 APB Timer 外设），电平触发（持续到软件 ack）。

### 8.3 异常检测点

- **Decode 阶段**：非法指令、ECALL、EBREAK
- **Mem 阶段**：Load/Store 地址未对齐
- **指令边界**：中断检测（在 EXEC 完成分支指令后、WB 完成后）

---

## 9. 测试验证

### 9.1 测试框架

| Testbench | 文件 | 行数 | 测试内容 |
|-----------|------|------|----------|
| tb_simple_cpu_top | `tb/tb_simple_cpu_top.v` | 220 | CPU 综合测试（ALU/访存/对齐/CSR/异常/中断） |
| tb_simple_cpu_compute | `tb/tb_simple_cpu_compute.v` | 220 | CPU 运算指令测试（M扩展+算术） |
| tb_simple_cpu_trap | `tb/tb_simple_cpu_trap.v` | 191 | CPU 异常/中断测试 |
| tb_uart_hello | `tb/tb_uart_hello.v` | 252 | UART Hello World 发送测试 |
| tb_ahb_bus | `tb/tb_ahb_bus.v` | 175 | AHB-Lite 总线功能测试 |
| tb_apb_perips | `tb/tb_apb_perips.v` | 202 | APB 外设读写测试 |
| tb_led_marquee | `tb/tb_led_marquee.v` | 189 | LED 走马灯测试 |
| lcd_module_stub | `tb/lcd_module_stub.v` | 34 | LCD 模块仿真桩 |
| tb_alu_cpu_integration | `tb/ALU/tb_alu_cpu_integration.v` | 149 | ALU 组合逻辑集成测试 |
| tb_mu_unit | `tb/ALU/tb_mu_unit.v` | 227 | 乘除法单元测试 |
| tb_non_restoring_divider | `tb/ALU/tb_non_restoring_divider.v` | 204 | 非恢复余数除法器测试 |

### 9.2 测试程序

| 程序 | 文件 | 说明 |
|------|------|------|
| CPU 综合测试 | `program_source/cpu_test.s` | ALU/访存/对齐/CSR/异常/中断综合测试 |
| CPU 运算测试 | `program_source/cpu_test_compute.s` | M扩展+算术运算测试 |
| CPU 异常测试 | `program_source/cpu_test_trap.s` | 异常/中断专项测试 |
| LED 走马灯 | `program_source/led_marquee.s` | LED 跑马灯演示程序 |
| UART Hello | `program_source/uart_hello.s` | UART Hello World 发送程序 |
| Fibonacci | `program_source/fib10.c` | C 语言 Fibonacci 数列计算 |

### 9.3 验证结果

| 测试类别 | 检查项数 | 结果 |
|----------|----------|------|
| CPU 综合测试 | 33 | ALL PASS |
| CPU 运算测试 | 33 | ALL PASS |
| CPU 异常测试 | 8 | ALL PASS |
| AHB 总线测试 | 3 | ALL PASS |
| APB 外设测试 | 10 | ALL PASS |
| ALU 集成测试 | 11 | ALL PASS |
| MU 单元测试 | 10 | ALL PASS |
| 除法器测试 | 8 | ALL PASS |

---

## 10. FPGA 集成

### 10.1 system_top — FPGA 顶层

**文件**：`rtl/system_top.v`（234行）

集成 CPU + ahb_lite_bus + LCD 显示模块：

```
system_top
├── core_top         # CPU 核心
├── ahb_lite_bus         # AHB-Lite + APB 总线 + 外设
│   ├── ahb_sram_slave     # SRAM (Sram IP, 1MB)
│   └── ahb_lite_to_apb    # → APB (GPIO/Timer/UART/SPI)
└── lcd_module             # LCD 触摸屏显示（.dcp 预编译）
```

**复位极性**：CPU 内部 `reset` 高有效，FPGA 板 `resetn` 低有效，顶层 `reset = ~resetn`。

**init_sig**：硬连线为 `1'b0`（总线始终就绪，无需初始化等待）。

**AHB 直连**：`core_top` 直接输出 AHB-Lite 信号（HADDR/HTRANS/HWRITE 等），连接到 `ahb_lite_bus`。

### 10.2 LCD 显示项

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

### 10.3 引脚约束

**文件**：`fpga/cpu.xdc`

约束覆盖：时钟(AC19)、复位(Y3)、8位拨码开关、LCD 触摸屏(16位数据+控制)、UART(RX:F23, TX:H19)、SPI(4线)、GPIO(16位扩展IO)。IO 标准均为 LVCMOS33。

---

## 11. 关键设计决策与演进

### 11.1 从 Bus4LZU Mock 到 AHB-Lite + APB 总线

| 方面 | 旧设计（bus4lzu_mock） | 新设计（AHB-Lite + APB） |
|------|----------------------|------------------------|
| 总线协议 | 自定义 Bus4LZU 仿真代理 | AMBA AHB-Lite + APB 标准协议 |
| 存储器 | 内部 BRAM 数组 + $readmemh | Sram BRAM IP (Xilinx) |
| 外设 | 内部 Timer 逻辑 | APB 总线挂载 GPIO/Timer/UART/SPI |
| Cache | 行为模型 (icache.v/dcache.v) | BRAM IP + 控制器 (icache_ctrl/dcache_ctrl) |
| 地址空间 | 0x1001xxxx 手动过滤 | bit31 译码：0=SRAM, 1=MMIO |
| CPU 桥接 | 直连 mock | cpu_bus_bridge (CPU→AHB direct) |
| init_sig | 100周期高电平冻结 | 硬连线 1'b0（总线始终就绪） |
| 扩展性 | 不可综合，仅仿真 | 可综合，支持 FPGA 部署 |

### 11.2 从 cpu_bus_adapter 到 cpu_bus_bridge

| 方面 | 旧设计（cpu_bus_adapter） | 新设计（cpu_bus_bridge） |
|------|--------------------------|------------------------|
| 桥接方式 | Bus4LZU → req/resp 握手 → ahb_master → AHB | CPU MMIO → 直接 AHB-Lite 信号 |
| 中间层 | 需要 ahb_master 转换 | 无中间层，直接驱动 AHB 信号 |
| 状态机 | 5状态 (IDLE/I_REQ/I_WAIT/D_REQ/D_WAIT) | 3状态 (IDLE/ADDR/DATA) |
| 行数 | 173行 | 157行 |
| 延迟 | 多一层握手 | 减少一周期延迟 |

### 11.3 CSR/Trap 逻辑重构

| 方面 | 旧设计 | 新设计 |
|------|--------|--------|
| CSR 新值计算 | 在 cpu_execute 中 | 独立 cpu_csr_interface 模块 |
| 异常检测 | 在 cpu_clint 中 | 独立 cpu_trap_manager 模块 |
| 模块结构 | cpu_clint 混合异常检测+CSR更新 | cpu_trap_csr 封装 → trap_manager + csr_interface |
| 优势 | - | 职责分离，便于维护与扩展 |

### 11.4 M 扩展集成

| 方面 | 说明 |
|------|------|
| 乘法器 | 基2 Booth 算法，32周期，硬件面积小 |
| 除法器 | 非恢复余数算法，32周期+修正，完整边界处理 |
| 握手协议 | mu_req_valid / mu_result_valid，支持 flush |
| EX 阶段集成 | 多周期等待，mu_unit busy 时 EX 阶段保持 |
| 指令集扩展 | RV32I → RV32IM，新增8条乘除法指令 |

### 11.5 Cache 控制器演进

| 方面 | 旧设计 | 新设计 |
|------|--------|--------|
| ICache | 行为模型，$readmemh 初始化 | icache_ctrl + BRAM IP，COE 初始化 |
| DCache | 行为模型，内部数组 | dcache_ctrl + BRAM IP，支持字节写 |
| MMIO | 无，所有访问走内部 | bit31 旁路，MMIO 直连总线 |
| MMU | 无 | 直通 MMU 预留，paddr=vaddr |

### 11.6 已修复的关键 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| mip MEIP 位映射错误 | w_mip_hw 仅27位，零扩展后 MEIP 落在 bit6 | 扩展为32位，MEIP=bit11, MTIP=bit7, MSIP=bit3 |
| interrupt_cause 编码错误 | {1'b1,27'd0,5'd11} = 33位，截断后 bit31=0 | 直接使用 32'h8000000B / 32'h80000007 / 32'h80000003 |
| Timer IRQ 电平触发 | 原为单周期脉冲 | 改为持续高直到软件 ack |
| Store 误写寄存器 | MEM_WRITE 状态遗漏清除 wb_we_reg | 增加 wb_we_reg<=0; wb_data_reg<=0 |
| MRET 误判为非法指令 | inst_mret 匹配模式仅20位有效 | 扩展为完整25位匹配 |

---

## 12. 目录结构

```
dev/
├── rtl/                              # RTL 源码
│   ├── core/                         # CPU 核心模块
│   │   ├── core_top.v          # CPU 顶层 (458行)
│   │   ├── cpu_controller.v          # FSM 控制器 (133行)
│   │   ├── cpu_fetch.v               # 取指阶段 (30行)
│   │   ├── cpu_decode.v              # 译码阶段 (360行)
│   │   ├── cpu_execute.v             # 执行阶段 (249行)
│   │   ├── cpu_mem.v                 # 访存阶段 (242行)
│   │   ├── cpu_wb.v                  # 回写阶段 (41行)
│   │   ├── cpu_regfile.v             # 寄存器堆 (34行)
│   │   ├── cpu_csr.v                 # CSR 寄存器 (119行)
│   │   ├── cpu_csr_interface.v       # CSR 指令接口 (103行)
│   │   ├── cpu_trap_csr.v            # 异常/CSR 封装 (109行)
│   │   ├── cpu_trap_manager.v        # 异常检测与trap管理 (130行)
│   │   ├── cpu_clint.v               # 中断控制逻辑 (77行)
│   │   ├── cpu_bus_bridge.v          # CPU→AHB 总线桥接 (157行)
│   │   ├── icache_ctrl.v             # ICache 控制器 (60行)
│   │   ├── dcache_ctrl.v             # DCache 控制器 (76行)
│   │   ├── icache.v                  # ICache BRAM IP 包装 (62行)
│   │   ├── dcache.v                  # DCache BRAM IP 包装 (62行)
│   │   ├── MMU.v                     # 内存管理单元 (10行)
│   │   ├── op_regroup.v              # 指令重组 (50行)
│   │   └── branch_comparator.v       # 分支比较器 (33行)
│   ├── ALU/                           # ALU 模块
│   │   ├── alu_32bit.v               # 顶层 ALU (104行)
│   │   ├── alu_result_selector.v     # 结果选择器 (51行)
│   │   ├── cla_adder_32bit.v         # 32位 CLA 加法器 (27行)
│   │   ├── cla_adder_16bit.v         # 16位 CLA 加法器 (51行)
│   │   ├── cla_adder_4bit.v          # 4位 CLA 加法器 (32行)
│   │   ├── logic_unit.v              # 逻辑运算单元 (27行)
│   │   ├── shifter.v                 # 桶形移位器 (138行)
│   │   ├── lui.v                     # LUI 单元 (8行)
│   │   ├── subtractor.v              # 减法器 (14行)
│   │   └── mux.v                     # 多路选择器库 (178行)
│   ├── MU/                            # 乘除法单元
│   │   ├── mu_unit.v                 # 乘除法调度 (197行)
│   │   ├── booth_multiplier.v        # Booth 乘法器 (129行)
│   │   └── non_restoring_divider.v   # 非恢复余数除法器 (397行)
│   ├── AHB-lite/                     # AHB-Lite 总线
│   │   ├── ahb_lite_bus.v          # AHB 外设总线顶层 (215行)
│   │   ├── ahb_decoder.v             # AHB 地址译码 (37行)
│   │   ├── ahb_mux.v                 # AHB 读数据 MUX (32行)
│   │   ├── ahb_sram_slave.v          # AHB SRAM 从设备 (121行)
│   │   ├── ahb_def.vh                # AHB 宏定义
│   │   └── ip/sram_model.v           # SRAM 仿真模型 (62行)
│   ├── APB/                           # APB 总线
│   │   ├── ahb_lite_to_apb.v         # AHB→APB 桥 (150行)
│   │   ├── apb_master.v              # APB 主设备 (101行)
│   │   ├── apb_slave.v               # APB 通用从设备 (66行)
│   │   ├── apb_decoder.v             # APB 地址译码 (35行)
│   │   ├── apb_bus.v                 # APB 独立总线 (132行)
│   │   ├── apb_def.vh                # APB 宏定义
│   │   ├── header/
│   │   │   ├── bus_define.vh         # 总线公共定义
│   │   │   └── timer_define.vh       # Timer 寄存器定义
│   │   └── perips/                    # APB 外设
│   │       ├── apb_perips.v          # 外设容器 (119行)
│   │       ├── gpio.v                # GPIO (104行)
│   │       ├── timer.v               # Timer (85行)
│   │       ├── uart_top.v            # UART 顶层 (153行)
│   │       ├── uart_rx.v             # UART 接收 (142行)
│   │       ├── uart_tx.v             # UART 发送 (133行)
│   │       └── spi.v                 # SPI 主机 (194行)
│   └── system_top.v                  # FPGA 系统顶层 (234行)
├── tb/                               # 测试台
│   ├── tb_simple_cpu_top.v           # CPU 综合测试 (220行)
│   ├── tb_simple_cpu_compute.v       # CPU 运算测试 (220行)
│   ├── tb_simple_cpu_trap.v          # CPU 异常测试 (191行)
│   ├── tb_uart_hello.v               # UART Hello 测试 (252行)
│   ├── tb_ahb_bus.v                  # AHB 总线测试 (175行)
│   ├── tb_apb_perips.v               # APB 外设测试 (202行)
│   ├── tb_led_marquee.v              # LED 跑马灯测试 (189行)
│   ├── lcd_module_stub.v             # LCD 仿真桩 (34行)
│   └── ALU/                           # ALU/MU 测试
│       ├── tb_alu_cpu_integration.v  # ALU 集成测试 (149行)
│       ├── tb_mu_unit.v              # MU 单元测试 (227行)
│       └── tb_non_restoring_divider.v # 除法器测试 (204行)
├── program_source/                   # 测试程序
│   ├── cpu_test.s / .hex / .coe      # CPU 综合测试程序
│   ├── cpu_test_compute.s / .hex / .coe  # CPU 运算测试程序
│   ├── cpu_test_trap.s / .hex / .coe     # CPU 异常测试程序
│   ├── led_marquee.s / .coe          # LED 跑马灯程序
│   ├── uart_hello.s / .coe           # UART Hello World 程序
│   ├── fib10.c / .coe / _inst.coe    # Fibonacci 程序
│   ├── link.ld                       # 链接脚本
│   ├── link_harvard.ld               # Harvard 链接脚本
│   ├── Makefile                      # 编译脚本
│   └── verilog_to_words.py           # 反汇编工具
├── fpga/                             # FPGA 集成
│   ├── cpu.xdc                       # 引脚约束
│   ├── lcd_module.dcp                # LCD 预编译 IP
│   └── QUICK_REF.md                  # FPGA 快速参考
├── docs/                             # 文档
│   ├── simpleCPU-design-report.md    # 本报告
│   ├── core/                         # CPU 核心文档
│   ├── alu/                          # ALU 文档
│   ├── AHB-lite/                     # AHB 总线文档
│   └── APB/                          # APB 总线文档
├── PLAN.md                           # 总线接入计划
└── PROCESS.md                        # 开发进度记录
```

---

## 13. 代码规模统计

| 类别 | 文件数 | 总行数 |
|------|--------|--------|
| CPU 核心模块 (core/) | 21 | ~2,311 |
| ALU 模块 (ALU/) | 10 | ~630 |
| 乘除法单元 (MU/) | 3 | ~723 |
| AHB-Lite 总线 | 4 | ~451 |
| APB 总线 | 5 | ~484 |
| APB 外设 (perips/) | 7 | ~930 |
| Testbench | 11 | ~2,043 |
| FPGA (system_top + XDC) | 2 | ~234 |
| **合计** | **63** | **~7,806** |

---

## 14. 工具链

| 工具 | 用途 | 路径 |
|------|------|------|
| mk.py | 编译与仿真执行 | `tools/mk.py` |
| rv2coe.py | 汇编/C → HEX/COE/BIN | `tools/rv2coe.py` |
| vivado_sim.tcl | Vivado 仿真自动化 | `vivado_sim.tcl` |
| Vivado | FPGA 综合/实现/Bitstream | 需独立安装 |

**仿真命令示例**：

```bash
python tools/mk.py --top dev/tb/tb_simple_cpu_top.v
```

**程序编译命令示例**：

```bash
python3 tools/rv2coe.py -i dev/program_source/test.S \
  -o dev/program_source/cpu_test.hex --depth 2048
```

**Vivado 仿真命令示例**：

```tcl
source vivado_sim.tcl
```

---

## 15. Xilinx IP 依赖

| IP 名称 | 用途 | 路径 | 配置 |
|---------|------|------|------|
| icache | 指令 Cache BRAM | `Reference/ips/icache/` | 双端口, 4KB, COE 初始化 |
| dcache | 数据 Cache BRAM | `Reference/ips/dcache/` | 双端口, 4KB, 字节写使能 |
| Sram | 主存储器 BRAM | `Reference/ips/Sram/` | 双端口, 1MB, 字节写使能 |

---

## 16. 总结

SimpleCPU 是一个功能完整的 RV32IM 多周期处理器，已实现：

1. **55条指令**：RV32I 基础40条 + M扩展8条 + Zicsr 6条 + Zifencei 1条
2. **M 扩展乘除法**：Booth 乘法器 + 非恢复余数除法器，多周期握手，完整边界处理
3. **完整异常处理**：非法指令、ECALL、EBREAK、地址未对齐，含 trap 进入/返回
4. **三级中断响应**：MEIP(外部) + MTIP(Timer) + MSIP(软件)，电平触发
5. **AMBA 两级总线**：AHB-Lite (SRAM+Bridge) → APB (GPIO/Timer/UART/SPI)
6. **Cache + MMIO 旁路**：ICache/DCache BRAM IP，bit31 地址译码直连总线
7. **CPU 总线直连**：cpu_bus_bridge 直接驱动 AHB-Lite 信号，减少延迟
8. **CSR/Trap 模块化**：cpu_trap_csr 封装 trap_manager + csr_interface，职责分离
9. **116项测试全部通过**：CPU综合33 + CPU运算33 + CPU异常8 + AHB总线3 + APB外设10 + ALU集成11 + MU单元10 + 除法器8
10. **FPGA 验证就绪**：system_top + XDC 约束 + LCD 调试显示，可综合部署

该项目从简单的 BRAM 直连模型演进为 AMBA 标准两级总线架构，并集成了 M 扩展乘除法单元，在保持功能正确性的同时获得了标准化的外设扩展能力与 FPGA 可综合性，为后续接入更多外设（SPI Flash 存储、GPIO 扩展、DMA 等）奠定了基础。
