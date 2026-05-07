# CPU 直连 AHB-Lite 总线重构

## 状态说明
- [x] 已完成
- [~] 进行中
- [ ] 未开始

---

## 1. 计划概述

移除 CPU 核心与 AHB-Lite 总线之间的 Bus4LZU 风格桥接模块 `cpu_bus_adapter`，将 CPU 直接连接到 AHB-Lite 总线。合并 `cpu_bus_adapter`（5 状态 FSM）+ `ahb_master`（4 状态 FSM）的功能到 `simple_cpu_top.v` 中，实现一个精简的 3 状态 AHB-Lite 主设备 FSM。

### 1.1 设计目标

| 目标 | 说明 |
|------|------|
| 消除桥接层 | 删除 `cpu_bus_adapter.v`，CPU 直接驱动 AHB-Lite 信号 |
| 协议合规 | 严格遵循 AMBA 3 AHB-Lite v1.0 规范 |
| 单主设备 | CPU 为唯一主设备，I 侧优先于 D 侧 |
| 3 状态 FSM | AHB_IDLE → AHB_ADDR → AHB_DATA，合并原 9 状态为 3 状态 |
| 零功能回归 | 所有既有测试保持 PASS |

### 1.2 架构变更

**重构前**：
```
simple_cpu_top (Bus4LZU) → cpu_bus_adapter (5-state) → ahb_master (4-state) → ahb_periph_bus
```

**重构后**：
```
simple_cpu_top → cpu_bus_bridge (AHB-Lite master FSM, 3-state) → ahb_periph_bus
```

### 1.3 模块变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `core/simple_cpu_top.v` | 重写 | Bus4LZU 端口 → AHB-Lite 端口，实例化 `cpu_bus_bridge` |
| `core/cpu_bus_bridge.v` | 新建 | 3 状态 AHB-Lite 主 FSM，从 `simple_cpu_top` 提取 |
| `core/dcache_ctrl.v` | 重写 | `cpu_req_wen` → `cpu_req_hwrite` + `cpu_req_hsize`，内部计算 BRAM 字节写使能 |
| `core/cpu_mem.v` | 修改 | `dataWen_4` → `mem_hwrite` + `mem_hsize`，修复 `mem_en_reg` 时序 |
| `AHB-lite/ahb_periph_bus.v` | 重写 | req/resp 接口 → 直接 AHB-Lite 信号，移除 `ahb_master` 实例化 |
| `system_top.v` | 重写 | 移除 `cpu_bus_adapter` 实例化，CPU AHB-Lite 信号直连 `ahb_periph_bus` |
| `core/cpu_bus_adapter.v` | 删除 | 功能已合并到 `simple_cpu_top.v` |
| `tb/tb_cpu_bus_adapter.v` | 删除 | 对应模块已删除 |

---

## 2. 实现步骤

### Step 1: dcache_ctrl.v — 字节写使能内化

- [x] `cpu_req_wen[3:0]` → `cpu_req_hwrite` + `cpu_req_hsize[2:0]`
- [x] 内部从 `hwrite`/`hsize`/`addr` 组合计算 `bram_wea[3:0]`，逻辑与 `ahb_sram_slave.v` 一致
- [x] MMIO 接口扩展：`mmio_hwrite`/`mmio_hsize` 传递到 AHB FSM
- [x] `dcache_valid_r` 仅在非 MMIO 时置位（`cpu_req_valid && !is_mmio`）

### Step 2: cpu_mem.v — 接口适配 + 时序修复

- [x] `dataWen_4[3:0]` → `mem_hwrite` + `mem_hsize[2:0]`
- [x] MEM_IDLE：根据 `is_load`/`is_store`/`mem_size` 设置 `hwrite_reg`/`hsize_reg`
- [x] MEM_WRITE：字节/半字写数据通道对齐（`{4{data[7:0]}}` 等）
- [x] **修复 `mem_en_reg` 时序**：在 MEM_READ/MEM_WRITE 的 `data_valid` 完成路径中清除 `mem_en_reg`，防止其在完成后的额外一周期保持高电平导致伪 AHB 传输

### Step 3: simple_cpu_top.v + cpu_bus_bridge.v — AHB-Lite 主 FSM 模块化

- [x] 端口替换：Bus4LZU → AHB-Lite（HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK/HWDATA/HRDATA/HREADY/HRESP）
- [x] 3 状态 FSM：AHB_IDLE / AHB_ADDR / AHB_DATA
- [x] AHB_IDLE：I 侧优先，`icache_mmio_req` 或 `dcache_mmio_req` 时启动传输
- [x] 重复传输防护：`!ahb_inst_valid_r && !ahb_data_valid_r` 条件守卫
- [x] AHB_ADDR：等待 HREADY，锁存 HWDATA，处理 HRESP=ERROR
- [x] AHB_DATA：等待 HREADY，采样 HRDATA，产生 `ahb_inst_valid_r`/`ahb_data_valid_r` 单周期脉冲
- [x] 复位：HTRANS=IDLE，所有输出默认值
- [x] FSM 提取到 `cpu_bus_bridge.v`：CPU 侧 req/resp 接口 + AHB-Lite 侧 master 信号
- [x] `simple_cpu_top.v` 实例化 `cpu_bus_bridge`，移除内联 FSM 和 `` `include "ahb_def.vh" ``

### Step 4: ahb_periph_bus.v — 直接 AHB-Lite 接口

- [x] 移除 req/resp 请求-响应接口
- [x] 移除 `ahb_master` 实例化
- [x] 直接接受 AHB-Lite 主设备信号（HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK/HWDATA）
- [x] 输出 HRDATA/HREADY/HRESP
- [x] 内部 decoder + mux + sram_slave + default_slave + ahb_lite_to_apb 结构不变

### Step 5: system_top.v — 直连拓扑

- [x] 移除 `cpu_bus_adapter` 实例化
- [x] CPU AHB-Lite 信号直连 `ahb_periph_bus`
- [x] `timer_irq` 反馈路径不变

### Step 6: 测试适配

- [x] `tb_simple_cpu_top.v`：AHB-Lite 端口 + 直连 `ahb_periph_bus`
- [x] `tb_led_marquee.v`：同上 + 仿真定时器值调整
- [x] `tb_uart_hello.v`：同上 + iverilog 兼容性修复
- [x] `tb_ahb_bus.v`：直接驱动 AHB-Lite 信号 + `#1` 延迟满足协议时序

---

## 3. 关键设计决策

### 3.1 AHB-Lite 主 FSM 状态设计

```
              icache_mmio_req || dcache_mmio_req
  AHB_IDLE ─────────────────────────────────────> AHB_ADDR
     ↑                                              │
     │              HREADY=1                         │ HREADY=1
     │         (HRESP=ERROR → IDLE)                  ↓
     │                                         AHB_DATA
     │                                              │
     │              HREADY=1                         │ HREADY=0 (保持)
     └──────────────────────────────────────────────┘
```

- **AHB_IDLE**：无传输，HTRANS=IDLE。检测 MMIO 请求（I 侧优先），启动时锁存地址/控制/写数据
- **AHB_ADDR**：地址阶段，HTRANS=NONSEQ。等待 HREADY 确认上一传输完成，然后进入数据阶段
- **AHB_DATA**：数据阶段，HWDATA 有效。等待 HREADY，采样 HRDATA，产生 valid 脉冲

### 3.2 重复传输防护

`ahb_inst_valid_r` / `ahb_data_valid_r` 为单周期脉冲。在脉冲有效周期内，`dcache_mmio_req` 可能仍为高（`mem_en_reg` 时序），需守卫防止 AHB FSM 在 AHB_IDLE 重复启动传输：

```verilog
if (dcache_mmio_req && !ahb_inst_valid_r && !ahb_data_valid_r)
```

### 3.3 mem_en_reg 时序修复

**问题**：原 `cpu_mem.v` 中 `mem_en_reg` 仅在 `MEM_IDLE` 状态清除，导致 `data_valid` 到达后 `mem_en_reg` 仍保持一周期高电平。`dcache_ctrl.v` 的 `mmio_req = is_mmio ? cpu_req_valid : 1'b0` 组合逻辑会在该额外周期产生伪请求，触发 AHB FSM 启动虚假传输。

**修复**：在 MEM_READ/MEM_WRITE 的 `data_valid` 完成路径中立即清除 `mem_en_reg`：

```verilog
MEM_READ:  if (data_valid) begin mem_en_reg <= 1'b0; ... end
MEM_WRITE: if (data_valid) begin mem_en_reg <= 1'b0; ... end
```

### 3.4 字节写使能计算

`dcache_ctrl.v` 内部从 `hwrite`/`hsize`/`addr` 组合计算 BRAM 字节写使能，逻辑与 `ahb_sram_slave.v` 完全一致：

| hsize | addr[1:0] | bram_wea |
|-------|-----------|----------|
| BYTE  | 00/01/10/11 | 0001/0010/0100/1000 |
| HWORD | 0/1 | 0011/1100 |
| WORD  | — | 1111 |

### 3.5 仿真定时器值调整

`led_marquee.hex` 原定时器比较值为 100000000（1 秒 @100MHz，适用于 FPGA），仿真中每步 10000 周期超时远不够。修改为 1000 周期（`LUI x16,0x0` + `ADDI x16,x16,0x3E8`），配合 100000 周期步超时。

---

## 4. AHB-Lite 协议合规要点

| 规范要求 | 实现 | 状态 |
|----------|------|------|
| HRESETn 低有效 | `HRESETn = ~reset` | ✅ |
| HTRANS=IDLE 复位初始值 | `ahb_HTRANS_r <= AHB_TRANS_IDLE` | ✅ |
| 地址阶段 HTRANS=NONSEQ | AHB_ADDR 状态驱动 | ✅ |
| 数据阶段 HWDATA 有效 | AHB_DATA 状态输出 `ahb_HWDATA_r` | ✅ |
| HREADY 延长数据阶段 | AHB_ADDR/AHB_DATA 均等待 HREADY | ✅ |
| HRESP=ERROR 两周期 | AHB_ADDR 检测 ERROR，立即返回 IDLE | ✅ |
| 单主设备无仲裁 | CPU 为唯一主，I/D 互斥由控制器保证 | ✅ |
| HBURST=SINGLE | 所有传输为单次突发 | ✅ |

---

## 5. 测试结果

### 5.1 iverilog 仿真

| 测试 | 结果 | 说明 |
|------|------|------|
| `tb_ahb_bus` | 3/3 PASS | SRAM 读写 + APB 桥 GPIO 访问 |
| `tb_simple_cpu_top` | 34/34 PASS | RV32I 完整指令集 + MMIO 读写 |
| `tb_led_marquee` | 16/16 PASS | 16 步 LED 走马灯（定时器=1000 周期） |
| `tb_uart_hello` | 12/12 PASS | UART 输出 "Hello World"（11 字符 + 计数） |

### 5.2 编译命令

```bash
iverilog -g2005 \
  -I dev/rtl/AHB-lite -I dev/rtl/ALU -I dev/rtl/core \
  -I dev/rtl/APB -I dev/rtl/APB/header -I dev/rtl/APB/perips \
  -o tb.vvp \
  dev/rtl/AHB-lite/ip/sram_model.v \
  dev/rtl/ALU/*.v \
  dev/rtl/core/*.v \
  dev/rtl/AHB-lite/ahb_master.v dev/rtl/AHB-lite/ahb_decoder.v \
  dev/rtl/AHB-lite/ahb_mux.v dev/rtl/AHB-lite/ahb_periph_bus.v \
  dev/rtl/AHB-lite/ahb_sram_slave.v dev/rtl/AHB-lite/ahb_default_slave.v \
  dev/rtl/AHB-lite/ahb_bus.v \
  dev/rtl/APB/ahb_lite_to_apb.v dev/rtl/APB/apb_decoder.v \
  dev/rtl/APB/apb_slave.v dev/rtl/APB/apb_bus.v dev/rtl/APB/apb_master.v \
  dev/rtl/APB/perips/*.v \
  dev/tb/tb_xxx.v
```

---

## 6. 实现记录

### 2026-05-05 CPU 直连 AHB-Lite 总线重构完成

**变更文件**：

| 文件 | 行数 | 变更 |
|------|------|------|
| `core/simple_cpu_top.v` | 573 | 重写：AHB-Lite 端口 + 实例化 cpu_bus_bridge |
| `core/cpu_bus_bridge.v` | 143 | 新建：3 状态 AHB-Lite 主 FSM（从 simple_cpu_top 提取） |
| `core/dcache_ctrl.v` | 76 | 重写：hwrite/hsize 接口 + 内部字节写使能 |
| `core/cpu_mem.v` | 228 | 修改：hwrite/hsize 接口 + mem_en_reg 时序修复 |
| `AHB-lite/ahb_periph_bus.v` | — | 重写：直接 AHB-Lite 信号接口 |
| `system_top.v` | — | 重写：移除 cpu_bus_adapter，直连拓扑 |
| `core/cpu_bus_adapter.v` | — | 删除 |
| `tb/tb_cpu_bus_adapter.v` | — | 删除 |
| `tb/tb_simple_cpu_top.v` | — | 适配 AHB-Lite 端口 |
| `tb/tb_led_marquee.v` | — | 适配 AHB-Lite 端口 + 超时调整 |
| `tb/tb_uart_hello.v` | — | 适配 AHB-Lite 端口 + iverilog 兼容 |
| `tb/tb_ahb_bus.v` | — | 直接驱动 AHB-Lite 信号 |
| `program_source/led_marquee.hex` | 23 | 定时器值 100M→1000（仿真用） |

**修复的 Bug**：

1. **mem_en_reg 时序**：`cpu_mem.v` 中 `mem_en_reg` 在 MEM_READ/MEM_WRITE 完成后额外保持一周期高电平，导致 `dcache_mmio_req` 产生伪请求，触发 AHB FSM 启动虚假传输。修复：在 `data_valid` 完成路径中立即清除 `mem_en_reg`。

2. **AHB FSM 重复传输**：`ahb_data_valid_r` 脉冲周期内 `dcache_mmio_req` 仍可能为高，需 `!ahb_inst_valid_r && !ahb_data_valid_r` 守卫防止重复启动传输。

3. **仿真定时器超时**：`led_marquee.hex` 定时器比较值 100000000 适用于 FPGA（1 秒 @100MHz），仿真 10000 周期步超时远不足。修改为 1000 周期 + 100000 步超时。

4. **iverilog 兼容性**：`tb_uart_hello.v` 使用 SystemVerilog `string` 类型，iverilog 不支持。移除并简化输出逻辑。

---

## 7. 后续计划

- [ ] 恢复 `led_marquee.hex` 定时器值为 100000000（FPGA 部署时）
- [ ] 突发传输支持（INCR4/WRAP4 地址生成逻辑）
- [ ] HMASTLOCK 锁定传输支持（SWP 原子操作）
- [ ] 性能优化：I/D 并发访问（当前控制器保证互斥）

---

## 8. 补充实现记录

### 2026-05-05 AHB-Lite 主 FSM 模块化（cpu_bus_bridge 提取）

**动机**：`simple_cpu_top.v` 内联 AHB-Lite 主设备 FSM（~120 行寄存器 + always + assign），使顶层模块过于臃肿。将 FSM 提取为独立模块 `cpu_bus_bridge`，降低 `simple_cpu_top` 复杂度，总线逻辑可独立验证和复用。

**架构变更**：

```
重构前: simple_cpu_top (内联 3-state FSM) → ahb_periph_bus
重构后: simple_cpu_top → cpu_bus_bridge (3-state FSM) → ahb_periph_bus
```

**变更文件**：

| 文件 | 行数 | 变更 |
|------|------|------|
| `core/cpu_bus_bridge.v` | 143 | 新建：AHB-Lite 主设备 FSM，CPU 侧 req/resp + AHB-Lite 侧 master 信号 |
| `core/simple_cpu_top.v` | 669→573 | 移除内联 FSM，实例化 `cpu_bus_bridge`，移除 `` `include "ahb_def.vh" `` |

**`cpu_bus_bridge` 接口**：

| 方向 | 信号 | 说明 |
|------|------|------|
| CPU 侧输入 | `icache_mmio_req/addr` | I 侧 MMIO 请求 |
| CPU 侧输入 | `dcache_mmio_req/addr/wdata/hwrite/hsize` | D 侧 MMIO 请求 |
| CPU 侧输出 | `ahb_inst_data/valid` | I 侧 AHB 读数据 + 有效脉冲 |
| CPU 侧输出 | `ahb_data_rdata/valid` | D 侧 AHB 读数据 + 有效脉冲 |
| AHB-Lite 输出 | `HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK/HWDATA` | 主设备信号 |
| AHB-Lite 输入 | `HRDATA/HREADY/HRESP` | 从设备响应 |

**测试结果**：全部零回归

| 测试 | 结果 |
|------|------|
| `tb_simple_cpu_top` | 34/34 PASS |
| `tb_ahb_bus` | 3/3 PASS |
| `tb_led_marquee` | 16/16 PASS |
| `tb_uart_hello` | 12/12 PASS |

---

### 2026-05-05 CSR 与 异常/Trap 重构（cpu_trap_csr 提取）

**动机**：`simple_cpu_top.v` 内联大量 CSR 和异常/Trap glue 逻辑（~130 行），包括异常检测与注册、CSR 写解码（funct3 分派 + new_val 计算 + no_write 判断）、CSR WB 总线构造、`cpu_csr` 和 `cpu_clint` 实例化。将这些提取为独立模块 `cpu_trap_csr`，降低顶层复杂度。

**架构变更**：

```
重构前: simple_cpu_top (内联异常检测 + CSR 写解码 + cpu_csr + cpu_clint)
重构后: simple_cpu_top → cpu_trap_csr (异常检测 + CSR 写解码 + cpu_csr + cpu_clint)
```

**变更文件**：

| 文件 | 行数 | 变更 |
|------|------|------|
| `core/cpu_trap_csr.v` | 209 | 新建：封装异常检测/注册 + CSR 写解码 + cpu_csr + cpu_clint |
| `core/simple_cpu_top.v` | 573→439 | 移除 CSR/异常内联逻辑，实例化 `cpu_trap_csr` |

**`cpu_trap_csr` 接口**：

| 方向 | 信号 | 说明 |
|------|------|------|
| 输入 | `id_valid/id_done/dec_illegal/dec_is_ecall/dec_is_ebreak/id_pc/id_inst/dec_csr_addr` | Decode 阶段异常源 |
| 输入 | `mem_valid/mem_done/mem_misalign_*/mem_pc` | MEM 阶段异常源 |
| 输入 | `id_exe_bus_r[315:0]` | CSR 指令字段提取源 |
| 输入 | `csr_valid/trap_enter_valid/trap_return_valid` | 控制器信号 |
| 输入 | `timer_irq/current_pc` | 中断输入 |
| 输出 | `exception_at_decode` | Decode 阶段异常标志 → 控制器 |
| 输出 | `trap_pending` | 中断待处理 → 控制器 |
| 输出 | `csr_read_data` | CSR 读数据 → 执行级 |
| 输出 | `csr_wb_bus[167:0]` | CSR 写回总线 → 流水线寄存器 |
| 输出 | `trap_pc[31:0]` | Trap 目标 PC → PC 更新 |
| 输出 | `csr_pc_plus4[31:0]` | CSR 指令 PC+4 → PC 更新 |

**测试结果**：全部零回归

| 测试 | 结果 |
|------|------|
| `tb_simple_cpu_top` | 34/34 PASS |
| `tb_ahb_bus` | 3/3 PASS |
| `tb_led_marquee` | 16/16 PASS |
| `tb_uart_hello` | 12/12 PASS |

---

### 2026-05-05 CSR 与 异常/Trap 进一步拆分

**动机**：`cpu_trap_csr.v`（209 行）内部混合了异常/trap 决策逻辑与 CSR 读写解码逻辑，职责不够单一。拆分为 `cpu_trap_manager`（异常捕获 + trap 决策）和 `cpu_csr_interface`（CSR 读写 + 写回总线），`cpu_trap_csr` 退化为薄包装层。

**架构变更**：

```
重构前: cpu_trap_csr (异常检测 + CSR 写解码 + cpu_csr + cpu_clint)
重构后: cpu_trap_csr (薄包装)
          ├── cpu_trap_manager (异常检测/注册 + cpu_clint + trap_pending)
          └── cpu_csr_interface (CSR 字段提取 + 写解码 + csr_wb_bus + cpu_csr)
```

**变更文件**：

| 文件 | 行数 | 变更 |
|------|------|------|
| `core/cpu_trap_manager.v` | 129 | 新建：异常检测/注册 + `cpu_clint` 实例 + `trap_pending` 计算 |
| `core/cpu_csr_interface.v` | 103 | 新建：CSR 字段提取 + funct3 分派 + `csr_wb_bus` 构造 + `cpu_csr` 实例 |
| `core/cpu_trap_csr.v` | 209→109 | 退化为薄包装层，仅实例化两个子模块并连线 |

**模块职责**：

| 模块 | 职责 | 子模块 |
|------|------|--------|
| `cpu_trap_manager` | Decode/MEM 异常检测 → 注册 → `cpu_clint` → `trap_pending`/`trap_pc`/`hw_csr_*` | `cpu_clint` |
| `cpu_csr_interface` | `id_exe_bus_r` 字段提取 → funct3 分派 → `sw_csr_*` → `cpu_csr` → `csr_wb_bus` | `cpu_csr` |
| `cpu_trap_csr` | 信号连线（`hw_csr_*` 和 CSR 值交叉连接） | 上述两个 |

**交叉连接**：`cpu_trap_manager` 输出 `hw_csr_*` → `cpu_csr_interface` 输入；`cpu_csr_interface` 输出 CSR 值 → `cpu_trap_manager` 输入（供 `cpu_clint` 读取）。

**测试结果**：全部零回归

| 测试 | 结果 |
|------|------|
| `tb_simple_cpu_top` | 34/34 PASS |
| `tb_ahb_bus` | 3/3 PASS |
| `tb_led_marquee` | 16/16 PASS |
| `tb_uart_hello` | 12/12 PASS |
