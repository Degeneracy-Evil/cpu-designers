# MIG 7 Series + AHB-Lite AXI Bridge 联合配置报告

## 1. IP 概览

### 1.1 MIG 7 Series (DDR3 控制器)

| 属性 | 值 |
|---|---|
| IP VLNV | `xilinx.com:ip:mig_7series:4.2` |
| 实例名 | `bd_soc_mig_7series_0_1` |
| 内存型号 | MT41J64M16XX-125G (Micron DDR3, 64M×16) |
| 内存容量 | 128 MB (134217728 bytes) |
| 数据速率 | 800 Mbps (400 MHz DDR, TimePeriod=2500ps) |
| 参考时钟 | 100 MHz, No Buffer (外部提供) |
| 接口类型 | **AXI4 Slave** (S_AXI) |
| AXI 地址宽度 | **27 bit** |
| AXI 数据宽度 | **32 bit** |
| AXI ID 宽度 | **8 bit** |
| AXI 仲裁 | RD_PRI_REG (读优先注册) |
| 支持窄突发 | 1 (是) |
| 配置文件 | `mig_a.prj` (XML_INPUT_FILE) |

### 1.2 AHB-Lite AXI Bridge

| 属性 | 值 |
|---|---|
| IP VLNV | `xilinx.com:ip:ahblite_axi_bridge:3.0` |
| 实例名 | `ahblite_axi_bridge_0` |
| AHB-Lite 侧 | **Slave** (S_AHB), 32-bit addr, 32-bit data |
| AXI 侧 | **Master** (M_AXI), AXI4, 32-bit addr, 32-bit data |
| AXI ID 宽度 | **0 bit** (可配置) |
| 支持窄突发 | 1 (可配置) |
| AHB 时钟频率 | 100 MHz |
| 超时配置 | C_AHB_AXI_TIMEOUT = 0 (无超时) |

---

## 2. 联合配置参数填写

### 2.1 MIG IP 创建命令

```tcl
# 创建 MIG 7 Series IP
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 \
    -module_name bd_soc_mig_7series_0_1

# MIG 的核心配置由 XML_INPUT_FILE (mig_a.prj) 决定
# mig_a.prj 包含: 引脚分配、Bank选择、时序参数、内存型号、AXI参数等
set_property -dict [list \
    CONFIG.XML_INPUT_FILE        {E:/Xprogram/FPGA/tmpp/bd_soc_mig_7series_0_1/mig_a.prj} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
] [get_ips bd_soc_mig_7series_0_1]
```

### 2.2 AHB-Lite AXI Bridge 创建命令

```tcl
# 创建 AHB-Lite AXI Bridge IP
create_ip -name ahblite_axi_bridge -vendor xilinx.com -library ip -version 3.0 \
    -module_name ahblite_axi_bridge_0

# 配置 Bridge 参数
set_property -dict [list \
    CONFIG.C_M_AXI_THREAD_ID_WIDTH   {0} \
    CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {1} \
] [get_ips ahblite_axi_bridge_0]
```

### 2.3 参数配置详解

#### C_M_AXI_THREAD_ID_WIDTH = 0

**含义**: AXI Master 接口的 Transaction ID 宽度。

**为什么设为 0**:
- Bridge 的 M_AXI 端口不输出 `awid`/`arid` 信号 (ID_WIDTH=0 时这些信号不存在)
- MIG 的 S_AXI 端口接受 `s_axi_awid[7:0]`/`s_axi_arid[7:0]` (ID_WIDTH=8)
- 连接时将 MIG 的 ID 输入硬连线为 0
- 设为 0 可节省 Bridge 内部的 FIFO 资源，避免不必要的 ID 跟踪逻辑

**如果设为非 0**:
- Bridge 会生成 `m_axi_awid`/`m_axi_arid` 输出端口
- 可直接连接到 MIG 的 ID 输入
- 但 Bridge 内部需要 ID 跟踪 FIFO，增加资源消耗
- 对于单主设备访问 DDR 的场景，ID=0 完全足够

#### C_M_AXI_SUPPORTS_NARROW_BURST = 1

**含义**: AXI Master 是否支持窄突发 (传输宽度小于数据总线宽度)。

**为什么设为 1**:
- MIG 的 S_AXI 也支持窄突发 (C0_S_AXI_SUPPORTS_NARROW_BURST=1)
- AHB-Lite 的 HSIZE 可以指定小于 32-bit 的传输 (HSIZE=0→BYTE, HSIZE=1→HALFWORD)
- Bridge 需要将 AHB-Lite 的窄传输转换为 AXI 的窄突发
- 设为 1 确保 Bridge 正确生成 `m_axi_wstrb` 信号

**如果设为 0**:
- Bridge 不支持窄突发，所有传输按 32-bit 全宽处理
- AHB-Lite 的 HSIZE=0 (BYTE) 和 HSIZE=1 (HALFWORD) 传输将被错误处理
- MIG 侧的 `s_axi_wstrb` 将始终为 4'b1111

---

## 3. AHB-Lite 总线特性要求

### 3.1 Bridge 对 AHB-Lite 总线的硬性要求

| 要求 | 说明 |
|---|---|
| **HCLK 频率匹配** | AHB HCLK 必须等于 MIG ui_clk (100 MHz)。Bridge 不做时钟域交叉，AHB 和 AXI 侧共享同一时钟 |
| **HRESETn 极性** | 低有效 (ACTIVE LOW)，与 MIG 的 aresetn 极性一致 |
| **HTRANS 编码** | 必须使用标准 AHB-Lite 编码: 00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ |
| **HBURST 编码** | 必须使用标准编码: 000=SINGLE, 001=INCR, 010=WRAP4, 011=INCR4, 100=WRAP8, 101=INCR8, 110=WRAP16, 111=INCR16 |
| **HSIZE 编码** | 000=BYTE, 001=HALFWORD, 010=WORD, 其他保留。最大 HSIZE=010 (32-bit) |
| **HSEL 使用** | Bridge 仅在 HSEL=1 时响应总线交易。HSEL 通常由地址译码器产生 |
| **HREADY_IN** | 多从设备总线中，HREADY_IN 来自前一个从设备的 HREADY_OUT。单从设备时接 1 |
| **HRESP** | Bridge 输出 0=OKAY, 1=ERROR。AHB-Lite 不支持 SPLIT/RETRY |

### 3.2 AHB-Lite 总线限制 (Bridge 侧)

| 限制 | 说明 |
|---|---|
| **不支持 SPLIT/RETRY** | AHB-Lite 协议不支持 SPLIT/RETRY 响应，Bridge 仅输出 OKAY 或 ERROR |
| **最大突发长度 16** | AHB-Lite 最大 WRAP16/INCR16 = 16 拍。AXI4 最大 256 拍。Bridge 将 AHB 突发映射到 AXI 突发，不会超过 16 拍 |
| **地址必须对齐** | HSIZE=WORD 时 HADDR[1:0]=00, HSIZE=HALFWORD 时 HADDR[0]=0。Bridge 依赖对齐地址生成正确的 AXI 信号 |
| **不支持独占访问** | AHB-Lite 无独占访问概念，Bridge 不生成 AXI 的 AxLOCK 信号 (输出常量 0) |
| **HPROT 处理** | Bridge 将 HPROT 映射到 AXI AxPROT: HPROT[0]→AxPROT[0] (Data/Instr), HPROT[1]→AxPROT[1] (Privileged), HPROT[2]→AxPROT[2] (Secure/Non-secure) |

### 3.3 AHB-Lite 到 AXI4 突发映射

| AHB-Lite HBURST | AHB 拍数 | AXI4 AxLEN | AXI4 AxBURST | 备注 |
|---|---|---|---|---|
| SINGLE (000) | 1 | 0 | INCR (01) | 单拍 → AXI INCR 长度 1 (PG176 Table 3-1) |
| INCR4 (011) | 4 | 3 | INCR (01) | |
| WRAP4 (010) | 4 | 3 | WRAP (10) | |
| INCR8 (101) | 8 | 7 | INCR (01) | |
| WRAP8 (100) | 8 | 7 | WRAP (10) | |
| INCR16 (111) | 16 | 15 | INCR (01) | |
| WRAP16 (110) | 16 | 15 | WRAP (10) | |
| INCR (001) | 未定义长度 | 0 | INCR (01) | 未定义长度 → AXI INCR 长度 0 |

> **重要 (PG176)**:
> - SINGLE 映射为 AXI **INCR** 长度 1，**不是** FIXED (PG176 Table 3-1 明确规定)
> - INCR (未定义长度) 映射为 AXI INCR 长度 0，某些 AXI Interconnect 可能不支持。**建议避免使用 INCR 突发访问 DDR，改用 INCR4/INCR8/INCR16**
> - **突发提前终止**: 当 AHB 主设备提前终止突发 (HTRANS 从 SEQ 变为 IDLE/NONSEQ)，Bridge 在 AXI 侧用 **dummy 传输** 完成剩余拍数，写通零 (`wstrb=0`) 防止误写

---

## 4. 两个 IP 的连接方案

### 4.1 接口匹配分析

```
                    AHB-Lite Bus
                         │
                         ▼
┌─────────────────────────────────────────┐
│        ahblite_axi_bridge_0             │
│                                         │
│  S_AHB (Slave)      M_AXI (Master)     │
│  32-bit addr        32-bit addr        │
│  32-bit data        32-bit data        │
│  ID_WIDTH=N/A       ID_WIDTH=0         │
│                      No awid/arid      │
│                      SUPPORTS_NARROW=1 │
└──────────────────────┬──────────────────┘
                       │ AXI4
                       ▼
┌─────────────────────────────────────────┐
│        bd_soc_mig_7series_0_1           │
│                                         │
│  S_AXI (Slave)                          │
│  27-bit addr                            │
│  32-bit data                            │
│  ID_WIDTH=8                             │
│  SUPPORTS_NARROW=1                      │
└─────────────────────────────────────────┘
                       │
                       ▼
                   DDR3 SDRAM
```

### 4.2 关键不匹配点及解决方案

| 不匹配项 | Bridge M_AXI | MIG S_AXI | 解决方案 |
|---|---|---|---|
| **地址宽度** | 32 bit | 27 bit | Bridge 输出 32-bit 地址，取低 27 位连接到 MIG，高 5 位忽略 |
| **ID 宽度** | 0 (无 ID 端口) | 8 bit | MIG 的 `s_axi_awid`/`s_axi_arid` 硬连线为 8'h00 |
| **QoS** | 无 (HAS_QOS=0) | 有 `s_axi_awqos`/`s_axi_arqos` | 硬连线为 4'h0 |
| **Region** | 无 (HAS_REGION=0) | 有 `s_axi_awregion`/`s_axi_arregion` | 硬连线为 4'h0 |
| **AWID/ARID** | 不存在 | 需要 8-bit | 硬连线为 0 |

### 4.3 完整端口连接 Verilog 代码

```verilog
// =========================================================================
// AHB-Lite AXI Bridge → MIG DDR3 Controller 连接
// =========================================================================

// --- 时钟和复位 ---
// Bridge 和 MIG 共享同一时钟域 (ui_clk = 100 MHz)
assign s_ahb_hclk    = ui_clk;       // AHB 时钟 = MIG UI 时钟
assign s_ahb_hresetn = aresetn;      // AHB 复位 = MIG AXI 复位 (低有效)

// --- AXI4 Write Address Channel ---
assign mig_s_axi_awid     = 8'h00;                   // Bridge 无 ID, 硬连线 0
assign mig_s_axi_awaddr   = bridge_m_axi_awaddr[26:0]; // 取低 27 位
assign mig_s_axi_awlen    = bridge_m_axi_awlen;
assign mig_s_axi_awsize   = bridge_m_axi_awsize;
assign mig_s_axi_awburst  = bridge_m_axi_awburst;
assign mig_s_axi_awlock   = bridge_m_axi_awlock;
assign mig_s_axi_awcache  = bridge_m_axi_awcache;
assign mig_s_axi_awprot   = bridge_m_axi_awprot;
assign mig_s_axi_awqos    = 4'h0;                     // Bridge 无 QoS, 硬连线 0
assign mig_s_axi_awvalid  = bridge_m_axi_awvalid;
assign bridge_m_axi_awready = mig_s_axi_awready;

// --- AXI4 Write Data Channel ---
assign mig_s_axi_wdata    = bridge_m_axi_wdata;
assign mig_s_axi_wstrb    = bridge_m_axi_wstrb;
assign mig_s_axi_wlast    = bridge_m_axi_wlast;
assign mig_s_axi_wvalid   = bridge_m_axi_wvalid;
assign bridge_m_axi_wready  = mig_s_axi_wready;

// --- AXI4 Write Response Channel ---
assign bridge_m_axi_bresp  = mig_s_axi_bresp;
assign bridge_m_axi_bvalid = mig_s_axi_bvalid;
assign mig_s_axi_bready   = bridge_m_axi_bready;
// 注意: MIG 输出 s_axi_bid[7:0], Bridge 无 bready ID 输入, 忽略

// --- AXI4 Read Address Channel ---
assign mig_s_axi_arid     = 8'h00;                   // Bridge 无 ID, 硬连线 0
assign mig_s_axi_araddr   = bridge_m_axi_araddr[26:0]; // 取低 27 位
assign mig_s_axi_arlen    = bridge_m_axi_arlen;
assign mig_s_axi_arsize   = bridge_m_axi_arsize;
assign mig_s_axi_arburst  = bridge_m_axi_arburst;
assign mig_s_axi_arlock   = bridge_m_axi_arlock;
assign mig_s_axi_arcache  = bridge_m_axi_arcache;
assign mig_s_axi_arprot   = bridge_m_axi_arprot;
assign mig_s_axi_arqos    = 4'h0;                     // Bridge 无 QoS, 硬连线 0
assign mig_s_axi_arvalid  = bridge_m_axi_arvalid;
assign bridge_m_axi_arready = mig_s_axi_arready;

// --- AXI4 Read Data Channel ---
assign bridge_m_axi_rdata  = mig_s_axi_rdata;
assign bridge_m_axi_rresp  = mig_s_axi_rresp;
assign bridge_m_axi_rvalid = mig_s_axi_rvalid;
assign bridge_m_axi_rlast  = mig_s_axi_rlast;
assign mig_s_axi_rready   = bridge_m_axi_rready;
// 注意: MIG 输出 s_axi_rid[7:0], Bridge 无 rready ID 输入, 忽略
```

### 4.4 端口连接汇总表

| Bridge M_AXI (输出) | 方向 | MIG S_AXI (输入) | 备注 |
|---|---|---|---|
| `m_axi_awaddr[26:0]` | → | `s_axi_awaddr[26:0]` | 取低27位 |
| `m_axi_awlen[7:0]` | → | `s_axi_awlen[7:0]` | 直连 |
| `m_axi_awsize[2:0]` | → | `s_axi_awsize[2:0]` | 直连 |
| `m_axi_awburst[1:0]` | → | `s_axi_awburst[1:0]` | 直连 |
| `m_axi_awlock` | → | `s_axi_awlock[0]` | 直连 |
| `m_axi_awcache[3:0]` | → | `s_axi_awcache[3:0]` | 直连 |
| `m_axi_awprot[2:0]` | → | `s_axi_awprot[2:0]` | 直连 |
| `m_axi_awvalid` | → | `s_axi_awvalid` | 直连 |
| — | → | `s_axi_awid[7:0]` | **硬连线 8'h00** |
| — | → | `s_axi_awqos[3:0]` | **硬连线 4'h0** |
| `m_axi_wdata[31:0]` | → | `s_axi_wdata[31:0]` | 直连 |
| `m_axi_wstrb[3:0]` | → | `s_axi_wstrb[3:0]` | 直连 |
| `m_axi_wlast` | → | `s_axi_wlast` | 直连 |
| `m_axi_wvalid` | → | `s_axi_wvalid` | 直连 |
| `m_axi_bready` | → | `s_axi_bready` | 直连 |
| `m_axi_araddr[26:0]` | → | `s_axi_araddr[26:0]` | 取低27位 |
| `m_axi_arlen[7:0]` | → | `s_axi_arlen[7:0]` | 直连 |
| `m_axi_arsize[2:0]` | → | `s_axi_arsize[2:0]` | 直连 |
| `m_axi_arburst[1:0]` | → | `s_axi_arburst[1:0]` | 直连 |
| `m_axi_arlock` | → | `s_axi_arlock[0]` | 直连 |
| `m_axi_arcache[3:0]` | → | `s_axi_arcache[3:0]` | 直连 |
| `m_axi_arprot[2:0]` | → | `s_axi_arprot[2:0]` | 直连 |
| `m_axi_arvalid` | → | `s_axi_arvalid` | 直连 |
| — | → | `s_axi_arid[7:0]` | **硬连线 8'h00** |
| — | → | `s_axi_arqos[3:0]` | **硬连线 4'h0** |
| `m_axi_rready` | → | `s_axi_rready` | 直连 |

| MIG S_AXI (输出) | 方向 | Bridge M_AXI (输入) | 备注 |
|---|---|---|---|
| `s_axi_awready` | → | `m_axi_awready` | 直连 |
| `s_axi_wready` | → | `m_axi_wready` | 直连 |
| `s_axi_bid[7:0]` | → | — | **忽略** (Bridge 无 ID) |
| `s_axi_bresp[1:0]` | → | `m_axi_bresp[1:0]` | 直连 |
| `s_axi_bvalid` | → | `m_axi_bvalid` | 直连 |
| `s_axi_arready` | → | `m_axi_arready` | 直连 |
| `s_axi_rid[7:0]` | → | — | **忽略** (Bridge 无 ID) |
| `s_axi_rdata[31:0]` | → | `m_axi_rdata[31:0]` | 直连 |
| `s_axi_rresp[1:0]` | → | `m_axi_rresp[1:0]` | 直连 |
| `s_axi_rlast` | → | `m_axi_rlast` | 直连 |
| `s_axi_rvalid` | → | `m_axi_rvalid` | 直连 |

---

## 5. 连接到 AHB-Lite 总线

### 5.1 AHB-Lite 总线信号清单

AHB-Lite 总线由以下信号组成 (AMBA 3 AHB-Lite 协议):

| 信号 | 方向 | 宽度 | 说明 |
|---|---|---|---|
| HCLK | 全局 | 1 | 总线时钟 |
| HRESETn | 全局 | 1 | 总线复位 (低有效) |
| HADDR | Master→Slave | 32 | 地址 |
| HTRANS | Master→Slave | 2 | 传输类型 |
| HSIZE | Master→Slave | 3 | 传输大小 |
| HBURST | Master→Slave | 3 | 突发类型 |
| HWRITE | Master→Slave | 1 | 写使能 |
| HPROT | Master→Slave | 4 | 保护控制 |
| HWDATA | Master→Slave | 32 | 写数据 |
| HRDATA | Slave→Master | 32 | 读数据 |
| HREADY | Slave→Master | 1 | 从设备就绪 |
| HRESP | Slave→Master | 1 | 传输响应 |
| HSEL | 译码器→Slave | 1 | 从设备选择 |

### 5.2 AHB-Lite 多从设备总线连接

在典型的 AHB-Lite 总线中，多个从设备通过地址译码器选择。Bridge 作为其中一个从设备：

```
                    AHB-Lite Master (CPU)
                         │
                         ▼
              ┌─────────────────────┐
              │   AHB-Lite Bus      │
              │  HADDR, HTRANS, ... │
              └──────┬──────┬───────┘
                     │      │
              ┌──────┴──┐ ┌┴──────────────────┐
              │ Address  │ │                    │
              │ Decoder  │ │                    │
              └──────┬──┘ │                    │
                     │    │                    │
              ┌──────┴────┴──────────┐ ┌──────┴──────┐
              │  HSEL = f(HADDR)     │ │  Other      │
              │                       │ │  AHB Slaves │
              │  ahblite_axi_bridge_0 │ │  (APB, SRAM)│
              │  (DDR 区域)           │ │             │
              └───────────┬───────────┘ └─────────────┘
                          │ AXI4
                          ▼
              ┌───────────────────────┐
              │  bd_soc_mig_7series_0_1│
              │  (DDR3 Controller)     │
              └───────────┬───────────┘
                          │
                          ▼
                      DDR3 SDRAM
```

### 5.3 地址译码器设计

MIG DDR3 的 AXI 地址宽度为 27 bit，对应 128MB 地址空间。在 32-bit AHB 地址空间中：

```verilog
// DDR3 地址区域: 0x0000_0000 ~ 0x07FF_FFFF (128MB, 地址[31:25]=0)
// 也可映射到其他基地址, 例如 0x8000_0000 ~ 0x87FF_FFFF
parameter DDR_BASE_ADDR = 32'h0000_0000;
parameter DDR_ADDR_MASK = 32'hF800_0000;  // 高 5 位掩码

// HSEL 生成: 当 AHB 地址落在 DDR 区域时选中 Bridge
assign bridge_s_ahb_hsel = ((HADDR & DDR_ADDR_MASK) == (DDR_BASE_ADDR & DDR_ADDR_MASK));
```

### 5.4 AHB-Lite 总线信号连接到 Bridge

```verilog
// --- Bridge AHB-Lite Slave 端口连接 ---
assign bridge_s_ahb_hclk     = HCLK;
assign bridge_s_ahb_hresetn  = HRESETn;
assign bridge_s_ahb_hsel     = ddr_hsel;      // 地址译码器输出
assign bridge_s_ahb_haddr    = HADDR;
assign bridge_s_ahb_htrans   = HTRANS;
assign bridge_s_ahb_hsize    = HSIZE;
assign bridge_s_ahb_hburst   = HBURST;
assign bridge_s_ahb_hwrite   = HWRITE;
assign bridge_s_ahb_hprot    = HPROT;
assign bridge_s_ahb_hwdata   = HWDATA;
assign bridge_s_ahb_hready_in = HREADY;        // 来自前一个从设备或 1

// Bridge 输出到 AHB 总线
assign ddr_hrdata   = bridge_s_ahb_hrdata;
assign ddr_hready   = bridge_s_ahb_hready_out;
assign ddr_hresp    = bridge_s_ahb_hresp;

// 多从设备 HREADY 多路选择
// HREADY = ddr_hready (当 ddr_hsel=1) | other_hready (当 other_hsel=1) | ...
```

### 5.5 多从设备 HRESP 和 HRDATA 仲裁

```verilog
// HRDATA 多路选择: 根据 HSEL 选择对应从设备的读数据
assign HRDATA = ddr_hsel   ? bridge_s_ahb_hrdata :
                other_hsel ? other_hrdata        :
                32'h0;

// HRESP: AHB-Lite 任意从设备返回 ERROR 则总线响应 ERROR
assign HRESP = ddr_hsel   ? bridge_s_ahb_hresp :
               other_hsel ? other_hresp        :
               1'b0;  // OKAY

// HREADY: 所有从设备就绪
assign HREADY = (ddr_hsel   & bridge_s_ahb_hready_out) |
                (other_hsel & other_hready)            |
                (~ddr_hsel & ~other_hsel);  // 无从设备选中时默认就绪
```

---

## 6. 完整 TCL 生成脚本

```tcl
# =========================================================================
# gen_mig_bridge.tcl — 生成 MIG DDR3 + AHB-Lite AXI Bridge IP
# =========================================================================

set base_dir    [file dirname [file normalize [info script]]]
set proj_name   "test"
set device_part "xc7a200tfbg676-2"
set proj_dir    "${base_dir}/${proj_name}"

# --- Step 1: 打开工程 ---
set cur_proj [current_project -quiet]
if { $cur_proj ne "" && $cur_proj ne $proj_name } {
    catch { close_project }
    set cur_proj ""
}
if { $cur_proj eq "" } {
    set xpr_path "${proj_dir}/${proj_name}.xpr"
    if { [file exists $xpr_path] } {
        open_project $xpr_path
    } else {
        create_project $proj_name $proj_dir -part $device_part -force
        set_property target_language Verilog [current_project]
    }
}

# --- Step 2: 创建 MIG 7 Series IP ---
set mig_prj_file "${base_dir}/bd_soc_mig_7series_0_1/mig_a.prj"

if { [get_ips -quiet bd_soc_mig_7series_0_1] ne "" } {
    catch { remove_ip [get_ips bd_soc_mig_7series_0_1] }
}

create_ip -name mig_7series -vendor! xilinx.com -library ip -version 4.2 \
    -module_name bd_soc_mig_7series_0_1

set_property -dict [list \
    CONFIG.XML_INPUT_FILE        $mig_prj_file \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
] [get_ips bd_soc_mig_7series_0_1]

generate_target all [get_ips bd_soc_mig_7series_0_1]
catch { config_ip_cache -export [get_ips bd_soc_mig_7series_0_1] }
export_ip_user_files -of_objects [get_ips bd_soc_mig_7series_0_1] -no_script -sync -force -quiet

# --- Step 3: 创建 AHB-Lite AXI Bridge IP ---
if { [get_ips -quiet ahblite_axi_bridge_0] ne "" } {
    catch { remove_ip [get_ips ahblite_axi_bridge_0] }
}

create_ip -name ahblite_axi_bridge -vendor xilinx.com -library ip -version 3.0 \
    -module_name ahblite_axi_bridge_0

set_property -dict [list \
    CONFIG.C_M_AXI_THREAD_ID_WIDTH     {0} \
    CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {1} \
] [get_ips ahblite_axi_bridge_0]

generate_target all [get_ips ahblite_axi_bridge_0]
catch { config_ip_cache -export [get_ips ahblite_axi_bridge_0] }
export_ip_user_files -of_objects [get_ips ahblite_axi_bridge_0] -no_script -sync -force -quiet

update_compile_order -fileset sources_1

puts "MIG + AHB-Lite AXI Bridge IP 生成完成!"
```

---

## 7. 注意事项与常见陷阱

### 7.1 时钟域

- **Bridge 不做时钟域交叉**。`s_ahb_hclk` 必须等于 MIG 的 `ui_clk`
- MIG 的 `ui_clk` 由内部 MMCM 生成 (从 `sys_clk_i` 或 `clk_ref_i` 产生)
- AHB 总线时钟必须由 MIG 的 `ui_clk` 驱动，**不能独立使用其他时钟源**

### 7.2 地址空间

- MIG AXI 地址宽度 27 bit → 2^27 = 128MB 地址空间
- Bridge 输出 32-bit 地址，高 5 位被忽略
- AHB 地址译码器必须确保访问 DDR 区域时，`HADDR[26:0]` 覆盖完整的 128MB 空间

### 7.3 初始化顺序

- MIG DDR3 控制器需要校准时间 (约 100-200 μs)
- `init_calib_complete` 信号指示校准完成
- **在 `init_calib_complete` 为高之前，不应通过 AHB 总线访问 DDR**
- 建议在 AHB 主设备侧增加校准完成检查，或用 `init_calib_complete` 门控 Bridge 的 `s_ahb_hsel`

### 7.4 AXI ID 一致性

- Bridge M_AXI ID_WIDTH=0，所有事务 ID=0
- MIG S_AXI ID_WIDTH=8，硬连线到 0
- 如果未来需要多主设备访问 DDR (如 DMA + CPU)，需要 AXI Interconnect，此时 ID 宽度需重新规划

### 7.5 突发对齐

- AHB-Lite WRAP 突发要求地址对齐到突发大小边界
- 例如 WRAP4 (4×32-bit=16-byte) 要求 HADDR[3:0]=0000
- Bridge 依赖 AHB-Lite 的对齐规则生成正确的 AXI 地址
- **如果 AHB 主设备发出未对齐的 WRAP 突发，Bridge 行为未定义**

### 7.6 MIG sys_rst 极性

- `mig_a.prj` 中 `SysResetPolarity = ACTIVE LOW`
- MIG 的 `sys_rst` 输入低有效
- Bridge 的 `s_ahb_hresetn` 也是低有效
- 两者可以共用同一复位信号

### 7.7 超时与复位 (PG176 关键规则)

- 当前配置 `C_AHB_AXI_TIMEOUT = 0` (无超时)，Bridge 会无限等待 AXI 从设备响应
- **如果启用超时** (值 16/32/64/128/256)：Bridge 在超时后在 AHB 侧产生 ERROR 响应
- **PG176 强制规则**: 启用超时时，检测到 ERROR 响应后 **必须对 Bridge 复位**。因为 Bridge 无法区分从设备错误和超时错误，超时后 AXI 侧可能处于不一致状态
- 未启用超时时，ERROR 响应不需要复位
- **建议**: 保持 TIMEOUT=0，依赖 MIG 的正常响应时序；如需超时保护，选择较大值 (≥128) 并确保错误处理逻辑包含复位

### 7.8 AXI4 响应映射 (PG176)

| AXI4 响应 | 编码 | AHB-Lite 响应 | 说明 |
|---|---|---|---|
| OKAY | 00 | OKAY (0) | 正常完成 |
| EXOKAY | 01 | — | Bridge 不发起独占访问，不会收到此响应 |
| SLVERR | 10 | ERROR (1) | 从设备错误 |
| DECERR | 11 | ERROR (1) | 译码错误 |

- **SPLIT/RETRY 不支持**: AHB-Lite 协议仅定义 OKAY/ERROR，Bridge 不支持 SPLIT/RETRY
- MIG DDR3 正常情况下只返回 OKAY；SLVERR/DECERR 仅在非法访问时出现

### 7.9 AHB 突发 1KB 边界规则 (ARM IHI 0033)

- AHB-Lite 协议要求：**增量突发 (INCR/INCR4/INCR8/INCR16) 不能跨越 1KB 地址边界**
- 1KB 边界地址: 0x000, 0x400, 0x800, 0xC00, 0x1000, ...
- WRAP 突发自动在边界处回卷，不受此限制
- **违反此规则会导致 Bridge 生成错误的 AXI 地址**，可能造成 DDR 数据损坏

---

## 8. 参考文档

| 文档 | 编号 | 版本 | 链接 |
|---|---|---|---|
| AHB-Lite to AXI4 Bridge Product Guide | PG176 | v3.0 | [docs.amd.com/v/u/en-US/pg176-ahblite-axi-bridge](https://docs.amd.com/v/u/en-US/pg176-ahblite-axi-bridge) |
| AMBA 3 AHB-Lite 协议规范 | IHI 0033 | v1.0 | [documentation-service.arm.com](https://documentation-service.arm.com/static/5f91607cf86e16515cdc3b4b) |
| MIG 7 Series User Guide | UG586 | — | Xilinx MIG 7 Series DDR3/DDR2 内存接口解决方案用户指南 |
| AXI Reference Guide | UG1037 | — | Vivado AXI 参考指南 |
