"""vivado_core — Python orchestration layer for Vivado TCL workflows.

This package replaces the monolithic ``vivado_do.tcl`` with a modular,
session-based architecture that supports:

- **Layered hashing** for staleness detection across RTL, TB, COE, and
  FPGA source layers.
- **Task-driven configuration** loaded from ``tasks.yaml``.
- **Isolated sessions** with per-session Vivado subprocess management.
- **Preflight checks** and incremental refresh planning.
- **High-level operations** (create, refresh, sim, bitstream, program,
  archive) with automatic staleness handling.

Example
-------
>>> from pathlib import Path
>>> from vivado_core import (
...     GlobalConfig, LayeredHash, Operations,
...     SessionManager, SyncPolicy, TaskRegistry,
... )
>>> base = Path(".")
>>> config = GlobalConfig()
>>> task_reg = TaskRegistry(base / "tasks.yaml")
>>> task_reg.load()
>>> layered_hash = LayeredHash(base)
>>> session_mgr = SessionManager(base, config)
>>> sync = SyncPolicy(layered_hash)
>>> ops = Operations(session_mgr, task_reg, sync, layered_hash)
"""

from __future__ import annotations

# Core data types and configuration
from .config import GlobalConfig, LimitsConfig, load_config

# Exception hierarchy
from .exceptions import (
    ConcurrentLimitError,
    DiskLimitError,
    OperationError,
    SessionError,
    SessionLimitError,
    SessionNotFoundError,
    StaleSessionError,
    TaskError,
    TaskNotFoundError,
    VivadoCoreError,
    VivadoError,
    VivadoProcessError,
    VivadoTimeoutError,
)

# Hash computation
from .hash import LayeredHash

# High-level operations
from .operations import Operations

# Session management
from .session import ExecuteResult, Session, SessionManager, SessionMeta

# Synchronisation policy
from .sync import PreflightResult, RefreshPlan, SyncPolicy

# Task definitions
from .tasks import TaskConfig, TaskRegistry

# Batch execution
from .batch import (
    BatchExecutor,
    BatchResult,
    BatchSpec,
    BatchTask,
    ProgressTracker,
    TaskResult,
    expand_batch_spec,
    load_batch_plan,
)

__all__ = [
    # config
    "GlobalConfig",
    "LimitsConfig",
    "load_config",
    # exceptions
    "ConcurrentLimitError",
    "DiskLimitError",
    "OperationError",
    "SessionError",
    "SessionLimitError",
    "SessionNotFoundError",
    "StaleSessionError",
    "TaskError",
    "TaskNotFoundError",
    "VivadoCoreError",
    "VivadoError",
    "VivadoProcessError",
    "VivadoTimeoutError",
    # hash
    "LayeredHash",
    # operations
    "Operations",
    # session
    "ExecuteResult",
    "Session",
    "SessionManager",
    "SessionMeta",
    # sync
    "PreflightResult",
    "RefreshPlan",
    "SyncPolicy",
    # tasks
    "TaskConfig",
    "TaskRegistry",
    # batch
    "BatchExecutor",
    "BatchResult",
    "BatchSpec",
    "BatchTask",
    "ProgressTracker",
    "TaskResult",
    "expand_batch_spec",
    "load_batch_plan",
]
