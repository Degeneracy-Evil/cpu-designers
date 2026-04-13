# 10 - 仿真与验证

## 1. 工具链

| 工具 | 用途 |
|------|------|
| iverilog | 编译 Verilog 源码 |
| vvp | 运行仿真 |
| gtkwave | 查看波形（可选） |

### 1.1 安装

```bash
sudo apt-get install iverilog
iverilog -V
```

### 1.2 编译与运行

```bash
iverilog -o cpu_tb rtl/*.v tb/tb_cpu_top.v
vvp cpu_tb
```

### 1.3 波形生成

```bash
iverilog -DGENERATE_WAVE -o cpu_tb rtl/*.v tb/tb_cpu_top.v
vvp cpu_tb
gtkwave cpu_tb.vcd
```

## 2. Makefile

项目根目录提供 Makefile，至少支持以下目标：

```bash
make compile    # 编译
make test       # 编译 + 运行
make wave       # 编译 + 运行 + 生成波形
make check      # 语法检查
make clean      # 清理
```

## 3. 验证策略

### 3.1 模块级验证

每个核心模块应有独立测试平台：

| 模块 | 验证要点 |
|------|----------|
| pc_reg | PC 自增、跳转、复位 |
| regfile | 读写正确性、x0 恒零 |
| imm_gen | 五种格式立即数生成正确性 |
| alu_wrapper | ALU 控制信号映射、运算结果正确性 |
| main_control | FSM 状态转移、控制信号正确性 |
| instr_mem | 指令读取正确性 |
| data_mem | 读写正确性、字节/半字/字访问 |
| csr_regfile | CSR 读写、trap 自动更新 |
| trap_unit | trap 进入/返回流程 |
| gpio_if | MMIO 读写 |
| uart_if | 收发时序、中断触发 |

### 3.2 指令级验证

按 RV32I 指令类别设计测试程序，验证：
- 编码译码正确性
- 控制信号正确性
- 执行结果正确性
- 跳转与分支路径正确性
- 访存行为正确性

### 3.3 系统级验证

- 程序从 iMem 正常取指执行
- dMem 读写正确
- 异常可进入 trap
- 中断可进入中断处理流程
- UART / GPIO 能与 CPU 配合工作

## 4. 测试平台规范

参考 `dev/1-alu/AGENTS.md` 测试规范：
- 自动输出 PASS/FAIL 结果
- 统计通过率
- 包含边界值测试
