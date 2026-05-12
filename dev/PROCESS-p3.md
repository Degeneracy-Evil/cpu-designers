# 开发过程记录

## P3 — 优化数据通路 (回写数据链路优化)

### 目标

不需要访存的指令（ALU/JAL/JALR/LUI/AUIPC/MUL/DIV 等）跳过 MEM 阶段，
直接从 EXEC 进入 WRITE_BACK，减少 1 个 FSM 状态，降低 CPI。

### 变更清单

#### 1. cpu_execute.v

- 新增输出端口 `exe_need_mem`（组合逻辑 `is_load | is_store`）
- 向控制器暴露当前指令是否需要访存

#### 2. cpu_controller.v

- 新增输入端口 `exe_need_mem`
- 新增输出端口 `exe_to_wb`（选择器信号，指示 EXE 直连 WB）
- FSM STATE_EXEC 分支改为三路判断：
  - `exe_is_branch` → FETCH / TRAP_ENTER（分支，不变）
  - `exe_need_mem` → STATE_MEM（Load/Store，不变）
  - 否则 → STATE_WB（非访存指令，**新增直接路径**）
- `exe_to_wb` 定义：`STATE_EXEC && exe_done && !exe_is_branch && !exe_need_mem && !init_sig`

#### 3. core_top.v

- 新增 wire `exe_need_mem`、`exe_to_wb`
- 新增组合逻辑 `exe_wb_bus`（168 bit）：将 `exe_mem_bus`（207 bit）字段映射为 `mem_wb_bus` 格式
  - `pc_plus4` → `pc_plus4`
  - `is_jal_like` → `is_jal_like`
  - `is_csr` → `is_csr`
  - `wb_we & result_ok` → `wb_we_reg`（与 MEM 模块行为一致）
  - `wb_rd` → `wb_rd_reg`
  - `result_reg` → `wb_data_reg`
  - `csr_rdata / pc / inst` 直通
- `mem_wb_bus_r` 加载逻辑改为三级 if-else：
  - `exe_to_wb` → `exe_wb_bus`（最高优先级，EXE 直连 WB）
  - `mem_done` → `mem_wb_bus`（正常 MEM→WB）
  - `csr_valid` → `csr_wb_bus`（CSR→WB）

#### 4. cpu_test.s

- 定时器比较值 200 → 100000
- 原因：CPU 加速后程序更早到达定时器设置点，200 周期内定时器中断提前触发，
  导致 x2/x3/x4/x10 被中断处理程序覆写；增大比较值避免中断在测试窗口内触发

### 验证结果

| 测试项 | 结果 |
|--------|------|
| tb_simple_cpu_top | 42 PASS / 0 FAIL |
| tb_ahb_bus | 3 PASS / 0 FAIL |
| tb_alu_cpu_integration | 12 PASS / 0 FAIL |
| tb_mu_unit | 42 PASS / 0 FAIL |

### 收益

非访存指令（R-type、I-type 运算、JAL/JALR、LUI/AUIPC、M 扩展）减少 1 个 FSM 状态，
从 FETCH→DECODE→EXEC→MEM→WB 缩短为 FETCH→DECODE→EXEC→WB，CPI 降低。
