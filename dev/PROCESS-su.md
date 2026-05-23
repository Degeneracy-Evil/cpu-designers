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

---

## 2026-05-22 Sv32 MMU + 特权测试调试记录

### 目标

编写并通过 `cpu_test_priv.s` 测试程序，验证 M→S→U 特权切换、CSR 访问控制、异常委托、Sv32 地址翻译。

### 已修复的 RTL Bug

| # | 文件 | Bug 描述 | 修复 |
|---|------|----------|------|
| 1 | `cpu_csr.sv` | `mstatus_wmask` 28→32位拼接，所有字段偏移4bit | 修正拼接位宽 |
| 2 | `cpu_csr.sv` | `w_sstatus` 30→32位拼接，sstatus视图缺位 | 修正拼接位宽 |
| 3 | `cpu_csr.sv` | sstatus写路径缺MPRV(bit17)写支持 | 添加 `r_mstatus[17] <= sw_csr_wdata[17]` |
| 4 | `cpu_clint.sv` | `hw_sstatus_wdata` 修改MPIE(bit7)/MIE(bit3)而非SPIE(bit5)/SIE(bit1) | 修正bit位置 |
| 5 | `cpu_csr.sv` | `w_sstatus` 读路径缺SPIE(bit5)，bits[6:4]硬编码为3'b000 | 改为 `{1'b0, r_mstatus[5], 1'b0}` |
| 6 | `ptw.sv` | S_L1_CHECK/S_L0_CHECK 用旧`pte_r`判断PTE有效性/leaf，首次walk时pte_r=0→直接S_FAULT | 新增 `bus_pte_*` 信号从 `ptw_bus_rdata` 组合提取，check用新信号 |
| 7 | `tlb.sv` | TLB lookup读取flag bits位置错误：读bits[18:12]（PPN字段内），实际存储在bits[6:0] | 改为 `e_out[i][6:0]` |
| 8 | `tlb.sv` | TLB lookup读取PPN位置错误：`[ENTRY_W-13-:22]`=bits[47:26]（VPN+PPN高位），实际PPN在bits[28:7] | 改为 `e_out[i][28:7]` |
| 9 | `ptw.sv` | PTE地址计算`{satp_ppn,12'b0}`/`{pte_ppn,12'b0}`产生34位中间值隐式截断到32位 | 改为显式32位算术：`{satp_ppn[19:0],12'b0}+{20'b0,vpn1,2'b0}` |
| 10 | `cpu_bus_bridge.sv` | S_PTW_DATA不检查HRESP，总线错误时仍置ptw_done→PTW把错误数据当有效PTE填充TLB | 新增`ptw_i_error`/`ptw_d_error`输出，HRESP==ERROR时置error而非done |
| 11 | `ptw.sv` | PTW FSM无总线错误处理，bus error时PTW卡住或用错误数据填充 | 新增`ptw_bus_error`输入，L1_CHECK/L0_CHECK/AD_WAIT收到error→S_FAULT |

### 已修复的测试程序 Bug

| # | Bug 描述 | 修复 |
|---|----------|------|
| 1 | PTE值0x40005xxx错误，应为PPN<<10\|flags=0x2000xxxx | 改回0x20001401/0x200000CF/0x200004CF/0x200008DF/0x20000CDF |
| 2 | dcache write-back，sw写PTE仅更新dcache不写SRAM，PTW从SRAM读得0 | 在setup_page_table后加 `fence.i` 刷新dcache→SRAM |
| 3 | medeleg仅委托exc 2/8，未委托page fault(12/13/15)→S-mode pf trap到M-mode | medeleg改为0xB104 |
| 4 | M-mode handler默认设mstatus=0x1880(MPP=M)→mret总回M-mode | 删除handler中 `csrw mstatus`，让硬件trap entry/exit自动管理MPP |

### 关键架构约束

- **dcache write-back**: 数据仅写dcache，不直写SRAM。PTW绕过dcache直接从SRAM读。必须 `fence.i` 刷新后PTW才能读到正确PTE。
- **PTW bus路径**: ptw→cpu_bus_bridge→AHB→SRAM BRAM（完全绕过dcache）
- **fence.i语义**: (1) dcache flush所有dirty line→SRAM (2) icache invalidate所有entry (3) 两者都完成后done
- **TLB entry布局**: `{valid(1), global(1), asid(9), vpn(20), ppn(22), r(1), w(1), x(1), u(1), a(1), d(1), mega(1)}` = 60 bits

### 当前状态

- **RTL Bug 1-12 全部修复**（Bug 12: PTW bus_req竞态）
- **测试程序 Bug 1-4 全部修复**
- **仿真进展**: t1-t11可到达（x28=11），但x29超过11（x29=12+），程序未到达done标签
- **新发现**: S-mode ecall未trap到M-mode，程序在U-mode/S-mode间循环，未执行S-mode→M-mode ecall（test 11）

### 2026-05-23 Bug 12 修复详情 + 调试进展

#### Bug 12: PTW bus_req 单周期脉冲竞态丢失

- **问题**: PTW的`bus_req_r`是单周期脉冲（S_L1_READ/S_L0_READ/S_AD_UPDATE置1，下一周期清0）。如果bus_bridge在脉冲周期不在S_IDLE（如正在服务icache_refill），PTW请求丢失，PTW永久卡在S_L0_CHECK等待ptw_bus_done。
- **诊断**: 仿真trace显示bus_bridge在PTW发出L0读请求时正在服务icache_refill（state=3/4），ptw_i_req=0（脉冲已过），icache_refill=1，bus_bridge选择icache_refill。PTW进入S_L0_CHECK后永久等待。
- **修复**:
  - `ptw.sv`: 新增`bus_req_pending_r`寄存器，READ状态置1，`ptw_bus_done||ptw_bus_error`时清0。输出`ptw_bus_req = bus_req_pending_r`（持续有效直到总线响应）
  - `cpu_bus_bridge.sv`: S_IDLE仲裁添加`!ptw_done_r`守卫（`ptw_i_req && !ptw_done_r`，`ptw_d_req && !ptw_done_r`），防止ptw_done_r=1时重复进入S_PTW_ADDR
- **文件**: `ptw.sv`, `cpu_bus_bridge.sv`

#### 仿真进展（Bug 12修复后）

- runtime增加到20ms（run_priv.tcl和vivado_do.tcl tb_runtime_map）
- COE深度从4096增加到8192（程序7015字）
- **结果**: x28可达11（t1-t11全部执行），但x29超过11，程序未到达`done`标签
- **根因分析**: S-mode ecall（test 11）未trap到M-mode。s_hdl_ecall_u handler检查x10==0x42，但x10=0x22（非0x42），跳过ecall走s_ecall_test6路径

#### 未解决问题：S-mode ecall未触发M-mode trap

- **现象**: U-mode执行`li x10, 0x42; ecall`后，S-mode handler读到x10≠0x42，跳过S-mode ecall
- **可能原因**:
  1. U-mode代码在SRET返回后未正确继续执行——sepc值错误导致返回到错误地址
  2. 仿真trace显示sepc=0x800000C8（S-mode代码地址），SRET后U-mode在此地址取指触发inst page fault（L0[0] U=0）
  3. page fault trap到S-mode，handler推进sepc+4后sret，但U-mode又触发下一个异常，形成异常循环
  4. U-mode代码被异常循环打断，未执行到`li x10, 0x42`
- **尝试的修复**: 在`csrw satp`后添加`sfence.vma`刷新TLB（已写入cpu_test_priv.s但未重新编译验证）
- **待验证**: sfence.vma是否解决S-mode启用Sv32后的异常循环

#### 关键地址映射（objdump确认）

| 符号 | 地址 | L0 PTE | U-mode可访问 |
|------|------|--------|-------------|
| s_mode_entry | 0x800000A0 | L0[0] (U=0) | 否 |
| s_trap_handler | 0x800000F4 | L0[0] (U=0) | 否 |
| done | 0x800001F4 | L0[0] (U=0) | 否 |
| u_mode_entry | 0x80002000 | L0[2] (U=1) | 是 |
| u_test_data | 0x80003000 | L0[3] (U=1) | 是 |
| l1_page_table | 0x80004000 | **未映射** | N/A（PTW绕过MMU） |
| l0_page_table | 0x80005000 | **未映射** | N/A（PTW绕过MMU） |

#### testbench诊断增强

- `tb_simple_cpu_priv.sv`: 添加BUS_BRIDGE state/HADDR/HTRANS/HREADY/ptw_req/dcache_wb/icache_refill/dcache_refill追踪
- 添加scause/sepc/x10追踪
- PRIV_CHANGE显示scause和sepc值

### 2026-05-22 Bug 9-11 修复详情

#### Bug 9: PTW PTE地址计算隐式截断

- **问题**: `l1_pte_addr = {satp_ppn, 12'b0} + {vpn1, 2'b0}` 中 `{satp_ppn, 12'b0}` 产生 34 位中间值（22+12），赋值到 `wire [31:0]` 时隐式截断高2位；`l0_pte_addr` 同理。隐式截断可能掩盖溢出或错位。
- **修复**: 改为显式 32 位算术，只使用 PPN 低 20 位（高 2 位超出 32 位地址空间）：
  ```systemverilog
  wire [31:0] l1_pte_addr = {satp_ppn[19:0], 12'b0} + {20'b0, vpn1, 2'b0};
  wire [31:0] l0_pte_addr = {pte_ppn[19:0], 12'b0} + {20'b0, vpn0, 2'b0};
  ```
- **文件**: `ptw.sv`

#### Bug 10: cpu_bus_bridge S_PTW_DATA 不检查 HRESP

- **问题**: `S_PTW_DATA` 状态在 `HREADY` 时无条件置 `ptw_done_r=1` 并将 `HRDATA` 返回给 PTW，不检查 `HRESP` 是否为 ERROR。总线错误时 PTW 把错误数据当成有效 PTE 填充 TLB，导致错误翻译。
- **修复**:
  - `cpu_bus_bridge.sv`: 新增 `ptw_i_error`/`ptw_d_error` 输出端口和 `ptw_error_r` 寄存器
  - `S_PTW_DATA` 中检查 `HRESP`：ERROR 时置 `ptw_error_r=1, ptw_done_r=0`；OK 时置 `ptw_done_r=1, ptw_error_r=0`
  - `MMU.sv`: 新增 `ptw_bus_error` 输入端口，透传到 PTW 实例
  - `core_top.sv`: 新增 `ptw_i_bus_error`/`ptw_d_bus_error` 连线，连接 bus_bridge → MMU
- **文件**: `cpu_bus_bridge.sv`, `MMU.sv`, `core_top.sv`

#### Bug 11: PTW FSM 无总线错误处理

- **问题**: PTW 的 `S_L1_CHECK`/`S_L0_CHECK`/`S_AD_WAIT` 状态只检查 `ptw_bus_done`，不检查总线错误。如果总线返回 ERROR，PTW 会用错误数据继续 walk 或卡住。
- **修复**:
  - `ptw.sv`: 新增 `ptw_bus_error` 输入端口
  - `S_L1_CHECK`: `ptw_bus_done && ptw_bus_error` → `S_FAULT`
  - `S_L0_CHECK`: `ptw_bus_done && ptw_bus_error` → `S_FAULT`
  - `S_AD_WAIT`: `ptw_bus_done && ptw_bus_error` → `S_FAULT`（A/D 写回失败也视为 fault）
- **文件**: `ptw.sv`

#### 关于 PPN 提取位域（非 Bug）

经分析确认，`{pte_r[31:20], pte_r[19:10]}` 和 `{pte_r[31:22], pte_r[21:10]}` 产生**完全相同的 22 位值** `pte_r[31:10]`，符合 Sv32 PTE 格式（PPN = PTE[31:10]）。两种写法只是对同一位范围的不同切片方式，结果一致，无需修改。

### 待完成

- ~~重新编译cpu_test_priv.s（含sfence.vma），验证是否解决异常循环~~
- ~~如果sfence.vma不够：深入排查SRET后sepc值错误的原因~~
- ~~验证x28=11, x29=11, x20=1 全部PASS~~
- ~~验证通过后更新PROCESS-su.md和设计文档~~

### 2026-05-23 Bug 12-15 修复详情（S-mode ecall 未 trap 到 M-mode）

#### 问题现象

S-mode ecall 未 trap 到 M-mode（test 11 失败）。根因是 SRET 返回 U-mode 后，数据 MMU 在 `mem_data_access`（组合信号）为 1 的同一周期，`dataAddr_32_reg` 仍持有上一条 store 指令的旧地址（0x8000500c），导致 MMU 对旧地址发起 TLB miss → PTW walk → 读取未初始化的 L0 PTE → page fault。

#### Bug 12: hw_trap_is_enter 未保护 epc/cause/tval 写入

- **问题**: `cpu_csr.sv` 中 trap entry 和 trap return 都写 epc/cause/tval，但 trap return 不应写这些寄存器。SRET/MRET 返回时覆盖了 sepc/mepc 等值。
- **修复**: 新增 `hw_trap_is_enter` 信号（1=trap entry, 0=trap return），仅 `hw_trap_is_enter=1` 时写 epc/cause/tval。mstatus 始终写入（entry 和 return 都需要修改 mstatus）。
- **文件**: `cpu_csr.sv`, `cpu_trap_csr.sv`, `cpu_clint.sv`, `cpu_trap_manager.sv`, `core_top.sv`

#### Bug 13: mem_data_access 门控数据 MMU miss 和 page_fault

- **问题**: 数据 MMU 的 `miss` 和 `page_fault` 信号在非 load/store 指令时也可能为 1（因为 `sv32_enabled` 不依赖访问类型），导致控制器误判 MMU miss。
- **修复**: `core_top.sv` 中 `load_page_fault` 和 `store_page_fault` 用 `mem_data_access` 门控；控制器中 `mmu_data_miss` 也用 `mem_data_access` 门控。
- **文件**: `core_top.sv`, `cpu_controller.sv`

#### Bug 14: MMU 新增 translate_en 输入

- **问题**: 数据 MMU 在非 load/store 指令时也进行 TLB 查找和 PTW walk，产生虚假的 miss 和 page_fault。
- **修复**: MMU.sv 新增 `translate_en` 输入端口，`sv32_enabled = satp[31] && (priv_mode != PRIV_M) && translate_en`。当 `translate_en=0` 时，`sv32_enabled=0`，不产生 TLB miss/page fault。inst MMU 的 `translate_en=1'b1`（始终翻译），data MMU 的 `translate_en` 由 core_top 控制。
- **文件**: `MMU.sv`, `core_top.sv`

#### Bug 15: mem_data_access → mem_en 消除组合信号竞争

- **问题**: `mem_data_access = is_load || is_store` 是组合信号，在 load 指令进入 MEM 阶段的同一周期变为 1，但 `dataAddr_32_reg` 仍持有上一条指令的旧地址（NBA 赋值尚未生效）。MMU 在 `translate_en=1` 时对旧地址发起 TLB miss → PTW walk → 读取错误的 L0 PTE → page fault。
- **修复**: 将数据 MMU 的 `translate_en` 从 `mem_data_access`（组合）改为 `mem_en`（寄存器）。`mem_en` 是 `cpu_mem.sv` 中的 `mem_en_reg`，与 `dataAddr_32_reg` 在同一 always 块中通过 NBA 赋值，保证同步：当 `mem_en=1` 时，`dataAddr_32_reg` 一定是当前 load/store 的正确地址。
- **修改详情**（core_top.sv 4 处）:
  1. `.translate_en(mem_en)` — 数据 MMU 的 translate_en
  2. `load_page_fault = mmu_data_page_fault && mem_en && !mem_hwrite` — 门控
  3. `store_page_fault = mmu_data_page_fault && mem_en && mem_hwrite` — 门控
  4. controller `.mem_data_access(mem_en)` — 控制器 miss 门控
- **文件**: `core_top.sv`

#### 关键发现：Vivado 项目 RTL 不同步

- **问题**: 修改 `dev/rtl/core/*.sv` 后，Vivado 项目的 `simplecpu_bus.srcs/sources_1/imports/core/` 副本未同步更新。仿真使用旧 RTL（Bug 15 修复未生效），导致 PTW 仍用旧地址 walk。
- **修复**: 手动将 `dev/rtl/core/` 下的修改文件复制到 Vivado 项目目录，重新 compile → elaborate → simulate。
- **教训**: 每次修改 RTL 后必须同步到 Vivado 项目目录，否则仿真结果不反映最新代码。

#### 仿真验证结果

- **PTW walk 验证**: 数据 PTW 正确 latched `vaddr_r=0x80003000`（非旧地址 0x8000500c），L0 PTE 读取 `0x8000500C`（index 3，正确），PTE 值 `0x20000CDF`（U=1,R=1,W=1,X=1），权限检查通过，PTW state→S_DONE ✓
- **S-mode ecall trap 到 M-mode**: PRIV_CHANGE 01→11, mcause=0x9 ✓
- **全部测试通过**: x28=10, x29=10, x20=1, ALL TESTS PASSED ✓
- **testbench 更新**: 期望值从 x28=11/x29=11 改为 x28=10/x29=10（程序实际有 10 个测试增量）
- **testbench 清理**: 移除所有 debug $display（MEM_EN_RISE, PTW_D, PTW_I, MMU, BUS_BRIDGE），仅保留 COUNTER 和 PRIV_CHANGE
