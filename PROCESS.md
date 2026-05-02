# simpleCPU Cache-First 访存架构实施进度

## Phase 1：AHB解码器更新 — 已完成

| 步骤 | 内容 | 状态 |
|------|------|------|
| 1.1 | 修改ahb_decoder.v：SLAVE_NUM==2使用HADDR[31]解码（~HADDR[31]→SRAM, HADDR[31]→APB桥） | PASS |
| 1.2 | 修改ahb_periph_bus.v：默认SLAVE_NUM 4→2，移除ahb_default_slave和reserved slave | PASS |
| 1.3 | 修改system_top.v：ahb_periph_bus实例SLAVE_NUM=2 | PASS |

## Phase 2：测试程序地址更新 — 已完成

| 步骤 | 内容 | 状态 |
|------|------|------|
| 2.1 | timer_seconds.s/timer_irq_test.s外设地址0x00104000→0x80004000，重新生成hex | PASS |
| 2.2 | 添加.equ TIMER_BASE常量定义 | PASS |

## Phase 3：仿真验证 — 已完成

| 步骤 | 内容 | 状态 |
|------|------|------|
| 3.1 | cache命中路径：tb_simple_cpu_top ALL TESTS PASSED (33/33) | PASS |
| 3.2 | MMIO路径：tb_timer_seconds (3/3), tb_timer_irq_test (2/2) | PASS |
| 3.3 | 回归测试：tb_simple_cpu_top, tb_align_test, tb_csr_test, tb_timer_seconds, tb_timer_irq_test, tb_ahb_bus, tb_apb_perips 全部PASS | PASS |

## Phase 4：主存占位确认 — 已完成

| 步骤 | 内容 | 状态 |
|------|------|------|
| 4.1 | SRAM slave作为HSELx[0]存在于AHB总线，CPU通过cache访问不直接访问 | PASS |
| 4.2 | icache/dcache端口B已预留（enb=0），cache miss refill接口就绪 | PASS |

## 变更文件汇总

### 修改的RTL文件
- `rtl/AHB-lite/ahb_decoder.v` — SLAVE_NUM==2解码改为HADDR[31]
- `rtl/AHB-lite/ahb_periph_bus.v` — 默认SLAVE_NUM 4→2，移除default/reserved slave
- `rtl/system_top.v` — ahb_periph_bus实例SLAVE_NUM=2

### 修改的汇编文件
- `program_source/timer_seconds.s` — 外设地址0x00104000→0x80004000，添加.equ
- `program_source/timer_irq_test.s` — 外设地址0x00104000→0x80004000，添加.equ

### 修改的测试平台
- `tb/tb_simple_cpu_top.v` — SLAVE_NUM 4→2
- `tb/tb_timer_seconds.v` — SLAVE_NUM 4→2，添加icache/dcache hex加载
- `tb/tb_timer_irq_test.v` — SLAVE_NUM 4→2，添加icache/dcache hex加载
- `tb/tb_align_test.v` — SLAVE_NUM 4→2，添加icache/dcache hex加载
- `tb/tb_csr_test.v` — SLAVE_NUM 4→2，添加icache/dcache hex加载，check_mem_word改为读dcache
- `tb/tb_ahb_bus.v` — SLAVE_NUM 4→2，移除default_slave_test，GPIO地址更新
- `tb/tb_apb_perips.v` — SLAVE_NUM 4→2，所有外设地址0x001xxxxx→0x8000xxxx

### 重新生成的hex文件
- `program_source/timer_seconds.hex`
- `program_source/timer_irq_test.hex`
