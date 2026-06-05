# DDR3 主存替换计划

> 日期: 2026-06-05 | 状态: 进行中 (Phase 1+2+2.5 完成) | 依赖资料: `Reference/mig/ip_report.md`, `Reference/mig/mig_a.prj`

---

## 1. 背景与动机

### 1.1 当前主存

| 项目 | 值 |
|------|-----|
| 实现 | BRAM IP `Sram`（Vivado blk_mem_gen） |
| 容量 | 32-bit × 8192 = **32KB** |
| 接口 | `ahb_sram_slave.sv` → AHB-Lite @ `0x8000_0000` |
| 程序加载 | COE 文件烧入 BRAM（综合时固定） |
| 延迟 | 1 cycle（BRAM 寄存输出） |

### 1.2 为何改用 DDR3

板载 DDR3 芯片（Samsung K4B1G1646G-BCK0, 128MB）通过 Xilinx MIG 7 Series IP 可提供：

| 对比项 | BRAM (当前) | DDR3 (目标) |
|--------|-------------|-------------|
| 容量 | 32KB | **128MB** (4000×) |
| 数据宽度 | 32-bit | 32-bit (AXI 侧) |
| 随机访问延迟 | 1 cycle | ~20-30 cycles (CAS+总线) |
| 突发吞吐 | 1 word/cycle | 1 word/cycle (突发高效) |
| 初始化 | COE 烧入 | 需 bootloader |
| 功耗 | 低 | 较高 |
| 适合场景 | 小程序、快速启动 | 大程序、OS、复杂应用 |

**关键优势**：DDR3 通过 MIG 的 AXI4 接口提供 **32-bit 数据宽度**，与 CPU 天然匹配，无需像 8-bit SRAM 那样做 4 次字节拼接。配合 CPU 的 icache/dcache（写回+写分配），cache 命中时零额外延迟，cache miss 时 DDR3 突发传输可高效填充缓存行。

### 1.3 之前 SRAM 方案为何放弃

板载 SRAM（IDT 71V124SA10TYG）为 128K×8-bit：
- 8-bit 数据宽度 → 32-bit 访问需 4 次顺序字节操作（4× 延迟）
- 10ns 访问时间在 100MHz 下余量为零，必须加等待状态
- 容量仅 128KB，相比 DDR3 的 128MB 微不足道
- 需要手写 async SRAM 控制器，复杂度高

DDR3 + MIG + AHB-Lite AXI Bridge 方案利用 Xilinx 成熟 IP，无需手写存储控制器，且数据宽度天然匹配。

---

## 2. 技术方案

### 2.1 整体架构

```
                         AHB-Lite Bus (100 MHz)
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────┴──────┐ ┌─────┴─────┐ ┌───────┴────────┐
     │  Boot ROM     │ │  Other    │ │  ahblite_axi   │
     │  (BRAM, 4KB)  │ │  Slaves   │ │  _bridge_0     │
     │  0x8000_0000  │ │  PLIC/    │ │  (DDR3 区域)   │
     │               │ │  CLINT/   │ │                │
     │  含 UART      │ │  APB      │ │  S_AHB ← AHB  │
     │  bootloader   │ │           │ │  M_AXI → AXI4 │
     └───────────────┘ └───────────┘ └───────┬────────┘
                                       AXI4  │
                                     ┌───────┴────────┐
                                     │  MIG 7 Series   │
                                     │  (DDR3 控制器)  │
                                     │  S_AXI ← AXI4  │
                                     └───────┬────────┘
                                             │
                                         DDR3 SDRAM
                                        (128 MB)
```

### 2.2 IP 配置

#### MIG 7 Series (`bd_soc_mig_7series_0_1`)

| 属性 | 值 | 来源 |
|------|-----|------|
| IP | `xilinx.com:ip:mig_7series:4.2` | ip_report.md |
| 内存 | MT41J64M16XX-125G (Micron DDR3) | mig_a.prj |
| 容量 | **128 MB** (2^27 bytes) | mig_a.prj C0_MEM_SIZE |
| 数据速率 | 800 Mbps (400 MHz DDR) | TimePeriod=2500ps |
| 参考时钟 | 100 MHz, No Buffer | SystemClock/ReferenceClock |
| AXI 接口 | S_AXI, 27-bit addr, 32-bit data, 8-bit ID | AXIParameters |
| 突发 | 支持窄突发 | SUPPORTS_NARROW_BURST=1 |
| 仲裁 | RD_PRI_REG (读优先注册) | AXIParameters |
| ui_clk | **100 MHz** (与 AHB HCLK 匹配) | MMCM_VCO=800, PHYRatio=4:1 |
| 引脚 | 已在 mig_a.prj 中分配 (SSTL15) | PinSelection |

#### AHB-Lite AXI Bridge (`ahblite_axi_bridge_0`)

| 属性 | 值 | 说明 |
|------|-----|------|
| IP | `xilinx.com:ip:ahblite_axi_bridge:3.0` | ip_report.md |
| S_AHB | 32-bit addr, 32-bit data | AHB-Lite Slave 端 |
| M_AXI | 32-bit addr, 32-bit data | AXI4 Master 端 |
| C_M_AXI_THREAD_ID_WIDTH | **0** | 单主设备，ID 硬连线 0 |
| C_M_AXI_SUPPORTS_NARROW_BURST | **1** | 支持 HSIZE=BYTE/HWORD |
| C_AHB_AXI_TIMEOUT | **0** | 无超时，依赖 MIG 正常响应 |

### 2.3 Bridge ↔ MIG 连接

关键不匹配点及解决方案（详见 `ip_report.md` §4.2）：

| 不匹配 | Bridge M_AXI | MIG S_AXI | 解决 |
|--------|-------------|-----------|------|
| 地址宽度 | 32 bit | 27 bit | 取低 27 位 `awaddr[26:0]` |
| ID 宽度 | 0 (无端口) | 8 bit | 硬连线 `s_axi_awid = 8'h00` |
| QoS | 无 | 4 bit | 硬连线 `s_axi_awqos = 4'h0` |
| Region | 无 | 4 bit | 硬连线 `s_axi_awregion = 4'h0` |

完整端口连接代码见 `ip_report.md` §4.3。

### 2.4 地址映射设计

#### 当前映射

```
HADDR[31:24]  从设备
0x80          SRAM (BRAM, 32KB)
0x0C          PLIC
0x02          CLINT
0x10          APB Bridge (GPIO/UART/Timer/SPI)
其他          Default Slave (ERROR)
```

#### 目标映射

```
HADDR[31:24]  从设备
0x80          Boot ROM (BRAM, 4KB, 含 bootloader)
0x00-0x07     DDR3 (128MB, via ahblite_axi_bridge + MIG)
0x0C          PLIC
0x02          CLINT
0x10          APB Bridge (GPIO/UART/Timer/SPI)
其他          Default Slave (ERROR)
```

**DDR3 地址译码**：

```verilog
// DDR3 区域: HADDR[31:25] == 7'h00 → 0x0000_0000 ~ 0x07FF_FFFF (128MB)
// MIG AXI 地址 = HADDR[26:0] (27 bit, 直接映射)
assign ddr_hsel = (HADDR[31:25] == 7'b000_0000);
```

**Boot ROM 地址译码**：

```verilog
// Boot ROM: HADDR[31:24] == 8'h80 → 0x8000_0000 ~ 0x8000_FFFF (64KB 空间, 实际 4KB)
assign bootrom_hsel = (HADDR[31:24] == 8'h80);
```

**启动流程**：

```
1. FPGA 上电 → CPU PC = 0xFC00_0000 (Boot ROM 起始)
2. MIG 校准中 (init_calib_complete = 0) → Boot ROM 等待
3. MIG 校准完成 (init_calib_complete = 1) → DDR3 自检
   a. 向 DDR3 测试地址写入已知数据 (如 0xDEADBEEF)
   b. fence.i  ← 确保写操作到达 DDR3，防止 dcache 命中返回脏数据
   c. 从同一地址读回数据
   d. 比对：匹配 → GPIO 点亮 LED0；不匹配 → GPIO 点亮所有 LED
   e. 若自检失败，进入死循环（不继续 UART 加载）
4. DDR3 自检通过 → Boot ROM 开始 UART 加载
5. Boot ROM 通过 UART 接收程序数据 → 写入 DDR3 (0x8000_0000 起)
6. 加载完成 → 跳转到 DDR3 (0x8000_0000) 执行
```

> **DDR3 自检说明**：
> - 自检在 UART 加载之前执行，确保 DDR3 链路可用后再加载程序
> - `fence.i` 刷新 icache 并确保 dcache 写回，保证读操作真正访问 DDR3 而非返回 cache 中的脏数据
> - GPIO 操作通过 APB Bridge (0x1000_0000) 访问 LED 寄存器
> - 自检失败时点亮所有 LED 并死循环，避免将程序加载到不可靠的存储中

> **注意**：RISC-V 规范中 `0x8000_0000` 是 DRAM 基址。本方案将 DDR3 映射到 `0x0000_0000`，Boot ROM 在 `0x8000_0000`。这需要修改链接脚本 (`link.ld`) 的基址从 `0x8000_0000` 改为 `0x0000_0000`。或者，可将 DDR3 映射到 `0x8000_0000`（需调整地址译码逻辑，DDR3 占用 `0x8000_0000`~`0x87FF_FFFF`），Boot ROM 放在更高地址如 `0xFC00_0000`。**推荐后者**，保持与 RISC-V 规范一致：

#### 推荐映射（RISC-V 规范兼容）

```
HADDR 区域          从设备
0x8000_0000-0x87FF_FFFF  DDR3 (128MB, via Bridge + MIG)  ← 主存，RISC-V DRAM 基址
0xFC00_0000-0xFC00_0FFF  Boot ROM (4KB BRAM)             ← bootloader
0x0C00_0000-0x0CFF_FFFF  PLIC
0x0200_0000-0x02FF_FFFF  CLINT
0x1000_0000-0x10FF_FFFF  APB Bridge
其他                      Default Slave (ERROR)
```

```verilog
// DDR3: HADDR[31:28] == 4'h8 → 0x8xxx_xxxx (256MB 空间, MIG 用低 27 位)
assign ddr_hsel = (HADDR[31:28] == 4'h8);

// Boot ROM: HADDR[31:20] == 12'hFC0 → 0xFC0xx_xxxx (4KB)
assign bootrom_hsel = (HADDR[31:20] == 12'hFC0);

// PLIC, CLINT, APB: 保持不变
assign plic_hsel   = (HADDR[31:24] == 8'h0C);
assign clint_hsel  = (HADDR[31:24] == 8'h02);
assign apb_hsel    = (HADDR[31:24] == 8'h10);
```

### 2.5 AHB-Lite 总线修改

当前 `ahb_lite_bus.sv` 有 5 个从设备（SLAVE_NUM=5），需增加为 7：

| 索引 | 从设备 | 地址译码 |
|------|--------|----------|
| 0 | **DDR3** (via Bridge) | `HADDR[31:28] == 4'h8` |
| 1 | **Boot ROM** (BRAM) | `HADDR[31:20] == 12'hFC0` |
| 2 | PLIC | `HADDR[31:24] == 8'h0C` |
| 3 | CLINT | `HADDR[31:24] == 8'h02` |
| 4 | APB Bridge | `HADDR[31:24] == 8'h10` |
| 5 | Default Slave | 其他 |

**修改要点**：

1. `SLAVE_NUM` 从 5 改为 6（+1 DDR3，Boot ROM 替换原 SRAM）
2. 原 `slave_HSELx[0]`（SRAM 0x80）改为 DDR3 译码
3. 新增 `slave_HSELx[1]` 为 Boot ROM 译码
4. 原 `slave_HSELx[1-3]`（PLIC/CLINT/APB）顺移为 `[2-4]`
5. Default Slave 为 `[5]`
6. 新增 `ahblite_axi_bridge_0` 实例化，连接 AHB 信号和 AXI 信号
7. 新增 `ahb_bootrom_slave` 实例（类似 `ahb_sram_slave`，但 BRAM 更小且为只读）

### 2.6 AHB-Lite 协议兼容性检查

Bridge 对 AHB-Lite 总线的硬性要求 vs 当前实现：

| 要求 | Bridge 规范 | 当前实现 | 兼容？ |
|------|------------|----------|--------|
| HTRANS 编码 | 00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ | ✅ 完全一致 (ahb_def.svh) | ✅ |
| HBURST 编码 | 标准 AHB-Lite 编码 | ✅ 完全一致 | ✅ |
| HSIZE 编码 | 000=BYTE, 001=HWORD, 010=WORD | ✅ 完全一致 | ✅ |
| HCLK = ui_clk | 100 MHz | ✅ 相同 | ✅ |
| HRESETn 极性 | 低有效 | ✅ 相同 | ✅ |
| HPROT 映射 | → AXI AxPROT | ✅ CPU 发 4'b0011 | ✅ |
| 最大 HSIZE | 010 (WORD) | ✅ CPU 最大 32-bit | ✅ |
| 1KB 边界规则 | INCR 突发不跨 1KB | ⚠️ 需验证 | ⚠️ |
| INCR 突发 | 映射为 AXI INCR len=0 | ❌ CPU 用 INCR8，非 INCR | ✅ |
| WRAP 突发 | 地址对齐 | ❌ CPU 不用 WRAP | ✅ |

**1KB 边界规则验证**：

CPU 的 `cpu_bus_bridge.sv` 发出的 INCR8 突发：
- 起始地址 = cache line 起始（32-byte 对齐）
- INCR8 = 8 × 4-byte = 32-byte
- 32-byte < 1KB，且起始地址 32-byte 对齐
- **结论：INCR8 突发不会跨越 1KB 边界** ✅

**突发映射**：

| CPU 发出 | Bridge 转换 | MIG 接收 |
|----------|------------|----------|
| SINGLE (MMIO/PTW) | AXI INCR, len=0 | 单拍读写 |
| INCR8 (cache refill/wb) | AXI INCR, len=7 | 8 拍突发读写 |

### 2.7 程序加载方案

#### Boot ROM 设计

Boot ROM 为小型 BRAM IP（4KB），COE 初始化 UART bootloader，地址 `0xFC00_0000`。

**Bootloader 流程**（汇编，~1-2KB）：

```
1. _start: 等待 MIG init_calib_complete = 1
2. DDR3 自检:
   a. li t0, 0xDEADBEEF
   b. sw t0, 0(DDR3_BASE)        # 写入 DDR3 测试地址
   c. fence.i                     # 确保 dcache 写回 + icache 刷新
   d. lw t1, 0(DDR3_BASE)        # 读回
   e. beq t0, t1, ddr_ok         # 比对
   f. # 不匹配: GPIO 点亮所有 LED → 死循环
      li t2, 0xFF
      sw t2, 0(GPIO_LED_ADDR)
      j .
   g. ddr_ok: GPIO 点亮 LED0
3. 初始化 UART (波特率 115200)
4. 通过 UART 接收头部：
   - 魔数 (4 byte): 0xRISC
   - 程序长度 (4 byte): N bytes
   - 加载地址 (4 byte): 默认 0x8000_0000
   - 入口地址 (4 byte): 默认 0x8000_0000
5. 循环接收 N bytes → 写入 DDR3 (从加载地址起)
6. 跳转到入口地址执行
```

> **关键点**：
> - DDR3 自检在 UART 初始化之前执行，尽早验证 DDR3 链路
> - `fence.i` 确保 sw 的数据已写回 DDR3（dcache write-back），lw 从 DDR3 读取而非命中 dcache 脏行
> - GPIO LED 通过 APB Bridge (0x1000_0000 区域) 访问
> - 自检失败死循环防止将程序加载到不可靠存储

**主机端加载脚本**（基于 `tools/uart_console.py`）：

```python
# uart_load.py — 通过 UART 加载程序到 DDR3
import serial, struct, sys

def load_program(port, hex_file, baud=115200):
    ser = serial.Serial(port, baud)
    program = parse_hex(hex_file)  # 读取 .hex 文件

    # 发送头部
    ser.write(struct.pack('<I', 0x52495343))  # 魔数 "RISC"
    ser.write(struct.pack('<I', len(program)))  # 程序长度
    ser.write(struct.pack('<I', 0x80000000))    # 加载地址
    ser.write(struct.pack('<I', 0x80000000))    # 入口地址

    # 发送程序数据
    ser.write(program)
    ser.flush()
    print(f"Loaded {len(program)} bytes to DDR3")
```

#### 仿真中的程序加载

仿真中不需要 UART bootloader。直接通过 BRAM 行为模型加载：
- Boot ROM：COE 初始化（含 bootloader 代码）
- DDR3：MIG 仿真模型 + testbench 中通过 AHB 总线直接写入程序
- 或：testbench 等待 `init_calib_complete` 后通过 AHB 写入程序到 DDR3 区域

### 2.8 system_top.sv 修改

需要添加的顶层端口：

```verilog
module system_top(
    // ... 现有端口 ...

    // DDR3 引脚 (来自 MIG)
    output        ddr3_reset_n,
    output [0:0]  ddr3_ck_p,
    output [0:0]  ddr3_ck_n,
    output        ddr3_cke,
    output        ddr3_ras_n,
    output        ddr3_cas_n,
    output        ddr3_we_n,
    output [2:0]  ddr3_ba,
    output [12:0] ddr3_addr,
    output [1:0]  ddr3_dm,
    inout  [15:0] ddr3_dq,
    inout  [1:0]  ddr3_dqs_p,
    inout  [1:0]  ddr3_dqs_n,
    output [0:0]  ddr3_odt,

    // MIG 状态
    output        init_calib_complete  // DDR3 校准完成指示
);
```

### 2.9 约束文件修改

`dev/fpga/cpu.xdc` 需添加 DDR3 引脚约束（引脚分配已在 `mig_a.prj` 中，MIG IP 会自动生成约束）。额外需要：

```tcl
# MIG 系统时钟 (100 MHz 差分, 用于 DDR3 参考时钟)
# 注意: 如果与现有 clk 共用同一 100MHz 晶振, 需确认 MIG 的 sys_clk_i 连接
# MIG 的 sys_clk_i 和 clk_ref_i 可能需要差分时钟对

# MIG 复位
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst]

# init_calib_complete 指示 (可选, 连接到 LED)
# set_property IOSTANDARD LVCMOS33 [get_ports init_calib_complete]
```

> **重要**：MIG IP 的 DDR3 引脚约束由 `mig_a.prj` 中的 PinSelection 自动生成，**不需要手动在 XDC 中添加 DDR3 引脚约束**。但需确认 MIG 的 `sys_clk_i` 和 `sys_rst` 连接。

---

## 3. AHB-Lite 总线特性与 Bridge 兼容性详析

### 3.1 当前 AHB 总线使用的特性

| 特性 | 使用情况 | Bridge 支持 |
|------|----------|------------|
| HTRANS=IDLE (00) | ✅ 空闲/突发结束 | ✅ |
| HTRANS=BUSY (01) | ❌ 未使用 | ✅ Bridge 忽略 |
| HTRANS=NONSEQ (10) | ✅ 突发首拍/单拍 | ✅ |
| HTRANS=SEQ (11) | ✅ 突发后续拍 | ✅ |
| HBURST=SINGLE (000) | ✅ MMIO/PTW | ✅ → AXI INCR len=0 |
| HBURST=INCR8 (101) | ✅ cache refill/wb | ✅ → AXI INCR len=7 |
| HBURST=INCR (001) | ❌ 未使用 | ⚠️ → AXI len=0, 部分互连不支持 |
| HBURST=WRAP* | ❌ 未使用 | ✅ Bridge 支持 |
| HSIZE=BYTE (000) | ✅ dcache MMIO byte | ✅ narrow burst |
| HSIZE=HWORD (001) | ✅ dcache MMIO halfword | ✅ narrow burst |
| HSIZE=WORD (010) | ✅ 主流使用 | ✅ |
| HPROT=4'b0011 | ✅ 始终 | ✅ → AxPROT |
| HMASTLOCK=0 | ✅ 始终 | ✅ → AxLOCK=0 |
| HRESP=OKAY/ERROR | ✅ 错误处理 | ✅ SLVERR/DECERR→ERROR |
| Wait states | ✅ HREADY 反压 | ✅ → AXI xREADY |

### 3.2 关键注意事项

1. **INCR 突发避免**：CPU 不使用 INCR（未定义长度），仅用 INCR8 和 SINGLE，Bridge 映射正确
2. **突发提前终止**：CPU 的 `cpu_bus_bridge.sv` 在 INCR8 突发中，最后一拍 HTRANS 从 SEQ 变为 IDLE。Bridge 会用 dummy 传输（wstrb=0）完成剩余拍数，**不会误写 DDR3**
3. **1KB 边界**：INCR8 突发 = 32 bytes，cache line 32-byte 对齐，**不跨 1KB 边界**
4. **MIG 校准**：`init_calib_complete` 为低时，Bridge 的 AXI 请求会被 MIG 阻塞（awready/wready/arready 为低），AHB 侧表现为 HREADYOUT=0（等待状态）。**CPU 会被自然反压，无需额外逻辑**——但为安全起见，Boot ROM 应显式等待 `init_calib_complete`

---

## 4. 实施计划

### 阶段 1：Vivado Orchestrator IP 扩展 + 示例工程验证（~5 天）

> **目标**：修改 Orchestrator 工具支持 MIG + Bridge + Clocking Wizard IP 生成，生成示例工程后**停止等待手动检查**。

| 步骤 | 内容 | 产出 |
|------|------|------|
| 1.1 | 扩展 `vivado_config.yaml`：新增 `ddr3` 配置段（MIG 参数 + Bridge 参数 + clk_wiz 参数），参数严格按 `mig_a.prj` 填写 | YAML 配置 |
| 1.2 | 扩展 `tools/vivado_core/config.py`：新增 `Ddr3Config`、`AhbBridgeConfig`、`ClkWizConfig` 数据类 | Python 数据类 |
| 1.3 | 扩展 `tools/vivado_core/ip_gen.py`：新增 `generate_mig_create_ip_tcl()`、`generate_bridge_create_ip_tcl()`、`generate_clkwiz_create_ip_tcl()` 函数，在 `generate_all_ip_tcl()` 中调用 | IP 生成逻辑 |
| 1.4 | 扩展 `tools/vivado_core/operations.py`：`_tcl_setup_ip()` 中新增 MIG + Bridge + clk_wiz 的 create_ip + generate_target TCL | 操作流水线 |
| 1.5 | 更新 `tools/vivado_core/cache_header_gen.py`：`cache_def.svh` 新增 DDR3 相关常量（地址宽度、基地址等） | 头文件生成 |
| 1.6 | **生成示例工程**：运行 `python -m tools.vivado_cli -task ddr3_test -create`，仅生成工程和 IP，**不仿真不综合** | Vivado 工程 |
| 1.7 | ⏸ **停止，手动检查**：在 Vivado GUI 中打开示例工程，逐个检查 IP 配置是否正确：MIG 引脚/时序、Bridge ID_WIDTH/narrow_burst、clk_wiz 频率/MMCM 参数 |  手动验证 |
| 1.8 | 手动验证通过后，编写 Bridge ↔ MIG 连接模块 `ddr3_bridge_wrapper.sv` | RTL 文件 |
| 1.9 | 编写 DDR3 独立测试 testbench：通过 AHB 写入模式 → 读回 → 比对 | `tb_ddr3_basic.sv` |
| 1.10 | 仿真验证 DDR3 读写基本功能 | 仿真 PASS |

**vivado_config.yaml 新增内容**：

```yaml
memory:
  # ... 现有 sram/icache/dcache/tlb 配置 ...

  ddr3:
    enabled: true
    ip_name: bd_soc_mig_7series_0_1
    ip_version: "4.2"
    mig_prj_file: "Reference/mig/mig_a.prj"  # MIG 引脚/时序配置
    mem_size: 134217728          # 128MB (来自 mig_a.prj C0_MEM_SIZE)
    axi_addr_width: 27           # AXI 地址宽度 (来自 mig_a.prj)
    axi_data_width: 32           # AXI 数据宽度
    axi_id_width: 8              # AXI ID 宽度
    supports_narrow_burst: true  # 支持窄突发
    data_rate: 800               # Mbps
    input_clk_freq: 100          # MHz

  ahb_bridge:
    enabled: true
    ip_name: ahblite_axi_bridge_0
    ip_version: "3.0"
    thread_id_width: 0           # 单主设备, ID 硬连线 0
    supports_narrow_burst: true   # 支持 HSIZE=BYTE/HWORD
    timeout: 0                   # 无超时

  clk_wiz:
    enabled: true
    ip_name: clk_wiz_0
    ip_version: "6.0"
    prim_in_freq: 100.0          # MHz, 外部晶振
    mmcm_clkin_period: 10.0      # ns
    mmcm_clkfbout_mult_f: 10.0   # VCO = 1000MHz
    mmcm_divclk_divide: 1
    num_out_clks: 2
    clk_out1_freq: 100.0         # MHz, clk_system (备用)
    clk_out2_freq: 200.0         # MHz, clk_ddr_ref → MIG clk_ref_i
    reset_type: ACTIVE_LOW
```

**ip_gen.py 新增函数要点**：

```python
def generate_mig_create_ip_tcl(cfg: Ddr3Config, ip_dir: str) -> str:
    """MIG 7 Series IP: 核心配置由 XML_INPUT_FILE (mig_a.prj) 决定"""
    # create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2
    # set_property CONFIG.XML_INPUT_FILE {mig_a.prj 路径}
    # set_property CONFIG.RESET_BOARD_INTERFACE {Custom}
    # ⚠️ mig_a.prj 路径必须为绝对路径或相对于 Vivado 工程的正确路径

def generate_bridge_create_ip_tcl(cfg: AhbBridgeConfig, ip_dir: str) -> str:
    """AHB-Lite AXI Bridge IP"""
    # create_ip -name ahblite_axi_bridge -vendor xilinx.com -library ip -version 3.0
    # set_property CONFIG.C_M_AXI_THREAD_ID_WIDTH {0}
    # set_property CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {1}

def generate_clkwiz_create_ip_tcl(cfg: ClkWizConfig, ip_dir: str) -> str:
    """Clocking Wizard IP: 生成 200MHz DDR 参考时钟"""
    # create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0
    # set_property CONFIG.CLK_IN1_BOARD_INTERFACE {Custom}
    # set_property CONFIG.PRIM_IN_FREQ {100.000}
    # set_property CONFIG.MMCM_CLKFBOUT_MULT_F {10.000}
    # set_property CONFIG.MMCM_DIVCLK_DIVIDE {1}
    # set_property CONFIG.CLK_OUT1_REQUESTED_OUT_FREQ {100.000}
    # set_property CONFIG.CLK_OUT2_REQUESTED_OUT_FREQ {200.000}
    # set_property CONFIG.NUM_OUT_CLKS {2}
    # set_property CONFIG.RESET_TYPE {ACTIVE_LOW}
```

> **⚠️ MIG 参数必须严格按 `mig_a.prj`**：MIG IP 的核心配置（引脚分配、时序参数、内存型号、Bank 选择）全部由 `mig_a.prj` 的 `XML_INPUT_FILE` 决定。`ip_gen.py` 只需设置 `CONFIG.XML_INPUT_FILE` 和 `CONFIG.RESET_BOARD_INTERFACE`，**不要尝试在 TCL 中覆盖 mig_a.prj 内的任何参数**。

### 阶段 2：AHB 总线集成（~4 天）

| 步骤 | 内容 | 产出 |
|------|------|------|
| 2.1 | 修改 `ahb_lite_bus.sv`：SLAVE_NUM 5→6，新增 DDR3 从设备译码 | 总线修改 |
| 2.2 | 将原 SRAM slave (0x80) 改为 Boot ROM slave（更小 BRAM，只读） | `ahb_bootrom_slave.sv` |
| 2.3 | 实例化 `ahblite_axi_bridge_0` + `ddr3_bridge_wrapper` 在总线中 | Bridge 集成 |
| 2.4 | 修改 `system_top.sv`：连接 DDR3 引脚、init_calib_complete | 顶层修改 |
| 2.5 | 修改 `cpu.xdc`：DDR3 IOSTANDARD 约束 | 约束文件 |

### 阶段 2.5：DDR3 仿真验证（~3 天）

> **目标**：参考 Xilinx MIG example project (`project/bd_soc_mig_7series_0_1_ex/`)，验证 DDR3 链路和 AHB→AXI→DDR3 通路。

| 步骤 | 内容 | 产出 |
|------|------|------|
| 2.5.1 | 编写 `tb_ddr3_mig_ex.sv`：MIG+ddr3_model+WireDelay+AXI4 BFM | Phase 1 仿真 TB |
| 2.5.2 | 编写 `tb_ddr3_ahb_ex.sv`：ddr3_bridge_wrapper+ddr3_model+WireDelay+AHB BFM | Phase 2 仿真 TB |
| 2.5.3 | 编写 `run_ddr3_sim.tcl`：Vivado 批处理仿真脚本 | 仿真脚本 |
| 2.5.4 | 运行 Phase 1 仿真：MIG 校准 + AXI4 读写验证 | MIG 链路 PASS |
| 2.5.5 | 运行 Phase 2 仿真：AHB→Bridge→MIG 全通路读写验证 | 全通路 PASS |

**仿真架构**：

```
tb_ddr3_mig_ex.sv (Phase 1: MIG 链路)
  AXI4 BFM → MIG → WireDelay → ddr3_model

tb_ddr3_ahb_ex.sv (Phase 2: 全通路)
  AHB BFM → Bridge → MIG → WireDelay → ddr3_model
```

**关键设计决策**（与 Xilinx 示例对齐）：
- `timescale 1ps/100fs`（匹配 Xilinx 示例，MIG 内部时序以 ps 为单位）
- WireDelay 用于 DQ/DQS 双向总线建模
- `SIM_BYPASS_INIT_CAL=FAST`（完整校准 ~50µs，FAST ~2µs）
- `RST_ACT_LOW=1`，`aresetn <= ~ui_clk_sync_rst`

**依赖源文件**：
- Xilinx 示例：`ddr3_model.sv`, `ddr3_model_parameters.vh`, `wiredly.v`, `glbl.v`
- MIG user_design：`bd_soc_mig_7series_0_1.v` + ~100 子模块
- 项目 RTL：`ddr3_bridge_wrapper.sv`, `ahb_def.svh`

### 阶段 3：Bootloader 实现（~4 天）

| 步骤 | 内容 | 产出 |
|------|------|------|
| 3.1 | 编写 DDR3 自检汇编：等待 init_calib_complete → 写 DDR3 → fence.i → 读回 → 比对 → GPIO LED 指示 | 自检代码段 |
| 3.2 | 编写 UART bootloader 汇编（~1-2KB），含 DDR3 自检作为第一步 | `bootloader.s` |
| 3.3 | 编译 bootloader → COE → 初始化 Boot ROM BRAM IP | `bootloader.coe` |
| 3.4 | 编写主机端 UART 加载脚本 `tools/uart_load.py` | Python 脚本 |
| 3.5 | 仿真验证：DDR3 自检（写→fence.i→读→比对→LED） | 自检仿真 PASS |
| 3.6 | 仿真验证：完整 bootloader 流程（自检 → UART 接收 → DDR3 写入 → 跳转） | 仿真 PASS |

### 阶段 4：全系统验证（~3 天）

| 步骤 | 内容 | 产出 |
|------|------|------|
| 4.1 | 修改链接脚本 `link.ld`：基址保持 `0x8000_0000`（DDR3 区域） | 链接脚本 |
| 4.2 | 运行现有 ISA 测试程序通过 DDR3（uart_load 加载 → DDR3 执行） | ISA 测试 PASS |
| 4.3 | 运行集成测试（cpu_full, cpu_trap, led_marquee, uart_hello） | 集成测试 PASS |
| 4.4 | 性能测量：DDR3 访问延迟 vs BRAM，cache miss rate 影响 | 性能报告 |

### 阶段 5：优化与清理（~2 天）

| 步骤 | 内容 | 产出 |
|------|------|------|
| 5.1 | 评估是否移除 BRAM SRAM IP（完全依赖 DDR3） | 配置清理 |
| 5.2 | 更新 `vivado_config.yaml`：sram 段改为 Boot ROM 配置 | 配置更新 |
| 5.3 | 更新 `tools/vivado_core/ip_gen.py`：生成 Boot ROM BRAM IP | 工具更新 |
| 5.4 | 更新设计报告 `simpleCPU-design-report.md` | 文档更新 |

**总工作量估计：~18 天**

---

## 5. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| MIG 校准失败 | 中 | 高 | 检查 mig_a.prj 引脚分配与 PCB 一致；确认 clk_ref_i 200MHz 参考时钟连接 |
| Bridge 协议不兼容 | 低 | 高 | 已逐项验证 AHB-Lite 特性兼容性（§3.1-3.2） |
| DDR3 访问延迟导致 CPU 性能严重下降 | 中 | 中 | Cache 命中时零额外延迟；仅 cache miss 受影响；可调整 cache 几何 |
| Boot ROM 容量不足 | 低 | 低 | 4KB 足够放 UART bootloader；不够可扩至 8KB |
| UART 加载速度慢 | 低 | 低 | 115200 baud ≈ 10KB/s，32KB 程序 ~3s；可提高波特率 |
| 时序不收敛 | 中 | 高 | DDR3 引脚 SSTL15 + MIG 内部时序约束；可能需要降频或调整 MMCM |
| MIG sys_clk 与 AHB HCLK 冲突 | 中 | 高 | Bridge 要求 HCLK = ui_clk；系统时钟改为 MIG ui_clk 输出 |
| **MIG clk_ref_i 缺失 200MHz** | **高** | **高** | **必须通过 Clocking Wizard 从 100MHz 生成 200MHz 参考时钟**；参考项目已验证此方案 |
| Clocking Wizard MMCM 不锁定 | 低 | 高 | 检查 VCO 频率在 MMCM 允许范围（600-1200MHz for Artix-7）；1000MHz 在范围内 |

### 关键时钟架构决策（参考项目验证）

#### 参考项目时钟架构（nontrivial-mips, 同一开发板）

参考项目 `E:\Xprogram\git\nontrivial-mips-master\vivado` 使用 Vivado 块设计（Block Design），其时钟架构如下：

**Clocking Wizard IP** (`main_mmcm` = `clk_wiz:6.0`)：
- 输入：100MHz 外部晶振 (AC19)
- MMCM VCO = 100MHz × 10 = 1000MHz
- 输出时钟：
  - `clk_cpu` = 80MHz (MMCM_CLKOUT0_DIVIDE_F=12.5)
  - `clk_ddr_ref` = **200MHz** (MMCM_CLKOUT1_DIVIDE=5) → MIG `clk_ref_i`
  - `clk_vga` = 25MHz (MMCM_CLKOUT2_DIVIDE=40)
  - `clk_spi` = 20MHz (MMCM_CLKOUT3_DIVIDE=50)
  - `clk_peripheral` = **100MHz** (MMCM_CLKOUT4_DIVIDE=10) → MIG `sys_clk_i`

**MIG 连接**：
- `sys_clk_i` ← `main_mmcm/clk_peripheral` (100MHz)
- `clk_ref_i` ← `main_mmcm/clk_ddr_ref` (200MHz)
- `ui_clk` → 暴露为外部端口（100MHz 输出）

**复位管理**：`proc_sys_reset:5.0` IP + 自定义 `reset_synchronizer` 模块

**关键发现**：
1. ⚠️ **MIG 的 `clk_ref_i` 需要 200MHz 参考时钟**，不能仅用 100MHz！参考项目通过 Clocking Wizard 从 100MHz 生成 200MHz
2. `mig_a.prj` 中 `SystemClock=No Buffer, ReferenceClock=No Buffer` 表示 MIG 不内部缓冲时钟，**需要外部提供 200MHz 参考时钟**
3. 参考项目无 `ahblite_axi_bridge`（其 CPU 直接使用 AXI 接口）

#### 本项目时钟方案

```
FPGA 外部 100MHz 晶振 (AC19)
  │
  ├── clk_wiz_0 (Clocking Wizard IP)
  │     ├── clk_in1  ← 100MHz (外部晶振)
  │     ├── clk_out1 = 100MHz (clk_system, 备用)
  │     └── clk_out2 = 200MHz (clk_ddr_ref) → MIG clk_ref_i
  │
  ├── MIG 7 Series
  │     ├── sys_clk_i  ← 100MHz (外部晶振, No Buffer)
  │     ├── clk_ref_i  ← 200MHz (clk_wiz_0 clk_out2)
  │     ├── sys_rst    ← ~resetn (低有效)
  │     └── ui_clk     → 100MHz (输出, 驱动 AHB HCLK)
  │
  └── 系统时钟 = MIG ui_clk (100MHz)
        ├── AHB-Lite HCLK
        ├── CPU core clk
        ├── ahblite_axi_bridge s_ahb_hclk
        └── 所有 AHB/APB 从设备
```

**Clocking Wizard IP 配置**（`clk_wiz_0`）：

| 参数 | 值 | 说明 |
|------|-----|------|
| IP | `xilinx.com:ip:clk_wiz:6.0` | Clocking Wizard |
| PRIM_IN_FREQ | 100.000 MHz | 输入频率 |
| MMCM_CLKFBOUT_MULT_F | 10.000 | VCO = 1000MHz |
| MMCM_DIVCLK_DIVIDE | 1 | |
| CLK_OUT1_FREQ | 100.000 MHz | clk_system (备用) |
| CLK_OUT2_FREQ | **200.000 MHz** | clk_ddr_ref → MIG |
| NUM_OUT_CLKS | 2 | |
| RESET_TYPE | ACTIVE_LOW | |
| USE_LOCKED | true | MMCM locked 输出 |

**关键约束**：
- **Bridge 硬性要求**：`s_ahb_hclk = MIG ui_clk`（PG176 §7.1）
- 因此整个系统时钟必须来自 MIG 的 `ui_clk` 输出，不能直接用外部晶振
- MIG 校准期间 `ui_clk` 仍然运行（是有效时钟），但 DDR3 访问会被反压
- CPU 从 Boot ROM 启动时，DDR3 访问自然 stall 直到 `init_calib_complete=1`

**system_top.sv 时钟连接**：

```verilog
// 外部时钟和复位
input  wire ext_clk,      // 100MHz 外部晶振 (AC19)
input  wire resetn,        // 低有效复位 (Y3)

// Clocking Wizard: 生成 200MHz DDR 参考时钟
wire clk_100mhz;           // clk_wiz clk_out1 (100MHz, 备用)
wire clk_ddr_ref;          // clk_wiz clk_out2 (200MHz → MIG)
wire mmcm_locked;          // clk_wiz locked

clk_wiz_0 u_clk_wiz (
    .clk_in1   (ext_clk),
    .clk_out1  (clk_100mhz),
    .clk_out2  (clk_ddr_ref),
    .resetn    (resetn),
    .locked    (mmcm_locked)
);

// MIG: DDR3 控制器
wire ui_clk;               // MIG 输出 100MHz → 系统主时钟
wire aresetn;              // MIG AXI 复位
wire init_calib_complete;  // DDR3 校准完成

bd_soc_mig_7series_0_1 u_mig (
    .sys_clk_i       (ext_clk),          // 100MHz 外部晶振
    .clk_ref_i       (clk_ddr_ref),      // 200MHz 参考时钟
    .sys_rst         (~resetn),          // 低有效复位
    .ui_clk          (ui_clk),           // 输出 100MHz
    .aresetn         (aresetn),
    .init_calib_complete(init_calib_complete),
    // ... DDR3 引脚 + AXI 接口 ...
);

// 系统主时钟 = MIG ui_clk
// 所有模块 (CPU, AHB bus, Bridge, peripherals) 使用此时钟
wire clk = ui_clk;
```

> ⚠️ **时钟源变更**：当前 `system_top.clk` 直接来自外部晶振，修改后来自 MIG 的 `ui_clk`（MMCM 输出）。这引入了时钟延迟和抖动，但保证了 Bridge 的时钟一致性。需要在约束文件中正确处理此时钟关系。

---

## 6. 文件修改清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `dev/rtl/system_top.sv` | 修改 | 添加 DDR3 引脚、MIG 实例、时钟改为 ui_clk、init_calib_complete |
| `dev/rtl/AHB-lite/ahb_lite_bus.sv` | 修改 | SLAVE_NUM+1、DDR3 译码、Bridge 实例、Boot ROM 替换 SRAM |
| `dev/rtl/AHB-lite/ahb_sram_slave.sv` | 修改/保留 | 改为 Boot ROM（只读、更小 BRAM）或新建 `ahb_bootrom_slave.sv` |
| 新增 `dev/rtl/AHB-lite/ddr3_bridge_wrapper.sv` | 新建 | Bridge ↔ MIG 连接逻辑（地址截取、ID 硬连线等） |
| 新增 `dev/program_source/boot/bootloader.s` | 新建 | UART bootloader 汇编源码 |
| 新增 `tools/uart_load.py` | 新建 | 主机端 UART 程序加载脚本 |
| `dev/fpga/cpu.xdc` | 修改 | MIG 时钟/复位约束（DDR3 引脚由 MIG 自动生成） |
| `vivado_config.yaml` | 修改 | 新增 ddr3/ahb_bridge/clk_wiz 配置段，sram 段改为 Boot ROM |
| `tools/vivado_core/config.py` | 修改 | 新增 Ddr3Config/AhbBridgeConfig/ClkWizConfig 数据类 |
| `tools/vivado_core/ip_gen.py` | 修改 | 新增 MIG + Bridge + clk_wiz IP 生成函数 |
| `tools/vivado_core/operations.py` | 修改 | setup_ip TCL 包含 MIG + Bridge + clk_wiz |
| `tools/vivado_core/cache_header_gen.py` | 修改 | cache_def.svh 新增 DDR3 地址/基地址常量 |
| `dev/program_source/link.ld` | 修改 | 基址保持 0x8000_0000（DDR3 区域） |
| 新增 `dev/tb/tb_ddr3_basic.sv` | 新建 | DDR3 基本读写测试 testbench |
| 新增 `dev/tb/tb_ddr3_mig_ex.sv` | 新建 | Phase 1: MIG+ddr3_model+WireDelay+AXI4 BFM 仿真 |
| 新增 `dev/tb/tb_ddr3_ahb_ex.sv` | 新建 | Phase 2: AHB→Bridge→MIG+WireDelay+AHB BFM 仿真 |
| 新增 `dev/tb/run_ddr3_sim.tcl` | 新建 | Vivado 批处理仿真脚本 |

---

## 7. 参考资料

| 文档 | 编号 | 位置 |
|------|------|------|
| MIG + Bridge 联合配置报告 | — | `Reference/mig/ip_report.md` |
| MIG 项目文件 (引脚/时序) | — | `Reference/mig/mig_a.prj` |
| MIG 生成脚本 | — | `Reference/mig/gen_ddr_controller.tcl` |
| AHB-Lite to AXI4 Bridge PG | PG176 | [docs.amd.com/v/u/en-US/pg176-ahblite-axi-bridge](https://docs.amd.com/v/u/en-US/pg176-ahblite-axi-bridge) |
| AMBA 3 AHB-Lite 协议 | IHI 0033 | ARM 官方 |
| MIG 7 Series UG | UG586 | Xilinx |
| AXI Reference Guide | UG1037 | Xilinx |
| **参考项目 (同开发板)** | — | `E:\Xprogram\git\nontrivial-mips-master\vivado` |
| 参考项目块设计 | — | `NonTrivialMIPS.srcs/sources_1/bd/bd_soc/bd_soc.bd` |
| 参考项目时钟约束 | — | `NonTrivialMIPS.srcs/constrs_1/new/io_timings.xdc` |
| CPU 设计报告 | — | `dev/docs/simpleCPU-design-report.md` |
| FPGA 基硎信息 | — | `Reference/FPGA基础信息.md` |
| 引脚表 | — | `Reference/pins.csv` |
