# Process Log

## 2026-06-16: axi4lite_plic.sv — SiFive PLIC standard layout + dual-context support

### Changed files
- `dev/rtl/axi/axi4lite_plic.sv` — full rewrite
- `dev/rtl/system_top.sv` — o_eip connection updated

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
