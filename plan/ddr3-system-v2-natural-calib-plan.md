# DDR3 System V2: Natural Calibration Plan

> ⛔ **已停止** — 2026-06-09: AHB-Lite 架构已废弃，全面转向 AXI 总线 + chiplab 对齐架构。见新计划 `plan/axi-mig-alignment-plan.md`

> **Date**: 2026-06-08
> **Goal**: Build tb_ddr3_system_v2 with zero workaround forces, relying on natural MIG calibration
> **Key Insight**: Eliminate forces by fixing RTL reset architecture, not by adding more TB patches

## Core Design Principle

The root cause of 22 forces is not "TB needs more workarounds" but "RTL reset architecture is wrong".
Fix the RTL → TB doesn't need patches.

### Current 22 Forces Root Cause

| Class | Count | Root Cause | Solution |
|-------|-------|-----------|----------|
| A | 6 | PHASER_IN SIP doesn't drive PHASELOCKED | **Experiment**: test natural calib with clk_wiz_0_passthrough |
| B | 7 | CPU reset releases before ahb_hresetn | **RTL fix**: CPU reset waits for ahb_hresetn |
| C | 9 | MIG AXI upsizer internal state abnormal | **Conjecture**: if A-class forces removed (natural calib), PHY state correct → deadlock resolves |

---

## Step 1: RTL Reset Architecture Fix — system_top.sv

### Problem

```
CPU.reset = ~ext_resetn        ← releases at t=200ns
ahb_hresetn                    ← releases at t≈62.5µs (after calib)

Gap: CPU drives HTRANS=NONSEQ for ~62µs while AHB bus is in reset
     → mux_HSELx corruption → AXI channel desync → wready deadlock
```

### Fix

```verilog
// CPU reset: hold until system reset clears AND AHB bus is ready.
wire cpu_reset;
assign cpu_reset = reset | ~ahb_hresetn;

core_top cpu(
    .clk   (mig_ui_clk),
    .reset (cpu_reset),    // was: reset
    ...
);
```

### Effect

| Condition | cpu_reset | CPU behavior |
|-----------|-----------|-------------|
| ext_resetn=0 | 1 | System reset, HTRANS=IDLE |
| ext_resetn=1, ahb_hresetn=0 | 1 | CPU waits for DDR3, HTRANS=IDLE |
| ext_resetn=1, ahb_hresetn=1 | 0 | CPU starts executing |

This is also correct for real hardware — CPU must not access uncalibrated DDR3.

---

## Step 2: TB Two-Phase Reset Strategy

### BFM Window

After calibration, `ahb_hresetn=1` but CPU just exited reset. BFM needs exclusive AHB access
before CPU fetches first instruction.

### Strategy

```
t=0         t=200ns              t≈calib done           t=BFM done
│           │                    │                      │
│ ext_rst=0 │ ext_rst=1          │ ahb_hresetn=1        │
│           │ MIG calibrating    │ cpu_reset=0          │
│           │ cpu_reset=1        │ CPU about to start   │
│           │ HTRANS=IDLE        │                      │
│           │                    │ force cpu.reset=1    │ release cpu.reset
│           │                    │ force cpu_H*=bfm_*   │ release cpu_H*
│           │                    │ BFM writes DDR3      │ CPU starts
```

**B-class forces: 7 → 1** (force `cpu.reset=1` instead of 7 AHB signals)
**BFM AHB forces: still 7** (methodology-required, not workaround)

---

## Step 3: New TB Structure — tb_ddr3_system_v2.sv

### Same as v1

- Parameters, clocks, DDR3 model + WireDelay, BFM tasks
- WireDelay, ddr3_model, hex loading, trampoline
- GPIO monitoring, timeout watchdog

### Different from v1

| Aspect | v1 (22 forces) | v2 |
|--------|---------------|-----|
| Calibration | 6 A-class forces | **Zero forces** — pure wait(init_calib_complete) |
| CPU isolation | 7 B-class forces on cpu_H* | **1 force** on cpu.reset |
| BFM window | 7 cpu_H* forces (same) | 7 cpu_H* forces (methodology-required) |
| AXI deadlock | 9 C-class forces | **Zero forces** — rely on natural PHY state |
| B/R channel kick | 2 dynamic forces | **Zero** — monitoring only |
| PHASER_IN | 4 initial blocks with forces | **Zero** — experiment |

### Total forces: 22 → 8 (1 cpu.reset + 7 BFM AHB)

---

## Step 4: Experiment Phases & Fallback

```
                ┌─────────────────────────┐
                │  Experiment 1:          │
                │  Zero A-class force     │
                │  Natural calibration    │
                └──────────┬──────────────┘
                           │
                ┌──────────▼──────────────┐
                │  init_calib_complete=1? │
                └──────────┬──────────────┘
                       ╱         ╲
                     YES          NO (FSM stuck at state 38)
                      │            │
                      │     ┌──────▼──────────────┐
                      │     │  Fallback A1:       │
                      │     │  Add back           │
                      │     │  pi_phase_locked_   │
                      │     │  all force (1 line) │
                      │     └──────┬──────────────┘
                      │            │
                ┌─────▼────────────▼──────┐
                │  Experiment 2:          │
                │  Zero C-class force     │
                │  Test DDR3 write/read   │
                └──────────┬──────────────┘
                           │
                ┌──────────▼──────────────┐
                │  wready=1? R/W PASS?    │
                └──────────┬──────────────┘
                       ╱         ╲
                     YES          NO (AXI deadlock)
                      │            │
                      │     ┌──────▼──────────────┐
                      │     │  Experiment 3:      │
                      │     │  Add back minimal   │
                      │     │  C-class force      │
                      │     │  (wr_cmd_valid=1)   │
                      │     └──────┬──────────────┘
                      │            │
                ┌─────▼────────────▼──────┐
                │  8-pattern write/read    │
                │  → PASS → full flow test │
                └─────────────────────────┘
```

---

## Step 5: Implementation Checklist

### 5.1 RTL Modification (1 file, 1 change)

| File | Change | Impact |
|------|--------|--------|
| `system_top.sv` | Add `wire cpu_reset = reset \| ~ahb_hresetn`; CPU `.reset(cpu_reset)` | HW-correct: CPU waits for DDR3 calib; SIM: eliminates B-class force root cause |

### 5.2 New TB File

| File | Description |
|------|-------------|
| `dev/tb/tb_ddr3_system_v2.sv` | New testbench, based on v1 with restructured force strategy |

### 5.3 tasks.yaml

```yaml
ddr3_system_v2:
  tb: tb_ddr3_system_v2
  sim_mode: ddr3
  verilog_defines:
    SIM_BYPASS_INIT_CAL: FAST
    SIMULATION: "TRUE"
    sg125: 1
    DDR3_BYPASS_CLK_WIZ: 1
  hex_file: app/ddr3_test.hex
  runtime: 100ms
```

### 5.4 Vivado Orchestrator

| File | Change |
|------|--------|
| `tools/vivado_core/operations.py` | Add tb_ddr3_system_v2 to sim_1 file list |

---

## Step 6: Verification Checkpoints

| CP | Condition | Pass | Fail Action |
|----|-----------|------|-------------|
| CP1 | Natural calibration | init_calib_complete=1 within 200µs | Add back A1 force, retry |
| CP2 | Post-calib AXI state | wready=1 when wvalid=0 | Log state, enter Experiment 3 |
| CP3 | Single write | bfm_ahb_write no HREADYOUT timeout | Log AXI snapshot, analyze deadlock |
| CP4 | 8-pattern write/read | 8/8 PASS | Per-word failure analysis |
| CP5 | CPU execution | GPIO_DATA[0]=1 (PASS) | Check CPU fetch/execute path |

---

## Step 7: Expected Outcomes & Risk

| Scenario | Prob | Result | Next |
|----------|------|--------|------|
| Best: natural calib ✅ + AXI normal ✅ | 30% | Zero A/C forces, 1+7 BFM forces | v2 replaces v1 |
| Medium: need A1 + AXI normal | 40% | 1 A + 1+7 BFM forces | Major simplification |
| Poor: need A1+A2 + C1 | 20% | 2 A + 1 C + 1+7 BFM forces | Still better than v1's 22 |
| Worst: natural calib fails + AXI deadlock | 10% | Revert to v1, keep RTL cpu_reset fix | RTL fix still beneficial |

**Key**: Step 1's RTL reset fix is correct hardware design regardless of simulation outcome.
