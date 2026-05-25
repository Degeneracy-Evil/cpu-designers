# 项目修改记录

## 2026-05-14

### 修复：地址空间映射改变导致的测试程序执行异常

**问题描述**：
由于全局地址映射重构（DRAM 基址从 `0x00000000` 变更为 `0x80000000`，PC 复位向量相应修改），`dev/program_source/cpu_test.s` 和 `cpu_test_compute.s` 中的绝对地址跳转指令失效。原代码使用 `addi x5, x0, 0xC8` 配合 `jalr x4, x5, 0`，导致程序中途错误地跳转到 `0x000000C8`。
虽然测试平台中 AHB SRAM 也被相同固件初始化，CPU 能继续执行并“通过”测试，但实际上后半段程序完全绕过了 ICache，直接在 AHB SRAM（MMIO 空间）中执行，失去了对 Cache 的测试意义。同时，trap 处理程序保存的 `mepc` 也变成了 `0x0000021C` 而非 `0x8000021C`。

**修复方案**：

1. **测试程序修正**：将 `cpu_test.s` 和 `cpu_test_compute.s` 中的 `addi x5, x0, 0xC8` 替换为 `addi x5, x22, 116`。因为 `x22` 在之前通过 `auipc x22, 0` 被正确赋予了基于当前 PC 的值（`0x80000054`），加上偏移 116 后正好等于目标地址 `0x800000C8`。这样可以在保持指令长度（1条）不变的前提下实现动态正确寻址。
2. **测试平台期望值更新**：由于程序全程在 `0x80000000` 空间执行，触发 exception 时的 `mepc` 随之改变。将 `tb_simple_cpu_top.v` 和 `tb_simple_cpu_compute.v` 中对 `x20` 寄存器的期望值从 `0x00000220` 修正为 `0x80000220`。同样地，将 `tb_simple_cpu_trap.v` 中的期望值修正为 `0x8000003C`。
3. **编译并验证**：重新生成 Hex 并在三个 testbench 中运行验证，所有测试均已正确 PASS。

## 2026-05-25

### 新增：配置驱动的 IP 生成与 Cache 参数化

**目标**：在 Vivado Orchestrator 体系中添加依据 `vivado_config.yaml` 动态生成 BRAM IP（`create_ip` TCL）和 RTL 常量头文件（`cache_def.svh`）的功能，实现修改 YAML 即可灵活调整内存/Cache 大小，IP 与 RTL 始终同步。

**新增/修改文件**：

1. **`vivado_config.yaml`** — 新增 `memory` 配置段（sram、icache、dcache、use_tag_bram）
2. **`tools/vivado_core/config.py`** — 新增 `SramConfig`、`CacheConfig`、`MemoryConfig` 数据类；`GlobalConfig` 增加 `memory` 字段；`load_config()` 解析 memory 段
3. **`tools/vivado_core/ip_gen.py`** — 新增 `BramConfig` 数据类、推导辅助函数（`sram_to_bram`、`cache_data_to_bram`、`cache_tag_to_bram`）、`generate_bram_create_ip_tcl()` 和 `generate_all_ip_tcl()` 动态生成 `create_ip` TCL
4. **`tools/vivado_core/cache_header_gen.py`** — 新增 `_derive_addr_slices()`、`_derive_sram_defines()`、`generate_cache_header()`、`write_cache_header()` 生成 `cache_def.svh`
5. **`tools/vivado_core/operations.py`** — `_tcl_setup_ip()` 从静态 XCI 导入改为动态 `create_ip`；新增 `_regenerate_cache_header()` 和 `gen_config()` 方法；`_tcl_create_project()` 中添加 `cache_def.svh` 导入
6. **`tools/vivado_cli.py`** — 新增 `--gen-config` CLI 选项，调用 `Operations.gen_config()` 重新生成 `cache_def.svh`
7. **`dev/rtl/core/cache_def.svh`** — 自动生成的 Cache/Memory 几何常量头文件（`` `define`` 宏）
8. **`dev/rtl/core/icache_ctrl.sv`** — 重构为 `include "cache_def.svh"`，所有 localparam 从 define 派生，地址位切片、tag entry 宽度、BRAM 端口宽度、地址构造全部参数化
9. **`dev/rtl/core/dcache_ctrl.sv`** — 同上参数化，dirty bit 使用 `TAG_ENTRY_W-2`，flush 迭代使用 `NUM_WAYS/NUM_SETS` 比较
10. **`tools/tcl/setup_ip.tcl`** — 添加注释说明已被动态 `create_ip` 取代（保留为 `vivado_do.tcl` 直接使用的回退）
11. **`tools/tcl/create_proj.tcl`** — 添加 `$cpu_core_dir/*.svh` 导入（含 `cache_def.svh`），设置 `file_type "Verilog Header"`

**关键设计决策**：

- 使用 `create_ip` TCL 命令替代静态 XCI 文件导入 — 支持从配置动态调整 IP 大小
- 使用 `` `define`` 宏（而非 SV package）— 与现有 `include 模式兼容
- Tag entry 布局：icache = valid(1) + tag(TAG_WIDTH)；dcache = valid(1) + dirty(1) + tag(TAG_WIDTH)
- 地址构造使用 `ADDR_UPPER_ZEROS` / `ADDR_LOWER_ZEROS` 复制运算符

**使用方法**：

```bash
# 编辑 vivado_config.yaml 中的 memory 段后，重新生成：
python -m tools.vivado_cli --gen-config

# 或在 Python 代码中：
from tools.vivado_core.operations import Operations
ops.gen_config()  # 返回生成的 cache_def.svh 路径
```

**验证**：

- Python 导入链全部通过（config、ip_gen、cache_header_gen、operations）
- 推导值与原始 XCI 一致：Sram=32×8192 addr=13, icached=256×32 addr=5 wea=32, dcached=256×32 addr=5 wea=32
- 端到端测试：修改 YAML num_sets 8→16 → `--gen-config` → cache_def.svh 正确更新 → 还原 → 恢复原始值

### 修复：动态 create_ip 生成与 RTL 回归

**问题描述**：
使用 `python -m tools.vivado_cli -task cpu_full -create -sim` 运行仿真时，IP 未正确生成，仿真结果全量 FAIL（25/42 寄存器值不匹配）。

**根因分析与修复（共 6 个 bug）**：

1. **`set_property -dict` 嵌套列表格式**（`ip_gen.py:166`）
   - 原代码：`prop_dict = " ".join(f"[list {p}]" for p in props)` → 生成 `[list [list K V] [list K V] ...]`
   - Vivado 期望扁平格式：`[list K V K V ...]`
   - 修复：`prop_dict = " \\\n    ".join(props)`

2. **`create_ip -dir` 目录不存在**（`ip_gen.py:170`）
   - Vivado 要求 `-dir` 路径在调用前已存在
   - 修复：在每个 `create_ip` 前添加 `file mkdir`

3. **缺少关键 BRAM 属性**（`ip_gen.py:143-158`）
   - 原始 XCI 包含 `Operating_Mode_A/B=WRITE_FIRST`、`Interface_Type=Native`、`PRIM_type_to_Implement=BRAM`，动态生成未设置
   - 修复：在 props 列表中添加这三个属性，与 XCI 完全对齐

4. **Sram `generate_target` 被调用两次**（`ip_gen.py` + `operations.py`）
   - `generate_all_ip_tcl()` 对所有 IP 调用 `generate_target`，然后 COE 配置块又对 Sram 调用一次
   - 第一次生成时 Sram 未加载 COE，可能导致初始化不一致
   - 修复：将 `generate_bram_create_ip_tcl()` 拆分为 create-only + `_tcl_generate_target()`；`_tcl_setup_ip()` 中先对 icached/dcached 生成 target，Sram 在 COE 配置后才生成 target

5. **`VivadoConfig` 缺少 `memory` 字段**（`vivado_cli.py:136`）
   - CLI 的 `load_config()` 返回 `VivadoConfig`（无 memory），而 `Operations` 访问 `config.memory` 导致 `AttributeError`
   - 修复：`load_config()` 在 core 可用时委托给 `vivado_core.config.load_config()` 返回 `GlobalConfig`

6. **dcache_ctrl.sv flush 终止条件永远为假**（`dcache_ctrl.sv:351,352,380,381`）— **关键 RTL bug**
   - 原代码：`flush_way == NUM_WAYS[WAY_W-1:0] - 1`
   - 当 NUM_WAYS=4, WAY_W=2 时：`4[1:0]` = `2'b00` = 0，`0-1` = `32'hFFFFFFFF`
   - `flush_way`（2位无符号，最大值3）永远不等于 `32'hFFFFFFFF` → flush 永不终止 → CPU 在 `fence.i` 指令上挂死
   - 同理 `NUM_SETS[SET_IDX_W-1:0]`：`8[2:0]` = 0 → 同样永远为假
   - 修复：`NUM_WAYS[WAY_W-1:0] - 1` → `NUM_WAYS - 1`，`NUM_SETS[SET_IDX_W-1:0] - 1` → `NUM_SETS - 1`
   - **根因**：对 2 的幂次 N 做位截断 `N[log2(N)-1:0]` 会丢失唯一的 set bit，结果恒为 0
