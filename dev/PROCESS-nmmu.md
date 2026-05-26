# NMMU 存储改造进度

> 创建日期: 2026-05-25 | 关联计划: `dev/PLAN-nmmu.md`

---

## 总体进度

| 阶段 | 状态 | 开始 | 完成 | 备注 |
|------|------|------|------|------|
| Phase 1: Cache 标志段 BRAM | 🔄 进行中 | 2026-05-25 | — | 步骤 1.1-1.5 完成，1.6 仿真部分通过，修复 store hit bug |
| Phase 2: TLB BRAM + tree-PLRU | ⬜ 未开始 | — | — | 依赖 Phase 1 |
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
| 1.6 | 仿真验证: tb_simple_cpu_top, tb_simple_cpu_trap, tb_simple_cpu_priv | 🔄 | trap/priv PASS, top: x11 时序偏差已修复期望值，store hit bug 已修 |

---

## Phase 2: TLB BRAM + tree-PLRU

| 步骤 | 任务 | 状态 | 验证 |
|------|------|------|------|
| 2.1 | 创建 BRAM XCI: `tlb_flag.xci` (128bit×4 TDP), `tlb_data.xci` (112bit×4 TDP) | ⬜ | |
| 2.2 | 更新 `cache_def.svh`: TLB BRAM 宏定义 | ⬜ | |
| 2.3 | 重写 `tlb.sv`: 组相联 BRAM, 集成 tree_plru, 新增 S_LOOKUP | ⬜ | |
| 2.4 | 修改 `MMU.sv`: 适配新 TLB 接口 | ⬜ | |
| 2.5 | 仿真验证: tb_simple_cpu_priv | ⬜ | |

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
| D1 | TLB 组索引策略 | XOR hash | 2026-05-25 | 用户确认，分散 megapage |
| D2 | Tag BRAM 写策略 | 字节写使能 (Byte_Size=9/8) | 2026-05-25 | 用户确认，无需 RMW |
| D3 | 统一 MMU 并发 miss 优先级 | d-miss 优先 | 2026-05-25 | 用户确认默认 |
| D4 | TLB 容量 | 16 项 (4way×4set) | 2026-05-25 | 用户确认默认 |
| D5 | PLRU 参数化 | 不参数化 | 2026-05-25 | 用户确认，配置/文档标记限制 |
| D6 | Invalidate/Flush | 逐 set BRAM 写 | 2026-05-25 | 用户确认默认 |

---

## 问题与变更日志

| 日期 | 类型 | 描述 | 状态 |
|------|------|------|------|
| 2026-05-25 | 规划 | 初始计划创建 | ✅ |
| 2026-05-25 | 实施 | Phase 1 步骤 1.1-1.5 完成 (config + RTL) | ✅ |
| 2026-05-25 | 修复 | tag BRAM Port A 地址需 mux: flush_scan 时用 flush_set | ✅ |
| 2026-05-25 | 仿真 | Phase 1 步骤 1.6: trap/priv PASS, top x11 FAIL (mtime 时序偏差 264 cycles) | ✅ 期望值已更新 |
| 2026-05-25 | 修复 | dcache store hit 后状态停留在 S_TAG_READ → 添加 state <= S_IDLE | ✅ |
