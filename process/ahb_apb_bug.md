# 总线系统信号协议合规性分析报告

> 分析日期：2026-06-08
> 规范依据：ARM IHI0033A (AMBA 3 AHB-Lite v1.0)、ARM IHI0024E (AMBA APB Issue E)
> 分析范围：`dev/rtl/AHB-lite/`、`dev/rtl/APB/`、`dev/rtl/core/cpu_bus_bridge.sv`

---

## 一、AHB-Lite 协议合规性

### 1.1 信号完整性检查

| 规范要求 | 实现 | 状态 |
|---------|------|------|
| **全局信号** | | |
| HCLK | 所有模块均存在 | ✅ |
| HRESETn (低电平有效) | 所有模块使用 `negedge HRESETn` | ✅ |
| **主设备信号** | | |
| HADDR[31:0] | `cpu_bus_bridge` 输出 | ✅ |
| HBURST[2:0] | `cpu_bus_bridge` 输出 (SINGLE/INCR8) | ✅ |
| HMASTLOCK | `cpu_bus_bridge` 输出 (常量0) | ✅ |
| HPROT[3:0] | `cpu_bus_bridge` 输出 (常量4'b0011) | ✅ |
| HSIZE[2:0] | `cpu_bus_bridge` 输出 | ✅ |
| HTRANS[1:0] | `cpu_bus_bridge` 输出 | ✅ |
| HWDATA[31:0] | `cpu_bus_bridge` 输出 | ✅ |
| HWRITE | `cpu_bus_bridge` 输出 | ✅ |
| **从设备信号** | | |
| HRDATA[31:0] | 所有从设备输出 | ✅ |
| HREADYOUT | 所有从设备输出 | ✅ |
| HRESP | 所有从设备输出 | ✅ |
| **互连信号** | | |
| HSELx | `ahb_lite_bus` 译码逻辑生成 | ✅ |
| HREADY (全局) | `ahb_mux` 输出 | ✅ |

### 1.2 编码定义验证

| 信号 | 规范编码 | `ahb_def.svh` 定义 | 状态 |
|------|---------|-------------------|------|
| HTRANS IDLE | 2'b00 | `AHB_TRANS_IDLE = 2'b00` | ✅ |
| HTRANS BUSY | 2'b01 | `AHB_TRANS_BUSY = 2'b01` | ✅ |
| HTRANS NONSEQ | 2'b10 | `AHB_TRANS_NONSEQ = 2'b10` | ✅ |
| HTRANS SEQ | 2'b11 | `AHB_TRANS_SEQ = 2'b11` | ✅ |
| HBURST SINGLE | 3'b000 | `AHB_BURST_SINGLE = 3'b000` | ✅ |
| HBURST INCR | 3'b001 | `AHB_BURST_INCR = 3'b001` | ✅ |
| HBURST WRAP4/INCR4/... | 3'b010-3'b111 | 全部匹配 | ✅ |
| HSIZE BYTE/HWORD/WORD | 3'b000/001/010 | 匹配 | ✅ |
| HRESP OKAY/ERROR | 1'b0/1'b1 | 匹配 | ✅ |

### 1.3 关键协议规则合规性

#### ✅ 复位行为

- 规范：复位期间主设备必须驱动 `HTRANS=IDLE`，从设备必须驱动 `HREADYOUT=HIGH`
- `cpu_bus_bridge`：复位时 `htrans_r <= AHB_TRANS_IDLE` ✅
- 所有从设备：复位时 `HREADYOUT <= 1'b1` ✅

#### ✅ 2周期 ERROR 响应

- 规范：ERROR 必须为2周期 — 第一周期 `HRESP=ERROR, HREADY=LOW`；第二周期 `HRESP=ERROR, HREADY=HIGH`
- `ahb_default_slave`：使用 `error_phase` 标志正确实现 ✅
- `ahb_lite_to_apb`：使用 `error_phase` 标志正确实现 ✅

#### ✅ IDLE/BUSY 零等待 OKAY 响应

- 规范：IDLE 和 BUSY 传输必须以零等待状态 OKAY 响应
- `ahb_default_slave`：`ahb_transfer = HSEL & HREADY & HTRANS[1]` 仅对 NONSEQ/SEQ 生效，IDLE/BUSY 走默认路径 `HREADYOUT=1, HRESP=0` ✅
- `ahb_sram_slave`：第112-117行显式处理 IDLE/BUSY ✅
- `ahb_bootrom_slave`：第129-134行显式处理 ✅
- 零等待从设备 (PLIC/CLINT/SysStatus)：`HREADYOUT=1` 常量 ✅

#### ✅ HSELx 流水线锁存

- 规范：多路选择器必须使用地址阶段的 HSELx，而非当前 HADDR
- `ahb_lite_bus` 第114-120行：在 `HREADY && HTRANS!=IDLE` 时锁存 `mux_HSELx` ✅
- `HTRANS!=IDLE` 门控防止空闲相位腐蚀（已修复的已知 BUG）✅

#### ✅ 写数据时序

- 规范：HWDATA 在数据阶段驱动（地址阶段后一周期）
- `cpu_bus_bridge`：MMIO 写在 `S_MMIO_ADDR` → `S_MMIO_DATA` 时更新 `hwdata_r` ✅
- 写回写在 `S_WB_ADDR` → `S_WB_DATA` 时更新 ✅

#### ✅ 等待状态期间 HWDATA 稳定

- `hwdata_r` 仅在 `HREADY` 跳变时更新 ✅

#### ✅ 突发期间控制信号稳定

- INCR8 突发期间：`hwrite_r`, `hsize_r`, `hburst_r` 不变 ✅

#### ✅ 默认从设备行为

- 规范：NONSEQ/SEQ 访问未映射地址 → ERROR；IDLE/BUSY → 零等待 OKAY
- `ahb_default_slave`：正确实现 ✅

#### ✅ 最小 1KB 地址空间

- 所有从设备地址空间 ≥ 16MB ✅

### 1.4 AHB-Lite 发现的问题

#### ⚠️ 问题 1：`mux_HSELx` 初始化值导致 DDR3 未校准时总线死锁风险

**位置**：`ahb_lite_bus.sv` 第117行

```systemverilog
mux_HSELx <= 7'b0000001;  // Default to DDR3 bridge (slave 0)
```

**分析**：复位后 `mux_HSELx` 指向 DDR3 从设备。若 DDR3 未校准完成（`init_calib_complete=0`），DDR3 的 `HREADYOUT=0`，导致全局 `HREADY=0`。由于锁存条件需要 `HREADY=1`，`mux_HSELx` 无法更新，**整个总线死锁**——即使 CPU 访问 BootROM 或 CLINT 也无法完成。

**当前缓解**：`system_top.sv` 的3阶段复位序列确保 CPU 在 DDR3 校准完成后才释放复位，因此在实际系统中不会触发。

**建议修复**：将初始化改为 `7'b0000000`。当无从设备被选中时，`ahb_mux` 默认输出 `HREADY=1`（见第21行），第一个 NONSEQ 传输到来时锁存条件满足，`mux_HSELx` 正确更新。

---

#### ⚠️ 问题 2：从设备接口不一致

部分从设备缺少完整的 AHB-Lite 端口：

| 从设备 | 缺少端口 | 影响 |
|--------|---------|------|
| `ahb_plic` | HBURST, HPROT | 功能无影响（零等待），但接口不规范 |
| `ahb_clint` | HBURST, HPROT | 同上 |
| `ahb_sys_status` | HBURST, HSIZE, HWDATA | 同上 |
| `ahb_default_slave` | HADDR, HWRITE, HSIZE, HBURST, HPROT, HWDATA, HRDATA | HRDATA 由外部赋0，功能正确但接口非标准 |

**建议**：统一所有从设备接口，即使内部不使用也保留完整端口，提高可维护性和可替换性。

---

#### ⚠️ 问题 3：HMASTLOCK 始终为 0

`cpu_bus_bridge` 始终驱动 `HMASTLOCK=0`。对于单主系统无原子操作需求时合规，但若未来需要实现 RISC-V LR/SC 原子指令，需修改。

---

#### ⚠️ 问题 4：INCR8 突发未检查 1KB 边界

规范要求增量突发不得跨越 1KB 地址边界。`cpu_bus_bridge` 的 INCR8 突发（8拍 × 4字节 = 32字节）不检查此约束。由于 cache line 对齐到 32 字节边界，实际不会越界，但缺少显式保护。

---

## 二、APB 协议合规性

### 2.1 信号完整性检查（APB4 标准）

| 规范要求 | 实现 | 状态 |
|---------|------|------|
| PCLK | 所有模块存在 | ✅ |
| PRESETn (低电平有效) | 所有模块使用 `negedge PRESETn` | ✅ |
| PADDR[31:0] | 所有模块存在 | ✅ |
| PSELx | 解码器生成，外设接收 | ✅ |
| PENABLE | 所有模块存在 | ✅ |
| PWRITE | 所有模块存在 | ✅ |
| PWDATA[31:0] | 所有模块存在 | ✅ |
| PRDATA[31:0] | 所有模块存在 | ✅ |
| PREADY | 所有模块存在 | ✅ |
| PSLVERR | 所有模块存在 | ✅ |
| PPROT[2:0] (APB4) | 所有模块存在 | ✅ |
| PSTRB[3:0] (APB4) | 所有模块存在 | ✅ |

### 2.2 关键协议规则合规性

#### ✅ 状态机转换

- `apb_master`：IDLE → SETUP → ACCESS → IDLE ✅
- SETUP 恒定1周期转入 ACCESS ✅
- ACCESS 阶段 `PREADY=0` 时保持 ✅

#### ✅ PSTRB 读传输时全零

- `apb_master` 第66行：`PSTRB <= req_write ? req_strb : {STRB_WIDTH{1'b0}}` ✅
- `ahb_lite_to_apb` 第104行：`PSTRB <= HWRITE ? latch_strb : {(DATA_WIDTH/8){1'b0}}` ✅

#### ✅ PSLVERR 仅在传输最后周期有效

- 所有外设：`PSLVERR=0` 常量 ✅（不产生错误，自然合规）

#### ✅ ACCESS 阶段信号稳定

- `apb_master`：ACCESS 状态 `PREADY=0` 时不更新任何 APB 输出信号 ✅
- `ahb_lite_to_apb`：BR_ACCESS 状态 `PREADY=0` 时 APB 侧信号不变 ✅

#### ✅ PENABLE 时序

- SETUP：`PENABLE=0` ✅
- ACCESS：`PENABLE=1` ✅

#### ✅ 复位行为

- 所有模块：`PSEL=0, PENABLE=0, PREADY=1` ✅

#### ✅ 写访问门控

- 所有外设：`write_access = PSEL & PENABLE & PWRITE & PREADY` ✅

#### ✅ 解码器全覆盖

- `apb_decoder` (SLAVE_NUM=4)：`PADDR[15:14]` 覆盖 00/01/10/11 全部4个从设备，无间隙 ✅

### 2.3 APB 发现的问题

#### ❌ 问题 5（严重）：`ahb_lite_to_apb` 的 PPROT[0] 映射反转

**位置**：`ahb_lite_to_apb.sv` 第58行

```systemverilog
PPROT[0] = ~HPROT[1];  // ❌ 反转
```

**规范对照**：

| 信号 | 值=0 含义 | 值=1 含义 |
|------|----------|----------|
| AHB `HPROT[1]` | 用户模式 | **特权**模式 |
| APB `PPROT[0]` | 正常访问 | **特权**访问 |

**正确映射应为**：`PPROT[0] = HPROT[1]`

**当前行为**：AHB 特权访问（HPROT[1]=1）被映射为 APB 正常访问（PPROT[0]=0），反之亦然。由于当前所有 APB 外设均忽略 PPROT，**功能暂无影响**，但若未来添加特权保护外设将导致安全漏洞。

---

#### ⚠️ 问题 6：`PPROT[1]` 语义不匹配

**位置**：`ahb_lite_to_apb.sv` 第59行

```systemverilog
PPROT[1] = ~HPROT[2];  // ⚠️ 语义不匹配
```

**分析**：

| 信号 | 含义 |
|------|------|
| AHB `HPROT[2]` | 可缓冲性（0=不可缓冲，1=可缓冲） |
| APB `PPROT[1]` | 安全/非安全（0=安全，1=非安全） |

"可缓冲"与"非安全"是完全不同的概念。AHB-Lite 没有安全位，APB 没有缓冲位。此映射在语义上无意义。

**建议**：由于 AHB-Lite 没有安全信息，`PPROT[1]` 应固定为 0（安全访问）或 1（非安全访问），而非从 HPROT 映射。

---

#### ⚠️ 问题 7：`read_access` 未门控 PREADY

**位置**：所有 APB 外设（gpio.sv, timer.sv, uart_top.sv, spi.sv）

```systemverilog
wire read_access = PSEL & PENABLE & !PWRITE;  // 缺少 & PREADY
```

**对比**：写访问正确包含 PREADY：

```systemverilog
wire write_access = PSEL & PENABLE & PWRITE & PREADY;  // ✅
```

**影响**：当前所有外设均为零等待状态（`PREADY=1`），功能无影响。但若未来添加有等待状态的外设，`PRDATA` 可能在 `PREADY=0` 期间被更新，导致请求方采样到中间数据。

**建议**：统一为 `read_access = PSEL & PENABLE & !PWRITE & PREADY`，与写访问保持一致。

---

#### ⚠️ 问题 8：PSTRB 被所有外设忽略

GPIO、Timer、UART、SPI 均接收 PSTRB 但完全忽略——始终写整个字。这意味着子字写入（如 byte write to UART TXDATA）会覆盖整个寄存器，而非仅更新目标字节。

**影响**：若软件执行非对齐或子字写操作，寄存器值将被错误覆盖。

**建议**：至少对 UART TXDATA 和 SPI DATA 等关键寄存器实现 PSTRB 门控写。

---

#### ⚠️ 问题 9：PPROT 被所有外设忽略

4个 APB 外设均接收 PPROT 但完全忽略，无特权/安全过滤。对于当前单特权级 RISC-V 系统可接受，但不符合安全设计最佳实践。

---

## 三、AHB-to-APB 桥合规性

### ✅ 正确行为

| 行为 | 验证 |
|------|------|
| AHB 地址阶段 → APB SETUP 转换 | BR_IDLE → BR_SETUP ✅ |
| SETUP 恒定1周期 → ACCESS | BR_SETUP 无条件转 BR_ACCESS ✅ |
| HWDATA 在数据阶段更新 | BR_SETUP 中 `PWDATA <= HWDATA` ✅ |
| PSLVERR → 2周期 AHB ERROR | `error_phase` 机制 ✅ |
| 无传输时 PSEL=0, PENABLE=0 | BR_IDLE 默认输出 ✅ |
| ACCESS 等待期间 APB 信号稳定 | BR_ACCESS PREADY=0 分支不更新 APB 信号 ✅ |
| 连续传输 PENABLE 正确转换 | ACCESS→SETUP: PENABLE 1→0 ✅ |

### ⚠️ 桥接问题

同上述 PPROT 问题 5、6。

---

## 四、总结

| 严重级别 | 编号 | 问题 | 位置 | 当前功能影响 |
|---------|------|------|------|------------|
| ❌ 严重 | 5 | PPROT[0] 映射反转 | `ahb_lite_to_apb.sv:58` | 无（外设忽略 PPROT） |
| ⚠️ 中等 | 1 | mux_HSELx 初始化死锁风险 | `ahb_lite_bus.sv:117` | 无（3阶段复位缓解） |
| ⚠️ 中等 | 6 | PPROT[1] 语义不匹配 | `ahb_lite_to_apb.sv:59` | 无（外设忽略 PPROT） |
| ⚠️ 中等 | 7 | read_access 缺 PREADY 门控 | 所有 APB 外设 | 无（零等待状态） |
| ⚠️ 中等 | 8 | PSTRB 被外设忽略 | GPIO/Timer/UART/SPI | 子字写入寄存器覆盖 |
| ⚠️ 低 | 2 | 从设备接口不一致 | PLIC/CLINT/SysStatus/Default | 无 |
| ⚠️ 低 | 3 | HMASTLOCK 始终为 0 | `cpu_bus_bridge.sv` | 无（无原子操作需求） |
| ⚠️ 低 | 4 | INCR8 突发未检查 1KB 边界 | `cpu_bus_bridge.sv` | 无（cache line 对齐） |
| ⚠️ 低 | 9 | PPROT 被所有外设忽略 | 所有 APB 外设 | 无（单特权级系统） |

**整体评价**：总线系统核心协议合规性**良好**。AHB-Lite 的关键规则（2周期 ERROR、IDLE/BUSY 响应、流水线锁存、写数据时序）全部正确实现。APB4 状态机和信号时序完全合规。最严重的 PPROT 映射反转问题因当前外设不使用 PPROT 而无功能影响，但应在添加安全外设前修复。
