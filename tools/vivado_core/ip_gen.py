"""BRAM IP generation from MemoryConfig.

Generates Vivado ``create_ip`` TCL commands for blk_mem_gen IPs
based on the memory/cache configuration in ``vivado_config.yaml``.
This replaces the old approach of importing static XCI files.
"""
from __future__ import annotations

from dataclasses import dataclass

from .config import CacheConfig, MemoryConfig, SramConfig


# ---------------------------------------------------------------------------
# BramConfig — derived IP parameters
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BramConfig:
    """Fully resolved blk_mem_gen IP configuration.

    All width/depth values are derived from the high-level
    ``SramConfig`` / ``CacheConfig`` and are ready for TCL emission.
    """

    name: str
    """IP instance name (e.g. ``"icached"``, ``"Sram"``)."""

    data_width: int
    """Port A/B data width in bits."""

    depth: int
    """Memory depth in words."""

    byte_enable: bool
    """Whether byte-write enable is active."""

    byte_size: int
    """Byte size for write-enable granularity."""

    register_output: bool = False
    """Whether to register the output of memory primitives."""

    @property
    def addr_width(self) -> int:
        """Address width = ceil(log2(depth))."""
        if self.depth <= 1:
            return 1
        return (self.depth - 1).bit_length()

    @property
    def wea_width(self) -> int:
        """Write-enable signal width."""
        if self.byte_enable:
            return self.data_width // self.byte_size
        return 1


# ---------------------------------------------------------------------------
# Derivation helpers
# ---------------------------------------------------------------------------

def sram_to_bram(cfg: SramConfig) -> BramConfig:
    """Derive BRAM config for the main-memory SRAM."""
    return BramConfig(
        name="Sram",
        data_width=cfg.data_width,
        depth=cfg.depth,
        byte_enable=cfg.byte_enable,
        byte_size=cfg.byte_size,
        register_output=False,
    )


def cache_data_to_bram(name: str, cfg: CacheConfig) -> BramConfig:
    """Derive BRAM config for a cache *data* array.

    Parameters
    ----------
    name:
        IP instance name (``"icached"`` or ``"dcached"``).
    cfg:
        Cache geometry configuration.
    """
    line_width = cfg.line_words * 32  # e.g. 8 * 32 = 256
    depth = cfg.num_sets * cfg.num_ways  # e.g. 8 * 4 = 32
    return BramConfig(
        name=name,
        data_width=line_width,
        depth=depth,
        byte_enable=cfg.byte_enable,
        byte_size=cfg.byte_size,
        register_output=False,
    )


def cache_tag_to_bram(name: str, cfg: CacheConfig, has_dirty: bool = False) -> BramConfig:
    """Derive BRAM config for a cache *tag* array.

    Parameters
    ----------
    name:
        IP instance name (``"icachet"`` or ``"dcachet"``).
    cfg:
        Cache geometry configuration.
    has_dirty:
        If true, tag entry includes a dirty bit (dcache).
    """
    # Tag entry: valid(1) [+ dirty(1)] + tag(tag_width)
    extra_bits = 2 if has_dirty else 1
    tag_entry_width = extra_bits + cfg.tag_width
    depth = cfg.num_sets * cfg.num_ways
    return BramConfig(
        name=name,
        data_width=tag_entry_width,
        depth=depth,
        byte_enable=False,
        byte_size=8,  # unused when byte_enable=false
        register_output=False,
    )


# ---------------------------------------------------------------------------
# TCL generation
# ---------------------------------------------------------------------------

def generate_bram_create_ip_tcl(cfg: BramConfig, ip_dir: str) -> str:
    """Generate ``create_ip`` + ``set_property`` TCL for one blk_mem_gen IP.

    Parameters
    ----------
    cfg:
        Fully resolved BRAM configuration.
    ip_dir:
        Directory where the IP should be created (forward-slash TCL path).

    Returns
    -------
    str
        TCL script that creates and configures the IP.
    """
    # Build set_property dict entries — must match original XCI properties.
    props: list[str] = [
        f"CONFIG.Memory_Type {{True_Dual_Port_RAM}}",
        f"CONFIG.Write_Width_A {{{cfg.data_width}}}",
        f"CONFIG.Write_Depth_A {{{cfg.depth}}}",
        f"CONFIG.Read_Width_A {{{cfg.data_width}}}",
        f"CONFIG.Write_Width_B {{{cfg.data_width}}}",
        f"CONFIG.Read_Width_B {{{cfg.data_width}}}",
        f"CONFIG.Enable_B {{Use_ENB_Pin}}",
        f"CONFIG.Register_PortA_Output_of_Memory_Primitives "
        f"{{{'true' if cfg.register_output else 'false'}}}",
        f"CONFIG.Register_PortB_Output_of_Memory_Primitives "
        f"{{{'true' if cfg.register_output else 'false'}}}",
        f"CONFIG.Operating_Mode_A {{WRITE_FIRST}}",
        f"CONFIG.Operating_Mode_B {{WRITE_FIRST}}",
        f"CONFIG.Interface_Type {{Native}}",
        f"CONFIG.PRIM_type_to_Implement {{BRAM}}",
        f"CONFIG.Port_B_Clock {{100}}",
        f"CONFIG.Port_B_Write_Rate {{50}}",
        f"CONFIG.Port_B_Enable_Rate {{100}}",
    ]

    if cfg.byte_enable:
        props.append(f"CONFIG.Use_Byte_Write_Enable {{true}}")
        props.append(f"CONFIG.Byte_Size {{{cfg.byte_size}}}")
    else:
        props.append(f"CONFIG.Use_Byte_Write_Enable {{false}}")

    prop_dict = " \\\n    ".join(props)

    return f"""\
# --- create IP: {cfg.name} ({cfg.data_width}-bit x {cfg.depth}, byte_en={cfg.byte_enable}) ---
file mkdir {ip_dir}/{cfg.name}
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \\
    -module_name {cfg.name} -dir {ip_dir}/{cfg.name}
set_property -dict [list \\
    {prop_dict}] [get_ips {cfg.name}]
"""


def _tcl_generate_target(name: str) -> str:
    """Generate TCL to generate target + export for one IP."""
    return f"""\
generate_target all [get_ips {name}]
catch {{ config_ip_cache -export [get_ips -all {name}] }}
export_ip_user_files -of_objects [get_ips {name}] -no_script -sync -force -quiet
"""


def generate_all_ip_tcl(mem: MemoryConfig, ip_dir: str) -> tuple[str, list[str]]:
    """Generate TCL for all BRAM IPs from the memory configuration.

    Parameters
    ----------
    mem:
        Memory/cache configuration.
    ip_dir:
        Target directory for IP creation.

    Returns
    -------
    tuple[str, list[str]]
        Combined TCL script for IP creation + property configuration,
        and a list of IP names in creation order.
        Callers must call ``_tcl_generate_target()`` separately
        (Sram after COE config, others immediately).
    """
    parts: list[str] = []
    names: list[str] = []

    # Sram (main memory)
    cfg_sram = sram_to_bram(mem.sram)
    parts.append(generate_bram_create_ip_tcl(cfg_sram, ip_dir))
    names.append(cfg_sram.name)

    # icached (I-cache data)
    cfg_ic = cache_data_to_bram("icached", mem.icache)
    parts.append(generate_bram_create_ip_tcl(cfg_ic, ip_dir))
    names.append(cfg_ic.name)

    # dcached (D-cache data)
    cfg_dc = cache_data_to_bram("dcached", mem.dcache)
    parts.append(generate_bram_create_ip_tcl(cfg_dc, ip_dir))
    names.append(cfg_dc.name)

    # Tag BRAMs (optional)
    if mem.use_tag_bram:
        cfg_ict = cache_tag_to_bram("icachet", mem.icache, has_dirty=False)
        parts.append(generate_bram_create_ip_tcl(cfg_ict, ip_dir))
        names.append(cfg_ict.name)
        cfg_dct = cache_tag_to_bram("dcachet", mem.dcache, has_dirty=True)
        parts.append(generate_bram_create_ip_tcl(cfg_dct, ip_dir))
        names.append(cfg_dct.name)

    return "\n".join(parts), names
