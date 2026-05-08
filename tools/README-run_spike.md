# Spike 运行与状态捕获工具 (run_spike.py)

`run_spike.py` 是一个辅助脚本，用于通过 [Spike RISC-V ISA 模拟器](https://github.com/riscv-software-src/riscv-isa-sim) 执行编译好的 RISC-V ELF 程序，并在执行结束（或达到设置的最大指令数）时，自动捕获并导出最终的寄存器快照和内存状态。
这非常有助于与硬件（或者 RTL 仿真的输出）进行对比验证和调试。

## 前置依赖

系统必须已经安装 Spike 模拟器，并确保 `spike` 命令可以在系统的 `PATH` 环境中直接调用。

## 使用方法

```bash
./tools/run_spike.py <program.elf> [options]
```

### 必填参数

- `<program.elf>`: 要执行的 RISC-V 目标文件（ELF 格式）。

### 可选参数

- `--out-prefix <PREFIX>`: 指定输出文件名的前缀（默认：`spike_out`）。
- `--max-insns <N>`: 指定脚本在强制停止并记录状态前，允许执行的最大指令数量（默认：`100000`）。因为大多数裸机测试程序最终会进入死循环，这有助于防止无限执行。
- `--memory <BASE:SIZE>`: 定义模拟的目标内存区域（默认：`0x0:0x20000`，即地址 `0x0` 开始的 128KB 空间）。如果程序的入口不在 `0x0`，可以相应修改，例如 `--memory 0x80000000:0x20000`。设置有限大小（如 `0x20000`）可防止导出过大（默认 2GB）的全局内存镜像。

## 输出产物

当脚本执行完成后，会在当前执行目录下生成以下文件：

1. **`${PREFIX}_regs.txt`** (如 `spike_out_regs.txt`):
   包含执行结束时所有通用寄存器的值的文本文件。
2. **`mem.${BASE_ADDR}.bin`** (如 `mem.0x0.bin`):
   模拟器内存配置对应地址段的二进制转储文件 (*Binary Dump*)。你可以使用 `hexdump` 等工具查看其内容。
