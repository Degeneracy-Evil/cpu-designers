# simpleCPU bus重构计划

## 原因

为了获得更规范的总线架构以及更高的内存交换效率

## 选型

低速外设总线：APB (AMBA 3 APB4)

高速系统总线：AHB-Lite (AMBA 3 AHB-Lite)

## 设计

低速外设总线连接外设，高速系统总线连接外设总线桥以及主存。

系统总线数据位宽：32位

## 涉及的更改部分

构建：APB, AHB（已完成）

更改：core
  主要内容：cache（L1）封装进核心，构建：mem模块->MMU(暂时直接映射)->cache控制器->（未hit）缓存主存交换/MMIO访问外设 基本存储框架

目前主存缓存映射采用硬映射方式，即缓存即固定对应主存的低位部分。

更改：system_top：整合bus以及core以及LCD显示模块（主要调试用，所以直连核心、bus）

## 远景

在后续实验开始制作MMU等存储体系时不需要大改CPU架构

---

# 详细实施计划

## 一、架构总览

### 1.1 目标架构框图

```
                    +------------------+
                    |   system_top     |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
     +--------v--------+          +---------v---------+
     |  simple_cpu_top |          |   lcd_module      |
     |  (CPU Core)     |          |   (调试显示)      |
     +--------+--------+          +-------------------+
              |
     +--------v--------+
     |  cpu_bus_adapter |   ← 新建：CPU总线接口→AHB请求适配
     +--------+--------+
              |
     +--------v-----------------------------------+
     |              AHB-Lite 系统总线              |
     |  +----------+  +----------+  +----------+  |
     |  | ahb_     |  | ahb_     |  | ahb_     |  |
     |  | master   |  | decoder  |  | mux      |  |
     |  +----------+  +-----+----+  +----------+  |
     |                      |                      |
     |  +----------+  +----v-----+  +----------+  |
     |  | ahb_sram |  | ahb_lite |  | ahb_     |  |
     |  | _slave   |  | _to_apb  |  | default  |  |
     |  | (主存)   |  | (桥)     |  | _slave   |  |
     |  +----------+  +----+-----+  +----------+  |
     +----------------------|----------------------+
                            |
     +----------------------v----------------------+
     |              APB 外设总线                   |
     |  +----------+  +----------+  +----------+  |
     |  | apb_     |  | apb_     |  | apb_     |  |
     |  | decoder  |  | perips   |  | (master) |  |
     |  +----------+  +-----+----+  +----------+  |
     |                      |                      |
     |  +------+ +------+ +----+ +---+            |
     |  | GPIO | | Timer| |UART| |SPI|            |
     |  +------+ +------+ +----+ +---+            |
     +--------------------------------------------+
```

### 1.2 与当前架构的对比

| 项目 | 当前 (Bus4LZU) | 目标 (AHB+APB) |
|------|---------------|----------------|
| 系统总线 | Bus4LZU (自定义) | AHB-Lite (AMBA标准) |
| 外设总线 | Bus4LZU bus_top (自定义) | APB4 (AMBA标准) |
| 总线桥 | 无 (统一总线) | AHB-Lite-to-APB 桥 |
| CPU接口 | 直连Bus4LZU信号 | cpu_bus_adapter → AHB master |
| 主存 | memory_slot (SRAM) | ahb_sram_slave (SRAM) |
| 地址解码 | bus_addr_decoder (自定义) | ahb_decoder + apb_decoder |
| Cache | icache/dcache存在但未使用 | L1 I$/D$ 封装进核心 |

### 1.3 关键设计决策

**决策1：I+D统一AHB总线**
- CPU有独立的I侧(instAddr_32/instData_32)和D侧(dataAddr_32/writeData_32/readData_32)
- 方案：单AHB总线 + cpu_bus_adapter内部仲裁（I请求优先，D请求次之）
- 理由：与当前Bus4LZU统一SRAM架构一致，实现简单，避免双master复杂性

**决策2：init_sig处理**
- Bus4LZU的init_sig用于UART加载期间冻结CPU
- 方案：新架构中init_sig恒接0（使用COE初始化BRAM，无需UART加载）
- 理由：COE初始化已在Vivado验证中成功使用，UART加载为可选功能

**决策3：地址映射重新设计**
- 现有软件地址(UART@0x00010000, GPIO@0x00020000等)全部落入AHB SRAM区间
- 方案：重新设计AMBA规范的地址映射，同步更新所有测试程序
- 理由：AMBA标准地址空间应清晰分离主存与外设，避免地址冲突

---

## 二、地址映射设计

### 2.1 AHB-Lite地址映射（4 Slave, HADDR[31:20]解码）

| Slave | HSELx | 地址范围 | 大小 | 功能 |
|-------|-------|---------|------|------|
| 0 | HSELx[0] | 0x00000000 - 0x000FFFFF | 1MB | 主存SRAM (ahb_sram_slave) |
| 1 | HSELx[1] | 0x00100000 - 0x001FFFFF | 1MB | AHB-to-APB桥 (外设) |
| 2 | HSELx[2] | 0x10000000 - 0x100FFFFF | 1MB | 保留 (未来MMIO扩展) |
| 3 | HSELx[3] | 其余 | - | 默认从设备 (ERROR) |

### 2.2 APB外设地址映射（4 Slave, PADDR[15:14]解码）

APB地址空间位于AHB Slave 1范围内(0x00100000-0x001FFFFF)。

| PSELx | 地址范围 | 大小 | 外设 | 对应Bus4LZU旧地址 |
|-------|---------|------|------|-------------------|
| PSELx[0] | 0x00100000 - 0x00103FFF | 16KB | GPIO | 0x00020000 |
| PSELx[1] | 0x00104000 - 0x00107FFF | 16KB | Timer | 0x10010000 |
| PSELx[2] | 0x00108000 - 0x0010BFFF | 16KB | UART | 0x00010000 |
| PSELx[3] | 0x0010C000 - 0x0010FFFF | 16KB | SPI | 0x00080000 |

### 2.3 APB解码器修改

当前apb_decoder使用PADDR[31:30]（4 Slave）或PADDR[31:29]（8 Slave）进行高位解码，
粒度过粗（每区1GB/512MB），不适合外设寻址。

修改为使用PADDR[15:14]进行解码（每区16KB），匹配AHB-to-APB桥传递的地址：

```verilog
// 4 Slave APB decoder (modified)
assign PSELx[0] = (PADDR[15:14] == 2'b00);  // GPIO  @ 0x00100000
assign PSELx[1] = (PADDR[15:14] == 2'b01);  // Timer @ 0x00104000
assign PSELx[2] = (PADDR[15:14] == 2'b10);  // UART  @ 0x00108000
assign PSELx[3] = (PADDR[15:14] == 2'b11);  // SPI   @ 0x0010C000
```

### 2.4 地址映射汇总（软件视角）

| 用途 | 新地址 | 旧地址(Bus4LZU) | 偏移/说明 |
|------|--------|----------------|----------|
| 主存SRAM | 0x00000000 | 0x00000000 | 不变 |
| GPIO CTRL | 0x00100000 | 0x00020000 | +0x000E0000 |
| GPIO DATA | 0x00100004 | 0x00020004 | +0x000E0000 |
| Timer EXPR | 0x00104000 | 0x10010000 | 完全重映射 |
| Timer CTRL | 0x00104004 | 0x10010004 | 完全重映射 |
| Timer INTR | 0x00104008 | 0x10010008 | 完全重映射 |
| Timer COUNTER | 0x0010400C | 0x1001000C | 完全重映射 |
| UART | 0x00108000 | 0x00010000 | +0x000F8000 |
| SPI | 0x0010C000 | 0x00080000 | +0x0008C000 |

---

## 三、新增模块设计

### 3.1 cpu_bus_adapter（CPU总线→AHB请求适配器）

**职责**：将CPU核心的Bus4LZU风格接口转换为AHB-Lite master的req/resp接口，
并处理I侧/D侧的仲裁。

**接口定义**：

```verilog
module cpu_bus_adapter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                        clk,
    input  wire                        resetn,

    // CPU I-side interface (Bus4LZU style)
    input  wire  [ADDR_WIDTH-1:0]      inst_addr,       // instAddr_32
    output wire  [DATA_WIDTH-1:0]      inst_data,       // instData_32
    input  wire                        inst_req,        // if_valid (取指请求)

    // CPU D-side interface (Bus4LZU style)
    input  wire  [ADDR_WIDTH-1:0]      data_addr,       // dataAddr_32
    input  wire  [DATA_WIDTH-1:0]      data_wdata,      // writeData_32
    output wire  [DATA_WIDTH-1:0]      data_rdata,      // readData_32
    input  wire  [3:0]                 data_wen,        // dataWen_4 (反相: 1111=read)
    input  wire                        data_req,        // mem_en

    // AHB-Lite master request interface
    output reg                         req_valid,
    output reg                         req_write,
    output reg  [ADDR_WIDTH-1:0]       req_addr,
    output reg  [DATA_WIDTH-1:0]       req_wdata,
    output reg  [2:0]                  req_size,        // HSIZE
    output reg  [2:0]                  req_burst,
    output reg  [3:0]                  req_prot,
    output reg                         req_lock,

    // AHB-Lite master response interface
    input  wire                        req_ready,
    input  wire                        resp_valid,
    input  wire                        resp_error,
    input  wire  [DATA_WIDTH-1:0]      resp_rdata
);
```

**dataWen_4 → req_write/req_size 转换逻辑**：

| dataWen_4 | 含义 | req_write | req_size (HSIZE) |
|-----------|------|-----------|-----------------|
| 4'b1111 | 读 (word) | 0 | 3'b010 (WORD) |
| 4'b1110 | 写 byte0 | 1 | 3'b000 (BYTE) |
| 4'b1101 | 写 byte1 | 1 | 3'b000 (BYTE) |
| 4'b1011 | 写 byte2 | 1 | 3'b000 (BYTE) |
| 4'b0111 | 写 byte3 | 1 | 3'b000 (BYTE) |
| 4'b1100 | 写 halfword0 | 1 | 3'b001 (HWORD) |
| 4'b0011 | 写 halfword1 | 1 | 3'b001 (HWORD) |
| 4'b0000 | 写 word | 1 | 3'b010 (WORD) |

**I/D仲裁策略**：
- 状态机：IDLE → I_REQ → I_WAIT → D_REQ → D_WAIT → IDLE
- I请求优先：当if_valid有效时优先发出I侧AHB请求
- D请求跟随：I侧完成后若有data_req则发出D侧AHB请求
- 响应路由：根据当前服务侧(I/D)将resp_rdata路由到inst_data或data_rdata

**延迟处理**：
- CPU fetch阶段已有r_wait机制处理1周期读延迟
- CPU mem阶段已有MEM_READ2状态处理1周期读延迟
- AHB master的2相位(ADDR+DATA)协议增加额外1周期延迟
- 需在adapter中处理：req_valid发出后等待req_ready，resp_valid返回后才能完成

### 3.2 ahb_periph_bus（AHB异构总线顶层）

**职责**：替代当前ahb_bus（全SRAM slave），支持异构从设备（SRAM + AHB-to-APB桥 + 默认）。

**与ahb_bus的区别**：
- Slave 0: ahb_sram_slave (主存SRAM，可COE初始化)
- Slave 1: ahb_lite_to_apb + apb_perips (外设桥)
- Slave 2: 保留 (可接未来MMIO设备)
- Slave 3: ahb_default_slave (错误响应)

**接口定义**：

```verilog
module ahb_periph_bus #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter MEM_DEPTH   = 8192,
    parameter WAIT_STATES = 0,
    parameter GPIO_NUM    = 16,
    parameter UART_FREQ   = 25
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    // AHB master request
    input  wire                    req_valid,
    input  wire                    req_write,
    input  wire  [ADDR_WIDTH-1:0]  req_addr,
    input  wire  [DATA_WIDTH-1:0]  req_wdata,
    input  wire  [2:0]             req_size,
    input  wire  [2:0]             req_burst,
    input  wire  [3:0]             req_prot,
    input  wire                    req_lock,

    // AHB master response
    output wire                    req_ready,
    output wire                    resp_valid,
    output wire                    resp_error,
    output wire  [DATA_WIDTH-1:0]  resp_rdata,

    // Peripheral external pins
    output wire                    o_timer_irq,
    inout  wire [GPIO_NUM-1:0]     io_gpioPin,
    input  wire                    i_uart_rx,
    output wire                    o_uart_tx,
    output wire                    o_spiMosi,
    input  wire                    i_spiMiso,
    output wire                    o_spiSs,
    output wire                    o_spiClk
);
```

**内部结构**：
```
ahb_periph_bus
  ├── ahb_master          (请求→AHB信号)
  ├── ahb_decoder         (HADDR→HSELx[3:0])
  ├── ahb_mux             (多slave响应→总线响应)
  ├── ahb_sram_slave[0]   (主存SRAM, HSELx[0])
  ├── ahb_lite_to_apb     (AHB→APB桥, HSELx[1])
  │     └── apb_perips    (GPIO/Timer/UART/SPI)
  ├── [保留: HSELx[2]]    (未来扩展)
  └── ahb_default_slave   (错误, HSELx[3])
```

---

## 四、现有模块修改清单

### 4.1 ahb_decoder.v

**修改内容**：无需修改（当前4-slave解码已匹配目标地址映射）

**验证**：
- HADDR[31:20]==12'h000 → HSELx[0] (SRAM) ✓
- HADDR[31:20]==12'h001 → HSELx[1] (APB桥) ✓
- HADDR[31:20]==12'h100 → HSELx[2] (保留) ✓
- 其余 → HSELx[3] (default) ✓

### 4.2 apb_decoder.v

**修改内容**：将4-slave解码从PADDR[31:30]改为PADDR[15:14]

**修改前**：
```verilog
assign PSELx[0] = (addr_region[31:30] == 2'b00);  // 每区1GB
assign PSELx[1] = (addr_region[31:30] == 2'b01);
assign PSELx[2] = (addr_region[31:30] == 2'b10);
assign PSELx[3] = (addr_region[31:30] == 2'b11);
```

**修改后**：
```verilog
assign PSELx[0] = (addr_region[15:14] == 2'b00);  // 每区16KB
assign PSELx[1] = (addr_region[15:14] == 2'b01);
assign PSELx[2] = (addr_region[15:14] == 2'b10);
assign PSELx[3] = (addr_region[15:14] == 2'b11);
```

**注意**：需同步修改8-slave解码（PADDR[15:13]），以及新增参数化解码位宽选项。

### 4.3 apb_perips.v

**修改内容**：新增参数化APB解码位宽，确保PADDR传递到各外设时偏移正确

**当前状态**：已完整实现GPIO/Timer/UART/SPI的APB4接口，无需修改逻辑
**需确认**：各外设使用PADDR[3:2]（字偏移）选择寄存器，与APB子地址无关

### 4.4 ahb_sram_slave.v

**修改内容**：可选增加COE初始化参数支持

**当前状态**：使用Sram模型(BRAM)，支持MEM_DEPTH参数化
**需确认**：BRAM初始化方式（$readmemh或COE），确保testbench可预加载指令

### 4.5 system_top.v

**修改内容**：替换soc_top(Bus4LZU)为ahb_periph_bus + cpu_bus_adapter

**修改前**：
```
system_top
  ├── soc_top (Bus4LZU)
  ├── simple_cpu_top (CPU)
  └── lcd_module
```

**修改后**：
```
system_top
  ├── simple_cpu_top (CPU, 不变)
  ├── cpu_bus_adapter (新建)
  ├── ahb_periph_bus (新建)
  └── lcd_module (不变)
```

**信号连接变化**：

| 信号 | 旧连接 (Bus4LZU) | 新连接 (AHB+APB) |
|------|-----------------|-----------------|
| instAddr_32 | CPU→soc_top | CPU→adapter |
| instData_32 | soc_top→CPU | adapter→CPU |
| dataAddr_32 | CPU→soc_top | CPU→adapter |
| writeData_32 | CPU→soc_top | CPU→adapter |
| readData_32 | soc_top→CPU | adapter→CPU |
| dataWen_4 | CPU→soc_top | CPU→adapter |
| data_req | CPU→(未连接soc_top) | CPU→adapter |
| init_sig | soc_top→CPU | 恒0 (COE初始化) |
| timer_irq | soc_top→CPU | ahb_periph_bus→CPU |
| uart_rx/tx | soc_top端口 | ahb_periph_bus端口 |
| spi_*/gpio_io | soc_top端口 | ahb_periph_bus端口 |

### 4.6 simple_cpu_top.v

**修改内容**：无需修改（CPU核心接口不变，adapter处理所有转换）

**前提**：cpu_bus_adapter正确处理延迟和信号转换

---

## 五、测试程序地址更新

### 5.1 需更新的汇编程序

所有引用外设地址的测试程序需更新：

| 文件 | 修改内容 |
|------|---------|
| timer_irq_test.s | Timer地址 0x10010000→0x00104000 |
| timer_seconds.s | Timer地址 0x10010000→0x00104000 |
| comprehensive_test.s | 如有外设地址引用需更新 |
| 其他.s | 检查并更新所有外设地址 |

### 5.2 地址常量定义（建议）

在汇编程序头部统一定义外设地址常量，便于后续修改：

```asm
.equ GPIO_BASE,  0x00100000
.equ TIMER_BASE, 0x00104000
.equ UART_BASE,  0x00108000
.equ SPI_BASE,   0x0010C000
```

---

## 六、实施阶段与步骤

### Phase 1：基础设施搭建

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 1.1 | 修改apb_decoder.v：PADDR[31:30]→PADDR[15:14]解码 | 无 | 编译通过 |
| 1.2 | 新建ahb_periph_bus.v：异构AHB总线(SRAM+桥+默认) | ahb_lite_to_apb, apb_perips | 编译通过 |
| 1.3 | ahb_periph_bus连接apb_perips外设引脚(timer_irq/gpio/uart/spi) | 1.2 | 编译通过 |
| 1.4 | 新建cpu_bus_adapter.v：I/D仲裁+信号转换 | 无 | 编译通过 |
| 1.5 | cpu_bus_adapter: dataWen_4→req_write/req_size转换逻辑 | 1.4 | 单元测试 |
| 1.6 | cpu_bus_adapter: I/D仲裁状态机 | 1.4 | 单元测试 |
| 1.7 | cpu_bus_adapter: 延迟处理(req_ready/resp_valid握手) | 1.6 | 单元测试 |

### Phase 2：顶层集成

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 2.1 | 修改system_top.v：替换soc_top为cpu_bus_adapter+ahb_periph_bus | Phase 1 | 编译通过 |
| 2.2 | 连接外设引脚(uart_rx/tx, spi_*, gpio_io) | 2.1 | 编译通过 |
| 2.3 | 连接timer_irq信号 | 2.1 | 编译通过 |
| 2.4 | init_sig处理：恒接0或简单复位逻辑 | 2.1 | 编译通过 |
| 2.5 | LCD显示模块信号连接确认 | 2.1 | 编译通过 |

### Phase 3：测试程序适配

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 3.1 | 更新timer_irq_test.s：Timer地址→0x00104000 | 2.1 | 重新生成.hex |
| 3.2 | 更新timer_seconds.s：Timer地址→0x00104000 | 2.1 | 重新生成.hex |
| 3.3 | 更新其他.s文件的外设地址 | 2.1 | 重新生成.hex |
| 3.4 | 统一定义外设地址常量(.equ) | 3.1-3.3 | 汇编通过 |

### Phase 4：仿真验证

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 4.1 | 新建tb_ahb_bus.v：AHB总线功能测试 | Phase 1 | SRAM读写+桥访问+默认错误 |
| 4.2 | 新建tb_apb_perips.v：APB外设独立测试 | Phase 1 | GPIO/Timer/UART/SPI寄存器读写 |
| 4.3 | 新建tb_cpu_bus_adapter.v：适配器功能测试 | 1.4-1.7 | I/D仲裁+信号转换+延迟 |
| 4.4 | 修改现有testbench：替换soc_top为ahb_periph_bus | Phase 2, 3 | 编译通过 |
| 4.5 | testbench: BRAM预加载($readmemh) | 4.4 | 指令正确加载 |
| 4.6 | 回归测试：simple_cpu_top 33项 | 4.4 | 33/33 PASS |
| 4.7 | 回归测试：csr_test 20项 | 4.4 | 20/20 PASS |
| 4.8 | 回归测试：timer_irq_test | 4.4 | PASS |
| 4.9 | 回归测试：align_test 23项 | 4.4 | 23/23 PASS |
| 4.10 | 回归测试：timer_seconds | 4.4 | PASS |
| 4.11 | 全量回归：81/81 PASS | 4.6-4.10 | 全部PASS |

### Phase 5：Cache集成（可与Phase 1-4并行设计）

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 5.1 | 激活icache.v：接入cpu_fetch取指路径 | Phase 2 | 取指命中/未命中 |
| 5.2 | 激活dcache.v：接入cpu_mem访存路径 | Phase 2 | Load/Store命中/未命中 |
| 5.3 | cache控制器：未命中时发起AHB总线请求 | 5.1, 5.2 | Cache fill正确 |
| 5.4 | 硬映射策略：cache固定映射主存低位部分 | 5.3 | 地址映射正确 |
| 5.5 | MMIO判断：外设地址范围绕过cache直连总线 | 5.3 | 外设访问不走cache |
| 5.6 | simple_cpu_top.v：封装cache进核心 | 5.1-5.5 | 编译通过 |
| 5.7 | 回归测试：81/81 PASS | 5.6 | 全部PASS |

### Phase 6：MMU直接映射（Phase 5完成后）

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 6.1 | 实现MMU.v：直接映射模式(虚拟地址=物理地址) | Phase 5 | 地址透传 |
| 6.2 | 存储访问路径：core→MMU→cache控制器→总线 | 6.1 | 完整路径验证 |
| 6.3 | 为未来TLB/SV32预留接口 | 6.1 | 接口定义 |
| 6.4 | 回归测试：81/81 PASS | 6.2 | 全部PASS |

---

## 七、风险与注意事项

### 7.1 延迟兼容性（高风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| AHB 2相位延迟 | AHB master的ADDR→DATA两相位增加1周期延迟，CPU fetch/mem的r_wait/MEM_READ2仅处理BRAM 1周期延迟 | adapter中需正确处理AHB握手时序，可能需要调整CPU延迟预期 |
| APB 3相位延迟 | AHB-to-APB桥的SETUP→ACCESS→完成增加2周期延迟 | 外设访问(Timer/UART等)本身较慢，CPU mem阶段应能容忍 |
| I/D仲裁延迟 | I侧和D侧共享总线，仲裁可能引入额外等待周期 | adapter的仲裁状态机需正确stall CPU |

### 7.2 写使能转换（中风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| dataWen_4语义 | CPU的dataWen_4使用反相逻辑(0=写,1=不写)，AHB使用HWRITE(1=写) | adapter中严格转换，增加断言检查 |
| 字节对齐 | AHB的HSIZE+HADDR决定写入字节，CPU的dataWen_4直接指定字节位 | 确保HSIZE和HADDR组合产生正确的字节写使能 |

### 7.3 地址映射（中风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| 软件地址更新遗漏 | 部分汇编程序硬编码外设地址 | 全局搜索0x10010000/0x00010000/0x00020000/0x00080000 |
| APB解码粒度 | PADDR[15:14]仅4个区，每区16KB，未来扩展受限 | 预留AHB Slave 2(0x10000000)作为扩展空间 |

### 7.4 init_sig处理（低风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| 无UART加载 | init_sig恒0意味着无法通过UART加载程序 | 使用COE初始化BRAM；未来可添加UART加载逻辑 |

---

## 八、文件变更汇总

### 新建文件

| 文件路径 | 说明 | 预计行数 |
|---------|------|---------|
| rtl/core/cpu_bus_adapter.v | CPU总线→AHB请求适配器(I/D仲裁+信号转换) | ~200 |
| rtl/AHB-lite/ahb_periph_bus.v | AHB异构总线顶层(SRAM+桥+默认) | ~180 |
| tb/tb_ahb_bus.v | AHB总线功能测试 | ~150 |
| tb/tb_apb_perips.v | APB外设独立测试 | ~150 |
| tb/tb_cpu_bus_adapter.v | 适配器功能测试 | ~200 |

### 修改文件

| 文件路径 | 修改内容 | 影响范围 |
|---------|---------|---------|
| rtl/APB/apb_decoder.v | PADDR[31:30]→PADDR[15:14]解码 | 4行 |
| rtl/system_top.v | 替换soc_top为adapter+ahb_periph_bus | ~70行重写 |
| program_source/*.s | 外设地址更新 | 多文件，每文件少量 |
| tb/tb_simple_cpu_top.v | 替换soc_top实例化 | ~30行 |
| tb/tb_csr_test.v | 替换soc_top实例化 | ~30行 |
| tb/tb_timer_irq_test.v | 替换soc_top实例化+Timer地址 | ~30行 |
| tb/tb_align_test.v | 替换soc_top实例化 | ~30行 |
| tb/tb_timer_seconds.v | 替换soc_top实例化+Timer地址 | ~30行 |

### 不变文件

| 文件路径 | 说明 |
|---------|------|
| rtl/core/simple_cpu_top.v | CPU核心接口不变 |
| rtl/core/cpu_controller.v | FSM不变 |
| rtl/core/cpu_fetch.v | 取指逻辑不变 |
| rtl/core/cpu_decode.v | 译码逻辑不变 |
| rtl/core/cpu_execute.v | 执行逻辑不变 |
| rtl/core/cpu_mem.v | 访存逻辑不变(延迟处理已兼容) |
| rtl/core/cpu_wb.v | 写回逻辑不变 |
| rtl/core/cpu_regfile.v | 寄存器堆不变 |
| rtl/core/cpu_csr.v | CSR不变 |
| rtl/core/cpu_clint.v | CLINT不变 |
| rtl/AHB-lite/ahb_master.v | AHB master不变 |
| rtl/AHB-lite/ahb_decoder.v | AHB解码器不变(已匹配) |
| rtl/AHB-lite/ahb_mux.v | AHB mux不变 |
| rtl/AHB-lite/ahb_default_slave.v | 默认从设备不变 |
| rtl/AHB-lite/ahb_sram_slave.v | SRAM从设备不变 |
| rtl/APB/ahb_lite_to_apb.v | AHB→APB桥不变 |
| rtl/APB/perips/*.v | APB外设不变 |

---

## 九、Cache集成详细设计（Phase 5）

### 9.1 当前Cache状态

- `icache.v`：512项BRAM直接映射I-Cache，已实现但未接入（cpu_fetch直连总线取指）
- `dcache.v`：512项BRAM直接映射D-Cache，已实现但未接入（cpu_mem直连总线访存）
- `MMU.v`：直接返回地址（直接映射）

### 9.2 Cache集成路径

```
cpu_fetch → icache → (hit) → instData_32
                     (miss) → cache_controller → AHB bus → fill → icache

cpu_mem   → dcache → (hit) → readData_32
                     (miss) → cache_controller → AHB bus → fill → dcache

外设地址  → MMIO判断 → 绕过cache → AHB bus → APB bridge → 外设
```

### 9.3 硬映射策略

当前阶段采用硬映射：cache固定对应主存低位部分。

- I-Cache (512项×4B = 2KB)：映射主存 0x00000000-0x000007FF
- D-Cache (512项×4B = 2KB)：映射主存 0x00000000-0x000007FF
- 超出cache范围的地址：直接访问AHB总线（uncached）

### 9.4 MMIO判断逻辑

地址落入外设范围(0x00100000-0x001FFFFF)时绕过cache：

```verilog
wire is_mmio = (dataAddr_32[31:20] == 12'h001);  // APB外设区
wire is_uncached = is_mmio || (dataAddr_32 >= CACHE_SIZE);  // 超出cache范围
```

### 9.5 Cache控制器状态机

```
IDLE → (miss) → REFILL_REQ → REFILL_WAIT → REFILL_DONE → IDLE
```

- REFILL_REQ：向AHB总线发起cache line填充请求
- REFILL_WAIT：等待AHB响应(resp_valid)
- REFILL_DONE：写入cache BRAM，置valid位，返回数据

---

## 十、验收标准

### Phase 1-4 完成标准

- [ ] cpu_bus_adapter编译通过，I/D仲裁功能正确
- [ ] ahb_periph_bus编译通过，SRAM读写+APB桥访问正确
- [ ] system_top编译通过，所有外设引脚正确连接
- [ ] 所有测试程序地址更新完成
- [ ] 81/81 回归测试全部PASS
- [ ] 无Bus4LZU依赖（可删除rtl/bus4lzu/目录）

### Phase 5 完成标准

- [ ] I-Cache接入cpu_fetch，命中时1周期延迟取指(BRAM IP 仅在时钟上升沿读写数据)
- [ ] D-Cache接入cpu_mem，命中时1周期延迟访存(BRAM IP 仅在时钟上升沿读写数据)
- [ ] Cache未命中时正确发起总线请求并填充
- [ ] MMIO地址绕过cache直接访问总线
- [ ] 81/81 回归测试全部PASS

### Phase 6 完成标准

- [ ] MMU直接映射实现，虚拟地址=物理地址
- [ ] 存储访问完整路径：core→MMU→cache→bus
- [ ] 为TLB/SV32预留标准接口
- [ ] 81/81 回归测试全部PASS

---

## 十一、资源

### tools

mk.py:`tools/mk.py`用于一次性调用 `iverilog` 和 `vvp` 完成编译、模拟过程。

rv2coe.py:用于编译c/asm程序为hex/coe文件

以上两个工具在tools中均有readme文件描述

### 文档

`dev/2-simpleCPU/doc`中有AHB-lite,APB,core的文档，分别对应各自文件夹
