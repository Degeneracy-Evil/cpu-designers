# CPU Designers

## 项目结构说明

```txt
example是老师给的课程资料
dev是我们的开发目录
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

## 工具

`tools/`目录下提供了一些工具，例如c语言/汇编到coe文件编译程序`rv2coe.py`。详细用法见`tools`目录下README。

## 仿真

项目使用 Vivado TCL 进行仿真，RTL 为 SystemVerilog (`*.sv` / `*.svh`)。

```tcl
# 启动 Vivado TCL Shell
vivado.bat -mode tcl

# 加载脚本
source vivado_sim.tcl

# 运行仿真 (全流程)
vivado_sim -tb tb_simple_cpu_top -step all

# 单步执行
vivado_sim -tb tb_ahb_bus -step create
vivado_sim -tb tb_ahb_bus -step sim

# 可用参数: -tb <testbench> -step <create|ip|constrs|tb|sim|all> -runtime <time> -clean
```

详见 `vivado_sim.tcl` 头部注释。
