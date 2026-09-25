> **[历史归档 2026-09-25]** 本文为 2026-06-14 的 A 扩展实现计划快照，基于当时的 RV32IMAF 设计（commit bb4b3fb）。A 扩展已实现并通过回归（`isa_a_ext` 52 子测试），现行设计为 RV32IMASU，AMO/LR/SC 实现见 `../simpleCPU-design-report.md` §3.5。仅作历史记录，勿作操作依据。

# A 扩展（原子指令）实现详细计划

> 日期: 2026-06-14 | 基于设计报告 commit bb4b3fb + near-linux-bug-fix | 目标: RV32IMAF（在现有 RV32IMF 基础上增加 A 扩展）
>
> **2026-06-14 更新**：经检查 near-linux-bug-fix（Bug 1-6）的 RTL 变更，确认 A 扩展计划无需结构性修改。
> 详见 [§8 计划验证与更新](#8-计划验证与更新near-linux-bug-fix-后)。

---

## 0. 需求分析

### 0.1 A 扩展指令集（RV32A，共 11 条）

A 扩展 = Zaamo（原子内存操作）+ Zalrsc（Load-Reserved/Store-Conditional）

**Zalrsc（2 条）：**

| 指令 | funct5 | opcode | 说明 |
|------|--------|--------|------|
| LR.W | 00010 | 0101111 | 加载并注册保留集 |
| SC.W | 00011 | 0101111 | 条件存储，成功写 0 到 rd，失败写非零 |

**Zaamo（9 条）：**

| 指令 | funct5 | opcode | 说明 |
|------|--------|--------|------|
| AMOSWAP.W | 00001 | 0101111 | 原子交换 |
| AMOADD.W | 00000 | 0101111 | 原子加 |
| AMOAND.W | 01100 | 0101111 | 原子与 |
| AMOOR.W | 01000 | 0101111 | 原子或 |
| AMOXOR.W | 00100 | 0101111 | 原子异或 |
| AMOMIN.W | 11000 | 0101111 | 原子有符号最小值 |
| AMOMAX.W | 10100 | 0101111 | 原子有符号最大值 |
| AMOMINU.W | 11100 | 0101111 | 原子无符号最小值 |
| AMOMAXU.W | 11110 | 0101111 | 原子无符号最大值 |

**指令编码格式（R-type）：**

```
| funct5[31:27] | aq[26] | rl[25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0] |
```

- opcode = 0101111（AMO）
- funct3 = 010（RV32 仅支持 word 宽度）
- aq/rl 位控制内存排序语义

### 0.2 关键约束

1. **单 hart 系统**：当前 CPU 为单核单 hart，LR/SC 保留集仅需跟踪本 hart 的保留
2. **自然对齐要求**：LR.W/SC.W/AMO 地址必须 4 字节对齐（addr[1:0]==00），否则产生地址对齐异常
3. **内存排序（aq/rl）**：单 hart 顺序执行 CPU 中，aq/rl 语义天然满足（无乱序执行、无推测），可简化实现
4. **SC 失败码**：规范要求非零，推荐返回 1（可用 SLT 多路复用器实现）
5. **AMO 原子性**：单 hart + FSM 持有流水线 = 天然原子，无需额外锁机制

### 0.3 与现有架构的兼容性

- **多周期 FSM**：AMO/LR/SC 在 MEM 级内部扩展 FSM 即可，无需新增控制器顶层状态
- **dcache 集成**：AMO 通过 dcache 现有读/写接口完成（read → compute → write），dcache 无需修改
- **MMIO 路径**：AMO 对 MMIO 地址通过 AXI 总线单拍读+写完成，流水线持有保证原子性
- **M/F 扩展模式**：AMO 不在 EXE 级执行运算（与 MU/FPU 不同），而是在 MEM 级完成读-改-写

---

## 1. 总体架构设计

### 1.1 数据通路新增信号流

```
cpu_decode                    cpu_execute                   cpu_mem
┌──────────┐                 ┌──────────┐                 ┌──────────────────────┐
│ OPCODE_AMO│                 │ pass-thru │                 │ AMO FSM:             │
│ is_lr/is_sc│──id_exe_bus──>│ is_amo    │──exe_mem_bus──>│  MEM_AMO_READ        │
│ is_amo    │                │ amo_funct5│                 │  → compute           │
│ amo_funct5│                │ amo_aq/rl │                 │  → MEM_AMO_WRITE     │
│ amo_aq/rl │                │           │                 │ Reservation Set:     │
│           │                 │           │                 │  lr_addr + lr_valid  │
└──────────┘                 └──────────┘                 └──────────────────────┘
```

### 1.2 MEM 级 AMO FSM 状态扩展

现有 MEM FSM：`MEM_IDLE(0) → MEM_READ(1) → MEM_WRITE(2)`

扩展为：`MEM_IDLE(0) → MEM_READ(1) → MEM_WRITE(2) → MEM_AMO_READ(3) → MEM_AMO_WRITE(4)`

```
MEM_IDLE:
  ├── 普通 Load → MEM_READ
  ├── 普通 Store → MEM_WRITE
  ├── LR.W → MEM_AMO_READ (读 + 设保留)
  ├── SC.W → MEM_AMO_READ (读检查 → 条件写)
  └── AMO → MEM_AMO_READ (读 → 计算 → 写回)

MEM_AMO_READ: (等待 data_valid)
  ├── LR.W 完成 → 设保留, wb_data=读出值, done
  ├── SC.W → 检查保留:
  │     ├── 匹配 → MEM_AMO_WRITE (写 rs2, rd=0)
  │     └── 不匹配 → rd=1, done (不写内存)
  └── AMO → 计算 amo_result → MEM_AMO_WRITE (写 amo_result)

MEM_AMO_WRITE: (等待 data_valid)
  ├── SC.W 完成 → rd=0, done
  └── AMO 完成 → wb_data=原始读出值(AMO 返回旧值), done
```

### 1.3 保留集（Reservation Set）设计

```systemverilog
// 在 cpu_mem 内部实现
reg [31:0] lr_reservation_addr;  // LR 保留地址
reg        lr_reservation_valid; // 保留有效位

// LR.W 完成时:
lr_reservation_addr  <= alu_result;  // 锁存地址
lr_reservation_valid <= 1'b1;

// SC.W 执行时:
// 匹配条件: lr_reservation_valid && (lr_reservation_addr == alu_result)

// 失效条件（任一发生即清除 lr_reservation_valid）:
// 1. SC.W 执行后（无论成功失败）
// 2. 任何普通 Store 执行后
// 3. 陷阱进入时（trap_enter 信号）
// 4. 上下文切换时
```

### 1.4 AMO 计算逻辑

```systemverilog
// 组合逻辑，在 MEM_AMO_READ 完成后计算
wire [31:0] amo_computed_result;
assign amo_computed_result = 
    (amo_funct5 == 5'b00001) ? rs2_value :                    // AMOSWAP
    (amo_funct5 == 5'b00000) ? (loaded_value + rs2_value) :   // AMOADD
    (amo_funct5 == 5'b01100) ? (loaded_value & rs2_value) :   // AMOAND
    (amo_funct5 == 5'b01000) ? (loaded_value | rs2_value) :   // AMOOR
    (amo_funct5 == 5'b00100) ? (loaded_value ^ rs2_value) :   // AMOXOR
    (amo_funct5 == 5'b11000) ? ($signed(loaded_value) < $signed(rs2_value) ? loaded_value : rs2_value) :  // AMOMIN
    (amo_funct5 == 5'b10100) ? ($signed(loaded_value) > $signed(rs2_value) ? loaded_value : rs2_value) :  // AMOMAX
    (amo_funct5 == 5'b11100) ? (loaded_value < rs2_value ? loaded_value : rs2_value) :                    // AMOMINU
    (amo_funct5 == 5'b11110) ? (loaded_value > rs2_value ? loaded_value : rs2_value) :                    // AMOMAXU
    loaded_value;  // 默认（不应到达）
```

---

## 2. 文件修改清单（按执行顺序）

### Phase 1: 流水线总线扩展

#### 2.1.1 `src/rtl/core/core_bus_types.svh`

**修改内容**：扩展 `exe_mem_bus_t` 和 `wb_bus_t` 结构体

**exe_mem_bus_t 新增字段**：

| 字段 | 位宽 | 说明 |
|------|------|------|
| `is_amo` | 1 | 当前指令为 AMO 指令（含 LR/SC） |
| `is_lr` | 1 | 当前指令为 LR.W |
| `is_sc` | 1 | 当前指令为 SC.W |
| `amo_funct5` | 5 | AMO 操作码（funct7[6:2]） |
| `amo_aq` | 1 | acquire 排序位 |
| `amo_rl` | 1 | release 排序位 |

新增位宽：1+1+1+5+1+1 = 10 bit
新 exe_mem_bus_t 总宽：216 + 10 = **226 bit**

**wb_bus_t 新增字段**：

| 字段 | 位宽 | 说明 |
|------|------|------|
| `is_amo` | 1 | 用于 WB 级判断 |
| `is_lr` | 1 | 用于 WB 级判断 |
| `is_sc` | 1 | 用于 WB 级判断 |

新增位宽：3 bit
新 wb_bus_t 总宽：177 + 3 = **180 bit**

#### 2.1.2 `src/rtl/core/cpu_decode.sv` — id_exe_bus 扩展

**新增 opcode 常量**：
```systemverilog
localparam OPCODE_AMO = 7'b0101111;
```

**新增指令匹配 wire**：
```systemverilog
// A extension instruction matches
wire funct5 = inst[31:27];
wire amo_aq = inst[26];
wire amo_rl = inst[25];

wire inst_lr_w     = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00010) && (rs2 == 5'd0);
wire inst_sc_w     = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00011);
wire inst_amoswap  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00001);
wire inst_amoadd   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00000);
wire inst_amoand   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b01100);
wire inst_amoor    = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b01000);
wire inst_amoxor   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b00100);
wire inst_amomin   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b11000);
wire inst_amomax   = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b10100);
wire inst_amominu  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b11100);
wire inst_amomaxu  = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (funct5 == 5'b11110);
```

**新增分类信号**：
```systemverilog
wire is_amo_all = inst_amoswap | inst_amoadd | inst_amoand | inst_amoor |
                  inst_amoxor | inst_amomin | inst_amomax | inst_amominu | inst_amomaxu;
wire is_lr = inst_lr_w;
wire is_sc = inst_sc_w;
wire is_amo = is_amo_all | is_lr | is_sc;  // 所有 A 扩展指令

wire [4:0] amo_funct5_dec = inst[31:27];  // 直接从指令位提取
```

**修改 valid_inst**：
```systemverilog
assign valid_inst = is_branch | is_load | is_store | is_jal_like | is_alu | is_mu |
                    is_csr | is_system_trap | is_mret | is_sret | is_nop_like | is_fencei | is_sfence_vma |
                    is_fpu | is_flw | is_fsw |
                    is_amo;  // 新增
```

**修改 wb_we**：
```systemverilog
assign wb_we = valid_inst && (is_alu | is_jal_like | is_csr | is_mu | is_fpu | is_flw | is_amo);
// LR.W/SC.W/AMO 均写回 rd
```

**修改 alu_src2**：AMO/LR/SC 地址 = rs1，无需立即数偏移
```systemverilog
// 在 alu_src2 赋值中添加 is_amo 分支：
assign alu_src2 = ... | is_amo ? 32'b0 : ...;
// AMO 的 ALU 操作就是 ADD(src1=rs1, src2=0)，结果即为地址
```

**修改 alu_control**：AMO 使用 ADD 计算地址
```systemverilog
// 在 alu_control 赋值中添加 is_amo：
(is_amo) ? 16'b0001_0000_0000_0000 :  // ADD
```

**修改 mem_size**：AMO 固定为 word
```systemverilog
// mem_size 已默认为 3'b010 (word)，AMO 不需要额外修改
```

**修改 dec_need_exe**：AMO 需要执行级（计算地址）
```systemverilog
// dec_need_exe 已包含 valid_inst && !is_nop_like && !is_fencei && !is_sfence_vma && !is_system_trap && !is_mret && !is_sret && !is_csr
// is_amo 为 valid_inst 的一部分，且不在排除列表中，所以 AMO 自然需要执行级
```

**扩展 id_exe_bus**：在末尾追加新字段
```systemverilog
assign id_exe_bus = {
    pc_plus4,
    valid_inst,
    is_alu,
    is_load,
    is_store,
    is_jal_like,
    is_branch,
    use_fixed_wb,
    wb_we,
    rd,
    wb_fixed_data,
    mem_size,
    mem_unsigned,
    alu_control,
    is_mu,
    mu_funct3,
    alu_src1,
    alu_src2,
    rs1_value,
    rs2_value,
    branch_funct3,
    is_csr,
    is_ecall,
    is_ebreak,
    is_mret,
    csr_addr,
    csr_funct3,
    csr_uimm,
    pc,
    inst,
    is_fpu,
    is_flw,
    is_fsw,
    fpu_funct,
    fpu_rm,
    fpu_rd_is_int,
    // --- A extension 新增 ---
    is_amo,         // 1 bit
    is_lr,          // 1 bit
    is_sc,          // 1 bit
    amo_funct5_dec, // 5 bits
    amo_aq,         // 1 bit
    amo_rl          // 1 bit
};
```

新 id_exe_bus 总宽：334 + 10 = **344 bit**

---

### Phase 2: 执行级传递

#### 2.2.1 `src/rtl/core/cpu_execute.sv`

**修改内容**：

1. **解包新增字段**：从 `id_exe_bus_r` 解包 `is_amo`, `is_lr`, `is_sc`, `amo_funct5`, `amo_aq`, `amo_rl`

2. **修改 exe_need_mem**：
```systemverilog
assign exe_need_mem = is_load | is_store | is_flw | is_fsw | is_amo;
// AMO/LR/SC 需要访存级
```

3. **打包 exe_mem_bus**：追加新字段
```systemverilog
assign exe_mem_bus = '{
    pc_plus4:      pc_plus4,
    result_ok:     result_ok,
    is_jal_like:   is_jal_like,
    is_load:       is_load,
    is_store:      is_store,
    is_csr:        is_csr,
    wb_we:         wb_we,
    wb_rd:         wb_rd,
    result_reg:    result_reg,
    mem_size:      mem_size,
    mem_unsigned:  mem_unsigned,
    rs2_value:     rs2_value,
    csr_rdata:     csr_rdata,
    pc:            pc,
    inst:          inst,
    is_fpu:        is_fpu,
    is_flw:        is_flw,
    is_fsw:        is_fsw,
    fpu_rd_is_int: fpu_rd_is_int,
    fpu_fflags:    fpu_fflags,
    // --- A extension 新增 ---
    is_amo:        is_amo,
    is_lr:         is_lr,
    is_sc:         is_sc,
    amo_funct5:    amo_funct5,
    amo_aq:        amo_aq,
    amo_rl:        amo_rl
};
```

4. **注意**：AMO/LR/SC 在执行级仅计算地址（ALU ADD: rs1 + 0），不执行 AMO 运算。AMO 运算在 MEM 级完成。这与 MU/FPU 在 EXE 级完成运算的模式不同。

---

### Phase 3: 访存级核心实现

#### 2.3.1 `src/rtl/core/cpu_mem.sv` — 主要修改

这是 A 扩展实现的核心文件，修改量最大。

**新增输入端口**：
```systemverilog
input  trap_enter,       // 陷阱进入时使保留失效
```

**新增内部信号**：
```systemverilog
// 从 exe_mem_bus_r 解包
wire is_amo, is_lr, is_sc;
wire [4:0] amo_funct5;
wire amo_aq, amo_rl;

// 保留集
reg [31:0] lr_reservation_addr;
reg        lr_reservation_valid;

// AMO 计算结果
reg [31:0] amo_loaded_value;    // 从内存读出的原始值
reg [31:0] amo_computed_result; // AMO 运算结果（写回内存的值）
reg [4:0]  amo_funct5_reg;      // 锁存的 AMO 操作码
reg [31:0] amo_rs2_reg;         // 锁存的 rs2 值（SC/AMO 用）
reg        is_lr_reg;           // 锁存的 LR 标志
reg        is_sc_reg;           // 锁存的 SC 标志
reg        is_amo_op_reg;       // 锁存的 AMO 操作标志（非 LR/SC 的 AMO）
```

**扩展 FSM 状态**：
```systemverilog
localparam MEM_IDLE      = 3'd0;  // 扩展为 3-bit
localparam MEM_READ      = 3'd1;
localparam MEM_WRITE     = 3'd2;
localparam MEM_AMO_READ  = 3'd3;  // 新增：AMO/LR/SC 读阶段
localparam MEM_AMO_WRITE = 3'd4;  // 新增：AMO/SC 写阶段
```

**AMO 计算组合逻辑**：
```systemverilog
wire [31:0] amo_calc_result;
assign amo_calc_result = 
    (amo_funct5_reg == 5'b00001) ? amo_rs2_reg :                                              // AMOSWAP
    (amo_funct5_reg == 5'b00000) ? (amo_loaded_value + amo_rs2_reg) :                         // AMOADD
    (amo_funct5_reg == 5'b01100) ? (amo_loaded_value & amo_rs2_reg) :                         // AMOAND
    (amo_funct5_reg == 5'b01000) ? (amo_loaded_value | amo_rs2_reg) :                         // AMOOR
    (amo_funct5_reg == 5'b00100) ? (amo_loaded_value ^ amo_rs2_reg) :                         // AMOXOR
    (amo_funct5_reg == 5'b11000) ? ($signed(amo_loaded_value) < $signed(amo_rs2_reg) ? amo_loaded_value : amo_rs2_reg) :   // AMOMIN
    (amo_funct5_reg == 5'b10100) ? ($signed(amo_loaded_value) > $signed(amo_rs2_reg) ? amo_loaded_value : amo_rs2_reg) :   // AMOMAX
    (amo_funct5_reg == 5'b11100) ? (amo_loaded_value < amo_rs2_reg ? amo_loaded_value : amo_rs2_reg) :                      // AMOMINU
    (amo_funct5_reg == 5'b11110) ? (amo_loaded_value > amo_rs2_reg ? amo_loaded_value : amo_rs2_reg) :                      // AMOMAXU
    amo_loaded_value;
```

**SC 保留匹配检查**：
```systemverilog
wire sc_reservation_match = lr_reservation_valid && (lr_reservation_addr == alu_result);
```

**对齐异常检测**（AMO/LR/SC 要求 word 对齐）：
```systemverilog
wire amo_misalign = is_amo && (alu_result[1:0] != 2'b00);
```

**FSM 状态转换逻辑**（伪代码，详细实现见实际代码）：

```
MEM_IDLE:
  if mem_valid:
    if is_amo:
      if amo_misalign:
        → 触发对齐异常, done
      else:
        → 锁存 amo_funct5, rs2, is_lr, is_sc, is_amo_op
        → 发读请求 (hwrite=0, hsize=WORD)
        → MEM_AMO_READ
    else:
      → 原有 Load/Store 逻辑不变

MEM_AMO_READ: (等待 data_valid)
  if data_valid:
    amo_loaded_value <= readData_32
    if is_lr_reg:
      → 设保留: lr_reservation_addr <= addr, lr_reservation_valid <= 1
      → wb_data = readData_32 (LR 返回读出值)
      → done
    else if is_sc_reg:
      → 清保留: lr_reservation_valid <= 0
      if sc_reservation_match:
        → 发写请求 (hwrite=1, hsize=WORD, wdata=amo_rs2_reg)
        → MEM_AMO_WRITE
      else:
        → wb_data = 1 (SC 失败)
        → wb_we = 1 (仍写 rd)
        → done (不写内存)
    else: // AMO 操作
      → 计算 amo_computed_result = amo_calc_result
      → 发写请求 (hwrite=1, hsize=WORD, wdata=amo_computed_result)
      → MEM_AMO_WRITE

MEM_AMO_WRITE: (等待 data_valid)
  if data_valid:
    if is_sc_reg:
      → wb_data = 0 (SC 成功)
    else: // AMO
      → wb_data = amo_loaded_value (AMO 返回原始读出值)
    → wb_we = 1
    → done
```

**保留失效逻辑**：
```systemverilog
// 任何普通 Store 完成时，使保留失效
if (mem_state == MEM_WRITE && data_valid && !is_amo) begin
    lr_reservation_valid <= 1'b0;
end

// 陷阱进入时，使保留失效
if (trap_enter) begin
    lr_reservation_valid <= 1'b0;
end
```

**修改 mem_data_access**：
```systemverilog
assign mem_data_access = is_load || is_store || is_flw || is_fsw || is_amo;
```

**修改 misalign 检测**：
```systemverilog
assign mem_misalign_load  = (is_load | is_flw | is_lr)  && misalign_addr;
assign mem_misalign_store = (is_store | is_fsw | is_sc | (is_amo & ~is_lr)) && misalign_addr;
// 注意：AMO 的对齐异常类型为 Store/AMO misalign (exception code 6)
```

**打包 mem_wb_bus**：追加 A 扩展字段
```systemverilog
assign mem_wb_bus = '{
    ...
    is_amo:        is_amo,
    is_lr:         is_lr,
    is_sc:         is_sc
};
```

---

### Phase 4: 回写级

#### 2.4.1 `src/rtl/core/cpu_wb.sv`

**修改内容**：

1. 从 `mem_wb_bus_r` 解包 `is_amo`, `is_lr`, `is_sc`
2. AMO/LR/SC 写回整数寄存器（与普通 Load 类似）
3. 不需要特殊处理 — `wb_we` 已在译码级设置，`wb_data` 在 MEM 级已正确设置

---

### Phase 5: 核心顶层连线

#### 2.5.1 `src/rtl/core/core_top.sv`

**修改内容**：

1. **更新 id_exe_bus 位宽**：334 → 344
2. **更新 exe_mem_bus_r 位宽**：216 → 226（或使用 struct 自动推导）
3. **更新 mem_wb_bus_r 位宽**：177 → 180
4. **连接 trap_enter 信号到 cpu_mem**：从 trap_manager 或 controller 获取
5. **更新流水线寄存器位宽声明**

---

### Phase 6: CSR misa 更新

#### 2.6.1 `src/rtl/core/cpu_csr.sv`

**修改内容**：

更新 `misa` 硬连线值，设置 A 扩展位（bit 0）：

```
当前: 0x40141120 (RV32IMFSU)
      bit 0 (A)  = 0
      bit 8 (I)  = 1
      bit 12 (M) = 1
      bit 5 (F)  = 1
      bit 18 (S) = 1
      bit 20 (U) = 1

修改后: 0x40141121 (RV32AIMFSU)
        bit 0 (A)  = 1  ← 新增
```

---

### Phase 7: 控制器（无需修改）

#### 2.7.1 `src/rtl/core/cpu_controller.sv`

**无需修改**。原因：
- AMO/LR/SC 走正常的 EXEC → MEM → WB 流程
- MEM 级内部 FSM 处理 AMO 的多周期操作
- 控制器只需等待 `mem_done`，无需新增顶层状态
- `exe_need_mem` 已包含 `is_amo`，控制器自然进入 STATE_MEM

---

### Phase 8: DCache（无需修改）

#### 2.8.1 `src/rtl/core/dcache_ctrl.sv`

**无需修改**。原因：
- AMO 通过 dcache 现有读/写接口完成
- MEM 级依次发读请求 → 写请求，dcache 视为两次独立操作
- 单 hart + 流水线持有 = 天然原子性
- MMIO 路径同样适用（AXI 单拍读 + 单拍写）

---

### Phase 9: 总线桥接（无需修改）

#### 2.9.1 `src/rtl/core/cpu_bus_bridge.sv`

**无需修改**。AMO 的读/写请求与普通 Load/Store 使用相同的 AXI4 协议。

---

### Phase 10: 内存排序（aq/rl）实现

**设计决策**：在单 hart 顺序执行 CPU 中，aq/rl 语义天然满足。

- **aq（acquire）**：后续内存操作不得重排到此操作之前 → 顺序执行天然保证
- **rl（release）**：此前内存操作不得重排到此操作之后 → 顺序执行天然保证
- **aq+rl（seq_cst）**：完全顺序一致 → 顺序执行天然保证

**实现方式**：aq/rl 位在译码级提取并传递到 MEM 级，但在当前单 hart 实现中不产生任何额外操作。未来若实现多核或乱序执行，需在此处插入 FENCE 操作。

**注意**：规范建议软件不应在 LR 上设 rl（除非同时设 aq），不应在 SC 上设 aq（除非同时设 rl）。我们的实现接受任何 aq/rl 组合，不做额外检查。

---

### Phase 11: 陷阱与异常处理

#### 2.11.1 `src/rtl/core/cpu_trap_manager.sv`

**修改内容**：

1. **Store/AMO 访问错误异常**：AMO 指令的访问错误应使用 Exception Code = 7（Store/AMO access fault），而非 5（Load access fault）
2. **Store/AMO 页错误**：Exception Code = 15（Store/AMO page fault），已在设计报告中列出
3. **AMO 对齐异常**：Exception Code = 6（Store/AMO misaligned address），与 Store 对齐异常相同

**注意**：LR.W 的对齐异常使用 Exception Code = 4（Load misaligned）还是 6（Store/AMO misaligned）？根据 RISC-V 规范，LR.W 是 Load 类操作，对齐异常使用 code=4；SC.W 和 AMO 使用 code=6。

#### 2.11.2 保留集与陷阱交互

- **陷阱进入**：使保留失效（`lr_reservation_valid <= 0`）
- **MRET/SRET**：不恢复保留（保留在陷阱进入时已失效）
- **上下文切换**：OS 应在切换前执行 SC 到临时地址强制使保留失效

---

### Phase 12: 测试程序

#### 2.12.1 ISA 测试程序

**新建**：`src/program_source/test/isa/a_ext.S`

测试用例：

| 测试项 | 指令 | 验证内容 |
|--------|------|----------|
| LR.W 基本功能 | LR.W + 读取 rd | 读出值 = 内存值，保留有效 |
| SC.W 成功 | LR.W → SC.W（无干扰） | rd = 0，内存已更新 |
| SC.W 失败（无 LR） | SC.W（无前置 LR） | rd = 1，内存未更新 |
| SC.W 失败（地址不匹配） | LR.W addr1 → SC.W addr2 | rd = 1 |
| SC.W 失败（Store 干扰） | LR.W → SW 同地址 → SC.W | rd = 1 |
| AMOSWAP.W | AMOSWAP.W | rd = 旧值，内存 = rs2 |
| AMOADD.W | AMOADD.W | rd = 旧值，内存 = 旧值+rs2 |
| AMOAND.W | AMOAND.W | rd = 旧值，内存 = 旧值&rs2 |
| AMOOR.W | AMOOR.W | rd = 旧值，内存 = 旧值\|rs2 |
| AMOXOR.W | AMOXOR.W | rd = 旧值，内存 = 旧值^rs2 |
| AMOMIN.W | AMOMIN.W | 有符号最小值 |
| AMOMAX.W | AMOMAX.W | 有符号最大值 |
| AMOMINU.W | AMOMINU.W | 无符号最小值 |
| AMOMAXU.W | AMOMAXU.W | 无符号最大值 |
| 对齐异常 | LR.W 未对齐地址 | 触发异常（code=4/6） |
| aq/rl 位 | LR.W.aq / SC.W.rl | 功能正确（排序为 no-op） |
| 互斥锁惯用法 | LR/SC 自旋锁 | 成功获取/释放锁 |

#### 2.12.2 Testbench

**新建**：`src/tb/tb_isa_a_ext.sv`

基于 `tb_isa_template.sv` 模板，使用自检程序（x28=pass, x30=first_fail_id）。

---

## 3. 实现步骤与依赖关系

```
Phase 1: 总线扩展 (core_bus_types.svh)
    ↓
Phase 2: 译码级 (cpu_decode.sv)
    ↓
Phase 3: 执行级 (cpu_execute.sv)
    ↓
Phase 4: 访存级 (cpu_mem.sv) ← 核心实现
    ↓
Phase 5: 回写级 (cpu_wb.sv)
    ↓
Phase 6: 核心连线 (core_top.sv)
    ↓
Phase 7: CSR 更新 (cpu_csr.sv)
    ↓
Phase 8: 陷阱处理 (cpu_trap_manager.sv) ← 可能需要微调
    ↓
Phase 9: 测试程序 + Testbench
    ↓
Phase 10: 仿真验证
```

**关键路径**：Phase 1→2→3→4→5→6 必须顺序执行（总线位宽变更影响所有级）

**可并行**：Phase 7（CSR）和 Phase 8（陷阱）可与 Phase 9（测试）并行

---

## 4. 风险与注意事项

### 4.1 总线位宽变更风险

**风险**：id_exe_bus 从 334→344 bit，exe_mem_bus 从 216→226 bit，mem_wb_bus 从 177→180 bit。所有使用这些总线的模块都需要同步更新。

**缓解**：
- 使用 `core_bus_types.svh` struct 定义，编译器自动检查位宽
- 一次性修改所有总线相关代码
- 修改后立即运行现有测试回归

### 4.2 MEM 级 FSM 扩展风险

**风险**：新增 MEM_AMO_READ/MEM_AMO_WRITE 状态可能影响现有 Load/Store 逻辑。

**缓解**：
- 新状态与现有状态互斥（仅 is_amo 时进入）
- 现有 MEM_READ/MEM_WRITE 逻辑完全不变
- 保留集寄存器仅在 AMO 路径中修改

### 4.3 保留集正确性

**风险**：保留集失效条件不完整可能导致 SC 虚假成功。

**缓解**：
- 严格实现规范要求的失效条件：SC 执行后、Store 执行后、陷阱进入后
- 单 hart 系统中，外部 hart 干扰不存在，简化了保留管理
- 测试用例覆盖所有失效场景

### 4.4 AMO 与 MMIO 交互

**风险**：AMO 对 MMIO 设备寄存器可能产生意外行为（两次 AXI 事务：读+写）。

**缓解**：
- 规范允许 AMO 访问 I/O 空间
- 某些设备可能不支持原子操作（如 UART），但这是软件责任
- 硬件层面保证读-改-写序列不被打断

### 4.5 aq/rl 排序简化

**风险**：当前实现将 aq/rl 视为 no-op，未来多核扩展时需重新实现。

**缓解**：
- 在代码中添加明确注释标记简化点
- aq/rl 信号在总线上传递，未来可在此处插入 FENCE 逻辑
- 单 hart 系统中此简化完全正确

---

## 5. 验证计划

### 5.1 单元验证

| 阶段 | 测试内容 | 方法 |
|------|----------|------|
| 译码级 | 11 条 A 扩展指令正确识别 | 仿真检查 id_exe_bus 信号 |
| 执行级 | AMO 地址计算正确（rs1+0） | 仿真检查 result_reg |
| 访存级 | LR/SC/AMO FSM 状态转换 | 波形检查 |
| 访存级 | 保留集设/查/清 | 仿真检查 lr_reservation_* |
| 访存级 | AMO 计算逻辑（9 种操作） | 定向测试 |
| CSR | misa 包含 A 位 | 寄存器读取 |

### 5.2 集成验证

| 测试 | 程序 | 预期 |
|------|------|------|
| A 扩展 ISA 测试 | a_ext.S | 全部 PASS |
| 回归测试 | 现有全部测试 | 无 FAIL（确保无破坏） |
| 互斥锁应用 | 自旋锁小程序 | 正确获取/释放 |

### 5.3 回归测试

修改完成后，运行以下现有测试确保无破坏：
- `tb_isa_alu`, `tb_isa_branch`, `tb_isa_jump`, `tb_isa_memory`, `tb_isa_upper_imm`
- `tb_isa_m_ext`, `tb_isa_csr`, `tb_isa_f_ext`
- `tb_simple_cpu_top`, `tb_simple_cpu_compute`, `tb_simple_cpu_trap`
- 所有异常/缓存/MMU/特权测试

---

## 6. 工作量估算

| 阶段 | 文件 | 估计工作量 | 复杂度 |
|------|------|-----------|--------|
| Phase 1 | core_bus_types.svh | 小 | 低 — 仅添加 struct 字段 |
| Phase 2 | cpu_decode.sv | 中 | 中 — 新增 11 条指令识别 + 总线扩展 |
| Phase 3 | cpu_execute.sv | 小 | 低 — 透传信号 + exe_need_mem 修改 |
| Phase 4 | cpu_mem.sv | **大** | **高** — FSM 扩展 + 保留集 + AMO 计算 |
| Phase 5 | cpu_wb.sv | 小 | 低 — 解包新字段 |
| Phase 6 | core_top.sv | 中 | 中 — 总线位宽更新 + 信号连线 |
| Phase 7 | cpu_csr.sv | 小 | 低 — misa 硬连线值修改 |
| Phase 8 | cpu_trap_manager.sv | 小 | 低 — AMO 异常码调整 |
| Phase 9 | a_ext.S + tb | 中 | 中 — 测试程序编写 |
| Phase 10 | 仿真验证 | 中 | 中 — 回归测试 |

**总计**：约 2-3 天工作量（含调试）

**核心难点**：Phase 4（cpu_mem.sv 的 AMO FSM + 保留集 + AMO 计算逻辑）

---

## 7. 设计报告更新

实现完成后，更新 `dev/docs/simpleCPU-design-report.md`：

1. §1.1 核心特性：指令集 RV32IMF → RV32IMAF
2. §1.2 支持的指令集：新增 A 扩展指令表
3. §3.3 译码级：更新 ID/EX 总线位宽和字段
4. §3.5 访存级：新增 AMO FSM 描述和保留集设计
5. §4.1 异常检测：新增 AMO 对齐异常说明
6. §4.2 CSR：更新 misa 值
7. §7 模块间总线：更新总线位宽
8. §9.1 文件清单：新增测试文件
9. §10 设计特点：新增 A 扩展相关特点

---

## 8. 计划验证与更新（near-linux-bug-fix 后）

> 检查日期: 2026-06-14 | 基于 near-linux-bug-fix.md（Bug 1-6）的 RTL 变更

### 8.1 Bug Fix 变更与 A 扩展计划交集分析

| Bug Fix | 变更文件 | 影响 A 扩展？ | 说明 |
|---------|----------|:---:|------|
| Bug 1: is_mmio 改用物理地址 | icache_ctrl.sv, dcache_ctrl.sv | ❌ | dcache 读/写接口未变，AMO 仍通过现有接口 |
| Bug 2: sip[5]/M/S 中断优先级 | cpu_csr.sv, cpu_clint.sv | ❌ | 不涉及流水线数据通路或总线 |
| Bug 3: STATE_SFENCE_VMA | cpu_controller.sv, MMU.sv, core_top.sv | ❌ | 新状态与 AMO 路径无交集；AMO 走 EXEC→MEM→WB |
| Bug 4: time/timeh/U-mode 计数器 | cpu_csr.sv, cpu_decode.sv, core_top.sv, axi4lite_clint.sv 等 | ❌ | 不涉及流水线总线结构 |
| Bug 5: PMP CSR | cpu_csr.sv, cpu_decode.sv, core_top.sv 等 | ❌ | 不涉及流水线总线结构 |
| Bug 6: PTW A/D dcache invalidation | dcache_ctrl.sv, core_top.sv | ❌ | inv_line 接口用于 PTW 一致性，AMO 不需要 |

### 8.2 需要注意的 3 处更新

#### 8.2.1 core_top.sv 复杂度增加

Bug 3/4/5/6 使 core_top.sv 新增了：
- sfence.vma 三阶段序列化逻辑（dcache flush → icache inv → TLB flush）
- mtime 跨时钟域同步（两级 FF 同步器）
- PMP 输出端口连线
- PTW A/D 写完成 → dcache inv_line 触发逻辑

**影响**：修改总线位宽时（Phase 6）需更谨慎，避免破坏新增逻辑。具体注意：
- `id_exe_bus_r <= 334'b0` 需更新为 `344'b0`
- `exe_mem_bus_r <= 216'b0` 需更新为 `226'b0`（或使用 `'0` 自动填充）
- `mem_wb_bus_r <= 177'b0` 需更新为 `180'b0`（或使用 `'0` 自动填充）
- sfence/mtime/PMP/inv_line 相关逻辑不涉及总线位宽，不受影响

**建议**：使用 struct 类型赋值 `'0` 代替硬编码位宽常量，避免未来遗漏。

#### 8.2.2 trap_enter 信号已存在

计划中 cpu_mem 新增 `trap_enter` 输入用于使 LR 保留失效。

**现状**：core_top 中已有 `trap_enter_valid` 信号（来自 cpu_controller），可直接连接：
```systemverilog
// core_top.sv 中连接
.trap_enter(trap_enter_valid)  // 连接到 cpu_mem 新增端口
```

**更新**：计划 §2.3.1 中 `trap_enter` 输入端口描述已正确，连接方式确认可行。

#### 8.2.3 misa 值确认

**当前值**：`32'h40141120`（cpu_csr.sv 第 630 行）
**计划修改**：`32'h40141121`（置 bit 0 = A 扩展）
**确认**：正确无误。A 扩展对应 misa bit 0。

### 8.3 无需修改的确认项

| 计划章节 | 确认内容 |
|----------|----------|
| §2.7 控制器 | STATE_SFENCE_VMA 新增不影响 AMO 路径，控制器仍无需修改 |
| §2.8 DCache | dcache 新增 inv_line 接口不影响 AMO，dcache 仍无需修改 |
| §2.9 总线桥接 | cpu_bus_bridge 未被 bug fix 修改，仍无需修改 |
| §1.2 总线位宽 | id_exe_bus 334→344, exe_mem_bus 216→226, mem_wb_bus 177→180 计算仍正确 |
| §2.1.1 core_bus_types.svh | struct 定义未被 bug fix 修改，扩展方案仍正确 |
| §2.2.1 cpu_decode.sv | 新增 U-mode/PMP CSR 逻辑与 A 扩展 opcode(0101111) 无交集 |

### 8.4 结论

**A 扩展实现计划无需结构性修改。** near-linux-bug-fix 的 6 个 bug 修复均不涉及流水线总线结构或 AMO 相关的数据通路，计划中所有文件修改清单、总线位宽计算、FSM 扩展方案、保留集设计均保持有效。

唯一需在实现时注意的点是 core_top.sv 的总线位宽更新需避免破坏 bug fix 新增的 sfence/mtime/PMP/inv_line 逻辑（建议使用 `'0` 赋值代替硬编码位宽）。
