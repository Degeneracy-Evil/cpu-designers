# 仿真对比测试计划

> 目的: 通过定向仿真测试验证 `dev/docs/scan.md` 中发现的 bug，确认根因  
> 约束: 只验证 kernel 能跑起来的必要 bug，U-mode 不测  
> 日期: 2026-06-22

---

## 1. 总体策略

### 1.1 方法
针对每个 bug 编写**定向自检测试程序**，在 RTL 仿真上运行，通过 x28/x30 寄存器和内存结果区判断 PASS/FAIL。

- **PASS** = RTL 行为符合 RISC-V spec → bug 不存在或该路径无问题
- **FAIL** = RTL 行为违反 spec → bug 确认

### 1.2 测试基础设施
- **框架**: `framework/test_framework.s` (test_init/test_run/test_report) + `framework/trap_handlers.s` + `framework/page_table_utils.s`
- **自检协议**: x28=pass_count, x29=total_count, x30=first_fail_id, x31=current_test_id
- **内存结果区**: 0x80007000 (total/pass/fail_id/reserved/test_results...)
- **构建**: `python tools/test_builder.py --test <category/test>` → .hex
- **仿真**: `python -m tools.vivado_cli -task <task_name> -sim`
- **任务配置**: `tasks.yaml` 中添加 task 条目 (tb, blhex, phex, runtime)

### 1.3 新建测试目录
```
dev/program_source/test/audit/
├── csr_bugs.s          # CSR 相关 bug 验证 (BUG-CSR-3, BUG-CSR-5, BUG-CSR-6)
├── mmu_bugs.s          # MMU 相关 bug 验证 (BUG-MMU-1, BUG-MMU-2, BUG-MMU-3)
└── plic_bugs.s         # PLIC 相关 bug 验证 (BUG-PLIC-1, BUG-TRAP-3)
```

### 1.4 build.yaml 新增类别
```yaml
  audit:
    framework: mmu          # 统一用 mmu 框架 (包含 page_table_utils)
    tests:
      - audit/csr_bugs
      - audit/mmu_bugs
      - audit/plic_bugs
```

### 1.5 tasks.yaml 新增条目
每个测试对应一个 task，使用 `tb_simple_cpu_top` testbench，runtime 20ms。

---

## 2. 测试详细设计

### 2.1 BUG-CSR-5: mstatus SPIE 写入被清零

| 项目 | 内容 |
|------|------|
| **文件** | `cpu_csr.sv:408` |
| **根因** | mstatus_wmask bits[6:4]=0，SPIE (bit 5) 被强制清零 |
| **测试文件** | `test/audit/csr_bugs.s` sub-test 1 |
| **框架** | common (无需 MMU) |
| **预期行为** | csrw mstatus 设置 SPIE=1 后，csrr mstatus bit 5 应为 1 |
| **Bug 行为** | bit 5 为 0 |

**测试伪代码:**
```asm
test_01_mstatus_spie_write:
    # 1. 写 mstatus: MPP=M(0x800), MPIE=1(0x80), SPIE=1(0x20)
    li   x10, 0x8A0          # 0x800 | 0x80 | 0x20
    csrw mstatus, x10
    # 2. 读回 mstatus
    csrr x11, mstatus
    # 3. 检查 bit 5 (SPIE)
    andi x12, x11, 0x20
    # 4. PASS if bit5=1, FAIL if bit5=0
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  ret
```

**注意**: 需要确保 mstatus 其他必要位不干扰 (MIE=0 避免中断, MPP=M 保持 M-mode)。

---

### 2.2 BUG-CSR-3: sip.SEIP 缺少 ext_seip

| 项目 | 内容 |
|------|------|
| **文件** | `cpu_csr.sv:645` |
| **根因** | sip.SEIP read 只返回 r_sip[9]，不包含 ext_seip (PLIC 外部中断) |
| **测试文件** | `test/audit/csr_bugs.s` sub-test 2 |
| **框架** | common |
| **预期行为** | PLIC assert SEIP 后，csrr sip bit 9 应为 1 |
| **Bug 行为** | bit 9 为 0 |

**测试伪代码:**
```asm
test_02_sip_seip_ext:
    # 1. PLIC 设置: context 1 (S-mode), enable source 10 (UART)
    #    PLIC base = 0x0C000000
    #    context 1 enable addr = 0x0C002000 + 0x80 = 0x0C002080
    #    source 10 priority addr = 0x0C000000 + 0x1000 + 10*4 = 0x0C001028
    #    context 1 threshold addr = 0x0C200000 + 0x80 = 0x0C200080
    li   x10, 0x0C002080      # context 1 enable
    li   x11, 1               # bit 10 (source 10)
    slli x11, x11, 10
    sw   x11, 0(x10)

    li   x10, 0x0C001028      # source 10 priority
    li   x11, 1               # priority = 1
    sw   x11, 0(x10)

    li   x10, 0x0C200080      # context 1 threshold
    li   x11, 0               # threshold = 0
    sw   x11, 0(x10)

    # 2. 读 sip
    csrr x11, sip
    # 3. 检查 bit 9 (SEIP)
    andi x12, x11, 0x200
    li   x10, 1
    bnez x12, 1f
    li   x10, 0
1:  ret
```

**风险**: PLIC context 编号可能与 RTL 不一致 (这正是 BUG-PLIC-1 的内容)。如果 context 1 在 RTL 上是 M-mode context，则 SEIP 不会 assert。需要先确认 PLIC context mapping。
**备选方案**: 直接写 mip[9]=1 (软件中断), 读 sip[9]，验证 r_sip 路径。但这不测试 ext_seip 路径。

---

### 2.3 BUG-CSR-6: scounteren S-mode 可写

| 项目 | 内容 |
|------|------|
| **文件** | `cpu_csr.sv:587` |
| **根因** | scounteren 在 S-mode 下可写 (应为只读或 WARL) |
| **测试文件** | `test/audit/csr_bugs.s` sub-test 3 |
| **框架** | mmu (需要 S-mode 切换) |
| **预期行为** | S-mode csrw scounteren 应触发 illegal instruction (mcause=2) |
| **Bug 行为** | 写入成功，无 trap |

**测试伪代码:**
```asm
test_03_scounteren_smode_write:
    # 1. 设置页表 + SV32
    jal  x1, setup_identity_map
    jal  x1, enable_sv32
    # 2. 切换到 S-mode
    la   x5, s_scounteren_test
    csrw mepc, x5
    li   x5, 0x880           # S-mode, MPIE=1
    csrw mstatus, x5
    mret

s_scounteren_test:
    # 3. S-mode 下写 scounteren
    li   x10, 0x7
    csrw scounteren, x10     # 应触发 illegal instruction
    # 4. 如果执行到这里 → bug 确认 (写入成功)
    li   x10, 0              # FAIL (不应到达此处)
    ecall

# trap handler 检查:
#   mcause=2 (illegal) → PASS (S-mode 不能写 scounteren)
#   无 trap → FAIL
```

**优先级**: MEDIUM，可延后。

---

### 2.4 BUG-MMU-1: TLB hit 绕过 D bit 检查 (CRITICAL)

| 项目 | 内容 |
|------|------|
| **文件** | `MMU.sv:271-277` |
| **根因** | TLB hit 路径 `d_tlb_perm_fault` 不检查 D bit，store 到 D=0 页不触发 page fault 也不置 D=1 |
| **测试文件** | `test/audit/mmu_bugs.s` sub-test 1 |
| **框架** | mmu |
| **预期行为** | store 到 D=0 页应触发 store page fault (mcause=15) 或 PTW 重走置 D=1 |
| **Bug 行为** | store 静默成功，PTE D bit 保持 0 |

**测试伪代码:**
```asm
test_01_tlb_d_bit_bypass:
    # 1. 设置恒等映射
    jal  x1, setup_identity_map
    # 2. 修改 L0[4] (0x80004000) 为 A=1, D=0 (V|R|W|X|A, no D)
    la   x14, l0_page_table
    li   x15, 0x80004
    slli x15, x15, 10
    li   x16, 0x04F           # V|R|W|X|A (D=0)
    or   x15, x15, x16
    sw   x15, 16(x14)         # L0[4] → D=0 page
    # 3. 启用 SV32
    jal  x1, enable_sv32
    sfence.vma                # flush TLB
    # 4. 切换到 S-mode
    la   x5, s_dbit_test
    csrw mepc, x5
    li   x5, 0x880
    csrw mstatus, x5
    mret

s_dbit_test:
    # 5. Load from 0x80004000 → 触发 PTW, 填充 TLB (A=1, D=0)
    li   x14, 0x80004000
    lw   x15, 0(x14)          # load fills TLB with D=0
    # 6. Store to same address → TLB hit
    li   x15, 0x12345678
    sw   x15, 0(x14)          # store: if D check missing → silent success
    # 7. 返回 M-mode 检查 PTE
    ecall

# M-mode 检查:
post_dbit_check:
    # 8. 读回 L0[4] PTE
    la   x14, l0_page_table
    lw   x15, 16(x14)
    # 9. 检查 D bit (bit 7)
    andi x16, x15, 0x80
    # 10. 如果 D=1 → PASS (PTW 重走置 D)
    #     如果 D=0 → FAIL (bug 确认: store 绕过了 D 检查)
    #     如果 trap 发生 (mcause=15) → PASS (spec-compliant page fault)
    # 需要同时检查 got_fault 标志
```

**关键细节:**
- `enable_sv32` 中的 `fence.i` 确保 dcache 写回，PTW 能看到更新后的 PTE
- Load 必须先于 store，确保 TLB 被 D=0 条目填充
- Store 后需要 `fence.i` 再读 PTE，确保 dcache 写回
- 需要处理两种正确行为: (a) D 被置 1, (b) 触发 store page fault

**trap handler 需要处理:**
- mcause=15 (store page fault) → 正确行为，PASS
- 无 trap + D=0 → bug 确认，FAIL
- 无 trap + D=1 → PTW 重走置 D，PASS

---

### 2.5 BUG-MMU-2: PTW access fault 在数据侧被丢弃

| 项目 | 内容 |
|------|------|
| **文件** | `core_top.sv:1297-1299` |
| **根因** | PTW access fault (cause 5/7) 在数据侧被静默丢弃，不触发 trap |
| **测试文件** | `test/audit/mmu_bugs.s` sub-test 2 |
| **框架** | mmu |
| **预期行为** | PTW 访问非法物理地址应触发 load/store access fault (mcause=5/7) |
| **Bug 行为** | access fault 被丢弃，无 trap，CPU 可能挂死或返回错误数据 |

**测试伪代码:**
```asm
test_02_ptw_data_access_fault:
    # 1. 设置恒等映射
    jal  x1, setup_identity_map
    # 2. 修改 L0[4] PTE 指向未映射的物理地址 (如 0x00000000)
    la   x14, l0_page_table
    li   x15, 0x00000         # PPN = 0 → PA = 0x00000000 (ROM/unmapped)
    slli x15, x15, 10
    li   x16, 0x04F           # V|R|W|X|A (valid PTE but bad PA)
    or   x15, x15, x16
    sw   x15, 16(x14)
    # 3. 启用 SV32
    jal  x1, enable_sv32
    sfence.vma
    # 4. 切换到 S-mode, load from 0x80004000
    #    PTW 会 walk → L0[4] PPN=0 → PA=0x00000000
    #    如果 0x00000000 不可访问 → access fault
    #    如果 0x00000000 是 ROM → 返回 ROM 数据 (不是 access fault)
    ...
```

**风险**: 0x00000000 可能是有效地址 (ROM/BootROM)。需要选一个明确非法的物理地址。
- SoC 地址映射: DDR3@0x80000000, PLIC@0x0C000000, CLINT@0x02000000, APB@0x10000000, ROM@0xFC000000
- 非法地址候选: 0x40000000 (未映射), 0x70000000 (未映射)
- 但仿真中 bus bridge 可能对未映射地址返回 0 或挂起

**备选方案**: 使用 PTE V=0 (invalid PTE) → page fault (cause 13/15)，这已经被 `reg_ptw_fault_latch.s` 测试覆盖。BUG-MMU-2 特指 **PTE 本身所在的物理地址**不可访问的情况 (如 L1 表指向非法 PA)。这更难构造。

**实际测试**: 让 L1[512] 指向一个非法物理地址的 L0 表。当 PTW 尝试读 L0 表时触发 access fault。
```asm
    # 修改 L1[512] 指向非法 PA
    la   x14, l1_page_table
    li   x15, 0x40000         # PPN = 0x40000 → PA = 0x40000000 (unmapped)
    slli x15, x15, 10
    li   x16, 0x001           # V=1 (valid pointer to L0)
    or   x15, x15, x16
    sw   x15, 0x800(x14)      # L1[512]
```

---

### 2.6 BUG-MMU-3: PTW access fault cause 硬编码为 12

| 项目 | 内容 |
|------|------|
| **文件** | `cpu_trap_manager.sv:228` |
| **根因** | PTW access fault 在指令侧 cause 硬编码为 12 (instruction page fault)，应为 1 (instruction access fault) |
| **测试文件** | `test/audit/mmu_bugs.s` sub-test 3 |
| **框架** | mmu |
| **预期行为** | 指令 fetch 触发 PTW access fault → mcause=1 (inst access fault) |
| **Bug 行为** | mcause=12 (inst page fault) |

**测试伪代码:**
```asm
test_03_ptw_inst_access_fault_cause:
    # 1. 设置恒等映射
    jal  x1, setup_identity_map
    # 2. 修改 L0[5] PTE 指向非法物理地址
    la   x14, l0_page_table
    li   x15, 0x40000         # PPN = 0x40000 → PA = 0x40000000 (unmapped)
    slli x15, x15, 10
    li   x16, 0x05F           # V|R|W|X|U|A|D (valid PTE, bad PA)
    or   x15, x15, x16
    sw   x15, 20(x14)         # L0[5] → bad PA
    # 3. 启用 SV32
    jal  x1, enable_sv32
    sfence.vma
    # 4. 切换到 S-mode, jump to 0x80005000
    #    PTW walks L0[5] → PA=0x40000000 → access fault
    #    mcause should be 1 (inst access fault)
    #    bug: mcause = 12 (inst page fault)
    li   x5, 0x80005000
    csrw mepc, x5
    li   x5, 0x880
    csrw mstatus, x5
    mret

# trap handler:
#   mcause=1 → PASS (correct: instruction access fault)
#   mcause=12 → FAIL (bug: hardcoded to page fault)
```

**依赖**: 需要先确认 0x40000000 在仿真中确实触发 access fault (而非返回 0 或挂起)。

---

### 2.7 BUG-PLIC-1: PLIC DTS context 不匹配 (CRITICAL)

| 项目 | 内容 |
|------|------|
| **文件** | `boot/dts/simplecpu.dts:126` |
| **根因** | DTS 只声明 1 个 context (S-mode at index 0)，但 RTL context 0=M-mode (MEIP), context 1=S-mode (SEIP) |
| **测试文件** | `test/audit/plic_bugs.s` sub-test 1 |
| **框架** | common |
| **预期行为** | PLIC context 1 enable + priority → SEIP assert → mip/sip bit 9 = 1 |
| **Bug 行为** | PLIC context 0 是 M-mode → MEIP assert → mip bit 11 = 1 (不是 SEIP) |

**测试伪代码:**
```asm
test_01_plic_context_mapping:
    # 1. PLIC context 0 (RTL: M-mode) enable source 10
    li   x10, 0x0C000080      # context 0 enable base
    li   x11, 1
    slli x11, x11, 10         # bit 10 = source 10
    sw   x11, 0(x10)

    # 2. PLIC source 10 priority = 1
    li   x10, 0x0C001028      # source 10 priority
    li   x11, 1
    sw   x11, 0(x10)

    # 3. PLIC context 0 threshold = 0
    li   x10, 0x0C000000      # context 0 threshold
    sw   x0, 0(x10)

    # 4. 读 mip
    csrr x11, mip
    # 5. 检查 bit 11 (MEIP) — 如果 RTL context 0 = M-mode
    andi x12, x11, 0x800
    bnez x12, ctx0_is_mmode

    # 6. 检查 bit 9 (SEIP) — 如果 RTL context 0 = S-mode
    andi x12, x11, 0x200
    bnez x12, ctx0_is_smode

    # 7. 都没有 → PLIC 未 assert
    li   x10, 0              # FAIL: no interrupt pending
    ret

ctx0_is_mmode:
    # context 0 = M-mode → 确认 DTS bug (DTS 声明 ctx0=S-mode)
    li   x10, 1              # PASS: bug confirmed
    ret

ctx0_is_smode:
    # context 0 = S-mode → DTS 正确，无 bug
    li   x10, 0              # FAIL (期望确认 bug 但未确认)
    ret
```

**注意**: 这个测试的 PASS = "bug 确认" (context 0 是 M-mode)。如果 context 0 是 S-mode，说明 RTL 与 DTS 匹配，bug 不存在。

**风险**: 需要触发 source 10 (UART) 的中断。在仿真中 UART 可能不会自动产生中断。可以使用 PLIC 的 software interrupt 或直接写 PLIC claim 寄存器。
**备选**: 使用 CLINT 的 MSIP/SSIP 来测试中断路径，而非 PLIC。

---

### 2.8 BUG-TRAP-3: MSIP 混入 SSI

| 项目 | 内容 |
|------|------|
| **文件** | `cpu_clint.sv:86,100` |
| **根因** | M-mode software interrupt (MSIP) 信号混入 S-mode software interrupt (SSI) |
| **测试文件** | `test/audit/plic_bugs.s` sub-test 2 |
| **框架** | common |
| **预期行为** | 写 CLINT MSIP (0x02000000) 只影响 mip bit 3 (MSIP)，不影响 sip bit 1 (SSIP) |
| **Bug 行为** | 写 MSIP 同时设置 MSIP 和 SSIP |

**测试伪代码:**
```asm
test_02_msip_leaks_to_ssi:
    # 1. 清除所有 pending
    csrw mip, x0
    # 2. 写 CLINT MSIP = 1
    li   x10, 0x02000000      # CLINT MSIP
    li   x11, 1
    sw   x11, 0(x10)
    # 3. 读 mip
    csrr x12, mip
    # 4. 检查 bit 3 (MSIP) — 应为 1
    andi x13, x12, 0x8
    beqz x13, msip_fail       # MSIP 未设置 → 异常
    # 5. 检查 bit 1 (SSIP) — 应为 0
    andi x13, x12, 0x2
    bnez x13, ssi_leaked      # SSIP 被设置 → bug 确认
    # 6. MSIP=1, SSIP=0 → 无 bug
    li   x10, 1              # PASS (no bug)
    ret

ssi_leaked:
    li   x10, 0              # FAIL: MSIP leaked to SSIP (bug confirmed)
    ret

msip_fail:
    li   x10, 0              # FAIL: MSIP not set
    ret
```

---

## 3. 执行步骤

### Step 1: 创建测试文件 (并行委派 3 个 deep agent)
- Agent A: `test/audit/csr_bugs.s` (3 sub-tests: CSR-5, CSR-3, CSR-6)
- Agent B: `test/audit/mmu_bugs.s` (3 sub-tests: MMU-1, MMU-2, MMU-3)
- Agent C: `test/audit/plic_bugs.s` (2 sub-tests: PLIC-1, TRAP-3)

### Step 2: 更新构建配置
- 在 `build.yaml` 添加 `audit` 类别
- 在 `tasks.yaml` 添加 3 个 task 条目:
  - `audit_csr_bugs`: tb=tb_simple_cpu_top, phex=test/audit/csr_bugs.hex, runtime=20ms
  - `audit_mmu_bugs`: tb=tb_simple_cpu_top, phex=test/audit/mmu_bugs.hex, runtime=20ms
  - `audit_plic_bugs`: tb=tb_simple_cpu_top, phex=test/audit/plic_bugs.hex, runtime=20ms

### Step 3: 构建测试程序
```bash
python tools/test_builder.py --test audit/csr_bugs
python tools/test_builder.py --test audit/mmu_bugs
python tools/test_builder.py --test audit/plic_bugs
```

### Step 4: 运行仿真 (并行)
```bash
python -m tools.vivado_cli -task audit_csr_bugs -create -sim
python -m tools.vivado_cli -task audit_mmu_bugs -create -sim
python -m tools.vivado_cli -task audit_plic_bugs -create -sim
```

### Step 5: 分析结果
- 检查 x28 (pass_count) 和 x30 (first_fail_id)
- FAIL 的 sub-test → bug 确认
- PASS 的 sub-test → bug 不存在或测试未触发

### Step 6: 写入报告
- 结果追加到 `dev/docs/scan.md` 的 "仿真验证结果" 章节

---

## 4. 风险和缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 仿真中未映射地址不触发 access fault | MMU-2/MMU-3 测试无效 | 先写探测测试确认 bus 行为 |
| PLIC 在仿真中不产生中断 | PLIC-1 测试无效 | 使用 CLINT MSIP 替代或手动注入 |
| TLB 行为与预期不符 (如 PTW 自动置 D) | MMU-1 测试结果模糊 | 同时检查 PTE D bit 和 mcause |
| dcache write-back 时序问题 | 页表修改不可见 | 使用 fence.i + sfence.vma |
| 测试程序本身有 bug | 误报/漏报 | 先在 QEMU 上验证测试程序逻辑正确 |

---

## 5. 优先级排序

| 优先级 | 测试 | 理由 |
|--------|------|------|
| P0 | BUG-MMU-1 (TLB D bit) | CRITICAL，Linux 脏页跟踪失效 |
| P0 | BUG-PLIC-1 (PLIC context) | CRITICAL，中断走错 mode |
| P1 | BUG-CSR-5 (SPIE) | HIGH，简单且影响中断恢复 |
| P1 | BUG-MMU-2/3 (PTW fault) | HIGH，影响错误传播 |
| P2 | BUG-CSR-3 (sip.SEIP) | HIGH，但依赖 PLIC context 确认 |
| P2 | BUG-TRAP-3 (MSIP leak) | MEDIUM，简单可快速验证 |
| P3 | BUG-CSR-6 (scounteren) | MEDIUM，不影响 kernel 启动 |

---

## 6. 预期结果

| 测试 | 预期 RTL 行为 | 结论 |
|------|--------------|------|
| CSR-5 SPIE | bit5=0 (被清零) | Bug 确认 |
| CSR-3 sip.SEIP | bit9=0 (缺 ext_seip) | Bug 确认 (依赖 PLIC) |
| CSR-6 scounteren | 无 trap (S-mode 可写) | Bug 确认 |
| MMU-1 TLB D bit | D=0 (store 绕过) | Bug 确认 |
| MMU-2 PTW data fault | 无 trap (fault 丢弃) | Bug 确认 |
| MMU-3 PTW inst fault | mcause=12 (硬编码) | Bug 确认 |
| PLIC-1 context | MEIP assert (ctx0=M-mode) | Bug 确认 |
| TRAP-3 MSIP leak | SSIP=1 (MSIP 混入) | Bug 确认 |

如果所有测试结果与预期一致，则 scan.md 中所有 bug 均被仿真确认。
