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
from pathlib import Path
from typing import Any

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


@dataclass
class VivadoConfig:
    limits: Limits = field(default_factory=Limits)
    vivado_path: str = "vivado.bat"
    proj_name: str = "simplecpu_bus"
    device_part: str = "xc7a200tfbg676-2"


def load_config(path: Path) -> VivadoConfig:
    """Load vivado_config.yaml into VivadoConfig dataclass."""
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
    )
    return VivadoConfig(
        limits=limits,
        vivado_path=str(raw.get("vivado_path", "vivado.bat")),
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
    coe: str | None = None
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
            coe=spec.get("coe"),
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
) -> str:
    """Format operation result as human-readable text."""
    lines: list[str] = []
    lines.append(f"Operation : {operation}")
    lines.append(f"Session   : {session}")
    lines.append(f"Task      : {task}")
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
) -> str:
    """Format operation result as JSON."""
    result: dict[str, Any] = {
        "operation": operation,
        "session": session,
        "task": task,
        "success": success,
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
    parser.add_argument("-sim", action="store_true", help="Run simulation")
    parser.add_argument(
        "-runtime", metavar="TIME", help="Override simulation runtime"
    )
    parser.add_argument(
        "-refresh", action="store_true", help="Refresh session (sync source changes)"
    )
    parser.add_argument(
        "-bitstream", action="store_true", help="Generate bitstream"
    )
    parser.add_argument(
        "-hw-connect", action="store_true", help="Connect to hardware server"
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
        help="Remove oldest sessions to stay within limit",
    )
    parser.add_argument(
        "--cleanup-all", action="store_true", help="Remove ALL sessions"
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

    return parser


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
    # --status: show all sessions
    # =======================================================================
    if args.status:
        _require_core()
        try:
            session_mgr = SessionManager(project_root, config)  # type: ignore[call-arg]
            sessions = session_mgr.list_sessions()  # type: ignore[attr-defined]
        except VivadoCoreError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return EXIT_SESSION
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
                removed = session_mgr.cleanup(keep=0)  # type: ignore[attr-defined]
            else:
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
    # Operation flags require a task
    # =======================================================================
    has_operation = any(
        [args.create, args.sim, args.refresh, args.bitstream, args.hw_connect, args.program, args.archive]
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
        session = session_mgr.get_or_create(task_name, session_name)  # type: ignore[attr-defined]
    except VivadoCoreError as e:
        print(f"ERROR: Session error: {e}", file=sys.stderr)
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

    # --- Execute operations in order ---
    results: list[dict[str, Any]] = []

    # -create
    if args.create:
        t0 = time.monotonic()
        try:
            task_obj = task_registry.get(task_name)  # type: ignore[attr-defined]
            res = ops.create(session, task_obj)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("create", session_name, task_name, success, output, duration, None)
        )

    # -refresh
    if args.refresh:
        t0 = time.monotonic()
        try:
            preflight = sync.preflight_check(session, "refresh")  # type: ignore[attr-defined]
            res = ops.refresh(session, layers=refresh_layers)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
            preflight = None
        duration = time.monotonic() - t0
        staleness_dict = {l: True for l in preflight.stale_layers} if preflight else None
        results.append(
            _make_result("refresh", session_name, task_name, success, output, duration, staleness_dict)
        )

    # -sim
    if args.sim:
        t0 = time.monotonic()
        staleness_dict = None
        try:
            preflight = sync.preflight_check(session, "sim")  # type: ignore[attr-defined]
            if preflight.stale_layers:
                print(f"WARNING: Stale layers detected: {', '.join(preflight.stale_layers)}")
            staleness_dict = {l: True for l in preflight.stale_layers}
            task_obj = task_registry.get(task_name)  # type: ignore[attr-defined]
            res = ops.sim(session, task_obj, runtime=runtime)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("sim", session_name, task_name, success, output, duration, staleness_dict)
        )

    # -bitstream
    if args.bitstream:
        t0 = time.monotonic()
        staleness_dict = None
        try:
            preflight = sync.preflight_check(session, "bitstream")  # type: ignore[attr-defined]
            if preflight.stale_layers:
                print(f"WARNING: Stale layers detected: {', '.join(preflight.stale_layers)}")
            staleness_dict = {l: True for l in preflight.stale_layers}
            res = ops.bitstream(session)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("bitstream", session_name, task_name, success, output, duration, staleness_dict)
        )

    # -hw-connect
    if args.hw_connect:
        t0 = time.monotonic()
        try:
            res = ops.hw_connect(session)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("hw_connect", session_name, task_name, success, output, duration, None)
        )

    # -program
    if args.program:
        t0 = time.monotonic()
        try:
            res = ops.program(session)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("program", session_name, task_name, success, output, duration, None)
        )

    # -archive
    if args.archive:
        t0 = time.monotonic()
        try:
            res = ops.archive(session)  # type: ignore[attr-defined]
            output, success = res.output, res.success
        except VivadoCoreError as e:
            output, success = str(e), False
        duration = time.monotonic() - t0
        results.append(
            _make_result("archive", session_name, task_name, success, output, duration, None)
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
                )
            )

    # --- Determine exit code ---
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
    }


if __name__ == "__main__":
    sys.exit(main())
