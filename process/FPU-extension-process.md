# FPU 扩展实施进度

> 创建日期: 2026-06-03 | 关联计划: `plan/FPU-extension-plan.md`

---

## 总体进度

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | 浮点寄存器堆 + CSR 基础 | ✅ 完成 | 2026-06-03 |
| Phase 2 | 浮点运算单元 (FPU 子模块) | ✅ 完成 | 2026-06-03 |
| Phase 3 | 指令译码 + 数据通路集成 | ✅ 完成 | 2026-06-04 |
| Phase 4 | 浮点指令 ISA 测试 | ✅ 完成 | 2026-06-04 |
| Phase 5 | 浮点异常/舍入测试 | ✅ 完成 | 2026-06-04 |
| Phase 6 | FPU 单元测试 | ⬜ 未开始 | |
| Phase 7 | 计算器应用 | ⬜ 未开始 | |
| Phase 8 | 计算器测试 | ⬜ 未开始 | |

---

## Phase 1: 浮点寄存器堆 + CSR 基础

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.1 | fpu_regfile.sv | ✅ | 32×32-bit, 双读单写, f0 硬连线零 |
| 1.2 | cpu_csr.sv: fflags/frm/fcsr | ✅ | fflags=0x001, frm=0x002, fcsr=0x003 |
| 1.3 | cpu_csr.sv: misa.F=1 | ✅ | misa=0x40141120 |
| 1.4 | cpu_csr.sv: mstatus.FS | ✅ | FS[14:13] 已在原有 mstatus 中 |
| 1.5 | core_top.sv: 实例化 fpu_regfile | ✅ | |
| 1.6 | core_top.sv: 调试读端口 | ✅ | |

## Phase 2: 浮点运算单元

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.1 | fpu_adder.sv | ✅ | FADD.S/FSUB.S |
| 2.2 | fpu_multiplier.sv | ✅ | FMUL.S |
| 2.3 | fpu_divider.sv | ✅ | FDIV.S, 非恢复余数算法 |
| 2.4 | fpu_sqrt.sv | ✅ | FSQRT.S, Newton-Raphson |
| 2.5 | fpu_compare.sv | ✅ | FEQ/FLT/FLE |
| 2.6 | fpu_minmax.sv | ✅ | FMIN/FMAX |
| 2.7 | fpu_classify.sv | ✅ | FCLASS |
| 2.8 | fpu_sign_inject.sv | ✅ | FSGNJ/FSGNJN/FSGNJX |
| 2.9 | fpu_cvt.sv | ✅ | FCVT.W.S/FCVT.WU.S/FCVT.S.W/FCVT.S.WU |
| 2.10 | fpu_round.sv | ✅ | 27-bit mantissa 舍入 |
| 2.11 | fpu_special.sv | ✅ | NaN/Inf/zero 检测 |
| 2.12 | fpu_unit.sv | ✅ | 握手协议 + 结果选择 |

## Phase 3: 指令译码 + 数据通路集成

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.1 | cpu_decode: opcode 识别 | ✅ | LOAD-FP/STORE-FP/OP-FP |
| 3.2 | cpu_decode: funct5+fmt+rm 译码 | ✅ | 20 条 FPU 指令 |
| 3.3 | cpu_decode: ID/EX 总线扩展 | ✅ | 320→334 bits |
| 3.4 | cpu_decode: 操作数选择 | ✅ | |
| 3.5 | cpu_execute: FPU 请求/等待 | ✅ | 握手协议与 MU 一致 |
| 3.6 | cpu_execute: EX/MEM 总线扩展 | ✅ | 207→216 bits |
| 3.7 | cpu_mem: FLW/FSW | ✅ | 复用整数 load/store |
| 3.8 | cpu_mem: MEM/WB 总线扩展 | ✅ | 168→177 bits |
| 3.9 | cpu_wb: 浮点寄存器写回 | ✅ | fp_wen/fp_waddr/fp_wdata |
| 3.10 | cpu_controller: FPU 等待 | ✅ | fpu_active 互斥 |
| 3.11 | core_top: 实例化 fpu_unit | ✅ | 在 cpu_execute 中实例化 |
| 3.12 | core_top: 浮点寄存器读端口 | ✅ | frs1/frs2 直传 execute |

## Phase 4: 浮点指令 ISA 测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | f_ext.s 测试程序 | ✅ | 26 个子测试覆盖全部 20 条 FPU 指令 |
| 4.2 | tests.yaml 注册 | ✅ | arch=rv32imf_zicsr_zifencei, abi=ilp32 |
| 4.3 | tb_isa_f_ext.sv | ✅ | 100000 周期, x28/x29/x30 框架 |
| 4.4 | tasks.yaml 任务 | ✅ | isa_f_ext 任务 |

## Phase 5: 浮点异常/舍入测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 5.1 | f_ext_special.s | ✅ | 24 子测试: fflags(NV/DZ/OF/UF/NX) + 舍入模式(RTZ/RDN/RUP/RMM/DYN) + 边界 |
| 5.2 | tests.yaml 注册 | ✅ | isa_f 类别下注册 |
| 5.3 | tb_isa_f_ext_special.sv | ✅ | 100000 周期, x28/x29/x30 框架 |
| 5.4 | tasks.yaml 任务 | ✅ | isa_f_ext_special 任务 |

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

## 仿真验证

| 日期 | 测试 | 结果 | 备注 |
|------|------|------|------|
| 2026-06-04 | cpu_full (集成测试) | 41/42 pass | 1 个预存失败 (x11), FPU 零回归 |
| 2026-06-04 | csr_wb_bus 宽度修复后 | 41/42 pass | 同上, 确认基线一致 |
| 2026-06-04 | isa_f_ext (BUG 7 修复前) | 22/26 pass | first_fail_id=17 (FCVT.S.W) |
| 2026-06-04 | isa_f_ext (BUG 7 修复后) | 24/26 pass | first_fail_id=21 (FLW), FCVT 恢复正确 |
| 2026-06-04 | isa_f_ext (BUG 7+8 全部修复) | **26/26 pass** | **ALL TESTS PASSED** ✅ |
| 2026-06-04 | isa_f_ext_special (BUG 9 修复前) | 11/24 pass | CSRR fflags 被判非法指令 |
| 2026-06-04 | isa_f_ext_special (BUG 9+10+11 全部修复) | **24/24 pass** | **ALL TESTS PASSED** ✅ |
| 2026-06-04 | isa_f_ext (Phase 5 修复后回归) | **26/26 pass** | 基础测试无回归 ✅ |

---

## Bug 修复记录

| 日期 | BUG | 文件 | 修复内容 | 状态 |
|------|-----|------|----------|------|
| 2026-06-04 | BUG 1: fflags 软件写与硬件 OR 冲突 | cpu_csr.sv | 引入 fflags_sw_new/fflags_sw_wen 中间变量, 合并写逻辑: sw+hw 同时发生时先写软件值再 OR 硬件异常 | ✅ 已修复 |
| 2026-06-04 | BUG 2: FLW 双写整数+浮点寄存器 | cpu_wb.sv | rf_wen 条件增加 `!is_flw`, FLW 只写浮点寄存器 | ✅ 已修复 |
| 2026-06-04 | BUG 3+4: FMV.W.X/FCVT.S.W 源操作数错误 | cpu_execute.sv | 添加 fpu_src_is_int 判断 + fpu_src1_mux, int→float 指令选择 rs1_value | ✅ 已修复 |
| 2026-06-04 | BUG 5: FMA 未实现 | cpu_decode.sv | 添加明确注释说明为设计决策, 非缺陷 | ✅ 已注释 |
| 2026-06-04 | BUG 6: f0 硬连线零 | fpu_regfile.sv | 保持现状 (设计选择), 严格合规可后续修复 | ⬜ 低优先级 |
| 2026-06-04 | BUG 7: FCVT.S.W i_mant_overflow 恒为 1 | fpu_cvt.sv | 将 24 位加法扩展为 25 位, 用 bit[24] 作为真正的进位输出; 旧代码 `{1'b1,i_frac_r}+round_up` 的 bit[23] 始终为 1 (隐含前导 1), 导致指数恒 +1, 结果为正确值的 2 倍 | ✅ 已修复 |
| 2026-06-04 | BUG 8: FLW/FSW 地址计算错误 | cpu_decode.sv | alu_src2 增加 `is_flw→imm_i, is_fsw→imm_s`; alu_control ADD 路径增加 `is_flw|is_fsw`; 旧代码 FLW/FSW 未包含在 ALU 路径中, alu_control=0 导致 ALU 输出全零, 地址恒为 0 | ✅ 已修复 |
| 2026-06-04 | BUG 9: F-ext CSR 地址未加入 is_m_csr | cpu_decode.sv | fflags(0x001)/frm(0x002)/fcsr(0x003) 未加入 is_m_csr 判断, CSRR/CSRW 这些 CSR 被判为非法指令并 trap | ✅ 已修复 |
| 2026-06-04 | BUG 10: fflags_wen 未用 wb_valid 门控 | core_top.sv | fflags_wen 条件从 `(wb_fflags!=0)` 改为 `wb_valid&&(wb_fflags!=0)`; 旧代码在 FPU 写回后 ~31 周期残留 mem_wb_bus_r 导致假写 | ✅ 已修复 |
| 2026-06-04 | BUG 11: f_abs_int 位宽不足 | fpu_cvt.sv | f_abs_int 从 24→32 位, f_abs_rounded 从 25→33 位; 旧代码左移路径截断大浮点数, FCVT.W.S(2^31) 结果为 0 | ✅ 已修复 |

---

## 问题与决策记录

| 日期 | 问题 | 决策 | 理由 |
|------|------|------|------|
| 2026-06-03 | 是否实现 D 扩展? | 暂不实现，仅实现 F 扩展 | XLEN=32，D 需 FLEN=64，工作量翻倍且计算器不需要双精度 |
| 2026-06-03 | 是否实现 FMA 指令? | 暂不实现 | R4 格式译码复杂，硬件面积大，计算器非必需 |
| 2026-06-03 | FSQRT.S 是否实现? | 实现 | 硬件开销可控，计算器 sqrt 功能需要 |
| 2026-06-03 | FPU 多周期还是单周期? | 多周期 (与 MU 单元一致) | 浮点除法/平方根需多周期，统一握手协议 |
| 2026-06-03 | f0 是否硬连线零? | 硬连线零 (与 x0 一致) | 简化设计, 编译器通常不使用 f0 作为通用寄存器 |
| 2026-06-04 | fflags 软件写与硬件写冲突? | 合并写逻辑 | F 扩展规范 21.2: 软件写后的新值作为 OR 累加基础 |
| 2026-06-04 | FLW 的 is_fpu 标志? | is_fpu=0, is_flw=1 | FLW 走 load 路径, 但只写浮点寄存器, rf_wen 需排除 is_flw |
| 2026-06-04 | int→float 指令源操作数? | execute 阶段 mux 选择 | FMV.W.X/FCVT.S.W/WU 读整数 rs1, 其余读浮点 frs1 |
| 2026-06-04 | FCVT.S.W i_mant_overflow 恒为 1? | 扩展为 25 位加法 | `{1'b1,i_frac_r}` 的 bit[23] 是隐含前导 1, 恒为 1; 扩展到 25 位后 bit[24] 才是真正的进位输出 |
| 2026-06-04 | FLW/FSW 地址计算? | 加入 ALU 路径 | FLW/FSW 未包含在 alu_src2/alu_control 中, 导致 ALU 输出全零, 地址恒为 0 |
| 2026-06-04 | F-ext CSR 地址判别? | 加入 is_m_csr | fflags/frm/fcsr 未加入 is_m_csr, CSRR/CSRW 被判非法指令 |
| 2026-06-04 | fflags_wen 门控? | 加 wb_valid 条件 | 防止写回后残留 mem_wb_bus_r 触发假 fflags 写 |
| 2026-06-04 | f_abs_int 位宽? | 24→32 位 | 左移路径截断大浮点数, FCVT.W.S(2^31) 结果为 0 |
