# Focused simulation debugging

Read this reference only after a normal self-check or progress log has narrowed the problem.

## Prefer text before waves

Enable existing monitors without editing RTL:

```bash
python3 -m tools.vivado_cli -task <task> -sim --debug trace,trap
python3 -m tools.trace_analyzer parse instr_trace.log --limit 50
python3 -m tools.trace_analyzer find-fail instr_trace.log
python3 -m tools.trace_analyzer stats instr_trace.log
```

Available debug features are:

| Feature | Output |
|---|---|
| `trace` | `instr_trace.log` with cycle, time, PC, instruction and writeback |
| `pipeline` | `pipeline_dump.log` with stage state each cycle |
| `trap` | `trap_trace.log` with entry/return and CSR state |
| `spike` | `spike_commit.log` for differential analysis |
| `wave:minimal` | selected top-level WDB objects |
| `wave:normal` | selected top/core WDB objects |
| `wave:full` | all-object WDB plus `sim_dump.vcd` |

Simulation-created files live in the XSim run directory below the selected session project, normally:

```text
build/project/<session>/<project>.sim/sim_1/behav/xsim/
```

The CLI `--log` file is separate: it captures timestamped Vivado console output at the caller's path.

## Add a narrow `$fwrite` monitor

Prefer an existing generic monitor in `src/tb/tb_soc_includes.svh`. Add a new one only when the needed
event cannot be derived from existing commit, trap, UART, progress, Cache or bus signals.

Keep the monitor simulation-only and event-driven:

```systemverilog
`ifdef DEBUG_EXAMPLE
    integer dbg_fd;

    initial begin
        dbg_fd = $fopen("example.log", "w");
        if (dbg_fd == 0)
            $display("[DEBUG] cannot open example.log");
    end

    always @(posedge clk) begin
        if (resetn && dbg_fd != 0 && event_valid) begin
            $fwrite(dbg_fd, "%0t pc=%08h data=%08h\n", $time, event_pc, event_data);
            $fflush(dbg_fd);
        end
    end

    final begin
        if (dbg_fd != 0)
            $fclose(dbg_fd);
    end
`endif
```

Follow these constraints:

- Log on an actual handshake or state transition, not every cycle.
- Include `$time`, cycle or PC plus the values needed to establish causality.
- Check `$fopen`, flush rare critical events, and close the original descriptor.
- Avoid image-specific PC/address filters in shared RTL.
- Avoid duplicated architectural state snapshots and large forensic ring buffers.
- Remove the monitor after the investigation unless it remains generally useful.

## Escalate to waves

Start with:

```bash
python3 -m tools.vivado_cli -task <task> -sim --debug wave:minimal
```

Use `wave:normal` only if internal core timing is needed. Use `wave:full` only for a short, bounded
reproduction because it records all objects and emits VCD. Do not combine a full wave dump with a
long Linux or DDR3 run.

Correlate text and waves by recording `$time` in the log, then jumping to that timestamp in Vivado.
Keep a narrow window around the first incorrect transaction or architectural update; later failures
are often consequences.

## Compare against Spike carefully

Generate `spike_commit.log` with `--debug spike` and use:

```bash
python3 -m tools.trace_analyzer diff instr_trace.log spike_commit.log
```

Compare only when both traces describe the same retirement boundary, privilege state and firmware.
Interrupt timing, MMIO side effects and a trace taken at fetch rather than retirement can create false
divergence. Confirm the first mismatch against RTL handshakes before changing the CPU.

## Preserve evidence

Record the command, commit, task, firmware hashes, first failing time/PC and the minimal supporting log.
Do not commit WDB, VCD, generated sessions or multi-megabyte UART logs. Summarize a confirmed root cause
and its regression test in project documentation instead.
