/*
 * Diagnostic variant: keep uart.c library calls, but remove the local
 * stack-stored char in main().
 */

#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);

    for (;;)
        uart_putc(uart_getc());
}
