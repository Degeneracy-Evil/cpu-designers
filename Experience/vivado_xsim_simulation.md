# Vivado XSim 仿真经验总结

基于 `tb_bootloader`、`tb_simple_cpu_top` 等测试的实际调试过程，记录 Vivado xsim 行为级仿真的关键问题与解决方案。

---

## 1. xsim 工作目录与相对路径

### 问题

xsim 的工作目录为：

```
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/
```

而非仓库根目录。testbench 中 `$readmemh` 和 `$dumpfile` 使用的相对路径在 xsim 环境下无法解析。

### 解决方案

**方案 A：绝对路径**（推荐用于单机开发）

```verilog
$readmemh("E:/Xprogram/FPGA/cpu-designers/dev/program_source/cpu_test.hex", u_sram_model.mem32);
```

**方案 B：条件编译 + prog.hex 复制**（当前项目采用）

testbench 中用 `` `ifdef XILINX_SIMULATOR `` 区分 xsim 和 iverilog：

```verilog
initial begin
`ifdef XILINX_SIMULATOR
    $readmemh("prog.hex", u_sram_model.mem32);
`else
    $readmemh("dev/program_source/cpu_test.hex", u_sram_model.mem32);
`endif
end
```

`vivado_do.tcl` 的 `add_tb.tcl` 脚本自动将 hex 文件复制到 xsim 工作目录并重命名为 `prog.hex`。手动仿真时也需执行此复制步骤。

---

## 2. BRAM IP 核的内存层级路径

### 问题

使用真实 BRAM IP 核（Xilinx Block Memory Generator）时，testbench 通过 `$readmemh` 初始化内存需要访问 IP 内部的存储数组。直接使用 `u_bram.mem` 等路径会在 elaboration 阶段报错。

### BRAM 层级路径

| 层级 | 模块 | 实例名 |
|------|------|--------|
| 1 | IP 顶层 | `u_icache_wrap.u_data` / `u_dcache_wrap.u_tag` 等 |
| 2 | `blk_mem_gen_v8_4_2` | `inst` |
| 3 | generate 块 | `native_mem_module` |
| 4 | `blk_mem_gen_v8_4_2_mem_module` | `blk_mem_gen_v8_4_2_inst` |
| 5 | 内存数组 | `memory` |

### 示例

```verilog
// ROM BRAM (ahb_rom_slave 内)
u_bus.u_ahb_rom_slave.u_rom.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// I-Cache Data BRAM
dut.u_icache_wrap.u_data.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// D-Cache Tag BRAM
dut.u_dcache_wrap.u_tag.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory
```

### 关键发现：BRAM 行为模型读延迟

Vivado BRAM IP XCI 配置 `READ_LATENCY=1`，但**行为仿真模型提供组合输出**（数据在 ena+addra 同周期有效）。这意味着：

- 仿真中 BRAM 读是 0-cycle 延迟（组合逻辑）
- 实际硬件中 BRAM 读是 1-cycle 延迟（寄存输出）
- 仿真通过不代表硬件时序正确
- 综合时需关注此差异，可能需额外流水级

---

## 3. Verilog vs SystemVerilog 编译模式

### 问题

Vivado 2018.3 的 xvlog 默认以 Verilog 模式编译 `.v` 文件。`.sv` 文件自动以 SystemVerilog 模式编译。

### 受影响的 SV 特性

| SV 特性 | Verilog 模式错误 | 替代方案 |
|---------|------------------|----------|
| `string` 类型 | unknown type | 用 `reg` 数组或直接 `$write` |
| `$sformatf` | not allowed in this dialect | 用 `$write` / `$display` |
| `begin` 块内声明 | declarations not allowed | 移至模块级 |
| `logic` 类型 | syntax error | 用 `reg` / `wire` |

### 建议

所有 RTL 和 testbench 文件统一使用 `.sv` 扩展名，确保 xvlog 以 SV 模式编译。

---

## 4. 仿真运行时间配置

### 计算方法

```
仿真时间 ≥ (等待周期数 + 外设传输周期数) × 时钟周期
```

### 当前项目运行时间映射

```tcl
array set tb_runtime_map {
    tb_simple_cpu_top     "10ms"    ;# 120K cycles + CLINT timer (100K cycles)
    tb_simple_cpu_compute "10ms"
    tb_simple_cpu_trap    "5ms"
    tb_uart_hello         "10ms"
    tb_led_marquee        "2s"
    tb_bootloader         "30ms"    ;# UART 下载 + 程序执行
    tb_ahb_bus            "5000ns"
    tb_apb_perips         "2000ns"
}
```

### xsim TCL batch 文件

xsim 工作目录下的 `tb_name.tcl` 文件控制仿真运行时间：

```tcl
run 10ms
```

可通过 `vivado_do.tcl` 的 `-runtime` 参数覆盖：

```tcl
vivado_do -sim tb_simple_cpu_top -runtime 20ms
```

---

## 5. 手动批处理仿真流程

### 场景

修改 RTL/testbench 后需快速重新仿真，不想通过 Vivado GUI。

### 步骤

```bash
# 1. 进入 xsim 工作目录
cd project/simplecpu_bus/simplecpu_bus.sim/sim_1/behav/xsim/

# 2. 确保 prog.hex 已更新（$readmemh 需要）
copy /Y ..\..\..\..\..\..\dev\program_source\cpu_test.hex prog.hex

# 3. 重新编译（增量，仅编译修改的文件）
compile.bat

# 4. 重新例化（$readmemh 在此阶段执行）
elaborate.bat

# 5. 运行仿真
simulate.bat
```

### 注意事项

- **必须重新 elaborate**：`$readmemh` 在 elaboration 阶段执行，修改 hex 文件后仅 recompile 不够
- **compile.bat 是增量的**：xvlog `--incr` 选项仅重新编译修改的文件
- **simulate.bat 包含 run 命令**：仿真会自动运行到 `tb_name.tcl` 中指定的时间
- **输出在 stdout**：`$display` 输出直接打印到控制台，不写入独立日志文件

---

## 6. 调试层级路径（Hierarchical Signal Access）

### 问题

xsim 允许 testbench 通过层级路径（如 `dut.u_csr.r_mscratch`）访问 DUT 内部信号，但路径必须精确匹配 elaboration 后的实例层级。

### 当前项目关键层级路径

| 信号 | 层级路径 |
|------|----------|
| 寄存器文件 | `dut.u_regfile.rf[n]` |
| CSR mstatus | `dut.u_trap_csr.u_csr_if.u_csr.r_mstatus` |
| CSR mie | `dut.u_trap_csr.u_csr_if.u_csr.r_mie` |
| CSR mscratch | `dut.u_trap_csr.u_csr_if.u_csr.r_mscratch` |
| CLINT mtime | `u_bus.u_ahb_clint.r_mtime` |
| CLINT mtimecmp_lo | `u_bus.u_ahb_clint.r_mtimecmp_lo` |
| CLINT o_mtip | `u_bus.u_ahb_clint.o_mtip` (或顶层 `clint_mtip`) |
| I-Cache 状态 | `dut.u_icache_wrap.state` |
| I-Cache fill_buffer | `dut.u_icache_wrap.fill_buffer` |
| D-Cache 状态 | `dut.u_dcache_wrap.state` |
| trap_pending | `dut.u_trap_csr.u_trap_mgr.trap_pending` |
| SRAM 模型内存 | `u_sram_model.mem[n]` / `u_sram_model.mem32[n]` |

### 常见错误

```
ERROR: [VRFC 10-2991] 'u_trap_manager' is not declared under prefix 'dut'
```

**原因**：实例名与模块名不同。例如 `cpu_trap_csr` 模块内实例化 `cpu_trap_manager u_trap_mgr(...)`，应使用 `u_trap_mgr` 而非 `u_trap_manager`。

### 调试技巧

1. **先用 grep 确认实例名**：在 RTL 中搜索 `module_name u_instance_name` 确认层级
2. **逐层验证**：先尝试访问父模块信号，确认前缀正确，再深入子模块
3. **BRAM 内部信号**：需穿越 IP 层级（见第 2 节），且只能访问行为模型内的信号

---

## 7. RISC-V 中断调试经验

### CLINT vs APB Timer

| 特性 | CLINT (0x02000000) | APB Timer (0x10004000) |
|------|---------------------|------------------------|
| 触发中断 | MTIP (mip[7]) | PLIC src_irq[1] → MEIP (mip[11]) |
| 使能位 | MTIE (mie[7]) | MEIE (mie[11]) |
| 寄存器 | mtime (offset 0x8), mtimecmp (offset 0x0) | COUNT, COMPARE, CTRL |
| MTIP 条件 | mtime ≥ mtimecmp && mtimecmp ≠ 0 | COUNT ≥ COMPARE && CTRL[0] |
| 清除方式 | 写 mtimecmp 使其 > mtime | 写 CTRL[0]=0 |

### CLINT 寄存器映射

| 偏移 | 寄存器 | 读/写 |
|------|--------|-------|
| 0x0 | mtimecmp_lo | R/W |
| 0x4 | mtimecmp_hi | R/W |
| 0x8 | mtime_lo | R/W |
| 0xC | mtime_hi | R/W |

### 中断路径验证清单

1. **CLINT 输出**：`o_mtip` 在 mtime ≥ mtimecmp 时置位
2. **testbench 接线**：`core_top.timer_irq` 必须连接 `o_clint_mtip`（不是 `o_timer_irq`）
3. **CSR 状态**：mstatus[3]=MIE=1, mie[7]=MTIE=1
4. **trap_pending**：`clint_trap_enter && !exception_valid_r` 必须为 1
5. **控制器响应**：在 STATE_EXEC (branch) 或 STATE_WB 检测 trap_pending → STATE_TRAP_ENTER
6. **handler 执行**：mtvec 指向 handler 地址，handler 末尾 mret 返回

### 常见陷阱

- **mtime 递增频率**：当前实现每 cycle 递增 1（100MHz），RISC-V 规范通常要求更低的递增频率，但不影响功能正确性
- **mtimecmp_hi=0 陷阱**：若 mtime 已超过 32 位，设置 mtimecmp_hi=0 会导致 mtimecmp < mtime，MTIP 立即置位
- **MIE 清零**：trap entry 自动清零 MIE（mstatus[3]），handler 必须重新设置 mstatus 才能接收后续中断
- **addi 立即数范围**：`addi x11, x11, 100000` 会汇编报错（超出 12-bit 有符号范围 -2048~2047），应改用 `li x12, 100000; add x11, x11, x12`

---

## 8. Cache 调试经验

### I-Cache 行填充验证

关键检查点：
1. **fill 地址递增**：8 次读地址应为 base, base+4, base+8, ..., base+28
2. **fill_buffer 数据**：每个 32-bit 段应对应正确的指令字
3. **word_sel mux**：S_MISS_DONE 中 word_sel 0-7 必须分别选择 fill_buffer 的正确 32-bit 段

### D-Cache 写缺失路径

write-allocate 策略的正确流程：
1. S_MISS_REQ 发送 **READ**（不是 WRITE）
2. S_MISS_FILL 等待 mmio_valid，合并读回数据与写入数据
3. 合并后写入 cache 行
4. 走 write-through 路径将合并数据写入 SRAM

### MMIO 旁路

- `is_mmio = ~addr[31]`：bit31=0 为 MMIO（CLINT/PLIC/APB），bit31=1 为 cached（SRAM）
- MMIO 请求必须用 `!mmio_valid` 门控 `mmio_req`，防止重复事务
- D-Cache MMIO 路径：addr → bridge → AHB bus → 对应 slave

---

## 9. 仿真日志与输出

### 可用的日志文件

| 文件 | 位置 | 内容 |
|------|------|------|
| `compile.log` / `xvlog.log` | xsim dir | 编译详情与错误 |
| `elaborate.log` | xsim dir | 展开详情与错误 |
| `simulate.log` | xsim dir | BRAM 初始化信息、碰撞警告 |
| stdout | 控制台 | `$display` 输出（PASS/FAIL/调试信息） |

### 调试输出模式

```verilog
// 周期性采样（限制输出量）
integer debug_cnt;
initial begin
    debug_cnt = 0;
    @(negedge reset);
    forever begin
        @(posedge clk);
        #1;
        if (debug_cnt < 300) begin
            $display("TRACE [%0t] ...", $time, ...);
        end
        debug_cnt = debug_cnt + 1;
    end
end

// 条件触发（事件驱动）
always @(posedge clk) begin
    if (clint_mtip && !prev_mtip) begin
        $display("MTIP-ASSERTED [%0t] mtime=%0d mtimecmp=0x%08h", $time, ...);
    end
end
```

### $time 注意事项

xsim 的 `$time` 和 `%0t` 格式返回**最小 timescale 精度**单位的值。当 `timescale 1ns / 1ps` 时，`$time` 返回 ps 值。例如 10ns 时刻 `$time` 返回 10000。

---

## 10. vivado_do.tcl 使用流程

### 完整命令

```tcl
# 首次：创建工程并仿真
vivado_do -create -sim tb_simple_cpu_top

# 切换 testbench（复用工程）
vivado_do -sim tb_bootloader -runtime 30ms

# 完全重建
vivado_do -clear -create -sim tb_simple_cpu_top

# 仅生成 bitstream
vivado_do -bitstream
```

### COE/HEX 自动映射

脚本通过 `tb_coe_map` 和 `tb_hex_map` 数组自动配置：
- ROM COE 文件 → Vivado ROM IP 初始化
- SRAM hex 文件 → 复制到 xsim 工作目录为 `prog.hex`

---

## 11. 常见编译警告

| 警告 | 原因 | 处理 |
|------|------|------|
| VRFC 10-3380 | 标识符在声明前使用 | 纯语法警告，SV 允许，不影响仿真 |
| VRFC 10-3091 | 端口位宽不匹配 | 检查是否为有意截断（如 HBURST 3→4） |
| BRAM collision | 同一地址同时读写 | 行为模型不精确模拟碰撞，仿真可忽略 |

---

## 12. 项目目录与 .gitignore

Vivado 工程文件生成在 `project/` 子目录下，已在 `.gitignore` 中排除：

```gitignore
project/
waveform/
*.vcd
netlist/
```

每次重新运行 `vivado_do.tcl` 时，`-clear` 参数会删除已有工程。也可手动删除 `project/` 目录确保干净重建。
