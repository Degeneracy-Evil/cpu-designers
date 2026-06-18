/*
 * Diagnostic variant: original C uart_echo using uart.c library calls.
 * Kept separately from the stable assembly version for FPGA root-cause bisection.
 */

#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_230400);

    for (;;) {
        char c = uart_getc();
        uart_putc(c);
    }
}
