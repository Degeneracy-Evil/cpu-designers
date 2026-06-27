# 项目常用命令速查

> **日期**：2026-06-26
> **适用分支**：`chp`

---

## 0. 环境准备（每次开新终端必须执行）

```bash
cd /mnt/data/chen/cpu-designers          # 项目根目录（软链接自 /home/chen/cpu-designers）
export PATH="/tools/Xilinx/Vivado/2018.3/bin:$PATH"   # Vivado 工具链
```

---

## 1. 仿真（vivado_cli）— 最常用

### 1.1 基本流程

```bash
# 首次：创建会话 + 仿真（会自动编译 RTL、生成 IP、加载程序）
python3 -m tools.vivado_cli -task <任务名> -create -sim

# 复用已有会话重新仿真（不重新编译，秒级启动）
python3 -m tools.vivado_cli -task <任务名> -sim

# 改了 RTL 后：先刷新再仿真
python3 -m tools.vivado_cli -task <任务名> -refresh -sim

# 只改了程序 hex/coe：秒级刷新（不全量重编译）
python3 -m tools.vivado_cli -task <任务名> -refresh --layers coe -sim
```

### 1.2 Kernel Boot 仿真任务（当前调试重点）

```bash
# 128MB SRAM + 128MB DTB（与 FPGA 一致，约 5 小时到 trap）
python3 -m tools.vivado_cli -task kernel_boot_sram_cdc -create -sim \
  --debug trap --log /mnt/data/chen/logs/run_$(date +%Y%m%d_%H%M%S).log

# 128MB SRAM + 16MB DTB（控制变量，约 3.8 小时到 trap）
python3 -m tools.vivado_cli -task kernel_boot_sram128_dtb16 -create -sim \
  --debug trap --log /mnt/data/chen/logs/run_$(date +%Y%m%d_%H%M%S).log

# 后台运行（长时间仿真必须用 nohup）
nohup python3 -m tools.vivado_cli -task kernel_boot_sram128_dtb16 -create -sim \
  --debug trap \
  --log /mnt/data/chen/logs/run_$(date +%Y%m%d_%H%M%S).log \
  > /mnt/data/chen/logs/nohup_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

### 1.3 ISA / 单元测试仿真

```bash
# 单个 ISA 测试
python3 -m tools.vivado_cli -task isa_alu -create -sim
python3 -m tools.vivado_cli -task mmu_tlb_basic -create -sim

# 带调试输出
python3 -m tools.vivado_cli -task isa_alu -sim --debug trace,trap

# 全部调试（指令追踪 + 流水线 + 异常 + Spike对比 + 波形）
python3 -m tools.vivado_cli -task isa_alu -sim --debug all
```

### 1.4 批量仿真

```bash
# 并行仿真所有 ISA 测试（通配符）
python3 -m tools.vivado_cli -batch "isa_*" -create -sim

# 并行仿真 MMU + Cache 测试
python3 -m tools.vivado_cli -batch "mmu_*,cache_*" -create -sim --max-parallel 4

# 回归测试（构建 + 仿真一条龙）
python3 tools/run_regression.py                  # 全回归
python3 tools/run_regression.py --category mmu   # 按类别
python3 tools/run_regression.py --sim-only       # 仅仿真（跳过构建）
```

### 1.5 仿真监控与管理

```bash
# 查看所有会话状态 + 文件是否过期
python3 -m tools.vivado_cli --status

# 查看仿真进度（probe 日志）
ls -t /mnt/data/chen/logs/run_*.log | head -1 | xargs tail -5

# 查看 UART 输出（kernel printk）
cat /mnt/data/chen/cpu-designers/project/<task_name>/simplecpu_soc.sim/sim_1/behav/xsim/uart_tx.log

# 查看 trap 日志
tail -10 /mnt/data/chen/cpu-designers/project/<task_name>/simplecpu_soc.sim/sim_1/behav/xsim/trap_deleg.log

# 查看指令追踪
tail -10 /mnt/data/chen/cpu-designers/project/<task_name>/simplecpu_soc.sim/sim_1/behav/xsim/instr_trace.log

# 停止所有仿真
ps aux | grep -E "xsim|vivado" | grep -v grep | awk '{print $2}' | xargs -r kill -9

# 清理旧会话
python3 -m tools.vivado_cli --cleanup        # 清理最旧的，保留 max_sessions-1
python3 -m tools.vivado_cli --cleanup-all     # 清理所有会话
```

### 1.6 --debug 选项说明

| 选项 | 说明 | 产物 |
|------|------|------|
| `trace` | 指令追踪（每条指令 PC + inst + 关键寄存器） | `instr_trace.log` |
| `pipeline` | 流水线各阶段状态 | `instr_trace.log` |
| `trap` | 异常/trap 追踪 | `trap_deleg.log`, `trap_trace.log` |
| `spike` | Spike ISA 对比 | 对比日志 |
| `wave` | 波形记录 | `.wdb` 文件（注意空间！） |
| `wave:full` | 完整波形 | 更大的 `.wdb` |
| `all` | 以上全部 | 所有日志 + 最大 wdb |

> **注意**：`wave` 会产生巨大的 `.wdb` 文件（12G+/次）。长时间仿真慎用。

---

## 2. 测试程序构建（test_builder）

### 2.1 构建 hex/coe 文件

```bash
# 构建所有测试程序
python3 tools/test_builder.py

# 按类别构建
python3 tools/test_builder.py --category isa
python3 tools/test_builder.py --category mmu
python3 tools/test_builder.py --category cache

# 构建单个测试
python3 tools/test_builder.py --test isa/alu
python3 tools/test_builder.py --test mmu/tlb_basic

# 列出所有可用测试
python3 tools/test_builder.py --list

# 构建 app
python3 tools/test_builder.py --app led_marquee

# 清理所有生成的 hex/coe
python3 tools/test_builder.py --clean

# 生成 tasks.yaml 任务条目（粘贴到 tasks.yaml）
python3 tools/test_builder.py --gen-tasks
```

### 2.2 构建配置

测试程序定义在 `dev/program_source/build.yaml` 中：
- 源码：`dev/program_source/test/<category>/<name>.c` 或 `.S`
- 输出：`dev/program_source/test/<category>/<name>.hex` 和 `.coe`
- 链接脚本：`dev/program_source/link.ld`
- 编译器：`riscv64-linux-gnu-gcc`（rv32im_zicsr_zifencei, ilp32）

---

## 3. FPGA 上板

```bash
# 生成 bitstream
python3 -m tools.vivado_cli -task fpga -create -bitstream

# 下载 bitstream 到 FPGA
python3 -m tools.vivado_cli -task fpga -program

# 刷新后重新生成（改了 RTL 后）
python3 -m tools.vivado_cli -task fpga -refresh -bitstream
```

---

## 4. 反汇编与调试

```bash
# 反汇编 kernel（查找函数地址对应的指令）
riscv64-linux-gnu-objdump -d build/kernel/vmlinux | grep -A20 "c038af60"

# 反汇编并搜索特定地址
riscv64-linux-gnu-objdump -d build/kernel/vmlinux | grep -B5 -A5 "c01df3c8:"

# 查找函数所在地址
riscv64-linux-gnu-objdump -d build/kernel/vmlinux | grep "<dma_atomic_pool_init>"

# hex 转 bin
python3 tools/bin2hex.py <input.bin> <output.hex>

# 分析指令追踪日志
python3 -m tools.trace_analyzer parse <trace.log>
python3 -m tools.trace_analyzer find-fail <trace.log>     # 定位 PC 跳变
python3 -m tools.trace_analyzer diff <trace.log> <spike.log>  # 与 Spike 对比
python3 -m tools.trace_analyzer stats <trace.log>          # 统计信息
```

---

## 5. 配置与 IP 管理

```bash
# 修改 vivado_config.yaml 后重新生成 cache_def.svh
python3 -m tools.vivado_cli --gen-config

# 增量刷新（只刷新指定层）
python3 -m tools.vivado_cli -task <task> -refresh --layers rtl     # 只刷新 RTL
python3 -m tools.vivado_cli -task <task> -refresh --layers tb      # 只刷新 TB
python3 -m tools.vivado_cli -task <task> -refresh --layers coe     # 只刷新程序
python3 -m tools.vivado_cli -task <task> -refresh --layers fpga    # 只刷新 FPGA 约束

# 全量刷新（改了 RTL 后必须）
python3 -m tools.vivado_cli -task <task> -refresh
```

---

## 6. DTB Patch（16MB 控制变量）

```bash
# 将 fw_payload.bin 中的 DTB 从 128MB 改为 16MB
python3 << 'EOF'
import struct, shutil, subprocess
src = 'build/opensbi/fw_payload.bin'
dst = 'build/opensbi/fw_payload_16mb.bin'
shutil.copy2(src, dst)
with open(dst, 'r+b') as f:
    data = f.read()
    dtb = data.find(struct.pack('>I', 0xd00dfeed))
    reg = data.find(bytes([0x80,0,0,0,0x08,0,0,0]), dtb)
    f.seek(reg)
    f.write(bytes([0x80,0,0,0,0x01,0,0,0]))  # 128MB → 16MB
subprocess.run(['python3','tools/bin2hex.py',dst,
    'dev/program_source/firmware/fw_payload.hex'], capture_output=True)
print("Done")
EOF
```

---

## 7. 日志与空间管理

```bash
# 仿真日志统一放 /mnt/data/chen/logs/（根分区容易满）
mkdir -p /mnt/data/chen/logs

# 检查磁盘空间
df -h / /mnt/data

# 清理 /tmp 中的 vivado 临时文件（vivado 打开 wdb 时产生）
rm -f /tmp/tb_kernel_boot_behav_*.xilwvdat

# 清理旧 wdb（每个 12G+）
find /mnt/data/chen/cpu-designers/project -name "*.wdb" -exec ls -lh {} \;

# 清理旧会话目录
python3 -m tools.vivado_cli --cleanup
```

---

## 8. 常用任务名速查

| 任务名 | 说明 | 类型 |
|--------|------|------|
| `kernel_boot_sram_cdc` | Linux boot, 128MB SRAM + 128MB DTB | 仿真 |
| `kernel_boot_sram128_dtb16` | Linux boot, 128MB SRAM + 16MB DTB | 仿真 |
| `kernel_boot_ddr3` | Linux boot, DDR3 模式（极慢，暂不用） | 仿真 |
| `fpga` | FPGA bitstream 生成 + 下载 | 上板 |
| `cpu_full` | 集成测试 | 仿真 |
| `isa_alu` ~ `isa_f_ext` | ISA 单元测试 | 仿真 |
| `mmu_tlb_basic` ~ `mmu_tlb_asid` | MMU/TLB 测试 | 仿真 |
| `exception_*` | 异常处理测试 | 仿真 |
| `privilege_*` | 特权级测试 | 仿真 |

---

## 9. 典型工作流

### 9.1 修改 RTL 后重新仿真

```bash
cd /mnt/data/chen/cpu-designers
export PATH="/tools/Xilinx/Vivado/2018.3/bin:$PATH"

# 1. 改 RTL（如 dev/rtl/core/MMU.sv）
vim dev/rtl/core/MMU.sv

# 2. 刷新 + 仿真
python3 -m tools.vivado_cli -task kernel_boot_sram128_dtb16 -refresh -sim \
  --debug trap --log /mnt/data/chen/logs/run_$(date +%Y%m%d_%H%M%S).log
```

### 9.2 修改测试程序后重新仿真

```bash
# 1. 改测试源码
vim dev/program_source/test/isa/alu.c

# 2. 重新编译
python3 tools/test_builder.py --test isa/alu

# 3. 秒级刷新 + 仿真（只刷新 coe 层，不重编译 RTL）
python3 -m tools.vivado_cli -task isa_alu -refresh --layers coe -sim
```

### 9.3 后台长时间仿真

```bash
nohup python3 -m tools.vivado_cli -task kernel_boot_sram128_dtb16 -refresh -sim \
  --debug trap \
  --log /mnt/data/chen/logs/run_$(date +%Y%m%d_%H%M%S).log \
  > /mnt/data/chen/logs/nohup_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# 监控
ls -t /mnt/data/chen/logs/run_*.log | head -1 | xargs tail -3
```

---

## 10. 关键文件位置

```
项目根目录:        /mnt/data/chen/cpu-designers (← /home/chen/cpu-designers 软链接)
RTL 源码:          dev/rtl/core/           (CPU 核心)
                   dev/rtl/ram_wrap/       (内存包装器)
                   dev/rtl/system_top.sv   (SoC 顶层)
Testbench:         dev/tb/tb_kernel_boot.sv (kernel boot TB)
测试程序源码:       dev/program_source/test/
测试程序构建配置:   dev/program_source/build.yaml
仿真任务配置:       tasks.yaml
Vivado 配置:       vivado_config.yaml
IP 生成脚本:        tools/vivado_core/ip_gen.py
仿真项目输出:       project/<task_name>/simplecpu_soc.sim/sim_1/behav/xsim/
Kernel 二进制:     build/kernel/vmlinux
OpenSBI+Kernel:    build/opensbi/fw_payload.bin
QEMU 参考日志:     build/qemu/boot_kernel2.log
日志目录:          /mnt/data/chen/logs/
```
