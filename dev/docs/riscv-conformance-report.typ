#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 2.5cm),
  numbering: "1",
)
#set text(
  font: "New Computer Modern",
  size: 11pt,
)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#set document(title: [SimpleCPU RISC-V M-Level Conformance Report])

#align(center)[
  #text(size: 20pt, weight: "bold")[
    SimpleCPU RISC-V Privileged Specification\
    Conformance Report (Machine-Level Only)
  ]
  #v(0.5em)
  #text(size: 11pt)[
    Reference Spec: RISC-V Privileged Architecture, Version 20260120\
    Date: #datetime.today().display()
  ]
]

#v(1.5em)

= Executive Summary

This report evaluates the SimpleCPU implementation against the RISC-V Privileged Specification (Version 20260120), restricted to Machine (M) privilege level only. The analysis compares the specification document (`dev/docs/core/riscv-privileged.md`), the design report (`dev/docs/simpleCPU-design-report.md`), and the actual RTL implementation (`dev/rtl/core/cpu_csr.v`, `dev/rtl/core/cpu_clint.v`).

*Key findings:*

- *2 severe bugs* that break software correctness (MRET behavior, interrupt priority)
- *7 missing mandatory CSRs* that cause illegal-instruction exceptions on standard software
- *4 missing timer/counters CSRs*
- *3 CSRs lack WARL constraints*, allowing software to set invalid register states
- *Multiple minor deviations* from the specification

= Severe Bugs

== BUG-1: MRET Behavior Incorrect

*Location:* `dev/rtl/core/cpu_clint.v` (line 75)

*Spec requirement (Section 3.1.6):*
MRET must perform:
- `MIE ← MPIE` (restore MIE from saved MPIE)
- `MPIE ← 1` (set MPIE to 1)
- `MPP ← 2'b11` (set MPP to M-mode, since U-mode is not implemented)

*Actual RTL behavior:*
- `MIE ← 1` (hardcoded to 1, ignoring saved MPIE)
- `MPIE ← old_MPIE` (preserves old MPIE instead of setting to 1)
- `MPP ← 2'b00` (sets MPP to U-mode, which does not exist)

*Impact:* MIE and MPIE are swapped. After MRET, interrupts are unconditionally enabled regardless of the pre-trap state, and MPIE is corrupted. MPP is set to a non-existent privilege level. This breaks any software that relies on nested interrupt handling or conditional interrupt re-enable after MRET.

*Fix:*
```verilog
// Before (WRONG):
r_mstatus[3]   <= 1'b1;            // MIE ← 1
r_mstatus[7]   <= r_mstatus[7];    // MPIE ← MPIE
r_mstatus[12:11] <= 2'b00;         // MPP ← U-mode

// After (CORRECT per spec):
r_mstatus[3]   <= r_mstatus[7];    // MIE ← MPIE
r_mstatus[7]   <= 1'b1;            // MPIE ← 1
r_mstatus[12:11] <= 2'b11;         // MPP ← M-mode
```

== BUG-2: Interrupt Priority Reversed

*Location:* `dev/rtl/core/cpu_clint.v` (lines 51-53)

*Spec requirement (Section 3.1.9):*
Priority order: External (MEI) > Software (MSI) > Timer (MTI)

*Actual RTL behavior:*
Priority order: Software (MSI) > Timer (MTI) > External (MEI)

*Impact:* When multiple interrupts are pending simultaneously, the wrong interrupt is serviced. For example, if both MEI and MSI are pending, the spec requires MEI to be taken first, but the RTL takes MSI first. This breaks software that relies on the standard priority ordering.

*Fix:* Reverse the priority comparison logic in the CLINT to match `MEI > MSI > MTI`.

= Missing Mandatory CSRs

The following CSRs are required by the RISC-V Privileged Specification for a M-level-only implementation but are not implemented. Accessing any of them triggers an illegal-instruction exception.

== Identity and Configuration CSRs

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 8pt,
  [*CSR*], [*Address*], [*Required By*], [*Purpose*],
  [`misa`], [0x301], [Section 3.1.1], [Reports ISA extensions supported by the hart],
  [`mvendorid`], [0xF11], [Section 3.1.2], [Vendor ID of the implementation],
  [`marchid`], [0xF12], [Section 3.1.2], [Architecture ID of the implementation],
  [`mimpid`], [0xF13], [Section 3.1.2], [Implementation version/revision ID],
  [`mhartid`], [0xF14], [Section 3.1.2], [Hardware thread ID],
  [`mconfigptr`], [0xF15], [Section 3.1.2], [Pointer to configuration data structure],
  [`mstatush`], [0x310], [Section 3.1], [Upper 32 bits of mstatus (RV32)],
)

*Impact:* Standard RISC-V software (bootloaders, OS kernels, compliance tests) reads these CSRs at startup. Accessing them causes illegal-instruction traps, preventing such software from running.

*Recommended fix:* Implement these as hardwired read-only registers:
- `misa`: encode supported extensions (e.g., RV32I = `0x01000100`)
- `mvendorid`, `marchid`, `mimpid`: return 0 for open-source implementations
- `mhartid`: return 0 for single-hart systems
- `mconfigptr`: return 0 (no configuration structure)
- `mstatush`: return 0 (no upper bits used)

== Timer and Counter CSRs

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 8pt,
  [*CSR*], [*Address*], [*Required By*], [*Purpose*],
  [`mcycle`], [0xB00], [Section 3.1.1], [Cycle count (lower 32 bits)],
  [`minstret`], [0xB02], [Section 3.1.1], [Instruction retire count (lower 32 bits)],
  [`mcycleh`], [0xB80], [Section 3.1.1], [Cycle count (upper 32 bits)],
  [`minstreth`], [0xB82], [Section 3.1.1], [Instruction retire count (upper 32 bits)],
)

*Impact:* Performance profiling and timing loops cannot function. The Zicntr extension mandates these registers.

= WARL Constraint Violations

WARL (Write Any value, Read Legal value) constraints ensure that CSR writes that set invalid field values silently map to a legal value instead. The current RTL passes `sw_csr_wdata` directly to the CSR register without any masking or field enforcement.

== mstatus Not WARL

*Location:* `dev/rtl/core/cpu_csr.v` — `r_mstatus <= sw_csr_wdata`

The following fields should be hardwired to 0 in an M-only system (no S-mode, no FPU, no VS):

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 8pt,
  [*Field*], [*Bits*], [*Reason*],
  [SIE], [1], [No S-mode → no S-level interrupts],
  [SPIE], [5], [No S-mode],
  [SPP], [8], [No S-mode],
  [MPP], [12:11], [Must be 2'b11 (M-mode only); currently accepts any value],
  [MPRV], [17], [No S-mode → MPRV has no effect],
  [SUM], [18], [No S-mode],
  [MXR], [19], [No S-mode],
  [TVM], [20], [No S-mode],
  [TW], [21], [No S-mode],
  [TSR], [22], [No S-mode],
  [FS], [14:13], [No FPU → must be 00],
  [VS], [10:9], [No V-extension → must be 00],
  [XS], [16:15], [No extensions with status → must be 00],
  [SD], [31], [Read-only, derived from FS/VS/XS → must be 0],
)

*Fix:* Apply a mask on write: only MIE (bit 3) and MPIE (bit 7) are writable; all other bits are hardwired to their legal values.

== mie Not WARL

*Location:* `dev/rtl/core/cpu_csr.v` — `r_mie <= sw_csr_wdata`

Without S-mode, the S-level interrupt enable bits should be hardwired to 0:

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 8pt,
  [*Field*], [*Bits*], [*Reason*],
  [SSIE], [1], [No S-mode],
  [STIE], [5], [No S-mode],
  [SEIE], [9], [No S-mode],
)

Only MEIE (bit 11), MSIE (bit 3), and MTIE (bit 7) should be writable.

== mtvec Not WARL

*Location:* `dev/rtl/core/cpu_csr.v` — `r_mtvec <= sw_csr_wdata`

Two violations:

+ *BASE field (bits 31:2)* must be 4-byte aligned. Software can write an unaligned BASE, and the hardware will use it as-is, potentially jumping to a misaligned address on trap entry.
+ *MODE field (bits 1:0)* should only accept values 0 (Direct) or 1 (Vectored). The RTL only implements Direct mode, but software can set MODE=1 (Vectored) and the register will accept it, even though vectored dispatch is not actually implemented.

*Fix:* Mask BASE to 4-byte alignment on write; force MODE to 0 if hardware only supports Direct mode, or accept 0/1 and mask other values.

== mepc Not Masked

*Location:* `dev/rtl/core/cpu_csr.v` — `r_mepc <= sw_csr_wdata`

With IALIGN=32, the low 2 bits of mepc must always be 0. The RTL allows software to set these bits to non-zero values. While this is a minor issue (mepc is primarily written by hardware on trap entry, where it is naturally aligned), it violates the spec's WARL requirement.

= Missing Exception Types

The RTL only handles a subset of exception codes in mcause. The following standard exception types are not recognized:

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  inset: 8pt,
  [*Code*], [*Name*], [*Description*],
  [1], [Instruction access fault], [Fault during instruction fetch],
  [5], [Load access fault], [Fault during load operation],
  [7], [Store/AMO access fault], [Fault during store operation],
)

*Impact:* If these faults occur (e.g., bus error), the hardware cannot report the correct exception code. This is a functional gap for systems with bus error signals.

= WFI Not Implemented

The WFI (Wait For Interrupt) instruction is not implemented. The spec requires that WFI be treated as a NOP at minimum in M-mode (i.e., it must not cause an illegal-instruction exception). Currently, WFI triggers an illegal-instruction trap.

*Fix:* Decode WFI and execute as NOP (or implement actual wait-for-interrupt if desired).

= Conforming Items

The following aspects of the implementation correctly conform to the RISC-V Privileged Specification:

+ *mstatus bit layout*: MIE at bit 3, MPIE at bit 7, MPP at bits 12:11 — matches spec
+ *Trap entry behavior*: MPIE ← MIE, MIE ← 0, MPP ← M — correct
+ *mip hardware-driven bits*: MEIE/MSIE/MTIE bits are read-only (written only by CLINT) — correct
+ *medeleg/mideleg absent*: Correctly not implemented (M-only system)
+ *mcounteren absent*: Correctly not implemented (M-only system)
+ *CSR address validity check*: Accessing unimplemented CSR addresses triggers illegal-instruction — correct
+ *ECALL mcause code*: 11 (Environment call from M-mode) — correct
+ *EBREAK mcause code*: 3 (Breakpoint) — correct
+ *Illegal instruction mcause code*: 2 — correct
+ *Reset values*: All CSRs reset to zero — acceptable (spec allows implementation-defined for most)
+ *mtvec Direct mode*: Trap vector = BASE, all exceptions go to same address — correct
+ *8 implemented CSRs*: mstatus(0x300), mie(0x304), mtvec(0x305), mscratch(0x340), mepc(0x341), mcause(0x342), mtval(0x343), mip(0x344) — all at correct addresses

= Summary Table

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  inset: 8pt,
  [*ID*], [*Severity*], [*Category*], [*Description*],
  [BUG-1], [#text(fill: red)[*Severe*]], [Logic], [MRET: MIE/MPIE swapped, MPP set to U-mode],
  [BUG-2], [#text(fill: red)[*Severe*]], [Logic], [Interrupt priority reversed (MSI>MTI>MEI, should be MEI>MSI>MTI)],
  [MISS-1], [#text(fill: orange)[*Important*]], [Missing CSR], [misa (0x301) not implemented],
  [MISS-2], [#text(fill: orange)[*Important*]], [Missing CSR], [mvendorid/marchid/mimpid/mhartid/mconfigptr not implemented],
  [MISS-3], [#text(fill: orange)[*Important*]], [Missing CSR], [mstatush (0x310) not implemented],
  [MISS-4], [#text(fill: orange)[*Important*]], [Missing CSR], [mcycle/minstret/mcycleh/minstreth not implemented],
  [WARL-1], [#text(fill: orange)[*Important*]], [WARL], [mstatus: S-level/FS/VS/XS/SD/MPP fields not constrained],
  [WARL-2], [#text(fill: eastern)[*Minor*]], [WARL], [mie: S-level interrupt enable bits not constrained],
  [WARL-3], [#text(fill: eastern)[*Minor*]], [WARL], [mtvec: BASE alignment and MODE not constrained],
  [WARL-4], [#text(fill: eastern)[*Minor*]], [WARL], [mepc: low 2 bits not masked to 0],
  [EXC-1], [#text(fill: eastern)[*Minor*]], [Exception], [Missing exception codes: 1, 5, 7],
  [WFI-1], [#text(fill: eastern)[*Minor*]], [Instruction], [WFI not implemented (should be NOP at minimum)],
)

= Recommended Fix Priority

+ *Priority 1 — Severe:* Fix BUG-1 (MRET) and BUG-2 (interrupt priority). These break fundamental trap handling semantics and will cause immediate failures on any non-trivial software.

+ *Priority 2 — Important:* Implement missing identity CSRs (misa, mvendorid, etc.) as hardwired read-only registers. This is low effort and unblocks standard software.

+ *Priority 3 — Important:* Add WARL constraints to mstatus. This prevents software from putting the hart into an inconsistent state.

+ *Priority 4 — Important:* Implement mcycle/minstret counters. Required by Zicntr extension.

+ *Priority 5 — Minor:* Add WARL constraints to mie, mtvec, mepc. Add missing exception codes. Implement WFI as NOP.
