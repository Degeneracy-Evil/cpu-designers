# NMMU 存储改造进度

> 创建日期: 2026-05-25 | 关联计划: `dev/PLAN-nmmu.md`

---

## 总体进度

| 阶段 | 状态 | 开始 | 完成 | 备注 |
|------|------|------|------|------|
| Phase 1: Cache 标志段 BRAM | ✅ 完成 | 2026-05-25 | 2026-05-25 | 全部 3 testbench PASS |
| Phase 2: TLB BRAM + tree-PLRU | ✅ 完成 | 2026-05-25 | 2026-05-26 | 全部 4 testbench PASS，修复 11 个 bug |
| Phase 3: 统一 MMU | ⬜ 未开始 | — | — | 依赖 Phase 2 |
| Phase 4: 集成验证 | ⬜ 未开始 | — | — | 依赖全部 |

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
| 3.1 | 重写 `MMU.sv` → `MMU_unified`: 双查找接口, 单 PTW, 并发 miss 排队 | ⬜ | |
| 3.2 | 修改 `core_top.sv`: 单一 MMU 实例化 | ⬜ | |
| 3.3 | 修改 `cpu_bus_bridge.sv`: 合并 PTW 总线 | ⬜ | |
| 3.4 | 修改 `cpu_controller.sv`: 适配统一 MMU 信号 | ⬜ | |
| 3.5 | 仿真验证: 全部 testbench | ⬜ | |

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
| 2026-05-26 | 仿真 | Phase 2 步骤 2.8: cpu_full/cpu_priv/cpu_trap/cpu_compute 全部 PASS | ✅ |
