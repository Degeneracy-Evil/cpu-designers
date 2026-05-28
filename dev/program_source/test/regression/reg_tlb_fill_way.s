# ============================================================
# regression/reg_tlb_fill_way.s — Bug 1 regression: TLB fill way
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

# Test 1: Basic Sv32 load (sanity)
t1: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s1; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret
s1: la x14, td; lw x15, 0(x14); li x16, 0xDEADBEEF
    bne x15, x16, 1f; li x14, 1; j 2f
1:  li x14, 0
2:  la x15, mr; sw x14, 0(x15); ecall

# Test 2: Two pages (page 3 and page 4)
t2: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s2; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret
s2: la x14, td; lw x15, 0(x14); li x16, 0xDEADBEEF; bne x15, x16, _f2
    la x14, td2; lw x15, 0(x14); li x16, 0xCAFEBABE; bne x15, x16, _f2
    li x14, 1; j _d2
_f2: li x14, 0
_d2: la x15, mr; sw x14, 0(x15); ecall

# Test 3: Fill then re-read (verify no corruption)
t3: la x5, ms; sw x1, 0(x5); sw x0, 4(x5)
    jal x1, setup_identity_map
    jal x1, enable_sv32
    la x5, s3; csrw mepc, x5; li x5, 0x880; csrw mstatus, x5; mret
s3: la x14, td; lw x15, 0(x14); li x16, 0xDEADBEEF; bne x15, x16, _f3
    la x14, td2; lw x15, 0(x14); li x16, 0xCAFEBABE; bne x15, x16, _f3
    la x14, td; lw x15, 0(x14); li x16, 0xDEADBEEF; bne x15, x16, _f3  # re-read
    li x14, 1; j _d3
_f3: li x14, 0
_d3: la x15, mr; sw x14, 0(x15); ecall

mmu_trap_handler:
    csrr x22, mcause; csrr x23, mepc; csrr x24, mtval
    li x5, 9; beq x22, x5, _ec; li x5, 8; beq x22, x5, _ec
    la x5, mfc; sw x22, 0(x5); la x5, mfv; sw x24, 0(x5)
    li x5, 1; la x6, mgf; sw x5, 0(x6)
    la x5, mrp; lw x5, 0(x5)
    beqz x5, _fat
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
.balign 4096
td2: .word 0xCAFEBABE
.balign 4
ms: .word 0; mrp: .word 0; mr: .word 0; mgf: .word 0; mfc: .word 0; mfv: .word 0
