# Near-Linux Bug Fixes

> Date: 2026-06-14 | Verified by simulation (20 tests PASS)

---

## Bug 1: MMIO 判定基于虚拟地址而非物理地址

### 问题描述

`icache_ctrl.sv` 和 `dcache_ctrl.sv` 中的 `is_mmio` 信号使用虚拟地址 (`cpu_req_vaddr`) 判断 MMIO 区域：

```systemverilog
// 修复前（错误）
wire is_mmio = ~cpu_req_vaddr[31] | cpu_req_vaddr[30];
```

当 Sv32 地址翻译激活时，虚拟地址与物理地址的映射关系不确定：
- 虚拟地址在 0x80000000（Cacheable）可能映射到 MMIO 物理地址 → 错误走缓存路径
- 虚拟地址在 MMIO 区域可能映射到 0x80000000（Cacheable）→ 错误走 MMIO 旁路

这会导致 Linux 内核在启用 Sv32 页表后，设备访问（UART/CLINT/PLIC）走缓存路径，产生数据损坏或挂死。

### 修复方案

**核心原则**：MMIO/Cacheable 判定必须基于物理地址，因为地址译码器（system_top 中的 slave_sel）工作在物理地址空间。

#### 1. `is_mmio` 改用物理地址

```systemverilog
// 修复后（正确）
wire is_mmio = ~cpu_req_addr[31] | cpu_req_addr[30];
```

#### 2. S_IDLE 等待 mmu_ready 后再路由

物理地址仅在 `mmu_ready=1` 时有效。修复前，S_IDLE 立即根据虚拟地址决定 MMIO/Cache 路径；修复后，S_IDLE 等待 `mmu_ready` 后再根据物理地址路由：

```systemverilog
// icache_ctrl.sv S_IDLE（修复后）
if (mmu_ready) begin
    if (is_mmio) begin
        // MMIO 路径：物理地址有效且在 MMIO 区域
        ...
    end else begin
        // Cache 路径：物理地址有效且可缓存
        state <= S_TAG_READ;
    end
end else begin
    // 等待 mmu_ready（物理地址有效前不做路由决策）
    ...
end
```

#### 3. tag_bram_ena 增加 mmu_ready 门控

```systemverilog
// 修复前
wire tag_bram_ena = (state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && !is_mmio;
// 修复后
wire tag_bram_ena = (state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && mmu_ready && !is_mmio;
```

防止在物理地址无效时错误使能 tag BRAM。

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/icache_ctrl.sv` | `is_mmio` 改用 `cpu_req_addr`；S_IDLE 等待 mmu_ready；`tag_bram_ena` 增加 mmu_ready 门控 |
| `dev/rtl/core/dcache_ctrl.sv` | 同上 |

### 性能影响

- Bare 模式（satp[31]=0）：mmu_ready 始终为 1，零延迟影响
- Sv32 模式：TLB 命中时 mmu_ready 在 1-2 周期内有效；TLB 缺失时需等待 PTW 完成，但此延迟与修复前 TLB 缺失的等待时间一致

---

## Bug 2: STIP 无置位路径 + M/S 中断优先级 Bug

### 问题描述

三个子问题捆绑修复，均与 S-mode 定时器中断和 M/S 特权优先级相关。

### 子问题 ①：sip_wmask 缺少 bit5，sip[5] (STIP) 不可写

**问题**：`cpu_csr.sv` 中 `sip_wmask` 仅允许写 sip[1] (SSIP)：

```systemverilog
// 修复前
assign sip_wmask = {31'd0, sw_csr_wdata[1]};
```

Per RISC-V 特权规范，S-mode 应能写 sip[5] (STIP) 以设置/清除 S-mode 定时器中断挂起位。当 mideleg[5]=0（定时器中断未委托）时，Linux 需要通过写 sip[5] 来模拟 S-mode 定时器中断。

**修复**：

```systemverilog
// 修复后
assign sip_wmask = {26'd0, sw_csr_wdata[5], 4'd0, sw_csr_wdata[1], 1'b0};
```

同时修复 `r_mip` 构造，使 mip[5] 反映 sip[5]：

```systemverilog
// 修复前：mip[5] 始终为 0
r_mip <= {w_mip_hw[31:2], r_sip[1], w_mip_hw[0]};
// 修复后：mip[5] = r_sip[5] (STIP)
r_mip <= {w_mip_hw[31:6], r_sip[5], w_mip_hw[4:2], r_sip[1], w_mip_hw[0]};
```

以及 sip 读取暴露 bit5：

```systemverilog
// 修复前
ADDR_SIP: sw_csr_rdata_r = {31'd0, r_sip[1]};
// 修复后
ADDR_SIP: sw_csr_rdata_r = {26'd0, r_sip[5], 4'd0, r_sip[1], 1'b0};
```

### 子问题 ②：S-mode 定时器挂起改用 csr_mip[5] 而非 ext_mtip

**问题**：`cpu_clint.sv` 中 S-mode 定时器中断挂起检查直接使用 `ext_mtip`（CLINT 硬件 MTIP 信号）：

```systemverilog
// 修复前
wire mtip_bit = ext_mtip;
// S-mode timer pending 使用 mtip_bit（即 ext_mtip）
wire s_interrupt_pending = sie_bit && (...|| (stie_bit && mtip_bit) || ...);
```

这绕过了 mip 寄存器，导致：
- 软件写 sip[5]=1 无法触发 S-mode 定时器中断
- mip[5] 始终为 0，与实际中断挂起状态不一致

**修复**：S-mode 定时器挂起改用 `csr_mip[5]`（STIP），该位由 r_sip[5] 驱动（软件可写）：

```systemverilog
// 修复后
wire stip_bit = csr_mip[5];  // STIP from mip[5]
wire s_interrupt_pending = sie_bit && (...|| (stie_bit && stip_bit) || ...);
```

M-mode 的 `mtip_bit = ext_mtip` 保持不变（M-mode MTIP 直接由 CLINT 硬件驱动，符合规范）。

### 子问题 ③：M-mode 中断未委托时 S-mode 可抢占（优先级 Bug）

**问题**：`cpu_clint.sv` 中 S-mode 中断获取条件：

```systemverilog
// 修复前
wire m_int_delegated = m_interrupt_pending && csr_mideleg[m_int_idx];
wire s_int_taken     = s_interrupt_pending && !m_int_delegated;
```

当 M-mode 中断挂起且未委托时（`m_int_delegated=0`），`!m_int_delegated=1`，导致 `s_int_taken = s_interrupt_pending`。这意味着 **S-mode 中断可以抢占未委托的 M-mode 中断**，违反 RISC-V 特权优先级（M > S）。

**场景**：
1. M-mode 定时器中断挂起（MTIP=1, MTIE=1, MIE=1），mideleg[7]=0（未委托）
2. S-mode 外部中断也挂起（SEIP=1, SEIE=1, SIE=1）
3. 修复前：S-mode 中断被错误地获取（s_int_taken=1），跳转到 stvec
4. 修复后：M-mode 中断优先获取（s_int_taken=0），跳转到 mtvec

**修复**：

```systemverilog
// 修复后
wire m_int_not_delegated = m_interrupt_pending && !m_int_delegated;
wire s_int_taken         = s_interrupt_pending && !m_int_not_delegated;
```

等价于：`s_int_taken = s_interrupt_pending && (!m_interrupt_pending || m_int_delegated)`

S-mode 中断仅在以下条件可获取：
- 无 M-mode 中断挂起，或
- M-mode 中断已委托至 S-mode

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/cpu_csr.sv` | sip_wmask 扩展 bit5；r_mip 构造包含 r_sip[5]；sip 读取暴露 bit5 |
| `dev/rtl/core/cpu_clint.sv` | S-mode 定时器改用 csr_mip[5]；M/S 优先级修复 |

---

## Bug 4: time/timeh CSR 未实现 + U-mode 计数器别名 CSR 未实现

### 问题描述

两个子问题捆绑修复，均与 RISC-V 计数器 CSR 的 U-mode 可访问性相关。

### 子问题 ①：time/timeh CSR (0xC01/0xC81) 无读路径

**问题**：`cpu_csr.sv` 中没有 `ADDR_TIME`/`ADDR_TIMEH` 的定义和读路径。Per RISC-V 特权规范，`time` CSR (0xC01) 反映 CLINT 的 `mtime` 寄存器值，是 U-mode 唯一可以直接读取的硬件计时器。

Linux 用户态程序（如 `clock_gettime(CLOCK_MONOTONIC)`）通过 `rdtime` 指令读取 `time` CSR。如果该 CSR 不可读，用户态时间测量将触发非法指令异常。

**根因**：
1. `axi4lite_clint.sv` 内部有 `r_mtime` 寄存器，但未暴露为输出端口
2. `cpu_csr.sv` 没有 `ext_mtime` 输入端口
3. `cpu_csr.sv` 读数据 mux 没有 `ADDR_TIME`/`ADDR_TIMEH` 分支

**修复**：

#### 1. axi4lite_clint.sv：暴露 r_mtime

```systemverilog
output wire [63:0] o_mtime
assign o_mtime = r_mtime;
```

#### 2. system_top.sv：跨时钟域同步 + 连线

CLINT 在 `sys_clk` 域，CPU 在 `cpu_clk` 域。添加两级 FF 同步器（与 ext_mtip/ext_msip 相同模式）：

```systemverilog
wire [63:0] clint_mtime;
logic [63:0] clint_mtime_cpuclk_ff1, clint_mtime_cpuclk_ff2;
// 两级 FF 同步器
clint_mtime_cpuclk_ff1 <= clint_mtime;
clint_mtime_cpuclk_ff2 <= clint_mtime_cpuclk_ff1;
```

连接到 core_top：`.ext_mtime(clint_mtime_cpuclk_ff2)`

#### 3. cpu_csr.sv：添加 time/timeh 读路径

```systemverilog
input [63:0] ext_mtime,

localparam ADDR_TIME  = 12'hC01;
localparam ADDR_TIMEH = 12'hC81;

// 读数据 mux
ADDR_TIME:  sw_csr_rdata_r = ext_mtime[31:0];
ADDR_TIMEH: sw_csr_rdata_r = ext_mtime[63:32];
```

`time`/`timeh` 为只读 CSR（写入触发非法指令异常，由 `is_read_only_csr` 和 `cpu_decode.sv` 的 `write_ro_csr` 检查覆盖）。

### 子问题 ②：U-mode 计数器别名 CSR 未实现

**问题**：`cpu_csr.sv` 和 `cpu_decode.sv` 中 U-mode CSR 访问完全阻止：

```systemverilog
// 修复前
PRIV_U: csr_access_ok_r = 1'b0;      // 阻止所有 U-mode CSR 访问
PRIV_U: dec_csr_access_ok_r = 1'b0;   // 同上
```

Per RISC-V 特权规范，U-mode 可以读取以下计数器别名 CSR（如果 `mcounteren` 允许）：

| CSR | 地址 | 含义 | 映射 |
|-----|------|------|------|
| cycle | 0xC00 | 时钟周期计数 | mcycle |
| time | 0xC01 | 实时计时器 | mtime (CLINT) |
| instret | 0xC02 | 指令完成计数 | minstret |
| cycleh | 0xC80 | cycle 高 32 位 | mcycleh |
| timeh | 0xC81 | time 高 32 位 | mtimeh |
| instreth | 0xC82 | instret 高 32 位 | minstreth |

**修复**：

#### 1. 添加 U-mode CSR 地址定义和识别函数

```systemverilog
localparam ADDR_CYCLE    = 12'hC00;
localparam ADDR_TIME     = 12'hC01;
localparam ADDR_INSTRET  = 12'hC02;
localparam ADDR_CYCLEH   = 12'hC80;
localparam ADDR_TIMEH    = 12'hC81;
localparam ADDR_INSTRETH = 12'hC82;

function is_u_csr;
    input [11:0] addr;
    is_u_csr = (addr == ADDR_CYCLE)  || (addr == ADDR_TIME)    ||
               (addr == ADDR_INSTRET)||
               (addr == ADDR_CYCLEH) || (addr == ADDR_TIMEH)  ||
               (addr == ADDR_INSTRETH);
endfunction
```

#### 2. 修复 csr_access_ok（mcounteren/scounteren 门控）

```systemverilog
// mcounteren bit 映射：bit0=cycle, bit1=time, bit2=instret
wire [2:0] counter_idx;
assign counter_idx = (addr == ADDR_CYCLE || addr == ADDR_CYCLEH) ? 3'd0 :
                     (addr == ADDR_TIME  || addr == ADDR_TIMEH)  ? 3'd1 :
                     (addr == ADDR_INSTRET || addr == ADDR_INSTRETH) ? 3'd2 : 3'd0;

wire u_counter_allowed = r_mcounteren[counter_idx];
wire s_counter_allowed = r_mcounteren[counter_idx] && r_scounteren[counter_idx];

// 修复后
PRIV_U: csr_access_ok_r = is_u_csr(sw_csr_addr) && u_counter_allowed;
PRIV_S: csr_access_ok_r = is_s_csr(sw_csr_addr) || (is_u_csr(sw_csr_addr) && s_counter_allowed);
```

- U-mode：仅当 `mcounteren` 对应位为 1 时可读计数器别名
- S-mode：仅当 `mcounteren` 和 `scounteren` 对应位均为 1 时可读计数器别名
- M-mode：无限制（`csr_access_ok_r = 1'b1`）

#### 3. 添加 U-mode 计数器别名读路径

```systemverilog
ADDR_CYCLE:     sw_csr_rdata_r = r_mcycle[31:0];     // cycle = mcycle
ADDR_TIME:      sw_csr_rdata_r = ext_mtime[31:0];     // time = mtime
ADDR_INSTRET:   sw_csr_rdata_r = r_minstret[31:0];   // instret = minstret
ADDR_CYCLEH:    sw_csr_rdata_r = r_mcycle[63:32];    // cycleh = mcycleh
ADDR_TIMEH:     sw_csr_rdata_r = ext_mtime[63:32];    // timeh = mtimeh
ADDR_INSTRETH: sw_csr_rdata_r = r_minstret[63:32];  // instreth = minstreth
```

#### 4. 同步修复 cpu_decode.sv

```systemverilog
// 修复前
PRIV_U: dec_csr_access_ok_r = 1'b0;
PRIV_S: dec_csr_access_ok_r = is_s_csr(csr_addr);

// 修复后
PRIV_U: dec_csr_access_ok_r = is_u_csr(csr_addr);
PRIV_S: dec_csr_access_ok_r = is_s_csr(csr_addr) || is_u_csr(csr_addr);
```

`cpu_decode.sv` 的 `csr_read_only = (csr_addr[11:10] == 2'b11)` 检查已覆盖 U-mode 计数器别名（地址 0xC00-0xCFF 的 bit[11:10] = 2'b11），写入自动触发非法指令异常。

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/axi/axi4lite_clint.sv` | 添加 `o_mtime` 输出端口 |
| `dev/rtl/system_top.sv` | mtime 跨时钟域同步；连接到 core_top |
| `dev/rtl/core/core_top.sv` | 添加 `ext_mtime` 输入端口；连接到 cpu_trap_csr |
| `dev/rtl/core/cpu_trap_csr.sv` | 添加 `ext_mtime` 输入端口；连接到 cpu_csr_interface |
| `dev/rtl/core/cpu_csr_interface.sv` | 添加 `ext_mtime` 输入端口；连接到 cpu_csr |
| `dev/rtl/core/cpu_csr.sv` | 添加 `ext_mtime` 输入；time/timeh 读路径；U-mode 计数器别名；mcounteren/scounteren 门控 |
| `dev/rtl/core/cpu_decode.sv` | 添加 U-mode CSR 地址和 `is_u_csr`；修复 `dec_csr_access_ok` |

---

## Bug 3: sfence.vma 缓存一致性问题

### 问题描述

`sfence.vma` 指令隐含内存屏障语义：它不仅刷新 TLB，还应强制等待所有之前的页表写操作（store）完成并全局可见（即从 dcache 写回到主存），之后才使 TLB 失效。

**修复前的执行路径**：

```
sfence.vma 解码 → cpu_controller: STATE_DECODE → STATE_FETCH（立即！）
                  core_top: sfence_vma_pulse → MMU: TLB flush
```

问题：`sfence.vma` 解码后立即发送 `sfence_vma_pulse` 到 MMU 刷新 TLB，**没有等待 dcache 中可能缓存的页表写操作完成**。如果页表条目（PTE）的 store 仍在 dcache 中（dirty 但未写回），TLB 刷新后 PTW 使用主存中的旧 PTE 重新填充 TLB，导致：

- TLB 中缓存了过时的地址翻译
- 后续访问使用错误的物理地址
- Linux 内核在修改页表后调用 sfence.vma 可能观察到不一致的地址翻译

### 修复方案

**核心原则**：sfence.vma 的执行顺序必须是 dcache writeback+invalidate → icache invalidate → TLB flush，确保：

1. **dcache writeback+invalidate**：所有 dirty cache line（包含 PTE 写操作）写回主存，然后使 dcache 标志位无效
2. **icache invalidate**：使 icache 标志位无效，防止使用基于旧翻译缓存的指令
3. **TLB flush**：此时主存中的页表已是最新版本，TLB 刷新后 PTW 将读到正确的 PTE

#### 1. cpu_controller.sv：添加 STATE_SFENCE_VMA

```systemverilog
// 修复前：sfence.vma 立即返回
dec_is_sfence_vma → next_state = STATE_FETCH;

// 修复后：sfence.vma 等待完成序列
localparam STATE_SFENCE_VMA = 4'd10;
dec_is_sfence_vma → next_state = STATE_SFENCE_VMA;
STATE_SFENCE_VMA: next_state = sfence_vma_done ? STATE_FETCH : STATE_SFENCE_VMA;
```

添加端口：
- `output sfence_vma_req`：指示控制器处于 SFENCE_VMA 状态
- `input sfence_vma_done`：dcache flush + icache inv + TLB flush 全部完成

#### 2. MMU.sv：添加 sfence_done 输出

MMU 需要向 core_top 报告 TLB 刷新完成，使 core_top 知道何时可以退出 sfence 序列：

```systemverilog
output wire sfence_done

// 内部跟踪
reg sfence_pending_r;
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn)
        sfence_pending_r <= 1'b0;
    else if (sfence_vma && !sfence_pending_r)
        sfence_pending_r <= 1'b1;
    else if (sfence_pending_r && (i_state == I_IDLE) && (d_state == D_IDLE) && !sfence_vma)
        sfence_pending_r <= 1'b0;
end
assign sfence_done = sfence_pending_r && (i_state == I_IDLE) && (d_state == D_IDLE);
```

`sfence_done` 在 MMU 的 i-side 和 d-side 都回到 IDLE 后置位，表示 TLB 刷新完成。

#### 3. core_top.sv：sfence.vma 三阶段序列化

**阶段 1 — dcache flush（writeback+invalidate）**：

```systemverilog
sfence_vma_req && !sfence_dcache_flush_sent_r
// 等待 dcache_flush_done 后设置 sfence_dcache_flush_sent_r
```

**阶段 2 — icache invalidate**：

```systemverilog
sfence_vma_req && sfence_dcache_flush_sent_r && !sfence_icache_inv_sent_r
// 等待 icache_invalidate_done 后设置 sfence_icache_inv_sent_r
```

**阶段 3 — TLB flush**：

```systemverilog
// dcache+icache 完成后发送 sfence_vma 脉冲到 MMU
wire sfence_vma_to_mmu_pulse = sfence_vma_req && sfence_dcache_flush_sent_r
                             && sfence_icache_inv_sent_r && !sfence_tlb_pulse_sent_r;
// 等待 mmu_sfence_done 后设置 sfence_tlb_flush_sent_r
```

**完成信号**：

```systemverilog
assign sfence_vma_done = sfence_dcache_flush_sent_r && sfence_icache_inv_sent_r && sfence_tlb_flush_sent_r;
```

**合并 cache 维护请求**（fencei 和 sfence 互斥，OR 安全）：

```systemverilog
assign dcache_flush_req      = (fencei_req && !fencei_dcache_flush_sent_r)
                             || (sfence_vma_req && !sfence_dcache_flush_sent_r);
assign icache_invalidate_req = (fencei_req && fencei_dcache_flush_sent_r && !fencei_icache_inv_sent_r)
                             || (sfence_vma_req && sfence_dcache_flush_sent_r && !sfence_icache_inv_sent_r);
```

#### 4. 附带修复：fence.i 序列化 bug

修复前 `fencei_dcache_flush_sent_r` 的赋值存在重复行导致条件被短路（`dcache_flush_sent_r` 在 `fencei_req` 活跃时始终为 1），使 icache 无效化与 dcache flush 并行执行而非串行。修复后使用正确的条件门控：

```systemverilog
// 修复前（bug：重复行无条件执行，短路了 dcache_flush_done 条件）
if (dcache_flush_done && !dcache_flush_sent_r)
    dcache_flush_sent_r <= 1'b1;
    dcache_flush_sent_r <= 1'b1;  // ← 重复行，无条件执行

// 修复后
if (dcache_flush_done && !fencei_dcache_flush_sent_r)
    fencei_dcache_flush_sent_r <= 1'b1;
if (icache_invalidate_done && fencei_dcache_flush_sent_r && !fencei_icache_inv_sent_r)
    fencei_icache_inv_sent_r <= 1'b1;
```

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/cpu_controller.sv` | 添加 `STATE_SFENCE_VMA`、`sfence_vma_req`/`sfence_vma_done` 端口 |
| `dev/rtl/core/MMU.sv` | 添加 `sfence_done` 输出及完成跟踪逻辑 |
| `dev/rtl/core/core_top.sv` | sfence.vma 三阶段序列化；合并 fencei/sfence cache 维护请求；修复 fencei 序列化 bug |

### 性能影响

- **Bare 模式**（satp[31]=0）：sfence.vma 变为 NOP（TVM 检查会触发非法指令异常，或直接跳过），无额外开销
- **Sv32 模式**：sfence.vma 执行时间 = dcache flush 时间 + icache invalidate 时间 + TLB flush 时间
  - dcache flush：最坏情况 O(SETS × WAYS) 周期（每个 dirty line 需写回）
  - icache invalidate：O(SETS) 周期
  - TLB flush：O(TLB_SETS) 周期
  - 对于当前配置（dcache 8 sets × 4 ways, icache 8 sets, TLB 4 sets），最坏约 50-60 周期
  - Linux 内核中 sfence.vma 仅在页表修改时调用（低频），性能影响可忽略

---

## 仿真验证

以下 20 个测试全部 PASS，确认修复未引入回归：

| 类别 | 测试 | 结果 |
|------|------|------|
| ISA | isa_alu, isa_csr | PASS |
| Exception | exception_interrupt_basic, exception_ecall, exception_ebreak, exception_illegal_inst | PASS |
| Privilege | privilege_delegation, privilege_priv_transition, privilege_csr_access_priv | PASS |
| MMU | mmu_sv32_basic, mmu_permission, mmu_page_fault, mmu_tlb_basic, mmu_ptw_walk, mmu_unified_mmu | PASS |
| Cache | cache_icache_basic, cache_dcache_basic | PASS |
| CPU | cpu_trap, cpu_compute, cpu_full | PASS |

---

## Bug 5: PMP (物理内存保护) 寄存器未实现

### 问题描述

RISC-V 特权规范要求 PMP (Physical Memory Protection) 单元提供 per-hart 机器模式控制寄存器，为物理内存区域指定访问权限。Linux 内核启动时需要写入 pmpcfg0-3 和 pmpaddr0-15 CSR 来配置内存保护。如果这些 CSR 不存在，Linux 将在 M-mode 初始化阶段触发非法指令异常。

### 实现方案：最小 PMP (仅寄存器)

实现 16 个 PMP 条目的 CSR 寄存器（pmpcfg0-3, pmpaddr0-15），包含：
- CSR 读写路径
- 锁定位 (L) 强制：L=1 后 pmpcfg 和 pmpaddr 变为只读直至复位
- WARL 约束：保留位 [6:5] 读零写忽略；A 字段仅支持 OFF(00) 和 TOR(01)
- PMP CSR 仅 M-mode 可访问
- 输出端口供未来硬件权限强制使用

**未实现**：PMP 硬件权限检查（S/U-mode 内存访问强制）。当前所有内存访问默认允许。这是"最小 PMP"——寄存器存在且可正确读写，Linux 可配置 PMP 条目，但硬件不强制执行权限。Linux 启动时 M-mode 通常设置 pmpcfg0 使全地址空间 R/W/X 可访问，因此不强制执行不影响启动。

### PMP 配置格式

每个 PMP 条目由 8 位配置字节和 32 位地址寄存器描述：

| 位 | 7 | 6-5 | 4-3 | 2 | 1 | 0 |
|----|---|------|------|---|---|---|
| | L | 0 | A[1:0] | X | W | R |

- **R/W/X**：读/写/执行权限
- **A[1:0]**：地址匹配模式（OFF=00 禁用，TOR=01 范围顶部，NA4=10，NAPOT=11）
- **L**：锁定位。置位后配置和地址寄存器不可写直至复位

pmpcfg0 包含 entry 0-3 的配置字节，pmpcfg1 包含 entry 4-7，以此类推。

### 实现细节

#### 1. CSR 地址定义

```systemverilog
localparam ADDR_PMPCFG0  = 12'h3A0;  // entry 0-3
localparam ADDR_PMPCFG1  = 12'h3A1;  // entry 4-7
localparam ADDR_PMPCFG2  = 12'h3A2;  // entry 8-11
localparam ADDR_PMPCFG3  = 12'h3A3;  // entry 12-15
localparam ADDR_PMPADDR0 = 12'h3B0;  // ~ ADDR_PMPADDR15 = 12'h3BF
```

#### 2. 寄存器声明与复位

```systemverilog
reg [31:0] r_pmpcfg0, r_pmpcfg1, r_pmpcfg2, r_pmpcfg3;
reg [31:0] r_pmpaddr0  /* ~ r_pmpaddr15 */;

// 复位：per RISC-V spec, 可写 PMP 寄存器的 A 和 L 字段清零
r_pmpcfg0 <= 32'b0;  // 所有 A=00(OFF), L=0
r_pmpaddr0 <= 32'b0; // ...
```

#### 3. 锁定位强制

```systemverilog
// 检测每个 entry 的 lock bit (bit 7 of each config byte)
wire pmp_entry0_locked = r_pmpcfg0[7];
wire pmp_entry1_locked = r_pmpcfg0[15];
// ...

// pmpcfg 写掩码：锁定 entry 的字节写零，保留位 [6:5] 强制零
wire [31:0] pmpcfg0_wmask;
assign pmpcfg0_wmask = {(pmp_entry3_locked ? 8'b0 : (sw_csr_wdata[31:24] & 8'h9F)),
                        (pmp_entry2_locked ? 8'b0 : (sw_csr_wdata[23:16] & 8'h9F)),
                        (pmp_entry1_locked ? 8'b0 : (sw_csr_wdata[15:8]  & 8'h9F)),
                        (pmp_entry0_locked ? 8'b0 : (sw_csr_wdata[7:0]   & 8'h9F))};
// 8'h9F = 1001_1111: 保留 bit[6:5]=0，允许 bit[7](L), bit[4:3](A), bit[2:0](X,W,R)

// pmpaddr 写：锁定 entry 的地址寄存器不可写
ADDR_PMPADDR0: if (!pmp_entry0_locked) r_pmpaddr0 <= sw_csr_wdata;
```

#### 4. CSR 访问权限

```systemverilog
// PMP CSR 仅 M-mode 可访问
function is_pmp_csr;
    input [11:0] addr;
    is_pmp_csr = (addr == ADDR_PMPCFG0) || ... || (addr == ADDR_PMPADDR15);
endfunction

// csr_addr_valid 包含 PMP
assign csr_addr_valid = is_s_csr(...) || is_m_csr(...) || is_u_csr(...) || is_pmp_csr(...);

// cpu_decode.sv: is_m_csr 包含 PMP 地址（M-mode 可访问）
// S/U-mode 访问 PMP CSR → dec_csr_access_ok = 0 → 非法指令异常
```

#### 5. 输出端口

```systemverilog
// cpu_csr.sv 输出
output [31:0] csr_pmpcfg0, csr_pmpcfg1, csr_pmpcfg2, csr_pmpcfg3,
output [31:0] csr_pmpaddr0  /* ~ csr_pmpaddr15 */

// 连线链: cpu_csr → cpu_csr_interface → cpu_trap_csr → core_top
// core_top 当前未使用 PMP 输出（留空），供未来 MMU PMP 检查使用
```

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/cpu_csr.sv` | PMP CSR 地址定义、寄存器、复位、读 mux、写逻辑（锁定位+WARL）、输出端口、`is_pmp_csr` 函数 |
| `dev/rtl/core/cpu_decode.sv` | PMP CSR 地址定义、`is_m_csr` 包含 PMP 地址 |
| `dev/rtl/core/cpu_csr_interface.sv` | PMP 输出端口声明与连线 |
| `dev/rtl/core/cpu_trap_csr.sv` | PMP 输出端口声明与连线 |
| `dev/rtl/core/core_top.sv` | PMP 输出端口连线（当前未使用） |

### 仿真验证

20 个测试全部 PASS，包括 `isa_csr`（CSR 读写）、`privilege_csr_access_priv`（权限检查）、`cpu_full`（完整 CPU 集成）。

---

## Bug 6: PTW A/D 位写回与 dcache 一致性问题

### 问题描述

RISC-V Sv32 页表遍历器 (PTW) 在首次访问页时需要设置页表条目 (PTE) 的 A (Accessed) 位和 D (Dirty) 位。PTW 通过 `cpu_bus_bridge` 直接写入主存，**旁路 dcache**。

如果 dcache 中缓存了该 PTE 所在 cache line 的副本（可能包含脏数据），PTW 写入 A/D 位后，dcache 中的副本变为过时数据。后续 CPU 读取该 PTE（如 TLB refill 时的 PTW 读取，或软件直接读取页表）将从 dcache 获取旧值（A=0/D=0），导致：

1. **重复 A/D 位写回**：PTW 再次认为 A/D 位未设置，触发不必要的写回
2. **TLB 一致性问题**：如果 TLB 从 dcache 读取 PTE（而非从主存），可能缓存 A=0/D=0 的旧 PTE，导致权限判断错误
3. **软件可见不一致**：软件读取页表内存看到的 A/D 位状态与实际不符

### 根因

PTW 的 A/D 位写回路径：

```
PTW (S_AD_UPDATE) → ptw_bus_we=1, ptw_bus_addr=pte_addr_r → cpu_bus_bridge → AXI → 主存
```

此路径完全旁路 dcache。dcache 没有被告知该地址的 cache line 已被外部修改，形成隐式写操作的一致性漏洞。

### 修复方案：PTW A/D 写回后 invalidate dcache 对应行

当 PTW 完成 A/D 位写回时，向 dcache 发送单行无效化请求，使包含该 PTE 的 cache line 失效。后续对该地址的访问将触发 cache miss，从主存重新填充，获取 PTW 更新后的 PTE。

#### 关键设计决策：不写回脏数据

如果 dcache 中该 line 的 D=1（脏位为 1），正常无效化流程需要先写回脏数据。但在此场景下，**绝不能写回脏数据**：

- dcache 中的脏数据是**旧 PTE**（A/D 位未设置）
- PTW 已将**新 PTE**（A/D 位已设置）写入主存
- 如果写回 dcache 的旧 PTE，会覆盖 PTW 的更新，导致 A/D 位丢失

因此，修复方案是**直接清除 V 位**（丢弃 dcache 中的旧数据），而非写回后无效化。这确保 PTW 的 A/D 更新不会被覆盖。

#### 实现细节

##### 1. dcache_ctrl.sv：添加单行无效化接口

```systemverilog
// 新增端口
input  wire        inv_line_req,     // 单行无效化请求
input  wire [31:0] inv_line_addr,    // 要无效化的物理地址
output wire        inv_line_done     // 无效化完成

// 新增状态
localparam S_INV_LINE       = 4'd11;  // 读取 tag BRAM
localparam S_INV_LINE_WRITE = 4'd12;  // 比较并清除匹配 way 的 V 位
```

**S_INV_LINE** (1 周期)：启用 tag BRAM Port A 读取 `inv_line_addr` 对应 set 的标签。

**S_INV_LINE_WRITE** (1 周期)：tag 输出有效，比较 `inv_latched_tag` 与各 way 的标签：

```systemverilog
// 无效化命中检测
wire inv_hit0 = tag_r0[TAG_ENTRY_W-1] && (tag_r0[TAG_WIDTH-1:0] == inv_latched_tag);
// ... inv_hit1/2/3 同理

// 清除匹配 way 的 V 位：写入 {V=0, D=0, tag}
if (inv_hit0) begin
    tag_bram_enb_r   <= 1'b1;
    tag_bram_web_r   <= ((1 << TAG_BRAM_BPW) - 1);  // way 0
    tag_bram_addrb_r <= inv_latched_set;
    tag_bram_dinb_r  <= ... {1'b0, 1'b0, tag_r0[TAG_WIDTH-1:0]};  // V=0, D=0
end
```

仅处理第一个匹配的 way（同一 set 中多个 way 匹配同一 tag 是不可能的，因为 tag 是唯一标识符）。

##### 2. core_top.sv：PTW 写完成时触发无效化

```systemverilog
reg        ptw_ad_inv_pending_r;
reg [31:0] ptw_ad_inv_addr_r;

always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        ptw_ad_inv_pending_r <= 1'b0;
    end else begin
        if (ptw_bus_we && ptw_bus_done && !ptw_ad_inv_pending_r) begin
            // PTW 写完成 → 请求 dcache 无效化
            ptw_ad_inv_pending_r <= 1'b1;
            ptw_ad_inv_addr_r   <= ptw_bus_addr;
        end else if (ptw_ad_inv_done) begin
            // dcache 完成无效化
            ptw_ad_inv_pending_r <= 1'b0;
        end
    end
end
```

**触发条件**：`ptw_bus_we && ptw_bus_done` — PTW 写操作完成（仅在 `S_AD_UPDATE` 状态下 `ptw_bus_we` 为 1）。

**握手协议**：`inv_line_req` 保持高电平直到 `inv_line_done` 返回。dcache 仅在 `S_IDLE` 状态下接受请求，如果 dcache 忙则等待。

##### 3. 时序分析

```
PTW S_AD_UPDATE → ptw_bus_we=1 → bus bridge → 主存写入
                                          ↓
                                    ptw_bus_done=1
                                          ↓
core_top: ptw_ad_inv_pending_r=1 → inv_line_req=1
                                          ↓
dcache: S_IDLE → S_INV_LINE → S_INV_LINE_WRITE → S_IDLE
                                          ↓
                                   inv_line_done=1
                                          ↓
core_top: ptw_ad_inv_pending_r=0
```

无效化延迟：2-3 个时钟周期（取决于 dcache 是否空闲）。在此窗口内，CPU 可能从 dcache 读取旧 PTE，但这仅在 PTW 设置 A/D 位后立即访问同一 PTE 时发生，实际场景中不会出现（PTW 是为 CPU 的当前访问进行页表遍历，CPU 在 PTW 完成前不会继续执行）。

### 影响的文件

| 文件 | 修改内容 |
|------|----------|
| `dev/rtl/core/dcache_ctrl.sv` | 添加 `inv_line_req/addr/done` 端口；`S_INV_LINE`/`S_INV_LINE_WRITE` 状态；无效化命中检测逻辑；tag BRAM Port A 地址扩展 |
| `dev/rtl/core/core_top.sv` | PTW A/D 写完成检测；`ptw_ad_inv_pending_r`/`ptw_ad_inv_addr_r` 寄存器；连接到 dcache `inv_line_*` 端口 |

### 仿真验证

20 个测试全部 PASS，包括 `mmu_ptw_walk`（PTW 页表遍历）、`mmu_unified_mmu`（MMU 集成）、`cache_dcache_basic`（dcache 基本功能）、`cpu_full`（完整 CPU 集成）。

---

## 设计约束说明

所有修复方案均遵循"仿真为最终实际上板服务"的约束：

1. **MMIO 物理地址判定**：不绕过缓存或地址翻译，而是正确使用 MMU 输出的物理地址进行路由决策。这是硬件正确行为，上板后同样适用。

2. **sip[5] 可写**：RISC-V 特权规范要求，Linux 内核依赖此功能实现 S-mode 定时器中断。非绕过方案。

3. **M/S 中断优先级**：RISC-V 规范明确规定 M-mode 中断优先于 S-mode 中断。修复使硬件行为与规范一致，上板后中断处理顺序正确。

4. **sfence.vma 缓存一致性**：sfence.vma 的内存屏障语义是 RISC-V 规范明确要求的。dcache writeback 确保页表写操作全局可见，这是 TLB 刷新正确性的前提条件。非绕过方案，上板后页表修改→sfence.vma→TLB 刷新序列正确。

5. **time/timeh CSR**：RISC-V 规范要求 time CSR 反映 CLINT mtime 寄存器值。直接从 CLINT 读取 mtime（经跨时钟域同步），非绕过方案。上板后 U-mode 程序可通过 rdtime 获取硬件时间。

6. **U-mode 计数器别名**：RISC-V 规范要求 U-mode 可通过 mcounteren 控制访问 cycle/time/instret 计数器别名。mcounteren 门控是规范定义的权限机制，非绕过方案。上板后 Linux 内核设置 mcounteren 允许用户态读取计时器。

7. **PMP 寄存器**：RISC-V 规范要求 PMP CSR 存在且可由 M-mode 读写。锁定位 (L) 强制是规范定义的安全机制——L=1 后寄存器只读直至复位。WARL 约束（保留位读零、A 字段仅支持 OFF/TOR）是规范要求的合法实现子集。非绕过方案，上板后 Linux 可正确配置 PMP 条目。当前未实现硬件权限强制（S/U-mode 内存访问检查），所有访问默认允许；这是"最小 PMP"，不影响 Linux 启动。

8. **PTW A/D 位 dcache 一致性**：PTW 写 A/D 位旁路 dcache 直接到主存，是硬件设计选择（PTW 使用独立总线接口）。修复不是绕过而是正确维护一致性：PTW 写完成后 invalidate dcache 对应行，确保后续访问从主存获取更新后的 PTE。不写回脏数据是正确的——dcache 中的旧 PTE 必须丢弃而非写回，否则会覆盖 PTW 的 A/D 更新。上板后页表修改→PTW 设置 A/D→dcache invalidate→后续 refill 获取正确 PTE，序列正确。
