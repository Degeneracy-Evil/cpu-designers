.equ PTE_V, 0x001
.equ PTE_R, 0x002
.equ PTE_W, 0x004
.equ PTE_X, 0x008
.equ PTE_U, 0x010
.equ PTE_A, 0x040
.equ PTE_D, 0x080

.section .text
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10

    li x28, 0
    li x29, 0

    li x10, 0x00001888
    csrw mstatus, x10
    csrr x11, mstatus
    li x12, 0x00001888
    beq x11, x12, t1_ok
    j t1_end
t1_ok:
    addi x28, x28, 1
t1_end:
    addi x29, x29, 1

    li x10, 0x00000122
    csrw sstatus, x10
    csrr x11, sstatus
    li x12, 0x00000122
    beq x11, x12, t2_ok
    j t2_end
t2_ok:
    addi x28, x28, 1
t2_end:
    addi x29, x29, 1

    jal ra, setup_page_table
    fence.i

    li x10, 0xB104
    csrw medeleg, x10
    li x10, 0x0020
    csrw mideleg, x10

    la x10, s_trap_handler
    csrw stvec, x10

    la x10, s_mode_entry
    csrw mepc, x10
    li x10, 0x00000882
    csrw mstatus, x10
    mret

s_mode_entry:
    addi x28, x28, 1
    addi x29, x29, 1

    la x10, l1_page_table
    srli x10, x10, 12
    li x11, 0x80000000
    or x10, x10, x11
    csrw satp, x10
    sfence.vma

    csrr x10, sstatus
    li x11, 0x00040000
    or x10, x10, x11
    csrw sstatus, x10

    csrr x10, scause
    addi x28, x28, 1
    addi x29, x29, 1

    la x10, u_mode_entry
    csrw sepc, x10
    li x10, 0x00000022
    csrw sstatus, x10
    sret

s_trap_handler:
    csrr x24, scause
    csrr x25, sepc

    li x26, 8
    beq x24, x26, s_hdl_ecall_u

    li x26, 2
    beq x24, x26, s_hdl_illegal

    li x26, 13
    beq x24, x26, s_hdl_pf

    li x26, 15
    beq x24, x26, s_hdl_pf

    li x26, 12
    beq x24, x26, s_hdl_pf

    addi x25, x25, 4
    csrw sepc, x25
    sret

s_hdl_ecall_u:
    li x26, 0x42
    bne x10, x26, s_ecall_test6
    ecall
s_ecall_test6:
    addi x28, x28, 1
    addi x29, x29, 1
    addi x25, x25, 4
    csrw sepc, x25
    sret

s_hdl_illegal:
    addi x28, x28, 1
    addi x29, x29, 1
    addi x25, x25, 4
    csrw sepc, x25
    sret

s_hdl_pf:
    addi x25, x25, 4
    csrw sepc, x25
    sret

m_trap_handler:
    csrr x24, mcause
    csrr x25, mepc

    li x26, 9
    beq x24, x26, m_hdl_ecall_s

    addi x25, x25, 4
    csrw mepc, x25
    mret

m_hdl_ecall_s:
    addi x28, x28, 1
    addi x29, x29, 1
    j done

setup_page_table:
    la x15, l1_page_table
    li x16, 0x20001401
    li x17, 0x800
    add x17, x15, x17
    sw x16, 0(x17)

    la x15, l0_page_table
    li x16, 0x200000CF
    sw x16, 0(x15)
    li x16, 0x200004CF
    sw x16, 4(x15)
    li x16, 0x200008DF
    sw x16, 8(x15)
    li x16, 0x20000CDF
    sw x16, 12(x15)

    ret

done:
    bne x28, x29, done_fail
    li x20, 1
    j done_end
done_fail:
    li x20, 0
done_end:
    j done_end

.balign 8192
u_mode_entry:
    addi x28, x28, 1
    addi x29, x29, 1

    ecall

    csrr x10, sstatus

    .word 0x10200073

    la x10, u_test_data
    lw x11, 0(x10)
    li x12, 0xDEADBEEF
    beq x11, x12, t9_ok
    j t9_end
t9_ok:
    addi x28, x28, 1
t9_end:
    addi x29, x29, 1

    la x10, u_test_data
    li x11, 0xCAFEBABE
    sw x11, 0(x10)
    lw x12, 0(x10)
    beq x11, x12, t10_ok
    j t10_end
t10_ok:
    addi x28, x28, 1
t10_end:
    addi x29, x29, 1

    li x10, 0x42
    ecall

.balign 4096
u_test_data:
    .word 0xDEADBEEF

.balign 4096
l1_page_table:
    .fill 1024, 4, 0

.balign 4096
l0_page_table:
    .fill 1024, 4, 0
