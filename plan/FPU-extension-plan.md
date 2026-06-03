# FPU 扩展实施计划：RISC-V F/D 浮点单元 + 测试 + 计算器应用

> 创建日期: 2026-06-03 | 状态: **待实现** | 进度追踪: `process/FPU-extension-process.md`

---

## 0. 项目现状摘要

| 项目 | 当前状态 |
|------|----------|
| ISA | RV32IM (整数 + 乘除法)，48 条指令 |
| 数据通路 | 32-bit，多周期 FSM 五级流水线 (IF→ID→EX→MEM→WB) |
| 寄存器 | 32×32-bit 整数寄存器 (x0-x31) |
| CSR | mstatus/misa/mepc/mcause 等，misa 硬连线 `0x40001100` (RV32IM) |
| 运算单元 | ALU (CLA+逻辑+移位) + MU (Booth 乘法器 + 非恢复余数除法器) |
| 多周期握手 | MU 单元: `req_valid → mu_ready → mu_busy → result_valid → result_got` |
| 存储子系统 | ICache/DCache (1KB 各) + TLB (16项) + Sv32 MMU + AHB-Lite 总线 |
| 外设 | UART (TX/RX FIFO 16B) + GPIO + SPI + Timer + CLINT + PLIC |
| 测试体系 | 40 文件 / 264 子测试，自检协议 (x28=pass, x30=first_fail_id) |
| 程序库 | lib/uart.c, lib/gpio.c, app/uart_echo.c, app/uart_hello.s |
| SRAM | 32KB (0x80000000 ~ 0x80007FFC) |

---

## 1. 目标范围

### 1.1 实现范围

本计划实现 **RV32F** (单精度浮点) 扩展为核心，**暂不实现 D 扩展** (双精度)。原因：

1. 当前 CPU 为 RV32 (XLEN=32)，D 扩展要求 FLEN≥64，浮点寄存器需 64 位宽
2. D 扩展的 NaN-boxing、FMV.X.D/FMV.D.X 仅在 XLEN≥64 时可用
3. 单精度 F 扩展已足够覆盖计算器应用需求
4. F 扩展是 D 扩展的前置依赖，先实现 F 可为后续 D 扩展打好基础

> **D 扩展预留**：浮点寄存器堆参数化 (FLEN)，数据通路宽度可配置，为后续 D 扩展留接口。

### 1.2 F 扩展指令实现优先级

| 优先级 | 指令组 | 指令 | 理由 |
|--------|--------|------|------|
| P0 (必须) | 计算 | FADD.S, FSUB.S, FMUL.S, FDIV.S | 算术基础，计算器核心需求 |
| P0 (必须) | 加载/存储 | FLW, FSW | 浮点数据访存 |
| P0 (必须) | 转换 | FCVT.W.S, FCVT.S.W, FCVT.WU.S, FCVT.S.WU | 整数↔浮点互转 |
| P0 (必须) | 符号注入 | FSGNJ.S, FSGNJN.S, FSGNJX.S | FMV.F.X / FNEG / FABS 伪指令基础 |
| P0 (必须) | 移动 | FMV.X.W, FMV.W.X | 整数↔浮点寄存器位模式传输 |
| P1 (重要) | 比较 | FEQ.S, FLT.S, FLE.S | 条件判断 |
| P1 (重要) | 分类 | FCLASS.S | NaN/Inf/次正规数检测 |
| P1 (重要) | 最值 | FMIN.S, FMAX.S | 数值算法常用 |
| P2 (可选) | 融合乘加 | FMADD.S, FMSUB.S, FNMSUB.S, FNMADD.S | 性能优化，计算器非必需 |
| P2 (可选) | 平方根 | FSQRT.S | 可用牛顿迭代软件替代 |

> **实施策略**：P0 + P1 全部实现 (共 20 条指令)，P2 中 FSQRT.S 实现（硬件开销可控），FMA 四条暂不实现（R4 格式需新增译码逻辑，且硬件面积大）。

### 1.3 最终实现清单 (21 条浮点指令)

```
计算:    FADD.S  FSUB.S  FMUL.S  FDIV.S  FSQRT.S     (5)
加载存储: FLW     FSW                                  (2)
转换:    FCVT.W.S  FCVT.S.W  FCVT.WU.S  FCVT.S.WU    (4)
符号注入: FSGNJ.S  FSGNJN.S  FSGNJX.S                (3)
移动:    FMV.X.W  FMV.W.X                            (2)
比较:    FEQ.S  FLT.S  FLE.S                          (3)
分类:    FCLASS.S                                    (1)
最值:    FMIN.S  FMAX.S                              (2)
                                              合计: 22 条
```

> 注：FSGNJ/FSGNJN/FSGNJX 是独立指令，FMV.X.W/FMV.W.X 也是独立指令（不同编码），总计 22 条。

---

## 2. 架构设计

### 2.1 浮点寄存器堆 (`fpu_regfile.sv`)

```
fpu_regfile
├── 32 × 32-bit 浮点寄存器 f0-f31
├── f0 恒为 0 (与 x0 类似，RISC-V 规范不要求 f0=0，但简化设计)
├── 双读端口 + 单写端口
├── 调试读端口 (dbg_faddr / dbg_fdata)
└── 参数化 FLEN (当前=32，D 扩展时=64)
```

**接口**：

```systemverilog
module fpu_regfile(
    input         clk, reset,
    input         wen,
    input  [4:0]  raddr1, raddr2, waddr,
    input  [31:0] wdata,
    output [31:0] rdata1, rdata2,
    input  [4:0]  dbg_faddr,
    output [31:0] dbg_fdata
);
```

### 2.2 浮点运算单元 (`fpu_unit.sv`)

采用与 `mu_unit` 相同的多周期握手协议，复用 FSM 控制器等待逻辑：

```
fpu_unit
├── fpu_adder      ← 浮点加法器 (FADD.S / FSUB.S)
├── fpu_multiplier ← 浮点乘法器 (FMUL.S)
├── fpu_divider    ← 浮点除法器 (FDIV.S)
├── fpu_sqrt       ← 浮点平方根 (FSQRT.S)
├── fpu_compare    ← 浮点比较器 (FEQ.S / FLT.S / FLE.S)
├── fpu_minmax     ← 浮点最值 (FMIN.S / FMAX.S)
├── fpu_classify   ← 浮点分类 (FCLASS.S)
├── fpu_sign_inject← 符号注入 (FSGNJ.S / FSGNJN.S / FSGNJX.S)
├── fpu_cvt        ← 浮点转换 (FCVT.W.S / FCVT.S.W / FCVT.WU.S / FCVT.S.WU)
└── 结果选择器     ← 按 fpu_funct 选择结果
```

**握手协议** (与 mu_unit 一致)：

```
req_valid → fpu_ready → fpu_busy → result_valid → result_got
```

**接口**：

```systemverilog
module fpu_unit(
    input         clk, reset,
    input  [6:0]  fpu_funct,    // 浮点操作码
    input  [2:0]  fpu_rm,       // 舍入模式
    input  [31:0] src1, src2,   // 浮点操作数
    input         req_valid,
    input         flush,
    input         result_got,
    output [31:0] result,       // 结果 (写入浮点寄存器或整数寄存器)
    output        fpu_busy,
    output        fpu_ready,
    output        result_valid,
    output [4:0]  fflags        // 异常标志 (NV/DZ/OF/UF/NX)
);
```

### 2.3 浮点加法器 (`fpu_adder.sv`)

IEEE 754 单精度浮点加法，支持舍入模式：

```
fpu_adder
├── 输入对齐: 指数差 → 尾数右移
├── 有效减法检测: 符号不同且指数相同
├── 尾数加/减
├── 前导零计数 (LZC) → 规格化
├── 舍入 (RNE/RTZ/RDN/RUP/RMM)
├── 溢出/下溢检测
└── NaN/Inf 特殊处理
```

**多周期实现**：3-5 周期完成 (对齐→加法→规格化→舍入)。

### 2.4 浮点乘法器 (`fpu_multiplier.sv`)

```
fpu_multiplier
├── 指数相加 (减偏移 127)
├── 尾数相乘 (24×24 → 48-bit，可复用 Booth 乘法器或直接组合)
├── 规格化 + 舍入
├── 溢出/下溢检测
└── NaN/Inf/零 特殊处理
```

**实现选择**：采用组合乘法 (24×24 位宽可控)，单周期或 2 周期完成。

### 2.5 浮点除法器 (`fpu_divider.sv`)

```
fpu_divider
├── SRT 除法迭代 (24 周期)
├── 指数相减 (加偏移 127)
├── 规格化 + 舍入
├── 除零检测 → DZ 标志
└── NaN/Inf 特殊处理
```

### 2.6 浮点平方根 (`fpu_sqrt.sv`)

```
fpu_sqrt
├── 牛顿-Raphson 迭代 (初始近似 + 3-4 次迭代)
├── 或非恢复余数法 (类似除法器)
├── 规格化 + 舍入
└── 负数输入 → NaN + NV 标志
```

### 2.7 浮点 CSR (`fcsr`)

| CSR 地址 | 名称 | 位域 | 说明 |
|----------|------|------|------|
| 0x001 | fflags | [4:0] = NV·DZ·OF·UF·NX | 累积异常标志 |
| 0x002 | frm | [2:0] = 舍入模式 | 动态舍入模式 |
| 0x003 | fcsr | [7:0] = frm·fflags | 合并寄存器 |

**mstatus 扩展**：

- FS 域 [14:13]：浮点状态 (00=Off, 01=Initial, 10=Clean, 11=Dirty)
- 写浮点寄存器时置 FS=Dirty
- misa 更新：F 位 [5] = 1，新值 `0x40001120` (RV32IMF)

### 2.8 译码扩展 (`cpu_decode.sv`)

新增 opcode 识别：

| opcode | 名称 | 指令 |
|--------|------|------|
| 0x07 (0000111) | LOAD-FP | FLW |
| 0x27 (0100111) | STORE-FP | FSW |
| 0x43 (1000011) | OP-FP | FADD.S/FSUB.S/FMUL.S/FDIV.S/FSQRT.S/FMIN.S/FMAX.S/FSGNJ*/FCVT/FEQ/FLT/FLE/FCLASS/FMV.X.W/FMV.W.X |

**ID/EX 总线扩展**：新增字段 `is_fpu`, `fpu_funct[6:0]`, `fpu_rm[2:0]`, `frs1_addr[4:0]`, `frs2_addr[4:0]`, `fpu_rd_is_int` (比较/分类/FMV.X.W 结果写整数寄存器)。

### 2.9 执行级扩展 (`cpu_execute.sv`)

- FPU 请求：当 `is_fpu=1` 时，发起 `fpu_req_valid`
- FPU 等待：FSM 在 STATE_EXEC 等待 `fpu_result_valid`
- 结果获取：`fpu_result_valid=1` 时锁存结果，发 `fpu_result_got`
- 结果路由：`fpu_rd_is_int=1` → 写整数寄存器，否则 → 写浮点寄存器

### 2.10 访存级扩展 (`cpu_mem.sv`)

- FLW：Load 数据写入浮点寄存器 (需新增浮点寄存器写端口)
- FSW：从浮点寄存器读取数据写入内存

### 2.11 回写级扩展 (`cpu_wb.sv`)

- 新增浮点寄存器写使能和数据路径
- FPU 计算结果 → 浮点寄存器
- FCVT/FEQ/FLT/FLE/FCLASS/FMV.X.W → 整数寄存器

### 2.12 FSM 控制器扩展 (`cpu_controller.sv`)

- 新增 `STATE_FPU_WAIT` 状态 (可选，或在 STATE_EXEC 内轮询)
- 推荐方案：在 STATE_EXEC 内轮询 `fpu_result_valid`，与 MU 单元等待逻辑一致
- 无需新增 FSM 状态

### 2.13 系统顶层修改

```
core_top (修改)
├── fpu_regfile     ← 新增: 32×32-bit 浮点寄存器堆
├── fpu_unit        ← 新增: 浮点运算单元
├── cpu_decode      ← 修改: 新增浮点指令译码
├── cpu_execute     ← 修改: FPU 请求/等待逻辑
├── cpu_mem         ← 修改: FLW/FSW 数据路径
├── cpu_wb          ← 修改: 浮点寄存器写回
├── cpu_csr         ← 修改: fflags/frm/fcsr CSR + mstatus.FS + misa.F
└── cpu_controller  ← 修改: FPU 等待 (复用 MU 等待模式)
```

---

## 3. 实施阶段

### Phase 1: 浮点寄存器堆 + CSR 基础 (RTL)

**目标**：添加浮点寄存器堆和浮点 CSR，不改变指令执行逻辑。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 1.1 | `dev/rtl/FPU/fpu_regfile.sv` | 新建：32×32-bit 浮点寄存器堆 |
| 1.2 | `dev/rtl/core/cpu_csr.sv` | 修改：添加 fflags (0x001), frm (0x002), fcsr (0x003) CSR |
| 1.3 | `dev/rtl/core/cpu_csr.sv` | 修改：misa 更新 F 位 [5]=1，新值 `0x40001120` |
| 1.4 | `dev/rtl/core/cpu_csr.sv` | 修改：mstatus 添加 FS 域 [14:13] 写支持 |
| 1.5 | `dev/rtl/core/core_top.sv` | 修改：实例化 fpu_regfile，连接 CSR 信号 |
| 1.6 | `dev/rtl/core/core_top.sv` | 修改：添加浮点寄存器调试读端口 |

**验证**：CSR 读写测试 (fflags/frm/fcsr 可读写，misa.F=1)。

### Phase 2: 浮点运算单元 (RTL)

**目标**：实现 FPU 子模块，可独立验证。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 2.1 | `dev/rtl/FPU/fpu_adder.sv` | 新建：IEEE 754 单精度加法器 (FADD.S/FSUB.S) |
| 2.2 | `dev/rtl/FPU/fpu_multiplier.sv` | 新建：IEEE 754 单精度乘法器 (FMUL.S) |
| 2.3 | `dev/rtl/FPU/fpu_divider.sv` | 新建：SRT 除法器 (FDIV.S) |
| 2.4 | `dev/rtl/FPU/fpu_sqrt.sv` | 新建：平方根单元 (FSQRT.S) |
| 2.5 | `dev/rtl/FPU/fpu_compare.sv` | 新建：浮点比较器 (FEQ.S/FLT.S/FLE.S) |
| 2.6 | `dev/rtl/FPU/fpu_minmax.sv` | 新建：浮点最值 (FMIN.S/FMAX.S) |
| 2.7 | `dev/rtl/FPU/fpu_classify.sv` | 新建：浮点分类 (FCLASS.S) |
| 2.8 | `dev/rtl/FPU/fpu_sign_inject.sv` | 新建：符号注入 (FSGNJ.S/FSGNJN.S/FSGNJX.S) |
| 2.9 | `dev/rtl/FPU/fpu_cvt.sv` | 新建：浮点↔整数转换 (FCVT.W.S/FCVT.S.W/FCVT.WU.S/FCVT.S.WU) |
| 2.10 | `dev/rtl/FPU/fpu_round.sv` | 新建：舍入模式逻辑 (RNE/RTZ/RDN/RUP/RMM/DYN) |
| 2.11 | `dev/rtl/FPU/fpu_special.sv` | 新建：NaN/Inf/零/次正规数特殊处理 |
| 2.12 | `dev/rtl/FPU/fpu_unit.sv` | 新建：FPU 顶层 (握手协议 + 结果选择) |

**验证**：每个子模块独立 testbench，对照 IEEE 754 参考结果。

### Phase 3: 指令译码 + 数据通路集成 (RTL)

**目标**：将浮点指令接入 CPU 流水线，实现完整执行路径。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 3.1 | `dev/rtl/core/cpu_decode.sv` | 修改：新增 LOAD-FP/STORE-FP/OP-FP opcode 识别 |
| 3.2 | `dev/rtl/core/cpu_decode.sv` | 修改：新增浮点指令 funct5+fmt+rm 译码 |
| 3.3 | `dev/rtl/core/cpu_decode.sv` | 修改：ID/EX 总线扩展 (is_fpu, fpu_funct, fpu_rm, frs1/frs2, fpu_rd_is_int) |
| 3.4 | `dev/rtl/core/cpu_decode.sv` | 修改：操作数选择 (浮点寄存器读) |
| 3.5 | `dev/rtl/core/cpu_execute.sv` | 修改：FPU 请求/等待/结果获取逻辑 |
| 3.6 | `dev/rtl/core/cpu_execute.sv` | 修改：EX/MEM 总线扩展 (浮点结果 + fflags) |
| 3.7 | `dev/rtl/core/cpu_mem.sv` | 修改：FLW/FSW 数据路径 (浮点寄存器↔内存) |
| 3.8 | `dev/rtl/core/cpu_mem.sv` | 修改：MEM/WB 总线扩展 |
| 3.9 | `dev/rtl/core/cpu_wb.sv` | 修改：浮点寄存器写回 + fflags 累积 |
| 3.10 | `dev/rtl/core/cpu_controller.sv` | 修改：FPU 等待 (STATE_EXEC 内轮询 fpu_result_valid) |
| 3.11 | `dev/rtl/core/core_top.sv` | 修改：实例化 fpu_unit，连接各级信号 |
| 3.12 | `dev/rtl/core/core_top.sv` | 修改：浮点寄存器读端口连接 (decode 级读 frs1/frs2) |

**验证**：简单浮点指令端到端测试 (FADD.S + FLW/FSW + FCVT)。

### Phase 4: 浮点指令测试 (测试程序)

**目标**：编写自检测试程序，覆盖所有 22 条浮点指令。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 4.1 | `dev/program_source/test/isa/f_ext.s` | 新建：F 扩展 ISA 测试 (22 条指令逐一测试) |
| 4.2 | `dev/program_source/test/tests.yaml` | 修改：注册 `isa/f_ext` 测试 |
| 4.3 | `dev/tb/tb_isa_f_ext.sv` | 新建：F 扩展 testbench |
| 4.4 | `tasks.yaml` | 修改：添加 `isa_f_ext` 任务 |

**测试用例设计** (f_ext.s)：

| 子测试 | 指令 | 测试内容 |
|--------|------|----------|
| 1-3 | FADD.S | 正+正, 正+负, 溢出 |
| 4-6 | FSUB.S | 正-正, 正-负, 下溢 |
| 7-9 | FMUL.S | 正×正, 零×Inf, 溢出 |
| 10-12 | FDIV.S | 正/正, 正/零(DZ), Inf/Inf(NV) |
| 13-14 | FSQRT.S | √4=2, √-1=NaN(NV) |
| 15-16 | FLW/FSW | 存后加载一致性 |
| 17-18 | FCVT.W.S | 3.7→3(RNE), 3.7→4(RUP) |
| 19-20 | FCVT.S.W | 3→3.0, -1→-1.0 |
| 21-22 | FCVT.WU.S | 正数转无符号, 负数越界 |
| 23-24 | FCVT.S.WU | 无符号转浮点 |
| 25-27 | FSGNJ/FSGNJN/FSGNJX | 符号注入各模式 |
| 28-29 | FMV.X.W/FMV.W.X | 位模式传输 |
| 30-32 | FEQ/FLT/FLE | 比较结果 (1/0) |
| 33 | FCLASS.S | 正规数分类 |
| 34-35 | FMIN.S/FMAX.S | 最值选择 |

### Phase 5: 浮点异常/舍入测试 (测试程序)

**目标**：验证 fflags 累积、舍入模式、特殊值处理。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 5.1 | `dev/program_source/test/isa/f_ext_special.s` | 新建：特殊值 + 舍入模式测试 |
| 5.2 | `dev/program_source/test/tests.yaml` | 修改：注册 `isa/f_ext_special` |
| 5.3 | `dev/tb/tb_isa_f_ext_special.sv` | 新建：testbench |
| 5.4 | `tasks.yaml` | 修改：添加任务 |

**测试内容**：

- NaN 传播 (qNaN + 1 = qNaN, sNaN + 1 = qNaN + NV)
- Inf 运算 (Inf + Inf = Inf, Inf - Inf = NaN + NV)
- 零运算 (+0 + -0 = +0 RNE, -0 + +0 = +0 RNE)
- 次正规数运算
- 舍入模式 (RNE/RTZ/RDN/RUP/RMM 各测试 FCVT 和 FADD)
- fflags 累积 (连续运算后 fflags 包含所有历史异常)
- fcsr 读写 (frm + fflags 合并/拆分)

### Phase 6: FPU 单元测试 (Testbench)

**目标**：RTL 子模块独立验证，确保 IEEE 754 合规。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 6.1 | `dev/tb/FPU/tb_fpu_adder.sv` | 新建：加法器单元测试 |
| 6.2 | `dev/tb/FPU/tb_fpu_multiplier.sv` | 新建：乘法器单元测试 |
| 6.3 | `dev/tb/FPU/tb_fpu_divider.sv` | 新建：除法器单元测试 |
| 6.4 | `dev/tb/FPU/tb_fpu_sqrt.sv` | 新建：平方根单元测试 |
| 6.5 | `dev/tb/FPU/tb_fpu_cvt.sv` | 新建：转换单元测试 |
| 6.6 | `dev/tb/FPU/tb_fpu_unit.sv` | 新建：FPU 顶层集成测试 |

**测试策略**：
- 边界值：±0, ±Inf, qNaN, sNaN, 最大/最小正规数, 最大/最小次正规数
- 随机测试：1000+ 随机浮点对，**预计算参考表比对**
  - 由 `tools/fpu_ref_gen.py` 生成：随机 float 对 → C `<math.h>` 计算期望结果 → 输出 hex 文件
  - hex 格式：每行 `{src1[31:0], src2[31:0], expected[31:0], fflags[4:0]}`
  - testbench 用 `$readmemh` 读入，逐向量驱动 FPU → 比对 result vs expected
  - 失败时打印向量索引 + 实际/期望十六进制值
- 舍入验证：每种舍入模式下的边界情况

### Phase 7: 计算器应用 (应用程序)

**目标**：基于 UART IO 的浮点计算器，支持四则运算 + 括号。

| 步骤 | 文件 | 内容 |
|------|------|------|
| 7.1 | `dev/program_source/lib/stdio.c` | 新建：printf/scanf 简化实现 (基于 UART) |
| 7.2 | `dev/program_source/lib/stdio.h` | 新建：stdio 头文件 |
| 7.3 | `dev/program_source/lib/ftoa.c` | 新建：float→ASCII 转换 (利用 FMV.X.W 提取 IEEE 754 位域) |
| 7.4 | `dev/program_source/lib/atof.c` | 新建：ASCII→float 转换 (利用 FMV.W.X 构造 IEEE 754 位域) |
| 7.5 | `dev/program_source/lib/math.c` | 新建：软件数学函数 (pow, sin, cos, sqrt - 利用 FPU 指令) |
| 7.6 | `dev/program_source/lib/math.h` | 新建：math 头文件 |
| 7.7 | `dev/program_source/app/calculator.c` | 新建：计算器主程序 |
| 7.8 | `dev/program_source/app/calculator.s` | 新建：计算器汇编入口 (如需) |

**计算器功能规格**：

```
输入格式:  <表达式>\n
输出格式:  = <结果>\n

支持运算:
  +  加法       例: 3.14+2.86
  -  减法       例: 10-3.5
  *  乘法       例: 2.5*4
  /  除法       例: 10/3
  () 括号      例: (1+2)*3
  sqrt 平方根   例: sqrt(2)
  neg 取负     例: neg(3.14)

示例交互:
  > 1.5+2.5
  = 4.000000
  > 10/3
  = 3.333333
  > sqrt(2)
  = 1.414214
  > (1+2)*3.5
  = 10.500000
```

**实现架构**：

```
calculator.c
├── main()
│   ├── uart_init()
│   ├── 打印欢迎信息
│   └── 循环: 读取输入行 → 解析求值 → 输出结果
├── eval_expr()      ← 递归下降表达式解析器
│   ├── parse_expr()   ← 加减层
│   ├── parse_term()   ← 乘除层
│   ├── parse_factor() ← 括号/一元/数字
│   └── parse_number() ← atof 转换
└── ftoa()           ← 浮点结果转字符串输出
```

**SRAM 预算**：

- 代码 + 库 ≈ 4KB
- 栈 + 数据 ≈ 1KB
- 总计 ≈ 5KB << 32KB，充裕

### Phase 8: 计算器测试 (Testbench)

| 步骤 | 文件 | 内容 |
|------|------|------|
| 8.1 | `dev/tb/tb_calculator.sv` | 新建：计算器 testbench (UART 输入→输出验证) |
| 8.2 | `tasks.yaml` | 修改：添加 calculator 任务 |

**验证方式**：

- testbench 内嵌 UART TX 发送器，发送算式字符串
- testbench 内嵌 UART RX 接收器，捕获输出
- 逐算式比对输出结果

---

## 4. 文件清单汇总

### 4.1 新建文件

| 目录 | 文件 | 说明 |
|------|------|------|
| `dev/rtl/FPU/` | `fpu_regfile.sv` | 浮点寄存器堆 |
| `dev/rtl/FPU/` | `fpu_unit.sv` | FPU 顶层 |
| `dev/rtl/FPU/` | `fpu_adder.sv` | 浮点加法器 |
| `dev/rtl/FPU/` | `fpu_multiplier.sv` | 浮点乘法器 |
| `dev/rtl/FPU/` | `fpu_divider.sv` | 浮点除法器 |
| `dev/rtl/FPU/` | `fpu_sqrt.sv` | 浮点平方根 |
| `dev/rtl/FPU/` | `fpu_compare.sv` | 浮点比较器 |
| `dev/rtl/FPU/` | `fpu_minmax.sv` | 浮点最值 |
| `dev/rtl/FPU/` | `fpu_classify.sv` | 浮点分类 |
| `dev/rtl/FPU/` | `fpu_sign_inject.sv` | 符号注入 |
| `dev/rtl/FPU/` | `fpu_cvt.sv` | 浮点↔整数转换 |
| `dev/rtl/FPU/` | `fpu_round.sv` | 舍入模式逻辑 |
| `dev/rtl/FPU/` | `fpu_special.sv` | NaN/Inf 特殊处理 |
| `dev/tb/FPU/` | `tb_fpu_adder.sv` | 加法器单元测试 |
| `dev/tb/FPU/` | `tb_fpu_multiplier.sv` | 乘法器单元测试 |
| `dev/tb/FPU/` | `tb_fpu_divider.sv` | 除法器单元测试 |
| `dev/tb/FPU/` | `tb_fpu_sqrt.sv` | 平方根单元测试 |
| `dev/tb/FPU/` | `tb_fpu_cvt.sv` | 转换单元测试 |
| `dev/tb/FPU/` | `tb_fpu_unit.sv` | FPU 集成测试 |
| `dev/tb/` | `tb_isa_f_ext.sv` | F 扩展 ISA testbench |
| `dev/tb/` | `tb_isa_f_ext_special.sv` | F 扩展特殊值 testbench |
| `dev/tb/` | `tb_calculator.sv` | 计算器 testbench |
| `dev/program_source/test/isa/` | `f_ext.s` | F 扩展 ISA 测试 |
| `dev/program_source/test/isa/` | `f_ext_special.s` | F 扩展特殊值测试 |
| `dev/program_source/lib/` | `stdio.c` | printf/scanf 简化实现 |
| `dev/program_source/lib/include/` | `stdio.h` | stdio 头文件 |
| `dev/program_source/lib/` | `ftoa.c` | float→ASCII 转换 |
| `dev/program_source/lib/` | `atof.c` | ASCII→float 转换 |
| `dev/program_source/lib/` | `math.c` | 软件数学函数 |
| `dev/program_source/lib/include/` | `math.h` | math 头文件 |
| `dev/program_source/app/` | `calculator.c` | 计算器主程序 |
| `tools/` | `fpu_ref_gen.py` | FPU 测试参考向量生成器 (Python, 调用 C math) |

### 4.2 修改文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/core_top.sv` | 实例化 fpu_regfile + fpu_unit，连接信号 |
| `dev/rtl/core/cpu_decode.sv` | 浮点指令译码 + ID/EX 总线扩展 |
| `dev/rtl/core/cpu_execute.sv` | FPU 请求/等待/结果获取 |
| `dev/rtl/core/cpu_mem.sv` | FLW/FSW 数据路径 |
| `dev/rtl/core/cpu_wb.sv` | 浮点寄存器写回 |
| `dev/rtl/core/cpu_controller.sv` | FPU 等待逻辑 |
| `dev/rtl/core/cpu_csr.sv` | fflags/frm/fcsr + mstatus.FS + misa.F |
| `dev/rtl/system_top.sv` | 可能需要调整 (调试端口) |
| `dev/program_source/test/tests.yaml` | 注册 F 扩展测试 |
| `tasks.yaml` | 添加仿真任务 |

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| FPU 子模块 IEEE 754 不合规 | 计算结果错误 | Phase 6 单元测试 + 随机对照 C 语言 |
| 浮点除法器/平方根周期数过长 | 性能下降 | 与 MU 单元共享等待逻辑，FSM 已支持多周期 |
| ID/EX 总线扩展位宽增加 | 面积增加 | 仅新增 ~50 bit (is_fpu+fpu_funct+fpu_rm+frs1+frs2+fpu_rd_is_int) |
| SRAM 容量不足 (32KB) | 计算器程序放不下 | 估算仅 5KB，远低于上限 |
| 舍入模式实现错误 | 边界结果偏差 | 5 种舍入模式逐一测试 (Phase 5) |
| NaN/Inf 传播不符合规范 | 异常标志错误 | Phase 5 特殊值测试全覆盖 |
| F 扩展与现有 M 扩展冲突 | 译码空间重叠 | opcode 空间独立 (LOAD-FP/STORE-FP/OP-FP)，无冲突 |

---

## 6. D 扩展预留

本计划为后续 D 扩展 (双精度浮点) 预留以下接口：

| 预留项 | 当前实现 | D 扩展时修改 |
|--------|----------|-------------|
| FLEN | 32 | 64 |
| fpu_regfile 宽度 | 32-bit | 64-bit |
| NaN-boxing | 不需要 | 单精度值 NaN-box 到 64-bit |
| FMV.X.D/FMV.D.X | 不实现 | XLEN=64 时实现 |
| FCVT.S.D/FCVT.D.S | 不实现 | 精度间转换 |
| fmt 字段 | 硬连线 S (00) | 译码 D (01) |
| misa.D | 0 | 置 1 |

---

## 7. 工作量估算

| Phase | 内容 | 预估工时 | 复杂度 |
|-------|------|----------|--------|
| Phase 1 | 浮点寄存器堆 + CSR | 4h | 低 |
| Phase 2 | FPU 子模块 (12 个) | 40h | 高 |
| Phase 3 | 译码 + 数据通路集成 | 16h | 高 |
| Phase 4 | F 扩展 ISA 测试 | 8h | 中 |
| Phase 5 | 特殊值/舍入测试 | 6h | 中 |
| Phase 6 | FPU 单元测试 | 12h | 中 |
| Phase 7 | 计算器应用 | 12h | 中 |
| Phase 8 | 计算器测试 | 4h | 低 |
| **合计** | | **~102h** | |

---

## 8. 执行顺序与依赖

```
Phase 1 (寄存器+CSR) ──→ Phase 3 (集成) ──→ Phase 4 (ISA测试)
                              ↑                    ↓
Phase 2 (FPU子模块) ─────────┘              Phase 5 (特殊值测试)
                                                    ↓
Phase 6 (FPU单元测试) ←── Phase 2 ──────────────┘
                                                    ↓
Phase 7 (计算器应用) ──→ Phase 8 (计算器测试)
```

**关键路径**：Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 7 → Phase 8

**可并行**：

- Phase 6 (FPU 单元测试) 可与 Phase 3 并行 (FPU 子模块独立验证)
- Phase 5 可与 Phase 4 部分并行

---

## 9. 验收标准

| # | 标准 | 验证方式 |
|---|------|----------|
| 1 | 所有 22 条浮点指令功能正确 | Phase 4 ISA 测试全 PASS |
| 2 | IEEE 754 特殊值处理正确 (NaN/Inf/零/次正规数) | Phase 5 特殊值测试全 PASS |
| 3 | 5 种舍入模式正确 | Phase 5 舍入测试全 PASS |
| 4 | fflags 累积正确 | Phase 5 异常标志测试全 PASS |
| 5 | FPU 子模块 IEEE 754 合规 | Phase 6 单元测试全 PASS |
| 6 | 计算器正确计算四则运算 + 括号 + sqrt | Phase 8 testbench 验证 |
| 7 | 原有 264 子测试不受影响 | 全回归 PASS |
| 8 | misa = 0x40001120 (RV32IMF) | CSR 读取验证 |

## 10. 标准文件

F扩展：dev\docs\IS\21-F扩展-单精度浮点.md
