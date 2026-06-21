# MMU/TLB Unit Test Plan — SystemVerilog Testbench

> **Status**: Planning document (no code changes yet)
> **Date**: 2026-06-21
> **Scope**: All bugs identified in the deep audit of `MMU.sv`, `tlb.sv`, and integration layer
> **Strategy**: SystemVerilog testbench unit tests (直接例化 DUT, 精确控制时序)

---

## 1. Overview

### 1.1 Audit Summary

| Component | Bugs Found | Critical | High | Medium |
|-----------|-----------|----------|------|--------|
| `tlb.sv`  | 4         | 3        | 1    | 0      |
| `MMU.sv`  | 7         | 0        | 5    | 2      |
| Integration | 3       | 0        | 0    | 3      |
| **Total** | **14**    | **3**    | **6**| **5**  |

### 1.2 Test Infrastructure Requirements

#### 1.2.1 Directory Structure

```
dev/tb/mmu_tlb_unit/
├── tb_pkg.svh                    # Shared types, macros, helpers
├── tlb_tb.sv                     # TLB unit testbench (DUT = tlb.sv)
├── mmu_tb.sv                     # MMU unit testbench (DUT = MMU.sv)
├── mmu_integration_tb.sv         # MMU + TLB + PTW + mock bus (DUT = MMU.sv + ptw.sv)
├── tests/
│   ├── tlb_test_base.svh         # Base class for TLB tests
│   ├── mmu_test_base.svh         # Base class for MMU tests
│   ├── tlb_tc_*.sv               # Individual TLB test cases
│   ├── mmu_tc_*.sv               # Individual MMU test cases
│   └── int_tc_*.sv               # Individual integration test cases
└── run_all.do                    # Vivado TCL script to run all tests
```

#### 1.2.2 Common Testbench Components

| Component | Purpose | Notes |
|-----------|---------|-------|
| `clk_rst_gen` | Clock + reset generator | 10ns period, synchronous assert/deassert reset |
| `csr_mock_drv` | Drive CSR inputs (satp, priv_mode, sum, mxr, mstatus) | Programmable, supports mid-walk changes |
| `bus_bfm` | AXI4-lite BFM for PTW bus interface | Configurable latency, error injection |
| `tlb_scoreboard` | Compare TLB lookup results vs reference model | Reference: simple array-based TLB |
| `mmu_scoreboard` | Compare MMU translation results vs reference | Reference: software page walker |
| `ref_tlb_model` | Golden reference TLB model (simple array) | No timing, pure functional |
| `ref_mmu_model` | Golden reference MMU model (Sv32 walker) | No timing, pure functional |
| `vcd_dump` | Waveform capture for debug | Optional, enabled via `+DUMP_VCD` plusarg |

#### 1.2.3 Test Result Convention

- Each test case prints: `[PASS] TC_xxx` or `[FAIL] TC_xxx — <reason>`
- Testbench exits with `$finish` after all tests; overall pass = all individual pass
- Use `+TC=<test_id>` plusarg to run a single test case (default: run all)

---

## 2. TLB Unit Tests (`tlb.sv`)

### 2.1 DUT Configuration

```
DUT: dev/rtl/core/tlb.sv
Parameters: USE_TLB_BRAM=1 (BRAM path, primary target)
Clock: clk
Reset: rst (active high, synchronous)
Key interfaces:
  - i_lookup_req/addr/valid/hit/ppn/perm  (Port A, i-side)
  - d_lookup_req/addr/valid/hit/ppn/perm  (Port B, d-side)
  - fill_req/set_idx/way_idx/ppn/perm/asid (TLB fill)
  - flush_req/flush_done                  (TLB flush)
  - BRAM inference via `USE_TLB_BRAM
```

### 2.2 Test Cases

---

#### TC_TLB_001: D-side lookup corrupted by concurrent fill (TLB-1)

| Field | Value |
|-------|-------|
| **Bug ID** | TLB-1 |
| **Severity** | CRITICAL |
| **Bug Location** | tlb.sv L166, L173-184, L435-440 |
| **Objective** | Verify that a d-side lookup in progress is not corrupted when a TLB fill starts on the next cycle |

**Bug Description**:
Cycle N: `d_lookup_req=1` → latches `d_latched_vpn`, sets `d_lookup_valid_r=1`, BRAM Port B reads `d_lookup_set_idx`.
Cycle N+1: `fill_req=1` → Port B switches to write mode at `fill_set_idx`. But `d_lookup_valid_r` is still 1, so the comparison logic uses BRAM Port B output (now showing fill data for a different set) vs `d_latched_vpn` → wrong hit/miss decision.

**Preconditions**:
- TLB has at least 1 valid entry in set 0, way 0 (VPN=0x100, PPN=0x200, ASID=1)
- TLB is empty for set 1
- Current ASID = 1

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | Assert `d_lookup_req=1`, `d_lookup_vpn=0x100` (should hit set 0) |
| 1     | Deassert `d_lookup_req=0`; Assert `fill_req=1`, `fill_set_idx=1`, `fill_way_idx=0`, `fill_vpn=0x300`, `fill_ppn=0x400` |
| 2     | Deassert `fill_req=0` |

**Expected (correct) behavior**:
- Cycle 1: `d_lookup_hit=1`, `d_lookup_ppn=0x200` (result from Cycle 0's lookup)
- Cycle 2: `d_lookup_hit=0` (fill complete, no active lookup)

**Actual (buggy) behavior**:
- Cycle 1: `d_lookup_hit=0` or `d_lookup_hit=1` with wrong PPN (Port B now reading set 1 data during fill write, comparison uses wrong set data)

**Pass Criteria**: `d_lookup_hit` and `d_lookup_ppn` at Cycle 1 match the golden reference model

**Testbench Implementation Notes**:
- Drive `d_lookup_req` and `fill_req` with exact 1-cycle offset
- Sample `d_lookup_hit`/`d_lookup_ppn` at Cycle 1 posedge
- Compare against `ref_tlb_model.lookup(d_vpn=0x100, asid=1)`

---

#### TC_TLB_002: Back-to-back i-side lookups produce wrong results (TLB-2)

| Field | Value |
|-------|-------|
| **Bug ID** | TLB-2 |
| **Severity** | CRITICAL |
| **Bug Location** | tlb.sv L427-432, L450-458 |
| **Objective** | Verify that two consecutive i-side lookups to different sets return correct results for both |

**Bug Description**:
Cycle N: `i_lookup_req=1` with VPN_A → latches VPN_A, BRAM Port A reads set(A).
Cycle N+1: `i_lookup_req=1` with VPN_B → latches VPN_B (overwrites VPN_A in latch), BRAM Port A reads set(B).
But the comparison logic for Cycle N's lookup uses the BRAM output available at Cycle N+1 (which is set(B) data), comparing it against VPN_A (still in `i_lookup_valid_r` path) → VPN_A vs set(B) data → wrong result.

**Preconditions**:
- Set 0, way 0: VPN=0x100, PPN=0x200, ASID=1, valid=1
- Set 1, way 0: VPN=0x300, PPN=0x400, ASID=1, valid=1
- Current ASID = 1

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_lookup_req=1`, `i_lookup_vpn=0x100` (set 0, should hit) |
| 1     | `i_lookup_req=1`, `i_lookup_vpn=0x300` (set 1, should hit) |
| 2     | `i_lookup_req=0` |

**Expected**: Both lookups return hit with correct PPN (0x200 and 0x400 respectively)

**Actual (buggy)**: First lookup's result at Cycle 1 is computed using set 1's BRAM data → miss or wrong PPN

**Pass Criteria**: Cycle 1 `i_lookup_hit=1, i_lookup_ppn=0x200`; Cycle 2 `i_lookup_hit=1, i_lookup_ppn=0x400`

---

#### TC_TLB_003: Back-to-back d-side lookups produce wrong results (TLB-3)

| Field | Value |
|-------|-------|
| **Bug ID** | TLB-3 |
| **Severity** | CRITICAL |
| **Bug Location** | tlb.sv L435-440, L450-458 |
| **Objective** | Same as TC_TLB_002 but for d-side port |

**Preconditions**: Same as TC_TLB_002

**Stimulus**: Same pattern, using `d_lookup_req`/`d_lookup_vpn` instead of i-side

**Expected/Actual/Pass Criteria**: Same as TC_TLB_002, d-side variants

---

#### TC_TLB_004: PLRU drops i-side hit update on simultaneous i+d hit (TLB-4)

| Field | Value |
|-------|-------|
| **Bug ID** | TLB-4 |
| **Severity** | HIGH |
| **Bug Location** | tlb.sv L450-458 |
| **Objective** | Verify PLRU state correctly reflects both i-side and d-side accesses when both hit the same set simultaneously |

**Bug Description**:
When i-side and d-side both hit the same set in the same cycle, the PLRU update logic only applies `d_plru_next`, dropping `i_plru_next`. Over time, i-side accesses don't affect PLRU → i-side working set may be evicted prematurely.

**Preconditions**:
- All 4 ways of set 0 are valid (VPN_A, VPN_B, VPN_C, VPN_D with PPNs 0xA, 0xB, 0xC, 0xD)
- PLRU tree initialized to a known state (e.g., all zeros → way 0 next victim)

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0-3   | Fill all 4 ways of set 0 |
| 4     | `i_lookup_req=1`, VPN_A (way 0); `d_lookup_req=1`, VPN_B (way 1) — both hit set 0 |
| 5     | Deassert both |
| 6-9   | Repeat i+d hits to VPN_A and VPN_B several times |
| 10    | Insert new VPN_E into set 0 (trigger eviction) |
| 11    | Lookup VPN_A (should still be present if PLRU tracked i-side access) |

**Expected**: VPN_A is NOT evicted (PLRU should have marked way 0 as recently used via i-side)

**Actual (buggy)**: VPN_A may be evicted because i-side PLRU updates were dropped → way 0 still appears "least recently used"

**Pass Criteria**: After eviction, `i_lookup(VPN_A)` still hits

**Notes**: This test requires careful PLRU state tracking in the reference model. The test may need multiple rounds of i+d simultaneous access to make the PLRU divergence observable.

---

#### TC_TLB_005: Fill during i-side lookup corruption (TLB-1 variant)

| Field | Value |
|-------|-------|
| **Bug ID** | TLB-1 (i-side variant) |
| **Severity** | CRITICAL |
| **Bug Location** | tlb.sv L427-432 (Port A conflict with fill) |
| **Objective** | Verify i-side lookup not corrupted when fill uses Port A |

**Notes**: Fill typically uses Port B, but if the implementation routes fill through Port A under certain conditions, this variant is needed. Check tlb.sv fill path to determine if Port A is ever used for fill. If fill only uses Port B, this test is N/A for i-side (Port A is dedicated to i-side reads).

**Pass Criteria**: i-side lookup result stable during fill on Port B

---

#### TC_TLB_006: Flush during active lookup

| Field | Value |
|-------|-------|
| **Bug ID** | (New — coverage) |
| **Severity** | MEDIUM |
| **Objective** | Verify TLB behavior when flush_req arrives during an active lookup |

**Preconditions**: TLB has valid entries, `d_lookup_req=1` in progress

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `d_lookup_req=1`, VPN=0x100 (hit) |
| 1     | `flush_req=1`, `d_lookup_req=0` |

**Expected**: Lookup result for Cycle 0 is valid; flush completes correctly; subsequent lookups miss

**Pass Criteria**: No X-propagation, no hang, flush_done asserts within expected cycles

---

#### TC_TLB_007: Flush during active fill

| Field | Value |
|-------|-------|
| **Bug ID** | (New — coverage) |
| **Severity** | MEDIUM |
| **Objective** | Verify behavior when flush_req arrives while fill is writing BRAM |

**Stimulus**: Assert `fill_req` and `flush_req` simultaneously on consecutive cycles

**Expected**: Defined priority (flush wins or fill completes then flush), no BRAM corruption

**Pass Criteria**: Post-flush, all lookups miss; no X values in TLB entries

---

### 2.3 TLB Test Summary

| Test ID | Bug | Severity | Cycles | Status |
|---------|-----|----------|--------|--------|
| TC_TLB_001 | TLB-1 | CRITICAL | ~5 | Pending |
| TC_TLB_002 | TLB-2 | CRITICAL | ~4 | Pending |
| TC_TLB_003 | TLB-3 | CRITICAL | ~4 | Pending |
| TC_TLB_004 | TLB-4 | HIGH | ~15 | Pending |
| TC_TLB_005 | TLB-1 | CRITICAL | ~5 | Pending (verify N/A) |
| TC_TLB_006 | — | MEDIUM | ~10 | Pending |
| TC_TLB_007 | — | MEDIUM | ~10 | Pending |

---

## 3. MMU Unit Tests (`MMU.sv`)

### 3.1 DUT Configuration

```
DUT: dev/rtl/core/MMU.sv
Configuration: USE_TLB_BRAM=1 (BRAM path) and USE_TLB_BRAM=0 (non-BRAM path)
  → Run full suite twice, once per configuration
Key interfaces:
  - i_translate_req/vaddr/valid/paddr/fault/perm  (i-side translation)
  - d_translate_req/vaddr/valid/paddr/fault/perm  (d-side translation)
  - ptw_req/ptw_ready/ptw_addr/ptw_pte             (PTW interface)
  - csr_satp/csr_priv_mode/csr_sum/csr_mxr         (CSR inputs)
  - sfence_vma/sfence_done                          (SFENCE handshake)
  - flush_req/flush_done                            (TLB flush)
```

### 3.2 Test Cases

---

#### TC_MMU_001: sfence_done asserts before TLB flush starts (MMU-5)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-5 |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L541-551 |
| **Objective** | Verify that sfence_done does not assert until TLB flush is actually complete |

**Bug Description**:
When `sfence_vma` asserts and both i_state and d_state are IDLE, the FSM sets `sfence_pending_r=1` and `sfence_done=1` in the same cycle. But the TLB flush hasn't started yet — the FSM transitions to FLUSH state on the *next* cycle. The CPU sees `sfence_done=1` and may resume execution (e.g., write new page tables) before the TLB is actually flushed → stale TLB entries survive the sfence.

**Preconditions**:
- TLB has valid entries (at least 2 entries with ASID=1)
- MMU is in IDLE state (both i and d sides idle)
- `csr_satp.MODE` = Sv32

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `sfence_vma=1` (pulse) |
| 1     | `sfence_vma=0`; Check `sfence_done` |
| 2     | Check `sfence_done`; Check TLB entries |
| 3+    | Attempt lookup for previously-cached VPN |

**Expected**: `sfence_done=0` at Cycle 1 (flush still in progress); `sfence_done=1` only after flush truly completes (Cycle 2 or 3); all TLB entries invalidated

**Actual (buggy)**: `sfence_done=1` at Cycle 1 (same cycle as sfence_pending_r set); TLB still has stale entries at Cycle 1

**Pass Criteria**: `sfence_done` asserts only when `tlb_flush_done=1`; all TLB entries invalid before `sfence_done=1`

---

#### TC_MMU_002: Walk arbiter loses d_walk_req (MMU-6)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-6 |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L573-586 |
| **Objective** | Verify that a d-side walk request is not lost when an i-side walk is being serviced |

**Bug Description**:
In `W_IDLE` state, the walk arbiter checks `pending_i_walk` first. If `pending_i_walk=1`, it starts the i-side walk. If `d_walk_req=1` arrives in the same cycle, it is NOT captured into `pending_d_walk` (the pending_d_walk assignment is gated by `!pending_i_walk` or similar priority logic). The d-side request is lost. If d_state is in `D_WALK_PENDING`, it waits forever.

**Preconditions**:
- TLB empty (both i and d will miss)
- Page table set up for both i-side VPN and d-side VPN
- MMU in IDLE state

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_translate_req=1`, `i_vaddr=0x1000` (miss → triggers i_walk_req) |
| 0     | `d_translate_req=1`, `d_vaddr=0x2000` (miss → triggers d_walk_req simultaneously) |
| 1     | Deassert both requests (level-to-pulse conversion in MMU) |
| 2-N   | Wait for i-side walk to complete |
| N+1   | Check d-side translation result |

**Expected**: Both translations complete; i-side gets PPN for 0x1000, d-side gets PPN for 0x2000

**Actual (buggy)**: i-side walk completes; d-side walk never starts (d_walk_req lost); d_translate_valid never asserts → hang

**Pass Criteria**: `d_translate_valid=1` within expected walk latency; `d_paddr` correct

**Notes**: May need to drive i and d requests on the exact same cycle to trigger the arbiter priority bug. If the MMU converts req to internal pending signals with 1-cycle delay, adjust timing accordingly.

---

#### TC_MMU_003: Non-BRAM fill_asid uses raw satp (MMU-7)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-7 |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L761 |
| **Objective** | Verify TLB fill uses the ASID from the satp value latched at walk start, not the current raw satp |
| **Configuration** | `USE_TLB_BRAM=0` (non-BRAM path only) |

**Bug Description**:
BRAM path latches `satp` at walk start and uses `latched_satp.asid` for TLB fill. Non-BRAM path uses raw `csr_satp.asid` at fill time. If `satp` changes during the walk (e.g., trap to M-mode changes satp, or OS context switch), the TLB entry is filled with the wrong ASID → subsequent lookups with the correct ASID miss, or worse, lookups with the wrong ASID hit.

**Preconditions**:
- `USE_TLB_BRAM=0`
- TLB empty
- Initial `csr_satp` = {Sv32, ASID=1, PTBA=0x80000}
- Page table valid for VPN=0x100 → PPN=0x200

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `d_translate_req=1`, `d_vaddr=0x100000` (VPN=0x100), `csr_satp.ASID=1` |
| 1     | `d_translate_req=0` |
| 2     | (walk in progress) Change `csr_satp.ASID=2` (simulate context switch mid-walk) |
| ...   | Wait for walk to complete and TLB fill |
| N     | Check TLB entry: should have ASID=1 (latched), not ASID=2 (raw) |
| N+1   | Lookup VPN=0x100 with ASID=1 → should hit |
| N+2   | Lookup VPN=0x100 with ASID=2 → should miss |

**Expected**: TLB entry has ASID=1 (latched at walk start); lookup with ASID=1 hits, ASID=2 misses

**Actual (buggy)**: TLB entry has ASID=2 (raw satp at fill time); lookup with ASID=1 misses, ASID=2 hits

**Pass Criteria**: Post-fill lookup with ASID=1 hits with correct PPN

---

#### TC_MMU_004: Non-BRAM PTW uses raw CSR inputs (MMU-8)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-8 |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L1058-1061 |
| **Objective** | Verify PTW permission checks use CSR values latched at walk start, not raw current values |
| **Configuration** | `USE_TLB_BRAM=0` |

**Bug Description**:
Non-BRAM path passes raw `csr_satp`, `csr_priv_mode`, `csr_sum`, `csr_mxr` to PTW. If any CSR changes during the multi-cycle walk, the permission check at walk completion uses the new value, not the value when the translation was requested. This can cause:
- Security leak: U-mode access checked with S-mode privileges (if priv_mode changed mid-walk)
- False fault: SUM bit cleared mid-walk → S-mode U-page access faults incorrectly

**Preconditions**:
- `USE_TLB_BRAM=0`
- Page table: VPN=0x100 → PTE with U=1 (user-accessible), R=1, W=0, X=0
- Initial: `csr_priv_mode=S-mode`, `csr_sum=1` (S-mode can access U pages)

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `d_translate_req=1`, `d_vaddr=0x100000`, `csr_priv_mode=S`, `csr_sum=1` |
| 1     | `d_translate_req=0` |
| 2     | (walk in progress) Change `csr_sum=0` (trap handler modifies mstatus) |
| ...   | Wait for walk to complete |
| N     | Check `d_translate_fault` |

**Expected**: No fault (SUM=1 was active when translation requested → S-mode can access U page)

**Actual (buggy)**: Fault (SUM=0 at walk completion → S-mode denied U page access)

**Pass Criteria**: `d_translate_fault=0` and `d_paddr` correct

---

#### TC_MMU_005: Non-BRAM does not wait for TLB flush (MMU-9)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-9 |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L846-848, L878-881, L772 |
| **Objective** | Verify non-BRAM path waits for TLB flush to complete before resuming translations |
| **Configuration** | `USE_TLB_BRAM=0` |

**Bug Description**:
After `sfence_vma`, the non-BRAM FSM transitions directly back to `NB_IDLE` and re-latches new requests, without waiting for `tlb_flush_done`. The `flush_done` output signal is not connected (line 772). This means:
- New translation can start while TLB is still being flushed
- New fill can write TLB while flush is invalidating entries → race condition
- Stale entries may survive if fill happens during flush

**Preconditions**:
- `USE_TLB_BRAM=0`
- TLB has valid entries
- New translation request pending (different VPN)

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `sfence_vma=1` (pulse) |
| 1     | `sfence_vma=0`; `d_translate_req=1`, `d_vaddr=new_VPN` (immediately request new translation) |
| 2+    | Observe whether translation starts before flush completes |

**Expected**: Translation waits until `tlb_flush_done=1`; no new TLB fills during flush

**Actual (buggy)**: Translation starts immediately at Cycle 1 (FSM back to NB_IDLE); TLB fill may occur during flush → race

**Pass Criteria**: No `tlb_fill_req` asserted while `tlb_flush` is in progress

---

#### TC_MMU_006: Non-BRAM suppresses permission fault during active walk (MMU-10)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-10 |
| **Severity** | MEDIUM |
| **Bug Location** | MMU.sv L1000, L1033 |
| **Objective** | Verify TLB permission faults are reported even when a walk is in progress |
| **Configuration** | `USE_TLB_BRAM=0` |

**Bug Description**:
The non-BRAM path gates permission fault reporting with `!walk_active_r`. If a TLB hit occurs with a permission violation (e.g., writing a read-only page) while a walk is in progress for the other side, the fault is suppressed. The fault is never re-reported (walk_active_r eventually deasserts, but the fault condition is no longer present → silent miss).

**Preconditions**:
- `USE_TLB_BRAM=0`
- TLB has entry for VPN=0x100 → PPN=0x200, PTE.R=1, PTE.W=0 (read-only)
- Trigger a walk on the other side (e.g., i-side miss) to set `walk_active_r=1`

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_translate_req=1`, `i_vaddr=uncached_VPN` (miss → starts walk, sets walk_active_r) |
| 1     | `d_translate_req=1`, `d_vaddr=0x100000`, `d_access_type=STORE` (hit, but write to read-only → fault) |
| 2     | Deassert both |
| ...   | Wait for walk to complete |
| N     | Check if d-side fault was ever reported |

**Expected**: `d_translate_fault=1` with fault cause = Store Page Fault (permission violation)

**Actual (buggy)**: `d_translate_fault=0` (fault suppressed by `!walk_active_r`); fault never re-reported

**Pass Criteria**: `d_translate_fault=1` at Cycle 1 or 2 (while walk is active)

---

#### TC_MMU_007: Non-BRAM walk arbiter doesn't capture misses during active walk (MMU-11)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-11 |
| **Severity** | MEDIUM |
| **Bug Location** | MMU.sv L944-966, L1064 |
| **Objective** | Verify that a TLB miss occurring during an active walk is captured and serviced after the current walk completes |
| **Configuration** | `USE_TLB_BRAM=0` |

**Bug Description**:
When `walk_active_r=1`, new TLB misses are not recorded as pending. The code assumes the miss signal is a level signal that will remain asserted and be re-detected after the walk completes. But if the miss is a pulse (or if the requesting side deasserts its request after detecting "in progress"), the miss is lost.

**Preconditions**:
- `USE_TLB_BRAM=0`
- TLB empty
- Two different VPNs for i-side and d-side

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_translate_req=1`, `i_vaddr=0x1000` (miss → walk starts) |
| 1     | `i_translate_req=0` (pulse request, not level) |
| 2     | `d_translate_req=1`, `d_vaddr=0x2000` (miss → should be captured as pending) |
| 3     | `d_translate_req=0` (pulse) |
| ...   | Wait for i-side walk to complete |
| N     | Check if d-side walk starts automatically |

**Expected**: After i-side walk completes, d-side walk starts automatically (pending miss serviced)

**Actual (buggy)**: d-side miss was not captured; after i-side walk completes, d-side walk does not start → d_translate_valid never asserts → hang

**Pass Criteria**: `d_translate_valid=1` within 2× walk latency

---

#### TC_MMU_008: I-side permission check asymmetry — MXR/SUM missing in non-BRAM (MMU-1)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-1 (from first audit) |
| **Severity** | HIGH |
| **Bug Location** | MMU.sv L252-258 (BRAM) vs L889-892 (non-BRAM) |
| **Objective** | Verify non-BRAM i-side permission check includes MXR and SUM bits |
| **Configuration** | `USE_TLB_BRAM=0` |

**Bug Description**:
BRAM path (lines 252-258) checks MXR (Make eXecutable Readable) and SUM (S-mode User Memory) for i-side permission checks. Non-BRAM path (lines 889-892) omits these checks. This means:
- With MXR=1, S-mode should be able to read X-only pages (for instruction fetch). Non-BRAM path faults.
- With SUM=1, S-mode should be able to access U-mode pages. Non-BRAM path faults on i-side.

**Preconditions**:
- `USE_TLB_BRAM=0`
- Page table: VPN=0x100 → PTE with X=1, R=0, U=1 (execute-only user page)
- `csr_priv_mode=S-mode`, `csr_mxr=1`, `csr_sum=1`

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_translate_req=1`, `i_vaddr=0x100000` (i-fetch from X-only U page) |
| 1     | Deassert |
| ...   | Wait for translation |

**Expected**: No fault (MXR=1 allows S-mode to read X-only pages; SUM=1 allows S-mode to access U pages)

**Actual (buggy)**: Fault (non-BRAM path doesn't check MXR or SUM for i-side)

**Pass Criteria**: `i_translate_fault=0` and `i_paddr` correct

---

### 3.3 MMU Test Summary

| Test ID | Bug | Severity | Config | Cycles | Status |
|---------|-----|----------|--------|--------|--------|
| TC_MMU_001 | MMU-5 | HIGH | Both | ~10 | Pending |
| TC_MMU_002 | MMU-6 | HIGH | Both | ~30 | Pending |
| TC_MMU_003 | MMU-7 | HIGH | Non-BRAM | ~30 | Pending |
| TC_MMU_004 | MMU-8 | HIGH | Non-BRAM | ~30 | Pending |
| TC_MMU_005 | MMU-9 | HIGH | Non-BRAM | ~15 | Pending |
| TC_MMU_006 | MMU-10 | MEDIUM | Non-BRAM | ~30 | Pending |
| TC_MMU_007 | MMU-11 | MEDIUM | Non-BRAM | ~30 | Pending |
| TC_MMU_008 | MMU-1 | HIGH | Non-BRAM | ~30 | Pending |

---

## 4. Integration Unit Tests

### 4.1 DUT Configuration

```
DUT: MMU.sv + ptw.sv + tlb.sv (connected as in core_top.sv)
Mock: bus_bfm (replaces cpu_bus_bridge.sv for PTW AXI transactions)
Mock: csr_mock_drv (drives all CSR inputs)
Monitor: Probe key internal signals for race detection
```

### 4.2 Test Cases

---

#### TC_INT_001: PTW A/D invalidation loses second request (INT-1)

| Field | Value |
|-------|-------|
| **Bug ID** | INT-1 |
| **Severity** | MEDIUM |
| **Bug Location** | core_top.sv L718-725 |
| **Objective** | Verify that two rapid PTW writes (setting A/D bits) both trigger dcache invalidation |

**Bug Description**:
`ptw_ad_inv_pending_r` latches the first PTW write address. If a second PTW write arrives before the first invalidation completes, it is gated by `!ptw_ad_inv_pending_r` and dropped. The dcache line for the second PTE is not invalidated → dcache serves stale PTE data (without A/D bits set).

**Preconditions**:
- Dcache has cached PTE lines
- Two page table entries need A/D bit updates (two different pages accessed for the first time)
- PTW configured to write back A/D bits via AXI

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | Trigger d-side access to page A (first access → PTE A needs A bit set) |
| ...   | PTW walks, writes PTE A with A=1 |
| N     | PTW write A completes, `ptw_ad_inv_pending_r=1` |
| N     | Simultaneously trigger d-side access to page B (first access → PTE B needs A bit set) |
| N+1   | PTW write B arrives while `ptw_ad_inv_pending_r=1` |
| ...   | Wait for invalidation of A to complete |
| M     | Check: was invalidation for B's PTE line also issued? |

**Expected**: Both PTE A and PTE B dcache lines are invalidated

**Actual (buggy)**: Only PTE A's dcache line invalidated; PTE B's line stays cached with stale data (A=0)

**Pass Criteria**: Dcache invalidation issued for both PTE addresses; subsequent reads of PTE B see A=1

**Notes**: This test requires mocking the PTW-to-dcache invalidation interface. May need to probe internal signals of core_top.sv or create a reduced integration testbench.

---

#### TC_INT_002: dcache inv_line without dirty writeback (INT-2)

| Field | Value |
|-------|-------|
| **Bug ID** | INT-2 |
| **Severity** | MEDIUM |
| **Bug Location** | dcache_ctrl.sv L777-820 |
| **Objective** | Verify that dcache invalidation of a dirty line does not lose uncommitted data |

**Bug Description**:
When PTW updates A/D bits in the page table, it writes via AXI to memory. Dcache then invalidates the cache line containing the PTE. If the dcache line is dirty (PTE was written via dcache before PTW's AXI write reached memory), the invalidation discards the dirty line without writeback. The PTW's AXI write may not have reached memory yet → data lost.

**Preconditions**:
- Dcache has a dirty line containing PTE address
- PTW writes to the same address (A/D bit update)
- AXI write from PTW is still in-flight (not yet committed to memory)

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | Write PTE via dcache (make line dirty) |
| 1     | Trigger page table walk that updates A/D bit for same PTE |
| ...   | PTW writes via AXI (in-flight) |
| N     | Dcache receives inv_line for PTE address |
| N+1   | Check: did dcache writeback dirty data before invalidating? |

**Expected**: Dcache writes back dirty line (or defers invalidation until writeback completes); no data loss

**Actual (buggy)**: Dcache invalidates dirty line immediately; if AXI write hasn't reached memory, the dirty data (original PTE) is lost, and only PTW's partial update (A/D bit) reaches memory

**Pass Criteria**: Memory contains correct PTE with both original data and A/D bit set

**Notes**: This may be "by design" (PTW writes the full PTE, so dcache's dirty data is stale). Verify by reading the PTW write logic — if PTW does a read-modify-write of the full PTE, the dcache dirty data is indeed stale and this is not a bug. If PTW only writes A/D bits (partial write), it IS a bug.

---

#### TC_INT_003: PTW bus has no abort mechanism (INT-3)

| Field | Value |
|-------|-------|
| **Bug ID** | INT-3 |
| **Severity** | MEDIUM |
| **Bug Location** | MMU.sv ↔ cpu_bus_bridge.sv interface |
| **Objective** | Verify behavior when MMU deasserts ptw_req during an active AXI transaction |

**Bug Description**:
The PTW-to-bus-bridge interface uses a simple `ptw_req`/`ptw_ready` handshake. If MMU deasserts `ptw_req` mid-transaction (e.g., due to sfence.vma interrupting a walk), the bus bridge has no mechanism to abort the AXI transaction. The AXI AR/AW channel is already committed — the bridge continues waiting for R/B response. If the response arrives, it may be written to TLB fill for a now-invalid translation.

**Preconditions**:
- PTW walk in progress (AXI AR sent, waiting for R)
- sfence.vma arrives mid-walk

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | Trigger translation (miss → walk starts → AXI AR sent) |
| ...   | Wait until AXI AR handshake complete, R not yet received |
| N     | Assert `sfence_vma=1` (should abort walk) |
| N+1   | MMU deasserts `ptw_req` |
| N+2   | bus_bfm delivers AXI R response (late) |
| N+3   | Check: does TLB fill happen with stale data? |

**Expected**: Walk aborted; AXI R response discarded; no TLB fill; TLB flushed by sfence

**Actual (buggy)**: Bus bridge continues AXI transaction; when R arrives, bridge signals ptw_ready with valid PTE; MMU may fill TLB with stale entry (if FSM hasn't fully reset)

**Pass Criteria**: No TLB fill after sfence; bus bridge returns to idle cleanly (no hung AXI)

---

#### TC_INT_004: sfence.vma during active i-side walk (stress)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-5 + MMU-9 combined |
| **Severity** | HIGH |
| **Objective** | Verify sfence.vma correctly aborts an in-progress i-side walk and flushes TLB |

**Preconditions**: i-side walk in progress (multi-cycle PTW)

**Stimulus**: Assert sfence_vma at various points during the walk (parametrized: cycle 1, 2, 3, ... of walk FSM)

**Expected**: Walk aborted; TLB flushed; sfence_done only after flush complete; no stale TLB entries

**Pass Criteria**: For all injection points, post-sfence lookups miss; no X propagation; no hang

---

#### TC_INT_005: sfence.vma during active d-side walk (stress)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-5 + MMU-9 combined |
| **Severity** | HIGH |
| **Objective** | Same as TC_INT_004 but for d-side walk |

---

#### TC_INT_006: Simultaneous i+d miss with sfence (stress)

| Field | Value |
|-------|-------|
| **Bug ID** | MMU-5 + MMU-6 combined |
| **Severity** | HIGH |
| **Objective** | Verify behavior when i-side and d-side both miss, walk starts, then sfence arrives |

**Stimulus**:

| Cycle | Action |
|-------|--------|
| 0     | `i_translate_req=1`, `d_translate_req=1` (both miss) |
| 1     | Deassert both |
| 2     | `sfence_vma=1` (interrupt walk) |
| 3     | `sfence_vma=0` |
| ...   | Wait for sfence_done |
| N     | Re-issue both translation requests |

**Expected**: Both walks aborted; TLB flushed; sfence_done after flush; re-issued translations walk correctly

**Pass Criteria**: No hang; no stale entries; both translations complete after re-issue

---

### 4.3 Integration Test Summary

| Test ID | Bug | Severity | Cycles | Status |
|---------|-----|----------|--------|--------|
| TC_INT_001 | INT-1 | MEDIUM | ~50 | Pending |
| TC_INT_002 | INT-2 | MEDIUM | ~40 | Pending |
| TC_INT_003 | INT-3 | MEDIUM | ~30 | Pending |
| TC_INT_004 | MMU-5+9 | HIGH | ~30×N | Pending |
| TC_INT_005 | MMU-5+9 | HIGH | ~30×N | Pending |
| TC_INT_006 | MMU-5+6 | HIGH | ~40 | Pending |

---

## 5. Coverage Gap Tests

These tests address coverage gaps identified in the audit, not specific bugs.

### 5.1 Permission/Privilege Tests

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC_COV_001 | U-mode instruction fetch from S-only page → fault | P1 |
| TC_COV_002 | U-mode data load from S-only page → fault | P1 |
| TC_COV_003 | U-mode data store to read-only page → fault | P1 |
| TC_COV_004 | S-mode with SUM=0 access U page → fault | P1 |
| TC_COV_005 | S-mode with SUM=1 access U page → success | P1 |
| TC_COV_006 | S-mode with MXR=1 read X-only page → success | P1 |
| TC_COV_007 | M-mode translation (paging disabled) → identity | P1 |
| TC_COV_008 | Access type: load from X-only page → fault | P1 |
| TC_COV_009 | Access type: store to X-only page → fault | P1 |
| TC_COV_010 | Access type: i-fetch from R-only page → fault | P1 |

### 5.2 TLB Replacement Stress

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC_COV_011 | Fill all 16 entries, then access 17th → eviction | P2 |
| TC_COV_012 | Touch all 4 ways of one set, verify PLRU eviction order | P2 |
| TC_COV_013 | Working set > 16 pages, verify thrashing behavior | P2 |
| TC_COV_014 | ASID mismatch → miss even with matching VPN | P2 |
| TC_COV_015 | Global bit (G=1) entries survive ASID change | P2 |

### 5.3 Megapage Tests

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC_COV_016 | 4MB megapage (level-1 leaf) translation → correct PPN | P2 |
| TC_COV_017 | Megapage A/D bit update → PTW writes level-1 PTE | P2 |
| TC_COV_018 | Mixed megapage + regular page in same address space | P2 |
| TC_COV_019 | Megapage permission check (U, X, R, W bits) | P2 |

### 5.4 Edge Case Tests

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC_COV_020 | VPN = 0x0 (lowest address) translation | P2 |
| TC_COV_021 | VPN = 0x3FFFFF (highest Sv32 VPN) translation | P2 |
| TC_COV_022 | Misaligned PTE (PTE address not 4-byte aligned) → fault | P3 |
| TC_COV_023 | Invalid PTE (R=0, W=1) → page fault | P2 |
| TC_COV_024 | Leaf PTE at level 0 with reserved bits set → fault | P3 |
| TC_COV_025 | satp.MODE = 0 (bare) → no translation, identity mapping | P2 |

### 5.5 PTW Error Handling

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC_COV_026 | AXI read error (SLVERR) during walk → translation fault | P1 |
| TC_COV_027 | AXI read timeout (no R response) → hang detection? | P1 |
| TC_COV_028 | AXI decode error (DECERR) during walk → translation fault | P1 |

---

## 6. Test Execution Plan

### 6.1 Priority Order

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | TC_TLB_001-003, TC_MMU_001-002, TC_INT_004-006 | CRITICAL + HIGH bugs that cause silent data corruption or hangs |
| **P1** | TC_TLB_004, TC_MMU_003-008, TC_INT_001-003, TC_COV_001-010, TC_COV_026-028 | HIGH bugs + permission coverage + error handling |
| **P2** | TC_TLB_005-007, TC_COV_011-025 | TLB replacement, megapage, edge cases |
| **P3** | TC_COV_022, TC_COV_024 | Rare edge cases, low probability |

### 6.2 Configuration Matrix

| Configuration | Tests |
|---------------|-------|
| `USE_TLB_BRAM=1` | TC_TLB_*, TC_MMU_001-002, TC_INT_*, TC_COV_* |
| `USE_TLB_BRAM=0` | TC_MMU_003-008 (non-BRAM specific), re-run TC_MMU_001-002, TC_INT_* |

### 6.3 Estimated Effort

| Phase | Tests | Effort |
|-------|-------|--------|
| Testbench infrastructure | — | 3-5 days (clk/rst, BFM, scoreboard, ref models) |
| P0 tests (CRITICAL+HIGH) | 11 | 2-3 days |
| P1 tests (HIGH+permissions) | 18 | 2-3 days |
| P2 tests (coverage) | 15 | 2-3 days |
| P3 tests (edge cases) | 2 | 0.5 day |
| **Total** | **46** | **~10-14 days** |

---

## 7. Reference Models

### 7.1 Golden TLB Model (`ref_tlb_model`)

```
Structure: simple array of 16 entries
  - entry[i] = {valid, asid, vpn, ppn, perm_bits, global}
Operations:
  - lookup(vpn, asid, side): linear scan, return first match
  - fill(vpn, asid, ppn, perm, global): find empty slot or evict LRU
  - flush(): invalidate all entries
  - flush_asid(asid): invalidate entries matching asid (if supported)
No timing — purely functional, immediate response
```

### 7.2 Golden MMU Model (`ref_mmu_model`)

```
Structure: software Sv32 page walker
Operations:
  - translate(vaddr, access_type, priv_mode, sum, mxr, satp):
    1. If satp.MODE == 0: return vaddr (bare)
    2. ptba = satp.PPN << 12
    3. for level = 1 downto 0:
         pte = read_memory(ptba + (vpn[level] << 2))
         if pte.V == 0 or (pte.R == 0 and pte.W == 1): return FAULT
         if pte.R == 1 or pte.X == 1: // leaf
           check_permissions(pte, access_type, priv_mode, sum, mxr)
           update_ad_bits(pte, access_type)
           return (pte.PPN << 12) | offset
         else: // non-leaf
           ptba = pte.PPN << 12
    4. return FAULT (no leaf found)
No timing — purely functional
```

---

## 8. Appendix: Bug-to-Test Traceability

| Bug ID | Severity | Test Case(s) | Component |
|--------|----------|-------------|-----------|
| TLB-1 | CRITICAL | TC_TLB_001, TC_TLB_005 | tlb.sv |
| TLB-2 | CRITICAL | TC_TLB_002 | tlb.sv |
| TLB-3 | CRITICAL | TC_TLB_003 | tlb.sv |
| TLB-4 | HIGH | TC_TLB_004 | tlb.sv |
| MMU-1 | HIGH | TC_MMU_008 | MMU.sv |
| MMU-5 | HIGH | TC_MMU_001, TC_INT_004-006 | MMU.sv |
| MMU-6 | HIGH | TC_MMU_002, TC_INT_006 | MMU.sv |
| MMU-7 | HIGH | TC_MMU_003 | MMU.sv |
| MMU-8 | HIGH | TC_MMU_004 | MMU.sv |
| MMU-9 | HIGH | TC_MMU_005, TC_INT_004-005 | MMU.sv |
| MMU-10 | MEDIUM | TC_MMU_006 | MMU.sv |
| MMU-11 | MEDIUM | TC_MMU_007 | MMU.sv |
| INT-1 | MEDIUM | TC_INT_001 | core_top.sv |
| INT-2 | MEDIUM | TC_INT_002 | dcache_ctrl.sv |
| INT-3 | MEDIUM | TC_INT_003 | MMU↔bus_bridge |

---

## 9. Appendix: Key Signal Cross-Reference

| Signal | File | Line(s) | Context |
|--------|------|---------|---------|
| `d_lookup_valid_r` | tlb.sv | L166, L435-440 | D-side lookup in progress flag |
| `i_lookup_valid_r` | tlb.sv | L427-432 | I-side lookup in progress flag |
| `sfence_pending_r` | MMU.sv | L541-551 | SFENCE in progress |
| `sfence_done` | MMU.sv | L541-551 | SFENCE completion (premature) |
| `walk_active_r` | MMU.sv | L944-966, L1000 | Walk in progress flag |
| `pending_i_walk` | MMU.sv | L573-586 | I-side walk pending flag |
| `pending_d_walk` | MMU.sv | L573-586 | D-side walk pending flag |
| `fill_asid` | MMU.sv | L761 | ASID used for TLB fill |
| `ptw_ad_inv_pending_r` | core_top.sv | L718-725 | PTW A/D invalidation pending |
| `flush_done` (unconnected) | MMU.sv | L772 | TLB flush done (non-BRAM, unused) |

---

*End of document. 46 test cases planned covering 14 confirmed bugs + 28 coverage gap tests.*
