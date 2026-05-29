"""Session management for isolated Vivado project directories.

Each :class:`Session` wraps a dedicated project directory under
``project/<session_name>/`` and optionally manages a running Vivado
TCL subprocess.  The :class:`SessionManager` coordinates multiple
sessions, enforces resource limits, and handles cleanup.
"""
from __future__ import annotations

import shutil
import subprocess
import threading
import threading
import time
import queue

import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

from .config import GlobalConfig
from .exceptions import (
    ConcurrentLimitError,
    DiskLimitError,
    SessionLimitError,
    SessionNotFoundError,
    VivadoProcessError,
    VivadoTimeoutError,
)

if TYPE_CHECKING:
    from .tasks import TaskRegistry


# ---------------------------------------------------------------------------
# Execute result
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ExecuteResult:
    """Result of a single Vivado TCL command execution."""

    output: str
    """Captured stdout/stderr text."""

    success: bool
    """``True`` if the command completed without a Vivado-reported error."""

    timed_out: bool
    """``True`` if the command exceeded its timeout."""

    duration: float
    """Wall-clock execution time in seconds."""


# ---------------------------------------------------------------------------
# Session metadata (persisted)
# ---------------------------------------------------------------------------

@dataclass
class SessionMeta:
    """Metadata persisted as ``.session.yaml`` inside each session directory.

    Attributes
    ----------
    name:
        Session identifier (directory name under ``project/``).
    task:
        Task name from ``tasks.yaml`` that this session was created for.
    created_at:
        ISO 8601 creation timestamp.
    last_used_at:
        ISO 8601 timestamp of last activity.
    hashes:
        Per-layer content hashes at the time of last create/refresh.
    vivado_pid:
        PID of the running Vivado process, or ``None``.
    status:
        One of ``"idle"``, ``"busy"``, ``"error"``.
    """

    name: str
    task: str
    created_at: str = ""
    last_used_at: str = ""
    hashes: dict[str, str] = field(default_factory=dict)
    vivado_pid: int | None = None
    status: str = "idle"

    def __post_init__(self) -> None:
        if not self.created_at:
            self.created_at = _now_iso()
        if not self.last_used_at:
            self.last_used_at = self.created_at


def _now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

class Session:
    """One isolated project directory with an optional running Vivado process.

    Parameters
    ----------
    name:
        Session identifier.
    project_dir:
        The session's project directory (``project/<name>/``).
    config:
        Global configuration (used for ``vivado_path`` etc.).
    """

    def __init__(
        self,
        name: str,
        project_dir: Path,
        config: GlobalConfig,
        concurrent_sem: threading.Semaphore | None = None,
    ) -> None:
        self.name = name
        self.project_dir = project_dir
        self.meta_path = project_dir / ".session.yaml"
        self._config = config
        self._concurrent_sem = concurrent_sem
        self._process: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()
        self._sem_held: bool = False  # track whether we acquired the semaphore
        self.meta = SessionMeta(name=name, task="")

    # ------------------------------------------------------------------
    # Metadata I/O
    # ------------------------------------------------------------------

    def load_meta(self) -> None:
        """Load session metadata from ``.session.yaml``.

        If the file does not exist, the in-memory metadata is left
        unchanged (useful for brand-new sessions before the first save).
        """
        if not self.meta_path.is_file():
            return

        with self.meta_path.open("r", encoding="utf-8") as fh:
            raw: dict = yaml.safe_load(fh) or {}

        self.meta = SessionMeta(
            name=raw.get("name", self.name),
            task=raw.get("task", ""),
            created_at=raw.get("created_at", ""),
            last_used_at=raw.get("last_used_at", ""),
            hashes=raw.get("hashes", {}),
            vivado_pid=raw.get("vivado_pid"),
            status=raw.get("status", "idle"),
        )

    def save_meta(self) -> None:
        """Persist current metadata to ``.session.yaml``."""
        self.project_dir.mkdir(parents=True, exist_ok=True)

        data = {
            "name": self.meta.name,
            "task": self.meta.task,
            "created_at": self.meta.created_at,
            "last_used_at": self.meta.last_used_at,
            "hashes": self.meta.hashes,
            "vivado_pid": self.meta.vivado_pid,
            "status": self.meta.status,
        }

        with self.meta_path.open("w", encoding="utf-8") as fh:
            yaml.safe_dump(data, fh, default_flow_style=False, sort_keys=False)

    # ------------------------------------------------------------------
    # Vivado process management
    # ------------------------------------------------------------------

    def is_alive(self) -> bool:
        """Check whether the Vivado subprocess is still running."""
        if self._process is None:
            return False
        return self._process.poll() is None

    def _project_xpr_path(self) -> Path:
        """Return the session project's XPR path."""
        return self.project_dir / f"{self._config.proj_name}.xpr"

    def start_vivado(self) -> None:
        """Spawn a Vivado TCL subprocess if one is not already running.

        The process is started with ``stdin=PIPE``, ``stdout=PIPE``,
        ``stderr=STDOUT`` so that all output can be captured and commands
        can be written to stdin.

        Raises
        ------
        VivadoProcessError
            If the subprocess fails to start.
        ConcurrentLimitError
            If the concurrent Vivado process limit would be exceeded.
        """
        if self.is_alive():
            return

        # Acquire the concurrent-process semaphore (blocks if at limit).
        if self._concurrent_sem is not None and not self._sem_held:
            if not self._concurrent_sem.acquire(timeout=0):
                from .exceptions import ConcurrentLimitError
                raise ConcurrentLimitError(
                    self._concurrent_sem._value if hasattr(self._concurrent_sem, '_value') else -1,
                    self._config.limits.max_concurrent,
                )
            self._sem_held = True

        try:
            self._process = subprocess.Popen(
                [
                    self._config.vivado_path, "-mode", "tcl",
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                cwd=str(self.project_dir),
                text=True,
                bufsize=1,  # line-buffered
            )
        except OSError as exc:
            # Release semaphore on failure to start.
            if self._concurrent_sem is not None and self._sem_held:
                self._concurrent_sem.release()
                self._sem_held = False
            raise VivadoProcessError(
                f"Failed to start Vivado: {exc}",
                returncode=None,
            ) from exc

        
        self.meta.vivado_pid = self._process.pid
        self.meta.status = "idle"
        self.save_meta()
        
        self._stdout_q = queue.Queue()
        def _reader():
            while True:
                line = self._process.stdout.readline()
                if not line:
                    break
                self._stdout_q.put(line)
        self._reader_thread = threading.Thread(target=_reader, daemon=True)
        self._reader_thread.start()


    def execute(self, cmd: str, timeout: float = 60.0) -> ExecuteResult:
        """Execute a single TCL command in the Vivado subprocess.

        A unique end-marker is injected after the command so that we can
        detect when Vivado has finished processing it.

        Parameters
        ----------
        cmd:
            TCL command string (without trailing newline).
        timeout:
            Maximum seconds to wait for the end-marker.

        Returns
        -------
        ExecuteResult

        Raises
        ------
        VivadoProcessError
            If the Vivado process is not running.
        VivadoTimeoutError
            If the command does not complete within *timeout*.
        """
        if not self.is_alive():
            self.start_vivado()

        marker = f"__VIVADO_END_{uuid.uuid4().hex[:8]}__"
        marker_line = f'puts "{marker}"'
        project_xpr = self._project_xpr_path().as_posix()
        project_open = f"""\
if {{ [catch {{current_project}} cur_proj] != 0 }} {{
    if {{ [file exists \"{project_xpr}\"] }} {{
        open_project \"{project_xpr}\"
    }}
}}
"""

        with self._lock:
            self.meta.status = "busy"
            self.save_meta()

            assert self._process is not None
            assert self._process.stdin is not None
            assert self._process.stdout is not None

            start = time.monotonic()

            # Restore the session project first so commands can rely on it.
            self._process.stdin.write(project_open)
            # Write command + marker to stdin.
            self._process.stdin.write(cmd + "\n")
            self._process.stdin.write(marker_line + "\n")
            self._process.stdin.flush()

            # Read stdout until the marker appears.
            output_lines: list[str] = []
            timed_out = False

            while True:
                remaining = timeout - (time.monotonic() - start)
                if remaining <= 0:
                    timed_out = True
                    break
                try:
                    line = self._stdout_q.get(timeout=remaining)
                except queue.Empty:
                    timed_out = True
                    break
                if not line:
                    break

                stripped = line.rstrip("\n").rstrip("\r")
                if stripped == marker:
                    break
                output_lines.append(stripped)


            duration = time.monotonic() - start
            output = "\n".join(output_lines)

            self.meta.status = "idle"
            self.update_last_used()

            if timed_out:
                self.stop_vivado()  # Force restart on next command (H6)
                return ExecuteResult(
                    output=output,
                    success=False,
                    timed_out=True,
                    duration=duration,
                )

            success = not any(line.startswith("ERROR:") for line in output_lines)

            return ExecuteResult(
                output=output,
                success=success,
                timed_out=False,
                duration=duration,
            )

    def stop_vivado(self) -> None:
        """Terminate the Vivado subprocess if running.

        Sends ``quit`` to stdin first (graceful), then waits briefly
        before killing the process.
        """
        if self._process is None:
            return

        was_alive = self.is_alive()

        if was_alive:
            try:
                assert self._process.stdin is not None
                self._process.stdin.write("quit\n")
                self._process.stdin.flush()
                self._process.wait(timeout=10)
            except Exception:
                self._process.kill()
                try:
                    self._process.wait(timeout=5)
                except Exception:
                    pass

        self._process = None
        self.meta.vivado_pid = None
        self.meta.status = "idle"
        self.save_meta()

        # Release the concurrent-process semaphore.
        if self._concurrent_sem is not None and self._sem_held:
            self._concurrent_sem.release()
            self._sem_held = False

    # ------------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------------

    def update_last_used(self) -> None:
        """Update ``last_used_at`` to the current time and persist."""
        self.meta.last_used_at = _now_iso()
        self.save_meta()

    def disk_mb(self) -> float:
        """Return the total disk usage of the session directory in MiB."""
        if not self.project_dir.is_dir():
            return 0.0
        total = sum(f.stat().st_size for f in self.project_dir.rglob("*") if f.is_file())
        return total / (1024 * 1024)

    def __repr__(self) -> str:
        alive = self.is_alive()
        return f"Session({self.name!r}, task={self.meta.task!r}, alive={alive})"


# ---------------------------------------------------------------------------
# Session manager
# ---------------------------------------------------------------------------

class SessionManager:
    """Manage multiple isolated project sessions.

    Parameters
    ----------
    base_dir:
        Project root directory.
    config:
        Global configuration (limits, Vivado path, etc.).
    """

    def __init__(self, base_dir: Path | str, config: GlobalConfig) -> None:
        self.base_dir = Path(base_dir).resolve()
        self.config = config
        self._sessions_dir = self.base_dir / "project"
        self._idle_watcher: threading.Thread | None = None
        self._watcher_stop = threading.Event()
        # Semaphore for atomic concurrent Vivado process limiting.
        # Replaces the racy running_count() filesystem scan for
        # admission control in batch/multi-threaded scenarios.
        self._concurrent_sem = threading.Semaphore(config.limits.max_concurrent)

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    def list_sessions(self) -> list[Session]:
        """Return all sessions (those with a ``.session.yaml`` file)."""
        sessions: list[Session] = []
        if not self._sessions_dir.is_dir():
            return sessions

        for child in sorted(self._sessions_dir.iterdir()):
            if child.is_dir() and (child / ".session.yaml").is_file():
                sess = Session(
                    name=child.name,
                    project_dir=child,
                    config=self.config,
                    concurrent_sem=self._concurrent_sem,
                )
                sess.load_meta()
                sessions.append(sess)

        return sessions

    def get_session(self, name: str) -> Session:
        """Retrieve an existing session by name.

        Raises
        ------
        SessionNotFoundError
            If the session does not exist.
        """
        sess_dir = self._sessions_dir / name
        if not (sess_dir / ".session.yaml").is_file():
            raise SessionNotFoundError(name)

        sess = Session(name=name, project_dir=sess_dir, config=self.config,
                       concurrent_sem=self._concurrent_sem)
        sess.load_meta()
        return sess

    def get_or_create(
        self,
        task_name: str,
        session_name: str | None = None,
        task_registry: TaskRegistry | None = None,
    ) -> Session:
        """Return an existing session or create a new one.

        If *session_name* is given and a session with that name exists,
        it is returned.  Otherwise a new session is created.

        Parameters
        ----------
        task_name:
            Task to associate with the new session (if creating).
        session_name:
            Optional explicit session name.
        task_registry:
            Task registry (used only when creating).

        Returns
        -------
        Session
        """
        if session_name is not None:
            try:
                return self.get_session(session_name)
            except SessionNotFoundError:
                pass

        return self.create_session(task_name, session_name, task_registry)

    def create_session(
        self,
        task_name: str,
        session_name: str | None = None,
        task_registry: TaskRegistry | None = None,
    ) -> Session:
        """Create a new isolated session directory.

        Parameters
        ----------
        task_name:
            Task to associate with the session.
        session_name:
            Optional explicit name; defaults to ``<task_name>_<timestamp>``.
        task_registry:
            Task registry (unused currently, reserved for future validation).

        Returns
        -------
        Session

        Raises
        ------
        SessionLimitError
            If the maximum number of sessions would be exceeded.
        ConcurrentLimitError
            If the maximum concurrent Vivado processes would be exceeded.
        DiskLimitError
            If the disk usage limit would be exceeded.
        """
        # --- Resource guards ---
        existing = self.list_sessions()
        if len(existing) >= self.config.limits.max_sessions:
            raise SessionLimitError(
                len(existing), self.config.limits.max_sessions
            )
        if self.running_count() >= self.config.limits.max_concurrent:
            raise ConcurrentLimitError(
                self.running_count(), self.config.limits.max_concurrent
            )
        current_mb = self.total_disk_mb()
        if current_mb >= self.config.limits.max_disk_gb * 1024:
            raise DiskLimitError(current_mb, self.config.limits.max_disk_gb)

        # --- Name ---
        if session_name is None:
            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            session_name = f"{task_name}_{ts}"

        sess_dir = self._sessions_dir / session_name
        sess_dir.mkdir(parents=True, exist_ok=True)

        sess = Session(name=session_name, project_dir=sess_dir, config=self.config,
                       concurrent_sem=self._concurrent_sem)
        sess.meta.task = task_name
        sess.save_meta()

        return sess

    def destroy_session(self, name: str) -> None:
        """Stop the Vivado process and delete the session directory.

        Parameters
        ----------
        name:
            Session name.

        Raises
        ------
        SessionNotFoundError
            If the session does not exist.
        """
        sess = self.get_session(name)
        sess.stop_vivado()

        if sess.project_dir.is_dir():
            shutil.rmtree(sess.project_dir, ignore_errors=True)

    # ------------------------------------------------------------------
    # Resource queries
    # ------------------------------------------------------------------

    def running_count(self) -> int:
        """Number of sessions with a live Vivado process."""
        return sum(1 for s in self.list_sessions() if s.is_alive())

    def total_disk_mb(self) -> float:
        """Total disk usage across all sessions (MiB)."""
        return sum(s.disk_mb() for s in self.list_sessions())

    # ------------------------------------------------------------------
    # Cleanup
    # ------------------------------------------------------------------

    def cleanup(self, keep: int = 3) -> list[str]:
        """Remove the oldest sessions, keeping the *keep* most recent.

        For example, if max_sessions is 5 and `--cleanup` is called,
        `keep` will be 4. This means the 4 most recently used sessions
        will remain untouched, and only sessions beyond that are removed,
        guaranteeing there is space to create exactly 1 new session without
        exceeding the limit. It does *not* clear all idle sessions.
        To wipe everything, `keep=0` is used by `--cleanup-all`.

        Parameters
        ----------
        keep:
            Number of most-recently-used sessions to retain. Default is 3.

        Returns
        -------
        list[str]
            Names of removed sessions.
        """
        sessions = self.list_sessions()
        if len(sessions) <= keep:
            return []

        # Sort by last_used_at ascending (oldest first).
        sessions.sort(key=lambda s: s.meta.last_used_at)
        to_remove = sessions[: len(sessions) - keep]

        removed: list[str] = []
        for sess in to_remove:
            try:
                self.destroy_session(sess.name)
                removed.append(sess.name)
            except Exception:
                pass

        return removed

    # ------------------------------------------------------------------
    # Idle timeout watcher
    # ------------------------------------------------------------------

    def start_idle_watcher(self) -> None:
        """Start a background thread that stops idle Vivado processes.

        The thread checks every 60 seconds whether any session's
        Vivado process has been idle longer than the configured
        ``idle_timeout_min``.  If so, the process is stopped (the
        session directory is **not** deleted).
        """
        if self._idle_watcher is not None and self._idle_watcher.is_alive():
            return

        self._watcher_stop.clear()

        def _watch() -> None:
            while not self._watcher_stop.wait(60):
                timeout_sec = self.config.limits.idle_timeout_min * 60
                now = datetime.now(timezone.utc)
                for sess in self.list_sessions():
                    if not sess.is_alive():
                        continue
                    try:
                        last = datetime.fromisoformat(sess.meta.last_used_at)
                        idle = (now - last).total_seconds()
                        if idle > timeout_sec:
                            sess.stop_vivado()
                    except Exception:
                        pass

        self._idle_watcher = threading.Thread(
            target=_watch, daemon=True, name="vivado-idle-watcher"
        )
        self._idle_watcher.start()

    def stop_idle_watcher(self) -> None:
        """Stop the idle timeout watcher thread."""
        self._watcher_stop.set()

    def __repr__(self) -> str:
        return f"SessionManager(base_dir={self.base_dir!s})"
