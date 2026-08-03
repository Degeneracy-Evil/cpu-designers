# Process Log

## 2026-06-19: tlb_megapage.s + sv32_edge.s — Fix simulation timeout from slow clear_page_tables

### Changed files
- `src/program_source/test/mmu/tlb_megapage.s` — added disable_sv32 + inline fast page table clear
- `src/program_source/test/mmu/sv32_edge.s` — added disable_sv32 + inline fast page table clear

### Root cause
`clear_page_tables` (in page_table_utils.s) clears all 2048 entries (L1: 1024 + L0: 1024)
with `sw x0, 0(x10)` in a loop. Each store takes ~50 cycles due to dcache write-back behavior,
so one call costs ~102K cycles. With 4 sub-tests in tlb_megapage (4 × 102K = 408K cycles) and
SIM_CYCLES=200K, the simulation times out before all sub-tests complete.

The original hypothesis (satp remaining set → dcache corruption → loop counter overrun) was
incorrect. Instruction trace analysis showed the loop runs exactly 1024 real iterations; the
"1122" count was duplicate trace entries from pipeline stalls, not counter corruption.

### Fix
1. Added `jal x1, disable_sv32` before page table setup in each sub-test (clears satp + fence.i)
2. Replaced `jal x1, clear_page_tables` with inline fast clear of only the 9 entries actually
   modified by any test (L1[512] + L0[0-7]), reducing from 2048 stores to 9 stores (~200x faster)

### Result
- tlb_megapage: ALL TESTS PASSED (4/4 sub-tests, pass_count=4, first_fail_id=0)
- sv32_edge: ALL TESTS PASSED (6/6 sub-tests, pass_count=6, first_fail_id=0)

## 2026-06-19: tlb_replace.s + tlb_stress.s — Fix test data overwriting code/page tables

### Changed files
- `src/program_source/test/mmu/tlb_replace.s` — remapped all test data addresses
- `src/program_source/test/mmu/tlb_stress.s` — remapped all test data addresses

### Root cause
Test data writes at offset 0x80 within pages 0-7 overlapped with:
- Page 0 (0x80000080): code (test functions at 0x8000006c-0x80000970)
- Page 1 (0x80001080): code (setup_identity_map at 0x80001000-0x80001170)
- Page 2 (0x80002080): l1_page_table (4KB at 0x80002000)
- Page 3 (0x80003080): l0_page_table (4KB at 0x80003000)

Writing unique values to these addresses in bare M-mode corrupted code and
page tables. When Sv32 was enabled, PTW read corrupted page tables → page
faults. Code corruption caused setup_identity_map to crash on re-entry.

### Fix
Changed all test data addresses to offset 0xF00 within each page, which is
past all code (ends ~0x970 in page 0, ~0x170 in page 1), past page tables
(pages 2-3 skipped entirely), and past data variables (end at 0xEB4 in
page 4). Uses 6 safe pages (skipping page table pages 2 and 3):
- A=0x80000F00 (page 0)  B=0x80001F00 (page 1)
- C=0x80004F00 (page 4)  D=0x80005F00 (page 5)
- E=0x80006F00 (page 6)  F=0x80007F00 (page 7)

test_03 in tlb_replace adjusted from 4 sequential replacements (8 pages)
to 2 sequential replacements (6 pages). All other tests use ≤6 pages.

### Results
- tlb_replace: ALL 6 sub-tests PASSED
- tlb_stress: ALL 6 sub-tests PASSED

## 2026-06-16: axi4lite_plic.sv — SiFive PLIC standard layout + dual-context support

### Changed files
- `src/rtl/axi/axi4lite_plic.sv` — full rewrite
- `src/rtl/system_top.sv` — o_eip connection updated

### Summary
Rewrote `axi4lite_plic` to use standard SiFive PLIC address offsets and support 2 interrupt contexts (M-mode + S-mode).

### Key changes in axi4lite_plic.sv
1. **Address decode** — switched to SiFive standard layout:
   - Priority[S]: `addr[23:12]==12'h000`, index=`addr[7:2]`
   - Pending: `addr[23:12]==12'h001`
   - Enable[ctx N]: `addr[23:12]==12'h002`, ctx=`addr[11:7]`
   - Threshold[ctx N]: `addr[23:20]==4'h2`, ctx=`addr[15:12]`, sub=`addr[3:2]==0`
   - Claim/Complete[ctx N]: `addr[23:20]==4'h2`, ctx=`addr[15:12]`, sub=`addr[3:2]==1`
2. **NUM_CTX parameter** — added `parameter NUM_CTX = 2`
3. **Per-context registers** — `r_enable[0:1]`, `r_threshold[0:1]`, `r_claim_id[0:1]`
4. **Shared registers** — `r_prio[0:NUM_SRC-1]`, `r_pending`, `r_gw_en[0:NUM_SRC-1]` remain shared
5. **o_eip output** — changed from `wire o_eip` to `wire [NUM_CTX-1:0] o_eip` (`[0]=M-mode, [1]=S-mode`)
6. **Per-context EIP** — each context computes its own EIP via `find_highest()` with its own enable/threshold
7. **Claim semantics** — claim on any context clears the shared `r_pending` bit and `r_gw_en` for the claimed ID
8. **Complete semantics** — complete on any context re-enables `r_gw_en[ID]`
9. **WSTRB-aware writes** — preserved for all register types, now per-context for enable/threshold
10. **AXI4-Lite FSM** — unchanged (WR_IDLE/WR_DATA/WR_RESP, RD_IDLE/RD_RESP)
11. **Reset pattern** — `always_ff @(posedge clk or negedge resetn)` preserved

### Key changes in system_top.sv
- `plic_eip` wire changed from scalar to `[1:0]`
- CDC synchronizer feeds from `plic_eip[0]` (M-mode) to existing `ext_meip_in` path
- `o_eip` port connection unchanged (auto-widens to match `[1:0]`)

## 2026-06-19: Fix MMU test programs referencing unmapped addresses (>= 0x80008000)

### Problem
`setup_identity_map` only maps L0[0-7] (0x80000000-0x80007FFF = 32KB SRAM).
Any test accessing 0x80008000+ in Sv32 S-mode page faults because L0[8+] is not mapped.

### Changed files
- `src/program_source/test/mmu/tlb_asid.s` — test_04_sfence_preserves_global: replaced 3 occurrences of `0x80008000` with `0x80005000` (within mapped range, not in test result area 0x80007000)

### Files checked but no fix needed
- `tlb_replace.s` — all addresses 0x80000080-0x80007080, all within mapped range
- `tlb_stress.s` — all addresses 0x80000080-0x80007080, all within mapped range
- `tlb_megapage.s` — uses labels (test_data_area, test_data_area2), megapage maps 4MB, no hardcoded out-of-range addresses
- `sv32_edge.s` — uses 0x80004000, 0x00000000 (intentional PF), 0xFFFFF000 (intentional PF), all correct

### Verification
- Rebuilt all 12 MMU tests: `python3 tools/test_builder.py --category mmu` — 12 built, 0 failed
- Ran `mmu_tlb_asid` simulation: pass_count=4, total_count=4, first_fail_id=0 — ALL TESTS PASSED
