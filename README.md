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

## Verilog 编译与仿真（mk.py）

仓库根目录提供了 `mk.py`，用于统一调用 `iverilog` 和 `vvp`。

特性：

- 通过命令行参数指定顶层文件。
- 自动递归搜索顶层文件实例化到的次级设计文件并参与编译。
- 所有编译与运行产物统一输出到 `build/` 目录。

### 基本用法

```bash
python mk.py --top <顶层Verilog文件路径>
```

例如（当前 32 位 ALU 测试）：

```bash
python mk.py --top dev/1alu/tb/tb_alu_32bit.v
```

### 常用参数

```bash
# 仅编译，不运行
python mk.py --top dev/1alu/tb/tb_alu_32bit.v --compile-only

# 仅运行（使用已编译的 vvp 输出）
python mk.py --top dev/1alu/tb/tb_alu_32bit.v --run-only

# 指定顶层模块名（传给 iverilog -s）
python mk.py --top dev/1alu/tb/tb_alu_32bit.v --top-module tb_alu_32bit

# 指定输出目录（默认 build）
python mk.py --top dev/1alu/tb/tb_alu_32bit.v --build-dir build
```

