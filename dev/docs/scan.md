# RTL Code Audit Scan Report

**Date**: 2026-06-21
**Goal**: Full RTL audit to find root cause of Linux kernel hang on FPGA
**Symptom**: Kernel prints 4 console-handoff lines (ttyS0 enabled + uart8250 disabled x2) at 23s timestamp, then hangs. QEMU reaches same point at 0.476s.
**Rule**: READ-ONLY scan. No code changes.

---

## Already Confirmed (Prior Audit)

### UART THRE Bug — FIXED
- **File**: `dev/rtl/APB/perips/uart16550/uart_regs_16550a.sv:349`
- **Status**: `thre_set_en = (tstate == 3'd0)` — correct, not `1'b1`
- **Impact**: No longer a root cause

### DTS Configuration — CORRECT
- **File**: `boot/dts/simplecpu.dts`
- UART base: `0x10008000`, `reg-shift = <2>`, `reg-io-width = <4>`
- `earlycon=uart8250,mmio32,0x10008000,230400n8`
- `timebase-frequency = <100000000>` (100MHz)
- `riscv,isa = "rv32ima_zicsr_zifencei"`, `mmu-type = "riscv,sv32"`
- Memory: 128MB @ 0x80000000, reserved 0x80000000~0x803FFFFF for OpenSBI

### CLINT — On sys_clk Domain
- **File**: `dev/rtl/axi/axi4lite_clint.sv`, `dev/rtl/system_top.sv:1680`
- mtime increments at sys_clk rate, Gray-code 2-stage sync to cpu_clk
- MTIP = `(mtime >= mtimecmp)` — level-triggered
- WSTRB-aware writes, mtime write pauses self-increment 1 cycle

### CPU CSR — rdtime & mcounteren
- **File**: `dev/rtl/core/cpu_csr.sv`
- `ADDR_TIME` → `ext_mtime[31:0]` (line 667)
- `ADDR_TIMEH` → `ext_mtime[63:32]` (line 670)
- `mcounteren` check: U-mode `r_mcounteren[counter_idx]` (line 391), S-mode additional `r_scounteren` (line 392)
- `mip` rebuild every cycle from `ext_mtip`, `r_sip`, `ext_seip`, `ext_msip` (line 516)

### SoC Address Map
- DDR3: 0x80000000 (128MB), Boot ROM: 0xFC000000, PLIC: 0x0C000000, CLINT: 0x02000000
- APB Bridge: 0x10000000 (UART@0x10008000, GPIO@0x10000000)
- Sys Status: 0x04000000

---

## Audit Results (6 Parallel Subagents)

---

### 1. Timer/CLINT/rdtime Audit — NO CRITICAL BUGS

**Verdict: PASS (all items)**

| Item | Verdict | Key Evidence |
|------|---------|-------------|
| A. rdtime frequency | **PASS** | sys_clk=100MHz (`cpu.xdc:326`) = DTS 100MHz. No mismatch. |
| B. mtimecmp 64-bit write | **PASS** | Split registers + WSTRB masking (`axi4lite_clint.sv:222-258`) |
| C. MTIP → mip.MTIP | **PASS** | 2-stage sync, read-only MTIP, writable STIP (`cpu_csr.sv:208,516,550-561`) |
| D. STIP injection | **PASS** | Mechanism correct; STIP doesn't auto-clear (software responsibility) |
| E. mcounteren.TM | **PASS** | `cpu_csr.sv:387-392,325` — proper gating |
| F. CDC | **PASS** | Gray-code 2-stage sync (`system_top.sv:379-426`) |
| G. Timer interrupt delivery | **PASS** | Correct causes, priority, delegation (`cpu_clint.sv:79-152`) |
| H. 23s anomaly | **CONCERN** | 23s is expected (50MHz FPGA vs multi-GHz QEMU); hang cause is elsewhere |

**Conclusion**: Timer subsystem is architecturally sound. STIP fix is correctly implemented. 23s timestamp is expected slowdown, not a bug. The hang is caused by something else.

---

### 2. PLIC Audit — **ROOT CAUSE FOUND**

**Verdict: BUG (CRITICAL) — DTS/RTL context mismatch**

#### BUG-PLIC-1 (CRITICAL): DTS interrupts-extended does not match RTL PLIC context numbering

- **File**: `boot/dts/simplecpu.dts:126`
- **Issue**: `interrupts-extended = <&cpu0_intc 9>` declares **only 1 context** (S-mode SEI at index 0). Linux PLIC driver uses the index in `interrupts-extended` as the PLIC context number for MMIO. With only one entry at index 0, Linux programs **PLIC context 0** for S-mode.
- **RTL**: `system_top.sv:854-855` — PLIC context 0 drives **MEIP** (M-mode), context 1 drives **SEIP** (S-mode).
- **Impact**: 
  1. Linux enables UART (source 2) in PLIC **context 0** enable register (0x0C002000).
  2. UART IRQ fires → PLIC context 0 pending → `o_eip[0]` → **MEIP** (not SEIP).
  3. `mideleg[11]` is hardwired 0 (`cpu_csr.sv:432`: mask `0x0000_0222`), so MEI traps to **M-mode (OpenSBI)**.
  4. OpenSBI receives MEI but has no PLIC M-mode context handler → spins on unclaimed MEIP.
  5. MEIP stays asserted → **immediate re-trap → infinite loop → HANG**.
- **This matches the symptom exactly**: kernel prints 4 earlycon polling lines, enables interrupts, UART TX/RX fires, traps to M-mode, hangs.
- **Required Fix**: DTS should be `interrupts-extended = <&cpu0_intc 11>, <&cpu0_intc 9>;` (context 0=M-mode, context 1=S-mode, matching RTL).

#### Other PLIC findings (all PASS):
- Claim/Complete mechanism: **PASS** (`axi4lite_plic.sv:176-199,311-324,299-302`)
- Source mapping (UART=2): **PASS** (`system_top.sv:1640`, `simplecpu.dts:147`)
- Level-triggered: **PASS** (`axi4lite_plic.sv:266-274`)
- Priority: **PASS** (`axi4lite_plic.sv:192,259`)
- MMIO access: **PASS** (`system_top.sv:1006`, `axi4lite_plic.sv:138-154`)

#### CONCERN-PLIC-1: S-mode interrupt delegation not checked in cpu_clint.sv
- **File**: `dev/rtl/core/cpu_clint.sv:130`
- `s_int_taken` does not check `mideleg[9]`. Per spec, if `mideleg[9]=0`, SEI should trap to M-mode. This code always takes S-mode interrupts in S-mode. Latent bug, no active impact when OpenSBI sets `mideleg[9]=1`.

---

### 3. Trap Delegation/mret/sret Audit — 4 BUGS

**Verdict: PASS with 4 bugs (2 medium, 2 low)**

| Item | Verdict | Key Evidence |
|------|---------|-------------|
| A. Trap delegation | **PASS** | `cpu_clint.sv:135,145`, `cpu_csr.sv:425,432` |
| B. Trap entry CSR save | **PASS** | `cpu_clint.sv:169-180`, `cpu_csr.sv:523-538` |
| C. mret execution | **PASS** | `cpu_clint.sv:155,156,171` |
| D. sret execution | **PASS** | `cpu_clint.sv:155,180`, `cpu_decode.sv:591` |
| E. ecall handling | **PASS** | `cpu_trap_manager.sv:92-95` |
| F. Interrupt priority | **PASS** | `cpu_clint.sv:91-102,129-130` |
| G. Trap cause values | **PASS** | All verified correct |
| H. mstatus interactions | **BUG** | SPIE cleared on mstatus write; sstatus write touches MPRV |
| I. Nested trap support | **PASS** | MIE/SIE cleared on entry, restored on return |

#### BUG-TRAP-1 (Medium): mstatus write clears SPIE (bit 5)
- **File**: `dev/rtl/core/cpu_csr.sv:395-413` (mstatus_wmask, bits [6:4] forced to `3'b000`)
- **Issue**: Every `csrw mstatus` clears SPIE to 0. Per spec, M-mode must be able to write SPIE.
- **Impact**: If OpenSBI writes mstatus and inadvertently clears SPIE, subsequent sret could restore SIE←SPIE=0, disabling S-mode interrupts. **Could contribute to hang if OpenSBI writes mstatus after trap setup.**

#### BUG-TRAP-2 (Low): sstatus write modifies MPRV (bit 17)
- **File**: `dev/rtl/core/cpu_csr.sv:573`
- **Issue**: S-mode can write MPRV via sstatus. MPRV is M-mode only.
- **Impact**: Privilege escalation. Low severity for Linux boot.

#### BUG-TRAP-3 (Medium): MSIP incorrectly included in S-mode SSI pending
- **File**: `dev/rtl/core/cpu_clint.sv:86,100`
- **Issue**: `msip_bit` (M-mode software interrupt) is OR'd into S-mode SSI check. Per spec, MSIP is separate (cause 3, MSI) and not delegatable.
- **Impact**: If MSIP is set while MIE=0 but SIE=1 and SSIE=1, triggers S-mode trap with cause 1 (SSI) instead of M-mode trap with cause 3 (MSI). Unlikely during Linux boot.

#### BUG-TRAP-4 (Low): sstatus read does not expose TSR/TW/TVM
- **File**: `dev/rtl/core/cpu_csr.sv:214-232` (bits 22:20 forced to `3'b000`)
- **Issue**: S-mode cannot read TSR/TW/TVM via sstatus. Per spec, these should be readable.
- **Impact**: Linux may read sstatus.TSR/TW and always see 0. Low severity.

---

### 4. CSR S-mode Views Audit — 6 BUGS

**Verdict: 6 bugs found (4 high, 1 medium, 1 concern)**

| Item | Verdict | Key Evidence |
|------|---------|-------------|
| A. sstatus | **BUG** | MPRV leaks in read/write |
| B. sie | **CONCERN** | Independent register, not view of mie |
| C. sip | **BUG** | SEIP read missing ext_seip |
| D. satp | **CONCERN** | No auto TLB flush on write (convention-dependent) |
| E. stvec | **CONCERN** | Vectored mode unsupported (design choice) |
| F. sscratch/sepc/scause/stval | **PASS** | All correct |
| G. scounteren | **BUG** | S-mode writable (should be read-only) |
| H. medeleg/mideleg | **PASS** | Correct masks |
| I. mstatus interactions | **BUG** | SPIE forced to 0 on mstatus write |
| J. CSR address decoding | **PASS** | All S-mode CSRs present |
| K. WARL behavior | **PASS** | Read-only CSRs silently ignore writes |

#### BUG-CSR-1 (High): sstatus write modifies MPRV (bit 17)
- **File**: `dev/rtl/core/cpu_csr.sv:573`
- **Issue**: `r_mstatus[17] <= sw_csr_wdata[17]` — S-mode can write MPRV via sstatus.
- **Impact**: Privilege escalation. S-mode can set MPRV=1, causing M-mode load/store address translation to use S-mode effective privilege.

#### BUG-CSR-2 (High): sstatus read exposes MPRV (bit 17)
- **File**: `dev/rtl/core/cpu_csr.sv:220` (w_sstatus construction)
- **Issue**: `r_mstatus[17]` exposed in sstatus read view. MPRV is M-mode only.
- **Impact**: M-mode state leak to S-mode.

#### BUG-CSR-3 (High): sip.SEIP read missing ext_seip
- **File**: `dev/rtl/core/cpu_csr.sv:645`
- **Issue**: `ADDR_SIP` read returns `r_sip[9]` only, missing `ext_seip`. Per spec, `sip.SEIP = ext_seip | software_seip`.
- **Impact**: **Linux reading sip will not see PLIC-asserted SEIP** → missed external interrupts. However, Linux typically uses PLIC claim register, not sip, for interrupt detection. May not directly cause hang.

#### BUG-CSR-4 (High): csr_sip output missing ext_seip
- **File**: `dev/rtl/core/cpu_csr.sv:721`
- **Issue**: `assign csr_sip = r_sip;` — outputs raw r_sip without ext_seip OR.
- **Impact**: If cpu_clint uses csr_sip for S-mode interrupt pending check, external SEIP is missed. However, cpu_clint uses csr_mip[9] (which includes ext_seip) for seip_bit, so this may not be actively harmful.

#### BUG-CSR-5 (High): mstatus_wmask forces SPIE (bit 5) = 0
- **File**: `dev/rtl/core/cpu_csr.sv:408` (bits [6:4] = `3'b000`)
- **Issue**: M-mode software cannot set SPIE via mstatus write. Hardware trap entry/exit bypasses this mask.
- **Impact**: If OpenSBI does `csrs mstatus, SPIE`, it won't stick. Could break S-mode interrupt enable restoration.

#### BUG-CSR-6 (Medium): scounteren writable by S-mode
- **File**: `dev/rtl/core/cpu_csr.sv:587,325`
- **Issue**: scounteren is M-mode RW, S-mode read-only per spec. Code allows S-mode full write.
- **Impact**: S-mode can grant itself U-mode counter access without M-mode permission.

---

### 5. MMU Sv32 PTW/Cache Audit — NO CRITICAL BUGS

**Verdict: PASS (all items, 5 minor concerns)**

| Item | Verdict | Key Evidence |
|------|---------|-------------|
| A. Sv32 PTW | **PASS** | `ptw.sv:72-73,162-163,87,186-187` |
| B. PTE permissions | **PASS** | `ptw.sv:170-185`, `MMU.sv:264-277` |
| C. A/D bit handling | **PASS** | Auto-set with dcache invalidation (`ptw.sv:337-357`, `core_top.sv:759-762`) |
| D. TLB operation | **PASS** | 4-way × 4-set, ASID+Global lookup (`tlb.sv:274-277`) |
| E. sfence.vma | **PASS** | Flushes TLB+dcache+icache (`core_top.sv:727-730`) |
| F. MMIO judgment | **PASS** | `~addr[31] | addr[30]` — all 5 MMIO regions correct |
| G. Cache coherence | **PASS** | VIPT safe (set bits within page offset), PTW A/D coherency handled |
| H. satp CSR | **PASS** | Mode 0/1 supported, TVM enforced in decode |
| I. Page fault handling | **PASS** | Correct causes (12/13/15), stval=VA, delegation via medeleg |
| J. PTW memory access | **PASS** | Separate port, uncached, 256-cycle timeout |

**Concerns (all low/performance)**:
- satp write doesn't auto-flush TLB (Linux uses sfence.vma after satp write — OK)
- sfence.vma ignores rs1/rs2 (always full flush — performance only)
- Hardware A/D auto-set without Svadu advertisement (spec-legal, Linux compatible)
- PTW bus priority 3 (below MMIO — could starve under heavy MMIO, mitigated by timeout)
- Single shared PTW (i-side and d-side serialize — performance only)

---

### 6. Bus Bridge WSTRB/MMIO Audit — NO CRITICAL BUGS

**Verdict: PASS (all items, 3 minor concerns)**

| Item | Verdict | Key Evidence |
|------|---------|-------------|
| A. WSTRB generation | **PASS** | SB/SH/SW → correct WSTRB + data alignment |
| B. MMIO routing | **PASS** | `~addr[31]|addr[30]` classification, SoC decoder correct |
| C. AXI4 protocol | **PASS** | All handshakes correct, BVALID waited |
| D. APB bridge | **PASS** | PSTRB passthrough, PWDATA/PRDATA mapping correct |
| E. APB decoder | **PASS** | UART at slave 2 (0x10008000) correct |
| F. Sub-word UART access | **PASS** | mmio32 word writes work correctly with PSTRB[0] |
| G. Store buffer/ordering | **PASS** | No store buffer, MMIO strongly ordered (DEV_NONBUF + BVALID wait) |
| H. Read response | **PASS** | MMIO read waits rvalid, data latched, RRESP checked |
| I. Bus error | **PASS** | DECERR from default slave, error propagates to trap |
| J. CDC in bus | **CONCERN** | Axi_CDC module handles cpu_clk→sys_clk (not fully verified) |

**Concerns (all low)**:
- awvalid/wvalid hold after handshake (mitigated by slaves deasserting awready)
- APB address aliasing (16KB granularity in 16MB window — design choice)
- AXI4-Lite awsize for sub-word (slaves ignore awsize, use WSTRB — works in practice)

---

## Summary of All Bugs Found

### CRITICAL (Root Cause of Hang)

| # | Bug | File | Impact |
|---|-----|------|--------|
| 1 | **DTS PLIC context mismatch** | `boot/dts/simplecpu.dts:126` | UART interrupts go to MEIP instead of SEIP → kernel hangs after enabling interrupts |

### HIGH

| # | Bug | File | Impact |
|---|-----|------|--------|
| 2 | sip.SEIP read missing ext_seip | `cpu_csr.sv:645` | Linux can't see PLIC SEIP via sip |
| 3 | csr_sip output missing ext_seip | `cpu_csr.sv:721` | Trap manager may miss external SEIP |
| 4 | mstatus_wmask forces SPIE=0 | `cpu_csr.sv:408` | OpenSBI can't set SPIE via mstatus write |
| 5 | sstatus write modifies MPRV | `cpu_csr.sv:573` | S-mode privilege escalation |
| 6 | sstatus read exposes MPRV | `cpu_csr.sv:220` | M-mode state leak to S-mode |

### MEDIUM

| # | Bug | File | Impact |
|---|-----|------|--------|
| 7 | MSIP in S-mode SSI pending | `cpu_clint.sv:86,100` | Wrong interrupt cause for MSIP |
| 8 | scounteren S-mode writable | `cpu_csr.sv:587` | S-mode can grant counter access |
| 9 | sstatus read hides TSR/TW/TVM | `cpu_csr.sv:214-232` | S-mode can't read trap config |

### LOW / CONCERN

| # | Bug/Concern | File | Impact |
|---|-------------|------|--------|
| 10 | sstatus write missing TSR/TW/TVM | `cpu_csr.sv:567-578` | S-mode can't write trap config |
| 11 | sie is independent register | `cpu_csr.sv:579,636` | Not a view of mie (spec non-compliance) |
| 12 | satp write no auto TLB flush | `cpu_csr.sv:586` | Linux uses sfence.vma (OK) |
| 13 | stvec vectored mode unsupported | `cpu_csr.sv:438` | Design choice (Linux uses Direct) |
| 14 | S-mode int delegation not checked | `cpu_clint.sv:130` | Latent (OpenSBI sets mideleg) |
| 15 | sfence.vma ignores rs1/rs2 | `cpu_decode.sv:270-273` | Performance only |
| 16 | APB address aliasing | `apb_decoder.sv` | Design choice |
| 17 | awvalid hold after handshake | `cpu_bus_bridge.sv:547` | Mitigated by slave behavior |

---

## Root Cause Analysis

**The primary root cause of the Linux kernel hang is BUG-PLIC-1 (DTS PLIC context mismatch).**

### Failure Sequence:
1. OpenSBI boots in M-mode, delegates SEI/STI/SSI to S-mode via `mideleg = 0x222`.
2. OpenSBI jumps to Linux kernel in S-mode.
3. Linux PLIC driver parses DTS `interrupts-extended = <&cpu0_intc 9>` → S-mode context = **index 0**.
4. Linux enables UART (source 2) in PLIC **context 0** (enable reg at 0x0C002000).
5. Linux sets context 0 threshold at 0x0C200000.
6. Kernel prints 4 console-handoff lines via earlycon (polling, no interrupts needed).
7. Kernel enables S-mode interrupts (`sstatus.SIE = 1`).
8. UART interrupt fires → PLIC context 0 pending → `o_eip[0]` → **MEIP** (not SEIP!).
9. `mideleg[11]` = 0 (hardwired) → MEI traps to **M-mode (OpenSBI)**.
10. OpenSBI receives MEI (mcause=0x8000000B) but has no PLIC M-mode context handler.
11. OpenSBI either ignores or spins → MEIP stays asserted → **immediate re-trap → infinite loop → HANG**.

### Why QEMU works:
QEMU's PLIC model correctly maps contexts based on the DTS, or QEMU's OpenSBI handles MEI differently. The QEMU PLIC might auto-forward MEI to SEI, or QEMU's DTS has both contexts.

### Required Fix:
```dts
// In boot/dts/simplecpu.dts, change:
interrupts-extended = <&cpu0_intc 9>;
// To:
interrupts-extended = <&cpu0_intc 11>, <&cpu0_intc 9>;
```
This declares context 0 = M-mode (MEI, local interrupt 11) and context 1 = S-mode (SEI, local interrupt 9), matching the RTL. Linux will then use PLIC context 1 for S-mode, and UART interrupts will assert SEIP → reach the kernel.

### Secondary Concerns (may need fixing after primary):
- **BUG-CSR-5 (SPIE cleared on mstatus write)**: If OpenSBI writes mstatus after trap setup, SPIE could be lost, breaking S-mode interrupt restoration. Verify OpenSBI's mstatus write patterns.
- **BUG-CSR-3 (sip.SEIP missing ext_seip)**: If Linux reads sip to check pending interrupts, it won't see PLIC SEIP. Verify Linux's interrupt checking path.
- **BUG-TRAP-3 (MSIP in SSI)**: If MSIP is used during boot, wrong interrupt cause. Verify MSIP usage.

