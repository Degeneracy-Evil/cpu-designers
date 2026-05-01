# simpleCPU bus重构 — 进度报告

## 总体状态

**Phase 1-4: 已完成** | Phase 5-6: 未开始

---

## 验收标准对照（PLAN.md §十）

### Phase 1-4 完成标准

| # | 标准 | 状态 | 说明 |
|---|------|------|------|
| 1 | cpu_bus_adapter编译通过，I/D仲裁功能正确 | ✅ | tb_cpu_bus_adapter PASS 6/6 |
| 2 | ahb_periph_bus编译通过，SRAM读写+APB桥访问正确 | ✅ | tb_ahb_bus PASS 4/4 |
| 3 | system_top编译通过，所有外设引脚正确连接 | ✅ | timer_irq/gpio/uart/spi引脚均已连接 |
| 4 | 所有测试程序地址更新完成 | ✅ | timer_irq_test.s, timer_seconds.s 已更新Timer地址; comprehensive_test.s, csr_test.s, align_test.s 无外设地址引用 |
| 5 | 81/81 回归测试全部PASS | ✅ | 33+20+23+2+3=81/81 PASS (另有新增单元测试6+4=10项) |
| 6 | 无Bus4LZU依赖（可删除rtl/bus4lzu/目录） | ✅ | system_top.v已无任何bus4lzu引用; bus4lzu/目录可安全删除 |

### Phase 5 完成标准

| # | 标准 | 状态 |
|---|------|------|
| 1 | I-Cache接入cpu_fetch，命中时0周期延迟取指 | ⬜ 未开始 |
| 2 | D-Cache接入cpu_mem，命中时0周期延迟访存 | ⬜ 未开始 |
| 3 | Cache未命中时正确发起总线请求并填充 | ⬜ 未开始 |
| 4 | MMIO地址绕过cache直接访问总线 | ⬜ 未开始 |
| 5 | 81/81 回归测试全部PASS | ⬜ 未开始 |

### Phase 6 完成标准

| # | 标准 | 状态 |
|---|------|------|
| 1 | MMU直接映射实现，虚拟地址=物理地址 | ⬜ 未开始 |
| 2 | 存储访问完整路径：core→MMU→cache→bus | ⬜ 未开始 |
| 3 | 为TLB/SV32预留标准接口 | ⬜ 未开始 |
| 4 | 81/81 回归测试全部PASS | ⬜ 未开始 |

---

## 测试结果汇总

| 测试名 | 结果 | 测试项数 |
|--------|------|---------|
| tb_simple_cpu_top (comprehensive_test) | ✅ PASS | 33 |
| tb_csr_test | ✅ PASS | 20 |
| tb_align_test | ✅ PASS | 23 |
| tb_timer_irq_test | ✅ PASS | 2 |
| tb_timer_seconds | ✅ PASS | 3 |
| **原始回归小计** | **✅ PASS** | **81** |
| tb_cpu_bus_adapter (新增) | ✅ PASS | 6 |
| tb_ahb_bus (新增) | ✅ PASS | 4 |
| **总计** | **✅ PASS** | **91** |

---

## 已完成工作详述

### Phase 1：基础设施搭建

| 步骤 | 内容 | 状态 |
|------|------|------|
| 1.1 | 修改apb_decoder.v：4-slave解码从PADDR[31:30]改为PADDR[15:14]，8-slave从[31:29]改为[15:13] | ✅ |
| 1.2 | 新建ahb_periph_bus.v：异构AHB总线，集成ahb_master/decoder/mux + sram_slave[0] + bridge[1] + reserved[2] + default_slave[3] | ✅ |
| 1.3 | ahb_periph_bus连接apb_perips外设引脚(timer_irq, gpio, uart, spi)；APB读数据/PREADY/PSLVERR多路选择 | ✅ |
| 1.4 | 新建cpu_bus_adapter.v：I/D仲裁FSM (IDLE→I_REQ→I_WAIT→D_REQ→D_WAIT) | ✅ |
| 1.5 | cpu_bus_adapter: dataWen_4→req_write/req_size转换逻辑 | ✅ |
| 1.6 | cpu_bus_adapter: I/D仲裁状态机，I侧优先 | ✅ |
| 1.7 | cpu_bus_adapter: req_ready/resp_valid握手，inst_valid/data_valid输出脉冲 | ✅ |

### Phase 2：顶层集成

| 步骤 | 内容 | 状态 |
|------|------|------|
| 2.1 | 重写system_top.v：替换soc_top为cpu_bus_adapter + ahb_periph_bus | ✅ |
| 2.2 | 连接外设引脚(uart_rx/tx, spi_*, gpio_io) | ✅ |
| 2.3 | 连接timer_irq信号 | ✅ |
| 2.4 | init_sig恒接0 | ✅ |
| 2.5 | LCD显示模块信号连接（lcd_module_stub用于仿真） | ✅ |

### Phase 3：测试程序适配

| 步骤 | 内容 | 状态 |
|------|------|------|
| 3.1 | 更新timer_irq_test.s：Timer地址 0x10010000→0x00104000 | ✅ |
| 3.2 | 更新timer_seconds.s：Timer地址 0x10010000→0x00104000 | ✅ |
| 3.3 | 确认comprehensive_test.s/csr_test.s/align_test.s无外设地址引用，无需更新 | ✅ |
| 3.4 | 创建Makefile + verilog_to_words.py构建脚本，统管汇编→链接→hex转换 | ✅ |

### Phase 4：仿真验证

| 步骤 | 内容 | 状态 |
|------|------|------|
| 4.1 | 新建tb_ahb_bus.v：SRAM读写+桥访问+默认错误响应 | ✅ |
| 4.2 | (tb_apb_perips.v未单独创建，APB外设通过集成测试覆盖) | — |
| 4.3 | 新建tb_cpu_bus_adapter.v：I/D仲裁+信号转换+延迟 | ✅ |
| 4.4 | 重写全部4个现有testbench + 新增2个单元testbench | ✅ |
| 4.5 | BRAM预加载($readmemh)路径更新为u_bus.u_ahb_sram_slave.u_bram.mem | ✅ |
| 4.6 | 回归测试：comprehensive_test 33/33 PASS | ✅ |
| 4.7 | 回归测试：csr_test 20/20 PASS | ✅ |
| 4.8 | 回归测试：timer_irq_test 2/2 PASS | ✅ |
| 4.9 | 回归测试：align_test 23/23 PASS | ✅ |
| 4.10 | 回归测试：timer_seconds 3/3 PASS | ✅ |
| 4.11 | 全量回归：81/81 PASS | ✅ |

---

## 遇到的问题与解决方案

### 问题1：AHB master缺少HRDATA输入端口

**现象**：ahb_master.v未从AHB总线读取HRDATA，导致resp_rdata永远为0。

**根因**：ahb_master.v是已有模块，但从未将总线读数据HRDATA接入master内部寄存器。

**解决**：为ahb_master.v添加HRDATA输入端口，在ACCESS相位将`resp_rdata_r <= HRDATA`；同步修改ahb_bus.v/ahb_periph_bus.v的例化连接。

**文件**：`ahb_master.v`, `ahb_periph_bus.v`

---

### 问题2：CPU时序不匹配 — 固定延迟假设失效

**现象**：CPU的cpu_fetch和cpu_mem模块使用固定周期延迟（r_wait翻转、MEM_READ2状态）假设总线1周期返回数据，但AHB-Lite协议需要2+周期。

**根因**：AHB-Lite的ADDR+DATA两相位协议以及APB桥的SETUP+ACCESS两相位，使总线访问延迟变为可变（2~5周期），CPU原有的固定延迟逻辑无法适配。

**解决**：
1. 在cpu_bus_adapter中新增`inst_valid`和`data_valid`输出脉冲信号
2. 修改cpu_fetch.v：删除r_wait翻转逻辑，改为`if_done = if_valid && inst_valid`
3. 修改cpu_mem.v：删除MEM_READ2状态，MEM_READ/MEM_WRITE改为等待`data_valid`脉冲
4. 在simple_cpu_top.v和system_top.v中传播inst_valid/data_valid信号
5. 更新所有6个testbench的端口连接

**文件**：`cpu_bus_adapter.v`, `cpu_fetch.v`, `cpu_mem.v`, `simple_cpu_top.v`, `system_top.v`, 全部testbench

---

### 问题3：mem_en_reg提前清零导致访存失败

**现象**：tb_simple_cpu_top 21/12 FAIL，store/load指令无法完成。

**根因**：cpu_mem.v中`mem_en_reg`在MEM_READ/MEM_WRITE状态每周期都被清零为0，导致data_req（=mem_en）在adapter返回data_valid前就已失效，adapter看不到请求。

**解决**：修改mem_en_reg清零逻辑 — 仅在`mem_state == MEM_IDLE`时清零，在MEM_READ/MEM_WRITE期间保持为1。

**文件**：`cpu_mem.v`

---

### 问题4：取指陈旧数据 — PC变化后adapter返回旧地址的指令

**现象**：tb_simple_cpu_top 26/7 FAIL，CPU在PC=0x54时消费了来自PC=0x50的指令数据0x12345ab7。

**根因**：cpu_bus_adapter的I侧采用推测取指（持续请求当前PC的指令），但PC可能在取指完成前被分支/中断改变。adapter在ST_I_WAIT状态收到resp_valid时无条件断言inst_valid，CPU消费了来自旧地址的指令数据。

**解决**：在cpu_bus_adapter中增加地址一致性检查：
1. 新增`i_addr_r`寄存器，在ST_I_REQ状态锁存inst_addr
2. 在ST_I_WAIT收到resp_valid时，检查`inst_addr == i_addr_r`
3. 若地址不匹配：丢弃结果，重启取指（`state <= ST_I_REQ`）
4. 若地址匹配：正常断言inst_valid

**文件**：`cpu_bus_adapter.v`

---

### 问题5：hex文件重定位未解析 — `la`伪指令偏移为0

**现象**：timer_irq_test和timer_seconds全部FAIL，CPU从未写入Timer寄存器。

**根因**：汇编源文件已更新Timer地址（`lui x10, 0x00104`），但hex文件未重新生成。更深层原因：之前使用`objcopy -O verilog`直接转换.o文件（未链接），导致`la x10, handler`伪指令（展开为auipc+addi）中的PC相对重定位未解析，addi偏移为0而非0x4c，handler地址错误。

**解决**：
1. 建立正确的汇编→链接→转换流程：`.s` → `as` → `.o` → `ld -m elf32lriscv -T link.ld` → `.elf` → `objcopy -O verilog` → `.hex`
2. 创建`link.ld`链接脚本（起始地址0x0）
3. 创建`verilog_to_words.py`将Verilog字节格式转为$readmemh所需的32位字格式
4. 创建`Makefile`统管全部6个测试程序的构建
5. 重新生成所有.hex文件

**文件**：`program_source/Makefile`, `program_source/link.ld`, `program_source/verilog_to_words.py`, 全部.hex文件

---

### 问题6：bridge_PREADY/PRDATA/PSLVERR声明类型错误

**现象**：ahb_periph_bus.v编译失败，多驱动冲突。

**根因**：bridge_PREADY/bridge_PRDATA/bridge_PSLVERR声明为`wire`，但在always块中被过程赋值。

**解决**：改为`reg`类型。

**文件**：`ahb_periph_bus.v`

---

### 问题7：ahb_sram_slave的HBURST位宽不匹配

**现象**：编译警告/错误，HBURST位宽不匹配。

**根因**：ahb_sram_slave的HBURST输入为4位（非标准AHB-Lite的3位），而总线HBURST为3位。

**解决**：在ahb_periph_bus.v的例化中用`{1'b0, bus_HBURST}`补位。

**文件**：`ahb_periph_bus.v`

---

## 关键设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| I+D总线 | 统一AHB总线 + adapter内仲裁 | 与原Bus4LZU架构一致，避免双master复杂性 |
| 仲裁优先级 | I侧优先 | 取指更频繁，D侧可等待 |
| init_sig | 恒接0 | 使用COE/$readmemh初始化BRAM，无需UART加载 |
| 延迟处理 | inst_valid/data_valid握手 | 替代CPU原有固定延迟逻辑，适配可变延迟总线 |
| 陈旧取指 | 地址锁存+比对+重发 | 防止分支/中断后消费来自旧PC的指令 |
| APB外设顺序 | gpio[0], timer[1], uart[2], spi[3] | 与apb_perips.v中的例化顺序一致 |
| hex构建 | as→ld→objcopy→python转换 | 确保重定位正确解析 |

---

## 文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| rtl/core/cpu_bus_adapter.v | CPU总线→AHB请求适配器 (I/D仲裁 + 信号转换 + inst_valid/data_valid + 陈旧取指防护) |
| rtl/AHB-lite/ahb_periph_bus.v | AHB异构总线顶层 (SRAM + AHB-to-APB桥 + 保留 + 默认从设备) |
| tb/tb_cpu_bus_adapter.v | 适配器单元测试 (6项) |
| tb/tb_ahb_bus.v | AHB总线单元测试 (4项) |
| tb/lcd_module_stub.v | LCD模块仿真桩 |
| program_source/Makefile | 测试程序构建脚本 |
| program_source/link.ld | 链接脚本 (起始地址0x0) |
| program_source/verilog_to_words.py | Verilog hex→字格式转换 |

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| rtl/APB/apb_decoder.v | 4-slave: PADDR[31:30]→[15:14]; 8-slave: [31:29]→[15:13] |
| rtl/AHB-lite/ahb_master.v | 新增HRDATA输入端口, resp_rdata_r<=HRDATA |
| rtl/core/cpu_fetch.v | 删除r_wait, 改为inst_valid握手 |
| rtl/core/cpu_mem.v | 删除MEM_READ2, 增加data_valid输入, 修复mem_en_reg持久化 |
| rtl/core/simple_cpu_top.v | 新增inst_valid/data_valid输入端口 |
| rtl/system_top.v | 替换soc_top为cpu_bus_adapter+ahb_periph_bus |
| program_source/timer_irq_test.s | Timer地址 0x10010000→0x00104000 |
| program_source/timer_seconds.s | Timer地址 0x10010000→0x00104000 |
| program_source/*.hex | 全部重新生成 (正确解析重定位) |
| tb/tb_simple_cpu_top.v | 重写: 替换soc_top, 增加adapter+bus, 新增握手端口 |
| tb/tb_csr_test.v | 同上 |
| tb/tb_align_test.v | 同上 |
| tb/tb_timer_irq_test.v | 同上 |
| tb/tb_timer_seconds.v | 同上 |

### 不变文件（与PLAN.md §八一致）

simple_cpu_top.v (仅新增端口), cpu_controller.v, cpu_decode.v, cpu_execute.v, cpu_wb.v, cpu_regfile.v, cpu_csr.v, cpu_clint.v, ahb_decoder.v, ahb_mux.v, ahb_default_slave.v, ahb_sram_slave.v, ahb_lite_to_apb.v, apb_perips.v, timer.v, gpio.v, uart_top.v, spi.v

---

## 下一步

Phase 5 (Cache集成) 和 Phase 6 (MMU直接映射) 尚未开始，参见PLAN.md §九详细设计。
