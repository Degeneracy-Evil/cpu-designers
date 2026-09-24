from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Hardware:
    vivado: str
    project: str
    part: str
    timeouts: dict[str, int]
    ddr3: dict[str, Any]
    clock: dict[str, Any]

    @property
    def build_dir(self) -> Path:
        return ROOT / "build" / "vivado"

    @property
    def project_dir(self) -> Path:
        return self.build_dir / "project"

    @property
    def xpr(self) -> Path:
        return self.project_dir / f"{self.project}.xpr"


@dataclass(frozen=True)
class Simulation:
    name: str
    top: str = ""
    bench: Path | None = None
    runtime: str = "1ms"
    boot_hex: Path | None = None
    program_hex: Path | None = None
    boot_coe: Path | None = None
    ddr3: bool = False
    defines: dict[str, str] = field(default_factory=dict)


def _read_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(path)
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def load_hardware() -> Hardware:
    raw = _read_yaml(ROOT / "config" / "vivado.yaml")
    return Hardware(
        vivado=str(raw.get("vivado", "vivado")),
        project=str(raw.get("project", "simplecpu_soc")),
        part=str(raw.get("part", "xc7a200tfbg676-2")),
        timeouts={key: int(value) for key, value in raw.get("timeouts", {}).items()},
        ddr3=dict(raw.get("ddr3", {})),
        clock=dict(raw.get("clock", {})),
    )


def _artifact(value: Any) -> Path | None:
    return ROOT / "build" / "program" / str(value) if value else None


def _find_bench(module: str) -> Path:
    matches = sorted((ROOT / "test" / "bench").rglob(f"{module}.sv"))
    if len(matches) != 1:
        raise ValueError(f"testbench {module!r}: expected one file, found {len(matches)}")
    return matches[0]


def load_simulations() -> tuple[dict[str, Simulation], dict[str, list[str]]]:
    raw = _read_yaml(ROOT / "config" / "simulations.yaml")
    defaults = raw.get("defaults", {})
    tasks: dict[str, Simulation] = {}
    for name, entry in raw.get("tasks", {}).items():
        bench_name = str(entry.get("tb", ""))
        defines = {str(key): str(value) for key, value in entry.get("verilog_defines", {}).items()}
        tasks[name] = Simulation(
            name=name,
            top=str(entry.get("top", "")),
            bench=_find_bench(bench_name) if bench_name else None,
            runtime=str(entry.get("runtime", "1ms")),
            boot_hex=_artifact(entry.get("blhex", defaults.get("blhex"))) if bench_name else None,
            program_hex=_artifact(entry.get("phex")),
            boot_coe=_artifact(entry.get("blcoe")),
            ddr3=bool(bench_name) and defines.get("SIMU_USE_DDR") == "1",
            defines=defines,
        )
    groups = {
        str(name): [str(task) for task in members]
        for name, members in raw.get("groups", {}).items()
    }
    return tasks, groups
