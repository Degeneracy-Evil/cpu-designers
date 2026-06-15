# NS16550A UART Echo
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
.equ LSR_DR,     0x01      # Data Ready
.equ LSR_THRE,   0x20      # TX Holding Register Empty
.equ DIV_115200, 54        # 100MHz / (16 * 115200) ≈ 54

.section .text
.globl _start

_start:
    lui  s0, 0x10008           # s0 = UART_BASE

    # ---- NS16550A init sequence ----
    # 1. Disable all interrupts
    sw   zero, UART_IER(s0)

    # 2. Set DLAB=1 to access divisor latch
    li   t0, DLAB
    sw   t0, UART_LCR(s0)

    # 3. Set baud divisor: DLL = 54, DLM = 0
    li   t0, DIV_115200
    sw   t0, UART_THR(s0)      # DLL (DLAB=1)
    sw   zero, UART_IER(s0)    # DLM (DLAB=1)

    # 4. 8N1, clear DLAB
    li   t0, WL8
    sw   t0, UART_LCR(s0)

    # 5. Enable FIFOs, reset both
    li   t0, FCR_INIT
    sw   t0, UART_FCR(s0)

    # 6. MCR: DTR + RTS
    li   t0, MCR_INIT
    sw   t0, UART_MCR(s0)

    # ---- Echo loop: recv byte, send byte ----
echo_loop:
    jal  ra, uart_recv_byte
    jal  ra, uart_send_byte
    j    echo_loop

# Blocking receive: wait until LSR.DR=1, then read RBR
uart_recv_byte:
1:
    lw   t0, UART_LSR(s0)
    andi t0, t0, LSR_DR
    beqz t0, 1b
    lw   a0, UART_THR(s0)      # RBR (DLAB=0)
    ret

# Blocking send: wait until LSR.THRE=1, then write THR
uart_send_byte:
1:
    lw   t0, UART_LSR(s0)
    andi t0, t0, LSR_THRE
    beqz t0, 1b
    sw   a0, UART_THR(s0)      # THR (DLAB=0)
    ret
