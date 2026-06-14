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

## 设计约束说明

所有修复方案均遵循"仿真为最终实际上板服务"的约束：

1. **MMIO 物理地址判定**：不绕过缓存或地址翻译，而是正确使用 MMU 输出的物理地址进行路由决策。这是硬件正确行为，上板后同样适用。

2. **sip[5] 可写**：RISC-V 特权规范要求，Linux 内核依赖此功能实现 S-mode 定时器中断。非绕过方案。

3. **M/S 中断优先级**：RISC-V 规范明确规定 M-mode 中断优先于 S-mode 中断。修复使硬件行为与规范一致，上板后中断处理顺序正确。
