# AHB-Lite / APB 总线 Bug 修复记录

> 日期：2026-05-23
> 范围：`dev/rtl/AHB-lite/`、`dev/rtl/APB/`、`dev/tb/`
> 参考规范：ARM IHI 0033A (AHB-Lite v1.0)、ARM IHI 0024E (APB Issue E)

---

## 1. 问题总览

扫描 AHB-Lite 与 APB 全部 20 个 RTL 文件，对照 AMBA 规范发现 **12 项逻辑/协议错误**，其中 4 项为致命级（导致仿真测试全部失败）。修复后三个此前失败的 testbench 均通过：

| Testbench | 修复前 | 修复后 |
|-----------|--------|--------|
| `tb_simple_cpu_top` | pass=41 fail=1 | **pass=42 fail=0** |
| `tb_simple_cpu_trap` | pass=11 fail=3 | **pass=14 fail=0** |
| `tb_led_marquee` | pass=1 fail=15 | **pass=16 fail=0** |

---

## 2. Bug 清单

### Bug #1 — AHB-to-APB 桥 ERROR 响应双赋值

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/APB/ahb_lite_to_apb.sv` |
| 现象 | HRESP 在 ERROR 传输中被两个 always 块同时驱动，导致 ERROR 信号丢失 |
| 根因 | 桥的状态机在 `BR_ACCESS` 状态同时赋值 `HRESP = 1'b1`（ERROR）和默认 `HRESP = 1'b0`（OKAY），综合后行为不确定 |
| 修复 | 引入 `error_phase` 寄存器，在检测到 PSLVERR 时置位，持续 2 个周期输出 ERROR 响应（符合 AHB-Lite 规范要求） |
| 规范依据 | AHB-Lite Spec §3.4: ERROR 响应必须持续 2 个时钟周期 |

### Bug #2 — SPI `spi_irq_pending` 多驱动

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/APB/perips/spi.sv` |
| 现象 | 两个 always 块同时驱动 `spi_irq_pending`，综合报 multi-driver 错误 |
| 根因 | 中断挂起逻辑被复制到两个独立的 always 块中 |
| 修复 | 删除重复的 always 块，保留含 `spi_ctrl[4]` 门控（IRQ 使能感知）的版本 |

### Bug #3 — SPI `spi_status[1]` 重复赋值

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/APB/perips/spi.sv` |
| 现象 | `spi_status[1]` 在同一 always 块中被两次赋值 |
| 修复 | 删除重复赋值行 |

### Bug #4 — SPI `bit_index` 下溢

| 项目 | 内容 |
|------|------|
| 严重度 | 🟠 中等 |
| 文件 | `dev/rtl/APB/perips/spi.sv` |
| 现象 | `bit_index` 为 4 位宽 `[3:0]`，递减到 0 后下溢为 15，导致 SPI 发送额外 15 个无效位 |
| 修复 | 扩展为 5 位 `[4:0]`，添加 `if (bit_index > 5'd0)` 递减保护；mode 0 初始值保持 6（bit 7 预装载到 MOSI） |

### Bug #5 — AHB-to-APB 桥 PWDATA 时序错误

| 项目 | 内容 |
|------|------|
| 严重度 | 🟠 中等 |
| 文件 | `dev/rtl/APB/ahb_lite_to_apb.sv` |
| 现象 | APB PWDATA 在 SETUP 相位无效（仍为旧值） |
| 根因 | 桥在 `BR_IDLE → BR_SETUP` 转换时未锁存 HWDATA 到 PWDATA |
| 修复 | 在状态转换中添加 `PWDATA <= HWDATA` |
| 规范依据 | APB Spec §3.2: PWDATA 必须在 SETUP 相位有效 |

### Bug #6 — CLINT/PLIC `rd_valid` 缺少 HREADY 检查（已被 Bug #9/#10 取代）

| 项目 | 内容 |
|------|------|
| 严重度 | 🟠 中等 |
| 文件 | `dev/rtl/AHB-lite/ahb_clint.sv`、`dev/rtl/AHB-lite/ahb_plic.sv` |
| 现象 | `rd_valid` 未检查 HREADY，可能在数据相位未就绪时输出无效数据 |
| 初始修复 | 添加 `&& HREADY` 到 `rd_valid` |
| 后续 | 此修复被 Bug #9/#10 的地址锁存方案完全取代 |

### Bug #7 — UART TX 复位值错误

| 项目 | 内容 |
|------|------|
| 严重度 | 🟡 轻微 |
| 文件 | `dev/rtl/APB/perips/uart_tx.sv` |
| 现象 | `o_txDataReady_1` 复位为 0，但上电后 TX 空闲时应指示"就绪" |
| 修复 | 复位值改为 `1'b1` |

### Bug #8 — Mux HSELx 未锁存（流水线数据通路错误）

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/AHB-lite/ahb_lite_bus.sv` |
| 现象 | AHB mux 直接使用组合逻辑 `slave_HSELx`（来自当前 HADDR）选择数据相位响应，在流水线传输中选择了错误从设备 |
| 根因 | AHB-Lite 流水线中，传输 T 的数据相位与传输 T+1 的地址相位重叠。此时 HADDR 已是 T+1 的地址，mux 据此选择 T+1 的从设备响应，但主设备需要 T 的响应 |
| 修复 | 添加 `mux_HSELx` 寄存器，在 `HREADY=1` 时锁存 `slave_HSELx`，传给 mux 用于数据相位选择 |

### Bug #9 — CLINT AHB-Lite 数据相位协议违规

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/AHB-lite/ahb_clint.sv` |
| 现象 | 所有 CLINT 寄存器读取返回 0，所有写入被静默丢弃。mtimecmp 写入失败导致定时器中断永不触发 |
| 根因 | `rd_valid` 和 `wr_valid` 门控于 `HTRANS[1]`，但 CPU 总线桥在数据相位设置 `HTRANS=IDLE`（`HTRANS[1]=0`），导致数据相位中 `rd_valid=0`、`wr_valid=0` |
| 修复 | 在地址相位（`HSEL && HTRANS[1] && HREADY`）锁存地址和控制信号，数据相位使用 `latch_valid` + 锁存地址进行读写 |
| 影响分析 | 此 bug 直接导致：(1) `tb_simple_cpu_top` 中 x11 读 mtime 返回 0（期望 2562）；(2) `tb_led_marquee` 中 mtimecmp 写入失败 → mtip 永为 0 → LED 卡死；(3) `tb_simple_cpu_trap` 中 CLINT 相关中断不工作 |

**时序分析**：

```
周期 N  (S_MMIO_ADDR):  HTRANS=NONSEQ, HTRANS[1]=1
                        → access_active=1, rd_valid=1
                        → CLINT 组合逻辑输出正确 HRDATA
                        → 但 CPU 不在此周期采样 HRDATA

周期 N+1 (S_MMIO_DATA): HTRANS=IDLE,   HTRANS[1]=0
                        → access_active=0, rd_valid=0
                        → HRDATA=0（默认值）
                        → CPU 采样 HRDATA=0 ← 错误！
```

### Bug #10 — PLIC 同样的 HTRANS 门控错误

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | `dev/rtl/AHB-lite/ahb_plic.sv` |
| 根因 | 与 Bug #9 完全相同 — `rd_valid`/`wr_valid` 门控于 `HTRANS[1]`，数据相位中 HTRANS=IDLE |
| 修复 | 同 Bug #9 方案：地址相位锁存，数据相位使用锁存值 |
| 影响 | PLIC 中断优先级/使能/阈值/claim 寄存器读写全部失效，外部中断无法正常工作 |

### Bug #11 — Mux HSELx 锁存缺少 HREADY 门控

| 项目 | 内容 |
|------|------|
| 严重度 | 🟠 中等 |
| 文件 | `dev/rtl/AHB-lite/ahb_lite_bus.sv` |
| 现象 | `mux_HSELx <= slave_HSELx` 每周期无条件更新；在等待状态期间，锁存值被下一传输的从设备选择覆盖 |
| 根因 | Bug #8 的初始修复未加 HREADY 门控。当 HREADY=0（数据相位未完成）时，mux_HSELx 不应更新 |
| 修复 | 改为 `else if (HREADY) mux_HSELx <= slave_HSELx` |
| 规范依据 | AHB-Lite Spec: 数据相位在 HREADY=1 时完成，此时下一传输进入数据相位，才应更新 mux 选择 |

### Bug #12 — Testbench SLAVE_NUM=4 与实际 5 从设备不匹配

| 项目 | 内容 |
|------|------|
| 严重度 | 🔴 致命 |
| 文件 | 9 个 testbench 文件（`tb_simple_cpu_top.sv` 等） |
| 现象 | 总线模块硬编码 5 个从设备实例（SRAM、PLIC、CLINT、APB 桥、默认从设备），但 testbench 传入 `SLAVE_NUM=4` |
| 根因 | SLAVE_NUM=4 导致：(1) `slave_HSELx[4]`（默认从设备选择）越界返回 'x'；(2) `slave_HRDATA` 宽度 128 位但拼接为 160 位 → `default_HRDATA` 被截断；(3) 默认从设备完全脱离 mux，未映射地址访问产生垃圾而非 ERROR |
| 修复 | 所有 testbench 中 `SLAVE_NUM` 从 4 改为 5 |

---

## 3. 修复方案详述

### 3.1 CLINT/PLIC 地址相位锁存模式

Bug #9 和 #10 的核心修复是将 CLINT 和 PLIC 从"组合逻辑直通"改为"地址相位锁存 + 数据相位输出"模式，与 SRAM 从设备的成熟模式一致。

**修改前**（CLINT 为例）：

```verilog
wire access_active = HSEL && HTRANS[1];
wire rd_valid = access_active && !HWRITE && HREADY;
wire wr_valid = access_active && HWRITE && HREADY;

wire addr_timelo = (HADDR[3:0] == ADDR_MTIME_LO);  // 使用当前 HADDR

always @(*) begin
    HRDATA = 32'd0;
    if (rd_valid) begin           // 数据相位时 rd_valid=0
        if (addr_timelo) HRDATA = r_mtime[31:0];
    end
end
```

**修改后**：

```verilog
wire ahb_transfer = HSEL && HTRANS[1] && HREADY;

reg [31:0] latch_addr;
reg        latch_write;
reg        latch_valid;   // 数据相位有效标志

always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
        latch_addr   <= 32'b0;
        latch_write  <= 1'b0;
        latch_valid  <= 1'b0;
    end else begin
        latch_valid <= ahb_transfer;  // 下一周期（数据相位）有效
        if (ahb_transfer) begin
            latch_addr   <= HADDR;    // 锁存地址相位地址
            latch_write  <= HWRITE;   // 锁存写标志
        end
    end
end

wire rd_valid = latch_valid && !latch_write;
wire wr_valid = latch_valid && latch_write;

wire addr_timelo = (latch_addr[3:0] == ADDR_MTIME_LO);  // 使用锁存地址

always @(*) begin
    HRDATA = 32'd0;
    if (rd_valid) begin           // 数据相位时 rd_valid=1
        if (addr_timelo) HRDATA = r_mtime[31:0];
    end
end
```

**时序对比**：

| 周期 | 修改前 HRDATA | 修改后 HRDATA |
|------|--------------|--------------|
| N（地址相位） | mtime（正确但无人采样） | 0（latch_valid=0） |
| N+1（数据相位） | **0**（rd_valid=0）← 错误 | **mtime**（latch_valid=1）← 正确 |

### 3.2 Mux HSELx 锁存

```verilog
// 修改前：每周期无条件更新
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn)
        mux_HSELx <= {SLAVE_NUM{1'b0}};
    else
        mux_HSELx <= slave_HSELx;     // ← 等待状态期间被覆盖
end

// 修改后：仅在 HREADY=1 时更新
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn)
        mux_HSELx <= {SLAVE_NUM{1'b0}};
    else if (HREADY)
        mux_HSELx <= slave_HSELx;     // ← 数据相位完成才更新
end
```

---

## 4. 根因链分析

三个 testbench 失败的根因链：

```
tb_led_marquee: LED 卡死
  └─ 定时器中断永不触发 (mtip=0)
      └─ mtimecmp 写入失败 (mtimecmp 保持 0)
          └─ CLINT wr_valid 在数据相位为 0
              └─ wr_valid 门控于 HTRANS[1]
                  └─ CPU 总线桥在数据相位设置 HTRANS=IDLE  ← Bug #9

tb_simple_cpu_top: x11 期望 0x000190a2 实际 0x000186a0
  └─ mtime 读取返回 0（期望 2562）
      └─ CLINT rd_valid 在数据相位为 0
          └─ 同上根因  ← Bug #9

tb_simple_cpu_trap: x19/x23/x24 错误
  └─ PLIC 寄存器读写失效
      └─ 同上根因（PLIC 与 CLINT 相同的 HTRANS 门控错误）  ← Bug #10
```

---

## 5. 修改文件清单

| 文件 | 修改内容 | Bug # |
|------|----------|-------|
| `dev/rtl/APB/ahb_lite_to_apb.sv` | error_phase 寄存器实现 2 周期 ERROR；PWDATA 锁存 | #1, #5 |
| `dev/rtl/APB/perips/spi.sv` | 删除多驱动 always 块；删除重复赋值；bit_index 扩展+保护 | #2, #3, #4 |
| `dev/rtl/AHB-lite/ahb_clint.sv` | 地址相位锁存模式（取代原 HTRANS 门控） | #6→#9 |
| `dev/rtl/AHB-lite/ahb_plic.sv` | 地址相位锁存模式（取代原 HTRANS 门控） | #6→#10 |
| `dev/rtl/AHB-lite/ahb_lite_bus.sv` | mux_HSELx 寄存器 + HREADY 门控 | #8, #11 |
| `dev/rtl/APB/perips/uart_tx.sv` | o_txDataReady_1 复位值 | #7 |
| `dev/tb/tb_simple_cpu_top.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_simple_cpu_trap.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_led_marquee.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_ahb_bus.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_apb_perips.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_simple_cpu_compute.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_uart_hello.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_simple_cpu_priv.sv` | SLAVE_NUM 4→5 | #12 |
| `dev/tb/tb_simple_cpu_mmu.sv` | SLAVE_NUM 4→5 | #12 |

---

## 6. 关键设计决策

1. **地址锁存 vs HTRANS 门控**：选择地址相位锁存模式而非简单移除 HTRANS 门控，因为锁存模式与 SRAM 从设备一致、符合 AHB-Lite 规范、且天然支持流水线传输。

2. **mux_HSELx 更新条件**：选择 `HREADY=1` 时更新而非每周期更新，确保等待状态期间 mux 指向当前数据相位的从设备。

3. **SLAVE_NUM 统一为 5**：总线模块硬编码 5 个从设备实例，参数必须匹配。未来如需增减从设备，应同步修改实例化和参数。

4. **error_phase 寄存器**：匹配 `ahb_default_slave.sv` 的 2 周期 ERROR 模式，避免引入不一致的 ERROR 处理行为。
