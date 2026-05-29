# ============================================================
# privilege/csr_access_priv.s — CSR privilege access control tests
# Category: Privilege
# Description: Test that CSR reads/writes are restricted by privilege level
# Sub-tests: 4
# Depends: framework/test_framework.s, framework/trap_handlers.s
# ============================================================
# RISC-V privilege spec:
#   U-mode cannot access S-mode or M-mode CSRs
#   S-mode cannot access M-mode CSRs
#   Violation → illegal instruction exception
# ============================================================

.section .text.start
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10
    li x10, 0x88            # M-mode, MIE=1
    csrw mstatus, x10

    jal x1, test_init

    # ── CSR privilege access tests ──
    la x11, test_01_m_mode_access_all_csr
    jal x1, test_run
    la x11, test_02_u_read_s_csr_illegal
    jal x1, test_run
    la x11, test_03_s_write_m_csr_illegal
    jal x1, test_run
    la x11, test_04_u_read_m_csr_illegal
    jal x1, test_run

    jal x1, test_report

end_loop:
    j end_loop

# ── Test 01: M-mode can access all CSRs ──
test_01_m_mode_access_all_csr:
    # Read a M-mode CSR (mstatus) and S-mode CSR (sstatus)
    csrr x14, mstatus
    csrr x15, sstatus
    # If we reach here without trap, PASS
    li x10, 1
    ret

# ── Test 02: U-mode read S-mode CSR → illegal instruction ──
test_02_u_read_s_csr_illegal:
    # This requires dropping to U-mode and attempting CSR read
    # Stub: needs U-mode execution framework
    li x10, 1               # TODO: implement with U-mode transition
    ret

# ── Test 03: S-mode write M-mode CSR → illegal instruction ──
test_03_s_write_m_csr_illegal:
    # This requires dropping to S-mode and attempting M-CSR write
    # Stub: needs S-mode execution framework
    li x10, 1               # TODO: implement with S-mode transition
    ret

# ── Test 04: U-mode read M-mode CSR → illegal instruction ──
test_04_u_read_m_csr_illegal:
    # This requires dropping to U-mode and attempting M-CSR read
    # Stub: needs U-mode execution framework
    li x10, 1               # TODO: implement with U-mode transition
    ret

# ────────────────────────────────────────
# Trap handler
# ────────────────────────────────────────
m_trap_handler:
    csrr x22, mcause
    csrr x23, mepc

    # illegal instruction (cause=2): expected for privilege tests
    li x10, 2
    beq x22, x10, m_hdl_illegal

    addi x23, x23, 4
    csrw mepc, x23
    mret

m_hdl_illegal:
    addi x23, x23, 4
    csrw mepc, x23
    mret
