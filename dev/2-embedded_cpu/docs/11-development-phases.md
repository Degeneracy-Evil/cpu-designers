# 11 - 开发阶段与里程碑

## 1. 总原则

1. 严格围绕课程实验目标展开
2. 先跑通，再完善；先验证，再扩展
3. 所有新模块接入前，先明确功能边界、接口定义与验证方式
4. 优先保证主线可运行，再逐步补充异常、中断与外设
5. 全部阶段的编译与仿真统一通过仓库tools `mk.py`

## 2. 阶段划分

### 阶段一：基础数据通路

**目标**：打通取指→译码→执行最基本路径

- [x] 搭建 pc_reg
- [x] 搭建 regfile
- [x] 搭建 imm_gen
- [x] 搭建 alu_wrapper + alu_control
- [x] 搭建 instr_mem
- [x] 实现 main_control FSM 基础状态（FETCH/DECODE/EXECUTE/WRITE_BACK/INTERRUPT_CHECK）
- [x] 预留 `REQ/WAIT` 状态骨架（即使首版先接 1-cycle 模块）
- [x] 验证：ADD、ADDI、LUI 等基本指令可执行
- [x] 验证命令：`python tools/mk.py --top <tb_top.v> --top-module <tb_module>`

### 阶段二：完整 RV32I 指令集

**目标**：实现RV32I+FENCE/FENCE.I 基础执行闭环

- [x] R-Type 全部运算指令
- [x] I-Type 全部运算指令
- [x] Load / Store 指令（接入 data_mem）
- [x] Branch 指令
- [x] JAL / JALR
- [x] AUIPC
- [x] FENCE / FENCE.I（NOP）
- [x] 补全访存/执行等待状态（`EXECUTE_WAIT`、`MEM_*_WAIT`）
- [x] 验证：每类指令独立测试通过
- [x] 回归命令统一走 `mk.py`，不直接调用裸 `iverilog`

### 阶段三：异常与中断

**目标**：实现精简 trap 机制与 CSR 指令

- [ ] 实现 csr_regfile（mstatus/mie/mip/mtvec/mepc/mcause/mtval/mscratch）
- [ ] 实现 CSR 指令（CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI）
- [ ] 实现 trap_unit（trap 进入/返回流程）
- [ ] 实现 ECALL / EBREAK 异常
- [ ] 实现非法指令异常
- [ ] 实现地址未对齐异常
- [ ] 实现 MRET 指令
- [ ] 验证：异常可进入 trap 并正确返回
- [ ] 验证 trap 精确边界：异常发生时不得提交当前指令副作用

### 阶段四：中断机制

**目标**：实现一级外部中断

- [ ] 实现 interrupt_ctrl
- [ ] 中断检测与响应流程
- [ ] UART RX 中断联动
- [ ] 验证：中断仅在指令边界响应，`WAIT` 状态不抢占
- [ ] 验证：中断可进入处理流程并正确返回

### 阶段五：外设支持

**目标**：实现 GPIO 与 UART

- [ ] 实现 gpio_if
- [ ] 实现 uart_if
- [ ] 实现 bus_decode（地址译码）
- [ ] MMIO 读写通路
- [ ] 验证：外设可通过 MMIO 正确访问

### 阶段六：系统联调

**目标**：完整系统验证

- [ ] 编写综合测试程序
- [ ] 指令级全覆盖测试
- [ ] 异常/中断场景测试
- [ ] 外设交互测试
- [ ] 全部测试通过
- [ ] 形成统一回归脚本清单（全部以 `mk.py` 命令形式记录）

## 3. 当前状态

**阶段一**：已完成
**阶段二**：已完成
**阶段三**：未开始
