# SimpleCPU 设计与实现报告

> 生成日期：2026-05-05
> 项目路径：`dev/2-simpleCPU/`
> 当前分支：`wood-dev`

---

## 1. 项目概述

SimpleCPU 是一个基于 RISC-V RV32I 指令集的**多周期处理器**实现，采用经典五级流水线结构（取指-译码-执行-访存-回写）但以**多周期串行**方式运行——每个时钟周期仅激活一个流水级，指令在多个周期内依次通过各阶段完成执行。

该项目已完成从内部 BRAM 直连模型到 **AHB-Lite + APB 两级总线架构**的迁移。CPU 通过 `cpu_bus_adapter` 桥接 AHB-Lite 总线，AHB-Lite 下挂 SRAM 从设备与 AHB-to-APB 桥，APB 总线下挂 GPIO/Timer/UART/SPI 四个外设。ICache/DCache 控制器支持 MMIO 旁路（地址 bit31=1 时直接访问总线），并实现了完整的 CSR 寄存器、异常处理与中断响应机制。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32I (40条) + Zicsr (6条) + Zifencei (1条) = 47条 |
| 架构 | 多周期五级流水（IF→ID→EXE→MEM→WB） |
| 数据宽度 | 32位地址、32位数据 |
| 总线架构 | AHB-Lite (2从设备) → APB (4从设备) |
| Cache | ICache/DCache 控制器 + BRAM IP，MMIO 旁路 |
| 特权模式 | 仅 Machine 模式 |
| CSR | mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip (8个) |
| 异常 | 非法指令、ECALL、EBREAK、地址未对齐 |
| 中断 | MEIP(外部)/MTIP(Timer)/MSIP(软件)，电平触发 |
| 外设 | GPIO(16bit)/Timer/UART(RX+TX)/SPI，APB 总线挂载 |
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
  sw[7:0] ──────────────┤  │  │ simple_cpu_top   │                      │
  uart_rx/tx ───────────┤  │  │  IF→ID→EXE→MEM→WB│                      │
  spi_miso/mosi/ss/clk ─┤  │  │  CSR + CLINT     │                      │
  gpio_io[15:0] ────────┤  │  │  icache_ctrl     │                      │
                        │  │  │  dcache_ctrl     │                      │
                        │  │  │  MMU ×2          │                      │
                        │  │  └────────┬────────┘                      │
                        │  │           │ Bus4LZU-style                  │
                        │  │  ┌────────┴────────┐                      │
                        │  │  │ cpu_bus_adapter  │                      │
                        │  │  │ (Bus4LZU→AHB)    │                      │
                        │  │  └────────┬────────┘                      │
                        │  │           │ AHB-Lite                      │
                        │  │  ┌────────┴────────────────────────┐      │
                        │  │  │       ahb_periph_bus            │      │
                        │  │  │  ┌──────────┐ ┌──────────────┐ │      │
                        │  │  │  │ahb_master│ │ahb_decoder   │ │      │
                        │  │  │  └────┬─────┘ └──────┬───────┘ │      │
                        │  │  │       │ AHB bus        │ HSELx   │      │
                        │  │  │  ┌────┴─────┐   ┌─────┴──────┐  │      │
                        │  │  │  │ahb_sram  │   │ahb_lite_to │  │      │
                        │  │  │  │_slave    │   │_apb bridge │  │      │
                        │  │  │  │(SRAM IP) │   │            │  │      │
                        │  │  │  └──────────┘   └─────┬──────┘  │      │
                        │  │  └───────────────────────┼─────────┘      │
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
├── simple_cpu_top              # CPU 核心
│   ├── cpu_controller          # FSM 状态机控制器
│   ├── icache_ctrl             # ICache 控制器 (BRAM IP + MMIO 旁路)
│   │   └── icache              # ICache BRAM IP (Xilinx)
│   ├── cpu_fetch               # 取指阶段
│   ├── cpu_decode              # 译码阶段
│   │   └── op_regroup          # 指令字段拆分与立即数生成
│   ├── cpu_execute             # 执行阶段
│   │   ├── alu_32bit           # 32位ALU（外部共享模块）
│   │   └── branch_comparator   # 分支条件比较器
│   ├── dcache_ctrl             # DCache 控制器 (BRAM IP + MMIO 旁路)
│   │   └── dcache              # DCache BRAM IP (Xilinx)
│   ├── cpu_mem                 # 访存阶段（字节掩码写入）
│   ├── cpu_wb                  # 回写阶段
│   ├── cpu_regfile             # 32×32bit 寄存器堆
│   ├── cpu_csr                 # CSR 寄存器模块
│   ├── cpu_clint               # 异常/中断控制逻辑
│   └── MMU ×2                  # 地址翻译 (当前直通)
├── cpu_bus_adapter             # CPU Bus4LZU → AHB-Lite 桥接
├── ahb_periph_bus              # AHB-Lite 外设总线
│   ├── ahb_master              # AHB-Lite 主设备
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
| `id_exe_bus` | 316位 | Decode → Execute | pc_plus4, 控制信号, ALU操作数, CSR信息, pc, inst |
| `exe_mem_bus` | 207位 | Execute → Mem | pc_plus4, ALU结果, 访存信息, CSR数据, pc, inst |
| `mem_wb_bus` | 168位 | Mem → Writeback | pc_plus4, 写回数据, CSR数据, pc, inst |

---

## 3. 各模块详细设计

### 3.1 cpu_controller — FSM 状态机控制器

**文件**：`rtl/core/cpu_controller.v`（128行）

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

### 3.2 icache_ctrl — ICache 控制器

**文件**：`rtl/core/icache_ctrl.v`（60行）

**设计要点**：
- 参数化深度 `DEPTH=4096`，12位索引 → 4KB 直接映射
- MMIO 旁路：`is_mmio = cpu_req_addr[31]`，地址 bit31=1 时绕过 Cache 直连总线
- Cache 命中：组合逻辑读 BRAM IP，下一周期 `icache_valid_r=1` 返回数据
- MMIO 访问：透传 `mmio_data`/`mmio_valid` 信号
- 输出 MUX：`cpu_req_data = is_mmio ? mmio_data : icache_dout`

### 3.3 dcache_ctrl — DCache 控制器

**文件**：`rtl/core/dcache_ctrl.v`（65行）

**设计要点**：
- 与 icache_ctrl 结构对称，额外支持写操作
- 写使能反转：CPU `wen`（1=读,0=写）→ BRAM `wea`（1=写,0=读），`wea = ~cpu_req_wen`
- MMIO 旁路时透传 `mmio_wdata`/`mmio_wen`
- 非 MMIO 写操作时 `mmio_wen=4'b0`（不向总线发写请求）

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

**文件**：`rtl/core/cpu_decode.v`（334行）

**功能**：
- 指令字段拆分（opcode/funct3/funct7/rs1/rs2/rd）
- 五种立即数生成（I/S/B/U/J型），均符号扩展
- 指令识别：RV32I 全部40条 + 6条CSR + ECALL/EBREAK/MRET/FENCE/FENCE.I
- ALU 操作数选择（源寄存器/立即数/PC）
- ALU 控制码生成（16位，区分 ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI）
- 分支类型与访存大小识别
- CSR 地址有效性检查（8个实现的CSR）

**非法指令判定**：`id_valid && !valid_inst`，其中 `valid_inst` 覆盖所有已实现指令。

### 3.7 cpu_execute — 执行阶段

**文件**：`rtl/core/cpu_execute.v`（231行）

**功能**：
- 调用 `alu_32bit` 执行算术逻辑运算
- 分支条件判断（通过 `branch_comparator`）
- 分支目标计算：JALR 结果清最低位 `(alu_result & ~3)`
- LUI 指令使用固定写回路径（`use_fixed_wb`），跳过 ALU
- CSR 新值计算（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI）
- CSR no-write 优化（rs1=0 或 uimm=0 时不写）

**握手协议**：使用 `req_valid`/`result_valid`/`result_ready` 与 ALU 交互，支持 ALU 多周期操作。

### 3.8 cpu_mem — 访存阶段

**文件**：`rtl/core/cpu_mem.v`（224行）

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

### 3.11 cpu_csr — CSR 寄存器模块

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

### 3.12 cpu_clint — 异常/中断控制逻辑

**文件**：`rtl/core/cpu_clint.v`（75行）

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

**异常优先级**：异常优先于中断；同一边界上的同步异常先处理。

### 3.13 cpu_bus_adapter — CPU 总线适配器

**文件**：`rtl/core/cpu_bus_adapter.v`（173行）

将 CPU 的 Bus4LZU 风格接口（inst_addr/data_addr/data_wen/data_req）桥接为 AHB-Lite 主设备请求接口（req_valid/req_write/req_addr/req_wdata/req_size）。

**状态机**：5状态

| 状态 | 说明 |
|------|------|
| ST_IDLE | 空闲，等待 inst_req 或 data_req |
| ST_I_REQ | 发起取指请求，等待 req_ready |
| ST_I_WAIT | 等待取指响应 resp_valid |
| ST_D_REQ | 发起数据请求，等待 req_ready |
| ST_D_WAIT | 等待数据响应 resp_valid |

**写使能/传输大小映射**：

| data_wen | 操作 | req_write | req_size |
|----------|------|-----------|----------|
| 1111 | 读 | 0 | WORD |
| 1110/1101/1011/0111 | 字节写 | 1 | BYTE |
| 1100/0011 | 半字写 | 1 | HWORD |
| 0000 | 字写 | 1 | WORD |

**流水优化**：取指完成后若 data_req 已有效，直接转入 ST_D_REQ，减少空闲周期。

### 3.14 辅助模块

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
cpu_bus_adapter (AHB Master)
        │
   ┌────┴─────────────────────┐
   │    ahb_periph_bus         │
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

### 4.2 ahb_master — AHB-Lite 主设备

**文件**：`rtl/AHB-lite/ahb_master.v`（141行）

4状态 FSM（IDLE→ADDR→DATA→ERROR），将简单的 req/resp 握手协议转换为 AHB-Lite 信号（HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK）。支持 ERROR 响应处理。

### 4.3 ahb_decoder — AHB 地址译码器

**文件**：`rtl/AHB-lite/ahb_decoder.v`（37行）

参数化 `SLAVE_NUM`，通过 generate 支持 1/2/4/8 从设备配置。当前系统使用 2 从设备模式：`HSELx[0]=~HADDR[31]`（SRAM），`HSELx[1]=HADDR[31]`（APB Bridge）。

### 4.4 ahb_mux — AHB 读数据多路选择器

**文件**：`rtl/AHB-lite/ahb_mux.v`（32行）

根据 `HSELx` 选择对应从设备的 HRDATA/HREADY/HRESP。

### 4.5 ahb_sram_slave — AHB SRAM 从设备

**文件**：`rtl/AHB-lite/ahb_sram_slave.v`（121行）

- 参数化 `MEM_DEPTH=262144`（1MB），`WAIT_STATES=0`
- 内部实例化 Sram BRAM IP（Xilinx Block Memory Generator）
- 支持字节/半字/字写使能，通过 `byte_we` 转换 HSIZE+HADDR 为 BRAM 字节掩码
- 等待状态计数器处理 BRAM 读延迟（1周期）

### 4.6 ahb_periph_bus — AHB 外设总线顶层

**文件**：`rtl/AHB-lite/ahb_periph_bus.v`（261行）

集成 ahb_master + ahb_decoder + ahb_mux + ahb_sram_slave + ahb_lite_to_apb + apb_decoder + apb_perips。对外暴露 req/resp 握手接口及外设 IO（GPIO/UART/SPI/Timer IRQ）。

### 4.7 ahb_bus / ahb_default_slave（已弃用）

- `ahb_bus.v`（151行）：旧版4从设备 AHB 总线，已由 `ahb_periph_bus` 替代
- `ahb_default_slave.v`（46行）：旧版默认从设备（返回 ERROR），2从设备译码器覆盖全地址空间不再需要

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

## 6. CPU 总线接口设计

### 6.1 CPU 侧接口信号 (Bus4LZU-style)

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

### 6.2 Cache MMIO 旁路机制

ICache/DCache 控制器通过地址最高位判断访问类型：

| 地址范围 | is_mmio | 路径 | 说明 |
|----------|---------|------|------|
| 0x00000000-0x7FFFFFFF | 0 | BRAM IP | Cache 本地 SRAM，零延迟读 |
| 0x80000000-0xFFFFFFFF | 1 | 总线 MMIO | 透传到 AHB-Lite 总线 |

ICache MMIO 时 `mmio_req=cpu_req_valid`，DCache MMIO 时透传 `cpu_req_wen`/`cpu_req_wdata`。

---

## 7. 异常与中断机制

### 7.1 异常类型

| 异常 | mcause Code | 触发条件 |
|------|-------------|----------|
| 非法指令 | 2 | opcode/funct3/funct7 未定义，或 CSR 地址无效 |
| EBREAK | 3 | 执行 EBREAK 指令 |
| Load 地址未对齐 | 4 | LH/LHU bit0≠0，LW bit[1:0]≠0 |
| Store 地址未对齐 | 6 | SH bit0≠0，SW bit[1:0]≠0 |
| ECALL (M-mode) | 11 | M-mode 下执行 ECALL |

### 7.2 中断类型

| 中断 | mcause Code | 触发条件 |
|------|-------------|----------|
| Machine 软件中断 | 0x80000003 | mip.MSIP=1 && mie.MSIE=1 && mstatus.MIE=1 |
| Machine Timer 中断 | 0x80000007 | mip.MTIP=1 && mie.MTIE=1 && mstatus.MIE=1 |
| Machine 外部中断 | 0x8000000B | mip.MEIP=1 && mie.MEIE=1 && mstatus.MIE=1 |

**中断源**：`ext_mtip` 连接 `timer_irq`（来自 APB Timer 外设），电平触发（持续到软件 ack）。

### 7.3 异常检测点

- **Decode 阶段**：非法指令、ECALL、EBREAK
- **Mem 阶段**：Load/Store 地址未对齐
- **指令边界**：中断检测（在 EXEC 完成分支指令后、WB 完成后）

---

## 8. 测试验证

### 8.1 测试框架

| Testbench | 文件 | 行数 | 测试内容 |
|-----------|------|------|----------|
| tb_simple_cpu_top | `tb/tb_simple_cpu_top.v` | 250 | CPU 综合测试（ALU/访存/对齐/CSR/异常/中断） |
| tb_ahb_bus | `tb/tb_ahb_bus.v` | 171 | AHB-Lite 总线功能测试 |
| tb_apb_perips | `tb/tb_apb_perips.v` | 202 | APB 外设读写测试 |
| tb_cpu_bus_adapter | `tb/tb_cpu_bus_adapter.v` | 202 | CPU 总线适配器桥接测试 |
| tb_led_marquee | `tb/tb_led_marquee.v` | 228 | LED 走马灯测试 |
| lcd_module_stub | `tb/lcd_module_stub.v` | 34 | LCD 模块仿真桩 |

### 8.2 测试程序

| 程序 | 文件 | 说明 |
|------|------|------|
| CPU 综合测试 | `program_source/cpu_test.s` | ALU/访存/对齐/CSR/异常/中断综合测试 |
| LED 走马灯 | `program_source/led_marquee.s` | LED 跑马灯演示程序 |
| Fibonacci | `program_source/fib10.c` | C 语言 Fibonacci 数列计算 |

### 8.3 验证结果

| 测试类别 | 检查项数 | 结果 |
|----------|----------|------|
| CPU 综合测试 | 33 | ALL PASS |
| AHB 总线测试 | 3 | ALL PASS |
| APB 外设测试 | 10 | ALL PASS |
| CPU 总线适配器 | 6 | ALL PASS |

---

## 9. FPGA 集成

### 9.1 system_top — FPGA 顶层

**文件**：`rtl/system_top.v`（274行）

集成 CPU + cpu_bus_adapter + ahb_periph_bus + LCD 显示模块：

```
system_top
├── simple_cpu_top         # CPU 核心
├── cpu_bus_adapter        # Bus4LZU → AHB-Lite 桥接
├── ahb_periph_bus         # AHB-Lite + APB 总线 + 外设
│   ├── ahb_sram_slave     # SRAM (Sram IP, 1MB)
│   └── ahb_lite_to_apb    # → APB (GPIO/Timer/UART/SPI)
└── lcd_module             # LCD 触摸屏显示（.dcp 预编译）
```

**复位极性**：CPU 内部 `reset` 高有效，FPGA 板 `resetn` 低有效，顶层 `reset = ~resetn`。

**init_sig**：硬连线为 `1'b0`（总线始终就绪，无需初始化等待）。

**inst_req 判定**：`inst_req = instAddr_32[31]`，仅 MMIO 地址范围发起总线取指请求。

### 9.2 LCD 显示项

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

### 9.3 引脚约束

**文件**：`fpga/cpu.xdc`

约束覆盖：时钟(AC19)、复位(Y3)、8位拨码开关、LCD 触摸屏(16位数据+控制)、UART(RX:F23, TX:H19)、SPI(4线)、GPIO(16位扩展IO)。IO 标准均为 LVCMOS33。

---

## 10. 关键设计决策与演进

### 10.1 从 Bus4LZU Mock 到 AHB-Lite + APB 总线

| 方面 | 旧设计（bus4lzu_mock） | 新设计（AHB-Lite + APB） |
|------|----------------------|------------------------|
| 总线协议 | 自定义 Bus4LZU 仿真代理 | AMBA AHB-Lite + APB 标准协议 |
| 存储器 | 内部 BRAM 数组 + $readmemh | Sram BRAM IP (Xilinx) |
| 外设 | 内部 Timer 逻辑 | APB 总线挂载 GPIO/Timer/UART/SPI |
| Cache | 行为模型 (icache.v/dcache.v) | BRAM IP + 控制器 (icache_ctrl/dcache_ctrl) |
| 地址空间 | 0x1001xxxx 手动过滤 | bit31 译码：0=SRAM, 1=MMIO |
| CPU 桥接 | 直连 mock | cpu_bus_adapter (Bus4LZU→AHB) |
| init_sig | 100周期高电平冻结 | 硬连线 1'b0（总线始终就绪） |
| 扩展性 | 不可综合，仅仿真 | 可综合，支持 FPGA 部署 |

### 10.2 Cache 控制器演进

| 方面 | 旧设计 | 新设计 |
|------|--------|--------|
| ICache | 行为模型，$readmemh 初始化 | icache_ctrl + BRAM IP，COE 初始化 |
| DCache | 行为模型，内部数组 | dcache_ctrl + BRAM IP，支持字节写 |
| MMIO | 无，所有访问走内部 | bit31 旁路，MMIO 直连总线 |
| MMU | 无 | 直通 MMU 预留，paddr=vaddr |

### 10.3 已修复的关键 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| mip MEIP 位映射错误 | w_mip_hw 仅27位，零扩展后 MEIP 落在 bit6 | 扩展为32位，MEIP=bit11, MTIP=bit7, MSIP=bit3 |
| interrupt_cause 编码错误 | {1'b1,27'd0,5'd11} = 33位，截断后 bit31=0 | 直接使用 32'h8000000B / 32'h80000007 / 32'h80000003 |
| Timer IRQ 电平触发 | 原为单周期脉冲 | 改为持续高直到软件 ack |
| Store 误写寄存器 | MEM_WRITE 状态遗漏清除 wb_we_reg | 增加 wb_we_reg<=0; wb_data_reg<=0 |
| MRET 误判为非法指令 | inst_mret 匹配模式仅20位有效 | 扩展为完整25位匹配 |

---

## 11. 目录结构

```
dev/2-simpleCPU/
├── rtl/                              # RTL 源码
│   ├── core/                         # CPU 核心模块
│   │   ├── simple_cpu_top.v          # CPU 顶层 (537行)
│   │   ├── cpu_controller.v          # FSM 控制器 (128行)
│   │   ├── cpu_fetch.v               # 取指阶段 (30行)
│   │   ├── cpu_decode.v              # 译码阶段 (334行)
│   │   ├── cpu_execute.v             # 执行阶段 (231行)
│   │   ├── cpu_mem.v                 # 访存阶段 (224行)
│   │   ├── cpu_wb.v                  # 回写阶段 (41行)
│   │   ├── cpu_regfile.v             # 寄存器堆 (34行)
│   │   ├── cpu_csr.v                 # CSR 寄存器 (119行)
│   │   ├── cpu_clint.v               # 异常/中断控制 (75行)
│   │   ├── cpu_bus_adapter.v         # CPU→AHB 总线适配器 (173行)
│   │   ├── icache_ctrl.v             # ICache 控制器 (60行)
│   │   ├── dcache_ctrl.v             # DCache 控制器 (65行)
│   │   ├── icache.v                  # ICache BRAM IP 包装 (62行)
│   │   ├── dcache.v                  # DCache BRAM IP 包装 (62行)
│   │   ├── MMU.v                     # 内存管理单元 (10行)
│   │   ├── op_regroup.v              # 指令重组 (50行)
│   │   └── branch_comparator.v       # 分支比较器 (33行)
│   ├── AHB-lite/                     # AHB-Lite 总线
│   │   ├── ahb_periph_bus.v          # AHB 外设总线顶层 (261行)
│   │   ├── ahb_master.v              # AHB 主设备 (141行)
│   │   ├── ahb_decoder.v             # AHB 地址译码 (37行)
│   │   ├── ahb_mux.v                 # AHB 读数据 MUX (32行)
│   │   ├── ahb_sram_slave.v          # AHB SRAM 从设备 (121行)
│   │   ├── ahb_bus.v                 # 旧版 AHB 总线 (151行, 已弃用)
│   │   ├── ahb_default_slave.v       # 默认从设备 (46行, 已弃用)
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
│   └── system_top.v                  # FPGA 系统顶层 (274行)
├── tb/                               # 测试台
│   ├── tb_simple_cpu_top.v           # CPU 综合测试 (250行)
│   ├── tb_ahb_bus.v                  # AHB 总线测试 (171行)
│   ├── tb_apb_perips.v               # APB 外设测试 (202行)
│   ├── tb_cpu_bus_adapter.v          # 总线适配器测试 (202行)
│   ├── tb_led_marquee.v              # LED 跑马灯测试 (228行)
│   └── lcd_module_stub.v             # LCD 仿真桩 (34行)
├── program_source/                   # 测试程序
│   ├── cpu_test.s / .hex             # CPU 综合测试程序
│   ├── led_marquee.s / .coe          # LED 跑马灯程序
│   ├── fib10.c / .coe / _inst.coe    # Fibonacci 程序
│   ├── link.ld                       # 链接脚本
│   ├── Makefile                      # 编译脚本
│   └── verilog_to_words.py           # 反汇编工具
├── fpga/                             # FPGA 集成
│   ├── cpu.xdc                       # 引脚约束
│   └── lcd_module.dcp                # LCD 预编译 IP
├── doc/                              # 文档
│   ├── simpleCPU-design-report.md    # 本报告
│   ├── core/                         # CPU 核心文档
│   │   ├── instruction-set.md        # 指令集定义
│   │   ├── exception-interrupt.md    # 异常/中断机制
│   │   └── 简单CPU项目描述.md         # 项目初始描述
│   ├── AHB-lite/                     # AHB 总线文档
│   │   └── AMBA_AHB-Lite_Spec_Summary.md
│   └── APB/                          # APB 总线文档
│       └── AMBA_APB_Spec_Summary.md
├── PLAN.md                           # 总线接入计划
└── PROCESS.md                        # 开发进度记录
```

---

## 12. 代码规模统计

| 类别 | 文件数 | 总行数 |
|------|--------|--------|
| CPU 核心模块 (core/) | 18 | ~1,974 |
| AHB-Lite 总线 | 7 | ~789 |
| APB 总线 | 5 | ~484 |
| APB 外设 (perips/) | 7 | ~930 |
| ALU 模块 (1-alu/) | 12 | ~1,223 |
| Testbench | 6 | ~1,087 |
| FPGA (system_top + XDC) | 2 | ~274 |
| **合计** | **57** | **~6,761** |

---

## 13. 工具链

| 工具 | 用途 | 路径 |
|------|------|------|
| mk.py | 编译与仿真执行 | `tools/mk.py` |
| rv2coe.py | 汇编/C → HEX/COE/BIN | `tools/rv2coe.py` |
| vivado_sim.tcl | Vivado 仿真自动化 | `vivado_sim.tcl` |
| Vivado | FPGA 综合/实现/Bitstream | 需独立安装 |

**仿真命令示例**：
```bash
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v
```

**程序编译命令示例**：
```bash
python3 tools/rv2coe.py -i dev/2-simpleCPU/program_source/test.S \
  -o dev/2-simpleCPU/program_source/cpu_test.hex --depth 2048
```

**Vivado 仿真命令示例**：
```tcl
source vivado_sim.tcl
```

---

## 14. Xilinx IP 依赖

| IP 名称 | 用途 | 路径 | 配置 |
|---------|------|------|------|
| icache | 指令 Cache BRAM | `Reference/ips/icache/` | 双端口, 4KB, COE 初始化 |
| dcache | 数据 Cache BRAM | `Reference/ips/dcache/` | 双端口, 4KB, 字节写使能 |
| Sram | 主存储器 BRAM | `Reference/ips/Sram/` | 双端口, 1MB, 字节写使能 |

---

## 15. 总结

SimpleCPU 是一个功能完整的 RV32I 多周期处理器，已实现：

1. **47条指令**：RV32I 基础40条 + Zicsr 6条 + Zifencei 1条
2. **完整异常处理**：非法指令、ECALL、EBREAK、地址未对齐，含 trap 进入/返回
3. **三级中断响应**：MEIP(外部) + MTIP(Timer) + MSIP(软件)，电平触发
4. **AMBA 两级总线**：AHB-Lite (SRAM+Bridge) → APB (GPIO/Timer/UART/SPI)
5. **Cache + MMIO 旁路**：ICache/DCache BRAM IP，bit31 地址译码直连总线
6. **CPU 总线适配**：cpu_bus_adapter 桥接 Bus4LZU 风格接口到 AHB-Lite
7. **52项测试全部通过**：CPU综合33 + AHB总线3 + APB外设10 + 总线适配器6
8. **FPGA 验证就绪**：system_top + XDC 约束 + LCD 调试显示，可综合部署

该项目从简单的 BRAM 直连模型演进为 AMBA 标准两级总线架构，在保持功能正确性的同时获得了标准化的外设扩展能力与 FPGA 可综合性，为后续接入更多外设（SPI Flash 存储、GPIO 扩展、DMA 等）奠定了基础。
