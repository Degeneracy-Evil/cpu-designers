> **[历史归档 2026-09-25]** 本文为 2026-06~08 的调试/规划快照：文中工具命令（`tools/vivado_cli`）、目录路径（`src/rtl`、`src/tb`、`src/program_source`）、时钟（cpu_clk 50MHz）及部分架构描述已被 2026-09 重构取代（现行工具链 `python3 -m tools.vivado`，RTL 位于 `src/{common,core,soc}`）。仅作历史记录，勿作操作依据。

# Linux Kernel Boot 调试文档

## 一、项目概述

在 RISC-V 32位 CPU (SimpleCPU) 上启动 Linux 7.1 kernel。CPU 通过 OpenSBI firmware 进入 S-mode kernel。目前在仿真中 kernel 可以启动到 `sched_clock` 阶段（~272M cycles），然后在 `sbi_set_timer` ecall 时崩溃。

## 二、SoC 地址映射

| 设备 | 地址范围 | 说明 |
|------|----------|------|
| DDR3/SRAM | 0x80000000 - 0x87FFFFFF | 128MB (FPGA), 16MB (仿真SRAM) |
| CLINT | 0x02000000 - 0x0200FFFF | Timer + IPI |
| PLIC | 0x0C000000 - 0x0CFFFFFF | 中断控制器 |
| APB | 0x10000000 - 0x1000FFFF | GPIO/Timer/SPI |
| UART | 0x10008000 - 0x10008FFF | NS16550A, 230400 baud |
| BootROM | 0xFC000000 - 0xFC001FFF | 2指令跳转到0x80000000 |

## 三、Firmware 构成

```
fw_payload.bin (9.4MB) = OpenSBI (0x80000000-0x803FFFFF, 4MB) + Linux Kernel (0x80400000+)
```

- OpenSBI 在 M-mode 运行，负责硬件初始化和 SBI 接口
- Kernel 在 S-mode 运行，入口 0x80400000 (物理) / 0xC0400000 (虚拟)
- DTB 嵌入在 fw_payload.bin 中，偏移 0x37020

## 四、当前崩溃问题（核心）

### 4.1 崩溃现象

```
[    0.000108] sched_clock: 64 bits at 100MHz, resolution 10ns, wraps every 4398046511100ns
```

Kernel 打印 `sched_clock` 后，下一次 SBI ecall (`sbi_set_timer`) 触发 trap 到 MTVEC (0x80000418)，但 MTVEC 处的内存内容已被清零为 `0x00000000`，导致非法指令 → 无限 trap 循环。

### 4.2 崩溃时间线

| 时间 (仿真ns) | 事件 |
|---------------|------|
| 1855769165000 | 最后一次正确执行 MTVEC (0x34021273 = OpenSBI trap handler) |
| 2723318705000 | Kernel ecall at 0xc0010bbc (sbi_set_timer) |
| 2723318985000 | MTVEC (0x80000418) 执行 0x00000000 → 非法指令 → 死循环 |

### 4.3 根因分析

**SRAM 地址 aliasing**：仿真使用 16MB SRAM 模型 (`axi_wrap_ram.sv`)，BRAM 索引为 `w_addr[23:2]`（22 bit = 16MB 寻址）。但 DTB 报告 128MB 内存，kernel 的内存初始化 (`free_area_init` / `memblock_free_all`) 清零 0x80400000-0x87FFFFFF 范围的页。当 kernel 写入 0x81000000+ 时，`[23:2]` 索引 wrap 回 0x80000000-0x80FFFFFF，覆盖了 OpenSBI 的 trap handler 代码。

**为什么 PMP 没有保护**：CPU 的 PMP CSR 寄存器存在（pmpcfg0-3, pmpaddr0-15），但 `core_top.sv` 中输出端口全部连接为空 `()`，硬件不执行任何 PMP 检查。OpenSBI 设置了 PMP 区域保护 firmware 代码，但硬件忽略这些设置。

### 4.4 当前修复方案（正在验证中）

1. **DTB patch**：将 fw_payload.bin 中 DTB 的 memory 从 128MB 改为 16MB
   - `reg = <0x80000000 0x08000000>` → `reg = <0x80000000 0x01000000>`
   - Kernel 只管理 0x80400000-0x80FFFFFF (12MB)，不会写超过 16MB 的地址
2. **SRAM 保持 16MB + [23:2]**（已知可运行到 286M cycles）
3. **远程 RTL 改动已回退**（icache/bus_bridge/dcache/MMU 的改动引入了 mmio_inflight_r 竞态条件）

### 4.5 已尝试但失败的方案

| 方案 | 结果 | 原因 |
|------|------|------|
| 128MB SRAM + [26:2] | kernel 在 0x80400098 非法指令 | Vivado xsim 对 32M entry BRAM 数组不稳定 |
| 完整 PMP checker (pmp_checker.sv) | 崩溃提前到 73M cycles | trap 进入 M-mode 时 priv_mode 未更新，PMP 拒绝 MTVEC 访问 |
| PMP M-mode bypass | 仍然 73M cycles 崩溃 | 复杂组合逻辑路径问题 |
| 简化 PMP (firmware region 写保护) | 272M cycles 仍崩溃 | dcache writeback 路径绕过检查 |
| 远程 icache mmio_inflight_r 修复 | bootROM 取指失败 | mmio_req 只由 mmio_pending_r 驱动，accept 后变低 |

## 五、远程 RTL 改动问题（需要单独修复）

同事在 git commit `e4f5cbb` 和 `2a7bffa` 中对以下文件做了修改，已回退但需要重新修复：

### 5.1 icache_ctrl.sv
- 新增 `mmio_inflight_r` 状态跟踪
- `mmio_req` 只由 `mmio_pending_r` 驱动 → bus_bridge accept 后 mmio_req 变低 → 响应被丢弃
- **修复方向**：`mmio_req = mmio_pending_r | mmio_inflight_r`

### 5.2 cpu_bus_bridge.sv
- 修改了 stale MMIO response 检测逻辑
- 原逻辑：`if (is_inst_r && icache_mmio_addr != addr_r)` 丢弃 stale 响应
- 新逻辑：`if (is_inst_r && (!icache_mmio_req || (icache_mmio_addr != addr_r)))` 丢弃
- 问题：`icache_mmio_req` 在 mmio_inflight_r 期间为低，导致正常响应被误丢弃

### 5.3 MMU.sv
- `satp_changed` 从 `(satp != satp_prev) && (priv_mode != PRIV_M)` 改为 `(satp != satp_prev)`
- 原逻辑在 M-mode 写 satp 时不触发 TLB flush，可能导致 stale TLB entries

### 5.4 dcache_ctrl.sv
- 类似的 mmio 处理改动

## 六、仿真环境

### 6.1 关键文件

| 文件 | 说明 |
|------|------|
| `src/tb/tb_kernel_boot.sv` | Kernel boot 仿真 testbench |
| `src/tb/tb_soc_includes.svh` | 仿真共享 boilerplate |
| `src/rtl/ram_wrap/axi_wrap_ram.sv` | SRAM 仿真模型 (16MB) |
| `src/rtl/core/core_top.sv` | CPU 顶层 |
| `src/rtl/core/pmp_checker.sv` | PMP 检查器 (当前未使用) |
| `config/tasks.yaml` | 仿真任务定义 |
| `build/opensbi/fw_payload.bin` | OpenSBI+kernel 原始二进制 (128MB DTB) |
| `build/opensbi/fw_payload_16mb.bin` | OpenSBI+kernel 16MB DTB 版本 |
| `src/program_source/firmware/fw_payload.hex` | 仿真用 hex 文件 (当前为 16MB DTB 版本) |

### 6.2 运行仿真

```bash
cd /home/chen/cpu-designers
export PATH="/tools/Xilinx/Vivado/2018.3/bin:$PATH"

# 日志放 /mnt/data/chen/logs/ (根分区快满了)
LOGDIR=/mnt/data/chen/logs
nohup python3 -m tools.vivado_cli -task kernel_boot_ddr3 -create -sim --debug trace,trap \
  --log $LOGDIR/run_$(date +%Y%m%d_%H%M%S).log > $LOGDIR/nohup_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

### 6.3 监控仿真

```bash
# 查看进度
XSIM_DIR="/home/chen/cpu-designers/project/kernel_boot_ddr3/simplecpu_soc.sim/sim_1/behav/xsim"
ls -t /mnt/data/chen/logs/run_*.log | head -1 | xargs tail -3

# 查看 trap 日志
wc -l "$XSIM_DIR/trap_deleg.log"
tail -5 "$XSIM_DIR/trap_deleg.log"

# 查看 UART 输出 (kernel printk)
cat "$XSIM_DIR/uart_tx.log"

# 查看指令 trace (可能很大)
wc -l "$XSIM_DIR/instr_trace.log"
tail -10 "$XSIM_DIR/instr_trace.log"
```

### 6.4 停止仿真

```bash
ps aux | grep -E "xsim|vivado" | grep -v grep | awk '{print $2}' | xargs -r kill -9
```

### 6.5 Patch DTB

```bash
python3 << 'EOF'
import struct, shutil
src = 'build/opensbi/fw_payload.bin'
dst = 'build/opensbi/fw_payload_16mb.bin'
shutil.copy2(src, dst)
with open(dst, 'r+b') as f:
    data = f.read()
    dtb = data.find(struct.pack('>I', 0xd00dfeed))
    reg = data.find(bytes([0x80,0,0,0,0x08,0,0,0]), dtb)
    f.seek(reg)
    f.write(bytes([0x80,0,0,0,0x01,0,0,0]))  # 128MB → 16MB
import subprocess
subprocess.run(['python3','tools/bin2hex.py',dst,
    'src/program_source/firmware/fw_payload.hex'], capture_output=True)
print("DTB patched to 16MB, hex regenerated")
EOF
```

## 七、关键 RTL 信号

用于调试的信号层次路径：

```
u_soc.cpu.priv_mode                    # 当前特权级 (2'b11=M, 2'b01=S)
u_soc.cpu.target_priv                  # trap 目特权级
u_soc.cpu.trap_enter_valid             # trap 进入脉冲
u_soc.cpu.trap_return_valid            # mret/sret 脉冲
u_soc.cpu.csr_mtvec                    # MTVEC 寄存器值
u_soc.cpu.csr_mepc                     # MEPC 寄存器值
u_soc.cpu.csr_mcause                   # MCAUSE 寄存器值
u_soc.cpu.csr_medeleg                  # MEDELEG 寄存器值
u_soc.cpu.csr_stval                    # STVAL 寄存器值
u_soc.cpu.hw_trap_epc                  # 硬件写入的 trap EPC
u_soc.cpu.hw_trap_tval                 # 硬件写入的 trap TVAL
u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.exc_delegated  # delegation 决策
u_soc.cpu.u_trap_csr.u_trap_mgr.u_clint.trap_to_s     # 是否 trap 到 S-mode
u_soc.cpu.u_trap_csr.u_trap_mgr.exception_pc_r        # 异常 PC
u_soc.cpu.u_trap_csr.u_trap_mgr.exception_mtval_r     # 异常 mtval
u_soc.cpu.u_trap_csr.u_trap_mgr.inst_page_fault_vaddr_r # inst PF 虚拟地址
u_soc.cpu.mmu_inst_paddr               # 指令物理地址 (MMU输出)
u_soc.cpu.mmu_data_paddr               # 数据物理地址 (MMU输出)
u_soc.cpu.mmu_inst_ready               # MMU i-side 就绪
u_soc.cpu.mmu_data_ready               # MMU d-side 就绪
u_soc.cpu.mem_en                       # 内存访问使能
u_soc.cpu.mem_hwrite                   # 写使能 (1=store, 0=load)
u_soc.cpu.csr_pmpcfg0                  # PMP config 0 (当前连接到wire但未使用)
u_soc.cpu.csr_pmpaddr0                 # PMP addr 0
```

## 八、CPU 架构要点

- **非流水线设计**：每条指令完整执行后才开始下一条，无 forwarding/hazard
- **MEDELEG=0xb109**：bit 0(instruction fault), bit 3(breakpoint), bit 8(ecall S), bit 11(ecall M) 已委托
- **MIDELEG=0x222**：bit 1(SSI), bit 5(STI), bit 9(SEI) 已委托
- **MMU**：SV32 分页，4个TLB set × 4 way = 16 entry
- **Cache**：icache 8set×4way×8word, dcache 8set×4way×8word, write-back
- **PMP**：16 entry CSR 存在但硬件检查未实现

## 九、QEMU 对比

Kernel 在 QEMU 上完整启动到 initcall late level，仅因无 initramfs panic。Kernel 二进制正确。

```bash
# QEMU 运行命令 (参考)
qemu-system-riscv32 -M virt -nographic -bios build/opensbi/fw_payload.bin \
  -append "console=ttyS0,230400 earlycon=uart8250,mmio32,0x10008000,230400n8 ignore_loglevel loglevel=8 rdinit=/init"
```

## 十、当前仿真状态

- **PID**: 3927079
- **配置**: 16MB SRAM + [23:2] + DTB 16MB + 旧 icache/bus_bridge + PMP 禁用
- **进度**: 75M cycles, kernel 在 S-mode 正常运行
- **目标**: 通过 272M cycle 崩溃点
- **预计到达崩溃点**: ~4 小时 (从 17:04 开始)
- **日志**: `/mnt/data/chen/logs/run_20260624_170423.log`

## 十一、Git 状态

```
当前分支: wood-dev
最新 commit: ec5bdb4 (回退SRAM到16MB+patch DTB到16MB)

本分支相对于 e000e3c 的改动:
- SRAM: 保持 16MB + [23:2] (原始配置)
- DTB: patch 到 16MB (fw_payload_16mb.bin)
- core_top.sv: PMP CSR 端口已连接, pmp_data_violation=0 (禁用)
- pmp_checker.sv: 新文件 (当前未实例化)
- tb_kernel_boot.sv: 新 testbench, UART 接收器使用 enable 信号
- config/tasks.yaml: 添加 kernel_boot_ddr3 任务
- 远程 icache/bus_bridge/dcache/MMU 改动已回退

远程 commit e4f5cbb/2a7bffa 的改动已回退, 需要重新修复:
- icache_ctrl.sv: mmio_inflight_r 竞态条件
- cpu_bus_bridge.sv: stale response 检测逻辑
- MMU.sv: satp_changed 权限门控
- dcache_ctrl.sv: mmio 处理改动
```
