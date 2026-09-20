# CPU 代码简化重构：MMU / TLB / PTW

> 分支：`chp`  
> 目标：在**不删除 CPU 关键功能**的前提下，将实现改得更朴素、更容易验证和排错。  
> 当前阶段只设计 MMU / TLB / PTW；Cache 与总线随后单独设计。

## 1. 重构原则

本轮重构不是“最小化到能跑 Linux”，而是保留完整 CPU 组成，同时减少不必要的微架构复杂度。

保留：

- RV32IMA + Zicsr + Zifencei
- M / S / U 特权级
- Sv32
- TLB
- PTW
- I-Cache / D-Cache
- PLIC / CLINT / UART / DDR3
- OpenSBI + Linux 启动能力

简化原则：

1. **功能不删，性能优化从简。**
2. **一次只处理一个事务。** 不做多 outstanding、不做并行 page walk。
3. **状态边界清晰。** 优先采用 `REQ -> WAIT -> CHECK`。
4. **避免跨模块隐式状态。** 不为了省几个周期引入额外 arbitration、bypass、coherence 补丁。
5. **局部且容易验证的优化可以保留。**
6. **当前 CPU 严格顺序执行的前提不变。** Fetch / Decode / Execute / MEM / WB 不并行推进多条指令。

---

## 2. 目标结构

```text
             Fetch / Load / Store VA
                      |
                      v
                +-----------+
                |    MMU    |
                | blocking  |
                +-----+-----+
                      |
               +------v------+
               | Unified TLB |
               | 4 set x 4way|
               |  registers  |
               +------+------+
                    hit|miss
                       v
                 +-----------+
                 |    PTW    |
                 | Sv32 FSM  |
                 +-----+-----+
                       |
                 physical PTE
                 read / write
                       |
                       v
                   D-Cache
```

MMU 最终提供：

```text
VA -> MMU -> PA -> Cache
```

以后 Cache 改为 PIPT 时，不需要再次重做 MMU 接口。

---

## 3. TLB

### 3.1 组织

保留真正的组相联 TLB：

```text
16 entries
= 4 sets x 4 ways
```

但底层改为普通寄存器数组，不再使用 BRAM。

采用 **Unified TLB**。当前 CPU 的 instruction fetch 与 data memory access 不并发，因此不需要 I-TLB / D-TLB 双端口并行查询。

每个 entry 至少包含：

```text
valid
VPN[19:0]
PPN[21:0]
ASID[8:0]
G
R/W/X/U/A/D
megapage
```

### 3.2 Lookup

每次只查询一个 set，并行比较 4 个 way。

当前建议：

```text
set index = VPN1 的低 2 bit
```

这样 4 MiB megapage 在匹配时可以直接忽略 VPN0，而不需要把一个 megapage entry 复制到多个 set。

代价是同一 4 MiB 区域内的 4 KiB 页面更容易产生 set conflict。当前阶段接受这一性能损失；如果以后实际 profile 证明 TLB thrashing 明显，再单独优化，不在本轮引入额外结构。

### 3.3 Replacement

不使用 PLRU。

每个 set 维护一个 2-bit round-robin victim pointer：

1. fill 时优先选择 invalid way；
2. 全部 valid 时选择 victim pointer；
3. fill 完成后 victim pointer 循环加一。

Replacement 不影响架构正确性，因此优先选择最容易验证的策略。

### 3.4 Flush

初版只实现 full flush：

- `SFENCE.VMA`：所有 entry `valid = 0`
- 实现可以在检测到 `satp` 改变时保守地 full flush

后者是本实现的保守策略，不依赖精细 ASID/VA flush 来保证正确性。

---

## 4. MMU

### 4.1 单一 translation engine

删除当前 I-side / D-side 两套独立 FSM 以及 walk arbitration。

MMU 每次只接受一个 translation request：

```text
req_valid
req_vaddr
req_access   // FETCH / LOAD / STORE
req_priv
```

输入还包括：

```text
satp
mstatus.SUM
mstatus.MXR
```

输出：

```text
resp_valid
resp_paddr

resp_fault
resp_fault_cause
resp_fault_vaddr
```

请求进入 MMU 后全部 latch，直到本次 translation 完成，不依赖上游 live signal。

### 4.2 MMU FSM

建议状态：

```text
IDLE
  |
  v
LOOKUP
  |
  +-- Bare / translation disabled ------> RESP
  |
  +-- TLB hit --------------------------> CHECK
  |                                        |
  |                                        +-- OK ----------> RESP
  |                                        |
  |                                        +-- fault -------> RESP_FAULT
  |                                        |
  |                                        +-- need A/D ----> WALK
  |
  +-- TLB miss --------------------------> WALK
                                             |
                                             v
                                          TLB_FILL
                                             |
                                             v
                                           RESP
```

原则：

- lookup 可以使用组合比较；
- request、lookup、权限判断、fill、response 分阶段处理；
- 不在同一个周期为了减少 latency 连续完成多项状态转换；
- 一个 translation 未结束时，不接收第二个请求。

---

## 5. PTW

### 5.1 严格串行 Sv32 walker

删除 pre-issue / overlap 优化。

建议 FSM：

```text
IDLE
 |
L1_REQ
 |
L1_WAIT
 |
L1_CHECK
 |
 +-- leaf ------------------------------+
 |                                      |
 +-- non-leaf -> L0_REQ                 |
                  |                     |
                L0_WAIT                 |
                  |                     |
                L0_CHECK                |
                  |                     |
                  +---------------------+
                                        |
                                   PERM_CHECK
                                        |
                           +------------+-----------+
                           |                        |
                         no A/D                  need A/D
                           |                        |
                           |                      AD_REQ
                           |                        |
                           |                      AD_WAIT
                           |                        |
                           +------------+-----------+
                                        |
                                      DONE
```

每个状态只负责一件明确的事情：

- `*_REQ`：生成并提交请求；
- `*_WAIT`：只等待 completion / error；
- `*_CHECK`：只解析和检查返回的 PTE。

不允许“本周期收到 L1 response，同时预发 L0 request”这类优化。

### 5.2 PTE 检查

必须继续完整实现 Sv32 所需检查，包括：

- V
- 非法 `R=0, W=1`
- leaf / non-leaf
- U/S privilege
- SUM
- MXR
- R/W/X
- megapage PPN alignment
- A/D

PTE 无效、权限失败、megapage 对齐错误等产生对应 page fault。

访问页表物理内存本身失败产生对应 access fault。

### 5.3 物理地址宽度

当前 SoC AXI / 物理地址通路为 32 bit，而 Sv32 PTE 的 PPN 可以表达超过当前实现范围的物理地址。

因此：

- 不能简单静默截断高位 PPN；
- 对当前硬件无法表示 / 访问的物理地址必须明确失败；
- 具体 fault 映射在实现阶段结合现有 trap 路径统一处理。

---

## 6. PTW 通过 D-Cache 访问页表

这是本轮最重要的结构调整。

当前实现中：

```text
CPU page-table store -> DCache
PTW PTE read/write   -> AXI
```

导致 DCache 与 PTW 看到的页表内容可能不一致，因此现在需要：

- PTW read 前 flush DCache；
- PTW A/D write 后 invalidate DCache line；
- `ptw_bus_hold` 等额外控制。

新的结构改为：

```text
CPU load/store -------+
                      |
                      v
                    DCache
                      ^
                      |
PTW PTE read/write ---+
```

PTW 访问的是已经计算好的 **physical PTE address**，因此 PTW 不会递归经过 MMU。

当前 CPU 严格顺序执行，因此：

```text
TLB miss
 -> 当前 CPU 访问暂停
 -> PTW 获得 DCache 使用权
 -> page walk 完成
 -> CPU 恢复
```

实现上只需要明确 owner：

```text
PTW busy ? PTW request : CPU request
```

不做 CPU/PTW 并行访问。

这样可以从结构上删除现有 PTW/DCache coherence 补丁。

### 6.1 当前假设

本设计当前针对单 hart CPU，且假设不存在能够与 PTW 并发修改页表的 coherent 外部 master。

如果以后增加：

- 多 hart；
- DMA / IOMMU；
- 其他可并发写页表的 master；

则需要重新审视页表访问的原子性和 coherence 规则。

---

## 7. SFENCE.VMA 与 FENCE.I

两者职责明确分离。

### SFENCE.VMA

本轮初版：

```text
SFENCE.VMA
  -> TLB full flush
  -> done
```

不再因为 PTW/DCache coherence 而：

- flush 整个 DCache；
- invalidate ICache。

### FENCE.I

保持真实 Cache 一致性需要：

```text
FENCE.I
  -> DCache writeback / flush
  -> ICache invalidate
  -> done
```

这部分属于必要功能，不在本轮删除。

---

## 8. 本轮明确删除的复杂度

完成重构后，MMU/TLB/PTW 路径应不再需要：

- BRAM TLB read latency handling
- dual-port TLB
- I/D parallel lookup
- Port-B fill preemption
- READ_FIRST collision handling
- shadow valid for BRAM victim selection
- I/D walk arbitration
- pending I/D walk
- PTW fill direct bypass
- PTW L1 -> L0 pre-issue
- PTW read 前 full DCache flush
- PTW A/D write 后 DCache line invalidate
- `ptw_bus_hold` 一类 coherence workaround

---

## 9. 暂不修改的部分

本阶段不主动重构：

- I-Cache / D-Cache 具体组织
- AXI bus bridge
- CSR
- trap / interrupt
- decode / execute
- M extension
- A extension
- PLIC / CLINT / UART
- MIG / DDR3
- APB / SoC peripheral

其中 Cache 和 bus bridge 是后续简化阶段，等新的 MMU/PTW 接口稳定后再设计，避免重复返工。

后续预计顺序：

```text
Phase 1: MMU / TLB / PTW
Phase 2: I-Cache / D-Cache
Phase 3: memory transaction interface / AXI bridge
Phase 4: core_top glue cleanup
Phase 5: Linux bring-up regression
```

---

## 10. 验证要求

每一步重构都必须先保证功能等价，再继续下一步。

至少覆盖：

- Bare mode translation bypass
- Sv32 4 KiB page hit / miss
- Sv32 4 MiB megapage
- TLB hit / miss / fill / replacement
- full flush
- U/S permission
- SUM / MXR
- R/W/X
- invalid PTE
- reserved `R=0,W=1`
- megapage alignment fault
- A update
- D update
- instruction / load / store page fault
- page-table memory access fault
- PTW through DCache hit
- PTW through DCache miss
- CPU store PTE -> PTW immediately observes latest value
- `SFENCE.VMA`
- `FENCE.I` regression

最终目标不是提升性能，而是获得一个行为容易解释、波形容易追踪、Linux 问题容易定位的 reference-quality RV32 implementation。
