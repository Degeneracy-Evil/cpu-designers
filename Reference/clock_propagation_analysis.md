# NonTrivialMIPS 时钟传播分析报告

> 项目：NonTrivialMIPS SoC (Vivado Block Design)  
> FPGA：XC7A200T-FBG676 (-2)  
> 日期：2026-06-07

---

## 1. 顶层时钟输入

| 信号 | 引脚 | IOSTANDARD | 频率 | 说明 |
|------|------|------------|------|------|
| `clk` | AC19 | LVCMOS33 | 100 MHz | 主系统时钟，`CLOCK_DEDICATED_ROUTE BACKBONE` |
| `rst_n` | Y3 | LVCMOS33 | — | 系统复位（低有效） |
| `UTMI_clk` | AA20 | LVCMOS33 | 60 MHz | USB UTMI 独立时钟 |
| `MII_tx_clk` | AB21 | LVCMOS33 | 外部PHY | 以太网发送时钟 |
| `MII_rx_clk` | AA19 | LVCMOS33 | 外部PHY | 以太网接收时钟 |

---

## 2. clk_wiz_0（`main_mmcm`）— 核心时钟发生器

### 2.1 基本信息

- **BD实例名**：`main_mmcm`
- **IP名**：`bd_soc_clk_wiz_0_0`
- **IP类型**：`xilinx.com:ip:clk_wiz:6.0`
- **底层原语**：MMCM（MMCME2_ADV）
- **输入**：`clk_in1` ← 顶层 `clk`（100 MHz）

### 2.2 MMCM 参数

| 参数 | 值 | 说明 |
|------|-----|------|
| CLKFBOUT_MULT_F | 10.000 | VCO = 100 × 10 = **1000 MHz** |
| DIVCLK_DIVIDE | 1 | 输入不分频 |
| CLKIN1_PERIOD | 10.000 ns | 对应 100 MHz |
| COMPENSATION | ZHOLD | 时钟补偿模式 |

### 2.3 五路输出

| 输出端口 | 频率 | 分频系数 | Jitter (ps) | 消费者 |
|----------|------|----------|-------------|--------|
| `clk_cpu` (CLK_OUT1) | **80 MHz** | 12.5 | 137.143 | CPU (`nontrivial_mips_cpu/aclk`)、处理器总线 S00/S01/S02 ACLK |
| `clk_ddr_ref` (CLK_OUT2) | **200 MHz** | 5 | 114.829 | MIG (`ddr_controller/clk_ref_i`) — DDR参考时钟 |
| `clk_vga` (CLK_OUT3) | **25 MHz** | 40 | 175.402 | VGA 控制器 (`vga_controller/sys_tft_clk`) |
| `clk_spi` (CLK_OUT4) | **20 MHz** | 50 | 183.243 | SPI Flash 控制器、CFG Flash 控制器 |
| `clk_peripheral` (CLK_OUT5) | **100 MHz** | 10 | 130.958 | 外设总线及所有外设（详见 §5） |

---

## 3. MIG（`ddr_controller`）— DDR3 控制器时钟链

### 3.1 基本信息

- **BD实例名**：`ddr_controller`
- **IP类型**：`xilinx.com:ip:mig_7series:4.2`
- **DDR3器件**：MT41J64M16XX-125G
- **DDR3频率**：400 MHz（数据速率 800 Mbps）
- **PHY比例**：4:1
- **接口**：AXI4（27位地址，32位数据）

### 3.2 两个时钟输入

| 输入端口 | 来源 | 频率 | 模式 | 用途 |
|----------|------|------|------|------|
| `sys_clk_i` | `clk_peripheral` | 100 MHz | **NO_BUFFER** | MIG 系统时钟，直接进入内部 PLL |
| `clk_ref_i` | `clk_ddr_ref` | 200 MHz | **NO_BUFFER** | IDELAYCTRL 参考时钟 |

> **注意**：MIG 配置为 `No Buffer` 模式，意味着 `sys_clk_i` 和 `clk_ref_i` 不经过 IBUFG，直接由外部驱动（即 clk_wiz_0 的输出）。

### 3.3 MIG 内部时钟生成架构

MIG 内部采用 **PLLE2_ADV + MMCME2_ADV 双级结构**：

```
sys_clk_i (100 MHz, NO_BUFFER)
    │
    ├── PLLE2_ADV (CLKFBOUT_MULT=4, DIVCLK_DIVIDE=1)
    │     │
    │     │  VCO = 100 × 4 = 400 MHz
    │     │
    │     ├── CLKOUT0 (÷16, phase=45°) → freq_refclk    [400 MHz, 用于 Phaser]
    │     ├── CLKOUT1 (÷4)             → mem_refclk     [100 MHz, DDR 内存参考时钟]
    │     ├── CLKOUT2 (÷64, phase=9.84°) → sync_pulse   [6.25 MHz, 1/16 mem_refclk]
    │     ├── CLKOUT3 (÷16)            → pll_clk3       [100 MHz, 喂给 MMCME2_ADV]
    │     └── CLKOUT4 (÷8)             → (未使用)
    │
    └── MMCME2_ADV (输入 = pll_clk3, 即 100 MHz)
          │
          ├── CLKFBOUT → clk_pll_i → BUFG → clk (fabric clock, 100 MHz)
          ├── CLKOUT0  → mmcm_ps_clk (相位偏移时钟, 用于读数据校准)
          └── CLKOUT1  → clk_div2   (50 MHz, 用于 PI incdec)
```

### 3.4 MIG 输出时钟与信号

| 输出 | 频率 | 消费者 | 说明 |
|------|------|--------|------|
| `ui_clk` | 100 MHz | `memory_bus/M00_ACLK`、`ddr_reset_synchronizer/clk` | DDR AXI 总线时钟 |
| `init_calib_complete` | — | `sys_reset_controller/aux_reset_in` | DDR 校准完成指示 |
| `mmcm_locked` | — | `sys_reset_controller/dcm_locked`、`ddr_controller/sys_rst` | MIG 内部 MMCM 锁定状态 |

---

## 4. CPU 时钟域

### 4.1 NonTrivialMIPS CPU

| 端口 | 来源 | 频率 | 说明 |
|------|------|------|------|
| `aclk` | `clk_cpu` | **80 MHz** | CPU 主时钟 |
| `reset_n` | `sys_reset_controller/mb_reset` 取反 | — | CPU 复位 |
| `intr` | 中断信号汇聚 | — | 中断输入 |

### 4.2 CPU 子模块接口

| 子模块 | BD接口路径 | 说明 |
|--------|-----------|------|
| icache | `nontrivial_mips_cpu/icache` | 指令缓存 |
| dcache | `nontrivial_mips_cpu/dcache` | 数据缓存 |
| uncached | `nontrivial_mips_cpu/uncached` | 非缓存访问 |

CPU 通过 **处理器总线** (`processor_bus`) 访问外设，总线时钟为 `clk_cpu`（80 MHz）。

---

## 5. 外设时钟域（`clk_peripheral` = 100 MHz）

`clk_peripheral` 驱动 SoC 中绝大多数外设和互连：

| 消费者 | 说明 |
|--------|------|
| `peripheral_bus/ACLK`, `S00_ACLK`, `M00~M10_ACLK` | 外设 AXI 互连 |
| `processor_bus/M00_ACLK`, `M01_ACLK` | 处理器到外设的总线桥 |
| `uart_controller/s_axi_aclk` | UART 16550 |
| `ethernet_controller/s_axi_aclk` | 以太网 (MII) |
| `vga_controller/s_axi_aclk`, `m_axi_aclk` | VGA 控制器 AXI 接口 |
| `spi_flash_controller/s_axi_aclk` | SPI Flash |
| `cfg_flash_controller/s_axi4_aclk`, `s_axi_aclk` | 配置 Flash |
| `external_interrupt_controller/s_axi_aclk` | 中断控制器 |
| `jtag_sys/aclk` | JTAG AXI 调试接口 |
| `bootrom_controller/s_axi_aclk` | BootROM 控制器 |
| `sys_reset_controller/slowest_sync_clk` | 复位控制器 |
| `loongson_confrreg/aclk`, `timer_clk` | 龙芯配置寄存器 |
| `framebuffer_reader/ap_clk` | 帧缓冲读取 |
| `framebuffer_writer/ap_clk` | 帧缓冲写入 |
| `frame_buffer_modifier/aclk` | 帧缓冲修改器 |
| `ocm_controller/s_axi_aclk` | OCM (On-Chip Memory) 控制器 |
| `ps2_contoller/clk` | PS/2 键盘 |
| `lcd_controller/clk` | LCD 控制器 |
| `ddr_controller/sys_clk_i` | **MIG 系统时钟** |
| `vio_reset/clk` | VIO 复位调试 |
| `peripheral_ila/clk` | ILA 调试探针 |

---

## 6. 独立时钟域

| 时钟 | 频率 | 引脚 | 消费者 | 说明 |
|------|------|------|--------|------|
| `UTMI_clk` | 60 MHz | AA20 | USB 控制器、USB 复位同步器 | USB PHY 独立时钟，在 `io_timings.xdc` 中定义 |
| `MII_tx_clk` | 来自 PHY | AB21 | 以太网 TX 路径 | MII 发送时钟 |
| `MII_rx_clk` | 来自 PHY | AA19 | 以太网 RX 路径 | MII 接收时钟 |

---

## 7. 跨时钟域分析

### 7.1 跨时钟域路径

| 源域 | 目标域 | 源频率 | 目标频率 | 处理方式 |
|------|--------|--------|----------|----------|
| CPU (`clk_cpu`) | DDR AXI (`ui_clk`) | 80 MHz | 100 MHz | `memory_bus` 中的 **auto_cc** (AXI Clock Converter) |
| CPU (`clk_cpu`) | 外设 (`clk_peripheral`) | 80 MHz | 100 MHz | `processor_bus` 中的 **auto_cc** |
| DDR AXI (`ui_clk`) | 外设 (`clk_peripheral`) | 100 MHz | 100 MHz | 同频但不同 MMCM 输出，BD 标记为不同时钟域，需 **auto_cc** |
| USB (`UTMI_clk`) | 外设 (`clk_peripheral`) | 60 MHz | 100 MHz | USB 复位同步器 (`reset_synchronizer`) 处理 |
| 以太网 (`MII_rx_clk`) | 外设 (`clk_peripheral`) | 外部 | 100 MHz | 以太网控制器内部 FIFO 处理 |

### 7.2 潜在风险

1. **CPU ↔ DDR 跨时钟域**：80 MHz → 100 MHz，依赖 AXI 互连的 auto_cc 异步 FIFO，需确保 auto_cc 正确例化
2. **DDR `ui_clk` 与 `clk_peripheral` 同频异源**：两者均为 100 MHz，但来自不同 MMCM 输出（MIG 内部 MMCME2 vs clk_wiz_0），相位不确定，BD 中标记为不同时钟域
3. **UTMI_clk 独立域**：60 MHz USB 时钟与系统时钟无确定相位关系，所有跨域信号需正确同步

---

## 8. 复位链

```
rst_n (外部, Y3, 高有效取反)
    │
    ├──→ clk_wiz_0/resetn
    │
    └──→ clk_wiz_0/locked
              │
              ├──→ sys_reset_controller/dcm_locked
              │         │
              │         ├──→ proc_sys_reset → mb_reset
              │         │       │
              │         │       ├──→ CPU reset_n (取反后)
              │         │       ├──→ processor_bus/S00~S02_ARESETN
              │         │       └──→ reset_negate → CPU reset_n
              │         │
              │         ├──→ peripheral_aresetn
              │         │       └──→ 所有外设 AXI 复位
              │         │
              │         └──→ interconnect_aresetn
              │               └──→ 所有 AXI 互连复位
              │
              └──→ ddr_controller/sys_rst (MIG 系统复位)
                        │
                        └──→ MIG init_calib_complete
                                  │
                                  └──→ sys_reset_controller/aux_reset_in
                                            (DDR 校准完成后才释放外设复位)
```

**复位顺序**：
1. 外部 `rst_n` 释放
2. clk_wiz_0 MMCM 锁定 → `locked` 拉高
3. MIG 开始 DDR3 校准
4. MIG 校准完成 → `init_calib_complete` 拉高
5. `sys_reset_controller` 释放所有复位

---

## 9. 时钟约束摘要

### 9.1 fpga_pins.xdc

- `clk` 引脚约束在 AC19，`CLOCK_DEDICATED_ROUTE BACKBONE` 确保低偏斜
- DDR3 引脚由 MIG XDC 单独约束（Bank 16, SSTL15, INTERNAL_VREF = 0.750V）

### 9.2 io_timings.xdc

| 约束 | 目标 | 说明 |
|------|------|------|
| `create_generated_clock clk_sck` | CFG Flash SCK | SPI 时钟由 STARTUPE2 USRCCLKO 驱动 |
| `set_output_delay` (VGA) | `VGA_*` 端口 | 相对 `clk_vga` (25 MHz) |
| `create_clock utmi_clk` | `UTMI_clk` 端口 | 60 MHz (16.667 ns) |
| `set_input/output_delay` (Ethernet) | MII 端口 | 相对 MII 时钟 |
| `set_false_path` (GPIO) | LED/按键/开关/UART/PS2 | 异步外设，无需时序约束 |

### 9.3 MIG XDC (bd_soc_mig_7series_0_1.xdc)

- DDR3 频率：400 MHz，周期 2500 ps
- PLLE2_ADV 位置：`PLLE2_ADV_X0Y4`
- MMCME2_ADV 位置：`MMCME2_ADV_X0Y4`
- PHASER_OUT/IN、FIFO、PHY_CONTROL 等物理原语位置约束

---

## 10. 总体时钟拓扑图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  clk (100MHz, AC19) ──→ clk_wiz_0 (MMCM, VCO=1000MHz)                 │
│                                                                         │
│    ┌── clk_cpu (80MHz) ──────→ NonTrivialMIPS CPU (aclk)              │
│    │                       ──→ processor_bus S00/S01/S02 ACLK          │
│    │                                                                    │
│    ├── clk_ddr_ref (200MHz) ─→ MIG clk_ref_i (IDELAYCTRL参考)         │
│    │                                                                    │
│    ├── clk_vga (25MHz) ─────→ VGA Controller (sys_tft_clk)            │
│    │                                                                    │
│    ├── clk_spi (20MHz) ─────→ SPI Flash Controller                     │
│    │                       ──→ CFG Flash Controller                     │
│    │                                                                    │
│    └── clk_peripheral (100MHz)                                         │
│          ├──→ MIG sys_clk_i ──→ PLLE2_ADV (×4) ──→ DDR3 400MHz       │
│          │                         └→ MMCME2_ADV ──→ ui_clk (100MHz)  │
│          │                                              │              │
│          │                                    memory_bus/M00_ACLK     │
│          │                                              │              │
│          ├──→ UART / Ethernet / SPI / VGA(AXI) / BootROM              │
│          ├──→ Interrupt Controller / JTAG / PS2 / LCD                 │
│          ├──→ Framebuffer Reader/Writer/Modifier                      │
│          ├──→ OCM Controller / Loongson ConfReg                      │
│          ├──→ sys_reset_controller / VIO Reset / ILA                  │
│          └──→ peripheral_bus (所有外设AXI互连)                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

  UTMI_clk (60MHz, AA20) ──→ USB Controller (独立时钟域)
  MII_tx_clk / MII_rx_clk ──→ Ethernet PHY (外部时钟)
```

---

## 11. 关键结论

1. **clk_wiz_0 是全系统唯一的时钟发生器**，从 100 MHz 晶振生成 5 路不同频率时钟，驱动整个 SoC
2. **MIG 有两条时钟输入**：`sys_clk_i` 来自 `clk_peripheral`（100 MHz），`clk_ref_i` 来自 `clk_ddr_ref`（200 MHz），均配置为 NO_BUFFER 模式
3. **MIG 内部有独立的 PLL+MMCM 双级时钟生成**，将 100 MHz 倍频至 400 MHz 驱动 DDR3 物理层，并输出 100 MHz `ui_clk` 驱动 AXI 总线
4. **CPU 运行在 80 MHz**，外设运行在 100 MHz，DDR UI 运行在 100 MHz — 存在跨时钟域，依赖 AXI 互连的 auto_cc 异步 FIFO
5. **USB UTMI_clk (60 MHz) 为完全独立的时钟域**，与系统时钟无相位关系
6. **复位链严格有序**：外部复位 → MMCM 锁定 → MIG 校准 → 系统复位释放，确保 DDR3 校准完成后 CPU 和外设才开始工作
