# M/S/U 特权架构实现进度

## 2026-05-22 实现记录

### 已完成

#### Step 1: 特权级寄存器与基础设施
- `core_top.sv`: 新增 `reg [1:0] priv_mode`，复位为 PRIV_M(2'b11)
- trap_enter 时 `priv_mode <= target_priv`
- trap_return 时：MRET 恢复 mstatus.MPP，SRET 恢复 sstatus.SPP

#### Step 2: mstatus 扩展
- `cpu_csr.sv`: mstatus 新增字段 SIE[1]/SPIE[5]/SPP[8]/MPRV[17]/MXR[19]/SUM[18]/TVM[20]/TW[21]/TSR[22]/FS[14:13]/XS[16:15]/SD[31]
- 写掩码更新，仅允许写合法字段
- SD 位为只读摘要：FS 或 XS 非 Off 时置 1

#### Step 3: 新增 S-mode CSR 与委托 CSR
- S-mode CSR: sstatus(0x100), sie(0x104), stvec(0x105), scounteren(0x106), sscratch(0x140), sepc(0x141), scause(0x142), stval(0x143), sip(0x144), satp(0x180)
- 委托 CSR: medeleg(0x302), mideleg(0x303)
- mcounteren(0x306) 新增
- sstatus 为 mstatus 子集视图：读返回对应位，写修改 mstatus 对应位

#### Step 4: CSR 访问控制
- `cpu_csr.sv`: 新增 `csr_access_ok` 输出，按 priv_mode 检查 CSR 地址
  - U-mode: 所有 S/M CSR 不可访问
  - S-mode: 仅 S-mode CSR 可访问（M-mode CSR 不可访问）
  - M-mode: 全部可访问
- `cpu_decode.sv`: 新增 `dec_csr_access_ok`，CSR 地址非法时触发 illegal_inst

#### Step 5: ECALL 异常码区分
- `cpu_trap_manager.sv`: ECALL 异常码根据 priv_mode 决定
  - U-mode → code 8
  - S-mode → code 9
  - M-mode → code 11

#### Step 6: 陷阱委托机制
- `cpu_clint.sv`: 完全重写
  - 新增 S-mode 中断检测（sie/sip）
  - 委托判定：异常看 medeleg[cause]，中断看 mideleg[cause]
  - 委托到 S-mode：写 sstatus/sepc/scause/stval，跳转 stvec
  - 进入 M-mode：写 mstatus/mepc/mcause/mtval，跳转 mtvec
  - hw_csr_wen 扩展：新增 hw_target_priv/hw_sepc/hw_scause/hw_stval/hw_sstatus

#### Step 7: SRET 指令
- `cpu_decode.sv`: 新增 inst_sret 识别
- `cpu_controller.sv`: SRET 与 MRET 共用 STATE_TRAP_RETURN
- `cpu_clint.sv`: SRET 恢复 SPP/SPIE/SIE，PC ← sepc
- U-mode 执行 SRET → 非法指令异常
- mstatus.TSR=1 且 S-mode 执行 SRET → 非法指令异常

#### Step 8: MRET 完善
- `cpu_clint.sv`: MRET 恢复 priv_mode ← MPP（读 mstatus.MPP 字段），MPP ← U(00)，MPIE ← 1

#### Step 9: SFENCE.VMA 指令
- `cpu_decode.sv`: 新增 inst_sfence_vma 识别，实现为 NOP（直接跳到下一条指令）
- mstatus.TVM=1 且 S-mode 执行 SFENCE.VMA → 非法指令异常

#### Step 10: WFI 特权控制
- `cpu_decode.sv`: mstatus.TW=1 且 S/U-mode 执行 WFI → 非法指令异常

#### Step 11: misa 更新
- `cpu_csr.sv`: misa 硬连线值更新为 0x40141100（MXL=1/RV32, I=1, M=1, S=1, U=1）

#### Step 12: mip/sip 联动
- `cpu_csr.sv`: sip[1](SSIP) 可由 S-mode 软件写，其余位只读
- `cpu_clint.sv`: S-mode 中断挂起从 mip 和 sip 联合获取

### 模块接口变更汇总

| 模块 | 变更 |
|------|------|
| `cpu_csr.sv` | 新增 priv_mode/hw_target_priv/S-mode CSR 写输入，新增 S-mode CSR/medeleg/mideleg/csr_access_ok 输出 |
| `cpu_csr_interface.sv` | 新增 priv_mode 传递，新增 S-mode CSR 输出，新增 hw_target_priv/S-mode CSR 写信号 |
| `cpu_trap_csr.sv` | 新增 priv_mode/target_priv/S-mode CSR 输出/csr_access_ok |
| `cpu_trap_manager.sv` | 新增 priv_mode/target_priv/hw_target_priv/S-mode CSR 写信号，ECALL 区分 |
| `cpu_clint.sv` | 完全重写：委托判定、SRET/MRET 区分、S-mode CSR 写、target_priv |
| `cpu_decode.sv` | 新增 dec_is_sret/dec_is_sfence_vma/dec_csr_access_ok，新增 priv_mode/csr_mstatus 输入 |
| `cpu_controller.sv` | 新增 dec_is_sret/dec_is_sfence_vma 输入 |
| `core_top.sv` | 新增 priv_mode 寄存器，新增 S-mode CSR 信号连线，trap 时更新 priv_mode |

### 仿真验证

#### 2026-05-22 tb_simple_cpu_trap 修复与验证
- **问题**: 测试程序 `cpu_test_trap.s` 中 `csrw mstatus, 0x88` 在新 mstatus 写掩码下会清除 MPP[12:11] 为 00(U)，导致 MRET 返回到 U-mode 而非 M-mode
- **修复**: 将 mstatus 写入值从 `0x88` 改为 `0x1888`（MPP=11/M, MPIE=1, MIE=1），从 `0x80` 改为 `0x1880`（MPP=11/M, MPIE=1, MIE=0），确保 MRET 后回到 M-mode
- **附带调整**: `li 0x1888` 展开为 2 条指令（lui+addi），导致指令地址偏移 +4，更新 testbench 中 x20 期望值从 `0x80000038` → `0x8000003c`
- **结果**: tb_simple_cpu_trap 14 PASS, 0 FAIL — ALL TESTS PASSED

#### 2026-05-22 tb_simple_cpu_top 验证
- **结果**: tb_simple_cpu_top 42 PASS, 0 FAIL — ALL TESTS PASSED
- M-mode 向后兼容性确认

### 待完成
- 编写 S/U-mode 特权测试程序（ECALL 委托、SRET、CSR 访问控制、特权切换）
- 更新 `dev\docs\simpleCPU-design-report.md` 文档
