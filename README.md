# CPU Designers

RISC-V CPU 教学项目：RTL 设计、仿真测试、FPGA 上板，目标是在自研 SoC 上跑 Linux。当前 ISA 为 RV32IMASU。

## 项目状态

[ ] 开发, [*] 调试, [*] 报告书写, [ ] 停顿

最近稳定节点：时序收敛 @40MHz（WNS +0.459，44758 端点全过）+ UART/bootloader 修复：cf8b4e4

## 项目结构说明

```txt
src/common           公共组件
src/core             CPU 核（control/execution/interface/memory/pipeline）
src/soc              SoC（bus/devices/memory）
test/bench           测试台（unit/program/system/support）
test/program         测试程序（isa/exception/privilege/mmu/cache/mmio/regression/integration/framework）
software/baremetal   裸机程序（applications/boot/linker/runtime）
software/system      系统软件（firmware/kernel/platform/userland/toolchains）
fpga/                约束文件（constraints.xdc）
config/              配置文件（vivado.yaml、simulations.yaml、programs.yaml、opensbi_simplecpu_defconfig）
docs/                文档
tools/               工具脚本
build/               构建产物（vivado/ program/ opensbi/ kernel/ logs/ test-results/，不入库）
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

docs/README.md：文档索引（全部文档入口）

docs/simpleCPU-design-report.md：项目报告，在不稳定版本中不一定更新及时，作为上一次修改后的总体报告。

docs/testing/test-system.md：测试程序规范与结构讲解

## 工具

### tools.vivado — Vivado 工程与仿真（主工具）

```bash
python3 -m tools.vivado project               # 重建 Vivado 工程
python3 -m tools.vivado sim cpu_full          # 跑一个仿真（--runtime 可限时长）
python3 -m tools.vivado regress short         # 顺序跑一组仿真
python3 -m tools.vivado bitstream --task fpga # 生成 bitstream（--output 指定路径）
python3 -m tools.vivado program               # 烧写 FPGA（--bitstream 指定文件）
python3 -m tools.vivado clean                 # 删除生成的工程
python3 -m tools.vivado list                  # 列出所有任务和组
```

工程配置在 `config/vivado.yaml`（Vivado 2018.3，工程 simplecpu_soc，FPGA 型号 xc7a200tfbg676-2），仿真任务定义在 `config/simulations.yaml`。详细用法见 `docs/tools/README-vivado.md`。

### test_builder.py — 测试程序构建

读取 `config/programs.yaml`，批量编译测试程序和应用：

```bash
python3 tools/test_builder.py --list          # 列出所有测试
python3 tools/test_builder.py --test isa/alu  # 构建单个测试
python3 tools/test_builder.py --category mmu  # 构建一类测试
python3 tools/test_builder.py --clean         # 清理产物
```

构建流程：`programs.yaml → test_builder.py → rv2coe.py → .coe + .hex`

### rv2coe.py — RISC-V 编译

C/汇编编译成 COE/HEX，是 `test_builder.py` 的底层调用，默认 march 为 rv32im_zicsr_zifencei。详细用法见 `docs/tools/README-rv2coe.md`。

### trace_analyzer.py — 仿真日志分析

```bash
python3 -m tools.trace_analyzer parse instr_trace.log      # 解析追踪日志
python3 -m tools.trace_analyzer find-fail instr_trace.log  # 定位失败点
```

子命令：parse / diff / find-fail / stats。

### uart_console.py — 上板加载与串口控制台

```bash
python3 -m tools.uart_console -p /dev/ttyUSB0 -f prog.hex  # 上传程序并进入控制台
```

默认波特率 230400，与 bootloader 匹配。

### 其他工具

- `tools/bin2hex.py`：bin 转 hex
- `tools/compile_kernel.sh`、`tools/compile_musl.sh`：编译 Linux 内核、musl

## 仿真

RTL 为 SystemVerilog（`*.sv` / `*.svh`）。

```bash
python3 -m tools.vivado project                # 首次或改了工程配置后：重建工程
python3 -m tools.vivado list                   # 看有哪些任务和组
python3 -m tools.vivado sim cpu_full           # 跑整机仿真
python3 -m tools.vivado sim isa_alu            # 跑单个单测
python3 -m tools.vivado regress short          # 顺序跑 short 组
python3 -m tools.vivado bitstream --task fpga  # 生成上板 bitstream
python3 -m tools.vivado program                # 烧写 FPGA
```

常用任务：`cpu_full`（整机）、`isa_alu` / `mmu_tlb_basic` / `exception_ecall` / `privilege_priv_transition` 等单测、`fpga`（上板，top 为 system_top）、`kernel_boot_sram` / `kernel_boot_ddr3`（内核启动）。

### 时钟

100MHz 晶振经 PLL（clk_wiz_0）分出三路：cpu_clk=40MHz、sys_clk=100MHz、ddr_clk_ref=200MHz。mtime 和 UART 挂在 sys_clk。

### 仿真配置

任务字段 `blhex` / `phex` / `blcoe` 控制程序加载方式：

- **`blhex` + `phex`（SRAM 仿真模式）**：bootROM 在 elaboration 阶段通过 `$readmemh("bootloader.hex")` 加载 `blhex` 文件，SRAM 通过 `$readmemh("prog.hex")` 加载 `phex` 文件。bootloader 仅是一个 2 指令的跳转桩（`jr 0x80000000`），不涉及 UART。ROM → 直接跳转 → 执行 SRAM 中的程序。
- **`blcoe`（DDR3/FPGA 模式）**：COE 文件初始化 BRAM IP，上板后程序经 UART bootloader 接收。ROM → bootloader → UART 接收 → 执行。

`blhex` 和 `blcoe` 互斥，一个任务只能设置其中之一。

波特率仿真中强制 dl=16（加速）。

注意：涉及 UART 的仿真会很慢，涉及 DDR 的更慢。
