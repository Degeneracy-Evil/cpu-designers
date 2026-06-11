"""Global configuration loading for the vivado_core package.

Reads an optional ``vivado_config.yaml`` from the project root.
If the file is absent, sensible defaults are used.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import math
import sys
from dataclasses import fields

from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Platform helpers
# ---------------------------------------------------------------------------

def _default_vivado_path() -> str:
    """Return the default Vivado executable name for the current platform.

    - Windows: ``vivado.bat`` (batch wrapper in Vivado install bin/)
    - Linux / macOS: ``vivado`` (shell wrapper in Vivado install bin/)
    """
    return "vivado.bat" if sys.platform == "win32" else "vivado"


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

    # --- Operation timeouts (seconds) ---
    create_timeout: float = 300.0
    """Timeout in seconds for the *create* operation."""

    refresh_timeout: float = 300.0
    """Timeout in seconds for the *refresh* operation."""

    sim_timeout: float = 600.0
    """Timeout in seconds for the *sim* operation."""

    sim_rerun_timeout: float = 3600.0
    """Timeout in seconds for the *sim* prj-patch rerun (DDR3 calibration needs longer)."""

    bitstream_timeout: float = 3600.0
    """Timeout in seconds for the *bitstream* operation."""

    program_timeout: float = 120.0
    """Timeout in seconds for the *program* operation."""

    archive_timeout: float = 300.0
    """Timeout in seconds for the *archive* operation."""


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
class Ddr3Config:
    """DDR3 main memory via MIG 7 Series configuration."""
    enabled: bool = False
    ip_name: str = "mig_axi_32"
    ip_version: str = "4.2"
    mig_prj_file: str = "Reference/mig/mig_a.prj"
    mem_size: int = 134217728  # 128MB
    axi_addr_width: int = 27
    axi_data_width: int = 32
    axi_id_width: int = 8
    supports_narrow_burst: bool = True
    data_rate: int = 800  # Mbps
    input_clk_freq: int = 100  # MHz


@dataclass(frozen=True)
class ClkWizConfig:
    """Clocking Wizard configuration for DDR3 reference clock."""
    enabled: bool = False
    ip_name: str = "clk_wiz_0"
    ip_version: str = "6.0"
    prim_in_freq: float = 100.0  # MHz
    mmcm_clkin_period: float = 10.0  # ns
    mmcm_clkfbout_mult_f: float = 10.0  # VCO = 1000MHz
    mmcm_divclk_divide: int = 1
    num_out_clks: int = 2
    clk_out1_freq: float = 100.0  # MHz (clk_system,备用)
    clk_out2_freq: float = 200.0  # MHz (clk_ddr_ref → MIG clk_ref_i)
    reset_type: str = "ACTIVE_LOW"


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

    ddr3: Ddr3Config = field(default_factory=Ddr3Config)
    """DDR3 main memory via MIG 7 Series configuration."""

    clk_wiz: ClkWizConfig = field(default_factory=ClkWizConfig)
    """Clocking Wizard configuration for DDR3 reference clock."""


@dataclass(frozen=True)
class GlobalConfig:
    """Top-level configuration for the vivado_core package."""

    limits: LimitsConfig = field(default_factory=LimitsConfig)
    """Resource limits."""

    vivado_path: str = _default_vivado_path()
    """Path or name of the Vivado executable.

    Defaults to ``vivado.bat`` on Windows and ``vivado`` on Linux/macOS.
    Override in ``vivado_config.yaml`` or via ``--config`` if needed.
    """

    proj_name: str = "simplecpu_soc"
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
        create_timeout=float(limits_raw.get("create_timeout", 300)),
        refresh_timeout=float(limits_raw.get("refresh_timeout", 300)),
        sim_timeout=float(limits_raw.get("sim_timeout", 600)),
        sim_rerun_timeout=float(limits_raw.get("sim_rerun_timeout", 3600)),
        bitstream_timeout=float(limits_raw.get("bitstream_timeout", 3600)),
        program_timeout=float(limits_raw.get("program_timeout", 120)),
        archive_timeout=float(limits_raw.get("archive_timeout", 300)),
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
    ddr3_raw: dict = mem_raw.get("ddr3", {}) or {}
    clk_wiz_raw: dict = mem_raw.get("clk_wiz", {}) or {}

    ddr3 = Ddr3Config(
        enabled=ddr3_raw.get("enabled", False),
        ip_name=ddr3_raw.get("ip_name", "mig_axi_32"),
        ip_version=ddr3_raw.get("ip_version", "4.2"),
        mig_prj_file=ddr3_raw.get("mig_prj_file", "Reference/mig/mig_a.prj"),
        mem_size=ddr3_raw.get("mem_size", 134217728),
        axi_addr_width=ddr3_raw.get("axi_addr_width", 27),
        axi_data_width=ddr3_raw.get("axi_data_width", 32),
        axi_id_width=ddr3_raw.get("axi_id_width", 8),
        supports_narrow_burst=ddr3_raw.get("supports_narrow_burst", True),
        data_rate=ddr3_raw.get("data_rate", 800),
        input_clk_freq=ddr3_raw.get("input_clk_freq", 100),
    )
    clk_wiz = ClkWizConfig(
        enabled=clk_wiz_raw.get("enabled", False),
        ip_name=clk_wiz_raw.get("ip_name", "clk_wiz_0"),
        ip_version=clk_wiz_raw.get("ip_version", "6.0"),
        prim_in_freq=float(clk_wiz_raw.get("prim_in_freq", 100.0)),
        mmcm_clkin_period=float(clk_wiz_raw.get("mmcm_clkin_period", 10.0)),
        mmcm_clkfbout_mult_f=float(clk_wiz_raw.get("mmcm_clkfbout_mult_f", 10.0)),
        mmcm_divclk_divide=clk_wiz_raw.get("mmcm_divclk_divide", 1),
        num_out_clks=clk_wiz_raw.get("num_out_clks", 2),
        clk_out1_freq=float(clk_wiz_raw.get("clk_out1_freq", 100.0)),
        clk_out2_freq=float(clk_wiz_raw.get("clk_out2_freq", 200.0)),
        reset_type=clk_wiz_raw.get("reset_type", "ACTIVE_LOW"),
    )
    memory = MemoryConfig(
        sram=sram,
        icache=icache,
        dcache=dcache,
        tlb=tlb,
        use_tag_bram=mem_raw.get("use_tag_bram", False),
        use_tlb_bram=mem_raw.get("use_tlb_bram", False),
        ddr3=ddr3,
        clk_wiz=clk_wiz,
    )

    return GlobalConfig(
        limits=limits,
        vivado_path=raw.get("vivado_path", _default_vivado_path()),
        proj_name=raw.get("proj_name", "simplecpu_bus"),
        device_part=raw.get("device_part", "xc7a200tfbg676-2"),
        memory=memory,
    )
