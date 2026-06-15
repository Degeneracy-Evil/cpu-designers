# CPU Designers

## 项目状态

[ ] 开发, [*] 调试, [ ] 报告书写

最近稳定节点：完成FPU：c5c9d7f106db651acba168dfd2d4f40e981caad5

## 项目结构说明

```txt
example     是老师给的课程资料
dev         是我们的开发目录
Experience  是调试经验（换工具后旧经验暂时用不到）
Reference   是存放从别处复制进来的参考资料，ip配置化后不存储ip，只有fpga引脚表格和基础信息
Report      存放实验报告
tools       存放各种工具
plan        计划
process     进度
```

## 本项目基础git使用

```bash
# 初始化
git checkout -b <your name> # 创建你自己的branch

# 然后你进行coding...
git status # 检查更改
git add .  # 添加文件到暂存区
git commit -m "<这里写你本次代码的摘要>" # commit 修改

# 推送
git checkout <your name>    # 确保你现在在自己的分支中
git push origin <your name> # 推送你的开发到你自己的远程分支进行存档
git checkout main           # 切换回main
git pull                    # 拉取别人的修改
git merge <your name>       # 合并你的本地分支到本地main，可能需要注意一下冲突
git push origin main        # 向main分支进行推送，这会自动的发送一个pr请求，等待管理员手动合并
```

## 基本资源

dev\docs\simpleCPU-design-report.md：项目报告，在不稳定版本中不一定更新及时，作为上一次修改后的总体报告。

dev\program_source\test-system.md：测试程序规范与结构讲解

## 工具

`tools/` 目录下提供了以下工具：

### Vivado Orchestrator — 仿真/构建自动化（主工具）

Python 驱动的 Vivado 仿真/综合自动化系统，替代原有 `vivado_do.tcl`。核心改进：

- **会话隔离并行**：不同任务可同时运行独立 Vivado 进程
- **分层哈希增量刷新**：RTL/TB/COE/FPGA 五层独立 SHA256 检测，仅 COE 变更时秒级刷新（对比旧脚本永远全量重建，快 10x+）
- **批处理模式**：`-batch "isa_*"` 一条命令并行仿真多任务，支持通配符、YAML 计划、失败策略
- **配置驱动 IP 生成**：`vivado_config.yaml` → `cache_def.svh` + BRAM/MIG/ClkWiz create_ip TCL，IP 与 RTL 常量自动同步
- **RTL 路径配置化**：`vivado_config.yaml` 的 `rtl_path` 段定义 RTL 子目录布局，项目重构时无需改代码
- **仿真调试**：`--debug trace,trap,wave` 启用指令追踪/异常追踪/波形，`trace_analyzer.py` 分析日志
- **双界面**：CLI（面向 agent/脚本）+ TUI（面向人类）

详细用法见 `tools/README-vivado-orchestrator.md`。

### test_builder.py — 测试程序构建

声明式测试构建系统，读取 `dev/program_source/build.yaml` 批量编译测试程序和应用：

```bash
python tools/test_builder.py                # 构建全部
python tools/test_builder.py --category mmu # 仅构建 MMU 测试
python tools/test_builder.py --test isa/alu # 构建单个测试
python tools/test_builder.py --list         # 列出所有测试
python tools/test_builder.py --gen-tasks    # 生成 tasks.yaml 任务条目
python tools/test_builder.py --clean        # 清理产物
```

构建流程：`build.yaml → test_builder.py → rv2coe.py → .coe + .hex`

测试体系采用自检协议：每个子测试独立返回 PASS/FAIL，通过 x28/x30 寄存器精确定位失败。详细规范见 `dev/program_source/test-system.md`。

### rv2coe.py — RISC-V 编译器

C 语言/汇编到 COE/HEX 文件编译程序，`test_builder.py` 的底层调用。详细用法见 `tools/README-rv2coe.md`。

### run_regression.py — 回归测试

完整回归流程：构建测试程序 → 批量仿真 → 结果汇总。

```bash
python tools/run_regression.py                  # 全回归
python tools/run_regression.py --category mmu   # 按类别
python tools/run_regression.py --sim-only       # 仅仿真（跳过构建）
```

### trace_analyzer.py — 仿真日志分析

解析 `--debug trace` 生成的指令追踪日志，支持 Spike ISA Simulator 对比。

```bash
python -m tools.trace_analyzer parse instr_trace.log          # 解析追踪日志
python -m tools.trace_analyzer find-fail instr_trace.log      # 定位失败点
python -m tools.trace_analyzer diff instr_trace.log spike.log # 与 Spike 对比
```

## 仿真

项目使用 Vivado Orchestrator 进行仿真，RTL 为 SystemVerilog (`*.sv` / `*.svh`)。

```bash
# 首次：创建会话 + 仿真
python -m tools.vivado_cli -task cpu_full -create -sim

# 复用已有会话仿真
python -m tools.vivado_cli -task cpu_full -sim

# 增量刷新（仅 COE 层，改了程序后秒级刷新）
python -m tools.vivado_cli -task cpu_full -refresh --layers coe

# 全量刷新（改了 RTL 后）
python -m tools.vivado_cli -task cpu_full -refresh

# 批处理：并行仿真所有 ISA 测试
python -m tools.vivado_cli -batch "isa_*" -create -sim

# 生成 bitstream 并下载
python -m tools.vivado_cli -task fpga -create -bitstream
python -m tools.vivado_cli -task fpga -program

# 重新生成 cache_def.svh（修改 vivado_config.yaml 后）
python -m tools.vivado_cli --gen-config
```

### 仿真调试

```bash
# 启用指令追踪
python -m tools.vivado_cli -task isa_alu -sim --debug trace

# 启用指令追踪 + 异常追踪 + 波形
python -m tools.vivado_cli -task isa_alu -sim --debug trace,trap,wave

# 启用全部调试（追踪+流水线+异常+Spike+波形full）
python -m tools.vivado_cli -task isa_alu -sim --debug all
```

> 旧 `vivado_do.tcl` 仍保留但不可用，仅供tcl命令参考

### 仿真配置

默认仿真（SRAM 模式）：程序在 elaboration 阶段通过 $readmemh 直接加载到 axi_wrap_ram（BRAM 行为模型），bootloader 仅是一个 2 指令的跳转桩，不涉及 UART。ROM → jr 0x80000000 → 直接执行

DDR3 模式：程序在运行后通过 tb 发送，AXI4 写入 / UART 交付。ROM → bootloader → UART 接收 → 执行

波特率均强制 dl=16（加速）

注意：涉及UART仿真会很慢，涉及ddr会更慢。