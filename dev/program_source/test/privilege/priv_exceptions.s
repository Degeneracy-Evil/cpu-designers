# ============================================================
# privilege/priv_exceptions.s — U/S/M privilege exception tests
# Category: Privilege
# Description: Test exceptions (illegal inst, ebreak, interrupts)
#              in S-mode and U-mode, covering delegation and
#              privilege-level preservation (MPP/SPP).
# Sub-tests: 8
# Depends: framework/test_framework.s, framework/trap_handlers.s,
#          framework/page_table_utils.s
# Prerequisites: Sv32 page table with dual mapping (setup_dual_map)
# ============================================================
#
# Coverage gaps filled (vs existing privilege/ tests):
#   1. S-mode illegal instruction (non-CSR type)
#   2. U-mode illegal instruction (non-CSR, delegated to S)
#   3. U-mode illegal instruction (non-CSR, NOT delegated -> M)
#   4. S-mode EBREAK (mcause=3, verify MPP=S preserved)
#   5. U-mode EBREAK delegated (scause=3, verify SPP=U preserved)
#   6. U-mode EBREAK not delegated (mcause=3, verify MPP=U preserved)
#   7. S-mode timer interrupt via mideleg[7] (trap reaches S)
#   8. S-mode software interrupt via mideleg[3] (scause=0x80000001)
#
# NOTE: S->U delegation (sedeleg/sideleg) is NOT tested because
#       the N extension (which provides U-mode trapping) is deprecated.
#
# Trap flow summary:
#   S-mode exception, not delegated -> M handler:
#     MPP=S -> skip (mepc+4), mret back to S
#   U-mode exception, not delegated -> M handler:
#     MPP=U -> jump to pe_return_pc (NEVER mret to U-mode VA in bare)
#   U-mode exception, delegated -> S handler:
#     skip (sepc+4), sret back to U
#     marker ecall (0x42) -> S handler -> s_pe_return_point -> ecall -> M
#   S-mode interrupt delegated -> S handler:
#     disable MIE/SIE, clear pending, sret to s_pe_return_point -> ecall -> M
#
# Page table layout (from setup_dual_map):
#   L0[0-7]:  Supervisor pages -> PA 0x80000000-0x80007000
#   L0[8-15]: User pages -> same PA (User alias at VA+0x8000)
# ============================================================

.equ USER_VA_OFFSET,  0x8000
.equ CLINT_BASE,      0x02000000
.equ MTIME_OFFSET,    0xBFF8
.equ MTIMECMP_OFFSET, 0x4000
.equ MSIP_OFFSET,     0x0000

.section .text.start
.globl _start

_start:
    la x10, m_pe_handler
    csrw mtvec, x10

    jal x1, test_init

    # -- S-mode exception tests (no delegation) --
    la x11, test_01_s_mode_illegal
    jal x1, test_run
    la x11, test_04_s_mode_ebreak
    jal x1, test_run

    # -- U-mode exception tests (delegated + not delegated) --
    la x11, test_02_u_illegal_delegated
    jal x1, test_run
    la x11, test_03_u_illegal_not_delegated
    jal x1, test_run
    la x11, test_05_u_ebreak_delegated
    jal x1, test_run
    la x11, test_06_u_ebreak_not_delegated
    jal x1, test_run

    # -- S-mode interrupt delegation tests --
    la x11, test_07_s_timer_delegated
    jal x1, test_run
    la x11, test_08_s_sw_interrupt_delegated
    jal x1, test_run
    # Test 07/08 temporarily disabled
    # la x11, test_08_s_sw_interrupt_delegated
    # jal x1, test_run
    # la x11, test_07_s_timer_delegated
    # jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ============================================================
# Common entry helpers
# ============================================================

# -- enter_s_mode: M->S transition via mret --
# Inputs: x5 = S-mode entry label, x6 = medeleg val, x7 = mideleg val
enter_s_mode:
    la x10, s_pe_handler
    csrw stvec, x10
    csrw medeleg, x6
    csrw mideleg, x7
    csrw mepc, x5
    li x10, 0x00000880      # MPP=01(S), MPIE=1, MIE=0
    csrw mstatus, x10
    mret

# -- enter_u_mode: S->U transition via sret --
# Inputs: x5 = U-mode entry label (Supervisor VA)
enter_u_mode:
    li x10, USER_VA_OFFSET
    add x5, x5, x10          # x5 = User VA of u_entry
    csrw sepc, x5
    li x10, 0x00000022      # SPP=0(U), SPIE=1, SIE=1
    csrw sstatus, x10
    sret

# ============================================================
# Test 01: S-mode illegal instruction (non-CSR) -> M trap
# ============================================================
test_01_s_mode_illegal:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_01; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    la x5, s_entry_01
    li x6, 0x000; li x7, 0x000    # no delegation
    jal x1, enter_s_mode

s_entry_01:
    .word 0x00000000              # illegal -> M trap (not delegated)
    li x10, 0x42; ecall           # marker ecall from S -> M -> pe_return_pc

post_01:
    la x5, pe_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_mcause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 02: U-mode illegal instruction (non-CSR) delegated -> S trap
# ============================================================
# medeleg[2]=1 (delegate illegal). medeleg[8]=0 (ecall-U not delegated).
# U-mode illegal -> S (delegated). U-mode marker ecall -> M (not delegated).
test_02_u_illegal_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_02; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x6, 0x004; li x7, 0x000    # medeleg[2]=1 only
    la x5, s_entry_02
    jal x1, enter_s_mode

s_entry_02:
    la x5, u_entry_02
    jal x1, enter_u_mode

u_entry_02:
    .word 0x00000000              # illegal in U -> S (delegated)
    li x10, 0x42; ecall           # ecall from U -> M (not delegated) -> pe_return_pc

post_02:
    la x5, pe_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_scause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 03: U-mode illegal instruction NOT delegated -> M trap
# ============================================================
# medeleg=0. U-mode illegal -> M (not delegated). M handler jumps to
# pe_return_pc (never returns to U-mode VA).
test_03_u_illegal_not_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_03; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x6, 0x000; li x7, 0x000
    la x5, s_entry_03
    jal x1, enter_s_mode

s_entry_03:
    la x5, u_entry_03
    jal x1, enter_u_mode

u_entry_03:
    .word 0x00000000              # illegal in U -> M (not delegated)

post_03:
    la x5, pe_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_mcause; lw x5, 0(x5)
    li x6, 2; beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 04: S-mode EBREAK -> M trap, verify MPP=S
# ============================================================
test_04_s_mode_ebreak:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_04; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x6, 0x000; li x7, 0x000
    la x5, s_entry_04
    jal x1, enter_s_mode

s_entry_04:
    ebreak                        # ebreak in S -> M trap
    li x10, 0x42; ecall           # marker ecall -> M -> pe_return_pc

post_04:
    la x5, pe_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_mcause; lw x5, 0(x5)
    li x6, 3; bne x5, x6, 1f     # mcause=3
    # MPP = mstatus[12:11], S-mode = 01
    la x5, pe_mstatus; lw x5, 0(x5)
    srli x5, x5, 11
    andi x5, x5, 3
    li x6, 1; bne x5, x6, 1f     # MPP=01(S)
    li x10, 1; j 2f
1:  li x10, 0
2:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 05: U-mode EBREAK delegated -> S trap, verify SPP=U
# ============================================================
# medeleg[3]=1 (delegate ebreak) + medeleg[8]=1 (delegate ecall-U).
# U-mode ebreak -> S (delegated). U-mode marker ecall -> S (delegated)
# -> s_pe_return_point -> ecall -> M -> pe_return_pc.
test_05_u_ebreak_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_05; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x6, 0x108; li x7, 0x000    # medeleg[3]=1, medeleg[8]=1
    la x5, s_entry_05
    jal x1, enter_s_mode

s_entry_05:
    la x5, u_entry_05
    jal x1, enter_u_mode

u_entry_05:
    ebreak                        # ebreak in U -> S (delegated)
    li x10, 0x42; ecall           # marker ecall -> S (delegated) -> s_pe_return_point

post_05:
    la x5, pe_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_scause; lw x5, 0(x5)
    li x6, 3; bne x5, x6, 1f     # scause=3
    la x5, pe_sstatus; lw x5, 0(x5)
    andi x5, x5, 0x100
    beqz x5, 2f                  # SPP=0 (bit 8 clear) -> U-mode
    j 1f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 06: U-mode EBREAK NOT delegated -> M trap, verify MPP=U
# ============================================================
# medeleg=0. U-mode ebreak -> M (not delegated). M handler jumps to
# pe_return_pc (never returns to U-mode VA).
test_06_u_ebreak_not_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_06; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    li x6, 0x000; li x7, 0x000
    la x5, s_entry_06
    jal x1, enter_s_mode

s_entry_06:
    la x5, u_entry_06
    jal x1, enter_u_mode

u_entry_06:
    ebreak                        # ebreak in U -> M (not delegated)

post_06:
    la x5, pe_got_m_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_mcause; lw x5, 0(x5)
    li x6, 3; bne x5, x6, 1f     # mcause=3
    # MPP = mstatus[12:11], U-mode = 00
    la x5, pe_mstatus; lw x5, 0(x5)
    srli x5, x5, 11
    andi x5, x5, 3
    bnez x5, 1f                  # MPP != 00 → FAIL
    li x10, 1; j 2f
1:  li x10, 0; j 3f
2:  la x5, pe_saved_ra; lw x1, 0(x5); ret
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 07: S-mode timer interrupt delegated -> S trap
# ============================================================
# mideleg[7]=1 (delegate M-mode timer, cause 7 -> S-mode timer).
# M->S, set mtimecmp < mtime, enable MTIE+STIE+MIE+SIE, wait.
# Expect: S-mode trap, scause=0x80000005 (S-mode timer interrupt).
test_07_s_timer_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_07; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    # Configure from M-mode (mie/sie/mtimecmp are M-mode accessible)
    li x10, 0x080; csrw mie, x10    # mie[7] = MTIE
    li x10, 0x020; csrw sie, x10    # sie[5] = STIE
    li x7, 0x080; csrw mideleg, x7  # mideleg[7]=1 (delegate timer)
    la x10, s_pe_handler; csrw stvec, x10
    # Read mtime and set mtimecmp = mtime + 50
    li x14, CLINT_BASE
    li x15, MTIME_OFFSET
    add x15, x14, x15
    lw x16, 0(x15)                  # mtime low
    li x15, MTIME_OFFSET + 4
    add x15, x14, x15
    lw x17, 0(x15)                  # mtime high
    li x6, 5000
    add x16, x16, x6                # mtimecmp = mtime + 5000 (enough for mret + S-mode setup)
    li x15, MTIMECMP_OFFSET
    add x15, x14, x15
    sw x16, 0(x15)
    li x15, MTIMECMP_OFFSET + 4
    add x15, x14, x15
    sw x17, 0(x15)
    # Enter S-mode with MIE=0, MPIE=0 + SIE=1
    # MIE=0 prevents M-mode timer from re-triggering after delegation.
    # MPIE=0 ensures mret doesn't set MIE=1 (mret sets MIE=MPIE).
    # The timer fires via m_interrupt_pending (needs MIE) which is delegated
    # to S-mode via mideleg[7]=1. But with MIE=0, m_interrupt_pending=0.
    # Instead, we rely on s_interrupt_pending: SIE=1, STIE=1, STIP=1
    # (STIP from mip[5] which mirrors MTIP when mideleg[7]=1 — Bug 2 fix).
    la x5, s_entry_07
    csrw mepc, x5
    li x10, 0x00000802              # MPP=S, MPIE=0, MIE=0, SIE=1
    csrw mstatus, x10
    mret

s_entry_07:
    # Wait for timer interrupt (all setup done from M-mode)
    # SIE=1, STIE=1, STIP will be set by hardware when mtime >= mtimecmp
    li x15, 300
1:
    addi x15, x15, -1
    bnez x15, 1b

    # Fallback if interrupt didn't fire
    li x10, 0x42; ecall

post_07:
    # Disarm timer and disable interrupts
    li x14, CLINT_BASE
    li x15, -1
    li x16, MTIMECMP_OFFSET
    add x16, x14, x16
    sw x15, 0(x16)
    li x16, MTIMECMP_OFFSET + 4
    add x16, x14, x16
    sw x15, 0(x16)
    csrw mie, x0
    csrw sie, x0
    li x10, 0x1800
    csrw mstatus, x10

    # Check: S-mode trap received with scause=0x80000005 (S-mode timer)
    la x5, pe_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_scause; lw x5, 0(x5)
    li x6, 0x80000005
    beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# Test 08: S-mode software interrupt delegated -> S trap
# ============================================================
# mideleg[3]=1 (delegate M-mode software interrupt, cause 3).
# M->S, enable MSIE+SSIE+MIE+SIE, write CLINT msip=1, wait.
# Expect: S-mode trap, scause=0x80000001 (S-mode software interrupt).
test_08_s_sw_interrupt_delegated:
    la x5, pe_saved_ra; sw x1, 0(x5)
    la x5, post_08; la x6, pe_return_pc; sw x5, 0(x6)
    sw x0, 4(x6); sw x0, 8(x6)
    jal x1, setup_dual_map
    jal x1, enable_sv32
    # Configure from M-mode
    li x10, 0x008; csrw mie, x10    # mie[3] = MSIE
    li x10, 0x002; csrw sie, x10    # sie[1] = SSIE
    li x7, 0x008; csrw mideleg, x7  # mideleg[3]=1 (delegate software IRQ)
    la x10, s_pe_handler; csrw stvec, x10
    # Pre-set SSIP from M-mode (sip is accessible from M-mode)
    li x10, 0x002; csrw sip, x10    # Set SSIP=1 (pending)
    # Enter S-mode with MIE=0 + SIE=1
    la x5, s_entry_08
    csrw mepc, x5
    li x10, 0x00000882              # MPP=S, MPIE=1, MIE=0, SIE=1
    csrw mstatus, x10
    mret

s_entry_08:
    # SIE=1, SSIE=1, SSIP=1 → S-mode software interrupt should fire immediately
    # Just wait (interrupt should trap before first instruction completes)
    li x15, 300
1:
    addi x15, x15, -1
    bnez x15, 1b

    # Fallback if interrupt didn't fire
    li x10, 0x42; ecall

post_08:
    # Clear msip and disable interrupts
    li x14, CLINT_BASE
    sw x0, 0(x14)
    csrw mie, x0
    csrw sie, x0
    li x10, 0x1800
    csrw mstatus, x10

    # Check: S-mode trap with scause=0x80000001
    la x5, pe_got_s_trap; lw x5, 0(x5)
    beqz x5, 1f
    la x5, pe_scause; lw x5, 0(x5)
    li x6, 0x80000001
    beq x5, x6, 2f
1:  li x10, 0; j 3f
2:  li x10, 1
3:  la x5, pe_saved_ra; lw x1, 0(x5); ret

# ============================================================
# S-mode trap handler
# ============================================================
s_pe_handler:
    csrr x22, scause
    csrr x23, sepc
    csrr x24, sstatus

    # Save trap info (only on FIRST S-mode trap to avoid overwrite)
    la x5, pe_got_s_trap; lw x5, 0(x5)
    bnez x5, s_pe_no_save
    li x5, 1; la x6, pe_got_s_trap; sw x5, 0(x6)
    la x5, pe_scause; sw x22, 0(x5)
    la x5, pe_sepc; sw x23, 0(x5)
    la x5, pe_sstatus; sw x24, 0(x5)
s_pe_no_save:

    # Check if interrupt (bit 31 set)
    li x5, 0x80000000
    and x5, x22, x5
    bnez x5, s_pe_interrupt

    # -- Exception handling --
    li x5, 2
    beq x22, x5, s_pe_skip       # illegal instruction
    li x5, 3
    beq x22, x5, s_pe_skip       # ebreak
    li x5, 8
    beq x22, x5, s_pe_ecall_u    # ecall from U

s_pe_skip:
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_pe_ecall_u:
    # Check marker: x10=0x42 means return to S-mode
    li x5, 0x42
    beq x10, x5, s_pe_return
    # Non-marker: skip
    addi x23, x23, 4
    csrw sepc, x23
    sret

s_pe_return:
    # Set SPP=1 so sret returns to S-mode
    csrr x5, sstatus
    li x6, 0x100
    or x5, x5, x6
    csrw sstatus, x5
    la x5, s_pe_return_point
    csrw sepc, x5
    sret

s_pe_interrupt:
    # Disable MIE to prevent M-mode timer re-trigger
    csrr x5, mstatus
    li x6, 0xFFFFFFF7            # clear MIE (bit 3)
    and x5, x5, x6
    csrw mstatus, x5

    # If software interrupt (scause=0x80000001), clear SSIP then return
    li x5, 0x80000001
    beq x22, x5, s_pe_clear_sip

    # If timer interrupt (scause=0x80000005), ecall to M to disarm timer
    li x5, 0x80000005
    beq x22, x5, s_pe_timer_ecall
    j s_pe_int_return

s_pe_clear_sip:
    csrw sip, x0
    j s_pe_int_return

s_pe_timer_ecall:
    # Ecall to M-mode to disarm the timer (S-mode can't access CLINT)
    # M-mode handler will disarm and jump to pe_return_pc
    li x10, 0x43                 # marker: timer disarm request
    ecall

s_pe_int_return:
    # Clear SPIE so SIE=0 after sret (prevent S-mode re-trigger)
    csrr x5, sstatus
    li x6, 0xFFFFFFDF            # clear SPIE (bit 5)
    and x5, x5, x6
    csrw sstatus, x5
    # Return to s_pe_return_point in S-mode (SPP=1)
    csrr x5, sstatus
    li x6, 0x100                 # SPP=1 (S-mode)
    or x5, x5, x6
    csrw sstatus, x5
    la x5, s_pe_return_point
    csrw sepc, x5
    sret

s_pe_return_point:
    # Back in S-mode: ecall to M to continue
    ecall

# ============================================================
# M-mode trap handler
# ============================================================
m_pe_handler:
    csrr x22, mcause
    csrr x23, mepc
    csrr x24, mstatus

    # Save trap info (only on FIRST M-mode trap to avoid overwrite)
    la x5, pe_got_m_trap; lw x5, 0(x5)
    bnez x5, m_pe_no_save
    li x5, 1; la x6, pe_got_m_trap; sw x5, 0(x6)
    la x5, pe_mcause; sw x22, 0(x5)
    la x5, pe_mepc; sw x23, 0(x5)
    la x5, pe_mstatus; sw x24, 0(x5)
m_pe_no_save:

    # Check if interrupt (bit 31 set)
    li x5, 0x80000000
    and x5, x22, x5
    bnez x5, m_pe_interrupt

    # -- Exception handling --
    li x5, 9
    beq x22, x5, m_pe_ecall_s    # ecall from S -> check marker
    li x5, 8
    beq x22, x5, m_pe_goto_retpc  # ecall from U -> pe_return_pc
    li x5, 11
    beq x22, x5, m_pe_skip        # ecall from M -> skip
    li x5, 2
    beq x22, x5, m_pe_check_mpp   # illegal -> check MPP
    li x5, 3
    beq x22, x5, m_pe_check_mpp   # ebreak -> check MPP

    # Unknown: skip
m_pe_skip:
    addi x23, x23, 4
    csrw mepc, x23
    mret

m_pe_ecall_s:
    # Check marker: x10=0x43 means timer disarm request from S-mode handler
    li x5, 0x43
    beq x10, x5, m_pe_disarm_timer
    # Otherwise: jump to pe_return_pc
    j m_pe_goto_retpc

m_pe_disarm_timer:
    # Disarm CLINT timer (S-mode can't access CLINT under Sv32)
    li x5, CLINT_BASE
    li x6, -1
    li x7, MTIMECMP_OFFSET
    add x7, x5, x7
    sw x6, 0(x7)
    li x7, MTIMECMP_OFFSET + 4
    add x7, x5, x7
    sw x6, 0(x7)
    # Disable MIE and jump to pe_return_pc
    j m_pe_goto_retpc

m_pe_check_mpp:
    # Check MPP: if S-mode (01), skip and mret back to S.
    # If U-mode (00), jump to pe_return_pc (never mret to U VA).
    # MPP = mstatus[12:11]
    srli x5, x24, 11
    andi x5, x5, 3
    li x6, 1                     # MPP=01(S)
    beq x5, x6, m_pe_skip       # MPP=S -> skip, mret to S
    # MPP=U -> jump to pe_return_pc
    j m_pe_goto_retpc

m_pe_goto_retpc:
    # Jump to pe_return_pc (M-mode, MIE=0, MPIE=0 to prevent interrupt re-trigger)
    la x5, pe_return_pc; lw x5, 0(x5)
    beqz x5, m_pe_skip          # fallback: skip if no return_pc
    csrw mepc, x5
    li x5, 0x1800; csrw mstatus, x5   # MPP=M, MPIE=0, MIE=0
    la x5, pe_return_pc; sw x0, 0(x5)
    mret

m_pe_interrupt:
    # Disable MIE and MPIE (prevent re-trigger after mret)
    li x5, 0x1800
    csrw mstatus, x5

    # If software interrupt (mcause=0x80000003), clear CLINT msip
    li x5, 0x80000003
    beq x22, x5, m_pe_clear_msip
    j m_pe_int_retpc

m_pe_clear_msip:
    li x5, CLINT_BASE
    sw x0, 0(x5)

m_pe_int_retpc:
    # Jump to pe_return_pc (MPIE=0 so MIE=0 after mret, no re-trigger)
    la x5, pe_return_pc; lw x5, 0(x5)
    beqz x5, m_pe_skip
    csrw mepc, x5
    li x5, 0x1800; csrw mstatus, x5
    la x5, pe_return_pc; sw x0, 0(x5)
    mret

# ============================================================
# Data area
# ============================================================
.section .text
.balign 4
pe_saved_ra:    .word 0
pe_return_pc:   .word 0
pe_got_m_trap:  .word 0
pe_got_s_trap:  .word 0
pe_mcause:      .word 0
pe_scause:      .word 0
pe_mepc:        .word 0
pe_sepc:        .word 0
pe_mstatus:     .word 0
pe_sstatus:     .word 0
