# Vivado Orchestrator Bug Report — `tools/vivado_core/` + `tools/vivado_cli.py`

> 审计时间: 2026-05-26
> 审计范围: `tools/vivado_core/` 全部 `.py` 文件 + `tools/vivado_cli.py` + `vivado_config.yaml` + `tasks.yaml`
> 审计方法: 逐文件精读 + 交叉验证 + 实际使用观察
> 代码版本: Python-based Vivado Orchestrator (替代 vivado_do.tcl)

---

## 🔴 HIGH Severity — 实际影响功能的 Bug

### H1: `session.py` — `readline()` 阻塞使 timeout 机制失效

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_core/session.py` | 283-301 | `Session.execute()` |

**问题描述**: `execute()` 方法使用 `readline()` (line 293) 读取 Vivado stdout。`readline()` 是阻塞调用，无超时参数。虽然外层有 elapsed-time 检查 (lines 284-288)，但该检查仅在 `readline()` 返回后才执行。

若 Vivado 输出无换行的部分行后挂起（或缓冲区中只有不完整行），`readline()` 将永久阻塞：
- timeout 检查永远无法触发
- 持有 `self._lock` 的线程永久卡死
- 后续所有 `execute()` 调用因无法获取锁而永久等待

**影响**: 整个 session 不可用，只能手动 kill Vivado 进程。

**建议**: 使用 `select`/`poll` 配合非阻塞读取，或将读取逻辑放入独立线程通过 `queue.Queue.get(timeout=...)` 传递数据。

---

### H2: `operations.py` — 全量 refresh 删除项目目录时 Vivado CWD 在其中

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_core/operations.py` | 476-486 | `Operations.refresh()` |
| `tools/vivado_core/session.py` | 210 | `Session.start_vivado()` |

**问题描述**: `refresh()` 全量重建路径执行 `close_project` + `file delete -force {proj_dir}`。但 Vivado 子进程的 CWD 被设为 `proj_dir` (session.py:210 `cwd=str(self.project_dir)`)。

在 Windows 上，运行中进程的 CWD 目录被文件锁保护，`file delete -force` 失败。

```tcl
# operations.py:479-480 生成的 TCL
catch { close_project }
file delete -force E:/Xprogram/FPGA/cpu-designers/project/cpu_full
```

**实际影响**: **每次 `-refresh` 必现 `error deleting ... permission denied`**。当前靠后续 `create_project -force` 覆盖绕过，但残留文件可能导致状态不一致（旧 IP 目标文件残留、编译缓存错乱）。

**建议**:
1. 删除前先切换 Vivado CWD：`cd [file dirname {proj_dir}]`
2. 或在 refresh 前重启 Vivado 进程（stop + start），确保无文件锁
3. 或使用 `file delete -force` 后检查结果并重试

---

### H3: `vivado_cli.py` — `ops.hw_connect()` 方法不存在

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_cli.py` | 675 | `main()` |
| `tools/vivado_core/operations.py` | — | `Operations` (缺失) |

**问题描述**: CLI 的 `-hw-connect` 处理分支调用 `ops.hw_connect(session)`，但 `Operations` 类未定义 `hw_connect` 方法。

```python
# vivado_cli.py:675
res = ops.hw_connect(session)  # AttributeError: 'Operations' has no attribute 'hw_connect'
```

**影响**: 执行 `python -m tools.vivado_cli -task fpga -hw-connect` 直接崩溃。

**建议**: 在 `Operations` 中实现 `hw_connect()` 方法，或移除 CLI 中的 `-hw-connect` 选项。

---

### H4: `operations.py` — TCL 字符串注入漏洞

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_core/operations.py` | 54-63, 133, 180, 199, 251 等 | 全部 `_tcl_*` 函数 |

**问题描述**: 路径和配置值通过 f-string 直接插入 TCL 脚本。`_tcl_path()` 仅将反斜杠转为正斜杠，**不转义 TCL 元字符**。

TCL 特殊字符：
- `{` `}` — 分组/字典，破坏 f-string 的 `{{ }}` 转义
- `"` — 字符串定界符，截断路径
- `$` — 变量替换，可泄露环境变量
- `[` `]` — 命令替换，**可执行任意 TCL 命令**

```python
# 示例：路径含空格和方括号
proj_dir = "E:/My [Project]/cpu"  # → TCL 执行 [Project] 命令
```

**影响**: 路径含空格（Windows 常见）或特殊字符时，TCL 脚本静默失败或执行非预期命令。

**建议**: 添加 `_tcl_escape()` 函数，将值用双引号包裹并转义 `\`、`"`、`$`、`[`、`]`：

```python
def _tcl_escape(s: str) -> str:
    """Escape a string for safe TCL double-quote interpolation."""
    s = s.replace('\\', '\\\\')
    s = s.replace('"', '\\"')
    s = s.replace('$', '\\$')
    s = s.replace('[', '\\[')
    s = s.replace(']', '\\]')
    return f'"{s}"'
```

---

### H5: `sync.py` + `operations.py` — `plan_refresh()` 与 `refresh()` 执行不匹配

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_core/sync.py` | 196-208 | `SyncPolicy.plan_refresh()` |
| `tools/vivado_core/operations.py` | 481-485 | `Operations.refresh()` |

**问题描述**: 当 RTL 层 stale 时，`plan_refresh()` 返回的 `tcl_steps` 包含 `"add_tb"` (sync.py:207)。但 `operations.py` 的 full-rebuild 路径 (lines 481-485) 只执行：

```python
tcl_rebuild = "\n".join([
    _tcl_create_project(...),
    _tcl_setup_ip(...),
    _tcl_add_constrs(base),
])
# 缺少 _tcl_add_tb() !
```

**影响**: 全量 refresh 后，sim_1 文件集中无 testbench，执行 `-sim` 必失败。

**建议**: 在 full-rebuild 路径中添加 `_tcl_add_tb()` 调用。

---

### H6: `session.py` — timeout 后不清除输出缓冲区

| 文件 | 行号 | 模块 |
|------|------|------|
| `tools/vivado_core/session.py` | 309-315 | `Session.execute()` |

**问题描述**: `execute()` 超时后直接返回 `ExecuteResult(timed_out=True)`，但 Vivado stdout 中仍有未读数据（超时命令的后续输出）。下次 `execute()` 调用时，`readline()` 会读到这些 stale 输出，与新 marker 匹配错乱。

**影响**: 超时后连续操作的结果不可信——可能读到上一条命令的输出，或永久挂起等待不存在的 marker。

**建议**: 超时后清空 stdout 缓冲区（非阻塞读取直到 EOF 或空行），或重启 Vivado 进程。

---

## 🟡 MEDIUM Severity — 设计不合理

### M1: `session.py` — `cmd.exe /k` 仅 Windows 且产生僵尸进程

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/session.py` | 203-204 |

**问题**: `cmd.exe /k` 是 Windows 专用启动方式。Vivado 崩溃后 cmd.exe 仍存活（`/k` 不自动退出），`is_alive()` 检查 cmd.exe PID 返回 True，但 Vivado 已死，所有命令失败。

**建议**: 直接启动 `vivado.bat -mode tcl`（Windows batch 文件可直接被 Popen 执行），或使用进程组管理。

---

### M2: `session.py` — 成功判断启发式过于粗糙

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/session.py` | 318 |

**问题**: `success = "ERROR:" not in output` 存在两类误判：
- **假阳性**: 输出含 "ERROR:" 但非错误（如信号名 `error_flag`、注释 `// ERROR handling`）
- **假阴性**: Vivado 失败但输出无 "ERROR:" 前缀（如 TCL `catch` 吞掉的错误）

**建议**: 仅匹配行首的 `ERROR:` 模式：`success = not any(line.startswith("ERROR:") for line in output.splitlines())`

---

### M3: `operations.py` — sim log 路径错误

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 264 |

**问题**: `_tcl_run_sim()` 读取 `{sim_log_dir}/xsim.log`，但 Vivado 2018.3 实际生成的日志文件为 `simulate.log`。

**实际影响**: **每次仿真必现 `WARNING: sim log not found: .../xsim.log`**，仿真详细日志丢失。

**建议**: 将 `xsim.log` 改为 `simulate.log`，或同时尝试两个文件名。

---

### M4: `hash.py` — `vivado_config.yaml` 不在任何 hash 层

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/hash.py` | 33-51 |

**问题**: 四层 hash（rtl/tb/coe/fpga）均不包含 `vivado_config.yaml`。修改内存配置（如 `num_sets`、`tag_width`、`use_tlb_bram`）不会触发 staleness 检测。

**影响**: 改 config 后不 refresh，用旧 IP 参数仿真而不知情。这是**内存/缓存参数变更场景下的静默正确性风险**。

**建议**: 在 RTL 层（或新增 config 层）中加入 `vivado_config.yaml`：

```python
"rtl": [
    "dev/rtl/**/*.sv",
    "dev/rtl/**/*.svh",
    "Reference/**/*.xci",
    "vivado_config.yaml",  # ← 新增
],
```

---

### M5: `config.py` — 默认值重复定义（DRY 违反）

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/config.py` | 22-31, 184-188（及所有 dataclass+load 对） |

**问题**: 每个配置字段的默认值定义两次：dataclass 中一次（如 `max_sessions: int = 5`），`load_config()` 中又一次（如 `limits_raw.get("max_sessions", 5)`）。修改一处而遗漏另一处将导致静默不一致。

**建议**: 使用 `dataclasses.fields()` 自省默认值，或用 `**kwargs` 构造 dataclass 让其自动补全默认值。

---

### M6: `config.py` — 无配置值验证

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/config.py` | 全文 |

**问题**: 无验证逻辑。以下非法配置均静默接受：
- 负数 `max_sessions`
- 零 `data_width`
- 非 2^n 的 `depth`
- 违反 tree_plru 约束的 `num_ways`（代码注释标记 `⚠ FIXED: do not change` 但无强制）

**建议**: 在 `load_config()` 末尾添加验证，至少 assert 正数、2^n、tree_plru 约束。

---

### M7: `operations.py` — `-jobs 14` 硬编码

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 630-634 |

**问题**: 综合/实现的并行 job 数硬编码为 14。

**建议**: 从 `vivado_config.yaml` 读取，或默认 `min(os.cpu_count(), 14)`。

---

### M8: `operations.py` — 所有操作 timeout 硬编码

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 416, 556, 599, 646, 693, 735 |

**问题**: `create=300s`, `refresh=300s`, `sim=600s`, `bitstream=3600s`, `program=120s`, `archive=300s`。大设计可能需要更长 bitstream 时间。

**建议**: 移入 `LimitsConfig` 或 per-operation 配置。

---

### M9: `operations.py` — 目录结构硬编码

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 54-63, 180, 358 |

**问题**: `dev/rtl/ALU`、`dev/rtl/MU`、`dev/rtl/core`、`dev/rtl/AHB-lite`、`dev/rtl/APB`、`dev/tb`、`dev/fpga`、`dev/program_source` 全部硬编码。项目重组即崩溃。

**建议**: 移入 `vivado_config.yaml` 的 `paths` 段。

---

### M10: `operations.py` — `sim()` 每次都重加 testbench

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 593-597 |

**问题**: 每次 `sim()` 调用 `_tcl_add_tb()`，移除并重新添加 sim_1 文件，即使 testbench 未变。强制不必要的重编译。

**建议**: 先检查 TB 层 staleness，仅 stale 时才 re-add。

---

### M11: `sync.py` — TB/COE stale 对 sim 仅 warning

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/sync.py` | 133-149 |

**问题**: TB 或 COE 层 stale 时，`preflight_check()` 返回 `ok=True, severity="warning"`。仿真可使用过期 testbench 或程序镜像运行，产出**静默错误结果**。对硬件验证工具，这是危险的。

**建议**: 至少对 COE stale 提升为 `severity="error"`（程序镜像错误 = 仿真结果无效）。

---

### M12: `hash.py` — hash 截断 8 hex 字符（32 bit）

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/hash.py` | 138 |

**问题**: SHA256 截断为 8 hex 字符（32 bit）。生日悖论：1000 文件时碰撞概率 ≈ N²/(2×2³²) ≈ 0.01%。对硬件验证工具，即使一次漏检变更也可能产出错误硅片。

**建议**: 至少使用 12-16 hex 字符（48-64 bit）。

---

### M13: `vivado_cli.py` — `_stale_layers` 属性从未设置

| 文件 | 行号 |
|------|------|
| `tools/vivado_cli.py` | 290 |

**问题**: `format_status_text()` 使用 `getattr(s, '_stale_layers', None)` 但 `Session` 对象无此属性，永远返回 None。status 输出中 stale layers 永远显示 "-"。

**建议**: 在 `--status` 处理中计算 staleness 并附加到 session 对象。

---

### M14: `vivado_cli.py` — fallback YAML 解析器无法处理嵌套结构

| 文件 | 行号 |
|------|------|
| `tools/vivado_cli.py` | 55-68 |

**问题**: 正则 `r"^(\w+)\s*:\s*(.+)$"` 仅匹配扁平 key-value。无法解析 `tasks:` 和 `memory:` 嵌套字典。无 PyYAML 时 CLI 完全不可用。

**建议**: 在 `pyproject.toml` / `requirements.txt` 中声明 PyYAML 为必需依赖，移除不完整的 fallback。

---

### M15: `config.py` — `proj_name` 默认值不一致

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/config.py` | 137 |
| `vivado_config.yaml` | 10 |

**问题**: `config.py` 默认 `proj_name="simplecpu_bus"`，`vivado_config.yaml` 写 `proj_name: simplecpu_soc`。YAML 覆盖了默认值，但默认值过时暗示历史遗留。

**建议**: 将 `config.py` 默认值改为 `"simplecpu_soc"` 以保持一致。

---

### M16: 全局 — 无日志配置

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/operations.py` | 21 |
| `tools/vivado_cli.py` | — |

**问题**: `operations.py` 使用 `logging.getLogger(__name__)` 但 CLI 从未调用 `logging.basicConfig()`。所有日志静默丢弃。

**建议**: 在 `vivado_cli.py` 的 `main()` 中添加 `logging.basicConfig(level=logging.INFO)`。

---

### M17: 全局 — 无信号处理

| 文件 | 行号 |
|------|------|
| `tools/vivado_cli.py` | — |

**问题**: Ctrl+C 中断长 Vivado 操作后，子进程残留运行。无 SIGINT/SIGTERM 处理。

**建议**: 安装 `signal.signal(SIGINT, ...)` 处理器，调用 `session.stop_vivado()` 后退出。

---

### M18: 全局 — Vivado 崩溃无自动恢复

| 文件 | 行号 |
|------|------|
| `tools/vivado_core/session.py` | 248-249 |

**问题**: Vivado 进程崩溃后，`execute()` 抛 `VivadoProcessError`，但无 auto-restart。用户须手动处理（stop + start 或新 session）。

**建议**: 在 `_ensure_vivado()` 中检测进程死亡并自动重启。

---

## 🟢 LOW Severity — 代码质量

### L1: `session.py:367` — `disk_mb()` 遍历全目录树

`rglob("*")` 对大 Vivado 项目可能耗时数秒。5 个 session 的 `total_disk_mb()` 可能耗时 5-10 秒。应缓存或采样。

### L2: `hash.py:49` — `.dcp` 文件纳入内容 hash

DCP 文件可达数百 MB，全量读取极慢。应改用 `size + mtime` 快速 hash，或排除 DCP。

### L3: `hash.py:33-51` — Python 编排代码不在 hash 层

`fpga` 层含 `tools/tcl/**/*.tcl` 但不含 `tools/vivado_core/**/*.py`。改 Python 代码不触发 stale。

### L4: `ip_gen.py:235` — 硬编码 `blk_mem_gen v8.4`

不同 Vivado 版本可能不兼容。应可配置或自动检测。

### L5: `cache_header_gen.py:61,143,170` — 硬编码 SV32 地址分解和 TLB entry 宽度

假设 32-bit 物理地址、SV32 页表格式。改为 RV64 需大量修改。

### L6: `vivado_cli.py:423-751` — `main()` 函数 ~330 行

深度嵌套，重复模式（preflight → execute → format）。应分解为 per-operation helper。

### L7: `session.py:609` — idle watcher 间隔硬编码 60s

应可配置。

### L8: `operations.py:76-93` — TCL `glob` 无 `-nocomplain`

目录不存在时 `glob -directory {dir} *.sv` 抛 TCL 错误，终止整个脚本。应加 `-nocomplain` 或目录存在性检查。

---

## 📊 审计统计

| 严重度 | 数量 | 模块分布 |
|--------|------|----------|
| 🔴 HIGH | 6 | session.py×3, operations.py×2, vivado_cli.py×1 |
| 🟡 MEDIUM | 18 | session.py×2, operations.py×5, config.py×2, hash.py×2, sync.py×2, vivado_cli.py×3, 全局×2 |
| 🟢 LOW | 8 | session.py×1, hash.py×2, ip_gen.py×1, cache_header_gen.py×1, vivado_cli.py×2, operations.py×1 |
| **合计** | **32** | |

### 已验证无问题的领域

- ✅ **异常层次结构**: `exceptions.py` 设计清晰，继承关系正确
- ✅ **Session 元数据持久化**: `.session.yaml` 读写逻辑正确
- ✅ **Task 注册与查找**: `tasks.py` 核心逻辑正确（仅 exception 类型语义问题）
- ✅ **IP 生成 TCL**: `ip_gen.py` 的 `create_ip` TCL 生成逻辑与 Vivado blk_mem_gen v8.4 兼容
- ✅ **cache_def.svh 生成**: `cache_header_gen.py` 地址切片推导与 RTL 宏使用一致
- ✅ **配置驱动 IP 生成链**: `vivado_config.yaml` → `ip_gen.py` → `cache_header_gen.py` → `operations.py` 链路完整

---

## 🔧 建议修复优先级

### P0 — 立即修复（影响每次使用）

1. **H2**: refresh 删除目录权限拒绝 → 改为先切换 CWD 或重启 Vivado
2. **H3**: `hw_connect` 方法缺失 → 实现或移除 CLI 选项
3. **M3**: sim log 路径错误 → `xsim.log` → `simulate.log`
4. **M16**: 无日志配置 → 添加 `logging.basicConfig()`

### P1 — 尽快修复（潜在严重后果）

5. **H1**: `readline()` 阻塞使 timeout 失效 → 改用非阻塞读取
6. **H4**: TCL 字符串注入 → 添加 `_tcl_escape()`
7. **H5**: plan_refresh 与 refresh 执行不匹配 → full-rebuild 路径添加 `_tcl_add_tb()`
8. **H6**: timeout 后不清除缓冲区 → 清空或重启
9. **M4**: `vivado_config.yaml` 不在 hash 层 → 加入 RTL 层

### P2 — 计划修复（设计改进）

10. **M2**: 成功判断启发式 → 改为行首匹配
11. **M5/M6**: 配置 DRY 违反 + 无验证 → 统一默认值来源 + 添加验证
12. **M7/M8**: 硬编码 jobs 和 timeout → 移入配置
13. **M11**: COE stale 应为 error → 提升 severity
14. **M12**: hash 截断过短 → 增至 12-16 hex

### P3 — 适时改进（代码质量）

15. **M1**: `cmd.exe /k` → 直接启动 vivado.bat
16. **M9**: 目录结构硬编码 → 移入配置
17. **M10**: sim 每次重加 TB → 检查 staleness 后按需添加
18. **M17/M18**: 信号处理 + 进程恢复
