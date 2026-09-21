# CPU 代码简化重构：Architecture Foundation

> 分支：`chp`  
> 前置阶段：MMU/TLB/PTW、Cache/Memory Interface、Control Path 已完成结构简化。  
> 本文定义后续功能开发的公共架构基础。后续 Trap、A Extension、PMP/PMA、CSR/Privilege、SoC address-map 工作都应建立在本文约定之上。

## 1. 背景

前三轮重构已经使 Controller、MMU/TLB/PTW、Cache、CPU bus bridge 基本收敛。重新审查完整 RTL 后，剩余问题主要来自多个模块对同一架构概念存在不同解释，而不是模块本身过于复杂。

当前典型问题：

- `mem_hwrite` 同时被当作 physical write 和 architectural store；
- AMO 的 read phase 被 MMU 看成 load；
- SC reservation fail 仍先做普通 read；
- store data 在 cpu_mem 和 DCache 被重复做 byte-lane placement；
- faulting PA / VA / PC 在异常路径中存在语义混淆；
- IF→ID、ID→EXE 仍使用 raw packed vector；
- privilege、memory access type、exception information 在多个模块重复定义；
- SoC physical address map 分散在 Cache、system_top、peripheral 等位置。

本阶段不继续增加 wrapper，而是建立少量、稳定、明确的公共契约。

---

# 2. 总体原则

## 2.1 Architecture semantics 与 physical micro-operation 分离

以后必须明确区分：

```text
Architectural memory operation
    LOAD
    STORE
    LR
    SC
    AMO

Physical memory micro-operation
    READ
    WRITE
```

例如 AMO：

```text
AMOADD.W

architectural kind = AMO
fault class        = STORE

physical phase 1   = READ old value
physical phase 2   = WRITE new value
```

不能再根据当前 physical read/write phase 推导 page-fault、PMP 或 PMA 权限类型。

SC reservation fail 即使最终没有 physical write，也仍然是 STORE-class architectural access。

## 2.2 stage 之间传递结果，而不是重复解释指令

每一级只把下一阶段真正需要的信息向后传递。

例如 WB 最终只应该知道：

```text
write enable
rd
write value
PC
instruction
```

WB 不应该再判断：

```text
is CSR?
is JAL?
is AMO?
is SC?
```

这些语义应在前一级已经转换成最终 writeback value。

## 2.3 一个架构概念只定义一次

以下公共概念统一进入公共 type/header：

- privilege mode；
- architectural memory kind；
- MMU/PMP/PMA access class；
- exception descriptor；
- stage bus type。

以下平台事实统一进入 SoC address-map header：

- DDR range；
- BootROM range；
- CLINT / PLIC / APB / SysStatus range。

禁止各模块重新复制 magic constants。

---

# Phase 5.1：Typed Core Contracts

## 3. 统一 privilege type

当前多个模块重复定义 privilege encoding。统一为：

```systemverilog
typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
} priv_mode_t;
```

建议放入 `core_bus_types.svh`；如果公共类型继续增加，可以将其重命名为更通用的 `core_types.svh`。

以下模块统一使用同一类型：

- core_top
- MMU
- PTW
- CSR
- Trap
- PMP

reserved encoding `2'b10` 仍然不是合法 privilege mode，后续 CSR/Privilege 阶段需单独处理 WARL 行为。

## 4. Architectural memory kind

新增：

```systemverilog
typedef enum logic [2:0] {
    MEM_NONE  = 3'd0,
    MEM_LOAD  = 3'd1,
    MEM_STORE = 3'd2,
    MEM_LR    = 3'd3,
    MEM_SC    = 3'd4,
    MEM_AMO   = 3'd5
} mem_kind_t;
```

Decode 负责唯一一次分类：

```text
LB/LH/LW/LBU/LHU -> MEM_LOAD
SB/SH/SW         -> MEM_STORE
LR.W             -> MEM_LR
SC.W             -> MEM_SC
AMO*.W           -> MEM_AMO
other            -> MEM_NONE
```

后续 stage 不再同时传播 `is_load/is_store/is_amo/is_lr/is_sc` 五组互相关联的 boolean。允许模块内部从 `mem_kind` 派生局部 wire，但不再写回 stage bus。

## 5. Architectural access class

MMU/PMP/PMA 实际只需要三种权限类别：

```systemverilog
typedef enum logic [1:0] {
    ACCESS_FETCH = 2'd0,
    ACCESS_LOAD  = 2'd1,
    ACCESS_STORE = 2'd2
} access_class_t;
```

统一映射：

```text
instruction fetch -> ACCESS_FETCH

MEM_LOAD           -> ACCESS_LOAD
MEM_LR             -> ACCESS_LOAD

MEM_STORE          -> ACCESS_STORE
MEM_SC             -> ACCESS_STORE
MEM_AMO            -> ACCESS_STORE
```

提供统一 helper/function 将 `mem_kind_t` 映射成 `access_class_t`。MMU/PTW 中现有重复 ACCESS_* localparam 逐步删除。

---

## 6. IF→ID typed bus

当前 `if_id_bus[95:0]` 改为：

```systemverilog
typedef struct packed {
    logic [31:0] pc_plus4;
    logic [31:0] pc;
    logic [31:0] inst;
} if_id_bus_t;
```

`cpu_fetch` 输出 `if_id_bus_t`，`cpu_decode` 直接按 field 访问。删除拼接/拆解和 core_top 中的 raw bit slicing。

## 7. ID→EXE typed bus

当前 330-bit raw vector 改为 `id_exe_bus_t`。

建议按职责组织：

```systemverilog
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] inst;

    logic [15:0] alu_control;
    logic [31:0] alu_src1;
    logic [31:0] alu_src2;

    logic        is_branch;
    logic        is_jal_like;
    logic [2:0]  branch_funct3;

    logic        use_fixed_wb;
    logic [31:0] fixed_wb_data;
    logic        wb_we;
    logic [4:0]  wb_rd;

    logic        is_mu;
    logic [2:0]  mu_funct3;

    mem_kind_t   mem_kind;
    logic [2:0]  mem_size;
    logic        mem_unsigned;
    logic [31:0] store_data;

    logic [4:0]  amo_funct5;
    logic        amo_aq;
    logic        amo_rl;

    logic        is_csr;
    logic [11:0] csr_addr;
    logic [2:0]  csr_funct3;
    logic [4:0]  csr_uimm;
    logic [4:0]  csr_rs1;
    logic [31:0] csr_rs1_value;
} id_exe_bus_t;
```

最终实现时根据实际消费者删减字段。不得因为旧 raw bus 中存在某字段就机械保留。

重点检查并删除仅在 Decode 有意义的历史字段，例如：

```text
valid_inst
is_alu
is_ecall
is_ebreak
is_mret
```

CSR path 可以继续复用 `id_exe_bus_t`，但必须使用 field name，禁止 raw bit slice。

## 8. EXE→MEM bus 收口

当前 `exe_mem_bus_t` 已是 typed struct，但 memory classification 仍冗余。

使用 `mem_kind` 替代：

```text
is_load
is_store
is_amo
is_lr
is_sc
```

目标大致为：

```systemverilog
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] inst;

    logic        result_ok;
    logic [31:0] result;
    logic        wb_we;
    logic [4:0]  wb_rd;

    mem_kind_t   mem_kind;
    logic [2:0]  mem_size;
    logic        mem_unsigned;
    logic [31:0] store_data;

    logic [4:0]  amo_funct5;
    logic        amo_aq;
    logic        amo_rl;
} exe_mem_bus_t;
```

CSR 不经过 MEM，因此不再为了历史路径把 CSR-only 字段塞入 EXE→MEM bus。

## 9. WB bus 收成最终 architectural result

当前 WB bus 仍包含 JAL/CSR/AMO 等语义。目标改为：

```systemverilog
typedef struct packed {
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    logic [31:0] pc;
    logic [31:0] inst;
} wb_bus_t;
```

前一级负责生成最终写回值：

```text
ALU        -> ALU result
LUI        -> immediate
JAL/JALR   -> PC + 4
CSR        -> old CSR value
Load       -> loaded value
LR         -> loaded value
AMO        -> old memory value
SC         -> 0 / 1
```

WB 不再解释 instruction class。

core_top 中 `actual_rf_wdata`、`wb_is_jal_like` 等 writeback semantic glue 随之删除。

## 10. 删除历史 dead interface

typed bus 转换过程中同步检查并删除无消费者的接口，重点包括：

```text
cpu_execute.exe_csr_wen
cpu_execute.exe_csr_waddr
cpu_execute.exe_csr_wdata
cpu_execute.exe_csr_old_val

core_top.dec_csr_funct3
core_top.dec_csr_addr_valid
core_top.dec_csr_access_ok
```

只要确认这些信号悬空、重复或只保留旧 compatibility，就直接删除。

---

# Phase 5.2：Architectural Memory Contract

## 11. 拆开 architectural access 与 physical request

当前 `mem_en/mem_hwrite/mem_hsize/dataAddr` 同时驱动 MMU 和 DCache，混合了两层语义。

以后拆成两组接口。

第一组表达整条 architectural memory operation：

```text
mem_access_valid
mem_vaddr
mem_kind
mem_size
```

这组信号用于：

```text
MMU
PMP
PMA
exception classification
```

它不描述当前 physical phase。

第二组表达真正的物理 transaction：

```text
phys_req_valid
phys_paddr
phys_write
phys_size
phys_wdata
```

只在 address/permission check 完成以后才允许发出。

## 12. Address-check pipeline

目标：

```text
mem_vaddr + mem_kind
          |
          v
   access_class
          |
          v
         MMU
          |
          v
         PMP
          |
          v
         PMA
          |
          v
   access_ready + PA
```

一条 architectural memory operation 的 access class 在整个生命周期内保持不变。

因此 AMO 第一阶段即使是 physical READ，也仍然是 STORE-class architectural access。

## 13. Physical operation mapping

```text
LOAD:
    architectural kind = LOAD
    physical op = READ

STORE:
    architectural kind = STORE
    physical op = WRITE

LR:
    architectural kind = LR
    physical op = READ

SC success:
    architectural kind = SC
    physical op = WRITE

SC fail:
    architectural kind = SC
    physical op = none

AMO:
    architectural kind = AMO
    physical op 1 = READ
    physical op 2 = WRITE
```

## 14. SC 顺序

SC 必须遵循：

```text
SC
 |
 +-> alignment check
 |
 +-> STORE-class MMU/PMP/PMA check
 |
 +-> denied -> synchronous exception
 |
 +-> allowed
       |
       +-> reservation mismatch
       |      |
       |      +-> clear reservation
       |      +-> rd = 1
       |      +-> no physical write
       |
       +-> reservation match
              |
              +-> physical WRITE
              +-> clear reservation
              +-> rd = 0
```

权限检查先于 reservation 判断。

## 15. AMO 顺序

```text
AMO
 |
 +-> alignment check
 |
 +-> STORE-class MMU/PMP/PMA check
 |
 +-> physical READ old value
 |
 +-> compute new value
 |
 +-> physical WRITE new value
 |
 +-> rd = old value
```

整个过程只使用一份经过检查得到的 PA。不得在 READ/WRITE phase 分别重新做 LOAD/STORE translation。

## 16. store data contract

cpu_mem 向下游输出的 store data 永远是低位有效的 architectural value：

```text
SB -> wdata[7:0]
SH -> wdata[15:0]
SW -> wdata[31:0]
```

cpu_mem 不根据 address 做 lane shift。

byte-lane placement 只允许存在一处，由 DCache 根据 PA 和 size 生成 byte enable 与 aligned lane data。

职责：

```text
cpu_mem
    architectural value

DCache
    address + size
    -> byte enable
    -> lane data

bus bridge
    -> AXI transaction
```

---

# Phase 5.3：Exception Contract

## 17. 统一 exception descriptor

新增：

```systemverilog
typedef struct packed {
    logic        valid;
    logic [31:0] cause;
    logic [31:0] epc;
    logic [31:0] tval;
} exception_t;
```

含义：

```text
cause : architectural exception cause
epc   : faulting instruction PC
tval  : architectural trap value
```

exception descriptor 中不保存 physical address。

PA 可以继续用于 Cache/Bus debug，但不能直接成为 architectural trap value。

## 18. Exception sources

统一来源：

```text
Fetch
    instruction access fault
    instruction page fault

Decode
    illegal instruction
    ecall
    ebreak

Execute
    instruction-address-misaligned

Memory
    load-address-misaligned
    store/AMO-address-misaligned
    load access fault
    store/AMO access fault
    load page fault
    store/AMO page fault
```

这些来源最终都转换成相同的 `exception_t`。

## 19. VA / PA / PC 严格区分

异常路径统一约定：

```text
epc = faulting instruction PC

tval:
    instruction address fault -> faulting virtual instruction address
    load/store address fault  -> faulting effective virtual address
    page fault                -> faulting virtual address
    illegal instruction       -> instruction bits
```

Cache/AXI 的 physical error address 只用于定位 downstream failure。

downstream physical failure 转成 architectural access fault 时，必须使用该 architectural operation 已锁存的 instruction PC、VA 和 access kind。

## 20. stage completion 的最终语义

后续 Trap 重构完成后：

```text
success -> stage_done
fault   -> exception.valid
```

stage_done 只表示成功完成。

例如：

```text
JAL target misaligned:
    exe_done = 0
    exe_exception.valid = 1

misaligned load:
    mem_done = 0
    mem_exception.valid = 1
```

但这一语义切换必须与后续统一 Trap/controller exception handling 同一次完成。

Foundation 阶段不得只改单个 stage 的 done 语义，留下 controller 无法退出的半完成状态。

## 21. Foundation 与 Trap 重构边界

本阶段建立：

- `exception_t` type；
- exception source 的统一数据格式；
- VA/PA/PC contract。

真正把 Controller/Trap manager 收口为：

```text
sync_exception_pending
interrupt_pending
```

留给下一阶段。

不得新增更多长期存在的 `*_fault_pending` 或 `*_misalign_pending` 作为补丁接口。

---

# Phase 5.4：SoC Address-Map Contract

## 22. 建立唯一物理地址定义

新增：

```text
src/rtl/soc_addr_map.svh
```

至少定义：

```text
DDR
    base = 0x8000_0000
    size = 0x0800_0000      // 128 MiB

BootROM
    base = 0xFC00_0000
    implemented size = 0x0000_8000   // 32 KiB

PLIC
    base = 0x0C00_0000

CLINT
    base = 0x0200_0000

SysStatus
    base = 0x0400_0000

APB
    base = 0x1000_0000
```

APB 当前子区域：

```text
slot 0  GPIO      0x1000_0000
slot 1  reserved  0x1000_4000
slot 2  UART      0x1000_8000
slot 3  SPI       0x1000_C000
```

PLIC/CLINT/APB/SysStatus 的最终 window size 在后续 SoC address-map cleanup 中根据实际 register layout 收紧。

## 23. implemented range 与 legacy decode window 分开

当前 system_top 存在 broad decode，例如：

```systemverilog
addr[31:24] == 8'hFC
```

这会把整个 16 MiB window 路由到实际只有 32 KiB 的 BootROM。

因此 address-map contract 必须区分：

```text
implemented range
legacy interconnect decode window
```

Foundation 阶段先定义真实 intended physical map，不在建立 header 时静默改变所有 decode 行为。

后续 SoC cleanup 再统一修改 system_top decoder。

## 24. address-map consumers

最终这些模块使用同一份 map：

```text
ICache / DCache cacheability
PMA checker
system_top address decoder
BootROM bounds
platform/debug information
```

不再维护多份 DDR/BootROM/MMIO range。

## 25. PMA 后续接口预留

Foundation 不实现完整 PMA，但 address map 为其提供平台事实。

目标 PMA：

```text
DDR
    R/W/X
    cacheable
    atomic-capable

BootROM
    R/X
    uncached
    no write
    no atomic

MMIO
    R/W
    uncached
    no execute
    no atomic

unmapped
    no access
```

PMA 是静态平台属性，不设计成可编程 CSR 或复杂 region table。

---

# 26. 实施顺序

建议按以下顺序开发，避免接口反复修改：

### 5.1A
统一 `priv_mode_t`、`mem_kind_t`、`access_class_t`，先建立公共 type。

### 5.1B
转换 `if_id_bus_t`、`id_exe_bus_t`、`exe_mem_bus_t`、`wb_bus_t`，删除 raw bit slicing 和 dead fields。

### 5.2A
Decode/Execute/MEM 全链路改用 `mem_kind`，删除 stage bus 中重复 memory booleans。

### 5.2B
拆分 architectural access 与 physical memory request，明确 AMO/SC 的 stable access class。

### 5.2C
收口 store-data convention：cpu_mem 输出 raw value，DCache 独占 lane placement。

### 5.3
加入统一 exception descriptor contract，并调整相关 module ports，为下一阶段 Trap 重整准备接口；此时不单独改变 stage_done fault semantics。

### 5.4
建立 `soc_addr_map.svh`，迁移确定无争议的平台常量；system_top broad decode 的行为修改留给后续 SoC cleanup。

---

# 27. 本阶段允许修改的区域

主要包括：

- `core_bus_types.svh`，必要时改为更通用的 core types header；
- `cpu_fetch.sv`
- `cpu_decode.sv`
- `cpu_execute.sv`
- `cpu_mem.sv`
- `cpu_wb.sv`
- `cpu_csr_interface.sv`
- `core_top.sv`
- MMU/PTW 中重复的 access/privilege type 定义；
- Cache CPU-side request 命名与 store-data convention；
- 新增 `soc_addr_map.svh`。

---

# 28. 本阶段不做的事情

本阶段不借接口重构扩大到：

- 重写 Controller FSM；
- 重写 MMU/TLB/PTW 算法；
- 修改 Cache policy；
- 重写 AXI bridge；
- 重写 system_top interconnect；
- 实现完整 Trap policy；
- 实现 PMP matcher；
- 实现 PMA checker；
- 修订所有 CSR WARL/WPRI；
- 改写 PLIC/CLINT/UART/GPIO/SPI。

这些都有后续独立阶段。

---

# 29. Foundation 完成后的目标结构

```text
                    Core architectural contracts
   +---------------------------------------------------+
   | priv_mode_t                                      |
   | mem_kind_t -> access_class_t                    |
   | exception_t                                      |
   | if_id / id_exe / exe_mem / wb typed buses       |
   +--------------------------+------------------------+
                              |
                              v
                    strictly serial core
                              |
                    architectural memory op
                              |
                VA + mem_kind + access class
                              |
                              v
                             MMU
                              |
                              v
                     future PMP / PMA
                              |
                              v
                              PA
                              |
               +--------------+--------------+
               |                             |
          physical READ                 physical WRITE
               |                             |
               +--------------+--------------+
                              |
                           DCache
                              |
                             AXI

SoC platform contract:
    soc_addr_map.svh
        -> Cache/PMA/system_top share one physical map
```

后续功能开发顺序：

```text
Unified Trap / Exception
          ↓
A Extension semantics
          ↓
PMP + PMA
          ↓
CSR / Privileged architecture
          ↓
SoC address-map cleanup
          ↓
remaining completeness fixes
```

从这一阶段开始，不再通过新增临时 signal 修补跨模块语义问题；新功能必须建立在统一 contract 上。
