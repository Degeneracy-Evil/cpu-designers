# MMU/TLB Unit Test Results

## Summary

**Total checks executed**: 265 (168 TLB + 97 MMU)
**All passed**: 265/265
**Test cases**: 70 (35 TLB + 35 MMU)

The test suite has been expanded from the original 73 checks (22 MMU + 51 TLB) to 265 checks, adding comprehensive coverage of Sv32 permission checking, megapage translation, A/D bit updates, bus errors, TLB hit/miss behavior, MXR/SUM interaction, sfence edge cases, and concurrent i/d translation.

---

## Test Execution Matrix

| Test Suite | Config | Checks | Pass | Fail | Result |
|-----------|--------|--------|------|------|--------|
| TLB unit (`tb_tlb_unit.sv`) | USE_TLB_BRAM=1 | 168 | 168 | 0 | ALL PASS |
| MMU unit (`tb_mmu_unit.sv`) | USE_TLB_BRAM=1 | 97 | 97 | 0 | ALL PASS |

---

## Test Case Inventory

### TLB Unit Tests (`tb_tlb_unit.sv`) — 35 test cases, 168 checks

| Test | Description | Checks |
|------|-------------|--------|
| TC_TLB_000 | Basic fill + i-lookup (sanity) | 3 |
| TC_TLB_001 | Basic fill + d-lookup (sanity) | 3 |
| TC_TLB_002 | Fill corrupts d-lookup (BUG TLB-1) | 3 |
| TC_TLB_003 | Back-to-back i-lookups (BUG TLB-2) | 6 |
| TC_TLB_004 | Back-to-back d-lookups (BUG TLB-3) | 6 |
| TC_TLB_005 | d-lookup miss (no entry) | 2 |
| TC_TLB_006 | i-lookup miss (no entry) | 2 |
| TC_TLB_007 | ASID mismatch | 3 |
| TC_TLB_008 | Global bit ignores ASID | 1 |
| TC_TLB_009 | Flush clears entries | 2 |
| TC_TLB_010 | Megapage lookup | 2 |
| TC_TLB_011 | Fill preempts d-lookup at same cycle | 3 |
| TC_TLB_012 | Multiple fills to same set | 4 |
| TC_TLB_013 | 5th fill evicts via PLRU (BUG TLB-4) | 7 |
| TC_TLB_014 | Simultaneous i+d lookup | 4 |
| TC_TLB_015 | PLRU eviction order verification | 6 |
| TC_TLB_016 | Global bit with different ASIDs | 3 |
| TC_TLB_017 | Flush single ASID (non-global entries) | 4 |
| TC_TLB_018 | Flush all (sfence.vma with asid=0) | 3 |
| TC_TLB_019 | i-lookup after flush (re-fill) | 3 |
| TC_TLB_020 | d-lookup after flush (re-fill) | 3 |
| TC_TLB_021 | Megapage vs 4KB page same VPN | 4 |
| TC_TLB_022 | All 4 ways occupied, PLRU eviction | 5 |
| TC_TLB_023 | Fill with different ASID same VPN | 4 |
| TC_TLB_024 | i-lookup perm fault (U=0, S-mode) | 3 |
| TC_TLB_025 | d-lookup perm fault (W=0, store) | 3 |
| TC_TLB_026 | d-lookup perm fault (R=0, load) | 3 |
| TC_TLB_027 | i-lookup perm fault (X=0, fetch) | 3 |
| TC_TLB_028 | SUM=1 allows S access U page (d-side) | 3 |
| TC_TLB_029 | SUM=0 blocks S access U page (d-side) | 3 |
| TC_TLB_030 | MXR=1 allows load X-only page | 3 |
| TC_TLB_031 | MXR=0 blocks load X-only page | 3 |
| TC_TLB_032 | Fill updates perm bits correctly | 5 |
| TC_TLB_033 | Concurrent i+d lookup different VPNs | 6 |
| TC_TLB_034 | 16-entry capacity (4 ways x 4 sets) | 8 |

### MMU Unit Tests (`tb_mmu_unit.sv`) — 35 test cases, 97 checks

| Test | Description | Checks |
|------|-------------|--------|
| TC_MMU_000 | Bare mode identity translation (sanity) | 3 |
| TC_MMU_001 | Sv32 i-side translation (page walk) | 3 |
| TC_MMU_002 | Sv32 d-side translation (page walk) | 3 |
| TC_MMU_003 | Sv32 i-side page fault U-mode (permission) | 3 |
| TC_MMU_004 | Sv32 d-side store to read-only (permission) | 3 |
| TC_MMU_005 | sfence_done premature check (BUG MMU-5) | 3 |
| TC_MMU_006 | Walk arbiter doesn't lose i-side (BUG MMU-6) | 4 |
| TC_MMU_007 | S-mode fetch from S-page RWXAD | 3 |
| TC_MMU_008 | S-mode load from S-page RWXAD | 3 |
| TC_MMU_009 | S-mode store to S-page RWXAD | 3 |
| TC_MMU_010 | U-mode fetch from U-page RWXAD | 3 |
| TC_MMU_011 | U-mode load from U-page RWXAD | 3 |
| TC_MMU_012 | U-mode store to U-page RWXAD | 3 |
| TC_MMU_013 | S-mode fetch from U-page (fault, cause=12) | 2 |
| TC_MMU_014 | S-mode load from U-page no SUM (fault, cause=13) | 2 |
| TC_MMU_015 | S-mode load from U-page SUM=1 (succeed) | 3 |
| TC_MMU_016 | S-mode store to U-page SUM=1 (succeed) | 3 |
| TC_MMU_017 | S-mode fetch from U-page SUM=1 (still fault) | 2 |
| TC_MMU_018 | S-mode load from R-only S-page | 3 |
| TC_MMU_019 | S-mode load from X-only no MXR (fault, cause=13) | 2 |
| TC_MMU_020 | S-mode load from X-only MXR=1 (succeed) | 3 |
| TC_MMU_021 | S-mode store to R-only (fault, cause=15) | 2 |
| TC_MMU_022 | U-mode load from S-page (fault, cause=13) | 2 |
| TC_MMU_023 | Megapage translation (L1 leaf, aligned PPN) | 3 |
| TC_MMU_024 | Megapage PPN misalignment (fault) | 2 |
| TC_MMU_025 | A/D bit update (A=0 -> PTW sets A=1) | 4 |
| TC_MMU_026 | Invalid PTE V=0 (fault) | 2 |
| TC_MMU_027 | Bus error during walk (access fault, cause=1) | 2 |
| TC_MMU_028 | Non-leaf L0 PTE (fault) | 2 |
| TC_MMU_029 | TLB hit after fill (no re-walk) | 4 |
| TC_MMU_030 | d_translate_en=0 (no translation) | 2 |
| TC_MMU_031 | M-mode bare translation (identity) | 3 |
| TC_MMU_032 | Page fault vaddr reporting | 2 |
| TC_MMU_033 | sfence during walk | 3 |
| TC_MMU_034 | Concurrent i+d translation | 4 |

---

## Coverage Summary

### Sv32 Permission Checking
- S-mode access to S-pages (fetch/load/store): TC_MMU_007-009
- U-mode access to U-pages (fetch/load/store): TC_MMU_010-012
- S-mode access to U-pages (fetch blocked, load/store with SUM): TC_MMU_013-017
- R/W/X permission enforcement: TC_MMU_018-022
- MXR bit interaction: TC_MMU_019-020
- SUM bit interaction: TC_MMU_015-017

### Sv32 Page Table Walk
- Standard 2-level walk (L1 pointer -> L0 leaf): TC_MMU_001-002
- Megapage (L1 leaf, aligned PPN): TC_MMU_023
- Megapage misalignment fault: TC_MMU_024
- Invalid PTE (V=0): TC_MMU_026
- Non-leaf L0 PTE (illegal): TC_MMU_028
- Bus error during walk: TC_MMU_027

### A/D Bit Updates
- A bit set by PTW on first access: TC_MMU_025

### TLB Behavior
- Hit after fill (no re-walk): TC_MMU_029
- Flush via sfence.vma: TC_MMU_005, TC_MMU_033
- PLRU eviction (4 ways): TC_TLB_013, TC_TLB_015, TC_TLB_022
- ASID-based flush: TC_TLB_017-018
- Global bit (ASID-independent): TC_TLB_016

### MMU FSM Edge Cases
- sfence during active walk: TC_MMU_033
- Concurrent i+d translation: TC_MMU_034
- Walk arbiter fairness: TC_MMU_006
- d_translate_en=0 bypass: TC_MMU_030
- Page fault vaddr reporting: TC_MMU_032

---

## Files

| File | Description |
|------|-------------|
| `dev/tb/mmu_tlb_unit/tb_tlb_unit.sv` | TLB unit testbench (35 tests, 168 checks) |
| `dev/tb/mmu_tlb_unit/tb_mmu_unit.sv` | MMU unit testbench (35 tests, 97 checks) |
| `dev/tb/mmu_tlb_unit/tb_bram_model.sv` | Behavioral BRAM models |
| `dev/tb/mmu_tlb_unit/run_tlb_tests.sh` | TLB test run script (BRAM) |
| `dev/tb/mmu_tlb_unit/run_mmu_tests.sh` | MMU test run script (BRAM) |
| `dev/docs/mmu_tlb_test_plan.md` | Original 46-test-case plan |
| `dev/docs/mmu_tlb_test_results.md` | This results document |

## How to Run

```bash
# TLB unit tests (BRAM path)
bash dev/tb/mmu_tlb_unit/run_tlb_tests.sh

# MMU unit tests (BRAM path)
bash dev/tb/mmu_tlb_unit/run_mmu_tests.sh
```
