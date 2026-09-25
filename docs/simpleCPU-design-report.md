# SimpleCPU 设计报告

> 生成日期: 2026-09-25 | 项目路径: `src/`（src/core、src/soc、src/common）

---

## 1. 项目概述

本项目实现了一个基于 RISC-V RV32IMASU 指令集的多周期单发射按序 CPU，数据通路分为取指-译码-执行-访存-回写五级，由有限状态机（FSM）控制器逐级推进（每时钟周期仅一级活跃，非流水线）。CPU 通过 AXI4 总线连接片上存储与外设，支持异常/中断陷阱处理、CSR 读写、A 扩展原子运算（LR/SC/AMO）、M 扩展乘除法运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32IMASU（整数 + 原子 + 乘除法 + S/U 特权，含 Zicsr/Zifencei），misa=0x40141101 |
| 架构 | 多周期 FSM 控制，单发射按序五级数据通路（每时钟周期仅一级活跃） |
| 数据位宽 | 32-bit |
| 特权模式 | M/S/U 三级特权模式，支持陷阱委托（medeleg/mideleg） |
| 地址空间 | 32-bit，Sv32 页表虚拟内存（MMU + TLB + PTW） |
| PMP | 16 项 base-PMP（pmpcfg0-3 / pmpaddr0-15），TOR/NA4/NAPOT 模式，取指/数据/PTW 三处检查点，M 模式默认放行 |
| 存储架构 | 哈佛结构（icache / dcache 分离），2 路 × 8 组 × 32B 行（各 512B），每组 1-bit victim 替换，PIPT（物理索引物理标记） |
| 缓存策略 | ICache 缺失填充；DCache 写通（write-through），store miss 不分配 |
| 标签存储 | RTL 寄存器数组（每组 2 路 valid + 24-bit tag） |
| TLB 架构 | 统一 Sv32 TLB：16 项全相联寄存器数组（victim 替换），I/D 侧共享单查找端口与单 PTW |
| 总线接口 | AXI4 Master（cpu_bus_bridge），读支持 INCR8 突发（refill）、写为单拍；AXI4-Lite 从设备（PLIC/CLINT/BootROM/SysStatus/APB Bridge） |
| 中断/异常 | 支持 Trap 进入/返回（mret/sret）、CLINT 定时器中断、PLIC 外部中断 |
| 特权指令 | SRET、SFENCE.VMA 指令支持 |
| 乘法器 | Booth 编码，32 周期迭代 |
| 除法器 | 非恢复余数法，32 周期迭代 + 修正 |
| 加法器 | 超前进位加法器（CLA），16-bit 级联为 32-bit |
| 启动 ROM | AXI4-Lite Boot ROM（0xFC00_0000），32KB BRAM，CPU 复位起始地址，bootloader 跳转至 DDR3/SRAM |
| DDR3 SDRAM | AXI4 MIG 接口（axi_wrap_ddr），可选 ROM 行为模型（axi_wrap_ram） |
| 时钟域 | cpu_clk（40MHz，时序收敛 WNS +0.459）/ sys_clk（100MHz）/ ddr_clk_ref（200MHz），Axi_CDC 跨域 |
| 系统状态 | AXI4-Lite Sys Status（0x0400_0000），MIG 校准/MMCM 锁定/clk_wiz 锁定 |
| 起始地址 | `0xFC00_0000`（Boot ROM，复位后跳转至 `0x8000_0000`） |

### 1.2 支持的指令集

**RV32I 基础整数指令及 Zicsr/Zifencei/特权指令（共 51 条 = RV32I 40 + CSR 6 + FENCE.I 1 + MRET/SRET/SFENCE.VMA/WFI 4）：**

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

**RV32A 原子扩展（11 条）：**

| 类别 | 指令 | 说明 |
|------|------|------|
| Load-Reserved | `LR.W rd, (rs1)` | 加载保留，设置保留集（reservation set） |
| Store-Conditional | `SC.W rd, rs2, (rs1)` | 条件存储，检查保留集有效性，成功写回返回 0，失败返回 1 |
| AMO 加算 | `AMOADD.W rd, rs2, (rs1)` | 原子加：rs2 + mem[rs1] |
| AMO 按位与 | `AMOAND.W rd, rs2, (rs1)` | 原子与：rs2 & mem[rs1] |
| AMO 按位或 | `AMOOR.W rd, rs2, (rs1)` | 原子或：rs2 \| mem[rs1] |
| AMO 按位异或 | `AMOXOR.W rd, rs2, (rs1)` | 原子异或：rs2 ^ mem[rs1] |
| AMO 有符号最大 | `AMOMAX.W rd, rs2, (rs1)` | 原子最大值（有符号比较） |
| AMO 无符号最大 | `AMOMAXU.W rd, rs2, (rs1)` | 原子最大值（无符号比较） |
| AMO 有符号最小 | `AMOMIN.W rd, rs2, (rs1)` | 原子最小值（有符号比较） |
| AMO 无符号最小 | `AMOMINU.W rd, rs2, (rs1)` | 原子最小值（无符号比较） |
| AMO 交换 | `AMOSWAP.W rd, rs2, (rs1)` | 原子交换：rs2 ↔ mem[rs1] |

> **实现说明**：LR.W 在 dcache 中设置保留集（reservation set）；SC.W 检查保留集是否仍然有效，仅在有效时执行写入并在 rd 返回 0，否则返回 1。AMO 操作在 `cpu_mem.sv` 中通过读-改-写（read-modify-write）周期原子执行。所有 A 扩展指令使用 OPCODE_AMO（0b0101111）。

> F/D 扩展未实现：misa=0x40141101（RV32IMASU），纯整数核，src/ 下无任何浮点模块。

---

## 2. 系统架构

### 2.1 顶层结构

```
system_top
├── Clock/Reset Architecture
│   ├── clk_wiz_0 (or sim direct)     ← 100MHz→40MHz CPU + 100MHz sys + 200MHz DDR ref
│   ├── reset_sync (×2)               ← Async assert, sync deassert (sys + cpu domains)
│   └── ddr_data_init / ddr_aresetn   ← DDR3 init gating (sim vs FPGA)
├── core_top              ← CPU 核心 (cpu_clk domain)
│   ├── cpu_controller    ← FSM 状态机控制器
│   ├── cpu_fetch         ← 取指级
│   ├── cpu_decode        ← 译码级
│   ├── cpu_execute       ← 执行级（含 ALU + MU）
│   ├── cpu_mem           ← 访存级
│   ├── cpu_wb            ← 回写级
│   ├── cpu_regfile       ← 32×32bit 整数寄存器堆
│   ├── cpu_trap_csr      ← 陷阱/CSR 子系统
│   ├── icache_ctrl       ← 指令缓存控制器（2路组相联，PIPT）
│   ├── dcache_ctrl       ← 数据缓存控制器（2路组相联，写通+不写分配，PIPT）
│   ├── MMU                ← Sv32 统一实例（双 i/d 接口，共享 TLB + PTW 页表漫游）
│   └── cpu_bus_bridge    ← AXI4 总线桥接（MMIO + INCR8 突发，AW/W/B/AR/R 五通道）
├── Axi_CDC               ← AXI4 时钟域穿越（cpu_clk → sys_clk）
├── Address Decoder + Slave Mux  ← 手动地址译码 + 7 从设备多路复用（sys_clk domain）
│   ├── Slave 0: DDR3/RAM (axi_wrap_ddr / axi_wrap_ram)  ← 全 AXI4，区域 0x8000_0000~0x87FF_FFFF（128MB）
│   ├── Slave 1: Boot ROM (axi4lite_bootrom)              ← AXI4-Lite，区域 0xFC00_0000~0xFC00_7FFF（32KB）
│   ├── Slave 2: PLIC (axi4lite_plic)                     ← AXI4-Lite，区域 0x0C00_0000~0x0CFF_FFFF（16MB）
│   ├── Slave 3: CLINT (axi4lite_clint)                   ← AXI4-Lite，区域 0x0200_0000~0x0200_FFFF（64KB）
│   ├── Slave 4: APB Bridge (axi4lite_to_apb)             ← AXI4-Lite，仅 GPIO/UART/SPI 三个 4KB 窗口
│   │   ├── apb_decoder
│   │   └── apb_perips
│   │       ├── GPIO          ← 16-bit 双向 IO，引脚变化中断（o_irq→PLIC src[4]）
│   │       ├── UART (ns16550a) ← ns16550a 标准串口，16-byte TX/RX FIFO，中断（o_irq→PLIC src[2]），APB4 封装
│   │       └── SPI            ← 主模式 SPI，传输完成中断（o_irq→PLIC src[3]）
│   ├── Slave 5: Sys Status (axi4lite_sys_status)         ← AXI4-Lite，区域 0x0400_0000~0x0400_0FFF（4KB）
│   └── Slave 6: Default Slave (axi4lite_default_slave)   ← AXI4-Lite，DECERR 响应
├── DDR3 Conditional Generate
│   ├── SIMU_USE_DDR=0: axi_wrap_ram  ← BRAM 行为模型（零延迟，快速仿真）
│   └── SIMU_USE_DDR=1: axi_wrap_ddr  ← MIG + DDR3 SDRAM（真实硬件通路）
```

FPU 未实现（当前 ISA 为 RV32IMASU，无 F 扩展；src/ 中无任何 fpu_* 模块）

### 2.2 地址映射（Memory Map）

#### 2.2.1 顶层地址译码

`system_top` 内手动实现 7 从设备地址译码，优先级从高到低（译码逻辑为组合优先级）：

| 从设备编号 | 判定条件 | 地址范围 | 从设备 | 总线协议 | 说明 |
|-----------|----------|----------|--------|----------|------|
| Slave 0 | `addr ∈ [0x8000_0000, 0x8800_0000)` | `0x8000_0000 ~ 0x87FF_FFFF` | DDR3/RAM | AXI4 | 主存储器（128MB 窗口） |
| Slave 1 | `addr ∈ [0xFC00_0000, 0xFC00_8000)` | `0xFC00_0000 ~ 0xFC00_7FFF` | Boot ROM | AXI4-Lite | 启动 ROM（32KB BRAM，只读） |
| Slave 2 | `addr ∈ [0x0C00_0000, 0x0D00_0000)` | `0x0C00_0000 ~ 0x0CFF_FFFF` | PLIC | AXI4-Lite | 平台级中断控制器（8 源） |
| Slave 3 | `addr ∈ [0x0200_0000, 0x0201_0000)` | `0x0200_0000 ~ 0x0200_FFFF` | CLINT | AXI4-Lite | 核心本地中断器 |
| Slave 4 | GPIO/UART/SPI 三个 4KB 窗口 | `0x1000_0000~0x1000_0FFF` / `0x1000_8000~0x1000_8FFF` / `0x1000_C000~0x1000_CFFF` | APB Bridge | AXI4-Lite | 外设桥（GPIO/UART/SPI） |
| Slave 5 | `addr ∈ [0x0400_0000, 0x0400_1000)` | `0x0400_0000 ~ 0x0400_0FFF` | Sys Status | AXI4-Lite | 系统状态（只读） |
| Slave 6 | 其他 | 未映射 | Default Slave | AXI4-Lite | 返回 DECERR 响应 |

> **注意**：所有从设备判定均使用 `addr_in_region(addr, base, size)` 显式区域检查（基址/大小定义于 `src/common/address_map.svh`），非位切片比较。未落入任何区域的访问路由到 Default Slave（DECERR）。

**Cache/MMIO 判定规则**：仅当物理地址落在 DDR 窗口 `0x8000_0000 ≤ paddr < 0x8800_0000`（`SOC_DDR_BASE ~ SOC_DDR_BASE+SOC_DDR_SIZE`）时为 Cacheable 区域（走 icache/dcache），其余地址（含 BootROM、PLIC、CLINT、APB 外设）一律不可缓存，直接走 AXI 单拍访问。判定使用物理地址（paddr，TLB 翻译后）。

#### 2.2.2 完整内存映射图

```
0xFFFF_FFFF ┌──────────────────────┐
            │     未映射区域        │ → Default Slave (DECERR)
0xFC00_8000 ├──────────────────────┤
            │     Boot ROM         │ 0xFC00_0000 (Slave 1, 32KB BRAM, 只读)
0xFC00_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x8800_0000 ├──────────────────────┤
            │     DDR3/RAM         │ 0x8000_0000 (Slave 0, 主存储器, Cacheable)
0x8000_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x1100_0000 ├──────────────────────┤
            │     APB Bridge       │ 0x1000_0000 (Slave 4, 外设桥)
             │  ├─ 0x1000_0000 GPIO  (PSELx[0], PADDR[15:14]==00)
             │  ├─ 0x1000_8000 UART  (PSELx[2], PADDR[15:14]==10, ns16550a)
            │  └─ 0x1000_C000 SPI   (PSELx[3], PADDR[15:14]==11)
0x1000_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x0D00_0000 ├──────────────────────┤
            │     PLIC             │ 0x0C00_0000 (Slave 2, 8 源中断控制器)
0x0C00_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x0500_0000 ├──────────────────────┤
            │     Sys Status       │ 0x0400_0000 (Slave 5, 只读)
0x0400_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x0300_0000 ├──────────────────────┤
            │     CLINT            │ 0x0200_0000 (Slave 3, 定时器中断)
0x0200_0000 ├──────────────────────┤
            │     未映射区域        │ → Default Slave (DECERR)
0x0000_0000 └──────────────────────┘
```

#### 2.2.3 CLINT 寄存器映射

基地址：`0x0200_0000`，AXI4-Lite，按 `addr[15:0]` 译码（标准 SiFive CLINT 布局）：

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x0000 | msip | RW | 软件中断挂起（写 [0] 位设置/清除 MSIP） |
| 0x4000 | mtimecmp_lo | RW | 定时器比较值低 32 位 |
| 0x4004 | mtimecmp_hi | RW | 定时器比较值高 32 位 |
| 0xBFF8 | mtime_lo | RW | 定时器计数值低 32 位（mtime 由 sys_clk 100MHz 驱动自增） |
| 0xBFFC | mtime_hi | RW | 定时器计数值高 32 位 |

> 中断产生条件：`mtime[63:0] >= mtimecmp[63:0]` 时 MTIP=1。

> **CLINT 标准地址布局**：寄存器布局遵循 SiFive CLINT 标准（msip @ 0x0000, mtimecmp @ 0x4000, mtime @ 0xBFF8），Linux 标准 sifive_clint 驱动可直接使用。mtime 由 sys_clk（100MHz）驱动，非 cpu_clk（40MHz）。

#### 2.2.4 PLIC 寄存器映射

基地址：`0x0C00_0000`，AXI4-Lite，支持 8 个中断源（NUM_SRC=8），双上下文（NUM_CTX=2）：

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x000000 ~ 0x00001C | priority[0:7] | RW | 每源优先级（4 字节对齐，addr[7:2] 索引；仅低 3 位有效，WARL 0..7；priority[0] 保留——写被忽略，读恒 0） |
| 0x001000 | pending | R | 中断挂起状态（32-bit，只读，硬件置位） |
| 0x002000 + N×0x80 | enable[ctx N] | RW | 中断使能掩码（32-bit，每源 1 位），N=0:M-mode, N=1:S-mode |
| 0x200000 + N×0x1000 | threshold[ctx N] | RW | 优先级阈值（仅优先级 > threshold 的中断可 claim） |
| 0x200004 + N×0x1000 | claim/complete[ctx N] | RW | 声明最高优先级中断（读返回 ID，写完成处理） |

> PLIC 中断路由：src[0] 保留，**src[1] 未使用（APB Timer 已移除，恒为 0）**，src[2]=UART, src[3]=SPI, src[4]=GPIO。8 个中断源，优先级 0-7（3-bit WARL）。Context 0: M-mode (o_eip[0]→mip[11])，Context 1: S-mode (o_eip[1]→mip[9])。SiFive 标准地址布局，Linux irq-sifive-plic.c 驱动可直接使用。

#### 2.2.5 APB 外设地址子译码

APB Bridge 仅在 GPIO/UART/SPI 三个 4KB 窗口被顶层译码选中；桥内 `apb_decoder` 仍按 4 槽位 `PADDR[15:14]` 译码，但槽 1（原 Timer）已移除，`apb_perips` 对该槽防御性返回 PSLVERR（实际不可达——该窗口根本不会路由到 APB 桥）：

| APB 槽位 | 判定条件 | 基地址 | 顶层可路由窗口 | 说明 |
|-----------|----------|--------|----------|------|
| GPIO（槽 0） | `PADDR[15:14]==2'b00` | `0x1000_0000` | `0x1000_0000 ~ 0x1000_0FFF` | 16-bit 双向 IO |
| （槽 1，无设备） | `PADDR[15:14]==2'b01` | （原 `0x1000_4000`） | 不可路由（→ Default Slave DECERR） | APB Timer 已移除 |
| UART（槽 2） | `PADDR[15:14]==2'b10` | `0x1000_8000` | `0x1000_8000 ~ 0x1000_8FFF` | ns16550a 标准串口 |
| SPI（槽 3） | `PADDR[15:14]==2'b11` | `0x1000_C000` | `0x1000_C000 ~ 0x1000_CFFF` | 主模式 SPI |

**GPIO 寄存器映射**（基址 `0x1000_0000`）：

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | CTRL | 方向控制（1=输出，0=输入） |
| 0x04 | DATA | 数据寄存器 |
| 0x08 | IRQ_EN | 逐引脚中断使能掩码 |
| 0x0C | IRQ_STAT | 逐引脚中断挂起（写 1 清除） |

**Timer 寄存器映射**：APB Timer 已移除，槽 1 返回 PSLVERR

**UART 寄存器映射**（基址 `0x1000_8000`，ns16550a 标准）：

文件：`src/soc/devices/uart16550/top.sv`（模块 `uart_16550a`，核心 `uart_regs_16550a` 位于 `src/soc/devices/uart16550/registers.sv`），通过 APB4 接口封装在 `src/soc/devices/apb_peripherals.sv` 中。APB4 总线为字对齐寻址：`PADDR[4:2]` 映射 NS16550A 寄存器索引 0-7：

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | THR/RBR/DLL | DLAB=0：写 THR/读 RBR；DLAB=1：DLL 除数锁存低字节 |
| 0x04 | IER/DLM | DLAB=0：中断使能（[0]RDA [1]THRE [2]RLS [3]MS）；DLAB=1：DLM 高字节 |
| 0x08 | FCR/IIR | 写：FIFO 控制（[7:6]触发水平 [2]TX 复位 [1]RX 复位 [0]FIFO 使能）；读：中断识别 |
| 0x0C | LCR | 线控制（[1:0]字长 [2]停止位 [3]校验 [7]DLAB） |
| 0x10 | MCR | Modem 控制（[0]DTR [1]RTS [4]Loopback） |
| 0x14 | LSR | 线状态（[0]DR [1]OE [2]PE [3]FE [4]BI [5]THRE [6]TEMT [7]EI） |
| 0x18 | MSR | Modem 状态（无外部 Modem 引脚，恒 0） |
| 0x1C | SCR | Scratch 寄存器 |

> 写操作仅接受字节通道 0（PSTRB[0]，数据取 PWDATA[7:0]）；读数据由 8 位零扩展到 32 位；PREADY 恒 1（零等待），PSLVERR 恒 0。

> ns16550a 特性：16-byte TX/RX FIFO（触发水平 1/4/8/14 可配），可配置波特率（16-bit Divisor Latch，PCLK=100MHz），中断生成（接收线状态 RLS / 接收数据可用 RDA / 接收超时 TI / 发送保持空 THRE / Modem 状态 MS，优先级编码至 IIR）。无外部 Modem 引脚（modem_inputs 恒为无效电平，MSR 恒 0；MCR Loopback 模式可用）。替代原自定义 UART，为 Linux 串口控制台提供标准兼容。

**SPI 寄存器映射**（基址 `0x1000_C000`）：

| 偏移 | 名称 | 位定义 | 说明 |
|------|------|--------|------|
| 0x00 | CTRL | [0]=EN [1]=CPOL [2]=CPHA [3]=CS [4]=IRQ_EN [15:8]=CLK_DIV | 控制/中断使能 |
| 0x04 | DATA | [7:0] | 数据寄存器 |
| 0x08 | STATUS | [0]=BUSY [1]=IRQ_PENDING | 状态/中断挂起 |

#### 2.2.6 System Status 寄存器映射

基地址：`0x0400_0000`，AXI4-Lite 只读，按 `addr[11:0]==0x000` 译码（区域大小 4KB）：

| 偏移 | 位定义 | 说明 |
|------|--------|------|
| 0x00 | [0]=init_calib_complete [1]=mig_mmcm_locked [2]=clk_wiz_locked [31:3]=保留 | 系统状态（只读） |

#### 2.2.7 Boot ROM 地址映射

基地址：`0xFC00_0000`，AXI4-Lite 只读，32KB BRAM（MEM_DEPTH=8192），写通道以 SLVERR 应答（ROM 只读）。

CPU 复位起始地址为 `0xFC00_0000`，启动流程：`复位 PC=0xFC00_0000` → Boot ROM 取 bootloader → 初始化 sp → 轮询 SysStatus 等待 DDR3 校准完成（init_calib_complete）→ DDR3 自检（写入/读回比较，GPIO LED 反馈：通过 LED0 亮，失败全亮并死循环）→ UART 初始化（230400 8N1，除数 27）→ UART 接收镜像头（magic 0x52495343 + length + load_addr + entry_addr，4 个小端字）→ 接收 length 字节写入 load_addr → fence.i 刷新 icache → 跳转至 **entry_addr** → 执行主程序

---

## 3. CPU 核心设计详述

### 3.1 多周期 FSM 控制器 (`cpu_controller`)

控制器采用 12 状态 FSM 驱动整个数据通路：

```
STATE_IDLE (0) → STATE_FETCH (1) → STATE_DECODE (2)
    ├── dec_is_fence/fencei/wfi → STATE_FETCH
    ├── dec_is_mret → STATE_TRAP_RETURN (8)
    ├── dec_is_sret → STATE_TRAP_RETURN (8)
    ├── dec_is_ecall → STATE_ECALL (9)
    ├── dec_is_fencei → STATE_FENCEI (10)
    ├── dec_is_sfence_vma → STATE_SFENCE_VMA (11)
    ├── exception_at_decode → STATE_TRAP_ENTER (7)
    ├── dec_is_csr → STATE_CSR_ACCESS (6) → STATE_WB (5)
    ├── !dec_need_exe → STATE_FETCH (跳过执行)
    └── dec_need_exe → STATE_EXEC (3)
        ├── exe_is_branch → STATE_FETCH (或 STATE_TRAP_ENTER)
        ├── exe_need_mem → STATE_MEM (4) → STATE_WB (5)
        └── !exe_need_mem → STATE_WB (5) → STATE_FETCH
```

12 个状态：STATE_IDLE, STATE_FETCH, STATE_DECODE, STATE_EXEC, STATE_MEM, STATE_WB, STATE_CSR_ACCESS, STATE_TRAP_ENTER, STATE_TRAP_RETURN, STATE_FENCEI, STATE_SFENCE_VMA, STATE_RETURN_BOUNDARY。

各级使能信号由当前状态直接译码产生（`if_valid`, `id_valid`, `exe_valid`, `mem_valid`, `wb_valid`, `csr_valid`），确保每个时钟周期仅一级活跃。

### 3.2 取指级 (`cpu_fetch`)

- 输入：PC、指令数据（来自 icache；非缓存地址（如 MMIO）经 icache 以单拍 len=0 读取）
- 输出：`if_id_bus[95:0]` = `{pc_plus4, pc, inst}`
- 完成条件：`if_valid && inst_valid`
- PC 更新在 `core_top` 中统一管理

### 3.3 译码级 (`cpu_decode`)

**指令重组 (`op_regroup`)**：从 32-bit 指令中提取 opcode、funct3、funct7、rs1、rs2、rd 及五种立即数（I/S/B/U/J 型），均带符号扩展。

**指令识别**：通过 opcode + funct3 + funct7 组合译码，识别全部 70 条指令（RV32I 40 + Zicsr 6 + Zifencei 1 + 特权 MRET/SRET/SFENCE.VMA/WFI 4 + M 扩展 8 + A 扩展 11）。

**操作数选择**：

- `alu_src1`：AUIPC/JAL/分支使用 PC，其余使用 rs1
- `alu_src2`：LUI/AUIPC 使用 imm_u，JAL 使用 imm_j，JALR 使用 imm_i，分支使用 imm_b，立即数算术使用 imm_i，移位使用 shamt，Load 使用 imm_i，Store 使用 imm_s，AMO/LR/SC 使用 0（地址 = rs1 + 0），其余使用 rs2

**ALU 控制码**（16-bit one-hot）：

| 位 | 操作 |
|----|------|
| [12] | ADD |
| [11] | SUB |
| [10] | SLT |
| [9] | SLTU |
| [8] | AND |
| [6] | OR |
| [5] | XOR |
| [4] | SLL |
| [3] | SRL |
| [2] | SRA |
| [1] | LUI |

> AMO/LR/SC 的 ALU 控制码为 ADD（计算访存地址 rs1 + 0），与整数 Load/Store 一致。

> 选择器另支持 NOR（bit[7]）与 NOT（bit[13]）编码，但当前指令集无对应指令，译码级不会产生。



**A 扩展 opcode 识别**：OPCODE_AMO = 0b0101111，funct3 = 010（.W），funct5 区分 LR.W（00010，rs2=x0）/ SC.W（00011）/ AMO 操作（AMOSWAP=00001、AMOADD=00000、AMOAND=01100、AMOOR=01000、AMOXOR=00100、AMOMIN=10000、AMOMAX=10100、AMOMINU=11000、AMOMAXU=11100）。

**ID/EX 总线**（325-bit）：`{pc, pc_plus4, inst, alu_control[15:0], alu_src1, alu_src2, is_branch, is_jal_like, branch_funct3[2:0], use_fixed_wb, fixed_wb_data, wb_we, wb_rd[4:0], is_mu, mu_funct3[2:0], mem_kind[2:0], mem_size[2:0], mem_unsigned, rs1_value, rs2_value, amo_funct5[4:0], csr_addr[11:0], csr_funct3[2:0], csr_uimm[4:0], csr_rs1[4:0]}`（以 mem_kind 取代 is_load/is_store 并区分 LOAD/STORE/LR/SC/AMO，新增 amo_funct5 与 csr_rs1，无任何 FPU 字段）

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
- 握手协议：`req_valid → mu_ready → mu_busy → result_valid → result_got`
- MULHSU 修正：`upper + (src2[31] ? src1 : 0)`
- MULHU 修正：`mulhsu_upper + (src1[31] ? src2 : 0)`

**JALR 对齐**：结果与 `0xFFFF_FFFE` 按位与，清除最低位。

**分支/跳转目标**：

- 分支：条件成立时目标 = ALU 结果（pc + imm_b）
- JAL：目标 = ALU 结果（pc + imm_j）
- JALR：目标 = ALU 结果 & ~1（rs1 + imm_i）

**指令对齐异常检测**：跳转目标 `[1:0] != 00` 时触发指令地址对齐异常（Exception Code = 0）。

**EX/MEM 总线**（178-bit）：`{pc, pc_plus4, inst, result, wb_we, wb_rd[4:0], mem_kind[2:0], mem_size[2:0], mem_unsigned, store_data, amo_funct5[4:0]}`（result 已在执行级合并 JAL/JALR 的 pc+4；无 CSR/FPU 字段）

### 3.5 访存级 (`cpu_mem`)

内部状态机：

```
MEM_IDLE → MEM_ACCESS（MMU 翻译 + PMP/PMA 权限检查）
    ├── MEM_LOAD  → MEM_READ  （等待 phys_resp_valid）→ MEM_IDLE
    ├── MEM_STORE → MEM_WRITE （等待 phys_resp_valid）→ MEM_IDLE
    ├── MEM_LR    → MEM_AMO_READ（设置保留集）→ MEM_IDLE
    ├── MEM_SC    → 保留有效：MEM_AMO_WRITE → MEM_IDLE（rd=0）
    │               保留无效：直接完成（rd=1，不写入）
    └── MEM_AMO   → MEM_AMO_READ → MEM_AMO_WRITE（读-改-写）→ MEM_IDLE
MEM_IDLE → MEM_IDLE（非访存指令，直接完成）
```

**Load 数据处理**：

- Byte：按 byte_offset 选择字节，根据 mem_unsigned 决定零扩展/符号扩展
- Halfword：按 addr[1] 选择半字，根据 mem_unsigned 决定零扩展/符号扩展
- Word：直接使用 readData

**Store 数据处理**：

- Byte：按 addr[1:0] 生成 one-hot wstrb 并将数据移位到对应字节通道
- Halfword：按 addr[1] 选择低/高半字并移位 16 位
- Word：直接写（wstrb=4'b1111）

> `cpu_mem` 始终传递未移位的架构值（`store_data_r`）；字节/半字的通道放置由 dcache 完成

**地址对齐异常**：

- Halfword 访问 `addr[0] != 0` → 对齐异常
- Word 访问 `addr[1:0] != 00` → 对齐异常

**MEM/WB 总线**（102-bit）：`{wb_we, wb_rd[4:0], wb_data, pc, inst}`

### 3.6 回写级 (`cpu_wb`)

- 整数寄存器写使能：`rf_wen = wb_valid && wb_we`
- 写数据选择：`mem_wb_bus_r` 在 `core_top` 中由三个来源装载——执行级直通（`exe_to_wb`，非访存指令）、访存级结果（`mem_done`，Load/LR/SC/AMO）、CSR 读出值（`csr_valid`，CSR 指令）
- JAL/JALR 写回值：`pc + 4`（在 `cpu_execute` 中合并入 result 字段：`is_jal_like ? pc_plus4 : result_reg`）
- 寄存器 x0 硬连线为 0（在 `cpu_regfile` 中实现）


### 3.7 寄存器堆 (`cpu_regfile`)

- 32 个 32-bit 整数寄存器
- x0 恒为 0（读返回 0，写忽略）
- 单写端口，双读端口
- 附加调试读端口 ×3（`dbg_raddr/dbg_rdata`、`dbg_raddr2/dbg_rdata2`、`dbg_raddr3/dbg_rdata3`）及专用 `dbg_x1`、`dbg_x9`~`dbg_x19` 输出；读端口带同周期写穿透（write-through），保证译码级读到最新 GPR 值



---

## 4. 陷阱与 CSR 子系统

### 4.1 陷阱管理器 (`cpu_trap_manager`)

**异常检测**：

| 异常类型 | 检测位置 | Exception Code |
|----------|----------|----------------|
| 指令地址未对齐（分支/跳转目标） | 执行级 | 0 |
| 指令访问错误 | 取指级 | 1 |
| 非法指令 | 译码级 | 2 |
| EBREAK | 译码级 | 3 |
| Load 地址对齐 | 访存级 | 4 |
| Load 访问错误 | 访存级 | 5 |
| Store 地址对齐 | 访存级 | 6 |
| Store/AMO 访问错误 | 访存级 | 7 |
| ECALL (U-mode) | 译码级 | 8 |
| ECALL (S-mode) | 译码级 | 9 |
| ECALL (M-mode) | 译码级 | 11 |
| 指令页错误 | 取指级 | 12 |
| Load 页错误 | 访存级 | 13 |
| Store/AMO 页错误 | 访存级 | 15 |

**中断检测**：中断源信号由 SoC 级 CLINT（`axi4lite_clint`，产生 MTIP/MSIP/mtime）与 PLIC（产生 MEIP/SEIP）提供，经 `core_top` 输入 `cpu_csr` 汇聚为 `mip`（硬件源与软件注入位按位 OR）；中断优先级判定在 `cpu_trap_router` 中完成

| 中断源 | Interrupt Code | 优先级 |
|--------|----------------|--------|
| 外部中断（MEIE & MEIP） | 0x8000_000B | 最高 |
| 软件中断（MSIE & MSIP） | 0x8000_0003 | 中 |
| 定时器中断（MTIE & MTIP） | 0x8000_0007 | 低 |
| S-mode 外部中断（SEIE & SEIP） | 0x8000_0009 | — |
| S-mode 软件中断（SSIE & SSIP） | 0x8000_0001 | — |
| S-mode 定时器中断（STIE & STIP） | 0x8000_0005 | — |

中断使能条件（特权级感知）：`pending = mip & mie`。对目标为 M-mode 的中断（未委托位），`priv != M` 时无条件使能，`priv == M` 时需 `mstatus.MIE=1`；对目标为 S-mode 的中断（已委托位），`priv == U` 时无条件使能，`priv == S` 时需 `mstatus.SIE=1`。即全局 xIE 位只门控"在目标特权级执行时"的中断，更高特权级目标的中断不受当前特权级 xIE 限制

**M/S 中断优先级**：当 M-mode 和 S-mode 中断同时挂起时，M-mode 中断优先被响应。该优先级判定位于 `cpu_trap_router`：先计算 M-mode 目标中断（`mip & mie & ~mideleg`），仅当其无挂起时才响应 S-mode 目标中断（`mip & mie & mideleg`）

**陷阱委托机制**：

通过 medeleg/mideleg CSR 实现异常/中断委托。对应位为 1 时，该异常/中断委托至 S-mode 处理：

- 委托判定：`delegated = medeleg[cause]`（异常）或 `mideleg[cause]`（中断）
- 硬件强制 medeleg[11]=0（ECALL-from-M 不可委托），且本设计额外强制 medeleg[9]=0（ECALL-from-S 不可委托），保证 Linux 经 S-mode ecall 发起的 SBI 调用陷入 M-mode/OpenSBI 处理而非回环进入 S-mode 陷阱处理程序。medeleg 写掩码为 `32'h0000_B1FF`，可委托异常码为 0-8、12、13、15

**Trap 进入**：

1. 判断委托：若 `delegated=1` 且当前特权级低于 M-mode，进入 S-mode；否则进入 M-mode（委托仅对源自 M-mode 以下的陷阱生效，M-mode 中发生的异常即使 medeleg 置位也陷入 M-mode）
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
| 0x300 | mstatus | 是 | MPP/MPIE/MIE/SPP/SPIE/SIE/MPRV/SUM/MXR/TVM/TW/TSR |
| 0x301 | misa | 否 | 硬连线 `0x40141101`（RV32IMASU，A bit[0]=1） |
| 0x302 | medeleg | 是 | 异常委托寄存器（写掩码 0x0000_B1FF，可委托码：0-8,12,13,15） |
| 0x303 | mideleg | 是 | 中断委托寄存器（写掩码 0x0000_0222，可委托位：SSIP[1], STIP[5], SEIP[9]） |
| 0x304 | mie | 是 | MEIE/MTIE/MSIE/SEIE/STIE/SSIE |
| 0x305 | mtvec | 是 | M-mode Trap 向量基址 |
| 0x306 | mcounteren | 是 | 计数器使能寄存器（mcounteren[slice]=1 且 scounteren[slice]=1 时 U-mode 可读 cycle/time/instret） |
| 0x310 | mstatush | 否 | 硬连线 0 |
| 0x340 | mscratch | 是 | M-mode 临时寄存器 |
| 0x341 | mepc | 是 | M-mode 异常/中断返回 PC |
| 0x342 | mcause | 是 | M-mode 异常/中断原因 |
| 0x343 | mtval | 是 | M-mode 异常附加信息 |
| 0x344 | mip | 是（受限） | 读值 = 硬件源（MEIP[11]/SEIP[9]/MTIP[7]/MSIP[3]）与软件注入位按位 OR；M-mode 软件写 mip 仅可更新软件注入位 SEIP[9]/STIP[5]/SSIP[1]（写掩码 0x0000_0222，支持 CSRRW/CSRRS/CSRRC 语义） |
| 0xB00 | mcycle | 是 | 时钟周期计数器低 32 位 |
| 0xB02 | minstret | 是 | 指令退休计数器低 32 位 |
| 0xB80 | mcycleh | 是 | 时钟周期计数器高 32 位 |
| 0xB82 | minstreth | 是 | 指令退休计数器高 32 位 |
| 0xF11-0xF15 | mvendorid 等 | 否 | 硬连线 0 |
| 0x3A0 | pmpcfg0 | 是 | PMP 配置寄存器 0（8 个 PMP entry 的配置字段） |
| 0x3A1 | pmpcfg1 | 是 | PMP 配置寄存器 1 |
| 0x3A2 | pmpcfg2 | 是 | PMP 配置寄存器 2 |
| 0x3A3 | pmpcfg3 | 是 | PMP 配置寄存器 3 |
| 0x3B0 | pmpaddr0 | 是 | PMP 地址寄存器 0 |
| 0x3B1 | pmpaddr1 | 是 | PMP 地址寄存器 1 |
| 0x3B2 | pmpaddr2 | 是 | PMP 地址寄存器 2 |
| 0x3B3 | pmpaddr3 | 是 | PMP 地址寄存器 3 |
| 0x3B4 | pmpaddr4 | 是 | PMP 地址寄存器 4 |
| 0x3B5 | pmpaddr5 | 是 | PMP 地址寄存器 5 |
| 0x3B6 | pmpaddr6 | 是 | PMP 地址寄存器 6 |
| 0x3B7 | pmpaddr7 | 是 | PMP 地址寄存器 7 |
| 0x3B8 | pmpaddr8 | 是 | PMP 地址寄存器 8 |
| 0x3B9 | pmpaddr9 | 是 | PMP 地址寄存器 9 |
| 0x3BA | pmpaddr10 | 是 | PMP 地址寄存器 10 |
| 0x3BB | pmpaddr11 | 是 | PMP 地址寄存器 11 |
| 0x3BC | pmpaddr12 | 是 | PMP 地址寄存器 12 |
| 0x3BD | pmpaddr13 | 是 | PMP 地址寄存器 13 |
| 0x3BE | pmpaddr14 | 是 | PMP 地址寄存器 14 |
| 0x3BF | pmpaddr15 | 是 | PMP 地址寄存器 15 |
| 0xC01 | time | 否 | mtime 低 32 位（只读，镜像 CLINT mtime，U-mode 计数器别名） |
| 0xC81 | timeh | 否 | mtime 高 32 位（只读，镜像 CLINT mtime，U-mode 计数器别名） |

> **PMP 说明**：pmpcfg0–pmpcfg3（0x3A0–0x3A3）和 pmpaddr0–pmpaddr15（0x3B0–0x3BF）共 20 个 CSR 已实现，且硬件强制执行已实现：组合式 16 项 PMP 检查器 `pmp_checker` 对取指、数据访问与 PTW 页表访问三类物理访问执行地址匹配 + 权限检查。支持 TOR/NA4/NAPOT 模式；首个与访问字节范围重叠的 entry 生效，部分覆盖即拒绝；M-mode 默认放行（除非 entry 的 L=1，此时按 R/W/X 权限判定）。pmpcfg 写入经 WARL 规整（掩码 0x9F，R=0 时 W 强制清 0），L=1 的 entry 其 cfg 与 pmpaddr 均锁定不可再写；PTW 访问按 S-mode 特权级检查

> **time/timeh 说明**：`cpu_csr` 读路径直接返回 `ext_mtime` 输入（SoC 级 CLINT mtime 经 soc_top→core_top 路由至 CSR），U-mode 通过 time(0xC01)/timeh(0xC81) 读取定时器值（U-mode 需 mcounteren[1]=1 且 scounteren[1]=1，S-mode 仅需 mcounteren[1]=1）

**S-mode CSR：**

| CSR 地址 | 名称 | 可写 | 说明 |
|----------|------|------|------|
| 0x100 | sstatus | 是 | mstatus 的 S-mode 视图（可写域：SIE[1]/SPIE[5]/SPP[8]/SUM[18]/MXR[19]，掩码 0x000C_0122） |
| 0x104 | sie | 是 | SEIE/STIE/SSIE |
| 0x105 | stvec | 是 | S-mode Trap 向量基址 |
| 0x106 | scounteren | 是 | S-mode 计数器使能寄存器（与 mcounteren 联合控制 U-mode 计数器访问） |
| 0x140 | sscratch | 是 | S-mode 临时寄存器 |
| 0x141 | sepc | 是 | S-mode 异常/中断返回 PC |
| 0x142 | scause | 是 | S-mode 异常/中断原因 |
| 0x143 | stval | 是 | S-mode 异常附加信息 |
| 0x144 | sip | 是（受限） | 读值 = mip & mideleg & 0x222（委托视图）；S-mode 软件写 sip 仅可更新 SSIP[1]，且需 mideleg[1] 已委托 |
| 0x180 | satp | 是 | S-mode 地址翻译与保护（ASID + PPN） |

**sstatus 与 mstatus 的关系**：sstatus 是 mstatus 的受限视图，仅暴露 SIE（位1）、SPIE（位5）、SPP（位8）、SUM（位18）、MXR（位19）。对 sstatus 的写操作仅修改 mstatus 中对应位，其余位保持不变

**mstatus.MPRV/SUM/MXR/TVM/TW/TSR**：MPRV（位17）=1 时 M-mode 的 load/store 按 MPP 指定特权级做地址翻译与保护检查（`effective_data_priv`）；SUM（位18）允许 S-mode 访问 U-mode 页；MXR（位19）使仅可执行页可读；TVM/TW/TSR（位20-22）分别拦截 S-mode 的 satp 访问与 SFENCE.VMA、非 M-mode 的 WFI、S-mode 的 SRET，违反时触发非法指令异常

**CSR 访问控制**：

- U-mode：不可访问 S-mode 和 M-mode CSR，访问触发非法指令异常
- S-mode：不可访问 M-mode CSR，访问触发非法指令异常
- M-mode：可访问所有 CSR

CSR 写掩码：mstatus 仅允许写 SIE[1]、MIE[3]、SPIE[5]、MPIE[7]、SPP[8]、MPP[12:11]、MPRV[17]、SUM[18]、MXR[19]、TVM[20]、TW[21]、TSR[22]（掩码 0x007E_19AA，MPP 写入保留值 2'b10 时规整为 U）；mie 仅允许写 MEIE[11]、SEIE[9]、MTIE[7]、STIE[5]、MSIE[3]、SSIE[1]（掩码 0x0000_0AAA）；mtvec/mepc/stvec/sepc 强制低 2 位为 0；satp 写入时 MODE 位[31]=0 则整寄存器存 0（Bare）

---

## 5. 存储子系统

### 5.1 缓存几何参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 相联度 | 2 路组相联 | 每组 2 个缓存行 |
| 组数 | 8 | set_idx = addr[7:5] |
| 标签位 | 24 | tag = addr[31:8] |
| 字偏移 | 3 位 | word_off = addr[4:2]，每行 8 字（32 字节） |
| 行大小 | 256-bit（8×32-bit） | 一次 INCR8 突发填充 |
| 总容量 | 8 组 × 2 路 × 32 字节 = 512B | ICache 与 DCache 各 512B |

地址分解：`| tag[31:8] | set[7:5] | word[4:2] | byte[1:0] |`（24-bit tag 覆盖全 4GB 物理地址空间，不依赖 DDR 窗口高位为零的假设）

> **注意**：实际 RTL 中 `ICACHE_TAG_WIDTH`/`DCACHE_TAG_WIDTH` = **24**，`ICACHE_TAG_HI`/`DCACHE_TAG_HI` = **31**，`ICACHE_TAG_LO`/`DCACHE_TAG_LO` = 8（见 `src/core/memory/cache/defs.svh`）。tag 取完整物理地址 addr[31:8]；cacheable 与否由独立的 DDR 窗口范围判定（见 §5.5/§5.6），与 tag 位宽无关。

### 5.2 两路替换策略

ICache、DCache 每组各使用 1-bit victim 状态；TLB 为 16 项全相联，使用单一 victim 指针（填充时优先替换 VPN 匹配项，其次无效项，最后 victim 指向项）。缓存命中或填充 way N 后，victim 指向另一路；替换时优先选择无效路，仅当两路都有效时使用 victim 位。

### 5.3 标签存储（寄存器数组）

ICache 和 DCache 标签直接使用 RTL 二维寄存器数组存储，同组两路在当前周期并行比较。

- ICache：每路 `{valid, tag[23:0]}`（25-bit tag 项）
- DCache：每路 `{valid, tag[23:0]}`；当前为写通策略，无 dirty 位和驱逐写回
- 命中判定：`valid && (tag == paddr[31:8])`
- invalidate 直接清除对应组的 valid 位

### 5.4 数据存储（BRAM IP）

| BRAM | 配置 | 端口 A | 端口 B |
|------|------|--------|--------|
| icached | 256-bit × 16，True Dual Port，READ_FIRST，Byte_Enable | CPU 读 | Refill 写 |
| dcached | 256-bit × 16，True Dual Port，READ_FIRST，Byte_Enable | CPU 读/写通更新 | Refill 写 |

数据 BRAM 地址映射：`bram_addr = {set_idx[2:0], way}`，4-bit 寻址 16 项。标签和 TLB 均由 RTL 寄存器数组实现。

**BRAM 读延迟**：icached/dcached 由 Vivado blk_mem_gen IP 生成（`tools/vivado/ip.py`），`Register_PortA/PortB_Output_of_Memory_Primitives=false`，同步读、1 周期延迟；仿真与硬件使用同一 IP 模型（仓库中无独立的组合读行为模型）。标签/TLB 是寄存器数组，不引入 BRAM 读延迟。缓存 FSM 在 S_LOOKUP 使能 BRAM 读、在下一状态使用输出，与 1 拍延迟匹配。

### 5.5 指令缓存控制器 (`icache_ctrl`)

ICache 采用 PIPT（Physically-Indexed Physically-Tagged）策略：set index 与 tag 均使用 MMU 翻译后的物理地址（cpu_req_paddr），请求在 MMU 翻译就绪后才被 icache 接受。

ICache FSM 状态转换：

```
S_IDLE → S_LOOKUP: 锁存请求（MMIO 则进 S_MMIO_WAIT）
S_LOOKUP → hit:  读数据 BRAM，进 S_READ_HIT
S_LOOKUP → miss: 选择 victim，发 refill_req，进 S_REFILL
S_READ_HIT:      返回数据 BRAM 输出，更新 victim，回 S_IDLE
S_REFILL:        保持 refill_req，完成后更新数据 BRAM、tag 和 victim
S_INVALIDATE:    逐组清除两路 valid，完成后回 S_IDLE
```

- MMIO 旁路：仅 DDR 窗口 `0x8000_0000 ≤ paddr < 0x8800_0000` 的地址走缓存（request_cacheable），其余地址（含 BootROM/外设）直接发 AXI 单拍请求，不经过缓存（使用物理地址判断，即 TLB 翻译后的 paddr）
- 标签在 S_LOOKUP 中两路并行比较，命中时进 S_READ_HIT 等待数据 BRAM
- 缺失时向 `cpu_bus_bridge` 发 INCR8 读突发请求，8 拍填充整行
- icache 请求由 `mmu_inst_ready` 门控（core_top 中 `cpu_req_valid = if_valid && mmu_inst_ready && PMP/PMA 允许`），确保仅使用 MMU 输出的有效物理地址，避免采用过时翻译结果

### 5.6 数据缓存控制器 (`dcache_ctrl`)

DCache 同样采用 PIPT 策略，索引与标签均使用物理地址；PTW 是 dcache 的第二请求者（固定优先级：PTW > CPU）。

DCache FSM 状态转换：

```
S_IDLE → S_LOOKUP: 锁存请求（MMIO 则进 S_BYPASS_WAIT）
S_LOOKUP → load hit:  读数据 BRAM，进 S_READ_HIT
S_LOOKUP → load miss: 发 refill_req，进 S_REFILL
S_LOOKUP → store:     向主存发单拍写，进 S_STORE_WAIT
S_STORE_WAIT:             主存写成功后，若 Cache 命中则同步更新数据 BRAM
```

**写策略**：

- 写通（write-through）：Store 总是先写主存，命中时再更新 Cache 副本
- Store miss 不分配，因此没有 dirty 位、驱逐写回或 flush 扫描状态

**Store 数据合并**：

- Byte Store：`wdata[7:0] << (addr[1:0] * 8)`
- Halfword Store：`wdata[15:0] << (addr[1] * 16)`（由 dcache_ctrl 完成移位）
- Word Store：直接使用 `cpu_req_wdata`
（cpu_mem 传递的是未移位的架构值，字节/半字对齐移位全部在 dcache_ctrl 内完成）

### 5.7 总线桥接 (`cpu_bus_bridge`)

将 icache（取指/refill/MMIO）与 dcache（load/store/refill/PTW 页表访问）请求转换为 AXI4 Master 协议（五通道：AW/W/B/AR/R）。D$ 写通+不写分配，**无写回通路**；PTW 请求经 dcache_ctrl 转发（dcache_ctrl 内部 PTW 优先）。

```
S_IDLE: 两请求者仲裁，d（dcache，含 PTW）优先于 i（icache）；选定 owner 后锁定至响应完成（单 outstanding 阻塞式）

读:  S_READ_ADDR → S_READ_DATA（逐拍写入 read_data_r[beat*32+:32]，rlast 结束返回）
写:  S_WRITE_SEND（AW+W 同时驱动，单拍，wlast 恒 1）→ S_WRITE_RESP
```

**AXI4 信号映射**：
- AW 通道：awid[3:0], awaddr[31:0], awlen[7:0], awsize[2:0], awburst[1:0], awlock, awcache[3:0], awprot[2:0], awqos[3:0], awregion[3:0], awvalid/awready
- W 通道：wdata[31:0], wstrb[3:0], wlast, wvalid/wready
- B 通道：bresp[1:0], bvalid/bready
- AR 通道：arid[3:0], araddr[31:0], arlen[7:0], arsize[2:0], arburst[1:0], arlock, arcache[3:0], arprot[2:0], arqos[3:0], arregion[3:0], arvalid/arready
- R 通道：rdata[31:0], rresp[1:0], rlast, rvalid/rready

**突发传输**：
- Cache Refill 读：ARBURST=INCR, ARLEN=7（8 拍），ARSIZE=4 字节，地址行对齐
- 写传输：单拍（AWLEN=0，wlast 恒 1），**无 INCR8 写回**（D$ 写通+不写分配，不存在写回突发）
- Refill 累积：`read_data_r[beat*32 +: 32] <= rdata`，按拍写入对应字节段，8 拍后得到完整 256-bit 行
- MMIO/PTW：单拍传输（ARLEN=0/AWLEN=0）
- awid/arid 恒 0；awcache/arcache 按 len≠0 选择 NORM_BUF / DEV_NONBUF

**错误响应**：SLVERR/DECERR 通过 rresp/bresp 传递，触发对应错误标志

**优先级**：cpu_bus_bridge 仅两级——d（dcache，含 PTW）优先于 i（icache）；PTW 与 CPU 的仲裁在 dcache_ctrl 内部完成（PTW 优先）

### 5.8 存储从设备（DDR3/SRAM）

主存储器通过条件生成选择后端，地址区域 0x8000_0000~0x87FF_FFFF（顶层区域译码；`axi_wrap_ram` 为 128MB BRAM 行为模型，MEM_DEPTH=33554432 字、addr[26:2] 索引，与 FPGA DDR3 容量一致）：

- **SRAM 仿真模式**（`SIMU_USE_DDR=0`）：`axi_wrap_ram` 作为 AXI4 从设备，BRAM 行为模型，零延迟（awready=1, wready=1, arready=1），支持 INCR 突发，快速仿真
- **DDR3 模式**（`SIMU_USE_DDR=1` 或 FPGA）：`axi_wrap_ddr` 封装 MIG（mig_axi_32），地址重映射基址 0x8000_0000，输出 `ddr_aresetn`（init_calib_complete），访问真实 DDR3 SDRAM

### 5.9 Clock/Reset Architecture

系统采用三时钟域设计：

| 时钟域 | 频率 | 来源 | 用途 |
|--------|------|------|------|
| cpu_clk | 40MHz | clk_wiz_0 clk_out1 | CPU 核心及内部缓存（仿真 SIMU_USE_PLL=0 时由 testbench 直产约 91MHz） |
| sys_clk | 100MHz | clk_wiz_0 clk_out2 / 外部晶振 | AXI 互联及从设备 |
| ddr_clk_ref | 200MHz | clk_wiz_0 clk_out3 | DDR3 MIG 参考时钟 |

**仿真模式**（`SIMULATION` 宏）：
- `SIMU_USE_PLL=0`（默认）：testbench 直产时钟，最快
- `SIMU_USE_PLL=1`：使用 clk_wiz_0 IP，更接近真实时钟关系

**复位链**：
- `reset_sync`（2 级移位寄存器）：异步断言、同步释放，每时钟域各一实例
- 仿真 SRAM 模式：`sys_resetn = sync(resetn & ddr_data_init)`
- 仿真 DDR3 模式：`sys_resetn = sync(resetn & clk_wiz_locked & ddr_data_init)`
- FPGA 模式：`sys_resetn = sync(resetn & clk_wiz_locked & ddr_aresetn)`

### 5.10 AXI4 时钟域穿越 (`Axi_CDC`)

`Axi_CDC` 将 CPU 的 AXI4 Master 接口从 `cpu_clk` 域穿越至 `sys_clk` 域，使用异步 FIFO 隔离：
- 五通道全穿越：AW/W/B/AR/R
- QoS/Region 信号不穿越，在 sys_clk 域直接置零
- ID 宽度：输入 4-bit（CPU），输出 4-bit（CDC）

### 5.11 地址译码与从设备多路复用

`system_top` 内手动实现 7 从设备地址译码（替代原 AHB-Lite 总线）：
- AW/AR 通道：组合逻辑译码，`aw_slave_sel_comb` / `ar_slave_sel_comb`
- W/B/R 通道：跟随 **AW/AR 握手完成时**锁存的 slave_sel（write_busy_r/read_busy_r 期间保持；AXI 允许 W 先于/伴随 AW 到达，互联在 AW 握手捕获目标从设备前阻塞 W）
- Ready/Response 多路复用回 CDC Master

### 5.12 DDR3/SRAM 条件生成

通过 `SIMULATION` 宏和 `SIMU_USE_DDR` 参数选择存储后端：

| 模式 | 宏配置 | 模块 | 说明 |
|------|--------|------|------|
| SRAM 仿真 | `SIMULATION` + `SIMU_USE_DDR=0` | `axi_wrap_ram` | BRAM 行为模型，零延迟，快速仿真 |
| DDR3 仿真 | `SIMULATION` + `SIMU_USE_DDR=1` | `axi_wrap_ddr` | MIG + DDR3 行为模型，验证 DDR3 通路 |
| FPGA | 非 `SIMULATION` | `axi_wrap_ddr` | MIG + 真实 DDR3 SDRAM |

`axi_wrap_ram`：源自 chiplab，BRAM-based AXI4 slave 仿真模型，支持 INCR 突发，零延迟（awready=1, wready=1, arready=1）。
`axi_wrap_ddr`：源自 chiplab，封装 MIG（mig_axi_32），地址重映射基址 0x8000_0000，输出 `ddr_aresetn`（init_calib_complete）。

### 5.13 Boot ROM (`axi4lite_bootrom`)

- 地址映射：0xFC00_0000（addr[31:24]==8'hFC）
- AXI4-Lite 只读从设备，32KB BRAM（MEM_DEPTH=8192）
- 写通道以 **SLVERR** 应答（ROM 只读）
- 读通道 1 周期 BRAM 延迟，R 通道 FSM 握手需 `rvalid && rready` 双条件（BUG-83 修复）
- 仿真（`SIMULATION` 宏）下内容由 `$readmemh("bootloader.hex")` 在 elaboration 阶段加载；FPGA/DDR3 模式使用 ROM IP（blk_mem_gen），由 **COE 文件初始化**（`tools/vivado/tcl.py` 设置 `Load_Init_File/Coe_File`）
- **原因**（仿真路径）：Vivado 仿真中使用 COE 初始化 BRAM 时，BRAM 输出初始值为 X（未知态），X 传播后产生大量 X→0/X→1 分辨事件（resolution event），引发事件风暴（event storm），仿真速度下降上千倍；`$readmemh` 在 elaboration 阶段完成初始化，仿真开始时输出已为确定值，完全避免此问题
- **启动流程**：CPU 复位 PC=0xFC00_0000 → Boot ROM 取 bootloader → 轮询 SysStatus 等待 DDR3 校准 → DDR3 自检（LED 反馈）→ UART 接收镜像（magic+length+load_addr+entry_addr）→ 写入 load_addr → fence.i 刷新缓存 → 跳转至 **entry_addr** → 执行主程序

### 5.14 System Status (`axi4lite_sys_status`)

- 地址映射：0x0400_0000（addr[31:24]==8'h04）
- AXI4-Lite 只读从设备
- 寄存器映射（偏移 0x00）：
  - [0] init_calib_complete — MIG DDR3 校准完成
  - [1] mig_mmcm_locked — MIG 内部 MMCM 锁定
  - [2] clk_wiz_locked — Clocking Wizard 锁定
  - [31:3] 保留（0）
- Bootloader 通过轮询此寄存器等待 DDR3 初始化完成

### 5.15 AXI4-Lite Default Slave (`axi4lite_default_slave`)

- 功能：响应未映射地址空间的 AXI4-Lite 传输请求
- 行为：任何传输返回 DECERR 响应（`BRESP/RRESP=2'b11`）
- 替代原 AHB-Lite Default Slave

### 5.16 AXI4-Lite to APB Bridge (`axi4lite_to_apb`)

- 替代原 `ahb_lite_to_apb`
- AXI4-Lite 从接口 → APB Master 接口
- APB 外设为 GPIO/UART/SPI（**Timer 已移除**）；桥仅在 GPIO/UART/SPI 三个 4KB 窗口被顶层选中

### 5.17 MMU（Sv32 虚拟内存）

CPU 包含一个统一 MMU 实例（`MMU.sv`），提供双 i/d 接口（指令侧和数据侧），内部共享 TLB 和 PTW。

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

TLB 为 16 项全相联结构，所有表项均为普通寄存器（寄存器阵列，非 BRAM），参数 ENTRIES=16：

- **统一单查找端口**：顺序核同一时刻只进行一次架构级翻译，TLB 仅有一个查找端口，由 MMU 内部 owner 机制在 i-side/d-side 间分时复用
- **表项字段**（每项）：`valid(1)`、`vpn[19:0]`、`asid[8:0]`、`ppn[21:0]`、属性位 `{R, W, X, U, A, D, G, megapage}`
- **查找**：组合逻辑并行比较全部 16 项，无 BRAM 读延迟
- **命中条件**：`valid && (megapage ? VPN[19:10] 相等 : VPN[19:0] 全等) && (G=1 || ASID 相等)`
- **Megapage 匹配**：仅比较 VPN[19:10]（高 10 位），VPN[9:0] 忽略
- **ASID 感知**：每项存储 9-bit ASID（取自 satp[30:22]），匹配时需 ASID 一致或 G=1（全局项）
- **缺失**：触发 PTW 页表漫游
- **Fill 策略**（优先级从高到低）：① 原地重填已存在的同映射表项（VPN/ASID/G/megapage 均匹配；store 仅为置 D 位而重新漫游时命中此条）；② 首个无效表项；③ 轮转 victim 指针（顺序循环）
- **驱逐/刷新**：SFENCE.VMA（或 satp 值变化）触发全量刷新——单周期内同时清零全部 16 项的 valid 位并将 victim 指针归零，无逐组清零过程

**PTW 状态机（`ptw.sv`）**：

页表漫游器按 Sv32 二级页表逐级查找，状态转换如下：

```
S_IDLE → S_L1_REQUEST  ← 锁存请求（vaddr/satp/priv/SUM/MXR/access 作为事务一次性捕获）
S_L1_REQUEST → S_FAULT   ← L1 PTE 地址超出 32-bit 物理总线范围 → Access Fault
S_L1_REQUEST → S_L1_WAIT ← 发总线读 L1 PTE
S_L1_WAIT → S_FAULT      ← 总线错误 → Access Fault
S_L1_WAIT → S_L1_CHECK   ← 总线返回 L1 PTE
S_L1_CHECK → S_FAULT     ← PTE 无效（V=0，或 R=0 且 W=1 的保留组合）→ Page Fault
S_L1_CHECK → S_PERM_CHECK ← L1 为叶节点（R=1 或 X=1）→ megapage，进入权限检查
S_L1_CHECK → S_L0_REQUEST ← L1 为非叶节点，记录 G 位传播，计算 L0 PTE 地址
S_L0_REQUEST → S_L0_WAIT  ← L0 PTE 地址越界 → Access Fault；否则发总线读
S_L0_WAIT → S_L0_CHECK    ← 总线返回 L0 PTE（总线错误 → Access Fault）
S_L0_CHECK → S_FAULT      ← PTE 无效或非叶节点（L0 必须为叶）→ Page Fault
S_L0_CHECK → S_PERM_CHECK ← L0 为叶节点，进入权限检查
S_PERM_CHECK → S_AD_REQUEST ← 权限通过但 A=0（或 store 且 D=0）→ 写回 PTE 置 A（/D）位
S_PERM_CHECK → S_DONE     ← 权限通过且 A/D 已置位，输出物理地址（由 MMU 填充 TLB）
S_AD_REQUEST → S_AD_WAIT → S_DONE ← 写回 PTE（A=1，store 时 D=1）后完成
S_PERM_CHECK → S_FAULT    ← 权限违规（含 megapage PPN[9:0]≠0 未对齐）→ Page Fault
```

并补注：故障码分类——Access Fault=1/5/7（fetch/load/store），Page Fault=12/13/15

**A/D 位硬件管理**：

PTW 在页表漫游过程中自动管理访问位（A）和脏位（D）：

- 首次访问某页时，若 PTE.A=0，PTW 写回 PTE 并置 A=1
- 首次写入某页时，若 PTE.D=0，PTW 写回 PTE 并置 D=1
- 写回通过 PTW 总线请求完成；该请求被注入 dcache 控制器的 PTW 端口，经 dcache 写通（write-through）路径发出 AXI4 单拍写，若 PTE 所在行已缓存则同拍更新缓存副本

**PTW-dcache 一致性维护**：

PTW 的读写请求不旁路 dcache，而是作为 dcache 控制器的第二逻辑 owner（固定优先级高于 CPU 数据请求）经 dcache 执行：PTW 读 PTE 时可在 dcache 命中，未命中则触发 8 拍行填充；PTW 写 A/D 位时走 dcache 写通路径，若该 PTE 所在行已缓存则同拍更新缓存副本。因此不存在"PTW 改 PTE 后 dcache 提供过期数据"的一致性问题，无需失效缓存行，也无需 snoop 机制

**translate_en 输入**（统一 MMU 的双端口使能）：i-side `i_translate_en = if_valid`（仅取指级活跃时发起翻译请求）；d-side `d_translate_en = mem_access_valid`（仅访存操作有效时发起翻译请求）。Sv32 翻译仅在 `translate_en && satp[31]（MODE=Sv32）&& 特权级 != M-mode` 时激活；M-mode 或 satp=Bare 时虚拟地址直接透传（物理地址 = 虚拟地址）

**权限检查**：

| 访问类型 | 权限要求 |
|----------|----------|
| 取指（fetch） | PTE.X=1 |
| Load | PTE.R=1（或 PTE.X=1 且 mstatus.MXR=1） |
| Store/AMO | PTE.W=1 |
| U-mode 访问 | PTE.U=1 |
| S-mode 访问 | 取指始终禁止；Load/Store 需 mstatus.SUM=1 |

**SFENCE.VMA 指令**：

控制器进入 SFENCE_VMA 状态并保持 `sfence_vma_req` 直至完成。MMU 先进入 S_ABORT 状态等待 PTW 排空在途总线事务（不取消已发出的请求），再进入 S_FLUSH 状态单周期清零统一 TLB 全部 16 项，最后置 `sfence_done`。当前实现忽略 rs1/rs2，统一执行全量 TLB 刷新；此外 satp CSR 值变化也被保守地视为全量 TLB 刷新。由于 PTW 的 A/D 写回经 dcache 写通路径同步更新缓存副本，SFENCE.VMA 无需额外的 dcache 失效或冲刷操作

**FENCE.I 指令**：

控制器进入 FENCEI 状态并保持 `fencei_req` 直至 `invalidate_done`。icache 收到失效请求后在单周期内同时清零全部组的 valid 位（含 victim 位），并非逐组多周期失效。由于本核为阻塞式顺序流水（前一条指令完成访存阶段后 FENCE.I 才进入译码），先前的写通 store 天然已完成，无需显式等待逻辑

### 5.18 dcache PTW 访存路径与总线桥接（`dcache_ctrl` + `cpu_bus_bridge`）

PTW 的读写请求不直接连接总线桥，而是经 `core_top` 注入 dcache 控制器 `dcache_ctrl` 的专用 PTW 端口（`ptw_req_*`），作为 dcache 的第二逻辑 owner 与 CPU 数据请求复用同一套缓存与总线通路；页表数据经 dcache → `cpu_bus_bridge` → AXI 总线访问 DDR

**PTW 请求处理**（在 dcache_ctrl 内）：PTW 请求固定优先于 CPU 数据请求被接受（S_IDLE 先检查 ptw_req_valid）；PTW 读请求在目标地址位于 DDR 时可命中 dcache，未命中触发 8 拍 cache 行填充后返回目标字；PTW 写请求（A/D 位写回）走 dcache 写通路径发 AXI4 单拍写，若 PTE 所在行已缓存则同拍更新缓存副本。PTW 物理访问另经独立的 PMP/PMA 检查（`u_ptw_pmp`/`u_ptw_pma`）：PMP 按 S-mode 特权级检查；PMA 限定页表访问仅允许 DDR、字大小、非取指

**仲裁优先级**：当前设计为两级仲裁、单在途事务（one-outstanding）阻塞式：
```
dcache_ctrl 内：PTW 请求 > CPU 数据请求
cpu_bus_bridge 内：dcache 请求 > icache 请求
```
`cpu_bus_bridge` 是单在途阻塞式 AXI 适配器，只有 icache（i_req）与 dcache（d_req）两个请求端口：S_IDLE 时 dcache 请求优先，选定 owner 后锁定至响应完成。dcache 为写通 + 8 拍行填充，无写回（writeback）操作；MMIO 由各 cache 控制器按地址是否落在 DDR 区间判定（非 DDR 单拍访问），桥内无独立 MMIO 仲裁

**PTW 总线错误处理**：PTW 请求在 dcache 侧收到错误响应（`ptw_req_error`，源自 AXI RRESP/BRESP=SLVERR/DECERR），或被 PTW 自身的 PMP/PMA 检查拒绝（`ptw_protection_deny`）时，`core_top` 将 `ptw_bus_error` 置 1；PTW 状态机在 S_L1_WAIT/S_L0_WAIT/S_AD_WAIT 采样到该信号后置 FAULT_ACCESS 并进入 S_FAULT，MMU 以访问错误（Access Fault，异常码 1/5/7，按 fetch/load/store 区分）上报，由陷阱管理器处理。注意：总线错误产生的是访问错误异常而非页错误（页错误码 12/13/15 仅由 PTE 无效/权限违规产生）

### 5.19 固定存储几何 (`src/core/memory/cache/defs.svh`)

Cache/ROM/DDR3 几何参数由手工维护的 `src/core/memory/cache/defs.svh` 固定描述（文件头注明 "fixed Cache & memory geometry constants … Keep them in sync with the Cache implementation and the fixed IP geometry in tools/vivado"）。`config/vivado.yaml` 仅驱动 BRAM/时钟/MIG IP 的 create_ip TCL 生成，不驱动 Cache 几何。

```
config/vivado.yaml
  └─→ tools/vivado/ip.py::create_ip_tcl() → create_ip TCL
        ├─ ROM      (32-bit × 8192, TDP, Byte_Enable)
        ├─ icached  (256-bit × 16, TDP, Byte_Enable)
        ├─ dcached  (256-bit × 16, TDP, Byte_Enable)
        ├─ clk_wiz_0 (100MHz 入 → 40/100/200MHz 出)
        └─ mig_axi_32 (DDR3 MIG, docs/Reference/mig/mig_a.prj)
```
  由 `tools/vivado/__main__.py` 写入 `build/vivado/generated/*.tcl` 并在 `project` 命令时执行

**`defs.svh`** 为手工维护的固定常量文件（修改 Cache 几何时需与 `tools/vivado/ip.py` 的 IP 几何同步），包含：
- ROM 参数：`ROM_DATA_WIDTH`=32、`ROM_DEPTH`=8192、`ROM_ADDR_WIDTH`=13、`ROM_WEA_WIDTH`=4
- DDR3/时钟参数：`DDR3_ENABLED`、`DDR3_AXI_ADDR_WIDTH`=27、`CLK_WIZ_*`
- ICache/DCache 参数：`NUM_SETS`=8、`NUM_WAYS`=2、`TAG_WIDTH`=24、`LINE_WORDS`=8、`LINE_WIDTH`=256、`DEPTH`=16、`ADDR_WIDTH`=4、`WEA_WIDTH`=32
- 地址切片：`WORD_OFF_LO/HI`=2/4、`SET_IDX_LO/HI`=5/7、`TAG_LO/HI`=8/31、`TAG_ENTRY_WIDTH`=25（含 valid 位）、`SET_IDX_WIDTH`=3、`WAY_WIDTH`=1

TLB 几何不在本文件中定义——TLB 现为统一 TLB，容量由 `src/core/memory/mmu/tlb.sv` 的 `ENTRIES=16` 参数定义

修改 `config/vivado.yaml`（时钟/IP 参数）后运行 `python3 -m tools.vivado project` 重建工程并重新生成 IP；修改 Cache 几何需同时手改 `src/core/memory/cache/defs.svh` 与 `tools/vivado/ip.py` 中的 IP 宽深

**`config/vivado.yaml` 实际内容**（无 memory 段）：

| 参数 | 当前值 | 说明 |
|------|--------|------|
| `vivado` | vivado | 可执行名 |
| `project` | simplecpu_soc | 工程名 |
| `part` | xc7a200tfbg676-2 | FPGA 型号 |
| `timeouts` | project 1800 / simulation 72000 / bitstream 7200 / program 120 | 超时（秒） |
| `ddr3` | enabled, mig_axi_32 v4.2, mig_a.prj | MIG 配置 |
| `clock.outputs_mhz` | [40.0, 100.0, 200.0] | cpu_clk/sys_clk/ddr_clk_ref |

Cache 几何（2 路、8 组、32B 行、TAG_WIDTH 24）为固定值，定义于 `defs.svh`

---

## 6. 总线与外设

### 6.1 AXI4 互联

- 7 从设备：DDR3/RAM, Boot ROM, PLIC, CLINT, APB Bridge, Sys Status, Default Slave
- 地址译码：按 `addr_in_region(base, size)` 显式区域检查选择从设备（基址/大小见 `src/common/address_map.svh`），未命中任何区域 → Default Slave
- Default Slave：未映射地址返回 DECERR 响应，防止总线挂死
- 手动地址译码 + 从设备多路复用（system_top 内实现）
- 时钟域穿越：Axi_CDC (cpu_clk → sys_clk)

### 6.2 APB 总线与外设

通过 AXI4-Lite to APB 桥接访问（仅 GPIO `0x1000_0000~0x1000_0FFF`、UART `0x1000_8000~0x1000_8FFF`、SPI `0x1000_C000~0x1000_CFFF` 三个 4KB 窗口被路由到 APB 桥，详细地址映射见 §2.2.5）：

| 外设 | 基地址 | 说明 |
|------|--------|------|
| GPIO | `0x1000_0000` | 16-bit 双向 IO，引脚变化中断，中断使能/状态寄存器 |
| Timer | ~~`0x1000_4000`~~ | 已移除 |
| UART | `0x1000_8000` | ns16550a 标准串口，16-byte TX/RX FIFO，中断输出，APB4 封装 |
| SPI | `0x1000_C000` | 主模式 SPI 控制器，传输完成中断 |

#### 6.2.1 ns16550a UART

UART 外设为 ns16550a 标准串口（`src/soc/devices/uart16550/top.sv`，模块 `uart_16550a`；寄存器核心 `uart_regs_16550a` 位于 `src/soc/devices/uart16550/registers.sv`），通过 APB4 接口封装在 `src/soc/devices/apb_peripherals.sv` 中，寄存器采用字对齐偏移（0x00 THR/RBR、0x04 IER、0x08 FCR/IIR、0x0C LCR、0x10 MCR、0x14 LSR，见 §2.2.5）。ns16550a 提供 16-byte TX/RX FIFO、可配置波特率（Divisor Latch）、标准中断生成（RLS/RDA/超时/THRE/Modem），为 Linux 串口控制台提供标准兼容。原自定义 UART 的 STATUS-read auto-arm 机制不再需要。

#### 6.2.2 PLIC 中断路由

| PLIC src_irq | 来源 | 说明 |
|--------------|------|------|
| src[0] | — | 保留 |
| src[1] | — | 未使用（APB Timer 已移除，恒为 0） |
| src[2] | UART | UART TX 完成 / RX 有效中断 |
| src[3] | SPI | SPI 传输完成中断 |
| src[4] | GPIO | GPIO 引脚变化中断 |
| src[5:7] | — | 保留 |

---

## 7. 模块间总线定义

| 总线名 | 位宽 | 传递内容 |
|--------|------|----------|
| `if_id_bus` | 96-bit | `{pc_plus4[31:0], pc[31:0], inst[31:0]}` |
| `id_exe_bus` | 325-bit | 完整译码结果（pc/pc_plus4/inst/alu_control/alu_src1/alu_src2/分支控制/wb_we/wb_rd/is_mu/mu_funct3/mem_kind/mem_size/mem_unsigned/rs1/rs2/amo_funct5/csr 字段，见 3.3 节；无 FPU 字段） |
| `exe_mem_bus` | 178-bit | 执行结果 + 访存控制（pc/pc_plus4/inst/result/wb_we/wb_rd/mem_kind/mem_size/mem_unsigned/store_data/amo_funct5，见 3.4 节） |
| `mem_wb_bus` | 102-bit | 回写控制 + 调试信息（wb_we/wb_rd/wb_data/pc/inst，见 3.5 节） |

级间设置触发器（`if_id_bus_r`, `id_exe_bus_r`, `exe_mem_bus_r`, `mem_wb_bus_r`）作为流水线寄存器，在对应级完成时锁存。

---

## 8. 验证

### 8.1 应用层验证状态

> 更新时间: 2026-09-25 | 基于 commit `cf8b4e4`（时序收敛 @40MHz + UART/bootloader 修复）

| 应用 | 程序 | 验证方式 | 结果 | 说明 |
|------|------|----------|------|------|
| LED 跑马灯 | `led_marquee.hex`（上板）/`led_marquee_sim.hex`（仿真） | 仿真 + 上板 | ✓ PASS | GPIO 输出 + CLINT MTIP 定时器驱动，TB `wait_for_gpio` 序列检查 |
| UART Hello | `uart_hello.hex` | 仿真 | ✓ PASS | UART 输出逐字符检查 |
| UART Echo | `uart_echo.hex` | 仿真 + 上板 | ✓ PASS | UART 回环收发，TB 内嵌 TX 引擎 + RX 解码器 |
| UART Echo（C 运行时） | `uart_echo_c_lib.hex` | 仿真 | ✓ PASS | C 运行时验证（start.S + uart.c + musl 风格头文件） |
| Bootloader | `bootloader_phase1.hex`（仿真）/`bootloader.hex`（上板） | 仿真 + 上板 | ✓ PASS | Phase-1 为 2 指令跳转桩（jr 0x80000000）；Phase-2 为 MIG 等待 → DDR3 自检 → UART 接收镜像（magic+length+load+entry 头，230400 波特）→ 跳转 |

**里程碑**：52/52 测试程序全部通过（`build/test-results/program-tests.log`：52 passed, 0 failed）；时序收敛 @40MHz（WNS +0.459 / TNS 0 / 44758 端点全过）并生成 bitstream；F 扩展与浮点计算器已随整数核化重构移除

### 8.2 测试平台

**程序测试台**（加载 `build/program/` 下 hex，经 `tb_program` + `soc_fixture.svh` 的 `finish_framework_test` 轮询 x28/x29/x30 判定 PASS/FAIL）: `tb_program`（通用，约 40 个仿真任务共用）、`tb_dcache_refill_error`/`tb_dcache_store_error`（AXI 错误注入）、`tb_cpu_full`/`tb_cpu_compute`/`tb_cpu_trap`（集成）— 52 个测试程序 361 子测试全部 PASS。
**应用测试台**: `tb_uart_hello`、`tb_uart_echo`、`tb_led_marquee`。
**内核启动测试台**: `tb_kernel_boot`（OpenSBI/Linux 启动监视器，写出 `uart_tx.log`/`kernel_trap.log`/`kernel_progress.log`；任务 `kernel_boot_sram`/`kernel_boot_ddr3`/`kernel_tb_compile_smoke`）。
**单元测试台**: `tb_icache`、`tb_dcache`、`tb_ptw`、`tb_sfence`、`tb_csr`、`tb_exception`、`tb_stage_exception`、`tb_interrupt_precision`、`tb_pmp_pma`、`tb_trap_router`、`tb_cpu_controller`、`tb_memory_contract`、`tb_cpu_bus_bridge`、`tb_clint`、`tb_plic`、`tb_apb_peripherals`、`tb_axi_interconnect`。
**FPGA**: `fpga` 任务（top `system_top`，blcoe=bootloader.coe，SIMU_USE_DDR=1/SIMU_USE_PLL=1）。

### 8.3 验证方法

- 寄存器检查：通过 `rf_addr`/`rf_data` 端口直接读取整数寄存器堆，与期望值比对
- 存储器检查：BRAM IP 内部数组路径在仿真中不可直接访问，标记为 SKIP
- UART 检查：testbench 内嵌 UART RX 解码器，逐字符比对输出
- GPIO 检查：监测 GPIO 端口状态变化，验证 LED 跑马灯序列
- 程序自检协议：测试框架 `test/program/framework/test_framework.s` 提供 test_init/test_run/test_report，子测试结果写入 0x80007000 结果区，TB 轮询 x29（total）非零判定结束，`x28==x29 && x30==0` 即 ALL TESTS PASSED
- PASS/FAIL 计数汇总
- 共享 testbench 框架：`test/bench/support/soc_fixture.svh`（system_top 实例化 + 时钟/复位 + DDR3 仿真支持 + check_reg/check_mem_word 任务 + pass/fail 计数）
- DDR3 仿真支持：ddr3_model + axi4_write task + write_hex_file task + ddr_data_init 序列化

### 8.4 仿真环境

- 仿真器：Vivado XSim（行为级仿真）
- 自动化工具：`python3 -m tools.vivado` 轻量封装（子命令 `project` / `sim <task> [--runtime]` / `regress <group>` / `bitstream [--task] [--output]` / `program [--bitstream]` / `clean` / `list`）
  - 仿真任务与组定义于 `config/simulations.yaml`（组 `short` 共 23 个任务）
  - 测试程序经 `python3 tools/test_builder.py`（读 `config/programs.yaml`）编译为 hex/coe
  - IP 生成：`config/vivado.yaml` → `tools/vivado/ip.py` → BRAM/clk_wiz/MIG create_ip TCL
- SoC 级仿真：testbench 实例化 `system_top`（而非 `core_top` + `ahb_lite_bus`），通过 `test/bench/support/soc_fixture.svh` 共享框架
- DDR3 仿真模式：`SIMU_USE_DDR=0`（SRAM 模型，快速）或 `SIMU_USE_DDR=1`（DDR3 模型，验证通路）
- `src/soc/config.svh` 控制仿真行为（SIMU_USE_PLL / SIMU_USE_DDR，可在 Vivado verilog_define 覆盖）
- 程序加载：`tools/vivado/tcl.py` 将任务的 phex/blhex 拷贝为 xsim 运行目录的 `prog.hex`/`bootloader.hex`，`axi4lite_bootrom` 与 `axi_wrap_ram` 在 elaboration 阶段 `$readmemh` 加载；FPGA 任务用 `blcoe` COE 初始化 BRAM IP
- hex/coe 文件由 `tools/test_builder.py` 读取 `config/programs.yaml` 声明式编译（底层调用 `tools/rv2coe.py`，默认 march rv32im_zicsr_zifencei、链接脚本 linker/ram.ld、深度 8192）
- BRAM 行为模型：0-cycle 读延迟，不精确模拟碰撞行为

### 8.5 已知限制

- **BRAM 读时序**：icached/dcached BRAM IP 配置为不寄存输出原语（ip.py），Cache 数据路径经 S_LOOKUP/S_READ_HIT 状态机同步访问；Tag 数组与统一 TLB 均为寄存器数组
- **SRAM 地址空间**：SRAM 仿真模式下 `axi_wrap_ram` 容量由 BRAM 配置决定，DDR3 模式下地址范围 `0x8000_0000` 起始
- **Cache 容量**：ICache/DCache 各 512B（8 组 × 2 路 × 32 字节），大工作集程序可能频繁缺失
- **TLB 容量**：统一 TLB 共 16 项全相联（单查找口，victim 替换），大工作集或频繁上下文切换可能 TLB 抖动
- **SRAM 字节写**：SRAM 仿真模型（axi_wrap_ram）支持 AXI4 字节写（wstrb），DDR3 通过 MIG 管理
- **PMP 已实现硬件强制**：`pmp_checker` 16 项（TOR/NA4/NAPOT），首匹配优先、部分覆盖即拒绝，M-mode 豁免；配套单元测试 `tb_pmp_pma`
- **CLINT 标准地址布局**：寄存器布局遵循 SiFive CLINT 标准（msip @ 0x0000, mtimecmp_lo @ 0x4000, mtimecmp_hi @ 0x4004, mtime_lo @ 0xBFF8, mtime_hi @ 0xBFFC），addr[15:0] 译码。Linux 标准 sifive_clint 驱动可直接使用
- **分支预测**：无分支预测（始终 not-taken），JAL/JALR 静态预测
- **无浮点扩展**：F/D 扩展均已移除，misa=0x40141101（RV32IMASU），整数核 only
- **写通 DCache 的总线流量**：所有 Store 均直达主存（写通不分配），Store 密集场景总线流量高于写回式 Cache

---

## 9. 文件清单

### 9.1 RTL 源文件

| 目录 | 文件 | 说明 |
|------|------|------|
| `src/common/` | `address_map.svh` | SoC 物理地址映射（DDR/BootROM/PLIC/CLINT/SysStatus/APB 外设基址与大小） |
| `src/common/` | `reset_sync.sv` | 复位同步器（异步断言，同步释放） |
| `src/common/bus/` | `axi.svh` | AXI4/AXI4-Lite 常量定义（基于 AMBA AXI4 IHI0022H，替代 ahb_def.svh） |
| `src/core/` | `top.sv` | `core_top`：CPU 核心顶层 |
| `src/core/interface/` | `types.svh` | 核心架构契约：流水线总线结构体（id_exe_bus_t 等）、特权/访问类型定义 |
| `src/core/interface/` | `bus_bridge.sv` | `cpu_bus_bridge`：AXI4 Master 五通道适配（one-outstanding，DCache 优先，INCR8 突发） |
| `src/core/pipeline/` | `controller.sv` | `cpu_controller`：多周期 FSM 控制器 |
| `src/core/pipeline/` | `fetch.sv` | `cpu_fetch`：取指级 |
| `src/core/pipeline/` | `decode.sv` | `cpu_decode`：译码级 |
| `src/core/pipeline/` | `execute.sv` | `cpu_execute`：执行级 |
| `src/core/pipeline/` | `memory.sv` | `cpu_mem`：访存级 |
| `src/core/pipeline/` | `writeback.sv` | `cpu_wb`：回写级 |
| `src/core/pipeline/` | `operation_decode.sv` | `op_regroup`：指令重组/立即数解码 |
| `src/core/pipeline/` | `register_file.sv` | `cpu_regfile`：整数寄存器堆 |
| `src/core/control/csr/` | `defs.svh` | 已实现 CSR 地址与固定架构掩码 |
| `src/core/control/csr/` | `top.sv` | `cpu_csr`：CSR 寄存器文件（misa=0x40141101 RV32IMASU） |
| `src/core/control/csr/` | `metadata.sv` | `csr_meta`：CSR 实现位图/最低特权级元数据 |
| `src/core/control/csr/` | `interface.sv` | `cpu_csr_interface`：CSR 读写接口 |
| `src/core/control/trap/` | `manager.sv` | `cpu_trap_manager`：陷阱管理器 |
| `src/core/control/trap/` | `router.sv` | `cpu_trap_router`：陷阱路由（M/S 目标与委托） |
| `src/core/control/trap/` | `csr_update.sv` | `cpu_trap_csr`：陷阱 CSR 更新（mepc/mcause/mstatus） |
| `src/core/memory/cache/` | `defs.svh` | 固定 Cache/ROM/DDR3 几何常量（**手工维护**，与 ip.py IP 几何同步） |
| `src/core/memory/cache/` | `instruction.sv` | `icache_ctrl`：2 路组相联 PIPT 阻塞式 ICache（DDR 窗口外旁路） |
| `src/core/memory/cache/` | `data.sv` | `dcache_ctrl`：2 路组相联 PIPT 写通不分配 DCache（PTW 为第二 owner） |
| `src/core/memory/mmu/` | `top.sv` | `MMU`：阻塞式 Sv32 翻译引擎（TLB 查找 + 页表漫游，satp 变更视为全刷） |
| `src/core/memory/mmu/` | `tlb.sv` | `tlb`：16 项全相联统一 TLB（ASID 感知，victim 替换，大页支持） |
| `src/core/memory/mmu/` | `page_table_walker.sv` | `ptw`：Sv32 页表漫游器（A/D 位硬件写回） |
| `src/core/memory/protection/` | `pmp.sv` | `pmp_checker`：16 项 PMP 硬件检查（TOR/NA4/NAPOT，首匹配优先） |
| `src/core/memory/protection/` | `pma.sv` | `pma_checker`：固定物理内存属性检查（区域+操作类型） |
| `src/core/execution/alu/` | `top.sv` | `alu_32bit`：32-bit ALU 顶层 |
| `src/core/execution/alu/adder/` | `cla_4bit.sv` | 4-bit CLA |
| `src/core/execution/alu/adder/` | `cla_16bit.sv` | 16-bit CLA |
| `src/core/execution/alu/adder/` | `cla_32bit.sv` | 32-bit CLA |
| `src/core/execution/alu/` | `logic.sv` | `logic_unit`：逻辑/比较单元 |
| `src/core/execution/alu/` | `shifter.sv` | `shifter`：桶形移位器（5 级：1/2/4/8/16） |
| `src/core/execution/alu/` | `immediate.sv` | `lui`：立即数生成 |
| `src/core/execution/alu/` | `mux.sv` | `mux_2to1`/`mux_4to1`：多路选择器 |
| `src/core/execution/alu/` | `result_selector.sv` | `alu_result_selector`：ALU 结果选择器 |
| `src/core/execution/alu/` | `branch_comparator.sv` | `branch_comparator`：分支条件比较器 |
| `src/core/execution/muldiv/` | `top.sv` | `mu_unit`：乘除法单元 |
| `src/core/execution/muldiv/multiplier/` | `booth.sv` | `booth_multiplier`：Booth 乘法器 |
| `src/core/execution/muldiv/divider/` | `non_restoring.sv` | `non_restoring_divider`：非恢复余数除法器 |
| `src/soc/` | `top.sv` | `system_top`：SoC 顶层（CPU + 三级总线 + 外设 + DDR3） |
| `src/soc/` | `config.svh` | SoC 配置宏（SIMU_USE_PLL / SIMU_USE_DDR） |
| `src/soc/bus/axi/` | `cdc.sv` | `Axi_CDC` + StreamFifoCC/BufferCC 系列：AXI4 时钟域穿越 |
| `src/soc/bus/axi/` | `default_slave.sv` | `axi4lite_default_slave`：未映射地址 DECERR 响应 |
| `src/soc/bus/apb/` | `defs.svh` | APB 总线常量 |
| `src/soc/bus/apb/` | `axi_bridge.sv` | `axi4lite_to_apb`：AXI4-Lite → APB 桥 |
| `src/soc/bus/apb/` | `decoder.sv` | `apb_decoder`：APB 地址译码（4 从设备） |
| `src/soc/devices/` | `boot_rom.sv` | `axi4lite_bootrom`：Boot ROM（0xFC00_0000，32KB，仿真 $readmemh） |
| `src/soc/devices/` | `clint.sv` | `axi4lite_clint`：CLINT（msip/mtimecmp/mtime，SiFive 布局） |
| `src/soc/devices/` | `plic.sv` | `axi4lite_plic`：双上下文 PLIC（8 源，M/S-mode 各一上下文） |
| `src/soc/devices/` | `system_status.sv` | `axi4lite_sys_status`：系统状态只读从设备（0x0400_0000） |
| `src/soc/devices/` | `apb_peripherals.sv` | `apb_perips`：APB 外设顶层 |
| `src/soc/devices/` | `gpio.sv` | `gpio`：GPIO（16-bit 双向，引脚变化中断） |
| `src/soc/devices/` | `spi.sv` | `spi`：SPI 主模式（传输完成中断） |
| `src/soc/devices/uart16550/` | `top.sv` | `uart_16550a`：ns16550a 标准串口（16-byte TX/RX FIFO，APB4 封装） |
| `src/soc/devices/uart16550/` | `registers.sv` | `uart_regs_16550a`：寄存器接口 |
| `src/soc/devices/uart16550/` | `receiver.sv` | `uart_receiver`：接收器 |
| `src/soc/devices/uart16550/` | `transmitter.sv` | `uart_transmitter`：发送器 |
| `src/soc/devices/uart16550/` | `rx_fifo.sv` / `tx_fifo.sv` | `uart_rfifo` / `uart_tfifo`：RX/TX FIFO |
| `src/soc/devices/uart16550/` | `synchronizer.sv` | `uart_sync_flops`：亚稳态同步器 |
| `src/soc/devices/uart16550/` | `ram.sv` | `raminfr`：RAM 基础设施 |
| `src/soc/devices/uart16550/` | `defs.svh` | UART 常量定义 |
| `src/soc/memory/` | `ram_axi_wrapper.sv` | `axi_wrap_ram`：AXI4 BRAM 仿真模型（SRAM 替代，$readmemh 加载 prog.hex） |
| `src/soc/memory/` | `ddr_axi_wrapper.sv` | `axi_wrap_ddr`：AXI4 DDR3 包装器（MIG） |

（注：rx_fifo/tx_fifo 合并为一行以保持表格紧凑，可拆为两行；总计 67 文件。）

**BRAM/时钟/MIG IP 核**（由 `config/vivado.yaml` 驱动，`tools/vivado/ip.py::create_ip_tcl()` 生成 create_ip TCL）：

| IP | 配置 | 用途 |
|----|------|------|
| `ROM` | 32-bit × 8192，True Dual Port，Byte_Enable | Boot ROM（32KB，sys_clk） |
| `icached` | 256-bit × 16，True Dual Port，Byte_Enable | ICache 数据存储（cpu_clk） |
| `dcached` | 256-bit × 16，True Dual Port，Byte_Enable | DCache 数据存储（cpu_clk） |
| `clk_wiz_0` | 100MHz 入 → 40/100/200MHz 出 | 三路时钟 |
| `mig_axi_32` | MIG 7series v4.2 | DDR3 控制器 |

Cache 标签数组与统一 TLB 使用 RTL 寄存器数组，不生成独立 BRAM IP。

### 9.2 Testbench 文件

| 文件 | 说明 |
|------|------|
| `test/bench/support/soc_fixture.svh` | 共享 fixture（system_top 实例化 + 时钟/复位 + check_reg/check_mem_word + DDR3 仿真支持） |
| `test/bench/program/tb_program.sv` | 通用程序测试台（finish_framework_test，约 40 个仿真任务共用） |
| `test/bench/program/fault/tb_dcache_refill_error.sv` | DCache refill AXI 错误注入测试台 |
| `test/bench/program/fault/tb_dcache_store_error.sv` | DCache store 响应错误注入测试台 |
| `test/bench/system/cpu/tb_cpu_full.sv` | 完整指令集集成测试 |
| `test/bench/system/cpu/tb_cpu_compute.sv` | 算术/逻辑/乘除法计算集成测试 |
| `test/bench/system/cpu/tb_cpu_trap.sv` | 异常/中断陷阱集成测试 |
| `test!bench/system/boot/tb_kernel_boot.sv` | OpenSBI/Linux 启动监视器（写出 uart_tx.log / kernel_trap.log / kernel_progress.log） |
| `test/bench/system/apps/tb_led_marquee.sv` | LED 跑马灯应用测试（wait_for_gpio 序列检查） |
| `test/bench/system/apps/tb_uart_hello.sv` | UART 输出应用测试 |
| `test/bench/system/apps/tb_uart_echo.sv` | UART 回环应用测试（内嵌 TX 引擎 + RX 解码器） |
| `test/bench/unit/cache/tb_icache.sv` | ICache 单元测试（阻塞式） |
| `test/bench/unit/cache/tb_dcache.sv` | DCache 单元测试（写通） |
| `test/bench/unit/core/tb_cpu_controller.sv` | FSM 控制器单元测试 |
| `test/bench/unit/core/tb_memory_contract.sv` | 访存级契约单元测试 |
| `test/bench/unit/interface/tb_cpu_bus_bridge.sv` | AXI4 总线桥单元测试 |
| `test/bench/unit/mmio/tb_clint.sv` | CLINT 单元测试 |
| `test/bench/unit/mmio/tb_plic.sv` | PLIC 单元测试 |
| `test/bench/unit/mmu/tb_ptw.sv` | PTW 页表漫游单元测试 |
| `test/bench/unit/mmu/tb_sfence.sv` | SFENCE.VMA 握手单元测试 |
| `test/bench/unit/privilege/tb_csr.sv` | CSR 单元测试 |
| `test/bench/unit/privilege/tb_exception.sv` | 异常契约单元测试 |
| `test/bench/unit/privilege/tb_stage_exception.sv` | 流水级异常单元测试 |
| `test/bench/unit/privilege/tb_interrupt_precision.sv` | 中断精确性单元测试（M 扩展指令完成后入陷阱） |
| `test/bench/unit/privilege/tb_pmp_pma.sv` | PMP/PMA 单元测试 |
| `test/bench/unit/privilege/tb_trap_router.sv` | 陷阱路由单元测试 |
| `test/bench/unit/soc/tb_apb_peripherals.sv` | APB 外设单元测试 |
| `test/bench/unit/soc/tb_axi_interconnect.sv` | AXI 互连单元测试 |

### 9.3 程序源文件

| 目录 | 说明 |
|------|------|
| `test/program/framework/` | 测试框架（test_framework.s 自检运行器、trap_handlers.s 陷阱模板、page_table_utils.s Sv32 页表工具） |
| `test/program/isa/` | ISA 测试 8 项 160 子测试（alu 20、branch 17、jump 8、memory 20、upper_imm 9、m_ext 16、csr 18、a_ext 52） |
| `test/program/exception/` | 异常测试 6 项 21 子测试（ecall 4、ebreak 3、illegal_inst 3、access_fault 3、timer_irq 2、interrupt_basic 6） |
| `test/program/privilege/` | 特权测试 5 项 43 子测试（priv_transition 11、delegation 8、csr_access_priv 11、wfi 6、counter_access 7） |
| `test/program/mmu/` | MMU 测试 12 项 82 子测试（sv32_basic 6、tlb_basic 12、tlb_replace 6、tlb_flush 8、tlb_asid 4、tlb_megapage 4、tlb_stress 6、ptw_walk 4、page_fault 4、permission 14、sv32_edge 6、unified_mmu 8） |
| `test/program/cache/` | Cache 测试 5 项 21 子测试（icache_basic 3、dcache_basic 4、dcache_dirty 4、fencei 4、cache_mmu_interact 6） |
| `test/program/mmio/` | MMIO 测试 2 项 8 子测试（clint 4、plic 4） |
| `test/programGression/` | 回归测试 11 项 26 子测试（reg_tlb_fill_way 3、reg_ptw_fault_latch 4、reg_sfence_during_walk 2、reg_stale_paddr 2、reg_bare_no_miss 3、reg_pf_latch 3、reg_mmio_ready 4、reg_dcache_refill_error 1、reg_dcache_store_error 1、reg_linux_ptr_reload 2、reg_linux_field_values 1） |
| `test/program/integration/` | 集成测试 3 项（cpu_full、cpu_compute、cpu_trap，无框架） |
| `software/baremetal/boot/` | Bootloader（bootloader_phase1.s 跳转桩 + bootloader.s DDR3 自检/UART 接收/跳转） |
| `software/baremetal/applications/` | 应用（led_marquee.s、led_marquee_sim.s、uart_hello.s、uart_echo.s、uart_echo_c_lib.c） |
| `software/baremetal/runtime/` | C 运行时（start.S、uart.c、include/uart.h、include/sys.h） |
| `software/baremetal/linker/` | 链接脚本（ram.ld、harvard.ld） |

（合计 52 个测试程序 361 子测试 + 3 框架文件 + 13 个 baremetal 文件。）

---

## 10. 设计特点总结

1. **多周期 FSM 控制**：非传统流水线，由状态机逐级推进，每周期仅一级活跃，简化数据冒险处理
2. **级间总线打包**：使用位拼接传递控制信号与数据，减少端口数量，但牺牲可读性
3. **CLA 超前进位加法器**：4-bit → 16-bit → 32-bit 级联，降低进位延迟
4. **桶形移位器**：5 级级联（1/2/4/8/16），单周期完成任意移位
5. **Booth 乘法器**：Radix-2 Booth 编码，32 周期迭代，支持有符号/无符号
6. **非恢复余数除法器**：32 周期迭代 + 修正阶段，处理除零/溢出/符号
7. **完整陷阱处理**：支持 14 种异常 + 6 种中断（M/S-mode 各 3 种），符合 RISC-V 特权规范
8. **M/S/U 三级特权模式**：支持陷阱委托（medeleg/mideleg），S-mode 独立陷阱向量与 CSR
9. **Sv32 二级页表虚拟内存**：硬件页表漫游（PTW），16 项全相联统一 TLB，ASID 感知
10. **SRET/SFENCE.VMA/fence.i 指令**：S-mode 陷阱返回、TLB 刷新（sfence.vma/satp 变更均触发全刷）、fence.i 触发 icache 失效
11. **硬件管理 A/D 位**：PTW 自动写回 PTE 的访问位和脏位
12. **PTW-dcache 共享通路**：PTW 作为 dcache 第二逻辑 owner（固定优先级）经同一数据通路读写 PTE，A/D 位写回经写通直达主存
13. **2 路组相联缓存**：ICache/DCache 各 512B（8 组 × 2 路 × 32B 行），标签使用寄存器数组
14. **两路 victim 替换**：每组 1-bit 状态，无效路优先
15. **DCache 写通**：Store 命中同时更新 Cache 和主存，Store miss 不分配，不需要 dirty 位和驱逐写回
16. **INCR8 突发传输**：Cache Refill 使用 AXI4 INCR8 读突发，8 拍传输整行 256-bit 数据；Store 写通为单拍传输
17. **MMIO 旁路**：DDR 窗口判断——`0x8000_0000 ≤ paddr < 0x8800_0000`（SOC_DDR_BASE/SOC_DDR_SIZE）可缓存，窗口外一律旁路 Cache 直走 AXI 总线，使用物理地址判断
18. **PIPT（Physically-Indexed Physically-Tagged）**：Cache 使用 TLB 翻译后的物理地址索引与比较
19. **寄存器标签存储**：Cache Tag 两路并行比较，无额外 BRAM 读等待状态
20. **统一 TLB**：16 项全相联寄存器数组实现，单查找口，victim 替换
21. **AXI4 + AXI4-Lite + APB 三级总线**：高速主存挂 AXI4，控制寄存器挂 AXI4-Lite，低速外设挂 APB，通过桥接互联
22. **AXI4 Master 接口**：cpu_bus_bridge 五通道 AW/W/B/AR/R，读支持 INCR8 突发（refill），写为单拍
23. **AXI4-Lite 从设备**：PLIC/CLINT/BootROM/SysStatus/APB Bridge，手动地址译码 + 从设备多路复用
24. **AXI4 时钟域穿越**：Axi_CDC，cpu_clk(40MHz) → sys_clk(100MHz) 异步隔离
25. **三时钟域架构**：cpu_clk/sys_clk/ddr_clk_ref，reset_sync 复位同步
26. **DDR3 SDRAM 支持**：axi_wrap_ddr + MIG，可选 SRAM 行为模型（axi_wrap_ram）
27. **Boot ROM**：0xFC00_0000，32KB BRAM，CPU 复位起始地址，bootloader 按协议头 entry_addr 跳转（典型 0x8000_0000）
28. **System Status**：0x0400_0000，MIG 校准/MMCM/clk_wiz 状态只读
29. **AXI4-Lite Default Slave**：未映射地址返回 DECERR 响应，防止总线挂死
30. **总线桥仲裁**：one-outstanding 阻塞式适配，DCache（含 PTW）优先于 ICache，选中 owner 锁定至响应完成
31. **数据 MMU translate_en 门控**：mem_access_valid 同步控制 Sv32 翻译使能，消除组合信号竞争
32. **固定存储几何**：src/core/memory/cache/defs.svh 手工维护常量，config/vivado.yaml → tools/vivado/ip.py 生成 BRAM/时钟/MIG create_ip TCL
33. **SoC 配置宏**：src/soc/config.svh，SIMU_USE_PLL / SIMU_USE_DDR 仿真模式选择
34. **流水线总线结构体**：src/core/interface/types.svh，替代手工位索引
35. **外设中断路由**：UART/SPI/GPIO 中断输出经 PLIC 路由至 CPU（src[2]=UART, src[3]=SPI, src[4]=GPIO）
36. **A 扩展原子指令**：LR.W/SC.W + 9 条 AMO（AMOADD/AMOAND/AMOOR/AMOXOR/AMOMAX/AMOMAXU/AMOMIN/AMOMINU/AMOSWAP），dcache 保留集 + read-modify-write 原子操作，支持 Linux SMP
37. **ns16550a 标准串口**：替代原自定义 UART，16-byte TX/RX FIFO，标准寄存器映射，APB4 封装，Linux 串口控制台兼容
38. **sfence.vma 触发 TLB 全刷**：rs1/rs2 忽略，恒为全刷；satp 写变更同样触发。写通 DCache 无脏行无需刷新
39. **MMIO 判定使用 paddr**：MMIO 判断基于物理地址（TLB 翻译后），而非虚拟地址，修复 VA≠PA 时 MMIO 误命中缓存
40. **PMP 硬件强制**：pmpcfg0–pmpcfg3 + pmpaddr0–pmpaddr15 共 20 CSR + 16 项硬件检查器（TOR/NA4/NAPOT，首匹配优先，M-mode 豁免）
41. **time/timeh CSR**：0xC01/0xC81 只读，镜像 CLINT mtime，U-mode 计数器别名（需 mcounteren+scounteren 使能）
42. **misa = 0x40141101**：RV32IMASU（F 已移除），A bit[0]=1，M bit[12]=1，S bit[18]=1，U bit[20]=1
43. **GPIO 引脚变化中断**：逐引脚中断使能掩码 + 写 1 清除挂起状态
44. **SPI 传输完成中断**：CTRL[4] 中断使能，传输完成置挂起，写 STATUS 清除
45. **CLINT 可写 msip**：msip 寄存器（偏移 0x0000，SiFive 标准布局）支持软件中断，符合 RISC-V CLINT 规范
46. **共享 testbench 框架**：test/bench/support/soc_fixture.svh，SoC 级仿真 + DDR3 支持
47. **测试程序分类重组**：8 类（isa/exception/privilege/mmu/cache/mmio/regression/integration），52 个测试程序，361 个子测试
48. **Boot ROM 启动流程**：CPU 复位 PC=0xFC000000 → bootloader（sp 初始化 + DDR3 自检 + UART 接收程序镜像 + fence.i + 跳转）→ 主程序执行
49. **应用验证**：LED 跑马灯、UART Hello/Echo（含 C 运行时版）、Bootloader；52/52 测试程序通过，时序收敛 @40MHz 并生成 bitstream（2026-09-25，cf8b4e4）
50. **完整内存映射模型**：7 从设备地址译码 + APB 4 从设备子译码 + CLINT/PLIC/SysStatus/BootROM 寄存器级映射（见 §2.2）
51. **Linux 适配修复**：11 项 Linux 启动适配 bug 修复（MMIO paddr 判断、PTW-dcache 一致性、sfence.vma dcache 刷新、M/S 中断优先级、sip STIP 可写、PMP CSR、time/timeh CSR 等），详见历史提交记录
52. **特权返回/陷阱路径修复**（sub-issue ④⑤⑥⑦，2026-06-19）：
   - ④ **M-mode陷阱误委托**：`src/core/control/trap/router.sv` 的 `trap_to_s` 增加 `(priv_mode != PRIV_M)` 门控。Per RISC-V Priv Spec §3.1.10，M-mode 异常/中断不可委托到 S-mode，旧实现缺少此检查导致 OpenSBI trap handler 中的异常可能错误进入 S-mode，绕过 OpenSBI 直接交付内核，造成崩溃或无限重入
   - ⑤ **mideleg WARL掩码过宽**：`src/core/control/csr/top.sv` 的 mideleg_wmask 从 `0x0000_0AAA`（bits 1,3,5,7,9,11）改为 `0x0000_0222`（仅 bits 1,5,9 = SSI/STI/SEI）。M-mode 中断（MSI=3, MTI=7, MEI=11）不可委托，旧掩码允许写入这些位
   - ⑥ **mret特权违例检查缺失**：`src/core/pipeline/decode.sv` 新增 `mret_priv_violation = is_mret && (priv_mode != PRIV_M)`，S/U-mode 执行 mret 触发 illegal instruction 异常。旧实现允许 S-mode 静默执行 mret，导致特权降级到 U-mode 后所有 S-mode CSR 访问触发非法指令异常→无限重入循环
   - ⑦ **非BRAM TLB路径时序修复**：`src/core/memory/mmu/top.sv` 非 BRAM 路径添加 IDLE/LOOKUP FSM + 输入锁存（`nb_i_latched_priv_mode`/`nb_d_latched_priv_mode` 等），与 BRAM 路径模式一致，打断 `core_top.priv_mode → MMU.perm_check → page_fault` 组合逻辑长路径，改善时序收敛
53. **回归验证**：short 组 23 任务 + 全量 52 程序测试 361 子测试 PASS（build/test-results/program-tests.log：52 passed, 0 failed）
54. **测试程序缺陷修复**（2026-06-19）：修复 6 个测试批次的测试程序/TB 缺陷，全部从 FAIL→PASS。所有缺陷均为测试程序逻辑错误，非 RTL 硬件缺陷：
   - **cpu_trap**（5→14 PASS）：定时器处理程序设置 mtimecmp=0 导致无限重触发；MTIP=1 在复位时即有效（mtimecmp=0）；TB `check_mem_word` 使用错误地址（0x48 vs 0x1048）；dcache 写回未刷新（缺少 fence.i）；TB x20 期望值过时
   - **mmu_tlb_asid**（0→2 PASS）：test_04 访问 0x80008000 超出 setup_identity_map 映射范围（仅映射 L0[0-7]=0x80000000-0x80007FFF），改为 0x80005000
   - **mmu_tlb_replace/tlb_stress**（FAIL→PASS）：测试数据写入偏移 0x80 覆盖代码（页 0-1）和页表（页 2-3），改为偏移 0xF00 并跳过页 2-3
   - **mmu_tlb_megapage/sv32_edge**（1/4→4/4, 1/6→6/6 PASS）：`clear_page_tables` 清零 2048 项×~50 周期/次超出仿真周期预算（200K cycles），替换为仅清零 9 个实际使用项（L1[512]+L0[0-7]）的快速内联清零；每个子测试前增加 `disable_sv32` 确保防御性状态清理
