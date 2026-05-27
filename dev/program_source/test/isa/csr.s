# ============================================================
# isa/csr.s — CSR instruction tests
# 类别:   ISA
# 描述:   测试 CSR 指令 (CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI)
# 子测试: 18
# 依赖:   framework/test_framework.s, framework/trap_handlers.s
# ============================================================

.section .text.start
.globl _start

_start:
    # ── 全局 Setup ──
    la   x10, m_trap_simple
    csrw mtvec, x10
    li   x10, 0x88             # MSTATUS: MPP=M, MPIE=1, MIE=1
    csrw mstatus, x10

    # ── 框架初始化 ──
    jal  x1, test_init

    # ── 运行子测试 ──
    la   x11, test_01_csrrw_read_old
    jal  x1, test_run
    la   x11, test_02_csrrw_overwrite
    jal  x1, test_run
    la   x11, test_03_csrrs_set_bits
    jal  x1, test_run
    la   x11, test_04_csrrc_clear_bits
    jal  x1, test_run
    la   x11, test_05_csrrwi_imm
    jal  x1, test_run
    la   x11, test_06_csrrsi_imm
    jal  x1, test_run
    la   x11, test_07_csrrci_imm
    jal  x1, test_run
    la   x11, test_08_csrrw_x0_read
    jal  x1, test_run
    la   x11, test_09_csrrw_nonzero
    jal  x1, test_run
    la   x11, test_10_mstatus_wr
    jal  x1, test_run
    la   x11, test_11_mie_wr
    jal  x1, test_run
    la   x11, test_12_mtvec_wr
    jal  x1, test_run
    la   x11, test_13_roundtrip
    jal  x1, test_run
    la   x11, test_14_csrrs_x0_read
    jal  x1, test_run
    la   x11, test_15_csrrc_x0_read
    jal  x1, test_run
    la   x11, test_16_csrrwi_zero
    jal  x1, test_run
    la   x11, test_17_csrrsi_zero
    jal  x1, test_run
    la   x11, test_18_csrrci_zero
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试
# ============================================================

# Test 1: CSRRW — write mscratch, read old value
test_01_csrrw_read_old:
    li   x10, 0x1234
    csrw mscratch, x10         # mscratch = 0x1234
    li   x11, 0x5678
    csrrw x12, mscratch, x11   # x12 = old = 0x1234; mscratch = 0x5678
    li   x13, 0x1234
    li   x10, 1
    beq  x12, x13, _t01_end
    li   x10, 0
_t01_end:
    ret

# Test 2: CSRRW then CSRRW — verify overwrite
test_02_csrrw_overwrite:
    li   x10, 0xAAAA
    csrw mscratch, x10         # mscratch = 0xAAAA
    li   x10, 0xBBBB
    csrw mscratch, x10         # mscratch = 0xBBBB
    csrr x11, mscratch         # x11 = 0xBBBB
    li   x12, 0xBBBB
    li   x10, 1
    beq  x11, x12, _t02_end
    li   x10, 0
_t02_end:
    ret

# Test 3: CSRRS — set bits in mscratch
test_03_csrrs_set_bits:
    li   x10, 0x00FF
    csrw mscratch, x10         # mscratch = 0x00FF
    li   x11, 0xFF00
    csrrs x12, mscratch, x11   # x12 = 0x00FF; mscratch = 0x00FF | 0xFF00 = 0xFFFF
    csrr x13, mscratch         # x13 = 0xFFFF
    li   x14, 0xFFFF
    li   x10, 1
    beq  x13, x14, _t03_end
    li   x10, 0
_t03_end:
    ret

# Test 4: CSRRC — clear bits in mscratch
test_04_csrrc_clear_bits:
    li   x10, 0xFFFF
    csrw mscratch, x10         # mscratch = 0xFFFF
    li   x11, 0xFF00
    csrrc x12, mscratch, x11   # x12 = 0xFFFF; mscratch = 0xFFFF & ~0xFF00 = 0x00FF
    csrr x13, mscratch         # x13 = 0x00FF
    li   x14, 0x00FF
    li   x10, 1
    beq  x13, x14, _t04_end
    li   x10, 0
_t04_end:
    ret

# Test 5: CSRRWI — write immediate to mscratch
test_05_csrrwi_imm:
    csrrwi x11, mscratch, 15   # mscratch = 15; x11 = old value
    csrr  x12, mscratch        # x12 = 15
    li   x13, 15
    li   x10, 1
    beq  x12, x13, _t05_end
    li   x10, 0
_t05_end:
    ret

# Test 6: CSRRSI — set immediate bits
test_06_csrrsi_imm:
    li   x10, 0
    csrw mscratch, x10         # mscratch = 0
    csrrsi x11, mscratch, 3    # mscratch = 0 | 3 = 3; x11 = old = 0
    csrr  x12, mscratch        # x12 = 3
    li   x13, 3
    li   x10, 1
    beq  x12, x13, _t06_end
    li   x10, 0
_t06_end:
    ret

# Test 7: CSRRCI — clear immediate bits
test_07_csrrci_imm:
    li   x10, 0xFF
    csrw mscratch, x10         # mscratch = 0xFF
    csrrci x11, mscratch, 3    # mscratch = 0xFF & ~3 = 0xFC; x11 = old = 0xFF
    csrr  x12, mscratch        # x12 = 0xFC
    li   x13, 0xFC
    li   x10, 1
    beq  x12, x13, _t07_end
    li   x10, 0
_t07_end:
    ret

# Test 8: CSRRW x0 — read without write (pseudo CSRR via CSRRW)
test_08_csrrw_x0_read:
    li   x10, 0xDEAD
    csrw mscratch, x10         # mscratch = 0xDEAD
    li   x11, 0xBEEF
    csrrw x0, mscratch, x11    # rd=x0: old value discarded; mscratch = 0xBEEF
    csrr  x12, mscratch        # x12 = 0xBEEF
    li   x13, 0xBEEF
    li   x10, 1
    beq  x12, x13, _t08_end
    li   x10, 0
_t08_end:
    ret

# Test 9: CSRRW with non-zero — write and read old
test_09_csrrw_nonzero:
    li   x10, 0x1111
    csrw mscratch, x10         # mscratch = 0x1111
    li   x11, 0x2222
    csrrw x12, mscratch, x11   # x12 = 0x1111; mscratch = 0x2222
    li   x13, 0x1111
    li   x10, 1
    beq  x12, x13, _t09_end
    li   x10, 0
_t09_end:
    ret

# Test 10: MSTATUS write/read
test_10_mstatus_wr:
    # Save current mstatus, write test value, read back, restore
    csrr x15, mstatus          # save
    li   x10, 0x1888           # MPP=M, MPIE=1, MIE=1, SIE=1
    csrw mstatus, x10
    csrr x11, mstatus          # read back
    # Restore mstatus for trap safety
    csrw mstatus, x15
    # Verify: check that MPP bits [12:11] = 11 and MPIE bit 7 = 1
    li   x12, 0x1888
    li   x10, 1
    beq  x11, x12, _t10_end
    li   x10, 0
_t10_end:
    ret

# Test 11: MIE write/read
test_11_mie_wr:
    csrr x15, mie              # save
    li   x10, 0x888            # MEIE=1, MTIE=1, MSIE=1
    csrw mie, x10
    csrr x11, mie              # read back
    csrw mie, x15              # restore
    li   x12, 0x888
    li   x10, 1
    beq  x11, x12, _t11_end
    li   x10, 0
_t11_end:
    ret

# Test 12: MTVEC write/read
test_12_mtvec_wr:
    csrr x15, mtvec            # save old mtvec
    la   x10, m_trap_simple
    addi x10, x10, 0           # nop alignment — use same handler addr
    csrw mtvec, x10
    csrr x11, mtvec            # read back
    csrw mtvec, x15            # restore old mtvec
    la   x12, m_trap_simple
    li   x10, 1
    beq  x11, x12, _t12_end
    li   x10, 0
_t12_end:
    ret

# Test 13: Full roundtrip — write → read → verify for mscratch
test_13_roundtrip:
    li   x10, 0x5A5A
    csrw mscratch, x10
    csrr x11, mscratch
    li   x12, 0x5A5A
    li   x10, 1
    beq  x11, x12, _t13_mid
    li   x10, 0
    ret
_t13_mid:
    li   x10, 0xA5A5
    csrw mscratch, x10
    csrr x11, mscratch
    li   x12, 0xA5A5
    li   x10, 1
    beq  x11, x12, _t13_end
    li   x10, 0
_t13_end:
    ret

# Test 14: CSRRS x0 — read without side effects (pseudo CSRR via CSRRS)
test_14_csrrs_x0_read:
    li   x10, 0x3333
    csrw mscratch, x10         # mscratch = 0x3333
    csrrs x11, mscratch, x0    # rs1=x0: mscratch |= 0 (no change); x11 = 0x3333
    csrr  x12, mscratch        # x12 = 0x3333 (unchanged)
    li   x13, 0x3333
    li   x10, 1
    beq  x11, x13, _t14_end
    li   x10, 0
_t14_end:
    ret

# Test 15: CSRRC x0 — read without side effects (pseudo CSRR via CSRRC)
test_15_csrrc_x0_read:
    li   x10, 0x4444
    csrw mscratch, x10         # mscratch = 0x4444
    csrrc x11, mscratch, x0    # rs1=x0: mscratch &= ~0 (no change); x11 = 0x4444
    csrr  x12, mscratch        # x12 = 0x4444 (unchanged)
    li   x13, 0x4444
    li   x10, 1
    beq  x11, x13, _t15_end
    li   x10, 0
_t15_end:
    ret

# Test 16: CSRRWI zero — write 0 to mscratch (clear it)
test_16_csrrwi_zero:
    li   x10, 0xFFFF
    csrw mscratch, x10         # mscratch = 0xFFFF
    csrrwi x11, mscratch, 0    # mscratch = 0; x11 = 0xFFFF
    csrr  x12, mscratch        # x12 = 0
    li   x10, 1
    beq  x12, x0, _t16_end
    li   x10, 0
_t16_end:
    ret

# Test 17: CSRRSI zero — no change to CSR (set 0 bits)
test_17_csrrsi_zero:
    li   x10, 0x7777
    csrw mscratch, x10         # mscratch = 0x7777
    csrrsi x11, mscratch, 0    # mscratch |= 0 = 0x7777; x11 = 0x7777
    csrr  x12, mscratch        # x12 = 0x7777
    li   x13, 0x7777
    li   x10, 1
    beq  x12, x13, _t17_end
    li   x10, 0
_t17_end:
    ret

# Test 18: CSRRCI zero — no change to CSR (clear 0 bits)
test_18_csrrci_zero:
    li   x10, 0x8888
    csrw mscratch, x10         # mscratch = 0x8888
    csrrci x11, mscratch, 0    # mscratch &= ~0 = 0x8888; x11 = 0x8888
    csrr  x12, mscratch        # x12 = 0x8888
    li   x13, 0x8888
    li   x10, 1
    beq  x12, x13, _t18_end
    li   x10, 0
_t18_end:
    ret
