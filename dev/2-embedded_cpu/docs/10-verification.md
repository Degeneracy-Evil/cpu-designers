# 10 - 仿真与验证

## 1. 工具链

| 工具 | 用途 |
|------|------|
| iverilog | 编译 Verilog 源码 |
| vvp | 运行仿真 |
| gtkwave | 查看波形（可选） |
| mk.py | 统一编译/运行入口（根目录脚本） |

### 1.1 安装

```bash
sudo apt-get install iverilog
iverilog -V
```

### 1.2 编译与运行

```bash
python mk.py --top <tb_top.v> --top-module <tb_module>
```

### 1.3 波形生成

```bash
python mk.py --top <tb_top.v> --top-module <tb_module> --define GENERATE_WAVE
gtkwave <wave_file>.vcd
```

## 2. 统一命令规范（mk.py）

项目内所有仿真命令统一从仓库根目录发起，并通过 `mk.py` 执行：

```bash
# 仅编译
python mk.py --top <tb_top.v> --top-module <tb_module> --compile-only

# 编译 + 运行
python mk.py --top <tb_top.v> --top-module <tb_module>

# 仅运行（复用 build 目录已有产物）
python mk.py --top <tb_top.v> --top-module <tb_module> --run-only

# 宏开关（示例：生成波形）
python mk.py --top <tb_top.v> --top-module <tb_module> --define GENERATE_WAVE

# 预检命令（不实际执行编译）
python mk.py --top <tb_top.v> --top-module <tb_module> --compile-only --dry-run
```

### 2.1 mk.py 标准检查清单

- 必须支持：`--top`、`--top-module`、`--compile-only`、`--run-only`、`--dry-run`
- 依赖解析应自动覆盖顶层实例化的子模块
- 构建产物（`.vvp`、日志、filelist）统一输出到 `build/`
- 命令失败时返回非 0 退出码
- 文档示例路径必须与仓库目录一致（如 `dev/1-alu/...`）

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
