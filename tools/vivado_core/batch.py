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
from typing import TYPE_CHECKING, Any, Callable

import yaml

from .exceptions import (
    SessionLimitError,
    SessionNotFoundError,
    TaskNotFoundError,
    VivadoCoreError,
)

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
    log_dir:
        Directory for per-session log files.  When set, each session
        automatically writes Vivado output to ``{log_dir}/{session_name}.log``.
    """

    tasks: list[BatchTask]
    max_parallel: int
    on_error: str = "continue"
    operations: list[str] = field(default_factory=list)
    refresh_layers: list[str] | None = None
    runtime_override: str | None = None
    log_dir: str | None = None


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
    expected_fail:
        ``True`` if this task was annotated ``expected_fail: true`` in
        ``tasks.yaml``.  A failure with ``expected_fail=True`` is
        reported as ``XFAIL`` (expected failure) and does not count
        toward the batch ``failed`` total.
    """

    task_name: str
    session_name: str
    success: bool
    operations: list[dict[str, Any]] = field(default_factory=list)
    duration: float = 0.0
    error: str | None = None
    expected_fail: bool = False


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
        Number of tasks that failed (excluding expected failures).
    skipped:
        Number of tasks skipped (due to fail-fast / stop-accepting).
    duration:
        Total wall-clock time for the entire batch.
    results:
        Per-task results in completion order.
    exit_code:
        Process exit code (0 if all succeeded, 1 otherwise).
    xfailed:
        Number of tasks that failed as expected (``expected_fail: true``).
    """

    total: int
    succeeded: int
    failed: int
    skipped: int
    duration: float
    results: list[TaskResult] = field(default_factory=list)
    exit_code: int = 0
    xfailed: int = 0


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
        output_callback: Callable[[str], None] | None = None,
    ) -> None:
        self._session_mgr = session_mgr
        self._task_registry = task_registry
        self._sync = sync
        self._layered_hash = layered_hash
        self._config = config
        self._output_callback = output_callback

    def execute(self, spec: BatchSpec) -> BatchResult:
        """Execute a batch specification.

        When the number of tasks requiring new sessions exceeds
        ``max_sessions``, the tasks are automatically split into rounds.
        Each round runs at most ``max_sessions`` tasks concurrently.
        After a round completes, its sessions are destroyed to free
        slots for the next round.

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

        # --- Determine if round-based execution is needed ---
        needs_create = "create" in spec.operations
        max_sessions = self._config.limits.max_sessions

        if needs_create and len(spec.tasks) > max_sessions:
            return self._execute_rounds(spec, max_sessions, t0)

        # --- Single-round (or no-create) path ---
        return self._execute_single_round(spec, t0)

    def _execute_rounds(
        self, spec: BatchSpec, max_sessions: int, t0: float
    ) -> BatchResult:
        """Execute tasks in multiple rounds, destroying sessions between rounds.

        Parameters
        ----------
        spec:
            Original batch specification.
        max_sessions:
            Maximum sessions per round.
        t0:
            Start time from the outer call.

        Returns
        -------
        BatchResult
        """
        all_results: list[TaskResult] = []
        all_tasks = spec.tasks
        total = len(all_tasks)
        num_rounds = (total + max_sessions - 1) // max_sessions

        logger.info(
            "Batch: %d tasks exceed max_sessions=%d — splitting into %d rounds",
            total, max_sessions, num_rounds,
        )

        global_cancel = threading.Event()
        global_failure_seen = threading.Event()
        global_skipped = 0

        for round_idx in range(num_rounds):
            if global_cancel.is_set():
                remaining_start = round_idx * max_sessions
                for bt in all_tasks[remaining_start:]:
                    all_results.append(TaskResult(
                        task_name=bt.task_name,
                        session_name=bt.session_name or "",
                        success=False,
                        error="Cancelled by fail-fast (round skipped)",
                    ))
                    global_skipped += 1
                break

            if spec.on_error == "stop-accepting" and global_failure_seen.is_set():
                remaining_start = round_idx * max_sessions
                for bt in all_tasks[remaining_start:]:
                    all_results.append(TaskResult(
                        task_name=bt.task_name,
                        session_name=bt.session_name or "",
                        success=False,
                        error="Skipped: stop-accepting after earlier failure",
                    ))
                    global_skipped += 1
                break

            start = round_idx * max_sessions
            end = min(start + max_sessions, total)
            round_tasks = all_tasks[start:end]

            logger.info(
                "Round %d/%d: tasks %d-%d (%d tasks)",
                round_idx + 1, num_rounds, start + 1, end, len(round_tasks),
            )

            round_spec = BatchSpec(
                tasks=round_tasks,
                max_parallel=min(spec.max_parallel, len(round_tasks)),
                on_error=spec.on_error,
                operations=spec.operations,
                refresh_layers=spec.refresh_layers,
                runtime_override=spec.runtime_override,
                log_dir=spec.log_dir,
            )

            round_result = self._execute_single_round(round_spec, time.monotonic())

            all_results.extend(round_result.results)

            for tr in round_result.results:
                if not tr.success and not tr.expected_fail:
                    if spec.on_error == "fail-fast":
                        global_cancel.set()
                    elif spec.on_error == "stop-accepting":
                        global_failure_seen.set()

            # Destroy sessions from this round to free slots for the next round
            # (skip on the last round — no next round needs the slots)
            if round_idx < num_rounds - 1:
                destroyed = []
                for tr in round_result.results:
                    if tr.session_name:
                        try:
                            self._session_mgr.destroy_session(tr.session_name)
                            destroyed.append(tr.session_name)
                        except Exception as e:
                            logger.warning(
                                "Failed to destroy session %s: %s",
                                tr.session_name, e,
                            )
                if destroyed:
                    logger.info(
                        "Round %d complete: destroyed %d sessions (%s)",
                        round_idx + 1, len(destroyed),
                        ", ".join(destroyed[:5]) + ("..." if len(destroyed) > 5 else ""),
                    )

        # --- Aggregate across all rounds ---
        duration = time.monotonic() - t0
        succeeded = sum(1 for r in all_results if r.success)
        failed = sum(
            1 for r in all_results
            if not r.success
            and not r.expected_fail
            and r.error != "Skipped: stop-accepting after earlier failure"
            and not (r.error and r.error.startswith("Cancelled"))
        )
        xfailed = sum(1 for r in all_results if not r.success and r.expected_fail)
        skipped = sum(
            1 for r in all_results
            if r.error and (
                r.error.startswith("Skipped:")
                or r.error.startswith("Cancelled")
            )
        )

        exit_code = 0 if failed == 0 and all(
            r.success or r.expected_fail for r in all_results
        ) else 1

        return BatchResult(
            total=total,
            succeeded=succeeded,
            failed=failed,
            skipped=skipped,
            duration=duration,
            results=all_results,
            exit_code=exit_code,
            xfailed=xfailed,
        )

    def _execute_single_round(self, spec: BatchSpec, t0: float) -> BatchResult:
        """Execute a single round of batch tasks (fits within max_sessions).

        Parameters
        ----------
        spec:
            Batch specification for this round.
        t0:
            Monotonic start time.

        Returns
        -------
        BatchResult
        """
        # --- Pre-check resource limits ---
        existing_sessions = self._session_mgr.list_sessions()
        new_sessions_needed = len(spec.tasks)
        if "create" not in spec.operations:
            new_sessions_needed = 0

        if new_sessions_needed > 0:
            available_slots = max(
                self._config.limits.max_sessions - len(existing_sessions), 0
            )
            if new_sessions_needed > self._config.limits.max_sessions:
                raise SessionLimitError(
                    len(existing_sessions),
                    self._config.limits.max_sessions,
                )
            if new_sessions_needed > available_slots and new_sessions_needed > 1:
                logger.warning(
                    "Batch requires %d new sessions but only %d slots available "
                    "(%d existing, %d max). Auto-eviction will reclaim old sessions.",
                    new_sessions_needed,
                    available_slots,
                    len(existing_sessions),
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
                if not task_result.success and not task_result.expected_fail:
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
        failed = sum(
            1 for r in results
            if not r.success
            and not r.expected_fail
            and r.error != "Skipped: stop-accepting after earlier failure"
        )
        xfailed = sum(1 for r in results if not r.success and r.expected_fail)
        skipped = sum(1 for r in results if r.error and r.error.startswith("Skipped:"))
        skipped += sum(1 for r in results if r.error and r.error.startswith("Cancelled"))

        exit_code = 0 if failed == 0 and all(
            r.success or r.expected_fail for r in results
        ) else 1

        return BatchResult(
            total=len(spec.tasks),
            succeeded=succeeded,
            failed=failed,
            skipped=skipped,
            duration=duration,
            results=results,
            exit_code=exit_code,
            xfailed=xfailed,
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

        .. warning::

            **Batch mode + no-create + session-reuse crash.**

            ``vivado_cli -batch "A,B" -sim`` (without ``-create``) relies on
            existing sessions.  When sessions do not exist, every parallel task
            raises ``SessionNotFoundError`` — all tasks fail harmlessly.

            When sessions **do** exist, each task finds its own session and
            starts a Vivado subprocess.  The crash scenario:

            1. Two+ tasks run ``sim()`` in parallel (gated by the concurrent
               semaphore at ``max_concurrent``).
            2. After each task completes, ``stop_vivado()`` (line ~808) kills
               its Vivado process and **releases** the semaphore.
            3. **The release immediately allows another waiting Vivado to start
               while the previous Vivado's child processes (xelab/xsim) may
               still be terminating.**
            4. Vivado 2018.3's ``launch_simulation`` spawns ``xelab`` / ``xsim``
               children that use in-memory library caches.  When a sibling
               process's Vivado is killed and its semaphore released concurrently,
               the shared Vivado binary cache or pid-reuse can corrupt xsim
               state, causing ``xelab``/``xsim`` to crash or produce corrupted
               output (segfault, silent truncation, or ``cannot find design
               unit``).

            **Mitigation**: always use ``-create -sim`` (not ``-sim`` alone)
            in batch mode so each task gets a fresh project from scratch.
            See also the ``stop_vivado()`` call at ``batch.py`` line ~808 for
            the cleanup code path.
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

        # --- Per-session log file (auto-logging in batch mode) ---
        session_log_fh: Any = None
        if spec.log_dir:
            log_dir = Path(spec.log_dir)
            log_dir.mkdir(parents=True, exist_ok=True)
            log_path = log_dir / f"{session_name}.log"
            session_log_fh = log_path.open("a", encoding="utf-8")
            session_log_fh.write(f"\n{'=' * 60}\n")
            session_log_fh.write(f"Session: {session_name}  Task: {batch_task.task_name}  Started: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')}\n")
            session_log_fh.write(f"{'=' * 60}\n")
            session_log_fh.flush()

        tracker.on_start(batch_task.task_name)
        t0 = time.monotonic()

        # --- Create/get session ---
        try:
            if "create" in spec.operations:
                session = self._session_mgr.get_or_create(
                    batch_task.task_name,
                    session_name,
                    self._task_registry,
                )
            else:
                # Without 'create', the session must already exist.
                if batch_task.session_name:
                    session = self._session_mgr.get_session(batch_task.session_name)
                else:
                    session = self._session_mgr.find_session_for_task(
                        batch_task.task_name
                    )
        except VivadoCoreError as exc:
            duration = time.monotonic() - t0
            tracker.on_complete(batch_task.task_name, False, duration)
            if session_log_fh is not None:
                try:
                    session_log_fh.close()
                except Exception:
                    pass
            return TaskResult(
                task_name=batch_task.task_name,
                session_name=session_name,
                success=False,
                duration=duration,
                error=str(exc),
            )

        # --- Execute operations ---
        if self._output_callback is not None:
            session.output_callback = self._output_callback
        if session_log_fh is not None:
            def _session_log_cb(line: str) -> None:
                ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                session_log_fh.write(f"[{ts}] {line}\n")
                session_log_fh.flush()
            if session.output_callback is not None:
                outer_cb = session.output_callback
                def _dual_cb(line: str) -> None:
                    outer_cb(line)
                    _session_log_cb(line)
                session.output_callback = _dual_cb
            else:
                session.output_callback = _session_log_cb
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
                    "timed_out": res.timed_out,
                })
                if not res.success:
                    all_success = False
                    # Abort remaining operations — a failed create/refresh
                    # leaves the project in an undefined state; running sim
                    # or bitstream against it would produce meaningless results.
                    remaining = spec.operations[spec.operations.index(operation) + 1:]
                    if remaining:
                        skip_msg = f"Aborted: {operation} failed, skipping {remaining}"
                        for skip_op in remaining:
                            op_results.append({
                                "operation": skip_op,
                                "success": False,
                                "duration": 0.0,
                                "error": skip_msg,
                            })
                        break
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
                break
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
                break

        duration = time.monotonic() - t0
        tracker.on_complete(batch_task.task_name, all_success, duration)

        # Batch mode explicit resource cleanup:
        # Stop Vivado to release the concurrent semaphore and drop running_count(),
        # allowing subsequent tasks in the batch to acquire a concurrency slot.
        #
        # !!! KNOWN CRASH: stop_vivado() + semaphore release + concurrent
        # start_vivado() on another session can cause xelab/xsim child-process
        # corruption in Vivado 2018.3 (segfault / "cannot find design unit").
        # See docstring of _execute_single for the full root-cause analysis.
        # Mitigation: always use "-create -sim" (not "-sim" alone) in batch.
        try:
            session.stop_vivado()
        except Exception as e:
            logger.warning("Failed to stop Vivado for session %s: %s", session_name, e)

        if session_log_fh is not None:
            try:
                session_log_fh.close()
            except Exception:
                pass

        try:
            task_cfg = self._task_registry.get(batch_task.task_name)
            expected_fail = task_cfg.expected_fail
        except Exception:
            expected_fail = False

        return TaskResult(
            task_name=batch_task.task_name,
            session_name=session_name,
            success=all_success,
            operations=op_results,
            duration=duration,
            error=None if all_success else "One or more operations failed",
            expected_fail=expected_fail,
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

    log_dir = raw.get("log_dir")
    if log_dir is not None:
        log_dir = str(log_dir)

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
        log_dir=log_dir,
    )
