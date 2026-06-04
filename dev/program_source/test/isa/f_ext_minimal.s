.section .text.start
.globl _start

_start:
    la   x10, m_trap_simple
    csrw mtvec, x10
    li   x10, 0x88
    csrw mstatus, x10
    jal  x1, test_init

    # Test: FCVT.S.W int 1 -> float 1.0
    li   x14, 1
    fcvt.s.w f10, x14, rne
    fmv.x.w x12, f10
    lui  x13, 0x3F800         # 1.0 = 0x3F800000
    li   x10, 1
    beq  x12, x13, _pass
    li   x10, 0
_pass:
    # Store result: x10=1 pass, x10=0 fail; x12=actual, x13=expected
    lui  x14, 0x80006
    sw   x10, 0(x14)           # pass/fail at 0x80006000
    sw   x12, 4(x14)           # actual at 0x80006004
    sw   x13, 8(x14)           # expected at 0x80006008

_end:
    j    _end
