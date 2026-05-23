.equ PAGE_SIZE, 4096
.equ PTE_V,     0x001
.equ PTE_R,     0x002
.equ PTE_W,     0x004
.equ PTE_X,     0x008
.equ PTE_U,     0x010
.equ PTE_G,     0x020
.equ PTE_A,     0x040
.equ PTE_D,     0x080

.section .text
.globl _start

_start:
    la x10, m_trap_handler
    csrw mtvec, x10
    li x10, 0x1888
    csrw mstatus, x10

    li x28, 0
    li x29, 0

    jal ra, setup_page_table

    li x10, 0x1888
    csrw mstatus, x10

    li x10, 0xB3FF
    csrw medeleg, x10
    li x10, 0x0AAA
    csrw mideleg, x10

    la x10, s_trap_handler
    csrw stvec, x10

    li x10, 0
    csrw sscratch, x10

    li x10, 0x00000A00
    csrw mstatus, x10

    csrr x10, mstatus
    li x11, 0x00000A00
    or x10, x10, x11
    csrw mstatus, x10

    li x5, 0x11111111
    li x6, 0x22222222
    li x7, 0x33333333

    csrw satp, x0

    la x10, test_data_area
    lw x11, 0(x10)
    addi x11, x11, 1
    sw x11, 0(x10)

    li x10, 0x80001
    csrw satp, x10

    la x10, test_data_area
    lw x11, 0(x10)

    addi x28, x28, 1

    li x10, 0
    csrw satp, x10

    li x10, 0x1888
    csrw mstatus, x10

    li x20, 0
    beq x28, x29, done
    li x20, 1

done:
    addi x20, x20, 0
    j done

setup_page_table:
    la x15, l1_page_table

    li x16, 0x80000
    srli x16, x16, 12

    li x17, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D
    slli x16, x16, 10
    or x16, x16, x17
    sw x16, 0(x15)

    la x15, l0_page_table

    li x16, 0x80000
    srli x16, x16, 12

    li x17, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D
    slli x16, x16, 10
    or x16, x16, x17
    sw x16, 0(x15)

    ret

m_trap_handler:
    csrr x24, mcause
    csrr x25, mepc
    addi x25, x25, 4
    csrw mepc, x25
    mret

s_trap_handler:
    csrr x24, scause
    csrr x25, sepc
    addi x25, x25, 4
    csrw sepc, x25
    sret

.balign 4096
l1_page_table:
    .fill 1024, 4, 0

.balign 4096
l0_page_table:
    .fill 1024, 4, 0

.balign 4096
test_data_area:
    .word 0xDEADBEEF
    .fill 1023, 4, 0
