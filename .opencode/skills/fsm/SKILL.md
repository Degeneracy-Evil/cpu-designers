---
name: fsm
description: |
  Multi-cycle FSM implementation guide for the embedded CPU project.
  Use this skill when designing, implementing, or debugging the multi-cycle
  finite state machine, control signals, or state transitions.
---

# 多周期 FSM 实现指导

## FSM 状态

| 状态 | 描述 |
|------|------|
| FETCH | 取指 |
| DECODE | 译码 |
| EXECUTE | R/I-type 运算 |
| EXECUTE_J | JAL/JALR 跳转 |
| EXECUTE_B | 分支判断 |
| MEM_ADDR | 访存地址计算 |
| MEM_READ | dMem 读 |
| MEM_WRITE | dMem 写 |
| MEM_READ_PERIPH | MMIO 读 |
| MEM_WRITE_PERIPH | MMIO 写 |
| WRITE_BACK | 写回寄存器堆 |
| CSR_ACCESS | CSR 读写 |
| TRAP_ENTER | 进入 trap |
| TRAP_RETURN | MRET 返回 |

## 状态路径

| 指令类型 | 路径 |
|----------|------|
| R/I-type 运算 | FETCH→DECODE→EXECUTE→WRITE_BACK |
| Load | FETCH→DECODE→MEM_ADDR→MEM_READ→WRITE_BACK |
| Store | FETCH→DECODE→MEM_ADDR→MEM_WRITE |
| Branch | FETCH→DECODE→EXECUTE_B |
| JAL/JALR | FETCH→DECODE→EXECUTE_J |
| LUI/AUIPC | FETCH→DECODE→EXECUTE→WRITE_BACK |
| CSR | FETCH→DECODE→CSR_ACCESS→WRITE_BACK |
| ECALL/EBREAK | FETCH→DECODE→TRAP_ENTER |
| MRET | FETCH→DECODE→TRAP_RETURN |
| FENCE/FENCE.I | FETCH→DECODE→(NOP) |

## 详细规格

完整状态定义与控制信号见 `docs/05-fsm-control.md`
