# 通过 tcl-tunnel 驱动 Vivado 仿真的实战指南

本文档总结在 WSL2 环境下，通过 tcl-tunnel HTTP 服务远程驱动 Windows 端 Vivado TCL 会话，完成 SimpleCPU + Bus4LZU IP 核行为级仿真的完整经验。

---

## 1. 环境拓扑

```
WSL2 (Ubuntu 24.04)                    Windows
┌──────────────────────┐              ┌─────────────────────────────┐
│  curl / opencode     │──HTTP──────▶│  tcl-tunnel (127.0.0.1:8000)│
│  /mnt/e/Xprogram/... │              │    │                        │
│  源码编辑、文件准备   │              │    ▼                        │
└──────────────────────┘              │  Vivado 2018.3 TCL shell   │
                                      │  E:/Xprogram/FPGA/tmp/...  │
                                      └─────────────────────────────┘
```

- tcl-tunnel 监听 `127.0.0.1:8000`，仅本机可访问
- WSL2 通过 `localhost` 访问 Windows 端服务（WSL2 自动转发）
- 文件通过 WSL2 挂载点 `/mnt/e/...` 与 Windows `E:\...` 共享

---

## 2. 路径映射规则

| WSL2 路径 | Windows 路径 | 说明 |
|---|---|---|
| `/mnt/e/Xprogram/FPGA/tmp/` | `E:/Xprogram/FPGA/tmp/` | 工作区根目录 |
| `/mnt/e/Xprogram/FPGA/tmp/rtl/*.v` | `E:/Xprogram/FPGA/tmp/rtl/*.v` | RTL 源文件 |
| `/mnt/e/Xprogram/FPGA/tmp/tb/*.v` | `E:/Xprogram/FPGA/tmp/tb/*.v` | testbench |

**关键规则：TCL 命令中必须使用 Windows 路径格式（`E:/...`），不能用 WSL2 的 `/mnt/e/...`。**

Vivado 在 Windows 端运行，只识别 Windows 路径。虽然 `/mnt/e/...` 和 `E:/...` 指向同一物理位置，但 Vivado TCL 解析路径时按 Windows 规则处理。

---

## 3. curl 调用模板

### 3.1 基本执行

```bash
SID="你的session_id"
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d '{"command":"puts [version]","timeout_seconds":30}'
```

### 3.2 多条命令串联

用 `;` 或 `&&` 连接多条 TCL 命令，减少 HTTP 往返：

```bash
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d '{"command":"add_files E:/path/to/file.v; update_compile_order -fileset sources_1; puts done","timeout_seconds":30}'
```

### 3.3 长耗时操作

IP 核生成、综合等操作需要增大 `timeout_seconds`：

```bash
# IP 核生成可能需要 2-3 分钟
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d '{"command":"create_ip ...; generate_target all ...","timeout_seconds":300}'
```

### 3.4 读取文件内容

通过 TCL 读文件并返回到 WSL2：

```bash
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d '{"command":"set fp [open E:/path/to/file r]; set data [read $fp]; close $fp; puts $data","timeout_seconds":10}'
```

---

## 4. 仿真项目搭建步骤

### Step 1: 创建 Vivado 工程

```bash
CMD='create_project simplecpu_ip_sim E:/Xprogram/FPGA/tmp/simplecpu_ip_sim -part xc7a100tfgg484-2 -force'
```

### Step 2: 添加 RTL 源文件

```bash
# 添加单个文件
CMD='add_files E:/Xprogram/FPGA/tmp/rtl/cpu_controller.v'

# 批量添加（用 TCL glob）
CMD='add_files [glob -directory E:/Xprogram/FPGA/tmp/rtl *.v]'

# 更新编译顺序
CMD='update_compile_order -fileset sources_1'
```

**注意：`add_files` 对已存在的文件会跳过并给出 WARNING，不影响功能。**

### Step 3: 添加 IP 核 Verilog 源文件和头文件

```bash
# IP 核的 Verilog 源文件
CMD='add_files [glob -directory E:/Xprogram/FPGA/tmp/ip/Asyncsys_bus_bus4LZU_1.0/sources_1/new *.v]'

# IP 核的子目录源文件
CMD='add_files [glob -directory E:/Xprogram/FPGA/tmp/ip/Asyncsys_bus_bus4LZU_1.0/sources_1/new/slot *.v]'
CMD='add_files [glob -directory E:/Xprogram/FPGA/tmp/ip/Asyncsys_bus_bus4LZU_1.0/sources_1/new/perips *.v]'

# 头文件（VH）必须用 include_dirs 而非 add_files
CMD='set_property include_dirs [list E:/Xprogram/FPGA/tmp/ip/Asyncsys_bus_bus4LZU_1.0/sources_1/new] [current_fileset]'
```

**关键：`.vh` 头文件不能通过 `add_files` 添加，必须通过 `include_dirs` 属性设置搜索路径。否则 Vivado 报 `file not found` 错误。**

### Step 4: 创建 BRAM IP 核（blk_mem_gen）

```bash
# 创建 IP 核
CMD='create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name Sram_icache -dir E:/Xprogram/FPGA/tmp/simplecpu_ip_sim/simplecpu_ip_sim.srcs/sources_1/ip/Sram_icache'

# 配置 IP 核参数（分号分隔多条 set_property）
CMD='set_property -dict [list \
  CONFIG.Memory_Type {Single_Port_RAM} \
  CONFIG.Read_Width_A {32} \
  CONFIG.Write_Width_A {32} \
  CONFIG.Write_Depth_A {8192} \
  CONFIG.Operating_Mode_A {READ_FIRST} \
  CONFIG.Use_Byte_Write_Enable {true} \
  CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
  CONFIG.Load_Init_File {true} \
  CONFIG.Coe_File {E:/Xprogram/FPGA/tmp/program/icache_init.coe} \
  CONFIG.Fill_Remaining_Memory_Locations {true} \
  CONFIG.Primitive {8kx2} \
] [get_ips Sram_icache]'

# 生成 IP 输出产物
CMD='generate_target all [get_ips Sram_icache]'
```

**COE 文件路径注意：**
- `create_ip` 时使用绝对路径
- Vivado 会在内部将 COE 路径转为相对路径（如 `../../../../../program/icache_init.coe`），这是正常行为
- 确保 COE 文件在执行 `generate_target` 之前已存在于指定路径

### Step 5: 添加 testbench

```bash
CMD='add_files -fileset sim_1 E:/Xprogram/FPGA/tmp/tb/tb_simplecpu_ip_sim.v'
CMD='set_property top tb_simplecpu_ip_sim [get_filesets sim_1]'
CMD='update_compile_order -fileset sim_1'
```

### Step 6: 启动仿真

```bash
CMD='launch_simulation -mode behavioral'
# timeout_seconds 建议设为 300（5分钟），因为编译+elaborate 需要时间
```

### Step 7: 继续运行仿真

`launch_simulation` 默认只运行 1000ns。如果 testbench 需要更长时间：

```bash
CMD='run 50000ns'
```

---

## 5. 常见问题与解决方案

### 5.1 Module not found

**现象：** `ERROR: [VRFC 10-2063] Module <xxx> not found while processing module instance <yyy>`

**原因：** 被实例化的模块源文件未添加到工程中。

**解决：** 找到对应 `.v` 文件，用 `add_files` 添加，然后 `update_compile_order -fileset sources_1`。

**排查方法：** 在 WSL2 端用 `grep` 搜索模块定义：
```bash
grep -rn "module alu_32bit" /home/wood/cpu-designers/
```

### 5.2 头文件找不到

**现象：** 编译报错找不到 `.vh` 文件。

**原因：** `.vh` 文件不能通过 `add_files` 添加到工程。

**解决：** 使用 `include_dirs` 设置搜索路径：
```bash
CMD='set_property include_dirs [list E:/path/to/header/dir] [current_fileset]'
```

### 5.3 IP 核 Primitive 参数被忽略

**现象：** `WARNING: [IP_Flow 19-365] ... parameter 'Primitive' is disabled ... value 'BRAM' ignored, default value '8kx2' will be used`

**影响：** 无。Vivado 会自动选择合适的 BRAM 原语。`8kx2` 是 blk_mem_gen 的默认原语选择策略，不影响功能。

### 5.4 COE 文件路径转换

**现象：** COE 文件路径从绝对路径变为相对路径。

**影响：** 无。Vivado 内部自动管理路径转换，只要 COE 文件在创建 IP 时存在于指定路径即可。

### 5.5 仿真结果中 load 数据错误

**现象：** `lw`/`lb`/`lh` 等加载指令返回的数据来自上一个操作的地址，而非当前地址。

**根本原因：** BRAM（blk_mem_gen）具有 **1 周期读延迟**（READ_LATENCY=1）。CPU 的 MEM 阶段在呈现地址后的下一个时钟沿就采样数据，但此时 BRAM 输出的仍是前一个地址的数据。

**诊断方法：**
1. 检查 BRAM XCI 配置中 `READ_LATENCY_A` 的值
2. 对比 `cpu_fetch.v`（已处理延迟）和 `cpu_mem.v`（未处理延迟）的实现差异
3. 分析失败寄存器的值是否为"前一次访问地址的数据"

**解决方案：** 在 `cpu_mem.v` 中增加 `MEM_READ2` 等待状态：

```verilog
// 修改前（2周期：IDLE→READ）
localparam MEM_IDLE  = 2'd0;
localparam MEM_READ  = 2'd1;
localparam MEM_WRITE = 2'd2;

MEM_READ: begin
    wb_data_reg <= load_value;  // 此时 BRAM 输出仍是旧地址数据！
    done_reg <= 1'b1;
    mem_state <= MEM_IDLE;
end

// 修改后（3周期：IDLE→READ→READ2）
localparam MEM_IDLE   = 2'd0;
localparam MEM_READ   = 2'd1;
localparam MEM_WRITE  = 2'd2;
localparam MEM_READ2  = 2'd3;

MEM_READ: begin
    mem_state <= MEM_READ2;     // 等待 BRAM 输出更新
end
MEM_READ2: begin
    wb_data_reg <= load_value;  // 此时 BRAM 输出已是正确数据
    done_reg <= 1'b1;
    mem_state <= MEM_IDLE;
end
```

**参照：** `cpu_fetch.v` 已用 `r_wait` 标志正确处理了 ICache BRAM 的 1 周期读延迟（取指需要 2 个周期：发地址 + 等待数据）。

### 5.6 init_sig 与 UART 加载协议

**现象：** Bus4LZU 的 `init_sig` 为高时，CPU 取到的指令全为 0（BRAM 被 UART 加载逻辑控制）。

**解决：** 在 testbench 中用 `force` 强制拉低 `init_sig`，跳过 UART 加载：

```verilog
repeat (20) @(posedge clk);  // 等待复位后稳定
force u_bus.init_sig = 1'b0; // 跳过 UART 加载，BRAM 已通过 COE 初始化
```

**前提：** ICache BRAM 已通过 COE 文件预加载指令数据，无需 UART 加载。

---

## 6. BRAM IP 核配置要点

### 6.1 ICache（指令缓存）

| 参数 | 值 | 说明 |
|---|---|---|
| Memory_Type | Single_Port_RAM | 单端口 |
| Read/Write_Width_A | 32 | 32位字宽 |
| Write_Depth_A | 8192 | 8K字 = 32KB |
| Use_Byte_Write_Enable | true | 4字节写使能 |
| Operating_Mode_A | READ_FIRST | 同时读写时先读 |
| Register_PortA_Output_of_Memory_Primitives | false | 不寄存输出（但 BRAM 原语本身有1周期延迟） |
| Load_Init_File | true | 加载 COE 初始化文件 |
| READ_LATENCY_A | 1 | **1周期读延迟** |

### 6.2 DCache（数据缓存）

与 ICache 配置相同，但：
- `Load_Init_File = false`（不加载 COE，初始为全0）
- `Coe_File = no_coe_file_loaded`

### 6.3 ICache 与 DCache 必须使用不同的 IP 实例

原始 Bus4LZU 设计中 ICache 和 DCache 使用同一个 `Sram` 模块。如果 ICache 配置了 COE 初始化，DCache 也会被初始化为同样的指令数据，导致数据区被错误预填充。

**解决方案：** 创建两个独立的 blk_mem_gen IP（`Sram_icache` 和 `Sram_dcache`），修改 `memory_slot.v` 分别实例化。

---

## 7. 分步 TCL 脚本模式

为便于调试和重跑，推荐将完整流程拆分为多个 TCL 脚本文件，每个脚本对应一个步骤：

```
step1_create_proj.tcl    — 创建工程
step2_add_rtl.tcl        — 添加 RTL 源文件
step3_add_ip_sources.tcl — 添加 IP 核 Verilog 源文件和头文件
step4_create_icache.tcl  — 创建 ICache BRAM IP
step5_create_dcache.tcl  — 创建 DCache BRAM IP
step6_add_testbench.tcl  — 添加 testbench
step7_launch_sim.tcl     — 启动仿真
```

通过 tcl-tunnel 执行脚本：

```bash
# 方法1：直接读取脚本内容并通过 execute API 发送
SCRIPT=$(cat /mnt/e/Xprogram/FPGA/tmp/step1_create_proj.tcl)
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d "{\"command\":\"$SCRIPT\",\"timeout_seconds\":60}"

# 方法2：在 TCL 中 source 脚本文件
curl -s -X POST "http://127.0.0.1:8000/sessions/$SID/execute" \
  -H "Content-Type: application/json" \
  -d '{"command":"source E:/Xprogram/FPGA/tmp/step1_create_proj.tcl","timeout_seconds":60}'
```

---

## 8. 仿真结果解读

### 8.1 成功输出

```
PASS reg x1 = 0x00000005
PASS reg x2 = 0x0000004d
...
PASS reg x31 = 0x000000ac
========================================
SimpleCPU IP-sim test summary
pass=31 fail=0
ALL TESTS PASSED
========================================
```

### 8.2 失败输出

```
FAIL reg x23 expected=0x0000000c got=0x00070005
FAIL reg x24 expected=0x00000005 got=0x0000000c
...
pass=28 fail=3
TEST FAILED
```

### 8.3 常见失败模式

| 模式 | 特征 | 原因 |
|---|---|---|
| 加载数据错位 | load 返回的是前一次访问地址的数据 | BRAM 1周期读延迟未处理 |
| 加载数据全零 | load 返回 0x00000000 | DCache 未正确写入，或 init_sig 未拉低 |
| 指令执行异常 | 大量寄存器值错误 | ICache COE 文件未正确加载，或指令编码错误 |

---

## 9. 完整工作流速查

```bash
# 0. 设置变量
SID="你的session_id"
BASE="E:/Xprogram/FPGA/tmp"

# 1. 创建工程
curl -s -X POST ".../execute" -d '{"command":"create_project sim $BASE/sim -part xc7a100tfgg484-2 -force"}'

# 2. 添加 RTL
curl -s -X POST ".../execute" -d '{"command":"add_files [glob -directory $BASE/rtl *.v]; update_compile_order -fileset sources_1"}'

# 3. 添加 IP 源文件 + 头文件路径
curl -s -X POST ".../execute" -d '{"command":"add_files [glob -directory $BASE/ip/.../new *.v]; add_files [glob -directory $BASE/ip/.../new/slot *.v]; add_files [glob -directory $BASE/ip/.../new/perips *.v]; set_property include_dirs [list $BASE/ip/.../sources_1/new] [current_fileset]"}'

# 4. 创建 BRAM IP（ICache + DCache）
curl -s -X POST ".../execute" -d '{"command":"create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name Sram_icache -dir ...; set_property -dict [list CONFIG.Memory_Type {Single_Port_RAM} ...] [get_ips Sram_icache]; generate_target all [get_ips Sram_icache]","timeout_seconds":300}'

# 5. 添加 testbench
curl -s -X POST ".../execute" -d '{"command":"add_files -fileset sim_1 $BASE/tb/tb.v; set_property top tb [get_filesets sim_1]; update_compile_order -fileset sim_1"}'

# 6. 启动仿真
curl -s -X POST ".../execute" -d '{"command":"launch_simulation -mode behavioral","timeout_seconds":300}'

# 7. 运行足够长时间
curl -s -X POST ".../execute" -d '{"command":"run 50000ns","timeout_seconds":120}'

# 8. 如需重跑（修改了 RTL 后）
curl -s -X POST ".../execute" -d '{"command":"reset_simulation; launch_simulation -mode behavioral","timeout_seconds":300}'
```

---

## 10. 经验总结

1. **文件准备在 WSL2，执行在 Windows**：在 WSL2 端编辑源码、准备 COE 文件，通过共享文件系统自动同步到 Windows。TCL 命令中始终使用 Windows 路径。

2. **先 add_files，后 generate_target**：IP 核的 Verilog wrapper 在 `generate_target` 后才存在。如果其他模块依赖 IP wrapper，必须先生成。

3. **BRAM 读延迟是硬伤**：blk_mem_gen 的 BRAM 模式天然具有 1 周期读延迟。CPU 设计时必须考虑这一点（fetch 阶段用 wait 标志，mem 阶段用额外状态）。

4. **ICache/DCache 分离**：当 ICache 需要 COE 初始化而 DCache 不需要时，必须使用两个独立的 blk_mem_gen IP 实例，不能共用同一个模块。

5. **force 信号跳过初始化**：Bus4LZU 的 UART 加载协议需要较长时间。当 BRAM 已通过 COE 预初始化时，用 `force init_sig = 0` 跳过加载是最简单的方案。

6. **超时设置要宽裕**：IP 核生成（300s）、仿真启动（300s）、仿真运行（120s）都需要足够的超时时间，避免 HTTP 504。

7. **增量编译**：`launch_simulation` 使用 `--incr` 增量编译。修改少量 RTL 后重跑仿真，只需 `reset_simulation; launch_simulation -mode behavioral`，未修改的文件不会重新编译。
