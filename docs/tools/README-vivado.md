# tools.vivado：Vivado 批处理封装

`tools/vivado/`（`__main__.py`、`config.py`、`ip.py`、`tcl.py`）是 Vivado 2018.3 批模式的薄封装，提供建工程、仿真、bitstream、烧板一条链路。

## 命令

```bash
python3 -m tools.vivado <子命令>
```

| 子命令 | 说明 |
|--------|------|
| `project` | 重建 Vivado 工程（`build/vivado/project/simplecpu_soc.xpr`） |
| `sim <task> [--runtime RUNTIME]` | 跑一个仿真任务，时长默认来自任务配置 |
| `regress <group>` | 顺序跑一组任务 |
| `bitstream [--task TASK] [--output PATH]` | 综合 + 实现 + bitstream；默认任务 `fpga`，输出 `build/vivado/simplecpu_soc.bit` |
| `program [--bitstream PATH]` | 烧写第一个连接的 FPGA |
| `clean` | 删除生成的工程 |
| `list` | 列出任务和组 |

```bash
python3 -m tools.vivado list
python3 -m tools.vivado sim cpu_full
python3 -m tools.vivado sim cpu_full --runtime 10ms
python3 -m tools.vivado regress short
python3 -m tools.vivado bitstream --task fpga
python3 -m tools.vivado program
python3 -m tools.vivado clean
```

任务名和组名定义在 `config/simulations.yaml`，可用 `list` 查看。

## 配置文件

- `config/vivado.yaml`：Vivado 可执行文件、工程名（`simplecpu_soc`）、器件（`xc7a200tfbg676-2`）、时钟（100MHz 输入，clk_wiz 输出 40/100/200MHz）、DDR3 MIG 配置（源自 `docs/Reference/mig/`）、各阶段超时。
- `config/simulations.yaml`：仿真和 FPGA 任务定义（`tb`、`blhex`、`phex`、`blcoe`、`runtime`、`verilog_defines`），程序路径相对 `build/program/`；`groups` 段定义任务组（如 `short`）。
- `config/programs.yaml`：测试程序和应用的编译定义，供 `tools/test_builder.py` 使用。

任务定义示例（摘自 `config/simulations.yaml`）：

```yaml
defaults:
  blhex: boot/bootloader_phase1.hex   # 未单独指定 blhex 时的默认值

tasks:
  cpu_full:                           # 仿真任务：指定 testbench
    tb: tb_cpu_full
    phex: test/integration/cpu_full.hex   # 相对 build/program/
    runtime: 5ms
  fpga:                               # FPGA 任务：指定综合顶层
    top: system_top
    blcoe: boot/bootloader.coe

groups:
  short:                              # regress 顺序执行的任务列表
    - isa_m_ext
    - exception_interrupt_basic
    # ……
```

`blhex` + `phex` 为 SRAM 加载模式（`$readmemh`），`blcoe` 用 COE 初始化 BRAM（DDR3/FPGA 模式），两者互斥。

### IP 生成

`ip.py` 依据 `vivado.yaml` 生成 BRAM（ROM / icached / dcached）、时钟向导、MIG 的 `create_ip` TCL。bitstream 流程会在 IP `generate_target` 之后把 BRAM OOC xdc 的时钟周期改写为真实时钟（ROM 为 10ns @ sys_clk，cache 为 25ns @ cpu_clk），消除 Timing 38-316。全程自动，无需手动操作。

## 典型工作流

### 仿真

```bash
python3 tools/test_builder.py          # 1. 构建测试程序到 build/program/
python3 -m tools.vivado project        # 2. 重建 Vivado 工程
python3 -m tools.vivado sim cpu_full   # 3. 跑单个任务
python3 -m tools.vivado regress short  #    或顺序跑一组
```

### 上板

```bash
python3 -m tools.vivado bitstream --task fpga  # 1. 综合 + 实现 + bitstream
python3 -m tools.vivado program                # 2. 烧写 FPGA
# 3. LED0 亮起后，通过 UART 加载程序：
python3 -m tools.uart_console -p /dev/ttyUSB0 -f build/opensbi/platform/generic/firmware/fw_payload.bin
```

## 输出位置

- `build/vivado/`：Vivado 工程（`project/simplecpu_soc.xpr`）与 bitstream（`simplecpu_soc.bit`）
- `build/logs/`：运行日志
