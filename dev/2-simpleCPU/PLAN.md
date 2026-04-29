# simpleCPU 融合 Bus4LZU IP 源码计划（busip分支）

## 1. 目标与范围

将 `Reference/Bus4LZU` 中的 **Bus4LZU IP 真实源码** 融合到 `dev/2-simpleCPU` 项目中，替换当前仿真用的 `bus4lzu_mock.v`，使 CPU 可直接与真实总线控制器 RTL 协同仿真与综合。

**前置条件**：Phase 1-6（CPU 改造 + mock 验证）已全部完成，78 项测试全部 PASS。

## 2. Bus4LZU IP 源码结构

源码根目录：`Reference/Bus4LZU/`

```
Reference/Bus4LZU/
├── bus_interface.v              # 实例化模板（bus4LZU_0）
├── Bus4LZU文档.md               # 技术文档
├── component.xml                # Vivado IP 组件定义（VLNV: Asyncsys:bus:bus4LZU:1.0, Rev4）
├── xgui/
│   └── bus4LZU_v1_0.tcl         # Vivado GUI 定制脚本
└── sources_1/
    ├── ip/
    │   └── Sram/                 # Xilinx blk_mem_gen IP（BRAM）
    │       ├── Sram.xci          # IP 配置文件
    │       ├── Sram.dcp          # 综合后网表
    │       ├── Sram_stub.v       # Verilog stub
    │       └── ...               # 其他（hdl/sim/synth/doc等）
    └── new/
        ├── soc_core.v            # 顶层模块（component.xml 中 modelName）
        ├── header/
        │   ├── bus_define.vh     # 总线地址/参数定义
        │   └── timer_define.vh   # Timer 寄存器定义
        ├── slot/
        │   ├── bus_addr_decoder.v  # 地址解码器
        │   ├── bus_slave_mux.v     # 从设备数据多路复用
        │   ├── bus_top.v           # 总线顶层（解码+MUX+初始化）
        │   ├── data_init.v         # UART 数据加载/校验/分流
        │   ├── data_mux.v          # 初始化选择器（UART vs CPU）
        │   └── memory_slot.v       # SRAM 封装（双口 BRAM）
        └── perips/
            ├── gpio.v             # GPIO 模块
            ├── spi.v              # SPI 模块
            ├── timer.v            # Timer 模块
            ├── uart_rx.v          # UART 接收
            ├── uart_tx.v          # UART 发送
            └── uart_top.v         # UART 顶层
```

### 2.1 关键源文件说明

| 文件 | 作用 | 对 mock 的对应 |
|------|------|---------------|
| `soc_core.v` | IP 顶层，例化 bus_top + perips | `bus4lzu_mock.v` 整体 |
| `bus_top.v` | 地址解码 + 从设备 MUX + 初始化控制 | mock 内地址解码逻辑 |
| `bus_addr_decoder.v` | 0x0000-0xFFFF→SRAM, 0x10000+→外设 | mock 内 `addr < 16'h10000` 判断 |
| `bus_slave_mux.v` | 多从设备读数据选择 | mock 内单 SRAM 直连 |
| `memory_slot.v` | SRAM 双口封装（ICache + DCache） | mock 内 `imem`/`dmem` 行为模型 |
| `data_init.v` | UART 加载程序 + Checksum 校验 + I/D 分流 | mock 内 `init_sig` 固定延迟 |
| `data_mux.v` | 初始化选择器（UART 写 vs CPU 写） | mock 内无（组合读0延迟） |
| `timer.v` | Timer 计数器 + `timer_irq` 中断 | mock 内 Timer mock |
| `gpio.v` / `spi.v` | GPIO / SPI 外设 | mock 内无（未实现） |
| `uart_top.v` / `uart_rx.v` / `uart_tx.v` | UART 串口 | mock 内无（init_sig 跳过加载） |
| `bus_define.vh` | 地址空间/偏移常量 | mock 内硬编码地址 |
| `timer_define.vh` | Timer 寄存器偏移常量 | mock 内硬编码偏移 |
| `Sram.xci` / `Sram.dcp` | Xilinx BRAM IP 核 | mock 内 `reg [31:0] imem/dmem` |

### 2.2 IP 可配置参数

| 参数 | 范围 | 默认值 | 说明 |
|------|------|--------|------|
| `CLK_FREQ` | 1-100 | 25 | 系统时钟频率(MHz)，影响 UART 波特率分频 |
| `GPIO_NUM` | 1-16 | 16 | GPIO 引脚数量，决定 `gpio_io` 位宽 |

### 2.3 IP 接口（bus_interface.v）

```verilog
bus4LZU_0 your_instance_name (
  .clk(clk),                    // input wire
  .rstn(rstn),                  // input wire  (低有效！)
  .rx(rx),                      // input wire  (UART RX)
  .tx(tx),                      // output wire (UART TX)
  .timer_irq(timer_irq),          // output wire
  .init_sig(init_sig),          // output wire (高有效，暂停CPU)
  .spi_miso(spi_miso),          // input wire
  .spi_mosi(spi_mosi),          // output wire
  .spi_ss(spi_ss),              // output wire
  .spi_clk(spi_clk),            // output wire
  .gpio_io(gpio_io),            // inout wire [15:0]
  .instAddr_32(instAddr_32),    // input wire [31:0]
  .instData_32(instData_32),    // output wire [31:0]
  .dataWen_4(dataWen_4),        // input wire [3:0]
  .dataAddr_32(dataAddr_32),    // input wire [31:0]
  .writeData_32(writeData_32),  // input wire [31:0]
  .readData_32(readData_32)     // output wire [31:0]
);
```

## 3. 设计决策

| 决策项 | 方案 | 理由 |
|--------|------|------|
| 源码引入方式 | **复制到 `rtl/bus4lzu/` 子目录** | 保持项目自包含，避免依赖外部 Reference 路径；便于后续修改适配 |
| 头文件处理 | **复制 `.vh` 到 `rtl/bus4lzu/header/`，仿真时通过 `-I` 指定 include 路径** | 与 Vivado IP 打包方式一致（component.xml 中 `isIncludeFile=true`） |
| BRAM IP 处理 | **仿真用行为模型替代 Sram.xci；综合用 Sram.dcp 或重新打包** | Sram.xci 依赖 Vivado blk_mem_gen，iverilog 无法直接编译；行为模型保持与真实 BRAM 时序一致（1周期读延迟） |
| mock 去留 | **保留 `bus4lzu_mock.v` 作为快速回归测试选项** | mock 编译快、无外部依赖，适合日常开发；真实 IP 用于完整验证 |
| UART 冲突 | **CPU 侧移除 `uart_top.v` 实例（已在 Phase 4 完成）** | Bus4LZU 内含 UART，CPU 不再直接驱动 UART |
| 复位极性 | **顶层 `rstn = ~reset` 连接 Bus4LZU** | Bus4LZU rstn 低有效，CPU reset 高有效，已在 Phase 4 确认 |

## 4. 关键接口映射（与原 PLAN 一致，此处确认无变更）

### 4.1 CPU → Bus4LZU

| CPU 侧信号 | Bus4LZU 侧信号 | 位宽 | 说明 |
|-----------|---------------|------|------|
| `instAddr_32` | `.instAddr_32` | 32 | PC 直接输出（字节地址） |
| `dataWen_4` | `.dataWen_4` | 4 | 字节写掩码；4'b1111=读，其他=写 |
| `dataAddr_32` | `.dataAddr_32` | 32 | 访存地址（字节地址） |
| `writeData_32` | `.writeData_32` | 32 | store 数据（已按地址偏移对齐） |

### 4.2 Bus4LZU → CPU

| Bus4LZU 侧信号 | CPU 侧信号 | 位宽 | 说明 |
|---------------|-----------|------|------|
| `.instData_32` | `instData_32` | 32 | 指令数据，读延迟1周期 |
| `.readData_32` | `readData_32` | 32 | load 数据，读延迟1周期 |
| `.init_sig` | `init_sig` | 1 | 初始化暂停信号 |
| `.timer_irq` | `timer_irq` | 1 | 定时器中断 → MTIP（mip[7]） |

## 5. 实现步骤

### Phase A：源码引入与目录准备

**目标**：将 Bus4LZU IP 源码复制到项目内，建立编译结构。

- **操作**：
  1. 创建 `rtl/bus4lzu/` 子目录结构：
     ```
     rtl/bus4lzu/
     ├── soc_core.v
     ├── header/
     │   ├── bus_define.vh
     │   └── timer_define.vh
     ├── slot/
     │   ├── bus_addr_decoder.v
     │   ├── bus_slave_mux.v
     │   ├── bus_top.v
     │   ├── data_init.v
     │   ├── data_mux.v
     │   └── memory_slot.v
     ├── perips/
     │   ├── gpio.v
     │   ├── spi.v
     │   ├── timer.v
     │   ├── uart_rx.v
     │   ├── uart_tx.v
     │   └── uart_top.v
     └── ip/
         └── sram_model.v        # 行为模型（替代 Sram.xci）
     ```
  2. 从 `Reference/Bus4LZU/sources_1/new/` 复制所有 `.v` / `.vh` 文件到对应子目录。
  3. 检查源码中的 `` `include `` 路径，确认与子目录结构匹配。

### Phase B：BRAM 行为模型适配

**目标**：创建 `sram_model.v` 替代 Xilinx blk_mem_gen IP，保持与真实 BRAM 的时序一致。

- **新建文件**：`rtl/bus4lzu/ip/sram_model.v`
- **内容**：
  1. 双口 RAM 行为模型（1读口 + 1写口），32位数据宽度。
  2. **读延迟1周期**（与 blk_mem_gen READ_LATENCY_A=1 一致）。
  3. 支持4位字节写使能（`dataWen_4` 掩码写入）。
  4. 支持 `$readmemh` 初始化（用于 ICache 预加载测试程序）。
- **修改 `memory_slot.v`**：
  1. 将 `Sram` IP 实例替换为 `sram_model` 实例。
  2. 确认端口映射：地址、写数据、读数据、写使能、时钟。
  3. 注意 `memory_slot.v` 可能例化两个 Sram（ICache + DCache），需分别替换。

### Phase C：源码适配与编译修复

**目标**：确保 Bus4LZU 源码在 iverilog 环境下可编译。

- **操作**：
  1. **头文件 include 路径**：确认 `bus_define.vh` / `timer_define.vh` 的 `` `include `` 方式（`"header/bus_define.vh"` vs `` `<bus_define.vh>` ``），必要时调整为相对路径。
  2. **Xilinx 原语替换**：检查源码中是否使用了 Xilinx 专用原语（如 `BUFG`、`IOBUF` 等），如有则替换为行为模型或移除。
  3. **参数传递**：确认 `CLK_FREQ` / `GPIO_NUM` 参数在 `soc_core.v` 中的传递方式，确保可在实例化时覆盖。
  4. **信号位宽/极性确认**：逐一对比 `bus_interface.v` 模板与 `soc_core.v` 端口声明，确保完全一致。
  5. **编译测试**：`iverilog` 单独编译 `soc_core.v` 及所有依赖，确保无 error。

### Phase D：顶层集成替换 mock

**目标**：在 testbench 中用真实 Bus4LZU 替换 `bus4lzu_mock.v`。

- **文件**：`tb/tb_simple_cpu_top.v`
- **改造内容**：
  1. 移除 `bus4lzu_mock` 实例。
  2. 新增 `soc_core`（或 `bus4LZU_0`）实例，按 `bus_interface.v` 模板连接：
     - CPU 总线信号直连（`instAddr_32` / `instData_32` / `dataWen_4` / `dataAddr_32` / `writeData_32` / `readData_32`）。
     - `clk` 直连。
     - `rstn = ~reset`（极性转换）。
     - `rx` / `tx` 连接 UART 引脚（或悬空，仿真中不使用 UART 加载）。
     - `spi_*` / `gpio_io` 悬空或接默认值。
  3. **init_sig 处理**：
     - 方案1：testbench `force u_bus.init_sig = 0` 跳过 UART 加载（与 Vivado IP-sim 一致）。
     - 方案2：保留 `init_sig` 自然行为，仿真开始后等待其拉低。
  4. **ICache 初始化**：通过 `sram_model` 的 `$readmemh` 预加载测试程序 HEX 文件。

### Phase E：回归测试与问题修复

**目标**：确保真实 Bus4LZU 替换后所有测试通过。

- **测试策略**：
  1. 先运行基础33项测试，确认取指/访存基本通路正确。
  2. 运行 CSR 20项测试，确认中断/异常通路不受影响。
  3. 运行 Timer 中断测试，确认 `timer_irq` 信号通路正确。
  4. 运行字节/半字对齐测试，确认 `dataWen_4` 掩码与 `readData_32` 提取正确。
- **预期问题**：
  - `memory_slot.v` 中 BRAM 实例化方式与 mock 不同，可能需调整地址位宽/深度。
  - `data_init.v` / `data_mux.v` 的初始化逻辑可能在 `init_sig=0`（force 跳过）时有副作用。
  - `bus_addr_decoder.v` 的地址空间划分需与 CPU 访问地址匹配（0x0000-0xFFFF SRAM，0x10000+ 外设）。

### Phase G：核心计时器中断（MTIP）集成

**目标**：将 Bus4LZU 的 `timer_irq` 信号正确连接为 MTIP（mip[7]），实现 RISC-V 标准定时器中断通路。

**背景**：当前 `cpu_clint.v` 仅处理 MEIP（bit 11）和 MSIP（bit 3），`timer_irq` 错误地连接到 MEIP。RISC-V 特权规范要求定时器中断对应 MTIP（mip[7]）和 MTIE（mie[7]），mcause = 0x80000007。

- **改造内容**：

  1. **`cpu_clint.v`**：
     - 新增 `ext_mtip` 输入端口（1 位，来自 `timer_irq`）。
     - `interrupt_pending` 增加 MTIP 条件：`mie_bit && ((meie_bit && meip_bit) || (mtie_bit && mtip_bit) || (msie_bit && msip_bit))`。
     - `interrupt_cause` 优先级更新：MSIP(3) > MTIP(7) > MEIP(11)。
       ```verilog
       assign interrupt_cause = (msie_bit && msip_bit) ? 32'h80000003 :
                                (mtie_bit && mtip_bit) ? 32'h80000007 :
                                32'h8000000B;
       ```
     - 新增 `mtie_bit = csr_mie[7]` 和 `mtip_bit` 提取。

  2. **`simple_cpu_top.v`**：
     - 将 `timer_irq` 连接到 `cpu_clint` 的 `ext_mtip` 端口（而非 `ext_meip`）。
     - 若 MEIP 仍需支持（如 UART 中断），需新增独立 `ext_meip` 输入端口。

  3. **`cpu_csr.v`**（如 mip 硬件位需要扩展）：
     - 确保 mip[7] 由硬件驱动（`mtip_bit = ext_mtip`），软件不可写。

- **测试策略**：
  1. 编写定时器中断测试程序：设置 mtimecmp、启动计时器、使能 MTIE + MIE、等待中断。
  2. 验证 mcause = 0x80000007。
  3. 验证中断返回后 mtime 清零（周期模式）或 start 清零（单次模式）。
  4. 验证多中断优先级：同时触发 MSIP + MTIP，确认 mcause = 3（MSIP 优先）。

### Phase H：编译脚本更新

**目标**：更新 `tools/mk.py` 或仿真脚本，支持真实 IP 编译及定时器中断测试。

- **操作**：
  1. 添加 `rtl/bus4lzu/` 下所有 `.v` 文件到编译文件列表。
  2. 添加 `-I rtl/bus4lzu/header` include 路径。
  3. 保留 mock 编译选项（可通过 `--use-mock` 参数切换）。
  4. 更新 `tools/rv2coe.py` 输出路径，确保 HEX 文件可被 `sram_model` 的 `$readmemh` 正确加载。

## 6. 总线位宽与信号变更汇总（与原 PLAN 一致）

| 模块 | 变更项 | 变更前 | 变更后 |
|------|--------|--------|--------|
| `cpu_fetch` | 输出地址 | `icache_en`, `icache_addr[10:0]` | `instAddr_32[31:0]` |
| `cpu_fetch` | 输入数据 | `inst_data[31:0]` | `instData_32[31:0]` |
| `cpu_fetch` | 内部逻辑 | 组合逻辑当周期完成 | 1周期延迟 + 等待状态机 |
| `cpu_mem` | 输出 | `dcache_en`, `dcache_we[0:0]`, `dcache_addr[10:0]`, `dcache_wdata[31:0]` | `dataWen_4[3:0]`, `dataAddr_32[31:0]`, `writeData_32[31:0]` |
| `cpu_mem` | 输入 | `dcache_rdata[31:0]` | `readData_32[31:0]` |
| `cpu_mem` | store 逻辑 | read-modify-write (3周期) | 直接字节掩码 (1周期) |
| `cpu_mem` | load 逻辑 | 当周期完成 (2状态) | 1周期等待 (3状态: IDLE→READ→READ2) |
| `cpu_controller` | 新增输入 | — | `init_sig` |
| `simple_cpu_top` | 移除模块 | `icache`, `dcache`, `uart_top` | — |
| `simple_cpu_top` | 新增端口 | — | 总线接口 + `init_sig` + `timer_irq` |
| `simple_cpu_top` | 中断源 | `uart_rx_valid` → MEIP | `timer_irq` → MTIP |

## 7. 风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|----------|
| Bus4LZU 源码含 Xilinx 专用原语/属性，iverilog 无法编译 | 仿真无法运行 | 逐文件检查，用 `` `ifdef `` 条件编译或行为模型替换 |
| `memory_slot.v` BRAM 接口与行为模型端口不匹配 | 编译/功能错误 | 先阅读 `memory_slot.v` 源码，按其端口声明编写 `sram_model.v` |
| `soc_core.v` 顶层模块名与 `bus_interface.v` 实例名不一致 | 实例化失败 | `bus_interface.v` 模板用 `bus4LZU_0`，`component.xml` 指定 `modelName=soc_top`，需确认实际模块名 |
| `data_init.v` UART 加载逻辑在 force `init_sig=0` 时仍有副作用 | CPU 误读 UART 数据 | 阅读源码确认 `init_sig` 与 `data_init` 的交互逻辑 |
| 地址空间划分与 CPU 预期不一致 | 外设访问失败 | 对比 `bus_addr_decoder.v` 与 `bus_define.vh` 的地址常量，确认与 CPU 侧一致 |
| BRAM 深度/位宽与测试程序不匹配 | 取指/访存越界 | 确认 Sram.xci 配置的深度/位宽，`sram_model.v` 保持一致 |

## 8. 工具使用指南

### 编译仿真（真实 IP）
```bash
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v
```

### 编译仿真（mock 回归）
```bash
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v --use-mock
```

### 生成测试程序
```bash
python3 tools/rv2coe.py \
  -i dev/2-simpleCPU/program_source/test.S \
  -o dev/2-simpleCPU/program_source/icache_init.hex \
  --depth 2048
```

### 参考代码速查
- **Bus4LZU 实例化模板**：`Reference/Bus4LZU/bus_interface.v`
- **Bus4LZU 技术文档**：`Reference/Bus4LZU/Bus4LZU文档.md`
- **Bus4LZU 顶层源码**：`Reference/Bus4LZU/sources_1/new/soc_core.v`
- **地址解码器**：`Reference/Bus4LZU/sources_1/new/slot/bus_addr_decoder.v`
- **总线顶层**：`Reference/Bus4LZU/sources_1/new/slot/bus_top.v`
- **SRAM 封装**：`Reference/Bus4LZU/sources_1/new/slot/memory_slot.v`
- **初始化控制**：`Reference/Bus4LZU/sources_1/new/slot/data_init.v`
- **1周期延迟 fetch**：`dev/2-simpleCPU/rtl/cpu_fetch.v`（已改造完成）
- **4位字节写使能 LSU**：`dev/2-simpleCPU/rtl/cpu_mem.v`（已改造完成）

## 9. 目录结构变更

```
dev/2-simpleCPU/
├── rtl/
│   ├── cpu_fetch.v              # 已改造：1周期延迟取指
│   ├── cpu_mem.v                # 已改造：字节掩码 + 1周期读延迟
│   ├── cpu_controller.v         # 已改造：init_sig 门控
│   ├── simple_cpu_top.v         # 已改造：总线接口集成
│   ├── bus4lzu_mock.v           # 保留：快速回归测试用
│   ├── bus4lzu/                 # 新增：真实 Bus4LZU IP 源码
│   │   ├── soc_core.v
│   │   ├── header/
│   │   │   ├── bus_define.vh
│   │   │   └── timer_define.vh
│   │   ├── slot/
│   │   │   ├── bus_addr_decoder.v
│   │   │   ├── bus_slave_mux.v
│   │   │   ├── bus_top.v
│   │   │   ├── data_init.v
│   │   │   ├── data_mux.v
│   │   │   └── memory_slot.v
│   │   ├── perips/
│   │   │   ├── gpio.v
│   │   │   ├── spi.v
│   │   │   ├── timer.v
│   │   │   ├── uart_rx.v
│   │   │   ├── uart_tx.v
│   │   │   └── uart_top.v
│   │   └── ip/
│   │       └── sram_model.v     # 新增：BRAM 行为模型
│   ├── icache.v                 # 保留但不再实例化
│   ├── dcache.v                 # 保留但不再实例化
│   └── uart_*.v                 # 保留但不再实例化
├── tb/
│   └── tb_simple_cpu_top.v      # 修改：接入真实 Bus4LZU（可切换 mock）
├── program_source/
│   └── icache_init.hex          # 由 rv2coe.py 生成，供 sram_model 加载
├── fpga/
│   ├── system_top.v             # FPGA 顶层（CPU + Bus4LZU IP）
│   └── cpu.xdc                  # 引脚约束
└── PLAN.md                      # 本文件
```

---

**变更日期**：2026-04-29  
**分支**：`busip`  
**当前阶段**：融合 Bus4LZU IP 真实源码 + MTIP 定时器中断集成（Phase A-H）  
**前提**：Phase 1-6（CPU 改造 + mock 验证）已完成，78 项测试全部 PASS；Vivado IP-sim 验证已完成（31/31 PASS）  
**MTIP 状态**：文档已更新，RTL 改造待实施（Phase G）
