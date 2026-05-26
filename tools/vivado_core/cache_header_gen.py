"""Generate ``cache_def.svh`` from MemoryConfig.

Produces a SystemVerilog header file with ```define`` constants for
cache geometry, address bit slices, and BRAM port widths.  This file
is the single source of truth for RTL — changing the YAML config and
regenerating this header automatically keeps RTL and IP in sync.

Address decomposition (32-bit physical address):

    addr[31]       = is_mmio     (1 bit)
    addr[TAG_HI:TAG_LO]   = tag        (TAG_WIDTH bits)
    addr[SET_IDX_HI:SET_IDX_LO] = set_idx  (log2(NUM_SETS) bits)
    addr[WORD_OFF_HI:WORD_OFF_LO] = word_off (log2(LINE_WORDS) bits)
    addr[1:0]      = byte_off   (2 bits, unused at word level)
"""
from __future__ import annotations

import math
from pathlib import Path

from .config import CacheConfig, MemoryConfig, TlbConfig


# ---------------------------------------------------------------------------
# Address bit-slice derivation
# ---------------------------------------------------------------------------

def _clog2(n: int) -> int:
    """Ceiling log2: smallest k such that 2^k >= n."""
    if n <= 1:
        return 1
    return (n - 1).bit_length()


def _derive_addr_slices(cfg: CacheConfig, prefix: str) -> list[str]:
    """Derive address bit-slice ``define`` macros for one cache.

    Parameters
    ----------
    cfg:
        Cache geometry.
    prefix:
        Macro prefix (``"ICACHE"`` or ``"DCACHE"``).

    Returns
    -------
    list[str]
        Lines of ```define`` statements.
    """
    log2_sets = _clog2(cfg.num_sets)
    log2_line = _clog2(cfg.line_words)
    depth = cfg.num_sets * cfg.num_ways
    line_width = cfg.line_words * 32
    wea_width = line_width // cfg.byte_size if cfg.byte_enable else 1

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
    tag_hi = tag_lo + cfg.tag_width - 1

    # Tag entry widths (for register arrays)
    # icache: valid(1) + tag(tag_width) = tag_width + 1
    # dcache: valid(1) + dirty(1) + tag(tag_width) = tag_width + 2
    icache_tag_entry = cfg.tag_width + 1
    dcache_tag_entry = cfg.tag_width + 2

    lines: list[str] = []
    p = prefix  # shorthand

    lines.append(f"`define {p}_NUM_SETS    {cfg.num_sets}")
    lines.append(f"`define {p}_NUM_WAYS    {cfg.num_ways}")
    lines.append(f"`define {p}_TAG_WIDTH   {cfg.tag_width}")
    lines.append(f"`define {p}_LINE_WORDS  {cfg.line_words}")
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
        lines.append(f"`define {p}_TAG_ENTRY_WIDTH {icache_tag_entry}")
    else:
        lines.append(f"`define {p}_TAG_ENTRY_WIDTH {dcache_tag_entry}")

    # Bit widths for set_idx and way (used in wire declarations)
    lines.append(f"`define {p}_SET_IDX_WIDTH {log2_sets}")
    lines.append(f"`define {p}_WAY_WIDTH    {_clog2(cfg.num_ways)}")

    return lines


def _derive_tag_bram_defines(cfg: CacheConfig, prefix: str, has_dirty: bool) -> list[str]:
    """Derive tag BRAM ``define`` macros for one cache (when use_tag_bram=true).

    Tag BRAM packs all ways of a set into one BRAM line:
      - data_width = num_ways * tag_entry_width
      - depth = num_sets
      - Byte write enable: 1 bit per way (byte_size = tag_entry_width)
    """
    extra_bits = 2 if has_dirty else 1
    tag_entry_width = extra_bits + cfg.tag_width
    packed_width = cfg.num_ways * tag_entry_width
    depth = cfg.num_sets
    wea_width = cfg.num_ways  # 1 WEA bit per way

    lines: list[str] = []
    p = prefix
    lines.append(f"`define {p}_TAG_BRAM_WIDTH      {packed_width}")
    lines.append(f"`define {p}_TAG_BRAM_DEPTH      {depth}")
    lines.append(f"`define {p}_TAG_BRAM_ADDR_WIDTH {_clog2(depth)}")
    lines.append(f"`define {p}_TAG_BRAM_WEA_WIDTH  {wea_width}")
    # Per-way byte size within the packed BRAM line (matches Byte_Size in IP config)
    lines.append(f"`define {p}_TAG_BRAM_BYTE_SIZE  {tag_entry_width}")

    return lines


def _derive_tlb_bram_defines(cfg: TlbConfig) -> list[str]:
    """Derive TLB BRAM ``define`` macros (when use_tlb_bram=true).

    TLB Flag BRAM: packed all ways per set.
      - Per-way flag: V(1) + G(1) + ASID(9) + VPN(20) + mega(1) = 32 bits
      - Packed width = num_ways × 32 = 128 bits
      - Depth = num_sets

    TLB Data BRAM: packed all ways per set.
      - Per-way data: PPN(22) + R(1) + W(1) + X(1) + U(1) + A(1) + D(1) + pad(4) = 32 bits
      - Packed width = num_ways × 32 = 128 bits
      - Depth = num_sets
    """
    flag_entry_width = 1 + 1 + 9 + 20 + 1  # 32
    data_entry_width = 22 + 1 + 1 + 1 + 1 + 1 + 1 + 4  # 32 (with 4-bit padding)
    flag_packed_width = cfg.num_ways * flag_entry_width  # 128
    data_packed_width = cfg.num_ways * data_entry_width  # 128
    depth = cfg.num_sets
    # WEA width = packed_width / byte_size (from config, not per-way entry width)
    flag_wea_width = flag_packed_width // cfg.flag_byte_size
    data_wea_width = data_packed_width // cfg.data_byte_size

    lines: list[str] = []
    lines.append(f"`define TLB_NUM_WAYS           {cfg.num_ways}")
    lines.append(f"`define TLB_NUM_SETS          {cfg.num_sets}")
    lines.append(f"`define TLB_SET_IDX_WIDTH     {_clog2(cfg.num_sets)}")
    lines.append(f"`define TLB_WAY_WIDTH         {_clog2(cfg.num_ways)}")
    lines.append(f"")
    lines.append(f"`define TLB_FLAG_ENTRY_WIDTH  {flag_entry_width}")
    lines.append(f"`define TLB_FLAG_BRAM_WIDTH   {flag_packed_width}")
    lines.append(f"`define TLB_FLAG_BRAM_DEPTH   {depth}")
    lines.append(f"`define TLB_FLAG_BRAM_ADDR_WIDTH {_clog2(depth)}")
    lines.append(f"`define TLB_FLAG_BRAM_WEA_WIDTH  {flag_wea_width}")
    lines.append(f"`define TLB_FLAG_BRAM_BYTE_SIZE  {cfg.flag_byte_size}")
    lines.append(f"")
    lines.append(f"`define TLB_DATA_ENTRY_WIDTH  {data_entry_width}")
    lines.append(f"`define TLB_DATA_BRAM_WIDTH   {data_packed_width}")
    lines.append(f"`define TLB_DATA_BRAM_DEPTH   {depth}")
    lines.append(f"`define TLB_DATA_BRAM_ADDR_WIDTH {_clog2(depth)}")
    lines.append(f"`define TLB_DATA_BRAM_WEA_WIDTH  {data_wea_width}")
    lines.append(f"`define TLB_DATA_BRAM_BYTE_SIZE  {cfg.data_byte_size}")

    return lines


# ---------------------------------------------------------------------------
# SRAM defines
# ---------------------------------------------------------------------------

def _derive_sram_defines(mem: MemoryConfig) -> list[str]:
    """Derive ``define`` macros for SRAM."""
    lines: list[str] = []
    lines.append(f"`define SRAM_DATA_WIDTH  {mem.sram.data_width}")
    lines.append(f"`define SRAM_DEPTH       {mem.sram.depth}")
    lines.append(f"`define SRAM_ADDR_WIDTH  {_clog2(mem.sram.depth)}")
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

    # SRAM
    lines.append("// --- SRAM (Main Memory) ---")
    lines.extend(_derive_sram_defines(mem))
    lines.append("")

    # I-Cache
    lines.append("// --- I-Cache ---")
    lines.extend(_derive_addr_slices(mem.icache, "ICACHE"))
    if mem.use_tag_bram:
        lines.extend(_derive_tag_bram_defines(mem.icache, "ICACHE", has_dirty=False))
    lines.append("")

    # D-Cache
    lines.append("// --- D-Cache ---")
    lines.extend(_derive_addr_slices(mem.dcache, "DCACHE"))
    if mem.use_tag_bram:
        lines.extend(_derive_tag_bram_defines(mem.dcache, "DCACHE", has_dirty=True))
    lines.append("")

    # Tag BRAM flag
    lines.append("// --- Tag storage mode ---")
    lines.append(f"`define USE_TAG_BRAM {1 if mem.use_tag_bram else 0}")
    lines.append("")

    # TLB BRAM
    # Always generate TLB geometry defines (needed for ifdef blocks in RTL)
    lines.append("// --- TLB geometry ---")
    lines.extend(_derive_tlb_bram_defines(mem.tlb))
    lines.append("")

    # TLB storage mode (only define when enabled, so ifdef works correctly)
    if mem.use_tlb_bram:
        lines.append("// --- TLB storage mode ---")
        lines.append(f"`define USE_TLB_BRAM 1")
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
        Full path to the output file (e.g. ``dev/rtl/core/cache_def.svh``).
    """
    content = generate_cache_header(mem)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(content, encoding="utf-8")
