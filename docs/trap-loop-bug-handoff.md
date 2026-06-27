# Trap-Loop Bug 调试交接文档

> **用途**：本文档是新 AI session 的入口点，包含当前 bug 的完整状态、已完成的工作、待做的决策。
> **日期**：2026-06-26 20:30
> **分支**：`chp`

---

## 一、当前核心 Bug

### 1.1 现象

Linux kernel 启动到 `initcall level: postcore` 阶段后，CPU 突然产生**假的 ecall trap**（cause=9, ecall from S-mode），然后进入 `handle_exception` 死循环。

**两个仿真配置均在同一位置崩溃：**

| 配置 | 首次假 ecall cycle | trap-loop PC | cause | EPC | EMTVAL |
|------|---------------------|--------------|-------|-----|--------|
| #3: 128MB SRAM + 128MB DTB | 361.7M | c037fa58-78 | 9 | c01df3c8 | a0021014 |
| #4: 128MB SRAM + 16MB DTB | 264.4M | c037fa58-78 | 9 | c01df3c8 | a0021014 |

**FPGA 上同样的 bug**：PC=0xC037FA58-0xC037FA78 (handle_exception)，cause=9，IPFN=0xC038AF60 (dma_atomic_pool_init)。**仿真已成功复现 FPGA bug。**

### 1.2 关键证据

#### trap_deleg.log 分析（#3 为例）

```
# 最后一次正常 ecall (line 118):
118  2723117635000  TRAP_IN  c0010bbc  1  3  00000009  0  0  c0010bbc  00000000  80400098  ...  (ecall in __sbi_ecall, M-mode处理, 正常)

# ~894ms 正常执行后...

# 第一次假 ecall (line 120):
120  3617262635000  TRAP_IN  c01df3cc  1  1  00000009  1  1  c01df3c8  a0021014  80400098  ...  (EPC=c01df3c8, 但真实指令是 sw s1,20(a0), 不是 ecall!)

# 紧接着进入 handle_exception 也触发假 ecall (line 121+):
121  3617263555000  TRAP_IN  c037fa68  1  1  00000009  1  1  c01df3c8  a0021014  ...
122  3617264855000  TRAP_IN  c037fa78  1  1  00000009  1  1  c037fa74  ffffff74  ...
...（200万行 trap-loop）
```

#### 反汇编对照

```
c01df3c8:  00952a23  sw s1,20(a0)     # gen_pool_add_owner 中的 store，不是 ecall
c0010bbc:  00000073  ecall            # __sbi_ecall 中的合法 ecall

c037fa58 <handle_exception>:
c037fa58:  14021273  csrrw tp,sscratch,tp
c037fa5c:  00021663  bnez tp,c037fa68
c037fa64:  00222423  sw sp,8(tp)
c037fa68:  00222623  sw sp,12(tp)
c037fa6c:  00822103  lw sp,8(tp)
c037fa70:  f7010113  addi sp,sp,-144
c037fa74:  00112223  sw ra,4(sp)      # 这些指令全被误判为 ecall
c037fa78:  00312623  sw gp,12(sp)
```

#### UART 输出（两个仿真完全一致）

```
[    0.895701] calling  0xc038af60 @ 1     # dma_atomic_pool_init
# 之后无更多输出，进入 trap-loop
```

### 1.3 根因推断

**CPU 在连续大量执行后，取指开始返回 0x00000073 (ecall) 而非真实指令。**

证据：
1. EPC=c01df3c8 的真实指令是 `0x00952a23` (sw)，但 CPU 报告 cause=9 (ecall)
2. 进入 handle_exception 后，其内部指令也全部被识别为 ecall → 死循环
3. EMTVAL=`a0021014` — ecall 指令不应产生非零 mtval，这个值是异常的
4. IPF_VA=`80400098` — 两个仿真完全相同，确定性 bug
5. 两个仿真 EMTVAL 和 IPF_VA 完全一致 → 不是随机翻转

**可能原因（待验证）：**
- icache miss 后 refill 从 AXI 总线读取到错误数据（0x00000073）
- TLB 查找返回错误物理地址，导致从错误地址取指
- 某种状态机竞态导致取指数据路径被污染

---

## 二、已完成的工作

### 2.1 已修复的 Bug（均在 `chp` 分支）

| Bug | 文件 | 修复内容 | 验证状态 |
|-----|------|----------|----------|
| MMU walk arbiter 竞态 | `MMU.sv` | W_D_WALK/W_I_WALK 的 ptw_walk_done 分支增加 walk_req 捕获 | ✅ 通过旧 182M 死锁点 |
| TLB BRAM WRITE_FIRST 碰撞 | `ip_gen.py` | 所有 BRAM IP 改为 READ_FIRST | ✅ XCI 确认 + 仿真通过旧 300M panic |
| i-side 查找被 tlb_fill_req 门控 | `MMU.sv` | 移除 i_tlb_lookup_req/i_ready/i_miss/i_walk_req 的 tlb_fill_req 门控 | ✅ 编译通过 |
| SRAM 16MB aliasing | `axi_wrap_ram.sv` | MEM_DEPTH 4M→32M, [23:2]→[26:2], 扩展到 128MB | ✅ 通过旧 272M crash 点 |
| SRAM X 传播 | `axi_wrap_ram.sv` | $readmemh 前零初始化整个数组 | ✅ 通过旧 65M crash 点 |
| TB repeat(3B) 整数溢出 | `tb_kernel_boot.sv` | repeat(3000000000)→repeat(2000000000) | ✅ xsim 不再 0fs 退出 |
| TB stall watchdog | `tb_kernel_boot.sv` | if_done==0 持续 10000 周期时 dump 状态并 finish | ✅ 未误触发 |

### 2.2 已验证的里程碑

两个仿真（#3 和 #4）在 trap-loop 前都**成功通过**了以下旧 crash 点：

| 旧 crash 点 | cycle | 原因 | 修复 |
|-------------|-------|------|------|
| 65M X 传播 | 65M | 未初始化 BRAM 区域 X 传播 | 零初始化 |
| 182M MMU 死锁 | 182M | walk arbiter 竞态 | walk_req 捕获 |
| 272M SRAM aliasing | 272M | 16MB SRAM 地址回绕 | 128MB 扩展 |
| 300M stack-protector panic | 300M | TLB BRAM WRITE_FIRST 碰撞 | READ_FIRST |

### 2.3 仿真进度对照（QEMU 参考）

| 里程碑 | QEMU kernel time | #3 (128+128) | #4 (128+16) |
|--------|------------------|--------------|-------------|
| early | 0.047s | ✅ 已过 | ✅ 已过 |
| pure | 0.080s | ✅ 已过 | ✅ 已过 |
| core | 0.082s | ✅ 已过 | ✅ 已过 |
| postcore | 0.108s | ✅ 已过 | ✅ 已过 |
| **calling c038af60** | ~0.11s | ✅ 到达后 trap-loop | ✅ 到达后 trap-loop |
| arch | 0.129s | ❌ 未到 | ❌ 未到 |
| subsys | 0.151s | ❌ | ❌ |
| fs | 0.190s | ❌ | ❌ |
| device | 0.247s | ❌ | ❌ |
| late | 0.526s | ❌ | ❌ |
| Run /bin/init | 0.629s | ❌ | ❌ |
| Kernel panic (QEMU终态) | 0.632s | ❌ | ❌ |

---

## 三、wdb 波形分析结果（已尝试，失败）

### 3.1 现有 wdb 文件

- 路径: `/mnt/data/chen/cpu-designers/project/kernel_boot_sram_cdc/simplecpu_soc.sim/sim_1/behav/xsim/tb_kernel_boot_behav.wdb`
- 大小: 12 GB
- 包含数据到: xsim 崩溃时刻 (cycle ~483M)

### 3.2 查询方法

用 `vivado -mode batch` 打开 wdb，使用 `get_value_database -time <ps> <object>` 查询信号值：

```tcl
open_wave_database "/path/to/tb_kernel_boot_behav.wdb"
set val [get_value_database -radix hex -time 3617262635000 [get_objects /tb_kernel_boot/if_pc]]
```

### 3.3 失败原因

1. **wdb 只记录了 TB 顶层端口信号**：`add_wave /` 在 batch xsim 模式下只添加了 TB 顶层端口（`if_pc`, `if_inst`, `clk` 等），CPU 内部所有 debug 信号（`dbg_mmu_i_state`, `dbg_icache_state`, `csr_satp`, `hw_trap_epc` 等）全部 `NO_OBJECT`
2. **TB 顶层信号全部返回 `c037fa58`**：trap-loop 中所有流水线阶段的 PC 都相同，没有时间维度的变化信息
3. **`get_transitions` 返回 Blank**：wdb 可能因 xsim 崩溃而数据不完整
4. **vivado 打开 12G wdb 产生 ~16G 临时文件**在 `/tmp`，容易吃满根分区
5. **每次 `get_value_database` 查询耗时 ~1 分钟**

**结论：现有 wdb 无法用于有效分析 trap-loop 的根因。**

---

## 四、接下来需要做的决策

### 4.1 重新仿真的方案选择

| 方案 | 优点 | 缺点 |
|------|------|------|
| **A. $fwrite circular buffer** | 零开销、精确捕捉 trigger 前 2000 周期、不依赖 wdb | 需要修改 TB，可能引入变量（但复用现有 probe 块的层次引用可降低风险） |
| **B. 显式 add_wave CPU 内部信号** | wdb 可用 vivado batch 查询 | 12G→可能 50G+ wdb，查询极慢，仍需 GUI 分析 |
| **C. $fwrite 全量 trace（cycle > N 后）** | 简单直接 | 5M 周期 × 20 信号 ≈ 5-10 GB 文本，大部分是无关数据 |
| **D. VCD dump（时间门控）** | 标准格式，可用 gtkwave | xsim VCD 支持不确定，仍需跑 264M 周期 |

**推荐方案 A**：circular buffer 方案。在 TB 的 `always @(posedge clk)` 里维护深度 2000 的环形缓冲区，存关键信号。当检测到假 ecall trap（cause=9 且 EPC ≠ c0010bbc）时，dump 缓冲区到文件并 `$finish`。

### 4.2 仿真配置选择

| 配置 | 到 trap 时间 | 优点 | 缺点 |
|------|-------------|------|------|
| **128MB SRAM + 16MB DTB (#4)** | ~3.8 小时 | 更快到达 trap | - |
| 128MB SRAM + 128MB DTB (#3) | ~5.2 小时 | 与 FPGA 完全一致 | 更慢 |

**推荐用 #4**（128+16）：bug 完全一致，节省 1.4 小时。

### 4.3 关键注意事项

1. **保持 `add_wave /`**：即使不用 wdb，也保持原有的波形配置，避免改变 xsim 的优化行为导致 bug 不复现
2. **wdb 写到 data 盘**：`/home/chen/cpu-designers` 已软链接到 `/mnt/data/chen/cpu-designers`，wdb 会写到 data 盘（49G 可用），不会吃满根分区
3. **清理 /tmp**：vivado 打开 wdb 会在 /tmp 产生大量临时文件，注意监控
4. **`/tmp` 中的 xilwvdat 文件**：vivado batch 查询 wdb 产生，每次 ~16G，用完必须删

---

## 五、需要捕捉的关键信号

在 circular buffer 中应存储以下信号（从 TB 层次引用，`/tb_kernel_boot/u_soc/cpu/...`）：

### 5.1 取指路径（最关键）

```
fetch_vaddr           # 虚拟取指地址
mmu_inst_paddr        # MMU 翻译后的物理地址
mmu_inst_ready        # MMU i-side 就绪
mmu_inst_miss         # TLB miss
instData_32_mux       # 最终指令字
inst_valid_mux        # 指令有效
if_pc / if_inst       # IF 阶段 PC 和指令
id_pc / id_inst       # ID 阶段
exe_pc / exe_inst     # EXE 阶段
```

### 5.2 TLB / MMU 状态

```
dbg_mmu_i_state       # i-side MMU 状态机
dbg_mmu_i_tlb_hit     # TLB 命中
dbg_mmu_i_tlb_valid   # TLB valid
dbg_mmu_i_input_changed
dbg_mmu_i_latched_vaddr
dbg_mmu_walk_state    # PTW walk 状态机
dbg_ptw_walk_active
dbg_pending_i_walk
```

### 5.3 ICache 状态

```
dbg_icache_state      # icache 状态机
icache_refill_req     # refill 请求
icache_refill_addr    # refill 地址
icache_refill_data    # refill 数据
icache_refill_valid   # refill 有效
```

### 5.4 AXI 总线（取指 refill 走的总线）

```
cpu_araddr / cpu_arvalid / cpu_arready
cpu_rdata / cpu_rvalid / cpu_rlast / cpu_rready
```

### 5.5 Trap 相关

```
hw_trap_epc           # 硬件 trap EPC
hw_trap_cause         # 硬件 trap cause
hw_trap_tval          # 硬件 trap tval
priv_mode             # 当前特权级
trap_enter_valid      # trap 进入脉冲
dec_is_ecall          # 译码阶段 ecall 识别
```

---

## 六、关键文件索引

### RTL

| 文件 | 说明 |
|------|------|
| `dev/rtl/core/MMU.sv` | MMU + TLB，含 walk arbiter 修复 |
| `dev/rtl/core/tlb.sv` | TLB 模块 (Port A=i-side, Port B=d-side/fill, READ_FIRST) |
| `dev/rtl/core/core_top.sv` | CPU 顶层 |
| `dev/rtl/core/cpu_clint.sv` | trap 委托逻辑, medeleg=0x0000_B1FF |
| `dev/rtl/core/cpu_trap_manager.sv` | 异常原因生成 |
| `dev/rtl/system_top.sv` | SoC 顶层, Axi_CDC, 地址解码器 |
| `dev/rtl/ram_wrap/axi_wrap_ram.sv` | SRAM 模型 (128MB, [26:2], 零初始化) |
| `dev/rtl/ram_wrap/axi_wrap_ddr.sv` | DDR3 包装器 (FPGA用, 第二级 Axi_CDC) |

### 仿真

| 文件 | 说明 |
|------|------|
| `dev/tb/tb_kernel_boot.sv` | Kernel boot TB, 含 stall watchdog |
| `tasks.yaml` | 任务定义: `kernel_boot_sram_cdc` (128+128), `kernel_boot_sram128_dtb16` (128+16) |
| `dev/program_source/firmware/fw_payload.hex` | 128MB DTB hex |
| `dev/program_source/firmware/fw_payload_16mb.hex` | 16MB DTB hex |

### 构建

| 文件 | 说明 |
|------|------|
| `build/opensbi/fw_payload.bin` | OpenSBI+kernel, 128MB DTB (FPGA用) |
| `build/opensbi/fw_payload_16mb.bin` | OpenSBI+kernel, 16MB DTB (仿真控制变量) |
| `build/kernel/vmlinux` | Linux kernel ELF (可用 riscv64-linux-gnu-objdump 反汇编) |
| `build/qemu/boot_kernel2.log` | QEMU 参考启动日志 (860行, panic at 0.632s) |
| `tools/vivado_core/ip_gen.py` | BRAM IP 生成, READ_FIRST |

### 日志（崩溃数据）

| 文件 | 说明 |
|------|------|
| `project/kernel_boot_sram_cdc/.../xsim/trap_deleg.log` | #3 trap 日志 (2088733行) |
| `project/kernel_boot_sram_cdc/.../xsim/uart_tx.log` | #3 UART 输出 (202行) |
| `project/kernel_boot_sram_cdc/.../xsim/trap_trace.log` | #3 trap trace (24M) |
| `project/kernel_boot_sram_cdc/.../xsim/tb_kernel_boot_behav.wdb` | #3 波形 (12G, 不可用) |
| `project/kernel_boot_sram128_dtb16/.../xsim/trap_deleg.log` | #4 trap 日志 (2922757行) |
| `project/kernel_boot_sram128_dtb16/.../xsim/uart_tx.log` | #4 UART 输出 (203行) |

---

## 七、环境信息

### 磁盘

```
/dev/vda1 (根)   99G  69G used  26G free  73%  ← /tmp 在这里, 注意监控
/data (data盘)   73G  24G used  49G free  33%  ← /mnt/data/chen, 仿真项目在这里
/home/chen/cpu-designers → /mnt/data/chen/cpu-designers (软链接)
```

### 工具链

```bash
export PATH="/tools/Xilinx/Vivado/2018.3/bin:$PATH"
# 反汇编
riscv64-linux-gnu-objdump -d build/kernel/vmlinux
# 仿真
python3 -m tools.vivado_cli -task kernel_boot_sram128_dtb16 -create -sim
```

### 仿真速率

- SRAM 模式: ~70 M cycles/hr (1.18 M cycles/min)
- DDR3 模式: 不可用 (AXI hex 加载需 107 小时)

### CPU 架构要点

- **非流水线设计**：每条指令完整执行后才开始下一条
- **SV32 分页**：4 个 TLB set × 4 way = 16 entry
- **Cache**：icache 8set×4way×8word, dcache 8set×4way×8word, write-back
- **MEDELEG=0x0000b109** (仿真中), bit 9=0 (S-mode ecall 不可委托)
- **PMP**：CSR 存在但硬件检查未实现

---

## 八、Git 状态

```
分支: chp
最新 commit: 36f8a75 (SRAM零初始化)

chp 分支的修复 commit (从旧到新):
7c6c1ca  修复walk_req被tlb_fill_req错误门控导致walk请求丢失
91a2546  修复TLB BRAM碰撞: WRITE_FIRST→READ_FIRST + 移除i-side冻结
ebf3c02  DDR3仿真: 128MB DTB + stall watchdog等ddr_data_init
ab4837e  SRAM模型扩到128MB: 地址线[23:2]→[26:2], MEM_DEPTH 4M→32M
36f8a75  SRAM模型: 初始化整个数组为0,避免X传播
```

---

## 九、FPGA 与仿真对比

### 9.1 FPGA 状态

- FPGA 有 READ_FIRST + 所有 MMU 修复
- 但仍显示 `handle_exception` trap-loop
- FPGA trap-loop 详情：PC=0xC037FA78, cause=9, stval=0xFFFFFF74, sepc=0xC037FA74, IPFN=0xC038AF60

### 9.2 仿真与 FPGA 的差异

| | 仿真 (SRAM) | FPGA (DDR3) |
|---|---|---|
| 内存模型 | SRAM 行为模型 | DDR3 MIG |
| CDC 级数 | 1级 (cpu_clk→sys_clk) | 2级 (cpu_clk→sys_clk→ui_clk→MIG) |
| 内存大小 | 128MB SRAM | 128MB DDR3 |
| DTB | 128MB 或 16MB | 128MB |

**关键结论**：Axi_CDC 不会损坏数据（OpenSBI 在 FPGA 上完整运行+输出证明了这一点）。bug 在 CPU 核心逻辑中，与内存介质无关。仿真已成功复现 FPGA bug。

### 9.3 OpenSBI 验证

OpenSBI 在 M-mode 运行，不走 MMU 翻译，在 FPGA 上完整输出。说明：
- AXI 路径（包括两级 CDC）数据传输正确
- M-mode 取指/执行完全正常
- bug 出在 S-mode + MMU 翻译启用后

---

## 十、下一步操作建议

1. **实现 circular buffer 方案**：在 `tb_kernel_boot.sv` 中添加环形缓冲区逻辑，trigger 条件为 cause=9 且 EPC≠c0010bbc，dump 前 2000 周期的关键信号到文本文件
2. **用 #4 配置重跑仿真**（128MB SRAM + 16MB DTB），保持 `add_wave /`，预计 ~3.8 小时到 trap
3. **分析 dump 文件**：重点关注 trap 前几个周期的 `mmu_inst_paddr`、`icache_refill_data`、`instData_32_mux` 信号，看是否有错误数据（如 0x00000073）出现在取指路径上
4. **根据分析结果修复 RTL**，然后重新仿真验证
5. **修复后再上 FPGA 验证**
