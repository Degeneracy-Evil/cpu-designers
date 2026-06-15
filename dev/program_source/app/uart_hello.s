# NS16550A UART Hello World
#
# Register map (APB4 word offsets from UART_BASE 0x10008000):
#   0x00  THR/RBR/DLL  (DLAB=0: TX write / RX read; DLAB=1: divisor low)
#   0x04  IER/DLM      (DLAB=0: IER; DLAB=1: divisor high)
#   0x08  IIR/FCR      (read: IIR; write: FCR)
#   0x0C  LCR          (line control: DLAB=bit7, WL=bits[1:0])
#   0x10  MCR          (modem control)
#   0x14  LSR          (line status: DR=bit0, THRE=bit5)
#   0x18  MSR
#   0x1C  SCR

.equ UART_BASE, 0x10008000
.equ UART_THR,   0x00
.equ UART_IER,   0x04
.equ UART_FCR,   0x08
.equ UART_LCR,   0x0C
.equ UART_MCR,   0x10
.equ UART_LSR,   0x14

.equ DLAB,       0x80      # Divisor Latch Access Bit
.equ WL8,        0x03      # 8-bit word length
.equ FCR_INIT,   0x07      # FIFO enable + reset RX + reset TX
.equ MCR_INIT,   0x03      # DTR + RTS
.equ LSR_THRE,   0x20      # TX Holding Register Empty
.equ DIV_115200, 54        # 100MHz / (16 * 115200) ≈ 54

.section .text
.globl _start

_start:
    lui  x10, 0x10008          # x10 = UART_BASE

    # ---- NS16550A init sequence ----
    # 1. Disable all interrupts
    sw   zero, UART_IER(x10)

    # 2. Set DLAB=1 to access divisor latch
    li   x11, DLAB
    sw   x11, UART_LCR(x10)

    # 3. Set baud divisor: DLL = 54, DLM = 0
    li   x11, DIV_115200
    sw   x11, UART_THR(x10)    # DLL (DLAB=1)
    sw   zero, UART_IER(x10)   # DLM (DLAB=1)

    # 4. 8N1, clear DLAB
    li   x11, WL8
    sw   x11, UART_LCR(x10)

    # 5. Enable FIFOs, reset both
    li   x11, FCR_INIT
    sw   x11, UART_FCR(x10)

    # 6. MCR: DTR + RTS
    li   x11, MCR_INIT
    sw   x11, UART_MCR(x10)

    # ---- Send "Hello World" in infinite loop ----
    la   x20, msg
    mv   x21, x20

send_loop:
    lb   x12, 0(x21)
    beq  x12, x0, done

wait_tx:
    lw   x13, UART_LSR(x10)
    andi x13, x13, LSR_THRE
    beqz x13, wait_tx

    sw   x12, UART_THR(x10)

    addi x21, x21, 1
    j    send_loop

done:
    mv   x21, x20
    j    send_loop

msg:
    .byte 'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd', 0
