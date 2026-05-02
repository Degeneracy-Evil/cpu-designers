# simpleCPU Cache-First 访存架构计划

## 设计目标

CPU首先访问cache（icache/dcache），MMIO区域（地址最高位为1）绕过cache通过总线访问外设。主存暂不使用，仅作占位。

## 架构总览

### 目标架构框图

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
      |  MMU (直接映射)  |   vaddr = paddr
      +--------+--------+
               |
      +--------v--------+
      |  icache_ctrl /  |   ← cache优先，MMIO(addr[31]==1)时绕过cache
      |  dcache_ctrl    |
      +---+--------+----+
          |        |
   (cache hit)  (MMIO)
          |        |
   +------v--+  +--v------------------+
   | icache  |  | cpu_bus_adapter     |
   | dcache  |  | (I/D仲裁→AHB请求)  |
   +---------+  +--------+-----------+
                         |
      +------------------v------------------+
      |           AHB-Lite 系统总线          |
      |  +----------+  +----------+        |
      |  | ahb_     |  | ahb_     |        |
      |  | master   |  | decoder  |        |
      |  +----------+  +-----+----+        |
      |                      |              |
      |  +----------+  +----v-----+       |
      |  | ahb_sram |  | ahb_lite |       |
      |  | _slave   |  | _to_apb  |       |
      |  | (主存占位)|  | (桥)     |       |
      |  +----------+  +----+-----+       |
      +----------------------|-------------+
                             |
      +----------------------v-------------+
      |           APB 外设总线             |
      |  +------+ +------+ +----+ +---+  |
      |  | GPIO | | Timer| |UART| |SPI|  |
      |  +------+ +------+ +----+ +---+  |
      +-----------------------------------+
```

### CPU访存路径

**取指路径（I侧）**：
```
cpu_fetch → MMU → icache_ctrl
  → addr[31]==0 (非MMIO): icache BRAM读取 (16KB, DEPTH=4096)
  → addr[31]==1 (MMIO):   绕过cache → cpu_bus_adapter → AHB bus → 外设
```

**访存路径（D侧）**：
```
cpu_mem → MMU → dcache_ctrl
  → addr[31]==0 (非MMIO): dcache BRAM读写 (16KB, DEPTH=4096)
  → addr[31]==1 (MMIO):   绕过cache → cpu_bus_adapter → AHB bus → 外设
```

> **关键原则**：CPU首先访问cache，MMIO地址(addr[31]==1)绕过cache直连总线。主存SRAM仅作占位，当前不主动使用。

## Cache设计

### 当前实现（icache_ctrl / dcache_ctrl）

icache_ctrl和dcache_ctrl已实现并集成在simple_cpu_top.v中，**不做修改**。

**icache_ctrl** (`rtl/core/icache_ctrl.v`)：
- DEPTH=4096，12位索引(addr[13:2])，覆盖16KB地址空间
- MMIO判断：`is_mmio = cpu_req_addr[31]`
- 非MMIO：使能icache BRAM读取（只读，wea=4'b0）
- MMIO：绕过cache，输出mmio_req/mmio_addr，从总线获取mmio_data/mmio_valid
- 输出MUX：`cpu_req_data = is_mmio ? mmio_data : icache_dout`

**dcache_ctrl** (`rtl/core/dcache_ctrl.v`)：
- DEPTH=4096，12位索引(addr[13:2])，覆盖16KB地址空间
- MMIO判断：`is_mmio = cpu_req_addr[31]`
- 非MMIO：使能dcache BRAM读写（wea=~cpu_req_wen，反相写使能）
- MMIO：绕过cache，输出mmio_req/mmio_addr/mmio_wdata/mmio_wen
- 输出MUX：`cpu_req_rdata = is_mmio ? mmio_rdata : dcache_dout`

**icache / dcache** (`rtl/core/icache.v`, `rtl/core/dcache.v`)：
- 双端口BRAM数据阵列，DEPTH=4096，每项32bit
- 端口A：CPU读写侧（clka, ena, wea, addra, dina, douta）
- 端口B：预留refill侧（当前未使用，enb=0）
- 字节写使能：wea[3:0]分别控制byte0-3

### Cache地址映射

- Cache大小：4096 × 4B = 16KB
- 索引位：addr[13:2]（12位，索引4096项）
- 字节偏移：addr[1:0]（2位）
- 覆盖地址范围：0x00000000 - 0x00003FFF（16KB）
- 映射方式：硬映射（直接对应地址低位，无tag/valid比较）

> **注意**：当前cache为直接映射BRAM，无tag存储和valid位。地址超出16KB且addr[31]==0时，索引回绕（addr[13:2]截断）。程序需确保代码和数据位于0x00000000-0x00003FFF范围内。

### MMU

MMU.v当前为直接映射：`paddr = vaddr`，虚拟地址等于物理地址。

## MMIO设计

### MMIO判断

```verilog
wire is_mmio = addr[31];  // 地址最高位为1时为MMIO区域
```

- MMIO区域：0x80000000 - 0xFFFFFFFF（2GB地址空间）
- 非MMIO区域：0x00000000 - 0x7FFFFFFF（2GB地址空间，cache覆盖前16KB）

### MMIO访问路径

```
CPU → cache_ctrl (检测is_mmio) → cpu_bus_adapter → AHB bus → APB bridge → 外设
```

MMIO访问绕过cache，直接通过cpu_bus_adapter发起AHB总线请求，经AHB-to-APB桥访问外设。

## 主存占位

主存SRAM（ahb_sram_slave）在AHB总线上作为Slave存在，但当前不主动使用：

- CPU的指令和数据访问优先走cache（addr[31]==0时）
- MMIO访问走总线→外设（addr[31]==1时）
- 主存SRAM仅在以下场景使用：
  - 未来实现cache miss refill时作为后备存储
  - 调试时直接通过总线访问
- 当前MEM_DEPTH=262144(1MB)，地址范围由AHB解码器决定

## 地址映射

### AHB-Lite地址映射（基于addr[31]解码，2 Slave）

| Slave | HSELx | 地址范围 | 大小 | 功能 |
|-------|-------|---------|------|------|
| 0 | addr[31]==0 | 0x00000000 - 0x7FFFFFFF | 2GB | 主存SRAM占位 (ahb_sram_slave) |
| 1 | addr[31]==1 | 0x80000000 - 0xFFFFFFFF | 2GB | AHB-to-APB桥 (外设MMIO) |

> **注意**：当前ahb_decoder使用HADDR[31:20]进行4-slave解码，需修改为基于HADDR[31]的2-slave解码以匹配新的MMIO定义。两个slave覆盖完整32位地址空间，无需default slave。

### APB外设地址映射（4 Slave, PADDR[15:14]解码）

APB地址空间位于AHB Slave 1范围内(0x80000000起)。

| PSELx | 地址范围 | 大小 | 外设 |
|-------|---------|------|------|
| PSELx[0] | 0x80000000 - 0x80003FFF | 16KB | GPIO |
| PSELx[1] | 0x80004000 - 0x80007FFF | 16KB | Timer |
| PSELx[2] | 0x80008000 - 0x8000BFFF | 16KB | UART |
| PSELx[3] | 0x8000C000 - 0x8000FFFF | 16KB | SPI |

### APB解码器

```verilog
assign PSELx[0] = (PADDR[15:14] == 2'b00);  // GPIO  @ 0x80000000
assign PSELx[1] = (PADDR[15:14] == 2'b01);  // Timer @ 0x80004000
assign PSELx[2] = (PADDR[15:14] == 2'b10);  // UART  @ 0x80008000
assign PSELx[3] = (PADDR[15:14] == 2'b11);  // SPI   @ 0x8000C000
```

### 地址映射汇总（软件视角）

| 用途 | 地址 | 说明 |
|------|------|------|
| Cache (指令+数据) | 0x00000000 - 0x00003FFF | 16KB, icache/dcache BRAM直接映射 |
| 主存占位 | 0x00004000 - 0x7FFFFFFF | SRAM占位, 当前不使用 |
| GPIO CTRL | 0x80000000 | MMIO, 绕过cache |
| GPIO DATA | 0x80000004 | MMIO, 绕过cache |
| Timer EXPR | 0x80004000 | MMIO, 绕过cache |
| Timer CTRL | 0x80004004 | MMIO, 绕过cache |
| Timer INTR | 0x80004008 | MMIO, 绕过cache |
| Timer COUNTER | 0x8000400C | MMIO, 绕过cache |
| UART | 0x80008000 | MMIO, 绕过cache |
| SPI | 0x8000C000 | MMIO, 绕过cache |

### 汇编地址常量定义

```asm
.equ GPIO_BASE,  0x80000000
.equ TIMER_BASE, 0x80004000
.equ UART_BASE,  0x80008000
.equ SPI_BASE,   0x8000C000
```

## 总线基础设施

### AHB-Lite系统总线

- 连接cpu_bus_adapter（唯一master）与SRAM占位+APB桥（2个slaves）
- cpu_bus_adapter内部仲裁I侧/D侧请求（I请求优先）
- dataWen_4→req_write/req_size转换逻辑

### APB外设总线

- 通过AHB-to-APB桥连接到AHB总线
- 4个外设：GPIO, Timer, UART, SPI
- apb_decoder使用PADDR[15:14]解码（每区16KB）

## 实施阶段

### Phase 1：AHB解码器更新

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 1.1 | 修改ahb_decoder.v：新增SLAVE_NUM==2的HADDR[31]解码逻辑 | 无 | 编译通过 |
| 1.2 | 修改ahb_periph_bus.v：SLAVE_NUM=4→2，移除default slave和reserved slave | 1.1 | 编译通过 |
| 1.3 | 修改system_top.v：ahb_periph_bus实例化SLAVE_NUM=2 | 1.2 | 编译通过 |

### Phase 2：测试程序地址更新

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 2.1 | 更新所有汇编程序外设地址：0x001xxxxx→0x8000xxxx | Phase 1 | 重新生成.hex |
| 2.2 | 统一定义外设地址常量(.equ) | 2.1 | 汇编通过 |

### Phase 3：仿真验证

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 3.1 | 验证cache命中路径：指令和数据在0x00000000-0x00003FFF内正确读写 | Phase 1 | 功能正确 |
| 3.2 | 验证MMIO路径：外设地址(0x80000000+)绕过cache正确访问 | Phase 1 | 功能正确 |
| 3.3 | 回归测试：全部PASS | 3.1, 3.2 | 全部PASS |

### Phase 4：主存占位确认

| 步骤 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| 4.1 | 确认SRAM slave在AHB总线上存在但CPU不主动访问 | Phase 1 | 编译通过 |
| 4.2 | 预留cache miss refill接口（icache/dcache端口B） | 4.1 | 接口定义 |

## 远景

- Cache miss refill：当实现tag/valid逻辑后，cache miss时通过总线从主存SRAM加载数据
- MMU扩展：从直接映射升级为SV32分页映射
- 主存激活：当cache miss refill实现后，主存SRAM从占位变为实际使用

## 已修复的矛盾

### icache/dcache地址位宽与条目数不对应（已修复）

icache.v和dcache.v已参数化(DEPTH参数)，地址位宽=$clog2(DEPTH)。

### CPU访存路径已集成cache

icache_ctrl和dcache_ctrl已集成在simple_cpu_top.v中：
- icache_ctrl: 取指路径，cache优先，MMIO绕过
- dcache_ctrl: 访存路径，cache优先，MMIO绕过

## 风险与注意事项

### 地址回绕（中风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| Cache索引回绕 | addr[13:2]仅12位，地址≥16KB时索引回绕，可能读到错误数据 | 程序限制在16KB内；未来添加tag比较逻辑 |

### AHB解码器变更（中风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| 解码逻辑变更 | 从HADDR[31:20] 4-slave改为HADDR[31] 2-slave，影响所有总线从设备选择 | 仔细验证SRAM和APB桥的HSELx条件 |

### 外设地址变更（中风险）

| 风险 | 说明 | 缓解 |
|------|------|------|
| 软件地址更新 | 所有汇编程序外设地址需从0x001xxxxx更新为0x8000xxxx | 全局搜索替换 |

## 文件变更汇总

### 修改文件

| 文件路径 | 修改内容 | 影响范围 |
|---------|---------|---------|
| rtl/AHB-lite/ahb_decoder.v | 新增SLAVE_NUM==2的HADDR[31]解码 | 解码逻辑变更 |
| rtl/AHB-lite/ahb_periph_bus.v | SLAVE_NUM 4→2，移除default/reserved slave | 从设备连接变更 |
| rtl/system_top.v | ahb_periph_bus实例SLAVE_NUM=2 | 参数变更 |
| program_source/*.s | 外设地址0x001xxxxx→0x8000xxxx | 多文件 |
| tb/*.v | 适配新地址映射 | testbench更新 |

### 不变文件

| 文件路径 | 说明 |
|---------|------|
| rtl/core/icache.v | BRAM数据阵列，已参数化，不变 |
| rtl/core/dcache.v | BRAM数据阵列，已参数化，不变 |
| rtl/core/icache_ctrl.v | cache控制器，MMIO判断addr[31]，不变 |
| rtl/core/dcache_ctrl.v | cache控制器，MMIO判断addr[31]，不变 |
| rtl/core/simple_cpu_top.v | 已集成cache_ctrl，不变 |
| rtl/core/MMU.v | 直接映射，不变 |
| rtl/core/cpu_bus_adapter.v | I/D仲裁+信号转换，不变 |

## 资源

### tools

mk.py:`tools/mk.py`用于一次性调用 `iverilog` 和 `vvp` 完成编译、模拟过程。

rv2coe.py:用于编译c/asm程序为hex/coe文件

以上两个工具在tools中均有readme文件描述

### 文档

`dev/2-simpleCPU/doc`中有AHB-lite,APB,core的文档，分别对应各自文件夹
