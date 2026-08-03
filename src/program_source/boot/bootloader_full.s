/**
 * bootloader.s — DDR3 Bootloader with self-test
 *
 * Runs from Boot ROM at 0xFC00_0000. Flow:
 *   1. Wait for MIG init_calib_complete (poll SYS_STATUS)
 *   2. DDR3 self-test: write → fence.i → read → compare → LED
 *   3. Init UART (NS16550A, 230400 baud)
 *   4. Receive header via UART: magic(4B) + length(4B) + load_addr(4B) + entry_addr(4B)
 *   5. Receive N bytes → write to DDR3 starting at load_addr
 *   6. Jump to entry address
 *
 * Address map:
 *   SYS_STATUS  = 0x0400_0000  [0]=init_calib_complete [1]=mmcm_locked [2]=clk_wiz_locked
 *   DDR3_BASE   = 0x8000_0000
 *   GPIO_CTRL   = 0x1000_0000  (direction: 1=output)
 *   GPIO_DATA   = 0x1000_0004  (data)
 *   UART_BASE   = 0x1000_8000  (NS16550A, word-aligned)
 *     THR/RBR/DLL(0x00), IER/DLM(0x04), IIR/FCR(0x08), LCR(0x0C),
 *     MCR(0x10), LSR(0x14), MSR(0x18), SCR(0x1C)
 */

# ── Address constants ──────────────────────────────────────────────

.equ SYS_STATUS_BASE,  0x04000000

.equ DDR3_BASE,        0x80000000
.equ DDR3_TEST_ADDR,   0x80000000      # First word of DDR3

.equ GPIO_BASE,        0x10000000
.equ GPIO_CTRL,        0x00
.equ GPIO_DATA,        0x04

# NS16550A register offsets (word-aligned: byte_offset × 4)
.equ UART_BASE,        0x10008000
.equ UART_THR,         0x00            # THR(write)/RBR(read)/DLL(DLAB=1)
.equ UART_IER,         0x04            # IER/DLM(DLAB=1)
.equ UART_FCR,         0x08            # FCR(write)/IIR(read)
.equ UART_LCR,         0x0C            # Line Control Register
.equ UART_MCR,         0x10            # Modem Control Register
.equ UART_LSR,         0x14            # Line Status Register

# LCR bits
.equ LCR_DLAB,         0x80            # Divisor Latch Access Bit
.equ LCR_8N1,          0x03            # 8 data bits, 1 stop bit, no parity

# LSR bits
.equ LSR_DR,           0x01            # Data Ready
.equ LSR_THRE,         0x20            # TX Holding Register Empty

# FCR bits
.equ FCR_INIT,         0xC7            # FIFO en + RX reset + TX reset + TL=14

# MCR bits
.equ MCR_INIT,         0x0B            # DTR + RTS + OUT2

# IER bits
.equ IER_RDA,          0x01            # Received Data Available interrupt

# Baud divisor: 100MHz / (16 × 230400) ≈ 27
.equ BAUD_DIV,         27

.equ MAGIC,            0x52495343      # "RISC" in little-endian

# ── Entry point ────────────────────────────────────────────────────

.section .text
.globl _start

_start:
    # ── Step 0: Init stack pointer ───────────────────────────────────
    lui  sp, 0x80008          # sp = 0x80008000 (top of 32KB SRAM, grows down)

    # ── Step 1: Init GPIO (all pins output) ───────────────────────
    lui  t0, 0x10000          # t0 = GPIO_BASE
    li   t1, 0xFFFF
    sw   t1, GPIO_CTRL(t0)    # All 16 pins as output

    # ── Step 2: Wait for MIG init_calib_complete ──────────────────
    lui  t0, 0x04000          # t0 = SYS_STATUS_BASE
1:
    lw   t1, 0(t0)            # Read STATUS register
    andi t1, t1, 0x01         # Bit 0 = init_calib_complete
    beqz t1, 1b               # Loop until DDR3 calibrated

    # ── Step 3: DDR3 self-test ────────────────────────────────────
    # Write known pattern to DDR3, fence.i, read back, compare
    lui  t0, 0x80000          # t0 = DDR3_TEST_ADDR
    li   t1, 0xDEADBEEF       # Test pattern
    sw   t1, 0(t0)             # Write to DDR3

    fence.i                    # Flush dcache write-back + icache invalidate
                               # Ensures subsequent lw reads from DDR3, not dcache

    lw   t2, 0(t0)             # Read back from DDR3
    bne  t1, t2, ddr_fail      # Compare

    # Also test a second word at offset +4
    li   t1, 0xCAFEBABE
    sw   t1, 4(t0)
    fence.i
    lw   t2, 4(t0)
    bne  t1, t2, ddr_fail

    # ── Self-test PASS: LED0 on (active-low: bit=0→LED on) ──────────
    lui  t0, 0x10000           # t0 = GPIO_BASE
    li   t1, 0xFFFE
    sw   t1, GPIO_DATA(t0)    # LED0 = on, others off (active-low)
    j    uart_init

ddr_fail:
    # ── Self-test FAIL: all LEDs on, then halt (active-low: all bits=0) ──
    lui  t0, 0x10000           # t0 = GPIO_BASE
    li   t1, 0x0000
    sw   t1, GPIO_DATA(t0)    # All LEDs = on (active-low)
    j    .                     # Dead loop — do not proceed to UART load

    # ── Step 4: Init NS16550A UART (115200 baud) ────────────────────
uart_init:
    lui  s10, 0x10008          # s10 = UART_BASE (callee-saved, persistent)

    # Disable all interrupts
    sw   zero, UART_IER(s10)

    # Set DLAB=1 to access divisor latch
    li   t0, LCR_DLAB
    sw   t0, UART_LCR(s10)

    # Set baud divisor: DLL = low byte, DLM = high byte
    li   t0, BAUD_DIV
    andi t1, t0, 0xFF          # DLL
    sw   t1, UART_THR(s10)     # THR/DLL at offset 0x00
    srli t1, t0, 8             # DLM
    sw   t1, UART_IER(s10)     # IER/DLM at offset 0x04

    # 8N1, clear DLAB
    li   t0, LCR_8N1
    sw   t0, UART_LCR(s10)

    # Enable FIFOs, trigger level 14, reset both FIFOs
    li   t0, FCR_INIT
    sw   t0, UART_FCR(s10)

    # MCR: DTR + RTS + OUT2
    li   t0, MCR_INIT
    sw   t0, UART_MCR(s10)

    # Enable RX data available interrupt
    li   t0, IER_RDA
    sw   t0, UART_IER(s10)

    # ── Step 5: Receive header via UART ───────────────────────────
    # Receive 4 bytes → word (little-endian)
    jal  ra, uart_recv_word    # magic
    li   t0, MAGIC
    bne  a0, t0, hdr_err       # Check magic

    jal  ra, uart_recv_word    # length
    mv   s1, a0                # s1 = program length (bytes)

    jal  ra, uart_recv_word    # load_addr
    mv   s2, a0                # s2 = load address

    jal  ra, uart_recv_word    # entry_addr
    mv   s3, a0                # s3 = entry address

    # ── Step 6: Receive program data → DDR3 ───────────────────────
    # s1 = remaining bytes, s2 = current write address
    srli s4, s1, 2             # s4 = number of words (length / 4)
    slli s1, s4, 2             # s1 = s4 * 4 (round down to word boundary)
1:
    beqz s4, load_done
    jal  ra, uart_recv_word    # a0 = received word
    sw   a0, 0(s2)             # Write to DDR3
    addi s2, s2, 4
    addi s4, s4, -1
    j    1b

load_done:
    # ── Step 7: Jump to entry address ─────────────────────────────
    fence.i                    # Flush dcache write-back + icache invalidate
                               # Ensures CPU fetches freshly-written program, not stale icache
    jr   s3                    # Jump to program entry in DDR3

hdr_err:
    # Header magic mismatch — alternating LED pattern (active-low inverted)
    lui  t0, 0x10000
    li   t1, 0x5555            # Alternating pattern (active-low: odd LEDs on)
    sw   t1, GPIO_DATA(t0)
    j    .                     # Halt

# ── UART helper: receive one byte (NS16550A) ────────────────────────
# Poll LSR.DR, then read RBR
# Returns: a0 = byte (zero-extended)
uart_recv_byte:
1:
    lw   t0, UART_LSR(s10)
    andi t0, t0, LSR_DR        # Data Ready bit
    beqz t0, 1b                # Wait until byte available
    lw   a0, UART_THR(s10)     # Read RBR (auto-pops from RX FIFO)
    ret

# ── UART helper: receive 4 bytes → word (little-endian) ──────────
# Returns: a0 = 32-bit word
# Uses sb+lw instead of slli/or to avoid CPU pipeline hazard
uart_recv_word:
    addi sp, sp, -8          # Save ra + word buffer on stack
    sw   ra, 0(sp)
    jal  ra, uart_recv_byte    # byte 0 (LSB)
    sb   a0, 4(sp)
    jal  ra, uart_recv_byte    # byte 1
    sb   a0, 5(sp)
    jal  ra, uart_recv_byte    # byte 2
    sb   a0, 6(sp)
    jal  ra, uart_recv_byte    # byte 3 (MSB)
    sb   a0, 7(sp)
    lw   a0, 4(sp)             # Load full 32-bit word (little-endian)
    lw   ra, 0(sp)            # Restore ra from stack
    addi sp, sp, 8
    ret
