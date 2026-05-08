# ALU 乘除法器独立与 ALU 重构 — 过程记录

## 1. 变更概述

将 `booth_multiplier` 和 `non_restoring_divider` 从 `alu_32bit` 内部提取为独立 `MU` 模块，
ALU 重构为纯组合单周期模块，移除握手协议接口。`cpu_execute` 对单周期运算直接获取结果，
仅乘除法走 MU 握手路径。

## 2. 变更前架构

```
alu_32bit (多周期 + 握手)
├── booth_multiplier      (嵌入)
├── non_restoring_divider (嵌入)
├── cla_adder / logic_unit / shifter / lui / alu_result_selector
└── 握手协议: req_valid / alu_ready / result_valid / result_got / flush

cpu_execute → alu_32bit (所有运算均经握手)
```

所有运算（含 ADD/SUB 等单周期操作）均需经过握手协议，EX 阶段至少 2 拍才能完成。

## 3. 变更后架构

```
alu_32bit (纯组合，单周期)
├── cla_adder / logic_unit / shifter / lui / alu_result_selector
└── 接口: alu_control, src1, src2 → result (组合直出)

MU/mu_unit (多周期 + 握手)
├── booth_multiplier      (从 ALU 移入)
├── non_restoring_divider (从 ALU 移入)
└── 握手协议: req_valid / mu_ready / result_valid / result_got / flush

cpu_execute
├── alu_32bit (单周期运算: 直接获取结果, exe_done=1 同拍)
└── mu_unit   (乘除法: 握手等待 result_valid)
```

单周期运算在 EX 阶段 1 拍完成，CPI 降低。

## 4. 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `dev/rtl/MU/mu_unit.v` | 乘除法独立模块，含握手协议 |
| 移动 | `dev/rtl/ALU/booth_multiplier.v` → `dev/rtl/MU/booth_multiplier.v` | 乘法器移至 MU 文件夹 |
| 移动 | `dev/rtl/ALU/non_restoring_divider.v` → `dev/rtl/MU/non_restoring_divider.v` | 除法器移至 MU 文件夹 |
| 重写 | `dev/rtl/ALU/alu_32bit.v` | 移除 clk/reset/握手/乘除法实例，变为纯组合模块 |
| 重写 | `dev/rtl/ALU/alu_result_selector.v` | 移除 mul_result/div_result 输入 |
| 重写 | `dev/rtl/core/cpu_execute.v` | 实例化单周期 ALU + MU 单元，单周期运算直接完成 |
| 重写 | `dev/tb/ALU/tb_alu_cpu_integration.v` | 适配单周期 ALU 接口，测试组合运算 |
| 新建 | `dev/tb/ALU/tb_mu_unit.v` | MU 单元握手协议测试 |
| 删除 | `dev/rtl/ALU/booth_multiplier.v` | 已移至 MU/ |
| 删除 | `dev/rtl/ALU/non_restoring_divider.v` | 已移至 MU/ |

## 5. 接口变更详情

### alu_32bit

```verilog
// 变更前
module alu_32bit(
    input clk, input reset,
    input [15:0] alu_control, input [31:0] src1, input [31:0] src2,
    input req_valid, input flush, input result_got,
    output [31:0] result, output alu_busy, output alu_ready,
    output result_valid, output illegal_op, output div_by_zero
);

// 变更后
module alu_32bit(
    input  [15:0] alu_control,
    input  [31:0] src1,
    input  [31:0] src2,
    output [31:0] result
);
```

### mu_unit (新增)

```verilog
module mu_unit(
    input clk, input reset,
    input [1:0] mu_control,   // 2'b01=MUL, 2'b10=DIV
    input [31:0] src1, input [31:0] src2,
    input req_valid, input flush, input result_got,
    output [31:0] result, output mu_busy, output mu_ready,
    output result_valid, output div_by_zero
);
```

### cpu_execute 关键逻辑变更

```verilog
// 变更前: 所有运算走握手
if (!exe_active && exe_valid && !exe_seen_valid) begin
    if (use_fixed_wb) begin
        // LUI: 立即完成
    end else begin
        req_valid <= 1'b1;    // 发送握手请求
        exe_active <= 1'b1;   // 等待 result_valid
    end
end

// 变更后: 单周期运算直接完成，仅乘除法走握手
if (!mu_active && exe_valid && !exe_seen_valid) begin
    exe_seen_valid <= 1'b1;
    if (use_fixed_wb) begin
        // LUI: 立即完成 (不变)
    end else if (is_mu_op) begin
        mu_req_valid <= 1'b1;  // 乘除法: 走 MU 握手
        mu_active <= 1'b1;
    end else begin
        result_reg <= alu_result;  // 单周期: 直接获取结果
        done_reg <= 1'b1;          // 同拍完成
    end
end
```

## 6. 仿真验证结果

| 测试 | 结果 |
|------|------|
| ALU 单周期测试 (tb_alu_cpu_integration) | 12 PASS |
| MU 单元测试 (tb_mu_unit) | 9 PASS |
| 除法器测试 (tb_non_restoring_divider) | 11 PASS |
| CPU 全功能测试 (tb_simple_cpu_top) | 34 PASS |
| AHB 总线测试 (tb_ahb_bus) | 3 PASS |
| LED 走马灯测试 (tb_led_marquee) | 16 PASS |

全部 **85 项检查 PASS**，无 FAIL。

## 7. 收益分析

| 指标 | 变更前 | 变更后 |
|------|--------|--------|
| ADD/SUB 等 EX 周期 | 2 拍 (握手) | 1 拍 (直出) |
| ALU 接口复杂度 | 11 端口 (含握手) | 4 端口 (纯组合) |
| 乘除法路径 | 嵌入 ALU | 独立 MU 模块 |
| RV32M 扩展就绪 | 需重构 | MU 已独立，可直接接入 |
| RV32M 已实现 | — | 8 条 M 指令全流程验证通过 |

## 8. RV32M 扩展实现 — 过程记录

### 8.1 变更概述

实现 RV32M 扩展全部 8 条指令：MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU。
指令格式：R-type, funct7=0000001, opcode=0110011, funct3 区分操作。

### 8.2 关键设计决策

| 决策 | 说明 |
|------|------|
| `mu_funct3[2:0]` | 直接映射指令 funct3 (000=MUL…111=REMU)，取代原 2-bit `mu_control` |
| `is_mu` 独立标志 | `is_alu` 不包含 M 指令；`wb_we = is_alu \| is_jal_like \| is_csr \| is_mu` |
| Booth A/M 33 位 | 修复 INT_MIN*2 等边界：32-bit 累加器溢出导致 MULH 上半错误 |
| MULHU 修正 | `product[63:32] + (src2[31]?src1:0) + (src1[31]?src2:0)`，CLA 加法器 |
| MULHSU 修正 | `product[63:32] + (src2[31]?src1:0)`，CLA 加法器 |
| DIVU/REMU | 除法器增加 `is_unsigned` 输入，覆盖 abs mux select，跳过 INT_MIN/-1 检查 |
| 无符号大除数 | `is_unsigned && divisor[31]` → 商为 0 或 1，直接计算 |
| 除零 | RISC-V spec：有符号/无符号均返回 quotient=0xFFFFFFFF |

### 8.3 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 修改 | `dev/rtl/MU/booth_multiplier.v` | A/M 扩展至 33 位，乘法运算 33-bit，product={A[31:0],Q} |
| 修改 | `dev/rtl/MU/non_restoring_divider.v` | 增加 `is_unsigned` 输入，无符号大除数特殊处理，除零返回 0xFFFFFFFF |
| 重写 | `dev/rtl/MU/mu_unit.v` | 3-bit `mu_funct3`，8 种 M 操作，CLA 修正逻辑 |
| 修改 | `dev/rtl/core/cpu_decode.v` | M 指令识别，`is_mu`/`mu_funct3`，`id_exe_bus` 扩展至 320 位 |
| 修改 | `dev/rtl/core/cpu_execute.v` | 解包 `is_mu`/`mu_funct3`，传递 `mu_funct3` 至 mu_unit |
| 修改 | `dev/rtl/core/core_top.v` | 320 位 `id_exe_bus`，更新位索引 |
| 修改 | `dev/rtl/core/cpu_csr_interface.v` | 320 位总线，更新位索引 |
| 修改 | `dev/rtl/core/cpu_trap_csr.v` | 320 位总线宽度 |
| 重写 | `dev/tb/ALU/tb_mu_unit.v` | 3-bit 接口，8 种 M 操作测试，42 项检查 |
| 修改 | `dev/tb/ALU/tb_non_restoring_divider.v` | `is_unsigned`，`check_divu`，21 项检查 |
| 修改 | `dev/program_source/cpu_test.s` | 添加 8 条 M 指令全流程测试，结果存入 mem[0x10-0x2C] |
| 修改 | `dev/program_source/Makefile` | ARCH 改为 rv32im_zicsr |
| 修改 | `dev/tb/tb_simple_cpu_top.v` | 添加 8 项 mem 检查，更新 x5/x6/x7 预期值 |

### 8.4 仿真验证结果

| 测试 | 结果 |
|------|------|
| ALU 单周期测试 (tb_alu_cpu_integration) | 12 PASS |
| MU 单元测试 (tb_mu_unit) | 42 PASS |
| 除法器测试 (tb_non_restoring_divider) | 21 PASS |
| CPU 全功能测试 (tb_simple_cpu_top) | 42 PASS |
| AHB 总线测试 (tb_ahb_bus) | 3 PASS |
| LED 走马灯测试 (tb_led_marquee) | 16 PASS |

全部 **136 项检查 PASS**，无 FAIL。

## 9. 后续工作

- **MU flush 下沉**: 当前 flush 仅作用于 mu_unit 顶层状态，可扩展到子模块内部以降低无效计算开销。
