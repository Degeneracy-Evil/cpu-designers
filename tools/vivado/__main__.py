from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from .config import ROOT, Hardware, Simulation, load_hardware, load_simulations
from . import tcl


def _write_script(hardware: Hardware, name: str, content: str) -> Path:
    directory = hardware.build_dir / "generated"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}.tcl"
    path.write_text(content.strip() + "\n", encoding="utf-8")
    return path


def _run(hardware: Hardware, name: str, content: str, timeout_name: str) -> int:
    script = _write_script(hardware, name, content)
    log_dir = hardware.build_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    command = [
        hardware.vivado,
        "-mode", "batch",
        "-source", str(script),
        "-journal", str(log_dir / f"{name}.jou"),
        "-log", str(log_dir / f"{name}.log"),
    ]
    try:
        return subprocess.run(
            command,
            cwd=ROOT,
            timeout=hardware.timeouts.get(timeout_name),
            check=False,
        ).returncode
    except FileNotFoundError:
        print(f"Vivado executable not found: {hardware.vivado}", file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print(f"Vivado command timed out: {name}", file=sys.stderr)
        return 1


def _task(tasks: dict[str, Simulation], name: str) -> Simulation:
    try:
        return tasks[name]
    except KeyError:
        raise SystemExit(f"Unknown task: {name}") from None


def _require_project(hardware: Hardware) -> None:
    if not hardware.xpr.is_file():
        raise SystemExit("Vivado project does not exist; run 'python -m tools.vivado project'")


def _require_images(task: Simulation) -> None:
    for path in (task.boot_hex, task.program_hex, task.boot_coe):
        if path is not None and not path.is_file():
            raise SystemExit(f"Required image does not exist: {path}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Simple Vivado command wrapper")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("project", help="recreate the Vivado project")
    sim = commands.add_parser("sim", help="run one simulation task")
    sim.add_argument("task")
    sim.add_argument("--runtime")
    regression = commands.add_parser("regress", help="run one task group sequentially")
    regression.add_argument("group")
    bitstream = commands.add_parser("bitstream", help="build an FPGA bitstream")
    bitstream.add_argument("--task", default="fpga")
    bitstream.add_argument("--output", type=Path)
    program = commands.add_parser("program", help="program the first attached FPGA")
    program.add_argument("--bitstream", type=Path)
    commands.add_parser("clean", help="remove the generated Vivado project")
    commands.add_parser("list", help="list tasks and groups")
    return root


def main() -> int:
    args = parser().parse_args()
    hardware = load_hardware()
    tasks, groups = load_simulations()

    if args.command == "list":
        for name in tasks:
            print(name)
        for name in groups:
            print(f"group:{name}")
        return 0

    if args.command == "clean":
        if hardware.build_dir.is_dir():
            shutil.rmtree(hardware.build_dir)
        print(f"Removed {hardware.build_dir}")
        return 0

    if args.command == "project":
        if hardware.project_dir.is_dir():
            shutil.rmtree(hardware.project_dir)
        return _run(hardware, "project", tcl.project(hardware), "project")

    _require_project(hardware)

    if args.command == "sim":
        task = _task(tasks, args.task)
        _require_images(task)
        return _run(hardware, f"sim_{task.name}", tcl.simulate(hardware, task, args.runtime), "simulation")

    if args.command == "regress":
        if args.group not in groups:
            raise SystemExit(f"Unknown group: {args.group}")
        selected = [_task(tasks, name) for name in groups[args.group]]
        for task in selected:
            _require_images(task)
        return _run(hardware, f"regress_{args.group}", tcl.regress(hardware, selected), "simulation")

    if args.command == "bitstream":
        task = _task(tasks, args.task)
        _require_images(task)
        output = args.output or hardware.build_dir / f"{hardware.project}.bit"
        return _run(hardware, "bitstream", tcl.bitstream(hardware, task, output), "bitstream")

    if args.command == "program":
        bitstream_file = args.bitstream or hardware.build_dir / f"{hardware.project}.bit"
        if not bitstream_file.is_file():
            raise SystemExit(f"Bitstream does not exist: {bitstream_file}")
        return _run(hardware, "program", tcl.program(hardware, bitstream_file), "program")

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
