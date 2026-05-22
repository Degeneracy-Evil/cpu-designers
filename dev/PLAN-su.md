# 完整特权架构构建计划

## 目标

建立M、S、U完整三级特权结构。

仅构建对应CSR和相关指令，暂不考虑权限隔离（即页表和PMP都暂不实现）

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。

## 验收

确认对应CSR和相关指令功能正确。

## 参考资料

上一阶段完成后项目整体报告：dev\docs\simpleCPU-design-report.md
AHB-lite标准文件：dev\docs\AHB-lite\AMBA_AHB-Lite_Spec_Summary.md
APB标准文件：dev\docs\APB\AMBA_APB_Spec_Summary.md
M模式标准：dev\docs\privileged\machine-mode.md
S模式标准：dev\docs\privileged\supervisor-mode.md
U模式标准：dev\docs\privileged\user-mode.md

## 工具

vivado_do.tcl：vivado tcl 脚本，使用其进行模拟
tools\rv2coe.py：rv汇编/C程序编译脚本，输出格式HEX/COE/...

## 开发约束

将更改和进度输出到dev\PROCESS-su.md中。

---

## 现状分析

当前 CPU 仅支持 M-mode 单一特权级：
- **CSR**：仅实现 M-mode CSR（mstatus/mie/mtvec/mepc/mcause/mtval/mip 等）
- **特权指令**：仅支持 MRET，ECALL 固定产生 exception code 11
- **mstatus**：仅跟踪 MPP[12:11]/MPIE[7]/MIE[3] 三个字段
- **无特权级寄存器**：CPU 始终运行在 M-mode，无权限检查
- **陷阱路由**：所有异常/中断固定进入 M-mode

## 实现范围

| 类别 | 具体内容 |
|------|----------|
| **特权级寄存器** | 新增 2-bit `priv_mode`（00=U, 01=S, 11=M），复位为 M |
| **S-mode CSR** | sstatus, sie, stvec, sscratch, sepc, scause, stval, sip, satp, scounteren |
| **委托 CSR** | medeleg, mideleg |
| **mstatus 扩展** | 新增 SIE/SPIE/SPP/MPRV/MXR/SUM/TVM/TW/TSR/FS/XS/SD 字段 |
| **misa 更新** | bit18(S)=1, bit20(U)=1 → 0x40141100 |
| **特权指令** | SRET, SFENCE.VMA（NOP 实现） |
| **ECALL 区分** | U→code 8, S→code 9, M→code 11 |
| **陷阱委托** | medeleg/mideleg 控制陷阱路由到 S 还是 M |
| **CSR 访问控制** | 按当前 priv_mode 检查 CSR 地址合法性 |
| **特权指令检查** | SRET 仅 S/M 可执行；WFI 在 S/U 下受 TW 控制 |

## 分步实现方案

### Step 1：特权级寄存器与基础设施

修改 `core_top.sv`：
- 新增 `reg [1:0] priv_mode` 寄存器，复位为 `2'b11`（M-mode）
- 将 `priv_mode` 传递给 `cpu_trap_csr`、`cpu_decode`、`cpu_controller` 等子模块
- Trap 进入时根据目标特权级更新 `priv_mode`
- MRET/SRET 返回时根据 xPP 恢复 `priv_mode`

### Step 2：mstatus 扩展

修改 `cpu_csr.sv`：
- 扩展 mstatus 字段：SIE[1], SPIE[5], SPP[8], MPRV[17], MXR[19], SUM[18], TVM[20], TW[21], TSR[22], FS[14:13], XS[16:15], SD[31]（只读摘要）
- 复位值：`32'h0000_1800`（MPP=3, SPP=0, MPIE=0, MIE=0, SPIE=0, SIE=0）
- 更新写掩码，仅允许写合法字段
- sstatus 视图：mstatus 的子集（SIE/SPIE/SPP/MXR/SUM/FS/XS/SD）

### Step 3：新增 S-mode CSR 与委托 CSR

修改 `cpu_csr.sv`：
- 新增 S-mode 寄存器：r_sie(0x104), r_stvec(0x105), r_sscratch(0x140), r_sepc(0x141), r_scause(0x142), r_stval(0x143), r_sip(0x144), r_satp(0x180), r_scounteren(0x106)
- 新增委托寄存器：r_medeleg(0x302), r_mideleg(0x303)
- sstatus(0x100)：读返回 mstatus 子集，写修改 mstatus 对应位

### Step 4：CSR 访问控制

修改 `cpu_csr.sv` + `cpu_decode.sv`：
- CSR 地址空间权限规则：
  - 0x000-0x0FF：U-mode 可访问（非特权 CSR）
  - 0x100-0x1FF：S-mode CSR，S/M 可读写
  - 0x300-0x3FF：M-mode CSR，仅 M 可读写
  - 0xC00-0xC1F：计数器，U 访问受 mcounteren/scounteren 控制
  - 0xF00-0xFFF：只读，M 可读
- S-mode 试图访问 M-mode 专属 CSR → 非法指令异常
- U-mode 试图访问 S/M CSR → 非法指令异常

### Step 5：ECALL 异常码区分

修改 `cpu_trap_manager.sv`：
- ECALL 异常码由当前 `priv_mode` 决定：U(00)→8, S(01)→9, M(11)→11

### Step 6：陷阱委托机制

修改 `cpu_clint.sv` + `cpu_trap_manager.sv`：
- 陷阱目标判定：中断看 mideleg[cause]，异常看 medeleg[cause]
- 委托到 S-mode：写 sstatus(SPP/SPIE/SIE), sepc, scause, stval，跳转 stvec
- 进入 M-mode：写 mstatus(MPP/MPIE/MIE), mepc, mcause, mtval，跳转 mtvec
- hw_csr_wen 扩展为可写 S-mode CSR

### Step 7：SRET 指令

修改 `cpu_decode.sv`：新增 inst_sret 识别
修改 `cpu_controller.sv`：SRET 复用 STATE_TRAP_RETURN
修改 `cpu_clint.sv`：SRET 恢复 SPP/SPIE/SIE，priv_mode ← SPP
若 mstatus.TSR=1 且当前在 S-mode → 非法指令异常

### Step 8：MRET 完善

修改 `cpu_clint.sv`：
- MRET：priv_mode ← MPP（读 mstatus.MPP 字段），MPP ← 00（U），MPIE ← 1

### Step 9：SFENCE.VMA 指令

修改 `cpu_decode.sv`：新增 inst_sfence_vma 识别，实现为 NOP
若 mstatus.TVM=1 且当前在 S-mode → 非法指令异常

### Step 10：WFI 特权控制

若 mstatus.TW=1 且当前在 S/U-mode 执行 WFI → 非法指令异常

### Step 11：misa 更新

misa 硬连线值：bit8(I)=1, bit12(M)=1, bit18(S)=1, bit20(U)=1 → 0x40141100

### Step 12：mip/sip 联动

sip 是 mip 的子集：SSIP 可由 S-mode 软件写，STIP/SEIP 只读

## 模块接口变更汇总

| 模块 | 新增输入 | 新增输出 | 说明 |
|------|----------|----------|------|
| `core_top` | — | `priv_mode[1:0]` | 特权级寄存器 |
| `cpu_csr` | `priv_mode[1:0]` | `csr_access_ok`, S-mode CSR 输出 | CSR 访问控制 |
| `cpu_csr_interface` | `priv_mode[1:0]` | — | 传递特权级 |
| `cpu_trap_csr` | `priv_mode[1:0]`, `dec_is_sret` | `target_priv[1:0]` | 陷阱/CSR 联动 |
| `cpu_trap_manager` | `priv_mode[1:0]`, `dec_is_sret` | `target_priv[1:0]` | 委托判定 |
| `cpu_clint` | `priv_mode[1:0]`, S-mode CSR, medeleg/mideleg | `target_priv[1:0]`, S-mode CSR 写 | 委托路由 |
| `cpu_decode` | `priv_mode[1:0]` | `dec_is_sret`, `dec_is_sfence` | 新指令识别 |
| `cpu_controller` | `dec_is_sret` | — | SRET 状态处理 |

## 验收测试方案

1. **基本 CSR 读写**：S/M 模式下读写 sstatus/sie/stvec 等 S-mode CSR
2. **CSR 访问控制**：U-mode 访问 S/M CSR 触发非法指令异常
3. **ECALL 区分**：U-mode ECALL → code 8, S-mode → code 9, M-mode → code 11
4. **委托机制**：设置 medeleg/mideleg 后，异常/中断路由到 S-mode
5. **SRET**：S-mode 陷阱返回到 U-mode，恢复 SIE/SPP
6. **MRET 返回 S**：MPP=01 时 MRET 返回 S-mode
7. **特权级切换**：M→S→U→S(trap)→M(trap)→S(mret)→U(sret) 完整流程
8. **satp 读写**：Bare 模式下 satp 可读写但不影响地址翻译

## 实现顺序

```
Step 1 (priv_mode) → Step 2 (mstatus扩展) → Step 3 (S-mode CSR)
→ Step 4 (CSR访问控制) → Step 5 (ECALL区分) → Step 6 (委托机制)
→ Step 7 (SRET) → Step 8 (MRET完善) → Step 9 (SFENCE.VMA)
→ Step 10 (WFI控制) → Step 11 (misa更新) → Step 12 (mip/sip联动)
```
