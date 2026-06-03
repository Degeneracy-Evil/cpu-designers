# CPU Designers

## 项目状态

[*] 开发, [ ] 调试, [ ] 报告书写

最近稳定节点：报告更新：19cbc9300ef45cd2d13eea26f1448872e94cc060

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

### rv2coe.py — RISC-V 编译器

C 语言/汇编到 COE/HEX 文件编译程序。详细用法见 `tools/README-rv2coe.md`。

### Vivado Orchestrator — 仿真/构建自动化（主工具）

Python 驱动的 Vivado 仿真/综合自动化系统，替代原有 `vivado_do.tcl`。核心改进：

- **会话隔离并行**：不同任务可同时运行独立 Vivado 进程
- **分层哈希增量刷新**：RTL/TB/COE/FPGA 四层独立 SHA256 检测，仅 COE 变更时秒级刷新（对比旧脚本永远全量重建，快 10x+）
- **批处理模式**：`-batch "isa_*"` 一条命令并行仿真多任务，支持通配符、YAML 计划、失败策略
- **配置驱动 IP 生成**：`vivado_config.yaml` → `cache_def.svh` + BRAM create_ip TCL，IP 与 RTL 常量自动同步
- **双界面**：CLI（面向 agent/脚本）+ TUI（面向人类）

详细用法见 `tools/README-vivado-orchestrator.md`。

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

> 旧 `vivado_do.tcl` 仍保留可用，但推荐使用 Vivado Orchestrator。对照：`vivado_do -sim tb_simple_cpu_top` → `python -m tools.vivado_cli -task cpu_full -sim`
