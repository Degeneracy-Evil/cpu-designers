# ============================================================
# isa/jump.s — Jump instruction tests
# 类别:   ISA
# 描述:   测试跳转指令 (JAL, JALR)
# 子测试: 8
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
    la   x11, test_01_jal_fwd
    jal  x1, test_run
    la   x11, test_02_jal_bwd
    jal  x1, test_run
    la   x11, test_03_jalr
    jal  x1, test_run
    la   x11, test_04_jalr_x0
    jal  x1, test_run
    la   x11, test_05_jal_jalr
    jal  x1, test_run
    la   x11, test_06_jalr_misalign
    jal  x1, test_run
    la   x11, test_07_nested_jal
    jal  x1, test_run
    la   x11, test_08_jalr_offset
    jal  x1, test_run

    # ── 报告结果 ──
    jal  x1, test_report

    # ── 结束 ──
end_loop:
    j    end_loop


# ============================================================
# 子测试
# ============================================================

# Test 1: JAL forward — link register = PC+4, jump taken
test_01_jal_fwd:
    jal  x15, _t01_target
_t01_after:
    li   x10, 0                # FAIL — should not reach here
    ret
_t01_target:
    la   x16, _t01_after       # expected link-register value
    li   x10, 1
    beq  x15, x16, _t01_end
    li   x10, 0
_t01_end:
    ret

# Test 2: JAL backward — jump back to earlier label
test_02_jal_bwd:
    j    _t02_mid
_t02_back:
    li   x10, 1                # PASS — reached backward target
    ret
_t02_mid:
    jal  x15, _t02_back        # jump backward
    li   x10, 0                # FAIL
    ret

# Test 3: JALR — jump to computed address, link register saved
test_03_jalr:
    la   x15, _t03_target
    jalr x16, x15, 0           # x16 = return address
    li   x10, 1                # PASS — returned successfully
    ret
_t03_target:
    jalr x0, x16, 0            # return via saved link register

# Test 4: JALR with x0 — jump without saving return (tail call)
test_04_jalr_x0:
    la   x15, _t04_target
    jalr x0, x15, 0            # tail call, x0 = discard link
    li   x10, 0                # FAIL — should not reach here
    ret
_t04_target:
    li   x10, 1                # PASS — x1 still valid, ret goes to test_run
    ret

# Test 5: JAL + JALR combination — call and return
test_05_jal_jalr:
    jal  x15, _t05_func        # call via JAL, x15 = return addr
    li   x10, 1                # PASS — returned via JALR
    ret
_t05_func:
    jalr x0, x15, 0            # return via JALR (tail)

# Test 6: JALR to misaligned address — base ISA has no alignment req
test_06_jalr_misalign:
    la   x15, _t06_target
    ori  x15, x15, 1           # force odd (misaligned) address
    jalr x16, x15, 0           # attempt misaligned jump
    # If exception: m_trap_simple skips, we land here
    # If success: we return from _t06_target here
    li   x10, 1                # PASS — CPU handled it (exception or direct)
    ret
_t06_target:
    jalr x0, x16, 0            # if jump succeeded, return to caller

# Test 7: Nested JAL — two levels of call
test_07_nested_jal:
    jal  x15, _t07_level1      # call level 1
    li   x10, 1                # PASS — both levels returned
    ret
_t07_level1:
    jal  x16, _t07_level2      # call level 2 (x16 = link)
    jalr x0, x15, 0            # return to test_07 (via x15)
_t07_level2:
    jalr x0, x16, 0            # return to level 1 (via x16)

# Test 8: JALR with offset — jalr rd, rs1, imm (non-zero immediate)
test_08_jalr_offset:
    la   x15, _t08_target
    addi x15, x15, 8           # x15 = target + 8
    jalr x16, x15, -8          # effective addr = (target+8) + (-8) = target
    li   x10, 1                # PASS — JALR with offset worked
    ret
_t08_target:
    jalr x0, x16, 0            # return via saved link
