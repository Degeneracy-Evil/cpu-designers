# ============================================================
# regression/reg_pf_latch.s — Bug 11 regression
# Category: Regression | Sub-tests: 3
# ============================================================
.section .text.start
.globl _start

_start:
    la x10, mmu_trap_handler
    csrw mtvec, x10; li x10, 0x1888; csrw mstatus, x10
    jal x1, test_init
    la x11, t1; jal x1, test_run
    la x11, t2; jal x1, test_run
    la x11, t3; jal x1, test_run
    jal x1, test_report
end_loop: j end_loop

# Test 1: PF detected (invalid PTE → load PF)
t1: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    la x16, l0_page_table; lw x17, 24(x16); li x5, ~0x001
    and x17, x17, x5; sw x17, 24(x16)   # L0[6] V=0
    jal x1, enable_sv32
    la x5, sc1; la x6, mrp; sw x5, 0(x6)
    la x5, mgf; sw x0, 0(x5)
    la x5, sp1; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

sp1: li x14, 0x80006000; lw x15, 0(x14)  # PF
    la x5, ms; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret

sc1: la x15, mgf; lw x15, 0(x15); beqz x15, _t1f
    la x15, mfc; lw x15, 0(x15)
    li x16, 13; beq x15, x16, _t1p   # load PF (13)
    li x16, 12; beq x15, x16, _t1p   # or inst PF (12)
_t1f: li x14, 0; j _t1d
_t1p: li x14, 1
_t1d: la x15, mr; sw x14, 0(x15); ecall

# Test 2: Valid access after restoring PTE
t2: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map  # all valid again
    jal x1, enable_sv32
    la x5, s2; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret
s2: la x14, td; lw x15, 0(x14); li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mr; sw x14, 0(x15); ecall

# Test 3: Store PF (W=0) detected
t3: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    la x16, l0_page_table; lw x17, 16(x16); li x5, ~0x004
    and x17, x17, x5; sw x17, 16(x16)   # L0[4] W=0
    jal x1, enable_sv32
    la x5, sc3; la x6, mrp; sw x5, 0(x6)
    la x5, mgf; sw x0, 0(x5)
    la x5, sp3; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret

sp3: li x14, 0x80004000; sw x0, 0(x14)   # store PF
    la x5, ms; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret

sc3: la x15, mgf; lw x15, 0(x15); beqz x15, _t3f
    la x15, mfc; lw x15, 0(x15)
    li x16, 15; bne x15, x16, _t3f      # store PF (15)
    li x14, 1; j _t3d
_t3f: li x14, 0
_t3d: la x15, mr; sw x14, 0(x15); ecall

mmu_trap_handler:
    csrr x22, mcause; csrr x23, mepc; csrr x24, mtval
    li x5, 9; beq x22, x5, _ec; li x5, 8; beq x22, x5, _ec
    li x5, 11; beq x22, x5, _ec
    la x5, mfc; sw x22, 0(x5); la x5, mfv; sw x24, 0(x5)
    li x5, 1; la x6, mgf; sw x5, 0(x6)
    la x5, mrp; lw x5, 0(x5); beqz x5, _fat
    csrw mepc, x5; li x5, 0x1888; csrw mstatus, x5
    la x5, mrp; sw x0, 0(x5); mret
_fat: la x5, ms; lw x5, 0(x5); csrw mepc, x5
    li x10, 0; li x5, 0x1888; csrw mstatus, x5; mret
_ec: la x5, mr; lw x10, 0(x5)
    la x5, mrp; lw x5, 0(x5); bnez x5, _ec2
    la x5, ms; lw x5, 0(x5); csrw mepc, x5
    li x5, 0x1888; csrw mstatus, x5; mret
_ec2: csrw mepc, x5; la x5, mrp; sw x0, 0(x5)
    li x5, 0x1888; csrw mstatus, x5; mret

.section .text
.balign 4096
td:  .word 0xDEADBEEF
.balign 4
ms: .word 0; mrp: .word 0; mr: .word 0; mgf: .word 0; mfc: .word 0; mfv: .word 0
