---
name: test-builder
description: Build, list, clean, debug, or extend this CPU project's bare-metal tests and applications. Use for tools/test_builder.py, src/program_source/build.yaml, rv2coe output, the x28-x31 self-check protocol, adding a test and its Vivado task/testbench, or diagnosing a failed ISA, privilege, MMU, Cache, MMIO, regression, or integration test.
---

# Test builder

Use `tools/test_builder.py` as the only registry-driven entry for bare-metal tests and applications.
Use `tools/rv2coe.py` directly only for an ad-hoc program or when debugging the compiler/linker step.

## Locate the source of truth

- Read `src/program_source/build.yaml` for framework groups, categories, tests, applications and ISA.
- Read `config/tasks.yaml` for explicit Vivado task-to-testbench and HEX/COE mappings.
- Read `src/program_source/test-system.md` only when detailed framework or MMU layout rules are needed.
- Keep task entries explicit; do not infer testbench and image fields from naming conventions.

Generated test and application images remain under `src/program_source/` beside their sources and are
ignored by Git. Normal SRAM simulation consumes HEX; FPGA/DDR boot paths may consume COE/BIN as named
by the selected task.

## Use the supported commands

```bash
# Inspect without compiling
python3 tools/test_builder.py --list
python3 tools/test_builder.py --dry-run

# Build
python3 tools/test_builder.py
python3 tools/test_builder.py --category mmu
python3 tools/test_builder.py --test isa/m_ext
python3 tools/test_builder.py --app uart_hello

# Remove generated test and application HEX/COE files
python3 tools/test_builder.py --clean
```

Treat a nonzero exit status or a printed failed target as a build failure. Do not infer success merely
from the presence of an older image.

## Understand the registry

Use these `build.yaml` fields:

```yaml
framework:
  common:
    - framework/test_framework.s
    - framework/trap_handlers.s

defaults:
  arch: rv32im_zicsr_zifencei
  abi: ilp32
  linker_script: link.ld
  depth: 8192

categories:
  example:
    framework: common
    arch: rv32ima_zicsr_zifencei
    tests:
      - example/my_test

apps:
  my_app:
    src_files: [app/my_app.s]
    linker_script: null
```

Override `arch`, `abi`, `linker_script`, `depth` or `include_dirs` only where the target differs from
the defaults. Select the `mmu` framework for page-table helpers. Select `none` only for a standalone
integration program that intentionally supplies its own startup and reporting.

`rv2coe.py` validates instructions against the selected ISA. Use `rv32ima_zicsr_zifencei` when a test
contains LR/SC/AMO; do not rely on an unknown architecture string silently skipping validation.

## Follow the self-check protocol

Call the framework in this order:

```asm
jal x1, test_init

la  x11, test_01_behavior
jal x1, test_run

jal x1, test_report
1:  j 1b
```

Return each subtest result in `x14`: nonzero for PASS, zero for FAIL. Let `test_run` preserve and
aggregate framework state.

Interpret the compatibility registers only after `test_report` publishes them:

| Register | Meaning |
|---|---|
| `x28` | passed subtests |
| `x29` | total subtests and completion marker |
| `x30` | first failing subtest ID, zero on success |
| `x31` | current/final subtest ID |

The summary and per-test results are also written at `0x80007000`. Keep MMU tests within their
documented 32 KiB layout so page tables and result memory do not overlap.

## Add a test end to end

1. Add `src/program_source/test/<category>/<name>.s` with small numbered subtests.
2. Register `<category>/<name>` under the correct category in `build.yaml`.
3. Build just that target and inspect the emitted command if it fails:

```bash
python3 tools/test_builder.py --test <category/name> -v
```

4. Add or reuse a self-checking testbench under `src/tb/`. Set its expected total to the actual
   subtest count and use the helpers in `tb_soc_includes.svh`.
5. Add an explicit task to `config/tasks.yaml` with the correct `tb`, `blhex`, `phex` and `runtime`.
6. Run the task and confirm both XSim completion and the semantic PASS marker:

```bash
python3 -m tools.vivado_cli -task <task-name> -create -sim
```

Do not treat `XSim completed` alone as a self-checking PASS.

## Diagnose a failure

1. Read `x30` or the testbench's first-fail report and open that numbered subtest.
2. Inspect `x22`–`x27` for trap-handler outputs when the failure involves an exception.
3. Enable a text trace before enabling waves:

```bash
python3 -m tools.vivado_cli -task <task> -sim --debug trace,trap
python3 -m tools.trace_analyzer find-fail instr_trace.log
```

4. Use `--debug wave:minimal` only when signal timing remains ambiguous.
5. Rebuild after source changes and refresh the `coe` layer before reusing a Vivado session.

## Run grouped validation

Use category globs for focused work and the curated plan for routine full coverage:

```bash
python3 -m tools.vivado_cli -batch "mmu_*" -create -sim --max-parallel 2
python3 -m tools.vivado_cli -batch-plan config/short_regression.yaml
```

The short plan deliberately excludes full Linux and DDR3 simulation. Keep those slow paths as
separate milestones rather than adding them to every test cycle.
