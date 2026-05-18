---
name: vivado-xsim-simulation
description: |
  Vivado XSim behavioral simulation guide for the embedded CPU project.
  Use this skill when running, debugging, or troubleshooting Vivado simulations,
  configuring testbenches, working with BRAM IP cores, or handling $readmemh paths.
---

# Vivado XSim 仿真指南

## 1. xsim 工作目录与路径

xsim 工作目录为 `<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/`，非仓库根目录。

### $readmemh 路径处理

使用条件编译区分 xsim 和 iverilog：

```verilog
initial begin
`ifdef XILINX_SIMULATOR
    $readmemh("prog.hex", u_sram_model.mem32);
`else
    $readmemh("dev/program_source/cpu_test.hex", u_sram_model.mem32);
`endif
end
```

`vivado_do.tcl` 的 `add_tb.tcl` 自动将 hex 复制到 xsim 工作目录并重命名为 `prog.hex`。

## 2. BRAM IP 核内存层级路径

使用 `$readmemh` 初始化 BRAM IP 需访问内部存储数组，层级路径：

| 层级 | 模块 | 实例名 |
|------|------|--------|
| 1 | IP 顶层 | `u_icache_wrap.u_data` / `u_dcache_wrap.u_tag` |
| 2 | `blk_mem_gen_v8_4_2` | `inst` |
| 3 | generate 块 | `native_mem_module` |
| 4 | `blk_mem_gen_v8_4_2_mem_module` | `blk_mem_gen_v8_4_2_inst` |
| 5 | 内存数组 | `memory` |

### 示例路径

```verilog
// ROM BRAM
u_bus.u_ahb_rom_slave.u_rom.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// I-Cache Data BRAM
dut.u_icache_wrap.u_data.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// D-Cache Tag BRAM
dut.u_dcache_wrap.u_tag.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory
```

### BRAM 读延迟差异

- **仿真**：BRAM 行为模型提供组合输出（0-cycle 延迟）
- **硬件**：`READ_LATENCY=1`，寄存输出（1-cycle 延迟）
- 仿真通过不代表硬件时序正确，综合时需关注

## 3. Verilog vs SystemVerilog

Vivado 2018.3 的 xvlog 默认以 Verilog 模式编译 `.v` 文件，`.sv` 自动以 SV 模式编译。

| SV 特性 | Verilog 模式错误 | 替代方案 |
|---------|------------------|----------|
| `string` 类型 | unknown type | 用 `reg` 数组或直接 `$write` |
| `$sformatf` | not allowed in this dialect | 用 `$write` / `$display` |
| `begin` 块内声明 | declarations not allowed | 移至模块级 |
| `logic` 类型 | syntax error | 用 `reg` / `wire` |

**建议**：所有 RTL 和 testbench 统一使用 `.sv` 扩展名。

## 4. 仿真运行时间

### 运行时间映射

```tcl
array set tb_runtime_map {
    tb_simple_cpu_top     "10ms"
    tb_simple_cpu_compute "10ms"
    tb_simple_cpu_trap    "5ms"
    tb_uart_hello         "10ms"
    tb_led_marquee        "2s"
    tb_bootloader         "30ms"
    tb_ahb_bus            "5000ns"
    tb_apb_perips         "2000ns"
}
```

### 覆盖运行时间

```tcl
vivado_do -sim tb_simple_cpu_top -runtime 20ms
```

## 5. 手动批处理仿真流程

```bash
# 1. 进入 xsim 工作目录
cd project/simplecpu_bus/simplecpu_bus.sim/sim_1/behav/xsim/

# 2. 更新 prog.hex
copy /Y ..\..\..\..\..\..\dev\program_source\cpu_test.hex prog.hex

# 3. 重新编译（增量）
compile.bat

# 4. 重新例化（$readmemh 在此阶段执行）
elaborate.bat

# 5. 运行仿真
simulate.bat
```

**注意**：修改 hex 后必须重新 elaborate，`$readmemh` 在 elaboration 阶段执行。

## 6. 调试层级路径

### 关键信号路径

| 信号 | 层级路径 |
|------|----------|
| 寄存器文件 | `dut.u_regfile.rf[n]` |
| CSR mstatus | `dut.u_trap_csr.u_csr_if.u_csr.r_mstatus` |
| CSR mie | `dut.u_trap_csr.u_csr_if.u_csr.r_mie` |
| CSR mscratch | `dut.u_trap_csr.u_csr_if.u_csr.r_mscratch` |
| CLINT mtime | `u_bus.u_ahb_clint.r_mtime` |
| CLINT mtimecmp_lo | `u_bus.u_ahb_clint.r_mtimecmp_lo` |
| CLINT o_mtip | `u_bus.u_ahb_clint.o_mtip` |
| I-Cache 状态 | `dut.u_icache_wrap.state` |
| I-Cache fill_buffer | `dut.u_icache_wrap.fill_buffer` |
| D-Cache 状态 | `dut.u_dcache_wrap.state` |
| trap_pending | `dut.u_trap_csr.u_trap_mgr.trap_pending` |
| SRAM 模型内存 | `u_sram_model.mem[n]` / `u_sram_model.mem32[n]` |

### 调试技巧

1. 先用 grep 确认实例名（`module_name u_instance_name`）
2. 逐层验证：先访问父模块信号，再深入子模块
3. BRAM 内部信号需穿越 IP 层级

## 7. RISC-V 中断调试

### CLINT vs APB Timer

| 特性 | CLINT (0x02000000) | APB Timer (0x10004000) |
|------|---------------------|------------------------|
| 触发中断 | MTIP (mip[7]) | PLIC src_irq[1] → MEIP (mip[11]) |
| 使能位 | MTIE (mie[7]) | MEIE (mie[11]) |
| 寄存器 | mtime (0x8), mtimecmp (0x0) | COUNT, COMPARE, CTRL |
| 清除方式 | 写 mtimecmp > mtime | 写 CTRL[0]=0 |

### CLINT 寄存器映射

| 偏移 | 寄存器 | 读/写 |
|------|--------|-------|
| 0x0 | mtimecmp_lo | R/W |
| 0x4 | mtimecmp_hi | R/W |
| 0x8 | mtime_lo | R/W |
| 0xC | mtime_hi | R/W |

### 中断路径验证清单

1. CLINT 输出：`o_mtip` 在 mtime ≥ mtimecmp 时置位
2. testbench 接线：`core_top.timer_irq` 连接 `o_clint_mtip`
3. CSR 状态：mstatus[3]=MIE=1, mie[7]=MTIE=1
4. trap_pending：`clint_trap_enter && !exception_valid_r` 为 1
5. 控制器响应：STATE_EXEC 或 STATE_WB 检测 trap_pending → STATE_TRAP_ENTER
6. handler 执行：mtvec 指向 handler，末尾 mret 返回

### 常见陷阱

- mtime 每 cycle 递增 1（100MHz），不影响功能正确性
- mtimecmp_hi=0 时若 mtime 已超 32 位，MTIP 立即置位
- trap entry 自动清零 MIE，handler 需重新设置 mstatus
- `addi` 立即数范围 -2048~2047，大数用 `li` + `add`

## 8. Cache 调试

### I-Cache 行填充

1. fill 地址递增：base, base+4, ..., base+28
2. fill_buffer 数据对应正确指令字
3. word_sel 0-7 分别选择 fill_buffer 正确 32-bit 段

### D-Cache 写缺失（write-allocate）

1. S_MISS_REQ 发送 **READ**（非 WRITE）
2. S_MISS_FILL 等待 mmio_valid，合并读回与写入数据
3. 合并后写入 cache 行
4. write-through 路径写入 SRAM

### MMIO 旁路

- `is_mmio = ~addr[31]`：bit31=0 为 MMIO，bit31=1 为 cached
- MMIO 请求用 `!mmio_valid` 门控 `mmio_req`

## 9. 仿真日志

| 文件 | 内容 |
|------|------|
| `compile.log` / `xvlog.log` | 编译详情与错误 |
| `elaborate.log` | 展开详情与错误 |
| `simulate.log` | BRAM 初始化、碰撞警告 |
| stdout | `$display` 输出（PASS/FAIL/调试） |

### $time 注意事项

`timescale 1ns / 1ps` 时，`$time` 返回 ps 值。10ns 时刻 `$time` 返回 10000。

## 10. vivado_do.tcl 使用

```tcl
# 首次：创建工程并仿真
vivado_do -create -sim tb_simple_cpu_top

# 切换 testbench
vivado_do -sim tb_bootloader -runtime 30ms

# 完全重建
vivado_do -clear -create -sim tb_simple_cpu_top

# 仅生成 bitstream
vivado_do -bitstream
```

## 11. 常见编译警告

| 警告 | 原因 | 处理 |
|------|------|------|
| VRFC 10-3380 | 标识符在声明前使用 | SV 允许，不影响仿真 |
| VRFC 10-3091 | 端口位宽不匹配 | 检查是否为有意截断 |
| BRAM collision | 同一地址同时读写 | 行为模型不精确，可忽略 |

## 12. 项目目录

Vivado 工程在 `project/` 子目录，已在 `.gitignore` 中排除：

```gitignore
project/
waveform/
*.vcd
netlist/
```

`vivado_do.tcl` 的 `-clear` 参数删除已有工程，也可手动删除 `project/` 确保干净重建。
