# 中断与CSR实现计划

## 设计决策
- **特权模式**：固定M-mode，ecall产生mcause=11
- **中断源**：集成UART外设（参考example/livep-2），MEIP由UART RX驱动
- **mtvec MODE**：仅Direct模式
- **CSR执行路径**：FSM新增CSR_ACCESS专用状态

## FSM状态编码（4位）

| 编码 | 状态 | 描述 |
|------|------|------|
| 0 | IDLE | 初始 |
| 1 | FETCH | 取指 |
| 2 | DECODE | 译码 |
| 3 | EXEC | 执行 |
| 4 | MEM | 访存 |
| 5 | WB | 写回 |
| 6 | CSR_ACCESS | CSR读写 |
| 7 | TRAP_ENTER | 进入trap |
| 8 | TRAP_RETURN | MRET返回 |

## 总线位宽变更

| 总线 | 当前 | 变更后 | 新增字段 |
|------|------|--------|----------|
| id_exe_bus | 292 | ~330 | +is_csr, is_ecall, is_ebreak, is_mret, csr_addr[11:0], csr_funct3[2:0], csr_rdata[31:0] |
| exe_mem_bus | 174 | ~210 | +is_csr, csr_wen, csr_waddr[11:0], csr_wdata[31:0], csr_rdata[31:0] |
| mem_wb_bus | 135 | ~170 | +is_csr, csr_rdata[31:0] |

## 实现步骤

1. 新建 rtl/cpu_csr.v — 8个CSR寄存器，双写端口
2. 新建 rtl/cpu_clint.v — trap进入/返回逻辑
3. 复制并适配UART模块
4. 修改 cpu_decode.v — 识别CSR/ECALL/EBREAK/MRET/FENCE
5. 修改 cpu_controller.v — FSM扩展3个新状态
6. 修改 cpu_execute.v — CSR指令执行
7. 修改 cpu_mem.v — 异常信号输出+总线扩展
8. 修改 cpu_wb.v — CSR写回+总线扩展
9. 修改 simple_cpu_top.v — 顶层集成
10. 更新testbench
11. 编译仿真验证
