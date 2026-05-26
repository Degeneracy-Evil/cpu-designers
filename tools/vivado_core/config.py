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
class SramConfig:
    """SRAM (main memory) BRAM configuration."""

    data_width: int = 32
    """Word width in bits."""

    depth: int = 8192
    """Memory depth in words."""

    byte_enable: bool = False
    """Whether byte-write enable is active."""

    byte_size: int = 8
    """Byte size for write-enable granularity (only when byte_enable=true)."""


@dataclass(frozen=True)
class CacheConfig:
    """Cache geometry configuration (applies to icache or dcache)."""

    num_sets: int = 8
    """Number of cache sets."""

    num_ways: int = 4
    """Associativity (ways per set)."""

    tag_width: int = 7
    """Tag field width in bits."""

    line_words: int = 8
    """Words per cache line.  line_width = line_words * 32."""

    byte_enable: bool = True
    """Whether byte-write enable is active for data BRAM."""

    byte_size: int = 8
    """Byte size for write-enable granularity."""

    tag_bram_byte_enable: bool = True
    """Whether byte-write enable is active for tag BRAM (when use_tag_bram=true)."""

    tag_bram_byte_size: int = 8
    """Byte size for tag BRAM write-enable granularity (8 for icache, 9 for dcache)."""


@dataclass(frozen=True)
class TlbConfig:
    """TLB geometry configuration (set-associative BRAM structure)."""

    num_ways: int = 4
    """Associativity (ways per set). ⚠ FIXED: do not change (tree_plru hardcoded)."""

    num_sets: int = 4
    """Number of TLB sets. Total entries = num_ways × num_sets."""

    flag_byte_enable: bool = True
    """Whether byte-write enable is active for flag BRAM."""

    flag_byte_size: int = 8
    """Byte size for flag BRAM write-enable granularity (8 → 16-bit WEA, 4 bits per 32-bit way)."""

    data_byte_enable: bool = True
    """Whether byte-write enable is active for data BRAM."""

    data_byte_size: int = 8
    """Byte size for data BRAM write-enable granularity (8 → 16-bit WEA, 4 bits per 32-bit way)."""


@dataclass(frozen=True)
class MemoryConfig:
    """Top-level memory/cache configuration."""

    sram: SramConfig = field(default_factory=SramConfig)
    """Main memory SRAM configuration."""

    icache: CacheConfig = field(default_factory=CacheConfig)
    """I-cache configuration."""

    dcache: CacheConfig = field(default_factory=CacheConfig)
    """D-cache configuration."""

    tlb: TlbConfig = field(default_factory=TlbConfig)
    """TLB configuration."""

    use_tag_bram: bool = False
    """If true, use BRAM IPs (icachet/dcachet) for tag storage; otherwise register arrays."""

    use_tlb_bram: bool = False
    """If true, use BRAM IPs (tlb_flag/tlb_data) for TLB storage; otherwise register array."""


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

    memory: MemoryConfig = field(default_factory=MemoryConfig)
    """Memory and cache configuration."""


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

    # --- memory sub-dict ---
    mem_raw: dict = raw.get("memory", {}) or {}
    sram_raw: dict = mem_raw.get("sram", {}) or {}
    icache_raw: dict = mem_raw.get("icache", {}) or {}
    dcache_raw: dict = mem_raw.get("dcache", {}) or {}
    tlb_raw: dict = mem_raw.get("tlb", {}) or {}

    sram = SramConfig(
        data_width=sram_raw.get("data_width", 32),
        depth=sram_raw.get("depth", 8192),
        byte_enable=sram_raw.get("byte_enable", False),
        byte_size=sram_raw.get("byte_size", 8),
    )
    icache = CacheConfig(
        num_sets=icache_raw.get("num_sets", 8),
        num_ways=icache_raw.get("num_ways", 4),
        tag_width=icache_raw.get("tag_width", 7),
        line_words=icache_raw.get("line_words", 8),
        byte_enable=icache_raw.get("byte_enable", True),
        byte_size=icache_raw.get("byte_size", 8),
        tag_bram_byte_enable=icache_raw.get("tag_bram_byte_enable", True),
        tag_bram_byte_size=icache_raw.get("tag_bram_byte_size", 8),
    )
    dcache = CacheConfig(
        num_sets=dcache_raw.get("num_sets", 8),
        num_ways=dcache_raw.get("num_ways", 4),
        tag_width=dcache_raw.get("tag_width", 7),
        line_words=dcache_raw.get("line_words", 8),
        byte_enable=dcache_raw.get("byte_enable", True),
        byte_size=dcache_raw.get("byte_size", 8),
        tag_bram_byte_enable=dcache_raw.get("tag_bram_byte_enable", True),
        tag_bram_byte_size=dcache_raw.get("tag_bram_byte_size", 9),
    )
    tlb = TlbConfig(
        num_ways=tlb_raw.get("num_ways", 4),
        num_sets=tlb_raw.get("num_sets", 4),
        flag_byte_enable=tlb_raw.get("flag_byte_enable", True),
        flag_byte_size=tlb_raw.get("flag_byte_size", 32),
        data_byte_enable=tlb_raw.get("data_byte_enable", True),
        data_byte_size=tlb_raw.get("data_byte_size", 32),
    )
    memory = MemoryConfig(
        sram=sram,
        icache=icache,
        dcache=dcache,
        tlb=tlb,
        use_tag_bram=mem_raw.get("use_tag_bram", False),
        use_tlb_bram=mem_raw.get("use_tlb_bram", False),
    )

    return GlobalConfig(
        limits=limits,
        vivado_path=raw.get("vivado_path", "vivado.bat"),
        proj_name=raw.get("proj_name", "simplecpu_bus"),
        device_part=raw.get("device_part", "xc7a200tfbg676-2"),
        memory=memory,
    )
