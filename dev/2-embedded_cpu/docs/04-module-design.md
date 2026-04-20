# 04 - 模块划分

## 1. 模块清单

| 模块 | 文件 | 描述 |
|------|------|------|
| cpu_top | cpu_top.v | CPU 顶层集成模块 |
| pc_reg | pc_reg.v | 程序计数器 |
| icache_32x2048 | icache_32x2048.v | iCache BRAM IP 占位模型（接口同 IP） |
| dcache_8x1024 | dcache_8x1024.v | dCache BRAM IP 占位模型（接口同 IP） |
| instr_mem | instr_mem.v | 指令侧 L1 iCache 封装 |
| data_mem | data_mem.v | 数据侧 L1 dCache 封装 |
| regfile | regfile.v | 32 × 32bit 通用寄存器堆（x0 恒零） |
| imm_gen | imm_gen.v | 立即数生成模块（I/S/B/U/J 五种格式） |
| alu_wrapper | alu_wrapper.v | 对接已有 ALU 的适配层 |
| alu_control | alu_control.v | ALU 控制信号译码 |
| main_control | main_control.v | 多周期主控制器 FSM |
| trap_unit | trap_unit.v | 异常与 trap 管理模块 |
| interrupt_ctrl | interrupt_ctrl.v | 中断控制模块 |
| csr_regfile | csr_regfile.v | CSR 寄存器堆 |
| gpio_if | gpio_if.v | GPIO 接口模块 |
| uart_if | uart_if.v | UART 接口模块 |
| bus_decode | bus_decode.v | 地址译码模块（dMem / GPIO / UART 空间选择） |

## 2. 模块层次结构

```
cpu_top
├── pc_reg
├── instr_mem
│   └── icache_32x2048    (iCache BRAM IP)
├── regfile
├── imm_gen
├── alu_wrapper
│   └── alu_32bit          (来自 dev/1-alu)
├── alu_control
├── main_control
├── data_mem
│   └── dcache_8x1024     (dCache BRAM IP)
├── bus_decode
│   ├── gpio_if
│   └── uart_if
├── csr_regfile
├── trap_unit
└── interrupt_ctrl
```

## 3. 关键接口约定

### 3.1 时钟与复位

所有时序模块统一使用：
- `clk`：上升沿有效
- `reset`：高电平异步复位

### 3.2 数据通路信号

| 信号 | 位宽 | 方向 | 描述 |
|------|------|------|------|
| pc | 32 | pc_reg → instr_mem | 当前 PC |
| instr | 32 | instr_mem → 译码 | 当前指令 |
| rs1_data | 32 | regfile → ALU | rs1 读出值 |
| rs2_data | 32 | regfile → ALU | rs2 读出值 |
| imm | 32 | imm_gen → ALU/访存 | 立即数 |
| alu_result | 32 | ALU → 数据通路 | ALU 运算结果 |
| mem_rdata | 32 | data_mem → 数据通路 | 存储器读出值 |

### 3.2.1 BRAM IP 关键端口（dCache）

| 信号 | 位宽 | 方向 | 描述 |
|------|------|------|------|
| clka | 1 | input | CPU 主访问端口时钟 |
| ena | 1 | input | A 口使能 |
| wea | 1 | input | A 口写使能 |
| addra | 11 | input | A 口字地址（CPU 地址 `[12:2]`） |
| dina | 32 | input | A 口写数据 |
| douta | 32 | output | A 口读数据 |
| clkb | 1 | input | 显示/调试端口时钟 |
| enb | 1 | input | B 口使能 |
| web | 1 | input | B 口写使能（当前固定 0） |
| addrb | 11 | input | B 口字地址（显示读） |
| dinb | 32 | input | B 口写数据（当前固定 0） |
| doutb | 32 | output | B 口读数据 |

### 3.3 控制信号

由 `main_control` FSM 产生，驱动数据通路多路选择与写使能。具体信号定义在 `05-fsm-control.md` 中给出。

## 4. 设计原则

1. 功能划分清晰，严禁将大量互不相关逻辑堆叠在单一文件
2. 模块命名可调整，但功能边界必须保持
3. 每个模块先明确接口再实现
