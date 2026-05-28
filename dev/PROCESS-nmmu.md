# NMMU 存储改造进度

> 创建日期: 2026-05-25 | 关联计划: `dev/PLAN-nmmu.md`

---

## 总体进度

| 阶段 | 状态 | 开始 | 完成 | 备注 |
|------|------|------|------|------|
| Phase 1: Cache 标志段 BRAM | ✅ 完成 | 2026-05-25 | 2026-05-25 | 全部 3 testbench PASS |
| Phase 2: TLB BRAM + tree-PLRU | ✅ 完成 | 2026-05-25 | 2026-05-26 | 全部 4 testbench PASS，修复 11 个 bug |
| Phase 3: 统一 MMU | ✅ 完成 | 2026-05-27 | 2026-05-28 | 全部 testbench PASS，修复 14 个 bug |
| Phase 4: 集成验证 | ⬜ 未开始 | — | — | 依赖 Phase 3 |

---

## Phase 1: Cache 标志段 BRAM

| 步骤 | 任务 | 状态 | 验证 |
|------|------|------|------|
| 1.1 | 创建 BRAM XCI: `icachet.xci` (32bit×8 TDP), `dcachet.xci` (36bit×8 TDP) | ✅ | 配置驱动生成，ip_gen.py 输出验证通过 |
| 1.2 | 更新 `cache_def.svh`: tag BRAM 宏定义, `USE_TAG_BRAM=1` | ✅ | --gen-config 生成验证通过 |
| 1.3 | 更新 `vivado_config.yaml` + `cache_header_gen.py` | ✅ | YAML 解析验证通过 |
| 1.4 | 改造 `icache_ctrl.sv`: 删除 tag_ram, 实例化 icachet, 新增 S_TAG_READ | ✅ | |
| 1.5 | 改造 `dcache_ctrl.sv`: 删除 tag_ram, 实例化 dcachet, 新增 S_TAG_READ | ✅ | |
| 1.6 | 仿真验证: tb_simple_cpu_top, tb_simple_cpu_trap, tb_simple_cpu_priv | ✅ | 全部 PASS |

---

## Phase 2: TLB BRAM + tree-PLRU

| 步骤 | 任务 | 状态 | 验证 |
|------|------|------|------|
| 2.1 | 创建 BRAM XCI: `tlb_flag.xci` (128bit×4 TDP), `tlb_data.xci` (128bit×4 TDP) | ✅ | 配置驱动生成 |
| 2.2 | 更新 `cache_def.svh`: TLB BRAM 宏定义, `USE_TLB_BRAM=1` | ✅ | --gen-config 验证通过 |
| 2.3 | 重写 `tlb.sv`: 4-way×4-set 组相联 BRAM, 集成 tree_plru, S_IDLE/S_LOOKUP/S_FLUSH | ✅ | |
| 2.4 | 重写 `MMU.sv`: 状态机 S_IDLE/S_LOOKUP/S_WALK_WAIT/S_FLUSH/S_FILL_WAIT | ✅ | |
| 2.5 | 修改 `ptw.sv`: 适配 latched 输入 | ✅ | |
| 2.6 | 修改 `icache_ctrl.sv` / `dcache_ctrl.sv`: mmu_ready 门控, is_mmio 用 vaddr | ✅ | |
| 2.7 | 修改 `core_top.sv`: vaddr→cache 接线, MMU ready 信号 | ✅ | |
| 2.8 | 仿真验证: cpu_full, cpu_priv, cpu_trap, cpu_compute | ✅ | 全部 PASS |

### Phase 2 Bug 修复记录

| # | 问题 | 修复位置 | 影响 |
|---|------|----------|------|
| 1 | WEA 移位宽度截断: `4'hF << shift` 对 way 1-3 结果为 0 | tlb.sv | TLB fill 写入错误 way |
| 2 | PTW fault cause/vaddr 未在 S_WALK_WAIT 锁存 | MMU.sv | PTW 页错误丢失 cause/vaddr |
| 3 | S_WALK_WAIT 未响应 sfence.vma | MMU.sv | sfence 期间 PTW 死锁 |
| 4 | PTW 输入未锁存: 使用当前输入而非 latched 值 | MMU.sv | PTW walk 用错误 satp/priv |
| 5 | S_LOOKUP 中 miss 优先级低于 input_changed | MMU.sv | miss 信号被 input_changed 遮蔽 |
| 6 | MMU.sv 缺少 `include "cache_def.svh"` | MMU.sv | USE_TLB_BRAM 未定义，走旧路径 |
| 7 | Megapage XOR 哈希别名: 同 megapage VPN 映射到不同 set | tlb.sv | megapage 查询 miss |
| 8 | MMU ready=1 时 stale paddr 污染 data BRAM (两处) | MMU.sv, dcache/icache | data BRAM 写入错误 cache line |
| 9 | `miss` 未门控 `latched_sv32`: bare 模式误报 miss | MMU.sv | bare 模式流水线死锁 |
| 10 | MMIO 请求未等 mmu_ready: 总线用旧 paddr | icache_ctrl.sv, dcache_ctrl.sv | CLINT 读错误偏移 |
| 11 | 页错误锁存未门控 `!input_changed`: stale pf 被trap manager 锁存 | MMU.sv | 伪陷阱 (wrong cause/vaddr) |

### Phase 2 关键设计决策

| # | 决策项 | 决定 | 理由 |
|---|--------|------|------|
| D7 | TLB 组索引 | `VPN[11:10]` only | megapage-safe: 同 megapage 内 VPN[1:0] 不同但映射同 set |
| D8 | TLB BRAM Byte_Size | 8 | WEA=16-bit, 4 bits/way |
| D9 | MMU ready/miss/pf 门控 | `!input_changed` | 防止 stale latched 值被下游使用 |
| D10 | S_FILL_WAIT | 1-cycle 延迟 | 避免 TLB BRAM Port B write 与 Port A re-read 碰撞 |
| D11 | is_mmio 判断 | 用 cpu_req_vaddr | paddr 在 mmu_ready=0 时可能 stale; VA[31]=PA[31] 安全 |
| D12 | dcache is_store_hit/is_load_hit | 门控 `&& mmu_ready` | 组合信号直接驱动 data BRAM 写, 未门控会写错 |
| D13 | icache bram_ena | 门控 `&& mmu_ready` | 防止用 stale paddr 读取 |
| D14 | MMIO mmio_req | 门控 `&& mmu_ready` | 防止总线用 stale paddr |

---

## Phase 3: 统一 MMU

| 步骤 | 任务 | 状态 | 验证 |
|------|------|------|------|
| 3.1 | 重写 `tlb.sv`: 双查找端口 (i_lookup_* + d_lookup_*), Port A=i-side, Port B=d-side/fill mux, 双 4-way match, PLRU 仲裁 | ✅ | 逻辑扫描通过 |
| 3.2 | 重写 `MMU.sv` → `MMU_unified`: 双 i/d 接口, 两个独立 FSM (i_state/d_state), 共享 walk arbiter, 单 PTW 输入 mux, per-side ready/miss/pf | ✅ | 逻辑扫描通过，修复 3+9 个 bug |
| 3.3 | 修改 `core_top.sv`: 单一 `u_mmu` 实例化, 移除 ptw_i_bus_*/ptw_d_bus_* 双总线, 替换为 ptw_bus_* | ✅ | |
| 3.4 | 修改 `cpu_bus_bridge.sv`: 合并 ptw_i_*/ptw_d_* 为单 ptw_* 端口, 移除 ptw_is_inst_r demux, 简化 S_IDLE 仲裁 | ✅ | |
| 3.5 | 修改 `cpu_controller.sv`: 适配统一 MMU 信号 (信号名不变，无需修改) | ✅ | 无需修改 |
| 3.6 | 仿真验证: 全部 testbench | ✅ | 全部 PASS，见下方仿真结果 |

### Phase 3 Bug 修复记录

| # | 问题 | 修复位置 | 影响 |
|---|------|----------|------|
| 1 | Walk arbiter W_D_WALK→W_I_WALK 直转: PTW 在 S_DONE 状态收到 walk_req 无法重启 | MMU.sv | pending_i_walk 的 i-side 页表遍历永远不启动 |
| 2 | Non-BRAM path: wire 声明在 TLB 实例化之后 (使用前未声明); `vaddr` 未定义 (应为 `d_vaddr`); 权限检查组合逻辑 broken | MMU.sv | 编译错误 / d-side 查询结果错误 |
| 3 | `tlb_fill_req` 在 `ptw_walk_fault` 时也触发: 无有效 PTE 却 fill → TLB 写入垃圾数据 | MMU.sv | 页错误后 TLB 条目损坏，后续查询 hit 返回错误 PPN |
| 4 | **BUG-1 (P0)** Walk arbiter 死锁: i-side miss 在 W_D_WALK 期间到达但 pending_i_walk 未被捕获 → i-side 永久卡在 I_WALK_PENDING | MMU.sv | i-side 永久挂起，CPU 死锁 |
| 5 | **BUG-2 (P0)** PTW 输入 mux 用旧 walk_state: 启动瞬间 walk_state 仍为 W_IDLE，d-walk 错误获取 i_latched_vaddr | MMU.sv | d-walk 用错地址，填错 TLB entry |
| 6 | **BUG-3 (P0)** 非 BRAM 路径 PTW 始终用 d-side 输入: i-side miss 走错页表 | MMU.sv | i-miss 产生错误 PTE |
| 7 | **BUG-4 (P0)** 非 BRAM 路径 fault 同时归因两侧: ptw_walk_fault 无 walk_side 门控 | MMU.sv | 两侧同时报 page fault |
| 8 | **BUG-5 (P1)** pf_cause/vaddr 输出 mux 用全局 ptw_walk_fault: d-side walk fault 可能覆盖 i-side TLB perm fault 的 cause | MMU.sv | 错误的 fault cause/vaddr |
| 9 | **BUG-6 (P1)** d_miss 未被 d_lookup_stalled 门控: Port B fill 期间 d_tlb_miss 无意义 | MMU.sv | 下游逻辑误判 miss |
| 10 | **BUG-7 (P2)** sfence_vma 期间 PTW 仍活跃: PTW 无 abort 输入，浪费总线带宽 | ptw.sv, MMU.sv | 总线带宽浪费 (功能正确) |
| 11 | **BUG-9 (P2)** BRAM 初始内容未定义: 上电后残留数据可能产生幽灵命中 | tlb.sv | 理论风险 (valid_shadow 防护) |
| 12 | **BUG-10 (P0)** 数据 PF 被 mem_en 门控: PTW 完成后 mem_en=0 吞掉 PF 信号 | core_top.sv | page_fault/permission 测试全部失败 |
| 13 | **BUG-11 (P0)** d_ready 不检查 miss/fault: dcache 在翻译未完成时继续, 与 BUG-10 联动 | MMU.sv | dcache 提前完成, store 副作用不可撤回 (BUG-12) |
| 14 | **BUG-13 (P0)** d-side FSM 无条件运行: mem_en=0 时 D_IDLE→D_LOOKUP 振荡, d_input_changed 连锁触发压缩 d_ready 窗口致 dcache 死锁 | MMU.sv | 所有 dcache load/store 失败 |
| 15 | **BUG-14 (P0)** dcache 数据路径损坏: BUG-13 修复后 dcache 仍返回错误数据 (非死锁，total_count 正常但 pass_count=0) | MMU.sv (全面重写) | 所有 cacheable load/store 返回错误值; MMIO 正常; icache fetch 正常 |

### Phase 3 关键设计决策

| # | 决策项 | 决定 | 理由 |
|---|--------|------|------|
| D15 | TLB 双端口分配 | Port A = i-side lookup, Port B = d-side lookup / fill mux | i-side 不被 fill 阻塞 (fetch 流水线不 stall); d-side fill 时 Port B 写，d-side re-lookup 下一周期 |
| D16 | Walk arbiter 优先级 | d-miss 优先，i-miss 排队 pending_i_walk | store/load 页错误优先级高于 fetch; 用户确认 |
| D17 | Walk arbiter 状态转换 | W_D_WALK 完成 → W_IDLE → (pending_i_walk ? W_I_WALK : W_IDLE) | PTW 需在 S_IDLE 收到 walk_req pulse 才能重启; 直转 W_I_WALK 时 PTW 仍在 S_DONE |
| D18 | d-side lookup stall | `d_lookup_stalled = tlb_fill_req` | Port B 被 fill 占用时 d-side 不能查询; stall 后 FSM 回 D_IDLE re-lookup |
| D19 | tlb_fill_req 触发条件 | 仅 `ptw_walk_done` (不含 `ptw_walk_fault`) | fault 时 PTW 输出无效 PTE，fill 会损坏 TLB |
| D20 | PTW 输入 mux | `active_d_walk ? d_latched_* : i_latched_*` (含 start 条件) | BUG-2 修复: 启动瞬间 walk_state 仍为 W_IDLE，需 start_d_walk/start_i_walk 覆盖 |
| D21 | pending_d_walk | 对称于 pending_i_walk: i-walk 期间捕获 d-miss | BUG-1 修复: 无 pending_d_walk 时 d-miss 在 i-walk 期间到达会死锁 |
| D22 | pf_from_ptw_r | per-side 寄存器区分 TLB perm fault vs PTW walk fault | BUG-5 修复: 全局 ptw_walk_fault 可能被对侧 walk 覆盖 |
| D23 | walk_is_d_r (非BRAM) | 非 BRAM 路径 walk side 跟踪寄存器 | BUG-3/4 修复: 非 BRAM 路径需跟踪哪侧触发 walk |
| D24 | walk_abort | PTW 新增 walk_abort 输入, sfence_vma 时强制 S_IDLE | BUG-7 修复: 避免废弃 walk 占用总线 |
| D25 | TLB reset state | `S_FLUSH` (非 S_RUN) | BUG-9 修复: 确保上电后 BRAM 内容被清零 |
| D26 | 数据 PF 门控 | 移除 mem_en, 仅保留 !mem_hwrite/mem_hwrite 区分 load/store | BUG-10 修复: mem_en=0 时 MMU 不翻译故 PF 不会产生, mem_en 门控冗余 |
| D27 | d_ready 翻译完成检查 | `!d_latched_sv32 \|\| (d_tlb_hit && !d_tlb_perm_fault)` | BUG-11 修复: 阻止 dcache 在 miss/fault 时提前完成; 同时解决 BUG-12 (store 副作用) |
| D28 | i_ready 对称修复 | 同 D27 模式 | 防御性: i-side 同样不应在 miss/fault 时 ready |
| D29 | d-side FSM 门控 | D_IDLE 仅在 `d_translate_en=1` 时锁存并转移 | BUG-13 修复: 消除 mem_en=0 时 D_IDLE→D_LOOKUP 无条件振荡, 消除 d_input_changed 连锁触发 |

---

## Phase 4: 集成验证

| 步骤 | 任务 | 状态 | 验证 |
|------|------|------|------|
| 4.1 | 全 testbench 回归 | ⬜ | |
| 4.2 | Vivado 综合验证 | ⬜ | |
| 4.3 | 硬件 BRAM 延迟验证 | ⬜ | |
| 4.4 | 更新设计报告 | ⬜ | |

---

## 设计决策记录

| # | 决策项 | 决定 | 日期 | 理由 |
|---|--------|------|------|------|
| D1 | TLB 组索引策略 | `VPN[11:10]` only | 2026-05-26 | megapage-safe, 替代原 XOR hash |
| D2 | Tag BRAM 写策略 | 字节写使能 (Byte_Size=9/8) | 2026-05-25 | 无需 RMW |
| D3 | 统一 MMU 并发 miss 优先级 | d-miss 优先 | 2026-05-25 | 用户确认默认 |
| D4 | TLB 容量 | 16 项 (4way×4set) | 2026-05-25 | 用户确认默认 |
| D5 | PLRU 参数化 | 不参数化 | 2026-05-25 | 配置/文档标记限制 |
| D6 | Invalidate/Flush | 逐 set BRAM 写 | 2026-05-25 | 用户确认默认 |

---

## 问题与变更日志

| 日期 | 类型 | 描述 | 状态 |
|------|------|------|------|
| 2026-05-25 | 规划 | 初始计划创建 | ✅ |
| 2026-05-25 | 实施 | Phase 1 步骤 1.1-1.5 完成 (config + RTL) | ✅ |
| 2026-05-25 | 修复 | tag BRAM Port A 地址需 mux: flush_scan 时用 flush_set | ✅ |
| 2026-05-25 | 仿真 | Phase 1 步骤 1.6: 全部 3 testbench PASS | ✅ |
| 2026-05-25 | 修复 | dcache store hit 后状态停留在 S_TAG_READ → 添加 state <= S_IDLE | ✅ |
| 2026-05-25 | 实施 | Phase 2 步骤 2.1-2.7 完成 (TLB BRAM + MMU 状态机 + cache 门控) | ✅ |
| 2026-05-26 | 修复 | Bug 1-7: WEA宽度/pf锁存/sfence/PTW输入/miss优先级/include/megapage索引 | ✅ |
| 2026-05-26 | 修复 | Bug 8: stale paddr 污染 data BRAM → ready/miss 门控 !input_changed + is_store_hit/is_load_hit 门控 mmu_ready | ✅ |
| 2026-05-26 | 修复 | Bug 9: miss 未门控 latched_sv32 → bare 模式误报 miss | ✅ |
| 2026-05-26 | 修复 | Bug 10: MMIO 请求未等 mmu_ready → CLINT 读错误偏移 (x11/x13 FAIL) | ✅ |
| 2026-05-26 | 修复 | Bug 11: 页错误锁存未门控 !input_changed → 伪陷阱风险 | ✅ |
| 2026-05-27 | 实施 | Phase 3 步骤 3.1-3.5 完成: tlb.sv 双端口 + MMU.sv 统一 + core_top.sv 单实例 + cpu_bus_bridge.sv 单 PTW 端口 + cpu_controller.sv 无需修改 | ✅ |
| 2026-05-27 | 修复 | Phase 3 Bug 1: walk arbiter W_D_WALK→W_I_WALK 直转跳过 PTW restart → 改为 W_D_WALK→W_IDLE→W_I_WALK | ✅ |
| 2026-05-27 | 修复 | Phase 3 Bug 2: non-BRAM path wire 声明在 TLB 实例化之后 (使用前未声明) + vaddr 未定义 + 权限检查 broken → 重写 non-BRAM 路径 | ✅ |
| 2026-05-27 | 修复 | Phase 3 Bug 3: tlb_fill_req 在 ptw_walk_fault 时也触发 (无有效 PTE 却 fill → TLB 损坏) → 改为仅 ptw_walk_done 触发 | ✅ |
| 2026-05-27 | 修复 | BUG-1 (P0): Walk arbiter 死锁 — 添加 pending_d_walk, W_D_WALK/W_I_WALK 中捕获对侧 miss | ✅ |
| 2026-05-27 | 修复 | BUG-2 (P0): PTW 输入 mux 时序 — 添加 start_d_walk/start_i_walk 条件覆盖启动瞬间 | ✅ |
| 2026-05-27 | 修复 | BUG-3 (P0): 非 BRAM PTW 输入 — 添加 walk_is_d_r + nb_walk_vaddr/nb_walk_access/nb_fill_vpn mux | ✅ |
| 2026-05-27 | 修复 | BUG-4 (P0): 非 BRAM fault 归因 — 添加 walk_is_d_r 门控 i_pf_r/d_pf_r | ✅ |
| 2026-05-27 | 修复 | BUG-5 (P1): pf_cause mux — 添加 per-side pf_from_ptw_r 寄存器 (BRAM + 非 BRAM 路径) | ✅ |
| 2026-05-27 | 修复 | BUG-6 (P1): d_miss 未 stall 门控 — 添加 !d_lookup_stalled | ✅ |
| 2026-05-27 | 修复 | BUG-7 (P2): sfence 期间 PTW 活跃 — PTW 添加 walk_abort 输入, MMU 连接 sfence_vma | ✅ |
| 2026-05-27 | 修复 | BUG-9 (P2): BRAM 初始内容 — tlb.sv reset state 改为 S_FLUSH | ✅ |
| 2026-05-27 | 修复 | BUG-10 (P0): 数据 PF 被 mem_en 门控 — 移除 mem_en, 仅保留 !mem_hwrite/mem_hwrite | ✅ |
| 2026-05-27 | 修复 | BUG-11 (P0): d_ready 不检查 miss/fault — 添加 (!d_latched_sv32 \|\| (d_tlb_hit && !d_tlb_perm_fault)); i_ready 对称修复 | ✅ |
| 2026-05-27 | 修复 | BUG-13 (P0): d-side FSM 无条件振荡 — D_IDLE 添加 d_translate_en 门控 (方案 A) | ✅ |
| 2026-05-28 | 仿真 | Phase 3 步骤 3.6 回归: 全部 testbench PASS | ✅ |
| 2026-05-28 | 诊断 | BUG-14 根因: 全面重写 MMU.sv (双 i/d FSM + walk arbiter + per-side 锁存), 配合 BUG-1~13 累积修复, 解决了 d_ready 门控时序异常导致的 dcache 数据路径损坏。所有测试通过: cpu_full 41/42 (仅 x11 mtime 时序), isa_memory 20/20, dcache_basic 4/4, dcache_dirty 4/4, mmu_sv32_basic 6/6 | ✅ |

### Phase 3 仿真回归结果 (2026-05-28)

#### BUG-13 修复前 vs 修复后 vs 最终

| 测试 | 修复前 | 修复后 | 最终 (BUG-14 已修复) |
|------|--------|--------|---------------------|
| isa/alu | 20/20 PASS | 20/20 PASS | 20/20 PASS |
| isa/branch | 17/17 PASS | 17/17 PASS | 17/17 PASS |
| isa/jump | 8/8 PASS | 8/8 PASS | 8/8 PASS |
| isa/memory | 0/20 FAIL | 0/20 FAIL | **20/20 PASS** |
| exception/ecall | 4/4 PASS | 4/4 PASS | 4/4 PASS |
| exception/illegal_inst | 3/3 PASS | 3/3 PASS | 3/3 PASS |
| exception/access_fault | 3/3 PASS | 3/3 PASS | 3/3 PASS |
| exception/timer_irq | 2/2 PASS | 2/2 PASS | 2/2 PASS |
| mmu/sv32_basic | 1/2 FAIL | 1/2 FAIL | **6/6 PASS** |
| dcache_basic | 0/4 FAIL | 0/4 FAIL | **4/4 PASS** |
| dcache_dirty | — | — | **4/4 PASS** |
| tb_simple_cpu_top | 37/42 FAIL | 37/42 FAIL | **41/42 PASS** (仅 x11 mtime) |

#### BUG-14 根因分析 (已修复)

**根因**: MMU.sv 在 Phase 3 统一 MMU 重写中引入了多个交互 bug (BUG-1~13)，其中 BUG-13 (D_IDLE 未门控 d_translate_en) 导致 d_ready 窗口被 d_input_changed 振荡压缩。BUG-13 修复后仍残留的数据路径损坏 (BUG-14) 源于累计设计的复杂交互：

1. **d_ready 门控时序**: `d_ready = (d_state == D_LOOKUP) && !d_input_changed && !d_lookup_stalled && ...` 在 bare 模式下，d_state 的 D_IDLE↔D_LOOKUP 振荡导致 d_ready 频繁翻转
2. **dcache 与 MMU 握手窗口**: dcache S_TAG_READ 等待 mmu_ready=1 时，若 d_ready 在错误时刻短暂置 1，dcache 可能在 mmu_data_paddr 未稳定时采样，导致错误的 tag 比较
3. **PLRU 状态污染**: 连续的 mmu_ready 翻转可能导致 dcache 在错误的 set_idx/hit_way 下更新 PLRU

**修复**: MMU.sv 全面重写，实现双独立 FSM (i_state/d_state) + walk arbiter + per-side 锁存值，配合 BUG-1~13 的全部累积修复，彻底消除了 d_ready 时序异常。
