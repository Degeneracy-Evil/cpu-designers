# rv2coe

把 RISC-V 汇编/C 源文件编译为 COE/hex/bin 初始化文件，支持统一输出和指令/数据分离输出（Harvard 架构）。

## 要求

在本地或者wsl中有（Windows时会自动尝试查找本地以及wsl）：

- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-ld`（多文件链接时需要）
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-objdump`（仅 `--check-isa` 时需要）

## 快速开始

### 统一输出（Von Neumann 架构）

```bash
python3 tools/rv2coe.py \
  -i tools/examples/phase1_prog.S \
  -o src/program_source/icache_init.coe
```

### 指令/数据分离输出（Harvard 架构 / bootloader 烧录）

```bash
python3 tools/rv2coe.py \
  -i app.S \
  --inst-bin app.inst.bin \
  --data-bin app.data.bin
```

分离输出的文件可直接用于 `bootloader/main.py` 烧录：
- `*.inst.bin` — 指令存储器（`.text` 段）
- `*.data.bin` — 数据存储器（`.data` + `.rodata` + `.sdata` 段）

## 常用参数

### 通用

- `-i` / `--input`：输入源文件（`.S` / `.s` / `.asm` / `.c`），**可多次指定**以实现多文件编译
- `-o` / `--output`：统一 COE 输出（仅 `.text` 段）
- `--lang {auto,asm,c}`：指定输入语言，默认自动识别
- `-I` / `--include`：添加头文件搜索路径（可多次指定）
- `--linker-script FILE`：自定义链接脚本（`.ld`），多文件编译时推荐使用
- `--entry`：链接入口符号，默认 `_start`
- `--march`：目标 ISA，默认 `rv32i_zicsr_zifencei`（同时控制 GCC 编译和 ISA 白名单检查）
- `--abi`：目标 ABI，默认 `ilp32`
- `--no-check-isa`：关闭 ISA 白名单检查
- `--depth N`：指令输出补齐到 N 条（默认不补齐）
- `--data-depth N`：数据输出补齐到 N 条（默认不补齐）
- `--hex FILE`：同时输出 `$readmemh` 格式 hex 文件
- `-v` / `--verbose`：打印完整工具链命令
- `--text-base`：指定连接地址，默认`0x80000000`

### 指令/数据分离输出

| 参数 | 说明 |
|------|------|
| `--inst-coe FILE` | 指令 COE 文件（`.text` 段） |
| `--inst-hex FILE` | 指令 hex 文件（`$readmemh`） |
| `--inst-bin FILE` | 指令原始二进制文件（`.inst.bin`） |
| `--data-coe FILE` | 数据 COE 文件（`.data`+`.rodata`+`.sdata` 段） |
| `--data-hex FILE` | 数据 hex 文件（`$readmemh`） |
| `--data-bin FILE` | 数据原始二进制文件（`.data.bin`） |

## 指令集配置（--march）

`--march` 同时控制 GCC 编译选项和 ISA 白名单检查。内置以下 ISA profile：

| Profile | 包含扩展 |
|---------|---------|
| `rv32i` | 基硎整数指令集 |
| `rv32i_zicsr` | + CSR 指令 |
| `rv32i_zicsr_zifencei` | + 指令缓存刷新（**默认**） |
| `rv32im*` | + 乘除法（M 扩展） |
| `rv32imc*` | + 乘除法 + 压缩指令（C 扩展） |
| `rv32imac*` | + 乘除法 + 原子 + 压缩 |
| `rv32if*` | + 单精度浮点（F 扩展） |
| `rv32imaf*` | + 乘除法 + 单精度浮点 |

每个 base profile 均有 `_zicsr` 和 `_zicsr_zifencei` 变体。若 `--march` 未匹配任何内置 profile，ISA 检查将跳过并输出警告。

## C 输入说明

支持 C 到 COE 的基础流程（无标准库）：

- 编译选项包含 `-ffreestanding -nostdlib -nostartfiles`
- 需自行提供入口和启动逻辑（默认入口 `_start`）
- 如代码触发运行时辅助符号（例如某些除法/大整数辅助），需自行提供实现

## 多文件编译

`-i` 可多次指定，支持将多个源文件编译后链接为一个 ELF：

```bash
# 多文件编译：start.S + uart.c + uart_echo.c → uart_echo.hex
python3 tools/rv2coe.py \
  -i src/program_source/lib/start.S \
  -i src/program_source/lib/uart.c \
  -i src/program_source/uart_echo.c \
  -I src/program_source/lib/include \
  --linker-script src/program_source/link.ld \
  --march rv32im_zicsr_zifencei \
  --hex src/program_source/uart_echo.hex \
  -o src/program_source/uart_echo.coe
```

编译流程：
1. 每个源文件独立编译为 `.o`（C 文件加 `-ffreestanding` 等选项，ASM 文件加 `-x assembler-with-cpp`）
2. 所有 `.o` 通过 `ld` 链接为 ELF（使用 `--linker-script` 指定链接脚本）
3. 单文件时仍使用 GCC 一体化编译+链接（向后兼容）

## 示例

```bash
# asm -> coe（统一输出）
python3 tools/rv2coe.py -i app.S -o app.coe

# c -> coe（无标准库）
python3 tools/rv2coe.py -i app.c -o app.coe --lang c

# 补齐到 2048 words
python3 tools/rv2coe.py -i app.S -o app.coe --depth 2048

# 指令/数据分离输出（bootloader 烧录）
python3 tools/rv2coe.py -i app.S \
  --inst-bin app.inst.bin \
  --data-bin app.data.bin

# 分离输出 + COE + hex 全格式
python3 tools/rv2coe.py -i app.S \
  --inst-coe app.inst.coe \
  --inst-hex app.inst.hex \
  --inst-bin app.inst.bin \
  --data-coe app.data.coe \
  --data-hex app.data.hex \
  --data-bin app.data.bin

# 使用 rv32im 编译（乘除法扩展）
python3 tools/rv2coe.py -i app.S -o app.coe \
  --march rv32im_zicsr_zifencei --abi ilp32

# 使用 rv32imc 编译（乘除法 + 压缩指令）
python3 tools/rv2coe.py -i app.S -o app.coe \
  --march rv32imc_zicsr_zifencei --abi ilp32

# 多文件编译（C 库 + 应用）
python3 tools/rv2coe.py \
  -i lib/start.S -i lib/uart.c -i app/uart_echo.c \
  -I lib/include \
  --linker-script link.ld \
  --march rv32im_zicsr_zifencei \
  -o uart_echo.coe --hex uart_echo.hex
```
