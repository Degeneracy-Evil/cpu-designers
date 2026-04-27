# simpleCPU 开发进度（busip分支）

## 状态说明
- [ ] 未开始
- [~] 进行中
- [x] 已完成
- [!] 有问题

---

## 历史进度：中断与CSR实现（已完成）

- [x] 1. 新建 rtl/cpu_csr.v — CSR寄存器模块
- [x] 2. 新建 rtl/cpu_clint.v — 异常/中断控制模块
- [x] 3. 复制并适配UART模块到 rtl/（uart_rx.v, uart_tx.v, uart_top.v）
- [x] 4. 修改 rtl/cpu_decode.v — 扩展译码（ECALL/EBREAK/MRET/FENCE/CSR六指令，id_exe_bus 316位）
- [x] 5. 修改 rtl/cpu_controller.v — FSM扩展（9状态4位，CSR_ACCESS/TRAP_ENTER/TRAP_RETURN）
- [x] 6. 修改 rtl/cpu_execute.v — CSR新值计算+exe_mem_bus 207位
- [x] 7. 修改 rtl/cpu_mem.v — 未对齐异常检测+mem_wb_bus 168位
- [x] 8. 修改 rtl/cpu_wb.v — CSR写回（is_csr时用csr_rdata写rd）
- [x] 9. 修改 rtl/simple_cpu_top.v — 顶层集成（CSR/CLINT/UART实例化，PC跳转，异常汇聚）
- [x] 10. 更新testbench适配新端口（uart_rx_pin, uart_tx_pin）
- [x] 11. 编译通过 + 原有33项测试全部PASS
- [x] 12. CSR指令专项测试（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI）
- [x] 13. 异常处理测试（ECALL/EBREAK/非法指令 → trap进入/返回）
- [x] 14. 中断测试（Timer IRQ触发MEIP → 中断进入/返回）
- [x] 15. MRET测试（mepc恢复PC，mstatus恢复MIE）

---

## 当前进度：接入 Bus4LZU 总线器件

- [x] 1. `cpu_fetch.v` — 1周期延迟取指 + `init_sig` 冻结
- [x] 2. `cpu_mem.v` — 字节掩码 store + 1周期延迟 load + 移除 read-modify-write
- [x] 3. `cpu_controller.v` — `init_sig` 门控所有状态转移与 valid 输出
- [x] 4. `simple_cpu_top.v` — 移除 icache/dcache/uart，新增总线接口，切换中断源
- [x] 5. `bus4lzu_mock.v` — 简化 BRAM + init_sig 模拟 + Timer mock + 地址解码
- [x] 6. `tb_simple_cpu_top.v` — 接入 mock 总线，调整 init_sig 时序，保留现有检查
- [x] 7. 回归测试：原有33项 + CSR 异常测试全部 PASS
- [x] 8. 新增测试：Timer 中断触发/进入/返回 PASS
- [x] 9. 新增测试：字节/半字 store/load 对齐 PASS
- [x] 10. 与真实 Bus4LZU IP 顶层对接验证（Vivado 2018.3 + tcl-tunnel，31/31 PASS）
- [x] 11. FPGA顶层集成：system_top.v（CPU + Bus4LZU IP + 显示）
- [x] 12. XDC约束更新：UART/SPI/GPIO引脚

---

### busip Step10 Vivado IP-sim 验证（2026-04-27）

**环境**：WSL2 (Ubuntu 24.04) + Vivado 2018.3 (Windows) + tcl-tunnel HTTP服务

**搭建步骤**：
1. 通过 tcl-tunnel 创建 Vivado 工程，添加 CPU RTL + ALU RTL + Bus4LZU IP 源文件
2. 创建两个独立 blk_mem_gen IP：`Sram_icache`（COE初始化）+ `Sram_dcache`（无COE）
3. 修改 `memory_slot.v` 分别实例化两个 BRAM IP（原设计共用单一 Sram 模块）
4. `.vh` 头文件通过 `include_dirs` 设置搜索路径（不能 `add_files`）
5. testbench 中 `force u_bus.init_sig = 0` 跳过 UART 加载，BRAM 已通过 COE 预初始化

**Bug fix — BRAM 1周期读延迟未处理**：
- 根因：`cpu_mem.v` 的 MEM_READ 状态在呈现地址后的下一个时钟沿就采样 `load_value`，但 BRAM（blk_mem_gen）具有 1 周期读延迟（READ_LATENCY_A=1），此时输出仍是前一次操作地址的数据
- 表现：x23=0x00070005（期望0x0c），x24=0x0c（期望0x05），x28=0x6f（期望0x00）——load 返回值来自上一个访问地址
- 对比：`cpu_fetch.v` 已用 `r_wait` 标志正确处理 ICache BRAM 的 1 周期读延迟
- 修复：`cpu_mem.v` 新增 `MEM_READ2` 状态（2'd3），load 流程变为 IDLE→READ→READ2→IDLE（3周期），READ2 阶段采样 BRAM 输出

**验证结果**：
- icache_init 程序：31/31 寄存器全部 PASS（仿真耗时 30276ns）
- csr_test 程序：16/16 CSR寄存器全部 PASS（仿真耗时 50261ns）
- comprehensive_test 暂不适用（.data段需预加载DCache，Harvard架构下DCache未COE初始化）

**经验文档**：生成至 `tools/tcl-tunnel/vivado-sim-via-tcl-tunnel.md`

### busip Step8-12 变更记录（2026-04-25）

**Bug fix — mip MEIP位映射错误**：
- 根因：`cpu_csr.v` 中 `w_mip_hw = {20'b0, ext_meip, 1'b0, ext_msip, 1'b0, ext_msip, 1'b0, ext_msip}` 仅27位，Verilog零扩展到32位后ext_meip落在bit6而非RISC-V规定的bit11(MEIP)
- 修复：`w_mip_hw = {20'b0, ext_meip, 3'b0, 1'b0, 3'b0, ext_msip, 3'b0}` (MEIP=bit11, MSIP=bit3)

**Bug fix — interrupt_cause编码错误**：
- 根因：`cpu_clint.v` 中 `{1'b1, 27'd0, 5'd11}` = 33位，Verilog截断最高位后bit31=0
- 修复：直接使用 `32'h8000000B`(MEI)和 `32'h80000003`(MSI)

**Bug fix — Timer IRQ为电平触发**：
- 根因：bus4lzu_mock中timer_irq为单周期脉冲，但RISC-V要求电平触发（持续到软件ack）
- 修复：timer_irq_r持续为高直到软件写0x10010008地址ack

**新增测试**：
- Timer中断测试：配置timer阈值+使能，等待IRQ触发，验证mcause=0x8000000B，handler ack后mret返回 ✓
- 字节/半字对齐测试：sb/lb/lbu/sh/lh/lhu/sw/lw全覆盖，含符号扩展验证 ✓

**FPGA集成**：
- 新建 `fpga/system_top.v`：CPU + Bus4LZU IP + LCD显示，含复位极性转换(reset→rstn)
- 更新 `fpga/cpu.xdc`：新增UART(rx/tx)、SPI(miso/mosi/ss/clk)、GPIO[15:0]引脚约束
- 显示项9/10改为DADDR/DDATA（总线dataAddr_32/readData_32），替代原MADDR/MDATA

**验证结果**：
- 基础33项测试全部 PASS
- CSR 20项测试全部 PASS
- Timer中断2项测试全部 PASS
- 字节/半字对齐23项测试全部 PASS
- 总计78项检查全部 PASS

### busip Step2-7 变更记录（2026-04-25）

**Phase 2 — cpu_mem.v 改造**：
- 移除 read-modify-write 三阶段（MEM_WRITE_MODIFY/MEM_WRITE_COMMIT），改为直接字节掩码写入（MEM_WRITE）
- 新增 `dataWen_4[3:0]`/`dataAddr_32[31:0]`/`writeData_32[31:0]`/`mem_en` 输出端口
- 移除 `dcache_en`/`dcache_we`/`dcache_addr`/`dcache_wdata` 端口
- Load 1周期延迟：MEM_IDLE 发地址 → MEM_READ 取数据 → done

**Phase 3 — cpu_controller.v 改造**：
- 新增 `init_sig` 输入端口
- 所有状态转移门控：`if(init_sig) next_state = STATE_IDLE`
- 所有 `*_valid` 输出门控：`&& !init_sig`

**Phase 4 — simple_cpu_top.v 改造**：
- 移除 `uart_top` 实例和内部 `icache`/`dcache` 实例
- 新增总线接口端口：`instAddr_32`/`instData_32`/`dataWen_4`/`dataAddr_32`/`writeData_32`/`readData_32`/`data_req`/`init_sig`/`timer_irq`
- MEIP 中断源从 `uart_rx_valid` 切换为 `timer_irq`
- `init_sig` 连接到 fetch 和 controller

**Phase 5 — bus4lzu_mock.v**：
- 新建外部 mock：组合读（0延迟），`data_req` 门控写
- `init_sig`：复位后100周期高电平
- `timer_irq`：Timer mock（counter+threshold，地址 0x10010000/4）

**Phase 6 — testbench 适配**：
- `tb_simple_cpu_top.v`/`tb_csr_test.v`：外部实例化 bus4lzu_mock，连接总线信号

**Bug fix — store 指令误写寄存器**：
- 根因：原 `MEM_WRITE_COMMIT` 状态清除 `wb_we_reg<=0`/`wb_data_reg<=0`，新 `MEM_WRITE` 状态遗漏此清除
- 结果：store 指令（如 `sh x2,6(x0)`）的 `wb_we_reg` 保持为1，WB 阶段误写 x6
- 修复：`MEM_WRITE` 状态增加 `wb_we_reg<=1'b0; wb_data_reg<=32'b0;`

**验证结果**：
- 基础33项测试全部 PASS
- CSR 20项测试全部 PASS

### busip Step1 变更记录（2026-04-25）

**改造内容**：
- `cpu_fetch.v`：由纯组合逻辑改为时序逻辑，引入 `clk`/`reset`/`init_sig` 输入
- 移除 `icache_en`/`icache_addr` 输出，改为 `instAddr_32[31:0]`（=PC）
- 输入由 `inst_data` 改为 `instData_32[31:0]`，适配1周期总线读延迟
- 内部 `r_wait` 寄存器：if_valid 持续期间每周期翻转，实现“第1周期发地址，第2周期得指令”
- `init_sig=1` 时强制 `r_wait=0`，`if_done` 永不为1，冻结取指
- `simple_cpu_top.v`：更新 `u_fetch` 实例化，补充 `assign icache_en = if_valid` / `assign icache_addr = pc[12:2]` 驱动原有 icache

**验证结果**：
- 编译通过
- 原有33项基础测试全部 PASS
- CSR 专项20项测试全部 PASS

---

## 变更记录

### 2026-04-25 MRET解码修复 + 异常测试完善

**问题1**：MRET指令(0x30200073)被误判为非法指令，触发TRAP_ENTER而非TRAP_RETURN，导致无限trap循环

**根因**：cpu_decode.v中inst_mret的匹配模式 `25'b0011000_00000_00000_000` 仅20位有效数字，Verilog零扩展为25位后rs2字段(bits 24:20)为0，但MRET编码中rs2=00010。正确模式应为 `25'b0011000_00010_00000_000_00000`

**修复**：
- inst_mret匹配模式：`25'b0011000_00000_00000_000` → `25'b0011000_00010_00000_000_00000`

**问题2**：ECALL异常mcause期望值为0x8000000B（中断），但ECALL是同步异常，bit31应为0

**修复**：
- 测试期望值：0x8000000B → 0x0000000B

**问题3**：MRET返回到mepc（ECALL指令地址），未跳过ECALL，导致再次触发异常

**修复**：
- handler中增加 `addi x20, x20, 4; csrw mepc, x20` 将mepc前进4字节

**新增测试**：
- EBREAK异常：mcause=3 ✓
- 非法指令异常(.word 0x7F)：mcause=2 ✓
- handler使用mscratch计数器，将每次异常的mcause存入mem[72+4*N]
- CSR测试总计20项全部PASS，原有33项测试仍PASS

### 2026-04-25 总线宽度与逻辑修复

**问题**：id_exe_bus声明为336位，但实际字段总和为316位；CSR字段位切片全部错误；csr_wb_bus引用了过期的id_inst_wire；hw_csr_wen未受FSM门控

**修复**：
- id_exe_bus: 336→316位 [315:0]
  - [315:284] pc_plus4, [283] valid_inst, [282] is_alu, [281] is_load, [280] is_store
  - [279] is_jal_like, [278] is_branch, [277] use_fixed_wb, [276] wb_we, [275:271] rd
  - [270:239] wb_fixed_data, [238:236] mem_size, [235] mem_unsigned, [234:219] alu_control
  - [218:187] alu_src1, [186:155] alu_src2, [154:123] rs1_value, [122:91] rs2_value
  - [90:88] branch_funct3, [87] is_csr, [86] is_ecall, [85] is_ebreak, [84] is_mret
  - [83:72] csr_addr, [71:69] csr_funct3, [68:64] csr_uimm, [63:32] pc, [31:0] inst
- exe_mem_bus: 207位 [206:0] ✓
- mem_wb_bus: 168位 [167:0] ✓
- dec_need_exe: 排除CSR（CSR走CSR_ACCESS状态，不走EXEC）
- PC更新: 新增CSR_ACCESS→pc+4和FENCE→pc+4路径
- hw_csr_wen: 改为trap_enter_valid || trap_return_valid门控，不使用clint组合输出
- csr_wb_bus: inst字段改用csr_inst_bus（从id_exe_bus_r提取），不引用id_inst_wire
- cpu_csr.v: sw_csr_rdata改为reg类型（过程赋值）
- testbench: 新增uart_rx_pin/uart_tx_pin端口连接

### 2026-04-25 初始实现

- 新建cpu_csr.v：8个CSR寄存器(mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip)，双写端口(软件+硬件trap)，mip由外部中断信号驱动
- 新建cpu_clint.v：trap进入/返回逻辑，中断判定(mstatus.MIE && mie.MEIE && mip.MEIP)，mstatus硬件更新(MPP/MPIE/MIE)
- 新建uart_rx.v/uart_tx.v/uart_top.v：从example适配，reset极性改为高电平有效
- cpu_decode.v：新增ECALL/EBREAK/MRET/FENCE/FENCE.I/6条CSR指令识别，id_exe_bus扩展到316位
- cpu_controller.v：FSM扩展到4位9状态(IDLE/FETCH/DECODE/EXEC/MEM/WB/CSR_ACCESS/TRAP_ENTER/TRAP_RETURN)
- cpu_execute.v：CSR新值计算(CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI)，csr_no_write优化
- cpu_mem.v：地址未对齐异常检测，is_csr和csr_rdata透传
- cpu_wb.v：is_csr时用csr_rdata写回rd
- simple_cpu_top.v：实例化cpu_csr/cpu_clint/uart_top，PC trap跳转，异常信号汇聚，CSR软件写通路

### busip 分支：总线接入计划启动

- 基于已完成的 CSR/中断/异常全功能实现，启动 Bus4LZU 总线控制器接入
- 设计决策：1周期延迟取指、4位字节写掩码、32位字节地址、init_sig 暂停控制、Timer 中断替换 MEIP
