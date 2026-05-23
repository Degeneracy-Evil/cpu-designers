"""Global configuration loading for the vivado_core package.

Reads an optional ``vivado_config.yaml`` from the project root.
If the file is absent, sensible defaults are used.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class LimitsConfig:
    """Resource limits for session management."""

    max_sessions: int = 5
    """Maximum number of session directories allowed."""

    max_concurrent: int = 3
    """Maximum number of simultaneously running Vivado processes."""

    max_disk_gb: float = 20.0
    """Maximum total disk usage (in GiB) across all sessions."""

    idle_timeout_min: int = 60
    """Minutes of inactivity before a Vivado process is auto-stopped."""


@dataclass(frozen=True)
class GlobalConfig:
    """Top-level configuration for the vivado_core package."""

    limits: LimitsConfig = field(default_factory=LimitsConfig)
    """Resource limits."""

    vivado_path: str = "vivado.bat"
    """Path or name of the Vivado executable."""

    proj_name: str = "simplecpu_bus"
    """Vivado project name (used as XPR base name)."""

    device_part: str = "xc7a200tfbg676-2"
    """Target FPGA part number."""


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------

def load_config(path: Path | str | None = None, base_dir: Path | str | None = None) -> GlobalConfig:
    """Load global configuration from a YAML file.

    Parameters
    ----------
    path:
        Explicit path to the YAML config file.  If ``None``, the
        function looks for ``vivado_config.yaml`` in *base_dir*.
    base_dir:
        Project root directory.  Used only when *path* is ``None`` to
        locate the default config file.  Defaults to the current
        working directory.

    Returns
    -------
    GlobalConfig
        Parsed configuration with defaults applied for missing fields.
    """
    if path is None:
        search_dir = Path(base_dir) if base_dir is not None else Path.cwd()
        path = search_dir / "vivado_config.yaml"
    else:
        path = Path(path)

    if not path.is_file():
        return GlobalConfig()

    with path.open("r", encoding="utf-8") as fh:
        raw: dict = yaml.safe_load(fh) or {}

    # --- limits sub-dict ---
    limits_raw: dict = raw.get("limits", {}) or {}
    limits = LimitsConfig(
        max_sessions=limits_raw.get("max_sessions", 5),
        max_concurrent=limits_raw.get("max_concurrent", 3),
        max_disk_gb=float(limits_raw.get("max_disk_gb", 20)),
        idle_timeout_min=limits_raw.get("idle_timeout_min", 60),
    )

    return GlobalConfig(
        limits=limits,
        vivado_path=raw.get("vivado_path", "vivado.bat"),
        proj_name=raw.get("proj_name", "simplecpu_bus"),
        device_part=raw.get("device_part", "xc7a200tfbg676-2"),
    )
