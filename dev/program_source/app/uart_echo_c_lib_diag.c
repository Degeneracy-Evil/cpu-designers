/*
 * uart_echo_c_lib_diag.c — Self-diagnostic uart_echo using uart.c library.
 *
 * Purpose: Verify that BUG-96 instruction-memory corruption
 * (mepc=0x80000294, mtval=0x01010101) does not recur on the
 * latest bitstream (post BUG-91/BUG-97 + -Os).
 *
 * Strategy:
 *   1. Print "DIAG0" via direct MMIO (known-working path) before any
 *      uart.c call — proves CPU + UART MMIO are alive.
 *   2. Call uart_init(), print "DIAG1" — proves uart_init() doesn't crash.
 *   3. Call uart_getc()/uart_putc() in echo loop, print heartbeat
 *      every 64 iterations — proves long-running stability.
 *   4. If any crash occurs, start.S trap handler captures
 *      mcause/mepc/mtval and halts with WFI.
 *
 * Expected output (working):
 *   DIAG0
 *   DIAG1
 *   <echo characters>
 *   HB64
 *   <more echo>
 *   HB128
 *   ...
 *
 * Expected output (crash in uart_init):
 *   DIAG0
 *   <silence — trap handler halts>
 *
 * Expected output (crash in echo loop):
 *   DIAG0
 *   DIAG1
 *   <some echo then silence — trap handler halts>
 */

#include "sys.h"
#include "uart.h"

/* ---- Direct MMIO output (known-working, independent of uart.c) ---- */

#define UART_REG_CTRL     0x00U
#define UART_REG_STATUS   0x04U
#define UART_REG_TXDATA   0x08U
#define UART_REG_BAUD     0x10U
#define UART_STS_TX_BUSY  (1U << 0)

static inline volatile uint32_t *mmio_uart(uint32_t off)
{
    return (volatile uint32_t *)(UART_BASE + off);
}

static void diag_putc(char c)
{
    while (*mmio_uart(UART_REG_STATUS) & UART_STS_TX_BUSY)
        ;
    *mmio_uart(UART_REG_TXDATA) = (uint32_t)(uint8_t)c;
}

static void diag_puts(const char *s)
{
    while (*s)
        diag_putc(*s++);
}

int main(void)
{
    /* Phase 0: Prove CPU + UART MMIO are alive (before any uart.c call) */
    *mmio_uart(UART_REG_BAUD) = 0;
    *mmio_uart(UART_REG_CTRL) = 3;
    diag_puts("DIAG0\n");

    /* Phase 1: Call uart_init() via uart.c library */
    uart_init(UART_BAUD_115200);
    diag_puts("DIAG1\n");

    /* Phase 2: Echo loop using uart.c library, with heartbeat */
    uint32_t iter = 0;
    for (;;) {
        char c = uart_getc();
        uart_putc(c);

        iter++;
        if (iter % 64 == 0) {
            diag_puts("HB");
            /* Print iteration count in decimal (compact) */
            char buf[12];
            int len = 0;
            uint32_t n = iter;
            if (n == 0) {
                buf[len++] = '0';
            } else {
                while (n > 0) {
                    buf[len++] = '0' + (n % 10);
                    n /= 10;
                }
            }
            for (int i = len - 1; i >= 0; i--)
                diag_putc(buf[i]);
            diag_putc('\n');
        }
    }
}
