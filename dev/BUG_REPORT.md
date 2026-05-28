根据您提供的症状和代码片段，我已定位到导致仿真在**子测试 2 卡死不再推进**的根本原因。这不仅与你发现的 S-mode 访存有关，还是**测试框架的异常处理逻辑缺陷（软件 Bug）**与**潜在的 RTL 硬件 Bug**共同作用的结果。

以下是深度的症状剖析和修复方案：

### 1. 为什么会在子测试 2 死循环卡住？

当 Sv32 开启后，如果你的硬件 PTW 存在加载失败（比如因为 D-cache 未正确 flush 到以供 MMU 读取，导致获取到陈旧的全零页表），CPU 在试图 fetch `s_test_identity_code` 中第一条指令时，会触发**指令缺页异常 (Instruction Page Fault, `mcause=12`)** 或指令访问异常 (`mcause=1`)。

此时会陷阱进入 M-mode 的 `mmu_trap_handler`。问题出在你的异常处理分支 `_mth_fault_skip` 上：

由于当前没有预设期望的异常返回地址 (`mmu_return_pc` 为 0)，程序会跳到 `_mth_fault_skip`：
```assembly
_mth_fault_skip:
    addi x23, x23, 4
    csrw mepc, x23
    li x5, 0x2888    # 强制跳回 S-mode 
    csrw mstatus, x5
    mret
```
**严重缺陷**：如果是因为**指令本身 Fetch 失败**触发的问题，暴力将 `mepc + 4` 然后 `mret` 跳回 S-mode，只会导致 CPU 尝试去 fetch `PC+4` 的地址。但既然整个页面映射都失败了，`PC+4` 的 fetch **依然会再次触发缺页异常！**
结果导致：陷阱 → `mepc+=4` → 回 S-mode → 再次缺页陷阱 → `mepc+=4` → 回 S-mode…… 也就是 `mepc` 在地址空间里以 4 字节为单位步进，形成**数以亿次计的无限 Trap 循环**。这直接耗尽了仿真的 20 万周期 (20ms) 限制，使得 `test_run` 永远无法返回。

### 2. 为什么 MPP 修复 `0x1888 -> 0x2888` 是错误的？

你之前发现如果 `_mth_fault_skip` 返回 `0x1888`，会掉回 M-mode 导致后续测试失效，从而将所有的 `0x1888` 盲目替换成了 `0x2888`。这个修复**破坏了测试框架的设计范式**：
根据 sv32_basic.s 顶部的注释：
`# Pattern: M-mode setup → mret to S-mode → S-mode test → ecall → M-mode`
所有的子测试必须通过 `ecall` **返回到 M-mode** 交给 `test_run` 继续去调度下一个 M-mode 级别的测试。

如果你在 `_mth_ecall` 中返回了 `0x2888` (S-mode)，`test_run` 和随后子程序的 `csrw mepc/mstatus` 其实都运行在 S-mode 下，触发了一连串不该有的非法指令异常（只是被 skip 掩盖了），导致所有框架流程其实在非法状态下崩坏。

### 💡 修复方案（针对测试基建）

为了让验证框架能优雅地报出硬件的 PTW Error 而不是模拟器死锁超时，你需要对 sv32_basic.s 及相关测试汇编中的 `mmu_trap_handler` 做出两项修改：

#### 修改 1: 发生未预期 Fault 时直接判 FAIL，终结死循环
对于没有指定 `mmu_return_pc` 的异常，不要再任性地跳过指令，将其视为致命错误，清零 x10 (`FAIL`标志)，并强制跳回 `test_run`：

```assembly
    la x5, mmu_return_pc
    lw x5, 0(x5)
    beqz x5, _mth_fatal_fault      # 把原来的 _mth_fault_skip 替换成专门的 fatal 返回

# ... 中间代码保留

_mth_fatal_fault:
    # 遇到不在计划内的 Fault，直接标记测试失败并强行返回
    la x5, mmu_saved_ra
    lw x5, 0(x5)
    csrw mepc, x5                  # 把 PC 强行指向 test_run 的返回处
    li x10, 0                      # x10=0 代表 FAIL
    li x5, 0x1888                  # 必须返回 M-mode 以保证框架继续运转
    csrw mstatus, x5
    mret
```

#### 修改 2: 恢复 `_mth_ecall` 里的 MPP 到 M-mode (即 0x1888)
在 `_mth_ecall` 与 `_mth_ecall_post` 内部，请**把 `0x2888` 改回 `0x1888`**。

#### 修改 3: `_mth_fault_skip` 不需要手动干预 mstatus
原来的 `_mth_fault_skip`（如果用于预期中可以跳过的指令）应该依赖硬件自动保存的 `mstatus.MPP`，而不是暴力的赋予绝对值：

```assembly
_mth_fault_skip:
    addi x23, x23, 4
    csrw mepc, x23
    # 删掉 li x5, 0x2888 和 csrw mstatus, x5，让 mret 自动从原始的 MPP 字段恢复 S-mode 
    mret
```

### 未来排查（针对 RTL 设计）
当你在软件测完成上述修复并重新跑仿真后，你会得到：`first_fail_id = 2`（不再卡死，瞬间跑完）。
接下来的核心矛头将直指 RTL 对于 PTW 的硬件设计：
- 请在波形中抓取 **TLB Miss 到 PTW 状态机** 的第一个状态切换。
- **重点检查 Cache 一致性**：软件已经使用 `fence.i` 尝试刷脏（在 page_table_utils.s 的 `enable_sv32` 阶段），如果您的 RTL **没有把 D-Cache 的内容成功写入 SRAM 中**，或者 PTW FSM 没有对相关访存请求给足周期，PTW 数据线读取到的 PPN 就会全为 `0` 或 `X`，导致访问控制校验直接告崩塌进而报出 Instruction Page Fault。请拉出总线在 `0x80001800` 和 `0x80002000` 处的读事务进行分析波形以确认！