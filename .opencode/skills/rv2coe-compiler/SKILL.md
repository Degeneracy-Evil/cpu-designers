---
name: rv2coe-compiler
description: |
  Compile RISC-V assembly/C source files into Xilinx COE/hex/bin formats
  for instruction and data memories. Use this skill when the user needs to
  build, compile, or generate memory initialization files from RISC-V code.
---

# RV2COE 编译工具

## 概述

`tools/rv2coe.py` 将 RISC-V 汇编/C 源码编译为 Xilinx COE 格式（用于 FPGA 存储器初始化），支持 Harvard 架构的指令/数据分离输出。

## 前置条件

- RISC-V GCC 工具链（`riscv64-unknown-elf-gcc`、`objcopy`、`objdump`）
- 若 Windows 原生未安装，工具会自动回退到 WSL

## 基本用法

### 统一输出（单一 COE 文件）

```bash
python3 tools/rv2coe.py -i <source.S> -o <output.coe>
```

### 指令/数据分离输出（Harvard 架构）

```bash
python3 tools/rv2coe.py \
  -i <source.S> \
  --inst-coe <inst.coe> \
  --data-coe <data.coe>
```

### 同时输出 hex 文件（用于 $readmemh）

```bash
python3 tools/rv2coe.py \
  -i <source.S> \
  -o <output.coe> \
  --hex <output.hex>
```

### 输出原始二进制文件

```bash
python3 tools/rv2coe.py \
  -i <source.S> \
  --inst-bin <prog.inst.bin> \
  --data-bin <prog.data.bin>
```

## 常用参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-i, --input` | 输入源码文件（.S/.s/.asm/.c） | 必填 |
| `-o, --output` | 统一输出 COE 文件 | - |
| `--inst-coe` | 指令 COE 文件（.text） | - |
| `--data-coe` | 数据 COE 文件（.data+.rodata） | - |
| `--inst-hex` / `--data-hex` | 指令/数据 hex 文件 | - |
| `--inst-bin` / `--data-bin` | 指令/数据原始二进制 | - |
| `--march` | ISA 扩展（如 rv32im_zicsr_zifencei） | rv32im_zicsr_zifencei |
| `--abi` | ABI（如 ilp32） | ilp32 |
| `--base-addr` | .text 段基地址 | 0x0 |
| `--entry` | 入口符号 | _start |
| `--depth` | 固定指令字深度（0=不填充） | 0 |
| `--data-depth` | 固定数据字深度（0=不填充） | 0 |
| `--check-isa` | 检查指令是否在 ISA 白名单内 | 启用 |
| `--no-check-isa` | 跳过 ISA 检查 | - |
| `--keep-temp` | 保留中间文件 | - |
| `-v, --verbose` | 打印完整命令 | - |

## ISA 支持

支持的 ISA profile（通过 `--march` 指定）：
- `rv32i`, `rv32i_zicsr`, `rv32i_zicsr_zifencei`
- `rv32im`, `rv32im_zicsr`, `rv32im_zicsr_zifencei`
- `rv32imc`, `rv32imc_zicsr`, `rv32imc_zicsr_zifencei`
- `rv32imac`, `rv32imac_zicsr`, `rv32imac_zicsr_zifencei`
- `rv32if`, `rv32if_zicsr`, `rv32if_zicsr_zifencei`
- `rv32imaf`, `rv32imaf_zicsr`, `rv32imaf_zicsr_zifencei`

## COE 格式

输出格式：
```
memory_initialization_radix=16;
memory_initialization_vector=
xxxxxxxx,
xxxxxxxx;
```

- 16 进制，32 位字，小端序
- 最后一个字以 `;` 结尾，其余以 `,` 分隔

## 示例

### 编译 phase1 程序

```bash
python3 tools/rv2coe.py \
  -i tools/examples/phase1_prog.S \
  -o dev/2-embedded_cpu/program_source/icache_init.coe
```

### 编译 C 程序并分离指令/数据

```bash
python3 tools/rv2coe.py \
  -i my_program.c \
  --inst-coe inst.coe \
  --data-coe data.coe \
  --inst-hex inst.hex \
  --data-hex data.hex
```

### 设置基地址和填充深度

```bash
python3 tools/rv2coe.py \
  -i program.S \
  -o program.coe \
  --base-addr 0x00001000 \
  --depth 4096
```

## 注意事项

- 汇编文件扩展名：`.S`（带预处理）、`.s`/`.asm`（不带预处理）
- C 文件需使用 freestanding 模式（无标准库）
- 入口符号默认为 `_start`，可通过 `--entry` 修改
- ISA 检查默认启用，确保生成的指令在目标 CPU 支持范围内
