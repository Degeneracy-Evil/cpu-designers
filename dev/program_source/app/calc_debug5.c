/*
 * UART test: output "Hi" in a loop using uart.c driver.
 */
#include "uart.h"

int main(void)
{
    uart_init(UART_BAUD_115200);
    for (;;)
    {
        uart_putc('H');
        uart_putc('i');
    }
    return 0;
}
