# SimpleCPU 设计报告

> 生成日期: 2026-06-13 | 项目路径: `dev/rtl/`

---

## 1. 项目概述

本项目实现了一个基于 RISC-V RV32IMF 指令集的多周期 CPU，采用五级流水线结构（取指-译码-执行-访存-回写），通过有限状态机（FSM）控制器协调各级运行。CPU 通过 AXI4 总线连接片上存储与外设，支持异常/中断陷阱处理、CSR 读写、M 扩展乘除法运算、F 扩展单精度浮点运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32IMF（整数 + 乘除法 + 单精度浮点） |
| 架构 | 多周期 FSM 控制，五级流水线数据通路 |
| 数据位宽 | 32-bit |
| 特权模式 | M/S/U 三级特权模式，支持陷阱委托（medeleg/mideleg） |
| 地址空间 | 32-bit，Sv32 页表虚拟内存（MMU + TLB + PTW） |
| 存储架构 | 哈佛结构（icache / dcache 分离），4 路组相联，Tree-PLRU 替换，VIPT |
| 缓存策略 | 写回（write-back）+ 写分配（write-allocate），脏行驱逐写回主存 |
| 标签存储 | BRAM IP（icachet 144-bit×8 / dcachet 144-bit×8），19-bit tag 覆盖 128MB DDR3，配置驱动 |
| TLB 架构 | 4 路 × 4 组组相联（16 项），BRAM IP（tlb_flag 128-bit×4 / tlb_data 128-bit×4），Tree-PLRU 替换 |
| 总线接口 | AXI4 Master（cpu_bus_bridge），支持 INCR8 突发读/写；AXI4-Lite 从设备（PLIC/CLINT/BootROM/SysStatus/APB Bridge） |
| 中断/异常 | 支持 Trap 进入/返回（mret/sret）、CLINT 定时器中断、PLIC 外部中断 |
| 特权指令 | SRET、SFENCE.VMA 指令支持 |
| 乘法器 | Booth 编码，32 周期迭代 |
| 除法器 | 非恢复余数法，32 周期迭代 + 修正 |
| 加法器 | 超前进位加法器（CLA），16-bit 级联为 32-bit |
| 浮点单元 | IEEE 754 单精度，多周期握手协议，5 种舍入模式 |
| 浮点寄存器 | 32×32-bit（f0-f31），f0 硬连线零 |
| 启动 ROM | AXI4-Lite Boot ROM（0xFC00_0000），32KB BRAM，CPU 复位起始地址，bootloader 跳转至 DDR3/SRAM |
| DDR3 SDRAM | AXI4 MIG 接口（axi_wrap_ddr），可选 ROM 行为模型（axi_wrap_ram） |
| 时钟域 | cpu_clk（50MHz）/ sys_clk（100MHz）/ ddr_clk_ref（200MHz），Axi_CDC 跨域 |
| 系统状态 | AXI4-Lite Sys Status（0x0400_0000），MIG 校准/MMCM 锁定/clk_wiz 锁定 |
| 起始地址 | `0xFC00_0000`（Boot ROM，复位后跳转至 `0x8000_0000`） |

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

**RV32F 单精度浮点扩展（22 条）：**

| 类别 | 指令 | 说明 |
|------|------|------|
| 计算 | `FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S` | IEEE 754 算术运算 |
| 平方根 | `FSQRT.S` | Newton-Raphson 迭代 |
| 加载/存储 | `FLW`, `FSW` | 浮点数据访存 |
| 转换 | `FCVT.W.S`, `FCVT.WU.S`, `FCVT.S.W`, `FCVT.S.WU` | 整数↔浮点互转 |
| 符号注入 | `FSGNJ.S`, `FSGNJN.S`, `FSGNJX.S` | 符号位操作（FMV.F.X / FNEG / FABS 伪指令基础） |
| 移动 | `FMV.X.W`, `FMV.W.X` | 整数↔浮点寄存器位模式传输 |
| 比较 | `FEQ.S`, `FLT.S`, `FLE.S` | 浮点比较（结果写整数寄存器） |
| 分类 | `FCLASS.S` | NaN/Inf/次正规数检测（10-bit 掩码写整数寄存器） |
| 最值 | `FMIN.S`, `FMAX.S` | 浮点最小/最大值 |

> **未实现**：FMA 四条（FMADD.S / FMSUB.S / FNMSUB.S / FNMADD.S），R4 格式译码复杂且硬件面积大；D 扩展（双精度）暂不实现，XLEN=32 时 FLEN=64 需额外设计。

---

## 2. 系统架构

### 2.1 顶层结构

```
system_top
├── Clock/Reset Architecture
│   ├── clk_wiz_0 (or sim direct)     ← 100MHz→50MHz CPU + 100MHz sys + 200MHz DDR ref
│   ├── reset_sync (×2)               ← Async assert, sync deassert (sys + cpu domains)
│   └── ddr_data_init / ddr_aresetn   ← DDR3 init gating (sim vs FPGA)
├── core_top              ← CPU 核心 (cpu_clk domain)
│   ├── cpu_controller    ← FSM 状态机控制器
│   ├── cpu_fetch         ← 取指级
│   ├── cpu_decode        ← 译码级
│   ├── cpu_execute       ← 执行级（含 ALU + MU + FPU）
│   ├── cpu_mem           ← 访存级
│   ├── cpu_wb            ← 回写级
│   ├── cpu_regfile       ← 32×32bit 整数寄存器堆
│   ├── fpu_regfile       ← 32×32bit 浮点寄存器堆（f0 硬连线零）
│   ├── cpu_trap_csr      ← 陷阱/CSR 子系统
│   ├── icache_ctrl       ← 指令缓存控制器（4路组相联，VIPT）
│   ├── dcache_ctrl       ← 数据缓存控制器（4路组相联，写回+写分配，VIPT）
│   ├── MMU (×2)          ← Sv32 虚拟内存（TLB + PTW 页表漫游）
│   └── cpu_bus_bridge    ← AXI4 总线桥接（MMIO + INCR8 突发，AW/W/B/AR/R 五通道）
├── Axi_CDC               ← AXI4 时钟域穿越（cpu_clk → sys_clk）
├── Address Decoder + Slave Mux  ← 手动地址译码 + 7 从设备多路复用（sys_clk domain）
│   ├── Slave 0: DDR3/RAM (axi_wrap_ddr / axi_wrap_ram)  ← 全 AXI4，addr[31:28]==4'h8
│   ├── Slave 1: Boot ROM (axi4lite_bootrom)              ← AXI4-Lite，addr[31:24]==8'hFC
│   ├── Slave 2: PLIC (axi4lite_plic)                     ← AXI4-Lite，addr[31:24]==8'h0C
│   ├── Slave 3: CLINT (axi4lite_clint)                   ← AXI4-Lite，addr[31:24]==8'h02
│   ├── Slave 4: APB Bridge (axi4lite_to_apb)             ← AXI4-Lite，addr[31:24]==8'h10
│   │   ├── apb_decoder
│   │   └── apb_perips
│   │       ├── GPIO          ← 16-bit 双向 IO，引脚变化中断（o_irq→PLIC src[4]）
│   │       ├── UART (TX/RX)  ← TX/RX FIFO（16字节），中断（o_irq→PLIC src[2]），可配波特率，RXDATA peek + STATUS-read auto-arm
│   │       ├── Timer          ← 32-bit 定时器，中断（o_irq→PLIC src[1]）
│   │       └── SPI            ← 主模式 SPI，传输完成中断（o_irq→PLIC src[3]）
│   ├── Slave 5: Sys Status (axi4lite_sys_status)         ← AXI4-Lite，addr[31:24]==8'h04
│   └── Slave 6: Default Slave (axi4lite_default_slave)   ← AXI4-Lite，DECERR 响应
├── DDR3 Conditional Generate
│   ├── SIMU_USE_DDR=0: axi_wrap_ram  ← BRAM 行为模型（零延迟，快速仿真）
│   └── SIMU_USE_DDR=1: axi_wrap_ddr  ← MIG + DDR3 SDRAM（真实硬件通路）
└── lcd_module            ← LCD 调试显示
```

**FPU 子模块结构**（在 `cpu_execute` 中实例化）：

```
fpu_unit
├── fpu_adder      ← 浮点加法器（FADD.S / FSUB.S），FSM: 对齐→加法→规格化→舍入
├── fpu_multiplier ← 浮点乘法器（FMUL.S），组合 24×24 尾数乘
├── fpu_divider    ← 浮点除法器（FDIV.S），非恢复余数迭代
├── fpu_sqrt       ← 浮点平方根（FSQRT.S），非恢复余数法
├── fpu_compare    ← 浮点比较器（FEQ.S / FLT.S / FLE.S），组合逻辑
├── fpu_minmax     ← 浮点最值（FMIN.S / FMAX.S），组合逻辑
├── fpu_classify   ← 浮点分类（FCLASS.S），组合逻辑
├── fpu_sign_inject← 符号注入（FSGNJ.S / FSGNJN.S / FSGNJX.S），组合逻辑
├── fpu_cvt        ← 浮点转换（FCVT.W.S / FCVT.S.W / FCVT.WU.S / FCVT.S.WU），FSM
├── fpu_round      ← 舍入模式逻辑（RNE / RTZ / RDN / RUP / RMM），27-bit 尾数舍入
├── fpu_special    ← NaN/Inf/零/次正规数检测与特殊处理
└── 结果选择器     ← 按 fpu_funct 选择结果，输出 fflags[4:0]
```

### 2.2 地址映射（Memory Map）

#### 2.2.1 顶层地址译码

`system_top` 内手动实现 7 从设备地址译码，优先级从高到低（译码逻辑为组合优先级）：

| 从设备编号 | 判定条件 | 地址范围 | 从设备 | 总线协议 | 说明 |
|-----------|----------|----------|--------|----------|------|
| Slave 0 | `addr[31:27] == 5'h10` | `0x8000_0000 ~ 0x87FF_FFFF` | DDR3/RAM | AXI4 | 主存储器（128MB 窗口，DDR3 或 SRAM 行为模型） |
| Slave 1 | `addr[31:24] == 8'hFC` | `0xFC00_0000 ~ 0xFCFF_FFFF` | Boot ROM | AXI4-Lite | 启动 ROM（32KB BRAM，只读） |
| Slave 2 | `addr[31:24] == 8'h0C` | `0x0C00_0000 ~ 0x0CFF_FFFF` | PLIC | AXI4-Lite | 平台级中断控制器（8 源） |
| Slave 3 | `addr[31:24] == 8'h02` | `0x0200_0000 ~ 0x02FF_FFFF` | CLINT | AXI4-Lite | 核心本地中断器（mtime/mtimecmp/msip） |
| Slave 4 | `addr[31:24] == 8'h10` | `0x1000_0000 ~ 0x10FF_FFFF` | APB Bridge | AXI4-Lite | 外设桥（GPIO/Timer/UART/SPI） |
| Slave 5 | `addr[31:24] == 8'h04` | `0x0400_0000 ~ 0x04FF_FFFF` | Sys Status | AXI4-Lite | 系统状态（只读） |
| Slave 6 | 其他 | 未映射 | Default Slave | AXI4-Lite | 返回 DECERR 响应 |

> **注意**：Slave 0（DDR3）判定条件为 `addr[31:27]==5'h10`（即 `0x80`~`0x87` 开头），覆盖 128MB 地址窗口。此判定优先于 Default Slave，确保 DDR3 访问不被误路由。

**Cache/MMIO 判定规则**：`addr[31]==0 || addr[30]==1` 为 MMIO 区域（走 AXI 总线旁路缓存），其余为 Cacheable 区域（走 icache/dcache）。

#### 2.2.2 完整内存映射图

```
0xFFFF_FFFF ┌──────────────────────┐
            │     未映射区域        │ → Default Slave (DECERR)
0xFD00_0000 ├──────────────────────┤
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
            │  ├─ 0x1000_4000 Timer (PSELx[1], PADDR[15:14]==01)
            │  ├─ 0x1000_8000 UART  (PSELx[2], PADDR[15:14]==10)
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

基地址：`0x0200_0000`，AXI4-Lite，按 `addr[3:0]` 译码：

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x00 | mtimecmp_lo | RW | 定时器比较值低 32 位 |
| 0x04 | mtimecmp_hi | RW | 定时器比较值高 32 位 |
| 0x08 | mtime_lo | RW | 定时器计数值低 32 位（mtime 每周期自增 1） |
| 0x0C | mtime_hi | RW | 定时器计数值高 32 位 |
| 0x10 | msip | RW | 软件中断挂起（写 [0] 位设置/清除 MSIP） |

> 中断产生条件：`mtime[63:0] >= mtimecmp[63:0]` 时 MTIP=1。

#### 2.2.4 PLIC 寄存器映射

基地址：`0x0C00_0000`，AXI4-Lite，支持 8 个中断源（NUM_SRC=8）：

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x00 ~ 0x1C | priority[0:7] | RW | 每源优先级（4 字节对齐，addr[7:2] 索引） |
| 0x400 ~ 0x41F | pending[0:7] | R | 每源挂起状态（只读，硬件置位） |
| 0x800 | enable | RW | 中断使能掩码（32-bit，每源 1 位） |
| 0x200_000 | threshold | RW | 优先级阈值（仅优先级 > threshold 的中断可_claim） |
| 0x200_004 | claim/complete | RW | 声明最高优先级中断（读返回 ID，写完成处理） |

> PLIC 中断路由：src[1]=Timer, src[2]=UART, src[3]=SPI, src[4]=GPIO。

#### 2.2.5 APB 外设地址子译码

APB Bridge 基地址：`0x1000_0000`，4 个 APB 从设备按 `PADDR[15:14]` 译码：

| APB 从设备 | 判定条件 | 基地址 | 地址空间 | 说明 |
|-----------|----------|--------|----------|------|
| GPIO | `PADDR[15:14] == 2'b00` | `0x1000_0000` | `0x1000_0000 ~ 0x1000_3FFF` | 16-bit 双向 IO |
| Timer | `PADDR[15:14] == 2'b01` | `0x1000_4000` | `0x1000_4000 ~ 0x1000_7FFF` | 32-bit 定时器 |
| UART | `PADDR[15:14] == 2'b10` | `0x1000_8000` | `0x1000_8000 ~ 0x1000_BFFF` | TX/RX FIFO |
| SPI | `PADDR[15:14] == 2'b11` | `0x1000_C000` | `0x1000_C000 ~ 0x1000_FFFF` | 主模式 SPI |

**GPIO 寄存器映射**（基址 `0x1000_0000`）：

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | CTRL | 方向控制（1=输出，0=输入） |
| 0x04 | DATA | 数据寄存器 |
| 0x08 | IRQ_EN | 逐引脚中断使能掩码 |
| 0x0C | IRQ_STAT | 逐引脚中断挂起（写 1 清除） |

**Timer 寄存器映射**（基址 `0x1000_4000`）：

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | CTRL | 控制寄存器（使能/模式） |
| 0x04 | CNT | 当前计数值 |
| 0x08 | CMP | 比较值 |

**UART 寄存器映射**（基址 `0x1000_8000`）：

| 偏移 | 名称 | 位定义 | 说明 |
|------|------|--------|------|
| 0x00 | CTRL | [0]=TX_EN [1]=RX_EN [2]=TX_IE [3]=RX_IE | 控制/中断使能 |
| 0x04 | STATUS | [0]=TX_BUSY [1]=RX_VALID [2]=TX_FIFO_FULL [3]=RX_FIFO_EMPTY [4]=TX_FIFO_EMPTY [5]=RX_FIFO_FULL | FIFO 状态；**读取时若 RX_VALID=1 自动武装下次 RXDATA 弹出** |
| 0x08 | TXDATA | [7:0] | 写入推入 TX FIFO |
| 0x0C | RXDATA | [7:0] | 读取：若 `rx_pop_armed=1` 弹出 FIFO 并清标志；否则仅 peek |
| 0x10 | BAUD | [15:0] | 波特率分频系数（0=默认 115200） |
| 0x14 | IRQ_STAT | [0]=TX_DONE_IRQ [1]=RX_VALID_IRQ | 中断挂起（写 1 清除） |
| 0x18 | RXPOP | — | 保留（写 1 弹出 RX FIFO） |

**SPI 寄存器映射**（基址 `0x1000_C000`）：

| 偏移 | 名称 | 位定义 | 说明 |
|------|------|--------|------|
| 0x00 | CTRL | [0]=EN [1]=CPOL [2]=CPHA [3]=CS [4]=IRQ_EN [15:8]=CLK_DIV | 控制/中断使能 |
| 0x04 | DATA | [7:0] | 数据寄存器 |
| 0x08 | STATUS | [0]=BUSY [1]=IRQ_PENDING | 状态/中断挂起 |

#### 2.2.6 System Status 寄存器映射

基地址：`0x0400_0000`，AXI4-Lite 只读，按 `addr[3:0]` 译码：

| 偏移 | 位定义 | 说明 |
|------|--------|------|
| 0x00 | [0]=init_calib_complete [1]=mig_mmcm_locked [2]=clk_wiz_locked [31:3]=保留 | 系统状态（只读） |

#### 2.2.7 Boot ROM 地址映射

基地址：`0xFC00_0000`，AXI4-Lite 只读，32KB BRAM（MEM_DEPTH=8192），写通道静默应答 OKAY。

CPU 复位起始地址为 `0xFC00_0000`，启动流程：`复位 PC=0xFC00_0000` → Boot ROM 取 bootloader → bootloader 初始化 sp → DDR3 自检 → UART 接收程序镜像 → fence.i → 跳转至 `0x8000_0000` → 执行主程序。

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

**指令识别**：通过 opcode + funct3 + funct7 组合译码，识别全部 70 条指令（含 M 扩展 8 条 + F 扩展 22 条）。

**操作数选择**：

- `alu_src1`：AUIPC/JAL/分支使用 PC，其余使用 rs1
- `alu_src2`：LUI/AUIPC 使用 imm_u，JAL 使用 imm_j，JALR 使用 imm_i，分支使用 imm_b，立即数算术使用 imm_i，移位使用 shamt，Load 使用 imm_i，Store 使用 imm_s，FLW 使用 imm_i，FSW 使用 imm_s，其余使用 rs2

**浮点操作数选择**：

- 浮点计算指令（FADD/FSUB/FMUL/FDIV/FSQRT/FEQ/FLT/FLE/FMIN/FMAX/FSGNJ*/FCLASS）读取浮点寄存器 frs1/frs2
- 整数→浮点指令（FMV.W.X / FCVT.S.W / FCVT.S.WU）读取整数寄存器 rs1，通过 `fpu_src_is_int` 标志在执行级 mux 选择
- 浮点→整数指令（FMV.X.W / FCVT.W.S / FCVT.WU.S）结果写整数寄存器，通过 `fpu_rd_is_int` 标志路由

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

> FLW/FSW 的 ALU 控制码为 ADD（计算访存地址），与整数 Load/Store 一致。

**FPU 控制信号**：

| 信号 | 位宽 | 说明 |
|------|------|------|
| `is_fpu` | 1 | 当前指令为浮点运算指令 |
| `is_flw` | 1 | 当前指令为 FLW |
| `is_fsw` | 1 | 当前指令为 FSW |
| `fpu_funct` | 7 | 浮点操作码（0=FADD ~ 19=FCVT.S.WU） |
| `fpu_rm` | 3 | 舍入模式（来自 funct3，DYN=111 在执行级用 CSR frm 替换） |
| `fpu_rd_is_int` | 1 | 结果写整数寄存器（FEQ/FLT/FLE/FCLASS/FMV.X.W/FCVT.W.S/FCVT.WU.S） |

**浮点指令 opcode 识别**：

| opcode | 名称 | 指令 |
|--------|------|------|
| 0x07 (0000111) | LOAD-FP | FLW |
| 0x27 (0100111) | STORE-FP | FSW |
| 0x53 (1010011) | OP-FP | FADD.S/FSUB.S/FMUL.S/FDIV.S/FSQRT.S/FMIN.S/FMAX.S/FSGNJ*/FCVT/FEQ/FLT/FLE/FCLASS/FMV.X.W/FMV.W.X |

**非法指令检测**：无效指令编码、CSR 地址无效、写只读 CSR 均触发非法指令异常。

**ID/EX 总线**（334-bit）：`{pc_plus4, valid_inst, is_alu, is_load, is_store, is_jal_like, is_branch, use_fixed_wb, wb_we, rd, wb_fixed_data, mem_size, mem_unsigned, alu_control[15:0], is_mu, mu_funct3, alu_src1, alu_src2, rs1_value, rs2_value, branch_funct3, is_csr, is_ecall, is_ebreak, is_mret, csr_addr, csr_funct3, csr_uimm, pc, inst, is_fpu, is_flw, is_fsw, fpu_funct[6:0], fpu_rm[2:0], fpu_rd_is_int}`

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

**浮点运算单元 (`fpu_unit`)**：

采用与 `mu_unit` 相同的多周期握手协议，FSM 控制器在 STATE_EXEC 内轮询 `fpu_result_valid`，与 MU 等待逻辑一致，无需新增 FSM 状态。

- 握手协议：`req_valid → fpu_ready → fpu_busy → result_valid → result_got`
- 操作码 `fpu_funct[6:0]`：20 种浮点操作（FADD=0 ~ FCVT.S.WU=19）
- 舍入模式 `fpu_rm[2:0]`：来自指令 funct3，DYN(111) 在执行级用 CSR frm 替换
- 异常标志 `fflags[4:0]`：{NV, DZ, OF, UF, NX}，写回时 OR 累积至 CSR fflags
- 结果路由：`fpu_rd_is_int=1` → 写整数寄存器，否则 → 写浮点寄存器
- `fpu_active` 信号与 `mu_busy` 互斥，确保同一时刻仅一个多周期运算单元活跃

**FPU 子模块算法**：

| 子模块 | 指令 | 算法 | 周期数 |
|--------|------|------|--------|
| `fpu_adder` | FADD.S / FSUB.S | FSM: 对齐→加/减→前导零计数→规格化→舍入 | 3-5 周期 |
| `fpu_multiplier` | FMUL.S | 组合 24×24 尾数乘 + 规格化 + 舍入 | 1-2 周期 |
| `fpu_divider` | FDIV.S | 非恢复余数迭代（26-bit 商）+ 规格化 + 舍入 | ~27 周期 |
| `fpu_sqrt` | FSQRT.S | 非恢复余数法（28-bit 根）+ 规格化 + 舍入 | ~27 周期 |
| `fpu_cvt` | FCVT.* | FSM: COMPUTE→ROUND | 2-3 周期 |
| `fpu_compare` | FEQ/FLT/FLE | 组合逻辑（含 +0==-0 特殊处理） | 单周期 |
| `fpu_minmax` | FMIN/FMAX | 组合逻辑（NaN 输入返回 qNaN + NV） | 单周期 |
| `fpu_classify` | FCLASS | 组合逻辑（10-bit 掩码） | 单周期 |
| `fpu_sign_inject` | FSGNJ/FSGNJN/FSGNJX | 组合逻辑（符号位替换/取反/异或） | 单周期 |
| `fpu_round` | — | 27-bit 尾数舍入（G/R/S 位），5 种模式 | 组合逻辑 |
| `fpu_special` | — | NaN/Inf/零/次正规数检测，字段提取 | 组合逻辑 |

**JALR 对齐**：结果与 `0xFFFF_FFFE` 按位与，清除最低位。

**分支/跳转目标**：

- 分支：条件成立时目标 = ALU 结果（pc + imm_b）
- JAL：目标 = ALU 结果（pc + imm_j）
- JALR：目标 = ALU 结果 & ~1（rs1 + imm_i）

**指令对齐异常检测**：跳转目标 `[1:0] != 00` 时触发指令地址对齐异常（Exception Code = 0）。

**EX/MEM 总线**（216-bit）：`{pc_plus4, result_ok, is_jal_like, is_load, is_store, is_csr, wb_we, wb_rd, result_reg, mem_size, mem_unsigned, rs2_value, csr_rdata, pc, inst, is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0]}`

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

**MEM/WB 总线**（177-bit）：`{pc_plus4, is_jal_like, is_csr, wb_we, wb_rd, wb_data, csr_rdata, pc, inst, is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0]}`

### 3.6 回写级 (`cpu_wb`)

- 整数寄存器写使能：`wb_valid && wb_we && !is_flw`（FLW 不写整数寄存器）
- 写数据选择：CSR 指令写回 CSR 读出值，其余写回 ALU/MU/FPU/Load 结果
- JAL/JALR 写回值：`pc + 4`（在 `core_top` 中通过 `wb_is_jal_like` 信号选择）
- 寄存器 x0 硬连线为 0（在 `cpu_regfile` 中实现）
- **浮点寄存器写使能**：`wb_valid && (is_fpu || is_flw)`
- **浮点写数据**：FPU 计算结果 / FLW 加载数据
- **fflags 累积**：`wb_valid && (fpu_fflags != 0)` 时，OR 累积至 CSR fflags（`fflags_wen` 需 `wb_valid` 门控，防止残留总线数据误写）

### 3.7 寄存器堆 (`cpu_regfile`)

- 32 个 32-bit 整数寄存器
- x0 恒为 0（读返回 0，写忽略）
- 单写端口，双读端口
- 附加调试读端口（`dbg_raddr`/`dbg_rdata`）

### 3.8 浮点寄存器堆 (`fpu_regfile`)

- 32 个 32-bit 浮点寄存器（f0-f31）
- f0 恒为 0（设计选择，RISC-V 规范不要求 f0=0，但简化设计）
- 单写端口，双读端口
- 附加调试读端口（`dbg_faddr`/`dbg_fdata`）
- 参数化 FLEN（当前=32，D 扩展时=64）

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
| 0x300 | mstatus | 是 | MPP/MPIE/MIE/SPP/SPIE/SIE/FS/UXS/XS/SD |
| 0x001 | fflags | 是 | 累积浮点异常标志 {NV, DZ, OF, UF, NX} |
| 0x002 | frm | 是 | 动态舍入模式（0=RNE, 1=RTZ, 2=RDN, 3=RUP, 4=RMM） |
| 0x003 | fcsr | 是 | 合并寄存器 {frm[2:0], fflags[4:0]} |
| 0x301 | misa | 否 | 硬连线 `0x40141120`（RV32IMFSU） |
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

**sstatus 与 mstatus 的关系**：sstatus 是 mstatus 的受限视图，仅暴露 SIE（位1）、SPIE（位5）、SPP（位8）、FS（位14:13）、UXS（位18:17）、XS（位16:15）、SD（位31）。对 sstatus 的写操作仅修改 mstatus 中对应位，其余位保持不变。

**mstatus.FS 域**（位14:13）：浮点状态，00=Off, 01=Initial, 10=Clean, 11=Dirty。写浮点寄存器时置 FS=Dirty。当前实现中 FS 域可读写，但未强制 FS=Off 时浮点指令触发异常（为简化设计）。

**fflags 写逻辑**：软件 CSR 写与硬件 FPU 异常 OR 累积合并。当软件写 fflags/fcsr 与硬件 fflags_wen 同时发生时，先写入软件值再 OR 硬件异常标志（符合 RISC-V F 扩展规范 21.2）。`fflags_wen` 需 `wb_valid` 门控，防止写回后残留 `mem_wb_bus_r` 触发假写。

**CSR 访问控制**：

- U-mode：不可访问 S-mode 和 M-mode CSR，访问触发非法指令异常
- S-mode：不可访问 M-mode CSR，访问触发非法指令异常
- M-mode：可访问所有 CSR

CSR 写掩码：mstatus 仅允许写 MPP[12:11]、SPP[8]、MPIE[7]、SPIE[5]、MIE[3]、SIE[1]、FS[14:13]；mie 仅允许写 MEIE[11]、SEIE[9]、MTIE[7]、STIE[5]、MSIE[3]、SSIE[1]；mtvec/mepc/stvec/sepc 强制低 2 位为 0。fflags/frm/fcsr 为可写 CSR，fflags 写入后作为后续 OR 累积的基础值。

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

- MMIO 旁路：`vaddr[31]==0` 时直接发 AXI 请求，不经过缓存（使用虚拟地址判断，因为物理地址可能在 MMU 未就绪时无效）
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

将 Cache Refill/Writeback、MMIO 和 PTW 请求转换为 AXI4 Master 协议（五通道：AW/W/B/AR/R）：

```
S_IDLE: 仲裁请求（优先级: icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill）

MMIO 读:  S_MMIO_AR → S_MMIO_R
MMIO 写:  S_MMIO_AW_W (AW+W 同时驱动) → S_MMIO_B
IRefill:  S_IREFILL_AR → S_IREFILL_R (INCR8 突发，8 拍)
DRefill:  S_DREFILL_AR → S_DREFILL_R (INCR8 突发，8 拍)
WB:       S_WB_AW → S_WB_W (INCR8 突发，8 拍) → S_WB_B
PTW 读:   S_PTW_AR → S_PTW_R
PTW 写:   S_PTW_AW_W → S_PTW_B
```

**AXI4 信号映射**：
- AW 通道：awid[3:0], awaddr[31:0], awlen[7:0], awsize[2:0], awburst[1:0], awlock, awcache[3:0], awprot[2:0], awqos[3:0], awregion[3:0], awvalid/awready
- W 通道：wdata[31:0], wstrb[3:0], wlast, wvalid/wready
- B 通道：bresp[1:0], bvalid/bready
- AR 通道：arid[3:0], araddr[31:0], arlen[7:0], arsize[2:0], arburst[1:0], arlock, arcache[3:0], arprot[2:0], arqos[3:0], arregion[3:0], arvalid/arready
- R 通道：rdata[31:0], rresp[1:0], rlast, rvalid/rready

**突发传输**：
- Cache Refill：ARBURST=INCR, ARLEN=7（8 拍），ARSIZE=4 字节
- Cache Writeback：AWBURST=INCR, AWLEN=7, AWSIZE=4 字节
- Refill 累积：`refill_shift_reg = {RDATA, refill_shift_reg[255:32]}`，8 拍后得到完整 256-bit 行
- MMIO/PTW：单拍传输（ARLEN=0/AWLEN=0）

**错误响应**：SLVERR/DECERR 通过 rresp/bresp 传递，触发对应错误标志

**优先级防饿**：icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill

### 5.8 存储从设备（DDR3/SRAM）

主存储器通过条件生成选择后端，地址映射 0x8000_0000（addr[31:28]==4'h8）：

- **SRAM 仿真模式**（`SIMU_USE_DDR=0`）：`axi_wrap_ram` 作为 AXI4 从设备，BRAM 行为模型，零延迟（awready=1, wready=1, arready=1），支持 INCR 突发，快速仿真
- **DDR3 模式**（`SIMU_USE_DDR=1` 或 FPGA）：`axi_wrap_ddr` 封装 MIG（mig_axi_32），地址重映射基址 0x8000_0000，输出 `ddr_aresetn`（init_calib_complete），访问真实 DDR3 SDRAM

### 5.9 Clock/Reset Architecture

系统采用三时钟域设计：

| 时钟域 | 频率 | 来源 | 用途 |
|--------|------|------|------|
| cpu_clk | 50MHz | clk_wiz_0 clk_out1 | CPU 核心及内部缓存 |
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
- W/B/R 通道：跟随锁存的 slave_sel（AW valid 时锁存，防止 CDC 管线延迟导致 W 先于 AW 到达）
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
- 写通道静默应答 OKAY（ROM 只读）
- 读通道 1 周期 BRAM 延迟，R 通道 FSM 握手需 `rvalid && rready` 双条件（BUG-83 修复）
- 内容由 `$readmemh` 在 elaboration 阶段加载（bootloader.hex）
- **启动流程**：CPU 复位 PC=0xFC00_0000 → Boot ROM 取 bootloader → bootloader 初始化 sp → DDR3 自检 → UART 接收程序镜像 → fence.i 刷新缓存 → 跳转至 load_addr → 执行主程序

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
- 单拍传输转换，保持 APB 外设不变

### 5.17 MMU（Sv32 虚拟内存）

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
- 写回通过 PTW 总线请求完成，旁路 dcache 直接到 AXI→BRAM

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

### 5.18 总线桥接 PTW 路径 (`cpu_bus_bridge`)

`cpu_bus_bridge` 除了处理 Cache Refill/Writeback 和 MMIO 请求外，还负责 PTW 的读写请求。PTW 请求旁路 dcache，直接通过 AXI 总线访问 BRAM 中的页表数据。

**PTW 请求处理**：

- PTW 读请求：读取页表项（L1/L0 PTE），直接发 AXI4 单拍读
- PTW 写请求：A/D 位写回，直接发 AXI4 单拍写
- 旁路 dcache：PTW 请求不经过 dcache，避免缓存一致性问题和死锁

**仲裁优先级**（从高到低）：

```
icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill
```

PTW 优先级高于 Cache Writeback 和 Refill，确保页表漫游不会被缓存操作阻塞，但低于 MMIO 请求以保证外设访问的实时性。

**PTW 总线错误处理**（Bug 10/11 修复）：

当 PTW 发起的 AXI4 请求收到错误响应（RRESP/BRESP=SLVERR/DECERR）时：
1. 置 `ptw_error_r = 1`
2. PTW 状态机进入 S_FAULT
3. 产生页错误异常，由陷阱管理器处理

### 5.19 配置驱动的存储几何 (`cache_def.svh`)

所有 Cache/TLB 几何参数由 `vivado_config.yaml` 的 `memory` 段统一定义，通过自动生成链保持 IP 与 RTL 同步：

```
vivado_config.yaml
  ├─→ ip_gen.py           → create_ip TCL（BRAM 几何参数：ROM/icached/dcached/icachet/dcachet/tlb_flag/tlb_data）
  ├─→ cache_header_gen.py → cache_def.svh（`define 宏：地址切片、宽度常量、存储模式）
  └─→ operations.py       → _tcl_setup_ip() 在 create/refresh 时执行
```

**`cache_def.svh`** 为自动生成文件（勿手动编辑），包含：

- ROM 参数：`ROM_DATA_WIDTH`、`ROM_DEPTH`、`ROM_ADDR_WIDTH`
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
| `rom.data_width` | 32 | ROM 字宽 |
| `rom.depth` | 8192 | ROM 深度（32KB） |
| `rom.byte_enable` | false | ROM 字节写使能（当前关闭） |
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

### 6.1 AXI4 互联

- 7 从设备：DDR3/RAM, Boot ROM, PLIC, CLINT, APB Bridge, Sys Status, Default Slave
- 地址译码：按 `addr[31:28]` 或 `addr[31:24]` 选择从设备
- Default Slave：未映射地址返回 DECERR 响应，防止总线挂死
- 手动地址译码 + 从设备多路复用（system_top 内实现）
- 时钟域穿越：Axi_CDC (cpu_clk → sys_clk)

### 6.2 APB 总线与外设

通过 AXI4-Lite to APB 桥接访问（基址 `0x1000_0000`，详细地址映射见 §2.2.5）：

| 外设 | 基地址 | 说明 |
|------|--------|------|
| GPIO | `0x1000_0000` | 16-bit 双向 IO，引脚变化中断，中断使能/状态寄存器 |
| Timer | `0x1000_4000` | 32-bit 定时器，产生中断，单次/周期模式 |
| UART | `0x1000_8000` | TX/RX FIFO（16 字节），中断输出，运行时波特率配置，RXDATA peek + STATUS-read auto-arm（应对 CPU 重复 AXI 事务 bug） |
| SPI | `0x1000_C000` | 主模式 SPI 控制器，传输完成中断 |

#### 6.2.1 UART STATUS-read auto-arm 机制

由于 CPU 数据总线存在每条 `lw`/`sw` 指令触发两次 AXI4-Lite 事务的 bug，直接弹出 RXDATA 会导致每隔一字节丢失。解决方案：读取 STATUS 且 `RX_VALID=1` 时置 `rx_pop_armed=1`，后续 RXDATA 读取在该标志有效时弹出 FIFO 并清标志，重复读取仅 peek 不弹。此机制使重复总线事务对 FIFO 无副作用。

#### 6.2.2 PLIC 中断路由

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
| `id_exe_bus` | 334-bit | 完整译码结果（见 3.3 节，含 FPU 控制信号） |
| `exe_mem_bus` | 216-bit | 执行结果 + 访存控制 + FPU 标志（见 3.4 节） |
| `mem_wb_bus` | 177-bit | 访存结果 + 回写控制 + FPU 标志（见 3.5 节） |

级间设置触发器（`if_id_bus_r`, `id_exe_bus_r`, `exe_mem_bus_r`, `mem_wb_bus_r`）作为流水线寄存器，在对应级完成时锁存。

---

## 8. 验证

### 8.1 应用层验证状态

> 更新时间: 2026-06-13 | 基于 commit `bb4b3fb`（成功完成计算器、echo）

| 应用 | 程序 | 验证方式 | 结果 | 说明 |
|------|------|----------|------|------|
| LED 跑马灯 | `led_marquee.hex` | 仿真 + 上板 | ✓ PASS | GPIO 输出 + CLINT MTIP 定时器驱动，16 项检查全通过 |
| UART Echo | `uart_echo.hex` | 仿真 + 上板 | ✓ PASS | UART 回环收发，testbench 内嵌 TX 引擎 + RX 解码器 |
| 浮点计算器 | `calculator.hex` | 仿真 + 上板 | ✓ PASS | UART IO 递归下降表达式解析，5 项算式全通过 |
| Bootloader 仿真 | `bootloader_full.hex` | 仿真 | ✓ PASS | sp 初始化 → MIG 等待 → DDR3 自检 → UART 接收镜像 → fence.i → 跳转执行，全链路通过 |

**里程碑**：项目已从"ISA 单元测试通过"进入"系统集成应用验证"阶段，三个应用均成功上板运行，bootloader 全链路仿真通过。

### 8.2 测试平台

| Testbench | 程序 | 测试内容 | 结果 |
|-----------|------|----------|------|
| `tb_simple_cpu_top` | `cpu_full.hex` | 完整指令集测试 + UART Bootloader 程序下载 + SRAM 内存验证 | 41 PASS, 0 FAIL |
| `tb_simple_cpu_compute` | `cpu_compute.hex` | 算术/逻辑/移位/乘除法计算测试 | 42 PASS, 0 FAIL |
| `tb_simple_cpu_trap` | `cpu_trap.hex` | 异常/中断陷阱处理测试 | 14 PASS, 0 FAIL |
| `tb_isa_alu` | `alu.hex` | ALU ISA 测试 | — |
| `tb_isa_branch` | `branch.hex` | 分支 ISA 测试 | — |
| `tb_isa_jump` | `jump.hex` | 跳转 ISA 测试 | — |
| `tb_isa_memory` | `memory.hex` | 访存 ISA 测试 | — |
| `tb_isa_upper_imm` | `upper_imm.hex` | 上位立即数 ISA 测试 | — |
| `tb_isa_m_ext` | `m_ext.hex` | M 扩展 ISA 测试 | — |
| `tb_isa_csr` | `csr.hex` | CSR ISA 测试 | — |
| `tb_isa_f_ext` | `f_ext.hex` | F 扩展 ISA 测试 | 26 PASS, 0 FAIL |
| `tb_isa_f_ext_special` | `f_ext_special.hex` | F 扩展特殊值/舍入测试 | 24 PASS, 0 FAIL |
| `tb_exception_illegal_inst` | `illegal_inst.hex` | 非法指令异常测试 | — |
| `tb_exception_ecall` | `ecall.hex` | ECALL 异常测试 | — |
| `tb_exception_ebreak` | `ebreak.hex` | EBREAK 异常测试 | — |
| `tb_exception_access_fault` | `access_fault.hex` | 访问错误异常测试 | — |
| `tb_exception_interrupt_basic` | `interrupt_basic.hex` | 基本中断测试 | — |
| `tb_exception_timer_irq` | `timer_irq.hex` | 定时器中断测试 | — |
| `tb_cache_icache_basic` | `icache_basic.hex` | ICache 基本功能测试 | — |
| `tb_cache_dcache_basic` | `dcache_basic.hex` | DCache 基本功能测试 | — |
| `tb_cache_dcache_dirty` | `dcache_dirty.hex` | DCache 脏行写回测试 | — |
| `tb_cache_fencei` | `fencei.hex` | FENCE.I 缓存一致性测试 | — |
| `tb_cache_cache_mmu_interact` | `cache_mmu_interact.hex` | Cache/MMU 交互测试 | — |
| `tb_mmu_sv32_basic` | `sv32_basic.hex` | Sv32 基本翻译测试 | — |
| `tb_mmu_sv32_edge` | `sv32_edge.hex` | Sv32 边界条件测试 | — |
| `tb_mmu_ptw_walk` | `ptw_walk.hex` | PTW 页表漫游测试 | — |
| `tb_mmu_tlb_basic` | `tlb_basic.hex` | TLB 基本功能测试 | — |
| `tb_mmu_tlb_flush` | `tlb_flush.hex` | TLB 刷新测试 | — |
| `tb_mmu_tlb_asid` | `tlb_asid.hex` | TLB ASID 感知测试 | — |
| `tb_mmu_tlb_megapage` | `tlb_megapage.hex` | TLB 大页匹配测试 | — |
| `tb_mmu_tlb_replace` | `tlb_replace.hex` | TLB 替换策略测试 | — |
| `tb_mmu_tlb_stress` | `tlb_stress.hex` | TLB 压力测试 | — |
| `tb_mmu_permission` | `permission.hex` | 页表权限检查测试 | — |
| `tb_mmu_page_fault` | `page_fault.hex` | 页错误测试 | — |
| `tb_mmu_unified_mmu` | `unified_mmu.hex` | 统一 MMU 测试 | — |
| `tb_privilege_csr_access_priv` | `csr_access_priv.hex` | CSR 特权访问测试 | — |
| `tb_privilege_delegation` | `delegation.hex` | 陷阱委托测试 | — |
| `tb_privilege_priv_transition` | `priv_transition.hex` | 特权级转换测试 | — |
| `tb_mmio_clint` | `clint.hex` | CLINT MMIO 测试 | — |
| `tb_mmio_plic` | `plic.hex` | PLIC MMIO 测试 | — |
| `tb_regression_reg_bare_no_miss` | `reg_bare_no_miss.hex` | 回归：裸机无缺失 | — |
| `tb_regression_reg_mmio_ready` | `reg_mmio_ready.hex` | 回归：MMIO ready 时序 | — |
| `tb_regression_reg_pf_latch` | `reg_pf_latch.hex` | 回归：页错误锁存 | — |
| `tb_regression_reg_ptw_fault_latch` | `reg_ptw_fault_latch.hex` | 回归：PTW 错误锁存 | — |
| `tb_regression_reg_sfence_during_walk` | `reg_sfence_during_walk.hex` | 回归：漫游中 SFENCE | — |
| `tb_regression_reg_stale_paddr` | `reg_stale_paddr.hex` | 回归：过期物理地址 | — |
| `tb_regression_reg_tlb_fill_way` | `reg_tlb_fill_way.hex` | 回归：TLB 填充路选择 | — |
| `tb_led_marquee` | `led_marquee.hex` | LED 跑马灯 + GPIO + CLINT MTIP 测试 | 16 PASS, 0 FAIL |
| `tb_uart_hello` | `uart_hello.hex` | UART 输出测试 | 12 PASS, 0 FAIL |
| `tb_uart_echo` | `uart_echo_test.hex` | UART 回环测试 | — |
| `tb_calculator` | `calculator.hex` | 浮点计算器应用测试 | 5 PASS, 0 FAIL |
| `tb_ahb_bus` | — | AXI4 总线功能测试（原 AHB 总线测试已适配） | — |
| `tb_apb_perips` | — | APB 外设功能测试 | — |
| `tb_non_restoring_divider` | — | 除法器单元测试 | — |
| `tb_mu_unit` | — | 乘除法单元测试 | — |
| `tb_alu_cpu_integration` | — | ALU 集成测试 | — |
| `tb_fpu_adder` | — | FPU 加法器单元测试 | 30 PASS |
| `tb_fpu_multiplier` | — | FPU 乘法器单元测试 | 13 PASS |
| `tb_fpu_divider` | — | FPU 除法器单元测试 | 12 PASS |
| `tb_fpu_sqrt` | — | FPU 平方根单元测试 | 22 PASS |
| `tb_fpu_cvt` | — | FPU 转换单元测试 | 20 PASS |
| `tb_fpu_unit` | — | FPU 顶层集成测试 | 24 PASS |

### 8.3 验证方法

- 寄存器检查：通过 `rf_addr`/`rf_data` 端口直接读取整数寄存器堆，与期望值比对
- 浮点寄存器检查：通过 `dbg_faddr`/`dbg_fdata` 端口直接读取浮点寄存器堆，与期望 IEEE 754 位模式比对
- 存储器检查：BRAM IP 内部数组路径在仿真中不可直接访问，标记为 SKIP
- UART 检查：testbench 内嵌 UART RX 解码器，逐字符比对输出
- GPIO 检查：监测 GPIO 端口状态变化，验证 LED 跑马灯序列
- FPU 单元测试：每个 FPU 子模块独立 testbench，边界值（±0, ±Inf, qNaN, sNaN, 最大/最小正规数, 最大/最小次正规数）+ 随机浮点对对照
- FPU ISA 测试：自检程序（x28=pass, x30=first_fail_id），覆盖全部 22 条浮点指令 + 特殊值 + 5 种舍入模式
- 计算器测试：testbench 内嵌 UART TX 引擎发送算式 + RX 解码器捕获输出，逐算式比对结果
- PASS/FAIL 计数汇总
- 共享 testbench 框架：`tb_soc_includes.svh`（system_top 实例化 + 时钟/复位 + DDR3 仿真支持 + check_reg/check_mem_word 任务 + pass/fail 计数）
- DDR3 仿真支持：ddr3_model + axi4_write task + write_hex_file task + ddr_data_init 序列化

### 8.4 仿真环境

- 仿真器：Vivado XSim（行为级仿真）
- 自动化工具：Vivado Orchestrator（Python 驱动，替代 `vivado_do.tcl`）
  - 会话隔离并行：不同任务可同时运行独立 Vivado 进程
  - 分层哈希增量刷新：RTL/TB/COE/FPGA 四层独立检测，仅 COE 变更时秒级刷新
  - 批处理模式：`-batch "isa_*"` 一条命令并行仿真多任务
  - 配置驱动 IP 生成：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL
- SoC 级仿真：testbench 实例化 `system_top`（而非 `core_top` + `ahb_lite_bus`），通过 `tb_soc_includes.svh` 共享框架
- DDR3 仿真模式：`SIMU_USE_DDR=0`（SRAM 模型，快速）或 `SIMU_USE_DDR=1`（DDR3 模型，验证通路）
- 新增 `soc_config.vh` 控制仿真行为（SIMU_USE_PLL / SIMU_USE_DDR）
- 程序加载：`$readmemh` 在 elaboration 阶段将 hex 文件加载至 ROM BRAM IP
- hex/coe 文件由 `tools/rv2coe.py` 从 RISC-V 汇编源码编译生成（`--base-addr 0x80000000`）
- BRAM 行为模型：0-cycle 读延迟，不精确模拟碰撞行为

### 8.5 已知限制

- **BRAM 读延迟**：仿真中 BRAM 行为模型为组合输出（0-cycle），硬件中为寄存输出（1-cycle），仿真通过不代表硬件时序正确。Cache/TLB 控制器已新增 S_TAG_READ 等状态处理 BRAM 延迟
- **SRAM 地址空间**：SRAM 仿真模式下 `axi_wrap_ram` 容量由 BRAM 配置决定，DDR3 模式下地址范围 `0x8000_0000` 起始
- **Cache 容量**：ICache/DCache 各 1KB（8 组 × 4 路 × 32 字节），大工作集程序可能频繁缺失
- **TLB 容量**：4 路 × 4 组 = 16 项，大工作集或频繁上下文切换可能 TLB 抖动
- **SRAM 字节写**：SRAM 仿真模型（axi_wrap_ram）支持 AXI4 字节写（wstrb），DDR3 通过 MIG 管理
- **FMA 未实现**：FMADD.S / FMSUB.S / FNMSUB.S / FNMADD.S 四条融合乘加指令未实现（R4 格式译码复杂，硬件面积大）
- **D 扩展未实现**：双精度浮点暂不支持，XLEN=32 时 D 扩展需 FLEN=64（NaN-boxing、64-bit 浮点寄存器）
- **f0 硬连线零**：RISC-V 规范不要求 f0=0（与 x0 不同），当前实现 f0 恒为 0 为设计选择
- **mstatus.FS 未强制**：FS=Off 时浮点指令未触发异常，为简化设计
- **CPU 重复 AXI 事务 bug**：每条 `lw`/`sw` 指令触发两次 AXI4-Lite 总线事务（间隔约 15 周期）。对普通内存无影响（读无副作用），对有副作用的寄存器（如 UART RXDATA）需 RTL workaround（STATUS-read auto-arm 机制）。根本修复需排查 CPU 总线桥接逻辑

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
| `dev/rtl/core/` | `cpu_bus_bridge.sv` | AXI4 总线桥接（MMIO + INCR8 突发，AW/W/B/AR/R 五通道） |
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
| `dev/rtl/FPU/` | `fpu_regfile.sv` | 浮点寄存器堆（32×32-bit，f0 硬连线零） |
| `dev/rtl/FPU/` | `fpu_unit.sv` | FPU 顶层（握手协议 + 结果选择） |
| `dev/rtl/FPU/` | `fpu_adder.sv` | 浮点加法器（FADD.S / FSUB.S） |
| `dev/rtl/FPU/` | `fpu_multiplier.sv` | 浮点乘法器（FMUL.S） |
| `dev/rtl/FPU/` | `fpu_divider.sv` | 浮点除法器（FDIV.S，非恢复余数） |
| `dev/rtl/FPU/` | `fpu_sqrt.sv` | 浮点平方根（FSQRT.S，非恢复余数法） |
| `dev/rtl/FPU/` | `fpu_compare.sv` | 浮点比较器（FEQ.S / FLT.S / FLE.S） |
| `dev/rtl/FPU/` | `fpu_minmax.sv` | 浮点最值（FMIN.S / FMAX.S） |
| `dev/rtl/FPU/` | `fpu_classify.sv` | 浮点分类（FCLASS.S） |
| `dev/rtl/FPU/` | `fpu_sign_inject.sv` | 符号注入（FSGNJ.S / FSGNJN.S / FSGNJX.S） |
| `dev/rtl/FPU/` | `fpu_cvt.sv` | 浮点↔整数转换（FCVT.W.S / FCVT.S.W / FCVT.WU.S / FCVT.S.WU） |
| `dev/rtl/FPU/` | `fpu_round.sv` | 舍入模式逻辑（RNE / RTZ / RDN / RUP / RMM，27-bit 尾数） |
| `dev/rtl/FPU/` | `fpu_special.sv` | NaN/Inf/零/次正规数检测与特殊处理 |
| `dev/rtl/` | `axi4_def.svh` | AXI4 常量定义（替代 ahb_def.svh） |
| `dev/rtl/` | `soc_config.vh` | SoC 配置宏（SIMU_USE_PLL / SIMU_USE_DDR） |
| `dev/rtl/` | `clk_wiz_0_passthrough.sv` | Clock Wizard 直通（仿真用） |
| `dev/rtl/common/` | `reset_sync.sv` | 复位同步器（异步断言，同步释放） |
| `dev/rtl/core/` | `core_bus_types.svh` | 流水线总线结构体定义（exe_mem_bus_t / wb_bus_t） |
| `dev/rtl/axi/` | `axi4lite_bootrom.sv` | AXI4-Lite Boot ROM 从设备 |
| `dev/rtl/axi/` | `axi4lite_clint.sv` | AXI4-Lite CLINT 从设备 |
| `dev/rtl/axi/` | `axi4lite_default_slave.sv` | AXI4-Lite Default Slave（DECERR） |
| `dev/rtl/axi/` | `axi4lite_plic.sv` | AXI4-Lite PLIC 从设备 |
| `dev/rtl/axi/` | `axi4lite_sys_status.sv` | AXI4-Lite System Status 从设备 |
| `dev/rtl/AMBA/` | `Axi_CDC.v` | AXI4 时钟域穿越 |
| `dev/rtl/APB/` | `axi4lite_to_apb.sv` | AXI4-Lite → APB 桥 |
| `dev/rtl/ram_wrap/` | `axi_wrap_ram.sv` | AXI4 BRAM 仿真模型（SRAM 替代） |
| `dev/rtl/ram_wrap/` | `axi_wrap_ddr.sv` | AXI4 DDR3 包装器（MIG） |
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
| `icached` | 256-bit × 32，True Dual Port，Byte_Enable | ICache 数据存储 |
| `dcached` | 256-bit × 32，True Dual Port，Byte_Enable | DCache 数据存储 |
| `icachet` | 32-bit × 8，True Dual Port，Byte_Enable(Byte_Size=8) | ICache 标签存储 |
| `dcachet` | 36-bit × 8，True Dual Port，Byte_Enable(Byte_Size=9) | DCache 标签存储 |
| `tlb_flag` | 128-bit × 4，True Dual Port，Byte_Enable(Byte_Size=8) | TLB 标志存储 |
| `tlb_data` | 128-bit × 4，True Dual Port，Byte_Enable(Byte_Size=8) | TLB 数据存储 |

### 9.2 Testbench 文件

| 文件 | 说明 |
|------|------|
| `dev/tb/tb_soc_includes.svh` | 共享 testbench 框架（system_top 实例化 + DDR3 支持） |
| `dev/tb/tb_simple_cpu_top.sv` | 完整指令集测试 |
| `dev/tb/tb_simple_cpu_compute.sv` | 计算密集测试 |
| `dev/tb/tb_simple_cpu_trap.sv` | 异常/中断测试 |
| `dev/tb/tb_isa_alu.sv` | ALU ISA 测试 |
| `dev/tb/tb_isa_branch.sv` | 分支 ISA 测试 |
| `dev/tb/tb_isa_jump.sv` | 跳转 ISA 测试 |
| `dev/tb/tb_isa_memory.sv` | 访存 ISA 测试 |
| `dev/tb/tb_isa_upper_imm.sv` | 上位立即数 ISA 测试 |
| `dev/tb/tb_isa_m_ext.sv` | M 扩展 ISA 测试 |
| `dev/tb/tb_isa_csr.sv` | CSR ISA 测试 |
| `dev/tb/tb_isa_f_ext.sv` | F 扩展 ISA 测试（26 子测试） |
| `dev/tb/tb_isa_f_ext_special.sv` | F 扩展特殊值/舍入测试（24 子测试） |
| `dev/tb/tb_isa_template.sv` | ISA 测试模板 |
| `dev/tb/tb_exception_illegal_inst.sv` | 非法指令异常测试 |
| `dev/tb/tb_exception_ecall.sv` | ECALL 异常测试 |
| `dev/tb/tb_exception_ebreak.sv` | EBREAK 异常测试 |
| `dev/tb/tb_exception_access_fault.sv` | 访问错误异常测试 |
| `dev/tb/tb_exception_interrupt_basic.sv` | 基本中断测试 |
| `dev/tb/tb_exception_timer_irq.sv` | 定时器中断测试 |
| `dev/tb/tb_cache_icache_basic.sv` | ICache 基本测试 |
| `dev/tb/tb_cache_dcache_basic.sv` | DCache 基本测试 |
| `dev/tb/tb_cache_dcache_dirty.sv` | DCache 脏行测试 |
| `dev/tb/tb_cache_fencei.sv` | FENCE.I 测试 |
| `dev/tb/tb_cache_cache_mmu_interact.sv` | Cache/MMU 交互测试 |
| `dev/tb/tb_mmu_sv32_basic.sv` | Sv32 基本测试 |
| `dev/tb/tb_mmu_sv32_edge.sv` | Sv32 边界测试 |
| `dev/tb/tb_mmu_ptw_walk.sv` | PTW 漫游测试 |
| `dev/tb/tb_mmu_tlb_basic.sv` | TLB 基本测试 |
| `dev/tb/tb_mmu_tlb_flush.sv` | TLB 刷新测试 |
| `dev/tb/tb_mmu_tlb_asid.sv` | TLB ASID 测试 |
| `dev/tb/tb_mmu_tlb_megapage.sv` | TLB 大页测试 |
| `dev/tb/tb_mmu_tlb_replace.sv` | TLB 替换测试 |
| `dev/tb/tb_mmu_tlb_stress.sv` | TLB 压力测试 |
| `dev/tb/tb_mmu_permission.sv` | 页表权限测试 |
| `dev/tb/tb_mmu_page_fault.sv` | 页错误测试 |
| `dev/tb/tb_mmu_unified_mmu.sv` | 统一 MMU 测试 |
| `dev/tb/tb_privilege_csr_access_priv.sv` | CSR 特权访问测试 |
| `dev/tb/tb_privilege_delegation.sv` | 陷阱委托测试 |
| `dev/tb/tb_privilege_priv_transition.sv` | 特权级转换测试 |
| `dev/tb/tb_mmio_clint.sv` | CLINT MMIO 测试 |
| `dev/tb/tb_mmio_plic.sv` | PLIC MMIO 测试 |
| `dev/tb/tb_regression_reg_bare_no_miss.sv` | 回归：裸机无缺失 |
| `dev/tb/tb_regression_reg_mmio_ready.sv` | 回归：MMIO ready |
| `dev/tb/tb_regression_reg_pf_latch.sv` | 回归：页错误锁存 |
| `dev/tb/tb_regression_reg_ptw_fault_latch.sv` | 回归：PTW 错误锁存 |
| `dev/tb/tb_regression_reg_sfence_during_walk.sv` | 回归：漫游中 SFENCE |
| `dev/tb/tb_regression_reg_stale_paddr.sv` | 回归：过期物理地址 |
| `dev/tb/tb_regression_reg_tlb_fill_way.sv` | 回归：TLB 填充路 |
| `dev/tb/tb_ahb_bus.sv` | AXI4 总线功能测试 |
| `dev/tb/tb_apb_perips.sv` | APB 外设测试 |
| `dev/tb/tb_uart_hello.sv` | UART 输出测试 |
| `dev/tb/tb_uart_echo.sv` | UART 回环测试 |
| `dev/tb/tb_led_marquee.sv` | LED 跑马灯测试 |
| `dev/tb/tb_calculator.sv` | 浮点计算器应用测试（UART 交互） |
| `dev/tb/ALU/tb_non_restoring_divider.sv` | 除法器单元测试 |
| `dev/tb/ALU/tb_mu_unit.sv` | 乘除法单元测试 |
| `dev/tb/ALU/tb_alu_cpu_integration.sv` | ALU 集成测试 |
| `dev/tb/tb_fpu_adder.sv` | FPU 加法器单元测试（30 子测试） |
| `dev/tb/tb_fpu_multiplier.sv` | FPU 乘法器单元测试（13 子测试） |
| `dev/tb/tb_fpu_divider.sv` | FPU 除法器单元测试（12 子测试） |
| `dev/tb/tb_fpu_sqrt.sv` | FPU 平方根单元测试（22 子测试） |
| `dev/tb/tb_fpu_cvt.sv` | FPU 转换单元测试（20 子测试） |
| `dev/tb/tb_fpu_unit.sv` | FPU 顶层集成测试（24 子测试） |
| `dev/tb/run_ddr3_sim.tcl` | DDR3 仿真 TCL 脚本 |

### 9.3 程序源文件

| 目录 | 说明 |
|------|------|
| `dev/program_source/boot/` | Bootloader（DDR3 启动引导：sp 初始化 → MIG 等待 → DDR3 自检 → UART 接收程序镜像 → fence.i → 跳转执行） |
| `dev/program_source/app/` | 应用程序（calculator, led_marquee, uart_hello, uart_echo, ddr3_test） |
| `dev/program_source/test/isa/` | ISA 测试（alu, branch, jump, memory, upper_imm, m_ext, csr, f_ext, f_ext_special） |
| `dev/program_source/test/integration/` | 集成测试（cpu_full, cpu_compute, cpu_trap） |
| `dev/program_source/test/exception/` | 异常测试（illegal_inst, ecall, ebreak, access_fault, interrupt_basic, timer_irq） |
| `dev/program_source/test/cache/` | 缓存测试（icache_basic, dcache_basic, dcache_dirty, fencei, cache_mmu_interact） |
| `dev/program_source/test/mmu/` | MMU 测试（sv32_basic, sv32_edge, ptw_walk, tlb_*, permission, page_fault, unified_mmu） |
| `dev/program_source/test/privilege/` | 特权测试（csr_access_priv, delegation, priv_transition） |
| `dev/program_source/test/mmio/` | MMIO 测试（clint, plic） |
| `dev/program_source/test/regression/` | 回归测试（7 项回归用例） |
| `dev/program_source/framework/` | 测试框架代码 |
| `dev/program_source/lib/` | 公共库（sys.h 等） |

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
15. **INCR8 突发传输**：Cache Refill/Writeback 使用 AXI4 INCR8 突发，8 拍传输整行 256-bit 数据
16. **MMIO 旁路**：`vaddr[31]==0 || vaddr[30]==1` 直接走 AXI 总线，不经过缓存，保证外设访问强序（含 Boot ROM 0xFC000000）
17. **VIPT（Virtically-Indexed Physically-Tagged）**：Cache 使用虚拟地址的页内偏移位索引，物理地址标签比较，避免 MMU 翻译延迟
18. **BRAM-based 标签存储**：Tag 使用 BRAM IP（icachet/dcachet），byte-write enable 支持单路更新，S_TAG_READ 状态处理 1-cycle 读延迟
19. **BRAM-based TLB**：4 路×4 组组相联，tlb_flag/tlb_data 双 BRAM，双端口（i-side/d-side），Tree-PLRU 替换
20. **AXI4 + AXI4-Lite + APB 三级总线**：高速主存挂 AXI4，控制寄存器挂 AXI4-Lite，低速外设挂 APB，通过桥接互联
21. **AXI4 Master 接口**：cpu_bus_bridge 五通道 AW/W/B/AR/R，支持 INCR8 突发读/写
22. **AXI4-Lite 从设备**：PLIC/CLINT/BootROM/SysStatus/APB Bridge，手动地址译码 + 从设备多路复用
23. **AXI4 时钟域穿越**：Axi_CDC，cpu_clk(50MHz) → sys_clk(100MHz) 异步隔离
24. **三时钟域架构**：cpu_clk/sys_clk/ddr_clk_ref，reset_sync 复位同步
25. **DDR3 SDRAM 支持**：axi_wrap_ddr + MIG，可选 SRAM 行为模型（axi_wrap_ram）
26. **Boot ROM**：0xFC00_0000，32KB BRAM，CPU 复位起始地址，bootloader 跳转至 0x8000_0000
27. **System Status**：0x0400_0000，MIG 校准/MMCM/clk_wiz 状态只读
28. **AXI4-Lite Default Slave**：未映射地址返回 DECERR 响应，防止总线挂死
29. **总线桥优先级**：icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill，防止饿死与脏行堆积
30. **数据 MMU translate_en 门控**：mem_en 同步控制 Sv32 翻译使能，消除组合信号竞争
31. **配置驱动存储几何**：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL，IP 与 RTL 常量自动同步
32. **SoC 配置宏**：soc_config.vh，SIMU_USE_PLL / SIMU_USE_DDR 仿真模式选择
33. **流水线总线结构体**：core_bus_types.svh，替代手工位索引
34. **外设中断路由**：UART/SPI/GPIO 中断输出经 PLIC 路由至 CPU（src[2]=UART, src[3]=SPI, src[4]=GPIO）
35. **UART TX/RX FIFO**：各 16 字节同步 FIFO 缓冲，支持连续收发不丢数据
36. **UART 可配波特率**：BAUD 寄存器运行时设置分频系数，0 回退默认 115200
37. **UART RXDATA peek + STATUS-read auto-arm**：RXDATA 读取为 peek（不弹 FIFO），STATUS 读取自动武装下次 RXDATA 弹出，应对 CPU 重复 AXI 事务 bug
37. **GPIO 引脚变化中断**：逐引脚中断使能掩码 + 写 1 清除挂起状态
38. **SPI 传输完成中断**：CTRL[4] 中断使能，传输完成置挂起，写 STATUS 清除
39. **CLINT 可写 msip**：msip 寄存器（偏移 0x10）支持软件中断，符合 RISC-V CLINT 规范
40. **IEEE 754 单精度浮点**：22 条 F 扩展指令，5 种舍入模式（RNE/RTZ/RDN/RUP/RMM），fflags 异常标志累积
41. **FPU 多周期握手**：与 MU 单元统一握手协议（req_valid→fpu_ready→fpu_busy→result_valid→result_got），FSM 在 STATE_EXEC 内轮询
42. **FPU 子模块分工**：加法器（FSM 3-5 周期）、乘法器（组合 1-2 周期）、除法器/平方根（非恢复余数 ~27 周期）、比较/分类/最值/符号注入（组合单周期）、转换（FSM 2-3 周期）
43. **浮点寄存器堆**：32×32-bit（f0 硬连线零），双读单写 + 调试端口，参数化 FLEN 为 D 扩展预留
44. **F 扩展 CSR**：fflags(0x001) / frm(0x002) / fcsr(0x003)，fflags 软件/硬件写合并（OR 累积），mstatus.FS 域支持
45. **浮点计算器应用**：基于 UART IO 的递归下降表达式解析器，支持 +,-,*,/,(),sqrt(),neg()
46. **共享 testbench 框架**：tb_soc_includes.svh，SoC 级仿真 + DDR3 支持
47. **测试程序分类重组**：isa/exception/cache/mmu/privilege/mmio/regression/ 目录结构
48. **Boot ROM 启动流程**：CPU 复位 PC=0xFC000000 → bootloader（sp 初始化 + DDR3 自检 + UART 接收程序镜像 + fence.i + 跳转）→ 主程序执行
49. **系统集成应用验证通过**：LED 跑马灯、UART Echo、浮点计算器三个应用均成功上板运行，Bootloader 全链路仿真通过（2026-06-13）
50. **完整内存映射模型**：7 从设备地址译码 + APB 4 从设备子译码 + CLINT/PLIC/SysStatus/BootROM 寄存器级映射（见 §2.2）
