"""Batch execution support for parallel multi-session Vivado operations.

Provides :class:`BatchExecutor` for running multiple tasks concurrently
using :class:`~concurrent.futures.ThreadPoolExecutor`, with configurable
error handling strategies and real-time progress tracking.

Example
-------
>>> from pathlib import Path
>>> from vivado_core.batch import BatchExecutor, BatchSpec, BatchTask
>>> spec = BatchSpec(
...     tasks=[BatchTask("cpu_full"), BatchTask("cpu_compute")],
...     max_parallel=2,
...     operations=["create", "sim"],
... )
>>> executor = BatchExecutor(session_mgr, task_registry, sync, layered_hash, config)
>>> result = executor.execute(spec)
"""
from __future__ import annotations

import fnmatch
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any

import yaml

from .exceptions import TaskNotFoundError, VivadoCoreError

if TYPE_CHECKING:
    from .config import GlobalConfig
    from .hash import LayeredHash
    from .operations import Operations
    from .session import Session, SessionManager
    from .sync import SyncPolicy
    from .tasks import TaskRegistry

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class BatchTask:
    """A single task within a batch execution plan.

    Attributes
    ----------
    task_name:
        Name of the task (must exist in the task registry).
    session_name:
        Explicit session name.  Auto-generated as
        ``f"{task_name}_batch_{timestamp}"`` if ``None``.
    runtime:
        Task-level simulation runtime override.
    """

    task_name: str
    session_name: str | None = None
    runtime: str | None = None


@dataclass
class BatchSpec:
    """Specification for a batch execution run.

    Attributes
    ----------
    tasks:
        List of tasks to execute.
    max_parallel:
        Upper bound on concurrent sessions.
    on_error:
        Error handling strategy: ``"continue"``, ``"fail-fast"``,
        or ``"stop-accepting"``.
    operations:
        Ordered list of operations to run per task
        (e.g. ``["create", "sim"]``).
    refresh_layers:
        Specific layers to refresh, or ``None`` for all stale layers.
    runtime_override:
        Global runtime override applied to all tasks.
    """

    tasks: list[BatchTask]
    max_parallel: int
    on_error: str = "continue"
    operations: list[str] = field(default_factory=list)
    refresh_layers: list[str] | None = None
    runtime_override: str | None = None


@dataclass
class TaskResult:
    """Result of a single task within a batch execution.

    Attributes
    ----------
    task_name:
        Name of the task.
    session_name:
        Name of the session used.
    success:
        ``True`` if all operations completed without error.
    operations:
        Per-step result dicts with keys ``"operation"``, ``"success"``,
        ``"output"``, ``"duration"``.
    duration:
        Total wall-clock time for this task.
    error:
        Error message if the task failed, ``None`` otherwise.
    """

    task_name: str
    session_name: str
    success: bool
    operations: list[dict[str, Any]] = field(default_factory=list)
    duration: float = 0.0
    error: str | None = None


@dataclass
class BatchResult:
    """Aggregated result of a batch execution.

    Attributes
    ----------
    total:
        Total number of tasks in the batch.
    succeeded:
        Number of tasks that completed successfully.
    failed:
        Number of tasks that failed.
    skipped:
        Number of tasks skipped (due to fail-fast / stop-accepting).
    duration:
        Total wall-clock time for the entire batch.
    results:
        Per-task results in completion order.
    exit_code:
        Process exit code (0 if all succeeded, 1 otherwise).
    """

    total: int
    succeeded: int
    failed: int
    skipped: int
    duration: float
    results: list[TaskResult] = field(default_factory=list)
    exit_code: int = 0


# ---------------------------------------------------------------------------
# Progress tracker
# ---------------------------------------------------------------------------

class ProgressTracker:
    """Real-time progress display for batch execution.

    Thread-safe; all public methods may be called from any thread.

    Parameters
    ----------
    total:
        Total number of tasks in the batch.
    quiet:
        If ``True``, suppress rendering (used for JSON output mode).
    """

    def __init__(self, total: int, quiet: bool = False) -> None:
        self._total = total
        self._quiet = quiet
        self._statuses: dict[str, str] = {}
        self._durations: dict[str, float] = {}
        self._order: list[str] = []
        self._lock = threading.Lock()

    def on_start(self, task_name: str) -> None:
        """Mark a task as running.

        Parameters
        ----------
        task_name:
            Name of the task that just started.
        """
        with self._lock:
            self._statuses[task_name] = "RUNNING"
            if task_name not in self._order:
                self._order.append(task_name)
        if not self._quiet:
            logger.info("Batch task started: %s", task_name)

    def on_complete(self, task_name: str, success: bool, duration: float) -> None:
        """Mark a task as completed.

        Parameters
        ----------
        task_name:
            Name of the completed task.
        success:
            Whether the task succeeded.
        duration:
            Wall-clock duration in seconds.
        """
        status = "PASS" if success else "FAIL"
        with self._lock:
            self._statuses[task_name] = status
            self._durations[task_name] = duration
        if not self._quiet:
            logger.info("Batch task %s: %s (%.1fs)", task_name, status, duration)

    def on_skip(self, task_name: str) -> None:
        """Mark a task as skipped.

        Parameters
        ----------
        task_name:
            Name of the skipped task.
        """
        with self._lock:
            self._statuses[task_name] = "SKIP"
            if task_name not in self._order:
                self._order.append(task_name)
        if not self._quiet:
            logger.info("Batch task skipped: %s", task_name)

    def render(self) -> str:
        """Render the progress panel as a multi-line string.

        Returns
        -------
        str
            Formatted progress display, e.g.::

                [1/5] cpu_full    RUNNING  (12.3s)
                [2/5] cpu_compute PASS     (8.1s)
                [3/5] cpu_trap    FAIL     (5.2s)
                [4/5] cpu_fencei  WAITING
                [5/5] cpu_priv    WAITING
        """
        lines: list[str] = []
        with self._lock:
            order = list(self._order)
            # Add any tasks not yet in order (not started)
            all_tasks = set(self._statuses.keys())
            for t in all_tasks:
                if t not in order:
                    order.append(t)

            for idx, task_name in enumerate(order, start=1):
                status = self._statuses.get(task_name, "WAITING")
                dur = self._durations.get(task_name)
                if dur is not None:
                    dur_str = f"({dur:.1f}s)"
                else:
                    dur_str = ""
                lines.append(
                    f"[{idx}/{self._total}] {task_name:<16s}{status:<9s}{dur_str}"
                )

        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Batch executor
# ---------------------------------------------------------------------------

class BatchExecutor:
    """Execute multiple tasks in parallel with configurable error handling.

    Parameters
    ----------
    session_mgr:
        Session manager for creating/retrieving sessions.
    task_registry:
        Task registry for looking up task configurations.
    sync:
        Synchronisation policy for preflight checks.
    layered_hash:
        Hash computer for staleness detection.
    config:
        Global configuration.
    """

    def __init__(
        self,
        session_mgr: SessionManager,
        task_registry: TaskRegistry,
        sync: SyncPolicy,
        layered_hash: LayeredHash,
        config: GlobalConfig,
    ) -> None:
        self._session_mgr = session_mgr
        self._task_registry = task_registry
        self._sync = sync
        self._layered_hash = layered_hash
        self._config = config

    def execute(self, spec: BatchSpec) -> BatchResult:
        """Execute a batch specification.

        Parameters
        ----------
        spec:
            Batch specification defining tasks, parallelism, and error
            handling strategy.

        Returns
        -------
        BatchResult
            Aggregated results for all tasks.
        """
        t0 = time.monotonic()

        # --- Validate all task names ---
        for bt in spec.tasks:
            if bt.task_name not in self._task_registry:
                raise TaskNotFoundError(bt.task_name)

        # --- Pre-check resource limits ---
        existing_sessions = self._session_mgr.list_sessions()
        if len(existing_sessions) + len(spec.tasks) > self._config.limits.max_sessions:
            logger.warning(
                "Batch may exceed session limit: %d existing + %d batch > %d max",
                len(existing_sessions),
                len(spec.tasks),
                self._config.limits.max_sessions,
            )

        # --- Cancellation event for fail-fast ---
        cancel = threading.Event()
        # Track whether we've seen a failure (for stop-accepting)
        failure_seen = threading.Event()

        # --- Progress tracker ---
        tracker = ProgressTracker(total=len(spec.tasks))

        # --- Determine effective parallelism ---
        max_workers = min(spec.max_parallel, self._config.limits.max_concurrent)
        max_workers = max(max_workers, 1)

        # --- Submit tasks ---
        results: list[TaskResult] = []
        results_lock = threading.Lock()

        # For stop-accepting: track which tasks were submitted
        submitted: set[str] = set()
        submitted_lock = threading.Lock()

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures: dict[Any, BatchTask] = {}

            for bt in spec.tasks:
                # stop-accepting: don't submit new tasks after first failure
                if spec.on_error == "stop-accepting" and failure_seen.is_set():
                    # Skip this task
                    tracker.on_skip(bt.task_name)
                    skipped_result = TaskResult(
                        task_name=bt.task_name,
                        session_name=bt.session_name or "",
                        success=False,
                        error="Skipped: stop-accepting after earlier failure",
                    )
                    with results_lock:
                        results.append(skipped_result)
                    continue

                future = executor.submit(
                    self._execute_single, bt, spec, cancel, tracker
                )
                futures[future] = bt
                with submitted_lock:
                    submitted.add(bt.task_name)

            # Collect results as they complete
            for future in as_completed(futures):
                bt = futures[future]
                try:
                    task_result = future.result()
                except Exception as exc:
                    task_result = TaskResult(
                        task_name=bt.task_name,
                        session_name=bt.session_name or "",
                        success=False,
                        error=str(exc),
                    )
                    tracker.on_complete(bt.task_name, False, 0.0)

                with results_lock:
                    results.append(task_result)

                # Handle error strategies
                if not task_result.success:
                    if spec.on_error == "fail-fast":
                        cancel.set()
                        logger.warning(
                            "Fail-fast: cancelling remaining tasks after %s failed",
                            bt.task_name,
                        )
                    elif spec.on_error == "stop-accepting":
                        failure_seen.set()
                        logger.warning(
                            "Stop-accepting: no new tasks after %s failed",
                            bt.task_name,
                        )

        # --- Aggregate ---
        duration = time.monotonic() - t0
        succeeded = sum(1 for r in results if r.success)
        failed = sum(1 for r in results if not r.success and r.error != "Skipped: stop-accepting after earlier failure")
        skipped = sum(1 for r in results if r.error and r.error.startswith("Skipped:"))
        # Also count tasks that were skipped due to cancel event
        skipped += sum(1 for r in results if r.error and r.error.startswith("Cancelled"))

        exit_code = 0 if failed == 0 and all(r.success for r in results) else 1

        return BatchResult(
            total=len(spec.tasks),
            succeeded=succeeded,
            failed=failed,
            skipped=skipped,
            duration=duration,
            results=results,
            exit_code=exit_code,
        )

    def _execute_single(
        self,
        batch_task: BatchTask,
        spec: BatchSpec,
        cancel: threading.Event,
        tracker: ProgressTracker,
    ) -> TaskResult:
        """Execute a single batch task.

        Parameters
        ----------
        batch_task:
            The batch task to execute.
        spec:
            The parent batch specification.
        cancel:
            Cancellation event (set by fail-fast).
        tracker:
            Progress tracker for status updates.

        Returns
        -------
        TaskResult
        """
        # --- Check cancellation ---
        if cancel.is_set():
            tracker.on_skip(batch_task.task_name)
            return TaskResult(
                task_name=batch_task.task_name,
                session_name=batch_task.session_name or "",
                success=False,
                error="Cancelled by fail-fast",
            )

        # --- Generate session name ---
        if batch_task.session_name:
            session_name = batch_task.session_name
        else:
            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
            session_name = f"{batch_task.task_name}_batch_{ts}"

        tracker.on_start(batch_task.task_name)
        t0 = time.monotonic()

        # --- Create/get session ---
        try:
            session = self._session_mgr.get_or_create(
                batch_task.task_name,
                session_name,
                self._task_registry,
            )
        except VivadoCoreError as exc:
            duration = time.monotonic() - t0
            tracker.on_complete(batch_task.task_name, False, duration)
            return TaskResult(
                task_name=batch_task.task_name,
                session_name=session_name,
                success=False,
                duration=duration,
                error=str(exc),
            )

        # --- Execute operations ---
        ops = self._get_operations()
        task_obj = self._task_registry.get(batch_task.task_name)
        runtime = spec.runtime_override or batch_task.runtime or task_obj.runtime or None
        op_results: list[dict[str, Any]] = []
        all_success = True

        for operation in spec.operations:
            # Check cancellation before each step
            if cancel.is_set():
                all_success = False
                op_results.append({
                    "operation": operation,
                    "success": False,
                    "output": "",
                    "duration": 0.0,
                    "error": "Cancelled by fail-fast",
                })
                continue

            step_t0 = time.monotonic()
            try:
                res = self._run_operation(
                    ops, session, task_obj, operation, runtime, spec.refresh_layers
                )
                step_duration = time.monotonic() - step_t0
                op_results.append({
                    "operation": operation,
                    "success": res.success,
                    "output": res.output,
                    "duration": step_duration,
                })
                if not res.success:
                    all_success = False
            except VivadoCoreError as exc:
                step_duration = time.monotonic() - step_t0
                op_results.append({
                    "operation": operation,
                    "success": False,
                    "output": str(exc),
                    "duration": step_duration,
                    "error": str(exc),
                })
                all_success = False
            except Exception as exc:
                step_duration = time.monotonic() - step_t0
                op_results.append({
                    "operation": operation,
                    "success": False,
                    "output": str(exc),
                    "duration": step_duration,
                    "error": str(exc),
                })
                all_success = False

        duration = time.monotonic() - t0
        tracker.on_complete(batch_task.task_name, all_success, duration)

        # Batch mode explicit resource cleanup:
        # Stop Vivado to release the concurrent semaphore and drop running_count(),
        # allowing subsequent tasks in the batch to acquire a concurrency slot.
        try:
            session.stop_vivado()
        except Exception as e:
            logger.warning("Failed to stop Vivado for session %s: %s", session_name, e)

        return TaskResult(
            task_name=batch_task.task_name,
            session_name=session_name,
            success=all_success,
            operations=op_results,
            duration=duration,
            error=None if all_success else "One or more operations failed",
        )

    def _get_operations(self) -> Operations:
        """Create an Operations instance bound to our core components.

        Returns
        -------
        Operations
        """
        from .operations import Operations
        return Operations(
            self._session_mgr,
            self._task_registry,
            self._sync,
            self._layered_hash,
        )

    def _run_operation(
        self,
        ops: Operations,
        session: Session,
        task: Any,
        operation: str,
        runtime: str | None,
        refresh_layers: list[str] | None,
    ) -> Any:
        """Dispatch a single operation.

        Parameters
        ----------
        ops:
            Operations instance.
        session:
            Target session.
        task:
            Task configuration.
        operation:
            Operation name (``"create"``, ``"sim"``, etc.).
        runtime:
            Simulation runtime override.
        refresh_layers:
            Layers to refresh (for refresh operation).

        Returns
        -------
        ExecuteResult
        """
        if operation == "create":
            return ops.create(session, task)
        elif operation == "refresh":
            return ops.refresh(session, layers=refresh_layers)
        elif operation == "sim":
            return ops.sim(session, task, runtime=runtime)
        elif operation == "bitstream":
            return ops.bitstream(session)
        elif operation == "program":
            return ops.program(session)
        elif operation == "archive":
            return ops.archive(session)
        else:
            raise VivadoCoreError(f"Unknown batch operation: {operation!r}")


# ---------------------------------------------------------------------------
# Glob expansion
# ---------------------------------------------------------------------------

def expand_batch_spec(spec: str, task_names: list[str]) -> list[str]:
    """Expand comma-separated task names with glob support.

    Parameters
    ----------
    spec:
        Comma-separated task names or glob patterns.
    task_names:
        All available task names (from the registry).

    Returns
    -------
    list[str]
        Expanded, validated, deduplicated task names preserving order.

    Examples
    --------
    >>> expand_batch_spec("cpu_full,cpu_compute", ["cpu_full", "cpu_compute", "uart"])
    ['cpu_full', 'cpu_compute']
    >>> expand_batch_spec("isa_*", ["isa_rv32i", "isa_rv64i", "cpu_full"])
    ['isa_rv32i', 'isa_rv64i']
    >>> expand_batch_spec("cpu_*,uart_hello", ["cpu_full", "cpu_compute", "uart_hello"])
    ['cpu_full', 'cpu_compute', 'uart_hello']
    """
    parts = [p.strip() for p in spec.split(",") if p.strip()]
    expanded: list[str] = []
    seen: set[str] = set()

    for part in parts:
        # Check if it's a glob pattern (contains * or ? or [...])
        if any(ch in part for ch in ("*", "?", "[")):
            matches = [name for name in task_names if fnmatch.fnmatch(name, part)]
            if not matches:
                logger.warning("Batch pattern %r matched no tasks", part)
            for match in matches:
                if match not in seen:
                    expanded.append(match)
                    seen.add(match)
        else:
            # Exact name
            if part not in task_names:
                raise TaskNotFoundError(part)
            if part not in seen:
                expanded.append(part)
                seen.add(part)

    return expanded


# ---------------------------------------------------------------------------
# YAML batch plan loader
# ---------------------------------------------------------------------------

def load_batch_plan(path: Path) -> BatchSpec:
    """Load a batch plan from a YAML file.

    Expected YAML format::

        max_parallel: 3
        on_error: continue
        operations: [create, sim]
        tasks:
          - task: cpu_full
            runtime: 5ms
          - task: cpu_compute
        # OR use a glob pattern:
        task_pattern: "cpu_*"

    Parameters
    ----------
    path:
        Path to the YAML batch plan file.

    Returns
    -------
    BatchSpec
        Parsed batch specification.

    Raises
    ------
    FileNotFoundError
        If the YAML file does not exist.
    ValueError
        If the YAML file is missing required fields.
    """
    if not path.is_file():
        raise FileNotFoundError(f"Batch plan file not found: {path}")

    with path.open("r", encoding="utf-8") as fh:
        raw: dict = yaml.safe_load(fh) or {}

    max_parallel = int(raw.get("max_parallel", 2))
    on_error = str(raw.get("on_error", "continue"))
    operations = raw.get("operations", [])
    if isinstance(operations, str):
        operations = [o.strip() for o in operations.split(",")]
    operations = [str(o) for o in operations]

    refresh_layers = raw.get("refresh_layers")
    if refresh_layers is not None:
        refresh_layers = [str(l) for l in refresh_layers]

    runtime_override = raw.get("runtime_override")
    if runtime_override is not None:
        runtime_override = str(runtime_override)

    # Build task list
    tasks: list[BatchTask] = []
    tasks_raw = raw.get("tasks", [])
    if isinstance(tasks_raw, list):
        for item in tasks_raw:
            if isinstance(item, dict):
                task_name = item.get("task", "")
                if not task_name:
                    raise ValueError(
                        f"Batch plan task entry missing 'task' field: {item}"
                    )
                tasks.append(BatchTask(
                    task_name=str(task_name),
                    session_name=item.get("session"),
                    runtime=item.get("runtime"),
                ))
            elif isinstance(item, str):
                tasks.append(BatchTask(task_name=item))

    # If task_pattern is specified, it will be expanded later by the caller
    # using expand_batch_spec. Store it as a special marker.
    task_pattern = raw.get("task_pattern")
    if task_pattern and not tasks:
        # We can't expand here because we don't have the task registry.
        # Store the pattern as a single BatchTask with a marker prefix
        # that the CLI will recognize and expand.
        tasks.append(BatchTask(task_name=f"__pattern__:{task_pattern}"))

    if not tasks:
        raise ValueError("Batch plan has no tasks defined")

    return BatchSpec(
        tasks=tasks,
        max_parallel=max_parallel,
        on_error=on_error,
        operations=operations,
        refresh_layers=refresh_layers,
        runtime_override=runtime_override,
    )
