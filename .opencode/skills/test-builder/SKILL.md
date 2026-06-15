---
name: test-builder
description: |
  Structured test system with self-checking protocol, declarative build configuration,
  and batch compilation via test_builder.py. Use this skill when building test programs,
  adding new tests, working with build.yaml, running test_builder.py, or understanding
  the self-checking test protocol (x28/x29/x30/x31 registers, memory result area).
  Trigger on: 'build test', 'test_builder', 'build.yaml', 'self-check', 'test protocol',
  'add test', 'test framework', 'ISA test', 'MMU test', 'regression test'.
---

# 测试体系与 test_builder

结构化、自检、可扩展的测试体系，覆盖 ISA、异常/中断、特权级、MMU/TLB、Cache、MMIO、回归测试和集成测试。

## 核心设计

- **自检协议**: 每个子测试独立返回 PASS/FAIL，失败时精确定位到子测试 ID
- **框架复用**: `framework/` 提供统一的初始化、运行、报告和陷阱处理
- **声明式注册**: `build.yaml` 定义所有测试/应用及其依赖和构建参数

## 目录结构

```
dev/program_source/
├── build.yaml                   # 统一编译配置（测试 + 应用）
├── framework/                   # 测试框架 (公共)
│   ├── test_framework.s         # 自检运行器 (test_init/test_run/test_report)
│   ├── trap_handlers.s          # 陷阱处理器模板
│   └── page_table_utils.s      # Sv32 页表构建工具
├── test/                        # 测试程序
│   ├── isa/                     # ISA 指令测试 (8 文件, 107 子测试)
│   ├── exception/               # 异常/中断测试 (6 文件, 21 子测试)
│   ├── privilege/               # 特权级测试 (3 文件, 21 子测试)
│   ├── mmu/                     # MMU/TLB 测试 (12 文件, 80 子测试)
│   ├── cache/                   # Cache 测试 (5 文件, 21 子测试)
│   ├── mmio/                    # MMIO 测试 (2 文件, 8 子测试)
│   ├── regression/              # 回归测试 (7 文件, 21 子测试)
│   └── integration/             # 集成测试 (3 文件)
├── app/                         # 应用程序
├── lib/                         # 库
├── link.ld                      # 链接脚本 (Von Neumann)
└── link_harvard.ld              # 链接脚本 (Harvard)
```

## 自检协议

### 寄存器约定

| 寄存器 | 用途 | 说明 |
|--------|------|------|
| x28 | pass_count | 通过数 |
| x29 | total_count | 总测试数 |
| x30 | first_fail_id | 首个失败 ID (0=全过) |
| x31 | current_test_id | 当前测试 ID (1-based) |
| x10-x17 | 子测试自由使用 | Caller-saved |
| x18-x21 | test_run 内部 | Callee-saved (框架内部) |
| x22-x27 | trap_handler 输出 | mcause/mepc/mtval |

### 内存结果区

固定地址 `0x80007000` (BRAM 内，MMU 测试布局 page 7):

| 偏移 | 内容 | 说明 |
|------|------|------|
| +0 | total_count | 总测试数 |
| +4 | pass_count | 通过数 |
| +8 | first_fail_id | 首个失败 ID |
| +12 | reserved | 保留 |
| +16 | test_1_result | 1=PASS, 0=FAIL |
| +20 | test_2_result | ... |

### Testbench 检查

Testbench 读取 x28 (pass_count) 和 x30 (first_fail_id)：
- `x28 == EXPECTED_TOTAL && x30 == 0` → ALL PASS
- 否则报告具体失败信息

## 构建系统 (test_builder.py)

```bash
# 构建全部
python tools/test_builder.py

# 按类别构建
python tools/test_builder.py --category mmu

# 构建单个测试
python tools/test_builder.py --test isa/alu

# 列出所有测试
python tools/test_builder.py --list

# 生成 tasks.yaml 条目 (供 Vivado Orchestrator 使用)
python tools/test_builder.py --gen-tasks

# 清理产物
python tools/test_builder.py --clean

# 仅打印命令不执行
python tools/test_builder.py --dry-run
```

### 构建流程

```
build.yaml → test_builder.py → rv2coe.py (WSL 回退) → .hex + .coe
```

每条测试自动拼接框架文件 + 测试源文件，调用 rv2coe.py 编译链接。

### --gen-tasks 输出

`--gen-tasks` 根据 `build.yaml` 自动推导任务条目：

- `task_name`: 测试名中 `/` 替换为 `_`
- `tb`: 推导为 `tb_{task_name}`
- `coe`: 推导为 `test/{name}.coe`
- `runtime`: 按类别的 RUNTIME_MAP 推导

RUNTIME_MAP 默认值：

| 类别 | 默认仿真时间 |
|------|-------------|
| isa | 5ms |
| exception | 5ms |
| privilege | 20ms |
| mmu | 20ms |
| cache | 10ms |
| cache_mmu | 20ms |
| mmio | 10ms |
| regression | 20ms |
| integration | 10ms |

### build.yaml 结构

```yaml
defaults:
  arch: rv32im_zicsr_zifencei
  abi: ilp32
  linker_script: link.ld
  depth: 8192

framework:
  common: [framework/common.s]

categories:
  isa:
    tests: [isa/alu, isa/branch, isa/memory, ...]
  isa_f:
    arch: rv32imf_zicsr_zifencei
    abi: ilp32f
    tests: [isa_f/fadd, ...]
  mmu:
    framework: [framework/common.s, framework/mmu.s]
    tests: [mmu/sv32_basic, mmu/tlb_basic, ...]

apps:
  led_marquee:
    src_files: [app/led_marquee.s]
    linker_script: null
  calculator:
    src_files: [lib/start.S, ..., app/calculator.c]
    arch: rv32imaf_zicsr_zifencei
    include_dirs: [lib/include]
```

## 编写新测试

### 模板

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
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_01_xxx
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

test_01_xxx:
    li x14, 1                    # PASS
    ret
```

### 注册

1. 在 `build.yaml` 的 `categories` 段添加条目
2. 在 `tasks.yaml` 中添加任务（可使用 `--gen-tasks` 自动生成）
3. 创建 testbench（`EXPECTED_TOTAL` = 子测试数）

## MMU 测试特殊约定

### 内存布局

MMU 测试自约束使用前 32KB (8 页 × 4KB)：

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

### M→S→M 特权级切换

所有 Sv32 测试必须使用此模式 (M-mode 永远绕过 TLB)。

### 注意事项

- **fence.i 在 enable_sv32 前必需**
- **数据区最小化**: 使用 `.word + .word 0`，`.balign 4096` 保证页对齐
- **MMU 测试自约束 32KB**
- **地址偏移用 li+add**: 大立即数超出 addi 12-bit 范围

## 仿真

```bash
# 单个测试仿真
python -m tools.vivado_cli -task mmu_tlb_basic -create -sim

# 批量仿真
python -m tools.vivado_cli -batch "mmu_*" -create -sim --max-parallel 2
```

### 回归脚本

```bash
python tools/run_regression.py                  # 全回归
python tools/run_regression.py --category mmu   # 按类别
python tools/run_regression.py --sim-only       # 仅仿真
```

## 调试指南

| 层级 | 方法 | 适用场景 |
|------|------|----------|
| L1: 子测试 ID | x30 (first_fail_id) 直接定位 | 大多数失败 |
| L2: 陷阱记录 | x22 (mcause) + x23 (mepc) + x24 (mtval) | 异常相关失败 |
| L3: PC 追踪 | testbench 中 wb_pc/wb_inst | 时序/流水线问题 |
| L4: 波形 | Vivado XSim WDB | 硬件级问题 |

失败定位路径: `x30=5` → 查看源码 `test_05_xxx` → 5-10 行有效代码 → 直接定位出错指令。

## 测试覆盖总览

| Phase | 类别 | 测试文件 | 子测试 | 状态 |
|-------|------|---------|--------|------|
| T1 | 框架搭建 | 1 | 20 | ✅ |
| T2 | ISA | 7 | 107 | ✅ |
| T2.5 | ISA-F (FPU) | 2 | 50 | ✅ |
| T3 | 异常/中断 | 6 | 21 | ✅ |
| T4 | MMU/TLB | 11 | 72 | ✅ |
| T5 | Cache + MMIO | 7 | 29 | ✅ |
| T6 | 回归测试 | 7 | 21 | ✅ |
| T7 | 统一 MMU | 1 | 8 | ✅ |
| T8 | 特权级 | 3 | 21 | ✅ |
| T9 | 集成测试 | 3 | — | ✅ |
| **合计** | | **48** | **329** | **ALL PASS** |

## 相关技能

| 技能 | 关系 |
|------|------|
| `vivado-orchestrator` | 仿真执行：`-task` 指定测试任务，`-batch` 批量仿真，`--gen-tasks` 生成任务条目 |
| `vivado-sim-debug` | 仿真调试：`--debug trace` 启用指令追踪定位失败子测试 |
| `coding-standards` | 编码规范：testbench 命名、timescale、复位约定 |
