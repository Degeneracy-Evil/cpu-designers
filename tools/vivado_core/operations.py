"""High-level Vivado operations: create, refresh, sim, bitstream, program, archive.

Each method performs a preflight check, ensures the Vivado process is
running, executes the appropriate TCL commands, and updates session
metadata.
"""
from __future__ import annotations

import logging
import os
import re
from pathlib import Path

from .cache_header_gen import write_cache_header
from .config import MemoryConfig, RtlPathsConfig
from .exceptions import OperationError, StaleSessionError, VivadoProcessError
from .hash import LayeredHash
from .ip_gen import generate_all_ip_tcl, get_bram_ip_names
from .session import ExecuteResult, Session, SessionManager
from .sync import SyncPolicy
from .tasks import TaskConfig, TaskRegistry

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# TCL path helper
# ---------------------------------------------------------------------------

def _tcl_escape(s: str) -> str:
    """Escape a string for safe TCL interpolation."""
    s = str(s)
    s = s.replace('\\', '\\\\')
    s = s.replace('"', '\\"')
    s = s.replace('$', '\\$')
    s = s.replace('[', '\\[')
    s = s.replace(']', '\\]')
    return s

def _tcl_path(p: Path | str) -> str:
    """Convert a path to a TCL-safe forward-slash string.

    On Windows, ``str(Path(...))`` uses backslashes which TCL interprets
    as escape characters (e.g. ``E:\\Xprogram`` -> ``E:Xprogram``).
    Forward slashes work correctly in TCL on all platforms.
    """
    return _tcl_escape(Path(p).as_posix())


# ---------------------------------------------------------------------------
# TCL template helpers
# ---------------------------------------------------------------------------

def _find_tb_path(tb_dir: str, tb_name: str) -> str:
    """Resolve the actual path of a testbench file.

    Searches *tb_dir* first, then its immediate subdirectories, for
    ``{tb_name}.sv``.  This handles testbenches that live in sub-
    directories (e.g. ``dev/tb/ALU/tb_alu_cpu_integration.sv``).

    Returns the absolute path if found, otherwise falls back to
    ``{tb_dir}/{tb_name}.sv`` (the old behaviour) so that Vivado
    will emit its own clear "file not found" error.
    """
    direct = Path(tb_dir) / f"{tb_name}.sv"
    if direct.is_file():
        return str(direct)
    for child in sorted(Path(tb_dir).iterdir()):
        if child.is_dir():
            candidate = child / f"{tb_name}.sv"
            if candidate.is_file():
                return str(candidate)
    return str(direct)


def _resolve_rtl_dirs(dev_dir: str, rtl: RtlPathsConfig) -> dict[str, str]:
    """Build a dict of named RTL directory paths from config.

    Returns a mapping like ``{"alu": "dev/rtl/ALU", "mu": "dev/rtl/MU", ...}``
    using the relative fragments from *rtl* combined with *dev_dir*.
    """
    rtl_base = f"{dev_dir}/rtl"
    dirs: dict[str, str] = {}
    for key, frag in (
        ("alu", rtl.alu),
        ("mu", rtl.mu),
        ("fpu", rtl.fpu),
        ("cpu_core", rtl.cpu_core),
        ("common", rtl.common),
        ("ahb", rtl.ahb),
        ("ahb_ip", rtl.ahb_ip),
        ("amba", rtl.amba),
        ("ram_wrap", rtl.ram_wrap),
        ("apb", rtl.apb),
        ("apb_header", rtl.apb_header),
        ("apb_perips", rtl.apb_perips),
        ("apb_uart16550", rtl.apb_uart16550),
    ):
        dirs[key] = f"{rtl_base}/{frag}" if frag else rtl_base
    dirs["sys_rtl"] = f"{rtl_base}/{rtl.sys_rtl}" if rtl.sys_rtl else rtl_base
    dirs["tb"] = f"{dev_dir}/tb"
    return dirs

def _tcl_create_project(
    proj_name: str,
    device_part: str,
    proj_dir: str,
    dev_dir: str,
    base_dir: str,
    rtl: RtlPathsConfig,
) -> str:
    """Generate TCL for project creation + RTL import + include dirs.

    This mirrors the logic in ``tools/vivado_core/tcl/_create.tcl`` but with
    all paths parameterised.
    """
    d = _resolve_rtl_dirs(dev_dir, rtl)
    alu_rtl_dir = d["alu"]
    mu_rtl_dir = d["mu"]
    fpu_rtl_dir = d["fpu"]
    cpu_core_dir = d["cpu_core"]
    common_dir = d["common"]
    ahb_dir = d["ahb"]
    ahb_ip_dir = d["ahb_ip"]
    amba_dir = d["amba"]
    ram_wrap_dir = d["ram_wrap"]
    apb_dir = d["apb"]
    apb_header_dir = d["apb_header"]
    apb_perips_dir = d["apb_perips"]
    sys_rtl_dir = d["sys_rtl"]
    tb_dir = d["tb"]

    return f"""\
# --- create project ---
if {{ [catch {{current_project}} cur_proj] == 0 }} {{
    puts "Closing existing project: $cur_proj"
    close_project
}}
create_project "{proj_name}" "{proj_dir}" -part "{device_part}" -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# --- add RTL sources (scan_for_includes for auto dependency inference) ---
# Using add_files -scan_for_includes (chiplab approach) instead of
# per-file import_files, so Vivado auto-discovers `include deps
# and update_compile_order can infer correct compile order.
add_files -scan_for_includes "{alu_rtl_dir}"
add_files -scan_for_includes "{mu_rtl_dir}"
add_files -scan_for_includes "{fpu_rtl_dir}"
add_files -scan_for_includes "{cpu_core_dir}"
add_files -scan_for_includes "{common_dir}"
add_files -scan_for_includes "{ahb_dir}"
add_files -scan_for_includes "{amba_dir}"
add_files -scan_for_includes "{ram_wrap_dir}"
add_files -scan_for_includes "{apb_dir}"
# sys_rtl_dir top-level files only (avoid _archived/ recursion)
add_files -norecurse "{sys_rtl_dir}/system_top.sv"
add_files -norecurse "{sys_rtl_dir}/soc_config.vh"
if {{ [file exists "{sys_rtl_dir}/axi4_def.svh"] }} {{
    add_files -norecurse "{sys_rtl_dir}/axi4_def.svh"
}}
if {{ [file exists "{sys_rtl_dir}/clk_wiz_0_passthrough.sv"] }} {{
    add_files -norecurse "{sys_rtl_dir}/clk_wiz_0_passthrough.sv"
}}
if {{ [file exists "{sys_rtl_dir}/debug_uart_tx.sv"] }} {{
    add_files -norecurse "{sys_rtl_dir}/debug_uart_tx.sv"
}}
update_compile_order -fileset sources_1

# --- set include dirs ---
set_property include_dirs [list \\
    "{alu_rtl_dir}" \\
    "{mu_rtl_dir}" \\
    "{fpu_rtl_dir}" \\
    "{cpu_core_dir}" \\
    "{common_dir}" \\
    "{ahb_dir}" \\
    "{ahb_ip_dir}" \\
    "{amba_dir}" \\
    "{ram_wrap_dir}" \\
    "{apb_dir}" \\
    "{apb_header_dir}" \\
    "{apb_perips_dir}" \\
    "{sys_rtl_dir}" \\
    "{tb_dir}" \\
] [current_fileset]
"""


def _tcl_setup_ip(
    proj_name: str,
    proj_dir: str,
    base_dir: str,
    blcoe_file: str,
    mem_config: MemoryConfig,
) -> str:
    """Generate TCL for IP creation and ROM COE configuration.

    Uses ``create_ip`` from :mod:`ip_gen` to dynamically create BRAM IPs
    based on the memory configuration, replacing the old static XCI import.

    Target generation order: icached/dcached first, then ROM (after COE
    config) to avoid double ``generate_target`` on ROM.
    """
    from .ip_gen import _tcl_generate_target

    ip_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

    # --- Dynamic IP creation from config (create + set_property only) ---
    ip_tcl, ip_names = generate_all_ip_tcl(mem_config, ip_dir, base_dir)

    # Generate targets for non-ROM IPs immediately.
    gen_others = "\n".join(_tcl_generate_target(n) for n in ip_names if n != "ROM")

    # --- ROM COE configuration + generate_target ---
    if blcoe_file:
        coe_tail = Path(blcoe_file).name
        rom_block = f"""\
set ip_rom [get_ips -all ROM]
file copy -force {blcoe_file} "{ip_dir}/ROM/"
set_property -dict [list \\
    CONFIG.Load_Init_File {{true}} \\
    CONFIG.Coe_File "{ip_dir}/ROM/{coe_tail}" \\
] $ip_rom
{_tcl_generate_target("ROM")}
puts "ROM IP configured (COE: {blcoe_file})\""""
    else:
        rom_block = f"""\
set ip_rom [get_ips -all ROM]
set_property -dict [list \\
    CONFIG.Load_Init_File {{false}} \\
] $ip_rom
{_tcl_generate_target("ROM")}
puts "ROM IP configured (no COE init)\""""

    return f"""\
# --- setup IP (dynamic create_ip from config) ---
update_compile_order -fileset sources_1
{ip_tcl}

# --- Generate targets for all non-ROM IPs (cache BRAMs + DDR3 IPs) ---
{gen_others}

# --- ROM COE configuration + generate target ---
{rom_block}"""


def _tcl_add_constrs(base_dir: str) -> str:
    """Generate TCL for adding DCP and constraint files.

    Mirrors ``tools/vivado_core/tcl/_add_constrs.tcl``.
    """
    fpga_dir = f"{base_dir}/dev/fpga"
    return f"""\
# --- add constraints ---
import_files -norecurse "{fpga_dir}/lcd_module.dcp"
import_files -norecurse -fileset constrs_1 "{fpga_dir}/cpu.xdc"
"""


def _tcl_add_bram_sim_models(
    proj_dir: str,
    proj_name: str,
    bram_ip_names: list[str],
) -> str:
    """Generate TCL for adding BRAM IP simulation models to sim_1.

    For each BRAM IP created via ``create_ip``, XSim needs the
    behavioral simulation model (``blk_mem_gen_v8_4.v``) and the
    per-IP wrapper (``sim/<ip>.v``) to resolve the IP module during
    elaboration.  Without these, XSim fails with "module <IP> not found".

    Parameters
    ----------
    proj_dir:
        Vivado project directory (TCL path format).
    proj_name:
        Vivado project name (for constructing the IP path).
    bram_ip_names:
        List of BRAM IP instance names (derived from MemoryConfig).
    """
    ip_base = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"
    lines: list[str] = []
    lines.append('# --- BRAM IP simulation models (blk_mem_gen_v8_4) ---')
    lines.append('puts "Adding BRAM IP simulation models..."')
    lines.append(f'set bram_ip_dir "{ip_base}"')
    lines.append('set bram_sim_model_added 0')
    for ip_name in bram_ip_names:
        ip_path = f"$bram_ip_dir/{ip_name}/{ip_name}"
        lines.append(
            f'if {{ [file exists [file join "{ip_path}" sim {ip_name}.v]] }} {{\n'
            f'    add_files -fileset sim_1 -norecurse [file join "{ip_path}" sim {ip_name}.v]\n'
            f'}}'
        )
        lines.append(
            f'if {{ $bram_sim_model_added == 0 && [file exists [file join "{ip_path}" simulation blk_mem_gen_v8_4.v]] }} {{\n'
            f'    add_files -fileset sim_1 -norecurse [file join "{ip_path}" simulation blk_mem_gen_v8_4.v]\n'
            f'    set bram_sim_model_added 1\n'
            f'}}'
        )
    return "\n".join(lines)


def _tcl_cleanup_ip_gen(
    proj_dir: str,
    proj_name: str,
    bram_ip_names: list[str],
    mem_config: MemoryConfig,
) -> str:
    """Generate TCL to delete IP gen/ directories before project creation.

    Following the chiplab pattern: deleting ``gen/`` subdirectories forces
    Vivado to re-customize IPs from scratch on the next ``create_ip``,
    avoiding stale output products that can cause simulation failures
    (e.g. mismatched IP versions, corrupted simulation models).

    Parameters
    ----------
    proj_dir:
        Vivado project directory (TCL path format).
    proj_name:
        Vivado project name.
    bram_ip_names:
        BRAM IP instance names to clean.
    mem_config:
        Memory configuration (to check for DDR3/Bridge/ClkWiz IPs).
    """
    ip_base = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"
    lines: list[str] = []
    lines.append('# --- IP gen/ cleanup (chiplab pattern: force fresh IP customization) ---')
    for ip_name in bram_ip_names:
        lines.append(f'file delete -force "{ip_base}/{ip_name}/gen"')
    if mem_config.ddr3.enabled:
        lines.append(f'file delete -force "{ip_base}/{mem_config.ddr3.ip_name}/gen"')
        lines.append(f'file delete -force "{ip_base}/{mem_config.clk_wiz.ip_name}/gen"')
    return "\n".join(lines)


def _tcl_upgrade_ip() -> str:
    """Generate TCL for upgrade_ip step after all IPs are created.

    Following the chiplab pattern: ``upgrade_ip -quiet [get_ips]`` handles
    version migration when the Vivado version differs from the version
    that originally created the IP.  Without this, stale IP output
    products can cause elaborate/synthesis failures.
    """
    return """\
# --- upgrade_ip (chiplab pattern: handle version migration) ---
catch { upgrade_ip -quiet [get_ips] }
"""


def _tcl_add_ddr3_sim_models(
    base_dir: str,
    proj_dir: str,
    proj_name: str,
    bram_ip_names: list[str],
    mig_ip_name: str,
) -> str:
    """Generate TCL for adding DDR3 simulation model files.

    Adds the MIG simulation model (from the generated IP's ``user_design/rtl/``),
    the external DDR3 model files (``ddr3_model.sv``, ``wiredly.v``) from
    ``Reference/ddr3_sim/``, and BRAM IP simulation models.

    Parameters
    ----------
    base_dir:
        Project root directory (TCL path format).
    proj_dir:
        Vivado project directory (TCL path format).
    proj_name:
        Vivado project name.
    bram_ip_names:
        List of BRAM IP instance names (derived from MemoryConfig).
    mig_ip_name:
        MIG IP instance name (e.g. ``mig_axi_32``).
    """
    ddr3_dir = f"{base_dir}/Reference/ddr3_sim"

    # MIG IP simulation model path (generated by create_ip + generate_target)
    mig_ip_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip/{mig_ip_name}/{mig_ip_name}/{mig_ip_name}/user_design/rtl"

    bram_tcl = _tcl_add_bram_sim_models(proj_dir, proj_name, bram_ip_names)

    return f"""\
# --- MIG simulation model (from generated IP) ---
# MIG's sim model lives in user_design/rtl/ which XSim's dependency
# resolver cannot discover automatically.  We add the files to sim_1
# by reference so they appear in the prj file unconditionally.
#
# CRITICAL: Use _mig_sim.v (SIM_BYPASS_INIT_CAL="FAST") instead of
# _mig.v (SIM_BYPASS_INIT_CAL="OFF") for simulation. Per Xilinx UG586
# and AR 44019, SIM_BYPASS_INIT_CAL="OFF" is NOT SUPPORTED in
# behavioral simulation — calibration FSM hangs forever because
# IODELAY elements have no real delay. The _mig_sim.v model has
# SIM_BYPASS_INIT_CAL="FAST" as default, matching the official MIG
# example project which completes calibration at ~107ns.
#
# Both files define the same module name ({mig_ip_name}_mig),
# so only ONE must be in sim_1. We explicitly remove _mig.v if it
# was auto-added from sources_1 (by create_ip), then add _mig_sim.v.
puts "Adding MIG simulation model (using _mig_sim.v)..."
if {{ [file exists "{mig_ip_dir}"] }} {{
    # Remove _mig.v from sim_1 if present (hardware model, not for sim)
    set mig_v [get_files -of_objects [get_filesets sim_1] -quiet "*/{mig_ip_name}_mig.v"]
    if {{ [llength $mig_v] > 0 }} {{
        remove_files -fileset sim_1 -norecurse $mig_v
        puts "  Removed _mig.v (hardware model) from sim_1"
    }}
    add_files -fileset sim_1 -norecurse [file join "{mig_ip_dir}" {mig_ip_name}.v]
    add_files -fileset sim_1 -norecurse [file join "{mig_ip_dir}" {mig_ip_name}_mig_sim.v]
    puts "  Added _mig_sim.v (simulation model, SIM_BYPASS_INIT_CAL=FAST)"
    foreach subdir {{axi clocking controller ecc ip_top phy ui}} {{
        set subpath [file join "{mig_ip_dir}" $subdir]
        if {{[file exists $subpath]}} {{
            foreach f [glob -nocomplain -directory $subpath *.v] {{
                add_files -fileset sim_1 -norecurse $f
            }}
        }}
    }}
}} else {{
    puts "WARNING: MIG user_design/rtl not found at {mig_ip_dir}"
}}

# --- DDR3 simulation model ---
import_files -fileset sim_1 -norecurse "{ddr3_dir}/ddr3_model.sv"
import_files -fileset sim_1 -norecurse "{ddr3_dir}/ddr3_model_parameters.vh"
set_property file_type "Verilog Header" [get_files ddr3_model_parameters.vh]

{bram_tcl}

# --- glbl.v (global reset/set signals) ---
# Do NOT add a stub glbl.v to sim_1. XSim provides its own glbl.v
# (with proper GSR ROC_WIDTH timing) in the xsim run directory.
# A stub with GSR=1'b1 (permanent global reset) prevents MIG
# calibration from ever completing (init_calib_complete stays X).
# The testbench instantiates glbl explicitly: `glbl u_glbl();`
# which XSim resolves to its built-in glbl module.
puts "Skipping glbl.v stub — XSim provides its own with proper GSR timing"

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
"""


def _tcl_set_verilog_defines(defines: dict[str, str]) -> str:
    """Generate TCL for setting verilog defines for simulation.

    Parameters
    ----------
    defines:
        Mapping of define name to value, e.g.
        ``{"SIM_BYPASS_INIT_CAL": "FAST", "SIMULATION": "TRUE"}``.
    """
    parts = [f"{k}={v}" for k, v in defines.items()]
    define_str = " ".join(parts)
    return f"""\
# --- verilog defines for simulation ---
set_property verilog_define {{{define_str}}} [get_filesets sim_1]
"""


def _tcl_copy_hex_file(hex_src: str, proj_dir: str, proj_name: str, bl_src: str = "") -> str:
    """Generate TCL for copying HEX files for ``$readmemh`` access.

    Copies prog.hex (SRAM) and bootloader.hex (bootrom) to the xsim run directory.
    """
    xsim_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"
    bl_copy = ""
    if bl_src:
        bl_copy = f"""
if {{ [file exists "{bl_src}"] }} {{
    file copy -force "{bl_src}" "{xsim_dir}/bootloader.hex"
    puts "Copied {bl_src} -> {xsim_dir}/bootloader.hex"
}}"""
    return f"""\
# --- copy hex file for $readmemh ---
file mkdir "{xsim_dir}"
if {{ [file exists "{hex_src}"] }} {{
    file copy -force "{hex_src}" "{xsim_dir}/prog.hex"
    puts "Copied {hex_src} -> {xsim_dir}/prog.hex"
}} else {{
    puts "WARNING: HEX file not found: {hex_src}"
}}{bl_copy}
"""


def _tcl_add_tb(
    dev_dir: str,
    proj_dir: str,
    proj_name: str,
    tb_name: str,
    blcoe_file: str,
    rtl: RtlPathsConfig,
) -> str:
    """Generate TCL for adding testbench and updating COE.

    Mirrors ``tools/vivado_core/tcl/_add_tb.tcl``.
    """
    d = _resolve_rtl_dirs(dev_dir, rtl)
    tb_dir = d["tb"]
    ip_xci_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

    tb_path = _find_tb_path(tb_dir, tb_name)

    alu_rtl_dir = d["alu"]
    mu_rtl_dir = d["mu"]
    fpu_rtl_dir = d["fpu"]
    cpu_core_dir = d["cpu_core"]
    common_dir = d["common"]
    ahb_dir = d["ahb"]
    amba_dir = d["amba"]
    ram_wrap_dir = d["ram_wrap"]
    apb_dir = d["apb"]
    apb_header_dir = d["apb_header"]
    apb_perips_dir = d["apb_perips"]
    apb_uart16550_dir = d["apb_uart16550"]
    sys_rtl_dir = d["sys_rtl"]

    coe_update = ""
    if blcoe_file:
        coe_tail = Path(blcoe_file).name
        coe_update = f"""\
if {{ [catch {{get_ips ROM}} ip_rom] == 0 && $ip_rom ne "" }} {{
    file copy -force {blcoe_file} "{ip_xci_dir}/ROM/"
    set_property -dict [list \\
        CONFIG.Load_Init_File {{true}} \\
        CONFIG.Coe_File "{ip_xci_dir}/ROM/{coe_tail}" \\
    ] $ip_rom
    puts "COE updated: {blcoe_file}"
    generate_target all $ip_rom
}}"""
    else:
        coe_update = """\
if { [catch {get_ips ROM} ip_rom] == 0 && $ip_rom ne "" } {
    set_property -dict [list CONFIG.Load_Init_File {false}] $ip_rom
    puts "COE updated: no COE init"
    generate_target all $ip_rom
}"""

    return f"""\
# --- add testbench ---
set existing_sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if {{ [llength $existing_sim_files] > 0 }} {{
    remove_files -fileset sim_1 -quiet $existing_sim_files
}}
set src_includes [get_property include_dirs [get_filesets sources_1]]
set_property include_dirs $src_includes [get_filesets sim_1]

# --- import RTL sources into sim_1 (BEFORE testbench) ---
# Vivado 2018.3's prj generator only includes files that are
# imported into sim_1 — it ignores files merely referenced via
# add_files.  import_files -fileset sim_1 copies each source
# into the sim_1 directory so the prj generator discovers them.
foreach f [glob -nocomplain -directory "{alu_rtl_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{mu_rtl_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{fpu_rtl_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{cpu_core_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{cpu_core_dir}" *.svh] {{
    import_files -fileset sim_1 -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{common_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{ahb_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{ahb_dir}" *.svh] {{
    import_files -fileset sim_1 -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{amba_dir}" *.v] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{amba_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{ram_wrap_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_dir}" *.svh] {{
    import_files -fileset sim_1 -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{apb_perips_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_uart16550_dir}" *.sv] {{ import_files -fileset sim_1 -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_uart16550_dir}" *.svh] {{
    import_files -fileset sim_1 -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{apb_header_dir}" *.svh] {{
    import_files -fileset sim_1 -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
if {{ [file exists "{cpu_core_dir}/cache_def.svh"] }} {{
    import_files -fileset sim_1 -norecurse "{cpu_core_dir}/cache_def.svh"
    set_property file_type "Verilog Header" [get_files cache_def.svh]
}}
if {{ [file exists "{sys_rtl_dir}/soc_config.vh"] }} {{
    import_files -fileset sim_1 -norecurse "{sys_rtl_dir}/soc_config.vh"
    set_property file_type "Verilog Header" [get_files soc_config.vh]
}}
if {{ [file exists "{sys_rtl_dir}/axi4_def.svh"] }} {{
    import_files -fileset sim_1 -norecurse "{sys_rtl_dir}/axi4_def.svh"
    set_property file_type "Verilog Header" [get_files axi4_def.svh]
}}
import_files -fileset sim_1 -norecurse "{sys_rtl_dir}/system_top.sv"
if {{ [file exists "{sys_rtl_dir}/clk_wiz_0_passthrough.sv"] }} {{
    import_files -fileset sim_1 -norecurse "{sys_rtl_dir}/clk_wiz_0_passthrough.sv"
}}
if {{ [file exists "{sys_rtl_dir}/debug_uart_tx.sv"] }} {{
    import_files -fileset sim_1 -norecurse "{sys_rtl_dir}/debug_uart_tx.sv"
}}

# --- import testbench LAST (after all RTL) ---
# Vivado 2018.3: importing the testbench before RTL sources that define
# packages (e.g. MMU.sv's $unit_MMU_sv) causes xvlog --incr to
# re-analyze the testbench when the package is overwritten, which
# silently drops the .sdb file and breaks xelab.
import_files -fileset sim_1 "{tb_path}"
if {{ [file exists "{tb_dir}/lcd_module_stub.sv"] }} {{
    import_files -fileset sim_1 "{tb_dir}/lcd_module_stub.sv"
}}

update_compile_order -fileset sim_1

# --- set testbench as top (AFTER import_files + update_compile_order) ---
# Vivado 2018.3: import_files triggers hierarchy re-evaluation that may
# override the top module.  Setting source_mgmt_mode None and top AFTER
# all imports + compile order ensures the testbench is validated correctly.
set_property source_mgmt_mode None [current_project]
set_property top {tb_name} [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# --- update COE ---
{coe_update}
"""


def _tcl_debug_wave(level: str) -> str:
    """Generate TCL for debug waveform logging after simulation launch.

    Parameters
    ----------
    level:
        ``"minimal"`` — top-level ports + key control signals.
        ``"normal"`` — core pipeline + regfile + peripherals.
        ``"full"`` — all signals + VCD export.
    """
    if level == "minimal":
        return """\
# --- debug waveform: minimal (top ports + control) ---
log_wave [get_objects /tb_*/u_soc/*]
"""
    elif level == "normal":
        return """\
# --- debug waveform: normal (core pipeline + regfile + perips) ---
log_wave [get_objects /tb_*/u_soc/*]
log_wave [get_objects /tb_*/u_soc/cpu/*]
"""
    elif level == "full":
        return """\
# --- debug waveform: full (all signals + VCD) ---
log_wave [get_objects *]
open_vcd sim_dump.vcd
log_vcd [get_objects *]
"""
    else:
        return ""


def _tcl_run_sim(
    tb_name: str,
    runtime: str,
    proj_dir: str,
    proj_name: str,
    wave_level: str | None = None,
) -> str:
    """Generate TCL for launching simulation and reading the log.

    Mirrors ``tools/vivado_core/tcl/_run_sim.tcl``.

    Parameters
    ----------
    tb_name:
        Testbench module name.
    runtime:
        Simulation runtime string (e.g. ``"5ms"``).
    proj_dir:
        Project directory path.
    proj_name:
        Project name.
    wave_level:
        Debug waveform level: ``"minimal"``, ``"normal"``, ``"full"``,
        or ``None`` (no waveform).  Adds ``log_wave`` commands after
        ``launch_simulation``.
    """
    sim_log_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"

    # Waveform TCL snippet
    wave_tcl = ""
    if wave_level:
        wave_tcl = _tcl_debug_wave(wave_level)

    return f"""\
# --- run simulation ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
# Re-assert testbench as top after update_compile_order (Vivado 2018.3 may
# override it during hierarchy re-evaluation in auto update mode).
set_property source_mgmt_mode None [current_project]
set_property top {tb_name} [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

if {{ [catch {{current_sim_state}} sim_state] == 0 }} {{
    if {{ $sim_state ne "none" }} {{
        close_sim -force
    }}
}}
set_property xsim.simulate.runtime {runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]
launch_simulation -mode behavioral
{wave_tcl}
# --- read sim log ---
set sim_log_file "{sim_log_dir}/simulate.log"
if {{ [file exists $sim_log_file] }} {{
    set fp [open $sim_log_file r]
    set data [read $fp]
    close $fp
    puts $data
}} else {{
    puts "WARNING: sim log not found: $sim_log_file"
}}
"""


# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

class Operations:
    """High-level Vivado operations.

    Parameters
    ----------
    session_mgr:
        Session manager for locating/creating sessions.
    task_registry:
        Task registry for looking up task configurations.
    sync:
        Synchronisation policy for preflight checks.
    layered_hash:
        Hash computer for updating session hashes after create/refresh.
    """

    def __init__(
        self,
        session_mgr: SessionManager,
        task_registry: TaskRegistry,
        sync: SyncPolicy,
        layered_hash: LayeredHash,
    ) -> None:
        self.session_mgr = session_mgr
        self.task_registry = task_registry
        self.sync = sync
        self.layered_hash = layered_hash

    @property
    def _limits(self):
        """Shortcut to the limits config from the session manager."""
        return self.session_mgr.config.limits

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _ensure_vivado(self, session: Session) -> None:
        """Start the Vivado process if it is not already running."""
        if not session.is_alive():
            session.start_vivado()

    def _preflight(self, session: Session, operation: str) -> None:
        """Run a preflight check; raise on hard errors, warn on soft.

        Raises
        ------
        StaleSessionError
            If the preflight severity is ``"error"``.
        """
        result = self.sync.preflight_check(session, operation)
        if result.severity == "error":
            raise StaleSessionError(session.name, result.stale_layers)
        if result.severity == "warning":
            logger.warning(
                "Preflight warning for %s/%s: %s",
                session.name,
                operation,
                result.reason,
            )

    def _resolve_blcoe_path(self, task: TaskConfig) -> str:
        """Return the absolute blcoe path for a task, or empty string.

        The path is returned in forward-slash form for TCL safety.
        """
        if not task.blcoe:
            return ""
        return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.blcoe)

    def _resolve_blhex_path(self, task: TaskConfig) -> str:
        """Return the bootloader hex path for the bootROM $readmemh.

        For SRAM-mode tasks (blhex set): returns the blhex path.
        For DDR3/FPGA tasks (blcoe set): returns the default bootloader.hex.
        """
        if task.blhex:
            return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.blhex)
        return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / "boot/bootloader.hex")

    def _resolve_phex_path(self, task: TaskConfig) -> str:
        """Return the program hex path for SRAM $readmemh, or empty string."""
        if not task.phex:
            return ""
        return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.phex)

    def _check_required_files(self, task: TaskConfig) -> str:
        """Pre-check that blcoe/blhex/phex files referenced by the task exist on disk.

        Returns an error message string if any file is missing, or empty string
        if all files are present.  The message includes the task name, missing
        file path, and the command to generate it.
        """
        base = self.session_mgr.base_dir / "dev" / "program_source"
        missing = []

        if task.blcoe:
            coe_path = base / task.blcoe
            if not coe_path.exists():
                missing.append(("BLCOE", task.blcoe, coe_path))

        if task.blhex:
            hex_path = base / task.blhex
            if not hex_path.exists():
                missing.append(("BLHEX", task.blhex, hex_path))

        if task.phex:
            hex_path = base / task.phex
            if not hex_path.exists():
                missing.append(("PHEX", task.phex, hex_path))

        if not missing:
            return ""

        lines = [f"Task '{task.name}' references missing file(s):"]
        for kind, rel, abs_path in missing:
            lines.append(f"  {kind}: {rel}  (not found at {abs_path})")
        lines.append(
            "Fix: build the test program first, e.g.\n"
            "  python -m tools.test_builder --category <category>\n"
            "  python -m tools.test_builder --app <app_name>"
        )
        return "\n".join(lines)

    def _update_hashes(self, session: Session) -> None:
        """Recompute and persist the current source hashes."""
        session.meta.hashes = self.layered_hash.compute_current()
        session.save_meta()

    _TIMEOUT_HINTS: dict[str, str] = {
        "create": (
            "Hint (create): Project creation can be slow for large designs. "
            "If this repeats, try -refresh --layers coe for incremental updates instead."
        ),
        "refresh": (
            "Hint (refresh): Full refresh rebuilds everything. "
            "Use --layers coe or --layers tb for faster incremental refresh."
        ),
        "sim": (
            "Hint (sim): Simulation may timeout due to long runtime or infinite loops. "
            "Try: 1) -runtime <shorter_time>, 2) check testbench for $finish, "
            "3) increase sim_timeout in vivado_config.yaml limits section."
        ),
        "bitstream": (
            "Hint (bitstream): Synthesis + implementation can take 10+ minutes. "
            "If this repeats, the design may be too complex for the current timeout."
        ),
        "program": (
            "Hint (program): FPGA programming timeout usually means a hardware issue. "
            "Check: JTAG cable connection, board power, Vivado HW server."
        ),
        "archive": (
            "Hint (archive): Large projects take longer to archive. "
            "Consider cleaning up unused runs first."
        ),
    }

    def _append_timeout_hint(self, result: ExecuteResult, operation: str) -> ExecuteResult:
        """Append an operation-specific timeout hint to the result output.

        If the result did not time out, returns it unchanged.
        """
        if not result.timed_out:
            return result
        hint = self._TIMEOUT_HINTS.get(operation, "")
        if hint:
            return ExecuteResult(
                output=f"{result.output}\n{hint}",
                success=result.success,
                timed_out=result.timed_out,
                duration=result.duration,
            )
        return result

    def _regenerate_cache_header(self) -> None:
        """Regenerate ``cache_def.svh`` from the current memory config."""
        mem_config = self.session_mgr.config.memory
        target = self.session_mgr.base_dir / "dev" / "rtl" / "core" / "cache_def.svh"
        write_cache_header(mem_config, target)
        logger.info("Regenerated cache_def.svh from memory config")

    # ------------------------------------------------------------------
    # Public operations
    # ------------------------------------------------------------------

    def create(self, session: Session, task: TaskConfig) -> ExecuteResult:
        """Create a Vivado project inside the session directory.

        Executes the equivalent of ``create_proj.tcl`` +
        ``setup_ip.tcl`` + ``add_constrs.tcl`` as a single
        parameterised TCL script.

        No preflight check is performed -- creating a project from
        scratch is always valid regardless of staleness state.

        .. note::

            The TCL backend executes ``close_project`` + ``create_project -force``,
            which **overwrites** any existing project in the target directory.
            Old waveform databases (``.wdb``), IP compile caches, and elaborated
            results are all discarded.

            Session-level deduplication (reusing an existing Session object
            without creating a new directory) is handled by the CLI layer
            (``vivado_cli.py`` ``get_or_create()``), **not** by this method.
            This method always sends the full create-project TCL sequence.

        Parameters
        ----------
        session:
            Target session. The session's ``project_dir`` will be overwritten
            if it already contains a Vivado project.
        task:
            Task configuration (used for COE path).

        Returns
        -------
        ExecuteResult
        """
        self._ensure_vivado(session)

        # Pre-check: COE/HEX files must exist before creating the project.
        file_err = self._check_required_files(task)
        if file_err:
            return ExecuteResult(output=file_err, success=False, timed_out=False, duration=0.0)

        # Regenerate cache_def.svh from current config before creating project.
        self._regenerate_cache_header()

        base = _tcl_path(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        device_part = self.session_mgr.config.device_part
        mem_config = self.session_mgr.config.memory
        blcoe_file = self._resolve_blcoe_path(task)
        bram_ip_names = get_bram_ip_names(mem_config)

        tcl_parts = [
            _tcl_cleanup_ip_gen(proj_dir, proj_name, bram_ip_names, mem_config),
            _tcl_create_project(proj_name, device_part, proj_dir, dev, base, self.session_mgr.config.rtl_path),
            _tcl_setup_ip(proj_name, proj_dir, base, blcoe_file, mem_config),
            _tcl_upgrade_ip(),
            _tcl_add_constrs(base),
        ]

        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=self._limits.create_timeout)
        result = self._append_timeout_hint(result, "create")
        self._update_hashes(session)
        session.update_last_used()
        return result

    def gen_config(self) -> str:
        """Regenerate cache_def.svh from the current YAML config.

        This is a standalone operation that does not require a running
        Vivado session.  Use it after editing ``vivado_config.yaml``
        to update the RTL header before the next create/refresh.

        Returns
        -------
        str
            Path to the generated file.
        """
        self._regenerate_cache_header()
        target = self.session_mgr.base_dir / "dev" / "rtl" / "core" / "cache_def.svh"
        return str(target)

    def refresh(
        self,
        session: Session,
        layers: list[str] | None = None,
    ) -> ExecuteResult:
        """Refresh a session to bring it in sync with source changes.

        No preflight check is performed -- the purpose of refresh is
        to *fix* staleness, so blocking on it would be circular.

        Parameters
        ----------
        session:
            Session to refresh.
        layers:
            Specific layers to refresh.  If ``None``, all stale layers
            are refreshed (determined by the sync policy).

        Returns
        -------
        ExecuteResult
        """
        self._ensure_vivado(session)

        staleness = self.layered_hash.compute_staleness(session.meta.hashes)

        # --layers overrides staleness: force-refresh even if hashes match
        if layers is not None:
            for layer in layers:
                if layer in staleness and not staleness[layer]:
                    logger.info("Forcing stale layer %r (--layers override)", layer)
                    staleness[layer] = True

        task = self.task_registry.get(session.meta.task)
        plan = self.sync.plan_refresh(staleness, task)

        if not plan.layers:
            # Nothing to refresh.
            return ExecuteResult(output="No stale layers", success=True, timed_out=False, duration=0.0)

        base = _tcl_path(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        device_part = self.session_mgr.config.device_part
        blcoe_file = self._resolve_blcoe_path(task)

        if plan.full:
            # Full rebuild: close -> cd up -> delete -> create.
            mem_config = self.session_mgr.config.memory
            bram_ip_names = get_bram_ip_names(mem_config)
            tcl_parts: list[str] = [
                f"catch {{ close_project }}\ncd [file dirname {proj_dir}]",
                f"file delete -force {proj_dir}",
                _tcl_create_project(proj_name, device_part, proj_dir, dev, base, self.session_mgr.config.rtl_path),
                _tcl_setup_ip(proj_name, proj_dir, base, blcoe_file, mem_config),
                _tcl_upgrade_ip(),
                _tcl_add_constrs(base),
                _tcl_add_tb(dev, proj_dir, proj_name, task.tb, blcoe_file, self.session_mgr.config.rtl_path) if task.tb else "",
            ]
        else:
            # Incremental: execute only the needed steps.
            # session.execute() auto-opens the project before each command.
            tcl_parts: list[str] = []
            rtl_dirs = _resolve_rtl_dirs(dev, self.session_mgr.config.rtl_path)
            tb_dir = rtl_dirs["tb"]
            ip_xci_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

            for step in plan.tcl_steps:
                if step == "remove_files_sim_1":
                    tcl_parts.append(
                        "set existing [get_files -of_objects [get_filesets sim_1] -quiet]; "
                        "if { [llength $existing] > 0 } { remove_files -fileset sim_1 -quiet $existing }"
                    )
                elif step == "add_tb":
                    if task.tb:
                        tb_path = _find_tb_path(tb_dir, task.tb)
                        tcl_parts.append(
                            f'add_files -fileset sim_1 "{tb_path}"'
                        )
                elif step == "set_property_top":
                    if task.tb:
                        tcl_parts.append(
                            f"set_property top {task.tb} [get_filesets sim_1]"
                        )
                elif step == "update_compile_order":
                    tcl_parts.append("update_compile_order -fileset sim_1")
                elif step == "update_coe":
                    if blcoe_file:
                        coe_tail = Path(blcoe_file).name
                        tcl_parts.append(
                            f'file copy -force {blcoe_file} "{ip_xci_dir}/ROM/"; '
                            f'set ip_rom [get_ips -all ROM]; '
                            f'set_property -dict [list CONFIG.Load_Init_File {{true}} '
                            f'CONFIG.Coe_File "{ip_xci_dir}/ROM/{coe_tail}"] $ip_rom; '
                            f"generate_target all $ip_rom"
                        )
                    else:
                        tcl_parts.append(
                            "set ip_rom [get_ips -all ROM]; "
                            "set_property -dict [list CONFIG.Load_Init_File {false}] $ip_rom; "
                            "generate_target all $ip_rom"
                        )
                elif step == "set_property_coe":
                    if blcoe_file:
                        coe_tail = Path(blcoe_file).name
                        tcl_parts.append(
                            f'set ip_rom [get_ips -all ROM]; '
                            f'file copy -force {blcoe_file} "{ip_xci_dir}/ROM/"; '
                            f'set_property -dict [list CONFIG.Load_Init_File {{true}} '
                            f'CONFIG.Coe_File "{ip_xci_dir}/ROM/{coe_tail}"] $ip_rom'
                        )
                    else:
                        tcl_parts.append(
                            "set ip_rom [get_ips -all ROM]; "
                            "set_property -dict [list CONFIG.Load_Init_File {false}] $ip_rom"
                        )
                elif step == "generate_target":
                    tcl_parts.append(
                        "set ip_rom [get_ips -all ROM]; "
                        "generate_target all $ip_rom"
                    )
                elif step == "remove_constrs":
                    tcl_parts.append(
                        "set constrs [get_files -of_objects [get_filesets constrs_1] -quiet]; "
                        "if { [llength $constrs] > 0 } { remove_files -fileset constrs_1 -quiet $constrs }"
                    )
                elif step == "add_constrs":
                    tcl_parts.append(_tcl_add_constrs(base))

        # DDR3 simulation mode: add simulation models
        if task.sim_mode == "ddr3":
            bram_ip_names = get_bram_ip_names(self.session_mgr.config.memory)
            mig_ip_name = self.session_mgr.config.memory.ddr3.ip_name
            tcl_parts.append(_tcl_add_ddr3_sim_models(base, proj_dir, proj_name, bram_ip_names, mig_ip_name))
        else:
            # Non-DDR3 tasks still need BRAM simulation models for XSim elaboration
            if task.tb:
                bram_ip_names = get_bram_ip_names(self.session_mgr.config.memory)
                tcl_parts.append(_tcl_add_bram_sim_models(proj_dir, proj_name, bram_ip_names))
                tcl_parts.append("update_compile_order -fileset sim_1")

        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=self._limits.refresh_timeout)
        result = self._append_timeout_hint(result, "refresh")
        self._update_hashes(session)
        session.update_last_used()
        return result

    def sim(
        self,
        session: Session,
        task: TaskConfig,
        runtime: str | None = None,
        debug_defines: dict[str, str] | None = None,
    ) -> ExecuteResult:
        """Run a simulation in the session.

        Parameters
        ----------
        session:
            Session to simulate in.
        task:
            Task configuration (testbench name, COE, runtime).
        runtime:
            Override simulation runtime (e.g. ``"5ms"``).  Falls back
            to ``task.runtime``.
        debug_defines:
            Additional Verilog defines for debug instrumentation
            (e.g. ``{"DEBUG_TRACE": "1", "DEBUG_WAVE": "1"}``).
            These are merged into ``task.verilog_defines``.

        Returns
        -------
        ExecuteResult
        """
        self._preflight(session, "sim")
        self._ensure_vivado(session)

        # Pre-check: COE/HEX files must exist for simulation to work.
        file_err = self._check_required_files(task)
        if file_err:
            return ExecuteResult(output=file_err, success=False, timed_out=False, duration=0.0)

        sim_runtime = runtime or task.runtime or "100000ns"
        base = _tcl_path(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        blcoe_file = self._resolve_blcoe_path(task)

        # NOTE: blcoe_file is passed to _tcl_add_tb which updates the ROM IP's
        # CONFIG.Coe_File property, but this is dead code during simulation —
        # the `ifdef SIMULATION` blocks in axi_wrap_ram.sv and
        # axi4lite_bootrom.sv replace the BRAM IP with behavioral models
        # that use $readmemh instead.  The COE update only matters for
        # FPGA bitstream generation (see create/refresh operations).
        tcl_parts = [
            _tcl_add_tb(dev, proj_dir, proj_name, task.tb, blcoe_file, self.session_mgr.config.rtl_path),
        ]

        # BRAM simulation models — always needed for XSim elaboration
        # (DDR3 mode adds them via _tcl_add_ddr3_sim_models below)
        bram_ip_names = get_bram_ip_names(self.session_mgr.config.memory)
        if task.sim_mode == "ddr3":
            mig_ip_name = self.session_mgr.config.memory.ddr3.ip_name
            tcl_parts.append(_tcl_add_ddr3_sim_models(base, proj_dir, proj_name, bram_ip_names, mig_ip_name))
        else:
            tcl_parts.append(_tcl_add_bram_sim_models(proj_dir, proj_name, bram_ip_names))
            tcl_parts.append("update_compile_order -fileset sim_1")

        # Verilog defines for simulation
        # DDR3 tasks define SIMULATION via task.verilog_defines in tasks.yaml
        # Non-DDR3 tasks need SIMULATION=TRUE to activate generate blocks
        # in system_top.sv (SIMU_USE_PLL/SIMU_USE_DDR conditional paths)
        if task.verilog_defines:
            defines = dict(task.verilog_defines)
        else:
            defines = {}
        if debug_defines:
            defines.update(debug_defines)
        if task.sim_mode != "ddr3" and "SIMULATION" not in defines:
            defines["SIMULATION"] = "TRUE"
        if defines:
            tcl_parts.append(_tcl_set_verilog_defines(defines))

        # HEX file copy for $readmemh — copies prog.hex + bootloader.hex
        # to the xsim run directory so $readmemh can find them.
        phex_path = self._resolve_phex_path(task)
        bl_hex_path = self._resolve_blhex_path(task)
        if phex_path:
            tcl_parts.append(_tcl_copy_hex_file(phex_path, proj_dir, proj_name, bl_hex_path))

        # Determine waveform level from debug defines
        wave_level = None
        if debug_defines and "DEBUG_WAVE" in debug_defines:
            wave_level = debug_defines.get("WAVE_LEVEL", "normal")

        tcl_parts.append(_tcl_run_sim(task.tb, sim_runtime, proj_dir, proj_name, wave_level=wave_level))
        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=self._limits.sim_timeout)
        result = self._append_timeout_hint(result, "sim")

        # --- Vivado 2018.3 xsim.dir stale library workaround ---
        # xvlog --incr silently drops the testbench .sdb when files are
        # imported in the same process, causing xelab "Cannot find design
        # unit".  Restarting the Vivado process clears the stale in-memory
        # cache; the fresh process reads the persisted project from disk
        # and builds a correct library index.
        if not result.success and task.tb and "Cannot find design unit" in (result.output or ""):
            logger.info("Vivado 2018.3 incr bug detected — restarting process and retrying sim")
            xsim_dir = Path(proj_dir) / f"{proj_name}.sim" / "sim_1" / "behav" / "xsim" / "xsim.dir"
            if xsim_dir.exists():
                import shutil
                shutil.rmtree(xsim_dir, ignore_errors=True)
            session.stop_vivado()
            tcl_sim_only = _tcl_run_sim(task.tb, sim_runtime, proj_dir, proj_name, wave_level=wave_level)
            result = session.execute(tcl_sim_only, timeout=self._limits.sim_timeout)
            result = self._append_timeout_hint(result, "sim")

        # --- prj patching ---
        # Vivado 2018.3's dependency resolver frequently produces an
        # incomplete prj that omits sources_1 files (SV→VHDL boundaries,
        # `include dependencies, etc.).  When this happens,
        # launch_simulation fails at elaborate with "Module <X> not found".
        # We detect this, patch the prj file to include sources_1 files,
        # and re-run xvlog/xelab/xsim manually.
        if not result.success:
            patched = self._patch_prj_and_rerun(
                session, task, sim_runtime, proj_dir, proj_name, defines=defines
            )
            if patched is not None:
                return patched

        # --- Semantic pass/fail check on sim output ---
        # The normal path uses session.execute().success which only checks
        # for Vivado "ERROR:" lines.  Strengthen with text-level PASS/FAIL
        # detection so a sim that ran cleanly but reported FAIL in output
        # is correctly classified.
        if result.success and "PASS" in result.output:
            if "FAIL" in result.output:
                result = ExecuteResult(
                    output=result.output,
                    success=False,
                    timed_out=result.timed_out,
                    duration=result.duration,
                )

        session.update_last_used()
        return result

    def _patch_prj_and_rerun(
        self,
        session: Session,
        task: TaskConfig,
        runtime: str,
        proj_dir: str,
        proj_name: str,
        defines: dict[str, str] | None = None,
    ) -> ExecuteResult | None:
        """Patch incomplete prj file and re-run xvlog/xelab/xsim.

        Returns ``None`` if patching is not applicable (e.g. prj file
        not found or already complete).  Returns an ``ExecuteResult``
        from the manual simulation run on success.
        """
        xsim_dir = Path(proj_dir) / f"{proj_name}.sim" / "sim_1" / "behav" / "xsim"

        # Find the prj file
        prj_files = list(xsim_dir.glob("*.prj"))
        if not prj_files:
            logger.warning("No prj file found in %s — cannot patch", xsim_dir)
            return None

        prj_path = prj_files[0]
        prj_text = prj_path.read_text(encoding="utf-8", errors="replace")

        tb_name = task.tb
        tb_in_prj = any(tb_name in line for line in prj_text.splitlines() if line.strip().startswith('"'))
        file_count = prj_text.count('.sv"') + prj_text.count('.v"')

        if tb_in_prj and file_count >= 10:
            logger.info("prj file looks complete (%d files, tb present) — not patching", file_count)
            return None

        if not tb_in_prj:
            logger.info("Testbench %s missing from prj — patching", tb_name)
        else:
            logger.info("Detected incomplete prj (%d files) — patching with sources_1", file_count)

        # Collect sources_1 file paths from the project directory
        src_imports = Path(proj_dir) / f"{proj_name}.srcs" / "sources_1" / "imports"
        src_ip = Path(proj_dir) / f"{proj_name}.srcs" / "sources_1" / "ip"

        sim_imports = Path(proj_dir) / f"{proj_name}.srcs" / "sim_1" / "imports"

        # Collect files by type
        sv_files: list[str] = []
        v_files: list[str] = []
        vhd_files: list[str] = []   # xil_defaultlib

        for f in sorted(src_imports.rglob("*")):
            if not f.is_file():
                continue
            rel = os.path.relpath(f, xsim_dir).replace("\\", "/")
            if f.suffix in (".sv", ".svh"):
                if f'"{rel}"' not in prj_text and f'"{Path(rel).name}"' not in prj_text:
                    sv_files.append(rel)
            elif f.suffix == ".v":
                if f'"{rel}"' not in prj_text:
                    v_files.append(rel)

        for f in sorted(sim_imports.rglob("*")):
            if not f.is_file():
                continue
            rel = os.path.relpath(f, xsim_dir).replace("\\", "/")
            if f'"{rel}"' in prj_text:
                continue
            fname = f.name
            if any(fname in line for line in prj_text.splitlines() if line.strip().startswith('"')):
                continue
            if f.suffix in (".sv", ".svh"):
                sv_files.append(rel)
            elif f.suffix == ".v":
                v_files.append(rel)

        # IP simulation models
        for f in sorted(src_ip.rglob("*")):
            if not f.is_file():
                continue
            # Skip MIG example_design (not needed for simulation)
            if "user_design" in str(f) or "example_design" in str(f):
                continue
            rel = os.path.relpath(f, xsim_dir).replace("\\", "/")
            if f.suffix == ".vhd":
                vhd_files.append(rel)
            elif f.suffix == ".v":
                if f'"{rel}"' not in prj_text:
                    v_files.append(rel)

        if not (sv_files or v_files or vhd_files):
            logger.warning("No missing files found to patch prj")
            return None

        # Simplest approach: find the last file entry in each language group
        # and append sources_1 files after it.  We keep the original prj
        # structure intact and just add new file lines.
        patched = prj_text

        # Find the end of the sv group (last line starting with " before
        # a non-continuation line or a different language line)
        # We'll insert sv files after the last .sv/.svh file entry in the sv group
        if sv_files:
            sv_insert = "\n".join(f'"{f}" \\' for f in sv_files)
            # Find the last .sv/.svh file line in the prj
            lines = patched.split("\n")
            last_sv_idx = None
            in_sv_group = False
            for i, line in enumerate(lines):
                s = line.strip()
                if s.startswith("sv "):
                    in_sv_group = True
                elif in_sv_group and not s.startswith('"'):
                    # End of sv group
                    break
                if in_sv_group and s.startswith('"') and (".sv\"" in s or ".svh\"" in s):
                    last_sv_idx = i
            if last_sv_idx is not None:
                lines.insert(last_sv_idx + 1, sv_insert)
                patched = "\n".join(lines)

        # Find the end of the verilog group and insert .v files
        if v_files:
            v_insert = "\n".join(f'"{f}" \\' for f in v_files)
            lines = patched.split("\n")
            last_v_idx = None
            in_v_group = False
            for i, line in enumerate(lines):
                s = line.strip()
                if s.startswith("verilog ") and "glbl" not in s:
                    in_v_group = True
                elif in_v_group and not s.startswith('"'):
                    break
                if in_v_group and s.startswith('"') and ".v\"" in s:
                    last_v_idx = i
            if last_v_idx is not None:
                lines.insert(last_v_idx + 1, v_insert)
                patched = "\n".join(lines)

        # Add VHDL lines before "# compile glbl module"
        vhd_block = ""
        if vhd_files:
            vhd_block += "vhdl xil_defaultlib \\\n"
            vhd_block += "\n".join(f'"{f}" \\' for f in vhd_files) + "\n"
        if vhd_block:
            patched = patched.replace("# compile glbl module", f"{vhd_block}\n# compile glbl module")

        prj_path.write_text(patched, encoding="utf-8")
        total = len(sv_files) + len(v_files) + len(vhd_files)
        logger.info("Patched prj with %d sources_1 entries", total)

        # Re-run simulation by calling xvlog/xelab/xsim directly.
        # We cannot use launch_simulation because it regenerates the prj
        # file, overwriting our patch.
        tb = task.tb
        sim_log_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"
        prj_name_base = prj_path.stem
        snapshot = f"{tb}_behav"

        # Build xelab -d arguments from all verilog defines
        all_defines = dict(defines) if defines else {}
        if "SIMULATION" not in all_defines:
            all_defines["SIMULATION"] = "TRUE"
        define_args = " ".join(f"-d {k}={v}" for k, v in all_defines.items())

        tcl_rerun = f"""\
# --- Re-run simulation after prj patch (direct xvlog/xelab/xsim) ---
catch {{ close_sim -force }}
cd {sim_log_dir}
catch {{ exec xvlog --incr --relax -prj {prj_name_base}.prj }} xvlog_result
puts $xvlog_result
catch {{ exec xelab --incr --debug typical --relax -mt 8 {define_args} -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot {snapshot} xil_defaultlib.{tb} xil_defaultlib.glbl }} xelab_result
puts $xelab_result
catch {{ exec xsim {snapshot} -R -log simulate.log }} xsim_result
puts $xsim_result

# --- read sim log ---
set sim_log_file "{sim_log_dir}/simulate.log"
if {{ [file exists $sim_log_file] }} {{
    set fp [open $sim_log_file r]
    set data [read $fp]
    close $fp
    puts $data
}} else {{
    puts "WARNING: sim log not found: $sim_log_file"
}}
"""

        # BUG-55d: Full system simulation with CPU + MIG + DDR3 model needs
        # much longer than 10 minutes to reach MIG calibration (~200µs sim time).
        rerun_result = session.execute(tcl_rerun, timeout=self._limits.sim_rerun_timeout)
        rerun_result = self._append_timeout_hint(rerun_result, "sim")

        combined_output = f"Patched prj with {total} sources_1 entries\n{rerun_result.output}"
        success = "PASS" in combined_output and "FAIL" not in combined_output

        return ExecuteResult(
            output=combined_output,
            success=success,
            timed_out=rerun_result.timed_out,
            duration=rerun_result.duration,
        )

    def bitstream(self, session: Session) -> ExecuteResult:
        """Generate a bitstream in the session.

        Executes synthesis -> implementation -> write_bitstream.

        Parameters
        ----------
        session:
            Session with an open project.

        Returns
        -------
        ExecuteResult
        """
        self._preflight(session, "bitstream")
        self._ensure_vivado(session)

        base = _tcl_path(self.session_mgr.base_dir)
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name

        tcl = "\n".join([
            f"""\
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 20
wait_on_run synth_1
launch_runs impl_1 -jobs 20
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run impl_1
set bit_file "{proj_dir}/{proj_name}.runs/impl_1/system_top.bit"
if {{ [file exists $bit_file] }} {{
    file copy -force $bit_file "{base}/system_top.bit"
    puts "Bitstream generated: {base}/system_top.bit"
}} else {{
    puts "ERROR: Bitstream generation failed"
}}
""",
        ])

        result = session.execute(tcl, timeout=self._limits.bitstream_timeout)
        result = self._append_timeout_hint(result, "bitstream")
        session.update_last_used()
        return result

    def program(self, session: Session) -> ExecuteResult:
        """Program the FPGA with the session's bitstream.

        Parameters
        ----------
        session:
            Session with a generated bitstream.

        Returns
        -------
        ExecuteResult
        """
        self._preflight(session, "program")
        self._ensure_vivado(session)

        base = _tcl_path(self.session_mgr.base_dir)
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        bit_file = f"{base}/system_top.bit"

        tcl = "\n".join([
            f"""\
if {{ [file exists "{bit_file}"] }} {{
    catch {{ open_hw }}
    catch {{ connect_hw_server }}
    catch {{ open_hw_target }}
    set hw_device [lindex [get_hw_devices] 0]
    current_hw_device $hw_device
    refresh_hw_device -update_hw_probes false $hw_device
    set_property PROBES.FILE {{}} $hw_device
    set_property FULL_PROBES.FILE {{}} $hw_device
    set_property PROGRAM.FILE "{bit_file}" $hw_device
    program_hw_devices $hw_device
    refresh_hw_device $hw_device
    close_hw
    puts "FPGA programmed successfully"
}} else {{
    puts "ERROR: Bitstream file not found: {bit_file}"
}}
""",
        ])

        result = session.execute(tcl, timeout=self._limits.program_timeout)
        result = self._append_timeout_hint(result, "program")
        session.update_last_used()
        return result

    def archive(self, session: Session) -> ExecuteResult:
        """Export the session project as a ZIP archive.

        Parameters
        ----------
        session:
            Session with an open project.

        Returns
        -------
        ExecuteResult
        """
        self._preflight(session, "archive")
        self._ensure_vivado(session)

        base = _tcl_path(self.session_mgr.base_dir)
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name

        tcl = "\n".join([
            f"""\
set time_str [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set target_dir "{base}/archive"
file mkdir $target_dir
set archive_path "$target_dir/{proj_name}_$time_str.xpr.zip"
if {{ [catch {{archive_project $archive_path -force -include_local_ip_cache -include_config_settings}} err] }} {{
    if {{ [catch {{archive_project $archive_path -force}} err2] }} {{
        puts "ERROR: Archive failed: $err2"
    }} else {{
        puts "Archive created (basic mode): $archive_path"
    }}
}} else {{
    puts "Archive created: $archive_path"
}}
""",
        ])

        result = session.execute(tcl, timeout=self._limits.archive_timeout)
        result = self._append_timeout_hint(result, "archive")
        session.update_last_used()
        return result
