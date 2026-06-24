# ============================================================
# mmu/pmp_violation.s — PMP violation during PTW walk tests
# Category: MMU
# Sub-tests: 3
# ============================================================
# RISC-V Privileged Spec §3.6.2:
#   When PMP denies read access to a PTE address during a
#   page table walk, the PTW must raise an ACCESS FAULT
#   (mcause=1/5/7), NOT a page fault (mcause=12/13/15).
#   The fault cause matches the original access type:
#     FETCH → 1 (inst access fault)
#     LOAD  → 5 (load access fault)
#     STORE → 7 (store access fault)
#
# IMPORTANT: PMP is currently a PLACEHOLDER in this CPU.
#   ptw_pmp_grant is hardwired to 1'b1 in core_top.sv,
#   so PMP violations CANNOT actually occur yet.
#   This test is written to be correct once PMP is implemented.
#   Until then, sub-tests will FAIL (no fault triggered).
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, pmp_violation_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_fetch_access_fault
    jal x1, test_run
    la x11, test_load_access_fault
    jal x1, test_run
    la x11, test_store_access_fault
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Helper: configure PMP to deny read access to L0 page table ──
#
# PMP entry 0: NAPOT mode, deny all (R=0,W=0,X=0), Locked
# Targets the L0 page table region (4KB page-aligned).
#
# pmpcfg0 layout (per entry, 8 bits):
#   [7]=L  [6]=0  [5]=R  [4]=W  [3]=X  [2:1]=A  [0]=0
#   L=1, R=0, W=0, X=0, A=11(NAPOT) → 0b10000110 = 0x86
#
# NAPOT for 4KB (2^12 bytes):
#   n+3=12 → n=9 trailing 1-bits in pmpaddr
#   pmpaddr = (base >> 2) | ((1 << 9) - 1)
#   For base = l0_page_table address (page-aligned):
#     pmpaddr = (l0_page_table >> 2) | 0x1FF
#
configure_pmp_deny_l0:
    la x14, l0_page_table
    srli x14, x14, 2           # base >> 2
    ori  x14, x14, 0x1FF       # set 9 trailing 1s for 4KB NAPOT
    csrw pmpaddr0, x14
    # pmpcfg0: entry0 = 0x86 (L=1, R=0, W=0, X=0, A=NAPOT)
    li x14, 0x86
    csrw pmpcfg0, x14
    ret

# ── Helper: clear PMP entry 0 (allow all) ──
configure_pmp_allow_all:
    csrw pmpaddr0, x0
    csrw pmpcfg0, x0
    ret

# ── Sub-test 1: Fetch access fault when PMP denies PTE read ──
# When PTW reads a PTE from a PMP-denied region during an
# instruction fetch TLB miss, mcause should be 1 (inst access
# fault), NOT 12 (inst page fault).
test_fetch_access_fault:
    la x5, pmp_saved_ra; sw x1, 0(x5)
    la x5, post_fetch_af_check
    la x6, pmp_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)               # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    jal x1, configure_pmp_deny_l0
    sfence.vma                  # flush TLB to force PTW walk
    la x5, s_fetch_af; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_fetch_af:
    # Access a VA whose PTE is in the denied L0 region.
    # VA 0x80004000 → L0[4] which is in the denied L0 page.
    # This instruction fetch should trigger PTW → PMP violation
    # → inst access fault (mcause=1).
    li x14, 0x80004000
    # We cannot actually jump there in S-mode with PMP blocking
    # the PTW, so instead we trigger a fetch by doing an
    # indirect jump to an address that requires a TLB refill.
    # The fetch of the target will cause PTW to read L0[4].
    jr x14                      # fetch from denied PTE region
    li x14, 0                   # no fault → FAIL
    la x15, pmp_result; sw x14, 0(x15); ecall

post_fetch_af_check:
    la x5, pmp_got_fault; lw x5, 0(x5)
    beqz x5, 2f                 # no fault → FAIL
    la x5, pmp_fault_cause; lw x5, 0(x5)
    li x6, 1;  beq x5, x6, 1f   # inst access fault (expected)
    j 2f                         # unexpected cause → FAIL
1:  li x10, 1; j 3f
2:  li x10, 0
3:  jal x1, configure_pmp_allow_all
    la x5, pmp_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 2: Load access fault when PMP denies PTE read ──
# When PTW reads a PTE from a PMP-denied region during a
# load TLB miss, mcause should be 5 (load access fault),
# NOT 13 (load page fault).
test_load_access_fault:
    la x5, pmp_saved_ra; sw x1, 0(x5)
    la x5, post_load_af_check
    la x6, pmp_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)               # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    jal x1, configure_pmp_deny_l0
    sfence.vma                  # flush TLB to force PTW walk
    la x5, s_load_af; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_load_af:
    # Load from VA whose PTE is in the denied L0 region.
    # VA 0x80004000 → L0[4] in denied L0 page.
    # The load will cause TLB miss → PTW reads L0[4] → PMP
    # violation → load access fault (mcause=5).
    li x14, 0x80004000
    lw x15, 0(x14)             # should trigger load access fault
    li x14, 0                   # no fault → FAIL
    la x15, pmp_result; sw x14, 0(x15); ecall

post_load_af_check:
    la x5, pmp_got_fault; lw x5, 0(x5)
    beqz x5, 2f                 # no fault → FAIL
    la x5, pmp_fault_cause; lw x5, 0(x5)
    li x6, 5;  beq x5, x6, 1f   # load access fault (expected)
    j 2f                         # unexpected cause → FAIL
1:  li x10, 1; j 3f
2:  li x10, 0
3:  jal x1, configure_pmp_allow_all
    la x5, pmp_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 3: Store access fault when PMP denies PTE read ──
# When PTW reads a PTE from a PMP-denied region during a
# store TLB miss, mcause should be 7 (store access fault),
# NOT 15 (store page fault).
test_store_access_fault:
    la x5, pmp_saved_ra; sw x1, 0(x5)
    la x5, post_store_af_check
    la x6, pmp_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)               # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    jal x1, configure_pmp_deny_l0
    sfence.vma                  # flush TLB to force PTW walk
    la x5, s_store_af; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_store_af:
    # Store to VA whose PTE is in the denied L0 region.
    # VA 0x80004000 → L0[4] in denied L0 page.
    # The store will cause TLB miss → PTW reads L0[4] → PMP
    # violation → store access fault (mcause=7).
    li x14, 0x80004000
    li x15, 0xCAFEBABE
    sw x15, 0(x14)             # should trigger store access fault
    li x14, 0
    la x15, pmp_result; sw x14, 0(x15); ecall

post_store_af_check:
    la x5, pmp_got_fault; lw x5, 0(x5)
    beqz x5, 2f                 # no fault → FAIL
    la x5, pmp_fault_cause; lw x5, 0(x5)
    li x6, 7;  beq x5, x6, 1f   # store access fault (expected)
    j 2f                         # unexpected cause → FAIL
1:  li x10, 1; j 3f
2:  li x10, 0
3:  jal x1, configure_pmp_allow_all
    la x5, pmp_saved_ra; lw x1, 0(x5); ret

# ============================================================
# PMP Violation Trap Handler
# ============================================================
# Records fault cause and faulting address, then jumps to
# the post-check code set by each sub-test.
# Distinguishes access faults (1/5/7) from page faults (12/13/15).
pmp_violation_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    # Check for ecall (mcause=8 or 9) — used by sub-tests to
    # return result after no-fault path
    li x5, 9; beq x22, x5, _pvth_ecall
    li x5, 8; beq x22, x5, _pvth_ecall
    # Record fault info
    la x5, pmp_fault_cause; sw x22, 0(x5)
    la x5, pmp_fault_val; sw x24, 0(x5)
    li x5, 1; la x6, pmp_got_fault; sw x5, 0(x6)
    # Jump to post-check code
    la x5, pmp_return_pc; lw x5, 0(x5)
    beqz x5, _pvth_fatal_fault
    csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5
    la x5, pmp_return_pc; sw x0, 0(x5); mret
_pvth_fatal_fault:
    la x5, pmp_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret
_pvth_ecall:
    la x5, pmp_result; lw x10, 0(x5)
    la x5, pmp_return_pc; lw x5, 0(x5)
    bnez x5, _pvth_ecall_post
    la x5, pmp_saved_ra; lw x5, 0(x5); csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5; mret
_pvth_ecall_post:
    csrw mepc, x5; la x5, pmp_return_pc; sw x0, 0(x5); li x5, 0x1888; csrw mstatus, x5; mret

.section .text
.balign 4096
pmp_test_data_area:
    .word 0xDEADBEEF
    .fill 1023, 4, 0

.balign 4
pmp_saved_ra:    .word 0
pmp_return_pc:   .word 0
pmp_result:      .word 0
pmp_got_fault:   .word 0
pmp_fault_cause: .word 0
pmp_fault_val:   .word 0
