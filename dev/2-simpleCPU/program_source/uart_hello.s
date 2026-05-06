.equ UART_BASE, 0x80008000
.equ UART_CTRL,   0x00
.equ UART_STATUS, 0x04
.equ UART_TXDATA, 0x08

.section .text
.globl _start

_start:
    lui x10, 0x80008

    li x11, 0x01
    sw x11, UART_CTRL(x10)

    la x20, msg
    mv x21, x20

send_loop:
    lb x12, 0(x21)
    beq x12, x0, done

wait_tx:
    lw x13, UART_STATUS(x10)
    andi x13, x13, 1
    bne x13, x0, wait_tx

    sw x12, UART_TXDATA(x10)

    addi x21, x21, 1
    j send_loop

done:
    mv x21, x20
    j send_loop

msg:
    .byte 'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd', 0
