# 测试体系文档

> 最后更新: 2026-09-25

---

## 1. 概述

本项目使用**结构化、自检、可扩展**的测试体系，覆盖指令集 (ISA)、异常/中断、特权级、MMU/TLB、Cache、MMIO、回归测试和集成测试。

### 1.1 核心设计

- **自检协议**: 每个子测试独立返回 PASS/FAIL，失败时精确定位到子测试 ID
- **框架复用**: 测试框架 (`test/program/framework/`) 提供统一的初始化、运行、报告和陷阱处理
- **声明式注册**: `config/programs.yaml` 定义所有测试/应用及其依赖和构建参数

### 1.2 目录结构

```
config/programs.yaml              # ★ 统一编译配置（测试 + 应用）
test/program/                     # 测试程序
├── framework/                    # 测试框架 (公共)
│   ├── test_framework.s          # 自检运行器 (test_init/test_run/test_report)
│   ├── trap_handlers.s           # 陷阱处理器模板
│   └── page_table_utils.s        # Sv32 页表构建工具
├── isa/                          # ISA 指令测试 (8 文件, 160 子测试)
├── exception/                    # 异常/中断测试 (6 文件, 21 子测试)
├── privilege/                    # 特权级测试 (5 文件, 43 子测试)
├── mmu/                          # MMU/TLB 测试 (12 文件, 82 子测试)
├── cache/                        # Cache 测试 (5 文件, 21 子测试)
├── mmio/                         # MMIO 测试 (2 文件, 8 子测试)
├── regression/                   # 回归测试 (11 文件, 26 子测试)
└── integration/                  # 集成测试 (3 文件, framework: none)
test/bench/                       # 测试台
├── program/                      # 通用程序测试台 (tb_program 等)
├── system/                       # 系统级测试台 (boot/cpu 等)
├── unit/                         # 单元测试台
└── support/                      # 公共 fixture (soc_fixture.svh)
software/baremetal/               # 应用程序、链接脚本 (linker/ram.ld)
build/program/                    # 构建产物 (.hex/.coe，仿真任务从此处加载)
```

---

## 2. 自检协议

### 2.1 寄存器约定

| 寄存器 | 用途 | 说明 |
|--------|------|------|
| x8 | pass_count | 通过数 (框架主寄存器, s0) |
| x9 | total_count | 总测试数 (s1) |
| x18 | first_fail_id | 首个失败 ID (0=全过, s2) |
| x19 | current_test_id | 当前测试 ID (1-based, s3) |
| x28 | pass_count | x8 的兼容镜像，test_report 时更新 |
| x29 | total_count | x9 的兼容镜像，testbench 轮询此寄存器判断结束 |
| x30 | first_fail_id | x18 的兼容镜像 |
| x31 | current_test_id | x19 的兼容镜像 |
| x10-x17 | 子测试自由使用 | 子测试返回值固定用 x10: 1=PASS, 0=FAIL |
| x20-x21 | test_run 内部 | 保存当前 test_id 和 ra |
| x22-x27 | trap_handler 输出 | mcause/mepc/mtval 等 |

### 2.2 内存结果区

固定地址 `0x80007000` (MMU 测试布局 page 7):

| 偏移 | 内容 | 说明 |
|------|------|------|
| +0 | total_count | 总测试数 |
| +4 | pass_count | 通过数 |
| +8 | first_fail_id | 首个失败 ID |
| +12 | reserved | 保留 |
| +16 | test_1_result | 1=PASS, 0=FAIL |
| +20 | test_2_result | ... |

每个子测试的结果 slot 由 test_run 写入，最多支持 240 个子测试。

### 2.3 Testbench 检查

通用测试台 `tb_program` 通过 `soc_fixture.svh` 的 `finish_framework_test` 检查：
- 轮询 x29 (total_count 镜像，仅在 test_report 写入，非 0 即测试完成)
- 读取 x28 (pass_count) 和 x30 (first_fail_id)
- `x28 == x29 && x30 == 0` → 打印 `ALL TESTS PASSED`
- 否则打印 x22-x26 调试值并 `$fatal("TEST FAILED")`

---

## 3. 构建系统

### 3.1 test_builder.py

```bash
# 构建全部测试
python3 tools/test_builder.py

# 按类别构建
python3 tools/test_builder.py --category mmu

# 构建单个测试
python3 tools/test_builder.py --test isa/alu

# 构建应用
python3 tools/test_builder.py --app uart_hello

# 列出所有测试和应用
python3 tools/test_builder.py --list

# 预览构建命令（不实际执行）
python3 tools/test_builder.py --dry-run

# 清理产物
python3 tools/test_builder.py --clean
```

### 3.2 构建流程

```
config/programs.yaml → test_builder.py → rv2coe.py → build/program/ 下的 .hex + .coe
```

每条测试自动拼接框架文件 + 测试源文件，调用 rv2coe.py 编译链接。产物路径如 `build/program/test/isa/alu.hex`。

---

## 4. 仿真

### 4.1 Vivado 命令行

```bash
# 首次使用：创建 Vivado 工程
python3 -m tools.vivado project

# 单个测试仿真
python3 -m tools.vivado sim mmu_tlb_basic

# 列出所有任务和任务组
python3 -m tools.vivado list
```

### 4.2 回归

```bash
# 运行一个任务组（当前定义了 short 组，见 config/simulations.yaml 的 groups 段）
python3 -m tools.vivado regress short
```

---

## 5. 编写新测试

### 5.1 模板

```asm
# ============================================================
# 文件名: category/mytest.s
# 类别:   <category>
# 描述:   <brief description>
# 子测试: N
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler       # 或自定义 trap handler；简单场景可用 m_trap_simple
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_xxx
    jal x1, test_run
    # ... more tests ...

    jal x1, test_report

end_loop:
    j end_loop

test_01_xxx:
    # Setup → Exercise → Verify
    li x10, 1                    # PASS
    ret                           # 返回 x10=1(PASS) 或 x10=0(FAIL)
```

### 5.2 注册

在 `config/programs.yaml` 的 `categories` 段添加条目：

```yaml
categories:
  <category>:
    framework: common             # 或 mmu (需要页表工具) / none (无框架)
    tests:
      - <category>/mytest
```

再在 `config/simulations.yaml` 中添加仿真任务（多数程序测试复用通用 `tb_program`）：

```yaml
  mycategory_mytest:
    tb: tb_program
    phex: test/mycategory/mytest.hex
    runtime: 20ms
```

### 5.3 任务字段说明

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `tb` | str | — | 测试台模块名，在 `test/bench/` 下按文件名查找。 |
| `phex` | str | `""` | 程序 HEX 文件，SRAM 模式仿真由 RAM 模型 `$readmemh` 加载。相对路径于 `build/program/`。 |
| `blhex` | str | `boot/bootloader_phase1.hex` | Bootloader HEX 文件，bootROM 通过 `$readmemh` 加载。相对路径于 `build/program/`。 |
| `blcoe` | str | `""` | Bootloader COE 文件，仅 FPGA/bitstream 任务使用，初始化 ROM IP。相对路径于 `build/program/`。 |
| `runtime` | str | `1ms` | 仿真时间字符串。 |
| `verilog_defines` | dict | `{}` | 传给测试台的编译宏，如 `TB_MAX_CYCLES`。 |

### 5.4 Testbench

多数程序测试直接复用 `test/bench/program/tb_program.sv`（内部调用 `finish_framework_test`），无需新写测试台。默认最多运行 400000 周期，可通过任务字段覆盖：

```yaml
  mycategory_mytest:
    tb: tb_program
    phex: test/mycategory/mytest.hex
    runtime: 200ms
    verilog_defines:
      TB_MAX_CYCLES: 2000000
```

只有特殊场景（如 `mmu_sfence_handshake_unit`、`reg_dcache_refill_error`）才需要专用测试台。

---

## 6. MMU 测试特殊约定

### 6.1 内存布局

仿真内存模型 `src/soc/memory/ram_axi_wrapper.sv` 提供 128MB BRAM (MEM_DEPTH=33554432 words，与 FPGA DDR3 容量一致)。`setup_identity_map` 只恒等映射前 32KB (8 页 × 4KB)，MMU 测试自约束在该区域内，确保页表和测试数据在连续页内：

```
0x80000000: 代码 (.text.start)     [page 0]
0x80001000: L1 页表                [page 1]
0x80002000: L0 页表                [page 2]
0x80003000: 辅助代码/数据区         [page 3]
0x80004000: 数据页 A               [page 4]
0x80005000: 数据页 B               [page 5]
0x80006000: 数据页 C               [page 6]
0x80007000: TEST_RESULT_BASE       [page 7]
```

### 6.2 M→S→M 特权级切换

所有 Sv32 测试必须使用此模式 (M-mode 永远绕过 TLB):

```asm
    la x5, mmu_saved_ra; sw x1, 0(x5)     # 保存 M-mode ra
    # ... 页表设置 ...
    jal x1, enable_sv32
    la x5, s_mode_entry; csrw mepc, x5
    li x5, 0x880; csrw mstatus, x5; mret   # → S-mode

s_mode_entry:
    # ... S-mode 测试代码 ...
    ecall                                    # → M-mode trap handler
```

### 6.3 陷阱处理器

各 MMU 测试自定义 `mmu_trap_handler` (框架的 `trap_handlers.s` 提供通用模板):
- `mcause=8/9` (ecall): 经 `mmu_saved_ra` 返回 M-mode
- `mcause=12/13/15` (page fault): 记录 mcause/mtval 到 `mmu_fault_cause`/`mmu_fault_val`，经 `mmu_return_pc` 跳回检查函数

### 6.4 注意事项

- **enable_sv32 前的可见性**: DCache 写穿透保证 PTW 能看到页表 store；`fence.i` 只建立取指一致性边界
- **页对齐**: 页表和数据区用 `.balign 4096` 保证页对齐
- **MMU 测试自约束 32KB**: 页表 (8KB) + 代码 + 数据区必须落在恒等映射的前 8 页内
- **地址偏移用 li+add**: 0x800 等大立即数超出 addi 12-bit 范围

---

## 7. 测试覆盖总览

| 类别 | 测试文件 | 子测试 |
|------|---------|--------|
| ISA | 8 | 160 |
| 异常/中断 | 6 | 21 |
| 特权级 | 5 | 43 |
| MMU/TLB | 12 | 82 |
| Cache | 5 | 21 |
| MMIO | 2 | 8 |
| 回归测试 | 11 | 26 |
| 集成测试 | 3 | — |
| **合计** | **52** | **361** |

> 子测试数为各测试源码中 `test_run` 调用的数量（与文件头标注一致）。集成测试使用 `framework: none`，无子测试计数，采用直接寄存器/内存值检查。

---

## 8. 调试指南

| 层级 | 方法 | 适用场景 |
|------|------|----------|
| L1: 子测试 ID | x30 (first_fail_id) 直接定位 | 大多数失败 |
| L2: 陷阱记录 | x22-x24 (mcause/mepc/mtval，具体映射见所用 handler)；testbench 失败时自动打印 x22-x26 | 异常相关失败 |
| L3: 指令/异常追踪 | `soc_fixture.svh` 的 `DEBUG_TRACE`/`DEBUG_TRAP` 编译宏 (instr_trace.log / trap_trace.log)，需经任务的 verilog_defines 启用 | 时序/流水线问题 |

失败定位路径: `x30=5` → 查看源码 `test_05_xxx` → 5-10 行有效代码 → 直接定位出错指令。
