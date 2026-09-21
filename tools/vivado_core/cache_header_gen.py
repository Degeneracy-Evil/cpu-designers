"""Generate ``cache_def.svh`` from MemoryConfig.

Produces a SystemVerilog header file with ```define`` constants for
cache geometry, address bit slices, and BRAM port widths.  This file
is the single source of truth for RTL — changing the YAML config and
regenerating this header automatically keeps RTL and IP in sync.

Address decomposition (32-bit physical address):

    addr[31:TAG_LO] = tag        (TAG_WIDTH bits)
    addr[SET_IDX_HI:SET_IDX_LO] = set_idx  (log2(NUM_SETS) bits)
    addr[WORD_OFF_HI:WORD_OFF_LO] = word_off (log2(LINE_WORDS) bits)
    addr[1:0]      = byte_off   (2 bits, unused at word level)
"""
from __future__ import annotations

from pathlib import Path

from .config import (
    CACHE_BYTE_ENABLE,
    CACHE_BYTE_SIZE,
    CACHE_LINE_WORDS,
    CACHE_NUM_SETS,
    CACHE_NUM_WAYS,
    MemoryConfig,
)


# ---------------------------------------------------------------------------
# Address bit-slice derivation
# ---------------------------------------------------------------------------

def _clog2(n: int) -> int:
    """Ceiling log2: smallest k such that 2^k >= n."""
    if n <= 1:
        return 1
    return (n - 1).bit_length()


def _derive_addr_slices(prefix: str) -> list[str]:
    """Generate macros for the fixed cache architecture.

    Parameters
    ----------
    prefix:
        Macro prefix (``"ICACHE"`` or ``"DCACHE"``).

    Returns
    -------
    list[str]
        Lines of ```define`` statements.
    """
    log2_sets = _clog2(CACHE_NUM_SETS)
    log2_line = _clog2(CACHE_LINE_WORDS)
    depth = CACHE_NUM_SETS * CACHE_NUM_WAYS
    line_width = CACHE_LINE_WORDS * 32
    wea_width = line_width // CACHE_BYTE_SIZE if CACHE_BYTE_ENABLE else 1

    # Bit positions (from LSB upward):
    #   [1:0]       byte_off   = 2 bits
    #   [log2_line+1 : 2]      word_off
    #   [log2_line+log2_sets+1 : log2_line+2]  set_idx
    #   [tag_hi : log2_line+log2_sets+2]       tag
    word_off_lo = 2
    word_off_hi = 2 + log2_line - 1
    set_idx_lo = word_off_hi + 1
    set_idx_hi = set_idx_lo + log2_sets - 1
    tag_lo = set_idx_hi + 1
    tag_hi = 31
    tag_width = 32 - tag_lo

    # Tag entry widths (for register arrays)
    # Both caches are write-through and need only valid + complete physical tag.
    tag_entry = tag_width + 1

    lines: list[str] = []
    p = prefix  # shorthand

    lines.append(f"`define {p}_NUM_SETS    {CACHE_NUM_SETS}")
    lines.append(f"`define {p}_NUM_WAYS    {CACHE_NUM_WAYS}")
    lines.append(f"`define {p}_TAG_WIDTH   {tag_width}")
    lines.append(f"`define {p}_LINE_WORDS  {CACHE_LINE_WORDS}")
    lines.append(f"`define {p}_LINE_WIDTH  {line_width}")
    lines.append(f"`define {p}_DEPTH       {depth}")
    lines.append(f"`define {p}_ADDR_WIDTH  {_clog2(depth)}")
    lines.append(f"`define {p}_WEA_WIDTH   {wea_width}")
    lines.append(f"")
    lines.append(f"// Address bit slices for {p}")
    lines.append(f"`define {p}_WORD_OFF_LO {word_off_lo}")
    lines.append(f"`define {p}_WORD_OFF_HI {word_off_hi}")
    lines.append(f"`define {p}_SET_IDX_LO {set_idx_lo}")
    lines.append(f"`define {p}_SET_IDX_HI {set_idx_hi}")
    lines.append(f"`define {p}_TAG_LO     {tag_lo}")
    lines.append(f"`define {p}_TAG_HI     {tag_hi}")

    # Tag entry width (for register array declaration)
    if prefix == "ICACHE":
        lines.append(f"`define {p}_TAG_ENTRY_WIDTH {tag_entry}")
    else:
        lines.append(f"`define {p}_TAG_ENTRY_WIDTH {tag_entry}")

    # Bit widths for set_idx and way (used in wire declarations)
    lines.append(f"`define {p}_SET_IDX_WIDTH {log2_sets}")
    lines.append(f"`define {p}_WAY_WIDTH    {_clog2(CACHE_NUM_WAYS)}")

    return lines


# ---------------------------------------------------------------------------
# ROM defines
# ---------------------------------------------------------------------------

def _derive_rom_defines(mem: MemoryConfig) -> list[str]:
    """Derive ``define`` macros for ROM."""
    lines: list[str] = []
    lines.append(f"`define ROM_DATA_WIDTH  {mem.rom.data_width}")
    lines.append(f"`define ROM_DEPTH       {mem.rom.depth}")
    lines.append(f"`define ROM_ADDR_WIDTH  {_clog2(mem.rom.depth)}")
    wea_width = mem.rom.data_width // mem.rom.byte_size if mem.rom.byte_enable else 1
    lines.append(f"`define ROM_WEA_WIDTH   {wea_width}")
    return lines


def _derive_ddr3_defines(mem: MemoryConfig) -> list[str]:
    """Derive ``define`` macros for DDR3 / Clocking Wizard."""
    lines: list[str] = []
    if not mem.ddr3.enabled:
        return lines
    
    lines.append(f"`define DDR3_ENABLED        1")
    lines.append(f"`define DDR3_IP_NAME        \"{mem.ddr3.ip_name}\"")
    lines.append(f"`define DDR3_AXI_ADDR_WIDTH {mem.ddr3.axi_addr_width}")
    lines.append(f"`define DDR3_AXI_DATA_WIDTH {mem.ddr3.axi_data_width}")
    lines.append(f"`define DDR3_AXI_ID_WIDTH   {mem.ddr3.axi_id_width}")
    lines.append(f"`define DDR3_DATA_RATE      {mem.ddr3.data_rate}")
    lines.append(f"")
    lines.append(f"`define CLK_WIZ_IP_NAME     \"{mem.clk_wiz.ip_name}\"")
    lines.append(f"`define CLK_WIZ_PRIM_IN_FREQ  {int(mem.clk_wiz.prim_in_freq)}")
    ddr_ref_freq = (
        mem.clk_wiz.clk_out3_freq
        if mem.clk_wiz.num_out_clks >= 3
        else mem.clk_wiz.clk_out2_freq
    )
    lines.append(f"`define CLK_WIZ_DDR_REF_FREQ {int(ddr_ref_freq)}")
    lines.append(f"`define MIG_UI_CLK_FREQ     {mem.ddr3.input_clk_freq}")
    return lines


# ---------------------------------------------------------------------------
# Full header generation
# ---------------------------------------------------------------------------

def generate_cache_header(mem: MemoryConfig) -> str:
    """Generate the full ``cache_def.svh`` content.

    Parameters
    ----------
    mem:
        Memory/cache configuration.

    Returns
    -------
    str
        Complete content of ``cache_def.svh``.
    """
    lines: list[str] = []
    lines.append("// =========================================================================")
    lines.append("// cache_def.svh — Cache & Memory geometry constants")
    lines.append("//")
    lines.append("// AUTO-GENERATED by tools/vivado_core/cache_header_gen.py")
    lines.append("// Do NOT edit manually — changes will be overwritten.")
    lines.append("// Edit vivado_config.yaml -> memory section instead, then run:")
    lines.append("//   python -m tools.vivado_cli --gen-config")
    lines.append("// =========================================================================")
    lines.append("")
    lines.append("`ifndef CACHE_DEF_SVH")
    lines.append("`define CACHE_DEF_SVH")
    lines.append("")

    # ROM
    lines.append("// --- ROM (Boot ROM) ---")
    lines.extend(_derive_rom_defines(mem))
    lines.append("")

    # DDR3 / Clocking Wizard
    ddr3_lines = _derive_ddr3_defines(mem)
    if ddr3_lines:
        lines.append("// --- DDR3 Main Memory (via MIG) ---")
        lines.extend(ddr3_lines)
        lines.append("")

    # I-Cache
    lines.append("// --- I-Cache ---")
    lines.extend(_derive_addr_slices("ICACHE"))
    lines.append("")

    # D-Cache
    lines.append("// --- D-Cache ---")
    lines.extend(_derive_addr_slices("DCACHE"))
    lines.append("")

    lines.append("`endif // CACHE_DEF_SVH")
    lines.append("")

    return "\n".join(lines)


def write_cache_header(mem: MemoryConfig, target_path: Path) -> None:
    """Generate and write ``cache_def.svh`` to disk.

    Parameters
    ----------
    mem:
        Memory/cache configuration.
    target_path:
        Full path to the output file (e.g. ``src/rtl/core/cache_def.svh``).
    """
    content = generate_cache_header(mem)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(content, encoding="utf-8")
