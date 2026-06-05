"""BRAM IP generation from MemoryConfig.

Generates Vivado ``create_ip`` TCL commands for blk_mem_gen IPs
based on the memory/cache configuration in ``vivado_config.yaml``.
This replaces the old approach of importing static XCI files.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .config import CacheConfig, Ddr3Config, AhbBridgeConfig, ClkWizConfig, MemoryConfig, SramConfig, TlbConfig


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


@dataclass(frozen=True)
class MigIpConfig:
    """MIG 7 Series IP configuration for TCL generation."""
    name: str
    ip_version: str = "4.2"
    mig_prj_path: str = ""
    axi_data_width: int = 32
    axi_addr_width: int = 27
    axi_id_width: int = 8


@dataclass(frozen=True)
class BridgeIpConfig:
    """AHB-Lite AXI Bridge IP configuration for TCL generation."""
    name: str
    ip_version: str = "3.0"
    thread_id_width: int = 0
    supports_narrow_burst: bool = True


@dataclass(frozen=True)
class ClkWizIpConfig:
    """Clocking Wizard IP configuration for TCL generation."""
    name: str
    ip_version: str = "6.0"
    prim_in_freq: float = 100.0
    mmcm_clkin_period: float = 10.0
    mmcm_clkfbout_mult_f: float = 10.0
    mmcm_divclk_divide: int = 1
    num_out_clks: int = 2
    clk_out1_freq: float = 100.0
    clk_out2_freq: float = 200.0
    reset_type: str = "ACTIVE_LOW"


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
    """Derive BRAM config for a cache *tag* array (packed: all ways per set).

    Each BRAM address corresponds to one Set's all 4 Ways packed together.
    This enables single-read parallel tag comparison for the entire set.

    Parameters
    ----------
    name:
        IP instance name (``"icachet"`` or ``"dcachet"``).
    cfg:
        Cache geometry configuration.
    has_dirty:
        If true, tag entry includes a dirty bit (dcache).
    """
    # Tag entry per way: valid(1) [+ dirty(1)] + tag(tag_width)
    extra_bits = 2 if has_dirty else 1
    tag_entry_width = extra_bits + cfg.tag_width  # 8 for icache, 9 for dcache
    # Packed: all ways in one BRAM line
    packed_width = cfg.num_ways * tag_entry_width  # 32 for icache, 36 for dcache
    # Depth = number of sets (one BRAM address per set)
    depth = cfg.num_sets
    return BramConfig(
        name=name,
        data_width=packed_width,
        depth=depth,
        byte_enable=cfg.tag_bram_byte_enable,
        byte_size=cfg.tag_bram_byte_size,
        register_output=False,
    )


def tlb_flag_to_bram(name: str, cfg: TlbConfig) -> BramConfig:
    """Derive BRAM config for the TLB *flag* array (packed: all ways per set).

    Each BRAM address corresponds to one Set's all 4 Ways packed together.
    Per-way flag entry: V(1) + G(1) + ASID(9) + VPN(20) + mega(1) = 32 bits.
    Packed width = num_ways × 32 = 128 bits. Depth = num_sets.

    Parameters
    ----------
    name:
        IP instance name (``"tlb_flag"``).
    cfg:
        TLB geometry configuration.
    """
    flag_entry_width = 1 + 1 + 9 + 20 + 1  # 32 bits per way
    packed_width = cfg.num_ways * flag_entry_width  # 128 bits
    depth = cfg.num_sets
    return BramConfig(
        name=name,
        data_width=packed_width,
        depth=depth,
        byte_enable=cfg.flag_byte_enable,
        byte_size=cfg.flag_byte_size,
        register_output=False,
    )


def tlb_data_to_bram(name: str, cfg: TlbConfig) -> BramConfig:
    """Derive BRAM config for the TLB *data* array (packed: all ways per set).

    Each BRAM address corresponds to one Set's all 4 Ways packed together.
    Per-way data entry: PPN(22) + R(1) + W(1) + X(1) + U(1) + A(1) + D(1) + pad(4) = 32 bits.
    Packed width = num_ways × 32 = 128 bits. Depth = num_sets.

    Parameters
    ----------
    name:
        IP instance name (``"tlb_data"``).
    cfg:
        TLB geometry configuration.
    """
    data_entry_width = 22 + 1 + 1 + 1 + 1 + 1 + 1 + 4  # 32 bits per way (4 bits padding)
    packed_width = cfg.num_ways * data_entry_width  # 128 bits
    depth = cfg.num_sets
    return BramConfig(
        name=name,
        data_width=packed_width,
        depth=depth,
        byte_enable=cfg.data_byte_enable,
        byte_size=cfg.data_byte_size,
        register_output=False,
    )


def ddr3_to_mig_ip(cfg: Ddr3Config) -> MigIpConfig:
    """Derive MIG IP config from DDR3 config."""
    return MigIpConfig(
        name=cfg.ip_name,
        ip_version=cfg.ip_version,
        mig_prj_path=cfg.mig_prj_file,
        axi_data_width=cfg.axi_data_width,
        axi_addr_width=cfg.axi_addr_width,
        axi_id_width=cfg.axi_id_width,
    )


def bridge_to_ip(cfg: AhbBridgeConfig) -> BridgeIpConfig:
    """Derive Bridge IP config from AHB bridge config."""
    return BridgeIpConfig(
        name=cfg.ip_name,
        ip_version=cfg.ip_version,
        thread_id_width=cfg.thread_id_width,
        supports_narrow_burst=cfg.supports_narrow_burst,
    )


def clkwiz_to_ip(cfg: ClkWizConfig) -> ClkWizIpConfig:
    """Derive Clocking Wizard IP config from clk_wiz config."""
    return ClkWizIpConfig(
        name=cfg.ip_name,
        ip_version=cfg.ip_version,
        prim_in_freq=cfg.prim_in_freq,
        mmcm_clkin_period=cfg.mmcm_clkin_period,
        mmcm_clkfbout_mult_f=cfg.mmcm_clkfbout_mult_f,
        mmcm_divclk_divide=cfg.mmcm_divclk_divide,
        num_out_clks=cfg.num_out_clks,
        clk_out1_freq=cfg.clk_out1_freq,
        clk_out2_freq=cfg.clk_out2_freq,
        reset_type=cfg.reset_type,
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


def generate_mig_create_ip_tcl(cfg: MigIpConfig, ip_dir: str, base_dir: str = "") -> str:
    """Generate create_ip TCL for MIG 7 Series.
    
    MIG core config is driven entirely by XML_INPUT_FILE (mig_a.prj).
    Do NOT override any parameters that mig_a.prj controls.
    """
    # Resolve mig_prj_path relative to base_dir if not absolute
    if base_dir and not Path(cfg.mig_prj_path).is_absolute():
        mig_prj_abs = f"{base_dir}/{cfg.mig_prj_path}"
    else:
        mig_prj_abs = cfg.mig_prj_path
    
    return f"""\
# --- create IP: {cfg.name} (MIG 7 Series, DDR3 controller) ---
file mkdir {ip_dir}/{cfg.name}
create_ip -name mig_7series -vendor xilinx.com -library ip -version {cfg.ip_version} \\
    -module_name {cfg.name} -dir {ip_dir}/{cfg.name}
set_property -dict [list \\
    CONFIG.XML_INPUT_FILE {{{mig_prj_abs}}} \\
    CONFIG.RESET_BOARD_INTERFACE {{Custom}} \\
    CONFIG.MIG_DONT_TOUCH_PARAM {{Custom}} \\
] [get_ips {cfg.name}]
"""


def generate_bridge_create_ip_tcl(cfg: BridgeIpConfig, ip_dir: str) -> str:
    """Generate create_ip TCL for AHB-Lite to AXI4 Bridge."""
    narrow = "true" if cfg.supports_narrow_burst else "false"
    return f"""\
# --- create IP: {cfg.name} (AHB-Lite AXI Bridge, ID_WIDTH={cfg.thread_id_width}) ---
file mkdir {ip_dir}/{cfg.name}
create_ip -name ahblite_axi_bridge -vendor xilinx.com -library ip -version {cfg.ip_version} \\
    -module_name {cfg.name} -dir {ip_dir}/{cfg.name}
set_property -dict [list \\
    CONFIG.C_M_AXI_THREAD_ID_WIDTH {{{cfg.thread_id_width}}} \\
    CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {{{narrow}}} \\
] [get_ips {cfg.name}]
"""


def generate_clkwiz_create_ip_tcl(cfg: ClkWizIpConfig, ip_dir: str) -> str:
    """Generate create_ip TCL for Clocking Wizard (DDR3 ref clock generation).
    
    Vivado note: NUM_OUT_CLKS is a derived parameter — it is computed from
    CLKOUT<N>_USED flags, not set directly.  Setting CLKOUT2_USED {true}
    causes the IP to auto-compute NUM_OUT_CLKS = 2.
    """
    # Build CLKOUT_USED + frequency entries for each output clock
    clkout_props: list[str] = []
    clkout_props.append(f"CONFIG.CLKOUT1_USED {{true}}")
    clkout_props.append(f"CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {{{cfg.clk_out1_freq:.3f}}}")
    if cfg.num_out_clks >= 2:
        clkout_props.append(f"CONFIG.CLKOUT2_USED {{true}}")
        clkout_props.append(f"CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {{{cfg.clk_out2_freq:.3f}}}")
    clkout_str = " \\\n    ".join(clkout_props)

    return f"""\
# --- create IP: {cfg.name} (Clocking Wizard, {cfg.prim_in_freq}MHz → {cfg.clk_out2_freq}MHz DDR ref) ---
file mkdir {ip_dir}/{cfg.name}
create_ip -name clk_wiz -vendor xilinx.com -library ip -version {cfg.ip_version} \\
    -module_name {cfg.name} -dir {ip_dir}/{cfg.name}
set_property -dict [list \\
    CONFIG.PRIM_IN_FREQ {{{cfg.prim_in_freq:.3f}}} \\
    CONFIG.MMCM_CLKIN1_PERIOD {{{cfg.mmcm_clkin_period:.3f}}} \\
    CONFIG.MMCM_CLKFBOUT_MULT_F {{{cfg.mmcm_clkfbout_mult_f:.3f}}} \\
    CONFIG.MMCM_DIVCLK_DIVIDE {{{cfg.mmcm_divclk_divide}}} \\
    {clkout_str} \\
    CONFIG.RESET_TYPE {{{cfg.reset_type}}} \\
    CONFIG.USE_LOCKED {{true}} \\
    CONFIG.USE_RESET {{true}} \\
] [get_ips {cfg.name}]
"""


def _tcl_generate_target(name: str) -> str:
    """Generate TCL to generate target + export for one IP."""
    return f"""\
generate_target all [get_ips {name}]
catch {{ config_ip_cache -export [get_ips -all {name}] }}
export_ip_user_files -of_objects [get_ips {name}] -no_script -sync -force -quiet
"""


def generate_all_ip_tcl(mem: MemoryConfig, ip_dir: str, base_dir: str = "") -> tuple[str, list[str]]:
    """Generate TCL for all BRAM IPs from the memory configuration.

    Parameters
    ----------
    mem:
        Memory/cache configuration.
    ip_dir:
        Target directory for IP creation.
    base_dir:
        Project base directory for resolving relative paths (e.g. MIG prj file).

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

    # TLB BRAMs (optional)
    if mem.use_tlb_bram:
        cfg_tlb_flag = tlb_flag_to_bram("tlb_flag", mem.tlb)
        parts.append(generate_bram_create_ip_tcl(cfg_tlb_flag, ip_dir))
        names.append(cfg_tlb_flag.name)
        cfg_tlb_data = tlb_data_to_bram("tlb_data", mem.tlb)
        parts.append(generate_bram_create_ip_tcl(cfg_tlb_data, ip_dir))
        names.append(cfg_tlb_data.name)

    # DDR3 / Bridge / Clocking Wizard (when enabled)
    if mem.ddr3.enabled:
        # Clocking Wizard must be created first (provides clk_ddr_ref)
        cfg_cw = clkwiz_to_ip(mem.clk_wiz)
        parts.append(generate_clkwiz_create_ip_tcl(cfg_cw, ip_dir))
        names.append(cfg_cw.name)

        # MIG 7 Series
        cfg_mig = ddr3_to_mig_ip(mem.ddr3)
        parts.append(generate_mig_create_ip_tcl(cfg_mig, ip_dir, base_dir))
        names.append(cfg_mig.name)

        # AHB-Lite AXI Bridge
        cfg_bridge = bridge_to_ip(mem.ahb_bridge)
        parts.append(generate_bridge_create_ip_tcl(cfg_bridge, ip_dir))
        names.append(cfg_bridge.name)

    return "\n".join(parts), names
