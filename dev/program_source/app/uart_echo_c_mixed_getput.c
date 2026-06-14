/*
 * Diagnostic variant: direct MMIO init, but RX/TX still use uart.c library
 * functions. This isolates uart_init() from uart_getc()/uart_putc().
 */

#include "sys.h"
#include "uart.h"

int main(void)
{
    *(volatile uint32_t *)(UART_BASE + 0x10U) = 0;
    *(volatile uint32_t *)(UART_BASE + 0x00U) = 3;

    for (;;)
        uart_putc(uart_getc());
}
