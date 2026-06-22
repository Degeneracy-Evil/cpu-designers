# ============================================================
# audit/plic_seip.s — PLIC SEIP end-to-end verification
# Category: Audit | Sub-tests: 3
# ============================================================
# Tests:
#   1. PLIC pending → mip.SEIP (M-mode view)
#   2. PLIC pending → sip.SEIP (S-mode view, BUG-CSR-3)
#   3. PLIC claim returns correct source ID
#
# Testbench: tb_audit_plic_seip.sv forces plic_src_irq[4]=1
# ============================================================

.equ PLIC_BASE,    0x0C000000
.equ PLIC_PRIO4,   0x0C000010   # Priority[4] (gpio)
.equ PLIC_PENDING, 0x0C001000
.equ PLIC_ENABLE1, 0x0C002080   # Enable context 1 (S-mode)
.equ PLIC_THRESH1, 0x0C201000   # Threshold context 1
.equ PLIC_CLAIM1,  0x0C201004   # Claim context 1

.section .text.start
.globl _start

_start:
    la   x10, plic_seip_trap_handler
    csrw mtvec, x10
    li   x10, 0x1888
    csrw mstatus, x10

    jal  x1, test_init

    la   x11, test_01_mip_seip
    jal  x1, test_run
    la   x11, test_02_sip_seip
    jal  x1, test_run
    la   x11, test_03_claim_source
    jal  x1, test_run

    jal  x1, test_report

end_loop:
    j    end_loop

# ── Sub-test 1: mip.SEIP set when PLIC pending for ctx1 ──
# Configure PLIC context 1, then read mip bit 9
test_01_mip_seip:
    # Setup PLIC context 1: enable source 4, priority=2, threshold=0
    li   x10, PLIC_PRIO4
    li   x11, 2
    sw   x11, 0(x10)             # priority[4] = 2
    li   x10, PLIC_ENABLE1
    li   x11, 0x10               # bit 4 = source 4
    sw   x11, 0(x10)             # enable[ctx1][4] = 1
    li   x10, PLIC_THRESH1
    sw   x0, 0(x10)              # threshold[ctx1] = 0
    # Wait for PLIC to process (src_irq forced by testbench)
    nop; nop; nop; nop
    # Read mip and check SEIP (bit 9)
    csrr x12, mip
    li   x13, 0x200              # bit 9
    and  x13, x12, x13
    beqz x13, _mip_seip_fail     # SEIP not set → FAIL
    li   x10, 1; ret             # PASS: mip.SEIP = 1
_mip_seip_fail:
    li   x10, 0; ret             # FAIL: mip.SEIP = 0

# ── Sub-test 2: sip.SEIP set when PLIC pending for ctx1 (BUG-CSR-3) ──
# Read sip bit 9 — before fix this returned only r_sip[9] (software),
# missing ext_seip from PLIC. After fix it returns ext_seip | r_sip[9].
test_02_sip_seip:
    # PLIC already configured by test_01
    # Read sip and check SEIP (bit 9)
    csrr x12, sip
    li   x13, 0x200              # bit 9
    and  x13, x12, x13
    beqz x13, _sip_seip_fail     # SEIP not set → FAIL
    li   x10, 1; ret             # PASS: sip.SEIP = 1
_sip_seip_fail:
    li   x10, 0; ret             # FAIL: sip.SEIP = 0

# ── Sub-test 3: PLIC claim returns source 4 ──
# Read claim register for context 1, should return 4 (GPIO source)
test_03_claim_source:
    li   x10, PLIC_CLAIM1
    lw   x11, 0(x10)             # claim → returns source ID
    li   x12, 4
    beq  x11, x12, _claim_ok     # source 4 → PASS
    li   x10, 0; ret             # FAIL: wrong source or 0
_claim_ok:
    # Complete the claim (write back source ID)
    sw   x11, 0(x10)
    li   x10, 1; ret             # PASS: claim returned 4

# ============================================================
# Trap Handler
# ============================================================
plic_seip_trap_handler:
    csrr x22, mcause
    csrr x23, mepc
    addi x23, x23, 4
    csrw mepc, x23
    mret
