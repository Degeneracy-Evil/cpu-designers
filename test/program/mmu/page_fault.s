# ============================================================
# mmu/page_fault.s — Page fault exception tests
# Category: MMU
# Sub-tests: 4
# ============================================================
# Page fault causes:
#   FETCH PF: mcause=12, LOAD PF: mcause=13, STORE PF: mcause=15
#   Load/store access fault: mcause=5/7 (alternative encodings)
# Test unmapped pages and permission violations in S-mode.
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    jal x1, test_init

    la x11, test_load_pf_unmapped
    jal x1, test_run
    la x11, test_store_pf_no_write
    jal x1, test_run
    la x11, test_pf_mcause_correct
    jal x1, test_run
    la x11, test_pf_mtval_correct
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Sub-test 1: Load page fault on unmapped address ──
test_load_pf_unmapped:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_load_pf_check
    la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault (mmu_return_pc+8 = mmu_got_fault)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_load_pf; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_load_pf:
    li x14, 0x00001000
    lw x15, 0(x14)             # should trigger load PF
    li x14, 0                  # no fault → FAIL
    la x15, mmu_result; sw x14, 0(x15); ecall

post_load_pf_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 2f                # no fault → FAIL
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 1f  # load PF
    li x6, 5;  beq x5, x6, 1f  # load access fault
    j 2f                        # unexpected cause → FAIL
1:  li x10, 1; j 3f
2:  li x10, 0
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 2: Store page fault on read-only page ──
test_store_pf_no_write:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_store_pf_check
    la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    # Modify L0[4] to be read-only (R+X, no W) AFTER enable_sv32
    # so fence.i+sfence.vma happen right before S-mode entry
    la x14, l0_page_table
    li x15, 0x80004
    slli x15, x15, 10
    li x16, 0x04B               # V=1, R=1, X=1, A=1 (NO W, NO D)
    or x15, x15, x16
    sw x15, 16(x14)            # L0[4] → read-only page at 0x80004000
    fence.i                     # flush dcache so PTW sees updated PTE
    sfence.vma                  # flush TLB so next access re-walks
    la x5, s_store_pf; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_store_pf:
    li x14, 0x80004000
    li x15, 0xBBBBBBBB
    sw x15, 0(x14)             # should trigger store PF
    li x14, 0
    la x15, mmu_result; sw x14, 0(x15); ecall

post_store_pf_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 2f
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 15; beq x5, x6, 1f  # store PF
    li x6, 7;  beq x5, x6, 1f  # store access fault
    j 2f
1:  li x10, 1; j 3f
2:  li x10, 0
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 3: Page fault mcause is correct ──
test_pf_mcause_correct:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_mcause_check
    la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_mcause; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mcause:
    li x14, 0x00001000
    lw x15, 0(x14)             # load PF
    li x14, 0
    la x15, mmu_result; sw x14, 0(x15); ecall

post_mcause_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f
    la x5, mmu_fault_cause; lw x5, 0(x5)
    li x6, 13; beq x5, x6, 2f
    li x6, 5;  beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ── Sub-test 4: Page fault mtval has faulting address ──
test_pf_mtval_correct:
    la x5, mmu_saved_ra; sw x1, 0(x5)
    la x5, post_mtval_check
    la x6, mmu_return_pc; sw x5, 0(x6)
    sw x0, 8(x6)             # clear got_fault
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s_mtval; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

s_mtval:
    li x14, 0x00001000
    lw x15, 0(x14)             # load PF at VA 0x00001000
    li x14, 0
    la x15, mmu_result; sw x14, 0(x15); ecall

post_mtval_check:
    la x5, mmu_got_fault; lw x5, 0(x5)
    beqz x5, 1f
    la x5, mmu_fault_val; lw x5, 0(x5)
    li x6, 0x00001000
    beq x5, x6, 2f             # mtval should be faulting VA
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, mmu_saved_ra; lw x1, 0(x5); ret

# ============================================================
# MMU Trap Handler
# ============================================================
mmu_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mtval
    li x5, 9; beq x22, x5, _mth_ecall
    li x5, 8; beq x22, x5, _mth_ecall
    la x5, mmu_fault_cause; sw x22, 0(x5)
    la x5, mmu_fault_val; sw x24, 0(x5)
    li x5, 1; la x6, mmu_got_fault; sw x5, 0(x6)
    la x5, mmu_return_pc; lw x5, 0(x5)
    beqz x5, _mth_fatal_fault
    csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5
    la x5, mmu_return_pc; sw x0, 0(x5); mret
_mth_fatal_fault:
    la x5, mmu_saved_ra; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret
_mth_ecall:
    la x5, mmu_result; lw x10, 0(x5)
    la x5, mmu_return_pc; lw x5, 0(x5)
    bnez x5, _mth_ecall_post
    la x5, mmu_saved_ra; lw x5, 0(x5); csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5; mret
_mth_ecall_post:
    csrw mepc, x5; la x5, mmu_return_pc; sw x0, 0(x5); li x5, 0x1888; csrw mstatus, x5; mret

.section .text
.balign 4096
test_data_area:
    .word 0xDEADBEEF
    .fill 1023, 4, 0

.balign 4
mmu_saved_ra:    .word 0
mmu_return_pc:   .word 0
mmu_result:      .word 0
mmu_got_fault:   .word 0
mmu_fault_cause: .word 0
mmu_fault_val:   .word 0
