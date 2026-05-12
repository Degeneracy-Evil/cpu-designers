# simpleCPU Development Process Log

## 2026-05-12 — P1: PLIC + CLINT (mtime) Integration

### Modules Created

| Module | Path | Lines | Description |
|--------|------|-------|-------------|
| `ahb_plic` | `dev/rtl/AHB-lite/ahb_plic.v` | 142 | RISC-V Platform-Level Interrupt Controller (PLIC) as AHB-Lite slave. Supports 8 interrupt sources, 1 M-mode context. Standard priority/pending/enable/threshold/claim-complete register map. Level-triggered gateway. EIP output for CPU `ext_meip`. |
| `ahb_clint` | `dev/rtl/AHB-lite/ahb_clint.v` | 94 | Core-Local Interruptor (CLINT) as AHB-Lite slave. 64-bit `mtime` counter, 64-bit `mtimecmp` compare register. Generates MTIP when `mtime >= mtimecmp`. MSIP hardwired to 0. |

### Design Decisions

- **Address Map**: 4-way AHB address decode:
  - `0x00000000-0x00FFFFFF`: SRAM (HSEL if HADDR[31:24]==0x00)
  - `0x0C000000-0x0CFFFFFF`: PLIC (HSEL if HADDR[31:24]==0x0C)
  - `0x02000000-0x02FFFFFF`: CLINT (HSEL if HADDR[31:24]==0x02)
  - `0x80000000-0xFFFFFFFF`: APB Bridge (HSEL if HADDR[31]==1)
- **PLIC register map**: Standard RISC-V PLIC offsets (Priority at 0x000000, Pending at 0x001000, Enable at 0x002000, Threshold at 0x200000, Claim/Complete at 0x200004). Fits within 4MB window.
- **CLINT register map**: Compact offsets within 4KB region (mtimecmp_lo at +0x00, mtimecmp_hi at +0x04, mtime_lo at +0x08, mtime_hi at +0x0C).
- **Interrupt routing**: PLIC EIP → CPU `ext_meip`; CLINT MTIP → CPU `ext_mtip`; CLINT MSIP → CPU `ext_msip` (hardwired 0). APB Timer IRQ routed to PLIC source 1 (only connected source). UART/SPI/GPIO IRQ wires available for future use.

### Modules Modified

| Module | Changes |
|--------|---------|
| `ahb_lite_bus.v` | Expanded from 2 to 4 AHB slaves. Added PLIC + CLINT instances. Custom address decode replacing generic `ahb_decoder`. Added `o_plic_eip`, `o_clint_mtip`, `o_clint_msip` outputs. |
| `system_top.v` | SLAVE_NUM 2→4. Wire `plic_eip`, `clint_mtip`, `clint_msip` to CPU. APB Timer IRQ no longer connected to CPU directly. |
| `core_top.v` | Added `ext_meip_in`, `ext_msip_in` input ports. Routed to cpu_trap_csr. |
| `cpu_trap_csr.v` | Added `ext_meip_in`, `ext_msip_in` input ports. Routed to cpu_csr_interface. |
| `cpu_csr_interface.v` | Added `ext_meip_in`, `ext_msip_in` input ports, replacing hardcoded `1'b0` for ext_meip/ext_msip in cpu_csr instantiation. |
| All 7 testbenches | SLAVE_NUM 2→4. Added new ahb_lite_bus port connections. Added ext_meip_in/ext_msip_in=1'b0 to core_top instances. |

### Verification

- `tb_simple_cpu_top.v`: 42/42 PASS
- `tb_simple_cpu_compute.v`: 42/42 PASS
- `tb_simple_cpu_trap.v`: 14/14 PASS
- `system_top.v`: Compile OK
- All other testbenches: Compile OK
