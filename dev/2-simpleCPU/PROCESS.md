# PROCESS — dev/2-simpleCPU

## 2026-05-02 Vivado unpacked array port 兼容性修复

### 问题

Vivado xvlog 编译报错：

```
ERROR: [VRFC 10-3642] port 'slave_HRDATA' must not be declared to be an array [ahb_mux.v:9]
```

Vivado 的 Verilog 编译器不支持将 unpacked array 作为模块端口。
Iverilog 通过 `-g2005-sv` 支持，但 Vivado 不支持。

### 根因

`ahb_mux.v` 第 9 行声明了 unpacked array 端口：

```verilog
input wire [DATA_WIDTH-1:0] slave_HRDATA [0:SLAVE_NUM-1],
```

### 修复方案

将 unpacked array 端口展平为 packed vector，使用 `+:` 部分选择运算符索引。

#### 1. ahb_mux.v

| 项目 | 修改前 | 修改后 |
|------|--------|--------|
| 端口声明 | `[DATA_WIDTH-1:0] slave_HRDATA [0:SLAVE_NUM-1]` | `[DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA` |
| 内部访问 | `slave_HRDATA[i]` | `slave_HRDATA[i*DATA_WIDTH +: DATA_WIDTH]` |

#### 2. ahb_periph_bus.v

- 新增 `wire [DATA_WIDTH-1:0] sram_HRDATA;` 作为 SRAM slave HRDATA 输出中间线网
- `slave_HRDATA` 改为 packed vector：`wire [DATA_WIDTH*SLAVE_NUM-1:0] slave_HRDATA;`
- 拼接赋值：`assign slave_HRDATA = {bridge_HRDATA, sram_HRDATA};`
- SRAM slave 端口连接：`.HRDATA(sram_HRDATA)` 替代 `.HRDATA(slave_HRDATA[0])`
- 删除 `assign slave_HRDATA[1] = bridge_HRDATA;`

#### 3. ahb_bus.v (deprecated)

- `slave_HRDATA` 改为 packed vector
- 新增 generate 块创建中间线网 `gen_hrdata[g].hrdata` 并赋值到对应 slice
- SRAM slave / default slave 端口连接改为 `gen_hrdata[g].hrdata`

### 回归验证

全部 8 个 testbench 通过（iverilog + `--exclude Reference`）：

| Testbench | Pass | Fail |
|-----------|------|------|
| tb_simple_cpu_top | 33 | 0 |
| tb_ahb_bus | 3 | 0 |
| tb_apb_perips | 10 | 0 |
| tb_cpu_bus_adapter | 6 | 0 |
| tb_csr_test | 20 | 0 |
| tb_align_test | 23 | 0 |
| tb_timer_irq_test | 2 | 0 |
| tb_timer_seconds | 3 | 0 |

### 注意事项

- Vivado 仿真需确保 xvlog 使用 SystemVerilog 模式（`.sv` 后缀或 `-sv` 标志）以支持 `+:` 运算符；
  或直接使用 Verilog-2001 模式（`+:` 属于 Verilog-2001 标准部分选择，Vivado 默认支持）
- `+:` 部分选择运算符属于 Verilog-2001 标准，无需 SystemVerilog 扩展
