/**
 * bootloader.s — DDR3 Bootloader with self-test
 *
 * Runs from Boot ROM at 0xFC00_0000. Flow:
 *   1. Wait for MIG init_calib_complete (poll SYS_STATUS)
 *   2. DDR3 self-test: write → fence.i → read → compare → LED
 *   3. Init UART (115200 baud)
 *   4. Receive header via UART: magic(4B) + length(4B) + load_addr(4B) + entry_addr(4B)
 *   5. Receive N bytes → write to DDR3 starting at load_addr
 *   6. Jump to entry address
 *
 * Address map:
 *   SYS_STATUS  = 0x0400_0000  [0]=init_calib_complete [1]=mmcm_locked [2]=clk_wiz_locked
 *   DDR3_BASE   = 0x8000_0000
 *   GPIO_CTRL   = 0x1000_0000  (direction: 1=output)
 *   GPIO_DATA   = 0x1000_0004  (data)
 *   UART_BASE   = 0x1000_8000
 *     CTRL(0x00): [0]=TX_EN [1]=RX_EN [2]=TX_IE [3]=RX_IE
 *     STATUS(0x04): [0]=TX_BUSY [1]=RX_VALID [2]=TX_FIFO_FULL
 *     TXDATA(0x08): write byte
 *     RXDATA(0x0C): read byte
 *     BAUD(0x10): divider (0=115200)
 */

# ── Address constants ──────────────────────────────────────────────

.equ SYS_STATUS_BASE,  0x04000000

.equ DDR3_BASE,        0x80000000
.equ DDR3_TEST_ADDR,   0x80000000      # First word of DDR3

.equ GPIO_BASE,        0x10000000
.equ GPIO_CTRL,        0x00
.equ GPIO_DATA,        0x04

.equ UART_BASE,        0x10008000
.equ UART_CTRL,        0x00
.equ UART_STATUS,      0x04
.equ UART_TXDATA,      0x08
.equ UART_RXDATA,      0x0C
.equ UART_BAUD,        0x10
.equ UART_RXPOP,       0x18

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

    # ── Step 4: Init UART (115200 baud) ───────────────────────────
uart_init:
    lui  s10, 0x10008          # s10 = UART_BASE (callee-saved, persistent)
    li   t1, 0x03              # TX_EN=1, RX_EN=1
    sw   t1, UART_CTRL(s10)
    sw   zero, UART_BAUD(s10)  # Divider=0 → 115200 baud

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

# ── UART helper: receive one byte ─────────────────────────────────
# Returns: a0 = byte (zero-extended)
# STATUS read auto-arms RXDATA pop; duplicate bus transactions harmless:
#   lw STATUS (arm), lw STATUS (dup=no-op), lw RXDATA (pop), lw RXDATA (dup=peek)
uart_recv_byte:
1:
    lw   t0, UART_STATUS(s10)
    andi t0, t0, 0x02          # Bit 1 = RX_VALID
    beqz t0, 1b                # Wait until byte available
    lw   a0, UART_RXDATA(s10)  # Read byte + pop (STATUS read armed the pop)
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
