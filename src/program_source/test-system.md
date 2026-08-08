# 测试体系文档

> 最后更新: 2026-06-09 | 关联计划: `dev/PLAN-test-system.md` | 进度追踪: `dev/PROCESS-test-system.md`

---

## 1. 概述

本项目使用**结构化、自检、可扩展**的测试体系，覆盖指令集 (ISA)、异常/中断、特权级、MMU/TLB、Cache、MMIO、回归测试和统一 MMU 测试。

### 1.1 核心设计

- **自检协议**: 每个子测试独立返回 PASS/FAIL，失败时精确定位到子测试 ID
- **框架复用**: 测试框架 (`framework/`) 提供统一的初始化、运行、报告和陷阱处理
- **声明式注册**: `build.yaml` 定义所有测试/应用及其依赖和构建参数

### 1.2 目录结构

```
src/program_source/
├── build.yaml                   # ★ 统一编译配置（测试 + 应用）
├── framework/                  # 测试框架 (公共)
│   ├── test_framework.s        # 自检运行器 (test_init/test_run/test_report)
│   ├── trap_handlers.s         # 陷阱处理器模板
│   └── page_table_utils.s      # Sv32 页表构建工具
├── test/                       # 测试程序
│   ├── tests.yaml              # (已迁移至 build.yaml，仅保留作参考)
│   ├── isa/                    # ISA 指令测试 (7 文件, 107 子测试)
│   ├── exception/              # 异常/中断测试 (6 文件, 21 子测试)
│   ├── privilege/              # 特权级测试 (3 文件, 21 子测试)
│   ├── mmu/                    # MMU/TLB 测试 (12 文件, 80 子测试)
│   ├── cache/                  # Cache 测试 (5 文件, 21 子测试)
│   ├── mmio/                   # MMIO 测试 (2 文件, 8 子测试)
│   ├── regression/             # 回归测试 (7 文件, 21 子测试)
│   └── integration/            # 集成测试 (3 文件)
├── app/                        # 应用程序
├── lib/                        # 库
├── link.ld                     # 链接脚本 (Von Neumann)
└── link_harvard.ld             # 链接脚本 (Harvard)
```

---

## 2. 自检协议

### 2.1 寄存器约定

| 寄存器 | 用途 | 说明 |
|--------|------|------|
| x28 | pass_count | 通过数 |
| x29 | total_count | 总测试数 |
| x30 | first_fail_id | 首个失败 ID (0=全过) |
| x31 | current_test_id | 当前测试 ID (1-based) |
| x10-x17 | 子测试自由使用 | Caller-saved |
| x18-x21 | test_run 内部 | Callee-saved (框架内部) |
| x22-x27 | trap_handler 输出 | mcause/mepc/mtval |

### 2.2 内存结果区

固定地址 `0x80007000` (BRAM 内，MMU 测试布局 page 7):

| 偏移 | 内容 | 说明 |
|------|------|------|
| +0 | total_count | 总测试数 |
| +4 | pass_count | 通过数 |
| +8 | first_fail_id | 首个失败 ID |
| +12 | reserved | 保留 |
| +16 | test_1_result | 1=PASS, 0=FAIL |
| +20 | test_2_result | ... |

### 2.3 Testbench 检查

Testbench 读取 x28 (pass_count) 和 x30 (first_fail_id)：
- `x28 == EXPECTED_TOTAL && x30 == 0` → ALL PASS
- 否则报告具体失败信息

---

## 3. 构建系统

### 3.1 test_builder.py

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
```

### 3.2 构建流程

```
build.yaml → test_builder.py → rv2coe.py (WSL 回退) → .hex + .coe
```

每条测试自动拼接框架文件 + 测试源文件，调用 rv2coe.py 编译链接。

---

## 4. 仿真

### 4.1 Vivado Orchestrator

```bash
# 单个测试仿真
python -m tools.vivado_cli -task mmu_tlb_basic -create -sim

# 批量仿真
python -m tools.vivado_cli -batch "mmu_*" -create -sim --max-parallel 2
```

### 4.2 回归脚本

```bash
# 全回归
python tools/run_regression.py

# 按类别
python tools/run_regression.py --category mmu

# 仅仿真 (跳过构建)
python tools/run_regression.py --sim-only
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
    la x10, mmu_trap_handler       # 或自定义 trap handler
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
    li x14, 1                    # PASS
    ret                           # 返回 x14=1(PASS) 或 x14=0(FAIL)
```

### 5.2 注册

在 `build.yaml` 的 `categories` 段添加条目：

```yaml
categories:
  <category>:
    framework: common             # 或 mmu (需要页表工具)
    tests:
      - <category>/mytest
```

在 `tasks.yaml` 中添加任务（可使用 `--gen-tasks` 自动生成）：

```yaml
  mycategory_mytest:
    tb: tb_mycategory_mytest
    blcoe: test/mycategory/mytest.coe
    runtime: 20ms
```

### 5.3 任务字段说明

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `blcoe` | str | `""` | Bootloader COE 文件，用于 FPGA bitstream 生成和 DDR3 仿真。初始化 BRAM IP。相对路径于 `src/program_source/`。与 `blhex` 互斥。 |
| `blhex` | str | `""` | Bootloader HEX 文件，用于 SRAM 模式仿真。bootROM 通过 `$readmemh` 加载。正常仿真任务为 `boot/bootloader_phase1.hex`（2 指令跳转桩），DDR3 任务为 `boot/bootloader.hex`（完整 DDR3 初始化 + UART 下载）。与 `blcoe` 互斥。 |
| `phex` | str | `""` | 程序 HEX 文件，用于 SRAM 模式仿真。SRAM 通过 `$readmemh` 加载。相对路径于 `src/program_source/`。 |
| `runtime` | str | `""` | 仿真时间字符串 |

### 5.4 Testbench

```systemverilog
module tb_mycategory_mytest;
    localparam integer EXPECTED_TOTAL = N;
    localparam integer SIM_CYCLES    = 200000;
    // ... 标准模板 ...
endmodule
```

---

## 6. MMU 测试特殊约定

### 6.1 内存布局

仿真模型 `axi_wrap_ram` 提供 1MB BRAM (MEM_DEPTH=262144)。MMU 测试自约束使用前 32KB (8 页 × 4KB)，确保页表和测试数据在连续页内：

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

> `cache_def.svh` 中 `SRAM_DEPTH=8192` (32KB) 对应 FPGA BRAM IP 配置，仿真模型实际为 1MB。

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

自定义 `mmu_trap_handler` 处理:
- `mcause=9` (ecall from S-mode): 返回 M-mode
- `mcause=12/13/15` (page fault): 记录 mcause/mtval，跳转检查函数

### 6.4 注意事项

- **enable_sv32 前的可见性**: DCache 写穿透保证 PTW 能看到页表 store；`fence.i` 只建立取指一致性边界
- **数据区最小化**: 使用 `.word + .word 0` 代替 `.fill 1023, 4, 0`，`.balign 4096` 保证页对齐
- **MMU 测试自约束 32KB**: 页表 (8KB) + 代码 + 数据区 < 32KB (仿真模型为 1MB，但 MMU 测试布局仅使用前 8 页)
- **地址偏移用 li+add**: 0x800 等大立即数超出 addi 12-bit 范围

---

## 7. 测试覆盖总览

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

> 子测试数来源于各 testbench 的 `EXPECTED_TOTAL`。集成测试使用 `framework: none`，无子测试计数，采用直接寄存器/内存值检查。

---

## 8. 调试指南

| 层级 | 方法 | 适用场景 |
|------|------|----------|
| L1: 子测试 ID | x30 (first_fail_id) 直接定位 | 大多数失败 |
| L2: 陷阱记录 | x22 (mcause) + x23 (mepc) + x24 (mtval) | 异常相关失败 |
| L3: PC 追踪 | testbench 中 wb_pc/wb_inst | 时序/流水线问题 |
| L4: 波形 | Vivado XSim WDB | 硬件级问题 |

失败定位路径: `x30=5` → 查看源码 `test_05_xxx` → 5-10 行有效代码 → 直接定位出错指令。
