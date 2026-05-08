# AHB-Lite 总线实现计划与进度

## 状态说明
- [ ] 未开始
- [~] 进行中
- [x] 已完成
- [!] 有问题

---

## 1. 计划概述

基于 `doc/AHB-lite/AMBA_AHB-Lite_Spec_Summary.md` (ARM IHI 0033A) 规范，在 `rtl/AHB-lite/` 目录下实现完整的 AHB-Lite 总线互连，作为 CPU 核心与存储器/外设之间的高性能前端总线。

### 1.1 设计目标

| 目标 | 说明 |
|------|------|
| 协议合规 | 严格遵循 AMBA 3 AHB-Lite v1.0 规范 |
| 单主设备 | CPU 为唯一主设备（AHB-Lite 原生支持） |
| 多从设备 | 支持 1/2/4/8 个从设备，可配置 |
| 流水线传输 | 地址阶段与数据阶段重叠 |
| 突发支持 | SINGLE/INCR/INCR4/WRAP4 等突发类型 |
| ERROR 双周期响应 | 符合规范的 2 周期错误响应机制 |
| 默认从设备 | 未映射地址访问返回 ERROR |
| 可综合 | 纯 RTL，iverilog/Vivado 兼容 |

### 1.2 模块划分

```
AHB-lite/
├── ahb_def.vh            # 参数与常量定义（ADDR/DATA宽度、HTRANS/HBURST/HSIZE/HRESP编码）
├── ahb_lite_bus.v        # AHB 外设总线顶层：集成decoder+mux+sram_slave+ahb_lite_to_apb+apb
├── ahb_decoder.v         # 地址译码器：HADDR高位→HSELx选择信号，支持1/2/4/8从设备
├── ahb_mux.v             # 多路选择器：被选从设备的HRDATA/HREADYOUT/HRESP→全局HRDATA/HREADY/HRESP
└── ahb_sram_slave.v      # SRAM从设备：支持字节/半字/字写入，可配置等待状态
```

### 1.3 信号映射（参照规范第2节）

| 规范信号 | 实现信号 | 宽度 | 来源模块 |
|----------|----------|------|----------|
| HCLK | HCLK | 1 | 全局 |
| HRESETn | HRESETn | 1 | 全局（低有效） |
| HADDR[31:0] | bus_HADDR | 32 | ahb_master |
| HTRANS[1:0] | bus_HTRANS | 2 | ahb_master |
| HWRITE | bus_HWRITE | 1 | ahb_master |
| HSIZE[2:0] | bus_HSIZE | 3 | ahb_master |
| HBURST[2:0] | bus_HBURST | 3 | ahb_master |
| HPROT[3:0] | bus_HPROT | 4 | ahb_master |
| HMASTLOCK | bus_HMASTLOCK | 1 | ahb_master |
| HWDATA[31:0] | bus_HWDATA | 32 | ahb_master |
| HRDATA[31:0] | bus_HRDATA | 32 | ahb_mux |
| HREADY | bus_HREADY | 1 | ahb_mux |
| HRESP | bus_HRESP | 1 | ahb_mux |
| HSELx | slave_HSELx | N | ahb_decoder |
| HREADYOUT | slave_HREADYOUT | N | 各从设备 |

### 1.4 关键设计约束（参照规范第10节）

1. 所有信号在 HCLK 上升沿采样
2. 传输 = 地址阶段 + 数据阶段，两者重叠（流水线）
3. 从设备不能延长地址阶段，仅通过 HREADY 延长数据阶段
4. ERROR 响应必须 2 周期（HRESP=ERROR, HREADY=LOW → HREADY=HIGH）
5. 增量突发不得跨越 1KB 地址边界
6. 突发期间 HWRITE/HSIZE/HBURST 必须保持不变
7. HRESETn 唯一低电平有效信号
8. 从设备仅在 HREADY=HIGH 时采样 HSELx 和地址/控制信号
9. 单个从设备最小地址空间 1KB
10. IDLE/BUSY 传输从设备必须以零等待 OKAY 响应

---

## 2. 实现步骤

### Step 1: ahb_def.vh — 参数与常量定义

- [x] AHB_ADDR_WIDTH/DATA_WIDTH/STRB_WIDTH 宽度定义
- [x] HTRANS 编码：IDLE(00)/BUSY(01)/NONSEQ(10)/SEQ(11)
- [x] HBURST 编码：SINGLE/INCR/WRAP4/INCR4/WRAP8/INCR8/WRAP16/INCR16
- [x] HSIZE 编码：BYTE/HWORD/WORD/DWORD/4WORD/8WORD/16WORD/32WORD
- [x] HRESP 编码：OKAY(0)/ERROR(1)
- [x] HPROT 位定义：数据/指令、特权/用户、可缓冲、可缓存

### Step 2: ahb_master.v — 主设备接口

- [x] 请求接口：req_valid/req_write/req_addr/req_wdata/req_size/req_burst/req_prot/req_lock
- [x] 响应接口：req_ready/resp_valid/resp_error/resp_rdata
- [x] AHB 信号输出：HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HMASTLOCK/HWDATA
- [x] 状态机：IDLE→ADDR→DATA→IDLE（正常）/ IDLE→ADDR→ERROR（错误响应）
- [x] 地址阶段：req_valid 时驱动 NONSEQ + 地址/控制信号
- [x] 数据阶段：HREADY 时采样 HRESP，写传输驱动 HWDATA
- [x] ERROR 处理：收到 ERROR 后切换到 IDLE，2 周期响应窗口
- [x] 复位：HTRANS=IDLE，所有输出为默认值

### Step 3: ahb_decoder.v — 地址译码器

- [x] 输入：HADDR[31:0]
- [x] 输出：HSELx[SLAVE_NUM-1:0]
- [x] 支持 1/2/4/8 从设备配置（generate 条件编译）
- [x] 4 从设备默认映射：0x000→Slave0(SRAM), 0x001→Slave1, 0x100→Slave2, 其他→Slave3(Default)
- [x] 最小地址空间 1KB（高12位译码）
- [x] 纯组合逻辑（规范要求）

### Step 4: ahb_mux.v — 读数据/响应多路选择器

- [x] 输入：各从设备的 HRDATA/HREADYOUT/HRESP + HSELx 选择信号
- [x] 输出：全局 HRDATA/HREADY/HRESP
- [x] 选择逻辑：HSELx[i]=1 时路由 slave[i] 的信号到全局总线
- [x] 纯组合逻辑

### Step 5: ahb_default_slave.v — 默认从设备

- [x] NONSEQ/SEQ 传输 → ERROR 响应（2周期：HREADY=LOW+HRESP=ERROR → HREADY=HIGH+HRESP=ERROR）
- [x] IDLE/BUSY 传输 → 零等待 OKAY 响应（规范要求）
- [x] error_state 寄存器跟踪 2 周期 ERROR 响应状态
- [x] 复位：HREADYOUT=HIGH, HRESP=OKAY

### Step 6: ahb_sram_slave.v — SRAM 从设备

- [x] 字节/半字/字写入支持（HSIZE 译码 + 字节通道选择）
- [x] 字对齐地址索引：HADDR[INDEX_WIDTH+1:2]
- [x] 可配置等待状态（WAIT_STATES 参数）
- [x] 等待状态期间 HREADYOUT=LOW, HRESP=OKAY
- [x] IDLE/BUSY 传输 → 零等待 OKAY（规范要求）
- [x] 复位：HREADYOUT=HIGH, HRESP=OKAY

### Step 7: ahb_bus.v — 顶层互连

- [x] 实例化 ahb_master（CPU请求→AHB信号）
- [x] 实例化 ahb_decoder（地址→HSELx）
- [x] 实例化 ahb_mux（从设备响应→全局总线）
- [x] generate 循环实例化 SLAVE_NUM-1 个 ahb_sram_slave
- [x] 最后一个从设备实例化 ahb_default_slave
- [x] 可配置参数：ADDR_WIDTH/DATA_WIDTH/SLAVE_NUM/MEM_DEPTH/WAIT_STATES

### Step 8: 编译验证

- [x] iverilog -g2012 全模块编译通过
- [ ] testbench 仿真验证（待实现）

---

## 3. 实现记录

### 2026-04-30 AHB-Lite 总线初始实现

**参照规范**：`doc/AHB-lite/AMBA_AHB-Lite_Spec_Summary.md`（ARM IHI 0033A, AMBA 3 AHB-Lite v1.0）

**新建文件**：

| 文件 | 行数 | 功能 |
|------|------|------|
| `ahb_def.vh` | 37 | AHB-Lite 参数与常量定义（HTRANS/HBURST/HSIZE/HRESP 编码） |
| `ahb_master.v` | 128 | 主设备接口：请求→AHB信号转换，4状态FSM（IDLE/ADDR/DATA/ERROR） |
| `ahb_decoder.v` | 36 | 地址译码器：HADDR高12位→HSELx，支持1/2/4/8从设备 |
| `ahb_mux.v` | 31 | 多路选择器：HSELx选通从设备HRDATA/HREADYOUT/HRESP到全局总线 |
| `ahb_default_slave.v` | 47 | 默认从设备：NONSEQ/SEQ→2周期ERROR，IDLE/BUSY→0等待OKAY |
| `ahb_sram_slave.v` | 98 | SRAM从设备：字节/半字/字写入，可配置等待状态 |
| `ahb_bus.v` | 141 | 顶层互连：master+decoder+mux+sram_slaves+default_slave |

**编码规范**：
- 遵循项目既有风格（参照 `rtl/ABP/` 目录）
- 异步复位 `negedge HRESETn`，同步解除断言
- 参数化设计（ADDR_WIDTH/DATA_WIDTH/SLAVE_NUM/MEM_DEPTH/WAIT_STATES）
- `include "ahb_def.vh" 引用常量定义
- 无注释（项目约定）

**协议合规要点**：
1. HRESETn 低电平有效（规范唯一低有效信号）✓
2. HTRANS=IDLE 复位初始值 ✓
3. 从设备 HREADYOUT=HIGH 复位初始值 ✓
4. ERROR 响应 2 周期（default_slave: error_state 寄存器）✓
5. IDLE/BUSY 传输零等待 OKAY（default_slave + sram_slave）✓
6. 从设备仅在 HREADY=HIGH 时采样（ahb_transfer = HSEL & HREADY & HTRANS[1]）✓
7. 地址译码纯组合逻辑 ✓
8. 多路选择器纯组合逻辑 ✓

**编译验证**：
```
iverilog -g2012 -I rtl/AHB-lite ahb_master.v ahb_decoder.v ahb_mux.v ahb_default_slave.v ahb_sram_slave.v ahb_bus.v
→ 编译通过，0 error
```

**与既有 AHB-to-APB 桥的兼容性**：
- `rtl/ABP/ahb_lite_to_apb.v` 已实现 AHB-Lite 从设备侧接口（HSEL/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HWDATA/HREADY/HREADYOUT/HRESP）
- AHB-Lite 总线的 HSELx/HREADY/HRESP 全局信号可直接连接到桥的输入
- 桥的 APB 侧输出（PADDR/PSEL/PENABLE/PWRITE/PWDATA/PSTRB）连接到 APB 总线

---

## 4. 后续计划

- [ ] 编写 AHB-Lite testbench（基本读写、突发传输、ERROR响应、等待状态）
- [ ] 集成到 CPU 顶层（core_top → ahb_lite_bus → sram_slave + ahb_lite_to_apb → apb_bus）
- [ ] 地址映射细化（SRAM/Timer/UART/GPIO/SPI 地址空间分配）
- [ ] 突发传输完整支持（INCR4/WRAP4 地址生成逻辑）
- [ ] HMASTLOCK 锁定传输支持（SWP 原子操作）
