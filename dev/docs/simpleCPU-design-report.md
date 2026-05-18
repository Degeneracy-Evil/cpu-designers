# SimpleCPU 设计与实现报告

> 生成日期：2026-05-18
> 项目路径：`dev/`
> 当前分支：`nightly`

---

## 1. 项目概述

SimpleCPU 是一个基于 RISC-V RV32IM 指令集的**多周期处理器**实现，采用经典五级流水线结构（取指-译码-执行-访存-回写）但以**多周期串行**方式运行——每个时钟周期仅激活一个流水级，指令在多个周期内依次通过各阶段完成执行。

该项目已完成从内部 BRAM 直连模型到 **AHB-Lite + APB 两级总线架构**的迁移，并集成了 RISC-V 标准的 CLINT（Core Local Interruptor）与 PLIC（Platform-Level Interrupt Controller）。CPU 通过 `cpu_bus_bridge` 直接驱动 AHB-Lite 总线信号，AHB-Lite 下挂 4 个从设备：SRAM、PLIC、CLINT、AHB-to-APB 桥；APB 总线下挂 GPIO/Timer/UART/SPI 四个外设。CLINT 产生 MTIP 中断直连 CPU 核心，PLIC 统一管理外部中断（当前仅 APB Timer IRQ 接入 src_irq[1]），输出 MEIP 至 CPU。ICache/DCache 控制器支持 MMIO 旁路（地址 bit31=0 时直接访问总线外设，bit31=1 时访问 Cache），并实现了包含计数器与只读标识寄存器在内的 CSR 寄存器、异常处理与中断响应机制。M 扩展（乘除法）通过 Booth 乘法器与非恢复余数除法器实现，支持多周期运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32I (40条) + M (8条) + Zicsr (6条) + Zifencei (1条) = 55条 |
| 架构 | 多周期五级流水（IF→ID→EXE→MEM→WB） |
| 数据宽度 | 32位地址、32位数据 |
| 总线架构 | AHB-Lite (4从设备: SRAM/PLIC/CLINT/Bridge) → APB (4从设备) |
| Cache | ICache/DCache 控制器 + BRAM IP，MMIO 旁路 |
| 乘除法 | Booth 乘法器 + 非恢复余数除法器，多周期握手 |
| 特权模式 | 仅 Machine 模式 |
| CSR | mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip + mcycle/minstret 及只读标识寄存器（18个有效地址） |
| 异常 | 非法指令、ECALL、EBREAK、地址未对齐 |
| 中断 | MEIP(外部,PLIC)/MTIP(Timer,CLINT直连)/MSIP(软件,未实现)，电平触发 |
| 系统时钟 | 100 MHz |
| 外设 | GPIO(16bit)/Timer/UART(RX+TX, 115200 baud)/SPI，APB 总线挂载；CLINT(mtime/mtimecmp)/PLIC(8源)，AHB 总线挂载 |
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
  sw[7:0] ──────────────┤  │  │ core_top        │                      │
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
                        │  │  ┌────────┴────────────────────────────┐  │
                        │  │  │          ahb_lite_bus               │  │
                        │  │  │  ┌────────────┐                      │  │
                        │  │  │  │ahb_sram    │ HADDR[31:24]=0x00   │  │
                        │  │  │  │_slave      │                      │  │
                        │  │  │  └────────────┘                      │  │
                        │  │  │  ┌────────────┐  o_mtip ──→ MTIP    │  │
                        │  │  │  │ahb_clint   │ HADDR[31:24]=0x02   │  │
                        │  │  │  └────────────┘  o_msip(=0)         │  │
                        │  │  │  ┌────────────┐  o_eip ───→ MEIP    │  │
                        │  │  │  │ahb_plic    │ HADDR[31:24]=0x0C   │  │
                        │  │  │  └────────────┘                      │  │
                        │  │  │  ┌────────────┐                      │  │
                        │  │  │  │ahb_lite_to │ HADDR[31]=1         │  │
                        │  │  │  │_apb bridge │────┐                │  │
                        │  │  │  └────────────┘    │ APB            │  │
                        │  │  └────────────────────┼────────────────┘  │
                        │  │  ┌────────────────────┴────────────────┐  │
                        │  │  │          apb_perips                 │  │
                        │  │  │  ┌────┐┌─────┐┌────┐┌─────┐      │  │
                        │  │  │  │GPIO││Timer││UART││ SPI │      │  │
                        │  │  │  └────┘└──┬──┘└────┘└─────┘      │  │
                        │  │  │           │irq                      │  │
                        │  │  │           └──→ plic.src_irq[1]     │  │
                        │  │  └────────────────────────────────────┘  │
                        │  │                                           │
                        │  │  ┌─────────────────┐                      │
                        │  │  │ lcd_module (DCP)│                      │
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
│   │   ├── alu_32bit           # 32位ALU（外部共享模块，内联减法）
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
├── ahb_lite_bus              # AHB-Lite 外设总线 (4从设备)
│   ├── ahb_mux                 # AHB 读数据多路选择
│   ├── ahb_sram_slave          # AHB SRAM 从设备 (Sram IP)
│   │   └── Sram                # SRAM BRAM IP (Xilinx)
│   ├── ahb_plic                # AHB PLIC 从设备 (8源外部中断控制器)
│   ├── ahb_clint               # AHB CLINT 从设备 (mtime/mtimecmp)
│   ├── ahb_lite_to_apb         # AHB-to-APB 桥
│   ├── apb_decoder             # APB 地址译码 (4从设备)
│   └── apb_perips              # APB 外设容器
│       ├── gpio                # GPIO (16bit 双向)
│       ├── timer               # 定时器 (含 IRQ → PLIC src_irq[1])
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

**文件**：`rtl/core/cpu_controller.sv`（134行）

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

**默认状态保持**：状态转移逻辑添加 `default: next_state = state_r`，防止 latch 推断。

**中断检测点**：在 EXEC 完成（分支指令）和 WB 完成后检测 `trap_pending`，若有待响应中断则进入 TRAP_ENTER。

**exe_to_wb 快速路径**：R/I-type 运算指令跳过 MEM 阶段，EXEC 完成后直接写入 WB 总线，减少一个时钟周期。

### 3.2 icache_ctrl — ICache 控制器

**文件**：`rtl/core/icache_ctrl.sv`（70行）

**设计要点**：

- 参数化深度 `DEPTH=4096`，12位索引 → 4KB 直接映射
- MMIO 旁路：`is_mmio = ~cpu_req_addr[31]`，地址 bit31=0 时绕过 Cache 直连总线（访问外设区）
- Cache 命中：组合逻辑读 BRAM IP，寄存器级 `bram_ena_r`/`bram_addra_r` 打一拍后驱动 BRAM，`icache_valid_r` 下一周期有效返回数据
- MMIO 访问：透传 `mmio_data`/`mmio_valid` 信号
- 输出 MUX：`cpu_req_data = is_mmio ? mmio_data : icache_dout`

### 3.3 dcache_ctrl — DCache 控制器

**文件**：`rtl/core/dcache_ctrl.sv`（90行）

**设计要点**：

- 与 icache_ctrl 结构对称，额外支持写操作
- 字节写使能生成：根据 `cpu_req_hsize`（BYTE/HWORD/WORD）和地址低位生成 BRAM 字节掩码
- 寄存器级 `bram_ena_r`/`bram_wea_r`/`bram_addra_r`/`bram_dina_r` 打一拍后驱动 BRAM，`dcache_valid_r` 下一周期有效
- MMIO 旁路时透传 `mmio_wdata`/`mmio_hwrite`/`mmio_hsize`
- 非 MMIO 写操作时 `mmio_req=0`（不向总线发写请求）

### 3.4 MMU — 内存管理单元

**文件**：`rtl/core/MMU.sv`（10行）

当前为直通模式 `paddr = vaddr`，为后续虚拟内存扩展预留接口。CPU 中实例化两个 MMU，分别用于取指地址和访存地址翻译。

### 3.5 cpu_fetch — 取指阶段

**文件**：`rtl/core/cpu_fetch.sv`（30行）

**设计要点**：

- 输出 `instAddr_32 = PC`（32位字节地址）
- 输入 `instData_32` 来自 icache_ctrl，`inst_valid` 标识数据有效
- `if_done = if_valid && inst_valid`，当 icache 返回有效数据时完成取指
- 无内部等待状态，时序由 icache_ctrl 的 BRAM 延迟保证

### 3.6 cpu_decode — 译码阶段

**文件**：`rtl/core/cpu_decode.sv`（395行）

**功能**：

- 指令字段拆分（opcode/funct3/funct7/rs1/rs2/rd）
- 五种立即数生成（I/S/B/U/J型），均符号扩展
- 指令识别：RV32I 全部40条 + M扩展8条 + 6条CSR + ECALL/EBREAK/MRET/FENCE/FENCE.I
- ALU 操作数选择（源寄存器/立即数/PC）
- ALU 控制码生成（16位，区分 ADD/SUB/SLT/SLTU/XOR/OR/AND/SLL/SRL/SRA/LUI）
- M 扩展操作识别（MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU）
- 分支类型与访存大小识别
- CSR 地址有效性检查（18个有效地址：含计数器高低位与只读标识寄存器）

**非法指令判定**：`id_valid && !valid_inst`，其中 `valid_inst` 覆盖所有已实现指令。

### 3.7 cpu_execute — 执行阶段

**文件**：`rtl/core/cpu_execute.sv`（255行）

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

**文件**：`rtl/core/cpu_mem.sv`（242行）

**状态机**：3状态

| 状态 | 说明 |
|------|------|
| MEM_IDLE | 等待访存请求 |
| MEM_READ | 等待读数据返回（1周期延迟） |
| MEM_WRITE | 写操作完成 |

**AHB 总线访存写入逻辑**：

根据 `mem_size` 生成 AHB 总线的 `hsize` 和数据对齐：

| 指令 | alu_result[1:0] | hsize | writeData_32 | 说明 |
|------|-----------------|-------|--------------|------|
| SB | xx | 000 (BYTE) | `{4{data[7:0]}}` | 字节复写至全32位 |
| SH | 00 | 001 (HWORD) | `{16'b0, data[15:0]}` | 写半字低16位 |
| SH | 10 | 001 (HWORD) | `{data[15:0], 16'b0}` | 写半字高16位 |
| SW | 00 | 010 (WORD) | `data[31:0]` | 写全部32位 |
| LOAD | xx | 010 (WORD) | `32'b0` | 读操作(hwrite=0) |

*注：实际的字节掩码（BRAM WEA，高有效）在 `dcache_ctrl.sv` 或 AHB 从设备中根据 `hsize` 和地址低位解码生成。*

**读数据提取**：

- LB/LBU：按 `byte_offset` 选择对应字节，LB 符号扩展，LBU 零扩展
- LH/LHU：按 `byte_offset[1]` 选择高低半字，LH 符号扩展，LHU 零扩展
- LW：直接使用 `readData_32`

**未对齐检测**：LH/LHU 地址 bit0 非0、LW/SW 地址 bit[1:0] 非0 时触发异常。

### 3.9 cpu_wb — 回写阶段

**文件**：`rtl/core/cpu_wb.sv`（41行）

**功能**：

- 通用寄存器写回：`rf_wen = wb_valid && wb_we`
- CSR 结果选择：`is_csr` 时使用 `csr_rdata`，否则使用 `wb_data`
- JAL/JALR 写回值：PC+4（在顶层通过 `wb_is_jal_like` 选择）

### 3.10 cpu_regfile — 寄存器堆

**文件**：`rtl/core/cpu_regfile.sv`（35行）

- 32个32位寄存器 `rf[0:31]`
- x0 硬连线为0（读取返回0，写入忽略）
- 异步读、同步写
- 使用 `foreach` 遍历初始化（SV 惯用法）
- 调试端口 `dbg_raddr`/`dbg_rdata` 供外部观察

### 3.11 cpu_trap_csr — 异常/CSR 顶层封装

**文件**：`rtl/core/cpu_trap_csr.sv`（125行）

将异常管理与 CSR 访问逻辑封装为统一模块，内部实例化：

- `cpu_trap_manager`：异常检测、中断判定、trap PC 生成、CSR 硬件写触发
- `cpu_csr_interface`：CSR 指令新值计算、CSR 写回总线生成

### 3.12 cpu_trap_manager — 异常检测与 trap 管理

**文件**：`rtl/core/cpu_trap_manager.sv`（150行）

**功能**：

- Decode 阶段异常检测：非法指令(mcause=2)、ECALL(mcause=11)、EBREAK(mcause=3)
- Mem 阶段异常检测：Load 未对齐(mcause=4)、Store 未对齐(mcause=6)
- 异常寄存器锁存：`exception_valid_r`/`exception_cause_r`/`exception_pc_r`/`exception_mtval_r`
- `trap_pending` 判定：中断待响应且无更高优先级同步异常
- 内部实例化 `cpu_clint` 完成中断判定与 CSR 硬件写

**异常优先级**：同步异常优先于中断；同一边界上的同步异常先处理。

### 3.13 cpu_csr_interface — CSR 指令接口

**文件**：`rtl/core/cpu_csr_interface.sv`（110行）

**功能**：

- 从 `id_exe_bus_r` 提取 CSR 相关字段（funct3/uimm/rs1/rs1_val/rd/pc/inst）
- CSR 新值计算：CSRRW(rs1_val)、CSRRS(csr|rs1_val)、CSRRC(csr&~rs1_val)、CSRRWI(uimm)、CSRRSI(csr|uimm)、CSRRCI(csr&~uimm)
- CSR no-write 优化：CSRRS/CSRRC 且 rs1=0 时、CSRRSI/CSRRCI 且 uimm=0 时不写
- CSR 写回总线生成：`csr_wb_bus = {pc_plus4, 0, 1, 1, rd, csr_rdata, csr_rdata, pc, inst}`
- 内部实例化 `cpu_csr` 完成寄存器读写

### 3.14 cpu_csr — CSR 寄存器模块

**文件**：`rtl/core/cpu_csr.sv`（179行）

**实现的 CSR 寄存器**：

| 地址 | 名称 | 读写 | 说明 |
|------|------|------|------|
| 0x300 | mstatus | MRW | MIE[3], MPIE[7], MPP[12:11] |
| 0x301 | misa | R | 固定为 0x40001100 |
| 0x304 | mie | MRW | MSIE[3], MTIE[7], MEIE[11] |
| 0x305 | mtvec | MRW | trap 向量基址 |
| 0x310 | mstatush | R | 固定为 0 |
| 0x340 | mscratch | MRW | 暂存寄存器 |
| 0x341 | mepc | MRW | 异常 PC |
| 0x342 | mcause | MRW | 异常原因 |
| 0x343 | mtval | MRW | 异常附加值 |
| 0x344 | mip | MR | MEIP[11], MTIP[7], MSIP[3] 由硬件驱动 |
| 0xB00 | mcycle | MRW | 64 位周期计数器低 32 位 |
| 0xB02 | minstret | MRW | 64 位提交计数器低 32 位 |
| 0xB80 | mcycleh | MRW | 64 位周期计数器高 32 位 |
| 0xB82 | minstreth | MRW | 64 位提交计数器高 32 位 |
| 0xF11 | mvendorid | R | 固定为 0 |
| 0xF12 | marchid | R | 固定为 0 |
| 0xF13 | mimpid | R | 固定为 0 |
| 0xF14 | mhartid | R | 固定为 0 |
| 0xF15 | mconfigptr | R | 固定为 0 |

**双写端口**：

- 软件写（`sw_csr_wen`）：CSR 指令触发
- 硬件写（`hw_csr_wen`）：trap 进入/返回时自动更新 mepc/mcause/mtval/mstatus

**计数器与硬件驱动**：`mcycle` 在 `cycle_en` 有效时自增，`minstret` 在 `inst_retire` 有效时自增，均支持低/高 32 位读写；`mip` 由 `w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0}` 直接驱动，MEIP=bit11, MTIP=bit7, MSIP=bit3。

### 3.15 cpu_clint — 异常/中断控制逻辑

**文件**：`rtl/core/cpu_clint.sv`（78行）

**中断判定**：`mstatus.MIE && ((mie.MEIE && mip.MEIP) || (mie.MTIE && ext_mtip) || (mie.MSIE && mip.MSIP))`

**注意**：MTIP 直接取自 `ext_mtip` 端口输入（来自 ahb_clint.o_mtip），不经 CSR mip[7]；MEIP 取自 `csr_mip[11]`（经 PLIC → cpu_csr → mip）；MSIP 取自 `csr_mip[3]`（恒为0）。

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

**文件**：`rtl/core/cpu_bus_bridge.sv`（155行）

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

**与旧版 cpu_bus_adapter 的区别**：旧版使用 req/resp 握手协议经 `ahb_master` 转换；新版直接驱动 AHB-Lite 信号，省去 `ahb_master` 中间层，减少延迟。AHB_ADDR 状态移除冗余 `else HTRANS<=IDLE` 分支，`HReady` 信号名修正为 `HREADY`。

### 3.17 mu_unit — 乘除法单元

**文件**：`rtl/MU/mu_unit.sv`（197行）

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

**文件**：`rtl/MU/booth_multiplier.sv`（120行）

- 基2 Booth 算法，32周期迭代
- 3状态 FSM（IDLE/COMPUTE/FINISH）
- 65位 A:Q:Q_1 寄存器，根据 Q[0]/Q_1 位对决定加/减被乘数
- 每周期算术右移1位
- 6位 wire `count_next` 计数器（面积优化，替代原 32 位 cla_adder）
- 输出64位乘积

### 3.19 non_restoring_divider — 非恢复余数除法器

**文件**：`rtl/MU/non_restoring_divider.sv`（381行）

- 非恢复余数除法算法，32周期迭代
- 4状态 FSM（IDLE/COMPUTE/FIX/FINISH）
- 特殊情况处理：除零（商=0xFFFFFFFF, 余=被除数）、溢出（INT_MIN / -1 → 商=INT_MIN, 余=0）
- 无符号大除数快速路径
- 6位 wire `count_next` 计数器（面积优化，替代原 32 位 cla_adder）
- 绝对值转换 + 32周期迭代 + 余数修正 + 符号应用
- C 语言风格向零截断修正（同符号/异符号边界情况）

### 3.20 辅助模块

#### op_regroup — 指令重组电路（`rtl/core/op_regroup.sv`，50行）

- 拆分32位指令为 opcode/funct3/funct7/rs1/rs2/rd
- 生成五种立即数（I/S/B/U/J），均符号扩展

#### branch_comparator — 分支比较器（`rtl/core/branch_comparator.sv`，22行）

- 支持 BEQ/BNE/BLT/BGE/BLTU/BGEU
- wire+assign 三元链实现，有符号比较使用 `$signed`，无符号比较使用自然比较

---

## 4. AHB-Lite 总线设计

### 4.1 总线拓扑

```
cpu_bus_bridge (AHB Master, direct drive)
         │
    ┌────┴──────────────────────────────────┐
    │         ahb_lite_bus (4 slaves)        │
    │                                        │
    │  ┌─────────────────┐                   │
    │  │ Slave 0: SRAM   │  HADDR[31:24]=0x00  0x0000_0000  │
    │  │ (ahb_sram_slave)│                   │
    │  └─────────────────┘                   │
    │  ┌─────────────────┐                   │
    │  │ Slave 1: PLIC   │  HADDR[31:24]=0x0C  0x0C00_0000  │
    │  │ (ahb_plic)      │──o_eip──→ MEIP    │
    │  └─────────────────┘                   │
    │  ┌─────────────────┐                   │
    │  │ Slave 2: CLINT  │  HADDR[31:24]=0x02  0x0200_0000  │
    │  │ (ahb_clint)     │──o_mtip──→ MTIP   │
    │  └─────────────────┘                   │
    │  ┌─────────────────┐                   │
    │  │ Slave 3: APB    │  HADDR[31:24]=0x10  0x1000_0000  │
    │  │(ahb_lite_to_apb)│                   │
    │  └─────────────────┘                   │
    └────────────────────────────────────────┘
```

**地址译码**（内联实现，未使用独立 `ahb_decoder` 模块）：

| 从设备 | 选择条件 | 地址范围 | 大小 |
|--------|----------|----------|------|
| SRAM | `HADDR[31:24] == 8'h00` | `0x0000_0000 - 0x00FF_FFFF` | 16 MB |
| PLIC | `HADDR[31:24] == 8'h0C` | `0x0C00_0000 - 0x0CFF_FFFF` | 16 MB |
| CLINT | `HADDR[31:24] == 8'h02` | `0x0200_0000 - 0x02FF_FFFF` | 16 MB |
| APB Bridge | `HADDR[31:24] == 8'h10` | `0x1000_0000 - 0x10FF_FFFF` | 16 MB |

**CLINT 内部寄存器偏移**（基址 `0x0200_0000`）：

| 偏移 | 名称 | 读写 | 说明 |
|------|------|------|------|
| +0x00 | mtimecmp_lo | R/W | 比较寄存器低32位 |
| +0x04 | mtimecmp_hi | R/W | 比较寄存器高32位 |
| +0x08 | mtime_lo | R/W | 机器时间低32位 |
| +0x0C | mtime_hi | R/W | 机器时间高32位 |

**PLIC 内部寄存器偏移**（基址 `0x0C00_0000`）：

| 偏移 | 名称 | 读写 | 说明 |
|------|------|------|------|
| 0x000-0x01F | Priority[0:7] | R/W | 8个中断源优先级（4B对齐） |
| 0x400 | Pending | R | 中断挂起位 |
| 0x800 | Enable | R/W | 中断使能位 |
| 0x200000 | Threshold | R/W | 优先级阈值 |
| 0x200010 | Claim/Complete | R/W | 中断声明/完成 |

### 4.2 ahb_clint — AHB CLINT 从设备

**文件**：`rtl/AHB-lite/ahb_clint.sv`（81行）

RISC-V CLINT（Core Local Interruptor）的总线接口层，挂载在 AHB-Lite 总线上：

- 64位 `mtime` 计数器：每个时钟周期自增1
- 64位 `mtimecmp` 比较寄存器：通过总线写入
- MTIP 输出：`o_mtip = (mtime >= mtimecmp) && (mtimecmp != 0)`，直连 CPU 核心 `timer_irq`
- MSIP 输出：`o_msip = 1'b0`（当前未实现软件中断）
- 零等待周期（HREADYOUT=1），无错误响应（HRESP=0）

### 4.3 ahb_plic — AHB PLIC 从设备

**文件**：`rtl/AHB-lite/ahb_plic.sv`（152行）

RISC-V PLIC（Platform-Level Interrupt Controller）的总线接口层，参数化 `NUM_SRC=8`：

- **中断源**：8个 `src_irq` 输入，当前仅 `src_irq[1]` 接入 APB Timer IRQ，其余接地
- **网关（Gateway）**：边沿检测，`src_irq[i]` 上升沿时置 `r_pending[i]=1`
- **优先级仲裁**：遍历所有 enabled && pending 源，找优先级最高且大于阈值者
- **声明/完成**：读 Claim 寄存器返回 `highest_id` 并清除 pending；写 Complete 寄存器重新使能网关
- **EIP 输出**：`o_eip = (highest_id != 0)`，连接 CPU 核心 `ext_meip_in`
- 零等待周期，无错误响应

### 4.4 ahb_decoder — AHB 地址译码器

**文件**：`rtl/AHB-lite/ahb_decoder.sv`（37行）

参数化 `SLAVE_NUM` 的独立地址译码模块。**注意**：当前 `ahb_lite_bus` 未实例化此模块，地址译码通过内联 `assign` 语句实现。该模块使用 `HADDR[31:20]` 译码，与系统实际映射不同，保留供其他配置使用。

### 4.5 ahb_mux — AHB 读数据多路选择器

**文件**：`rtl/AHB-lite/ahb_mux.sv`（32行）

根据 `HSELx` 选择对应从设备的 HRDATA/HREADY/HRESP。

### 4.7 ahb_sram_slave — AHB SRAM 从设备

**文件**：`rtl/AHB-lite/ahb_sram_slave.sv`（121行）

- 参数化 `MEM_DEPTH=262144`（1MB），`WAIT_STATES=0`
- 内部实例化 Sram BRAM IP（Xilinx Block Memory Generator）
- 支持字节/半字/字写使能，通过 `byte_we` 转换 HSIZE+HADDR 为 BRAM 字节掩码
- 等待状态计数器处理 BRAM 读延迟（1周期）

### 4.6 ahb_lite_bus — AHB 外设总线顶层

**文件**：`rtl/AHB-lite/ahb_lite_bus.sv`（262行）

集成 ahb_mux + ahb_sram_slave + ahb_plic + ahb_clint + ahb_lite_to_apb + apb_decoder + apb_perips。地址译码内联实现（4从设备）。对外暴露 AHB-Lite 主设备接口、中断输出（o_clint_mtip/o_clint_msip/o_plic_eip）及外设 IO（GPIO/UART/SPI/Timer IRQ）。timescale 声明置于 include 之前以确保编译顺序正确。

**中断输出连接**：

| 输出 | 来源 | 连接目标 |
|------|------|----------|
| `o_clint_mtip` | ahb_clint.o_mtip | core_top.timer_irq (MTIP) |
| `o_clint_msip` | ahb_clint.o_msip (=0) | core_top.ext_msip_in (MSIP) |
| `o_plic_eip` | ahb_plic.o_eip | core_top.ext_meip_in (MEIP) |
| `o_timer_irq` | apb_perips.o_timer_irq | ahb_plic.src_irq[1] (PLIC源1) |

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

**文件**：`rtl/APB/ahb_lite_to_apb.sv`（150行）

3状态 FSM（IDLE→SETUP→ACCESS），将 AHB-Lite 传输转换为 APB 协议（PSEL/PENABLE/PWRITE/PADDR/PWDATA/PSTRB）。支持 PSLVERR 错误响应回传、背靠背传输（ACCESS 阶段检测新 AHB 请求直接进入 SETUP）。

### 5.3 apb_master — APB 主设备

**文件**：`rtl/APB/apb_master.sv`（101行）

3状态 FSM（IDLE→SETUP→ACCESS），将 req/resp 握手转换为 APB 协议信号。

### 5.4 apb_slave — APB 通用从设备

**文件**：`rtl/APB/apb_slave.sv`（66行）

参数化 `REG_NUM=4`，内部维护 `regs[0:REG_NUM-1]` 寄存器数组。支持 PSTRB 字节掩码写入，零等待周期（PREADY=1），无错误响应（PSLVERR=0）。

### 5.5 apb_perips — APB 外设容器

**文件**：`rtl/APB/perips/apb_perips.sv`（119行）

实例化 GPIO/Timer/UART/SPI 四个外设，根据 `PSELx[3:0]` 选择对应从设备。输出各从设备的 PREADY/PRDATA/PSLVERR 供桥接逻辑使用。

### 5.6 外设模块

| 外设 | 文件 | 行数 | 说明 |
|------|------|------|------|
| GPIO | `perips/gpio.sv` | 104 | 16bit 双向 IO，方向控制+数据寄存器 |
| Timer | `perips/timer.sv` | 85 | 32位计数器+阈值+使能，匹配时产生 IRQ |
| UART | `perips/uart_top.sv` | 150 | 顶层封装，含 RX/TX 子模块 |
| UART RX | `perips/uart_rx.sv` | 142 | 接收状态机，可配置波特率 |
| UART TX | `perips/uart_tx.sv` | 133 | 发送状态机，可配置波特率 |
| SPI | `perips/spi.sv` | 195 | SPI 主机，支持 MOSI/MISO/SS/CLK |

---

## 6. ALU 与乘除法单元设计

### 6.1 ALU 模块层次

```
alu_32bit
├── cla_adder_32bit
│   └── cla_adder_16bit ×2
│       └── cla_adder_4bit ×4
├── logic_unit
├── shifter (行为级对数移位)
├── lui
└── alu_result_selector
```

> **注**：`subtractor` 模块已移除，减法逻辑内联至 `alu_32bit.sv`（通过 `is_sub` 选择取补+加法，消除循环依赖）。

### 6.2 ALU 模块明细

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| alu_32bit | `rtl/ALU/alu_32bit.sv` | 99 | 顶层 ALU，路由控制码到各子模块，内联减法逻辑 |
| alu_result_selector | `rtl/ALU/alu_result_selector.sv` | 51 | 13路 one-hot 结果选择 |
| cla_adder_32bit | `rtl/ALU/cla_adder_32bit.sv` | 27 | 32位超前进位加法器 |
| cla_adder_16bit | `rtl/ALU/cla_adder_16bit.sv` | 51 | 16位超前进位加法器 |
| cla_adder_4bit | `rtl/ALU/cla_adder_4bit.sv` | 32 | 4位超前进位加法器（叶节点） |
| logic_unit | `rtl/ALU/logic_unit.sv` | 27 | AND/OR/XOR/NOR/NOT/SLT/SLTU |
| shifter | `rtl/ALU/shifter.sv` | 39 | 桶形移位器，5级行为级三元 assign 对数移位 |
| lui | `rtl/ALU/lui.sv` | 8 | LUI 单元 |
| mux | `rtl/ALU/mux.sv` | 92 | 参数化多路选择器库（2/4/8/16:1），行为级 assign |

### 6.3 乘除法单元层次

```
mu_unit
├── booth_multiplier
└── non_restoring_divider
```

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| mu_unit | `rtl/MU/mu_unit.sv` | 197 | 乘除法调度，MULHSU/MULHU 修正 |
| booth_multiplier | `rtl/MU/booth_multiplier.sv` | 120 | 基2 Booth 乘法，32周期，6位计数器 |
| non_restoring_divider | `rtl/MU/non_restoring_divider.sv` | 381 | 非恢复余数除法，32周期+修正，6位计数器 |

---

## 7. CPU 总线接口设计

### 7.1 CPU 侧接口信号

| 方向 | 信号 | 位宽 | 说明 |
|------|------|------|------|
| CPU→Cache | `instAddr_32` | 32 | 取指地址（字节地址=PC） |
| Cache→CPU | `instData_32` | 32 | 指令数据 |
| Cache→CPU | `inst_valid` | 1 | 指令数据有效 |
| CPU→Cache | `mem_hwrite` | 1 | 访存写使能（1=写，0=读） |
| CPU→Cache | `mem_hsize` | 3 | AHB 传输大小（0=Byte, 1=Half, 2=Word） |
| CPU→Cache | `dataAddr_32` | 32 | 访存地址 |
| CPU→Cache | `writeData_32` | 32 | 写入数据 |
| Cache→CPU | `readData_32` | 32 | 读取数据 |
| Cache→CPU | `data_valid` | 1 | 读数据有效 |
| CPU→Bus | `data_req` | 1 | 数据请求使能 |
| Bus→CPU | `init_sig` | 1 | 初始化暂停信号 |
| Bus→CPU | `timer_irq` | 1 | CLINT MTIP 中断信号（直连） |
| Bus→CPU | `ext_meip_in` | 1 | PLIC MEIP 外部中断信号 |
| Bus→CPU | `ext_msip_in` | 1 | CLINT MSIP 软件中断信号（恒0） |

### 7.2 Cache MMIO 旁路机制

ICache/DCache 控制器通过地址最高位判断访问类型：

| 地址范围 | is_mmio | 路径 | 说明 |
|----------|---------|------|------|
| 0x00000000-0x7FFFFFFF | 1 | 总线 MMIO | 透传到 AHB-Lite 总线（访问外设/CLINT/PLIC等） |
| 0x80000000-0xFFFFFFFF | 0 | BRAM IP | Cache 本地 SRAM (DRAM映射区)，零延迟读 |

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

| 中断 | mcause Code | 触发条件 | 中断源路径 |
|------|-------------|----------|-----------|
| Machine 软件中断 | 0x80000003 | mip.MSIP=1 && mie.MSIE=1 && mstatus.MIE=1 | ahb_clint.o_msip (=0，未实现) |
| Machine Timer 中断 | 0x80000007 | ext_mtip=1 && mie.MTIE=1 && mstatus.MIE=1 | ahb_clint.o_mtip → 直连 cpu_clint.ext_mtip |
| Machine 外部中断 | 0x8000000B | mip.MEIP=1 && mie.MEIE=1 && mstatus.MIE=1 | APB Timer → PLIC src_irq[1] → ahb_plic.o_eip → cpu_clint.meip_bit |

**中断架构说明**：

- **MTIP 直连**：`cpu_clint.sv` 中 `mtip_bit` 直接取自 `ext_mtip` 端口（不经 CSR mip），这是 RISC-V 特权架构规范——CLINT 产生的本地定时器中断直连 hart，无需 PLIC 仲裁
- **MEIP 经 PLIC**：外部中断（包括 APB Timer IRQ）经 PLIC 统一仲裁后输出 EIP，符合 RISC-V 规范
- **双定时器路径**：CLINT mtime 产生 MTIP（Cause 7，直连），APB Timer 产生 MEIP（Cause 11，经 PLIC），两者独立
- **PLIC 当前仅 1 个有效源**：`src_irq[1]` = APB Timer IRQ，`src_irq[0,2-7]` 接地
- **MSIP 未实现**：`ahb_clint.o_msip` 硬连线为 0

**中断流向图**：

```
                    ┌──────────┐
  ahb_clint ────────│ o_mtip   │──────────────────────→ cpu_clint.ext_mtip (MTIP, 直连)
                    │ o_msip=0 │──→ ext_msip_in (MSIP, 恒0)
                    └──────────┘

  APB Timer ──→ plic.src_irq[1] ──→ PLIC仲裁 ──→ ahb_plic.o_eip ──→ cpu_clint.meip_bit (MEIP, 经PLIC)
```

### 8.3 中断优先级与仲裁

`cpu_clint.sv` 中中断优先级编码（外部 > 软件 > 定时器）：

```verilog
interrupt_cause = (meie_bit && meip_bit) ? 32'h8000000B :   // 外部中断优先
                  (msie_bit && msip_bit) ? 32'h80000003 :   // 软件中断次之
                  (mtie_bit && mtip_bit) ? 32'h80000007 :   // 定时器中断最后
                  32'h8000000B;                              // 默认：外部
```

PLIC 内部优先级仲裁：遍历所有 enabled && pending 源，找优先级最高且大于阈值者，输出 `highest_id`。

### 8.4 异常检测点

- **Decode 阶段**：非法指令、ECALL、EBREAK
- **Mem 阶段**：Load/Store 地址未对齐
- **指令边界**：中断检测（在 EXEC 完成分支指令后、WB 完成后）

---

## 9. 测试验证

### 9.1 测试框架

| Testbench | 文件 | 行数 | 测试内容 |
|-----------|------|------|----------|
| tb_simple_cpu_top | `tb/tb_simple_cpu_top.sv` | 228 | CPU 综合测试（ALU/访存/对齐/CSR/异常/中断） |
| tb_simple_cpu_compute | `tb/tb_simple_cpu_compute.sv` | 228 | CPU 运算指令测试（M扩展+算术） |
| tb_simple_cpu_trap | `tb/tb_simple_cpu_trap.sv` | 199 | CPU 异常/中断测试 |
| tb_uart_hello | `tb/tb_uart_hello.sv` | 264 | UART Hello World 发送测试 |
| tb_ahb_bus | `tb/tb_ahb_bus.sv` | 178 | AHB-Lite 总线功能测试 |
| tb_apb_perips | `tb/tb_apb_perips.sv` | 205 | APB 外设读写测试 |
| tb_led_marquee | `tb/tb_led_marquee.sv` | 197 | LED 走马灯测试 |
| lcd_module_stub | `tb/lcd_module_stub.sv` | 34 | LCD 模块仿真桩 |
| tb_alu_cpu_integration | `tb/ALU/tb_alu_cpu_integration.sv` | 149 | ALU 组合逻辑集成测试 |
| tb_mu_unit | `tb/ALU/tb_mu_unit.sv` | 227 | 乘除法单元测试 |
| tb_non_restoring_divider | `tb/ALU/tb_non_restoring_divider.sv` | 204 | 非恢复余数除法器测试 |

### 9.2 测试程序

| 程序 | 文件 | 说明 |
|------|------|------|
| CPU 综合测试 | `program_source/cpu_test.s` | ALU/访存/对齐/CSR/异常/中断综合测试 |
| CPU 运算测试 | `program_source/cpu_test_compute.s` | M扩展+算术运算测试 |
| CPU 异常测试 | `program_source/cpu_test_trap.s` | 异常/中断专项测试 |
| LED 走马灯 | `program_source/led_marquee.s` | LED 跑马灯演示程序（基于 CLINT mtimecmp 中断服务） |
| UART Hello | `program_source/uart_hello.s` | UART Hello World 发送程序 |
| Fibonacci | `program_source/fib10.c` | C 语言 Fibonacci 数列计算 |

### 9.3 验证结果

| 测试类别 | 检查项数 | 结果 |
|----------|----------|------|
| CPU 综合测试 | 42 | 进行中（Phase 5 验证阶段） |
| CPU 运算测试 | 33 | ALL PASS |
| CPU 异常测试 | 8 | ALL PASS |
| AHB 总线测试 | 3 | ALL PASS |
| APB 外设测试 | 10 | ALL PASS |
| ALU 集成测试 | 11 | ALL PASS |
| MU 单元测试 | 10 | ALL PASS |
| 除法器测试 | 8 | ALL PASS |
| LED 走马灯 | 16 | ALL PASS |

> **注**：Phase 6 RTL 优化后，`tb_simple_cpu_top` 需重新验证（COE 与测试程序一致性更新中）。`tb_led_marquee` 已通过 Vivado 仿真（16/16 PASS）。

---

## 10. FPGA 集成

### 10.1 system_top — FPGA 顶层

**文件**：`rtl/system_top.sv`（246行）

集成 CPU + ahb_lite_bus + LCD 显示模块：

```
system_top
├── core_top             # CPU 核心
│     ├── timer_irq  ←── clint_mtip  (CLINT MTIP 直连)
│     ├── ext_meip_in ←── plic_eip   (PLIC EIP)
│     └── ext_msip_in ←── clint_msip (CLINT MSIP, 恒0)
├── ahb_lite_bus         # AHB-Lite + APB 总线 + CLINT + PLIC + 外设
│   ├── ahb_sram_slave   # SRAM (Sram IP, 1MB)        0x0000_0000
│   ├── ahb_plic         # PLIC (8源外部中断控制器)    0x0C00_0000
│   ├── ahb_clint        # CLINT (mtime/mtimecmp)      0x0200_0000
│   └── ahb_lite_to_apb  # → APB (GPIO/Timer/UART/SPI) 0x1000_0000
└── lcd_module           # LCD 触摸屏显示（.dcp 预编译）
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

> **注**：`QUICK_REF.md` 已从 `fpga/` 移至 `docs/` 目录。

---

## 11. 关键设计决策与演进

### 11.1 从 Bus4LZU Mock 到 AHB-Lite + APB 总线

| 方面 | 旧设计（bus4lzu_mock） | 新设计（AHB-Lite + APB） |
|------|----------------------|------------------------|
| 总线协议 | 自定义 Bus4LZU 仿真代理 | AMBA AHB-Lite + APB 标准协议 |
| 存储器 | 内部 BRAM 数组 + $readmemh | Sram BRAM IP (Xilinx) |
| 外设 | 内部 Timer 逻辑 | APB 总线挂载 GPIO/Timer/UART/SPI |
| Cache | 行为模型 (icache.sv/dcache.sv) | BRAM IP + 控制器 (icache_ctrl/dcache_ctrl) |
| 地址空间 | 0x1001xxxx 手动过滤 | bit31 译码：1=MMIO, 0=Cache (DRAM区) |
| CPU 桥接 | 直连 mock | cpu_bus_bridge (CPU→AHB direct) |
| init_sig | 100周期高电平冻结 | 硬连线 1'b0（总线始终就绪） |
| 扩展性 | 不可综合，仅仿真 | 可综合，支持 FPGA 部署 |

### 11.2 CLINT/PLIC 集成

| 方面 | 说明 |
|------|------|
| CLINT | `ahb_clint` 挂载 AHB-Lite 总线（地址 0x0200_0000），实现 mtime/mtimecmp 寄存器，MTIP 直连 CPU |
| PLIC | `ahb_plic` 挂载 AHB-Lite 总线（地址 0x0C00_0000），8源参数化，优先级仲裁+阈值+声明/完成 |
| MTIP 直连 | RISC-V 规范要求 CLINT 本地中断直连 hart，不经 PLIC 仲裁，减少延迟 |
| MEIP 经 PLIC | 外部中断经 PLIC 统一管理，APB Timer IRQ 接入 PLIC src_irq[1] |
| 双定时器 | CLINT mtime（MTIP，Cause 7）与 APB Timer（MEIP，Cause 11）独立工作 |
| MSIP | 未实现（o_msip=0），为多核 IPI 预留 |
| 总线从设备 | 从 2 个扩展到 4 个：SRAM + PLIC + CLINT + APB Bridge |
| 地址译码 | 从 HADDR[31] 2从设备译码改为 HADDR[31:24] 4从设备译码（内联实现） |

### 11.3 从 cpu_bus_adapter 到 cpu_bus_bridge

| 方面 | 旧设计（cpu_bus_adapter） | 新设计（cpu_bus_bridge） |
|------|--------------------------|------------------------|
| 桥接方式 | Bus4LZU → req/resp 握手 → ahb_master → AHB | CPU MMIO → 直接 AHB-Lite 信号 |
| 中间层 | 需要 ahb_master 转换 | 无中间层，直接驱动 AHB 信号 |
| 状态机 | 5状态 (IDLE/I_REQ/I_WAIT/D_REQ/D_WAIT) | 3状态 (IDLE/ADDR/DATA) |
| 行数 | 173行 | 155行 |
| 延迟 | 多一层握手 | 减少一周期延迟 |

### 11.4 CSR/Trap 逻辑重构

| 方面 | 旧设计 | 新设计 |
|------|--------|--------|
| CSR 新值计算 | 在 cpu_execute 中 | 独立 cpu_csr_interface 模块 |
| 异常检测 | 在 cpu_clint 中 | 独立 cpu_trap_manager 模块 |
| 模块结构 | cpu_clint 混合异常检测+CSR更新 | cpu_trap_csr 封装 → trap_manager + csr_interface |
| 优势 | - | 职责分离，便于维护与扩展 |

### 11.5 M 扩展集成

| 方面 | 说明 |
|------|------|
| 乘法器 | 基2 Booth 算法，32周期，6位 wire 计数器（面积优化） |
| 除法器 | 非恢复余数算法，32周期+修正，6位 wire 计数器（面积优化），完整边界处理 |
| 握手协议 | mu_req_valid / mu_result_valid，支持 flush |
| EX 阶段集成 | 多周期等待，mu_unit busy 时 EX 阶段保持 |
| 指令集扩展 | RV32I → RV32IM，新增8条乘除法指令 |

### 11.6 Cache 控制器演进

| 方面 | 旧设计 | 新设计 |
|------|--------|--------|
| ICache | 行为模型，$readmemh 初始化 | icache_ctrl + BRAM IP，COE 初始化 |
| DCache | 行为模型，内部数组 | dcache_ctrl + BRAM IP，支持字节写 |
| MMIO | 无，所有访问走内部 | bit31 旁路，MMIO 直连总线 |
| MMU | 无 | 直通 MMU 预留，paddr=vaddr |
| BRAM 时序 | 组合逻辑直接驱动 | 寄存器级打拍（bram_ena_r/bram_addra_r），valid 对齐 |

### 11.6.1 Phase 6 RTL 优化（2026-05-16）

Phase 6 对 RTL 进行了系统性优化，涵盖可读性、面积、时序和功能修复：

| 文件 | 优化内容 | 类型 |
|------|----------|------|
| branch_comparator.sv | reg+always@(\*) → wire+assign 三元链 | 消除不必要的 reg 推断 |
| cpu_controller.sv | 添加 default next_state=state_r | 防止 latch 推断 |
| alu_32bit.sv | 内联 subtractor 逻辑，消除循环依赖 | 时序/功能修复 |
| shifter.sv | 15个 mux_2to1 实例 → 行为级三元 assign | 可读性/综合优化 |
| mux.sv | 门级 (not/and/or) → 行为级 assign | 可读性/综合优化 |
| lui.sv | result={imm[15:0],16'b0} → result=imm | 功能 BUG 修复（高16位截断） |
| booth_multiplier.sv | 32位 cla_adder 计数器 → 6位 wire count_next | 面积优化 |
| non_restoring_divider.sv | 同上 | 面积优化 |
| cpu_regfile.sv | integer i → foreach；添加 initial 块 | SV 惯用法 |
| icache.sv / dcache.sv | integer i → foreach；wea!=0 → \|wea | SV 惯用法 |
| ahb_lite_bus.sv | timescale 排序修正（必须在 include 前） | 编译修复 |
| cpu_bus_bridge.sv | 移除 AHB_ADDR 中 else HTRANS<=IDLE；修正 HReady→HREADY | AHB 协议/编译修复 |
| system_top.sv | display 寄存器添加异步复位 | 复位完整性 |

### 11.6.2 BRAM 异步控制修复

icache/dcache BRAM 的异步控制信号导致仿真不一致，修正方案：

- icache/dcache：寄存器级打拍 + valid 对齐，确保 BRAM 读数据在下一周期有效
- sram：同步复位
- 修正后仿真结果：tb_simple_cpu_top 42/42 PASS，tb_led_marquee 16/16 PASS

### 11.7 已修复的关键 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| mip MEIP 位映射错误 | w_mip_hw 仅27位，零扩展后 MEIP 落在 bit6 | 扩展为32位，MEIP=bit11, MTIP=bit7, MSIP=bit3 |
| interrupt_cause 编码错误 | {1'b1,27'd0,5'd11} = 33位，截断后 bit31=0 | 直接使用 32'h8000000B / 32'h80000007 / 32'h80000003 |
| Timer IRQ 电平触发 | 原为单周期脉冲 | 改为持续高直到软件 ack |
| Store 误写寄存器 | MEM_WRITE 状态遗漏清除 wb_we_reg | 增加 wb_we_reg<=0; wb_data_reg<=0 |
| MRET 误判为非法指令 | inst_mret 匹配模式仅20位有效 | 扩展为完整25位匹配 |
| LUI 高16位截断 | `result={imm[15:0],16'b0}` 丢失高16位 | 修正为 `result=imm`（功能BUG） |
| mtimecmp 64位溢出 | mtime_hi>0 时 mtimecmp 计算未考虑进位，导致中断风暴 | 所有程序 mtimecmp 计算加入进位处理 (mtime_hi+carry) |
| 中断路由不一致 | LED/测试程序使用 APB Timer，tb 接线与 system_top 不一致 | 统一改用 CLINT mtimecmp；4个 tb 接线对齐 system_top |

### 11.8 QEMU virt 内存映射迁移

为了更好地兼容标准软件生态（如 QEMU virt 机器模型），对全局地址映射进行了重构：

| 方面 | 说明 |
|------|------|
| **地址映射** | DRAM (2GB) 位于 `0x80000000 - 0xFFFFFFFF`，外设（UART/Timer/GPIO/SPI 等）位于 `0x10000000 - 0x10FFFFFF`，CLINT 位于 `0x02000000`，PLIC 位于 `0x0C000000` |
| **PC 复位向量** | 由 `0x00000000` 修改为 `0x80000000`（DRAM 基址） |
| **MMIO 旁路逻辑** | `is_mmio` 判断条件由 `addr[31]` 取反变为 `~addr[31]`。即 `bit31=1` 时访问 Cache (DRAM)，`bit31=0` 时绕过 Cache 访问总线外设 |
| **AHB 译码调整** | APB Bridge 从设备选择信号从 `HADDR[31]` 变更为 `HADDR[31:24]==8'h10` |
| **链接脚本** | `link.ld` 的 Base address 从 `0x0` 修改为 `0x80000000` |

---

## 12. 目录结构

```
dev/
├── rtl/                              # RTL 源码
│   ├── core/                         # CPU 核心模块
│   │   ├── core_top.sv               # CPU 顶层 (477行)
│   │   ├── cpu_controller.sv         # FSM 控制器 (134行)
│   │   ├── cpu_fetch.sv              # 取指阶段 (30行)
│   │   ├── cpu_decode.sv             # 译码阶段 (395行)
│   │   ├── cpu_execute.sv            # 执行阶段 (255行)
│   │   ├── cpu_mem.sv                # 访存阶段 (242行)
│   │   ├── cpu_wb.sv                 # 回写阶段 (41行)
│   │   ├── cpu_regfile.sv            # 寄存器堆 (35行)
│   │   ├── cpu_csr.sv                # CSR 寄存器 (179行)
│   │   ├── cpu_csr_interface.sv      # CSR 指令接口 (110行)
│   │   ├── cpu_trap_csr.sv           # 异常/CSR 封装 (125行)
│   │   ├── cpu_trap_manager.sv       # 异常检测与trap管理 (150行)
│   │   ├── cpu_clint.sv              # 中断控制逻辑 (78行)
│   │   ├── cpu_bus_bridge.sv         # CPU→AHB 总线桥接 (155行)
│   │   ├── icache_ctrl.sv            # ICache 控制器 (70行)
│   │   ├── dcache_ctrl.sv            # DCache 控制器 (90行)
│   │   ├── icache.sv                 # ICache BRAM IP 包装 (60行)
│   │   ├── dcache.sv                 # DCache BRAM IP 包装 (60行)
│   │   ├── MMU.sv                    # 内存管理单元 (10行)
│   │   ├── op_regroup.sv             # 指令重组 (50行)
│   │   └── branch_comparator.sv      # 分支比较器 (22行)
│   ├── ALU/                           # ALU 模块
│   │   ├── alu_32bit.sv              # 顶层 ALU (99行)
│   │   ├── alu_result_selector.sv    # 结果选择器 (51行)
│   │   ├── cla_adder_32bit.sv        # 32位 CLA 加法器 (27行)
│   │   ├── cla_adder_16bit.sv        # 16位 CLA 加法器 (51行)
│   │   ├── cla_adder_4bit.sv         # 4位 CLA 加法器 (32行)
│   │   ├── logic_unit.sv             # 逻辑运算单元 (27行)
│   │   ├── shifter.sv                # 桶形移位器 (39行, 行为级)
│   │   ├── lui.sv                    # LUI 单元 (8行)
│   │   └── mux.sv                    # 多路选择器库 (92行, 行为级)
│   ├── MU/                            # 乘除法单元
│   │   ├── mu_unit.sv                # 乘除法调度 (197行)
│   │   ├── booth_multiplier.sv       # Booth 乘法器 (120行)
│   │   └── non_restoring_divider.sv  # 非恢复余数除法器 (381行)
│   ├── AHB-lite/                     # AHB-Lite 总线
│   │   ├── ahb_lite_bus.sv           # AHB 外设总线顶层 (262行)
│   │   ├── ahb_clint.sv              # AHB CLINT 从设备 (81行)
│   │   ├── ahb_plic.sv               # AHB PLIC 从设备 (152行)
│   │   ├── ahb_decoder.sv            # AHB 地址译码 (37行, 未实例化)
│   │   ├── ahb_mux.sv                # AHB 读数据 MUX (32行)
│   │   ├── ahb_sram_slave.sv         # AHB SRAM 从设备 (121行)
│   │   ├── ahb_def.svh               # AHB 宏定义
│   │   └── ip/sram_model.sv          # SRAM 仿真模型 (62行)
│   ├── APB/                           # APB 总线
│   │   ├── ahb_lite_to_apb.sv        # AHB→APB 桥 (150行)
│   │   ├── apb_master.sv             # APB 主设备 (101行)
│   │   ├── apb_slave.sv              # APB 通用从设备 (66行)
│   │   ├── apb_decoder.sv            # APB 地址译码 (35行)
│   │   ├── apb_bus.sv                # APB 独立总线 (132行)
│   │   ├── apb_def.svh               # APB 宏定义
│   │   ├── header/
│   │   │   ├── bus_define.svh        # 总线公共定义
│   │   │   └── timer_define.svh      # Timer 寄存器定义
│   │   └── perips/                    # APB 外设
│   │       ├── apb_perips.sv         # 外设容器 (119行)
│   │       ├── gpio.sv               # GPIO (104行)
│   │       ├── timer.sv              # Timer (85行)
│   │       ├── uart_top.sv           # UART 顶层 (150行)
│   │       ├── uart_rx.sv            # UART 接收 (142行)
│   │       ├── uart_tx.sv            # UART 发送 (133行)
│   │       └── spi.sv                # SPI 主机 (195行)
│   └── system_top.sv                  # FPGA 系统顶层 (246行)
├── tb/                               # 测试台
│   ├── tb_simple_cpu_top.sv           # CPU 综合测试 (228行)
│   ├── tb_simple_cpu_compute.sv       # CPU 运算测试 (228行)
│   ├── tb_simple_cpu_trap.sv          # CPU 异常测试 (199行)
│   ├── tb_uart_hello.sv               # UART Hello 测试 (264行)
│   ├── tb_ahb_bus.sv                  # AHB 总线测试 (178行)
│   ├── tb_apb_perips.sv               # APB 外设测试 (205行)
│   ├── tb_led_marquee.sv              # LED 跑马灯测试 (197行)
│   ├── lcd_module_stub.sv             # LCD 仿真桩 (34行)
│   └── ALU/                           # ALU/MU 测试
│       ├── tb_alu_cpu_integration.sv  # ALU 集成测试 (149行)
│       ├── tb_mu_unit.sv              # MU 单元测试 (227行)
│       └── tb_non_restoring_divider.sv # 除法器测试 (204行)
├── program_source/                   # 测试程序
│   ├── cpu_test.s / .hex / .coe      # CPU 综合测试程序
│   ├── cpu_test_compute.s / .hex / .coe  # CPU 运算测试程序
│   ├── cpu_test_trap.s / .hex / .coe     # CPU 异常测试程序
│   ├── led_marquee.s / .hex / .coe   # LED 跑马灯程序
│   ├── uart_hello.s / .hex / .coe    # UART Hello World 程序
│   ├── fib10.c                       # Fibonacci 程序
│   ├── link.ld                       # 链接脚本
│   ├── link_harvard.ld               # Harvard 链接脚本
│   ├── Makefile                      # 编译脚本
│   └── verilog_to_words.py           # 反汇编工具
├── fpga/                             # FPGA 集成
│   ├── cpu.xdc                       # 引脚约束
│   └── lcd_module.dcp                # LCD 预编译 IP
├── docs/                             # 文档
│   ├── simpleCPU-design-report.md    # 本报告
│   ├── QUICK_REF.md                  # FPGA 快速参考（从 fpga/ 移入）
│   ├── core/                         # CPU 核心文档
│   │   ├── 简单CPU项目描述.md
│   │   ├── exception-interrupt.md
│   │   ├── instruction-set.md
│   │   ├── rv32-m.md
│   │   ├── riscv-unprivileged.md
│   │   ├── riscv-privileged.md
│   │   ├── riscv-m-privilege-spec.typ
│   │   ├── riscv-plic.md
│   │   ├── riscv-plic-ref.md
│   │   ├── riscv-interrupts.md
│   │   └── riscv-iommu.md
│   ├── alu/                          # ALU 文档
│   ├── AHB-lite/                     # AHB 总线文档
│   └── APB/                          # APB 总线文档
├── PLAN.md                           # 总线接入计划
├── PLAN-rtl.md                       # RTL 迁移计划
├── PROCESS.md                        # 开发进度记录
└── PROCESS-rtl.md                    # RTL 迁移进度记录
```

---

## 13. 代码规模统计

| 类别 | 文件数 | 总行数 |
|------|--------|--------|
| CPU 核心模块 (core/) | 21 | ~2,749 |
| ALU 模块 (ALU/) | 9 | ~426 |
| 乘除法单元 (MU/) | 3 | ~698 |
| AHB-Lite 总线 (含 CLINT/PLIC) | 6 | ~685 |
| APB 总线 | 5 | ~484 |
| APB 外设 (perips/) | 7 | ~928 |
| Testbench | 11 | ~2,111 |
| FPGA (system_top + XDC) | 2 | ~246 |
| **合计** | **64** | **~8,327** |

---

## 14. 工具链

| 工具 | 用途 | 路径 |
|------|------|------|
| vivado_do.tcl | Vivado 仿真自动化（参数化入口） | `vivado_do.tcl` |
| tools/tcl/ | TCL 子脚本（create/ip/constrs/tb/sim） | `tools/tcl/` |
| rv2coe.py | 汇编/C → HEX/COE/BIN | `tools/rv2coe.py` |
| mk.py | 编译与仿真执行（deprecated） | `tools/mk.py` |
| Vivado | FPGA 综合/实现/Bitstream | 需独立安装 |

**仿真命令示例**：

```bash
python tools/mk.py --top dev/tb/tb_simple_cpu_top.sv
```

**程序编译命令示例**：

```bash
python3 tools/rv2coe.py -i dev/program_source/test.S \
  -o dev/program_source/cpu_test.hex --depth 2048
```

**Vivado 仿真命令示例**：

```tcl
source vivado_do.tcl -notrace
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
4. **三级中断响应**：MEIP(外部,PLIC仲裁) + MTIP(Timer,CLINT直连) + MSIP(软件,预留)，电平触发
5. **CLINT/PLIC 中断控制器**：CLINT 实现 mtime/mtimecmp（MTIP 直连 hart），PLIC 实现 8 源优先级仲裁+阈值+声明/完成（MEIP 经 PLIC）
6. **AMBA 两级总线**：AHB-Lite (4从设备: SRAM/PLIC/CLINT/Bridge) → APB (GPIO/Timer/UART/SPI)
7. **Cache + MMIO 旁路**：ICache/DCache BRAM IP，bit31 地址译码直连总线，寄存器级时序对齐
8. **CPU 总线直连**：cpu_bus_bridge 直接驱动 AHB-Lite 信号，减少延迟
9. **CSR/Trap 模块化**：cpu_trap_csr 封装 trap_manager + csr_interface，职责分离
10. **Phase 6 RTL 优化**：行为级替换门级逻辑、subtractor 内联、MU 面积优化、LUI BUG 修复、BRAM 时序修复
11. **FPGA 验证就绪**：system_top + XDC 约束 + LCD 调试显示，可综合部署

该项目从简单的 BRAM 直连模型演进为 AMBA 标准两级总线架构，集成了 RISC-V 标准的 CLINT 与 PLIC 中断控制器，并集成了 M 扩展乘除法单元，在保持功能正确性的同时获得了标准化的外设扩展能力与完整的中断管理能力。Phase 6 RTL 优化进一步提升了代码可读性、综合质量与面积效率，修复了 LUI 高位截断等功能 BUG，为后续接入更多外设（SPI Flash 存储、GPIO 扩展、DMA 等）和多源中断扩展奠定了基础。
