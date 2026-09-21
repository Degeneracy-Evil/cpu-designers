# CPU 代码简化重构：Control Path / core_top Glue

> 分支：chp  
> 前置阶段：MMU/TLB/PTW 与 Cache/Memory Interface 已完成结构简化。  
> 本文定义 Phase 4：控制路径与 core_top glue 清理。

## 1. 目标

本阶段不修改 CPU 的执行模型，也不改变 ISA、异常或特权级语义。

目标：

1. 让 cpu_controller 只负责指令生命周期控制，不感知 MMU、TLB、Cache、PTW、AXI 内部状态。
2. 将 FENCE.I、SFENCE.VMA 收敛为直接明确的 req/done 协议。
3. 删除 MMU 重构后遗留的 I/D 双路 debug compatibility。
4. 删除 core_top.sv 中已经失去必要性的 glue state / wire。
5. 保留 Linux bring-up 仍然有价值的可观测性。

原则：

> 删除不该存在的 glue，而不是隐藏必要的 glue。

---

## 2. 保持不变的执行模型

当前 CPU 继续采用严格串行控制：

    FETCH
      ↓
    DECODE
      ↓
    EXEC
      ↓
    MEM
      ↓
    WB

并继续保留：

    CSR_ACCESS
    TRAP_ENTER
    TRAP_RETURN
    FENCEI
    SFENCE_VMA

本阶段不引入 pipeline overlap、forwarding、scoreboard、speculation 或 multiple in-flight instruction。

stage register 与 PC update 的基本结构不变。

---

# Phase 4A：Controller 去除 MMU/Cache 感知

## 3. Controller 只看 stage completion

当前 cpu_controller.sv 仍直接接收：

    mmu_inst_miss
    mmu_data_miss
    mem_data_access

这些属于 memory subsystem 内部状态，不应该进入顶层指令控制器。

在当前 blocking 架构中：

- translation miss 时 if_done / mem_done 自然保持 0；
- PTW walk、cache miss、AXI wait 都由下层模块阻塞；
- controller 只需要等待当前 stage completion。

因此删除上述三个输入。

FETCH 目标逻辑：

    FETCH:
        if fetch_fault_pending:
            TRAP_ENTER
        else if if_done:
            DECODE
        else:
            FETCH

MEM 目标逻辑：

    MEM:
        if data_fault_pending:
            TRAP_ENTER
        else if mem_done:
            WB
        else:
            MEM

MMU miss、PTW walk、Cache miss、AXI wait 不再作为 controller 概念存在。

---

## 4. Fault pending 聚合

Controller 不需要知道 fault 类型。

在 core_top 聚合：

    fetch_fault_pending =
        inst_access_fault_pending ||
        inst_page_fault_pending

    data_fault_pending =
        data_access_fault_pending ||
        data_page_fault_pending

Controller 只接：

    fetch_fault_pending
    data_fault_pending

具体的 access fault / page fault、cause、tval、fault address、delegation 继续由 Trap/CSR subsystem 处理。

---

## 5. 删除无用 decode 输入

实现时确认 controller 当前已经不使用的输入，并删除其 port / wiring。

预计包括：

    dec_is_branch
    dec_illegal
    dec_is_ecall
    dec_is_ebreak

这些语义已经由 exception_at_decode、exe_is_branch 等更高层结果表达。

保留真正影响 controller 状态流的 decode 信息：

    dec_need_exe
    dec_is_csr
    dec_is_mret
    dec_is_sret
    dec_is_nop_like
    dec_is_fencei
    dec_is_sfence_vma

不要为了缩减端口重新复制 decode 逻辑到 controller 内部。

---

# Phase 4B：FENCE.I 直接握手

## 6. 删除 core_top 的重复状态

当前 ICache 已能够处理 held invalidate request，并通过内部 one-shot/block 防止同一个请求重复执行。

因此 core_top 不再需要：

    fencei_icache_inv_sent_r

目标连接：

    controller.fencei_req
            |
            v
    ICache.invalidate_req

    ICache.invalidate_done
            |
            v
    controller.fencei_done

即：

    icache_invalidate_req = fencei_req
    fencei_done = icache_invalidate_done

Controller 在 STATE_FENCEI 中等待 completion。

由于当前 DCache 为 write-through，store 完成时 backing memory 已经可见，因此本实现的 FENCE.I 仍只需要 ICache invalidate。

不要重新引入 DCache flush/writeback。

---

# Phase 4C：SFENCE.VMA 直接握手

## 7. 删除 core_top pulse adapter

当前 core_top 仍有：

    sfence_tlb_flush_sent_r
    sfence_tlb_pulse_sent_r
    sfence_vma_to_mmu_pulse

这些属于旧 MMU 接口留下的 glue。

MMU 改为直接提供：

    sfence_req
    sfence_done

语义：

1. sfence_req 可以保持高电平。
2. MMU 第一次观察到新的 held request 时接受一次。
3. 如果当前有 PTW transaction，先安全 drain 到可 flush 状态。
4. 执行 full TLB flush。
5. 输出一个 sfence_done completion pulse。
6. 在 sfence_req 拉低前，不再次接受同一个请求。

MMU 内部允许使用一个简单 one-shot/block bit。

目标连接：

    controller.sfence_vma_req -> MMU.sfence_req
    MMU.sfence_done -> controller.sfence_vma_done

core_top 不再负责 pulse conversion。

当前实现继续采用：

    SFENCE.VMA -> full TLB flush

不在本阶段增加 rs1/rs2 selective flush。

---

# Phase 4D：统一 MMU Debug

## 8. 删除旧 I/D compatibility debug

MMU 当前已经是：

    single owner
    single request register
    single FSM
    single PTW

因此 debug 也必须反映真实结构。

旧兼容信号例如：

    dbg_pending_i_walk
    dbg_pending_d_walk

    dbg_mmu_i_state
    dbg_mmu_d_state

    dbg_mmu_i_input_changed
    dbg_mmu_d_input_changed

    dbg_mmu_i_latched_vaddr
    dbg_mmu_d_latched_vaddr

    dbg_mmu_i_sv32
    dbg_mmu_d_latched_sv32

尤其 pending_i_walk / pending_d_walk 当前已经恒为 0，应直接删除。

建议统一为少量真实状态：

    dbg_mmu_state
    dbg_mmu_owner
    dbg_mmu_req_vaddr
    dbg_mmu_sv32
    dbg_mmu_tlb_hit
    dbg_mmu_tlb_perm_fault
    dbg_mmu_ptw_active
    dbg_mmu_fault_from_ptw

如果某个 debug 信号没有实际调试价值，可以不保留。

不要重新构造两套 I/D 虚假状态。

---

## 9. Linux bring-up 观测信号继续保留

本阶段不要激进删除：

    IF / ID / EXE / MEM / WB PC
    IF / ID / EXE / MEM / WB instruction

    priv_mode

    trap enter / return
    trap target PC
    cause
    epc
    tval

    satp
    关键 CSR

以及关键 GPR，例如：

    ra
    sp
    tp
    s1
    a0-a7
    s2-s3

原则：

> 删除历史 compatibility debug，但保留能直接回答“CPU 正在执行什么、为什么 trap、地址翻译发生了什么”的 debug。

---

# Phase 4E：core_top Glue Cleanup

## 10. core_top 的职责

core_top.sv 继续作为 composition root。

允许它负责：

- module instantiation；
- stage buses / stage registers；
- PC / privilege sequencing；
- controller wiring；
- MMU / Cache / bus wiring；
- trap/CSR wiring；
- externally useful debug export。

不要求因为文件较长而强行拆成 frontend_wrapper、memory_wrapper、control_wrapper、debug_wrapper。

除非拆分能明确消除逻辑耦合，否则不要为了行数移动代码。

---

## 11. 本阶段可以删除的 glue

实现时检查并删除：

- controller 已不使用的 input wires；
- FENCE.I sent-state；
- SFENCE.VMA pulse/sent-state；
- MMU 旧 I/D debug wires；
- 永远常量的 legacy debug；
- 因上述接口变化产生的中间 alias。

不要删除：

- stage registers；
- PC redirect；
- trap redirect；
- privilege update；
- Cache redirect/discard；
- Linux bring-up 所需观测信号。

---

# Phase 4F：Controller 目标接口

## 12. 建议最终输入

Controller 输入大致收敛为：

    clk
    resetn
    init_sig

    if_done
    id_done
    exe_done
    mem_done
    wb_done

    dec_need_exe
    dec_is_csr
    dec_is_mret
    dec_is_sret
    dec_is_nop_like
    dec_is_fencei
    dec_is_sfence_vma

    exe_is_branch
    exe_need_mem

    exception_at_decode
    fetch_fault_pending
    data_fault_pending
    trap_pending

    fencei_done
    sfence_vma_done

输出：

    if_valid
    id_valid
    exe_valid
    mem_valid
    wb_valid
    csr_valid

    trap_enter_valid
    trap_return_valid
    exe_to_wb

    fencei_req
    sfence_vma_req

    state

Controller 接口中不再出现 MMU、TLB、PTW、Cache、AXI 相关概念。

---

# 实施边界

## 13. 可以修改

主要：

- cpu_controller.sv
- core_top.sv
- MMU.sv 的 sfence/debug 接口
- system_top.sv 中直接受影响的 debug wiring
- 相关 testbench

允许删除旧 debug port，但必须同步修改所有实例化和测试。

---

## 14. 本阶段不要主动重构

不要借本阶段重写：

- cpu_fetch.sv
- cpu_decode.sv
- cpu_execute.sv
- cpu_mem.sv
- cpu_wb.sv
- cpu_trap_csr.sv
- cpu_trap_manager.sv
- cpu_clint.sv
- CSR implementation
- MMU/TLB/PTW translation semantics
- Cache hit/miss/write policy
- AXI bridge transaction semantics
- SoC / MIG / peripheral logic

如果发现真实 correctness bug，单独记录和修复，不扩大本阶段重构范围。

---

# 验证要求

## 15. Controller regression

至少覆盖：

- reset -> FETCH
- normal ALU instruction
- branch taken / not taken
- load
- store
- CSR
- illegal instruction
- ecall
- ebreak
- mret
- sret
- instruction page fault
- instruction access fault
- load/store page fault
- load/store access fault
- interrupt after retirement
- FENCE.I
- SFENCE.VMA

重点确认：

> 去掉 mmu_*_miss 后，MMU/PTW/Cache stall 仍然仅通过 if_done/mem_done=0 正确阻塞 controller。

---

## 16. FENCE regression

FENCE.I：

- held fencei_req 只触发一次 invalidate；
- invalidate completion 后 controller 离开 FENCEI；
- 不重复 invalidate；
- redirect/trap 不产生错误 completion。

SFENCE.VMA：

- held request 只执行一次；
- MMU idle 时正常 full flush；
- PTW active 时先 drain/abort 到安全点再 flush；
- completion 只 pulse 一次；
- request 拉低后下一次 SFENCE 可以重新接受。

---

## 17. Debug interface regression

确认：

- 删除旧 I/D MMU debug 后所有实例化同步；
- system-level simulation 不依赖被删除的恒 0 legacy debug；
- 新 unified debug 至少能看到 owner、state、request VA、TLB hit、PTW active 和 fault source。

---

## 18. 最终回归

本阶段完成后运行：

- SystemVerilog syntax/elaboration；
- controller/unit tests；
- MMU regression；
- Cache/bus regression；
- privilege/trap regression；
- short regression；
- Linux testbench smoke。

完整 regression 通过后冻结 Phase 4。

---

# 后续方向

完成 Phase 4 后，不再以减少行数为目标主动重构 control path。

下一阶段优先做 correctness review：

    Phase 5A: cpu_mem / A-extension review
    Phase 5B: Trap / CSR / privileged architecture review
    Phase 5C: Linux bring-up regression

这些阶段以确认架构语义没有缺口为主，而不是重新设计已经稳定的模块。
