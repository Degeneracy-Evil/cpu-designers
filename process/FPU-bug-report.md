# FPU 扩展代码审查 — BUG 报告

> 审查日期: 2026-06-04 | 依据: `dev/docs/IS/21-F扩展-单精度浮点.md` | 审查范围: git diff 修改部分
> 修复日期: 2026-06-05 | ISA 测试验证: 2026-06-05 (f_ext 26/26, f_ext_special 24/24, calculator 5/5)

---

## 审查方法

1. 依据 RISC-V F 扩展规范（第21章）逐项对照实现
2. 手工验证所有总线位宽打包/解包索引
3. 检查数据通路、控制信号、CSR 读写时序
4. 检查 FPU 握手协议与流水线交互

---

## 总线位宽验证（全部通过 ✅）

| 总线 | 计算位宽 | 声明位宽 | 结果 |
|------|----------|----------|------|
| `id_exe_bus` | 334 | [333:0] | ✅ |
| `exe_mem_bus` | 216 | [215:0] | ✅ |
| `mem_wb_bus` | 177 | [176:0] | ✅ |
| `exe_wb_bus` | 177 | [176:0] | ✅ |
| `csr_wb_bus` | 177 | [176:0] | ✅ |

所有位索引映射（`exe_wb_bus`、`cpu_csr_interface` 字段提取等）均与打包顺序一致，无错位。

---

## BUG 清单

### BUG 1 🔴→✅ 高 | fflags 软件写与硬件 OR 累加冲突 — 已修复

**文件**: `dev/rtl/core/cpu_csr.sv` L346-356

**问题代码**:
```sv
// 在 sw_csr_wen 的 case 块中:
ADDR_FFLAGS:     r_fflags    <= sw_csr_wdata[4:0];   // 软件写
ADDR_FCSR:       {r_frm, r_fflags} <= sw_csr_wdata[7:0]; // FCSR 写

// 紧接在 case 块之后:
if (fflags_wen) begin
    r_fflags <= r_fflags | fflags_wdata;  // 硬件 OR 累加
end
```

**问题**: 当同一时钟周期内 CSR 指令写 fflags（如 `csrw fflags, x1`）且 FPU 指令也产生异常（`fflags_wen=1`）时，`r_fflags` 有两个非阻塞赋值。Verilog 中**最后一个赋值生效**，因此硬件 OR 累加会覆盖软件写入值，软件写被静默丢弃。

**规范要求**: F 扩展规范 21.2 节定义 fflags 为累积异常标志，软件可通过 FSCSR/FSFLAGS 清零或写入。当硬件异常与软件写同时发生时，应基于软件写入后的新值进行 OR 累加。

**修复方案** (已实施 — 方案 B):
```sv
// 引入中间变量
wire [4:0] fflags_sw_new;
wire       fflags_sw_wen;
assign fflags_sw_new = (sw_csr_addr == ADDR_FFLAGS) ? sw_csr_wdata[4:0] :
                       (sw_csr_addr == ADDR_FCSR)   ? sw_csr_wdata[4:0] : r_fflags;
assign fflags_sw_wen = sw_csr_wen && (sw_csr_addr == ADDR_FFLAGS ||
                                      sw_csr_addr == ADDR_FCSR);

// case 块中:
ADDR_FFLAGS: ;                              // fflags 由合并逻辑处理
ADDR_FCSR:    r_frm <= sw_csr_wdata[7:5];   // frm 仍在 case 中, fflags 由合并逻辑处理

// 合并写逻辑:
if (fflags_sw_wen && fflags_wen)
    r_fflags <= fflags_sw_new | fflags_wdata;   // 同时: 先写软件值, 再 OR 硬件异常
else if (fflags_sw_wen)
    r_fflags <= fflags_sw_new;                   // 仅软件写
else if (fflags_wen)
    r_fflags <= r_fflags | fflags_wdata;         // 仅硬件 OR
```

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 2 🔴→✅ 高 | FLW 同时写整数寄存器和浮点寄存器 — 已修复

**文件**: `dev/rtl/core/cpu_wb.sv` L47

**问题代码**:
```sv
assign rf_wen = wb_valid && wb_we && (fpu_writes_int || !is_fpu);  // FLW: is_fpu=0, !is_fpu=1 → rf_wen=1
assign fp_wen = wb_valid && (fpu_writes_fp || is_flw);             // FLW: is_flw=1 → fp_wen=1
```

**问题**: FLW 的 `is_fpu=0`，导致 `!is_fpu=1`，`rf_wen=1`。FLW 同时写整数寄存器和浮点寄存器，违反 RISC-V 规范——FLW 只应写浮点寄存器 fd。

**规范依据**: F 扩展 21.5 节 — "FLW 指令从内存中加载一个单精度浮点值到**浮点寄存器** rd 中"。

**修复方案** (已实施):
```sv
assign rf_wen = wb_valid && wb_we && (fpu_writes_int || (!is_fpu && !is_flw));
```

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 3 🔴→✅ 高 | FMV.W.X 读取浮点寄存器而非整数寄存器 — 已修复

**文件**: `dev/rtl/core/cpu_execute.sv` L163

**问题代码**:
```sv
fpu_unit u_fpu(
    .src1(frs1_value),   // ← 始终传浮点寄存器 rs1 的值
    .src2(frs2_value),   // ← 始终传浮点寄存器 rs2 的值
    ...
);
```

fpu_unit 中 FMV.W.X 实现:
```sv
(FPU_FMV_W_X) ? src1_reg  // 直接传递 src1（应为整数寄存器值）
```

**问题**: FMV.W.X 语义为"将**整数寄存器** rs1 的低 32 位移动到浮点寄存器 rd"。当前实现读取的是浮点寄存器 frs1，源操作数完全错误。

**规范依据**: F 扩展 21.7 节 — "FMV.W.X 将**整数寄存器** rs1 低 32 位中以 IEEE 754-2008 标准编码表示的单精度值移动到浮点寄存器 rd"。

**修复方案** (已实施 — 与 BUG 4 合并修复):
```sv
// Int→float 指令源操作数 mux
wire fpu_src_is_int = (fpu_funct == 7'd15) ||  // FMV.W.X
                      (fpu_funct == 7'd18) ||  // FCVT.S.W
                      (fpu_funct == 7'd19);    // FCVT.S.WU
wire [31:0] fpu_src1_mux = fpu_src_is_int ? rs1_value : frs1_value;

fpu_unit u_fpu(
    .src1(fpu_src1_mux),
    .src2(frs2_value),
    ...
);
```

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 4 🔴→✅ 高 | FCVT.S.W / FCVT.S.WU 读取浮点寄存器而非整数寄存器 — 已修复

**文件**: `dev/rtl/core/cpu_execute.sv`（与 BUG 3 同源）

**问题**: FCVT.S.W 将**整数寄存器** rs1 中的有符号 32 位整数转换为浮点数。FCVT.S.WU 转换无符号整数。当前实现读取的是浮点寄存器 frs1，源操作数错误。

**规范依据**: F 扩展 21.7 节 — "FCVT.S.W 将**整数寄存器** rs1 中的 32 位有符号整数转换为浮点寄存器 rd 中的浮点数"。

**修复方案**: 与 BUG 3 合并修复，见上方 `fpu_src_is_int` + `fpu_src1_mux` 逻辑。

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 5 🟡→📝 中 | FMADD/FMSUB/FNMSUB/FNMADD 融合乘加指令未解码 — 已注释

**文件**: `dev/rtl/core/cpu_decode.sv`

**问题**: F 扩展规范 21.6 节定义了四条融合乘加指令（R4 格式）：
- FMADD.S: opcode=`1000011`, 计算 (rs1×rs2)+rs3
- FMSUB.S: opcode=`1000111`, 计算 (rs1×rs2)−rs3
- FNMSUB.S: opcode=`1001011`, 计算 −(rs1×rs2)+rs3
- FNMADD.S: opcode=`1001111`, 计算 −(rs1×rs2)−rs3

当前 `cpu_decode.sv` 未解码这些指令，遇到时会被判定为 `illegal_inst`。

**处理**: 进度文档中已记录"暂不实现 FMA 指令"的决策（R4 格式译码复杂，硬件面积大）。已在 `cpu_decode.sv` 中添加明确注释说明此为设计决策，非缺陷。

**修复状态**: ✅ 已注释说明 (2026-06-04)

---

### BUG 6 🟢 低 | f0 硬连线为零不符合 RISC-V 规范 — 保持现状

**文件**: `dev/rtl/FPU/fpu_regfile.sv` L17-19, L30, L35-36

**问题代码**:
```sv
// f0 is hardwired to zero, matching the integer register file pattern.
// The RISC-V spec does NOT require f0=0 (unlike x0), but this
// simplifies the design and is a common implementation choice.
```

**规范依据**: F 扩展 21.1 节 — 浮点寄存器 f0-f31 均为通用寄存器，无硬连线零要求（仅整数 x0 有此要求）。

**影响**: 写入 f0 的值被丢弃；读取 f0 总返回 0。依赖 f0 作为通用临时寄存器的软件会出错。

**严重程度**: 低。注释已说明是设计选择，大多数编译器不会使用 f0 作为通用寄存器（受 x0 惯例影响），但严格合规需修复。

**修复状态**: ⬜ 保持现状 (低优先级, 严格合规可后续修复)

---

### BUG 7 🔴→✅ 高 | FCVT.S.W i_mant_overflow 恒为 1 → 结果为正确值 2 倍 — 已修复

**文件**: `dev/rtl/FPU/fpu_cvt.sv` L255-258

**问题代码**:
```sv
wire [23:0] i_mant_rounded = {1'b1, i_frac_r} + i_round_up;
wire        i_mant_overflow = i_mant_rounded[23];
wire [22:0] i_final_frac   = i_mant_overflow ? i_mant_rounded[22:0] : i_mant_rounded[22:0];
wire [7:0]  i_final_exp    = i_mant_overflow ? (i_exp + 8'd1) : i_exp;
```

**问题**: `{1'b1, i_frac_r}` 是 24 位值, bit[23] 是隐含前导 1 (hidden bit), **恒为 1**。当 `i_round_up = 0` 时 (无舍入), `i_mant_rounded[23] = 1`, 因此 `i_mant_overflow = 1` **始终成立**。这导致 `i_final_exp = i_exp + 1` 对**所有**非零 int→float 转换生效, 使结果为正确值的 **2 倍**。

**示例**: FCVT.S.W 输入 42, 正确结果 42.0 = 0x42280000, 实际输出 84.0 = 0x43280000。

**发现过程**: 手工追踪 fpu_cvt.sv 组合逻辑时 `i_frac` 和 `i_exp` 计算正确, 但忽略了 `i_mant_overflow` 对 `i_final_exp` 的影响。Oracle 代理通过完整数据通路分析定位此 bug。

**修复方案** (已实施):
```sv
wire [24:0] i_mant_wide    = {1'b0, 1'b1, i_frac_r} + i_round_up;
wire        i_mant_overflow = i_mant_wide[24];      // 真正的进位输出
wire [23:0] i_mant_rounded = i_mant_wide[23:0];
wire [22:0] i_final_frac   = i_mant_rounded[22:0];  // 恒等, 简化原代码
wire [7:0]  i_final_exp    = i_mant_overflow ? (i_exp + 8'd1) : i_exp;
```

将加法扩展到 25 位, bit[24] 才是真正的进位输出 (仅当 1.111...1 + 1 = 10.000...0 时为 1)。

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 8 🔴→✅ 高 | FLW/FSW 地址计算恒为 0 — 已修复

**文件**: `dev/rtl/core/cpu_decode.sv` L338-340, L344

**问题代码**:
```sv
// alu_src2: FLW/FSW 未包含, 落入默认分支 rs2_value
assign alu_src2 = ... is_load ? imm_i : (is_store) ? imm_s : rs2_value;

// alu_control: FLW/FSW 未包含, 落入默认分支 16'b0
(inst_add | ... | is_load | is_store | ...) ? 16'b0001_0000_0000_0000 : ... 16'b0;
```

**问题**: FLW/FSW 不在 `alu_src2` 的 `imm_i`/`imm_s` 路径中, 也不在 `alu_control` 的 ADD 路径中。导致:
- `alu_src2 = rs2_value` (对 I/S 型指令, bits[24:20] 是立即数的一部分, 非寄存器索引)
- `alu_control = 16'b0` → ALU 结果选择器所有 sel 位为 0 → `alu_result = 0`
- FLW/FSW 的内存地址恒为 0, 无论 rs1 和 offset 为何值

**规范依据**: F 扩展 21.5 节 — FLW rd, offset(rs1) 地址 = rs1 + sign-extend(offset); FSW 类似。

**修复方案** (已实施):
```sv
// alu_src2: 增加 FLW/FSW 路径
assign alu_src2 = ... is_load ? imm_i :
                  is_flw  ? imm_i :    // ← 新增
                  (is_store) ? imm_s :
                  is_fsw  ? imm_s :    // ← 新增
                  rs2_value;

// alu_control: ADD 路径增加 FLW/FSW
(inst_add | ... | is_load | is_store | ... | is_flw | is_fsw) ? 16'b0001_0000_0000_0000 :
```

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 9 🔴→✅ 高 | F-ext CSR 地址未加入 is_m_csr — 已修复

**文件**: `dev/rtl/core/cpu_decode.sv`

**问题**: fflags(0x001)、frm(0x002)、fcsr(0x003) 未加入 `is_m_csr` 判断函数。导致 `CSRR x10, fflags` 和 `CSRW fflags, x0` 被判定为非法指令并触发 trap，CPU 无法读写浮点异常标志 CSR。

**规范依据**: F 扩展 21.2 节 — fflags/frm/fcsr 是标准浮点 CSR，机器模式必须可访问。

**修复方案**: 将 fflags/frm/fcsr 地址加入 `is_m_csr()` 函数。

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 10 🔴→✅ 高 | fflags_wen 未用 wb_valid 门控 — 已修复

**文件**: `dev/rtl/core/core_top.sv`

**问题代码**:
```sv
assign fflags_wen = (wb_fflags != 5'b0);  // 无 wb_valid 门控
```

**问题**: `fflags_wen` 仅检查 `wb_fflags != 0`，未检查 `wb_valid`。FPU 写回完成后，`mem_wb_bus_r` 保持旧值约 31 周期（直到下一条指令的写回），期间 `wb_fflags` 仍为非零旧值，导致 CSR 模块在非写回周期收到假 `fflags_wen` 脉冲，重复 OR 累加已写入的异常标志。

**修复方案**:
```sv
assign fflags_wen = wb_valid && (wb_fflags != 5'b0);
```

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 11 🔴→✅ 高 | f_abs_int 位宽不足导致 FCVT.W.S 大数截断 — 已修复

**文件**: `dev/rtl/FPU/fpu_cvt.sv`

**问题**: `f_abs_int` 仅 24 位，`f_abs_rounded` 仅 25 位。float→int 转换的左移路径（exp≥150 时）将浮点值左移到整数范围，但 24 位宽度无法容纳 32 位整数结果。例如 FCVT.W.S(2^31) 应返回 INT_MAX=0x7FFFFFFF，实际返回 0（bit 31 被截断丢失）。

**修复方案**: 将 `f_abs_int` 扩展为 32 位，`f_abs_rounded` 扩展为 33 位，确保左移路径不丢失高位。

**修复状态**: ✅ 已修复 (2026-06-04)

---

### BUG 12 🔴→✅ 高 | FSUB 结果符号错误 — 使用原始符号而非有效符号 — 已修复

**文件**: `dev/rtl/FPU/fpu_adder.sv`

**问题**: 当执行 FSUB 且 `|src2| > |src1|` 时，加法器内部 swap=1（交换操作数以大减小），但 `res_sign_sub` 使用原始符号 `s1_sign` 而非有效符号 `eff_sign_a`。这导致减法结果符号错误。

**示例**: FSUB 1.0 - 3.0 应返回 -2.0，但 swap 后实际计算 3.0 - 1.0 = 2.0，`res_sign_sub = s1_sign = 0`（正），结果为 +2.0 而非 -2.0。

**修复方案** (已实施):
```sv
wire eff_sign_a = swap ? eff_sign2 : s1_sign;
// res_sign_sub 使用有效符号而非原始符号
assign res_sign_sub = eff_sign_a;
```

**修复状态**: ✅ 已修复 (2026-06-05)

---

### BUG 13 🔴→✅ 高 | FCVT.W.S 有符号溢出检测误判 -2³¹ 为溢出 — 已修复

**文件**: `dev/rtl/FPU/fpu_cvt.sv`

**问题**: FCVT.W.S（float→signed int32）的溢出检测使用 OR 连接：`(abs > 0x7FFFFFFF) | (sign && abs > 0x80000000)`。当输入为 -2.0（float 值 -2.0，abs=2, sign=1）时，`abs > 0x80000000` 为 false，正确不溢出。但当输入恰好为 -2³¹（0xCF800000, abs=0x80000000）时，`abs > 0x80000000` 为 false（等于而非大于），也不溢出——这是正确的。然而，原代码实际使用的是 `(abs > 0x7FFF)` 与 `(sign && abs > 0x8000)` 的简化版本，由于位宽截断导致 -2³¹ 被误判为溢出（NV=1）。

**规范依据**: F 扩展 21.7 节 — FCVT.W.S 的合法输出范围是 [-2³¹, 2³¹-1]，-2³¹ (0x80000000) 是合法值，不应设置 NV。

**修复方案** (已实施):
```sv
// 改为 mux: 正数和负数使用不同溢出阈值
wire f_overflow = f_sign ? (f_abs_rounded > 32'h8000_0000) :
                              (f_abs_rounded > 32'h7FFF_FFFF);
```

**修复状态**: ✅ 已修复 (2026-06-05)

---

## 已知未修复问题

| 问题 | 文件 | 严重度 | 说明 |
|------|------|--------|------|
| fpu_multiply 极端下溢误报 OF | fpu_multiplier.sv | P3 | smallest_normal² → +0 时 fflags=OF+UF+NX（应为 UF+NX） |
| fpu_sqrt 次正规输入指数错误 | fpu_sqrt.sv | P3 | 次正规输入的 sqrt 结果指数偏小 |

---

## Phase 6 单元测试验证 ✅

| Testbench | 子测试 | 结果 | 覆盖范围 |
|-----------|--------|------|----------|
| tb_fpu_adder.sv | 30/30 | ✅ PASS | FADD/FSUB: 正常/特殊值/溢出/下溢/5种舍入 |
| tb_fpu_multiplier.sv | 13/13 | ✅ PASS | FMUL: 正常/符号/NaN/Inf/溢出/下溢/舍入 |
| tb_fpu_divider.sv | 12/12 | ✅ PASS | FDIV: 正常/符号/除零/NaN/Inf/溢出/下溢 |
| tb_fpu_sqrt.sv | 22/22 | ✅ PASS | FSQRT: 正常/负数/NaN/Inf/次正规/5种舍入 |
| tb_fpu_cvt.sv | 20/20 | ✅ PASS | FCVT.W.S/FCVT.WU.S/FCVT.S.W/FCVT.S.WU |
| tb_fpu_unit.sv | 24/24 | ✅ PASS | 全20种FPU操作+握手协议+flush |

**总计: 121 个子测试全部通过 ✅**

BUG 12/13 修复后 ISA 回归: isa_f_ext 26/26 ✅, isa_f_ext_special 24/24 ✅

---

## FPU 握手与时序验证（无问题 ✅）

| 检查项 | 结果 | 说明 |
|--------|------|------|
| FPU 握手协议 (req_valid/ready/result_valid/result_got) | ✅ | 与 MU 单元模式一致，2 周期握手时序正确 |
| fpu_active / mu_active 互斥 | ✅ | `!mu_active && !fpu_active` 条件正确防止同时发射 |
| fpu_result_got 清零时序 | ✅ | 每周期开头清零，与 result_valid 握手无竞争 |
| fflags_wen 组合逻辑到 CSR 时序 | ✅ | 源是寄存器输出，时钟沿采样稳定 |
| FLW/FSW 内存访问时序 | ✅ | 复用整数 load/store 状态机，FLW 走 load 路径，FSW 走 store 路径 |
| 流水线 stall/flush 对 FPU 的影响 | ⚠️ | flush 硬连线为 0（`fpu_unit` 的 `.flush(1'b0)`），异常/中断时 FPU 不会被冲刷，可能导致已完成的 FPU 结果写入错误的上下文。需后续验证 |

---

## MISA 验证 ✅

| 字段 | 旧值 | 新值 | 说明 |
|------|------|------|------|
| MXL [31:30] | 01 | 01 | XLEN=32 ✅ |
| F [5] | 0 | 1 | F 扩展已启用 ✅ |
| I [8] | 1 | 1 | I 扩展 ✅ |
| M [12] | 1 | 1 | M 扩展 ✅ |
| S [18] | 1 | 1 | S 扩展 ✅ |
| U [20] | 1 | 1 | U 扩展 ✅ |

---

## 修复优先级

| 优先级 | BUG | 影响范围 | 修复复杂度 | 状态 |
|--------|-----|----------|------------|------|
| P0 | BUG 2: FLW 双写 | 每次浮点加载都污染整数寄存器 | 低（1 行） | ✅ 已修复 |
| P0 | BUG 3+4: FMV.W.X / FCVT.S.W 源操作数错误 | 整数→浮点转换指令完全错误 | 中（加 mux + 确认 rs1_value 可用） | ✅ 已修复 |
| P0 | BUG 7: FCVT.S.W i_mant_overflow 恒为 1 | 所有 int→float 结果为正确值 2 倍 | 低（扩展加法位宽） | ✅ 已修复 |
| P0 | BUG 8: FLW/FSW 地址恒为 0 | 所有浮点 load/store 访问地址 0 | 低（decode 加 2 行） | ✅ 已修复 |
| P0 | BUG 9: F-ext CSR 地址未加入 is_m_csr | CSRR/CSRW fflags 判为非法指令 | 低（decode 加 3 个地址） | ✅ 已修复 |
| P0 | BUG 10: fflags_wen 未用 wb_valid 门控 | 写回后 ~31 周期假 fflags 写 | 低（加 1 个条件） | ✅ 已修复 |
| P0 | BUG 11: f_abs_int 位宽不足 | FCVT.W.S 大浮点数截断为 0 | 低（扩展位宽） | ✅ 已修复 |
| P0 | BUG 12: FSUB 结果符号错误 | FSUB 当 \|src2\|>\|src1\| 时结果符号反转 | 低（改用有效符号） | ✅ 已修复 |
| P0 | BUG 13: FCVT.W.S 溢出误判 -2³¹ | -2³¹ 被误判为溢出 (NV=1) | 低（改 mux 判断） | ✅ 已修复 |
| P1 | BUG 1: fflags 写冲突 | CSR 软件写与硬件异常同时发生时数据丢失 | 中（重构 fflags 写逻辑） | ✅ 已修复 |
| P2 | BUG 5: FMA 未实现 | 功能缺失，已有设计决策 | 高（R4 格式 + 3 源操作数） | ✅ 已注释 |
| P3 | BUG 6: f0 硬连线零 | 严格合规问题 | 低（移除 f0 特判） | ⬜ 低优先级 |

---

## 修复汇总

| BUG | 修复文件 | 修复方式 | 修复日期 |
|-----|----------|----------|----------|
| BUG 1 | cpu_csr.sv | 引入 fflags_sw_new/fflags_sw_wen, 合并写逻辑 | 2026-06-04 |
| BUG 2 | cpu_wb.sv | rf_wen 条件增加 `!is_flw` | 2026-06-04 |
| BUG 3+4 | cpu_execute.sv | 添加 fpu_src_is_int + fpu_src1_mux | 2026-06-04 |
| BUG 5 | cpu_decode.sv | 添加 FMA 未实现的设计决策注释 | 2026-06-04 |
| BUG 7 | fpu_cvt.sv | 24→25 位加法, i_mant_overflow = i_mant_wide[24] | 2026-06-04 |
| BUG 8 | cpu_decode.sv | alu_src2 增加 is_flw→imm_i, is_fsw→imm_s; alu_control ADD 路径增加 is_flw|is_fsw | 2026-06-04 |
| BUG 9 | cpu_decode.sv | fflags/frm/fcsr 地址加入 is_m_csr | 2026-06-04 |
| BUG 10 | core_top.sv | fflags_wen 加 wb_valid 门控 | 2026-06-04 |
| BUG 11 | fpu_cvt.sv | f_abs_int 24→32 位, f_abs_rounded 25→33 位 | 2026-06-04 |
| BUG 12 | fpu_adder.sv | res_sign_sub 改用有效符号 eff_sign_a | 2026-06-05 |
| BUG 13 | fpu_cvt.sv | 有符号溢出检测改为 mux: sign ? (abs>0x80000000) : (abs>0x7FFFFFFF) | 2026-06-05 |
| BUG 14 | tools/rv2coe.py | 统一输出改用 elf_all_to_bin() 包含 .text+.rodata+.data | 2026-06-05 |
| BUG 15 | tb_calculator.sv | 移除表达式尾部 8'h0, 调整 EXPRx_LEN | 2026-06-05 |

---

## BUG 14: rv2coe.py .rodata 段缺失

**发现日期**: 2026-06-05
**影响**: C 程序中所有字符串常量 (uart_puts, printf 等) 产生零输出
**严重性**: 高 — 完全阻断 C 程序的字符串输出功能

### 现象

- `uart_putc('H')` 正常输出 1 字节
- `uart_puts("Hi")` 输出 0 字节
- 汇编程序 (uart_hello.s) 正常 — 字符串在 .text 段

### 根因

`rv2coe.py` 的统一输出路径 (`-o`) 使用 `elf_text_to_bin()` 提取 ELF，该函数仅包含 `--only-section=.text`。C 编译器将字符串常量放入 `.rodata` 段，该段未被包含在 COE 文件中。

CPU 从 BRAM 读取 .rodata 地址时得到全零 (未初始化内存)，`while (*s)` 立即退出，`uart_puts` 返回而不输出任何字符。

### 修复

新增 `elf_all_to_bin()` 函数，使用 `objcopy -O binary` (无 `--only-section` 过滤) 提取所有可加载段。统一输出路径改用此函数。

```python
def elf_all_to_bin(args, elf_path, bin_path):
    run_cmd([args.objcopy, "-O", "binary", str(elf_path), str(bin_path)], args.verbose)
```

### 验证

- calc_debug6.coe: 170→171 words (多了 1 word 的 "Hi\0" 字符串数据)
- calculator.coe: 1712→1766 words (多了 54 words 的 .rodata)
- uart_puts("Hi") → 2 字节 "Hi" ✅

---

## BUG 15: tb_calculator 表达式 NUL 污染

**发现日期**: 2026-06-05
**影响**: 5 个测试表达式中 3 个被跳过 (乘法、减法、sqrt)
**严重性**: 中 — 不影响 RTL 正确性，仅影响 testbench 刺激

### 现象

calculator 仿真结果:
- 1+2=3 ✅, 3*4=12 ❌, 10-3=7 ❌, 8/2=4 ✅, sqrt(4)=2 ❌

规律: 每隔一个表达式失败，加法和除法通过但乘法和减法失败。

### 根因

testbench 表达式数组含尾部 NUL 终止符:

```systemverilog
expr0[0]="1"; expr0[1]="+"; expr0[2]="2"; expr0[3]="\n"; expr0[4]=8'h0;  // ← NUL
localparam EXPR0_LEN = 5;  // ← 包含 NUL 在内
```

TX 引擎按 `EXPRx_LEN` 发送字节，将 NUL (0x00) 作为第 5 个字节发送到 UART RX。`gets()` 在 `\n` 处 break，NUL 残留在 RX 缓冲区。下次 `gets()` 首字符读到 `\0`，加入缓冲区: `buf[0]='\0'`。calculator 的 `if (input_buf[0]=='\0') continue;` 判定为空行并跳过。

### 修复

移除表达式数组中的尾部 `8'h0`，将 `EXPRx_LEN` 减 1:

```systemverilog
expr0[0]="1"; expr0[1]="+"; expr0[2]="2"; expr0[3]="\n";
localparam EXPR0_LEN = 4;  // 仅含有效字符 + newline
```

### 验证

5/5 ALL TESTS PASSED: 1+2=3, 3*4=12, 10-3=7, 8/2=4, sqrt(4)=2 ✅
