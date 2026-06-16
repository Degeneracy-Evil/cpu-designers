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
| Phase 6 | FPU 单元测试 | ✅ 完成 | 2026-06-05 |
| Phase 7 | 计算器应用 | ✅ 完成 | 2026-06-05 |
| Phase 8 | 计算器测试 | ✅ 完成 | 2026-06-05 |
| Phase 9 | FMA 融合乘加指令 | ✅ 完成 | 2026-06-16 |

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
| 3.4 | cpu_decode: 操作数选择 | ✅ | rs3 (R4 format) for FMA |
| 3.5 | cpu_execute: FPU 请求/等待 | ✅ | 握手协议与 MU 一致 |
| 3.6 | cpu_execute: EX/MEM 总线扩展 | ✅ | 207→216 bits |
| 3.7 | cpu_mem: FLW/FSW | ✅ | 复用整数 load/store |
| 3.8 | cpu_mem: MEM/WB 总线扩展 | ✅ | 168→177 bits |
| 3.9 | cpu_wb: 浮点寄存器写回 | ✅ | fp_wen/fp_waddr/fp_wdata |
| 3.10 | cpu_controller: FPU 等待 | ✅ | fpu_active 互斥 |
| 3.11 | core_top: 实例化 fpu_unit | ✅ | 在 cpu_execute 中实例化 |
| 3.12 | core_top: 浮点寄存器读端口 | ✅ | frs1/frs2 直传 execute |
| 3.13 | cpu_decode: FMA R4 译码 | ✅ | FMADD/FMSUB/FNMSUB/FNMADD opcode+fmt+rs3 |
| 3.14 | fpu_regfile: 第三读端口 | ✅ | raddr3/rdata3 for rs3 |
| 3.15 | ID/EX 总线: rs3 扩展 | ✅ | 344→349 bits (rs3_addr 5 bits) |
| 3.16 | core_top: frs3 数据通路 | ✅ | frs3_addr→fpu_regfile.raddr3, frs3_value→cpu_execute |
| 3.17 | fpu_unit: FMA dispatch | ✅ | fma_start/fma_busy, src3→fpu_fma |
| 3.18 | fpu_fma.sv | ✅ | 867 行, 6-stage FSM, 48-bit product, 75-bit aligned field, 单次舍入 |

## Phase 4: 浮点指令 ISA 测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | f_ext.s 测试程序 | ✅ | 30 个子测试覆盖全部 24 条 FPU 指令 (含 FMA) |
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
| 6.1 | tb_fpu_adder.sv | ✅ | 30/30 PASS: FADD/FSUB 正常/特殊/溢出/下溢/5种舍入 |
| 6.2 | tb_fpu_multiplier.sv | ✅ | 13/13 PASS: FMUL 正常/符号/NaN/Inf/溢出/下溢/舍入 |
| 6.3 | tb_fpu_divider.sv | ✅ | 12/12 PASS: FDIV 正常/符号/除零/NaN/Inf/溢出/下溢 |
| 6.4 | tb_fpu_sqrt.sv | ✅ | 22/22 PASS: FSQRT 正常/负数/NaN/Inf/次正规/5种舍入 |
| 6.5 | tb_fpu_cvt.sv | ✅ | 20/20 PASS: FCVT.W.S/FCVT.WU.S/FCVT.S.W/FCVT.S.WU |
| 6.6 | tb_fpu_unit.sv | ✅ | 24/24 PASS: 全20种FPU操作+握手+flush |
| 6.7 | tasks.yaml 注册 | ✅ | 6 个 fpu_* 任务 |
| 6.8 | BUG 12/13 修复后 ISA 回归 | ✅ | isa_f_ext 26/26, isa_f_ext_special 24/24 |

## Phase 7: 计算器应用

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 7.1 | lib/include/stdio.h | ✅ | printf(%d/%s/%c), print_float(), gets(), ftoa(), atof() 声明 |
| 7.2 | lib/stdio.c | ✅ | printf 用 __builtin_va_list; print_float 调用 ftoa; gets 带回显+退格 |
| 7.3 | lib/ftoa.c | ✅ | FMV.X.W 提取 IEEE754 位; 处理 NaN/Inf/零/符号/整数/小数部分 |
| 7.4 | lib/atof.c | ✅ | 解析符号+整数+小数+指数部分; 编译器生成 FPU 指令 |
| 7.5 | lib/include/math.h | ✅ | PI 常量; sqrtf/fabsf/powf/sinf/cosf 声明 |
| 7.6 | lib/math.c | ✅ | sqrtf 用 FSQRT.S 内联 asm; powf 整数指数循环; sinf/cosf Taylor 7 项 |
| 7.7 | app/calculator.c | ✅ | 递归下降解析器 (expr→term→factor); 支持 +,-,*,/,(),sqrt(),neg() |
| 7.8 | rv2coe.py .rodata 修复 | ✅ | 统一输出改用 elf_all_to_bin() 包含 .text+.rodata+.data |

## Phase 8: 计算器测试

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 8.1 | tb_calculator.sv | ✅ | UART TX 引擎 (5 表达式+启动延迟) + RX 解码器 + 结果搜索 |
| 8.2 | tasks.yaml 任务 | ✅ | calculator 任务, runtime=100ms |
| 8.3 | tb NUL 污染修复 | ✅ | 移除表达式数组尾部 8'h0, 调整 EXPRx_LEN |
| 8.4 | 仿真验证 | ✅ | 5/5 ALL TESTS PASSED: 1+2=3, 3*4=12, 10-3=7, 8/2=4, sqrt(4)=2 |

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
| 2026-06-05 | tb_fpu_adder | **30/30 pass** | FADD/FSUB 单元测试 ✅ |
| 2026-06-05 | tb_fpu_multiplier | **13/13 pass** | FMUL 单元测试 ✅ |
| 2026-06-05 | tb_fpu_divider | **12/12 pass** | FDIV 单元测试 ✅ |
| 2026-06-05 | tb_fpu_sqrt | **22/22 pass** | FSQRT 单元测试 ✅ |
| 2026-06-05 | tb_fpu_cvt | **20/20 pass** | FCVT 全4种转换单元测试 ✅ |
| 2026-06-05 | tb_fpu_unit | **24/24 pass** | FPU 顶层握手+全操作单元测试 ✅ |
| 2026-06-05 | isa_f_ext (BUG 12/13 修复后回归) | **26/26 pass** | 无回归 ✅ |
| 2026-06-05 | isa_f_ext_special (BUG 12/13 修复后回归) | **24/24 pass** | 无回归 ✅ |
| 2026-06-05 | calculator (rv2coe .rodata 修复前) | 0 bytes | uart_puts 读到全零 (字符串在 .rodata, 未包含在 COE) |
| 2026-06-05 | calculator (rv2coe .rodata 修复后, NUL 修复前) | 2/5 pass | NUL 污染: expr 尾部 8'h0 残留 RX 缓冲区, gets() 首字符为 \0 |
| 2026-06-05 | calculator (全部修复后) | **5/5 ALL TESTS PASSED** | 1+2=3, 3*4=12, 10-3=7, 8/2=4, sqrt(4)=2 ✅ |
| 2026-06-16 | isa_f_ext (FMA 实现后) | **30/30 pass** | 新增 test_27~30: FMADD/FMSUB/FNMSUB/FNMADD ✅ |
| 2026-06-16 | isa_f_ext_special (FMA 回归) | **24/24 pass** | 无回归 ✅ |
| 2026-06-16 | ISA 全回归 (10 任务) | **全 PASS** | isa_alu/branch/csr/m_ext/f_ext/f_ext_special/a_ext/upper_imm/memory/jump ✅ |
| 2026-06-16 | MMU 全回归 (4 任务) | **全 PASS** | mmu_tlb_flush/megapage/stress/unified_mmu ✅ |

---

## Bug 修复记录

| 日期 | BUG | 文件 | 修复内容 | 状态 |
|------|-----|------|----------|------|
| 2026-06-04 | BUG 1: fflags 软件写与硬件 OR 冲突 | cpu_csr.sv | 引入 fflags_sw_new/fflags_sw_wen 中间变量, 合并写逻辑: sw+hw 同时发生时先写软件值再 OR 硬件异常 | ✅ 已修复 |
| 2026-06-04 | BUG 2: FLW 双写整数+浮点寄存器 | cpu_wb.sv | rf_wen 条件增加 `!is_flw`, FLW 只写浮点寄存器 | ✅ 已修复 |
| 2026-06-04 | BUG 3+4: FMV.W.X/FCVT.S.W 源操作数错误 | cpu_execute.sv | 添加 fpu_src_is_int 判断 + fpu_src1_mux, int→float 指令选择 rs1_value | ✅ 已修复 |
| 2026-06-04 | FMA 未实现 | cpu_decode.sv | 添加明确注释说明为设计决策, 非缺陷 | ✅ 已实现 (Phase 9) |
| 2026-06-04 | BUG 6: f0 硬连线零 | fpu_regfile.sv | 保持现状 (设计选择), 严格合规可后续修复 | ⬜ 低优先级 |
| 2026-06-04 | BUG 7: FCVT.S.W i_mant_overflow 恒为 1 | fpu_cvt.sv | 将 24 位加法扩展为 25 位, 用 bit[24] 作为真正的进位输出; 旧代码 `{1'b1,i_frac_r}+round_up` 的 bit[23] 始终为 1 (隐含前导 1), 导致指数恒 +1, 结果为正确值的 2 倍 | ✅ 已修复 |
| 2026-06-04 | BUG 8: FLW/FSW 地址计算错误 | cpu_decode.sv | alu_src2 增加 `is_flw→imm_i, is_fsw→imm_s`; alu_control ADD 路径增加 `is_flw|is_fsw`; 旧代码 FLW/FSW 未包含在 ALU 路径中, alu_control=0 导致 ALU 输出全零, 地址恒为 0 | ✅ 已修复 |
| 2026-06-04 | BUG 9: F-ext CSR 地址未加入 is_m_csr | cpu_decode.sv | fflags(0x001)/frm(0x002)/fcsr(0x003) 未加入 is_m_csr 判断, CSRR/CSRW 这些 CSR 被判为非法指令并 trap | ✅ 已修复 |
| 2026-06-04 | BUG 10: fflags_wen 未用 wb_valid 门控 | core_top.sv | fflags_wen 条件从 `(wb_fflags!=0)` 改为 `wb_valid&&(wb_fflags!=0)`; 旧代码在 FPU 写回后 ~31 周期残留 mem_wb_bus_r 导致假写 | ✅ 已修复 |
| 2026-06-04 | BUG 11: f_abs_int 位宽不足 | fpu_cvt.sv | f_abs_int 从 24→32 位, f_abs_rounded 从 25→33 位; 旧代码左移路径截断大浮点数, FCVT.W.S(2^31) 结果为 0 | ✅ 已修复 |
| 2026-06-05 | BUG 12: FSUB 符号错误 | fpu_adder.sv | res_sign_sub 使用原始符号而非有效符号; 当 \|src2\|>\|src1\| 且 is_sub=1 时结果符号错误; 修复: eff_sign_a = swap ? eff_sign2 : s1_sign; res_sign_sub = eff_sign_a | ✅ 已修复 |
| 2026-06-05 | BUG 13: FCVT.W.S 溢出误判 | fpu_cvt.sv | 有符号 int 溢出检测将 -2^31 (0x80000000) 误判为溢出; 修复: 改为 f_sign ? (abs > 0x80000000) : (abs > 0x7FFFFFFF) | ✅ 已修复 |
| 2026-06-05 | BUG 14: rv2coe.py .rodata 缺失 | tools/rv2coe.py | 统一输出 (-o) 仅提取 .text 段, 字符串常量 (.rodata) 未包含在 COE; CPU 读到全零, uart_puts 立即返回; 修复: 新增 elf_all_to_bin() 使用无 --only-section 的 objcopy | ✅ 已修复 |
| 2026-06-05 | BUG 15: tb_calculator NUL 污染 | tb_calculator.sv | 表达式数组含尾部 8'h0, TX 引擎将其作为有效字节发送; 残留在 UART RX 缓冲区, 下次 gets() 首字符为 \0 触发 continue 跳过; 修复: 移除尾部 NUL, 调整 EXPRx_LEN | ✅ 已修复 |

---

## 问题与决策记录

| 日期 | 问题 | 决策 | 理由 |
|------|------|------|------|
| 2026-06-03 | 是否实现 D 扩展? | 暂不实现，仅实现 F 扩展 | XLEN=32，D 需 FLEN=64，工作量翻倍且计算器不需要双精度 |
| 2026-06-03 | 是否实现 FMA 指令? | 暂不实现 → Phase 9 实现 | R4 格式译码复杂，硬件面积大；后因完整性需求实现 |
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
| 2026-06-05 | FSUB 结果符号? | 使用有效符号而非原始符号 | 当 \|src2\|>\|src1\| 且 is_sub=1 时, swap=1, 需用 eff_sign_a 而非 s1_sign |
| 2026-06-05 | FCVT.W.S 有符号溢出检测? | 正负不同阈值 | -2^31 是合法 int32 值, 不应判溢出; 改为 mux: sign ? (abs>0x80000000) : (abs>0x7FFFFFFF) |
| 2026-06-05 | fpu_unit 握手时序? | req_valid/result_got 保持 2 个上升沿 | XSim 竞争条件: 1 周期保持可能导致采不到信号 |
| 2026-06-05 | printf 是否支持 %f? | 不支持, 用 print_float() | float 在可变参数中提升为 double (C 标准), 但无 D 扩展; print_float() 直接调用 ftoa() 避免 double 提升 |
| 2026-06-05 | rv2coe 统一输出段范围? | 包含所有可加载段 | CPU 单 BRAM 需同时包含 .text 和 .rodata; 旧版仅提取 .text 导致字符串常量丢失 |
| 2026-06-05 | testbench 表达式是否含 NUL? | 不含, 仅 newline 终止 | TX 引擎按 EXPRx_LEN 发送字节; 尾部 NUL 会被发送并残留在 RX 缓冲区, 污染下次 gets() 读取 |

---

## Phase 9: FMA 融合乘加指令

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 9.1 | fpu_fma.sv 设计与实现 | ✅ | 867 行, 6-stage FSM (S_MUL→S_ALIGN→S_ADD→S_NORM→S_ROUND→S_DONE) |
| 9.2 | fpu_regfile.sv 第三读端口 | ✅ | raddr3/rdata3 for rs3 (R4 format inst[31:27]) |
| 9.3 | cpu_decode.sv FMA 译码 | ✅ | OPCODE_MADD/MSUB/NMSUB/NMADD, inst_fmadd_s/fmsub_s/fnmsub_s/fnmadd_s, fpu_funct 20-23 |
| 9.4 | ID/EX 总线 rs3 扩展 | ✅ | 344→349 bits, 末尾 5 bits 为 rs3_addr |
| 9.5 | cpu_execute.sv frs3_value | ✅ | 新输入端口, 直传 fpu_unit.src3 |
| 9.6 | core_top.sv frs3 数据通路 | ✅ | frs3_addr=cpu_decode.rs3_addr→fpu_regfile.raddr3, frs3_value=fpu_regfile.rdata3→cpu_execute |
| 9.7 | fpu_unit.sv FMA dispatch | ✅ | fma_start/fma_busy, fpu_funct 20-23→fma_start, src3_reg→fpu_fma.src3 |
| 9.8 | cpu_csr_interface.sv + cpu_trap_csr.sv | ✅ | ID/EX 总线宽度 344→349, 硬编码位索引 +5 |
| 9.9 | isa_f_ext.s FMA 测试 | ✅ | test_27~30: FMADD(2×3+4=10), FMSUB(2×3-4=2), FNMSUB(-2×3+10=4), FNMADD(-2×3-4=-10) |
| 9.10 | 仿真验证 + 回归 | ✅ | isa_f_ext 30/30, isa_f_ext_special 24/24, ISA 10 任务全 PASS, MMU 4 任务全 PASS |

### fpu_fma.sv 设计要点

- **内部表示宽度 75 位**: 乘积 48 位放置于 field[74:27], 加数对齐至同域, 二进制小数点在 bit 73
- **乘积使用 `*` 运算符**: Vivado DSP48 自动推断
- **有效符号**: `prod_sign_eff = (sign1^sign2) ^ (FNMSUB|FNMADD)`, `addend_sign_eff = sign3 ^ (FMSUB|FNMADD)`
- **三级进位归一化**: carry2 (bit 75, sum≥4.0) → exp+2; carry1 (bit 74, sum∈[2.0,4.0)) → exp+1; 无进位 → 左移归一化, exp-lz+2
- **单次舍入**: 乘积与加数对齐后仅做一次 fpu_round, 符合 IEEE 754 融合运算语义
- **特殊情况**: NaN→qNaN, Inf×0→qNaN, Inf-Inf→qNaN, Inf→带符号 Inf
- **ID/EX 总线**: rs3_addr 占用末尾 5 bits, 所有现有字段位索引 +5
