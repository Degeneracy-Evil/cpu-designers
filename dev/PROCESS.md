All fixes are complete. All 42+42+14=98 tests pass across all testbenches. Here is a summary of the changes:
Changes Summary
Severe Bugs (Priority 1)
Bug	File	Fix
BUG-1 MRET wrong	cpu_clint.v:74-76	MIE←MPIE, MPIE←1, MPP←2'b11 (was: MIE←1, MPIE←old_MPIE, MPP←U-mode)
BUG-2 Interrupt priority	cpu_clint.v:50-54	Priority: MEI > MSI > MTI (was: MSI > MTI > MEI)
Missing CSRs & WARL Constraints (Priority 2-4)
Change	File	Details
11 new CSRs	cpu_csr.v	misa(0x301, 0x40001100), mvendorid/marchid/mimpid/mhartid(all 0), mconfigptr(0), mstatush(0), mcycle/minstret/mcycleh/minstreth
WARL mstatus	cpu_csr.v:90	Only MIE[3] and MPIE[7] writable; MPP[12:11] forced to 2'b11
WARL mie	cpu_csr.v:93	Only MEIE[11], MTIE[7], MSIE[3] writable
WARL mtvec	cpu_csr.v:96	BASE 4-byte aligned, MODE forced to 0 (Direct only)
WARL mepc	cpu_csr.v:99	Low 2 bits masked to 0
Cycle/instret counters	cpu_csr.v:116-119	64-bit counters, cycle increments every non-init cycle, inst_retire on wb_done
WFI (Priority 5)
Change	File	Details
WFI as NOP	cpu_decode.v:186	Decoded WFI (0x105), treated as fence (advance to next PC)
Supporting Changes
Change	File	Details
CSR valid list expansion	cpu_decode.v:307-334	Added all 11 new CSRs to dec_csr_addr_valid
Counter signal passthrough	cpu_csr_interface.v, cpu_trap_csr.v, core_top.v	cycle_en and inst_retire wired from core_top to cpu_csr
Test expectation update	tb_simple_cpu_top.v:164, tb_simple_cpu_compute.v:164	x2 expected 0x1800 (mstatus reset with MPP=M-mode)