"""Custom exception hierarchy for the vivado_core package.

Hierarchy::

    VivadoCoreError (base)
    ├── SessionError (session CRUD issues)
    │   ├── SessionNotFoundError
    │   ├── SessionLimitError (max_sessions exceeded)
    │   ├── ConcurrentLimitError (max_concurrent exceeded)
    │   ├── DiskLimitError (max_disk_gb exceeded)
    │   └── StaleSessionError (session is stale, needs refresh)
    ├── TaskError (task config issues)
    │   └── TaskNotFoundError
    ├── VivadoError (Vivado process issues)
    │   ├── VivadoTimeoutError
    │   └── VivadoProcessError
    └── OperationError (high-level op failures)
"""
from __future__ import annotations


# ---------------------------------------------------------------------------
# Base
# ---------------------------------------------------------------------------
class VivadoCoreError(Exception):
    """Base exception for all vivado_core errors."""


# ---------------------------------------------------------------------------
# Session errors
# ---------------------------------------------------------------------------
class SessionError(VivadoCoreError):
    """Base for session CRUD issues."""


class SessionNotFoundError(SessionError):
    """Requested session does not exist."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(f"Session not found: {name!r}")


class SessionLimitError(SessionError):
    """Maximum number of sessions exceeded."""

    def __init__(self, current: int, limit: int) -> None:
        self.current = current
        self.limit = limit
        super().__init__(
            f"Session limit exceeded: {current} sessions exist, limit is {limit}"
        )


class ConcurrentLimitError(SessionError):
    """Maximum number of concurrent Vivado processes exceeded."""

    def __init__(self, current: int, limit: int) -> None:
        self.current = current
        self.limit = limit
        super().__init__(
            f"Concurrent Vivado limit exceeded: {current} running, limit is {limit}"
        )


class DiskLimitError(SessionError):
    """Maximum disk usage exceeded."""

    def __init__(self, current_mb: float, limit_gb: float) -> None:
        self.current_mb = current_mb
        self.limit_gb = limit_gb
        super().__init__(
            f"Disk limit exceeded: {current_mb:.1f} MB used, limit is {limit_gb:.1f} GB"
        )


class StaleSessionError(SessionError):
    """Session is stale and needs a refresh before the requested operation."""

    def __init__(self, session_name: str, stale_layers: list[str]) -> None:
        self.session_name = session_name
        self.stale_layers = stale_layers
        if stale_layers:
            msg = (
                f"Session {session_name!r} is stale in layers {stale_layers}; "
                f"refresh required"
            )
        else:
            msg = (
                f"Session {session_name!r} has no project created yet; "
                f"run -create before proceeding"
            )
        super().__init__(msg)


# ---------------------------------------------------------------------------
# Task errors
# ---------------------------------------------------------------------------
class TaskError(VivadoCoreError):
    """Base for task configuration issues."""


class TaskNotFoundError(TaskError):
    """Requested task definition does not exist."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(f"Task not found: {name!r}")


# ---------------------------------------------------------------------------
# Vivado process errors
# ---------------------------------------------------------------------------
class VivadoError(VivadoCoreError):
    """Base for Vivado process issues."""


class VivadoTimeoutError(VivadoError):
    """Vivado command timed out."""

    def __init__(self, cmd: str, timeout: float) -> None:
        self.cmd = cmd
        self.timeout = timeout
        super().__init__(f"Vivado command timed out after {timeout}s: {cmd!r}")


class VivadoProcessError(VivadoError):
    """Vivado process exited with a non-zero return code or failed to start."""

    def __init__(self, message: str, returncode: int | None = None) -> None:
        self.returncode = returncode
        super().__init__(message)


# ---------------------------------------------------------------------------
# Operation errors
# ---------------------------------------------------------------------------
class OperationError(VivadoCoreError):
    """High-level operation failure (create, sim, bitstream, etc.)."""

    def __init__(self, operation: str, detail: str = "") -> None:
        self.operation = operation
        msg = f"Operation {operation!r} failed"
        if detail:
            msg += f": {detail}"
        super().__init__(msg)
