from __future__ import annotations

from pathlib import Path

from .config import Hardware, ROOT, Simulation
from .ip import create_ip_tcl


def _q(path: Path) -> str:
    return "{" + path.resolve().as_posix() + "}"


def _list(paths: list[Path]) -> str:
    return "[list " + " ".join(_q(path) for path in paths) + "]"


def project(hardware: Hardware) -> str:
    sources = sorted(path for path in (ROOT / "src").rglob("*") if path.suffix in {".sv", ".svh"})
    headers = [path for path in sources if path.suffix == ".svh"]
    ip_dir = hardware.project_dir / f"{hardware.project}.srcs" / "sources_1" / "ip"
    header_commands = "\n".join(
        f"set_property file_type {{Verilog Header}} [get_files {_q(path)}]" for path in headers
    )
    return f"""
create_project {hardware.project} {_q(hardware.project_dir)} -part {hardware.part} -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -scan_for_includes {_list(sources)}
{header_commands}
set_property include_dirs [list {_q(ROOT / 'src')}] [get_filesets sources_1]
set_property top system_top [get_filesets sources_1]
add_files -fileset constrs_1 {_q(ROOT / 'fpga' / 'constraints.xdc')}
{create_ip_tcl(hardware, ip_dir)}
update_compile_order -fileset sources_1
close_project
"""


def _defines(task: Simulation) -> str:
    values = {"SIMULATION": "TRUE", **task.defines}
    joined = " ".join(f"{name}={value}" for name, value in values.items())
    return f"set_property verilog_define {{{joined}}} [get_filesets sim_1]"


def _copy_images(hardware: Hardware, task: Simulation) -> str:
    run_dir = hardware.project_dir / f"{hardware.project}.sim" / "sim_1" / "behav" / "xsim"
    commands = [f"file mkdir {_q(run_dir)}"]
    if task.program_hex:
        commands.append(f"file copy -force {_q(task.program_hex)} {_q(run_dir / 'prog.hex')}")
    if task.boot_hex:
        commands.append(f"file copy -force {_q(task.boot_hex)} {_q(run_dir / 'bootloader.hex')}")
    return "\n".join(commands)


def _ddr_models(task: Simulation) -> str:
    if not task.ddr3:
        return ""
    directory = ROOT / "docs" / "Reference" / "ddr3_sim"
    files = [directory / "ddr3_model.sv", directory / "ddr3_model_parameters.vh", directory / "wiredly.v"]
    return f"add_files -fileset sim_1 {_list(files)}"


def _simulation_body(hardware: Hardware, task: Simulation, runtime: str | None = None) -> str:
    if task.bench is None:
        raise ValueError(f"{task.name} is not a simulation task")
    actual_runtime = runtime or task.runtime
    return f"""
catch {{close_sim -force}}
set old_sim_files [get_files -quiet -of_objects [get_filesets sim_1]]
if {{[llength $old_sim_files] > 0}} {{remove_files -quiet -fileset sim_1 $old_sim_files}}
add_files -fileset sim_1 {_q(task.bench)}
{_ddr_models(task)}
set_property include_dirs [list {_q(ROOT / 'src')} {_q(ROOT / 'test' / 'bench')}] [get_filesets sim_1]
{_defines(task)}
set_property top {task.bench.stem} [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property xsim.simulate.runtime {actual_runtime} [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
{_copy_images(hardware, task)}
update_compile_order -fileset sim_1
launch_simulation -mode behavioral
close_sim -force
"""


def simulate(hardware: Hardware, task: Simulation, runtime: str | None = None) -> str:
    return f"open_project {_q(hardware.xpr)}\n{_simulation_body(hardware, task, runtime)}\nclose_project\n"


def regress(hardware: Hardware, tasks: list[Simulation]) -> str:
    blocks = [f"open_project {_q(hardware.xpr)}", "set failures {}"]
    for task in tasks:
        body = _simulation_body(hardware, task)
        blocks.append(f"""
puts "=== REGRESSION {task.name} ==="
if {{[catch {{
{body}
}} message]}} {{
    puts "ERROR {task.name}: $message"
    lappend failures {task.name}
}}
""")
    blocks.append("close_project\nif {[llength $failures] > 0} {error \"Regression failed: $failures\"}")
    return "\n".join(blocks)


def bitstream(hardware: Hardware, task: Simulation, output: Path) -> str:
    if not task.top:
        raise ValueError(f"{task.name} is not an FPGA task")
    defines = " ".join(f"{name}={value}" for name, value in task.defines.items())
    coe = ""
    if task.boot_coe:
        coe = f"""
set_property -dict [list CONFIG.Load_Init_File {{true}} CONFIG.Coe_File {_q(task.boot_coe)}] [get_ips ROM]
generate_target all [get_ips ROM]
"""
    generated_bit = hardware.project_dir / f"{hardware.project}.runs" / "impl_1" / f"{task.top}.bit"
    return f"""
open_project {_q(hardware.xpr)}
set_property top {task.top} [get_filesets sources_1]
set_property verilog_define {{{defines}}} [get_filesets sources_1]
{coe}
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
file mkdir {_q(output.parent)}
file copy -force {_q(generated_bit)} {_q(output)}
close_project
"""


def program(hardware: Hardware, bitstream_file: Path) -> str:
    return f"""
open_hw_manager
connect_hw_server
open_hw_target
set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE {_q(bitstream_file)} $device
program_hw_devices $device
close_hw_manager
"""
