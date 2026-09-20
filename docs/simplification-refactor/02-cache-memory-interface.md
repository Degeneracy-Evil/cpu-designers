# CPU 代码简化重构：Cache / Memory Interface

> 分支：`chp`  
> 前置阶段：`01-mmu-tlb-ptw.md` 已完成 Phase 1。  
> 本文定义后续 **Phase 2：Cache/MMU 接口收口** 与 **Phase 3：统一 Memory Transaction Interface / AXI bridge**。

## 1. 目标

本阶段不再重写 Cache 算法，而是收紧模块边界，删除历史兼容接口和多余状态，使 memory subsystem 形成清晰的分层：

```text
VA
 |
 v
MMU
 |
 | PA
 v
ICache / DCache
 |
 | simple memory transaction
 v
Memory Arbiter
 |
 v
AXI Master Adapter
 |
 v
DDR / BootROM / PLIC / CLINT / UART
```

原则：

1. Cache 只理解 **physical address**，不理解 VA/MMU。
2. ICache/DCache 保留当前朴素结构，不为重构而重构。
3. Cache 与 bus bridge 之间统一为阻塞式 request/response。
4. 系统最多一个 external memory transaction outstanding。
5. 保留 32B cache-line AXI burst。
6. 删除已经失效的 PTW direct-to-AXI 路径。
7. bus error 必须由发起者明确归属，不由 `core_top` 根据实时信号猜测。

---

## 2. 当前 Cache 结构：默认保留

当前 `chp` 已经是较简单的 blocking Cache。

### ICache

```text
2-way
8 sets
32 B / line
register tags
BRAM line data
blocking
```

### DCache

```text
2-way
8 sets
32 B / line
register tags
BRAM line data
blocking
write-through
load miss allocate
store miss no-allocate
no dirty line
no writeback
```

本阶段不主动改变：

- set / way 数量；
- cache-line 大小；
- replacement 策略；
- write-through 策略；
- load allocate / store no-allocate；
- BRAM line data。

当前每 set 1-bit victim replacement 足够简单，继续保留。

---

# Phase 2：Cache / MMU 接口收口

## 3. Cache 改成纯 PIPT 接口

当前 Cache 仍接收：

```text
cpu_req_addr   // PA
cpu_req_vaddr  // VA
mmu_ready
```

这是历史 VIPT 接口遗留。

虽然当前 set/index 位完全位于 4 KiB page offset 内，因此 VA/PA 对应位实际相同，但接口仍然让 Cache 知道了不该知道的 MMU 状态。

Phase 2 改为：

```text
VA
 |
 v
MMU
 |
 | PA + ready
 v
Cache
```

Cache CPU 侧只接收：

```text
req_valid
req_paddr
req_wdata
req_write
req_size
```

不再接收：

```text
req_vaddr
mmu_ready
```

由 `core_top` 负责：

```text
icache_req_valid = if_valid && mmu_inst_ready

dcache_req_valid = mem_en && mmu_data_ready
```

Cache 内部所有：

- byte offset；
- word offset；
- set index；
- tag；

都从 PA 提取。

---

## 4. 物理地址分解

当前几何：

```text
32 B line
8 sets
2 ways
```

因此：

```text
PA[1:0]   byte offset
PA[4:2]   word offset
PA[7:5]   set index
PA[31:8]  tag
```

建议将 tag 明确定义为：

```text
tag = PA[31:8]
```

即完整 24-bit physical tag。

不再手工配置 `tag_width = 19`。

当前 19-bit tag 依赖“只有 128 MiB DDR 区域可缓存”这一地址布局假设。对只有 16 条 line 的 Cache，省几个 tag bit 没有意义，完整 physical tag 更直观、更稳妥。

---

## 5. Cacheable 判断

当前 Cacheable/MMIO 判断不应继续依赖少量高地址位。

统一定义：

```text
cacheable =
    PA >= DDR3_BASE_ADDR &&
    PA <  DDR3_BASE_ADDR + DDR3_MEM_SIZE
```

当前配置即：

```text
0x8000_0000 <= PA < 0x8800_0000
```

其余物理地址全部走 direct/uncached path。

这样可以避免：

- unmapped physical address 被错误当作 cacheable；
- 高位地址被 tag 截断后 alias；
- Cache correctness 隐式依赖 SoC 地址空间布局。

---

## 6. ICache invalidate 简化

ICache 当前 valid/tag 为寄存器，仅 data line 使用 BRAM。

因此 `FENCE.I` invalidate 不需要逐 set FSM。

允许在一个时钟内：

```text
for all set/way:
    valid = 0
```

无需清空 data BRAM。

可以删除：

- `S_INVALIDATE`
- `invalidate_set_r`

`invalidate_done` 可在 invalidate 请求被接受后产生一个明确 completion pulse。

如果当前综合工具对 reset/批量 valid 写法有特殊限制，以“最简单且可综合”为准，但不要为了 BRAM data 清零引入额外状态。

---

## 7. DCache PTW owner 保留

PTW 已经通过 DCache 访问物理页表。

DCache 继续保留两个逻辑 requester：

```text
CPU physical request
PTW physical request
```

内部规则：

```text
IDLE:
    if PTW valid:
        latch owner = PTW
    else if CPU valid:
        latch owner = CPU
```

一旦请求被接受：

```text
owner 不变
直到 transaction completion
```

不支持 CPU/PTW 并发。

PTW 访问：

- 地址已经是 physical address；
- 固定 32-bit word；
- 可以命中或 miss DCache；
- store A/D bit 时走与 CPU store 相同的 write-through 路径。

不再增加额外 snoop / invalidate / coherence workaround。

---

# Phase 3：统一 Memory Transaction Interface

## 8. 目的

当前 bridge 仍暴露多个历史 client-specific 接口：

```text
icache_mmio_req
dcache_mmio_req
icache_refill_req
dcache_refill_req
ptw_req
```

其中：

- `dcache_mmio_req` 实际也承载正常 DDR write-through store；
- PTW direct bridge path 已经不再使用；
- level-style request 需要 `block_*_r` 防止重复接收。

Phase 3 将 ICache/DCache 对下游统一成一个简单 blocking memory port。

---

## 9. 统一 memory request

建议每个 Cache 向下游提供：

```text
mem_req_valid
mem_req_ready

mem_req_addr
mem_req_write
mem_req_size
mem_req_len
mem_req_wdata
```

含义：

```text
mem_req_len = 0
    single-beat transaction

mem_req_len = 7
    8-beat / 32B cache-line read
```

初版只需要支持：

```text
read  len=0
read  len=7
write len=0
```

不需要支持 cache-line write burst，因为当前 DCache 为 write-through，无 dirty/writeback。

---

## 10. 统一 memory response

建议：

```text
mem_resp_valid
mem_resp_data[255:0]
mem_resp_error
```

约定：

- single-beat read：仅 `resp_data[31:0]` 有效；
- line refill：`resp_data[255:0]` 有效；
- write completion：data ignored；
- error 与本次 transaction 绑定。

如果实现上把 single-beat 与 line response 分开能显著减少 RTL，也允许采用两个 data field，但必须保持一个统一 request/response transaction 语义。

---

## 11. VALID / READY 协议

请求必须是明确的握手，不再依赖“req 保持高直到 source 自己观察 completion”的兼容模式。

Cache：

```text
MEM_REQ:
    req_valid = 1
    wait req_ready

MEM_WAIT:
    req_valid = 0
    wait resp_valid

DONE
```

Bridge/arbiter 只在：

```text
req_valid && req_ready
```

时接受一次请求。

因此应删除类似：

- `block_i_refill_r`
- `block_d_refill_r`
- `block_ptw_r`
- 仅用于 level-request 去重的状态。

---

## 12. ICache 下游行为

ICache 只产生：

### Uncached instruction fetch

```text
read
len = 0
size = 4 B
```

### Cache miss refill

```text
read
len = 7
size = 4 B
addr = line aligned
```

不产生 write。

---

## 13. DCache 下游行为

DCache 只产生：

### Uncached load

```text
read
len = 0
size = CPU load size
```

### Store

write-through，因此所有 store 都产生：

```text
write
len = 0
size = CPU store size
wdata = CPU/PTW data
```

对于 cache hit，在 backing write 成功后更新 cached bytes。

对于 store miss，不 allocate。

### Load miss refill

```text
read
len = 7
size = 4 B
addr = line aligned
```

---

## 14. Memory Arbiter

I/D Cache 共用一个 external memory port。

初版只需要固定优先级。

建议：

```text
DCache > ICache
```

原因：

- 当前 CPU 严格顺序执行，不存在持续 I/D 并行压力；
- DCache 可能承载 PTW；
- 规则简单且确定。

一旦接受请求，arbiter 锁存：

```text
owner = ICache / DCache
```

直到 response 返回。

不做：

- round-robin fairness；
- multiple outstanding；
- owner switching；
- response reordering。

---

## 15. AXI Master Adapter

AXI adapter 只理解统一 memory transaction，不理解 ICache/DCache/PTW。

状态机保持：

```text
IDLE

READ_ADDR
READ_DATA

WRITE_SEND
WRITE_RESP
```

最多一个 outstanding transaction。

### Read

```text
IDLE
 -> latch request
 -> READ_ADDR
 -> AR handshake
 -> READ_DATA
 -> collect beats
 -> RLAST
 -> response
 -> IDLE
```

### Write

```text
IDLE
 -> latch request
 -> WRITE_SEND
 -> AW/W handshake
 -> WRITE_RESP
 -> B response
 -> response
 -> IDLE
```

---

## 16. 保留 AXI burst

Cache line 为：

```text
32 B = 8 × 32-bit beat
```

Refill 继续使用：

```text
ARLEN = 7
ARSIZE = 4 B
ARBURST = INCR
```

不把 line refill 拆成 8 次 single read。

这是局部且简单的性能优化，同时状态机也更清楚。

---

## 17. 删除 PTW direct bridge path

Phase 3 完成后，PTW 唯一路径：

```text
PTW
 |
 v
DCache
 |
 v
memory port
 |
 v
AXI
```

从 `cpu_bus_bridge.sv` 删除：

- `CLIENT_PTW`
- `ptw_req`
- `ptw_addr`
- `ptw_we`
- `ptw_wdata`
- `ptw_rdata`
- `ptw_done`
- `ptw_error`
- `block_ptw_r`

同时删除 `core_top.sv` 中对应的 unused tied-off bridge wires。

---

## 18. Bus error 归属

错误必须沿 transaction owner 返回。

不允许再由 `core_top` 使用实时信号判断：

```text
bridge error && !ptw_req
```

### ICache

```text
AXI error
 -> ICache mem_resp_error
 -> instruction access fault
```

### DCache

DCache 已锁存 owner：

```text
AXI error
 -> DCache
 -> if owner == CPU:
        CPU access fault
    else if owner == PTW:
        PTW access error
```

DCache 同时锁存本次 transaction 的 physical address，因此 fault address 使用 transaction-latched address，而不是 live bus address。

---

# 配置清理

## 19. 删除旧 TLB geometry 配置

新 TLB 已经是：

```text
16-entry fully associative register array
```

因此删除：

```text
memory.tlb.num_ways
memory.tlb.num_sets
TLB_NUM_WAYS
TLB_NUM_SETS
TLB_SET_IDX_WIDTH
TLB_WAY_WIDTH
```

如果希望保留参数化，只保留：

```text
TLB_ENTRIES = 16
```

或者直接在 TLB module parameter 中定义，不需要经过 Vivado Cache 配置生成系统。

---

## 20. 删除手工 Cache tag_width

建议配置系统只保留真正决定 Cache 几何的参数：

```text
num_sets
num_ways
line_words
```

`tag_width` 应根据 32-bit physical address 和：

```text
byte offset
word offset
set index
```

自动推导。

当前：

```text
tag width = 32 - 2 - log2(8 words) - log2(8 sets)
          = 24 bit
```

不要再通过 YAML 手工填写 19。

---

## 21. 避免假参数化

当前 RTL 实际固定为 2-way，并直接存在：

```text
hit0
hit1
way0
way1
```

因此不要在文档/配置中暗示 `num_ways` 可以任意修改，除非 RTL 真正支持。

当前优先目标是：

> 一颗结构明确的 CPU，而不是通用 Cache generator。

允许保留 2-way/8-set/32B line 为明确架构选择。

---

# 实施边界

## 22. Phase 2 可以修改

- `icache_ctrl.sv`
- `dcache_ctrl.sv`
- `core_top.sv`
- cache address macros / generator
- Cache unit tests

但不修改：

- MMU/PTW/TLB 语义；
- Cache replacement policy；
- DCache write policy；
- AXI protocol adapter。

## 23. Phase 3 可以修改

- `cpu_bus_bridge.sv`，或拆成：
  - `memory_arbiter.sv`
  - `axi_master_adapter.sv`
- ICache/DCache 下游接口
- `core_top.sv` glue
- bus/cache unit tests

不修改：

- Cache hit/miss policy；
- MMU/PTW/TLB；
- SoC address map；
- MIG / PLIC / CLINT / UART 实现。

---

# 验证

## 24. Phase 2 必须覆盖

- ICache hit / miss
- ICache line refill
- ICache uncached fetch
- ICache invalidate
- DCache load hit / miss
- DCache refill
- DCache store hit
- DCache store miss no-allocate
- byte / halfword / word store
- PTW DCache hit
- PTW DCache miss
- PTW A/D write
- CPU store PTE -> PTW observes latest value
- cacheable DDR boundary
- address below DDR uncached
- address at / above `0x8800_0000` uncached/error path
- MMU + Cache regression
- `FENCE.I`
- `SFENCE.VMA`

## 25. Phase 3 必须覆盖

- ICache single read
- ICache 8-beat refill
- DCache single read
- DCache single write
- DCache 8-beat refill
- AW/W independent handshake
- B error
- R error
- owner remains stable until response
- no duplicate request acceptance
- no request retargeting
- I/D arbitration
- bus error returned to correct owner
- PTW error through DCache
- complete CPU regression
- Linux testbench smoke

完成每个 Phase 后先冻结并跑完整回归，再继续下一阶段。

---

# 最终目标结构

```text
             +----------------+
VA ---------->      MMU       |
             +--------+-------+
                      |
                      | PA
          +-----------+-----------+
          |                       |
    +-----v-----+           +-----v-----+
    |  ICache   |           |  DCache   |<----- PTW
    | blocking  |           | blocking  |
    | 2-way     |           | 2-way     |
    +-----+-----+           +-----+-----+
          |                       |
          | memory transaction    |
          +-----------+-----------+
                      |
                +-----v-----+
                |  Arbiter  |
                +-----+-----+
                      |
                +-----v-----+
                | AXI Master|
                |  Adapter  |
                +-----+-----+
                      |
                      v
             DDR / SoC peripherals
```

这一结构保留完整 Cache/MMU/PTW/AXI 功能，但每层只承担一个明确职责，便于后续 Linux bring-up 时逐层定位错误。
