# CPU Designers 项目大扫除计划

## 0. 目标与已确认决策

本轮目标是清理 RTL/测试源码、工具脚本、本地 skills 和文档，在不削弱 Linux 启动能力与必要现代处理器特性的前提下降低维护复杂度。实施顺序固定为：

1. 源码
2. 工具脚本
3. skills
4. 文档

大扫除前基线提交为：

```text
d046fbc fix: stabilize Linux simulation and firmware workflow
```

已确认的删除边界：

- 完全删除板级 LCD、触摸接口、拨码开关调试页和 debug UART 接管逻辑。
- 删除绑定特定 Linux 镜像 PC、地址和旧 Cache 结构的 forensic 探针。
- 删除不用的 Vivado TUI、tcl-tunnel 和与 Python 主流程重复的 Tcl 模板。
- 删除仓库内通用 `skill-creator`、PlantUML 和 Typst skills。
- 删除仓库中复制的 ISA、AHB/APB、AXI 和 PlantUML 第三方手册，改为官方链接。
- 合并多轮 Linux/trap 调试记录，只保留仍有效的结论。

明确保留：

- 单核、顺序、多周期、单发射 CPU。
- RV32IMA、M/S/U、CSR、异常、中断与 LR/SC/AMO。
- 阻塞式 2 路组相联 ICache 和写穿透 DCache。
- 8 组 × 2 路 ITLB/DTLB、Sv32 PTW、superpage 和硬件 A/D 更新。
- CLINT、双 context PLIC、UART16550、SPI、GPIO、APB 和 AXI/CDC。
- SRAM 快速仿真、DDR3/MIG FPGA 路径和 Linux firmware 构建链。
- 通用的流水级、commit、trap、MMU、Cache、总线错误观测能力。
- 可选 ILA 调试入口；它不得污染普通仿真或普通 FPGA 构建。
- `docs/Report/` 课程提交物，以及 MIG、DDR 模型和引脚等构建输入。

本轮不做以下工作：

- 不引入分支预测、乱序、非阻塞 Cache、MSHR、多 outstanding 或硬件预取。
- 不重写已经通过回归的 TLB/PTW/Cache 算法。
- 不为统一命名而大面积改动功能接口；只有失效、误导或确实造成重复的别名才删除。
- 不把完整 Linux 长仿真当作每个小步骤的验证手段。

## 1. 通用实施纪律

- [ ] 每个阶段开始前确认工作区只包含已知改动。
- [ ] 每个阶段完成后先验证，再提交；不把未知回归带入下一阶段。
- [ ] 删除文件前确认当前构建、仿真和文档没有有效引用。
- [ ] 不以压缩行数为目的合并本来边界清楚的模块。
- [ ] 不保留两套功能等价的实现或两份互相复制的说明。
- [ ] 默认仿真不记录 WDB；只有显式 `--debug wave` 才启用波形。
- [ ] 所有长期行为由 RTL/工具本身表达，不依赖某次会话或生成目录中的缓存。

提交策略：

```text
refactor(rtl): remove board and image-specific debug logic
refactor(tools): reduce Vivado and build tooling to one workflow
refactor(skills): keep concise project-specific workflows
docs: replace stale references with current project documentation
```

## 2. 阶段 A：冻结验证基线

### A1. 静态与构建基线

- [x] `git diff --check` 通过。
- [x] `python3 -m compileall -q tools` 通过。
- [x] `bash -n tools/compile_kernel.sh tools/compile_musl.sh` 通过。
- [x] `config/vivado_config.yaml` 和 `config/tasks.yaml` 可被当前 Python 类型加载器读取。
- [x] `python3 tools/test_builder.py` 构建全部 52 个裸机测试，0 失败。
- [x] 核对每个 task 的 testbench 模块存在，所引用的测试程序已在构建目录生成。

### A2. RTL 行为基线

在干净 session 上至少运行以下集合：

```text
isa_m_ext
isa_a_ext
exception_interrupt_basic
privilege_delegation
mmu_permission
mmu_tlb_replace
cache_mmu_interact
mmio_plic
cpu_bus_bridge_unit
dcache_writethrough_unit
icache_blocking_unit
regression_m_irq_precision
kernel_tb_compile_smoke
```

- [x] 记录每项 PASS/FAIL 和自检数量。
- [x] 确认默认仿真结束后不存在 `.wdb` 路径。
- [x] 不运行完整 Linux 或 DDR3 长仿真。

基线结果：13 项短回归全部 PASS；用户要求减少 Vivado 启动次数后，后续改为每阶段集中验证。

验收门槛：所有既有短回归通过；若出现既有失败，先定位并记录，不能直接开始源码清理。

## 3. 阶段 B：源码清理

### B1. 删除板级 LCD、触摸与拨码调试接口

删除文件：

```text
src/fpga/lcd_module.dcp
src/rtl/debug_uart_tx.sv
src/tb/lcd_module_stub.sv
```

修改范围：

- [x] 从 `system_top.sv` 端口删除 `sw`、全部 `lcd_*` 和 `ct_*` 信号。
- [x] 删除 LCD 模块实例、显示页选择、显示请求/响应 CDC、扫描计数器和显示值复用器。
- [x] 删除 `sw[5]` 控制的 debug UART，`uart_tx` 始终直接连接 UART16550 输出。
- [x] 从 `src/fpga/cpu.xdc` 删除开关、LCD 和触摸引脚约束；保留 UART、SPI、GPIO、DDR3、时钟和复位约束。
- [x] 更新所有 `system_top` testbench 实例，删除对应寄存器、wire 和端口连接。
- [x] 删除 `tb_soc_includes.svh` 的 `display_state` 依赖；保留一个简单、可 force 的寄存器堆调试读地址，避免破坏自检 task。
- [x] 删除构建器对 LCD DCP、LCD stub 和 debug UART 源文件的导入。该项属于源码删除所需的最小配套修改，更深层脚本整理留到阶段 C。

ILA 处理：

- [x] 保留 `system_top.sv` 中受 `ENABLE_ILA` 控制的两组通用 AXI/复位探针。
- [x] 删除普通构建不需要、启用真实 ILA 时又可能重名的 `src/rtl/common/ila_stub.sv`。
- [x] 普通构建不定义 `ENABLE_ILA`，因此不需要任何 ILA stub。

验证：

- [ ] 运行 `apb_perips`、`mmio_plic`、`cpu_trap` 和 `kernel_tb_compile_smoke`。
- [ ] 创建一次 FPGA 工程，确认 XDC 不再引用已删除端口。
- [ ] 生成 bitstream，确认普通 FPGA 构建仍通过时序。

### B2. 删除历史镜像专用 RTL 探针

`system_top.sv`：

- [ ] 删除 `trap_c_region` 以及只为 LCD 页面服务的 trap 快照寄存器。
- [ ] 删除 S-mode trap 大型 GPR 快照、stvec 区间监视、recursive trap 计数和 initcall 地址比较器。
- [ ] 删除旧 MMIO、PTE、focus load/store 和 Cache 生命周期快照。
- [ ] 删除因此失去用途的 GPR/CSR/debug wire；保留当前 testbench 和 ILA 实际使用的通用信号。

`core_top.sv` 与子模块：

- [ ] 删除 `LEGACY_LINUX_DEBUG` 宏及其特定 PC/物理地址比较逻辑。
- [ ] 删除 `dbg_watch_*`、`dbg_focus_*` 和旧 write-back DCache 恒零探针端口。
- [ ] 从 `dcache_ctrl.sv` 删除仅供旧 forensic 输出使用的 hit/refill/writeback 计数器。
- [ ] 对剩余 debug 输出逐个做引用检查；只保留短回归、kernel 通用监视或 ILA 使用的信号。
- [ ] 不改变 CPU 控制器、MMU、PTW、Cache 和总线握手的功能路径。

测试与任务：

- [ ] 从 `reg_linux_ptr_reload` 和 `reg_linux_field_values` testbench 删除历史探针打印，保留寄存器自检和 PASS/FAIL 判定。
- [ ] 从 `config/tasks.yaml` 删除 `LEGACY_LINUX_DEBUG` define。
- [ ] 删除只为历史取证存在的 DDR3 回归变体；保留对应 SRAM 软件回归。

验证：

- [ ] 运行两个 Linux 字段/指针回归。
- [ ] 运行 M 扩展精确中断、DCache、MMU/PTW 和 trap 代表性回归。
- [ ] 比较综合警告，确认没有悬空端口、隐式 net 或未找到模块。

### B3. 精简 Linux kernel testbench

`tb_kernel_boot.sv` 最终只保留：

- 时钟、复位和 SRAM/DDR 镜像加载。
- UART16550 串行解码，并默认写入 `uart_tx.log`。
- 通用 trap 事件记录：cycle、PC、priv、cause、epc、tval、satp。
- 周期/退休指令/PC 进展采样。
- 可配置的无进展 watchdog 和仿真总超时。
- 结束时的简短状态摘要。

删除：

- [ ] 固定内核函数地址、固定 PTE 地址和固定 vmalloc 地址过滤器。
- [ ] forensic 环形缓冲区及其大量逐字段 dump。
- [ ] `pte_lifecycle`、`dcache_pte_deep`、`ptw_deep`、`vmalloc_exec`、`maintenance_trace`、`axi_pte_trace` 等针对已结束调查的日志。
- [ ] 依赖旧 4 路/dirty/writeback Cache 内部结构的层级引用。
- [ ] 与通用 `tb_soc_includes.svh` 重复的 trace 设施。

实现约束：优先使用一个短小 testbench 和少量 task，不使用 bind、复杂 class 或宏生成体系。只有在单个 monitor 明显独立且接口很小时才拆文件。

验证：

- [ ] `kernel_tb_compile_smoke` 完成 compile、elaborate 和 1 us 仿真。
- [ ] 使用现有 firmware 运行一个有界 SRAM 启动窗口，确认 UART/trap/progress 日志能生成且格式稳定。
- [ ] 默认无 WDB。

### B4. 源码阶段总回归与提交

- [ ] 重新构建全部裸机程序。
- [ ] 运行阶段 A 的完整短回归集合。
- [ ] 增补 `isa_memory`、`exception_access_fault`、`mmu_sv32_edge`、`cache_fencei`、`mmio_clint` 和 `cpu_compute`。
- [ ] FPGA bitstream 和 kernel smoke 均通过。
- [ ] `rg` 确认不存在 `LEGACY_LINUX_DEBUG`、LCD/触摸端口和旧 forensic 信号。
- [ ] 提交源码阶段。

## 4. 阶段 C：工具脚本清理

### C1. 收敛为唯一 Vivado 主流程

唯一入口：

```bash
python3 -m tools.vivado_cli ...
```

删除：

```text
tools/vivado_tui.py
tools/tcl-tunnel/
tools/vivado_core/tcl/_create.tcl
tools/vivado_core/tcl/_setup_ip.tcl
tools/vivado_core/tcl/_add_constrs.tcl
tools/vivado_core/tcl/_add_tb.tcl
tools/vivado_core/tcl/_run_sim.tcl
tools/vivado_core/tcl/_refresh_coe.tcl
tools/vivado_core/tcl/_refresh_tb.tcl
tools/vivado_core/tcl/_bitstream.tcl
tools/vivado_core/tcl/_program.tcl
tools/vivado_core/tcl/_archive.tcl
tools/vivado_core/tcl/_debug_wave.tcl
tools/vivado_core/tcl/build_with_ila.tcl
```

保留并改名为公开入口：

```text
tools/vivado_core/tcl/add_ila.tcl
```

- [x] `operations.py` 是 create/refresh/sim/bitstream/program/archive Tcl 的唯一实现。
- [x] 删除所有 “mirrors 某 Tcl 文件” 注释和哈希中对已删除模板的无效依赖。
- [x] `add_ila.tcl` 不含固定用户路径，只负责在已打开工程中创建 ILA IP；普通 CLI 不自动调用它。
- [x] 不保留另一份一键 ILA bitstream 流程。

### C2. 删除不受 RTL 支持的配置分支

- [x] 删除 `use_tag_bram`、`use_tlb_bram` 以及 tag/TLB BRAM IP 生成分支。
- [x] 删除只为上述分支存在的 byte-enable/width 配置字段。
- [x] Cache data BRAM、boot ROM、MIG 和 clk_wiz 配置继续保留。
- [x] 清理不存在目录对应的 `rtl_path` 字段；保留实际需要的最小路径集合。
- [x] 重新生成 `cache_def.svh`，确认内容与当前 2 路 Cache、2 路 TLB 一致。

### C3. 简化测试构建与任务配置

- [x] `test_builder.py` 只负责读取 `build.yaml`、构建、列出和清理测试程序。
- [x] 删除会生成错误命名和过时 `blcoe` 字段的 `--gen-tasks` 功能；任务保持显式维护。
- [x] 清理重复的 Linux task：保留 kernel smoke、一个 SRAM 启动任务和一个 DDR3 启动任务。
- [x] 删除固定 16 MiB DTB 控制实验和历史 DDR3 指针回归任务。
- [x] 将 task 名称改为反映当前实现的名称，避免把 AXI 主路径继续称作 AHB；仅在改名不触及功能接口时执行。
- [x] 增加一份明确排除长 Linux/DDR3 任务的短回归 batch plan，作为日常完整回归入口。

### C4. 清理 Python 与 shell 实现

- [x] 删除重复 import、未使用变量、已失效兼容注释和无入口函数。
- [x] 修正 `session.py` 以文本模式读取 Vivado 输出，消除 binary line-buffering warning，同时保留实时日志和超时行为。
- [x] 保持 `rv2coe.py` 为编译/链接和 COE/HEX 生成核心；`bin2hex.py` 只做裸 BIN 转换。
- [x] 删除未被文档或测试使用的 `tools/examples/phase1_prog.S`。
- [x] 检查 kernel、musl 和 OpenSBI 脚本的输入/输出边界，不重新引入发行版安装、下载或其他隐式系统修改。
- [x] 不为了拆文件而拆分 `operations.py`；只有出现可独立测试的纯函数集合时才提取模块。

### C5. 工具验证与提交

- [x] Python compileall、shell `bash -n`、YAML 加载通过。
- [x] `test_builder --list`、单测试构建、分类构建和完整构建通过。
- [x] BIN→HEX 对齐、little-endian、尾部补零单元检查通过。
- [x] CLI create、refresh、sim、status 和 cleanup 在临时 session 上通过。
- [ ] 默认无 WDB；`--debug wave:minimal` 可显式生成波形；随后普通仿真能恢复无 WDB。
- [x] kernel smoke、短回归 batch plan 和 FPGA bitstream 通过。
- [ ] 提交工具阶段。

验证结果：52 个裸机程序构建成功，13 项短回归全部 PASS；PLIC/CLINT
testbench 改为在自检协议完成后立即退出；普通模式未生成 WDB。FPGA bitstream
在 Vivado 2018.3 中生成成功。随后将 MIG 的 8 位 AXI ID 与 CPU 的 4 位 ID
边界改为显式适配，并明确留空连接 `device_temp`；该小改动留到最终集中 Vivado
验证时复核，不为它单独启动一次耗时构建。

## 5. 阶段 D：skills 清理

删除：

```text
.opencode/skills/skill-creator/
.opencode/skills/plantuml-ref/
.opencode/skills/typst-writer/
.opencode/skills/vivado-sim-debug/
```

保留并重写：

```text
.opencode/skills/coding-standards/SKILL.md
.opencode/skills/test-builder/SKILL.md
.opencode/skills/vivado-orchestrator/SKILL.md
```

### D1. 内容边界

- [x] `coding-standards`：只描述当前 SystemVerilog 风格、复位/CDC、握手、可综合边界和验证纪律。
- [x] `test-builder`：只描述 build/list/clean、测试注册、自检寄存器协议和新增测试流程。
- [x] `vivado-orchestrator`：只描述 session、create/refresh/sim、短回归、bitstream、显式波形和故障处理。
- [x] 将仍有价值的 `$fwrite`/波形调试方法放入 `vivado-orchestrator/references/simulation-debug.md`，按需读取。
- [x] 不在 skill 中复制任务全集、完整配置 schema 或大段项目文档。
- [x] 每个 `SKILL.md` 目标为 100–200 行，且不超过 500 行。
- [x] frontmatter 只保留 `name` 和可准确触发的 `description`。

### D2. 验证与提交

- [x] 搜索并清除 `dev/`、根目录 `tasks.yaml`、`vivado_do.tcl`、旧 FPU 和 `log_all_objects=true` 等失效说明。
- [x] 使用 skill validator 检查全部三个 skill。
- [x] 逐条执行 skill 给出的核心命令或其安全只读形式。
- [x] 确认 skill 不指导用户使用已删除的 TUI/Tcl/PlantUML/Typst 能力。
- [ ] 提交 skills 阶段。

验证结果：三个 `SKILL.md` 分别为 114、152、150 行，均通过 `skill-creator`
的 `quick_validate.py`；只读执行 CLI help/status、测试 list/dry-run 和 trace analyzer
help 均成功。审计同时发现 testbench 曾在所有 wave 级别无条件生成全量 VCD，已删除
该重复入口，波形范围统一由 `operations.py` 控制，留到最终集中 Vivado 验证复核。

## 6. 阶段 E：文档清理

### E1. 删除第三方资料副本

删除目录：

```text
docs/IS/
docs/axi/
docs/AHB-lite/
docs/APB/
docs/Reference/plantUML/
```

- [ ] 在文档索引中仅保留 RISC-V ISA/Privileged、AMBA AXI/APB/AHB 和 PlantUML 官方链接。
- [ ] 不在仓库继续维护第三方规范的翻译副本和 PDF。

### E2. 保留构建输入和课程成果

必须保留：

```text
docs/Reference/mig/mig_a.prj
docs/Reference/ddr3_sim/ddr3_model.sv
docs/Reference/ddr3_sim/ddr3_model_parameters.vh
docs/Reference/ddr3_sim/wiredly.v
docs/Reference/pins.csv
docs/Report/
```

- [ ] 检查 `gen_ddr_controller.tcl` 和 `ip_report.md`：仍能生成/解释当前 MIG 时保留，否则把有效内容并入工具文档后删除。
- [ ] `docs/Report/` 明确标为历史课程提交物，不作为当前 RTL 的规范来源。
- [ ] 报告引用的图片继续保留；不为匹配当前代码重写历史报告结论。

### E3. 合并历史调试文档

从以下文档提炼仍有效内容后删除原文件：

```text
docs/kernel-boot-debug.md
docs/kernel_debug_context.md
docs/run-linux-process.md
docs/scan.md
docs/trap-loop-analysis.md
docs/trap-loop-analysis2.md
docs/trap-loop-analysis3.md
docs/trap-loop-analysis4.md
docs/trap-loop-bug-handoff.md
docs/uart-earlycon-clock-bug.md
```

新建 `docs/debug-history.md`，只包含：

- [ ] 已确认并修复的 RTL 根因。
- [ ] 已排除的假设及其证据。
- [ ] 当前仍未完成的 Linux shell 验证。
- [ ] 对今后排障仍有价值的通用方法。
- [ ] 对应修复 commit 或 Git 历史入口，不复制数百行日志。

### E4. 建立当前文档体系

新建 `docs/README.md` 作为唯一索引，当前文档收敛为：

```text
README.md                         项目入口与快速开始
docs/README.md                    文档索引与资料类别
docs/architecture.md              当前 CPU/SoC 架构与设计边界
docs/verification.md              测试体系、短回归和判定标准
docs/tools.md                     构建与 Vivado CLI
docs/linux.md                     firmware、DTS、SRAM/DDR 启动方法
docs/debug-history.md             已解决问题和仍未知事项
docs/todo.md                      当前大扫除计划与进度
src/program_source/test-system.md 裸机自检协议的详细规范
```

- [ ] 用当前 RTL 重新核对地址映射、时钟/复位、Cache/TLB 参数、PLIC context、UART 和内存大小。
- [ ] 删除或合并空文档、重复 ALU 文档、已完成的实现计划和过时命令速查。
- [ ] 删除 `dev/`、旧目录结构、旧 Tcl/TUI、FPU 和 write-back DCache 的失效描述。
- [ ] 将 `docs/vivado-xsim-simulation.md` 和 `docs/linux仿真手册.md` 的有效内容分别并入 `verification.md`、`tools.md` 和 `linux.md`。
- [ ] README 只保留项目定位、结构、最短构建/仿真命令和文档入口。

### E5. 文档验证与提交

- [ ] 检查所有 Markdown 本地链接和命令路径。
- [ ] 检查文档中的模块名、任务名和配置字段确实存在。
- [ ] 检查 `rg 'dev/|vivado_do\.tcl|lcd_module|LEGACY_LINUX_DEBUG|FPU'` 的剩余结果，只允许出现在明确标注的历史课程报告中。
- [ ] 执行 README、tools 和 linux 文档中的安全构建/短仿真命令。
- [ ] 提交文档阶段。

## 7. 最终完成审计

### 7.1 仓库结构

- [ ] 每个保留的 RTL 模块都有实例入口或明确的可选构建用途。
- [ ] 每个保留工具都有用户入口或内部调用者。
- [ ] 只有三个项目专用 skills，且全部验证通过。
- [ ] 当前文档只有一个索引，不存在两份互相矛盾的主说明。
- [ ] Git 工作区干净，四个阶段提交边界清楚。

### 7.2 功能验证

- [ ] 52 个裸机测试程序全部构建成功。
- [ ] 短回归 batch plan 全部通过。
- [ ] kernel testbench compile/elaborate smoke 通过。
- [ ] 默认仿真不生成 WDB，显式波形模式可用。
- [ ] FPGA bitstream 生成成功且 routed timing 无失败路径。
- [ ] Linux firmware 脚本仍能生成 `fw_payload.bin` 和对应 HEX。
- [ ] 现有 firmware 的有界 SRAM 仿真能继续推进并输出可诊断日志。

### 7.3 最终系统验证

- [ ] 在可接受的长仿真窗口内启动 OpenSBI 和 Linux，确认没有出现清理引入的新 trap 或停滞。
- [ ] 最终进入 init/shell；若长仿真或 FPGA 条件暂不具备，此项保持未完成，不能用短 smoke test 代替宣称 Linux 已完全验证。

只有上述证据全部成立，才认为本轮大扫除及 Linux 启动目标完成。
