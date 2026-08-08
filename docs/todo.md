# CPU RTL 后续开发计划

## 目标与设计边界

本项目的目标是让当前单核、顺序、多周期 RISC-V CPU 稳定启动 Linux 并进入 shell，同时保留少量高性价比的现代处理器结构。

总体原则：保留局部、容易验证的数据结构优化，避免跨模块投机、请求取消和依赖隐含时序的复杂控制。

计划中的目标结构如下：

- CPU 核心保持顺序、多周期、单发射，不引入流水线投机。
- ICache 保留阻塞式 2 路组相联结构。
- DCache 使用阻塞式 2 路组相联、写穿透、不写分配结构。
- ITLB 和 DTLB 各 16 项，采用 8 组 x 2 路寄存器阵列。
- PTW 保留完整 Sv32 两级遍历、权限检查、superpage 和硬件 A/D 位更新。
- CPU 内部访存总线采用统一握手协议，并保持全局 single-outstanding。
- 保留 Linux 所需的 M/S/U 特权级、异常、中断、CSR 和 AMO 支持。
- 不实现分支预测、非阻塞 Cache、MSHR、投机访存和硬件预取。
- PMP 暂时允许保持宽松兼容，待 Linux 启动稳定后再单独完善。

## 验证策略

Linux kernel 和 initramfs 不作为前期 RTL 开发的日常测试输入。前八个阶段优先使用模块级测试和短小裸机程序，以缩短反馈周期并准确定位问题。

验证层次为：

1. RTL 编译、lint 类检查和模块级测试。
2. 裸机算术、分支、普通访存和 CSR 测试。
3. 异常、中断、分页、权限和 AMO 专项测试。
4. SRAM 后端上的 OpenSBI/Linux 仿真。
5. 最终 DDR 仿真或 FPGA 上板验证。

Linux 集成阶段使用项目维护者届时提供的 kernel/initramfs 编译脚本和生成的 bin 文件。

## 阶段 1：建立快速验证基线

- [x] 梳理现有 Vivado/xsim 测试入口、测试生成脚本和 SRAM 仿真后端。
- [x] 确认当前可运行的测试集合及其依赖工具。
- [x] 选出覆盖取指、访存、异常、CSR、分页和 AMO 的最小回归集合。
- [x] 确认现有测试具备固定周期超时、自检计数和通用寄存器/PC 观察能力。
- [x] 记录基线结果，区分既有失败和后续修改引入的回归。

验收标准：短程序可以稳定重复运行；失败时可以定位到具体指令、访存请求或状态机。

### 阶段 1 基线记录（2026-08-08）

- 测试构建入口：`python3 tools/test_builder.py`。
- 52 个测试程序全部成功生成 HEX/COE，0 个构建失败。
- Vivado 版本：2018.3；当前环境需临时将 `/tools/Xilinx/Vivado/2018.3/bin` 加入 `PATH`。
- 快速仿真使用 `blhex + phex` 和 `SIMU_USE_DDR=0`，主存由 `axi_wrap_ram` 提供，不经过 MIG/DDR3 模型。
- 最小基线结果：

| 测试 | 结果 | 自检项 |
|---|---:|---:|
| `isa_memory` | PASS | 20 |
| `isa_a_ext` | PASS | 52 |
| `privilege_delegation` | PASS | 8 |
| `mmu_sv32_basic` | PASS | 6 |
| `mmu_ptw_walk` | PASS | 4 |
| `cache_icache_basic` | PASS | 3 |
| `cache_dcache_basic` | PASS | 4 |
| `reg_stale_paddr` | PASS | 2 |
| `exception_interrupt_basic` | **既有失败** | 预期 6，实际 0 |

`exception_interrupt_basic` 能正常完成仿真，但测试程序没有完成任何子项；该失败作为阶段 3 的首要回归目标。现有 MMU 仿真日志还会报告 TLB BRAM 同地址读写碰撞，作为阶段 4 移除 TLB BRAM 依赖的直接依据。

## 阶段 2：清理非功能性调试逻辑

- [x] 使用 `LEGACY_LINUX_DEBUG` 隔离 `system_top.sv` 和 `core_top.sv` 中绑定特定测试/内核地址的历史探针。
- [x] 删除总线桥中的无效占位语句，并用自适应宽度的 `'0` 修正流水级寄存器清零。
- [x] 保留通用流水级、CSR/trap、访存和 MMIO 调试信号。
- [x] 通过普通访存和历史 Linux 指针回归确认本阶段没有改变 CPU 的体系结构行为。

验收标准：RTL 编译通过，阶段 1 的基线测试结果不变。

阶段 2 验证结果：`isa_memory` 20 项 PASS；显式启用 `LEGACY_LINUX_DEBUG` 的 `reg_linux_ptr_reload` 2 项 PASS。正常构建不再包含特定 Linux 地址比较器，历史取证测试仍可按需启用。

## 阶段 3：修正特权级与中断行为

- [x] 修正 M/S/U 当前特权级下的全局中断使能判断。
- [x] 修正中断委托、优先级和目标特权级选择。
- [x] 分离 MSIP 与 SSIP 的体系结构语义。
- [x] 将 `sie/sip` 改为 `mie/mip` 中已委托位的视图，并检查 trap/xRET 状态更新路径。
- [x] 修正定时器测试错误的 MTIP 清除方式，并增加 `cpu_clint` 定向单元测试。

验收标准：各特权级的同步异常、机器中断、监管者中断、委托和返回路径符合 RISC-V 特权规范。

阶段 3 验证结果：`cpu_clint_unit` 8 项 PASS，`exception_interrupt_basic` 由基线的 0/6 修复为 6/6 PASS，`exception_timer_irq` 2 项 PASS，`privilege_delegation` 8 项 PASS。

## 阶段 4：重构 TLB

- [x] ITLB 和 DTLB 分别实现为 16 项、8 组 x 2 路。
- [x] 使用寄存器数组，移除对 FPGA BRAM READ_FIRST/WRITE_FIRST 语义的依赖。
- [x] 每组两路并行比较，优先填充无效路。
- [x] 两路均有效时使用每组 1 bit victim/LRU 指针。
- [x] 正确处理 ASID、global、superpage 和全量 `sfence.vma` 失效。
- [x] 删除 `valid_shadow`、树形 PLRU、读写碰撞补丁和填充后 BRAM 特殊语义。

验收标准：裸地址、4 KiB 页面、megapage、权限异常、连续 miss、替换和 `sfence.vma` 测试通过。

阶段 4 验证结果：`mmu_sv32_basic`、`mmu_tlb_replace`、`mmu_tlb_asid`、`mmu_tlb_megapage`、`mmu_tlb_flush`、`mmu_tlb_stress` 和 `reg_tlb_fill_way` 全部 PASS。日志中已无 TLB BRAM 碰撞；剩余碰撞报告来自尚未重构的 I/D Cache tag BRAM。

## 阶段 5：简化 PTW

- [x] 将页表遍历改为明确的 request/wait/check 状态序列。
- [x] 保留 Sv32 两级遍历和硬件 A/D 位更新。
- [x] 锁存每次 walk 的全部输入；已发出的总线请求在 abort 时也必须排空响应。
- [x] 删除会把长延迟总线响应转换为 access fault 的固定周期硬件超时。
- [x] PTW 请求在 WAIT 状态持续有效，直至收到 done/error 响应。

建议状态序列：

```text
IDLE
  -> L1_REQUEST
  -> L1_WAIT
  -> L1_CHECK
  -> L0_REQUEST
  -> L0_WAIT
  -> L0_CHECK
  -> AD_WRITE_REQUEST（需要时）
  -> AD_WRITE_WAIT
  -> TLB_FILL
  -> DONE / FAULT
```

验收标准：L1 leaf、L0 leaf、非法 PTE、权限错误、A/D 更新和总线错误测试通过。

阶段 5 验证结果：`mmu_ptw_walk`、`mmu_permission`、`mmu_sv32_edge`、`reg_ptw_fault_latch` 和 `reg_sfence_during_walk` 全部 PASS。PTW 不再预发 L0 请求，也不会取消已经发出的事务或使用功能性 256-cycle 超时。

## 阶段 6：统一 CPU 内部总线协议

- [x] 将 ICache refill、CPU 数据访问和 PTW 收敛到一个内部事务状态机；现有客户端端口暂由薄兼容层接入。
- [x] 请求接受时锁存 client、地址、方向、宽度、写数据和字节使能。
- [x] 响应按照锁存的 client 返回，不根据实时地址推断归属。
- [x] 保持全局只存在一个未完成事务。
- [x] 删除总线桥中的 `req_changed`、旧 MMIO 响应地址补丁和 wait-drop 类补偿状态。

目标接口语义：

```text
req_valid / req_ready
req_addr
req_write
req_size
req_wdata
req_wstrb
req_client

rsp_valid
rsp_rdata
rsp_error
```

验收标准：人为增加 AXI ready/response 等待周期后，每个客户端仍只接收属于自己的响应。

阶段 6 验证结果：新增 `cpu_bus_bridge_unit`，分别在 AR、R beat、AW、W 和 B 通道插入独立等待，6 项全部 PASS；验证了锁存后的 MMIO 响应归属、PTW/DCache refill 仲裁、带间隙的 8-beat refill，以及 byte write 的地址/数据/strobe 保持。系统级回归 `mmu_ptw_walk`、`reg_stale_paddr`、`reg_mmio_ready`、`cache_icache_basic`、`cache_dcache_basic`、`reg_dcache_refill_error`、`reg_dcache_wb_error` 和 `isa_a_ext` 全部 PASS。ICache 已接受的 MMIO/refill 均会排空，redirect 只丢弃过时结果；客户端外部接口的最终收敛随阶段 7/8 完成。

## 阶段 7：简化 DCache

- [x] 实现阻塞式 2 路组相联结构。
- [x] 使用写穿透和写不命中不分配策略。
- [x] 仅在读不命中时执行 cache line refill。
- [x] 移除 dirty bit、victim writeback 和全 Cache flush 状态机。
- [x] MMIO 请求直接旁路 Cache。
- [x] AMO 使用总线独占的串行读-改-写流程。
- [x] 移除 PTW 前刷新整个 DCache；PTW A/D 写以明确的单字 snoop 更新命中的干净缓存行。

验收标准：两路冲突、替换、读 miss、写命中、写 miss、MMIO、不同访问宽度和 AMO 测试通过。

阶段 7 验证结果：`dcache_ctrl.sv` 从 800 余行收敛为 332 行，tag 改用 8 组×2 路寄存器数组，数据仍使用双口 BRAM。新增 `dcache_writethrough_unit` 8 项全部 PASS，直接验证写 miss 不分配、两路填充/冲突替换、写命中以及 byte store。`cache_dcache_basic` 4 项、`cache_dcache_dirty` 4 项、`cache_fencei` 4 项、`cache_mmu_interact` 6 项、`isa_a_ext` 52 项、`mmu_ptw_walk`、`mmu_sv32_edge`、`reg_sfence_during_walk` 和 `reg_dcache_refill_error` 均 PASS。总线桥中的 DCache victim-writeback 客户端已删除。

## 阶段 8：整理 ICache

- [x] 保留阻塞式 2 路组相联结构。
- [x] 接受请求时锁存 PC 和物理地址。
- [x] 已经发出的 refill 不得取消。
- [x] redirect 只决定完成后的结果是否丢弃，不改变总线事务的完成过程。
- [x] `fence.i` 使用明确的逐组失效过程。

验收标准：连续跳转、异常重定向、refill 期间 redirect、替换和自修改代码测试通过。

阶段 8 验证结果：`icache_ctrl.sv` 收敛为阻塞式 8 组×2 路结构，tag 和每组 victim 位改用寄存器数组，数据仍使用双口 BRAM；已删除 4 路树形 PLRU 模块。新增 `icache_blocking_unit` 10 项全部 PASS，覆盖两路填充/替换、refill 期间 redirect、flush 后排空、逐组失效、MMIO 响应归属以及 AXI refill error 不装入。系统级回归 `cache_icache_basic`、`cache_fencei`、`isa_branch`、`isa_jump`、`reg_mmio_ready`、`exception_access_fault`、`mmu_sv32_basic`、`cache_mmu_interact` 和 `cpu_bus_bridge_unit` 共 9 项全部 PASS。

## 阶段 9：系统级验证与 Linux 集成

- [x] 运行裸机算术、访存和控制流回归。
- [x] 运行 CSR、异常和中断回归。
- [x] 运行 Sv32 分页和权限回归。
- [x] 运行 AMO 回归。
- [x] 审计 Linux 所需的 WFI、计数器权限、LR/SC 保留集和 `sfence.vma` 语义。
- [ ] 使用 SRAM 后端启动 OpenSBI。
- [ ] 使用项目维护者生成的 kernel/initramfs bin 启动 Linux。
- [ ] 确认 Linux 找到 init 并进入 shell。
- [ ] Linux 稳定后再进行 DDR 长时间仿真或 FPGA 上板验证。

阶段 9 短回归进度（2026-08-08）：

- 52 个旧测试程序在清理前全部编译成功；退役 3 个仅适用于旧 write-back DCache 的伪回归，新增 1 个写穿透 store-response error 回归。清理后曾为 50 项，本轮新增 WFI 与 counter-access 两项特权测试；当前 52 项完整清单已再次全部编译成功。
- 非分页核心回归 15/15 PASS：覆盖 RV32I、M/A 扩展、CSR、同步异常、CLINT 中断、委托和 M/S/U 特权级切换。
- Sv32/MMU 回归 18/18 PASS：覆盖两路 TLB 替换、ASID、megapage、权限、page fault、PTW、A/D 更新、`sfence.vma` 和历史问题回归。
- Cache/MMIO/短集成回归全部 PASS：5 个 Cache 测试、CLINT、PLIC、`cpu_compute` 和 `cpu_trap`。`cpu_compute` 暴露的唯一失败是 TB 把 `0x80001000` 数据区误读为 `0x80000000`，修正检查地址后 42/42 PASS。
- `reg_dcache_store_error` 2/2 PASS：确认写穿透 store 的 AXI B 错误产生精确 `mcause=7`、正确 `mtval`，且可成功重试。
- 清理 CPU/MMU/boot ROM 中的“先使用后声明”编译警告。
- Linux 专用 `tb_kernel_boot` 已移除对旧 PTW `bus_req_pending_r` 的致命层级引用；新增 `kernel_tb_compile_smoke`，使用小型内置程序完成 Vivado elaboration 和 1 us 烟雾仿真，不依赖 Linux 镜像。
- 修正 Vivado 编排器的缺镜像处理：只对 `test/` 和 `app/` 调用 `test_builder`，`firmware/` 作为外部产物给出明确路径和转换命令。新增 `tools/bin2hex.py`，已验证 little-endian word 转换和 4-byte 尾部补零。
- 清理 `core_top`/CSR wrapper 的 ANSI 端口重复声明和 UART `lsr` 声明顺序；当前编译日志已无项目源码级声明警告，仅保留 Xilinx MIG/工程刷新类警告。`cpu_compute` 再次 42/42 PASS。
- Linux 启动前语义审计新增两项特权回归：`privilege_wfi` 6/6 PASS，确认合法 WFI 可立即返回、`mstatus.TW` 限制和固定编码；`privilege_counter_access` 6/6 PASS，修正原先写反且未进入异常路径的 `mcounteren/scounteren` 权限关系。现在 S-mode counter/time 访问只受 `mcounteren` 控制，U-mode 同时受 `mcounteren` 与 `scounteren` 控制。
- LR/SC 保留集已有 `isa_a_ext` 52 项覆盖；SC 地址比较改用接受请求时锁存的地址，移除对 execute-stage 实时输入保持不变的依赖，回归仍为 52/52 PASS。
- 复核 `sfence.vma`：硬件把所有选择性形式合法地 over-fence 为全量失效；`sfence.vma x0,x0` 应失效 global 项。修正旧测试中“保留 global”及“4 组/4 周期”的过时注释，`mmu_tlb_asid` 与 `mmu_tlb_flush` 均 PASS。
- PMP CSR 存储与锁定位仍保留，但数据/取指权限执行继续按设计边界保持宽松；这不是当前 Linux 启动阻塞项，待进入 shell 后再独立实现和验证。
- 计数器权限修改后，既有 `privilege_csr_access_priv` 仍 PASS，Linux 专用 `kernel_tb_compile_smoke` 也再次完成 elaboration 与 1 us 烟雾仿真。
- 修正 `sstatus` 对机器级 `MPRV` 位的错误暴露：读 `sstatus` 时 bit 17 固定为 0，写 `sstatus` 不再改变 `mstatus.MPRV`；同时按 xRET 规则在返回到较低特权级时清除 MPRV。扩展后的 `cpu_clint_unit` 与 `privilege_csr_access_priv` 分别全部 PASS。
- MMU 数据侧现使用 MPRV/MPP 计算有效特权级，M 模式取指仍使用实际特权级；新增两个回归分别验证 MPRV+MPP=S 会启用 Sv32 地址翻译，以及 MPRV+MPP=U 会执行 U 页权限检查。`mmu_permission` 扩展为 14 项并全部 PASS。
- 修正 TVM 只拦截 `satp` 写、未拦截读的问题；S 模式在 `mstatus.TVM=1` 时读写 `satp` 以及执行 `sfence.vma` 均进入非法指令异常。`privilege_csr_access_priv` 扩展为 11 项并全部 PASS。
- `minstret` 退休脉冲不再仅依赖 WB 阶段，现覆盖条件分支、`fence`、`fence.i`、`sfence.vma` 与 xRET；`privilege_counter_access` 增加精确差值检查后为 7/7 PASS。
- 上述修正后的受影响面回归 6/6 PASS：`isa_csr`、`privilege_wfi`、`cpu_clint_unit`、`privilege_delegation`、`mmu_permission`、`kernel_tb_compile_smoke`。完整 52 项裸机程序也已重新构建，0 项失败；`git diff --check` 通过。
- 完成一轮 FPGA 综合/实现审计。首次布线的 setup WNS 为 -0.500 ns、TNS 为 -1.388 ns，失败路径均位于 PLIC 中断优先级比较链。PLIC MMIO 仍保持 32 bit 视图，内部优先级和 threshold 收窄为平台实际实现的 3 bit WARL 字段（0..7），删除了不必要的 32 bit 比较器链。`axi4lite_plic_unit` 8/8 PASS，系统级 `mmio_plic` 4/4 PASS。
- PLIC 简化后从全新工程生成 bitstream 成功。最终 routed timing：WNS +0.978 ns、TNS 0、WHS +0.036 ns、THS 0，53,707 个 setup endpoint 无失败，报告明确显示所有用户时序约束均满足。产物为 `build/project/fpga/simplecpu_soc.runs/impl_1/system_top.bit`。
- BRAM IP 生成器现显式记录 ROM A/B 口 100 MHz、Cache A/B 口 50 MHz。Vivado 2018.3 的 `blk_mem_gen` 仍会为 boot ROM 生成 20 ns 的 OOC `clka` 约束，因而在顶层 10 ns 时钟下给出 `Timing 38-316` 提示；这一提示不影响顶层 routed timing 结论，干净重建的最终时序和 bitstream 均已通过。

未执行 `cpu_full` 的 1600 万周期长等待仿真、OpenSBI/Linux 以及 DDR 仿真；按计划等待项目维护者提供新的 OpenSBI/kernel/initramfs 镜像后再进入集成阶段。

## 开发纪律

- 每个阶段形成独立、可审阅、可回退的改动，不同时重写多个关键模块。
- 每次行为修改都应配套最小复现测试或明确的波形检查点。
- 不依赖未文档化的 RAM 碰撞行为、非阻塞赋值先后错觉或实时输入变化取消事务。
- 如果一项优化需要跨多个状态机维持隐含同步，默认不引入。
- 任一阶段出现既有测试回归时，先定位和解决，不带着未知回归进入下一阶段。
