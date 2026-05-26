# RTL Bug Report — `dev/rtl/`

> 扫描时间: 2026-05-26 (深度审计 v2)
> 扫描范围: `dev/rtl/` 下全部 `.sv` / `.svh` 文件（50+ 个）
> 覆盖子系统: core / ALU / MU / AHB-lite / APB
> 审计方法: 逐文件精读 + AST 模式匹配 + 多维度交叉验证

## 修复状态

| BUG | 严重度 | 状态 | 修复日期 | 验证 |
|-----|--------|------|----------|------|
| BUG-01 | HIGH | ✅ 已修复 | 2026-05-26 | cpu_full/trap/compute/priv PASS |
| BUG-02 | HIGH | ✅ 已修复 | 2026-05-26 | cpu_full/trap/compute/priv PASS |
| BUG-03 | HIGH | ✅ 已修复 | 2026-05-26 | cpu_full/trap/compute/priv PASS |
| BUG-04 | HIGH | ✅ 已修复 | 2026-05-26 | cpu_full/trap/compute/priv PASS |
| BUG-05 | MEDIUM | ⏭️ 跳过 | — | BRAM 寄存器堆同步复位有意设计 |
| BUG-06 | MEDIUM | ⏭️ 跳过 | — | 当前 FSM 下无功能影响 |
| BUG-07 | MEDIUM | ⏭️ 跳过 | — | 冗余采样，低风险 |
| BUG-08 | MEDIUM | ⏭️ 跳过 | — | 规范兼容性，非功能 bug |
| BUG-09~12 | LOW | ⏭️ 跳过 | — | 代码质量/lint |

---

## 🔴 HIGH Severity

### BUG-01: `cpu_bus_bridge.sv` — `mmio_inst_served` / `mmio_data_served` 复位缺失

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/core/cpu_bus_bridge.sv` | 102-103, 149-180 | `cpu_bus_bridge` |

**问题描述**: `mmio_inst_served` 和 `mmio_data_served` 两个寄存器在声明后（line 102-103），**未在 reset 块（line 149-180）中初始化**。

```systemverilog
// cpu_bus_bridge.sv:102-103 — 声明
reg        mmio_inst_served;
reg        mmio_data_served;

// reset 块中缺少:
//   mmio_inst_served <= 1'b0;
//   mmio_data_served <= 1'b0;
```

这两个寄存器用于防止同一 MMIO 请求被重复服务（line 198: `!mmio_inst_served`，line 209: `!mmio_data_served`）。复位后若值为 X（仿真）或 1（硅片），**首次 MMIO 请求将被永久忽略**。

**影响**: CPU 复位后首次访问 MMIO 设备（如 UART、SPI、GPIO）时，请求可能被丢弃，导致外设初始化失败或系统死锁。

**建议**: 在 reset 块中添加：

```systemverilog
mmio_inst_served <= 1'b0;
mmio_data_served <= 1'b0;
```

---

### BUG-02: `cpu_trap_manager.sv` — `exception_valid_r` 优先级错误导致中断永久阻塞

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/core/cpu_trap_manager.sv` | 254-270 | `cpu_trap_manager` |

**问题描述**: `exception_valid_r` 的更新逻辑中，`exception_valid` 的优先级**高于** `trap_enter_valid || trap_return_valid`：

```systemverilog
// cpu_trap_manager.sv:261-268
if (exception_valid) begin              // ← 优先级高
    exception_valid_r <= 1'b1;
    exception_cause_r <= exception_cause;
    ...
end else if (trap_enter_valid || trap_return_valid) begin  // ← 优先级低
    exception_valid_r <= 1'b0;
end
```

当 `trap_enter_valid` 为真的同一周期，若 `exception_valid` 也为真（因为 access fault / page fault 寄存器尚未清除——清除在下一拍才生效），则 `exception_valid_r` 被置 1 而非清 0。此后 `exception_valid_r` 持续为 1，直到下一次 trap 或 mret/sret。

由于 `trap_pending = clint_trap_enter && !exception_valid_r`（line 276），**`exception_valid_r = 1` 会阻塞所有后续中断**，即使 MIE 已被软件重新使能。

**影响**: 任何 access fault 或 page fault 触发后，中断被永久阻塞直到下一次 trap 或 mret/sret。若 trap handler 在返回前重新使能中断（写 mstatus.MIE），中断仍无法响应。

**建议**: 交换优先级，使 `trap_enter_valid || trap_return_valid` 优先于 `exception_valid`：

```systemverilog
if (trap_enter_valid || trap_return_valid) begin
    exception_valid_r <= 1'b0;
end else if (exception_valid) begin
    exception_valid_r <= 1'b1;
    ...
end
```

---

### BUG-03: `cpu_clint.sv` — S-mode 软件中断 cause 编码未考虑 `sip[1]`

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/core/cpu_clint.sv` | 87-90, 98-100 | `cpu_clint` |

**问题描述**: `s_interrupt_cause` 和 `s_int_idx` 在判断 S-mode 软件中断时，仅检查 `msip_bit`（CLINT 硬件中断），**遗漏了 `csr_sip[1]`（软件写 sip 触发的中断）**：

```systemverilog
// cpu_clint.sv:87-90 — s_interrupt_cause
assign s_interrupt_cause = (seie_bit && meip_bit) ? 32'h80000009 :
                           (ssie_bit && msip_bit) ? 32'h80000001 :  // ← 缺少 csr_sip[1]
                           (stie_bit && mtip_bit) ? 32'h80000005 :
                           32'h80000009;

// cpu_clint.sv:98-100 — s_int_idx
assign s_int_idx = (seie_bit && meip_bit) ? 6'd9 :
                   (ssie_bit && msip_bit) ? 6'd1 :  // ← 缺少 csr_sip[1]
                   (stie_bit && mtip_bit) ? 6'd5 : 6'd9;
```

对比 `s_interrupt_pending`（line 76）使用了 `csr_sip[1] | msip_bit`，是正确的。

**影响**: 当软件通过写 `sip[1]` 触发 S-mode 软件中断时（`csr_sip[1]=1, msip_bit=0`），`s_interrupt_pending` 为真（中断被识别），但 `s_interrupt_cause` 会错误地返回 `0x80000009`（外部中断）而非 `0x80000001`（软件中断）。`scause` 寄存器被写入错误的 cause code。

**建议**: 将 `ssie_bit && msip_bit` 替换为 `ssie_bit && (csr_sip[1] | msip_bit)`：

```systemverilog
assign s_interrupt_cause = (seie_bit && meip_bit) ? 32'h80000009 :
                           (ssie_bit && (csr_sip[1] | msip_bit)) ? 32'h80000001 :
                           (stie_bit && mtip_bit) ? 32'h80000005 :
                           32'h80000009;
// s_int_idx 同理
```

---

### BUG-04: `uart_tx.sv` / `uart_rx.sv` — 组合逻辑块中使用非阻塞赋值

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/APB/header/uart_tx.sv` | 40-66 | `uart_tx` |
| `dev/rtl/APB/header/uart_rx.sv` | 61-92 | `uart_rx` |

**问题描述**: 两个 UART 模块的 `next_state` 在 `always @(*)` 组合逻辑块中使用了非阻塞赋值 `<=` 而非阻塞赋值 `=`：

```systemverilog
// uart_tx.sv:40-66 — 组合逻辑块，应使用 =
always@(*) begin
    case(state)
        S_IDLE:
            if(i_txDataValid_1)
                next_state <= S_START;   // ← 应为 next_state = S_START;
            else
                next_state <= S_IDLE;    // ← 应为 next_state = S_IDLE;
        ...
    endcase
end
```

`uart_rx.sv` 存在完全相同的问题。

**影响**: IEEE 1364-2005 标准规定组合逻辑块中应使用阻塞赋值。使用非阻塞赋值可能导致：

- 仿真与综合行为不一致
- 多周期仿真中状态机行为异常
- 综合工具可能产生告警或意外优化

**建议**: 将两个文件中 `always @(*)` 块内的所有 `<=` 替换为 `=`。

---

## 🟡 MEDIUM Severity

### BUG-05: 寄存器堆复位风格不一致 → 仿真/综合失配风险

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/core/cpu_regfile.sv` | 23 | `cpu_regfile` |

**问题描述**: 项目编码规范要求 `always @(posedge clk or posedge reset)`（异步高复位），但 `cpu_regfile.sv` 使用了同步复位写法：

```systemverilog
// cpu_regfile.sv:23 — 同步复位（与规范不符）
always @(posedge clk) begin
    if (reset) begin
        foreach (rf[i]) rf[i] <= 32'b0;
    end else if (wen && (waddr != 5'd0)) begin
        rf[waddr] <= wdata;
    end
end
```

**对比其他模块**（全部使用异步复位敏感列表）:

- `core_top.sv:226` — `always @(posedge clk or posedge reset)`
- `cpu_controller.sv:62` — `always @(posedge clk or posedge reset)`
- `cpu_execute.sv:146` — `always @(posedge clk or posedge reset)`
- `cpu_mem.sv:109` — `always @(posedge clk or posedge reset)`

**风险**:

- 仿真中复位释放后寄存器值初始化时机不同
- 若 FPGA BRAM 不支持异步复位，同步复位可接受，但必须在注释中明确说明原因
- lint 工具会产生风格不一致告警

**建议**:

- 方案 A: 若 BRAM 支持，改为 `always @(posedge clk or posedge reset)`
- 方案 B: 若因 BRAM 限制需同步复位，在代码中添加注释说明

---

### BUG-06: `cpu_execute.sv` — MU 多周期操作期间 `exe_seen_valid` 清除逻辑脆弱

| 文件 | 行号 |
|------|------|
| `dev/rtl/core/cpu_execute.sv` | 161-163 |

**问题描述**: 当 `!exe_valid` 时，`exe_seen_valid` 被清零：

```systemverilog
// cpu_execute.sv:161-163
if (!exe_valid) begin
    exe_seen_valid <= 1'b0;  // 流水线无效时清除标志
end
```

若 MU 正在进行多周期运算时 `exe_valid` 因流水线冲刷被撤除，`exe_seen_valid` 清零。若后续同一指令重新进入 EXE 阶段且 `exe_valid` 再次置位，将**重复发起 MU 请求**（`mu_active=0 && exe_valid && !exe_seen_valid` → 条件满足）。

**当前 FSM 评估**: 控制器从 STATE_EXEC 切换至 STATE_TRAP_ENTER 时会冲刷流水线并加载新 PC，trap 返回后重新取指，不会回到同一 MU 操作。当前设计下不影响功能，但代码不够健壮——若未来 FSM 增加从 EXEC 非 trap 切换路径，此 bug 将暴露。

**建议**: 增加 `mu_active` 期间对 `exe_seen_valid` 的保护，或将 `exe_seen_valid` 清除条件增加 `!mu_active` 限制。

---

### BUG-07: `ahb_lite_to_apb.sv` — BR_SETUP 中冗余采样 HWDATA

| 文件 | 行号 |
|------|------|
| `dev/rtl/APB/ahb_lite_to_apb.sv` | 115-120 |

**问题描述**: 写数据 `HWDATA` 在 BR_IDLE 中已采样到 `PWDATA`（line 103），但在 BR_SETUP 中又做了一次冗余采样：

```systemverilog
// BR_IDLE (line 103): 首次采样
PWDATA <= HWDATA;

// BR_SETUP (line 118): 冗余采样
PWDATA <= HWDATA;
```

**风险分析**: 正常情况下 HWDATA 在整个 APB 传输期间保持稳定。但若 AHB-Lite 流水线中存在 back-to-back 写传输，`HWDATA` 可能在 BR_SETUP 期间已更新为下一笔传输的数据。当前 AHB-lite bus 使用 `mux_HSELx` 寄存器配合 `HREADY` 握手机制保证不会出现此重叠，因此实际安全——但依赖于上游行为。

**建议**: 移除 BR_SETUP 中的 `PWDATA <= HWDATA` 赋值，仅保留 BR_IDLE 中的采样。

---

### BUG-08: `cpu_csr.sv` — `r_mip` 每周期无条件覆盖，软件无法写 mip

| 文件 | 行号 | 模块 |
|------|------|------|
| `dev/rtl/core/cpu_csr.sv` | 269 | `cpu_csr` |

**问题描述**: `r_mip` 每周期被硬件中断源无条件覆盖：

```systemverilog
// cpu_csr.sv:269
r_mip <= w_mip_hw;  // w_mip_hw = {20'b0, ext_meip, 3'b0, ext_mtip, 3'b0, ext_msip, 3'b0};
```

同时，`sw_csr_wen` 的 case 语句中**没有 `ADDR_MIP` 分支**，软件无法写 mip。

**影响**:

- RISC-V 特权规范允许 M-mode 软件写 `mip.MSIP`（通过直接写 mip 或通过 CLINT msip 寄存器）。当前实现仅支持通过 CLINT 写 msip，直接写 `mip[3]` 无效。
- `sip` 仅暴露 `sip[1]`（SSIP），缺少 `sip[5]`（STIP）和 `sip[9]`（SEIP）的只读视图，不完全符合规范。

**建议**: 若需完整规范兼容，添加软件写 mip 的支持（至少 mip[3] 可写），并在 sip 读取中补充 STIP/SEIP 位。

---

## 🟢 LOW Severity / Code Quality

### BUG-09: `system_top.sv` — `timer_irq` 线网悬空

| 文件 | 行号 | 信号 |
|------|------|------|
| `dev/rtl/system_top.sv` | 49, 128 | `timer_irq` |

**问题描述**: `ahb_lite_bus` 输出的 `o_timer_irq` 连接到 `timer_irq` 线网，但该线网在 `system_top` 中没有被任何其他模块读取。

**实际影响**: `o_timer_irq` 在 `ahb_lite_bus` 内部已正确连接到 PLIC 中断源，功能不受影响。但顶层悬空线网会产生 lint warning。

**建议**: 移除顶层 `timer_irq` 声明和对应端口连接，或在 `ahb_lite_bus` 中将 `o_timer_irq` 改为内部信号。

---

### BUG-10: `cpu_decode.sv` — 多处使用按位或 `|` 代替逻辑或 `||`

| 文件 | 行号 |
|------|------|
| `dev/rtl/core/cpu_decode.sv` | 229-288 |

**问题描述**: 单比特信号的条件组合使用了 `|`（按位或）而非 `||`（逻辑或）：

```systemverilog
assign is_branch = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign is_alu    = inst_lui | inst_auipc | is_load | is_store | ...;
```

**影响**: 单比特信号上 `|` 和 `||` 功能等价，但不符合 SystemVerilog 编码惯例。

**建议**: 全局替换为 `||`。

---

### BUG-11: `core_top.sv` — `init_sig` 端口始终接地但保留接口

| 文件 | 行号 |
|------|------|
| `dev/rtl/core/core_top.sv` | 33 |
| `dev/rtl/system_top.sv` | 100 |

**问题描述**: `init_sig` 用于控制 CPU 初始化锁定（`cycle_en = ~init_sig`），但顶层硬编码为 0：`.init_sig(1'b0)`。

**建议**: 若确定不需要初始化锁定功能，可移除该端口及相关逻辑。

---

### BUG-12: `core_top.sv` — `exe_wb_bus` 的 `wb_we` 字段掩码语义缺少注释

| 文件 | 行号 |
|------|------|
| `dev/rtl/core/core_top.sv` | 168 |

**问题描述**: `exe_wb_bus` 的第 133 位被 `result_ok` 掩码：`exe_mem_bus[169] & exe_mem_bus[174]`。此掩码确保无效指令不会触发写回，语义正确但缺少注释。

**建议**: 添加注释说明掩码目的。

---

## 📊 审计统计

| 严重度 | 数量 | 模块分布 |
|--------|------|----------|
| 🔴 HIGH | 4 | cpu_bus_bridge, cpu_trap_manager, cpu_clint, uart_tx/rx |
| 🟡 MEDIUM | 4 | cpu_regfile, cpu_execute, ahb_lite_to_apb, cpu_csr |
| 🟢 LOW | 4 | system_top, cpu_decode, core_top×2 |
| **合计** | **12** | |

### 已验证无问题的领域

- ✅ **流水线总线位宽**: `if_id_bus`(96bit), `id_exe_bus`(320bit), `exe_mem_bus`(207bit), `mem_wb_bus`(168bit) — 所有字段映射与拆包一致
- ✅ **core_top 端口连接**: 所有模块例化的端口名称、信号宽度与模块声明匹配
- ✅ **exe_wb_bus 直通路径**: EXEC→WB 绕过 MEM 时，字段正确映射到 mem_wb_bus 格式
- ✅ **csr_wb_bus 格式**: CSR 访问的 WB 总线正确设置 `is_csr=1, wb_we=1`
- ✅ **cpu_csr_interface.sv 硬编码索引**: 从 `id_exe_bus_r` 提取的字段位索引与 `id_exe_bus` 打包顺序一致
- ✅ **控制器状态机**: 无死状态、无不可达状态、default 分支完备
- ✅ **指令解码**: RV32I/M 全部 opcode/funct3/funct7 解码正确
- ✅ **ALU 控制码**: 所有运算类型到 alu_control 的映射正确
- ✅ **分支比较**: beq/bne/blt/bge/bltu/bgeu 条件判断正确
- ✅ **CSR 读写逻辑**: csrrw/csrrs/csrrc/csrrwi/csrrsi/csrrci 新值计算正确，no-write 判断正确
- ✅ **特权级检查**: U/S/M 模式下 CSR 访问权限、sret/mret 权限检查正确
- ✅ **mstatus/sstatus 更新**: trap enter/return 时 MPP/MPIE/MIE/SPP/SPIE/SIE 更新符合 RISC-V 规范
- ✅ **icache/dcache 状态机**: 状态转换完备，PLRU 替换逻辑正确
- ✅ **MMU/TLB**: BRAM 路径和寄存器路径两种实现逻辑一致，权限检查正确
- ✅ **AHB-Lite 协议**: HTRANS/HBURST/HSIZE 信号使用正确，HREADY 握手无组合环路
- ✅ **无多重驱动**: 所有寄存器仅在一个 always 块中被驱动
- ✅ **无非阻塞赋值组合逻辑**: 除 uart_tx/rx 外，所有组合块使用阻塞赋值
- ✅ **无推断锁存**: 所有组合逻辑块有完备 default 赋值
