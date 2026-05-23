# MMU (Sv32) 实现进度

## 2026-05-22 实现记录

### 已完成

#### Step 1: 页错误异常基础设施

- `cpu_trap_manager.sv`: 新增页错误异常输入 `inst_page_fault`/`load_page_fault`/`store_page_fault` 及对应 vaddr/pc 信号；新增 `inst_page_fault_pending`/`data_page_fault_pending` 输出；异常码 12(指令页错误)/13(Load页错误)/15(Store页错误) 加入异常仲裁
- `cpu_trap_csr.sv`: 透传新增页错误信号到 `cpu_trap_manager`
- `cpu_decode.sv`: 新增 satp 写 TVM 陷阱检查（`priv_mode=S && TVM=1 && csr_addr=SATP && csr_is_write` → 非法指令异常）

#### Step 2: TLB 模块

- 新建 `dev/rtl/core/tlb.sv`
- 参数化设计，默认 16 项 CAM
- 查找：并行 VPN + ASID 匹配（全局映射忽略 ASID）
- 填充：round-robin 替换策略
- 刷新：`flush_all` 清除所有 valid 位
- TLB 项格式：valid(1) + global(1) + asid(9) + vpn(20) + ppn(22) + rwxu(4) + ad(2) + is_megapage(1) = 61 位

#### Step 3: 页表遍历器 (PTW)

- 新建 `dev/rtl/core/ptw.sv`
- 10 状态 FSM: IDLE → L1_READ → L1_CHECK → L0_READ → L0_CHECK → PERM_CHECK → AD_UPDATE → AD_WAIT → DONE / FAULT
- 权限检查：U-bit 与特权级/SUM/MXR 组合；R/W/X 与 access_type 匹配；megapage 对齐检查
- A/D 位硬件自动更新：单 hart 系统，直接写回 PTE（无需原子 compare-and-swap）
- 总线接口：单拍读/写请求，经 bus_bridge 访问物理内存

#### Step 4: 重写 MMU 模块

- `MMU.sv` 从直通改为完整 Sv32 实现
- Bare 模式 / M-mode 直通：`satp[31]==0 || priv_mode==M` → `paddr=vaddr`
- TLB 查找：组合逻辑，命中时立即输出物理地址
- TLB 未命中：启动 PTW，控制器 stall 等待
- TLB 命中但权限错误：输出 page_fault 信号
- 物理地址拼接：普通页 `{ppn, vaddr[11:0]}`；大页 `{ppn[21:10], vaddr[21:0]}`
- SFENCE.VMA：触发 TLB flush_all

#### Step 5: 修改 cpu_bus_bridge

- 新增 PTW inst/data 读写请求源（优先级在 MMIO 之后、cache 操作之前）
- 新增 FSM 状态：S_PTW_ADDR → S_PTW_DATA（单拍读/写）
- PTW 请求与流水线其他请求互斥（TLB miss 时流水线已 stall）

#### Step 6: 修改 core_top 连线

- MMU 实例扩展：连接 satp, priv_mode, mstatus_sum, mstatus_mxr, access_type, sfence_vma
- PTW 总线连线：MMU ptw_bus_* → bus_bridge 新端口
- 页错误信号连线：MMU page_fault → trap_manager
- SFENCE.VMA 脉冲：`id_valid && id_done && dec_is_sfence_vma`

#### Step 7: 修改控制器

- `cpu_controller.sv`: 新增 `inst_page_fault_pending`/`data_page_fault_pending`/`mmu_inst_miss`/`mmu_data_miss` 输入
- FETCH 状态：`inst_page_fault_pending` → TRAP_ENTER；`mmu_inst_miss` → 保持 FETCH 等待
- MEM 状态：`data_page_fault_pending` → TRAP_ENTER；`mmu_data_miss` → 保持 MEM 等待

#### Step 8: 修改 cpu_decode

- satp 写 TVM 陷阱：`is_csr && csr_addr==SATP && csr_is_write && TVM && priv_mode==S` → 非法指令异常

### 模块接口变更汇总

| 模块 | 变更 |
|------|------|
| `tlb.sv` | **新建** TLB CAM 模块，16 项，查找/填充/刷新 |
| `ptw.sv` | **新建** 页表遍历 FSM，10 状态，含 A/D 位写回 |
| `MMU.sv` | **重写** 从直通改为 Sv32 翻译：TLB + PTW + 权限检查 |
| `cpu_bus_bridge.sv` | **修改** 新增 PTW inst/data 读写请求源，新增 S_PTW_ADDR/S_PTW_DATA 状态 |
| `core_top.sv` | **修改** MMU 端口扩展，PTW 总线连线，页错误连线，SFENCE.VMA 脉冲 |
| `cpu_controller.sv` | **修改** 新增页错误/MMU miss 输入，FETCH/MEM 状态增加 stall 和 trap 逻辑 |
| `cpu_trap_manager.sv` | **修改** 新增页错误异常码 12/13/15，新增页错误输入/输出 |
| `cpu_trap_csr.sv` | **修改** 透传页错误信号 |
| `cpu_decode.sv` | **修改** satp 写 TVM 陷阱检查 |

### 仿真验证

#### 2026-05-22 tb_simple_cpu_top 验证（Bare 模式向后兼容）

- **结果**: 42 PASS, 0 FAIL — ALL TESTS PASSED
- satp=0（Bare 模式）下 MMU 直通，所有现有测试无修改通过

#### 2026-05-22 tb_simple_cpu_trap 验证

- **结果**: 14 PASS, 0 FAIL — ALL TESTS PASSED
- M/S 模式陷阱机制向后兼容

### Vivado 编译修复

#### 2026-05-22 Vivado 2018.3 xvlog 编译错误修复

- **问题**: Vivado 2018.3 xvlog 不支持 ANSI 风格端口声明中的 `output reg`，报 `procedural assignment to a non-register` 错误
- **修复方案**: 将 `output reg` 改为 `output`（隐式 wire）+ 内部 `reg _r` + `assign` 连接

| 文件 | 信号 | 修复方式 |
|------|------|----------|
| `cpu_decode.sv` | `dec_csr_access_ok` | `output` + `reg dec_csr_access_ok_r` + `assign dec_csr_access_ok = dec_csr_access_ok_r` |
| `cpu_csr.sv` | `csr_access_ok` | `output` + `reg csr_access_ok_r` + `assign csr_access_ok = csr_access_ok_r` |
| `cpu_csr.sv` | `sw_csr_rdata` | `output [31:0]` + `reg [31:0] sw_csr_rdata_r` + `assign sw_csr_rdata = sw_csr_rdata_r` |

- **问题**: `MMU.sv` 中 `ptw_fill_*` 线网声明在 TLB 实例之后，导致隐式声明冲突
- **修复**: 将所有 `wire ptw_fill_*` 和 `wire ptw_fault_*_out` 声明移至 TLB/PTW 实例之前；`assign ptw_fill_vpn/asid` 也前移

- **问题**: `MMU.sv` 中 `tlb_perm_fault` 声明为 `wire` 但在 `always @(*)` 中赋值
- **修复**: 改为 `reg tlb_perm_fault`

- **问题**: `core_top.sv` 中 `u_trap_csr` 实例的 `.cycle_en(cycle_en)` 端口连接重复
- **修复**: 删除重复行

- **问题**: `cpu_controller.sv` 缺少 `fencei_done` 输入端口
- **修复**: 添加 `input fencei_done` 端口

- **验证结果**: Vivado compile + elaborate 均通过，0 ERROR

### 待完成

- 完善 MMU 验收测试程序 `cpu_test_mmu.s`（当前测试未通过，需调试页表设置和 Sv32 翻译流程）
- 编写更全面的 Sv32 测试用例（权限隔离、大页、A/D 位更新、SFENCE.VMA 等）
- 更新 `dev\docs\simpleCPU-design-report.md` 文档
