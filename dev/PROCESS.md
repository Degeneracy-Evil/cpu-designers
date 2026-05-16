# Verilog → SystemVerilog 迁移进度

## 状态总览

| Phase | 描述 | 状态 |
|-------|------|------|
| Phase 1 | 文件重命名 (.v→.sv, .vh→.svh) | ✅ 完成 |
| Phase 2 | 引用更新 (`include, glob, 文档) | ✅ 完成 |
| Phase 3 | TCL 脚本重构 (拆分 + 参数化) | ✅ 完成 |
| Phase 4 | mk.py 弯用 + 文档更新 | ✅ 完成 |
| Phase 5 | 逐项验证 | ⬜ 待开始 |

## 详细记录

### Phase 1 — 文件重命名

**RTL 文件 (53 个 .v → .sv)：**

- [x] ALU/ (10): alu_32bit, alu_result_selector, cla_adder_4bit, cla_adder_16bit, cla_adder_32bit, logic_unit, lui, mux, shifter, subtractor
- [x] MU/ (3): booth_multiplier, mu_unit, non_restoring_divider
- [x] core/ (21): branch_comparator, cpu_bus_bridge, cpu_controller, cpu_csr, cpu_csr_interface, cpu_decode, cpu_execute, cpu_mem, cpu_regfile, cpu_trap_csr, cpu_trap_manager, cpu_wb, icache_ctrl, dcache_ctrl, core_top, cpu_clint, op_regroup, icache, dcache, MMU, cpu_fetch
- [x] AHB-lite/ (5): ahb_plic, ahb_lite_bus, ahb_decoder, ahb_mux, ahb_sram_slave
- [x] AHB-lite/ip/ (1): sram_model
- [x] APB/ (5): apb_decoder, apb_bus, ahb_lite_to_apb, apb_master, apb_slave
- [x] APB/perips/ (7): uart_tx, uart_top, uart_rx, timer, spi, gpio, apb_perips
- [x] 根 (1): system_top

**头文件 (4 个 .vh → .svh)：**

- [x] AHB-lite/ahb_def.vh → ahb_def.svh
- [x] APB/apb_def.vh → apb_def.svh
- [x] APB/header/timer_define.vh → timer_define.svh
- [x] APB/header/bus_define.vh → bus_define.svh

**Testbench 文件 (11 个 .v → .sv)：**

- [x] dev/tb/: tb_simple_cpu_top, tb_simple_cpu_compute, tb_simple_cpu_trap, tb_uart_hello, tb_led_marquee, tb_ahb_bus, tb_apb_perips, lcd_module_stub
- [x] dev/tb/ALU/: tb_non_restoring_divider, tb_mu_unit, tb_alu_cpu_integration

### Phase 2 — 引用更新

- [x] 所有 `` `include "xxx.vh" `` → `` `include "xxx.svh" `` (18 个文件)
- [x] `ifndef guard 宏名更新 (AHB_DEF_VH→AHB_DEF_SVH, APB_DEF_VH→APB_DEF_SVH)
- [x] AHB-lite/PROCESS.md 文件引用更新
- [x] AHB-lite/AHB-lite.md 文件引用更新
- [x] docs/simpleCPU-design-report.md 文件引用更新
- [x] tools/tcl-tunnel/vivado-sim-via-tcl-tunnel.md 文件引用更新
- [x] tools/tcl-tunnel/tcl常用命令.md 文件引用更新

### Phase 3 — TCL 脚本重构

- [x] 创建 tools/tcl/ 目录
- [x] 拆分 create_proj.tcl (Step 1-3: 创建工程 + 添加源文件 + include)
- [x] 拆分 setup_ip.tcl (Step 4: IP 导入 + COE 配置)
- [x] 拆分 add_constrs.tcl (Step 5: DCP + XDC)
- [x] 拆分 add_tb.tcl (Step 6: testbench)
- [x] 拆分 run_sim.tcl (Step 7-8: 仿真 + 日志)
- [x] 重写 vivado_do.tcl 为参数化入口
- [x] 支持 -tb / -step / -runtime / -clean 参数
- [x] 适配 .sv 扩展名 (glob *.sv, system_top.sv, tb_name.sv)
- [x] target_language/simulator_language 改为 SystemVerilog

### Phase 4 — mk.py 弯用 + 文档更新

- [x] tools/mk.py 顶部添加 deprecated 注释
- [x] tools/README-mk.md 添加 deprecated 说明
- [x] README.md 工具说明更新 (新增仿真章节)
- [x] .opencode/skills/coding-standards/SKILL.md 仿真命令更新

### Phase 5 — 验证

- [ ] tb_simple_cpu_top 仿真通过 (20/42 PASS)
- [ ] tb_simple_cpu_compute 仿真通过
- [ ] tb_simple_cpu_trap 仿真通过
- [ ] tb_uart_hello 仿真通过
- [x] tb_led_marquee 仿真通过
- [ ] tb_ahb_bus 仿真通过
- [ ] tb_apb_perips 仿真通过
- [ ] tb_alu_cpu_integration 仿真通过
- [ ] tb_mu_unit 仿真通过
- [ ] tb_non_restoring_divider 仿真通过

### Phase 6 — RTL 优化

| 文件 | 优化 | 类型 |
|------|------|------|
| branch_comparator.sv | reg+always@(*) → wire+assign 三元链 | 消除不必要的reg推断 |
| cpu_controller.sv | 添加 default next_state=state_r | 防止latch推断 |
| alu_32bit.sv | 内联 subtractor 逻辑, 消除循环依赖 | 时序/功能修复 |
| ahb_lite_bus.sv | timescale 排序修正 (必须在 include 前) | 编译修复 |
| cpu_decode.sv | 19项 \|\| 链保持 (Vivado 2018.3 不支持 inside) | 兼容性 |
| cpu_csr.sv | 同上, 保持 \|\| 链 | 兼容性 |
| cpu_regfile.sv | integer i → foreach; 添加 initial 块 | SV惯用法 |
| shifter.sv | 15个 mux_2to1 实例 → 行为级三元 assign | 可读性/综合 |
| mux.sv | 门级(not/and/or) → 行为级 assign | 可读性/综合 |
| icache.sv / dcache.sv | integer i → foreach; wea!=0 → \|wea | SV惯用法 |
| system_top.sv | display 寄存器添加异步复位 | 复位完整性 |
| cpu_bus_bridge.sv | 移除 AHB_ADDR 中 else HTRANS<=IDLE; 修正 HReady→HREADY | AHB协议/编译修复 |
| lui.sv | result={imm[15:0],16'b0} → result=imm | 功能BUG修复 (高16位截断) |
| booth_multiplier.sv | 32位 cla_adder 计数器 → 6位 wire count_next | 面积优化 |
| non_restoring_divider.sv | 同上 | 面积优化 |

**rv2coe.py 编译:** phase1_prog.S → icache_init.coe (4096 words) ✅

**Vivado 仿真 tb_simple_cpu_top:** 编译+elaborate+simulate 通过, pass=20 fail=22
- 多数 FAIL 为 x1~x9 寄存器值不匹配 (全0), 疑似测试程序与当前 COE 不一致
- x10=0x10008000 (期望 0x10004000), x20=0x80000040 (期望 0x80000220) 等偏移差异

## 变更日志

| 日期 | 操作 | 备注 |
|------|------|------|
| 2026-05-16 | 创建 PLAN.md / PROCESS.md | 迁移计划制定 |
| 2026-05-16 | Phase 1: 文件重命名 | 53 .v→.sv, 4 .vh→.svh, 11 tb .v→.sv |
| 2026-05-16 | Phase 2: 引用更新 | 18 个 include + 2 个 guard + 5 个 md 文件 |
| 2026-05-16 | Phase 3: TCL 重构 | 拆分 5 个子脚本 + 参数化入口 |
| 2026-05-16 | Phase 4: mk.py 弃用 | deprecated 标记 + 文档更新 |
| 2026-05-16 | tb_led_marquee PASS | TIMER_PERIOD 100000000→1000, rv2coe.py 重编译, 16/16 PASS |
| 2026-05-16 | Phase 6: RTL 优化 | 15项优化 (含 LUI 功能BUG修复, ALU循环依赖, MU面积优化) |
| 2026-05-16 | rv2coe.py 编译 | phase1_prog.S → icache_init.coe (4096 words) |
| 2026-05-16 | Vivado 仿真 tb_simple_cpu_top | 编译通过, pass=20 fail=22 |
| 2026-05-16 | Vivado log 警告修复 | 7项: 未用寄存器×3, default分支×2, BRAM异步控制, XDC属性, OOC时钟 |
| 2026-05-16 | BRAM异步控制修复(正确方案) | dcache/icache: 寄存器级+valid对齐; sram: 同步复位; sim 42/42+16/16 PASS |
