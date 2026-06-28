#!/usr/bin/env python3
"""Vivado orchestration CLI — agent-friendly interface with session isolation.

Usage:
    # Create session and run simulation
    python -m tools.vivado_cli -task cpu_full -create -sim

    # Run simulation in existing session
    python -m tools.vivado_cli -task cpu_full -sim

    # Custom session name
    python -m tools.vivado_cli -task cpu_full -session cpu_v2 -sim

    # Check staleness and session status
    python -m tools.vivado_cli --status

    # Incremental refresh (only COE layer)
    python -m tools.vivado_cli -task cpu_full -refresh --layers coe

    # Full refresh
    python -m tools.vivado_cli -task cpu_full -refresh

    # Generate bitstream
    python -m tools.vivado_cli -task fpga -bitstream

    # Program FPGA
    python -m tools.vivado_cli -task fpga -program

    # Cleanup old sessions
    python -m tools.vivado_cli --cleanup
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Platform helpers
# ---------------------------------------------------------------------------

def _default_vivado_path() -> str:
    """Return the default Vivado executable name for the current platform.

    - Windows: ``vivado.bat``
    - Linux / macOS: ``vivado``
    """
    return "vivado.bat" if sys.platform == "win32" else "vivado"


def _now_local() -> str:
    """Return the current local time as a human-readable string."""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _parse_debug_arg(debug_str: str) -> dict[str, str]:
    """Parse --debug argument into verilog defines dict.

    Supported features: trace, pipeline, trap, spike, wave[:LEVEL], all
    LEVEL: minimal, normal (default), full
    """
    VALID_FEATURES = {"trace", "pipeline", "trap", "spike", "wave", "all"}
    defines: dict[str, str] = {}
    parts = [p.strip().lower() for p in debug_str.split(",")]

    for part in parts:
        if ":" in part:
            feature, level = part.split(":", 1)
        else:
            feature, level = part, None

        if feature == "all":
            defines.update({
                "DEBUG_TRACE": "1",
                "DEBUG_PIPELINE": "1",
                "DEBUG_TRAP": "1",
                "DEBUG_SPIKE": "1",
                "DEBUG_WAVE": "1",
                "WAVE_LEVEL": "full",
            })
        elif feature == "trace":
            defines["DEBUG_TRACE"] = "1"
        elif feature == "pipeline":
            defines["DEBUG_PIPELINE"] = "1"
        elif feature == "trap":
            defines["DEBUG_TRAP"] = "1"
        elif feature == "spike":
            defines["DEBUG_SPIKE"] = "1"
        elif feature == "wave":
            defines["DEBUG_WAVE"] = "1"
            defines["WAVE_LEVEL"] = level or "normal"
        elif feature not in VALID_FEATURES:
            print(f"WARNING: Unknown debug feature: {feature}", file=sys.stderr)

    return defines

# ---------------------------------------------------------------------------
# YAML loading — prefer PyYAML, fall back to minimal parser
# ---------------------------------------------------------------------------
try:
    import yaml

    def _load_yaml(path: Path) -> dict[str, Any]:
        text = path.read_text(encoding="utf-8")
        return yaml.safe_load(text) or {}

except ImportError:

    def _load_yaml(path: Path) -> dict[str, Any]:  # type: ignore[misc]
        """Minimal YAML subset parser (keys/values only, no nested collections)."""
        import re as _re

        result: dict[str, Any] = {}
        text = path.read_text(encoding="utf-8")
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = _re.match(r"^(\w+)\s*:\s*(.+)$", line)
            if m:
                result[m.group(1)] = m.group(2).strip()
        return result


# ---------------------------------------------------------------------------
# vivado_core import — graceful degradation when core is not yet built
# ---------------------------------------------------------------------------
try:
    from tools.vivado_core import (
        LayeredHash,
        Operations,
        SessionManager,
        SyncPolicy,
        TaskRegistry,
        VivadoCoreError,
    )
    from tools.vivado_core.batch import (
        BatchExecutor,
        BatchResult,
        BatchSpec,
        BatchTask,
        TaskResult,
        expand_batch_spec,
        load_batch_plan,
    )
    from tools.vivado_core.exceptions import SessionNotFoundError

    _HAS_CORE = True
except ImportError:
    _HAS_CORE = False

    class VivadoCoreError(Exception):  # type: ignore[no-redef]
        """Placeholder when vivado_core is not available."""

    class SessionManager:  # type: ignore[no-redef]
        pass

    class TaskRegistry:  # type: ignore[no-redef]
        pass

    class LayeredHash:  # type: ignore[no-redef]
        pass

    class SyncPolicy:  # type: ignore[no-redef]
        pass

    class Operations:  # type: ignore[no-redef]
        pass

    class BatchExecutor:  # type: ignore[no-redef]
        pass

    class BatchSpec:  # type: ignore[no-redef]
        pass

    class BatchTask:  # type: ignore[no-redef]
        pass

    class BatchResult:  # type: ignore[no-redef]
        pass

    class TaskResult:  # type: ignore[no-redef]
        pass


# ---------------------------------------------------------------------------
# Exit codes
# ---------------------------------------------------------------------------
EXIT_OK = 0
EXIT_GENERAL = 1
EXIT_CONFIG = 2
EXIT_SESSION = 3
EXIT_STALE = 4


# ---------------------------------------------------------------------------
# Configuration dataclasses
# ---------------------------------------------------------------------------
@dataclass
class Limits:
    max_sessions: int = 5
    max_concurrent: int = 3
    max_disk_gb: int = 20
    idle_timeout_min: int = 60
    create_timeout: float = 300.0
    refresh_timeout: float = 300.0
    sim_timeout: float = 600.0
    sim_rerun_timeout: float = 3600.0
    bitstream_timeout: float = 3600.0
    program_timeout: float = 120.0
    archive_timeout: float = 300.0


@dataclass
class VivadoConfig:
    limits: Limits = field(default_factory=Limits)
    vivado_path: str = field(default_factory=_default_vivado_path)
    proj_name: str = "simplecpu_bus"
    device_part: str = "xc7a200tfbg676-2"


def load_config(path: Path) -> VivadoConfig:
    """Load vivado_config.yaml into config object.

    When vivado_core is available, delegates to the core's ``load_config``
    which returns a ``GlobalConfig`` (with ``memory`` field).  Otherwise
    falls back to the CLI's own ``VivadoConfig`` (without memory).
    """
    if _HAS_CORE:
        from tools.vivado_core.config import load_config as core_load_config
        return core_load_config(path)  # type: ignore[no-any-return]
    if not path.exists():
        print(f"WARNING: Config file not found: {path} — using defaults")
        return VivadoConfig()
    raw = _load_yaml(path)
    limits_raw = raw.get("limits", {})
    limits = Limits(
        max_sessions=int(limits_raw.get("max_sessions", 5)),
        max_concurrent=int(limits_raw.get("max_concurrent", 3)),
        max_disk_gb=int(limits_raw.get("max_disk_gb", 20)),
        idle_timeout_min=int(limits_raw.get("idle_timeout_min", 60)),
        create_timeout=float(limits_raw.get("create_timeout", 300)),
        refresh_timeout=float(limits_raw.get("refresh_timeout", 300)),
        sim_timeout=float(limits_raw.get("sim_timeout", 600)),
        sim_rerun_timeout=float(limits_raw.get("sim_rerun_timeout", 3600)),
        bitstream_timeout=float(limits_raw.get("bitstream_timeout", 3600)),
        program_timeout=float(limits_raw.get("program_timeout", 120)),
        archive_timeout=float(limits_raw.get("archive_timeout", 300)),
    )
    return VivadoConfig(
        limits=limits,
        vivado_path=str(raw.get("vivado_path", _default_vivado_path())),
        proj_name=str(raw.get("proj_name", "simplecpu_bus")),
        device_part=str(raw.get("device_part", "xc7a200tfbg676-2")),
    )


# ---------------------------------------------------------------------------
# Task definitions
# ---------------------------------------------------------------------------
@dataclass
class TaskDef:
    name: str
    tb: str | None = None
    top: str | None = None
    blcoe: str | None = None
    runtime: str | None = None

    @property
    def is_fpga(self) -> bool:
        return self.top is not None


def load_tasks(path: Path) -> dict[str, TaskDef]:
    """Load tasks.yaml into a dict of TaskDef objects."""
    if not path.exists():
        print(f"ERROR: Tasks file not found: {path}", file=sys.stderr)
        sys.exit(EXIT_CONFIG)
    raw = _load_yaml(path)
    tasks_raw = raw.get("tasks", {})
    if not tasks_raw:
        print(f"ERROR: No tasks defined in {path}", file=sys.stderr)
        sys.exit(EXIT_CONFIG)
    result: dict[str, TaskDef] = {}
    for name, spec in tasks_raw.items():
        if not isinstance(spec, dict):
            continue
        result[name] = TaskDef(
            name=name,
            tb=spec.get("tb"),
            top=spec.get("top"),
            blcoe=spec.get("blcoe"),
            runtime=spec.get("runtime"),
        )
    return result


# ---------------------------------------------------------------------------
# Output filtering
# ---------------------------------------------------------------------------
FILTER_PRESETS: dict[str, re.Pattern[str]] = {
    "error": re.compile(r"ERROR:|WARNING:"),
    "pass_fail": re.compile(r"PASS|FAIL|pass=|fail="),
    "progress": re.compile(r"\d+%\|.*\||\[\d+/\d+\]|#"),
}


def apply_filter(lines: list[str], pattern: str) -> list[str]:
    """Filter output lines by preset name or custom regex."""
    if pattern in FILTER_PRESETS:
        pat = FILTER_PRESETS[pattern]
    else:
        try:
            pat = re.compile(pattern)
        except re.error as e:
            print(f"WARNING: Invalid filter regex '{pattern}': {e}", file=sys.stderr)
            return lines
    return [line for line in lines if pat.search(line)]


# ---------------------------------------------------------------------------
# Result formatting
# ---------------------------------------------------------------------------
def format_result_text(
    operation: str,
    session: str,
    task: str,
    success: bool,
    output: str,
    duration: float,
    staleness: dict[str, bool] | None,
    timed_out: bool = False,
) -> str:
    """Format operation result as human-readable text."""
    lines: list[str] = []
    lines.append(f"Operation : {operation}")
    lines.append(f"Session   : {session}")
    lines.append(f"Task      : {task}")
    if timed_out:
        lines.append(f"Status    : TIMEOUT")
    else:
        lines.append(f"Success   : {success}")
    lines.append(f"Duration  : {duration:.1f}s")
    if staleness:
        stale_layers = [k for k, v in staleness.items() if v]
        lines.append(f"Stale     : {','.join(stale_layers) if stale_layers else '-'}")
    lines.append("--- Output ---")
    lines.append(output)
    return "\n".join(lines)


def format_result_json(
    operation: str,
    session: str,
    task: str,
    success: bool,
    output: str,
    filtered_output: str,
    duration: float,
    staleness: dict[str, bool] | None,
    timed_out: bool = False,
) -> str:
    """Format operation result as JSON."""
    result: dict[str, Any] = {
        "operation": operation,
        "session": session,
        "task": task,
        "success": success,
        "timed_out": timed_out,
        "output": output,
        "filtered_output": filtered_output,
        "duration": round(duration, 3),
        "staleness": staleness,
    }
    return json.dumps(result, indent=2, ensure_ascii=False)


def format_status_text(sessions: list[Any]) -> str:
    """Format session status as aligned text table."""
    header = f"{'Session':<14}{'Task':<12}{'Status':<8}{'Stale Layers':<16}{'Vivado PID':<10}"
    sep = "-" * len(header)
    rows = [header, sep]
    for s in sessions:
        # Support both Session objects and dicts
        name = s.name if hasattr(s, 'name') else s.get('name', '?')
        task = s.meta.task if hasattr(s, 'meta') else s.get('task', '?')
        status = s.meta.status if hasattr(s, 'meta') else s.get('status', '?')
        pid = s.meta.vivado_pid if hasattr(s, 'meta') else s.get('vivado_pid')
        stale_layers = getattr(s, '_stale_layers', None) or (s.get('stale_layers', []) if isinstance(s, dict) else [])
        stale = ",".join(stale_layers) or "-"
        pid_str = str(pid) if pid else "-"
        rows.append(
            f"{name:<14}{task:<12}{status:<8}{stale:<16}{pid_str:<10}"
        )
    return "\n".join(rows)


def format_status_json(sessions: list[Any]) -> str:
    """Format session status as JSON."""
    data = []
    for s in sessions:
        if hasattr(s, 'name'):
            data.append({
                "name": s.name,
                "task": s.meta.task,
                "status": s.meta.status,
                "vivado_pid": s.meta.vivado_pid,
                "stale_layers": getattr(s, '_stale_layers', []),
            })
        else:
            data.append(s)
    return json.dumps({"sessions": data}, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Core orchestration helpers (lightweight wrappers when vivado_core is absent)
# ---------------------------------------------------------------------------
def _require_core() -> None:
    """Exit with helpful message if vivado_core is not available."""
    if not _HAS_CORE:
        print(
            "ERROR: tools.vivado_core package is not yet implemented.\n"
            "       The CLI frontend is ready, but the core orchestration\n"
            "       engine (tools/vivado_core/) must be built first.\n"
            "       Falling back to direct vivado_do.tcl invocation is recommended.",
            file=sys.stderr,
        )
        sys.exit(EXIT_GENERAL)


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vivado_cli",
        description="Vivado orchestration CLI — agent-friendly interface with session isolation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Task & session
    parser.add_argument("-task", metavar="NAME", help="Specify task (from tasks.yaml)")
    parser.add_argument(
        "-session", metavar="NAME", help="Override session name (default: task name)"
    )

    # Operation flags
    parser.add_argument(
        "-create", action="store_true", help="Create/open project in session"
    )
    parser.add_argument(
        "-sim", action="store_true",
        help=(
            "Run simulation.  "
            "WARNING: in batch mode, use -create -sim (not -sim alone) — "
            "see batch.py _execute_single() docstring."
        ),
    )
    parser.add_argument(
        "-runtime", metavar="TIME", help="Override simulation runtime"
    )
    parser.add_argument(
        "--debug",
        metavar="FEATURES",
        help="Enable debug features: trace,pipeline,trap,spike,wave[:LEVEL]. "
             'E.g. --debug trace,trap  --debug wave:full  --debug all',
    )
    parser.add_argument(
        "-refresh", action="store_true", help="Refresh session (sync source changes)"
    )
    parser.add_argument(
        "-bitstream", action="store_true", help="Generate bitstream"
    )
    
    parser.add_argument("-program", action="store_true", help="Program FPGA")
    parser.add_argument(
        "-archive", action="store_true", help="Export project archive"
    )

    # Refresh layers
    parser.add_argument(
        "--layers",
        metavar="L1,L2",
        help="Comma-separated layers to refresh (rtl,tb,coe,fpga). Default: all stale layers",
    )

    # Status / cleanup
    parser.add_argument(
        "--status", action="store_true", help="Show all sessions status + staleness"
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Remove oldest sessions to stay within limit (keeps max_sessions - 1)",
    )
    parser.add_argument(
        "--cleanup-all", action="store_true", help="Remove ALL sessions completely"
    )
    parser.add_argument(
        "--gen-config", action="store_true",
        help="Regenerate cache_def.svh from vivado_config.yaml memory section",
    )

    # Batch execution
    parser.add_argument(
        "-batch", metavar="TASKS",
        help="Comma-separated task names or glob patterns for batch execution",
    )
    parser.add_argument(
        "-batch-plan", metavar="FILE",
        help="YAML file defining batch execution plan",
    )
    parser.add_argument(
        "--max-parallel", type=int, default=None,
        help="Max parallel sessions (default: min(len(tasks), max_concurrent))",
    )
    parser.add_argument(
        "--on-error",
        choices=["continue", "fail-fast", "stop-accepting"],
        default="continue",
        help="Error handling strategy for batch mode",
    )

    # Output control
    parser.add_argument(
        "--format",
        metavar="FMT",
        choices=["text", "json"],
        default="text",
        help='Output format: "text" (default) or "json"',
    )
    parser.add_argument(
        "--filter",
        metavar="PAT",
        dest="filter_pat",
        help='Filter output: "error", "pass_fail", "progress", or regex',
    )
    parser.add_argument(
        "--config", metavar="PATH", help="Path to vivado_config.yaml"
    )
    parser.add_argument("--tasks", metavar="PATH", help="Path to tasks.yaml")
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Verbose output"
    )
    parser.add_argument(
        "--log", metavar="FILE",
        help="Log Vivado output to FILE with timestamps (real-time, line-by-line)",
    )

    return parser


def format_batch_result_text(result: Any) -> str:
    """Format batch result as human-readable text.

    Parameters
    ----------
    result:
        :class:`BatchResult` object.

    Returns
    -------
    str
    """
    lines: list[str] = []
    lines.append("=" * 60)
    lines.append("BATCH RESULT")
    lines.append("=" * 60)
    lines.append(f"Total    : {result.total}")
    lines.append(f"Succeeded: {result.succeeded}")
    lines.append(f"Failed   : {result.failed}")
    if getattr(result, "xfailed", 0):
        lines.append(f"XFailed  : {result.xfailed}")
    lines.append(f"Skipped  : {result.skipped}")
    lines.append(f"Duration : {result.duration:.1f}s")
    lines.append("-" * 60)
    for tr in result.results:
        if tr.success:
            status = "PASS"
        elif getattr(tr, "expected_fail", False):
            status = "XFAIL"
        else:
            status = "FAIL"
        if tr.error and tr.error.startswith("Skipped:"):
            status = "SKIP"
        elif tr.error and tr.error.startswith("Cancelled"):
            status = "SKIP"
        lines.append(f"  {tr.task_name:<20s} {status:<6s} {tr.duration:.1f}s  session={tr.session_name}")
        if tr.error and status not in ("PASS", "XFAIL"):
            lines.append(f"    Error: {tr.error}")
        elif status == "XFAIL":
            lines.append(f"    Expected failure: {tr.error or 'no details'}")
        for op in tr.operations:
            if op.get("timed_out"):
                op_status = "TIMEOUT"
            elif op.get("success"):
                op_status = "OK"
            else:
                op_status = "FAIL"
            op_dur = op.get("duration", 0.0)
            lines.append(f"    {op['operation']:<12s} {op_status:<5s} {op_dur:.1f}s")
    lines.append("=" * 60)
    return "\n".join(lines)


def format_batch_result_json(result: Any) -> str:
    """Format batch result as JSON.

    Parameters
    ----------
    result:
        :class:`BatchResult` object.

    Returns
    -------
    str
    """
    data = {
        "total": result.total,
        "succeeded": result.succeeded,
        "failed": result.failed,
        "xfailed": getattr(result, "xfailed", 0),
        "skipped": result.skipped,
        "duration": round(result.duration, 3),
        "exit_code": result.exit_code,
        "results": [
            {
                "task_name": tr.task_name,
                "session_name": tr.session_name,
                "success": tr.success,
                "expected_fail": getattr(tr, "expected_fail", False),
                "duration": round(tr.duration, 3),
                "error": tr.error,
                "operations": tr.operations,
            }
            for tr in result.results
        ],
    }
    return json.dumps(data, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    # --- Resolve config / tasks paths ---
    project_root = Path(__file__).resolve().parent.parent

    config_path = Path(args.config) if args.config else project_root / "vivado_config.yaml"
    tasks_path = Path(args.tasks) if args.tasks else project_root / "tasks.yaml"

    # --- Load configuration ---
    try:
        config = load_config(config_path)
    except Exception as e:
        print(f"ERROR: Failed to load config from {config_path}: {e}", file=sys.stderr)
        return EXIT_CONFIG

    # --- Load task definitions ---
    try:
        task_defs = load_tasks(tasks_path)
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else EXIT_CONFIG

    if args.verbose:
        print(f"Config : {config_path}")
        print(f"Tasks  : {tasks_path}")
        print(f"Project: {config.proj_name}  Device: {config.device_part}")
        print(f"Tasks defined: {', '.join(task_defs.keys())}")

    # --- Validate -task argument ---
    task_def: TaskDef | None = None
    task_name: str | None = args.task
    if task_name:
        if task_name not in task_defs:
            print(
                f"ERROR: Unknown task '{task_name}'. "
                f"Available: {', '.join(sorted(task_defs.keys()))}",
                file=sys.stderr,
            )
            return EXIT_CONFIG
        task_def = task_defs[task_name]

    # --- Determine session name ---
    session_name: str | None = args.session or task_name

    # =======================================================================
    # Batch execution path
    # =======================================================================
    if getattr(args, "batch", None) or getattr(args, "batch_plan", None):
        _require_core()

        # --- Instantiate core components ---
        try:
            task_registry = TaskRegistry(tasks_path)  # type: ignore[call-arg]
            task_registry.load()  # type: ignore[attr-defined]
            session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
            layered_hash = LayeredHash(project_root)  # type: ignore[call-arg]
            sync = SyncPolicy(layered_hash)  # type: ignore[call-arg]
        except VivadoCoreError as e:
            print(f"ERROR: Core initialization failed: {e}", file=sys.stderr)
            return EXIT_GENERAL

        # --- Build BatchSpec ---
        if getattr(args, "batch_plan", None):
            # Load from YAML file
            try:
                batch_spec = load_batch_plan(Path(args.batch_plan))  # type: ignore[attr-defined]
            except (FileNotFoundError, ValueError) as e:
                print(f"ERROR: Invalid batch plan: {e}", file=sys.stderr)
                return EXIT_CONFIG
            # Expand pattern markers if present
            expanded_tasks: list[Any] = []
            for bt in batch_spec.tasks:
                if bt.task_name.startswith("__pattern__:"):
                    pattern = bt.task_name.split(":", 1)[1]
                    names = expand_batch_spec(pattern, task_registry.list_names())  # type: ignore[attr-defined]
                    expanded_tasks.extend(BatchTask(task_name=n) for n in names)
                else:
                    expanded_tasks.append(bt)
            batch_spec.tasks = expanded_tasks
        else:
            # Build from -batch argument
            try:
                task_names = expand_batch_spec(
                    args.batch, task_registry.list_names()  # type: ignore[attr-defined]
                )
            except VivadoCoreError as e:
                print(f"ERROR: {e}", file=sys.stderr)
                return EXIT_CONFIG
            batch_tasks = [BatchTask(task_name=n) for n in task_names]

            # Determine operations from flags
            operations: list[str] = []
            if args.create:
                operations.append("create")
            if args.refresh:
                operations.append("refresh")
            if args.sim:
                operations.append("sim")
            if args.bitstream:
                operations.append("bitstream")
            if args.program:
                operations.append("program")
            if args.archive:
                operations.append("archive")
            if not operations:
                operations = ["create", "sim"]

            # Determine max_parallel
            max_parallel = len(batch_tasks)
            max_concurrent = config.limits.max_concurrent
            if args.max_parallel is not None:
                max_parallel = min(max_parallel, args.max_parallel)
            max_parallel = min(max_parallel, max_concurrent)

            # Parse refresh layers
            refresh_layers: list[str] | None = None
            if args.layers:
                refresh_layers = [l.strip() for l in args.layers.split(",")]

            batch_spec = BatchSpec(
                tasks=batch_tasks,
                max_parallel=max_parallel,
                on_error=args.on_error,
                operations=operations,
                refresh_layers=refresh_layers,
                runtime_override=args.runtime,
            )

        # --- Auto-enable per-session logging in batch mode ---
        if not batch_spec.log_dir:
            if getattr(args, "log", None):
                log_arg = Path(args.log)
                if log_arg.is_dir() or not log_arg.suffix:
                    batch_spec.log_dir = str(log_arg)
                else:
                    batch_spec.log_dir = str(log_arg.parent)
            else:
                batch_spec.log_dir = str(project_root / "log")

        # --- Validate batch tasks ---
        for bt in batch_spec.tasks:
            if bt.task_name not in task_registry:  # type: ignore[attr-defined]
                print(
                    f"ERROR: Unknown task '{bt.task_name}' in batch. "
                    f"Available: {', '.join(sorted(task_registry.list_names()))}",  # type: ignore[attr-defined]
                    file=sys.stderr,
                )
                return EXIT_CONFIG

        # --- Execute batch ---
        batch_log_fh: Any = None
        batch_callback = None
        if getattr(args, "log", None):
            batch_log_path = Path(args.log)
            batch_log_path.parent.mkdir(parents=True, exist_ok=True)
            batch_log_fh = batch_log_path.open("a", encoding="utf-8")
            batch_log_fh.write(f"\n{'=' * 60}\n")
            batch_log_fh.write(f"Batch started: {_now_local()}\n")
            batch_log_fh.write(f"{'=' * 60}\n")
            batch_log_fh.flush()

            def _batch_log_cb(line: str) -> None:
                ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                batch_log_fh.write(f"[{ts}] {line}\n")
                batch_log_fh.flush()

            batch_callback = _batch_log_cb

        try:
            executor = BatchExecutor(
                session_mgr, task_registry, sync, layered_hash, config,  # type: ignore[call-arg]
                output_callback=batch_callback,
            )
            batch_result = executor.execute(batch_spec)
        except VivadoCoreError as e:
            print(f"ERROR: Batch execution failed: {e}", file=sys.stderr)
            if batch_log_fh:
                batch_log_fh.close()
            return EXIT_GENERAL

        # --- Output results ---
        if args.format == "json":
            print(format_batch_result_json(batch_result))
        else:
            print(format_batch_result_text(batch_result))

        if batch_log_fh:
            batch_log_fh.close()
        return batch_result.exit_code

    # =======================================================================
    # --status: show all sessions
    # =======================================================================
    if args.status:
        _require_core()
        try:
            layered_hash = LayeredHash(project_root)
            session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
            sessions = session_mgr.list_sessions()  # type: ignore[attr-defined]
            for s in sessions:
                if s.meta.status == "busy" and not s.is_alive():
                    s.meta.status = "stale"
                staleness = layered_hash.compute_staleness(s.meta.hashes)
                s._stale_layers = [k for k, v in staleness.items() if v]
        except Exception as e:
            print(f"ERROR: Failed to list sessions: {e}", file=sys.stderr)
            return EXIT_SESSION

        if args.format == "json":
            print(format_status_json(sessions))
        else:
            print(format_status_text(sessions))
        return EXIT_OK

    # =======================================================================
    # --cleanup / --cleanup-all
    # =======================================================================
    if args.cleanup or args.cleanup_all:
        _require_core()
        try:
            session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
            if args.cleanup_all:
                # --cleanup-all: Remove absolutely all existing sessions.
                removed = session_mgr.cleanup(keep=0)  # type: ignore[attr-defined]
            else:
                # --cleanup: Retain (max_sessions - 1) sessions, removing only the oldest ones.
                # This ensures there is space to create exactly 1 new session before hitting the limit.
                # Note: It does NOT wipe all idle sessions. Use --cleanup-all for a full wipe.
                keep = config.limits.max_sessions - 1
                removed = session_mgr.cleanup(keep=max(keep, 0))  # type: ignore[attr-defined]
        except VivadoCoreError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return EXIT_SESSION

        if args.format == "json":
            print(json.dumps({"removed_sessions": removed}, indent=2))
        else:
            if removed:
                print(f"Removed sessions: {', '.join(removed)}")
            else:
                print("No sessions to remove.")
        return EXIT_OK

    # =======================================================================
    # --gen-config: regenerate cache_def.svh from YAML
    # =======================================================================
    if args.gen_config:
        _require_core()
        try:
            session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
            task_registry = TaskRegistry(tasks_path)  # type: ignore[call-arg]
            task_registry.load()  # type: ignore[attr-defined]
            layered_hash = LayeredHash(project_root)  # type: ignore[call-arg]
            sync = SyncPolicy(layered_hash)  # type: ignore[call-arg]
            ops = Operations(session_mgr, task_registry, sync, layered_hash)  # type: ignore[call-arg]
            generated_path = ops.gen_config()  # type: ignore[attr-defined]
        except VivadoCoreError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return EXIT_GENERAL
        except Exception as e:
            print(f"ERROR: Failed to regenerate config: {e}", file=sys.stderr)
            return EXIT_GENERAL

        if args.format == "json":
            print(json.dumps({"generated": generated_path}, indent=2))
        else:
            print(f"Generated: {generated_path}")
        return EXIT_OK

    # =======================================================================
    # Operation flags require a task
    # =======================================================================
    has_operation = any(
        [args.create, args.sim, args.refresh, args.bitstream, args.program, args.archive]
    )
    if has_operation and not task_name:
        print(
            "ERROR: Operation flags require -task NAME to be specified.",
            file=sys.stderr,
        )
        return EXIT_CONFIG

    if not has_operation and not args.status and not args.cleanup and not args.cleanup_all:
        parser.print_help()
        return EXIT_OK

    # --- Require core for operations ---
    _require_core()

    # task_name is guaranteed non-None here (checked above)
    assert task_name is not None

    # --- Instantiate core components ---
    try:
        task_registry = TaskRegistry(tasks_path)  # type: ignore[call-arg]
        task_registry.load()  # type: ignore[attr-defined]
        session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
        layered_hash = LayeredHash(project_root)  # type: ignore[call-arg]
        sync = SyncPolicy(layered_hash)  # type: ignore[call-arg]
        ops = Operations(session_mgr, task_registry, sync, layered_hash)  # type: ignore[call-arg]
    except VivadoCoreError as e:
        print(f"ERROR: Core initialization failed: {e}", file=sys.stderr)
        return EXIT_GENERAL

    # --- Resolve / create session ---
    assert session_name is not None
    assert task_def is not None
    try:
        if args.create:
            session = session_mgr.get_or_create(task_name, session_name)  # type: ignore[attr-defined]
        else:
            # Exact name match first, then most-recent session for the task.
            try:
                session = session_mgr.get_session(session_name)  # type: ignore[attr-defined]
            except SessionNotFoundError:  # type: ignore[name-defined]
                from tools.vivado_core.exceptions import SessionNotFoundError as _SNFE  # type: ignore[attr-defined]
                try:
                    session = session_mgr.find_session_for_task(task_name)  # type: ignore[attr-defined]
                except _SNFE:
                    raise _SNFE(
                        f"{session_name!r} (and no session found for task {task_name!r})"
                    )
    except VivadoCoreError as e:
        print(f"ERROR: Session not found: {e}", file=sys.stderr)
        print(
            f"  Hint: Run with -create to create a new session first:\n"
            f"        python -m tools.vivado_cli -task {task_name} -create",
            file=sys.stderr,
        )
        return EXIT_SESSION

    # --- Parse refresh layers ---
    refresh_layers: list[str] | None = None
    if args.layers:
        refresh_layers = [l.strip() for l in args.layers.split(",")]
        valid_layers = {"rtl", "tb", "coe", "fpga"}
        invalid = set(refresh_layers) - valid_layers
        if invalid:
            print(
                f"ERROR: Invalid layer(s): {', '.join(invalid)}. "
                f"Valid: {', '.join(sorted(valid_layers))}",
                file=sys.stderr,
            )
            return EXIT_CONFIG

    # --- Runtime override ---
    runtime = args.runtime or (task_def.runtime if task_def else None)

    # --- Debug defines from --debug argument ---
    debug_defines: dict[str, str] | None = None
    if getattr(args, "debug", None):
        debug_defines = _parse_debug_arg(args.debug)

    # --- Log file setup ---
    log_fh: Any = None
    if getattr(args, "log", None):
        log_path = Path(args.log)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_fh = log_path.open("a", encoding="utf-8")
        log_fh.write(f"\n{'=' * 60}\n")
        log_fh.write(f"Session: {session_name}  Task: {task_name}  Started: {_now_local()}\n")
        log_fh.write(f"{'=' * 60}\n")
        log_fh.flush()

        def _log_callback(line: str) -> None:
            ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            log_fh.write(f"[{ts}] {line}\n")
            log_fh.flush()

        session.output_callback = _log_callback

    # --- Execute operations in order ---
    results: list[dict[str, Any]] = []

    # -create
    if args.create:
        t0 = time.monotonic()
        timed_out = False
        try:
            task_obj = task_registry.get(task_name)  # type: ignore[attr-defined]
            res = ops.create(session, task_obj)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("create", session_name, task_name, success, output, duration, None, timed_out)
        )

    # -refresh
    if args.refresh:
        t0 = time.monotonic()
        timed_out = False
        try:
            preflight = sync.preflight_check(session, "refresh")  # type: ignore[attr-defined]
            res = ops.refresh(session, layers=refresh_layers)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
            preflight = None
        duration = time.monotonic() - t0
        staleness_dict = {l: True for l in preflight.stale_layers} if preflight else None
        results.append(
            _make_result("refresh", session_name, task_name, success, output, duration, staleness_dict, timed_out)
        )

    # -sim
    if args.sim:
        t0 = time.monotonic()
        staleness_dict = None
        timed_out = False
        try:
            preflight = sync.preflight_check(session, "sim")  # type: ignore[attr-defined]
            if preflight.stale_layers:
                print(f"WARNING: Stale layers detected: {', '.join(preflight.stale_layers)}")
            staleness_dict = {l: True for l in preflight.stale_layers}
            task_obj = task_registry.get(task_name)  # type: ignore[attr-defined]
            res = ops.sim(session, task_obj, runtime=runtime, debug_defines=debug_defines)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("sim", session_name, task_name, success, output, duration, staleness_dict, timed_out)
        )

    # -bitstream
    if args.bitstream:
        t0 = time.monotonic()
        staleness_dict = None
        timed_out = False
        try:
            preflight = sync.preflight_check(session, "bitstream")  # type: ignore[attr-defined]
            if preflight.stale_layers:
                print(f"WARNING: Stale layers detected: {', '.join(preflight.stale_layers)}")
            staleness_dict = {l: True for l in preflight.stale_layers}
            res = ops.bitstream(session)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("bitstream", session_name, task_name, success, output, duration, staleness_dict, timed_out)
        )

    # -program
    if args.program:
        t0 = time.monotonic()
        timed_out = False
        try:
            res = ops.program(session)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("program", session_name, task_name, success, output, duration, None, timed_out)
        )

    # -archive
    if args.archive:
        t0 = time.monotonic()
        timed_out = False
        try:
            res = ops.archive(session)  # type: ignore[attr-defined]
            output, success, timed_out = res.output, res.success, res.timed_out
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("archive", session_name, task_name, success, output, duration, None, timed_out)
        )

    # --- Output results ---
    for r in results:
        output_lines = r["output"].splitlines()
        filtered_lines = output_lines
        if args.filter_pat:
            filtered_lines = apply_filter(output_lines, args.filter_pat)
        r["filtered_output"] = "\n".join(filtered_lines)

        if args.format == "json":
            print(
                format_result_json(
                    r["operation"],
                    r["session"],
                    r["task"],
                    r["success"],
                    r["output"],
                    r["filtered_output"],
                    r["duration"],
                    r["staleness"],
                    r.get("timed_out", False),
                )
            )
        else:
            print(
                format_result_text(
                    r["operation"],
                    r["session"],
                    r["task"],
                    r["success"],
                    r["filtered_output"],
                    r["duration"],
                    r["staleness"],
                    r.get("timed_out", False),
                )
            )
            if r.get("timed_out"):
                print(
                    f"\n⚠ TIMEOUT: {r['operation']} operation timed out after {r['duration']:.1f}s.\n"
                    f"  The Vivado process was killed and will restart on the next command.\n"
                    f"  See output above for operation-specific hints.",
                    file=sys.stderr,
                )

    # --- Determine exit code ---
    if log_fh:
        log_fh.close()
    if any(not r["success"] for r in results):
        # Check if any failure was due to staleness
        for r in results:
            if not r["success"] and r["staleness"] and any(r["staleness"].values()):
                return EXIT_STALE
        return EXIT_GENERAL
    return EXIT_OK


def _make_result(
    operation: str,
    session: str,
    task: str,
    success: bool,
    output: str,
    duration: float,
    staleness: dict[str, bool] | None,
    timed_out: bool = False,
) -> dict[str, Any]:
    """Build a result dict for an operation."""
    return {
        "operation": operation,
        "session": session,
        "task": task,
        "success": success,
        "output": output,
        "filtered_output": "",
        "duration": duration,
        "staleness": staleness,
        "timed_out": timed_out,
    }


if __name__ == "__main__":
    sys.exit(main())
