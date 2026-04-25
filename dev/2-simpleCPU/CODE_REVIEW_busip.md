# simpleCPU busip 分支代码审查报告

> 审查日期：2026-04-25
> 审查分支：busip
> 审查范围：dev/2-simpleCPU/rtl/ 及 testbench
> 审查人：AI Agent

---

## 一、变更总览

本次 `busip` 分支将 `simpleCPU` 从**内部 BRAM 直连模型**迁移为 **Bus4LZU 总线接口模型**，核心改动如下：

| 模块 | 变更内容 |
|------|----------|
| `cpu_fetch.v` | 引入 `clk`/`reset`/`init_sig`，改为 **1 周期延迟取指**（`r_wait` 翻转状态机），输出 `instAddr_32`（字节地址） |
| `cpu_mem.v` | 移除 read-modify-write（3 周期 store），改为 **字节掩码直接写入**（`dataWen_4[3:0]`），load 也改为 1 周期等待（2 状态） |
| `cpu_controller.v` | 增加 `init_sig` 门控：高电平时强制 `next_state = STATE_IDLE`，所有 `*_valid` 附加 `&& !init_sig` |
| `simple_cpu_top.v` | 移除 `icache`/`dcache`/`uart_top` 实例；新增总线端口；`ext_meip` 改为 `timer_irq` |
| `bus4lzu_mock.v` | **新增**：简化 BRAM 代理（`imem`/`dmem`），`init_sig` 上电 100 周期冻结，Timer 外设模拟（地址 `0x1001_0000`） |
| `tb_*.v` | 实例化 `bus4lzu_mock`，延长仿真等待周期（`1500` -> `2500`） |

---

## 二、仿真验证结果

| 测试项 | 结果 | 说明 |
|--------|------|------|
| 基础指令测试（33 项寄存器/存储器检查） | **33/33 PASS** | 包含算术、逻辑、分支、访存 |
| CSR 指令测试（20 项） | **20/20 PASS** | 包含 CSRRW/S/C/WI/SI/CI 及异常 |
| 异常处理测试（ECALL/EBREAK/非法指令/未对齐） | **全部 PASS** | CSR test 中隐含验证 |

**结论：当前所有已有回归测试均通过。**

---

## 三、逐文件详细审查

### 3.1 `cpu_fetch.v` — 1 周期延迟取指

**状态：正确**

```verilog
always @(posedge clk) begin
    if (reset) r_wait <= 0;
    else if (init_sig) r_wait <= 0;      // 冻结：强制清0
    else if (if_valid) r_wait <= ~r_wait; // 每周期翻转
    else r_wait <= 0;                    // 离开FETCH时重置
end
assign if_done = if_valid && r_wait;      // 第2周期才done
```

**逻辑验证：**
- `init_sig=1` 时 `r_wait` 被锁在 0，`if_done` 永不为 1，controller 无法离开 FETCH -> **冻结正确**
- `init_sig` 释放后，IDLE->FETCH 第 1 周期 `r_wait=0, if_done=0`；第 2 周期 `r_wait=1, if_done=1` -> **2 周期取指正确**
- controller 离开 FETCH 后 `if_valid=0`，`r_wait` 清 0，下一条指令重新 2 周期取指 -> **无残留状态**

---

### 3.2 `cpu_mem.v` — 字节掩码访存

**状态：功能正确，无冗余代码**

**store 时序验证（2 周期）：**
- 周期 N（MEM_IDLE posedge）：设置 `dataAddr_32`/`dataWen_4`/`writeData_32`，`mem_en_reg=1`，进入 MEM_WRITE
- 组合逻辑：`mem_en=1` -> `data_req=1`，mock 尚未采样
- 周期 N+1（MEM_WRITE posedge）：mock 采样 `data_req=1` 并写入 dmem；同时 `done_reg=1`
- 组合逻辑：`mem_done=1`，controller 进入 WB

**load 时序验证（2 周期）：**
- 周期 N（MEM_IDLE）：发地址，`dataWen_4=1111`（读），`mem_en=1`，进入 MEM_READ
- 组合逻辑：mock 更新 `readData_32`
- 周期 N+1（MEM_READ）：`wb_data_reg <= load_value`（使用 `readData_32`），`done_reg=1`

**字节掩码逻辑：**
- `sb`：offset 0/1/2/3 分别对应 `1110/1101/1011/0111`，覆盖所有对齐情况
- `sh`：offset 0 对应 `1100`，offset 2 对应 `0011`；offset 1/3 由 `misalign_store` 检测捕获为异常
- `sw`：统一为 `0000`；offset 非 0 由 `misalign_store` 检测捕获为异常

**结论：** 掩码生成逻辑正确，无冗余死代码。未对齐访问已由 `misalign_store` 检测提前拦截。

---

### 3.3 `cpu_controller.v` — init_sig 门控

**状态：正确**

所有状态转移被 `init_sig` 截断到 IDLE，所有 `*_valid` 被 `!init_sig` 屏蔽。这是安全的暂停策略，不丢失任何寄存器状态。

---

### 3.4 `simple_cpu_top.v` — 顶层重构

**状态：结构清晰**

- 总线端口与内部信号连接正确
- `data_req = mem_en` 赋值正确
- `hw_csr_wen = trap_enter_valid || trap_return_valid` 保持正确
- 移除了不再使用的 `icache`/`dcache`/`uart_top`

---

### 3.5 `bus4lzu_mock.v` — 仿真代理

**状态：正确**

#### dmem 写操作已含地址过滤

```verilog
always @(posedge clk) begin
    if (data_req && dataAddr_32[31:16] != 16'h1001) begin
        if (dataWen_4[0] == 1'b0) dmem[dword_addr][7:0]   <= writeData_32[7:0];
        if (dataWen_4[1] == 1'b0) dmem[dword_addr][15:8]  <= writeData_32[15:8];
        if (dataWen_4[2] == 1'b0) dmem[dword_addr][23:16] <= writeData_32[23:16];
        if (dataWen_4[3] == 1'b0) dmem[dword_addr][31:24] <= writeData_32[31:24];
    end
end
```

Timer 地址区间（`0x1001_xxxx`）已被过滤，不会污染 dmem。

#### imem initial 块结构正确

```verilog
initial begin
    for (i = 0; i < 2048; i = i + 1)
        dmem[i] = 32'b0;
    `ifdef CSR_TEST
        $readmemh("dev/2-simpleCPU/program_source/csr_test.hex", imem);
    `else
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", imem);
    `endif
end
```

单个 initial 块配合 `ifdef` 条件编译，加载顺序确定，无并发风险。

#### Timer 外设模拟

- 地址 `0x1001_0000`（offset 0）：配置 `timer_threshold`
- 地址 `0x1001_0004`（offset 1）：配置 `timer_en`
- 计数器自增，达到阈值后输出 `timer_irq` 一个周期

**结论：** mock 总线代理功能完整，地址过滤正确，初始化逻辑安全。

---

### 3.6 Testbench 适配

**状态：正确**

`tb_simple_cpu_top.v` 和 `tb_csr_test.v` 正确实例化了 `bus4lzu_mock`，`mem_addr`/`mem_data` 通过 mock 的 debug 端口访问。仿真周期从 `1500` 延长到 `2500`，以覆盖 `init_sig` 冻结的 100 周期 + 取指延迟增加的周期数。

---

## 四、关键时序分析

| 操作 | 旧版本周期 | 新版本周期 | 变化原因 |
|------|-----------|-----------|----------|
| 取指 | 1 | 2 | 1 周期总线读延迟 |
| Store | 3（read-modify-write） | 2 | 字节掩码直接写 |
| Load | 1（当周期完成） | 2 | 1 周期读等待 |
| 上电初始化 | 5 | 105 | `init_sig` 冻结 100 周期 |
| 整体仿真 | ~1500 | ~2500 | 上述延迟累积 |

---

## 五、未测试的新功能（风险项）

PLAN.md 和 PROCESS.md 中标记为未完成的项目，当前测试**未覆盖**：

| 功能 | 状态 | 风险 |
|------|------|------|
| Timer 中断触发/进入/返回 | 未测试 | `timer_irq` 逻辑已接入但未验证中断流 |
| 字节/半字 store/load 对齐测试 | 未测试 | `dataWen_4` 掩码逻辑未专项验证 |
| 与真实 Bus4LZU IP 对接 | 未进行 | 仅限 mock 仿真 |

---

## 六、后续工作建议（按优先级）

| 优先级 | 任务 | 目标 | 建议 |
|--------|------|------|------|
| 中 | 补充 Timer 中断测试 | 验证中断进入/返回流 | 编写汇编配置 `timer_threshold` 并等待中断触发，检查 mepc/mcause/mstatus |
| 中 | 补充字节/半字对齐测试 | 验证 `dataWen_4` 掩码 | 在 test 汇编中加入 sb/sh/lb/lh/lbu/lhu 在 offset 0/1/2/3 的读写组合 |
| 低 | 与真实 Bus4LZU IP 对接 | 硬件集成 | 需 Vivado 环境，参考 `Reference/Bus4LZU/bus_interface.v` |

---

## 七、总体评价

这是一次**结构清晰、目标明确、功能正确**的总线适配重构。核心改动（fetch 延迟、mem 字节掩码、init_sig 冻结）的时序逻辑全部正确，已有回归测试 100% 通过。`bus4lzu_mock.v` 的地址过滤和初始化逻辑已经正确处理。文档（PLAN.md/PROCESS.md）更新及时，变更记录完整。

**遗留工作：**
1. 补充 Timer 中断测试和字节/半字对齐测试
2. 与真实 Bus4LZU IP 顶层对接验证（需 Vivado 环境）
