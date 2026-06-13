.equ UART_BASE,   0x10008000
.equ UART_CTRL,   0x00
.equ UART_STATUS, 0x04
.equ UART_TXDATA, 0x08
.equ UART_RXDATA, 0x0C
.equ UART_BAUD,   0x10

.section .text
.globl _start

_start:
    lui  s0, 0x10008

    li   t0, 0x03
    sw   t0, UART_CTRL(s0)
    sw   zero, UART_BAUD(s0)

echo_loop:
    jal  ra, uart_recv_byte
    jal  ra, uart_send_byte
    j    echo_loop

uart_recv_byte:
1:
    lw   t0, UART_STATUS(s0)
    andi t0, t0, 0x02
    beqz t0, 1b
    lw   a0, UART_RXDATA(s0)
    ret

uart_send_byte:
1:
    lw   t0, UART_STATUS(s0)
    andi t0, t0, 0x01
    bnez t0, 1b
    sw   a0, UART_TXDATA(s0)
    ret
