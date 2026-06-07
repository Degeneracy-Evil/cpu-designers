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
from .config import MemoryConfig
from .exceptions import OperationError, StaleSessionError, VivadoProcessError
from .hash import LayeredHash
from .ip_gen import generate_all_ip_tcl
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

def _tcl_create_project(
    proj_name: str,
    device_part: str,
    proj_dir: str,
    dev_dir: str,
    base_dir: str,
) -> str:
    """Generate TCL for project creation + RTL import + include dirs.

    This mirrors the logic in ``tools/vivado_core/tcl/_create.tcl`` but with
    all paths parameterised.
    """
    alu_rtl_dir = f"{dev_dir}/rtl/ALU"
    mu_rtl_dir = f"{dev_dir}/rtl/MU"
    fpu_rtl_dir = f"{dev_dir}/rtl/FPU"
    cpu_core_dir = f"{dev_dir}/rtl/core"
    ahb_dir = f"{dev_dir}/rtl/AHB-lite"
    ahb_ip_dir = f"{dev_dir}/rtl/AHB-lite/ip"
    apb_dir = f"{dev_dir}/rtl/APB"
    apb_header_dir = f"{dev_dir}/rtl/APB/header"
    apb_perips_dir = f"{dev_dir}/rtl/APB/perips"
    sys_rtl_dir = f"{dev_dir}/rtl"
    tb_dir = f"{dev_dir}/tb"

    return f"""\
# --- create project ---
if {{ [catch {{current_project}} cur_proj] == 0 }} {{
    puts "Closing existing project: $cur_proj"
    close_project
}}
create_project "{proj_name}" "{proj_dir}" -part "{device_part}" -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# --- add RTL sources ---
foreach f [glob -nocomplain -directory "{alu_rtl_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{mu_rtl_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{fpu_rtl_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{cpu_core_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{ahb_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{ahb_dir}" *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{apb_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_dir}" *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -nocomplain -directory "{apb_perips_dir}" *.sv] {{ import_files -norecurse $f }}
foreach f [glob -nocomplain -directory "{apb_header_dir}" *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
if {{ [file exists "{cpu_core_dir}/cache_def.svh"] }} {{
    import_files -norecurse "{cpu_core_dir}/cache_def.svh"
    set_property file_type "Verilog Header" [get_files cache_def.svh]
}}
import_files -norecurse "{sys_rtl_dir}/system_top.sv"
update_compile_order -fileset sources_1

# --- set include dirs ---
set_property include_dirs [list \\
    "{alu_rtl_dir}" \\
    "{mu_rtl_dir}" \\
    "{fpu_rtl_dir}" \\
    "{cpu_core_dir}" \\
    "{ahb_dir}" \\
    "{ahb_ip_dir}" \\
    "{apb_dir}" \\
    "{apb_header_dir}" \\
    "{apb_perips_dir}" \\
    "{tb_dir}" \\
] [current_fileset]
"""


def _tcl_setup_ip(
    proj_name: str,
    proj_dir: str,
    base_dir: str,
    coe_file: str,
    mem_config: MemoryConfig,
) -> str:
    """Generate TCL for IP creation and Sram COE configuration.

    Uses ``create_ip`` from :mod:`ip_gen` to dynamically create BRAM IPs
    based on the memory configuration, replacing the old static XCI import.

    Target generation order: icached/dcached first, then Sram (after COE
    config) to avoid double ``generate_target`` on Sram.
    """
    from .ip_gen import _tcl_generate_target

    ip_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

    # --- Dynamic IP creation from config (create + set_property only) ---
    ip_tcl, ip_names = generate_all_ip_tcl(mem_config, ip_dir, base_dir)

    # Generate targets for non-Sram IPs immediately.
    gen_others = "\n".join(_tcl_generate_target(n) for n in ip_names if n != "Sram")

    # --- Sram COE configuration + generate_target ---
    if coe_file:
        coe_tail = Path(coe_file).name
        sram_block = f"""\
set ip_sram [get_ips -all Sram]
file copy -force {coe_file} "{ip_dir}/Sram/"
set_property -dict [list \\
    CONFIG.Load_Init_File {{true}} \\
    CONFIG.Coe_File "{ip_dir}/Sram/{coe_tail}" \\
] $ip_sram
{_tcl_generate_target("Sram")}
puts "Sram IP configured (COE: {coe_file})\""""
    else:
        sram_block = f"""\
set ip_sram [get_ips -all Sram]
set_property -dict [list \\
    CONFIG.Load_Init_File {{false}} \\
] $ip_sram
{_tcl_generate_target("Sram")}
puts "Sram IP configured (no COE init)\""""

    return f"""\
# --- setup IP (dynamic create_ip from config) ---
update_compile_order -fileset sources_1
{ip_tcl}

# --- Generate targets for all non-Sram IPs (cache BRAMs + DDR3 IPs) ---
{gen_others}

# --- Sram COE configuration + generate target ---
{sram_block}"""


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


def _tcl_add_ddr3_sim_models(base_dir: str, proj_dir: str) -> str:
    """Generate TCL for adding DDR3 simulation model files.

    Adds the MIG simulation model (from the generated IP's ``user_design/rtl/``),
    the external DDR3 model files (``ddr3_model.sv``, ``wiredly.v``) from
    ``Reference/ddr3_sim/``, a ``glbl.v`` stub, and BRAM IP simulation models
    (``blk_mem_gen_v8_4`` behavioral model + per-IP wrappers).

    Parameters
    ----------
    base_dir:
        Project root directory (TCL path format).
    proj_dir:
        Vivado project directory (TCL path format), used for
        generating the ``glbl.v`` stub.
    """
    ddr3_dir = f"{base_dir}/Reference/ddr3_sim"
    glbl_src = f"{base_dir}/dev/tb/glbl.v"
    glbl_stub = f"{proj_dir}/glbl.v"

    # MIG IP simulation model path (generated by create_ip + generate_target)
    mig_ip_dir = f"{proj_dir}/simplecpu_soc.srcs/sources_1/ip/bd_soc_mig_7series_0_1/bd_soc_mig_7series_0_1/bd_soc_mig_7series_0_1/user_design/rtl"

    # BRAM IP names that need simulation models (blk_mem_gen_v8_4)
    bram_ip_names = ["Sram", "icached", "dcached", "icachet", "dcachet", "tlb_flag", "tlb_data"]

    # Build BRAM sim model TCL: add sim/<ip>.v wrapper + simulation/blk_mem_gen_v8_4.v
    # blk_mem_gen_v8_4.v only needs to be added once (all IPs share identical content).
    bram_tcl_lines = []
    bram_tcl_lines.append('# --- BRAM IP simulation models (blk_mem_gen_v8_4) ---')
    bram_tcl_lines.append('puts "Adding BRAM IP simulation models..."')
    bram_tcl_lines.append(f'set bram_ip_dir "{proj_dir}/simplecpu_soc.srcs/sources_1/ip"')
    bram_tcl_lines.append('set bram_sim_model_added 0')
    for ip_name in bram_ip_names:
        ip_path = f"$bram_ip_dir/{ip_name}/{ip_name}"
        # Add the IP wrapper (sim/<ip>.v) — unique per IP
        bram_tcl_lines.append(
            f'if {{ [file exists [file join "{ip_path}" sim {ip_name}.v]] }} {{\n'
            f'    add_files -fileset sim_1 -norecurse [file join "{ip_path}" sim {ip_name}.v]\n'
            f'}}'
        )
        # Add the simulation model (simulation/blk_mem_gen_v8_4.v) — only once
        bram_tcl_lines.append(
            f'if {{ $bram_sim_model_added == 0 && [file exists [file join "{ip_path}" simulation blk_mem_gen_v8_4.v]] }} {{\n'
            f'    add_files -fileset sim_1 -norecurse [file join "{ip_path}" simulation blk_mem_gen_v8_4.v]\n'
            f'    set bram_sim_model_added 1\n'
            f'}}'
        )
    bram_tcl = "\n".join(bram_tcl_lines)

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
# example project (bd_soc_mig_7series_0_1_ex) which completes
# calibration at ~107ns.
#
# Both files define the same module name (bd_soc_mig_7series_0_1_mig),
# so only ONE must be in sim_1. We explicitly remove _mig.v if it
# was auto-added from sources_1 (by create_ip), then add _mig_sim.v.
puts "Adding MIG simulation model (using _mig_sim.v)..."
if {{ [file exists "{mig_ip_dir}"] }} {{
    # Remove _mig.v from sim_1 if present (hardware model, not for sim)
    set mig_v [get_files -of_objects [get_filesets sim_1] -quiet "*/bd_soc_mig_7series_0_1_mig.v"]
    if {{ [llength $mig_v] > 0 }} {{
        remove_files -fileset sim_1 -norecurse $mig_v
        puts "  Removed _mig.v (hardware model) from sim_1"
    }}
    add_files -fileset sim_1 -norecurse [file join "{mig_ip_dir}" bd_soc_mig_7series_0_1.v]
    add_files -fileset sim_1 -norecurse [file join "{mig_ip_dir}" bd_soc_mig_7series_0_1_mig_sim.v]
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
import_files -fileset sim_1 -norecurse "{ddr3_dir}/wiredly.v"

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


def _tcl_handle_bridge_vhdl() -> str:
    """Generate TCL for Bridge VHDL library workaround.

    When using ``create_ip`` to create the AHB-AXI Bridge, Vivado
    automatically manages VHDL library mapping.  However, if bridge
    VHDL files were manually imported (e.g. from a pre-built project),
    ``set_property library`` can corrupt the fileset in Vivado 2018.3.

    This workaround removes any manually-imported bridge VHDL files
    from the project to prevent conflicts with the ``create_ip``
    generated files.
    """
    return """\
# --- Bridge VHDL library workaround ---
set bridge_files [get_files -of_objects [get_filesets sources_1] -quiet "*ahblite_axi_bridge*"]
if {[llength $bridge_files] > 0} {
    remove_files $bridge_files
    puts "Removed [llength $bridge_files] bridge VHDL files from project"
}
"""


def _tcl_copy_hex_file(hex_src: str, proj_dir: str) -> str:
    """Generate TCL for copying a HEX file for ``$readmemh`` access.

    Parameters
    ----------
    hex_src:
        Absolute path to the HEX file (TCL path format).
    proj_dir:
        Vivado project directory (TCL path format).
    """
    hex_dst = f"{proj_dir}/prog.hex"
    return f"""\
# --- copy hex file for $readmemh ---
if {{ [file exists "{hex_src}"] }} {{
    file copy -force "{hex_src}" "{hex_dst}"
    puts "Copied {hex_src} -> {hex_dst}"
}} else {{
    puts "WARNING: HEX file not found: {hex_src}"
}}
"""


def _tcl_add_tb(
    dev_dir: str,
    proj_dir: str,
    proj_name: str,
    tb_name: str,
    coe_file: str,
) -> str:
    """Generate TCL for adding testbench and updating COE.

    Mirrors ``tools/vivado_core/tcl/_add_tb.tcl``.
    """
    tb_dir = f"{dev_dir}/tb"
    ip_xci_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

    coe_update = ""
    if coe_file:
        coe_tail = Path(coe_file).name
        coe_update = f"""\
if {{ [catch {{get_ips Sram}} ip_sram] == 0 && $ip_sram ne "" }} {{
    file copy -force {coe_file} "{ip_xci_dir}/Sram/"
    set_property -dict [list \\
        CONFIG.Load_Init_File {{true}} \\
        CONFIG.Coe_File "{ip_xci_dir}/Sram/{coe_tail}" \\
    ] $ip_sram
    puts "COE updated: {coe_file}"
    generate_target all $ip_sram
}}"""
    else:
        coe_update = """\
if { [catch {get_ips Sram} ip_sram] == 0 && $ip_sram ne "" } {
    set_property -dict [list CONFIG.Load_Init_File {false}] $ip_sram
    puts "COE updated: no COE init"
    generate_target all $ip_sram
}"""

    return f"""\
# --- add testbench ---
set existing_sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if {{ [llength $existing_sim_files] > 0 }} {{
    remove_files -fileset sim_1 -quiet $existing_sim_files
}}
import_files -fileset sim_1 "{tb_dir}/{tb_name}.sv"
if {{ [file exists "{tb_dir}/lcd_module_stub.sv"] }} {{
    import_files -fileset sim_1 "{tb_dir}/lcd_module_stub.sv"
}}
set_property top {tb_name} [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
# Propagate include_dirs from sources_1 to sim_1 so Vivado can
# resolve `include directives during update_compile_order.
set src_includes [get_property include_dirs [get_filesets sources_1]]
set_property include_dirs $src_includes [get_filesets sim_1]
update_compile_order -fileset sim_1

# --- update COE ---
{coe_update}
"""


def _tcl_run_sim(
    tb_name: str,
    runtime: str,
    proj_dir: str,
    proj_name: str,
) -> str:
    """Generate TCL for launching simulation and reading the log.

    Mirrors ``tools/vivado_core/tcl/_run_sim.tcl``.
    """
    sim_log_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"
    return f"""\
# --- run simulation ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

if {{ [catch {{current_sim_state}} sim_state] == 0 }} {{
    if {{ $sim_state ne "none" }} {{
        close_sim -force
    }}
}}
set_property xsim.simulate.runtime {runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]
launch_simulation -mode behavioral

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

    def _resolve_coe_path(self, task: TaskConfig) -> str:
        """Return the absolute COE path for a task, or empty string.

        The path is returned in forward-slash form for TCL safety.
        """
        if not task.coe:
            return ""
        return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.coe)

    def _resolve_hex_path(self, task: TaskConfig) -> str:
        """Return the absolute HEX path for a task, or empty string.

        The path is returned in forward-slash form for TCL safety.
        """
        if not task.hex_file:
            return ""
        return _tcl_path(self.session_mgr.base_dir / "dev" / "program_source" / task.hex_file)

    def _update_hashes(self, session: Session) -> None:
        """Recompute and persist the current source hashes."""
        session.meta.hashes = self.layered_hash.compute_current()
        session.save_meta()

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

        Parameters
        ----------
        session:
            Target session (must not already have a project).
        task:
            Task configuration (used for COE path).

        Returns
        -------
        ExecuteResult
        """
        self._ensure_vivado(session)

        # Regenerate cache_def.svh from current config before creating project.
        self._regenerate_cache_header()

        base = _tcl_path(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        device_part = self.session_mgr.config.device_part
        mem_config = self.session_mgr.config.memory
        coe_file = self._resolve_coe_path(task)

        tcl_parts = [
            _tcl_create_project(proj_name, device_part, proj_dir, dev, base),
            _tcl_setup_ip(proj_name, proj_dir, base, coe_file, mem_config),
            _tcl_add_constrs(base),
        ]

        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=300.0)
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
        coe_file = self._resolve_coe_path(task)

        if plan.full:
            # Full rebuild: close -> cd up -> delete -> create.
            mem_config = self.session_mgr.config.memory
            tcl_parts: list[str] = [
                f"catch {{ close_project }}\ncd [file dirname {proj_dir}]",
                f"file delete -force {proj_dir}",
                _tcl_create_project(proj_name, device_part, proj_dir, dev, base),
                _tcl_setup_ip(proj_name, proj_dir, base, coe_file, mem_config),
                _tcl_add_constrs(base),
                _tcl_add_tb(dev, proj_dir, proj_name, task.tb, coe_file) if task.tb else "",
            ]
        else:
            # Incremental: execute only the needed steps.
            # session.execute() auto-opens the project before each command.
            tcl_parts: list[str] = []
            tb_dir = f"{dev}/tb"
            ip_xci_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

            for step in plan.tcl_steps:
                if step == "remove_files_sim_1":
                    tcl_parts.append(
                        "set existing [get_files -of_objects [get_filesets sim_1] -quiet]; "
                        "if { [llength $existing] > 0 } { remove_files -fileset sim_1 -quiet $existing }"
                    )
                elif step == "add_tb":
                    if task.tb:
                        tcl_parts.append(
                            f'add_files -fileset sim_1 "{tb_dir}/{task.tb}.sv"'
                        )
                elif step == "set_property_top":
                    if task.tb:
                        tcl_parts.append(
                            f"set_property top {task.tb} [get_filesets sim_1]"
                        )
                elif step == "update_compile_order":
                    tcl_parts.append("update_compile_order -fileset sim_1")
                elif step == "update_coe":
                    if coe_file:
                        coe_tail = Path(coe_file).name
                        tcl_parts.append(
                            f'file copy -force {coe_file} "{ip_xci_dir}/Sram/"; '
                            f'set ip_sram [get_ips -all Sram]; '
                            f'set_property -dict [list CONFIG.Load_Init_File {{true}} '
                            f'CONFIG.Coe_File "{ip_xci_dir}/Sram/{coe_tail}"] $ip_sram; '
                            f"generate_target all $ip_sram"
                        )
                    else:
                        tcl_parts.append(
                            "set ip_sram [get_ips -all Sram]; "
                            "set_property -dict [list CONFIG.Load_Init_File {false}] $ip_sram; "
                            "generate_target all $ip_sram"
                        )
                elif step == "set_property_coe":
                    if coe_file:
                        coe_tail = Path(coe_file).name
                        tcl_parts.append(
                            f'set ip_sram [get_ips -all Sram]; '
                            f'file copy -force {coe_file} "{ip_xci_dir}/Sram/"; '
                            f'set_property -dict [list CONFIG.Load_Init_File {{true}} '
                            f'CONFIG.Coe_File "{ip_xci_dir}/Sram/{coe_tail}"] $ip_sram'
                        )
                    else:
                        tcl_parts.append(
                            "set ip_sram [get_ips -all Sram]; "
                            "set_property -dict [list CONFIG.Load_Init_File {false}] $ip_sram"
                        )
                elif step == "generate_target":
                    tcl_parts.append(
                        "set ip_sram [get_ips -all Sram]; "
                        "generate_target all $ip_sram"
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
            tcl_parts.append(_tcl_add_ddr3_sim_models(base, proj_dir))

        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=300.0)
        self._update_hashes(session)
        session.update_last_used()
        return result

    def sim(
        self,
        session: Session,
        task: TaskConfig,
        runtime: str | None = None,
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

        Returns
        -------
        ExecuteResult
        """
        self._preflight(session, "sim")
        self._ensure_vivado(session)

        sim_runtime = runtime or task.runtime or "100000ns"
        base = _tcl_path(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = _tcl_path(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        coe_file = self._resolve_coe_path(task)

        tcl_parts = [
            _tcl_add_tb(dev, proj_dir, proj_name, task.tb, coe_file),
        ]

        # DDR3 simulation mode: add simulation models to sim_1
        # (after testbench, because _tcl_add_tb clears sim_1 first)
        if task.sim_mode == "ddr3":
            tcl_parts.append(_tcl_add_ddr3_sim_models(base, proj_dir))

        # Verilog defines (e.g. SIM_BYPASS_INIT_CAL=FAST for DDR3)
        if task.verilog_defines:
            tcl_parts.append(_tcl_set_verilog_defines(task.verilog_defines))

        # HEX file copy for $readmemh
        if task.hex_file:
            hex_path = self._resolve_hex_path(task)
            tcl_parts.append(_tcl_copy_hex_file(hex_path, proj_dir))

        tcl_parts.append(_tcl_run_sim(task.tb, sim_runtime, proj_dir, proj_name))
        tcl = "\n".join(tcl_parts)

        result = session.execute(tcl, timeout=600.0)

        # --- DDR3 prj patching ---
        # Vivado 2018.3's dependency resolver fails at SV→VHDL boundaries
        # (Bridge IP), producing an incomplete prj that omits sources_1
        # files.  When this happens, launch_simulation fails at elaborate
        # with "Module <ddr3_bridge_wrapper> not found".  We detect this,
        # patch the prj file to include sources_1 files, and re-run
        # xvlog/xelab/xsim manually.
        if task.sim_mode == "ddr3" and not result.success:
            patched = self._patch_prj_and_rerun(
                session, task, sim_runtime, proj_dir, proj_name
            )
            if patched is not None:
                return patched

        session.update_last_used()
        return result

    def _patch_prj_and_rerun(
        self,
        session: Session,
        task: TaskConfig,
        runtime: str,
        proj_dir: str,
        proj_name: str,
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

        # Check if prj is already complete (has many file references)
        file_count = prj_text.count('.sv"') + prj_text.count('.v"')
        if file_count >= 10:
            logger.info("prj file looks complete (%d files) — not patching", file_count)
            return None

        logger.info("Detected incomplete prj (%d files) — patching with sources_1", file_count)

        # Collect sources_1 file paths from the project directory
        src_imports = Path(proj_dir) / f"{proj_name}.srcs" / "sources_1" / "imports"
        src_ip = Path(proj_dir) / f"{proj_name}.srcs" / "sources_1" / "ip"

        # Collect files by type
        sv_files: list[str] = []
        v_files: list[str] = []
        vhd_files: list[str] = []   # xil_defaultlib
        bridge_vhd: list[str] = []  # ahblite_axi_bridge_0_vhd

        for f in sorted(src_imports.rglob("*")):
            if not f.is_file():
                continue
            rel = os.path.relpath(f, xsim_dir).replace("\\", "/")
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
                if "ahblite_axi_bridge" in str(f):
                    bridge_vhd.append(rel)
                else:
                    vhd_files.append(rel)
            elif f.suffix == ".v":
                v_files.append(rel)

        if not (sv_files or v_files or vhd_files or bridge_vhd):
            logger.warning("No sources_1 files found — cannot patch prj")
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
        if bridge_vhd:
            vhd_block += "vhdl ahblite_axi_bridge_0_vhd \\\n"
            vhd_block += "\n".join(f'"{f}" \\' for f in bridge_vhd) + "\n"
        if vhd_block:
            patched = patched.replace("# compile glbl module", f"{vhd_block}\n# compile glbl module")

        prj_path.write_text(patched, encoding="utf-8")
        total = len(sv_files) + len(v_files) + len(vhd_files) + len(bridge_vhd)
        logger.info("Patched prj with %d sources_1 entries", total)

        # Re-run simulation via TCL (in-process, no external subprocess).
        # After patching the prj, close the failed simulation and re-launch.
        # Use -mt off to avoid XSIM 43-3356 (Vivado 2018.3 Windows file-locking race).
        tb = task.tb
        sim_log_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"

        tcl_rerun = f"""\
# --- Re-run simulation after prj patch ---
catch {{ close_sim -force }}
set_property xsim.elaborate.xsim.more_options {{-mt off -debug off}} [get_filesets sim_1]
set_property xsim.simulate.runtime {runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]
launch_simulation -mode behavioral

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
        rerun_result = session.execute(tcl_rerun, timeout=3600.0)

        combined_output = f"Patched prj with {total} sources_1 entries\n{rerun_result.output}"
        success = "ALL TESTS PASSED" in combined_output or "PASS" in combined_output

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

        result = session.execute(tcl, timeout=3600.0)
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

        result = session.execute(tcl, timeout=120.0)
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

        result = session.execute(tcl, timeout=300.0)
        session.update_last_used()
        return result
