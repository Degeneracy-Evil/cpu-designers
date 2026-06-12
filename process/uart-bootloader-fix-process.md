# UART Bootloader 数据接收失败修复过程

> 日期: 2026-06-12
> 任务: cpu_full 集成仿真 — Bootloader 无法通过 UART 接收程序镜像
> 最终结果: ✅ ALL TESTS PASSED (pass=41, fail=0)

---

## 1. 问题描述

cpu_full 集成仿真中，Boot ROM 中的 bootloader 通过 UART 接收程序镜像写入 SRAM 后跳转执行。仿真现象：

- UART TX 发送侧正常（testbench 发送 header + 程序数据）
- UART RX 接收侧：bootloader 读取 RXDATA 始终返回 0 或错误值
- 程序镜像无法正确写入 SRAM，内存检查全部失败

---

## 2. 根因分析

经过逐层排查，发现 **5 个独立 bug** 共同导致 UART RX 数据接收失败：

### Bug 1: `uart_recv_word` 未保存/恢复 ra

**文件**: `dev/program_source/boot/bootloader.s`

`uart_recv_word` 调用 `uart_recv_byte`（使用 `jal ra, uart_recv_byte`），但未在栈上保存 ra。返回后 ra 被覆盖，后续 `ret` 跳转到错误地址。

**修复**: 添加 `addi sp, sp, -4; sw ra, 0(sp)` / `lw ra, 0(sp); addi sp, sp, 4`。

### Bug 2: sp 未初始化 — `sw ra, 0(sp)` 写入地址 0

**文件**: `dev/program_source/boot/bootloader.s`

`_start` 中未初始化 sp，sp 默认为 0。`sw ra, 0(sp)` 写入地址 0（SRAM 基址），覆盖程序数据。后续 `lw ra, 0(sp)` 读回被覆盖的值。

**修复**: 在 `_start` 开头添加 `lui sp, 0x80008`（sp = 0x80008000，SRAM 高地址作为栈顶）。

### Bug 3: 跳转执行前缺少 `fence.i`

**文件**: `dev/program_source/boot/bootloader.s`

bootloader 将程序写入 SRAM 后直接 `jr s3` 跳转执行，但 icache 中可能缓存了旧数据（全零或随机值），dcache 中可能有脏行未写回。CPU 取到旧指令。

**修复**: 在 `jr s3` 前添加 `fence.i`，刷新 dcache 脏行写回 + icache 标签失效。

### Bug 4: CPU 重复 AXI 事务导致 UART RXDATA 重复弹出 FIFO

**文件**: `dev/rtl/APB/perips/uart_top.sv`

**核心 bug**：CPU 数据总线存在每条 `lw`/`sw` 指令触发两次 AXI4-Lite 事务的 bug（两次 AR/AW 握手，间隔约 15 个时钟周期）。对普通内存（SRAM/DDR3）无影响（读无副作用），但对 UART RXDATA 寄存器是致命的——每次 `lw RXDATA` 触发两次读，第二次读额外弹出 FIFO 中的一个字节，导致每隔一字节丢失。

**逐周期追踪**：
```
lw STATUS  → AXI AR#1 (arm)  → AXI AR#2 (dup, no-op)
lw RXDATA  → AXI AR#3 (pop)  → AXI AR#4 (dup, extra pop!) ← 丢失一字节
```

**修复方案**: STATUS-read auto-arm 机制：

1. 读取 STATUS 寄存器且 `rx_valid=1`（FIFO 非空）时，自动置 `rx_pop_armed=1`
2. 读取 RXDATA 时：
   - 若 `rx_pop_armed=1`：弹出 FIFO 头部，清 `rx_pop_armed=0`（正常弹出）
   - 若 `rx_pop_armed=0`：仅 peek FIFO 头部，不弹出（重复读安全）
3. 重复读 STATUS：`rx_pop_armed` 已为 1，重复置 1 无副作用（幂等）
4. 重复读 RXDATA：`rx_pop_armed=0`，仅 peek，不弹出（安全）

**执行序列**（修复后）：
```
lw STATUS  → AR#1 (rx_valid=1, arm)  → AR#2 (rx_valid=1, re-arm, idempotent)
lw RXDATA  → AR#3 (armed, pop FIFO)  → AR#4 (not armed, peek only) ← 无丢失
```

### Bug 5: `slli`/`or` 字组装受重复事务影响产生错误结果

**文件**: `dev/program_source/boot/bootloader.s`

bootloader 用 `slli` + `or` 将 4 个字节组装成 32 位字：
```asm
slli t0, t0, 8   ; shift byte to position
or  s1, s1, t0   ; merge into word
```

由于 CPU 重复 AXI 事务 bug，`lw` 读到的字节可能来自 FIFO 中错误的位置（虽然 STATUS-arm 修复了 FIFO 弹出，但重复读 STATUS 返回的 `rx_valid` 状态可能使 bootloader 在错误时机读取），导致 `slli`/`or` 组装出错误的字。

**修复**: 改用 `sb` + `lw` 方式组装字——将 4 个字节逐个 `sb` 写入栈上连续地址，然后 `lw` 一次性读出 32 位字。`sb` 写入不受重复读影响（写是幂等的），`lw` 从 SRAM 读普通内存（无副作用）。

---

## 3. 修复详情

### 3.1 UART RTL 修改 (`uart_top.sv`)

新增信号和逻辑：

```systemverilog
// 新增寄存器
logic rx_pop_armed;        // STATUS-read auto-arm 标志

// STATUS 读取逻辑（偏移 0x04）
if (prdata_sel && !pwrite && paddr[3:0] == 4'h04) begin
    if (rx_valid)          // FIFO 非空时自动武装
        rx_pop_armed <= 1'b1;
end

// RXDATA 读取逻辑（偏移 0x0C）
if (prdata_sel && !pwrite && paddr[3:0] == 4'h0C) begin
    if (rx_pop_armed) begin
        rx_fifo_pop <= 1'b1;    // 弹出 FIFO
        rx_pop_armed <= 1'b0;   // 清标志
    end
    // else: peek only, 不弹出
end

// RXPOP 寄存器（偏移 0x18）仍保留但 bootloader 未使用
```

### 3.2 Bootloader 修改 (`bootloader.s`)

```asm
_start:
    lui sp, 0x80008          # sp = 0x80008000 (新增：初始化栈指针)

    # ... DDR3 自检 ...

uart_recv_word:
    addi sp, sp, -4          # 新增：保存 ra
    sw   ra, 0(sp)

    jal  ra, uart_recv_byte  # byte 0
    sb   t0, 0(sp_tmp)       # 新增：sb 写入栈
    jal  ra, uart_recv_byte  # byte 1
    sb   t0, 1(sp_tmp)
    jal  ra, uart_recv_byte  # byte 2
    sb   t0, 2(sp_tmp)
    jal  ra, uart_recv_byte  # byte 3
    sb   t0, 3(sp_tmp)
    lw   t0, 0(sp_tmp)       # 新增：lw 读出完整字

    lw   ra, 0(sp)           # 新增：恢复 ra
    addi sp, sp, 4
    ret

    # 跳转前
    fence.i                  # 新增：缓存一致性
    jr   s3
```

### 3.3 Testbench 修改

| 修改 | 原值 | 新值 | 原因 |
|------|------|------|------|
| FIFO 节流 | `wait (rx_state == S_IDLE)` | `while (rx_fifo_count >= 14) @(posedge clk)` | S_IDLE 在 FIFO 满时永远不到（RX 卡在 S_DATA） |
| 等待周期 | 8M | 16M | 完整 UART 下载需要更多时间 |
| 探针窗口 | 200K | 5K | 减少仿真输出量，加速 |
| SIM_UART_CYCLE | 16 | 16（不变） | 54× 加速，平衡速度与可靠性 |

---

## 4. 仿真配置

| 参数 | 值 | 说明 |
|------|-----|------|
| SIM_UART_CYCLE | 16 | 每比特 16 周期（真实 115200 baud 的 54× 加速） |
| FIFO 节流阈值 | ≥14 等待 | FIFO 计数 ≥14 时 TB 暂停发送，防溢出 |
| SRAM 等待周期 | 16M | bootloader + UART 下载 + 程序执行总等待 |
| 详细探针窗口 | 前 5K 周期 | FIFO-CHG / MMIO-VLD 等仅在最初 5K 周期输出 |
| FIFO-MON 周期探针 | 每 500K 周期 | 周期性 FIFO 状态监控（5K 之后） |

---

## 5. 验证结果

```
pass=41, fail=0
UART delivery complete: 8192 words (32768 bytes) received and verified
```

所有 41 项内存检查全部通过，程序正确下载并执行。

---

## 6. 已知限制

1. **CPU 重复 AXI 事务 bug 未根本修复**：每条 `lw`/`sw` 仍触发两次 AXI4-Lite 事务。当前通过 UART RTL 的 STATUS-arm 机制 workaround。根本修复需排查 CPU 总线桥接逻辑。

2. **RXPOP 寄存器（偏移 0x18）未使用**：保留在 RTL 中但 bootloader 不使用。STATUS-arm 机制已完全替代 RXPOP 的弹出功能。

3. **仅验证 SRAM 模式**：DDR3 模式下的 UART 下载流程未验证。

---

## 7. 相关文件

| 文件 | 修改内容 |
|------|---------|
| `dev/rtl/APB/perips/uart_top.sv` | rx_pop_armed 标志 + STATUS-read auto-arm + RXDATA peek/pop 逻辑 |
| `dev/program_source/boot/bootloader.s` | sp 初始化 + ra 保存/恢复 + fence.i + sb+lw 字组装 |
| `dev/program_source/boot/bootloader.hex` | 重新编译（79 words） |
| `dev/program_source/boot/bootloader_full.s` | 同样修复 |
| `dev/program_source/boot/bootloader_full.hex` | 重新编译 |
| `dev/tb/tb_simple_cpu_top.sv` | 16M 等待 + 5K 探针窗口 |
| `dev/tb/tb_soc_includes.svh` | FIFO-count 节流（≥14） |
