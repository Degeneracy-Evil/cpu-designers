# program_source 用法说明

## 概述

`dev/2-simpleCPU/program_source/` 目录用于将 RISC-V 汇编程序编译并转换为可由 Verilog 仿真器加载的机器码字（32-bit word）格式的 HEX 文件。

## 构建流程

整个流程由 **Makefile** 驱动，分为四个阶段：

```
.s → .o → .elf → .verilog.hex → .hex
```

| 阶段 | 输入 | 输出 | 工具 | 说明 |
|------|------|------|------|------|
| 1 | `.s` | `.o` | `riscv64-unknown-elf-as` | 汇编，架构 `rv32i_zicsr`，ABI `ilp32` |
| 2 | `.o` + `link.ld` | `.elf` | `riscv64-unknown-elf-ld` | 链接，使用 `link.ld` 链接脚本，输出 `elf32lriscv` 格式 |
| 3 | `.elf` | `.verilog.hex` | `riscv64-unknown-elf-objcopy` | 将 ELF 转为 Verilog HEX 格式（逐字节，含地址标记 `@`） |
| 4 | `.verilog.hex` | `.hex` | `verilog_to_words.py` | 将逐字节格式转为 32-bit 小端字格式 |

## verilog_to_words.py

### 功能

将 `objcopy -O verilog` 生成的逐字节 HEX 文件转换为 32-bit word 格式的 HEX 文件。

### 输入格式（`.verilog.hex`）

- 以 `@` 开头的行是地址标记，跳过
- 其余每行包含若干空格分隔的单字节十六进制值
- 字节序为**小端序**（低地址存放低字节）

### 转换逻辑

每连续 4 个字节 `[b0, b1, b2, b3]` 合并为一个 32-bit word：

```
word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
```

即按小端序拼合，输出为 8 位十六进制字符串，每行一个 word。

### 用法

```bash
python3 verilog_to_words.py <input.verilog.hex> <output.hex>
```

### 示例

输入（`.verilog.hex`）：

```
@00000000
13 00 00 00 93 02 80 00
```

输出（`.hex`）：

```
00000013
00000293
```

## Makefile

### 变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `AS` | `riscv64-unknown-elf-as` | RISC-V 汇编器 |
| `LD` | `riscv64-unknown-elf-ld` | RISC-V 链接器 |
| `OBJCOPY` | `riscv64-unknown-elf-objcopy` | 目标文件转换工具 |
| `ARCH` | `rv32i_zicsr` | 目标架构（RV32I + Zicsr 扩展） |
| `ABI` | `ilp32` | 应用二进制接口 |

### 目标程序

```
PROGS = comprehensive_test csr_test align_test timer_irq_test timer_seconds icache_init
```

每个程序对应一个同名的 `.s` 汇编源文件。

### 使用方法

```bash
# 编译所有程序，生成 .hex 文件
make all

# 编译单个程序
make comprehensive_test.hex

# 清除所有生成文件
make clean
```

### 生成文件

- `*.o` — 目标文件
- `*.elf` — ELF 可执行文件
- `*.verilog.hex` — Verilog 格式字节 HEX（中间产物）
- `*.hex` — 最终 32-bit word 格式 HEX（供仿真器加载）

## COE 文件生成（Vivado 仿真用）

Vivado 仿真通过 Xilinx `blk_mem_gen` IP 加载 COE 初始化文件，而非 iverilog 的 `$readmemh`。修改汇编源后需重新生成 `.coe` 文件。

### 方法一：rv2coe.py 一步编译（推荐）

```bash
# 直接从 .s 编译为 .coe
python3 tools/rv2coe.py \
  -i dev/2-simpleCPU/program_source/led_marquee.s \
  -o dev/2-simpleCPU/program_source/led_marquee.coe

# 同时输出 .hex（供 iverilog $readmemh）
python3 tools/rv2coe.py \
  -i dev/2-simpleCPU/program_source/led_marquee.s \
  -o dev/2-simpleCPU/program_source/led_marquee.coe \
  --hex dev/2-simpleCPU/program_source/led_marquee.hex
```

### 方法二：Makefile + rv2coe.py

```bash
# 1. 编辑汇编源
vim dev/2-simpleCPU/program_source/led_marquee.s

# 2. 重新编译生成 .hex（供 iverilog 仿真）
make -C dev/2-simpleCPU/program_source led_marquee.hex

# 3. 生成 .coe（供 Vivado 仿真）
python3 tools/rv2coe.py \
  -i dev/2-simpleCPU/program_source/led_marquee.s \
  -o dev/2-simpleCPU/program_source/led_marquee.coe
```

### COE 与 testbench 的对应关系

`vivado_do.tcl` 中 `tb_coe_map` 字典定义了每个 testbench 使用的 COE 文件：

```tcl
set tb_coe_map {
  tb_simple_cpu_top  "icache_init.coe"
  tb_csr_test        "csr_test.coe"
  tb_align_test      "comprehensive_test.coe"
  tb_timer_irq_test  "comprehensive_test.coe"
  tb_timer_seconds   "comprehensive_test.coe"
  tb_led_marquee     "led_marquee.coe"
}
```

添加新 testbench 时，需在此映射中追加对应的 COE 文件路径。
