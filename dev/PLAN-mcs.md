# Cache-主存体系建立计划

## 目标

建立cache与主存之间的映射和交换机制。

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。

简述：rv32-im，cache采用哈佛存储结构，主存暂未使用，AHB系统总线，APB外设总线，仅M特权级。

## 设计

主存和缓存均使用BRAM IP（新IP文件在`Reference\newips`文件夹下，当前项目使用的旧IP在`Reference\ips`文件夹下），参数如下：

- SRAM:$32bit \times 8192=32KB$
  - 地址宽:15bit
  - 块大小:32字节
  - IP设置：没有开启字节读写，wea,web宽度只有1
- i/dcache-d:$256bit \times 4路 \times 8组=1KB$（cache数据段）
  - 行大小:32字节
  - 组数:8组
  - offset:5bit
  - 组号:3bit
  - IP设置：开启字节读写，wea,web宽度32
- i/dcache-t:$16bit \times 4路 \times 8组=64B$（cache标志段）
  - tag:$15-5-3=7bit$
  - 有效位:1bit
  - 脏位:1bit
  - PLRU状态位:3bit
  - resave:4bit
  - IP设置：没有开启字节读写，wea,web宽度只有1

计划采用写回设计，tree-PLRU替换算法，使用4路组相连。

icache进行只读特殊优化：脏位恒为零，替换时不进行回写到主存

## 现状分析

| 组件 | 文件 | 当前状态 |
| --- | --- | --- |
| icache/dcache | `icache.sv`/`dcache.sv` | 仅为32bit×4096的BRAM包装，无tag/miss/替换逻辑 |
| icache_ctrl/dcache_ctrl | `icache_ctrl.sv`/`dcache_ctrl.sv` | 直连BRAM读取，MMIO旁路，无命中/缺失判断 |
| cpu_bus_bridge | `cpu_bus_bridge.sv` | 仅处理MMIO请求(AHB单次传输)，无cache miss refill通道 |
| AHB SRAM slave | `ahb_sram_slave.sv` | 32bit×262144(1MB) BRAM，支持字节/半字/字写，不支持突发 |
| 复位向量 | `core_top.sv:149` | 已设为`0x8000_0000` |
| 新IP | `Reference/newips/` | icached(256bit×32,wea=32), icachet(16bit×32,wea=1), Sram(32bit×8192,wea=1) 已定义 |

地址划分：`is_mmio = ~addr[31]` → `0x0000_xxxx`=MMIO(走AHB), `0x8000_xxxx`=Cacheable

## 详细实施步骤

### 阶段1：Tree-PLRU替换算法模块

**新建** `dev/rtl/core/tree_plru.sv`

- 输入：`access_way[1:0]`(0-3), `plru_state[2:0]`(当前3bit状态)
- 输出：`victim_way[1:0]`(替换候选way), `next_state[2:0]`(更新后状态)
- 替换逻辑（来自`dev\docs\Mem\tree-PLRU.txt`）：
  - `00x` → way_0; `01x` → way_1; `1x0` → way_2; `1x1` → way_3
- 访问更新逻辑：
  - way_0 → `11_`; way_1 → `10_`; way_2 → `0_1`; way_3 → `0_0`（`_`表示不变）

### 阶段2：Cache数据/标签BRAM模块重构

**修改** `dev/rtl/core/icache.sv` 和 `dev/rtl/core/dcache.sv`

替换为新的BRAM IP接口：

| BRAM | 宽度 | 深度 | 地址宽 | wea宽 | 字节写使能 |
| --- | --- | --- | --- | --- | --- |
| icached/dcached | 256bit | 32(4路×8组) | 5bit | 32 | 是 |
| icachet/dcachet | 16bit | 32(4路×8组) | 5bit | 1 | 否 |

- 数据BRAM端口：Port A(CPU侧读/写), Port B(refill写回)
- 标签BRAM端口：Port A(CPU侧tag比较), Port B(refill时tag更新)
- 地址编码：`{set_index[2:0], way[1:0]}` = 5bit

标签16bit编码：`{reserve[3:0], plru[2:0], dirty, valid, tag[6:0]}`

tag=7bit（基于SRAM 15bit地址空间：15-5-3=7），仅缓存0x8000_0000~0x8000_7FFF(32KB)

### 阶段3：ICache控制器重写

**修改** `dev/rtl/core/icache_ctrl.sv`

新接口：

```systemverilog
module icache_ctrl(
    input  clk, reset,
    input  cpu_req_valid, input [31:0] cpu_req_addr,
    output [31:0] cpu_req_data, output cpu_req_ready,
    // MMIO旁路
    output mmio_req, output [31:0] mmio_addr,
    input [31:0] mmio_data, input mmio_valid,
    // Cache miss refill
    output refill_req, output [31:0] refill_addr,
    input [255:0] refill_data, input refill_valid
);
```

FSM状态机：

1. **LOOKUP**：用`addr[7:5]`(set)读取4路tag BRAM，比较tag与`addr[14:8]`
2. **HIT**：从命中way的数据BRAM读取对应word（根据`addr[4:2]`从256bit行中选取32bit），更新PLRU，返回ready
3. **MISS**：查PLRU获取victim way，检查valid+dirty（icache脏位恒0，跳过writeback），发refill请求
4. **REFILL_WAIT**：等待refill_valid
5. **REFILL_UPDATE**：将256bit数据写入数据BRAM Port B，更新tag BRAM（valid=1, dirty=0, tag），更新PLRU
6. 返回LOOKUP重新比较

icache特殊优化：脏位恒为0，替换时不回写主存

### 阶段4：DCache控制器重写

**修改** `dev/rtl/core/dcache_ctrl.sv`

与icache类似，增加：

- 写命中：写入数据BRAM（字节/半字/字使能），置脏位=1，更新PLRU
- 写缺失：写分配(write-allocate) — 先refill整行，再写入
- 替换回写：victim way的dirty=1时，需先将256bit行写回主存

新接口：

```systemverilog
module dcache_ctrl(
    // CPU侧(含hwrite/hsize)
    input  cpu_req_valid, input [31:0] cpu_req_addr,
    input [31:0] cpu_req_wdata, input cpu_req_hwrite, input [2:0] cpu_req_hsize,
    output [31:0] cpu_req_rdata, output cpu_req_ready,
    // MMIO旁路
    output mmio_req, output [31:0] mmio_addr, output [31:0] mmio_wdata,
    output mmio_hwrite, output [2:0] mmio_hsize,
    input [31:0] mmio_rdata, input mmio_valid,
    // Cache miss refill
    output refill_req, output [31:0] refill_addr,
    input [255:0] refill_data, input refill_valid,
    // Writeback
    output wb_req, output [31:0] wb_addr, output [255:0] wb_data,
    input wb_valid
);
```

DCache FSM状态：LOOKUP → HIT / MISS → WRITEBACK → REFILL_WAIT → REFILL_UPDATE → LOOKUP

### 阶段5a：AHB SRAM Slave突发支持

**修改** `dev/rtl/AHB-lite/ahb_sram_slave.sv`

增加INCR8突发支持：

- 检测`HBURST == AHB_BURST_INCR`时，进入突发模式
- 突发计数器`beat_cnt`：0→7共8拍
- 每拍地址自增：`burst_addr = latch_addr + (beat_cnt << 2)`
- 最后一拍`beat_cnt==7`时结束突发
- MEM_DEPTH从262144改为8192（匹配新Sram IP 32bit×8192=32KB）

### 阶段5b：CPU-Bus Bridge扩展

**修改** `dev/rtl/core/cpu_bus_bridge.sv`

扩展FSM支持突发传输：

1. MMIO路径：保持SINGLE传输
2. Refill路径：发HBURST=INCR8的读突发，连续接收8个HRDATA拼成256bit行
3. Writeback路径：发HBURST=INCR8的写突发，连续发8个HWDATA（从256bit行中依次取出）

Bridge FSM状态：IDLE → ADDR_PHASE → BURST_DATA(8拍) → DONE

仲裁优先级：MMIO > Writeback > Refill（避免死锁）

### 阶段6：Core Top连线更新

**修改** `dev/rtl/core/core_top.sv`

- icache_ctrl实例：增加refill端口连线
- dcache_ctrl实例：增加refill + writeback端口连线
- cpu_bus_bridge实例：增加cache refill/writeback端口连线
- 复位向量：已为`0x8000_0000`，无需修改

### 阶段7：SRAM IP/深度适配

- 将`ahb_sram_slave`的`MEM_DEPTH`从262144改为8192
- 替换Sram IP实例使用`Reference/newips/Sram.xci`配置
- 确认AHB decoder将0x8000_0000起始地址路由到SRAM slave

### 阶段7+a：fence.i指令支持

目标: 支持`fence.i`指令，此指令已经在decoder中被解码，但和`fence`,`wfi`一起被归类为`nop`

#### 步骤1：`cpu_decode.sv` — 分离fencei信号

- `is_fence` → `is_nop_like` = `inst_fence | inst_wfi`（fence和wfi仍为NOP）
- 新增 `is_fencei` = `inst_fencei`
- 输出端口 `dec_is_fence` → `dec_is_nop_like`，新增 `output dec_is_fencei`
- `valid_inst` 包含 `is_nop_like | is_fencei`
- `dec_need_exe` 排除 `is_nop_like` 和 `is_fencei`

#### 步骤2：`icache_ctrl.sv` — 新增invalidate机制

- 新增端口：`input invalidate_req`，`output invalidate_done`
- 新增FSM状态：`S_INVALIDATE` (2'd3)
  - 单周期清零所有 `tag_ram[s][w]` 的valid位（tag是寄存器，可并行清零）
  - 同时清零所有 `plru_state[s]`
  - `invalidate_done` 拉高一个周期
- `invalidate_req` 仅在S_IDLE时接受

#### 步骤3：`dcache_ctrl.sv` — 新增flush机制

- 新增端口：`input flush_req`，`output flush_done`
- 新增FSM状态：
  - `S_FLUSH_SCAN` (3'd5)：扫描 `tag_ram[flush_set][flush_way]`
    - 若 valid=1 && dirty=1 → 锁定set/way，转 `S_FLUSH_WB_READ`
    - 若无效或干净 → 推进到下一个way/set
    - 全部扫描完毕 → 清除所有valid位，`flush_done=1`，回S_IDLE
  - `S_FLUSH_WB_READ` (3'd6)：读取数据BRAM（Port B），转 `S_FLUSH_WB_SEND`
  - `S_FLUSH_WB_SEND` (3'd7)：发 `wb_req`，等 `wb_valid`，清脏位，推进计数器，回 `S_FLUSH_SCAN`
- 新增计数器：`flush_set[2:0]`、`flush_way[1:0]`（遍历8×4=32项）
- `flush_req` 仅在S_IDLE时接受

#### 步骤4：`cpu_controller.sv` — 新增STATE_FENCEI状态

- 输入：`dec_is_nop_like` 替换 `dec_is_fence`，新增 `dec_is_fencei`、`fencei_done`
- 新增状态 `STATE_FENCEI = 4'd9`
- STATE_DECODE中：`dec_is_nop_like` → STATE_FETCH（NOP）；`dec_is_fencei` → STATE_FENCEI
- STATE_FENCEI：等待 `fencei_done`（dcache flush完成 && icache invalidate完成），然后 → STATE_FETCH
- 新增输出 `fencei_req`（通知cache开始操作）

#### 步骤5：`core_top.sv` — fencei连线更新

- 新增wire：`dec_is_nop_like`、`dec_is_fencei`、`fencei_req`、`fencei_done`
- 新增wire：`dcache_flush_req`、`dcache_flush_done`、`icache_invalidate_req`、`icache_invalidate_done`
- `fencei_req` 连接控制器输出
- `dcache_flush_req = fencei_req`，`icache_invalidate_req = fencei_req && dcache_flush_done`（先flush dcache，再invalidate icache）
- `fencei_done = dcache_flush_done && icache_invalidate_done`
- PC更新逻辑：`dec_is_fence` → `dec_is_nop_like`
- 更新decode、controller、icache_ctrl、dcache_ctrl实例的端口连接

### 阶段7+b：访问错误异常

目标：修复AHB-lite,APB总线数据阶段和Burst传输阶段的错误响应会被忽略的问题，使其支持完整的错误响应机制。当访问到未定义地址区域时，总线传回错误响应，发生指令访问错误(1)、Load访问错误(5)或Store/AMO访问错误(7)同步异常（M模式）。

#### 步骤1：新建 `ahb_default_slave.sv`

- 路径：`dev/rtl/AHB-lite/ahb_default_slave.sv`
- 对NONSEQ/SEQ传输返回2周期ERROR响应（HRESP=1, 先HREADYOUT=0再HREADYOUT=1）
- 对IDLE/BUSY返回零等待OKAY
- HRDATA输出零

#### 步骤2：`ahb_lite_bus.sv` — 集成default slave

- SLAVE_NUM从4改为5
- 新增 `slave_HSELx[4] = ~(slave_HSELx[0] | slave_HSELx[1] | slave_HSELx[2] | slave_HSELx[3])`
- 实例化 `ahb_default_slave`，连接到 slave_HREADYOUT[4]、slave_HRESP[4]
- 更新 `slave_HRDATA` 拼接（default slave HRDATA = 0）

#### 步骤3：`cpu_bus_bridge.sv` — 错误检测与传播

- 新增输出端口：
  - `output icache_error` — icache mmio或refill的总线错误
  - `output dcache_error` — dcache mmio/refill/writeback的总线错误
  - `output dcache_error_is_store` — dcache错误是否为写操作
  - `output [31:0] bus_error_addr` — 错误地址
- 修改各状态的HRESP检查：
  - **S_MMIO_ADDR**：HRESP=ERROR时，设置对应error输出（而非吞掉），回S_IDLE
  - **S_MMIO_DATA**：新增HRESP检查。HREADY=1 && HRESP=ERROR → 设置error，回S_IDLE
  - **S_IREFILL_DATA / S_DREFILL_DATA**：每拍检查HRESP。ERROR → 终止突发（HTRANS=IDLE），设置error，回S_IDLE
  - **S_WB_DATA**：每拍检查HRESP。ERROR → 终止突发，设置error，回S_IDLE
- error信号为脉冲（有效一个周期），在trap manager中锁存

#### 步骤4：`cpu_trap_manager.sv` — 新增访问错误异常

- 新增输入：
  - `input inst_access_fault`，`input [31:0] inst_access_fault_addr`（cause 1）
  - `input load_access_fault`，`input [31:0] load_access_fault_addr`（cause 5）
  - `input store_access_fault`，`input [31:0] store_access_fault_addr`（cause 7）
- 新增异常源：
  - `inst_access_fault_valid`：取指阶段错误，cause=1，mtval=地址
  - `mem_access_fault_valid`：访存阶段错误，cause=5(load)/7(store)，mtval=地址
- 优先级：`inst_access_fault` > `exception_at_decode` > `mem_access_fault` > `misalign_exception` > `exe_exception`

#### 步骤5：`cpu_trap_csr.sv` — 透传access fault信号

- 新增输入端口，透传到 `cpu_trap_manager`

#### 步骤6：`cpu_controller.sv` — 取指错误处理

- 新增输入 `inst_access_fault`
- STATE_DECODE开头检查 `inst_access_fault`，若有效 → STATE_TRAP_ENTER（跳过正常解码流）

#### 步骤7：`core_top.sv` — bus error连线更新

- 新增wire：`icache_error`、`dcache_error`、`dcache_error_is_store`、`bus_error_addr`
- 连接bridge的error输出到trap_csr的access fault输入
- `inst_access_fault = icache_error`
- `load_access_fault = dcache_error && !dcache_error_is_store`
- `store_access_fault = dcache_error && dcache_error_is_store`

### 阶段8：仿真验证

1. 编译测试程序coe加载到主存（Sram IP通过COE初始化）
2. 运行Vivado XSim行为仿真
3. 验证：CPU从0x8000_0000取指 → icache miss → AHB refill → 执行正确
4. 验证：dcache load/store → hit/miss → refill/writeback
5. 验证：MMIO访问仍正常旁路

### 阶段9：进度记录

更新`dev\PROCESS-mcs.md`，记录每步完成状态和设计决策。

## 验收

验收目标：将coe加载到主存，cpu完成执行且结果正确，预计不需要更改测试程序。

注意：cpu复位应该读取0x8000_0000（内存模型主存首地址），当前已是此值（core_top.sv:149）。

## 参考资料

上一阶段完成后项目整体报告：dev\docs\simpleCPU-design-report.md
tree-PLRU替换算法描述：dev\docs\Mem\tree-PLRU.txt
AHB-lite标准文件：dev\docs\AHB-lite\AMBA_AHB-Lite_Spec_Summary.md
APB标准文件：dev\docs\APB\AMBA_APB_Spec_Summary.md
M模式标准：dev\docs\privileged\machine-mode.md

## 工具

vivado_do.tcl：vivado tcl 脚本，使用其进行模拟
tools\rv2coe.py：rv汇编/C程序编译脚本，输出格式HEX/COE/...

## 开发约束

将更改和进度输出到dev\PROCESS-mcs.md中。
