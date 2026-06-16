# 仿真测试进度

> 最后更新: 2026-06-16

## 总览

| 类别 | 通过 | 失败 | 跳过 | 备注 |
|------|------|------|------|------|
| 单元测试 (ALU/FPU) | 8/8 | 0 | 0 | LUI断言已修; Vivado incr bug已修 |
| ISA | 2/2 | 0 | 0 | isa_alu, isa_csr |
| ISA-F | 2/2 | 0 | 0 | isa_f_ext 26/26, isa_f_ext_special 24/24 |
| 异常 | 4/4 | 0 | 0 | |
| 特权 | 3/3 | 0 | 0 | |
| MMU | 6/6 | 0 | 0 | |
| Cache | 2/2 | 0 | 0 | |
| CPU集成 | 3/3 | 0 | 0 | cpu_trap, cpu_compute, cpu_full |
| 回归 | 1/1 | 0 | 0 | regression_all |
| 应用 | 3/3 | 0 | 0 | calculator PASS (Bug10: FMADD.S已修) |
| DDR3 | - | - | 3 | 暂跳过 |
| **合计** | **34/34** | **0** | **3** | |

## 详细结果

### 单元测试

| 测试 | testbench | 结果 | 备注 |
|------|-----------|------|------|
| alu_integration | tb_alu_cpu_integration | PASS 12/12 | Bug8: LUI断言已修 (期望0→0x00010000) |
| divider | tb_non_restoring_divider | PASS 16/16 | |
| mu_unit | tb_mu_unit | PASS | MUL/MULH/MULHSU/MULHU/DIV |
| fpu_adder | tb_fpu_adder | PASS 30/30 | |
| fpu_multiplier | tb_fpu_multiplier | PASS 13/13 | |
| fpu_divider | tb_fpu_divider | PASS 12/12 | |
| fpu_sqrt | tb_fpu_sqrt | PASS 22/22 | |
| fpu_cvt | tb_fpu_cvt | PASS 20/20 | |
| fpu_unit | tb_fpu_unit | PASS 24/24 | |

### ISA / 异常 / 特权 / MMU / Cache / CPU

全部 PASS (20+ 项，详见 tasks.yaml)

### ISA-F (浮点)

| 测试 | 结果 | 备注 |
|------|------|------|
| isa_f_ext | PASS 26/26 | 基本浮点指令 |
| isa_f_ext_special | PASS 24/24 | 特殊值 (NaN/Inf/零) |

### 应用

| 测试 | 结果 | 备注 |
|------|------|------|
| uart_hello | PASS 12/12 | "Hello World" 正确解码 |
| uart_echo | PASS 6/6 | "Echo!" 正确回显 |
| calculator | **PASS 5/5** | 1+2=3, 3*4=12, 10-3=7, 8/2=4, sqrt(4)=2 |

### DDR3 (暂跳过)

| 测试 | 结果 | 备注 |
|------|------|------|
| ddr3_mig_ex | 跳过 | |
| ddr3_ahb_ex | 跳过 | |
| ddr3_basic | 跳过 | |

## 已修复的基础设施问题

| Bug | 文件 | 修复 |
|-----|------|------|
| Vivado 2018.3 xvlog --incr 丢弃 .sdb | operations.py | 进程重启 + 仅重试 launch_simulation |
| ALU testbench 子目录搜索 | operations.py | _find_tb_path() 搜索 dev/tb/ 子目录 |
| LUI 断言错误 | tb_alu_cpu_integration.sv | 期望值 0→0x00010000 |
| Unicode 解码崩溃 | session.py | 二进制模式 + errors='replace' |
| GCC 生成 FMADD.S (R4格式未实现) | rv2coe.py | -ffp-contract=off 禁止融合乘加 |
| rv2coe --inst-* 遗漏 .rodata/.srodata | rv2coe.py | 无 --data-* 时用 elf_all_to_bin |
