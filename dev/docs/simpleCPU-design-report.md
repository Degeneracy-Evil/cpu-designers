# SimpleCPU 设计报告

> 生成日期: 2026-06-30 | 项目路径: `dev/rtl/`

---

## 1. 项目概述

本项目实现了一个基于 RISC-V RV32IMAFDSU 指令集的多周期 CPU，采用五级流水线结构（取指-译码-执行-访存-回写），通过有限状态机（FSM）控制器协调各级运行。CPU 通过 AXI4 总线连接片上存储与外设，支持异常/中断陷阱处理、CSR 读写、A 扩展原子运算、M 扩展乘除法运算、F 扩展单精度浮点运算、D 扩展双精度浮点运算。

### 1.1 核心特性

| 特性 | 说明 |
|------|------|
| 指令集 | RV32IMAFDSU（整数 + 原子 + 乘除法 + 单精度浮点 + 双精度浮点 + S/U 特权） |
| 架构 | 多周期 FSM 控制，五级流水线数据通路 |
| 数据位宽 | 32-bit 整数 / 64-bit 浮点 |
| 特权模式 | M/S/U 三级特权模式，支持陷阱委托（medeleg/mideleg） |
| 地址空间 | 32-bit，Sv32 页表虚拟内存（MMU + TLB + PTW） |
| 存储架构 | 哈佛结构（icache / dcache 分离），4 路组相联，Tree-PLRU 替换，PIPT |
| 缓存策略 | 写回（write-back）+ 写分配（write-allocate），脏行驱逐写回主存 |
| 标签存储 | BRAM IP（icachet 144-bit×8 / dcachet 144-bit×8），19-bit tag 覆盖 128MB DDR3，配置驱动 |
| TLB 架构 | 4 路 × 4 组组相联（16 项），BRAM IP（tlb_flag 128-bit×4 / tlb_data 128-bit×4），Tree-PLRU 替换 |
| 总线接口 | AXI4 Master（cpu_bus_bridge），支持 INCR8 突发读/写；AXI4-Lite 从设备（PLIC/CLINT/BootROM/SysStatus/APB Bridge） |
| 中断/异常 | 支持 Trap 进入/返回（mret/sret）、CLINT 定时器中断、PLIC 外部中断 |
| 特权指令 | SRET、SFENCE.VMA 指令支持 |
| 乘法器 | Booth 编码，32 周期迭代 |
| 除法器 | 非恢复余数法，32 周期迭代 + 修正 |
| 加法器 | 超前进位加法器（CLA），16-bit 级联为 32-bit |
| 浮点单元 | IEEE 754 单精度+双精度，多周期握手协议，5 种舍入模式 |
| 浮点寄存器 | 32×64-bit（f0-f31），f0 正常可写寄存器 |
| D 扩展 | 双精度浮点（22 条非 FMA 指令），FLD/FSD 双事务加载/存储 |
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

**RV32F 单精度浮点扩展（22 条）：**

| 类别 | 指令 | 说明 |
|------|------|------|
| 基础算术 | `FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S` | IEEE 754 算术运算 |
| 平方根 | `FSQRT.S` | Newton-Raphson 迭代 |
| 融合乘加 | `FMADD.S`, `FMSUB.S`, `FNMSUB.S`, `FNMADD.S` | R4 格式融合乘加/乘减/负乘减/负乘加 |
| 加载/存储 | `FLW`, `FSW` | 浮点数据访存 |
| 转换 | `FCVT.W.S`, `FCVT.WU.S`, `FCVT.S.W`, `FCVT.S.WU` | 整数↔浮点互转 |
| 符号注入 | `FSGNJ.S`, `FSGNJN.S`, `FSGNJX.S` | 符号位操作（FMV.F.X / FNEG / FABS 伪指令基础） |
| 移动 | `FMV.X.W`, `FMV.W.X` | 整数↔浮点寄存器位模式传输 |
| 比较 | `FEQ.S`, `FLT.S`, `FLE.S` | 浮点比较（结果写整数寄存器） |
| 分类 | `FCLASS.S` | NaN/Inf/次正规数检测（10-bit 掩码写整数寄存器） |
| 最值 | `FMIN.S`, `FMAX.S` | 浮点最小/最大值 |

> 全部 22 条 F 扩展指令已实现（含 FMA 四条融合乘加指令）。5 种舍入模式（RNE/RTZ/RDN/RUP/RMM），fcsr/frm/fflags CSR，NaN-boxing（32-bit float in 64-bit register），IEEE 754 异常标志（NX/UF/OF/DZ/NV）。D 扩展已实现（22 条非 FMA 指令），XLEN=32 时 FLEN=64，浮点寄存器堆拓宽为 64-bit，F 结果写入时 NaN-box 为 `{32'hFFFFFFFF, result[31:0]}`。

**RV32D 双精度浮点扩展（22 条，不含 FMA）：**

| 类别 | 指令 | 说明 |
|------|------|------|
| 基础算术 | `FADD.D`, `FSUB.D`, `FMUL.D`, `FDIV.D` | IEEE 754 双精度算术运算 |
| 平方根 | `FSQRT.D` | 非恢复余数法迭代 |
| 加载/存储 | `FLD`, `FSD` | 双精度浮点数据访存（双事务：低字 + 高字） |
| 转换 | `FCVT.W.D`, `FCVT.WU.D`, `FCVT.D.W`, `FCVT.D.WU` | 整数↔双精度互转 |
| 精度互转 | `FCVT.S.D`, `FCVT.D.S` | 单精度↔双精度互转 |
| 符号注入 | `FSGNJ.D`, `FSGNJN.D`, `FSGNJX.D` | 双精度符号位操作 |
| 比较 | `FEQ.D`, `FLT.D`, `FLE.D` | 双精度比较（结果写整数寄存器） |
| 分类 | `FCLASS.D` | 双精度 NaN/Inf/次正规数检测（10-bit 掩码） |
| 最值 | `FMIN.D`, `FMAX.D` | 双精度最小/最大值 |

> D 扩展采用独立的 D 专用子模块（非参数化 F 模块），F 子模块保持不变。D 操作直接读取 64-bit 寄存器值（不做 NaN-box 检查）。D-FMA（FMADD.D/FMSUB.D/FNMSUB.D/FNMADD.D）暂不实现。FMV.X.D/FMV.D.X 需要 XLEN≥64，不实现。

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
│   ├── fpu_regfile       ← 32×64bit 浮点寄存器堆（f0 正常可写，NaN-boxing）
│   ├── cpu_trap_csr      ← 陷阱/CSR 子系统
│   ├── icache_ctrl       ← 指令缓存控制器（4路组相联，PIPT）
│   ├── dcache_ctrl       ← 数据缓存控制器（4路组相联，写回+写分配，PIPT）
│   ├── MMU                ← Sv32 统一实例（双 i/d 接口，共享 TLB + PTW 页表漫游）
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
│   │       ├── UART (ns16550a) ← ns16550a 标准串口，16-byte TX/RX FIFO，中断（o_irq→PLIC src[2]），APB4 封装
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
├── fpu_fma        ← 浮点融合乘加（FMADD.S / FMSUB.S / FNMSUB.S / FNMADD.S），R4 格式
├── fpu_compare    ← 浮点比较器（FEQ.S / FLT.S / FLE.S），组合逻辑
├── fpu_minmax     ← 浮点最值（FMIN.S / FMAX.S），组合逻辑
├── fpu_classify   ← 浮点分类（FCLASS.S），组合逻辑
├── fpu_sign_inject← 符号注入（FSGNJ.S / FSGNJN.S / FSGNJX.S），组合逻辑
├── fpu_cvt        ← 浮点转换（FCVT.W.S / FCVT.S.W / FCVT.WU.S / FCVT.S.WU），FSM
├── fpu_round      ← 舍入模式逻辑（RNE / RTZ / RDN / RUP / RMM），27-bit 尾数舍入
├── fpu_special    ← NaN/Inf/零/次正规数检测与特殊处理
├── fpu_adder_d      ← 双精度加法器（FADD.D / FSUB.D）
├── fpu_multiplier_d ← 双精度乘法器（FMUL.D）
├── fpu_divider_d    ← 双精度除法器（FDIV.D）
├── fpu_sqrt_d       ← 双精度平方根（FSQRT.D）
├── fpu_cvt_d        ← 双精度转换（FCVT.W.D/FCVT.WU.D/FCVT.D.W/FCVT.D.WU/FCVT.S.D/FCVT.D.S）
├── fpu_compare_d    ← 双精度比较（FEQ.D / FLT.D / FLE.D）
├── fpu_minmax_d     ← 双精度最值（FMIN.D / FMAX.D）
├── fpu_classify_d   ← 双精度分类（FCLASS.D）
├── fpu_sign_inject_d← 双精度符号注入（FSGNJ.D / FSGNJN.D / FSGNJX.D）
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

**Cache/MMIO 判定规则**：`paddr[31]==0 || paddr[30]==1` 为 MMIO 区域（走 AXI 总线旁路缓存），其余为 Cacheable 区域（走 icache/dcache）。使用物理地址（paddr，TLB 翻译后）判断，而非虚拟地址（vaddr），避免 VA≠PA 时 MMIO 误命中缓存（Linux 适配关键修复）。

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

> **CLINT 标准地址布局**：寄存器布局遵循 SiFive CLINT 标准（msip @ 0x0000, mtimecmp @ 0x4000, mtime @ 0xBFF8），Linux 标准 sifive_clint 驱动可直接使用。mtime 由 sys_clk（100MHz）驱动，非 cpu_clk（50MHz）。

#### 2.2.4 PLIC 寄存器映射

基地址：`0x0C00_0000`，AXI4-Lite，支持 8 个中断源（NUM_SRC=8），双上下文（NUM_CTX=2）：

| 偏移 | 名称 | 读/写 | 说明 |
|------|------|-------|------|
| 0x000000 ~ 0x00001C | priority[0:7] | RW | 每源优先级（4 字节对齐，addr[7:2] 索引） |
| 0x001000 | pending | R | 中断挂起状态（32-bit，只读，硬件置位） |
| 0x002000 + N×0x80 | enable[ctx N] | RW | 中断使能掩码（32-bit，每源 1 位），N=0:M-mode, N=1:S-mode |
| 0x200000 + N×0x1000 | threshold[ctx N] | RW | 优先级阈值（仅优先级 > threshold 的中断可 claim） |
| 0x200004 + N×0x1000 | claim/complete[ctx N] | RW | 声明最高优先级中断（读返回 ID，写完成处理） |

> PLIC 中断路由：src[1]=Timer, src[2]=UART, src[3]=SPI, src[4]=GPIO。8 个中断源，优先级 0-7。Context 0: M-mode (o_eip[0]→mip[11])，Context 1: S-mode (o_eip[1]→mip[9])。SiFive 标准地址布局，Linux irq-sifive-plic.c 驱动可直接使用。

#### 2.2.5 APB 外设地址子译码

APB Bridge 基地址：`0x1000_0000`，4 个 APB 从设备按 `PADDR[15:14]` 译码：

| APB 从设备 | 判定条件 | 基地址 | 地址空间 | 说明 |
|-----------|----------|--------|----------|------|
| GPIO | `PADDR[15:14] == 2'b00` | `0x1000_0000` | `0x1000_0000 ~ 0x1000_3FFF` | 16-bit 双向 IO |
| Timer | `PADDR[15:14] == 2'b01` | `0x1000_4000` | `0x1000_4000 ~ 0x1000_7FFF` | 32-bit 定时器 |
| UART | `PADDR[15:14] == 2'b10` | `0x1000_8000` | `0x1000_8000 ~ 0x1000_BFFF` | ns16550a 标准串口 |
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

**UART 寄存器映射**（基址 `0x1000_8000`，ns16550a 标准）：

文件：`dev/rtl/APB/perips/uart16550/uart_16550a.sv`，通过 APB4 接口封装在 `apb_perips.sv` 中。

| 偏移 | 名称 | 说明 |
|------|------|------|
| 0x00 | THR/RBR/IER | 发送保持/接收缓冲/中断使能（DLAB=0 时 THR/RBR，DLAB=1 时 DLL） |
| 0x01 | IER/FCR | 中断使能/FIFO 控制（DLAB=0 时 IER，DLAB=1 时 DLM） |
| 0x02 | ISR/LCR | 中断状态/线控制 |
| 0x03 | LCR/MCR | 线控制/Modem 控制 |
| 0x04 | MCR/LSR | Modem 控制/线状态 |
| 0x05 | LSR/MSR | 线状态/Modem 状态 |
| 0x06 | MSR/SPR | Modem 状态/Scratch |
| 0x07 | SPR/SCR | Scratch/Divisor Latch |

> ns16550a 特性：16-byte TX/RX FIFO，可配置波特率（Divisor Latch），Modem 控制信号（CTS/RTS/DSR/DTR/DCD/RI），中断生成（THR 空/RX 数据/RX 超时/Modem 状态/线状态）。替代原自定义 UART，为 Linux 串口控制台提供标准兼容。

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

控制器采用 11 状态 FSM 驱动整个数据通路：

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

11 个状态：STATE_IDLE, STATE_IF, STATE_ID, STATE_EX, STATE_MEM, STATE_WB, STATE_MRET, STATE_SRET, STATE_ECALL, STATE_FENCEI, STATE_SFENCE_VMA。

各级使能信号由当前状态直接译码产生（`if_valid`, `id_valid`, `exe_valid`, `mem_valid`, `wb_valid`, `csr_valid`），确保每个时钟周期仅一级活跃。

### 3.2 取指级 (`cpu_fetch`)

- 输入：PC、指令数据（来自 icache 或 MMIO）
- 输出：`if_id_bus[95:0]` = `{pc_plus4, pc, inst}`
- 完成条件：`if_valid && inst_valid`
- PC 更新在 `core_top` 中统一管理

### 3.3 译码级 (`cpu_decode`)

**指令重组 (`op_regroup`)**：从 32-bit 指令中提取 opcode、funct3、funct7、rs1、rs2、rd 及五种立即数（I/S/B/U/J 型），均带符号扩展。

**指令识别**：通过 opcode + funct3 + funct7 组合译码，识别全部约 102 条指令（含 A 扩展 11 条 + M 扩展 8 条 + F 扩展 22 条 + D 扩展 22 条）。

**操作数选择**：

- `alu_src1`：AUIPC/JAL/分支使用 PC，其余使用 rs1
- `alu_src2`：LUI/AUIPC 使用 imm_u，JAL 使用 imm_j，JALR 使用 imm_i，分支使用 imm_b，立即数算术使用 imm_i，移位使用 shamt，Load 使用 imm_i，Store 使用 imm_s，FLW 使用 imm_i，FSW 使用 imm_s，其余使用 rs2

**浮点操作数选择**：

- 浮点计算指令（FADD/FSUB/FMUL/FDIV/FSQRT/FMADD/FMSUB/FNMSUB/FNMADD/FEQ/FLT/FLE/FMIN/FMAX/FSGNJ*/FCLASS 及 D 扩展对应指令）读取浮点寄存器 frs1/frs2（FMA 额外读取 frs3）
- 整数→浮点指令（FMV.W.X / FCVT.S.W / FCVT.S.WU / FCVT.D.W / FCVT.D.WU）读取整数寄存器 rs1，通过 `fpu_src_is_int` 标志在执行级 mux 选择
- 浮点→整数指令（FMV.X.W / FCVT.W.S / FCVT.WU.S / FCVT.W.D / FCVT.WU.D）结果写整数寄存器，通过 `fpu_rd_is_int` 标志路由

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
| `is_fld` | 1 | 当前指令为 FLD（D 扩展双精度加载） |
| `is_fsd` | 1 | 当前指令为 FSD（D 扩展双精度存储） |
| `fpu_funct` | 7 | 浮点操作码（46 种：F 0-23 + D 24-45；0=FADD ~ 19=FCVT.S.WU, 20=FMADD ~ 23=FNMADD, 24=FADD.D ~ 45=FSD） |
| `fpu_rm` | 3 | 舍入模式（来自 funct3，DYN=111 在执行级用 CSR frm 替换） |
| `fpu_rd_is_int` | 1 | 结果写整数寄存器（FEQ/FLT/FLE/FCLASS/FMV.X.W/FCVT.W.S/FCVT.WU.S） |
| `frs3_value` | 32 | FMA 第三操作数（R4 格式 rs3，用于 FMADD/FMSUB/FNMSUB/FNMADD） |

**浮点指令 opcode 识别**：

| opcode | 名称 | 指令 |
|--------|------|------|
| 0x07 (0000111) | LOAD-FP | FLW (funct3=010) / FLD (funct3=011) |
| 0x27 (0100111) | STORE-FP | FSW (funct3=010) / FSD (funct3=011) |
| 0x43 (1000011) | MADD-FP | FMADD.S |
| 0x47 (1000111) | MSUB-FP | FMSUB.S |
| 0x4B (1001011) | NMSUB-FP | FNMSUB.S |
| 0x4F (1001111) | NMADD-FP | FNMADD.S |
| 0x53 (1010011) | OP-FP | FADD.S/FSUB.S/FMUL.S/FDIV.S/FSQRT.S/FMIN.S/FMAX.S/FSGNJ*/FCVT/FEQ/FLT/FLE/FCLASS/FMV.X.W/FMV.W.X 及 D 扩展对应指令（FADD.D/FSUB.D/FMUL.D/FDIV.D/FSQRT.D/FMIN.D/FMAX.D/FSGNJ*.D/FCVT.*.D/FEQ.D/FLT.D/FLE.D/FCLASS.D） |

**非法指令检测**：无效指令编码、CSR 地址无效、写只读 CSR 均触发非法指令异常。

**ID/EX 总线**（334-bit）：`{pc_plus4, valid_inst, is_alu, is_load, is_store, is_jal_like, is_branch, use_fixed_wb, wb_we, rd, wb_fixed_data, mem_size, mem_unsigned, alu_control[15:0], is_mu, mu_funct3, alu_src1, alu_src2, rs1_value, rs2_value, branch_funct3, is_csr, is_ecall, is_ebreak, is_mret, csr_addr, csr_funct3, csr_uimm, pc, inst, is_fpu, is_flw, is_fsw, is_fld, is_fsd, fpu_funct[6:0], fpu_rm[2:0], fpu_rd_is_int, frs3_value[31:0]}`（含 FPU 控制信号、D 扩展 FLD/FSD 标志、舍入模式、rs3 字段用于 FMA R4 格式）

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

采用与 `mu_unit` 相同的多周期握手协议，内部使用 5 状态显式 FSM（MMU 风格状态枚举）控制运算流程：

```
F_IDLE → F_DISPATCH → F_WAIT → F_DONE → F_COMPLETE
```

- **F_IDLE**：等待 `req_valid`，锁存 fpu_funct/rm/src1/src2/src3
- **F_DISPATCH**：组合运算直接跳 F_DONE；时序运算置 start 脉冲跳 F_WAIT
- **F_WAIT**：轮询子模块 done 信号；超时看门狗（1000 周期）触发 `fpu_error=1` 强制完成
- **F_DONE**：锁存 result/fflags/rd_is_int，置 result_valid
- **F_COMPLETE**：保持 result_valid 直到 result_got（NBA 影子周期保护），然后回 F_IDLE
- Flush：从任意状态直接回 F_IDLE

- 握手协议：`req_valid → fpu_ready → fpu_busy → result_valid → result_got`
- 操作码 `fpu_funct[6:0]`：46 种浮点操作（F 0-23 + D 24-45；FADD=0 ~ FCVT.S.WU=19, FMADD=20 ~ FNMADD=23, FADD.D=24 ~ FSD=45）
- 舍入模式 `fpu_rm[2:0]`：来自指令 funct3，DYN(111) 在执行级用 CSR frm 替换
- 异常标志 `fflags[4:0]`：{NV, DZ, OF, UF, NX}，写回时 OR 累积至 CSR fflags
- `fpu_error`：超时看门狗输出，F_WAIT 状态下 1000 周期未收到 done 则置位，抑制写回（结果标记无效）
- 结果路由：`fpu_rd_is_int=1` → 写整数寄存器，否则 → 写浮点寄存器
- 数据位宽：src1/src2/src3/result 均为 64-bit；F 运算取低 32 位，结果 NaN-box 为 `{32'hFFFFFFFF, result[31:0]}`；D 运算使用完整 64 位
- `fpu_active` 信号与 `mu_busy` 互斥，确保同一时刻仅一个多周期运算单元活跃

**FPU 子模块算法**：

| 子模块 | 指令 | 算法 | 周期数 |
|--------|------|------|--------|
| `fpu_adder` | FADD.S / FSUB.S | FSM: 对齐→加/减→前导零计数→规格化→舍入 | 3-5 周期 |
| `fpu_multiplier` | FMUL.S | 组合 24×24 尾数乘 + 规格化 + 舍入 | 1-2 周期 |
| `fpu_fma` | FMADD.S / FMSUB.S / FNMSUB.S / FNMADD.S | R4 格式：先乘后加/减，含舍入中间步骤 | 3-5 周期 |
| `fpu_divider` | FDIV.S | 非恢复余数迭代（26-bit 商）+ 规格化 + 舍入 | ~27 周期 |
| `fpu_sqrt` | FSQRT.S | 非恢复余数法（28-bit 根）+ 规格化 + 舍入 | ~27 周期 |
| `fpu_cvt` | FCVT.* | FSM: COMPUTE→ROUND | 2-3 周期 |
| `fpu_compare` | FEQ/FLT/FLE | 组合逻辑（含 +0==-0 特殊处理） | 单周期 |
| `fpu_minmax` | FMIN/FMAX | 组合逻辑（NaN 输入返回 qNaN + NV） | 单周期 |
| `fpu_classify` | FCLASS | 组合逻辑（10-bit 掩码） | 单周期 |
| `fpu_sign_inject` | FSGNJ/FSGNJN/FSGNJX | 组合逻辑（符号位替换/取反/异或） | 单周期 |
| `fpu_round` | — | 27-bit 尾数舍入（G/R/S 位），5 种模式 | 组合逻辑 |
| `fpu_special` | — | NaN/Inf/零/次正规数检测，字段提取 | 组合逻辑 |

**FPU D 扩展子模块算法**：

| 子模块 | 指令 | 算法 | 周期数 |
|--------|------|------|--------|
| `fpu_adder_d` | FADD.D / FSUB.D | FSM: 6 states (align→add→norm→round)，56-bit 尾数 | 4-6 周期 |
| `fpu_multiplier_d` | FMUL.D | 组合 53×53 尾数乘 + 规格化 + 舍入 | 2-3 周期 |
| `fpu_divider_d` | FDIV.D | 非恢复余数迭代（55-bit 商）+ 规格化 + 舍入 | ~56 周期 |
| `fpu_sqrt_d` | FSQRT.D | 非恢复余数法（57-bit 根）+ 规格化 + 舍入 | ~57 周期 |
| `fpu_cvt_d` | FCVT.*.D / FCVT.D.* | FSM: IDLE→COMPUTE→DONE | 2-3 周期 |
| `fpu_compare_d` | FEQ.D/FLT.D/FLE.D | 组合逻辑 | 单周期 |
| `fpu_minmax_d` | FMIN.D/FMAX.D | 组合逻辑 | 单周期 |
| `fpu_classify_d` | FCLASS.D | 组合逻辑（10-bit 掩码） | 单周期 |
| `fpu_sign_inject_d` | FSGNJ.D/FSGNJN.D/FSGNJX.D | 组合逻辑 | 单周期 |

**JALR 对齐**：结果与 `0xFFFF_FFFE` 按位与，清除最低位。

**分支/跳转目标**：

- 分支：条件成立时目标 = ALU 结果（pc + imm_b）
- JAL：目标 = ALU 结果（pc + imm_j）
- JALR：目标 = ALU 结果 & ~1（rs1 + imm_i）

**指令对齐异常检测**：跳转目标 `[1:0] != 00` 时触发指令地址对齐异常（Exception Code = 0）。

**EX/MEM 总线**（216-bit）：`{pc_plus4, result_ok, is_jal_like, is_load, is_store, is_csr, wb_we, wb_rd, result_reg, mem_size, mem_unsigned, rs2_value, csr_rdata, pc, inst, is_fpu, is_flw, is_fsw, is_fld, is_fsd, fpu_rd_is_int, fpu_fflags[4:0]}`

### 3.5 访存级 (`cpu_mem`)

内部状态机（mem_state 4-bit）：

```
MEM_IDLE → MEM_READ  (Load)  → 等待 data_valid → MEM_IDLE
MEM_IDLE → MEM_WRITE (Store) → 等待 data_valid → MEM_IDLE
MEM_IDLE → MEM_IDLE   (非访存指令，直接完成)

// D 扩展 FLD/FSD 双事务（两个 32-bit 字拼合为 64-bit）
MEM_IDLE → MEM_FLD_LO  (FLD 读低字 addr)   → MEM_FLD_GAP → MEM_FLD_HI (读高字 addr+4) → MEM_IDLE
MEM_IDLE → MEM_FSD_LO  (FSD 写低字 addr)   → MEM_FSD_GAP → MEM_FSD_HI (写高字 addr+4) → MEM_IDLE
```

**FLD/FSD 双事务与 GAP 状态**：

D 扩展的 FLD/FSD 需要访问两个连续的 32-bit 字（addr 和 addr+4）拼合为 64-bit 浮点数据。由于两次访问地址不同，MMU 需要重新翻译第二个字的地址。GAP 状态（MEM_FLD_GAP / MEM_FSD_GAP）在两次访问之间脉冲 `mem_en=0` 一个周期，强制 MMU 重新翻译：

- **FLD**：MEM_FLD_LO 读取低字 → MEM_FLD_GAP（mem_en=0，触发 MMU 重翻译）→ MEM_FLD_HI 读取高字 → 拼合为 64-bit 结果
- **FSD**：MEM_FSD_LO 写入低字 → MEM_FSD_GAP（mem_en=0，触发 MMU 重翻译）→ MEM_FSD_HI 写入高字

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
- FLD/FSD 双精度访问 `addr[2:0] != 000` → 对齐异常（8 字节对齐）

**MEM/WB 总线**（177-bit）：`{pc_plus4, is_jal_like, is_csr, wb_we, wb_rd, wb_data, csr_rdata, pc, inst, is_fpu, is_flw, is_fsw, is_fld, is_fsd, fpu_rd_is_int, fpu_fflags[4:0], fp_wdata64[63:0]}`（含 D 扩展 FLD/FSD 标志及 64-bit 浮点加载数据）

### 3.6 回写级 (`cpu_wb`)

- 整数寄存器写使能：`wb_valid && wb_we && !is_fpu && !is_flw && !is_fld`（FLW/FLD 不写整数寄存器）
- 写数据选择：CSR 指令写回 CSR 读出值，其余写回 ALU/MU/FPU/Load 结果
- JAL/JALR 写回值：`pc + 4`（在 `core_top` 中通过 `wb_is_jal_like` 信号选择）
- 寄存器 x0 硬连线为 0（在 `cpu_regfile` 中实现）
- **浮点寄存器写使能**：`wb_valid && (is_fpu || is_flw || is_fld)`
- **浮点写数据（64-bit 数据通路）**：
  - F/D 计算指令：`fpu_result_64`（64-bit，F 结果已 NaN-box 为 `{32'hFFFFFFFF, result[31:0]}`，D 结果为完整 64 位）
  - FLD：`fp_wdata64`（64-bit，由 cpu_mem 双事务拼合）
  - FLW：`{32'hFFFFFFFF, wb_data[31:0]}`（NaN-box 32-bit 加载数据）
- **fflags 累积**：`wb_valid && (fpu_fflags != 0)` 时，OR 累积至 CSR fflags（`fflags_wen` 需 `wb_valid` 门控，防止残留总线数据误写）

### 3.7 寄存器堆 (`cpu_regfile`)

- 32 个 32-bit 整数寄存器
- x0 恒为 0（读返回 0，写忽略）
- 单写端口，双读端口
- 附加调试读端口（`dbg_raddr`/`dbg_rdata`）

### 3.8 浮点寄存器堆 (`fpu_regfile`)

- 32 个 64-bit 浮点寄存器（f0-f31），支持 D 扩展双精度存储
- f0 为正常可写寄存器（RISC-V 规范不要求 f0=0，与整数 x0 不同；复位初始化为 0 仅为确定性）
- 单写端口（64-bit），三读端口（64-bit，含 FMA rs3 第三读端口）
- 附加调试读端口（`dbg_faddr`/`dbg_fdata`，64-bit）
- NaN-boxing：F 单精度结果写入时高 32 位填充 `0xFFFFFFFF`，形成合法的 NaN-box；D 双精度结果写入完整 64 位

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
| S-mode 外部中断（SEIE & SEIP） | 0x8000_0009 | — |
| S-mode 软件中断（SSIE & SSIP） | 0x8000_0001 | — |
| S-mode 定时器中断（STIE & STIP） | 0x8000_0005 | — |

中断使能条件：`mstatus.MIE == 1` 且对应 `mie` 位为 1 且 `mip` 位为 1。

**M/S 中断优先级**：当 M-mode 和 S-mode 中断同时挂起时，M-mode 中断优先被响应。此前存在 S-mode 中断在 M-mode 中断挂起时仍被响应的缺陷，已修复：`cpu_clint.sv` 现先检查 M-mode 挂起，再检查 S-mode。

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
| 0x301 | misa | 否 | 硬连线 `0x40141129`（RV32IMAFDSU，A bit[0]=1，D bit[3]=1） |
| 0x302 | medeleg | 是 | 异常委托寄存器（委托码：0,2,3,6,7,8,9,11,12,13,15,19） |
| 0x303 | mideleg | 是 | 中断委托寄存器（委托位：MEIP[11], MTIP[7], MSIP[3]） |
| 0x304 | mie | 是 | MEIE/MTIE/MSIE/SEIE/STIE/SSIE |
| 0x305 | mtvec | 是 | M-mode Trap 向量基址 |
| 0x306 | mcounteren | 是 | 计数器使能寄存器（mcounteren[slice]=1 且 scounteren[slice]=1 时 U-mode 可读 cycle/time/instret） |
| 0x310 | mstatush | 否 | 硬连线 0 |
| 0x340 | mscratch | 是 | M-mode 临时寄存器 |
| 0x341 | mepc | 是 | M-mode 异常/中断返回 PC |
| 0x342 | mcause | 是 | M-mode 异常/中断原因 |
| 0x343 | mtval | 是 | M-mode 异常附加信息 |
| 0x344 | mip | 否 | MEIP[11]/SEIP[9]/MTIP[7]/STIP[5]/MSIP[3]/SSIP[1]（硬件写入；sip[5] STIP 可由 S-mode 软件写入注入定时器中断） |
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

> **PMP 说明**：pmpcfg0–pmpcfg3（0x3A0–0x3A3）和 pmpaddr0–pmpaddr15（0x3B0–0x3BF）共 20 个 CSR 已实现读写存储，但硬件强制执行（地址匹配 + 权限检查）未实现。Linux 可在无 PMP 强制执行下启动，此功能延后实现。

> **time/timeh 说明**：`core_top.sv` 将 CLINT mtime 直接路由至 CSR 读路径，U-mode 通过 time(0xC01)/timeh(0xC81) 读取定时器值（需 mcounteren[1]=1 且 scounteren[1]=1）。

**S-mode CSR：**

| CSR 地址 | 名称 | 可写 | 说明 |
|----------|------|------|------|
| 0x100 | sstatus | 是 | mstatus 的 S-mode 视图（SIE/SPIE/SPP/UXS/FS/XS/SD） |
| 0x104 | sie | 是 | SEIE/STIE/SSIE |
| 0x105 | stvec | 是 | S-mode Trap 向量基址 |
| 0x106 | scounteren | 是 | S-mode 计数器使能寄存器（与 mcounteren 联合控制 U-mode 计数器访问） |
| 0x140 | sscratch | 是 | S-mode 临时寄存器 |
| 0x141 | sepc | 是 | S-mode 异常/中断返回 PC |
| 0x142 | scause | 是 | S-mode 异常/中断原因 |
| 0x143 | stval | 是 | S-mode 异常附加信息 |
| 0x144 | sip | 否 | SEIP[9]/STIP[5]/SSIP[1]（STIP[5] 可由 S-mode 软件写入注入定时器中断） |
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
| 标签位 | 19 | tag = addr[26:8] |
| 字偏移 | 3 位 | word_off = addr[4:2]，每行 8 字（32 字节） |
| 行大小 | 256-bit（8×32-bit） | 一次 INCR8 突发填充 |
| 总容量 | 8 组 × 4 路 × 32 字节 = 1KB | ICache 与 DCache 各 1KB |

地址分解：`| tag[26:8] | set[7:5] | word[4:2] | byte[1:0] |`（19-bit tag 覆盖 128MB DDR3 地址空间 `0x8000_0000~0x87FF_FFFF`）

> **注意**：标签位 19 和 7 的差异说明：实际 RTL 中 `ICACHE_TAG_WIDTH` / `DCACHE_TAG_WIDTH` = 19，`ICACHE_TAG_HI` / `DCACHE_TAG_HI` = 26，`ICACHE_TAG_LO` / `DCACHE_TAG_LO` = 8。报告早期版本误写为 7 位 tag（addr[14:8]），实际应为 19 位（addr[26:8]），其中 addr[29:27] 在 AXI 地址中强制为零，addr[31:30] 用于 Cacheable/MMIO 判定。

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

| 缓存 | 标签 BRAM | BRAM 配置 | 每路标签格式 | BRAM 字内容 | 说明 |
|------|-----------|-----------|-------------|-------------|------|
| ICache | `icachet` | 144-bit × 8，True Dual Port，Byte_Enable，Byte_Size=36 | `{V(1), tag[18:0]}` = 20-bit | `{Way3[35:0]×4路打包}` = 144-bit（每路 36-bit，含 16-bit 填充） | 无脏位（指令缓存只读） |
| DCache | `dcachet` | 144-bit × 8，True Dual Port，Byte_Enable，Byte_Size=36 | `{V(1), D(1), tag[18:0]}` = 21-bit | `{Way3[35:0]×4路打包}` = 144-bit（每路 36-bit，含 15-bit 填充） | dirty 位标识写回需求 |

- BRAM 地址 = set_idx（3-bit），每个地址包含一组 4 路标签
- ICache 标签 BRAM 字：`{Way3[35:0], Way2[35:0], Way1[35:0], Way0[35:0]}` = 144-bit（每路 36-bit，含 16-bit 填充 + 20-bit 标签项）
- DCache 标签 BRAM 字：`{Way3[35:0], Way2[35:0], Way1[35:0], Way0[35:0]}` = 144-bit（每路 36-bit，含 15-bit 填充 + 21-bit 标签项）
- Port A：CPU 读（S_IDLE 使能，S_TAG_READ 出结果）
- Port B：Refill 写 / Dirty 更新 / Invalidate 写
- 命中判定：`valid && (tag == paddr[26:8])`，4 路并行，BRAM 读延迟 1 周期
- Byte-write enable 支持单路标签更新（Refill/Dirty 置位时仅写目标路）

### 5.4 数据存储（BRAM IP）

| BRAM | 配置 | 端口 A | 端口 B |
|------|------|--------|--------|
| icached | 256-bit × 32，True Dual Port，WRITE_FIRST，Byte_Enable | CPU 读 | Refill 写 |
| dcached | 256-bit × 32，True Dual Port，WRITE_FIRST，Byte_Enable | CPU 读/写 | Refill 写 / Victim 读 |
| icachet | 144-bit × 8，True Dual Port，Byte_Enable，Byte_Size=36 | CPU 读 | Refill 写 / Invalidate 写 |
| dcachet | 144-bit × 8，True Dual Port，Byte_Enable，Byte_Size=36 | CPU 读 / Flush 扫描 | Refill 写 / Dirty 更新 / Invalidate 写 |
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

ICache 采用 PIPT（Physically-Indexed Physically-Tagged）策略：set_idx 和 tag 均来自物理地址（paddr，TLB 翻译后）。此前使用 VIPT（虚拟地址索引 + 物理地址标签），已改为 PIPT 以简化设计并避免 VIPT 的别名问题。

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

- MMIO 旁路：`paddr[31]==0 || paddr[30]==1` 时直接发 AXI 请求，不经过缓存（使用物理地址判断，即 TLB 翻译后的 paddr；此前使用 vaddr 判断在 VA≠PA 时会导致 MMIO 误命中缓存，为 Linux 适配关键修复）
- 标签比较在 S_TAG_READ 完成（BRAM 1-cycle 延迟后），命中时进 S_READ 读数据 BRAM
- S_TAG_READ 不再等待 `mmu_ready`（ping-pong 等待已移除）：paddr 在 S_IDLE 已锁存，S_TAG_READ 可直接进行标签比较，无需二次等待 MMU
- 缺失时向 `cpu_bus_bridge` 发 INCR8 读突发请求，8 拍填充整行
- 数据 BRAM 读使能门控 `mmu_ready`，避免使用过时物理地址

### 5.6 数据缓存控制器 (`dcache_ctrl`)

DCache 同样采用 PIPT 策略，set_idx 和 tag 均来自物理地址（paddr，TLB 翻译后）。

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
- 内容由 `$readmemh` 在 elaboration 阶段加载（bootloader.hex），而非 COE 文件初始化 BRAM IP
- **原因**：Vivado 仿真中使用 COE 初始化 BRAM 时，BRAM 输出初始值为 X（未知态），X 传播到后续逻辑后会生成大量 X→0/X→1 的分辨事件（resolution event），导致事件风暴（event storm），仿真速度下降上千倍。`$readmemh` 在 Elaboration 阶段完成初始化，仿真开始时 BRAM 输出已为确定值，完全避免此问题。
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

**统一翻译 FSM（`MMU.sv`）**：

MMU 内部使用 11 状态统一翻译 FSM（替代早期双 i-side/d-side FSM），CPU 通过 `translate_req` 握手驱动，MMU 阻塞至 `translate_done`：

```
T_IDLE → T_LOOKUP → T_CHECK → T_DONE → T_COMPLETE → T_IDLE
                              → T_WALK → T_FILL → T_RELOOKUP → T_RECHECK → T_DONE
                              → T_FAULT → T_COMPLETE
T_* → T_FLUSH (sfence_vma)
```

| 状态 | 说明 |
|------|------|
| T_IDLE | 等待 translate_req，锁存 vaddr/satp/priv |
| T_LOOKUP | TLB BRAM 读请求（1 周期延迟） |
| T_CHECK | TLB 输出有效，判定 hit/miss/fault；bare 模式直接 T_DONE |
| T_WALK | TLB miss，PTW 页表漫游 |
| T_FILL | PTW 完成，写 TLB Port B（1 周期） |
| T_RELOOKUP | 重新读 TLB 确认 fill 提交 |
| T_RECHECK | 检查 re-lookup 结果 |
| T_DONE | 翻译成功，置 translate_done + translate_paddr |
| T_FAULT | 翻译失败，置 translate_done + translate_fault |
| T_COMPLETE | **保持 translate_done 为电平信号**，等待 translate_req 撤除后回 T_IDLE |
| T_FLUSH | sfence.vma 刷新 TLB，逐组写零 BRAM |

**T_COMPLETE 状态（关键简化）**：

- T_DONE/T_FAULT → T_COMPLETE（下一周期）→ 等待 `!translate_req` → T_IDLE
- `translate_done` 现为电平信号（在 T_COMPLETE 中保持高电平），而非早期的 1 周期脉冲
- 防止 `translate_req` 保持高电平时触发重复翻译
- 消除 T_DONE 与 T_COMPLETE 之间的 1 周期 gap，避免 dcache 数据 BRAM 使能被 mmu_ready 间隙抑制（store hit 数据丢失 / load hit 返回过期数据）
- 若 `translate_req` 保持高电平但 `translate_vaddr` 改变（如 FETCH→MEM 切换），则回 T_IDLE 重新翻译新地址

**A/D 位硬件管理**：

PTW 在页表漫游过程中自动管理访问位（A）和脏位（D）：

- 首次访问某页时，若 PTE.A=0，PTW 写回 PTE 并置 A=1
- 首次写入某页时，若 PTE.D=0，PTW 写回 PTE 并置 D=1
- 写回通过 PTW 总线请求完成，旁路 dcache 直接到 AXI→BRAM

**PTW-dcache 一致性维护**：

当 PTW 更新 PTE（置 A/D 位）时，会同时失效 dcache 中对应的缓存行，确保后续读操作看到更新后的 PTE。这修复了一致性缺陷：此前 PTW 修改 PTE 后，dcache 可能仍提供过期的 PTE 数据，导致页错误或权限判断错误。

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

执行 SFENCE.VMA 时触发 dcache 刷新 + TLB 刷新：
1. **dcache 刷新**：写回所有脏行（writeback dirty lines），然后失效所有缓存行（invalidate all lines）。实现：`core_top.sv` 检测 sfence.vma，启动 dcache flush FSM（S_FLUSH_SCAN 逐组扫描，S_FLUSH_WB_RD/WB_SD 写回脏行，S_FLUSH_INVALIDATE 失效所有行）
2. **TLB 刷新**：刷新两个 TLB 的全部项（逐组写零 BRAM，S_FLUSH 状态机）

此前 sfence.vma 仅刷新 TLB；新增 dcache 刷新确保地址翻译一致性——修改页表后 dcache 中缓存的旧 PTE 数据不会干扰后续翻译。若指定 rs1（ASID）或 rs2（VPN），可选择性刷新，当前实现为全刷新。

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
| UART | `0x1000_8000` | ns16550a 标准串口，16-byte TX/RX FIFO，中断输出，APB4 封装 |
| SPI | `0x1000_C000` | 主模式 SPI 控制器，传输完成中断 |

#### 6.2.1 ns16550a UART

UART 外设已替换为 ns16550a 标准串口（`dev/rtl/APB/perips/uart16550/uart_16550a.sv`），通过 APB4 接口封装在 `apb_perips.sv` 中。ns16550a 提供 16-byte TX/RX FIFO、可配置波特率（Divisor Latch）、Modem 控制信号、标准中断生成，为 Linux 串口控制台提供标准兼容。原自定义 UART 的 STATUS-read auto-arm 机制不再需要。

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

> 更新时间: 2026-07-03 | 基于 SimpleOS 交互模式完成

| 应用 | 程序 | 验证方式 | 结果 | 说明 |
|------|------|----------|------|------|
| LED 跑马灯 | `led_marquee.hex` | 仿真 + 上板 | ✓ PASS | GPIO 输出 + CLINT MTIP 定时器驱动，16 项检查全通过 |
| UART Echo | `uart_echo.hex` | 仿真 + 上板 | ✓ PASS | UART 回环收发，testbench 内嵌 TX 引擎 + RX 解码器 |
| 浮点计算器 | `calculator.hex` | 仿真 + 上板 | ✓ PASS | UART IO 递归下降表达式解析，5 项算式全通过 |
| Bootloader 仿真 | `bootloader_full.hex` | 仿真 | ✓ PASS | sp 初始化 → MIG 等待 → DDR3 自检 → UART 接收镜像 → fence.i → 跳转执行，全链路通过 |
| SimpleOS | `os.hex` | 仿真 | ✓ PASS | M/S/U 三级特权转换 + Sv32 分页 + ecall 系统调用 + U-mode 浮点计算器，5/5 自检通过 + 交互模式 |

**里程碑**：项目已从"ISA 单元测试通过"进入"系统集成应用验证"阶段，三个应用均成功上板运行，bootloader 全链路仿真通过。SimpleOS 进一步验证了 M/S/U 特权级 + Sv32 分页 + 系统调用的全栈功能。

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
| `tb_isa_f_ext` | `f_ext.hex` | F 扩展 ISA 测试（含 FMA） | 30 PASS, 0 FAIL |
| `tb_isa_f_ext_special` | `f_ext_special.hex` | F 扩展特殊值/舍入测试 | 24 PASS, 0 FAIL |
| `tb_isa_d_smoke` | `d_smoke.hex` | D 扩展冒烟测试 | 2 PASS, 0 FAIL |
| `tb_isa_d_ext` | `d_ext.hex` | D 扩展 ISA 测试 | 51 PASS, 0 FAIL |
| `tb_isa_d_ext_special` | `d_ext_special.hex` | D 扩展特殊值测试 | 28 PASS, 0 FAIL |
| `tb_isa_f_f0_writable` | `f0_writable.hex` | f0 可写测试 | 5 PASS, 0 FAIL |
| `tb_fpu_fsm` | — | FPU FSM 边界测试 | 15 PASS |
| `tb_exception_illegal_inst` | `illegal_inst.hex` | 非法指令异常测试 | PASS ✅ |
| `tb_exception_ecall` | `ecall.hex` | ECALL 异常测试 | PASS ✅ |
| `tb_exception_ebreak` | `ebreak.hex` | EBREAK 异常测试 | PASS ✅ |
| `tb_exception_access_fault` | `access_fault.hex` | 访问错误异常测试 | PASS ✅ |
| `tb_exception_interrupt_basic` | `interrupt_basic.hex` | 基本中断测试 | PASS ✅ |
| `tb_exception_timer_irq` | `timer_irq.hex` | 定时器中断测试 | PASS ✅ |
| `tb_cache_icache_basic` | `icache_basic.hex` | ICache 基本功能测试 | PASS ✅ |
| `tb_cache_dcache_basic` | `dcache_basic.hex` | DCache 基本功能测试 | PASS ✅ |
| `tb_cache_dcache_dirty` | `dcache_dirty.hex` | DCache 脏行写回测试 | PASS ✅ |
| `tb_cache_fencei` | `fencei.hex` | FENCE.I 缓存一致性测试 | PASS ✅ |
| `tb_cache_cache_mmu_interact` | `cache_mmu_interact.hex` | Cache/MMU 交互测试 | PASS ✅ |
| `tb_mmu_sv32_basic` | `sv32_basic.hex` | Sv32 基本翻译测试 | PASS ✅ |
| `tb_mmu_sv32_edge` | `sv32_edge.hex` | Sv32 边界条件测试 | PASS ✅ |
| `tb_mmu_ptw_walk` | `ptw_walk.hex` | PTW 页表漫游测试 | PASS ✅ |
| `tb_mmu_tlb_basic` | `tlb_basic.hex` | TLB 基本功能测试 | PASS ✅ |
| `tb_mmu_tlb_flush` | `tlb_flush.hex` | TLB 刷新测试 | PASS ✅ |
| `tb_mmu_tlb_asid` | `tlb_asid.hex` | TLB ASID 感知测试 | PASS ✅ |
| `tb_mmu_tlb_megapage` | `tlb_megapage.hex` | TLB 大页匹配测试 | PASS ✅ |
| `tb_mmu_tlb_replace` | `tlb_replace.hex` | TLB 替换策略测试 | PASS ✅ |
| `tb_mmu_tlb_stress` | `tlb_stress.hex` | TLB 压力测试 | PASS ✅ |
| `tb_mmu_permission` | `permission.hex` | 页表权限检查测试 | PASS ✅ |
| `tb_mmu_page_fault` | `page_fault.hex` | 页错误测试 | PASS ✅ |
| `tb_mmu_unified_mmu` | `unified_mmu.hex` | 统一 MMU 测试 | PASS ✅ |
| `tb_privilege_csr_access_priv` | `csr_access_priv.hex` | CSR 特权访问测试 | PASS ✅ |
| `tb_privilege_delegation` | `delegation.hex` | 陷阱委托测试 | PASS ✅ |
| `tb_privilege_priv_transition` | `priv_transition.hex` | 特权级转换测试 | PASS ✅ |
| `tb_mmio_clint` | `clint.hex` | CLINT MMIO 测试 | PASS ✅ |
| `tb_mmio_plic` | `plic.hex` | PLIC MMIO 测试 | PASS ✅ |
| `tb_regression_reg_bare_no_miss` | `reg_bare_no_miss.hex` | 回归：裸机无缺失 | PASS ✅ |
| `tb_regression_reg_mmio_ready` | `reg_mmio_ready.hex` | 回归：MMIO ready 时序 | PASS ✅ |
| `tb_regression_reg_pf_latch` | `reg_pf_latch.hex` | 回归：页错误锁存 | PASS ✅ |
| `tb_regression_reg_ptw_fault_latch` | `reg_ptw_fault_latch.hex` | 回归：PTW 错误锁存 | PASS ✅ |
| `tb_regression_reg_sfence_during_walk` | `reg_sfence_during_walk.hex` | 回归：漫游中 SFENCE | PASS ✅ |
| `tb_regression_reg_stale_paddr` | `reg_stale_paddr.hex` | 回归：过期物理地址 | PASS ✅ |
| `tb_regression_reg_tlb_fill_way` | `reg_tlb_fill_way.hex` | 回归：TLB 填充路选择 | PASS ✅ |
| `tb_led_marquee` | `led_marquee.hex` | LED 跑马灯 + GPIO + CLINT MTIP 测试 | 16 PASS, 0 FAIL |
| `tb_uart_hello` | `uart_hello.hex` | UART 输出测试 | 12 PASS, 0 FAIL |
| `tb_uart_echo` | `uart_echo_test.hex` | UART 回环测试 | — |
| `tb_calculator` | `calculator.hex` | 浮点计算器应用测试 | 5 PASS, 0 FAIL |
| `tb_simple_cpu_top` | `os.hex` | SimpleOS M/S/U + Sv32 + syscall 仿真 | 5/5 PASS（交互模式） |
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
| `tb_fpu_adder_d` | — | D 加法器单元测试 | — |
| `tb_fpu_multiplier_d` | — | D 乘法器单元测试 | — |
| `tb_fpu_divider_d` | — | D 除法器单元测试 | — |
| `tb_fpu_sqrt_d` | — | D 平方根单元测试 | — |
| `tb_fpu_cvt_d` | — | D 转换单元测试 | — |
| `tb_fpu_compare_d` | — | D 比较/最值/分类/符号注入单元测试 | — |

### 8.3 验证方法

- 寄存器检查：通过 `rf_addr`/`rf_data` 端口直接读取整数寄存器堆，与期望值比对
- 浮点寄存器检查：通过 `dbg_faddr`/`dbg_fdata` 端口直接读取浮点寄存器堆，与期望 IEEE 754 位模式比对
- 存储器检查：BRAM IP 内部数组路径在仿真中不可直接访问，标记为 SKIP
- UART 检查：testbench 内嵌 UART RX 解码器，逐字符比对输出
- GPIO 检查：监测 GPIO 端口状态变化，验证 LED 跑马灯序列
- FPU 单元测试：每个 FPU 子模块独立 testbench，边界值（±0, ±Inf, qNaN, sNaN, 最大/最小正规数, 最大/最小次正规数）+ 随机浮点对对照
- FPU ISA 测试：自检程序（x28=pass, x30=first_fail_id），覆盖全部 22 条浮点指令（含 FMA 四条融合乘加）+ 特殊值 + 5 种舍入模式
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
- **PMP 硬件强制未实现**：pmpcfg0–pmpcfg3 和 pmpaddr0–pmpaddr15 共 20 个 CSR 已实现读写存储，但硬件地址匹配与权限检查未实现。Linux 可在无 PMP 强制下启动
- **CLINT 标准地址布局**：寄存器布局遵循 SiFive CLINT 标准（msip @ 0x0000, mtimecmp_lo @ 0x4000, mtimecmp_hi @ 0x4004, mtime_lo @ 0xBFF8, mtime_hi @ 0xBFFC），addr[15:0] 译码。Linux 标准 sifive_clint 驱动可直接使用
- **分支预测**：无分支预测（始终 not-taken），JAL/JALR 静态预测
- **D-FMA 未实现**：D 扩展的融合乘加指令（FMADD.D/FMSUB.D/FNMSUB.D/FNMADD.D）暂不实现，仅实现 22 条非 FMA 双精度指令
- **FMV.X.D/FMV.D.X 未实现**：双精度浮点寄存器与整数寄存器间的位模式传输指令需要 XLEN≥64，RV32 下不实现
- **mstatus.FS 未强制**：FS=Off 时浮点指令未触发异常，为简化设计
- **CPU 重复 AXI 事务 bug**：每条 `lw`/`sw` 指令触发两次 AXI4-Lite 总线事务（间隔约 15 周期）。对普通内存无影响（读无副作用），对有副作用的寄存器需 RTL workaround。根本修复需排查 CPU 总线桥接逻辑

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
| `dev/rtl/core/` | `icache_ctrl.sv` | 指令缓存控制器（4路组相联，PIPT，Tree-PLRU） |
| `dev/rtl/core/` | `dcache_ctrl.sv` | 数据缓存控制器（4路组相联，写回+写分配，PIPT） |
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
| `dev/rtl/FPU/` | `fpu_regfile.sv` | 浮点寄存器堆（32×64-bit，f0 正常可写，NaN-boxing） |
| `dev/rtl/FPU/` | `fpu_unit.sv` | FPU 顶层（握手协议 + 结果选择） |
| `dev/rtl/FPU/` | `fpu_adder.sv` | 浮点加法器（FADD.S / FSUB.S） |
| `dev/rtl/FPU/` | `fpu_multiplier.sv` | 浮点乘法器（FMUL.S） |
| `dev/rtl/FPU/` | `fpu_divider.sv` | 浮点除法器（FDIV.S，非恢复余数） |
| `dev/rtl/FPU/` | `fpu_sqrt.sv` | 浮点平方根（FSQRT.S，非恢复余数法） |
| `dev/rtl/FPU/` | `fpu_fma.sv` | 浮点融合乘加（FMADD.S / FMSUB.S / FNMSUB.S / FNMADD.S，R4 格式） |
| `dev/rtl/FPU/` | `fpu_compare.sv` | 浮点比较器（FEQ.S / FLT.S / FLE.S） |
| `dev/rtl/FPU/` | `fpu_minmax.sv` | 浮点最值（FMIN.S / FMAX.S） |
| `dev/rtl/FPU/` | `fpu_classify.sv` | 浮点分类（FCLASS.S） |
| `dev/rtl/FPU/` | `fpu_sign_inject.sv` | 符号注入（FSGNJ.S / FSGNJN.S / FSGNJX.S） |
| `dev/rtl/FPU/` | `fpu_cvt.sv` | 浮点↔整数转换（FCVT.W.S / FCVT.S.W / FCVT.WU.S / FCVT.S.WU） |
| `dev/rtl/FPU/` | `fpu_round.sv` | 舍入模式逻辑（RNE / RTZ / RDN / RUP / RMM，27-bit 尾数） |
| `dev/rtl/FPU/` | `fpu_special.sv` | NaN/Inf/零/次正规数检测与特殊处理 |
| `dev/rtl/FPU/` | `fpu_adder_d.sv` | 双精度浮点加法器（FADD.D / FSUB.D） |
| `dev/rtl/FPU/` | `fpu_multiplier_d.sv` | 双精度浮点乘法器（FMUL.D） |
| `dev/rtl/FPU/` | `fpu_divider_d.sv` | 双精度浮点除法器（FDIV.D，非恢复余数） |
| `dev/rtl/FPU/` | `fpu_sqrt_d.sv` | 双精度浮点平方根（FSQRT.D，非恢复余数法） |
| `dev/rtl/FPU/` | `fpu_cvt_d.sv` | 双精度浮点转换（FCVT.W.D/FCVT.WU.D/FCVT.D.W/FCVT.D.WU/FCVT.S.D/FCVT.D.S） |
| `dev/rtl/FPU/` | `fpu_compare_d.sv` | 双精度浮点比较器（FEQ.D / FLT.D / FLE.D） |
| `dev/rtl/FPU/` | `fpu_minmax_d.sv` | 双精度浮点最值（FMIN.D / FMAX.D） |
| `dev/rtl/FPU/` | `fpu_classify_d.sv` | 双精度浮点分类（FCLASS.D） |
| `dev/rtl/FPU/` | `fpu_sign_inject_d.sv` | 双精度符号注入（FSGNJ.D / FSGNJN.D / FSGNJX.D） |
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
| `dev/rtl/APB/` | `apb_decoder.sv` | APB 地址译码 |
| `dev/rtl/APB/perips/` | `apb_perips.sv` | 外设顶层 |
| `dev/rtl/APB/perips/` | `gpio.sv` | GPIO（16-bit 双向 IO，引脚变化中断） |
| `dev/rtl/APB/perips/uart16550/` | `uart_16550a.sv` | ns16550a 标准串口（16-byte TX/RX FIFO，APB4 封装） |
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
| `dev/tb/tb_isa_f_ext.sv` | F 扩展 ISA 测试（30 子测试） |
| `dev/tb/tb_isa_f_ext_special.sv` | F 扩展特殊值/舍入测试（24 子测试） |
| `dev/tb/tb_isa_d_smoke.sv` | D 扩展冒烟测试（2 子测试） |
| `dev/tb/tb_isa_d_ext.sv` | D 扩展 ISA 测试（51 子测试） |
| `dev/tb/tb_isa_d_ext_special.sv` | D 扩展特殊值测试（28 子测试） |
| `dev/tb/tb_isa_f_f0_writable.sv` | f0 可写测试（5 子测试） |
| `dev/tb/tb_fpu_fsm.sv` | FPU FSM 边界测试（15 子测试） |
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
| `dev/tb/tb_fpu_adder_d.sv` | D 加法器单元测试 |
| `dev/tb/tb_fpu_multiplier_d.sv` | D 乘法器单元测试 |
| `dev/tb/tb_fpu_divider_d.sv` | D 除法器单元测试 |
| `dev/tb/tb_fpu_sqrt_d.sv` | D 平方根单元测试 |
| `dev/tb/tb_fpu_cvt_d.sv` | D 转换单元测试 |
| `dev/tb/tb_fpu_compare_d.sv` | D 比较/最值/分类/符号注入单元测试 |
| `dev/tb/run_ddr3_sim.tcl` | DDR3 仿真 TCL 脚本 |

### 9.3 程序源文件

| 目录 | 说明 |
|------|------|
| `dev/program_source/boot/` | Bootloader（DDR3 启动引导：sp 初始化 → MIG 等待 → DDR3 自检 → UART 接收程序镜像 → fence.i → 跳转执行） |
| `dev/program_source/app/` | 应用程序（calculator, led_marquee, uart_hello, uart_echo, ddr3_test） |
| `dev/os/` | SimpleOS 操作系统（M/S/U 特权级 + Sv32 分页 + ecall 系统调用 + U-mode 交互式浮点计算器） |
| `dev/program_source/test/isa/` | ISA 测试（alu, branch, jump, memory, upper_imm, m_ext, csr, f_ext, f_ext_special, d_smoke, d_ext, d_ext_special, f0_writable） |
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
7. **完整陷阱处理**：支持 11 种异常 + 6 种中断（M/S-mode 各 3 种），符合 RISC-V 特权规范
8. **M/S/U 三级特权模式**：支持陷阱委托（medeleg/mideleg），S-mode 独立陷阱向量与 CSR
9. **Sv32 二级页表虚拟内存**：硬件页表漫游（PTW），16 项 4 路×4 组组相联 TLB，ASID 感知
10. **SRET/SFENCE.VMA/fence.i 指令**：S-mode 陷阱返回、TLB+dcache 刷新、icache 失效 + dcache 写回
11. **硬件管理 A/D 位**：PTW 自动写回 PTE 的访问位和脏位
12. **PTW-dcache 一致性**：PTW 更新 PTE 后失效 dcache 对应行，确保后续读看到更新 PTE
13. **4 路组相联缓存**：ICache/DCache 各 1KB（8 组 × 4 路 × 32B 行），BRAM 标签存储
14. **Tree-PLRU 替换**：3-bit 状态编码，无效路优先，近似 LRU 替换策略（Cache 和 TLB 均使用）
15. **写回 + 写分配**：Store 命中仅写 BRAM + 置 dirty，缺失先 Refill 再合并写入，脏行驱逐写回主存
16. **INCR8 突发传输**：Cache Refill/Writeback 使用 AXI4 INCR8 突发，8 拍传输整行 256-bit 数据
17. **MMIO 旁路**：`paddr[31]==0 || paddr[30]==1` 直接走 AXI 总线，不经过缓存，使用物理地址判断（Linux 适配修复：VA≠PA 时 vaddr 判断导致 MMIO 误命中缓存）
18. **PIPT（Physically-Indexed Physically-Tagged）**：Cache 使用物理地址索引和标签比较（set_idx 和 tag 均来自 paddr），避免 VIPT 的别名问题，简化设计
19. **BRAM-based 标签存储**：Tag 使用 BRAM IP（icachet/dcachet），byte-write enable 支持单路更新，S_TAG_READ 状态处理 1-cycle 读延迟
20. **BRAM-based TLB**：4 路×4 组组相联，tlb_flag/tlb_data 双 BRAM，双端口（i-side/d-side），Tree-PLRU 替换
21. **AXI4 + AXI4-Lite + APB 三级总线**：高速主存挂 AXI4，控制寄存器挂 AXI4-Lite，低速外设挂 APB，通过桥接互联
22. **AXI4 Master 接口**：cpu_bus_bridge 五通道 AW/W/B/AR/R，支持 INCR8 突发读/写
23. **AXI4-Lite 从设备**：PLIC/CLINT/BootROM/SysStatus/APB Bridge，手动地址译码 + 从设备多路复用
24. **AXI4 时钟域穿越**：Axi_CDC，cpu_clk(50MHz) → sys_clk(100MHz) 异步隔离
25. **三时钟域架构**：cpu_clk/sys_clk/ddr_clk_ref，reset_sync 复位同步
26. **DDR3 SDRAM 支持**：axi_wrap_ddr + MIG，可选 SRAM 行为模型（axi_wrap_ram）
27. **Boot ROM**：0xFC00_0000，32KB BRAM，CPU 复位起始地址，bootloader 跳转至 0x8000_0000
28. **System Status**：0x0400_0000，MIG 校准/MMCM/clk_wiz 状态只读
29. **AXI4-Lite Default Slave**：未映射地址返回 DECERR 响应，防止总线挂死
30. **总线桥优先级**：icache_mmio > dcache_mmio > ptw_i > ptw_d > dcache_wb > icache_refill > dcache_refill，防止饿死与脏行堆积
31. **数据 MMU translate_en 门控**：mem_en 同步控制 Sv32 翻译使能，消除组合信号竞争
32. **配置驱动存储几何**：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL，IP 与 RTL 常量自动同步
33. **SoC 配置宏**：soc_config.vh，SIMU_USE_PLL / SIMU_USE_DDR 仿真模式选择
34. **流水线总线结构体**：core_bus_types.svh，替代手工位索引
35. **外设中断路由**：UART/SPI/GPIO 中断输出经 PLIC 路由至 CPU（src[2]=UART, src[3]=SPI, src[4]=GPIO）
36. **A 扩展原子指令**：LR.W/SC.W + 9 条 AMO（AMOADD/AMOAND/AMOOR/AMOXOR/AMOMAX/AMOMAXU/AMOMIN/AMOMINU/AMOSWAP），dcache 保留集 + read-modify-write 原子操作，支持 Linux SMP
37. **ns16550a 标准串口**：替代原自定义 UART，16-byte TX/RX FIFO，标准寄存器映射，APB4 封装，Linux 串口控制台兼容
38. **sfence.vma 含 dcache 刷新**：sfence.vma 触发 dcache 刷新（写回脏行 + 失效所有行）+ TLB 刷新，确保地址翻译一致性
39. **MMIO 判定使用 paddr**：MMIO 判断基于物理地址（TLB 翻译后），而非虚拟地址，修复 VA≠PA 时 MMIO 误命中缓存
40. **PMP CSR 存储**：pmpcfg0–pmpcfg3 + pmpaddr0–pmpaddr15 共 20 个 CSR 读写存储（硬件强制执行未实现）
41. **time/timeh CSR**：0xC01/0xC81 只读，镜像 CLINT mtime，U-mode 计数器别名（需 mcounteren+scounteren 使能）
42. **misa = 0x40141129**：RV32IMAFDSU，A bit[0]=1（原子扩展），D bit[3]=1（双精度浮点扩展），F bit[5]=1（单精度浮点扩展），S bit[18]=1，U bit[20]=1，M bit[12]=1
43. **GPIO 引脚变化中断**：逐引脚中断使能掩码 + 写 1 清除挂起状态
44. **SPI 传输完成中断**：CTRL[4] 中断使能，传输完成置挂起，写 STATUS 清除
45. **CLINT 可写 msip**：msip 寄存器（偏移 0x0000，SiFive 标准布局）支持软件中断，符合 RISC-V CLINT 规范
46. **IEEE 754 单精度+双精度浮点**：22 条 F 扩展指令（含 FMA 四条融合乘加）+ 22 条 D 扩展指令（不含 FMA），5 种舍入模式（RNE/RTZ/RDN/RUP/RMM），fflags 异常标志累积
47. **FPU 5 状态显式 FSM**：F_IDLE→F_DISPATCH→F_WAIT→F_DONE→F_COMPLETE，组合运算跳过 F_WAIT，F_COMPLETE 保持 result_valid 直到 result_got（NBA 影子周期保护），1000 周期超时看门狗（fpu_error）
48. **FPU 子模块分工**：F 加法器（FSM 3-5 周期）、乘法器（组合 1-2 周期）、FMA（融合乘加）、除法器/平方根（非恢复余数 ~27 周期）、比较/分类/最值/符号注入（组合单周期）、转换（FSM 2-3 周期）；D 加法器（4-6 周期）、D 乘法器（2-3 周期）、D 除法器（~56 周期）、D 平方根（~57 周期）、D 转换（2-3 周期）、D 比较/最值/分类/符号注入（组合单周期）
49. **浮点寄存器堆**：32×64-bit（f0 正常可写寄存器，RISC-V 规范合规），三读单写 + 调试端口，F 结果 NaN-box 为 `{32'hFFFFFFFF, result[31:0]}`
50. **F 扩展 CSR**：fflags(0x001) / frm(0x002) / fcsr(0x003)，fflags 软件/硬件写合并（OR 累积），mstatus.FS 域支持
51. **浮点计算器应用**：基于 UART IO 的递归下降表达式解析器，支持 +,-,*,/,(),sqrt(),neg()
52. **共享 testbench 框架**：tb_soc_includes.svh，SoC 级仿真 + DDR3 支持
53. **测试程序分类重组**：11 类（ISA/MMU/Cache/CSR/Interrupt/Exception/AMO/FPU/Pipeline/Peripheral/Linux-adj），48 个测试程序，329 个子测试
54. **Boot ROM 启动流程**：CPU 复位 PC=0xFC000000 → bootloader（sp 初始化 + DDR3 自检 + UART 接收程序镜像 + fence.i + 跳转）→ 主程序执行
55. **系统集成应用验证通过**：LED 跑马灯、UART Echo、浮点计算器三个应用均成功上板运行，Bootloader 全链路仿真通过（2026-06-16）
56. **完整内存映射模型**：7 从设备地址译码 + APB 4 从设备子译码 + CLINT/PLIC/SysStatus/BootROM 寄存器级映射（见 §2.2）
57. **Linux 适配修复**：11 项 Linux 启动适配 bug 修复（MMIO paddr 判断、PTW-dcache 一致性、sfence.vma dcache 刷新、M/S 中断优先级、sip STIP 可写、PMP CSR、time/timeh CSR 等），详见 `process/near-linux-bug-fix.md`
58. **特权返回/陷阱路径修复**（sub-issue ④⑤⑥⑦，2026-06-19）：
   - ④ **M-mode陷阱误委托**：`cpu_clint.sv` 的 `trap_to_s` 增加 `(priv_mode != PRIV_M)` 门控。Per RISC-V Priv Spec §3.1.10，M-mode 异常/中断不可委托到 S-mode，旧实现缺少此检查导致 OpenSBI trap handler 中的异常可能错误进入 S-mode，绕过 OpenSBI 直接交付内核，造成崩溃或无限重入
   - ⑤ **mideleg WARL掩码过宽**：`cpu_csr.sv` 的 mideleg_wmask 从 `0x0000_0AAA`（bits 1,3,5,7,9,11）改为 `0x0000_0222`（仅 bits 1,5,9 = SSI/STI/SEI）。M-mode 中断（MSI=3, MTI=7, MEI=11）不可委托，旧掩码允许写入这些位
   - ⑥ **mret特权违例检查缺失**：`cpu_decode.sv` 新增 `mret_priv_violation = is_mret && (priv_mode != PRIV_M)`，S/U-mode 执行 mret 触发 illegal instruction 异常。旧实现允许 S-mode 静默执行 mret，导致特权降级到 U-mode 后所有 S-mode CSR 访问触发非法指令异常→无限重入循环
   - ⑦ **非BRAM TLB路径时序修复**：`MMU.sv` 非 BRAM 路径添加 IDLE/LOOKUP FSM + 输入锁存（`nb_i_latched_priv_mode`/`nb_d_latched_priv_mode` 等），与 BRAM 路径模式一致，打断 `core_top.priv_mode → MMU.perm_check → page_fault` 组合逻辑长路径，改善时序收敛
59. **特权路径修复仿真验证**（2026-06-19）：ISA 10/10 PASS、Exception 6/6 PASS、Privilege 3/3 PASS、MMU 12/12 PASS、Cache 5/5 PASS、MMIO CLINT+PLIC PASS、Regression 7/7 PASS、cpu_full 41/41 PASS。总计 **83/83 PASS**（含后续测试程序缺陷修复后全部通过，见 §60）
60. **测试程序缺陷修复**（2026-06-19）：修复 6 个测试批次的测试程序/TB 缺陷，全部从 FAIL→PASS。所有缺陷均为测试程序逻辑错误，非 RTL 硬件缺陷：
   - **cpu_trap**（5→14 PASS）：定时器处理程序设置 mtimecmp=0 导致无限重触发；MTIP=1 在复位时即有效（mtimecmp=0）；TB `check_mem_word` 使用错误地址（0x48 vs 0x1048）；dcache 写回未刷新（缺少 fence.i）；TB x20 期望值过时
   - **mmu_tlb_asid**（0→2 PASS）：test_04 访问 0x80008000 超出 setup_identity_map 映射范围（仅映射 L0[0-7]=0x80000000-0x80007FFF），改为 0x80005000
   - **mmu_tlb_replace/tlb_stress**（FAIL→PASS）：测试数据写入偏移 0x80 覆盖代码（页 0-1）和页表（页 2-3），改为偏移 0xF00 并跳过页 2-3
    - **mmu_tlb_megapage/sv32_edge**（1/4→4/4, 1/6→6/6 PASS）：`clear_page_tables` 清零 2048 项×~50 周期/次超出仿真周期预算（200K cycles），替换为仅清零 9 个实际使用项（L1[512]+L0[0-7]）的快速内联清零；每个子测试前增加 `disable_sv32` 确保防御性状态清理
61. **D 扩展双精度浮点**（2026-06-30）：22 条非 FMA 双精度指令（FADD.D/FSUB.D/FMUL.D/FDIV.D/FSQRT.D/FLD/FSD/FCVT.*.D/FCVT.S.D/FCVT.D.S/FSGNJ*.D/FEQ.D/FLT.D/FLE.D/FCLASS.D/FMIN.D/FMAX.D），独立 D 专用子模块（非参数化 F 模块），64-bit 数据通路，misa bit[3]=1
62. **FPU 64-bit 寄存器堆与 NaN-boxing**（2026-06-30）：浮点寄存器堆拓宽为 32×64-bit，F 单精度结果写入时 NaN-box 为 `{32'hFFFFFFFF, result[31:0]}`，D 双精度结果写入完整 64 位，D 操作直接读取 64-bit 值（不做 NaN-box 检查）
63. **FLD/FSD 双事务加载/存储**（2026-06-30）：D 扩展双精度访存通过 4 个新 FSM 状态（MEM_FLD_LO/HI、MEM_FSD_LO/HI）+ 2 个 GAP 状态（MEM_FLD_GAP、MEM_FSD_GAP）实现，GAP 状态脉冲 mem_en=0 强制 MMU 重新翻译第二个字的地址，8 字节对齐检查
64. **MMU T_COMPLETE 状态**（2026-06-30）：统一翻译 FSM 新增 T_COMPLETE 状态，translate_done 改为电平信号（在 T_COMPLETE 中保持高电平），防止 translate_req 保持高电平时触发重复翻译，消除 T_DONE 与 T_COMPLETE 之间的 1 周期 gap
65. **PIPT 缓存**（2026-06-30）：icache/dcache 从 VIPT 改为 PIPT，set_idx 来自 paddr（物理地址）而非 vaddr，icache S_TAG_READ 移除 ping-pong 等待（paddr 在 S_IDLE 已锁存）
66. **f0 可写寄存器**（2026-06-30）：移除 f0 硬连线零，f0 为正常可写寄存器（RISC-V 规范不要求 f0=0，与整数 x0 不同），复位初始化为 0 仅为确定性
67. **F 扩展乘法器下溢修复**（2026-06-30）：`fpu_multiplier.sv` 的 exp_overflow_pre 添加符号位保护，修复下溢时 OF 标志误报
68. **F 扩展平方根次正规数修复**（2026-06-30）：`fpu_sqrt.sv` 次正规数尾数规格化修复，24-bit 拼接确保 [1.0,2.0) 范围
69. **FPU FSM 边界测试**（2026-06-30）：tb_fpu_fsm 15 子测试覆盖 F_IDLE/F_DISPATCH/F_WAIT/F_DONE/F_COMPLETE 状态转换、flush 时序、result_got 握手、超时看门狗等边界场景
70. **D 扩展回归验证**（2026-06-30）：F 回归 3/3 PASS（isa_f_ext 30 子测试、isa_f_ext_special 24 子测试、isa_f_f0_writable 5 子测试），D 回归 3/3 PASS（isa_d_smoke 2、isa_d_ext 51、isa_d_ext_special 28），FPU 单元测试 13/13 PASS（F 136 子测试、D 136 子测试、FSM 15 子测试），全回归 55 测试 ALL PASS（54 PASS + 1 XFAIL），时序 WNS=0.288ns（MET）
71. **SimpleOS 操作系统**（2026-07-03）：约 1500 行 C/汇编代码实现的最小化 OS，验证 M/S/U 三级特权转换 + Sv32 分页 + ecall 系统调用全栈功能：
    - M-mode：建页表（L1 + 2×L0 三级页表）、配委托（medeleg）、开分页、mret 进 S-mode
    - S-mode：装 stvec、开 FPU、UART 初始化（230400 baud）、sret 进 U-mode、syscall 服务器（SYS_write/SYS_read/SYS_report/SYS_exit）
    - U-mode：浮点计算器（RV32IMF），5 项自检 + 交互模式（UART 输入表达式实时计算，输入 exit 退出）
    - 单页表设计（S/U 共用 satp，陷入时不切换），VA 转换代替 SUM（内核走恒等映射访问用户内存）
    - A/D 位预置（硬件不自动置位），.incbin 嵌入用户镜像（单一 hex 文件）
72. **SimpleOS 系统调用**（2026-07-03）：4 个系统调用（SYS_write=8 / SYS_read=7 / SYS_report=9 / SYS_exit=2），ecall 陷入 S-mode 分发。SYS_report 写自检结果到内存后返回（不停机），SYS_exit 写结果后 wfi 停机。交互模式通过 SYS_read 阻塞等待 UART 输入
73. **SimpleOS 交互模式**（2026-07-03）：自检完成后不退出，进入交互式计算器循环。用户通过 UART 输入表达式（支持 +,-,*,/,(),sqrt(),neg()），实时计算并输出结果。输入 `exit` 调用 SYS_exit 停机。仿真中程序阻塞在 SYS_read（S-mode uart_getc 轮询），200M 周期后 TB $finish
74. **SimpleOS FPGA 上板就绪**（2026-07-03）：UART 波特率 230400（sys_clk=100MHz，分频系数 27），内核启动时 uart_init 初始化。上板流程：bootloader.coe 等待 DDR3 校准 → UART 接收 os.bin → fence.i → 跳转执行 → SimpleOS 启动 → 交互模式
