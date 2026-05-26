/*
 * UART echo program for SimpleCPU.
 *
 * Initialises UART at 115200 baud, then endlessly polls RX:
 *   - When a byte is available, read it and write it back (echo).
 */

#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);

    for (;;) {
        if (uart_rx_valid()) {
            char c = uart_getc();
            uart_putc(c);
        }
    }

    return 0;  /* unreachable */
}
