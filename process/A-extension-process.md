# A 扩展（原子指令）实施进度

> 创建日期: 2026-06-15 | 关联计划: `plan/A-extension-implementation.md`

---

## 总体进度

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | 流水线总线扩展 | ✅ 完成 | 2026-06-15 |
| Phase 2 | 译码级 A 扩展指令识别 | ✅ 完成 | 2026-06-15 |
| Phase 3 | 执行级信号透传 | ✅ 完成 | 2026-06-15 |
| Phase 4 | 访存级 AMO FSM + 保留集 + AMO 计算 | ✅ 完成 | 2026-06-15 |
| Phase 5 | 核心顶层连线 + CSR 更新 | ✅ 完成 | 2026-06-15 |
| Phase 6 | 测试程序 + Testbench | ✅ 完成 | 2026-06-15 |
| Phase 7 | 仿真验证 + Bug 修复 | ✅ 完成 | 2026-06-15 |

---

## Phase 1: 流水线总线扩展

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 1.1 | exe_mem_bus_t 新增 A 字段 | ✅ | is_amo/is_lr/is_sc/amo_funct5/amo_aq/amo_rl = 10 bit, 总宽 216→226 |
| 1.2 | wb_bus_t 新增 A 字段 | ✅ | is_amo/is_lr/is_sc = 3 bit, 总宽 177→180 |

## Phase 2: 译码级 A 扩展指令识别

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 2.1 | OPCODE_AMO 常量 | ✅ | 7'b0101111 |
| 2.2 | funct5/aq/rl 提取 | ✅ | inst[31:27], inst[26], inst[25] |
| 2.3 | 11 条指令匹配 wire | ✅ | LR.W/SC.W/AMOSWAP/AMOADD/AMOAND/AMOOR/AMOXOR/AMOMIN/AMOMAX/AMOMINU/AMOMAXU |
| 2.4 | is_amo/is_lr/is_sc 分类信号 | ✅ | is_amo_all \| is_lr \| is_sc |
| 2.5 | valid_inst 扩展 | ✅ | 新增 is_amo |
| 2.6 | wb_we 扩展 | ✅ | AMO/LR/SC 均写回 rd |
| 2.7 | alu_src2/alu_control | ✅ | AMO: ADD(rs1, 0) 计算地址 |
| 2.8 | id_exe_bus 扩展 | ✅ | 334→344 bit, 末尾追加 10 bit A 字段 |

## Phase 3: 执行级信号透传

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 3.1 | 解包 A 字段 | ✅ | 从 id_exe_bus_r 解包 |
| 3.2 | exe_need_mem 扩展 | ✅ | 新增 is_amo |
| 3.3 | exe_mem_bus 打包 | ✅ | 追加 A 字段 |

## Phase 4: 访存级核心实现

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 4.1 | FSM 状态扩展 | ✅ | MEM_AMO_READ(3)/MEM_AMO_WRITE(4) |
| 4.2 | 保留集寄存器 | ✅ | lr_reservation_addr + lr_reservation_valid |
| 4.3 | AMO 计算逻辑 | ✅ | amo_compute() 函数, 9 种操作 |
| 4.4 | SC 保留匹配检查 | ✅ | sc_reservation_match = valid && addr_match |
| 4.5 | AMO 对齐异常检测 | ✅ | amo_misalign, LR code=4, SC/AMO code=6 |
| 4.6 | MEM_IDLE AMO 入口 | ✅ | 锁存 funct5/rs2/lr/sc 标志, 发读请求 |
| 4.7 | MEM_AMO_READ 处理 | ✅ | LR: 设保留+返回值; SC: 检查保留; AMO: 计算+发写 |
| 4.8 | MEM_AMO_WRITE 处理 | ✅ | SC: rd=0; AMO: rd=原始读出值 |
| 4.9 | 保留失效逻辑 | ✅ | Store 完成后/SC 执行后/陷阱进入后 |
| 4.10 | mem_wb_bus 打包 | ✅ | 追加 is_amo/is_lr/is_sc |

## Phase 5: 核心顶层连线 + CSR 更新

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 5.1 | core_top.sv 总线位宽更新 | ✅ | id_exe_bus 344, exe_mem_bus 226, mem_wb_bus 180 |
| 5.2 | trap_enter 信号连接 | ✅ | cpu_mem.trap_enter ← trap_enter_valid |
| 5.3 | cpu_csr.sv misa 更新 | ✅ | 0x40141120 → 0x40141121 (bit 0 = A) |
| 5.4 | cpu_csr_interface.sv 适配 | ✅ | A 扩展相关 CSR 接口 |
| 5.5 | cpu_trap_csr.sv 适配 | ✅ | AMO 异常码调整 |

## Phase 6: 测试程序 + Testbench

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 6.1 | a_ext.s 测试程序 | ✅ | 16 个子测试覆盖全部 11 条 A 扩展指令 + 互斥锁 + 累加 + 交换 |
| 6.2 | build.yaml 注册 | ✅ | isa_a_ext 编译目标 |
| 6.3 | tb_isa_a_ext.sv | ✅ | wait(if_pc >= 0x80000000) + 500K cycles |
| 6.4 | tasks.yaml 任务 | ✅ | isa_a_ext, runtime=200ms |
| 6.5 | 寄存器重映射 | ✅ | test 函数 x18-x21 → x22-x25, 避免与 test_run 框架冲突 |

## Phase 7: 仿真验证 + Bug 修复

| 步骤 | 内容 | 状态 | 备注 |
|------|------|------|------|
| 7.1 | 首次仿真 | ✅ | 1/16 pass, x18-x21 与 test_run 冲突 |
| 7.2 | 寄存器重映射修复 | ✅ | x22-x25, 10/16 pass, first_fail_id=6 (AMOADD) |
| 7.3 | BUG 1: funct5 编码错误修复 | ✅ | AMOMIN/AMOMINU/AMOMAXU, 12/16 pass |
| 7.4 | BUG 2: AMO 计算时序错误修复 | ✅ | amo_compute() 函数替代 stale wire, **16/16 pass** |

---

## 仿真验证

| 日期 | 测试 | 结果 | 备注 |
|------|------|------|------|
| 2026-06-15 | isa_a_ext (首次, 寄存器冲突) | 1/16 pass | x18-x21 被 test_run 框架覆盖, x16 返回值被破坏 |
| 2026-06-15 | isa_a_ext (寄存器重映射后) | 10/16 pass | x22-x25 修复, first_fail_id=6 (test_amoadd_w) |
| 2026-06-15 | isa_a_ext (BUG 1 funct5 修复后) | 12/16 pass | AMOMIN/AMOMINU/AMOMAXU 识别恢复, AMOADD 仍失败 |
| 2026-06-15 | isa_a_ext (BUG 1+2 全部修复) | **16/16 pass** | **ALL TESTS PASSED** ✅ |

---

## Bug 修复记录

| 日期 | BUG | 文件 | 修复内容 | 状态 |
|------|-----|------|----------|------|
| 2026-06-15 | BUG 1: funct5 编码错误 | cpu_decode.sv, cpu_mem.sv | AMOMIN/AMOMINU/AMOMAXU 的 funct5 编码不符合 RISC-V spec Table 8.6。旧值: AMOMIN=11000, AMOMINU=11100, AMOMAXU=11110; 正确值: AMOMIN=10000, AMOMINU=11000, AMOMAXU=11100。影响: AMOMIN 指令(funct5=10000)未被识别, AMOMINU(funct5=11000)被误判为 AMOMIN, AMOMAXU(funct5=11100)被误判为 AMOMINU | ✅ 已修复 |
| 2026-06-15 | BUG 2: AMO 计算使用旧值 | cpu_mem.sv | `amo_calc_result` 组合线使用寄存器 `amo_loaded_value` (上一周期旧值), 而非当前周期刚读出的 `readData_32`。根因: MEM_AMO_READ 中 `amo_loaded_value <= readData_32` 为非阻塞赋值, 下一周期才生效, 但 `amo_calc_result` 在同一周期求值时读到旧值。证据: AMOADD loaded=0x64 rs2=0x32 产生 calc=0xAAAAAADC (使用了 AMOSWAP 的旧值 0xAAAAAAAA)。修复: 将 `amo_calc_result` 组合线替换为 `amo_compute()` 函数, MEM_AMO_READ 状态直接传入 `readData_32` | ✅ 已修复 |

---

## 问题与决策记录

| 日期 | 问题 | 决策 | 理由 |
|------|------|------|------|
| 2026-06-15 | AMO 在哪一级执行? | MEM 级 | AMO 需读-改-写访存, EXE 级无访存能力; 与 MU/FPU 在 EXE 级执行的模式不同 |
| 2026-06-15 | 单 hart 原子性如何保证? | FSM 持有流水线 | 单 hart + MEM FSM 持有流水线 = 天然原子, 无需额外锁 |
| 2026-06-15 | 保留集实现方式? | 1 地址寄存器 + valid 位 | 单 hart 仅需跟踪一个保留; 多 hart 需扩展为 CAM/SRAM |
| 2026-06-15 | aq/rl 排序位如何处理? | 当前为 no-op | 单 hart 顺序执行 CPU 中, aq/rl 语义天然满足 (无乱序/推测) |
| 2026-06-15 | SC 失败返回何值? | 返回 1 | 规范要求非零, 推荐 1; 成功返回 0 |
| 2026-06-15 | 正常 Store 是否清除保留? | 是 | RISC-V 规范: 其他 hart 或本 hart 的 Store 到保留地址使保留失效; 单 hart 简化为任何 Store 均清除 |
| 2026-06-15 | LR.W 对齐异常 code? | 4 (Load misaligned) | LR.W 是 Load 类操作; SC.W/AMO 用 code=6 (Store/AMO misaligned) |
| 2026-06-15 | test 函数使用哪些寄存器? | x5-x17 + x22-x25 | test_run 框架占用 x18(test_id)/x19(ra)/x20/x21(results_addr); x28-x31 为框架寄存器; x22-x27 为 callee-saved 且不被 test_run 使用 |
| 2026-06-15 | AMO 计算用组合线还是函数? | 函数 `amo_compute()` | 组合线 `amo_calc_result` 依赖寄存器 `amo_loaded_value`, 在 MEM_AMO_READ 同一周期读到旧值 (非阻塞赋值延迟); 函数接受 loaded 值参数, 可直接传入 `readData_32` |
| 2026-06-15 | Testbench 等待策略? | `wait(if_pc >= 0x80000000)` + 500K cycles | UART 加载 8192 words 需 ~98ms sim time; 固定 cycle 计数需覆盖加载+执行, 效率低; PC 阈值触发后仅需 500K cycles 覆盖程序执行 |

---

## 测试覆盖详情

### 16 个子测试

| ID | 测试名 | 指令 | 验证内容 |
|----|--------|------|----------|
| 1 | test_lr_w_basic | LR.W | 读出值 = 内存值, 保留有效 |
| 2 | test_sc_w_success | LR.W → SC.W | rd = 0 (成功), 内存已更新 |
| 3 | test_sc_w_fail_no_lr | SC.W (无前置 LR) | rd ≠ 0 (失败), 内存未更新 |
| 4 | test_sc_w_fail_after_store | LR.W → SW → SC.W | rd ≠ 0 (Store 使保留失效) |
| 5 | test_amoswap_w | AMOSWAP.W | rd = 旧值, 内存 = rs2 |
| 6 | test_amoadd_w | AMOADD.W | rd = 旧值, 内存 = 旧值+rs2 |
| 7 | test_amoand_w | AMOAND.W | rd = 旧值, 内存 = 旧值&rs2 |
| 8 | test_amoor_w | AMOOR.W | rd = 旧值, 内存 = 旧值\|rs2 |
| 9 | test_amoxor_w | AMOXOR.W | rd = 旧值, 内存 = 旧值^rs2 |
| 10 | test_amomin_w | AMOMIN.W | rd = 旧值, 内存 = min(旧值, rs2) 有符号 |
| 11 | test_amomax_w | AMOMAX.W | rd = 旧值, 内存 = max(旧值, rs2) 有符号 |
| 12 | test_amominu_w | AMOMINU.W | rd = 旧值, 内存 = minu(旧值, rs2) 无符号 |
| 13 | test_amomaxu_w | AMOMAXU.W | rd = 旧值, 内存 = maxu(旧值, rs2) 无符号 |
| 14 | test_lr_sc_mutex | LR.W/SC.W 循环 | 互斥锁惯用法: 成功获取+释放 |
| 15 | test_amoadd_accumulate | 3× AMOADD.W | 连续累加: counter 0→1→2→3 |
| 16 | test_amoswap_swap_values | 2× AMOSWAP.W | 连续交换: 验证两次 swap 的返回值和内存 |

---

## 关键实现细节

### AMO FSM 状态转换

```
MEM_IDLE ──(is_amo)──> MEM_AMO_READ ──(data_valid)──> MEM_AMO_WRITE ──(data_valid)──> MEM_IDLE
                           │                                                │
                           ├── LR: 设保留, wb=读出值, done                   ├── SC: wb=0 (成功)
                           ├── SC 匹配: 发写请求                             └── AMO: wb=原始读出值
                           └── SC 不匹配: wb=1, done (不写内存)

                           AMO: 计算 amo_compute(funct5, readData_32, rs2)
                                发写请求 (wdata=计算结果)
```

### 保留集失效条件

| 条件 | 实现 |
|------|------|
| SC.W 执行后 (无论成功失败) | `lr_reservation_valid <= 0` (MEM_AMO_READ, is_sc_reg) |
| 任何普通 Store 完成后 | `lr_reservation_valid <= 0` (MEM_WRITE, data_valid) |
| 陷阱进入时 | `lr_reservation_valid <= 0` (trap_enter) |

### amo_compute() 函数

```systemverilog
function automatic [31:0] amo_compute(
    input [4:0]  funct5,
    input [31:0] loaded,   // 直接传入 readData_32, 非 amo_loaded_value
    input [31:0] rs2
);
    case (funct5)
        5'b00001: amo_compute = rs2;                                    // AMOSWAP
        5'b00000: amo_compute = loaded + rs2;                           // AMOADD
        5'b01100: amo_compute = loaded & rs2;                           // AMOAND
        5'b01000: amo_compute = loaded | rs2;                           // AMOOR
        5'b00100: amo_compute = loaded ^ rs2;                           // AMOXOR
        5'b10000: amo_compute = ($signed(loaded) < $signed(rs2))        // AMOMIN
                            ? loaded : rs2;
        5'b10100: amo_compute = ($signed(loaded) > $signed(rs2))        // AMOMAX
                            ? loaded : rs2;
        5'b11000: amo_compute = (loaded < rs2) ? loaded : rs2;          // AMOMINU
        5'b11100: amo_compute = (loaded > rs2) ? loaded : rs2;          // AMOMAXU
        default:  amo_compute = loaded;
    endcase
endfunction
```

### funct5 编码 (RISC-V Spec Table 8.6)

| funct5 | 指令 | 备注 |
|--------|------|------|
| 00000 | AMOADD | |
| 00001 | AMOSWAP | |
| 00010 | LR.W | rs2=0 |
| 00011 | SC.W | |
| 00100 | AMOXOR | |
| 01000 | AMOOR | |
| 01100 | AMOAND | |
| 10000 | AMOMIN | ← BUG 1 曾错写为 11000 |
| 10100 | AMOMAX | |
| 11000 | AMOMINU | ← BUG 1 曾错写为 11100 |
| 11100 | AMOMAXU | ← BUG 1 曾错写为 11110 |

---

## 文件变更清单

| 文件 | 变更类型 | 变更内容 |
|------|----------|----------|
| `dev/rtl/core/core_bus_types.svh` | 修改 | exe_mem_bus_t 新增 6 字段 (10 bit), wb_bus_t 新增 3 字段 (3 bit) |
| `dev/rtl/core/cpu_decode.sv` | 修改 | OPCODE_AMO + 11 条指令匹配 + is_amo 分类 + id_exe_bus 扩展 + funct5 编码修复 |
| `dev/rtl/core/cpu_execute.sv` | 修改 | 解包/透传 A 字段 + exe_need_mem 扩展 |
| `dev/rtl/core/cpu_mem.sv` | 重写 | AMO FSM (2 新状态) + 保留集 + amo_compute() 函数 + 对齐异常 + 保留失效 + funct5 编码修复 |
| `dev/rtl/core/core_top.sv` | 修改 | 总线位宽更新 + trap_enter 连线 |
| `dev/rtl/core/cpu_csr.sv` | 修改 | misa: 0x40141120 → 0x40141121 |
| `dev/rtl/core/cpu_csr_interface.sv` | 修改 | A 扩展 CSR 接口适配 |
| `dev/rtl/core/cpu_trap_csr.sv` | 修改 | AMO 异常码调整 |
| `dev/program_source/test/isa/a_ext.s` | 新建 | 16 子测试汇编程序 |
| `dev/tb/tb_isa_a_ext.sv` | 新建 | Testbench (PC 阈值 + 500K cycles) |
| `dev/program_source/build.yaml` | 修改 | isa_a_ext 编译目标注册 |
| `tasks.yaml` | 修改 | isa_a_ext 任务注册 |
