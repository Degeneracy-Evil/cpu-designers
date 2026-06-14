/*
 * uart_echo_c_lib_preinit.c — Minimal control experiment for BUG-96.
 *
 * Identical to uart_echo_c_lib.c except:
 *   - Direct MMIO UART init BEFORE calling uart_init()
 *
 * If this works but uart_echo_c_lib fails, the residual RTL bug
 * is triggered by "first MMIO access goes through uart_init()
 * with sh/lhu stack spill creating dcache dirty line before MMIO".
 *
 * If this also fails, the bug is elsewhere.
 */

#include "sys.h"
#include "uart.h"

int main(void)
{
    /* Pre-init UART via direct MMIO (same as uart_echo_c_lib_diag phase 0) */
    *(volatile uint32_t *)(UART_BASE + 0x10U) = 0;  /* baud = 0 */
    *(volatile uint32_t *)(UART_BASE + 0x00U) = 3;  /* ctrl = TX_EN|RX_EN */

    /* Now call uart_init() — this will re-write the same registers,
     * but UART is already active. The key difference from uart_echo_c_lib
     * is that the FIRST MMIO access was a direct sw, not sh->lhu->sw. */
    uart_init(UART_BAUD_115200);

    for (;;) {
        char c = uart_getc();
        uart_putc(c);
    }
}
