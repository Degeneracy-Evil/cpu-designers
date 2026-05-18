# Vivado XSim 仿真经验总结

基于 `tb_uart_hello` 测试的实际调试过程，记录 Vivado xsim 行为级仿真的关键问题与解决方案。

---

## 1. xsim 工作目录与相对路径

### 问题

xsim 的工作目录为：

```
<proj_dir>/<proj_name>.sim/sim_1/behav/xsim/
```

而非仓库根目录。testbench 中 `$readmemh` 和 `$dumpfile` 使用的相对路径（如 `dev/2-simpleCPU/program_source/uart_hello.hex`）在 xsim 环境下无法解析。

### 解决方案

将 testbench 中所有文件引用路径改为**绝对路径**：

```verilog
// 修改前
$readmemh("dev/2-simpleCPU/program_source/uart_hello.hex", ...);
$dumpfile("dev/2-simpleCPU/tb/waveform/uart_hello.vcd");

// 修改后
$readmemh("E:/Xprogram/FPGA/cpu-designers/dev/2-simpleCPU/program_source/uart_hello.hex", ...);
$dumpfile("E:/Xprogram/FPGA/cpu-designers/dev/2-simpleCPU/tb/waveform/uart_hello.vcd");
```

> **注意**: iverilog 可直接解析相对路径，仅 xsim 需要绝对路径。若需同时兼容两种仿真器，可使用 `` `ifdef `` 条件编译或 TCL 脚本在仿真前自动替换路径。

---

## 2. BRAM IP 核的内存层级路径

### 问题

使用真实 BRAM IP 核（Xilinx Block Memory Generator）时，testbench 通过 `$readmemh` 初始化内存需要访问 IP 内部的存储数组。直接使用 `u_bram.mem` 等路径会在 elaboration 阶段报错：

```
ERROR: [VRFC 10-2991] 'mem' is not declared under prefix 'u_bram'
```

### 原因

Xilinx BRAM IP 的仿真模型（`blk_mem_gen_v8_4.v`）中，内存数组的完整层级为：

| 层级 | 模块 | 实例名 |
|------|------|--------|
| 1 | IP 顶层 (icache/dcache/Sram) | `u_icache` / `u_dcache` / `u_bram` |
| 2 | `blk_mem_gen_v8_4_2` | `inst` |
| 3 | generate 块 | `native_mem_module` |
| 4 | `blk_mem_gen_v8_4_2_mem_module` | `blk_mem_gen_v8_4_2_inst` |
| 5 | 内存数组 | `memory` |

存储数组声明为 `reg [MIN_WIDTH-1:0] memory [0:MAX_DEPTH-1]`，名称是 `memory` 而非 `mem`。

### 解决方案

使用完整层级路径访问 BRAM 内存：

```verilog
// SRAM (ahb_sram_slave 中的 BRAM)
u_bus.u_ahb_sram_slave.u_bram.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// ICache
dut.u_icache_wrap.u_icache.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory

// DCache
dut.u_dcache_wrap.u_dcache.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory
```

`$readmemh` 示例：

```verilog
initial begin
    $readmemh("E:/Xprogram/FPGA/cpu-designers/dev/2-simpleCPU/program_source/uart_hello.hex",
              u_bus.u_ahb_sram_slave.u_bram.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory);
    $readmemh("E:/Xprogram/FPGA/cpu-designers/dev/2-simpleCPU/program_source/uart_hello.hex",
              dut.u_icache_wrap.u_icache.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory);
    $readmemh("E:/Xprogram/FPGA/cpu-designers/dev/2-simpleCPU/program_source/uart_hello.hex",
              dut.u_dcache_wrap.u_dcache.inst.native_mem_module.blk_mem_gen_v8_4_2_inst.memory);
end
```

> **generate 块选择依据**: 当 `C_INTERFACE_TYPE=0` 且 `C_ENABLE_32BIT_ADDRESS=0` 时，激活 `native_mem_module` generate 块。若使用 32-bit 地址模式或 AXI 接口，generate 块名称会不同。

---

## 3. Verilog vs SystemVerilog 编译模式

### 问题

Vivado 2018.3 的 xvlog 默认以 Verilog 模式编译。testbench 中使用的 SystemVerilog 特性会导致编译失败：

```
ERROR: [VRFC 10-552] declarations not allowed in unnamed block
ERROR: [VRFC 10-2939] 'string' is an unknown type
ERROR: [VRFC 10-3734] system call 'sformatf' not allowed in this dialect. Use SystemVerilog mode
```

### 受影响的 SV 特性

| SV 特性 | 错误 | 替代方案 |
|---------|------|----------|
| `string` 类型 | unknown type | 用 `reg` 数组或直接 `$write` 输出 |
| `$sformatf` | not allowed in this dialect | 用 `$write` / `$display` 逐字符输出 |
| `begin` 块内声明 | declarations not allowed | 将声明移至模块级 |

### 解决方案

将 SV 语法替换为纯 Verilog 等价写法：

```verilog
// 修改前 (SystemVerilog)
begin
    string s;
    s = "";
    for (i = 0; i < count; i = i + 1) begin
        $write("%c", msg[i]);
        s = {s, $sformatf("%c", msg[i])};
    end
    $display("");
end

// 修改后 (Verilog)
for (i = 0; i < count; i = i + 1) begin
    $write("%c", msg[i]);
end
$display("");
```

> **替代方案**: 也可在 Vivado 项目中设置 `set_property simulator_language SystemVerilog`，或将 testbench 文件扩展名改为 `.sv`，使 xvlog 自动以 SV 模式编译。但需确保所有源文件兼容 SV 模式。

---

## 4. 仿真运行时间配置

### 问题

testbench 中 `repeat (3000000) @(posedge clk)` 等待 3M 个时钟周期。在 100MHz 时钟下（周期 10ns），实际需要约 30ms 仿真时间。若 `xsim.simulate.runtime` 设置过短，仿真会在 testbench 完成前终止，导致无法看到测试结果。

### 计算方法

```
仿真时间 ≥ (等待周期数 + UART传输周期数) × 时钟周期
         = (3,000,000 + ~95,000) × 10ns
         ≈ 31,000,000 ns
         = 31ms
```

其中 UART 传输周期数 = 字符数 × 每字符bit数 × 每bit时钟周期数
= 11 × 10 × (100M / 115200) ≈ 95,480

### 建议

在 `vivado_do.tcl` 的 `tb_runtime_map` 中，为每个 testbench 预留充足余量：

```tcl
array set tb_runtime_map {
    tb_simple_cpu_top  "500000ns"
    tb_uart_hello      "35000000ns"    ;# 3M cycles + UART TX + margin
    tb_led_marquee     "1000000000ns"
    tb_ahb_bus         "5000ns"
    tb_apb_perips      "2000ns"
    tb_cpu_bus_adapter "5000ns"
}
```

---

## 5. vivado_do.tcl 使用流程

### 完整命令

```bash
# 清除旧工程（如需）
rm -rf project/

# 启动 Vivado TCL 并执行脚本
vivado.bat -mode tcl -source vivado_do.tcl -notrace
```

### 切换 testbench

修改 `vivado_do.tcl` 中的 `tb_name` 变量：

```tcl
set tb_name "tb_uart_hello"    ;# 可选: tb_simple_cpu_top, tb_uart_hello, tb_led_marquee, tb_ahb_bus, tb_apb_perips, tb_cpu_bus_adapter
```

### COE 文件自动映射

脚本通过 `tb_coe_map` 数组自动为 ICache BRAM IP 配置对应的 COE 初始化文件，无需手动干预。

---

## 6. 仿真日志读取

### 问题

`vivado_do.tcl` Step 8 尝试读取 `xsim.log`，但该文件在 Vivado 2018.3 中不存在。testbench 的 `$display` 输出实际出现在 Vivado 控制台 stdout 中，而非写入独立日志文件。

### 可用的日志文件

| 文件 | 内容 |
|------|------|
| `simulate.log` | BRAM 初始化信息、碰撞警告 |
| `compile.log` / `xvlog.log` | 编译详情与错误 |
| `elaborate.log` | 展开详情与错误 |
| `xsimkernel.log` | 仿真完成状态、CPU/内存使用 |

### 建议

如需捕获 `$display` 输出到文件，可在 testbench 中使用 `$fopen` / `$fwrite` / `$fclose` 显式写入日志文件，或通过 Vivado TCL 的 `redirect` 命令捕获控制台输出。

---

## 7. 项目目录与 .gitignore

Vivado 工程文件生成在 `project/` 子目录下，已在 `.gitignore` 中排除：

```gitignore
project/
waveform/
*.vcd
netlist/
```

每次重新运行 `vivado_do.tcl` 时，`create_project -force` 会覆盖已有工程。也可手动删除 `project/` 目录确保干净重建。
