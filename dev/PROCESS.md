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

## 2026-05-13 — P2: QEMU virt Memory Map Migration

### Address Map Change

| Range (QEMU virt) | Device | Implementation |
|-------------------|--------|----------------|
| `0x00001000 - 0x00001FFF` | Boot ROM | Reserved (not implemented) |
| `0x02000000 - 0x02FFFFFF` | CLINT | `ahb_clint` AHB slave |
| `0x0C000000 - 0x0CFFFFFF` | PLIC | `ahb_plic` AHB slave |
| `0x10000000 - 0x10FFFFFF` | UART+Peripherals (APB) | AHB-to-APB bridge |
| `0x80000000 - 0xFFFFFFFF` | DRAM (2GB) | Cache (ICache/DCache BRAMs) |

### Key Design Decisions

- **Cache/MMIO bypass inversion**: `is_mmio = ~addr[31]`. DRAM (bit31=1) uses Cache; peripherals (bit31=0) use AHB bus. This is the inverse of the previous mapping.
- **CPU reset vector**: Changed from `0x00000000` to `0x80000000` (DRAM base). Programs are linked at `0x80000000` but loaded into BRAM at offset 0 — the Cache BRAM uses low-order address bits for indexing, so absolute address is transparent.
- **AHB address decode**: Updated from `HSELx[3]=HADDR[31]` (APB at 0x80000000+) to `HSELx[3]=HADDR[31:24]==8'h10` (APB at 0x10000000+), matching QEMU virt UART0/MMIO window.
- **Peripheral addresses**: GPIO at 0x10000000, Timer at 0x10004000, UART at 0x10008000, SPI at 0x1000C000 (APB decoder uses PADDR[15:14] for peripheral selection within the 0x10000000 range).
- **Test data I/O**: Stores to addresses < 0x80000000 go to AHB SRAM (MMIO path). Testbench `check_mem_word` reads from AHB SRAM instead of DCache BRAM, matching the MMIO write path.

### Modules Modified

| Module | Changes |
|--------|---------|
| `icache_ctrl.v` | `is_mmio = cpu_req_addr[31]` → `is_mmio = ~cpu_req_addr[31]` |
| `dcache_ctrl.v` | Same inversion as above |
| `ahb_lite_bus.v` | APB slave select: `HSELx[3]=HADDR[31]` → `HSELx[3]=HADDR[31:24]==8'h10` |
| `core_top.v` | PC reset: `32'b0` → `32'h80000000` |
| `link.ld` | Base address: `. = 0x0` → `. = 0x80000000` |
| Test programs (5 files) | TIMER_BASE/GPIO_BASE/UART_BASE updated to 0x1000XXXX range; hardcoded `lui` constants updated |
| Testbenches (3 files) | `check_mem_word` reads from AHB SRAM; x10/x20/x31 expected values updated |

### Verification

- `tb_simple_cpu_top.v`: 42/42 PASS
- `tb_simple_cpu_compute.v`: 42/42 PASS
- `tb_simple_cpu_trap.v`: 14/14 PASS
- `system_top.v`: Compile OK
