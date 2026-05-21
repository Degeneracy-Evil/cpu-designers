# MCS Cache Implementation Progress

## 2026-05-19: Full 4-way set-associative cache system implementation

### Files Created

- `dev/rtl/core/tree_plru.sv` — Tree-PLRU module (3-bit state, 4-way victim selection + access update)
- `dev/rtl/core/icache_ctrl.sv` — Rewritten: 4-way set-assoc ICache with icached BRAM IP, register tags, PLRU, MMIO bypass, refill interface
- `dev/rtl/core/dcache_ctrl.sv` — Rewritten: 4-way set-assoc DCache with dcached BRAM IP, store merge, writeback, refill interface
- `dev/rtl/core/cpu_bus_bridge.sv` — Rewritten: MMIO + ICache refill INCR8 + DCache refill INCR8 + DCache writeback INCR8 burst support

### Files Modified

- `dev/rtl/AHB-lite/ahb_sram_slave.sv` — Fixed: wea 4-bit→1-bit (Sram IP), MEM_DEPTH 262144→8192, HBURST [3:0]→[2:0]
- `dev/rtl/AHB-lite/ahb_lite_bus.sv` — SRAM decoder 0x00→0x80, MEM_DEPTH→8192, HBURST passthrough (no padding)
- `dev/rtl/core/core_top.sv` — Wired refill_req/addr/data/valid and wb_req/addr/data/valid between caches and bridge
- `dev/rtl/system_top.sv` — MEM_DEPTH 262144→8192

### Files Deleted

- `dev/rtl/core/icache.sv` — Behavioral model replaced by icache_ctrl.sv with icached BRAM IP
- `dev/rtl/core/dcache.sv` — Behavioral model replaced by dcache_ctrl.sv with dcached BRAM IP

### Design Summary

- **Cache geometry**: 8 sets × 4 ways, 7-bit tag (addr[14:8]), 3-bit set index (addr[7:5]), 3-bit word offset (addr[4:2])
- **Tag storage**: Registers (not BRAM) for parallel 4-way comparison in 1 cycle
  - ICache tag: {valid, tag[6:0]} = 8 bits
  - DCache tag: {valid, dirty, tag[6:0]} = 9 bits
- **Data storage**: Xilinx BRAM IPs (icached/dcached: 256-bit × 32 entries, True Dual Port, WRITE_FIRST)
  - BRAM address: {set_idx[2:0], way[1:0]} = 5 bits
  - Port A: CPU read/write, Port B: refill write / victim read
- **Replacement**: Tree-PLRU (invalid way first, then PLRU victim)
- **Write policy**: Write-back, write-allocate
  - Store hit: immediate BRAM PortA write, dirty bit set
  - Store miss: refill line, merge store data into refilled line, write merged line to PortB
- **Refill**: INCR8 burst on AHB bus (~17 cycles with 1-wait-state SRAM slave)
- **Writeback**: Read victim from BRAM PortB, INCR8 write burst on AHB bus
- **Bus bridge priority**: MMIO > WB > IRefill > DRefill
- **SRAM address mapping**: 0x80xxxxxx (changed from 0x00xxxxxx)
- **MMIO**: Addresses with addr[31]=0 bypass cache, go directly to AHB bus

### ICache FSM

- S_IDLE → S_READ (BRAM read enabled, 1-cycle latency)
- S_READ → hit: return data, update PLRU, back to S_IDLE
- S_READ → miss: latch set/addr/victim, assert refill_req, go to S_REFILL
- S_REFILL: hold refill_req, wait refill_valid, write BRAM PortB, update tag+PLRU, bypass data, back to S_IDLE

### DCache FSM

- S_IDLE → store hit: write BRAM PortA, set dirty, update PLRU, ready=1
- S_IDLE → load hit: go to S_READ_HIT
- S_IDLE → miss: latch request, if victim dirty → S_WB_READ, else → S_REFILL
- S_READ_HIT: return data from BRAM, update PLRU, back to S_IDLE
- S_WB_READ: enable BRAM PortB read, reconstruct WB address, go to S_WB_SEND
- S_WB_SEND: hold wb_req, wait wb_valid, clear dirty, assert refill_req, go to S_REFILL
- S_REFILL: hold refill_req, wait refill_valid, write BRAM PortB (merged for store miss), update tag+PLRU, bypass data, back to S_IDLE

### Bus Bridge FSM

- S_IDLE: arbitrate requests (MMIO > WB > IRefill > DRefill), guards against duplicate valid
- S_MMIO_ADDR/S_MMIO_DATA: single AHB transfer for MMIO
- S_IREFILL_ADDR/S_IREFILL_DATA: INCR8 read burst, accumulate HRDATA into refill_shift_reg
- S_DREFILL_ADDR/S_DREFILL_DATA: INCR8 read burst, same accumulation
- S_WB_ADDR/S_WB_DATA: INCR8 write burst, shift out wb_shift_reg[31:0] each beat

### Bug Fixes (2026-05-19)

1. **htrans_r premature IDLE in burst states** — In cpu_bus_bridge S_IREFILL_DATA, S_DREFILL_DATA, S_WB_DATA: `htrans_r` was set to IDLE when `beat_cnt==6`, causing `beat_done` to be false for beat 7 (last beat). Fix: always set SEQ in the else branch; last_beat branch already sets IDLE on transition to S_IDLE.
2. **No AHB slave at address 0x00** — Test program stores/loads to address 0x0 (MMIO range, addr[31]=0), but SRAM slave was only at 0x80. Fix: added `HADDR[31:24]==8'h00` to SRAM select in ahb_lite_bus.sv.
3. **x11 timing-dependent expected value** — x11 reads CLINT mtime register; cache miss/refill latency changes cycle count vs original system. Fix: updated expected value from 0x18e8e to 0x1909b in tb_simple_cpu_top.sv.

### Bug Fixes (2026-05-19, continued)

1. **Reverted HADDR[31:24]==8'h00 SRAM select** — Per user direction, address 0x0 region is exceptional (no slave); test programs must use 0x80000000+ addresses for data accesses.
2. **Modified all 3 test assembly sources** to use 0x80001000 base for data accesses (DATA_BASE via x21 register).
3. **Recompiled all 3 with rv2coe** — cpu_test: 216 words, cpu_test_compute: 149 words, cpu_test_trap: 67 words.

### Bug Fixes (2026-05-19, session 3 — dcache store data positioning)

**Root cause**: `word_store_data` and `latched_word_store_data` in dcache_ctrl.sv incorrectly re-positioned halfword store data.

- **Bug**: For halfword stores, dcache_ctrl extracted `cpu_req_wdata[15:0]` and shifted left by `addr[1]*16`. But cpu_mem already positions halfword data correctly within the 32-bit word: `{16'b0, hw}` when `addr[1]=0`, `{hw, 16'b0}` when `addr[1]=1`. When `addr[1]=1`, `wdata[15:0]=0`, so the shift produced 0 instead of the actual halfword data.
- **Fix**: For halfword and word stores, use `cpu_req_wdata` directly (cpu_mem already positions data in the correct byte lanes). Byte store logic (`wdata[7:0] << addr[1:0]*8`) is unchanged since cpu_mem replicates the byte 4×.
- **Before**: `word_store_data = ... (hsize==HWORD) ? (wdata[15:0] << (addr[1]*16)) : wdata`
- **After**: `word_store_data = (hsize==BYTE) ? (wdata[7:0] << (addr[1:0]*8)) : wdata`
- Same fix applied to `latched_word_store_data` for the store-miss merge path.

**Additional fix**: Vivado project source sync — the project uses copies in `simplecpu_bus.srcs/sources_1/imports/`, not the `dev/rtl/` originals. Edits to `dev/rtl/` must be explicitly copied to the project sources directory for simulation to pick up changes.

**Testbench expected value updates** (x11 mtime, x20/x22/x31 PC offsets — all timing/assembly-dependent, not functional bugs):

- x11: 0x0001909b → 0x0001903c (mtime cycle count)
- x20: 0x80000220 → 0x80000224 (mepc from trap handler)
- x22: 0x00000050 → 0x80001050 (data base address change 0x0→0x80001000)
- x31: 0x800000ac → 0x800000b0 (jal return address)

### Simulation Results (2026-05-19, after all fixes)

- **tb_simple_cpu_top**: **42 PASS, 0 FAIL — ALL TESTS PASSED**
  - All ALU, CSR, branch, trap, and data load/store results correct
  - Byte, halfword, and word stores/loads all working via dcache
  - Cache miss → refill → merge path verified working
  - Cache hit → store/load path verified working

- **tb_simple_cpu_compute**: **42 PASS, 0 FAIL — ALL TESTS PASSED**
  - Fixed expected values: x21=0x80001000 (lui x21,0x80001 overwrites lui x21,0x12345), x31=0x800000b0 (jal return address shifted)

- **tb_simple_cpu_trap**: **14 PASS, 0 FAIL — ALL TESTS PASSED**
  - Fixed expected value: x20=0x80000038 (mepc+4 for ecall at shifted PC)

- **tb_led_marquee**: **16 PASS, 0 FAIL — ALL TESTS PASSED**
  - GPIO peripheral functions are correct
  - CLINT MTIP function is correct
  - MMIO-GPIO is correct

- **tb_uart_hello**: **12 PASS, 0 FAIL — ALL TESTS PASSED**
  - Requires runtime ≥40ms (3M cycle wait for UART TX at 115200 baud)
  - Decoded "Hello World" — all 11 characters match

### Recent Fixes

- Fixed repeated trigger bug in dcache_ctrl.sv and icache_ctrl.sv: added !cpu_req_ready_r condition to cache hit determination and S_IDLE state transition to prevent multiple re-evaluations.
- Fixed tb_apb_perips.sv by replacing old req_*/resp_* protocol ports with the standard AHB-Lite signals and updated ahb_write/ahb_read tasks accordingly.

### Phase 8 Completion (2026-05-20)

All 5 testbenches pass with 0 failures:

| Testbench | Result | Details |
|-----------|--------|---------|
| tb_simple_cpu_top | 42 PASS, 0 FAIL | ALU, CSR, branch, trap, data load/store |
| tb_simple_cpu_compute | 42 PASS, 0 FAIL | Fixed x21=0x80001000, x31=0x800000b0 |
| tb_simple_cpu_trap | 14 PASS, 0 FAIL | Fixed x20=0x80000038 |
| tb_led_marquee | 16 PASS, 0 FAIL | GPIO, CLINT MTIP, MMIO |
| tb_uart_hello | 12 PASS, 0 FAIL | "Hello World" decoded, runtime ≥40ms |

### Next Steps

1. Verify writeback path (dirty victim eviction) with targeted tests
2. Performance measurement: cache hit/miss statistics

## 2026-05-21: 7+a fence.i instruction support

### Files Modified

- `dev/rtl/core/cpu_decode.sv` — Separated `is_fence` into `is_nop_like` (fence+wfi) and `is_fencei`; added outputs `dec_is_nop_like`, `dec_is_fencei`; updated `valid_inst` and `dec_need_exe`
- `dev/rtl/core/icache_ctrl.sv` — Added `invalidate_req`/`invalidate_done` ports, `S_INVALIDATE` state (single-cycle clear all tag_ram valid bits and plru_state)
- `dev/rtl/core/dcache_ctrl.sv` — Added `flush_req`/`flush_done` ports, states `S_FLUSH_SCAN`/`S_FLUSH_WB_RD`/`S_FLUSH_WB_SD`, flush_set/flush_way counters, iterates 8×4=32 entries writing back dirty lines then clearing all valid bits
- `dev/rtl/core/cpu_controller.sv` — Replaced `dec_is_fence` with `dec_is_nop_like`+`dec_is_fencei`, added `STATE_FENCEI=4'd9`, `fencei_req`/`fencei_done` ports, fencei→wait done→FETCH
- `dev/rtl/core/core_top.sv` — Added fencei wiring: `dcache_flush_req=fencei_req`, `icache_invalidate_req=fencei_req&&dcache_flush_done`, `fencei_done=dcache_flush_done&&icache_invalidate_done`; updated decode/controller/icache/dcache instance ports; PC logic uses `dec_is_nop_like||dec_is_fencei`

### Design Summary

- **fence.i semantics**: dcache write-back all dirty lines, then icache invalidate all lines
- **Flush order**: dcache first (write-back dirty), then icache invalidate (clear valid bits) — ensures memory consistency
- **icache invalidate**: single-cycle (tag_ram is register array, not BRAM)
- **dcache flush**: iterates all sets/ways via counter, writes back dirty lines through bus bridge
- **`is_nop_like`**: covers fence+wfi (still NOP), `is_fencei` is separate with full cache sync

### Bug Fixes (2026-05-21, fence.i handshake)

1. **`fencei_req`/`fencei_done` implicit wire redeclaration** — In core_top.sv, `fencei_req` and `fencei_done` were used as port connections in the controller instance (creating implicit wires) before their explicit `wire` declarations. Fix: moved `wire` declarations before the controller instance.

2. **dcache re-flushes forever** — `dcache_flush_req = fencei_req` stayed high for the entire STATE_FENCEI duration. After the dcache flush completed and returned to S_IDLE, it immediately saw flush_req still high and started another flush, looping indefinitely. Fix: added `dcache_flush_sent_r` flag; changed to `dcache_flush_req = fencei_req && !dcache_flush_sent_r`.

3. **fencei_done never asserts** — `fencei_done = dcache_flush_done && icache_invalidate_done` required both one-cycle pulses in the same cycle, but icache invalidate happens the cycle after dcache flush done, so the condition was never true. Fix: added `dcache_flush_sent_r` and `icache_invalidate_sent_r` latched flags; changed to `fencei_done = dcache_flush_sent_r && icache_invalidate_sent_r`.

   Corrected fencei handshake wiring in core_top.sv:
   ```
   dcache_flush_req      = fencei_req && !dcache_flush_sent_r
   icache_invalidate_req = fencei_req && dcache_flush_sent_r && !icache_invalidate_sent_r
   fencei_done           = dcache_flush_sent_r && icache_invalidate_sent_r
   ```
   Both flags reset when fencei_req goes low (controller exits STATE_FENCEI).

### Test Results (2026-05-21, after fence.i fixes)

- Added `fence.i` instruction at cpu_test.s:96 (between store and load to same address)
- **tb_simple_cpu_top**: 40 PASS, 2 FAIL → updated expected values:
  - x11: `0x0001903c` → `0x000190a2` (mtime shifted by fence.i flush+invalidate cycles)
  - x20: `0x80000224` → `0x80000228` (mepc shifted by fence.i instruction word in PC)
- After expected value update: **42 PASS, 0 FAIL**

## 2026-05-21: 7+b access fault exception support

### Files Created

- `dev/rtl/AHB-lite/ahb_default_slave.sv` — Default slave for unmapped AHB addresses; 2-cycle ERROR response for NONSEQ/SEQ transfers, OKAY for IDLE/BUSY

### Files Modified

- `dev/rtl/AHB-lite/ahb_lite_bus.sv` — SLAVE_NUM 4→5, added default slave selection logic (HSELx[4] = ~any_other_HSELx), instantiated ahb_default_slave, added default_HRDATA to slave_HRDATA concatenation
- `dev/rtl/core/cpu_bus_bridge.sv` — Added error output ports (`icache_error`, `dcache_error`, `dcache_error_is_store`, `bus_error_addr`); added error registers; HRESP checked in all data states (S_MMIO_ADDR, S_MMIO_DATA, S_IREFILL_DATA, S_DREFILL_DATA, S_WB_DATA); on error: latch address and type, abort to S_IDLE with HTRANS=IDLE
- `dev/rtl/core/cpu_trap_manager.sv` — Added access fault inputs (inst/load/store with addr and PC); added latch registers for access faults (persist until trap_enter_valid/trap_return_valid); added access fault to exception priority logic (cause 1/5/7, highest priority); `exception_at_decode` suppressed when `inst_access_fault_r` active; outputs `inst_access_fault_pending`/`data_access_fault_pending`
- `dev/rtl/core/cpu_trap_csr.sv` — Added access fault inputs/outputs, wired through to cpu_trap_manager instance
- `dev/rtl/core/cpu_controller.sv` — Added `inst_access_fault_pending`/`data_access_fault_pending` inputs; STATE_FETCH checks inst_access_fault_pending→STATE_TRAP_ENTER; STATE_MEM checks data_access_fault_pending→STATE_TRAP_ENTER
- `dev/rtl/core/core_top.sv` — Added bridge error wire declarations; wired bridge error outputs to trap_csr access fault inputs; wired trap_csr pending outputs to controller; `mem_access_fault_pc` tied to `exe_pc`

### Design Summary

- **Default slave**: Returns 2-cycle ERROR for NONSEQ/SEQ to unmapped addresses; previously unmapped addresses got silent OKAY (bug)
- **Error detection**: Bridge checks HRESP in all data-phase states; on ERROR, latches fault address and type, returns to S_IDLE
- **Exception causes**: inst_access_fault=1, load_access_fault=5, store_access_fault=7
- **Priority**: access_fault > exception_at_decode > misalign > exe_misalign
- **inst_access_fault suppresses exception_at_decode**: prevents garbage decode of unfetched instruction causing cause 2 instead of cause 1
- **Access fault latching**: Bridge error pulses are latched in trap_manager, persist until trap is taken
- **APB PSLVERR support deferred**: ahb_lite_to_apb.sv already handles PSLVERR→HRESP correctly
