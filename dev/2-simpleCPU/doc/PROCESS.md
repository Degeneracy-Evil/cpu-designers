# PROCESS — BRAM IP 核读延迟适配

## 背景

simpleCPU 原始设计使用行为级 icache/dcache 模型（组合读，零延迟）。切换到 Vivado BRAM IP 核（blk_mem_gen, True Dual Port RAM）后，BRAM 具有 1 周期同步读延迟：地址在时钟沿 N 被锁存，数据在沿 N 之后才有效。这导致 `mem_data` 和 `if_inst` 出现 X 值。

## 根因分析

| 模块 | 原始行为 | BRAM 行为 | 问题 |
|------|---------|----------|------|
| cpu_fetch | `if_done = if_valid`，同周期完成取指 | icache_en/addr 组合逻辑驱动，BRAM 在下一沿才输出数据 | if_id_bus_r 捕获到旧数据 |
| cpu_mem MEM_READ | 在 MEM_READ 状态直接采样 dcache_rdata | dcache_en/addr 为寄存器输出，BRAM 还需 1 沿迟才输出 | 采样到旧数据 |
| cpu_mem MEM_WRITE_MODIFY | 同上，读旧值后拼接写入 | 同上 | 读修改写读到旧值 |
| tb check_mem_word | `mem_addr = addr; #1;` 读取 | dcache 端口 B 也有 1 周期延迟 | 读到 0 或旧值 |

## 修改内容

### 1. cpu_fetch.v — 增加 r_bram_sent 等待标志

取指阶段 icache_en/icache_addr 为组合逻辑输出（直接由 if_valid 和 pc 驱动），BRAM 在下一个时钟沿才锁存地址、再下一个沿输出数据。因此取指需要 2 个周期（发地址 + 等数据）。

**改动：**

- 新增 `clk`、`reset` 输入端口（原模块无时钟）
- 新增 `r_bram_sent` 寄存器：当 `if_valid` 有效时置 1，无效时清 0
- `if_done` 从 `if_valid` 改为 `if_valid && r_bram_sent`

**时序：**

```
沿 E:   state_r 进入 FETCH, if_valid=1, icache_en=1, icache_addr 有效
沿 E+1: BRAM 锁存地址, r_bram_sent=1, if_done=1
沿 E+2: if_id_bus_r 捕获 icache_dout（此时数据已有效）
```

### 2. cpu_mem.v — 增加 MEM_READ2 / MEM_WRITE_MODIFY2 等待状态

dcache_en/dcache_addr 为寄存器输出（en_reg/daddr_reg），在 MEM_IDLE 设置后下一沿才有效。BRAM 再需一沿输出数据。因此读操作需要额外 1 个等待周期。

**改动：**

- 状态编码从 2 位扩展为 3 位
- 新增状态：`MEM_READ2 = 3'd2`、`MEM_WRITE_MODIFY2 = 3'd4`
- 状态转移变更：

```
MEM_READ        → MEM_READ2（等待 BRAM 输出）
MEM_READ2       → MEM_IDLE（采样 dcache_rdata，完成）
MEM_WRITE_MODIFY  → MEM_WRITE_MODIFY2（等待 BRAM 输出）
MEM_WRITE_MODIFY2 → MEM_WRITE_COMMIT（采样 dcache_rdata，发起写）
```

- `mem_word_for_extract` 多路选择器从 `MEM_READ || MEM_WRITE_MODIFY` 改为 `MEM_READ2 || MEM_WRITE_MODIFY2`
- `wdata_reg <= store_merged_word` 条件从 `MEM_WRITE_MODIFY` 改为 `MEM_WRITE_MODIFY2`

**时序（读路径）：**

```
沿 A:   MEM_IDLE 设置 en_reg=1, daddr_reg=addr, 进入 MEM_READ
沿 A+1: dcache_en=1, dcache_addr 有效, BRAM 锁存地址, 进入 MEM_READ2
沿 A+2: BRAM 输出有效, 采样 dcache_rdata, done=1
```

**时序（写路径）：**

```
沿 A:   MEM_IDLE 设置 en_reg=1, daddr_reg=addr, 进入 MEM_WRITE_MODIFY
沿 A+1: BRAM 锁存地址, 进入 MEM_WRITE_MODIFY2
沿 A+2: BRAM 输出有效, 采样 dcache_rdata, 设置写使能, 进入 MEM_WRITE_COMMIT
沿 A+3: BRAM 执行写入, done=1
```

### 3. icache.v / dcache.v — 行为级模型改为同步读

原始行为级模型使用组合读：`assign douta = ena ? mem[addra] : 32'b0`。当 ena=0 时输出为 0，与 BRAM 行为不符（BRAM 在 ena=0 时保持上次输出）。

**改动：**

- 新增 `douta_reg`、`doutb_reg` 寄存器
- 读逻辑改为同步：`always @(posedge clka) if (ena) douta_reg <= mem[addra]`
- 写逻辑移入同一 always 块：`if (ena && wea[0]) mem[addra] <= dina`
- 输出改为寄存器输出：`assign douta = douta_reg`

此修改使行为级模型与 BRAM IP 核行为一致，iverilog 仿真结果与 Vivado 仿真结果相同。

### 4. tb_simple_cpu_top.v — check_mem_word 增加时钟等待

dcache 端口 B 也有 1 周期同步读延迟。测试台设置 mem_addr 后，需等待一个时钟沿让 BRAM 锁存地址。

**改动：**

```verilog
// 修改前
mem_addr = addr;
#1;

// 修改后
mem_addr = addr;
@(posedge clk);
#1;
```

check_reg 不需要修改，因为寄存器堆（cpu_regfile）使用组合读。

### 5. simple_cpu_top.v — 连接 cpu_fetch 新增端口

cpu_fetch 新增了 clk 和 reset 端口，需要在顶层实例化中连接。

**改动：**

```verilog
cpu_fetch u_fetch(
    .clk(clk),        // 新增
    .reset(reset),    // 新增
    ...
);
```

## 验证结果

| 仿真环境 | 结果 |
|---------|------|
| iverilog（行为级模型） | pass=33 fail=0, ALL TESTS PASSED |
| Vivado xsim（BRAM IP 核） | pass=33 fail=0, ALL TESTS PASSED |

## Vivado 项目配置

- 项目路径：`E:/Xprogram/FPGA/tmp/simplecpu_bram_sim`
- 器件：xc7a200tfbg676-2
- icache BRAM IP：True_Dual_Port_RAM, 32bit×2048, COE 初始化, Use_Byte_Write_Enable=false, Register_PortA/B_Output=false
- dcache BRAM IP：同上，但 Load_Init_File=false（全零初始化）
- RTL 中不包含行为级 icache.v / dcache.v，由 BRAM IP wrapper 替代

## 性能影响

BRAM 读延迟导致每个访存操作增加 1 个时钟周期：

| 操作 | 原始周期数 | 修改后周期数 |
|------|-----------|------------|
| 取指（FETCH） | 1 | 2 |
| 读内存（lw/lb/lh） | 2（IDLE→READ） | 3（IDLE→READ→READ2） |
| 写内存（sw/sb/sh） | 3（IDLE→MODIFY→COMMIT） | 4（IDLE→MODIFY→MODIFY2→COMMIT） |
