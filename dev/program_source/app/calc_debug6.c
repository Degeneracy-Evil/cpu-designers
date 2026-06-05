/*
 * UART test: output "Hi" once via uart_puts then halt.
 */
#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);
    uart_puts("Hi");
    while (1)
        __asm__ volatile("wfi");
    return 0;
}
