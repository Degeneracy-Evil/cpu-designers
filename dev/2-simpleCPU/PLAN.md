# simpleCPU 接入 Bus4LZU 总线器件计划（busip分支）

## 1. 目标与范围

将当前 `dev/2-simpleCPU` 的多周期 CPU 从“内部 BRAM 直连”模型，迁移到通过 **Bus4LZU 总线控制器** 访问外部存储器与外设（UART/GPIO/Timer/SPI）。

保留现有 CSR/中断/异常体系，仅改造存储器访问层与顶层集成。

## 2. 设计决策

| 决策项 | 方案 | 理由 |
|--------|------|------|
| 取指延迟模型 | **1周期延迟**（发地址→下一周期得指令） | Bus4LZU 读操作固定1周期延迟；参考 livep-2 `prefetch.v` 的 RESET/IDLE/Normal 三级状态机处理 bubble |
| 访存写使能 | **4位字节掩码 `dataWen_4[3:0]`** | Bus4LZU 支持字节级写使能；参考 livep-2 `lsu.v` 直接生成掩码，无需 read-modify-write |
| 地址宽度 | **32位字节地址** | Bus4LZU 使用完整字节地址；当前 `pc[12:2]` / `alu_result[12:2]` 需扩展为 `instAddr_32` / `dataAddr_32` |
| 初始化控制 | **接入 `init_sig`** | Bus4LZU 在 UART 加载程序期间拉高 `init_sig`；CPU 状态机必须暂停，防止执行空内存 |
| 复位极性 | **CPU 内部保持 `reset` 高有效，顶层反相为 `rstn` 连接 Bus4LZU** | 与当前 CPU 内部模块一致，减少内部改动；顶层做极性转换 |
| 内部 cache | **移除 `icache.v` / `dcache.v` 行为模型** | 接入 Bus4LZU 后，存储器由总线控制器管理；测试阶段可用简化 BRAM wrapper 替代真实总线做单元测试 |
| 外设中断 | **Timer 中断接入 `timer_iqr` → MEIP** | Bus4LZU 提供 `timer_iqr`；替换当前仅由 UART RX 驱动的 MEIP，实现完整中断源 |

## 3. 关键接口映射

### 3.1 CPU → Bus4LZU（simple_cpu_top 输出）

| CPU 侧信号 | Bus4LZU 侧信号 | 位宽 | 说明 |
|-----------|---------------|------|------|
| `instAddr_32` | `.instAddr_32` | 32 | PC 直接输出（字节地址） |
| `dataWen_4` | `.dataWen_4` | 4 | 字节写掩码；全1表示读，全0表示字写，部分0表示字节/半字写 |
| `dataAddr_32` | `.dataAddr_32` | 32 | 访存地址（字节地址） |
| `writeData_32` | `.writeData_32` | 32 | store 数据（字节/半字需按地址偏移对齐到对应字节 lane） |

### 3.2 Bus4LZU → CPU（simple_cpu_top 输入）

| Bus4LZU 侧信号 | CPU 侧信号 | 位宽 | 说明 |
|---------------|-----------|------|------|
| `.instData_32` | `instData_32` | 32 | 指令数据，读延迟1周期 |
| `.readData_32` | `readData_32` | 32 | load 数据，读延迟1周期 |
| `.init_sig` | `init_sig` | 1 | 初始化暂停信号，高有效时冻结 PC 与状态机 |
| `.timer_iqr` | `timer_irq` | 1 | 定时器中断，接入 cpu_csr 的 `ext_meip` |

### 3.3 系统信号

| 信号 | 方向 | 处理 |
|------|------|------|
| `clk` | 输入 | 直连 |
| `reset` (高有效) | 输入 | CPU 内部使用；顶层反相生成 `rstn` 给 Bus4LZU |
| `uart_rx` / `uart_tx` | 输入/输出 | 直连 Bus4LZU 的 `rx` / `tx` |
| `spi_miso` / `spi_mosi` / `spi_ss` / `spi_clk` | 输入/输出 | 直连 |
| `gpio_io` | 双向 | 直连（位宽匹配 `gpio_num` 参数，默认16） |

## 4. 实现步骤

### Phase 1：Fetch 阶段改造（参考 livep-2 prefetch）

**目标**：适配1周期延迟的指令读取。

- **文件**：`rtl/cpu_fetch.v`
- **改造内容**：
  1. 移除 `icache_en` / `icache_addr`（11位字地址），改为输出 `instAddr_32[31:0]`（字节地址，等于 PC）。
  2. 输入由 `inst_data` 改为 `instData_32`。
  3. 引入 **2状态机**：`IF_IDLE` → `IF_WAIT`。
     - `IF_IDLE`：`if_valid` 到来时发地址，进入等待。
     - `IF_WAIT`：下一周期 `instData_32` 有效，`if_done=1`，返回 IDLE。
  4. 当 `init_sig` 为高时，冻结在 `IF_IDLE`（不推进，不置 `if_done`）。

### Phase 2：Mem 阶段改造（参考 livep-2 lsu）

**目标**：适配4位字节写使能与1周期读延迟，消除 read-modify-write。

- **文件**：`rtl/cpu_mem.v`
- **改造内容**：
  1. 移除 `MEM_WRITE_MODIFY` / `MEM_WRITE_COMMIT` 状态（不再需要）。
  2. 输出改为 `dataWen_4[3:0]`、`dataAddr_32[31:0]`、`writeData_32[31:0]`。
  3. **字节写掩码生成逻辑**（参考 livep-2 `lsu.v`）：
     - `sw`：根据 `byte_offset` 生成掩码（`0000`=全写, `0001`, `0011`, `0111` 用于未对齐字）。
     - `sh`：根据 `byte_offset` 生成掩码（`1100`, `1001`, `0011`, `0111`）。
     - `sb`：根据 `byte_offset` 生成掩码（`1110`, `1101`, `1011`, `0111`）。
     - 读操作：`dataWen_4 = 4'b1111`（Bus4LZU 文档中 `rd_en` / `wr_en` 由总线内部根据 `dataWen_4` 解码，或按 livep-2 惯例 1111 表示读）。
  4. store 数据对齐：字节/半字 store 需根据 `byte_offset` 将数据移位到正确的字节 lane（参考 livep-2）。
  5. load 时序调整：
     - `MEM_IDLE`：检测 load，输出地址 + `dataWen_4=4'b1111`，进入 `MEM_READ_WAIT`。
     - `MEM_READ_WAIT`：下一周期 `readData_32` 有效，进行字节/半字提取，置 `mem_done`，返回 `MEM_IDLE`。
  6. store 时序调整：
     - `MEM_IDLE`：检测 store，输出地址/数据/掩码，当周期置 `mem_done`（Bus4LZU 写无延迟）。

### Phase 3：Controller 状态机适配

**目标**：兼容 `init_sig` 暂停。

- **文件**：`rtl/cpu_controller.v`
- **改造内容**：
  1. 增加 `init_sig` 输入。
  2. 所有状态转移增加 `init_sig` 门控：当 `init_sig == 1` 时，强制 `next_state = STATE_IDLE`（或等效暂停状态）。
  3. 所有 `*_valid` 输出增加 `!init_sig` 条件。

### Phase 4：顶层重构

**目标**：移除内部 cache，集成 Bus4LZU 接口。

- **文件**：`rtl/simple_cpu_top.v`
- **改造内容**：
  1. **移除模块实例化**：删除 `icache u_icache(...)` 和 `dcache u_dcache(...)`。
  2. **新增总线接口端口**：
     - 输出：`instAddr_32`, `dataWen_4`, `dataAddr_32`, `writeData_32`
     - 输入：`instData_32`, `readData_32`, `init_sig`, `timer_irq`
  3. **内部信号重连**：
     - `cpu_fetch` 的 `inst_data` 改为 `instData_32`。
     - `cpu_mem` 的 `dcache_rdata` 改为 `readData_32`。
  4. **中断源切换**：`cpu_csr` 的 `ext_meip` 由 `uart_rx_valid` 改为 `timer_irq`（或保留两者经或门合并，视测试需求）。
  5. **复位反相**：生成 `rstn = ~reset`，用于未来顶层与 Bus4LZU 直连时信号极性匹配（当前测试环境可内部产生）。
  6. **调试端口 `mem_data` 保留**：通过 `mem_addr` 访问 dcache 的端口不再有效；改为通过总线读取或暂时保留内部 debug 通路（测试阶段可用）。

### Phase 5：总线 wrapper / 测试辅助（参考 livep-2 memory_slot + bus_top）

**目标**：在缺少真实 Bus4LZU IP 核源码的情况下，建立可编译仿真的测试环境。

- **新建文件**：`rtl/bus4lzu_mock.v`（或参考 livep-2 结构）
- **内容**：
  1. **简化 BRAM**：2块 32-bit × 2048 的 RAM（8KB I-Mem + 8KB D-Mem），行为模型，1周期读延迟，支持4位字节写使能。
  2. **init_sig 生成逻辑**：上电后固定延迟（如100周期）后拉低 `init_sig`，模拟 UART 加载完成；或使用 testbench 直接控制。
  3. **Timer 模拟**：简化计数器，达到阈值后输出 `timer_irq` 一个周期。
  4. **地址解码**：`0x0000_0000 - 0x0000_FFFF` → I-Mem/D-Mem；`0x1001_0000` 区间 → Timer；其余可忽略或返回0。
- **参考**：`example/livep-2/rtl/memory_slot.v` 的初始化选择器逻辑、`example/livep-2/rtl/bus_top.v` 的从设备多路复用。

### Phase 6：Testbench 改造

**目标**：验证总线接入后的功能正确性。

- **文件**：`tb/tb_simple_cpu_top.v`
- **改造内容**：
  1. 移除对 `mem_data` 的依赖（或改为通过总线 wrapper 读取）。
  2. 增加 `init_sig` 控制：复位后保持 `init_sig=1` 若干周期，再拉低释放 CPU。
  3. 实例化 `bus4lzu_mock` 作为总线代理，连接 CPU 的总线端口。
  4. 保留现有33项基础测试 + CSR 异常测试用例，确保总线改造不破坏已有功能。
  5. **新增测试**：
     - 基础算术/逻辑/分支（原有33项）。
     - CSR 读写 + 异常（ECALL/EBREAK/非法指令）。
     - **Timer 中断测试**：配置 timer 计数器，等待 `timer_irq` 触发，验证中断进入/返回流程。
     - **字节/半字 store/load 对齐测试**：验证 `dataWen_4` 掩码生成与数据提取正确。

### Phase 7：综合验证与回归

- 使用 `tools/mk.py` 编译仿真全部测试：
  ```bash
  python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v
  ```
- 使用 `tools/rv2coe.py` 生成测试程序的 COE/HEX：
  ```bash
  python3 tools/rv2coe.py -i dev/2-simpleCPU/program_source/test.S -o dev/2-simpleCPU/program_source/icache_init.hex
  ```
- 确保原有测试全部 PASS，新增 Timer 中断测试 PASS。

## 5. 总线位宽与信号变更汇总

| 模块 | 变更项 | 变更前 | 变更后 |
|------|--------|--------|--------|
| `cpu_fetch` | 输出地址 | `icache_en`, `icache_addr[10:0]` | `instAddr_32[31:0]` |
| `cpu_fetch` | 输入数据 | `inst_data[31:0]` | `instData_32[31:0]` |
| `cpu_fetch` | 内部逻辑 | 组合逻辑当周期完成 | 1周期延迟 + 等待状态机 |
| `cpu_mem` | 输出 | `dcache_en`, `dcache_we[0:0]`, `dcache_addr[10:0]`, `dcache_wdata[31:0]` | `dataWen_4[3:0]`, `dataAddr_32[31:0]`, `writeData_32[31:0]` |
| `cpu_mem` | 输入 | `dcache_rdata[31:0]` | `readData_32[31:0]` |
| `cpu_mem` | store 逻辑 | read-modify-write (3周期) | 直接字节掩码 (1周期) |
| `cpu_mem` | load 逻辑 | 当周期完成 (2状态) | 1周期等待 (3状态) |
| `cpu_controller` | 新增输入 | — | `init_sig` |
| `simple_cpu_top` | 移除模块 | `icache`, `dcache`, `uart_top` | — |
| `simple_cpu_top` | 新增端口 | — | 总线接口 + `init_sig` + `timer_irq` |
| `simple_cpu_top` | 中断源 | `uart_rx_valid` → MEIP | `timer_irq` → MEIP（或合并） |

## 6. 风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|----------|
| fetch 1周期延迟引入后 controller 停留时间变长导致整体周期增加 | 性能下降（仿真时间变长） | 多周期 CPU 天然串行，controller 在 FETCH 多停留1周期不影响正确性；确认所有测试在增加周期数后仍能通过 |
| store 字节掩码生成错误导致内存污染 | 测试失败 | 参考 livep-2 `lsu.v` 掩码表，逐项验证 sb/sh/sw 四种偏移 |
| `init_sig` 与现有复位/异常状态机冲突 | 死锁或异常丢失 | `init_sig` 仅冻结状态机到 IDLE，不重置任何寄存器；释放后从 IDLE→FETCH 自然恢复 |
| 移除内部 cache 后仿真测试无法初始化指令内存 | 无法运行测试 | 在 `bus4lzu_mock` 中支持通过 `readmemh` 直接加载 HEX；或使用 testbench 预写内存 |

## 7. 工具使用指南

### 编译仿真
```bash
# 完整编译+运行
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v

# 仅编译
python tools/mk.py --top dev/2-simpleCPU/tb/tb_simple_cpu_top.v --compile-only
```

### 生成测试程序
```bash
# 汇编 -> HEX（用于 mock BRAM 初始化）
python3 tools/rv2coe.py \
  -i dev/2-simpleCPU/program_source/test.S \
  -o dev/2-simpleCPU/program_source/icache_init.hex \
  --depth 2048
```

### 参考代码速查
- **1周期延迟 fetch + bubble**：`example/livep-2/rtl/cpu_core/prefetch.v`
- **4位字节写使能 LSU**：`example/livep-2/rtl/cpu_core/lsu.v`
- **初始化选择器 + 双口 RAM**：`example/livep-2/rtl/memory_slot.v`
- **总线地址解码 + 从设备 MUX**：`example/livep-2/rtl/bus_top.v`
- **Bus4LZU 实例化模板**：`Reference/Bus4LZU/bus_interface.v`

## 8. 目录结构变更

```
dev/2-simpleCPU/
├── rtl/
│   ├── cpu_fetch.v          # 修改：1周期延迟取指
│   ├── cpu_mem.v            # 修改：字节掩码 + 1周期读延迟
│   ├── cpu_controller.v     # 修改：init_sig 门控
│   ├── simple_cpu_top.v     # 修改：总线接口集成
│   ├── bus4lzu_mock.v       # 新增：仿真用总线代理
│   ├── icache.v             # 保留但不再实例化（或删除）
│   ├── dcache.v             # 保留但不再实例化（或删除）
│   └── uart_*.v             # 保留但不再实例化（Bus4LZU 内含 UART）
├── tb/
│   └── tb_simple_cpu_top.v  # 修改：接入 mock 总线
├── program_source/
│   └── icache_init.hex      # 由 rv2coe.py 生成，供 mock BRAM 加载
└── PLAN.md                  # 本文件
```

---

**变更日期**：2026-04-25  
**分支**：`busip`  
**前提**：当前分支已完成 CSR/中断/异常全功能实现（PROCESS.md 第1-15项中除中断测试外全部完成）
