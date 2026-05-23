"""High-level Vivado operations: create, refresh, sim, bitstream, program, archive.

Each method performs a preflight check, ensures the Vivado process is
running, executes the appropriate TCL commands, and updates session
metadata.
"""
from __future__ import annotations

import logging
from pathlib import Path

from .exceptions import OperationError, StaleSessionError, VivadoProcessError
from .hash import LayeredHash
from .session import ExecuteResult, Session, SessionManager
from .sync import SyncPolicy
from .tasks import TaskConfig, TaskRegistry

logger = logging.getLogger(__name__)


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

    This mirrors the logic in ``tools/tcl/create_proj.tcl`` but with
    all paths parameterised.
    """
    alu_rtl_dir = f"{dev_dir}/rtl/ALU"
    mu_rtl_dir = f"{dev_dir}/rtl/MU"
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
create_project {proj_name} {proj_dir} -part {device_part} -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# --- add RTL sources ---
foreach f [glob -directory {alu_rtl_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {mu_rtl_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {cpu_core_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {ahb_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {ahb_dir} *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -directory {apb_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {apb_dir} *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
foreach f [glob -directory {apb_perips_dir} *.sv] {{ import_files -norecurse $f }}
foreach f [glob -directory {apb_header_dir} *.svh] {{
    import_files -norecurse $f
    set_property file_type "Verilog Header" [get_files [file tail $f]]
}}
import_files -norecurse "{sys_rtl_dir}/system_top.sv"
update_compile_order -fileset sources_1

# --- set include dirs ---
set_property include_dirs [list \\
    {alu_rtl_dir} \\
    {mu_rtl_dir} \\
    {cpu_core_dir} \\
    {ahb_dir} \\
    {ahb_ip_dir} \\
    {apb_dir} \\
    {apb_header_dir} \\
    {apb_perips_dir} \\
    {tb_dir} \\
] [current_fileset]
"""


def _tcl_setup_ip(
    proj_name: str,
    proj_dir: str,
    base_dir: str,
    coe_file: str,
) -> str:
    """Generate TCL for IP import and Sram COE configuration.

    Mirrors ``tools/tcl/setup_ip.tcl``.
    """
    ips_dir = f"{base_dir}/Reference/newips"
    ip_xci_dir = f"{proj_dir}/{proj_name}.srcs/sources_1/ip"

    coe_block = ""
    if coe_file:
        coe_tail = Path(coe_file).name
        coe_block = f"""\
file copy -force {coe_file} "{ip_xci_dir}/Sram/"
set_property -dict [list \\
    CONFIG.Load_Init_File {{true}} \\
    CONFIG.Coe_File "{ip_xci_dir}/Sram/{coe_tail}" \\
] $ip_sram
puts "Sram IP configured (COE: {coe_file})\""""
    else:
        coe_block = """\
set_property -dict [list \\
    CONFIG.Load_Init_File {false} \\
] $ip_sram
puts "Sram IP configured (no COE init)\""""

    return f"""\
# --- setup IP ---
set ip_xci_dir "{ip_xci_dir}"
import_files -norecurse "{ips_dir}/icached.xci"
import_files -norecurse "{ips_dir}/dcached.xci"
import_files -norecurse "{ips_dir}/Sram.xci"
update_compile_order -fileset sources_1

set ip_icached [get_ips -all icached]
set ip_dcached [get_ips -all dcached]
set ip_sram    [get_ips -all Sram]

if {{ $ip_icached eq "" }} {{
    update_compile_order -fileset sources_1
    set ip_icached [get_ips -all icached]
    set ip_dcached [get_ips -all dcached]
    set ip_sram    [get_ips -all Sram]
}}

set_property -dict [list CONFIG.Load_Init_File {{false}}] $ip_icached
set_property -dict [list CONFIG.Load_Init_File {{false}}] $ip_dcached

{coe_block}

generate_target all $ip_icached
generate_target all $ip_dcached
generate_target all $ip_sram
catch {{ config_ip_cache -export $ip_icached }}
catch {{ config_ip_cache -export $ip_dcached }}
catch {{ config_ip_cache -export $ip_sram }}
export_ip_user_files -of_objects $ip_icached -no_script -sync -force -quiet
export_ip_user_files -of_objects $ip_dcached -no_script -sync -force -quiet
export_ip_user_files -of_objects $ip_sram    -no_script -sync -force -quiet
"""


def _tcl_add_constrs(base_dir: str) -> str:
    """Generate TCL for adding DCP and constraint files.

    Mirrors ``tools/tcl/add_constrs.tcl``.
    """
    fpga_dir = f"{base_dir}/dev/fpga"
    return f"""\
# --- add constraints ---
import_files -norecurse "{fpga_dir}/lcd_module.dcp"
import_files -norecurse -fileset constrs_1 "{fpga_dir}/cpu.xdc"
"""


def _tcl_add_tb(
    dev_dir: str,
    proj_dir: str,
    proj_name: str,
    tb_name: str,
    coe_file: str,
) -> str:
    """Generate TCL for adding testbench and updating COE.

    Mirrors ``tools/tcl/add_tb.tcl``.
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
add_files -fileset sim_1 "{tb_dir}/{tb_name}.sv"
if {{ [file exists "{tb_dir}/lcd_module_stub.sv"] }} {{
    add_files -fileset sim_1 "{tb_dir}/lcd_module_stub.sv"
}}
set_property top {tb_name} [get_filesets sim_1]
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

    Mirrors ``tools/tcl/run_sim.tcl``.
    """
    sim_log_dir = f"{proj_dir}/{proj_name}.sim/sim_1/behav/xsim"
    return f"""\
# --- run simulation ---
if {{ [catch {{current_sim_state}} sim_state] == 0 }} {{
    if {{ $sim_state ne "none" }} {{
        close_sim -force
    }}
}}
set_property xsim.simulate.runtime {runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_objects true [get_filesets sim_1]
launch_simulation -mode behavioral

# --- read sim log ---
set sim_log_file "{sim_log_dir}/xsim.log"
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
        """Return the absolute COE path for a task, or empty string."""
        if not task.coe:
            return ""
        return str(self.session_mgr.base_dir / "dev" / "program_source" / task.coe)

    def _update_hashes(self, session: Session) -> None:
        """Recompute and persist the current source hashes."""
        session.meta.hashes = self.layered_hash.compute_current()
        session.save_meta()

    # ------------------------------------------------------------------
    # Public operations
    # ------------------------------------------------------------------

    def create(self, session: Session, task: TaskConfig) -> ExecuteResult:
        """Create a Vivado project inside the session directory.

        Executes the equivalent of ``create_proj.tcl`` +
        ``setup_ip.tcl`` + ``add_constrs.tcl`` as a single
        parameterised TCL script.

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
        self._preflight(session, "create")
        self._ensure_vivado(session)

        base = str(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = str(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        device_part = self.session_mgr.config.device_part
        coe_file = self._resolve_coe_path(task)

        tcl = "\n".join([
            _tcl_create_project(proj_name, device_part, proj_dir, dev, base),
            _tcl_setup_ip(proj_name, proj_dir, base, coe_file),
            _tcl_add_constrs(base),
        ])

        result = session.execute(tcl, timeout=300.0)
        self._update_hashes(session)
        session.update_last_used()
        return result

    def refresh(
        self,
        session: Session,
        layers: list[str] | None = None,
    ) -> ExecuteResult:
        """Refresh a session to bring it in sync with source changes.

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
        self._preflight(session, "refresh")
        self._ensure_vivado(session)

        staleness = self.layered_hash.compute_staleness(session.meta.hashes)
        task = self.task_registry.get(session.meta.task)
        plan = self.sync.plan_refresh(staleness, task)

        if not plan.layers:
            # Nothing to refresh.
            return ExecuteResult(output="No stale layers", success=True, timed_out=False, duration=0.0)

        base = str(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = str(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        device_part = self.session_mgr.config.device_part
        coe_file = self._resolve_coe_path(task)

        if plan.full:
            # Full rebuild: close → delete → create.
            tcl_close = "catch { close_project }\n"
            tcl_delete = f"file delete -force {proj_dir}\n"
            tcl_rebuild = "\n".join([
                _tcl_create_project(proj_name, device_part, proj_dir, dev, base),
                _tcl_setup_ip(proj_name, proj_dir, base, coe_file),
                _tcl_add_constrs(base),
            ])
            tcl = tcl_close + tcl_delete + tcl_rebuild
        else:
            # Incremental: execute only the needed steps.
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
        base = str(self.session_mgr.base_dir)
        dev = f"{base}/dev"
        proj_dir = str(session.project_dir)
        proj_name = self.session_mgr.config.proj_name
        coe_file = self._resolve_coe_path(task)

        tcl = "\n".join([
            _tcl_add_tb(dev, proj_dir, proj_name, task.tb, coe_file),
            _tcl_run_sim(task.tb, sim_runtime, proj_dir, proj_name),
        ])

        result = session.execute(tcl, timeout=600.0)
        session.update_last_used()
        return result

    def bitstream(self, session: Session) -> ExecuteResult:
        """Generate a bitstream in the session.

        Executes synthesis → implementation → write_bitstream.

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

        base = str(self.session_mgr.base_dir)
        proj_dir = str(session.project_dir)
        proj_name = self.session_mgr.config.proj_name

        tcl = f"""\
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 14
wait_on_run synth_1
launch_runs impl_1 -jobs 14
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 14
wait_on_run impl_1
set bit_file "{proj_dir}/{proj_name}.runs/impl_1/system_top.bit"
if {{ [file exists $bit_file] }} {{
    file copy -force $bit_file "{base}/system_top.bit"
    puts "Bitstream generated: {base}/system_top.bit"
}} else {{
    puts "ERROR: Bitstream generation failed"
}}
"""

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

        base = str(self.session_mgr.base_dir)
        bit_file = f"{base}/system_top.bit"

        tcl = f"""\
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
"""

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

        base = str(self.session_mgr.base_dir)
        proj_name = self.session_mgr.config.proj_name

        tcl = f"""\
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
"""

        result = session.execute(tcl, timeout=300.0)
        session.update_last_used()
        return result
