# A Extension RTL Audit

Date: 2026-06-22

Scope: `dev/rtl/core/` A-extension implementation (`LR.W`, `SC.W`, `AMOSWAP.W`, `AMOADD.W`, `AMOAND.W`, `AMOOR.W`, `AMOXOR.W`, `AMOMIN.W`, `AMOMAX.W`, `AMOMINU.W`, `AMOMAXU.W`)

Goal: identify RTL issues that can break Linux or violate RV32A architectural behavior.

## Summary

The current RTL decodes the RV32A instructions and executes the arithmetic part of AMOs, but there are still architectural gaps:

1. `aq` / `rl` ordering bits are decoded but not implemented anywhere.
2. LR/SC and AMO are executed as a plain read followed by a plain write, with no lock/exclusive mechanism on the memory system interface.
3. An intervening AMO does not clear the LR reservation, contradicting both the spec intent and the existing ISA test source comments.
4. Existing A-extension tests do not cover `aq` / `rl` semantics, and the implemented reservation behavior appears inconsistent with the intended ISA test cases.

These are meaningful Linux risks because kernel spinlocks and atomic primitives rely on `aq` / `rl` ordering and on correct LR/SC reservation semantics.

## Findings

### 1. High: `aq` / `rl` bits are decoded and propagated, but never implemented

Evidence:

- `cpu_decode.sv` decodes the ordering bits from the instruction:
  - `amo_aq = inst[26]`
  - `amo_rl = inst[25]`
  - See `dev/rtl/core/cpu_decode.sv:230-234`.
- `cpu_execute.sv` forwards them through the pipeline bus:
  - `dev/rtl/core/cpu_execute.sv:124-130`
- `cpu_mem.sv` receives them:
  - `dev/rtl/core/cpu_mem.sv:91-96`
- After that, there is no functional use of `amo_aq` or `amo_rl` anywhere in the RTL:
  - `rg -n '\bamo_aq\b|\bamo_rl\b' dev/rtl/core -S`

Impact:

- Linux lock/unlock and atomic memory-ordering primitives depend on acquire/release semantics.
- With the current implementation, `amoswap.w.aq`, `amoswap.w.rl`, `lr.w.aq`, `sc.w.rl`, etc. behave the same as the unordered forms.
- This can break spinlock ordering, leading to hangs or data-structure corruption even if the arithmetic result of the atomic instruction itself is correct.

Assessment:

- Severity: High
- Linux relevance: High

### 2. High: LR/SC and AMO are implemented as separate read and write operations, without any memory-system exclusivity

Evidence:

- `cpu_mem.sv` issues AMO/LR/SC as a read phase first:
  - `MEM_AMO_READ` request setup at `dev/rtl/core/cpu_mem.sv:239-262`
- `SC.W` success then issues a later write phase:
  - `dev/rtl/core/cpu_mem.sv:369-380`
- Other AMOs also compute after the load and then issue a later write:
  - `dev/rtl/core/cpu_mem.sv:390-399`
- The bus master does not assert any lock/exclusive mechanism:
  - `arlock <= AXI_LOCK_NORMAL` at `dev/rtl/core/cpu_bus_bridge.sv:480-487`
  - `awlock <= AXI_LOCK_NORMAL` appears throughout the bridge, e.g. `dev/rtl/core/cpu_bus_bridge.sv:553`, `:705`, `:834`

Impact:

- The core performs a software-style read-modify-write sequence, not an architecturally protected atomic transaction.
- In a system with any competing writer outside the hart pipeline, another agent can modify the location between the read and write phases.
- Even in a single-hart system, this means the implementation is relying entirely on the local reservation bit instead of any memory-side exclusivity.

Assessment:

- Severity: High
- Linux relevance: Medium to High
- Note: if the platform truly has no competing memory masters, this reduces the practical exposure, but it is still not a complete RV32A implementation.

### 3. High: An intervening AMO does not invalidate the LR reservation

Evidence:

- Normal stores explicitly clear the reservation:
  - `lr_reservation_valid <= 1'b0;`
  - `dev/rtl/core/cpu_mem.sv:341-352`
- Trap entry also clears the reservation:
  - `dev/rtl/core/cpu_mem.sv:223-226`
- `SC.W` clears the reservation before testing success:
  - `dev/rtl/core/cpu_mem.sv:369-373`
- But plain AMO execution does not clear the reservation on completion:
  - AMO writeback path at `dev/rtl/core/cpu_mem.sv:404-420`
  - No `lr_reservation_valid <= 1'b0` in that path

Why this matters:

- The repository's own ISA test source explicitly expects AMO to invalidate an LR reservation:
  - `dev/program_source/test/isa/a_ext.s:294-304`
  - `dev/program_source/test/isa/a_ext.s:1050-1060`
- The RTL does not implement that behavior.

Impact:

- Sequence `lr.w; amoadd.w same_addr; sc.w same_addr` can incorrectly allow the `SC.W` to succeed.
- This is a direct semantic bug in reservation handling.

Assessment:

- Severity: High
- Linux relevance: Medium

### 4. Medium: Reservation tracking is purely local and only address-based

Evidence:

- Reservation state is just:
  - `lr_reservation_addr`
  - `lr_reservation_valid`
  - `dev/rtl/core/cpu_mem.sv:114-116`
- `SC.W` success is decided only by:
  - `lr_reservation_valid && (lr_reservation_addr == alu_result)`
  - `dev/rtl/core/cpu_mem.sv:180-181`

Impact:

- There is no visibility of external invalidation events.
- There is no reservation granule model beyond exact address equality.
- This is closely related to Finding 2, but worth calling out separately because the success criterion is purely local state.

Assessment:

- Severity: Medium
- Linux relevance: Medium

### 5. Medium: Existing A-extension tests do not cover `aq` / `rl` behavior

Evidence:

- The dedicated testbench exists:
  - `dev/tb/tb_isa_a_ext.sv`
- The ISA assembly includes many functional LR/SC/AMO tests:
  - `dev/program_source/test/isa/a_ext.s`
- But no `.aq`, `.rl`, or `.aqrl` forms are present in the current A-extension ISA test source:
  - `rg -n '\.aq|\.rl|aqrl|fence' dev/program_source/test/isa/a_ext.s dev/tb/tb_isa_a_ext.sv -S`
  - No matches

Impact:

- The current test collateral can validate arithmetic/dataflow behavior while still missing the ordering bug that matters for Linux spinlocks and atomic synchronization.

Assessment:

- Severity: Medium
- Linux relevance: High as a validation gap

## Non-findings

- Decode coverage for the word-sized RV32A instruction set looks structurally correct:
  - `LR.W`, `SC.W`, and the expected `.W` AMOs are decoded in `dev/rtl/core/cpu_decode.sv:236-246`
- Misaligned AMO detection exists and distinguishes LR from store/AMO-style misalign reporting:
  - `dev/rtl/core/cpu_mem.sv:154-156`
  - `dev/rtl/core/cpu_mem.sv:459-464`
- AMO result selection itself looks plausible for the supported operations:
  - `dev/rtl/core/cpu_mem.sv:161-176`

## Bottom Line

The A-extension implementation is not complete enough to trust for Linux synchronization primitives yet.

The most important bug is not the arithmetic of AMOs. It is the missing memory-ordering semantics:

- `aq` / `rl` are ignored
- AMO/LR/SC are not protected by any exclusive/locked memory transaction
- reservation invalidation is incomplete

If Linux is hanging around `printk`, spinlock or atomic-ordering failures remain a credible RTL root cause.
