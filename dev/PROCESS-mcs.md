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

### Recent Fixes

- Fixed repeated trigger bug in dcache_ctrl.sv and icache_ctrl.sv: added !cpu_req_ready_r condition to cache hit determination and S_IDLE state transition to prevent multiple re-evaluations.
- Fixed tb_apb_perips.sv by replacing old req_*/resp_* protocol ports with the standard AHB-Lite signals and updated ahb_write/ahb_read tasks accordingly.

### Next Steps

1. Run tb_simple_cpu_compute and tb_simple_cpu_trap simulations
2. Run tb_uart_hello, tb_led_marquee simulations
3. Verify writeback path (dirty victim eviction) with targeted tests
4. Performance measurement: cache hit/miss statistics
