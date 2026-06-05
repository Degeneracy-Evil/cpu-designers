/*
 * UART test: output "Hi" once then halt, using uart.c driver.
 */
#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);
    uart_putc('H');
    uart_putc('i');
    while (1)
        __asm__ volatile("wfi");
    return 0;
}
