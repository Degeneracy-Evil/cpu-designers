# MMU构建计划

## 目标

建立SV32页式虚拟内存，以及M,S,U权限体系配套的内存权限隔离。

## 背景

当前项目报告见`dev\docs\simpleCPU-design-report.md`。
上一次修改：进度：`dev\PROCESS-su.md`

## 验收

编写程序进行功能验收（见 Step 9 测试用例表）

## 参考资料

上一阶段完成后项目整体报告：dev\docs\simpleCPU-design-report.md
AHB-lite标准文件：dev\docs\AHB-lite\AMBA_AHB-Lite_Spec_Summary.md
APB标准文件：dev\docs\APB\AMBA_APB_Spec_Summary.md
M模式标准：dev\docs\privileged\machine-mode.md
S模式标准：dev\docs\privileged\supervisor-mode.md
U模式标准：dev\docs\privileged\user-mode.md
SV32标准：dev\docs\Mem\sv32-virtual-memory.md

## 工具

vivado_do.tcl：vivado tcl 脚本，使用其进行模拟
tools\rv2coe.py：rv汇编/C程序编译脚本，输出格式HEX/COE/...

## 开发约束

将更改和进度输出到dev\PROCESS-mmu.md中。

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| A/D 位处理 | 硬件自动更新 | PTW 写回 PTE 设置 A/D 位，软件无需处理 A/D 缺失页错误 |
| TLB 容量 | ITLB 16项 + DTLB 16项 | 面积约 2KB 寄存器，足够运行小型 OS |
| SFENCE.VMA 粒度 | 全刷新 | 任何 SFENCE.VMA 刷新全部 TLB 项，Spec 允许过度刷新 |
| PTW-dcache 一致性 | 软件维护 | PTW 绕过 cache，软件修改 PTE 前需刷新 dcache |

## 总体架构

```
core_top
  +-- MMU (inst) --+-- ITLB (16项 CAM)
  |                 +-- PTW (FSM: 页表遍历 + A/D位写回)
  +-- MMU (data) --+-- DTLB (16项 CAM)
  |                 +-- PTW (FSM: 页表遍历 + A/D位写回)
  +-- cpu_bus_bridge  <-- 新增 PTW 读写请求源
  +-- cpu_trap_manager <-- 新增页错误异常码 12/13/15
```

## 翻译流程

```
vaddr -> [satp.MODE=0? -> 直通]
      -> [priv_mode=M? -> 直通]
      -> [TLB 查找] -> 命中 -> 权限检查 -> paddr
                    -> 未命中 -> PTW 遍历 -> A/D位更新 -> 填充TLB -> paddr
                                                    -> 权限/有效性错误 -> 页错误异常
```

---

## Step 1: 页错误异常基础设施

修改文件: `cpu_trap_manager.sv`, `cpu_clint.sv`, `cpu_csr.sv`, `cpu_decode.sv`

1. 新增异常码：在 `cpu_trap_manager.sv` 中增加：
   - 12 = 指令页错误 (Instruction page fault)
   - 13 = Load 页错误 (Load page fault)
   - 15 = Store/AMO 页错误 (Store/AMO page fault)

2. stval/mtval 写入：页错误发生时，将触发错误的虚拟地址写入 `stval`（若委托到 S-mode）或 `mtval`（若进入 M-mode）。需在 `cpu_clint.sv` 中新增 `hw_stval` / `hw_mtval` 写路径，接收来自 MMU 的 `page_fault_vaddr`。

3. satp 写 TVM 陷阱：当 `priv_mode=S` 且 `mstatus.TVM=1` 时，对 `satp`（0x180）的写入触发非法指令异常。当前仅 SFENCE.VMA 有 TVM 检查，需扩展到 satp 写。

4. satp MODE 过滤：RV32 下 satp[31] 只有 0/1 两种合法值，天然合法，无需额外 WARL 逻辑。

---

## Step 2: TLB 模块

新建文件: `dev/rtl/core/tlb.sv`

接口：
```systemverilog
module tlb #(
    parameter ENTRIES = 16
)(
    input  clk, reset,
    // 查找
    input  [19:0] lookup_vpn,
    input  [8:0]  lookup_asid,
    input         lookup_req,
    output        lookup_hit,
    output [21:0] lookup_ppn,
    output        lookup_r, lookup_w, lookup_x, lookup_u,
    output        lookup_a, lookup_d, lookup_g,
    output        lookup_is_megapage,
    // 填充
    input         fill_req,
    input  [19:0] fill_vpn,
    input  [8:0]  fill_asid,
    input  [21:0] fill_ppn,
    input         fill_r, fill_w, fill_x, fill_u,
    input         fill_a, fill_d, fill_g,
    input         fill_is_megapage,
    // 刷新
    input         flush_all   // SFENCE.VMA: 刷新全部
);
```

实现要点：
- 寄存器数组存储 16 个 TLB 项，每项约 58 位
- 查找：并行比较所有项的 vpn + asid（或 global 位），命中输出对应 PPN 和权限位
- 填充：使用 round-robin 指针选择替换项，写入新翻译结果
- 刷新：flush_all 清除所有项的 valid 位
- Megapage 标志：每项存储 is_megapage 位，用于物理地址拼接时区分 4KiB 页和 4MiB 大页

TLB 项格式（约 58 位）：

| 字段 | 位宽 | 描述 |
|------|------|------|
| valid | 1 | 有效位 |
| global | 1 | 全局映射 (G 位) |
| asid | 9 | 地址空间标识符 |
| vpn | 20 | 虚拟页号 |
| ppn | 22 | 物理页号 |
| r/w/x/u | 4 | 权限位 |
| a/d | 2 | 访问/脏位 |
| is_megapage | 1 | 大页标志 |

---

## Step 3: 页表遍历器 (PTW)

新建文件: `dev/rtl/core/ptw.sv`

接口：
```systemverilog
module ptw(
    input  clk, reset,
    // 控制输入
    input  [31:0] satp,
    input  [1:0]  priv_mode,
    input         mstatus_sum, mstatus_mxr,
    input  [1:0]  access_type,  // 00=fetch, 01=load, 10=store
    // 启动
    input  [31:0] walk_vaddr,
    input         walk_req,
    output        walk_done,
    output        walk_fault,
    output [3:0]  walk_fault_cause,  // 12/13/15
    output [31:0] walk_fault_vaddr,
    // TLB 填充结果
    output [21:0] walk_ppn,
    output        walk_r, walk_w, walk_x, walk_u,
    output        walk_a, walk_d, walk_g,
    output        walk_is_megapage,
    // 总线接口 (经 bus_bridge)
    output        ptw_bus_req,
    output [31:0] ptw_bus_addr,
    output        ptw_bus_we,
    output [31:0] ptw_bus_wdata,
    input  [31:0] ptw_bus_rdata,
    input         ptw_bus_done
);
```

FSM 状态：
```
IDLE -> L1_READ -> L1_CHECK -> L0_READ -> L0_CHECK ->
PERM_CHECK -> AD_UPDATE -> AD_WAIT -> DONE / FAULT
```

各状态逻辑：

| 状态 | 操作 |
|------|------|
| IDLE | 等待 walk_req，锁存 walk_vaddr，计算 L1 PTE 地址 = satp.PPN * 4096 + VPN[1] * 4 |
| L1_READ | 发起 PTE 读请求到总线 |
| L1_CHECK | 检查 PTE：V=0 或 R=0&&W=1 -> FAULT；R\|X=1 -> 叶节点(megapage)，转 PERM_CHECK；否则 -> 计算 L0 PTE 地址 = PTE.PPN * 4096 + VPN[0] * 4，转 L0_READ |
| L0_READ | 发起 PTE 读请求到总线 |
| L0_CHECK | 检查 PTE：V=0 或 R=0&&W=1 -> FAULT；R\|X=1 -> 叶节点，转 PERM_CHECK；否则 -> FAULT（非叶但已是最低级） |
| PERM_CHECK | 检查权限：U-bit 与特权级/SUM/MXR 的组合；R/W/X 与 access_type 的匹配；megapage 对齐检查（PPN[0]!=0 -> FAULT）。若 A=0 或 (store && D=0)，转 AD_UPDATE；否则转 DONE |
| AD_UPDATE | 构造新 PTE 值（设置 A=1，若是 store 则 D=1），发起 PTE 写请求到总线 |
| AD_WAIT | 等待写完成，转 DONE |
| DONE | 输出翻译结果，walk_done=1 |
| FAULT | 输出页错误，walk_fault=1，根据 access_type 生成 cause (12/13/15) |

权限检查详细逻辑：
```
// U-bit 检查
if (priv_mode == U_MODE && !pte.u) -> FAULT
if (priv_mode == S_MODE && pte.u) {
    if (access_type == FETCH) -> FAULT  // S-mode 永不能执行 U-mode 页
    if (!mstatus_sum) -> FAULT          // SUM=0 时 S-mode 不能访问 U-mode 页
}

// R/W/X 检查
if (access_type == FETCH && !pte.x) -> FAULT
if (access_type == LOAD) {
    if (!pte.r && !(pte.x && mstatus_mxr)) -> FAULT
}
if (access_type == STORE && !pte.w) -> FAULT

// Megapage 对齐检查
if (is_megapage && pte.ppn[9:0] != 0) -> FAULT
```

A/D 位写回：
- 单 hart 系统，无需原子 compare-and-swap，直接写回即可
- 写回地址 = 叶 PTE 的物理地址（PTW 已知）
- 写回值 = 原 PTE 值 | (1<<6) 设置 A 位，若是 store 则再 | (1<<7) 设置 D 位

---

## Step 4: 重写 MMU 模块

修改文件: `dev/rtl/core/MMU.sv`

新接口：
```systemverilog
module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input  clk, reset,
    // 翻译请求
    input  [31:0] vaddr,
    input  [1:0]  access_type,   // 00=fetch, 01=load, 10=store
    input  [1:0]  priv_mode,
    input  [31:0] satp,
    input         mstatus_sum,
    input         mstatus_mxr,
    // 翻译结果
    output [31:0] paddr,
    output        miss,           // TLB 未命中，需要 PTW
    output        page_fault,
    output [3:0]  page_fault_cause,
    output [31:0] page_fault_vaddr,
    // PTW 完成信号
    input         ptw_done,       // PTW 完成，TLB 已填充
    input         ptw_fault,      // PTW 发现页错误
    // SFENCE.VMA
    input         sfence_vma,
    // PTW 总线接口 (直连 bus_bridge)
    output        ptw_bus_req,
    output [31:0] ptw_bus_addr,
    output        ptw_bus_we,
    output [31:0] ptw_bus_wdata,
    input  [31:0] ptw_bus_rdata,
    input         ptw_bus_done
);
```

内部逻辑：
1. Bare 模式 / M-mode 直通：satp[31]==0 || priv_mode==M -> paddr=vaddr, miss=0
2. TLB 查找：用 vaddr[31:12] 作为 VPN，satp[30:22] 作为 ASID 查 TLB
3. TLB 命中：权限检查（与 PTW 中相同的逻辑，但此时 A/D 已为 1 因为 TLB 只缓存 A=1 的项）
   - 权限通过 -> 拼接物理地址，miss=0
   - 权限失败 -> page_fault=1
4. TLB 未命中：miss=1，启动 PTW
5. 物理地址拼接：
   - 普通页：paddr = {tlb_ppn, vaddr[11:0]}（34 位，截断到 32 位）
   - 大页：paddr = {tlb_ppn[21:10], vaddr[21:0]}（34 位，截断到 32 位）
6. SFENCE.VMA：sfence_vma 信号触发 TLB flush_all

TLB 缓存策略：仅缓存 A=1（且 store 页 D=1）的翻译结果。这样 TLB 命中时无需再检查 A/D 位。

---

## Step 5: 修改 cpu_bus_bridge

修改文件: `dev/rtl/core/cpu_bus_bridge.sv`

新增 PTW 作为第 6/7 个请求源（ITLB PTW + DTLB PTW）：

| 优先级 | 请求源 | 类型 |
|--------|--------|------|
| 1 (最高) | icache MMIO | 单拍读 |
| 2 | dcache MMIO | 单拍读/写 |
| 3 | PTW (inst) | 单拍读/写 |
| 4 | PTW (data) | 单拍读/写 |
| 5 | dcache writeback | INCR8 突发写 |
| 6 | icache refill | INCR8 突发读 |
| 7 | dcache refill | INCR8 突发读 |

新增端口：
```systemverilog
// PTW inst
input         ptw_i_req,
input  [31:0] ptw_i_addr,
input         ptw_i_we,
input  [31:0] ptw_i_wdata,
output [31:0] ptw_i_rdata,
output        ptw_i_done,
// PTW data
input         ptw_d_req,
input  [31:0] ptw_d_addr,
input         ptw_d_we,
input  [31:0] ptw_d_wdata,
output [31:0] ptw_d_rdata,
output        ptw_d_done,
```

新增 FSM 状态：PTW_ADDR -> PTW_DATA（单拍读或写，与 MMIO 类似）

注意：PTW 请求与流水线其他请求互斥（TLB miss 时流水线已 stall），不会产生仲裁冲突。

---

## Step 6: 修改 core_top 连线

修改文件: `dev/rtl/core/core_top.sv`

1. MMU 实例扩展：为 u_mmu_inst 和 u_mmu_data 连接新增端口：
   - satp <- 从 CSR 子系统
   - priv_mode <- 已有
   - mstatus_sum <- r_mstatus[18]
   - mstatus_mxr <- r_mstatus[19]
   - access_type <- inst MMU 固定 2'b00(fetch)；data MMU 根据控制器状态决定 load/store
   - sfence_vma <- 控制器信号

2. PTW 总线连线：MMU 的 ptw_bus_* 连接到 cpu_bus_bridge 的新端口

3. 页错误信号连线：
   - mmu_inst_page_fault / mmu_data_page_fault -> cpu_trap_manager
   - mmu_*_page_fault_cause -> 异常码
   - mmu_*_page_fault_vaddr -> stval/mtval 写入值

4. 流水线 stall 信号：
   - mmu_inst_miss / mmu_data_miss -> 控制器 stall 条件

---

## Step 7: 修改控制器

修改文件: `dev/rtl/core/cpu_controller.sv`

1. 新增 MMU 等待逻辑：
   - FETCH 状态：若 mmu_inst_miss，保持 FETCH 状态等待 PTW 完成
   - MEM 状态：若 mmu_data_miss，保持 MEM 状态等待 PTW 完成

2. 页错误 trap：
   - 若 mmu_inst_page_fault，转入 TRAP_ENTER，cause=12
   - 若 mmu_data_page_fault，转入 TRAP_ENTER，cause=13(load) 或 15(store)

3. SFENCE.VMA 扩展：
   - 当前 SFENCE.VMA 解码后直接跳到下一条指令（NOP）
   - 修改为：发出 sfence_vma_req 脉冲到 MMU，等待 TLB 刷新完成后再继续
   - 简单实现：SFENCE.VMA 在控制器中增加 1 周期延迟发出 flush 脉冲

---

## Step 8: 修改 cpu_decode / cpu_csr

修改文件: `cpu_decode.sv`, `cpu_csr.sv`

1. satp 写 TVM 陷阱：在 CSR 写译码阶段，若 priv_mode==S 且 mstatus.TVM==1 且目标 CSR 为 satp（0x180），触发非法指令异常

2. SFENCE.VMA 刷新信号：cpu_decode.sv 中 inst_sfence_vma 识别已有，需输出到控制器/MMU

---

## Step 9: 验收测试

新建文件: `dev/program_source/cpu_test_mmu.s`

### 测试用例

| 编号 | 测试项 | 描述 |
|------|--------|------|
| T1 | Bare 模式直通 | satp=0，验证虚拟地址=物理地址，已有测试应全部通过 |
| T2 | Sv32 基本翻译 | M-mode 设置二级页表，S-mode 开启 Sv32，验证地址翻译正确 |
| T3 | 4KiB 页 + 4MiB 大页 | 分别测试普通页和大页翻译 |
| T4 | U-mode 页隔离 | U-mode 只能访问 U=1 的页，访问 U=0 的页触发页错误 |
| T5 | S-mode SUM 位 | SUM=0 时 S-mode 访问 U=1 页触发页错误；SUM=1 时允许 |
| T6 | S-mode 不可执行 U 页 | 无论 SUM 如何，S-mode 在 U=1 页取指触发页错误 |
| T7 | MXR 位 | MXR=1 时 S-mode 可从 X=1,R=0 的页 load |
| T8 | 权限错误 | R=0 页 load、W=0 页 store、X=0 页取指均触发页错误 |
| T9 | A/D 位硬件更新 | PTE 中 A=0，首次访问后硬件自动设置 A=1；D=0 页 store 后 D=1 |
| T10 | SFENCE.VMA | 修改 PTE 后执行 SFENCE.VMA，验证新翻译生效 |
| T11 | TLB 缓存 | 首次访问填充 TLB，再次访问应命中 TLB（无 PTW） |
| T12 | M-mode 绕过 | M-mode 下无论 satp 如何，地址不翻译 |
| T13 | 非法 PTE | V=0 或 R=0&&W=1 的 PTE 触发页错误 |
| T14 | satp TVM 陷阱 | TVM=1 时 S-mode 写 satp 触发非法指令异常 |

### 测试程序结构

```asm
# M-mode 引导
1. 设置页表结构（在物理内存中写入 PTE）
2. 设置 satp 指向根页表
3. 设置 medeleg 委托页错误到 S-mode
4. 通过 SRET 切换到 S-mode

# S-mode 测试
5. 执行各种内存访问（load/store/execute）
6. 验证翻译结果
7. 触发权限错误，验证页错误 trap

# U-mode 测试
8. 通过 SRET 切换到 U-mode
9. 执行内存访问，验证隔离
```

### 新建 testbench

新建文件: `dev/tb/tb_simple_cpu_mmu.sv`

- 加载 cpu_test_mmu.hex 到指令存储器
- 运行足够周期
- 检查关键寄存器值和 trap 计数

---

## Step 10: 进度记录

新建文件: `dev/PROCESS-mmu.md`

按步骤记录实现过程、修改的模块、接口变更、仿真结果。

---

## 实现顺序与依赖关系

```
Step 1 (异常基础) -----------------------------------+
                                                       |
Step 2 (TLB 模块) -----------------------------------+|
                                                       ||  Step 6 (core_top 连线)
Step 3 (PTW 模块) -----------------------------------+|       |
                                                       ||       |
Step 4 (MMU 重写, 依赖 Step 2+3) --------------------+|       |  Step 9 (验收测试)
                                                       |        |      |
Step 5 (bus_bridge, 可与 Step 4 并行) ----------------+|       |      |
                                                       |        |      |
Step 7 (控制器, 依赖 Step 4+5+6) ---------------------+|       |      |
                                                       |        |      |
Step 8 (decode/csr, 可与 Step 7 并行) ----------------+        |      |
                                                                |      |
                                                         Step 10 (进度记录)
```

建议实施顺序：Step 1 -> Step 2 -> Step 3 -> Step 4 -> Step 5 -> Step 6 -> Step 7 -> Step 8 -> Step 9 -> Step 10

---

## 模块接口变更汇总

| 模块 | 变更类型 | 变更描述 |
|------|----------|----------|
| tlb.sv | 新建 | TLB CAM 模块，16 项，查找/填充/刷新 |
| ptw.sv | 新建 | 页表遍历 FSM，8 状态，含 A/D 位写回 |
| MMU.sv | 重写 | 从直通改为 Sv32 翻译：TLB + PTW + 权限检查 |
| cpu_bus_bridge.sv | 修改 | 新增 PTW inst/data 读写请求源 |
| core_top.sv | 修改 | MMU 端口扩展，PTW 总线连线，页错误连线 |
| cpu_controller.sv | 修改 | TLB miss stall，页错误 trap，SFENCE.VMA flush |
| cpu_trap_manager.sv | 修改 | 新增页错误异常码 12/13/15 |
| cpu_clint.sv | 修改 | 页错误时 stval/mtval 写入 fault_vaddr |
| cpu_decode.sv | 修改 | satp 写 TVM 陷阱检查 |
| cpu_csr.sv | 修改 | satp 写 TVM 陷阱相关信号输出 |
| cpu_test_mmu.s | 新建 | MMU 验收测试程序 |
| tb_simple_cpu_mmu.sv | 新建 | MMU 验收 testbench |

---

## 风险与注意事项

1. 物理地址宽度：Sv32 产生 34 位物理地址，当前总线为 32 位。截断低 32 位，物理内存限 4GiB（对本系统足够）。
2. PTW 递归翻译：PTW 使用物理地址直接访问内存，不经过 MMU，无递归风险。
3. dcache 一致性：PTW 绕过 cache，软件修改 PTE 前必须刷新 dcache（FENCE.I + cache flush），然后 SFENCE.VMA。
4. A/D 位写回原子性：单 hart 系统，PTW 写回期间流水线已 stall，无并发修改风险。
5. 向后兼容：satp=0（Bare 模式）时 MMU 直通，所有现有测试应无修改通过。
