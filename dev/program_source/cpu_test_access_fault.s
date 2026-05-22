.section .text
.globl _start

_start:
    la   x10, trap_handler
    csrw mtvec, x10
    li   x10, 0x88
    csrw mstatus, x10

    csrw mscratch, x0

    lui  x10, 0x40000
    lw   x11, 0(x10)

    addi x1, x0, 1

    lui  x10, 0x40000
    sw   x0, 0(x10)

    addi x1, x1, 1

    la   x5, after_inst_fault
    lui  x6, 0x40000
    jalr x0, x6, 0
after_inst_fault:
    addi x1, x1, 1

    addi x2, x0, 42

end_loop:
    j    end_loop

trap_handler:
    csrrs x19, mcause, x0
    csrrs x20, mepc, x0
    csrrs x21, mtval, x0

    csrrs x22, mscratch, x0
    slli  x22, x22, 2
    addi  x23, x22, 72
    lui   x22, 0x80001
    add   x23, x23, x22
    sw    x19, 0(x23)

    csrrs x22, mscratch, x0
    addi  x22, x22, 1
    csrw  mscratch, x22

    li    x24, 1
    beq   x19, x24, inst_fault_return

    addi  x20, x20, 4
    csrw  mepc, x20
    mret

inst_fault_return:
    la    x20, after_inst_fault
    csrw  mepc, x20
    mret
