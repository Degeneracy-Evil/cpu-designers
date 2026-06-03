# FPU 扩展实施进度

> 创建日期: 2026-06-03 | 关联计划: `plan/FPU-extension-plan.md`

---

## 总体进度

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | 浮点寄存器堆 + CSR 基础 | ⬜ 未开始 | |
| Phase 2 | 浮点运算单元 (FPU 子模块) | ⬜ 未开始 | |
| Phase 3 | 指令译码 + 数据通路集成 | ⬜ 未开始 | |
| Phase 4 | 浮点指令 ISA 测试 | ⬜ 未开始 | |
| Phase 5 | 浮点异常/舍入测试 | ⬜ 未开始 | |
| Phase 6 | FPU 单元测试 | ⬜ 未开始 | |
| Phase 7 | 计算器应用 | ⬜ 未开始 | |
| Phase 8 | 计算器测试 | ⬜ 未开始 | |

---

## Phase 1: 浮点寄存器堆 + CSR 基础

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.1 | fpu_regfile.sv | ⬜ | |
| 1.2 | cpu_csr.sv: fflags/frm/fcsr | ⬜ | |
| 1.3 | cpu_csr.sv: misa.F=1 | ⬜ | |
| 1.4 | cpu_csr.sv: mstatus.FS | ⬜ | |
| 1.5 | core_top.sv: 实例化 fpu_regfile | ⬜ | |
| 1.6 | core_top.sv: 调试读端口 | ⬜ | |

## Phase 2: 浮点运算单元

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.1 | fpu_adder.sv | ⬜ | |
| 2.2 | fpu_multiplier.sv | ⬜ | |
| 2.3 | fpu_divider.sv | ⬜ | |
| 2.4 | fpu_sqrt.sv | ⬜ | |
| 2.5 | fpu_compare.sv | ⬜ | |
| 2.6 | fpu_minmax.sv | ⬜ | |
| 2.7 | fpu_classify.sv | ⬜ | |
| 2.8 | fpu_sign_inject.sv | ⬜ | |
| 2.9 | fpu_cvt.sv | ⬜ | |
| 2.10 | fpu_round.sv | ⬜ | |
| 2.11 | fpu_special.sv | ⬜ | |
| 2.12 | fpu_unit.sv | ⬜ | |

## Phase 3: 指令译码 + 数据通路集成

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.1 | cpu_decode: opcode 识别 | ⬜ | |
| 3.2 | cpu_decode: funct5+fmt+rm 译码 | ⬜ | |
| 3.3 | cpu_decode: ID/EX 总线扩展 | ⬜ | |
| 3.4 | cpu_decode: 操作数选择 | ⬜ | |
| 3.5 | cpu_execute: FPU 请求/等待 | ⬜ | |
| 3.6 | cpu_execute: EX/MEM 总线扩展 | ⬜ | |
| 3.7 | cpu_mem: FLW/FSW | ⬜ | |
| 3.8 | cpu_mem: MEM/WB 总线扩展 | ⬜ | |
| 3.9 | cpu_wb: 浮点寄存器写回 | ⬜ | |
| 3.10 | cpu_controller: FPU 等待 | ⬜ | |
| 3.11 | core_top: 实例化 fpu_unit | ⬜ | |
| 3.12 | core_top: 浮点寄存器读端口 | ⬜ | |

## Phase 4: 浮点指令 ISA 测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | f_ext.s 测试程序 | ⬜ | |
| 4.2 | tests.yaml 注册 | ⬜ | |
| 4.3 | tb_isa_f_ext.sv | ⬜ | |
| 4.4 | tasks.yaml 任务 | ⬜ | |

## Phase 5: 浮点异常/舍入测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 5.1 | f_ext_special.s | ⬜ | |
| 5.2 | tests.yaml 注册 | ⬜ | |
| 5.3 | tb_isa_f_ext_special.sv | ⬜ | |
| 5.4 | tasks.yaml 任务 | ⬜ | |

## Phase 6: FPU 单元测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 6.1 | tb_fpu_adder.sv | ⬜ | |
| 6.2 | tb_fpu_multiplier.sv | ⬜ | |
| 6.3 | tb_fpu_divider.sv | ⬜ | |
| 6.4 | tb_fpu_sqrt.sv | ⬜ | |
| 6.5 | tb_fpu_cvt.sv | ⬜ | |
| 6.6 | tb_fpu_unit.sv | ⬜ | |

## Phase 7: 计算器应用

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 7.1 | stdio.c | ⬜ | |
| 7.2 | stdio.h | ⬜ | |
| 7.3 | ftoa.c | ⬜ | |
| 7.4 | atof.c | ⬜ | |
| 7.5 | math.c | ⬜ | |
| 7.6 | math.h | ⬜ | |
| 7.7 | calculator.c | ⬜ | |
| 7.8 | calculator.s (如需) | ⬜ | |

## Phase 8: 计算器测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 8.1 | tb_calculator.sv | ⬜ | |
| 8.2 | tasks.yaml 任务 | ⬜ | |

---

## 问题与决策记录

| 日期 | 问题 | 决策 | 理由 |
|------|------|------|------|
| 2026-06-03 | 是否实现 D 扩展? | 暂不实现，仅实现 F 扩展 | XLEN=32，D 需 FLEN=64，工作量翻倍且计算器不需要双精度 |
| 2026-06-03 | 是否实现 FMA 指令? | 暂不实现 | R4 格式译码复杂，硬件面积大，计算器非必需 |
| 2026-06-03 | FSQRT.S 是否实现? | 实现 | 硬件开销可控，计算器 sqrt 功能需要 |
| 2026-06-03 | FPU 多周期还是单周期? | 多周期 (与 MU 单元一致) | 浮点除法/平方根需多周期，统一握手协议 |
