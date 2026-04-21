# rv2coe

把 RISC-V 汇编/C 源文件编译为 COE 初始化文件（适用于 `dev/2-embedded_cpu/program_source/icache_init.coe` 同格式）。

## 要求

- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-objdump`（仅 `--check-isa` 时需要）

## 快速开始（优先 asm）

```bash
python3 tools/rv2coe.py \
  -i tools/examples/phase1_prog.S \
  -o dev/2-embedded_cpu/program_source/icache_init.coe
```

## 常用参数

- `--lang {auto,asm,c}`：指定输入语言，默认自动识别
- `--march`：默认 `rv32i_zicsr_zifencei`
- `--abi`：默认 `ilp32`
- `--entry`：链接入口符号，默认 `_start`
- `--no-check-isa`：关闭 ISA 白名单检查
- `--depth N`：输出补齐到 N 条指令（默认不补齐）

## C 输入说明

支持 C 到 COE 的基础流程（无标准库）：

- 编译选项包含 `-ffreestanding -nostdlib -nostartfiles`
- 需自行提供入口和启动逻辑（默认入口 `_start`）
- 如代码触发运行时辅助符号（例如某些除法/大整数辅助），需自行提供实现

## 示例

```bash
# asm -> coe
python3 tools/rv2coe.py -i app.S -o app.coe

# c -> coe（无标准库）
python3 tools/rv2coe.py -i app.c -o app.coe --lang c

# 补齐到 2048 words
python3 tools/rv2coe.py -i app.S -o app.coe --depth 2048
```

