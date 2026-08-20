---
name: vivado-orchestrator
description: >-
  Operate this repository's Vivado 2018.3 workflow through tools.vivado_cli: create or refresh
  isolated sessions, run one simulation or the curated short batch, inspect status and logs,
  explicitly capture WDB/VCD, generate or program an FPGA bitstream, manage ILA insertion, and
  diagnose stale sources, timeout, elaboration, or semantic test failures.
---

# Vivado orchestrator

Run Vivado only through `python3 -m tools.vivado_cli`. Treat `config/vivado_config.yaml` and
`config/tasks.yaml` as the source of truth. Keep one CLI and one implementation of each operation.

## Choose the cheapest valid workflow

Start with read-only inspection:

```bash
python3 -m tools.vivado_cli --status
python3 -m tools.vivado_cli --help
python3 tools/test_builder.py --list
```

Group related RTL and tool edits before invoking Vivado. Use one focused task during development,
one short batch at a milestone, and one bitstream near the end. Do not use a full Linux/DDR3 run as a
routine correctness check.

## Create and reuse a session

Use a stable session name when iterative reuse matters. Without `-session`, the task name is used.

```bash
# First run: create the project, then simulate
python3 -m tools.vivado_cli -task isa_m_ext -session m_ext_work -create -sim

# After changing only the program image or testbench
python3 -m tools.vivado_cli -task isa_m_ext -session m_ext_work -refresh --layers coe,tb
python3 -m tools.vivado_cli -task isa_m_ext -session m_ext_work -sim

# After changing RTL or generated IP configuration
python3 -m tools.vivado_cli -task isa_m_ext -session m_ext_work -refresh
python3 -m tools.vivado_cli -task isa_m_ext -session m_ext_work -sim
```

Use `-create` again only when rebuilding the project is intended; creation uses a forced project
replacement inside that session. Available refresh layers are `rtl`, `tb`, `coe` and `fpga`.

Regenerate derived Cache/TLB constants after editing the memory configuration:

```bash
python3 -m tools.vivado_cli --gen-config
```

This must leave `src/rtl/core/cache_def.svh` consistent with the two-way Cache and TLB geometry.

## Run simulations

```bash
# One task, with optional runtime override and durable command log
python3 -m tools.vivado_cli -task mmu_permission -create -sim
python3 -m tools.vivado_cli -task mmu_permission -sim -runtime 30ms \
  --log build/logs/mmu_permission.log

# Focused group or curated fast regression
python3 -m tools.vivado_cli -batch "mmu_*" -create -sim --max-parallel 2
python3 -m tools.vivado_cli -batch-plan config/short_regression.yaml
```

Read the semantic PASS/FAIL emitted by each testbench. `XSim completed` only proves that the simulator
ran to its requested end; it does not prove the CPU result was correct.

The curated plan excludes DDR3 and full Linux boot. Keep `kernel_tb_compile_smoke` as a 1 us
compile/elaboration check and never describe it as a successful kernel boot.

## Keep waves opt-in

Normal simulation uses a custom run Tcl that removes XSim's otherwise automatic WDB pathname and does
not log signals. Enable only the smallest useful debug output:

```bash
python3 -m tools.vivado_cli -task <task> -sim --debug trace,trap
python3 -m tools.vivado_cli -task <task> -sim --debug wave:minimal
python3 -m tools.vivado_cli -task <task> -sim --debug wave:normal
python3 -m tools.vivado_cli -task <task> -sim --debug wave:full
```

`minimal` and `normal` produce selective WDB data. `full` records all objects and exports
`sim_dump.vcd`; expect a severe speed and disk penalty. Read
[`references/simulation-debug.md`](references/simulation-debug.md) before adding a new `$fwrite`
monitor, locating generated logs or collecting a wave window.

## Inspect and clean sessions

```bash
python3 -m tools.vivado_cli --status
python3 -m tools.vivado_cli --cleanup
python3 -m tools.vivado_cli --cleanup-all
```

Use `--cleanup` for automatic retention. Use `--cleanup-all` only when removing every generated session
is intended; it is destructive but does not touch tracked sources. Check for a live Vivado/XSim process
before diagnosing a session as deadlocked.

## Build and program FPGA

```bash
python3 -m tools.vivado_cli -task fpga -session fpga_final -create -bitstream \
  --log build/logs/fpga_final.log
python3 -m tools.vivado_cli -task fpga -session fpga_final -program
```

Require zero Vivado errors and no critical warnings that invalidate routing or timing. Inspect width,
unconnected-port, clock and reset warnings rather than accepting a bit file blindly.

For optional ILA debugging, first open the already-created FPGA project in Vivado, then source only:

```tcl
source tools/vivado_core/tcl/add_ila.tcl
```

The script creates the two project ILAs idempotently. It does not build a bitstream and is not invoked
by normal CLI flows.

## Diagnose failures in order

1. Check the CLI exit status and the last `ERROR:` line.
2. Run `--status` and confirm the selected task/session and stale layers.
3. Inspect the timestamped CLI log and XSim's `simulate.log` inside the session project.
4. Distinguish create/compile/elaboration failure from a semantic FAIL printed by the testbench.
5. For a timeout, check UART/progress timestamps and whether simulation time still advances before
   increasing the configured timeout.
6. Rebuild program images and refresh `coe` if source and loaded firmware differ.
7. Use `--debug trace,trap`; add minimal waves only after identifying a suspicious cycle or PC.
8. Recreate the session only after incremental refresh and log-based diagnosis are exhausted.

If the executable is not on `PATH`, prepend the local Vivado installation for that command or set
`vivado_path` locally. Do not commit a developer-specific absolute installation path.

## Preserve the single implementation

- Keep project creation, refresh, simulation, bitstream, programming and archive Tcl generation in
  `tools/vivado_core/operations.py`.
- Keep IP geometry in `config/vivado_config.yaml`, parsing in `config.py`, generation in `ip_gen.py`
  and derived RTL macros in `cache_header_gen.py`.
- Keep task names and firmware mappings explicit in `config/tasks.yaml`; do not copy the entire task
  table into this skill.
- Keep batch membership in small plan files such as `config/short_regression.yaml`.
- Keep default simulation free of WDB and add debug instrumentation only behind explicit options.
