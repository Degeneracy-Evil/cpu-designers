"""Task definition loading and querying.

Reads a ``tasks.yaml`` file that maps task names to their configuration
(testbench, bootloader/program images, runtime, top module).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .exceptions import TaskNotFoundError


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TaskConfig:
    """Configuration for a single task (simulation or FPGA build).

    Attributes
    ----------
    name:
        Unique task identifier (the key in ``tasks.yaml``).
    tb:
        Testbench module name (empty for FPGA-only tasks).
    blcoe:
        Bootloader COE filename relative to ``dev/program_source/``.
        Used for FPGA bitstream generation and DDR3 simulation where the
        BRAM IP is initialised from COE.  Mutually exclusive with
        ``blhex`` — tasks must set one or the other, never both.
    runtime:
        Simulation runtime string, e.g. ``"5ms"`` or ``"40ms"``.
    top:
        Top module name for bitstream generation (empty for
        simulation-only tasks).
    sim_mode:
        Simulation mode flag, e.g. ``"ddr3"`` to trigger DDR3
        simulation model import and configuration.
    verilog_defines:
        Verilog defines for simulation, e.g.
        ``{"SIM_BYPASS_INIT_CAL": "FAST", "SIMULATION": "TRUE"}``.
    mig_param_overrides:
        MIG parameter overrides for xsim elaboration, mapping
        hierarchical parameter paths to values, e.g.
        ``{"u_dut...u_mig.SIM_BYPASS_INIT_CAL": "FAST"}``.
        Passed as ``-g`` flags to xelab.
    blhex:
        Bootloader HEX filename relative to ``dev/program_source/``.
        Used for normal (SRAM) simulation where the bootROM reads the
        hex file via ``$readmemh``.  Mutually exclusive with
        ``blcoe`` — tasks must set one or the other, never both.
    phex:
        Program HEX filename relative to ``dev/program_source/``.
        Specifies the program image loaded into SRAM via
        ``$readmemh("prog.hex")`` during simulation.  Only used in
        SRAM-mode simulation; DDR3 simulation loads the program via
        UART instead.
    """

    name: str
    tb: str = ""
    blcoe: str = ""
    runtime: str = ""
    top: str = ""
    sim_mode: str = ""
    verilog_defines: dict[str, str] = field(default_factory=dict)
    mig_param_overrides: dict[str, str] = field(default_factory=dict)
    blhex: str = ""
    phex: str = ""


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

class TaskRegistry:
    """Load and query task definitions from a ``tasks.yaml`` file.

    Parameters
    ----------
    yaml_path:
        Path to the YAML file containing task definitions.

        Expected YAML format::

            tasks:
              cpu_full:
                tb: tb_simple_cpu_top
                blhex: boot/bootloader_phase1.hex
                phex: test/integration/cpu_full.hex
                runtime: 5ms
              fpga:
                top: system_top
                blcoe: boot/bootloader.coe
    """

    def __init__(self, yaml_path: Path | str) -> None:
        self.yaml_path = Path(yaml_path)
        self._tasks: dict[str, TaskConfig] = {}

    # ------------------------------------------------------------------
    # Loading
    # ------------------------------------------------------------------

    def load(self) -> None:
        """Parse the YAML file and populate the registry.

        Raises
        ------
        TaskError
            If the YAML file cannot be read or is malformed.
        """
        if not self.yaml_path.is_file():
            raise TaskNotFoundError(str(self.yaml_path))

        with self.yaml_path.open("r", encoding="utf-8") as fh:
            raw: dict = yaml.safe_load(fh) or {}

        tasks_raw: dict = raw.get("tasks", {}) or {}
        self._tasks = {}

        for name, cfg in tasks_raw.items():
            if not isinstance(cfg, dict):
                cfg = {}
            self._tasks[name] = TaskConfig(
                name=name,
                tb=cfg.get("tb", ""),
                blcoe=cfg.get("blcoe", ""),
                runtime=cfg.get("runtime", ""),
                top=cfg.get("top", ""),
                sim_mode=cfg.get("sim_mode", ""),
                verilog_defines=cfg.get("verilog_defines", {}) or {},
                mig_param_overrides=cfg.get("mig_param_overrides", {}) or {},
                blhex=cfg.get("blhex", ""),
                phex=cfg.get("phex", ""),
            )

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    def get(self, name: str) -> TaskConfig:
        """Look up a task by name.

        Parameters
        ----------
        name:
            Task identifier.

        Returns
        -------
        TaskConfig

        Raises
        ------
        TaskNotFoundError
            If *name* is not in the registry.
        """
        if name not in self._tasks:
            raise TaskNotFoundError(name)
        return self._tasks[name]

    def list_all(self) -> list[TaskConfig]:
        """Return all registered tasks (sorted by name)."""
        return [self._tasks[k] for k in sorted(self._tasks)]

    def list_names(self) -> list[str]:
        """Return all registered task names (sorted)."""
        return sorted(self._tasks)

    # ------------------------------------------------------------------
    # Dunder helpers
    # ------------------------------------------------------------------

    def __len__(self) -> int:
        return len(self._tasks)

    def __contains__(self, name: str) -> bool:
        return name in self._tasks

    def __repr__(self) -> str:
        return f"TaskRegistry({self.yaml_path!s}, tasks={len(self._tasks)})"
